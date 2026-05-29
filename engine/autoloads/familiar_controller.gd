extends Node

## FamiliarController — Stage 2 runtime mechanics for the Familiar proficiency.
##
## Owns the three runtime concerns documented in generation/gdd-familiars.md:
##
##   1. **Proximity bonus** — when a master's living familiar is within 30 ft
##      (6 voxel cells, Chebyshev distance), the master gets +1 to all five
##      saving throws. Implemented by setting the `familiar_within_30ft` flag
##      on master.flags AND pushing five `add: -1` modifiers (one per save key)
##      into master.modifiers, all sourced under the `familiar:proximity:`
##      prefix so they can be cleared atomically. Saves in ACKS are roll-high
##      target numbers — lower target = easier — so a +1 *bonus* on the
##      saving throw is a -1 modifier on the target.
##
##   2. **Death-link** — when the familiar dies, the master must save vs Death
##      (`save_poison_death`) or take damage equal to the familiar's max HP at
##      the time of death.
##
##   3. **Level-up cache refresh** — when the master gains a level, the
##      familiar's cached HD progression / HP / INT / proficiency budget all
##      need to refresh from the new master state. Stage 3's level-up UI
##      surfaces an additional-picks step when the proficiency budget grows.
##
## No `class_name` — autoload scripts must not declare class_name (causes
## "hides an autoload singleton" error in Godot 4). Reference as
## `FamiliarController.evaluate_proximity(...)` etc.
##
## Autoload registration: project.godot [autoload] section.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## 30 ft / 5 ft per voxel cell = 6 cells (inclusive). Distance uses Chebyshev
## metric so diagonals count the same as orthogonals.
const PROXIMITY_RANGE_CELLS := 6

## The five save-throw stat keys; saves in ACKS are roll-high target numbers.
const SAVE_KEYS := [
	"save_petrification",
	"save_poison_death",
	"save_blast_breath",
	"save_staffs_wands",
	"save_spells",
]

## ACKS rule: +1 saving throws → -1 to the target number on each of the five.
const SAVE_TARGET_DELTA := -1

## Source-id prefix for proximity-driven flags + modifiers. Single prefix lets
## us clear all five save modifiers atomically with `remove_all_with_source_prefix`.
const SOURCE_PREFIX := "familiar:proximity"

## EntityFlags key the proficiency catalog references (see
## data/proficiencies/proficiency_catalog.json:1393 — the conditional save
## modifiers reference this key). For Stage 2 the flag is informational
## (used by save-throw inspectors / debug UI / future LLM narration); the
## actual save bonus is delivered by the modifiers.
const PROXIMITY_FLAG := "familiar_within_30ft"


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## master_character_id → bool (true means flag+modifiers are currently active)
var _proximity_state: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	EventBus.character_leveled_up.connect(_on_character_leveled_up)
	EventBus.familiar_died.connect(_on_familiar_died)


# ---------------------------------------------------------------------------
# Proximity
# ---------------------------------------------------------------------------

## Computes Chebyshev cell distance between [param master_pos] and
## [param familiar_pos] and updates the proximity state for [param master_id].
## Caller supplies positions explicitly so this works in any context (combat,
## dungeon exploration, tests). Returns the resolved in-range bool.
##
## Pre-condition: [param master] is a live CharacterData reference belonging to
## the master with id == master_id. The flag/modifiers are mutated on its
## EntityFlags + ModifierContainer.
func evaluate_proximity(
		master: CharacterData,
		master_pos: Vector3i,
		familiar_pos: Vector3i) -> bool:
	var d: int = max(
		abs(master_pos.x - familiar_pos.x),
		max(abs(master_pos.y - familiar_pos.y), abs(master_pos.z - familiar_pos.z)))
	var in_range: bool = d <= PROXIMITY_RANGE_CELLS
	set_proximity_state(master, in_range)
	return in_range


## Force the proximity state for [param master] to [param in_range].
## Idempotent — calling repeatedly with the same value has no extra effect.
## Used directly by callers that already know the answer (e.g. familiar
## auto-co-located with master), and by tests.
func set_proximity_state(master: CharacterData, in_range: bool) -> void:
	if master == null:
		return
	var prev: bool = _proximity_state.get(master.id, false)
	if prev == in_range:
		return
	_proximity_state[master.id] = in_range
	if in_range:
		_apply_proximity_bonus(master)
	else:
		_clear_proximity_bonus(master)


## Returns whether the master currently has the proximity bonus active.
## Reads the in-memory state map; intended for tests and debug UI.
func is_in_proximity(master_id: String) -> bool:
	return _proximity_state.get(master_id, false)


