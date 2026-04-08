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

	# Create the controller with all dependencies
	_controller = CombatController.new(
		roster, init_resolver, attack_resolver,
		spell_hooks, condition_manager, ranged_resolver)

	EventBus.combat_started.emit(_encounter_id)

	# Advance to first meaningful state
	_controller.advance()


func exit(runner) -> void:
	_controller = null


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
	var rounds_fought: int = result.get("rounds", 0)
	if rounds_fought > 0:
		runner.advance_exploration_time(0)  # don't advance turns
		Timekeeping.advance_rounds(rounds_fought)
	# combat_ended signal is emitted by the controller
	return _return_state_key


## Returns the CombatController for UI queries (initiative order, waiting combatant, etc.).
func get_controller() -> CombatController:
	return _controller
