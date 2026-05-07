class_name CombatState
extends SessionState

## Combat session state — bridges SessionRunner and CombatController.
##
## Builds the combat roster from encounter data, instantiates the combat
## subsystem classes (including spell hooks, condition manager, ranged resolver),
## and routes player actions to CombatController.
## When combat ends, transitions back to the exploration state that
## triggered the encounter.

var _encounter_data: Dictionary = {}
var _return_state_key: String = "wilderness"
var _controller: CombatController = null
var _encounter_id: String = ""
var _combat_screen: CombatScreen = null
var _runner_ref = null
var _finalizer := CombatFinalizer.new()


func enter(runner, context: Dictionary) -> void:
	_encounter_data = context.get("encounter_data", {})
	_return_state_key = context.get("return_state", "wilderness")
	_encounter_id = _encounter_data.get("encounter_id", "")
	runner.cancel_pending_roll()

	# Build the combat roster from encounter data
	var party_data: PartyData = runner.get_party_data()
	var monster_registry: MonsterRegistry = runner.get_monster_registry()
	var roster := CombatRoster.build_from_encounter(
		party_data, _encounter_data, monster_registry, DiceSystem)

	# Add trained creatures with combat roles (war mounts, guards, hunters)
	roster.add_party_creatures(party_data, monster_registry)

	# Wire equipped weapons for PC combatants
	var equip_catalog = load("res://engine/subsystems/characters/equipment_catalog.gd")
	var catalog = equip_catalog.new() if equip_catalog != null else null
	for c in roster.get_party_combatants():
		var inv_rows: Array = CampaignRepository.get_inventory_items(c.id)
		c.wire_equipment(inv_rows, catalog)

	# Create combat subsystems
	var active_effects: ActiveEffectTracker = runner.get_active_effects()
	var condition_catalog := ConditionCatalog.new()
	var condition_manager := CombatConditionManager.new(condition_catalog)
	var spell_hooks := SpellCombatHooks.new(active_effects, DiceSystem)

	var init_resolver := InitiativeResolver.new(DiceSystem)
	var attack_resolver := AttackResolver.new(DiceSystem, spell_hooks)
	var ranged_resolver := RangedAttackResolver.new(DiceSystem, spell_hooks)

	# 500'×500' wilderness battle map per gdd-combat-map-generation.md §3.
	# 100×100 cells at 5'/cell accommodates the full ACKS encounter-distance
	# range (5d4 yards in heavy forest up to 5d20×10 yards in plains).
	# Context may provide a pre-built map (future battle-map generation).
	var voxel_map: VoxelMapData = context.get("voxel_map", null)
	if voxel_map == null:
		voxel_map = VoxelMapData.generate_open_field(100, 100)

	# Create Session 3 subsystems: AI, morale, cleave.
	# MovementResolver is created early so MonsterAI can use spatial queries.
	var movement_resolver := MovementResolver.new(roster)
	movement_resolver.set_voxel_map(voxel_map)
	var monster_ai := MonsterAI.new(roster, DiceSystem, movement_resolver, active_effects)
	var morale_resolver := MoraleResolver.new(DiceSystem)
	var cleave_resolver := CleaveResolver.new()

	# Create the mortal wounds resolver for post-combat PC casualty processing.
	var mortal_wounds_resolver := MortalWoundsResolver.new(DiceSystem)

	# Create the controller with all dependencies
	_controller = CombatController.new(
		roster, init_resolver, attack_resolver,
		spell_hooks, condition_manager, ranged_resolver,
		monster_ai, morale_resolver, cleave_resolver,
		mortal_wounds_resolver, voxel_map,
		runner.get_casting_resolver())
	_controller.encounter_id = _encounter_id

	# P3: Spawn-roster integrator wires Animate Dead / Sticks to Snakes /
	# Conjure Elemental / Invisible Stalker / Insect Plague spawns into the
	# live roster. Connected on combat start, disconnected on combat end.
	_controller.spawn_roster_integrator = SpawnRosterIntegrator.new(
		roster, movement_resolver, active_effects, monster_registry, DiceSystem)

	# P5: TeleportRuntimeConsumer snaps Dimension Door / Teleport targets to
	# their destination cells, applying solid-matter / falling / lost
	# outcomes per ACKS RAW. Same connect/disconnect lifecycle as P3.
	_controller.teleport_runtime_consumer = TeleportRuntimeConsumer.new(
		roster, movement_resolver, voxel_map, DiceSystem)

	_place_combatants_on_grid(roster, voxel_map)

	# Pause the scheduler — combat runs its own time loop.
	var sched_loop: SchedulerLoop = runner.get_scheduler_loop()
	if sched_loop != null:
		sched_loop.pause()

	EventBus.combat_started.emit(_encounter_id)

	# Push the combat screen with interactive HUD.
	_runner_ref = runner
	var packed: PackedScene = preload("res://scenes/ui/combat/combat_screen.tscn")
	_combat_screen = packed.instantiate()
	_combat_screen.setup(_controller)
	_combat_screen.combat_finished.connect(_on_combat_finished)

	runner.get_nav_stack().push_node(_combat_screen, "combat_%s" % _encounter_id)
	_combat_screen.start_interactive()


