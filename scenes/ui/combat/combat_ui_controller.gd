class_name CombatUIController
extends RefCounted

## Shared state machine bridging combat HUD widgets and CombatController.
##
## Used by both DungeonCombatOverlay (dungeon in-place combat) and the
## standalone CombatScreen (wilderness encounters). The controller never
## owns UI nodes directly — it communicates via signals and a duck-typed
## map_callbacks dictionary so the same logic works with either renderer.
##
## Pull-based loop:
##   call advance() → routes CombatController.advance() result →
##   emits signals for the HUD to react → waits for UI input →
##   calls advance() again.


# ---------------------------------------------------------------------------
# UI state enum
# ---------------------------------------------------------------------------

enum State {
	IDLE,                          ## Waiting for first advance() call
	ADVANCING,                     ## Processing a CombatController step
	DECLARATION_PHASE,             ## Waiting for player declarations
	PC_AWAITING_INPUT,             ## PC turn — waiting for right-click or quick button
	PC_CONTEXT_MENU_OPEN,          ## Context menu is visible, waiting for selection
	PC_SELECTING_FACING,           ## After move, waiting for facing click + Confirm Move
	PC_SELECTING_CLEAVE_TARGET,    ## After kill, waiting for cleave target click or Skip Cleave
	PC_SELECTING_WEAPON,           ## PC chose Sheathe & Draw — weapon popup visible
	ENEMY_ACTING,                  ## Enemy AI turn (auto-advance)
	COMBAT_OVER,                   ## Combat ended
}


# ---------------------------------------------------------------------------
# Signals (HUD widgets connect to these)
# ---------------------------------------------------------------------------

## Declaration overlay should appear.
signal show_declaration_requested(alive_pcs: Array)

## Initiative order was rolled — InitiativeStrip should update.
signal initiative_updated(order: Array)

## A PC's turn has started — show action buttons, update stat summary.
signal pc_turn_started(combatant_id: String)

## An action was resolved — log it, update HP bars, etc.
signal action_resolved(result: Dictionary)

## Combat has ended — show CombatEndOverlay.
signal combat_ended(result: Dictionary)

## Combat log entry generated.
signal log_entry(entry: Dictionary)

## The UI host (overlay or screen) should call advance() on the next frame.
signal auto_advance_requested()

## After a move, the player enters facing-selection mode. Host should show the
## "Confirm Move" button and listen for token_facing_preview updates.
signal facing_selection_started(combatant_id: String)

## Live facing preview update while player clicks different adjacent cells
## during the facing-selection phase.
signal token_facing_preview(combatant_id: String, facing: Vector2i)

## Emitted when a combatant becomes eligible for a cleave — host plays CLEAVE! flash.
signal may_cleave(combatant_id: String, combatant_name: String, target_name: String)

## Emitted when entering interactive cleave target selection. Host should show
## the Skip Cleave button and listen for entity clicks on the highlighted targets.
signal cleave_selection_started(combatant_id: String)

## Map should highlight reachable cells for movement.
signal highlight_reachable(cells: Array, color: Color)

## Map should highlight attack targets.
signal highlight_targets(entity_ids: Array)

## Map should clear all highlights.
signal clear_highlights_requested()

## Map should mark active combatant token.
signal active_token_changed(entity_id: String)

## Map should move a token to a new cell.
signal token_moved(entity_id: String, to_cell: Vector2i)

## After a move sub-action, disable the Move button but keep turn active.
signal move_completed()

## PC chose Sheathe & Draw — host should show weapon selection popup.
signal weapon_switch_requested(combatant_id: String, weapons: Array, has_moved: bool)

## Weapon switch completed — host should refresh stat summary.
signal weapon_switched(combatant_id: String)

## Request the host to build and show a context menu at the given position.
signal context_menu_requested(combatant_id: String, target_cell: Vector2i, screen_pos: Vector2)

## Proactive movement range display on entering PC_AWAITING_INPUT.
## walk_cells: cells within combat movement (blue).
## run_cells: cells within 3x movement (green).
## engagement_zones: enemy-adjacent cells (red).
signal movement_range_display(walk_cells: Array, run_cells: Array, engagement_zones: Array)


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _controller: CombatController = null
var _state: int = State.IDLE
var _current_pc_id: String = ""
var _selected_action: String = ""
var _has_moved_this_turn: bool = false
var _cleave_targets: Array = []
var _cleave_move_cells: Array = []
var _cleave_move_available: bool = false

