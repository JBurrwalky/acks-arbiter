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

	# Create combat subsystems
	var active_effects: ActiveEffectTracker = runner.get_active_effects()
	var condition_catalog := ConditionCatalog.new()
	var condition_manager := CombatConditionManager.new(condition_catalog)
	var spell_hooks := SpellCombatHooks.new(active_effects)

	var init_resolver := InitiativeResolver.new(DiceSystem)
	var attack_resolver := AttackResolver.new(DiceSystem, spell_hooks)
	var ranged_resolver := RangedAttackResolver.new(DiceSystem, spell_hooks)

	# Retrieve tactical map if available (dungeon/battle map combat)
	var tactical_map: TacticalMapData = context.get("tactical_map", null)

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

	EventBus.combat_started.emit(_encounter_id)

	# Push the combat screen and let it auto-advance.
	_runner_ref = runner
	var packed: PackedScene = preload("res://scenes/ui/combat/combat_screen.tscn")
	_combat_screen = packed.instantiate()
	_combat_screen.setup(_controller)
	_combat_screen.combat_finished.connect(_on_combat_finished)

	# Update subtitle with encounter summary
	var subtitle: Label = _combat_screen.get_node_or_null("Panel/VBox/Subtitle")
	if subtitle != null:
		var group: String = _encounter_data.get("monster_group", "unknown")
		var count: int = _encounter_data.get("number", 0)
		var disposition: String = _encounter_data.get("behavioral_disposition", "neutral")
		subtitle.text = "%d × %s  (%s)" % [count, group, disposition]

	runner.get_nav_stack().push_node(_combat_screen, "combat_%s" % _encounter_id)
	_combat_screen.start_auto_advance()


func exit(runner) -> void:
	runner.get_nav_stack().pop()
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
	var combat_result_str: String = result.get("result", "")

	# 1. Process mortal wounds outcomes — mark dead PCs in CharacterData.
	var downed_pcs: Array = result.get("downed_pcs", [])
	for entry in downed_pcs:
		var mw: Dictionary = entry.get("mortal_wound_result", {})
		if mw.get("is_dead", false):
			_mark_pc_dead(party_data, entry.get("combatant_id", ""))

	# 2. Award XP — only on victory (party won and survived to collect XP).
	if combat_result_str == "victory":
		_award_combat_xp(runner, result)

	# 3. Advance timekeeping by combat rounds.
	var rounds_fought: int = result.get("rounds", 0)
	if rounds_fought > 0:
		runner.advance_exploration_time(0)  # don't advance exploration turns
		Timekeeping.advance_rounds(rounds_fought)

	# combat_ended signal is emitted by the controller in _emit_combat_ended().
	return _return_state_key


func _mark_pc_dead(party_data: PartyData, combatant_id: String) -> void:
	## Set CharacterData.is_dead = true and emit character_died signal.
	if party_data == null or combatant_id.is_empty():
		return
	var char_data: CharacterData = party_data.get_member(combatant_id)
	if char_data == null:
		return
	char_data.is_dead = true
	char_data.is_active = false
	EventBus.character_died.emit(combatant_id)


func _award_combat_xp(runner, result: Dictionary) -> void:
	## Distribute monster XP to surviving (and downed-but-alive) party members.
	var party_data: PartyData = runner.get_party_data()
	if party_data == null:
		return
	var monster_xp_total: int = result.get("monster_xp_total", 0)
	if monster_xp_total <= 0:
		return

	# Build member list: alive active characters (dead-this-combat excluded).
	var downed_dead_ids: Array = []
	for entry in result.get("downed_pcs", []):
		if entry.get("mortal_wound_result", {}).get("is_dead", false):
			downed_dead_ids.append(entry.get("combatant_id", ""))

	var members: Array = []
	for char_data: CharacterData in party_data.character_data:
		if not char_data.is_active:
			continue  # Already inactive before this combat
		if char_data.id in downed_dead_ids:
			continue  # Died this combat — no XP per ACKS rules
		members.append({
			"character_id":          char_data.id,
			"is_henchman":           char_data.character_type == "henchman",
			"xp_adjustment_percent": char_data.xp_adjustment_percent,
			"character_data":        char_data,
		})

	if members.is_empty():
		return

	var class_registry: ClassRegistry = runner.get_class_registry()
	var calculator := XPAwardCalculator.new(class_registry)
	# treasure_xp = 0 until treasure collection system is built.
	var xp_results: Array = calculator.award_adventure_xp(monster_xp_total, 0, members)

	for xp_entry in xp_results:
		var cid: String = xp_entry["character_id"]
		var clamped: int = xp_entry["clamped_share"]
		var char_data: CharacterData = party_data.get_member(cid)
		if char_data == null:
			continue
		char_data.xp = xp_entry["xp_after"]
		EventBus.xp_awarded.emit(cid, clamped)
		if xp_entry.get("leveled_up", false):
			EventBus.character_leveled_up.emit(cid, char_data.level + 1)


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
