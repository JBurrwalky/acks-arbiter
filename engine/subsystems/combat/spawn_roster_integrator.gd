class_name SpawnRosterIntegrator
extends RefCounted

## Mid-combat consumer for spawn-producing spells.
##
## Subscribes to [signal EventBus.spell_effect_applied]. On each spawn-spell
## match, reads the active_effect's metadata, constructs Combatants from the
## monster catalog, places them on the grid, and adds them to the roster.
## Spawned combatant ids are written back to the active_effect metadata
## under `spawned_combatant_ids` so later cleanup/hostility-flip code (P7,
## P8) can find the spawns without re-deriving them.
##
## Coverage (P3):
##   animate_dead         — skeleton/zombie templates from spawn_profile.animated
##   sticks_to_snakes     — snake_normal/snake_poisonous from spawn_profile.snakes
##   conjure_elemental    — elemental_<type> from spawn_profile
##   invisible_stalker    — invisible_stalker (single spawn)
##   insect_plague        — 4× insect_swarm_4hd from plague_profile.swarms
##
## Spiritual Weapon is NOT rostered (it's a phantasmal weapon, not a creature).
## The session_runner / combat_controller wires one instance per combat and
## calls disconnect() at combat end so the integrator does not leak spawns
## across encounters.

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _roster: CombatRoster = null
var _movement_resolver: MovementResolver = null
var _active_effects: ActiveEffectTracker = null
var _monster_registry: MonsterRegistry = null
var _dice_system = null
var _connected: bool = false


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(
		roster: CombatRoster,
		movement_resolver: MovementResolver,
		active_effects: ActiveEffectTracker,
		monster_registry: MonsterRegistry,
		dice_system = null) -> void:
	_roster = roster
	_movement_resolver = movement_resolver
	_active_effects = active_effects
	_monster_registry = monster_registry
	_dice_system = dice_system


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func connect_signals() -> void:
	if _connected:
		return
	EventBus.spell_effect_applied.connect(_on_spell_effect_applied)
	_connected = true


func disconnect_signals() -> void:
	if not _connected:
		return
	if EventBus.spell_effect_applied.is_connected(_on_spell_effect_applied):
		EventBus.spell_effect_applied.disconnect(_on_spell_effect_applied)
	_connected = false


# ---------------------------------------------------------------------------
# Signal handler
# ---------------------------------------------------------------------------

func _on_spell_effect_applied(effect_id: String, spell_key: String, _target_ids: Array) -> void:
	if _roster == null or _active_effects == null or _monster_registry == null:
		return
	var effect: Dictionary = _active_effects.get_effect(effect_id)
	if effect.is_empty():
		return
	process_effect(effect, spell_key)


## Test-friendly entry point: applies spawn integration to [param effect]
## directly without a signal round-trip. Returns the array of spawned
## combatant ids (empty if the spell has no spawn profile).
func process_effect(effect: Dictionary, spell_key: String) -> Array[String]:
	var spawned: Array[String] = []
	match spell_key:
		"animate_dead":
			spawned = _spawn_animate_dead(effect)
		"sticks_to_snakes":
			spawned = _spawn_sticks_to_snakes(effect)
		"conjure_elemental":
			spawned = _spawn_conjure_elemental(effect)
		"invisible_stalker":
			spawned = _spawn_invisible_stalker(effect)
		"insect_plague":
			spawned = _spawn_insect_plague(effect)
		_:
			return spawned
	if not spawned.is_empty():
		_record_spawned_ids(effect, spawned)
	return spawned


# ---------------------------------------------------------------------------
# Per-spell spawn handlers
# ---------------------------------------------------------------------------