## Cached initiative order for the HUD.
var _initiative_display: Array = []


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func setup(controller: CombatController) -> void:
	_controller = controller
	_state = State.IDLE
	# Forward cleave events from the controller to the UI
	if not controller.cleave_triggered.is_connected(_on_controller_cleave_triggered):
		controller.cleave_triggered.connect(_on_controller_cleave_triggered)


func _on_controller_cleave_triggered(combatant_id: String, target_id: String) -> void:
	# Emit a CLEAVE log entry so the panel shows "X may cleave into Y!"
	log_entry.emit({
		"type": 10,  # CombatLog.EntryType.CLEAVE
		"round": _controller.round_number,
		"actor_id": combatant_id,
		"actor_name": _resolve_name(combatant_id),
		"target_id": target_id,
		"target_name": _resolve_name(target_id),
		"data": {"note": "may_cleave"},
		"timestamp": 0,
	})
	may_cleave.emit(combatant_id, _resolve_name(combatant_id), _resolve_name(target_id))


# ---------------------------------------------------------------------------
# Core loop
# ---------------------------------------------------------------------------

## Advance the combat one step. Call this to kick off combat and after
## each player input. Returns the raw CombatController result dict.
func advance() -> Dictionary:
	if _controller == null:
		return {"status": "error", "message": "no controller"}
	if _state == State.COMBAT_OVER:
		return {"status": "combat_over"}

	_state = State.ADVANCING
	var result := _controller.advance()
	var status: String = result.get("status", "")

	match status:
		"combat_started":
			# Auto-advance past the start marker
			return advance()

		"round_started":
			_state = State.DECLARATION_PHASE
			var alive_pcs: Array = _get_alive_pcs()
			# Log round start
			log_entry.emit({
				"type": 0, "round": result.get("round_number", 0),
				"actor_id": "", "target_id": "", "data": {}, "timestamp": 0,
			})
			show_declaration_requested.emit(alive_pcs)
			return result

		"initiative_rolled":
			_state = State.ADVANCING
			_cache_initiative_display(result.get("initiative_order", []))
			initiative_updated.emit(_initiative_display)
			# Log initiative with full roll breakdown and display names
			var init_with_names: Array = []
			for ie in result.get("initiative_order", []):
				var named_entry: Dictionary = ie.duplicate()
				named_entry["display_name"] = _resolve_name(ie.get("combatant_id", ""))
				init_with_names.append(named_entry)
			log_entry.emit({
				"type": 12, "round": result.get("round_number", 0),
				"actor_id": "", "target_id": "",
				"data": {"initiative_order": init_with_names},
				"timestamp": 0,
			})
			auto_advance_requested.emit()
			return result

		"waiting_for_pc_action":
			var cid: String = result.get("combatant_id", "")
			_current_pc_id = cid
			_selected_action = ""
			_has_moved_this_turn = false
			_state = State.PC_AWAITING_INPUT
			clear_highlights_requested.emit()
			active_token_changed.emit(cid)
			pc_turn_started.emit(cid)
			_show_proactive_movement_overlay()
			return result

		"action_resolved":
			_emit_action_log(result)
			action_resolved.emit(result)
			_update_initiative_hp()

			# Check for cleave eligibility — pause for player input instead of advancing
			var inner_res: Dictionary = result.get("result", {})
			if inner_res.get("cleave_eligible", false) \
					and result.get("combatant_id", "") == _current_pc_id:
				_enter_cleave_selection(
					inner_res.get("cleave_targets", []),
					inner_res.get("cleave_move_available", false),
					inner_res.get("cleave_move_cells", []))
				return result

			# Request deferred advance so UI can render the action result
			auto_advance_requested.emit()
			return result

		"round_ended":
			# Request deferred advance so UI can render round-end state
			auto_advance_requested.emit()
			return result

		"combat_over":
			_state = State.COMBAT_OVER
			clear_highlights_requested.emit()
			active_token_changed.emit("")
			# Log combat end
			log_entry.emit({
				"type": 11, "round": result.get("rounds", 0),
				"actor_id": "", "target_id": "",
				"data": {"result": result.get("result", "unknown")},
				"timestamp": 0,
			})
			combat_ended.emit(result)
			return result

	# Unknown status — keep advancing
	return result


