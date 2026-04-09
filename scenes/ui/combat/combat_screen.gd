class_name CombatScreen
extends CanvasLayer

## Minimal placeholder combat screen.
##
## Auto-advances combat: PCs always attack melee, no player input required.
## Displays encounter summary and round-by-round log.
## Emits combat_finished when the fight ends so CombatState can clean up.

signal combat_finished(result: Dictionary)

var _controller: CombatController = null
var _auto_advance: bool = false


func setup(controller: CombatController) -> void:
	_controller = controller


func start_auto_advance() -> void:
	_auto_advance = true
	_advance_loop()


func _advance_loop() -> void:
	if _controller == null:
		return

	var max_iter := 500
	var i := 0
	while i < max_iter:
		var result := _controller.advance()
		var status: String = result.get("status", "")

		match status:
			"waiting_for_pc_action":
				var combatant_id: String = result.get("combatant_id", "")
				_controller.submit_pc_action(combatant_id, "attack_melee")
				_log_line("  PC %s attacks melee." % combatant_id)

			"round_end":
				_log_line("--- Round %d end ---" % result.get("round", 0))

			"combat_over":
				var outcome: String = result.get("result", "unknown")
				var rounds: int = result.get("rounds", 0)
				_log_line("=== Combat %s after %d round(s) ===" % [outcome.to_upper(), rounds])
				combat_finished.emit(result)
				return

		i += 1

	_log_line("ERROR: combat did not complete in %d iterations." % max_iter)
	combat_finished.emit({"result": "timeout", "rounds": 0,
		"monster_xp_total": 0, "downed_pcs": []})


func _log_line(text: String) -> void:
	print(text)
	var label: RichTextLabel = get_node_or_null("Panel/VBox/Log")
	if label != null:
		label.append_text(text + "\n")