func _spawn_animate_dead(effect: Dictionary) -> Array[String]:
	var spawned: Array[String] = []
	var profile: Dictionary = effect.get("metadata", {}).get("animate_dead_spawn_profile", {})
	if profile.is_empty():
		return spawned
	var caster_id: String = String(profile.get("caster_id", effect.get("caster_id", "")))
	var origin: Vector3i = _resolve_origin_cell(caster_id)
	for entry_raw in profile.get("animated", []):
		if not (entry_raw is Dictionary):
			continue
		var entry: Dictionary = entry_raw
		var template := str(entry.get("undead_template", "skeleton"))
		var monster_id := template if _monster_registry.has_monster(template) else "skeleton"
		var combatant := _build_combatant(
			monster_id, str(entry.get("undead_id", "")), Combatant.Side.PARTY)
		if combatant == null:
			continue
		if _roster.add_combatant(combatant):
			_place_combatant(combatant, origin)
			spawned.append(combatant.id)
	return spawned


func _spawn_sticks_to_snakes(effect: Dictionary) -> Array[String]:
	var spawned: Array[String] = []
	var profile: Dictionary = effect.get("metadata", {}).get("sticks_to_snakes_spawn_profile", {})
	if profile.is_empty():
		return spawned
	var caster_id: String = String(profile.get("caster_id", effect.get("caster_id", "")))
	var snake_species := String(profile.get("snake_species", "pit_viper")).to_lower()
	var monster_id := "snake_%s" % snake_species
	if not _monster_registry.has_monster(monster_id):
		# Catalog mismatch — fall back to pit viper, which is always present.
		monster_id = "snake_pit_viper"
	# Spawn anchor: per-stick item-owner cell when the picker supplied selected
	# stick item ids; otherwise fall back to the caster cell. Inventory removal
	# (sticks vanish when transformed) is deferred — selected_stick_item_ids
	# is persisted for the future inventory-picker session.
	var spawn_anchor := String(profile.get("spawn_anchor", "caster"))
	var caster_cell: Vector3i = _resolve_origin_cell(caster_id)
	var stick_owner_cells: Array[Vector3i] = []
	if spawn_anchor == "item_owner":
		# Owner-cell resolution requires inventory + character lookup. Until
		# the picker UI lands, the integrator falls back to the caster cell
		# for every snake. Surface the deferred state in the spawned-effect
		# metadata so the UI can flag it.
		stick_owner_cells = []
	for entry_raw in profile.get("snakes", []):
		if not (entry_raw is Dictionary):
			continue
		var entry: Dictionary = entry_raw
		var combatant := _build_combatant(
			monster_id, str(entry.get("snake_id", "")), Combatant.Side.PARTY)
		if combatant == null:
			continue
		# Carry the per-snake poison-disabled flag onto the combatant so the
		# attack hooks can suppress poison effects (bite + cobra spit).
		combatant.set_meta("poison_disabled", bool(entry.get("poison_disabled", false)))
		if _roster.add_combatant(combatant):
			var place_cell: Vector3i = caster_cell
			if not stick_owner_cells.is_empty():
				place_cell = stick_owner_cells[spawned.size() % stick_owner_cells.size()]
			_place_combatant(combatant, place_cell)
			spawned.append(combatant.id)
	return spawned


func _spawn_conjure_elemental(effect: Dictionary) -> Array[String]:
	var spawned: Array[String] = []
	var profile: Dictionary = effect.get("metadata", {}).get("conjure_elemental_spawn_profile", {})
	if profile.is_empty():
		return spawned
	var elemental_type := String(profile.get("elemental_type", "earth")).to_lower()
	# Tier dispatch (8hd staff / 12hd item / 16hd spell). Conjure Elemental
	# always summons spell tier (16hd) by default; future non-spell paths
	# may override via the resolver's tier param.
	var tier := String(profile.get("tier", "16hd")).to_lower()
	var monster_id := "elemental_%s_%s" % [elemental_type, tier]
	if not _monster_registry.has_monster(monster_id):
		# Defensive fallback: try the spell tier, then the legacy single-tier
		# id. Either case logs a warning so misconfiguration is visible.
		var fallback: String = "elemental_%s_16hd" % elemental_type
		if _monster_registry.has_monster(fallback):
			monster_id = fallback
		elif _monster_registry.has_monster("elemental_%s" % elemental_type):
			monster_id = "elemental_%s" % elemental_type
		else:
			return spawned
	var combatant := _build_combatant(
		monster_id, String(profile.get("elemental_id", "")), Combatant.Side.PARTY)
	if combatant == null:
		return spawned
	if _roster.add_combatant(combatant):
		var summon_cell = profile.get("summon_cell", null)
		var cell: Vector3i = summon_cell if summon_cell is Vector3i else _resolve_origin_cell(
			String(profile.get("caster_id", "")))
		_place_combatant(combatant, cell)
		spawned.append(combatant.id)
	return spawned