# ---------------------------------------------------------------------------
# Player input handlers (called by the overlay/screen)
# ---------------------------------------------------------------------------

## Called when the declaration overlay confirms. Submits each declaration
## to the controller, then advances past declaration phase.
func on_declarations_confirmed(declarations: Array) -> void:
	if _state != State.DECLARATION_PHASE:
		return
	for decl in declarations:
		var cid: String = decl.get("combatant_id", "")
		var dtype: String = decl.get("declaration_type", "")
		if not cid.is_empty() and not dtype.is_empty():
			_controller.submit_declaration(cid, dtype)
			log_entry.emit({
				"type": 13, "round": _controller.round_number,
				"actor_id": cid, "actor_name": _resolve_name(cid),
				"target_id": "", "target_name": "",
				"data": {"declaration_type": dtype}, "timestamp": 0,
			})
	# Advance past declaration into initiative
	advance()


## Called when a quick-action button is pressed (Pass, Delay from the quick bar).
func on_action_button(action_id: String) -> void:
	if _state != State.PC_AWAITING_INPUT and _state != State.PC_CONTEXT_MENU_OPEN:
		return

	match action_id:
		"delay":
			clear_highlights_requested.emit()
			_controller.submit_pc_action(_current_pc_id, "pass",
				{"note": "delayed action"})
			advance()

		"pass":
			clear_highlights_requested.emit()
			_controller.submit_pc_action(_current_pc_id, "pass")
			advance()


## Called when the player right-clicks a cell during their turn.
## The host scene should call this from the renderer's cell_right_clicked signal.
func on_cell_right_clicked(target_cell: Vector2i, screen_pos: Vector2) -> void:
	if _state != State.PC_AWAITING_INPUT:
		return
	_state = State.PC_CONTEXT_MENU_OPEN
	context_menu_requested.emit(_current_pc_id, target_cell, screen_pos)


