class_name CombatRoster
extends RefCounted

## Holds both sides of a combat encounter.
##
## Builds Combatant wrappers for party members and monster instances.
## Tracks casualty counts for morale trigger detection.

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## All combatants in the encounter.
var _combatants: Dictionary = {}  # combatant_id -> Combatant

## Counts at combat start for morale trigger thresholds.
var enemy_count_at_start: int = 0

## Morale trigger tracking (per monster_group_id).
var _first_casualty_round: Dictionary = {}   # group_id -> round number
var _casualties_by_group: Dictionary = {}    # group_id -> count


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

## Build a roster from party data and an encounter.
## [param encounter_data] keys: monster_group (String), number (int).
## [param monster_registry] provides monster catalog lookups.
## [param dice_system] used to roll monster HP. Pass null for tests that
## pre-build combatants manually.
static func build_from_encounter(
		party_data: PartyData,
		encounter_data: Dictionary,
		monster_registry: MonsterRegistry,
		dice_system = null) -> CombatRoster:
	var roster := CombatRoster.new()

	# --- Add party members ---
	for cd: CharacterData in party_data.character_data:
		if cd.is_dead or not cd.is_active:
			continue
		var combatant := Combatant.from_character(cd)
		roster.add_combatant(combatant)

	# --- Add monsters ---
	var monster_id: String = encounter_data.get("monster_group", "")
	var count: int = int(encounter_data.get("number", 1))
	if monster_id.is_empty() or not monster_registry.has_monster(monster_id):
		push_error("CombatRoster: Unknown monster '%s'" % monster_id)
		return roster

	var monster_data: Dictionary = monster_registry.get_monster(monster_id)
	var hd_info: Dictionary = monster_data.get("hit_dice", {})
	var hd_base: int = int(hd_info.get("base", 1))
	var hd_modifier: int = int(hd_info.get("modifier", 0))
	var group_id := monster_id

	for i in range(count):
		# Roll HP: base * d8 + modifier (minimum 1 HP)
		var rolled_hp: int
		if dice_system != null:
			var die_count := maxi(1, hd_base)
			var result: RollResult = dice_system.roll_digital(8, die_count, hd_modifier, "starting_hp")
			rolled_hp = maxi(1, result.modified_total)
		else:
			# Fallback for tests: deterministic average HP
			rolled_hp = maxi(1, hd_base * 4 + hd_modifier)

		var combatant_id := "%s_%d" % [monster_id, i]
		var combatant := Combatant.from_monster(
			monster_data, rolled_hp, combatant_id, group_id)
		roster.add_combatant(combatant)

	roster.enemy_count_at_start = count
	roster._casualties_by_group[group_id] = 0
	return roster


## Add trained creatures from party data to the roster as PARTY combatants.
## Only creatures with combat roles (WM, G, H) and alive are added.
func add_party_creatures(party_data: PartyData, monster_registry: MonsterRegistry) -> void:
	for creature: TrainedCreatureData in party_data.creature_data:
		if not creature.is_alive or not creature.has_combat_role():
			continue
		if creature.monster_data.is_empty():
			creature.monster_data = monster_registry.get_monster(creature.species_id)
		var combatant := Combatant.from_trained_creature(
			creature, "creature_" + creature.id)
		add_combatant(combatant)


# ---------------------------------------------------------------------------
# Combatant management
# ---------------------------------------------------------------------------

func add_combatant(combatant: Combatant) -> bool:
	## Adds [param combatant] to the roster. Returns true on success, false if
	## the id was already registered (defensive guard for mid-combat re-summon
	## of the same caster's elemental, etc.). Existing callers ignore the
	## return; the SpawnRosterIntegrator (P3) consumes it.
	if combatant == null or combatant.id.is_empty():
		return false
	if _combatants.has(combatant.id):
		return false
	_combatants[combatant.id] = combatant
	return true


func get_by_id(combatant_id: String) -> Combatant:
	return _combatants.get(combatant_id, null)


func get_all() -> Array[Combatant]:
	var result: Array[Combatant] = []
	for c: Combatant in _combatants.values():
		result.append(c)
	return result


func get_alive() -> Array[Combatant]:
	var result: Array[Combatant] = []
	for c: Combatant in _combatants.values():
		if c.is_alive():
			result.append(c)
	return result


func get_alive_on_side(target_side: int) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for c: Combatant in _combatants.values():
		if c.is_alive() and c.side == target_side:
			result.append(c)
	return result


## Reassigns the combatant identified by [param combatant_id] to
## [param new_side] (Combatant.Side.PARTY or Combatant.Side.ENEMY). Used by
## P8 to flip an elemental's allegiance after concentration loss
## (`elemental_uncontrolled`) and by the Invisible Stalker reliability path
## when the stalker turns on its caster. No-op when the id is missing or the
## side already matches. Returns true on a successful flip.
func move_to_side(combatant_id: String, new_side: int) -> bool:
	var c: Combatant = _combatants.get(combatant_id, null)
	if c == null:
		return false
	if c.side == new_side:
		return false
	c.side = new_side
	return true


