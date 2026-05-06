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
		var template := String(entry.get("undead_template", "skeleton"))
		var monster_id := template if _monster_registry.has_monster(template) else "skeleton"
		var combatant := _build_combatant(
			monster_id, String(entry.get("undead_id", "")), Combatant.Side.PARTY)
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
	var origin: Vector3i = _resolve_origin_cell(caster_id)
	for entry_raw in profile.get("snakes", []):
		if not (entry_raw is Dictionary):
			continue
		var entry: Dictionary = entry_raw
		var monster_id: String = "snake_poisonous" if bool(entry.get("poisonous", false)) else "snake_normal"
		var combatant := _build_combatant(
			monster_id, String(entry.get("snake_id", "")), Combatant.Side.PARTY)
		if combatant == null:
			continue
		if _roster.add_combatant(combatant):
			_place_combatant(combatant, origin)
			spawned.append(combatant.id)
	return spawned


func _spawn_conjure_elemental(effect: Dictionary) -> Array[String]:
	var spawned: Array[String] = []
	var profile: Dictionary = effect.get("metadata", {}).get("conjure_elemental_spawn_profile", {})
	if profile.is_empty():
		return spawned
	var elemental_type := String(profile.get("elemental_type", "earth")).to_lower()
	var monster_id := "elemental_%s" % elemental_type
	if not _monster_registry.has_monster(monster_id):
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
	var stalker_id := String(profile.get("stalker_id", ""))
	if stalker_id.is_empty():
		stalker_id = "invisible_stalker:%s" % String(profile.get("caster_id", effect.get("caster_id", "")))
	var combatant := _build_combatant(
		"invisible_stalker", stalker_id, Combatant.Side.PARTY)
	if combatant == null:
		return spawned
	# Mark as invisible per RAW (always invisible).
	var flags := combatant.get_flags()
	if flags != null:
		flags.set_flag("is_invisible", "spell:invisible_stalker", {})
	if _roster.add_combatant(combatant):
		var origin := _resolve_origin_cell(String(profile.get("caster_id", "")))
		_place_combatant(combatant, origin)
		spawned.append(combatant.id)
	return spawned


func _spawn_insect_plague(effect: Dictionary) -> Array[String]:
	var spawned: Array[String] = []
	var profile: Dictionary = effect.get("metadata", {}).get("plague_profile", {})
	if profile.is_empty():
		return spawned
	for entry_raw in profile.get("swarms", []):
		if not (entry_raw is Dictionary):
			continue
		var entry: Dictionary = entry_raw
		var combatant := _build_combatant(
			"insect_swarm_4hd", String(entry.get("swarm_id", "")), Combatant.Side.PARTY)
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