## Called when the player selects an option from the combat context menu.
## The host scene should connect the menu's option_selected signal to this.
func on_context_action(action_data: Dictionary) -> void:
	if _state != State.PC_CONTEXT_MENU_OPEN:
		return

	var action_type: String = action_data.get("action_type", "")

	match action_type:
		"cancel":
			_state = State.PC_AWAITING_INPUT
			return

		"submenu_back":
			# Handled by the menu scene itself — should not reach here
			return

		"pass":
			clear_highlights_requested.emit()
			_controller.submit_pc_action(_current_pc_id, "pass")
			advance()

		"delay":
			clear_highlights_requested.emit()
			_controller.submit_pc_action(_current_pc_id, "pass",
				{"note": "delayed action"})
			advance()

		"move_here", "run_here":
			clear_highlights_requested.emit()
			var cell: Vector2i = action_data.get("cell", Vector2i(-1, -1))
			_controller.submit_pc_action(_current_pc_id, action_type,
				{"target_cell": cell})
			var move_result := _controller.advance()
			_emit_action_log(move_result)
			action_resolved.emit(move_result)
			# Enter facing-selection state
			_state = State.PC_SELECTING_FACING
			_enter_facing_selection()

		"attack_melee", "attack_ranged":
			clear_highlights_requested.emit()
			var target_id: String = action_data.get("target_id", "")
			_controller.submit_pc_action(_current_pc_id, action_type,
				{"target_id": target_id})
			advance()

		"charge":
			clear_highlights_requested.emit()
			var target_id: String = action_data.get("target_id", "")
			_controller.submit_pc_action(_current_pc_id, "charge",
				{"target_id": target_id})
			advance()

		"backstab":
			clear_highlights_requested.emit()
			var target_id: String = action_data.get("target_id", "")
			_controller.submit_pc_action(_current_pc_id, "backstab",
				{"target_id": target_id})
			advance()

		"fighting_withdrawal", "full_retreat":
			clear_highlights_requested.emit()
			# If Skirmishing on-turn declaration, submit the declaration first
			var combatant = _controller.get_combatant(_current_pc_id)
			if combatant != null and combatant.declared_defensive_movement.is_empty():
				_controller.submit_declaration(_current_pc_id, action_type)
			var cell: Vector2i = action_data.get("cell", Vector2i(-1, -1))
			_controller.submit_pc_action(_current_pc_id, action_type,
				{"target_cell": cell})
			var move_result := _controller.advance()
			_emit_action_log(move_result)
			action_resolved.emit(move_result)
			_state = State.PC_SELECTING_FACING
			_enter_facing_selection()

		"set_against_charge":
			_controller.submit_declaration(_current_pc_id, "set_against_charge")
			log_entry.emit({
				"type": 13, "round": _controller.round_number,
				"actor_id": _current_pc_id, "actor_name": _resolve_name(_current_pc_id),
				"target_id": "", "target_name": "",
				"data": {"declaration_type": "set_against_charge"}, "timestamp": 0,
			})
			_state = State.PC_AWAITING_INPUT

		"switch_weapon":
			var sw_combatant = _controller.get_combatant(_current_pc_id)
			if sw_combatant == null or not sw_combatant.is_character:
				_state = State.PC_AWAITING_INPUT
				return
			var sw_weapons := _get_switchable_weapons(sw_combatant)
			var current_wpn: Dictionary = sw_combatant.get_equipped_weapon()
			var has_weapon := not current_wpn.is_empty()
			if sw_weapons.is_empty() and not has_weapon:
				log_entry.emit({
					"type": 4, "round": _controller.round_number,
					"actor_id": _current_pc_id,
					"actor_name": _resolve_name(_current_pc_id),
					"target_id": "", "target_name": "",
					"data": {"note": "No other weapons available"},
					"timestamp": 0,
				})
				_state = State.PC_AWAITING_INPUT
				return
			_state = State.PC_SELECTING_WEAPON
			weapon_switch_requested.emit(_current_pc_id, sw_weapons, _has_moved_this_turn)

		var maneuver_action when maneuver_action.begins_with("maneuver_") or \
				maneuver_action.begins_with("brawl_"):
			clear_highlights_requested.emit()
			var target_id: String = action_data.get("target_id", "")
			_controller.submit_pc_action(_current_pc_id, action_type,
				{"target_id": target_id})
			advance()

		"use_item", "light_torch", "light_lantern", "stand_up", "drop_item":
			clear_highlights_requested.emit()
			_controller.submit_pc_action(_current_pc_id, action_type,
				{"character_id": action_data.get("character_id", _current_pc_id)})
			advance()

		"check_status", "carry", "loot", "coup_de_grace":
			clear_highlights_requested.emit()
			var target_id: String = action_data.get("target_id", "")
			_controller.submit_pc_action(_current_pc_id, action_type,
				{"target_id": target_id})
			advance()

		"heal", "trade":
			clear_highlights_requested.emit()
			var target_id: String = action_data.get("target_id", "")
			_controller.submit_pc_action(_current_pc_id, action_type,
				{"target_id": target_id})
			advance()

		_:
			# Unknown action — return to awaiting input
			_state = State.PC_AWAITING_INPUT


## Called when the context menu is dismissed without selection.
func on_context_menu_cancelled() -> void:
	if _state == State.PC_CONTEXT_MENU_OPEN:
		_state = State.PC_AWAITING_INPUT


## Called when a cell is clicked on the map during facing selection or cleave.
func on_cell_targeted(pos: Vector2i) -> void:
	if _state == State.PC_SELECTING_FACING:
		# Player clicked an adjacent cell to choose facing
		var combatant = _controller.get_combatant(_current_pc_id)
		if combatant == null:
			return
		var origin: Vector2i = combatant.grid_position
		if IsometricGrid.chebyshev_distance(origin, pos) != 1:
			return  # Only accept adjacent cells
		combatant.facing = _direction_vector(origin, pos)
		token_facing_preview.emit(_current_pc_id, combatant.facing)
		return

	if _state == State.PC_SELECTING_CLEAVE_TARGET:
		# Cell click during cleave: only valid if move is available and cell is highlighted
		if not _cleave_move_available:
			return
		if pos not in _cleave_move_cells:
			return
		clear_highlights_requested.emit()
		_cleave_targets.clear()
		_cleave_move_cells.clear()
		_cleave_move_available = false
		_controller.submit_pc_action(_current_pc_id, "cleave_move", {"target_cell": pos})
		advance()
		return