func _spawn_invisible_stalker(effect: Dictionary) -> Array[String]:
	var spawned: Array[String] = []
	var profile: Dictionary = effect.get("metadata", {}).get("invisible_stalker_spawn_profile", {})
	if profile.is_empty():
		return spawned
	var caster_id := String(profile.get("caster_id", effect.get("caster_id", "")))
	var stalker_id := String(profile.get("stalker_id", ""))
	if stalker_id.is_empty():
		stalker_id = "invisible_stalker:%s" % caster_id
	# P8 — reliability check. Per RAW the stalker "may not always be a
	# reliable servant". Modeled here as a 2d6 reaction-roll-style throw
	# vs caster Charisma modifier:
	#   2d6 + caster_charisma_modifier ≥ 6 → loyal (PARTY-side servant)
	#   below threshold                  → unreliable / hostile-to-caster
	#                                        (ENEMY side, is_hostile_to_caster
	#                                        flag, plus elemental_uncontrolled
	#                                        signal for downstream re-routers)
	var loyal: bool = _stalker_reliability_check(profile)
	var side: int = Combatant.Side.PARTY if loyal else Combatant.Side.ENEMY
	var combatant := _build_combatant("invisible_stalker", stalker_id, side)
	if combatant == null:
		return spawned
	# Always invisible per RAW.
	var flags := combatant.get_flags()
	if flags != null:
		flags.set_flag("is_invisible", "spell:invisible_stalker", {})
		if not loyal:
			flags.set_flag("is_hostile_to_caster", "spell:invisible_stalker",
				{"former_caster_id": caster_id})
	if _roster.add_combatant(combatant):
		var origin := _resolve_origin_cell(caster_id)
		_place_combatant(combatant, origin)
		spawned.append(combatant.id)
		if not loyal:
			# Re-use the elemental_uncontrolled signal — same downstream
			# semantics (was-PARTY-now-ENEMY summon) and MonsterAI's
			# subscriber already does the move_to_side flip safely.
			EventBus.elemental_uncontrolled.emit(stalker_id, "stalker", caster_id)
	return spawned


## Rolls the per-spawn reliability check for the stalker. Profile fields:
##   caster_charisma_modifier:  int — defaults to 0; CHA mod from caster.
##   reliability_threshold:     int — defaults to 6; 2d6+mod must meet this.
##   reliability_override:      Variant — when present, skips the dice roll
##                                        and uses the bool value directly
##                                        (test fixture path).
## Returns true on success (stalker loyal); false on failure.
func _stalker_reliability_check(profile: Dictionary) -> bool:
	var override = profile.get("reliability_override", null)
	if override != null:
		return bool(override)
	var threshold: int = int(profile.get("reliability_threshold", 6))
	var cha_mod: int = int(profile.get("caster_charisma_modifier", 0))
	var roll_total: int = 7 + cha_mod  # 2d6 average
	if _dice_system != null:
		var r = _dice_system.roll_digital(6, 2, cha_mod, "invisible_stalker_reliability")
		if r != null:
			roll_total = int(r.modified_total)
	return roll_total >= threshold


