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
	var spell_hooks := SpellCombatHooks.new(active_effects)

	var init_resolver := InitiativeResolver.new(DiceSystem)
	var attack_resolver := AttackResolver.new(DiceSystem, spell_hooks)
	var ranged_resolver := RangedAttackResolver.new(DiceSystem, spell_hooks)

	# Retrieve tactical map if available, otherwise generate an open-field battle map
	var tactical_map: TacticalMapData = context.get("tactical_map", null)
	if tactical_map == null:
		tactical_map = TacticalMapData.generate_open_field()

	# Create Session 3 subsystems: AI, morale, cleave
	# Create MovementResolver early so MonsterAI can use spatial queries
	var movement_resolver: MovementResolver = null
	if tactical_map != null:
		movement_resolver = MovementResolver.new(tactical_map, roster)
	var monster_ai := MonsterAI.new(roster, DiceSystem, movement_resolver)
	var morale_resolver := MoraleResolver.new(DiceSystem)
	var cleave_resolver := CleaveResolver.new()

	# Create the mortal wounds resolver for post-combat PC casualty processing.
	var mortal_wounds_resolver := MortalWoundsResolver.new(DiceSystem)

	# Create the controller with all dependencies
	_controller = CombatController.new(
		roster, init_resolver, attack_resolver,
		spell_hooks, condition_manager, ranged_resolver,
		monster_ai, morale_resolver, cleave_resolver,
		tactical_map, mortal_wounds_resolver)
	_controller.encounter_id = _encounter_id

	# Place combatants on grid if a tactical map is provided
	if tactical_map != null:
		_place_combatants_on_grid(roster, tactical_map)

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
	_finalizer.finalize(runner, result, party_data)
	# combat_ended signal is emitted by the controller in _emit_combat_ended().
	return _return_state_key


## Returns the CombatController for UI queries (initiative order, waiting combatant, etc.).
func get_controller() -> CombatController:
	return _controller


func _place_combatants_on_grid(
		roster: CombatRoster,
		tmap: TacticalMapData) -> void:
	## Place party near the entry position, monsters spread in the room.
	var entry := tmap.entry_pos
	var party_cells := IsometricGrid.get_cells_in_radius(entry, 2)
	var idx := 0
	for c: Combatant in roster.get_alive_on_side(Combatant.Side.PARTY):
		# Find a passable, unoccupied cell near entry
		while idx < party_cells.size():
			var cell: Vector2i = party_cells[idx]
			idx += 1
			if tmap.is_passable(cell) and tmap.get_entities_at(cell).is_empty():
				c.grid_position = cell
				tmap.set_entity_pos(c.id, cell)
				break

	# Place monsters away from party (offset from entry)
	var monster_center := Vector2i(entry.x + 6, entry.y)
	var monster_cells := IsometricGrid.get_cells_in_radius(monster_center, 3)
	idx = 0
	for c: Combatant in roster.get_alive_on_side(Combatant.Side.ENEMY):
		while idx < monster_cells.size():
			var cell: Vector2i = monster_cells[idx]
			idx += 1
			if tmap.is_passable(cell) and tmap.get_entities_at(cell).is_empty():
				c.grid_position = cell
				tmap.set_entity_pos(c.id, cell)
				break