# ---------------------------------------------------------------------------
# Charm defection (gdd-npc-dialogue.md §5.6, §12.1) — the ONE combat-system
# capability Dialogue Phase 3 needs. A charmed PC "acts to protect its friend"
# (RAW acore_spell_catalog_a-i_summary.xml:191): it enters combat on the
# charmer's side, and reverts when the charm ends (repeat save / dispel /
# session end). This reuses the mutable `side` field (like move_to_side) but
# RECORDS the original side on the combatant so the flip is reversible, and
# tags the combatant with the charmer id so callers can distinguish a charm
# defection from an elemental/stalker flip. Additive + guarded + restore-on-end.
# ---------------------------------------------------------------------------

## Move the charmed PC identified by [param combatant_id] to the charmer's side
## (RAW :191). [param charmer_side] is the side the charmer fights on
## (Combatant.Side.*); [param charmer_id] is recorded for restore + audit.
## Idempotent: re-applying to an already-defected-to-this-charmer combatant is a
## no-op that returns true. No-op false when the id is missing. Restore via
## end_charm_defection. Returns true when the combatant is (now) defected.
func apply_charm_defection(combatant_id: String, charmer_side: int,
		charmer_id: String) -> bool:
	var c: Combatant = _combatants.get(combatant_id, null)
	if c == null:
		return false
	if not c.charmed_by_id.is_empty() and c.charmed_by_id == charmer_id \
			and c.side == charmer_side:
		return true   # already defected to this charmer
	# Record the ORIGINAL side only the first time we flip (so a second
	# apply — e.g. re-charm before end — never overwrites the true origin).
	if c.pre_charm_side < 0:
		c.pre_charm_side = c.side
	c.charmed_by_id = charmer_id
	c.side = charmer_side
	return true


## Restore a charm-defected combatant to its pre-charm side (charm ended). No-op
## false when the id is missing or the combatant is not charm-defected. Returns
## true on a successful restore.
func end_charm_defection(combatant_id: String) -> bool:
	var c: Combatant = _combatants.get(combatant_id, null)
	if c == null or c.charmed_by_id.is_empty():
		return false
	if c.pre_charm_side >= 0:
		c.side = c.pre_charm_side
	c.pre_charm_side = -1
	c.charmed_by_id = ""
	return true


## True when the combatant identified by [param combatant_id] is currently
## charm-defected (on someone else's side by charm).
func is_charm_defected(combatant_id: String) -> bool:
	var c: Combatant = _combatants.get(combatant_id, null)
	return c != null and not c.charmed_by_id.is_empty()


## All currently charm-defected combatants (for UI / audit).
func charm_defectors() -> Array[Combatant]:
	var result: Array[Combatant] = []
	for c: Combatant in _combatants.values():
		if not c.charmed_by_id.is_empty():
			result.append(c)
	return result


func get_party_combatants() -> Array[Combatant]:
	return get_alive_on_side(Combatant.Side.PARTY)


func get_enemy_combatants() -> Array[Combatant]:
	return get_alive_on_side(Combatant.Side.ENEMY)


func get_combatants_in_group(group_id: String) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for c: Combatant in _combatants.values():
		if c.monster_group_id == group_id:
			result.append(c)
	return result


# ---------------------------------------------------------------------------
# Casualty tracking
# ---------------------------------------------------------------------------

func record_casualty(combatant: Combatant, round_number: int) -> void:
	## Call when a combatant is downed. Updates morale trigger counters.
	var group_id := combatant.monster_group_id
	if group_id.is_empty():
		return
	if not _casualties_by_group.has(group_id):
		_casualties_by_group[group_id] = 0
	_casualties_by_group[group_id] += 1
	if not _first_casualty_round.has(group_id):
		_first_casualty_round[group_id] = round_number


func is_first_casualty(group_id: String) -> bool:
	return _casualties_by_group.get(group_id, 0) == 1


func is_half_casualties(group_id: String) -> bool:
	var casualties: int = _casualties_by_group.get(group_id, 0)
	# Use Banker's rounding for the threshold
	var threshold := enemy_count_at_start / 2
	if enemy_count_at_start % 2 == 1:
		# Odd count: e.g., 5 monsters -> half = 2 (round down = fail at 3)
		threshold = (enemy_count_at_start + 1) / 2
	return casualties >= threshold


func get_casualties_in_group(group_id: String) -> int:
	return _casualties_by_group.get(group_id, 0)


# ---------------------------------------------------------------------------
# Combat end detection
# ---------------------------------------------------------------------------

func is_party_eliminated() -> bool:
	return get_alive_on_side(Combatant.Side.PARTY).is_empty()


func is_enemies_eliminated() -> bool:
	## Returns true if all enemies are dead or fleeing.
	for c: Combatant in _combatants.values():
		if c.is_enemy_side() and c.is_alive() and not c.is_fleeing:
			return false
	return true


func all_enemies_fled() -> bool:
	## Returns true if all surviving enemies are fleeing.
	for c: Combatant in _combatants.values():
		if c.is_enemy_side() and c.is_alive() and not c.is_fleeing:
			return false
	# At least one must be alive and fleeing
	for c: Combatant in _combatants.values():
		if c.is_enemy_side() and c.is_alive() and c.is_fleeing:
			return true
	return false


func get_downed_pcs() -> Array:
	## Returns all party combatants backed by CharacterData that are currently downed (HP <= 0).
	## Used by MortalWoundsResolver to process post-combat casualties.
	var result: Array = []
	for c: Combatant in _combatants.values():
		if c.is_pc_side() and c.is_character and not c.is_alive():
			result.append(c)
	return result