func _enter_facing_selection() -> void:
	var combatant = _controller.get_combatant(_current_pc_id)
	if combatant == null:
		return
	var origin: Vector2i = combatant.grid_position
	var adj := IsometricGrid.get_neighbors(origin)
	var typed_cells: Array[Vector2i] = []
	for c in adj:
		typed_cells.append(c)
	highlight_reachable.emit(typed_cells, Color(0.9, 0.9, 0.2, 0.20))
	facing_selection_started.emit(_current_pc_id)


## Called when the player clicks the "Confirm Move" button after choosing facing.
func on_confirm_move() -> void:
	if _state != State.PC_SELECTING_FACING:
		return
	clear_highlights_requested.emit()
	_has_moved_this_turn = true
	_state = State.PC_AWAITING_INPUT
	pc_turn_started.emit(_current_pc_id)
	move_completed.emit()
	_show_proactive_movement_overlay()


func _direction_vector(from_pos: Vector2i, to_pos: Vector2i) -> Vector2i:
	return Vector2i(signi(to_pos.x - from_pos.x), signi(to_pos.y - from_pos.y))


## Called when an entity token is clicked during attack-target or cleave selection.
func on_entity_targeted(entity_id: String) -> void:
	if _state == State.PC_SELECTING_CLEAVE_TARGET:
		# Only accept clicks on valid cleave targets
		if entity_id not in _cleave_targets:
			return
		clear_highlights_requested.emit()
		_cleave_targets.clear()
		_controller.submit_pc_action(_current_pc_id, "cleave", {"target_id": entity_id})
		advance()
		return

	# Left-click on entity during PC turn = selection only (no action).
	# All attack actions go through the right-click context menu.


## Called when the player clicks "Skip Cleave" to decline the cleave attempt.
func on_skip_cleave() -> void:
	if _state != State.PC_SELECTING_CLEAVE_TARGET:
		return
	clear_highlights_requested.emit()
	_cleave_targets.clear()
	_controller.submit_pc_action(_current_pc_id, "skip_cleave")
	advance()


func _enter_cleave_selection(targets: Array, move_available: bool = false, move_cells: Array = []) -> void:
	_state = State.PC_SELECTING_CLEAVE_TARGET
	_cleave_targets = targets.duplicate()
	_cleave_move_available = move_available
	_cleave_move_cells = move_cells.duplicate()

	# Highlight enemy targets (red rings)
	var typed_targets: Array[String] = []
	for t in targets:
		typed_targets.append(t)
	highlight_targets.emit(typed_targets)

	# Highlight valid 5ft step cells (yellow) if the move is still available
	if move_available and not move_cells.is_empty():
		var typed_cells: Array[Vector2i] = []
		for c in move_cells:
			typed_cells.append(c)
		highlight_reachable.emit(typed_cells, Color(0.9, 0.9, 0.2, 0.30))

	cleave_selection_started.emit(_current_pc_id)


## Cancel current selection — return to awaiting input.
func on_cancel() -> void:
	if _state == State.PC_CONTEXT_MENU_OPEN or \
	   _state == State.PC_SELECTING_WEAPON:
		clear_highlights_requested.emit()
		_state = State.PC_AWAITING_INPUT
		_selected_action = ""
		pc_turn_started.emit(_current_pc_id)
		_show_proactive_movement_overlay()


## Called by the overlay/screen when the player picks a weapon from the popup.
func on_weapon_selected(weapon_item: Dictionary) -> void:
	if _state != State.PC_SELECTING_WEAPON:
		return

	var is_stow_only: bool = weapon_item.get("stow_only", false)
	var params: Dictionary = {"new_weapon_item": weapon_item, "stow_only": is_stow_only}

	_controller.submit_pc_action(_current_pc_id, "switch_weapon", params)
	var result := _controller.advance()

	_emit_action_log(result)
	action_resolved.emit(result)
	weapon_switched.emit(_current_pc_id)

	var inner_result: Dictionary = result.get("result", {})
	if inner_result.get("continues_turn", false):
		# Cost was movement — player can still attack this turn
		_has_moved_this_turn = true
		_state = State.PC_AWAITING_INPUT
		pc_turn_started.emit(_current_pc_id)
		move_completed.emit()
		_show_proactive_movement_overlay()
	else:
		# Cost was attack — turn is over
		auto_advance_requested.emit()


