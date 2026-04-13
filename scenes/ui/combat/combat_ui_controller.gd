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
	PC_SELECTING_ACTION,           ## PC turn — action button panel visible
	PC_SELECTING_MOVE_TARGET,      ## PC chose Move — waiting for cell click
	PC_SELECTING_FACING,           ## After move, waiting for facing click + Confirm Move
	PC_SELECTING_ATTACK_TARGET,    ## PC chose Attack — waiting for entity click
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
			_state = State.PC_SELECTING_ACTION
			clear_highlights_requested.emit()
			active_token_changed.emit(cid)
			pc_turn_started.emit(cid)
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


## Called when an action button is pressed in the ActionButtonPanel.
func on_action_button(action_id: String) -> void:
	if _state != State.PC_SELECTING_ACTION:
		return

	_selected_action = action_id

	match action_id:
		"move":
			_state = State.PC_SELECTING_MOVE_TARGET
			var cells := _controller.get_reachable_cells(_current_pc_id)
			var typed_cells: Array[Vector2i] = []
			for c in cells:
				typed_cells.append(c)
			highlight_reachable.emit(typed_cells, Color(0.2, 0.6, 1.0, 0.25))

		"attack_melee":
			# Check for valid melee targets before entering target selection
			var melee_targets := _controller.get_melee_targets(_current_pc_id)
			if melee_targets.is_empty():
				log_entry.emit({
					"type": 4, "round": _controller.round_number,
					"actor_id": _current_pc_id,
					"actor_name": _resolve_name(_current_pc_id),
					"target_id": "", "target_name": "",
					"data": {"note": "No adjacent enemies for melee attack"},
					"timestamp": 0,
				})
				return
			_state = State.PC_SELECTING_ATTACK_TARGET
			# Highlight adjacent cells as range overlay + enemy tokens as targets
			var combatant = _controller.get_combatant(_current_pc_id)
			if combatant != null and _controller.movement_resolver != null:
				var pos: Vector2i = _controller.movement_resolver.get_grid_position(combatant)
				var adj_cells := IsometricGrid.get_neighbors(pos)
				var typed_cells: Array[Vector2i] = []
				for c in adj_cells:
					typed_cells.append(c)
				highlight_reachable.emit(typed_cells, Color(0.9, 0.3, 0.3, 0.15))
			var typed_melee_targets: Array[String] = []
			for t in melee_targets:
				typed_melee_targets.append(t)
			highlight_targets.emit(typed_melee_targets)

		"attack_ranged":
			# Check for valid ranged targets before entering target selection
			var ranged_targets := _controller.get_ranged_targets(_current_pc_id)
			if ranged_targets.is_empty():
				log_entry.emit({
					"type": 4, "round": _controller.round_number,
					"actor_id": _current_pc_id,
					"actor_name": _resolve_name(_current_pc_id),
					"target_id": "", "target_name": "",
					"data": {"note": "No enemies in range for ranged attack"},
					"timestamp": 0,
				})
				return
			_state = State.PC_SELECTING_ATTACK_TARGET
			# Show range-band overlay (short=green, medium=orange, long=yellow)
			var combatant_r = _controller.get_combatant(_current_pc_id)
			if combatant_r != null and _controller.movement_resolver != null:
				var pos_r: Vector2i = _controller.movement_resolver.get_grid_position(combatant_r)
				var ranges: Dictionary = combatant_r.get_weapon_ranges()
				var short_cells: int = int(ranges.get("short", 0)) / 5
				var medium_cells: int = int(ranges.get("medium", 0)) / 5
				var long_cells: int = int(ranges.get("long", 0)) / 5
				_highlight_range_bands(pos_r, short_cells, medium_cells, long_cells)
			# Highlight enemy tokens in range as targets
			var typed_ranged_targets: Array[String] = []
			for t in ranged_targets:
				typed_ranged_targets.append(t)
			highlight_targets.emit(typed_ranged_targets)

		"switch_weapon":
			# Sheathe & Draw — query inventory for switchable weapons
			var sw_combatant = _controller.get_combatant(_current_pc_id)
			if sw_combatant == null or not sw_combatant.is_character:
				return
			var sw_weapons := _get_switchable_weapons(sw_combatant)
			# Also allow "go unarmed" if currently armed
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
				return
			_state = State.PC_SELECTING_WEAPON
			weapon_switch_requested.emit(_current_pc_id, sw_weapons, _has_moved_this_turn)

		"delay":
			# Placeholder: treat delay as pass for now
			# Future: show initiative count dropdown dialog
			clear_highlights_requested.emit()
			_controller.submit_pc_action(_current_pc_id, "pass",
				{"note": "delayed action"})
			advance()

		"pass":
			clear_highlights_requested.emit()
			_controller.submit_pc_action(_current_pc_id, "pass")
			advance()


## Called when a cell is clicked on the map during move-target or facing selection.
func on_cell_targeted(pos: Vector2i) -> void:
	if _state == State.PC_SELECTING_MOVE_TARGET:
		clear_highlights_requested.emit()

		# Submit the move action
		_controller.submit_pc_action(_current_pc_id, "move", {"target_cell": pos})
		var move_result := _controller.advance()

		# Log the move
		_emit_action_log(move_result)
		action_resolved.emit(move_result)

		# Enter facing-selection state (do NOT end the turn yet)
		_state = State.PC_SELECTING_FACING
		_enter_facing_selection()
		return

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
	_state = State.PC_SELECTING_ACTION
	pc_turn_started.emit(_current_pc_id)
	move_completed.emit()


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

	if _state != State.PC_SELECTING_ATTACK_TARGET:
		return
	clear_highlights_requested.emit()
	var action_id := _selected_action  # "attack_melee" or "attack_ranged"
	_controller.submit_pc_action(_current_pc_id, action_id, {"target_id": entity_id})
	advance()


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


## Cancel current target/weapon selection — return to action selection.
func on_cancel() -> void:
	if _state == State.PC_SELECTING_MOVE_TARGET or \
	   _state == State.PC_SELECTING_ATTACK_TARGET or \
	   _state == State.PC_SELECTING_WEAPON:
		clear_highlights_requested.emit()
		_state = State.PC_SELECTING_ACTION
		_selected_action = ""
		pc_turn_started.emit(_current_pc_id)


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
		_state = State.PC_SELECTING_ACTION
		pc_turn_started.emit(_current_pc_id)
		move_completed.emit()
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
		"attack_melee", "attack_ranged":
			return 1  # CombatLog.EntryType.ATTACK
		"cast_spell":
			return 3  # SPELL
		"move":
			return 4  # MOVEMENT
		"fighting_withdrawal", "full_retreat":
			return 4  # MOVEMENT
		"switch_weapon":
			return 4  # MOVEMENT (sheathe & draw is a movement-type action)
		_:
			return 4  # Default to movement


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