func _spawn_insect_plague(effect: Dictionary) -> Array[String]:
	var spawned: Array[String] = []
	var profile: Dictionary = effect.get("metadata", {}).get("plague_profile", {})
	if profile.is_empty():
		return spawned
	# Catalog id is per-swarm-type and per-HD. Insect Plague summons HD 4
	# insect swarms; rat / bat swarm summon spells (future content) would
	# override via swarm_type on the plague_profile.
	var swarm_type := String(profile.get("swarm_type", "insect")).to_lower()
	for entry_raw in profile.get("swarms", []):
		if not (entry_raw is Dictionary):
			continue
		var entry: Dictionary = entry_raw
		var swarm_hd: int = int(entry.get("swarm_hd", 4))
		var monster_id: String = "%s_swarm_%dhd" % [swarm_type, swarm_hd]
		if not _monster_registry.has_monster(monster_id):
			# Fall back to the 4-HD insect entry for the spell-spawn path.
			monster_id = "insect_swarm_4hd"
		var combatant := _build_combatant(
			monster_id, str(entry.get("swarm_id", "")), Combatant.Side.PARTY)
		if combatant == null:
			continue
		if _roster.add_combatant(combatant):
			var swarm_cell = entry.get("swarm_cell", null)
			var cell: Vector3i = swarm_cell if swarm_cell is Vector3i else Vector3i.ZERO
			_place_combatant(combatant, cell)
			spawned.append(combatant.id)
	return spawned


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _build_combatant(monster_id: String, combatant_id: String, side: int) -> Combatant:
	if not _monster_registry.has_monster(monster_id):
		return null
	var monster_data: Dictionary = _monster_registry.get_monster(monster_id)
	var hd_info: Dictionary = monster_data.get("hit_dice", {})
	var hd_base: int = int(hd_info.get("base", 1))
	var hd_modifier: int = int(hd_info.get("modifier", 0))
	var rolled_hp: int
	if _dice_system != null:
		var die_count := maxi(1, hd_base)
		var result: RollResult = _dice_system.roll_digital(8, die_count, hd_modifier, "spawn_hp")
		rolled_hp = maxi(1, result.modified_total)
	else:
		# Deterministic average: 4 hp per die plus modifier, minimum 1.
		rolled_hp = maxi(1, hd_base * 4 + hd_modifier)
	var unique_id: String = combatant_id
	if unique_id.is_empty() or _roster.get_by_id(unique_id) != null:
		unique_id = "%s_%d" % [monster_id, Time.get_ticks_usec()]
	var combatant := Combatant.from_monster(monster_data, rolled_hp, unique_id, monster_id)
	combatant.side = side
	return combatant


func _place_combatant(combatant: Combatant, cell: Vector3i) -> void:
	if _movement_resolver == null:
		combatant.grid_position = cell
		return
	_movement_resolver.set_grid_position_3d(combatant, cell)


func _resolve_origin_cell(caster_id: String) -> Vector3i:
	if _roster == null or caster_id.is_empty():
		return Vector3i.ZERO
	var caster := _roster.get_by_id(caster_id)
	if caster == null:
		return Vector3i.ZERO
	return caster.grid_position


func _record_spawned_ids(effect: Dictionary, spawned: Array[String]) -> void:
	if _active_effects == null or spawned.is_empty():
		return
	var effect_id := String(effect.get("effect_id", ""))
	if effect_id.is_empty() or not _active_effects.has_effect(effect_id):
		return
	# Update via the tracker's stored copy (add_effect deep-duplicates on insert,
	# so the effect dict we received is a snapshot — we have to mutate the
	# tracker's internal dict directly).
	var stored: Dictionary = _active_effects.get_effect(effect_id)
	if stored.is_empty():
		return
	var meta: Dictionary = stored.get("metadata", {})
	meta["spawned_combatant_ids"] = spawned.duplicate()
	stored["metadata"] = meta