## Stage 2.x — caller-driven proximity refresh on a live CharacterData.
##
## Looks up the master's living familiar in the DB and applies the proximity
## bonus to [param master] when found, or clears it when not. Idempotent.
##
## Call sites (caller-driven so this stays decoupled from session/cache state):
##   1. SessionRunner.load_session() — after `_party_data.character_data` is
##      populated, iterate party members and call this for each. Restores
##      proximity bonuses across save/load round-trips.
##   2. CharacterCreationScreen._persist_familiar_if_bonded() — after the new
##      familiar row is written, default the master to in-range (familiars
##      follow their masters).
##   3. CSTabAdvancement._on_confirm_level_up() — after
##      LevelUpEngine.finalize_interactive_level_up returns, refresh on the
##      master's live CharacterData so a Stage 3d Case A replacement bonding
##      activates the bonus immediately.
##
## Combat separation (familiar deliberately moves >30 ft from master) is still
## handled via explicit `evaluate_proximity` / `set_proximity_state` calls
## from combat code; this helper is for the "default to in-range when alive,
## clear when dead" lifecycle baseline.
func apply_proximity_for_master(master: CharacterData) -> void:
	if master == null or master.id.is_empty():
		return
	var fam: Dictionary = CampaignRepository.get_living_familiar_for_master(master.id)
	set_proximity_state(master, not fam.is_empty())


## Clear all proximity state for a master — used when their familiar dies or
## is replaced. Safe to call when nothing is set.
func clear_proximity_for_master(master: CharacterData) -> void:
	if master == null:
		return
	_proximity_state.erase(master.id)
	_clear_proximity_bonus(master)


func _apply_proximity_bonus(master: CharacterData) -> void:
	master.flags.set_flag(PROXIMITY_FLAG, SOURCE_PREFIX)
	for save_key in SAVE_KEYS:
		master.modifiers.add_modifier(save_key, {
			"source_id": "%s:%s" % [SOURCE_PREFIX, save_key],
			"stat": save_key,
			"operation": "add",
			"value": SAVE_TARGET_DELTA,
			"stacking_group": "familiar_proximity",
		})


func _clear_proximity_bonus(master: CharacterData) -> void:
	master.flags.clear_flag(PROXIMITY_FLAG, SOURCE_PREFIX)
	master.modifiers.remove_all_with_source_prefix(SOURCE_PREFIX)


# ---------------------------------------------------------------------------
# Damage routing + death-link
# ---------------------------------------------------------------------------

## Reduce a familiar's HP by [param amount] (clamped to ≥ 0). If HP reaches 0,
## the familiar dies and `EventBus.familiar_died` is emitted, triggering the
## master's save-vs-Death routine.
func apply_familiar_damage(familiar_id: String, amount: int) -> void:
	if amount <= 0:
		return
	var row: Dictionary = CampaignRepository.get_familiar(familiar_id)
	if row.is_empty() or int(row.get("is_alive", 0)) == 0:
		return
	var new_hp: int = max(0, int(row.get("hp_current", 0)) - amount)
	if new_hp == 0:
		kill_familiar_now(familiar_id)
	else:
		CampaignRepository.update_familiar(familiar_id, {"hp_current": new_hp})


## Kills a familiar now (HP → 0, is_alive → false, death_save_pending → 1).
## Emits `EventBus.familiar_died` which `_on_familiar_died` consumes to roll
## the master's save-vs-Death.
func kill_familiar_now(familiar_id: String) -> void:
	var row: Dictionary = CampaignRepository.get_familiar(familiar_id)
	if row.is_empty() or int(row.get("is_alive", 0)) == 0:
		return
	var master_id: String = str(row.get("master_character_id", ""))
	var max_hp: int = int(row.get("hp_max_cached", 0))
	if not CampaignRepository.kill_familiar(familiar_id):
		return
	EventBus.familiar_died.emit(master_id, familiar_id, max_hp)