## Returns the current UI state.
func get_state() -> int:
	return _state


## Returns the CombatController (for direct queries).
func get_controller() -> CombatController:
	return _controller


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _get_alive_pcs() -> Array:
	var result: Array = []
	if _controller == null:
		return result
	for c in _controller.roster.get_alive_on_side(Combatant.Side.PARTY):
		result.append({
			"combatant_id": c.id,
			"display_name": c.display_name,
		})
	return result


func _cache_initiative_display(init_order: Array) -> void:
	_initiative_display.clear()
	for entry in init_order:
		var cid: String = entry.get("combatant_id", "")
		var c = _controller.roster.get_by_id(cid)
		if c == null:
			continue
		_initiative_display.append({
			"combatant_id": cid,
			"display_name": c.display_name,
			"side": c.side,
			"initiative_total": entry.get("total", 0),
			"hp_current": c.get_hp_current(),
			"hp_max": c.get_hp_max(),
			"is_alive": c.is_alive(),
			"is_fleeing": c.is_fleeing,
			"is_surprised": false,  # Set by surprise system when implemented
		})


func _update_initiative_hp() -> void:
	## Refresh HP values in the cached initiative display.
	for entry in _initiative_display:
		var cid: String = entry.get("combatant_id", "")
		var c = _controller.roster.get_by_id(cid)
		if c == null:
			continue
		entry["hp_current"] = c.get_hp_current()
		entry["is_alive"] = c.is_alive()
		entry["is_fleeing"] = c.is_fleeing
	initiative_updated.emit(_initiative_display)


func _emit_action_log(result: Dictionary) -> void:
	## Emit log entries for the resolved action so the CombatLogPanel can display them.
	var action_str: String = result.get("action", "")
	var actor_id: String = result.get("combatant_id", "")
	var action_result: Dictionary = result.get("result", {})

	if action_str.is_empty():
		return

	var target_id: String = action_result.get("target_id", "")
	var entry := {
		"type": _action_to_log_type(action_str),
		"round": _controller.round_number,
		"actor_id": actor_id,
		"actor_name": _resolve_name(actor_id),
		"target_id": target_id,
		"target_name": _resolve_name(target_id),
		"data": action_result,
		"timestamp": 0,
	}
	log_entry.emit(entry)


func _highlight_range_bands(origin: Vector2i, short_r: int, medium_r: int, long_r: int) -> void:
	## Emit highlight layers for ranged weapon range bands.
	## Short = green, Medium = orange, Long = yellow.
	if _controller == null or _controller.tactical_map == null:
		return
	var map: TacticalMapData = _controller.tactical_map
	var short_cells: Array[Vector2i] = []
	var medium_cells: Array[Vector2i] = []
	var long_cells: Array[Vector2i] = []

	for cell_pos in map._cells.keys():
		var dist: int = IsometricGrid.chebyshev_distance(origin, cell_pos)
		if dist == 0:
			continue
		if dist <= short_r:
			short_cells.append(cell_pos)
		elif dist <= medium_r:
			medium_cells.append(cell_pos)
		elif dist <= long_r:
			long_cells.append(cell_pos)

	if not short_cells.is_empty():
		highlight_reachable.emit(short_cells, Color(0.2, 0.8, 0.3, 0.12))
	if not medium_cells.is_empty():
		highlight_reachable.emit(medium_cells, Color(0.9, 0.6, 0.1, 0.12))
	if not long_cells.is_empty():
		highlight_reachable.emit(long_cells, Color(0.9, 0.9, 0.2, 0.12))


func _resolve_name(combatant_id: String) -> String:
	## Returns the display_name for a combatant ID, or the ID itself as fallback.
	if combatant_id.is_empty() or _controller == null:
		return combatant_id
	var c = _controller.roster.get_by_id(combatant_id)
	if c != null:
		return c.display_name
	return combatant_id