func exit(runner) -> void:
	runner.get_nav_stack().pop()

	# Resume the scheduler. It starts paused — the returning exploration state
	# or the player decides when to unpause. The party's time may now be ahead
	# of the global clock after combat time rounding.
	var sched_loop: SchedulerLoop = runner.get_scheduler_loop()
	if sched_loop != null and not sched_loop.is_paused():
		# Already unpaused by the return state — don't double-resume.
		pass

	_controller = null
	_combat_screen = null
	_runner_ref = null


func _on_combat_finished(result: Dictionary) -> void:
	## Called by CombatScreen when auto-advance completes.
	## Defers the state transition to avoid re-entrant transition_to_state calls
	## (combat_finished fires inside enter(), which is itself inside transition_to_state).
	if _runner_ref == null:
		return
	_finish_combat(_runner_ref, result)
	var return_key := _return_state_key
	_runner_ref.call_deferred("transition_to_state", return_key)


func handle_action(runner, action: String, payload: Dictionary) -> String:
	if _controller == null:
		return _return_state_key

	match action:
		"combat_advance":
			# Advance the combat state machine one step
			var result := _controller.advance()
			var status: String = result.get("status", "")
			if status == "combat_over":
				return _finish_combat(runner, result)
			return ""

		"combat_pc_action":
			# Submit a PC's chosen action, then advance
			var combatant_id: String = payload.get("combatant_id", "")
			var action_id: String = payload.get("action_id", "pass")
			var params: Dictionary = payload.get("parameters", {})
			_controller.submit_pc_action(combatant_id, action_id, params)
			var result := _controller.advance()
			var status: String = result.get("status", "")
			if status == "combat_over":
				return _finish_combat(runner, result)
			return ""

		"combat_ended":
			# Direct combat end (e.g., from override system)
			return _finish_combat(runner, payload)

	return ""


func _finish_combat(runner, result: Dictionary) -> String:
	var party_data: PartyData = runner.get_party_data()
	var roster: CombatRoster = _controller.roster if _controller != null else null
	_finalizer.finalize(runner, result, party_data, roster)
	# combat_ended signal is emitted by the controller in _emit_combat_ended().
	return _return_state_key


## Returns the CombatController for UI queries (initiative order, waiting combatant, etc.).
func get_controller() -> CombatController:
	return _controller