## Resolves the master's save vs Death after a familiar dies. On a failed
## save, applies damage equal to the familiar's max-hp-at-death. Always
## clears the death_save_pending flag and the proximity bonus (familiar is
## gone, so the +1 saves no longer apply).
##
## The roll uses `roll_type = "saving_throw_poison"` per OverrideManager's
## vocabulary, so the dice-override system can force a deterministic result
## in tests via `GameState.dice_overrides["saving_throw_poison"] = N`.
func _on_familiar_died(master_id: String, familiar_id: String, max_hp_at_death: int) -> void:
	var master_row: Dictionary = CampaignRepository.get_character(master_id)
	if master_row.is_empty():
		push_error("FamiliarController._on_familiar_died: master not found id=%s" % master_id)
		CampaignRepository.clear_familiar_death_save(familiar_id)
		return
	# Build a minimal CharacterData from the row. Avoids CharacterData.from_dict,
	# which strict-types employer_id and chokes on NULL DB values for non-henchman
	# characters. We only need the fields that bear on the death-link routine
	# (id for repo writes, hp_current for damage application, save_poison_death
	# for the save target, modifiers/flags for proximity-bonus management).
	var master := _master_from_row(master_row)

	# Clear the proximity bonus immediately — no more living familiar.
	clear_proximity_for_master(master)

	# Save target uses the master's effective save value (which now does NOT
	# include the proximity bonus, because we just cleared it — death of the
	# familiar removes that benefit before the save).
	var save_target: int = master.get_effective_save("save_poison_death")
	var roll: RollResult = DiceSystem.roll_digital(20, 1, 0, "saving_throw_poison")
	var passed: bool = roll.modified_total >= save_target

	if not passed:
		_apply_master_death_link_damage(master, max_hp_at_death)

	CampaignRepository.clear_familiar_death_save(familiar_id)


## Builds a minimal in-memory CharacterData from a `characters` table row,
## populating only the fields the familiar runtime needs. Avoids
## `CharacterData.from_dict`, which strict-types `employer_id` and chokes on
## NULL DB values for non-henchman characters.
func _master_from_row(row: Dictionary) -> CharacterData:
	var c := CharacterData.new()
	c.id = str(row.get("id", ""))
	c.campaign_id = str(row.get("campaign_id", ""))
	c.name = str(row.get("name", ""))
	c.level = int(row.get("level", 1))
	c.hp_max = int(row.get("hp_max", 1))
	c.hp_current = int(row.get("hp_current", 1))
	c.intelligence = int(row.get("intelligence", 10))
	c.save_petrification = int(row.get("save_petrification", 15))
	c.save_poison_death = int(row.get("save_poison_death", 14))
	c.save_blast_breath = int(row.get("save_blast_breath", 16))
	c.save_staffs_wands = int(row.get("save_staffs_wands", 16))
	c.save_spells = int(row.get("save_spells", 17))
	c.proficiencies = CampaignRepository.get_character_proficiencies(c.id)
	return c


func _apply_master_death_link_damage(master: CharacterData, amount: int) -> void:
	if amount <= 0:
		return
	var old_hp: int = master.hp_current
	var new_hp: int = old_hp - amount  # may go negative; combat resolver handles death
	master.hp_current = new_hp
	CampaignRepository.update_character_hp(master.id, new_hp)
	EventBus.hp_changed.emit(master.id, old_hp, new_hp)
	EventBus.damage_dealt.emit(master.id, amount, "familiar_death_link", "familiar_death_link")


# ---------------------------------------------------------------------------
# Level-up cache refresh
# ---------------------------------------------------------------------------

## Subscribes to `EventBus.character_leveled_up`. If the leveled-up character
## has a living familiar, refresh its cached stats (HP / HD progression / INT
## / proficiency budget) from the new master state and persist.
func _on_character_leveled_up(character_id: String, _new_level: int) -> void:
	refresh_familiar_stats_for_master(character_id)


## Recomputes a familiar's cached stats from its master's current values and
## persists. No-op if the master has no living familiar.
##
## Returns true if a familiar was refreshed, false otherwise. The boolean
## return is for tests; callers driving normal flow can ignore it.
func refresh_familiar_stats_for_master(master_id: String) -> bool:
	var fam_row: Dictionary = CampaignRepository.get_living_familiar_for_master(master_id)
	if fam_row.is_empty():
		return false
	var master_row: Dictionary = CampaignRepository.get_character(master_id)
	if master_row.is_empty():
		return false
	# Minimal CharacterData — see comment in _on_familiar_died re: from_dict NULL crash.
	var master := _master_from_row(master_row)

	var fam := FamiliarData.from_db(fam_row)
	fam.derive_stats_from_master(master)

	CampaignRepository.update_familiar(fam.id, {
		"hp_current": fam.hp_current,
		"hp_max_cached": fam.hp_max_cached,
		"hd_dice": fam.hd_dice,
		"hd_modifier_hp": fam.hd_modifier_hp,
		"is_half_hd": 1 if fam.is_half_hd else 0,
		"attack_save_class": fam.attack_save_class,
		"attack_save_level": fam.attack_save_level,
		"damage_bonus": fam.damage_bonus,
		"int_cached": fam.int_cached,
		"proficiency_count_cached": fam.proficiency_count_cached,
	})
	return true