func _action_to_log_type(action_id: String) -> int:
	match action_id:
		"attack_melee", "attack_ranged", "backstab", "charge", "coup_de_grace":
			return 1  # CombatLog.EntryType.ATTACK
		"cast_spell":
			return 3  # SPELL
		"move", "move_here", "run_here":
			return 4  # MOVEMENT
		"fighting_withdrawal", "full_retreat":
			return 4  # MOVEMENT
		"switch_weapon", "stand_up":
			return 4  # MOVEMENT (movement-type actions)
		var maneuver when maneuver.begins_with("maneuver_") or \
				maneuver.begins_with("brawl_"):
			return 5  # MANEUVER
		_:
			return 4  # Default to movement


func _show_proactive_movement_overlay() -> void:
	## Show movement range overlay when entering PC_AWAITING_INPUT.
	## Blue = walkable, green = running, red = engagement zones.
	if _controller == null or _controller.movement_resolver == null:
		return
	var combatant = _controller.get_combatant(_current_pc_id)
	if combatant == null:
		return

	var mr: MovementResolver = _controller.movement_resolver
	var engaged: bool = mr.is_engaged(combatant)
	var has_defensive: bool = not combatant.declared_defensive_movement.is_empty()
	var has_skirmishing: bool = combatant.has_proficiency("skirmishing")

	# No movement overlay for engaged entities without declaration or Skirmishing
	if engaged and not has_defensive and not has_skirmishing:
		return

	if combatant.has_moved_this_round:
		return

	# Walk cells (blue)
	var walk_cells := mr.get_cells_reachable(combatant, combatant.get_combat_movement_cells())
	if not walk_cells.is_empty():
		var typed_walk: Array[Vector2i] = []
		for c in walk_cells:
			typed_walk.append(c)
		highlight_reachable.emit(typed_walk, Color(0.2, 0.6, 1.0, 0.15))

	# Running cells (green) — beyond walk range, within 3x
	var run_cells := mr.get_cells_reachable(combatant, combatant.get_combat_movement_cells() * 3)
	var walk_set: Dictionary = {}
	for c in walk_cells:
		walk_set[c] = true
	var run_only: Array[Vector2i] = []
	for c in run_cells:
		if not walk_set.has(c):
			run_only.append(c)
	if not run_only.is_empty():
		highlight_reachable.emit(run_only, Color(0.3, 0.8, 0.3, 0.10))

	# Engagement zones (red) — cells adjacent to enemies
	var engagement_cells: Array[Vector2i] = []
	var enemy_side: int = Combatant.Side.ENEMY if combatant.is_pc_side() else Combatant.Side.PARTY
	for enemy in _controller.roster.get_alive_on_side(enemy_side):
		var epos: Vector2i = mr.get_grid_position(enemy)
		if epos == Vector2i(-1, -1):
			continue
		for n in IsometricGrid.get_neighbors(epos):
			if n not in engagement_cells:
				engagement_cells.append(n)
	if not engagement_cells.is_empty():
		highlight_reachable.emit(engagement_cells, Color(0.9, 0.2, 0.2, 0.12))

	# Emit the combined display signal
	movement_range_display.emit(walk_cells, run_only, engagement_cells)


func _get_switchable_weapons(combatant: Combatant) -> Array:
	## Returns inventory weapon rows that the combatant could switch to.
	## Excludes the currently equipped main-hand weapon.
	if not combatant.is_character or combatant._character == null:
		return []
	var char_id: String = combatant._character.id
	var all_items: Array = CampaignRepository.get_inventory_items(char_id)
	var current_item_id: String = combatant.get_equipped_weapon().get("item_id", "")
	var result: Array = []
	for item in all_items:
		if item.get("item_category", "") != "weapon":
			continue
		# Skip the currently equipped main-hand weapon
		if item.get("id", "") == current_item_id and not current_item_id.is_empty():
			continue
		# Skip items equipped in other slots (e.g. off-hand)
		if int(item.get("is_equipped", 0)) == 1 and item.get("slot", "") != "pack":
			continue
		result.append(item)
	return result