func _place_combatants_on_grid(
		roster: CombatRoster,
		vmap: VoxelMapData) -> void:
	## Place party near the entry position, monsters at the rolled ACKS
	## encounter distance (clamped to map bounds per gdd §7.3).
	var entry: Vector3i = vmap.entry_pos
	var party_cells := VoxelGrid.get_cells_in_radius_3d(entry, 2)
	var idx := 0
	for c: Combatant in roster.get_alive_on_side(Combatant.Side.PARTY):
		# Find a passable, unoccupied cell near entry
		while idx < party_cells.size():
			var cell: Vector3i = party_cells[idx]
			idx += 1
			if vmap.is_passable(cell) and vmap.get_entities_at(cell).is_empty():
				c.grid_position = cell
				vmap.set_entity_pos(c.id, cell)
				break

	# Place monsters at the rolled encounter distance, clamped to the map.
	var terrain_category: String = _encounter_data.get("terrain_category", "clear")
	# Phase 2: weather visibility shrinks the rolled distance.
	# `visibility_multiplier` is attached to encounter context by
	# WildernessHandlers when an encounter triggers; default 1.0 keeps prior
	# behavior for callers that don't provide it. Source:
	# `acore_adventures_and_encounters.xml` §encounter_distance + DaW
	# §severe_weather_effects (reconnaissance penalties).
	var visibility: float = float(_encounter_data.get("visibility_multiplier", 1.0))
	var distance_cells: int = _roll_encounter_distance_cells(
		terrain_category, DiceSystem, visibility)
	var max_offset: int = _max_offset_from_entry(entry, vmap)
	var clamped_offset: int = mini(distance_cells, max_offset)
	var monster_center := Vector3i(entry.x + clamped_offset, entry.y, entry.z)
	# Generous spread — many monsters in plains may otherwise overflow a 3-cell
	# radius. Stays bounded by the loop's "find passable cell" probe.
	var monster_cells := VoxelGrid.get_cells_in_radius_3d(monster_center, 5)
	idx = 0
	for c: Combatant in roster.get_alive_on_side(Combatant.Side.ENEMY):
		while idx < monster_cells.size():
			var cell: Vector3i = monster_cells[idx]
			idx += 1
			if not vmap.has_cell(cell):
				continue
			if vmap.is_passable(cell) and vmap.get_entities_at(cell).is_empty():
				c.grid_position = cell
				vmap.set_entity_pos(c.id, cell)
				break


## Rolls the ACKS wilderness encounter distance for [param terrain_category]
## (mapped from `HexTerrainData.movement_cost_category()`) and converts to
## battle-map cells (1 yard = 0.6 cells at 5'/cell). See
## `acore_adventures_and_encounters.xml` §encounter_distance_table.
##
## [param visibility_multiplier] (Phase 2) shrinks the rolled distance to
## model weather and ambient light per gdd-weather-generation.md §4.5 and
## §7.2. Default 1.0. Floor at 1 cell so monsters are never spawned on
## the party's own square.
static func _roll_encounter_distance_cells(
	terrain_category: String,
	dice,
	visibility_multiplier: float = 1.0,
) -> int:
	# (dice_count, dice_sides, multiplier_yards). Multiplier is the per-die
	# scaling — e.g. 4d6×10 yards is (4, 6, 10).
	var spec: Array = _encounter_distance_spec(terrain_category)
	var dc: int = spec[0]
	var ds: int = spec[1]
	var mult: int = spec[2]
	var yards: int = 0
	for _i in range(dc):
		var roll: RollResult = dice.roll_digital(ds, 1, 0, "encounter_distance")
		yards += roll.modified_total
	yards *= mult
	# Apply weather visibility scaling on yards before converting to cells —
	# preserves the ACKS "90% reduction" example (multiplier 0.1 on 5d20×10
	# plains drops 500-1000 yards to 50-100, matching the rule).
	var scaled_yards: float = float(yards) * visibility_multiplier
	# 1 yard = 3 feet; 1 cell = 5 feet → cells = round(yards * 3 / 5).
	return maxi(1, int(round(scaled_yards * 0.6)))


## Returns [dice_count, dice_sides, multiplier_yards] for an encounter on
## the given terrain category. Defaults to Plains (5d20×10) for unrecognised
## categories so we err on the side of giving ranged combat enough room.
static func _encounter_distance_spec(terrain_category: String) -> Array:
	match terrain_category:
		"jungle":     return [5, 4, 1]    # Forest, Heavy / Jungle
		"woods":      return [5, 8, 1]    # Forest, Light
		"swamp":      return [8, 10, 1]   # Marsh
		"mountains":  return [4, 6, 10]
		"hills":      return [4, 6, 10]   # not in RAW; share Mountains
		"desert":     return [4, 6, 10]
		"clear", "":  return [5, 20, 10]  # Plains
		_:            return [5, 20, 10]


## Returns the largest valid `entry.x + offset` that still falls inside the
## map. Used to clamp huge encounter distances per gdd §7.3 ("place monsters
## at the far edge of the map").
static func _max_offset_from_entry(entry: Vector3i, vmap: VoxelMapData) -> int:
	# VoxelMapData doesn't expose dimensions directly — probe outward from
	# entry until we leave the map.
	var offset := 0
	while vmap.has_cell(Vector3i(entry.x + offset + 1, entry.y, entry.z)):
		offset += 1
	return maxi(1, offset - 1)  # leave a 1-cell margin so monsters fit beside the edge
