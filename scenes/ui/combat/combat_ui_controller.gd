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
	PC_SELECTING_READY_CELL,       ## PC chose "Ready at cell..." — waiting for cell click
	PC_SPELL_TARGETING,            ## PC declared a cast — targeting controller is live
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

## Emitted when entering Ready-at-cell selection. Host should show a Cancel
## button. Clicking one of the highlighted cells submits the Ready Attack.
signal ready_cell_selection_started(combatant_id: String, weapon: String)

## Map should highlight reachable cells for movement.
signal highlight_reachable(cells: Array, color: Color)

## Map should highlight attack targets.
signal highlight_targets(entity_ids: Array)

## Map should highlight targets by HD-budget band (Session 2.9).
## Bands dict keys: "green" (eligible + under-budget), "yellow" (would over-spend),
## "red" (over per-target HD cap), "selected" (already chosen).
signal highlight_targets_by_band(bands: Dictionary)

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
signal context_menu_requested(combatant_id: String, target_cell: Vector3i, screen_pos: Vector2)

## Proactive movement range display on entering PC_AWAITING_INPUT.
## walk_cells: cells within combat movement (blue).
## run_cells: cells within 3x movement (green).
## engagement_zones: enemy-adjacent cells (red).
signal movement_range_display(walk_cells: Array, run_cells: Array, engagement_zones: Array)

## Emitted when a PC's spell-targeting begins. Host can show the HdTallyPanel
## or the AoePreviewOverlay depending on `kind`.
##   kind: "auto" | "single_entity" | "area_at_point" | "hd_budget"
##   spell_name: human-readable display
signal spell_targeting_started(combatant_id: String, spell_name: String, kind: String)

## Emitted when AoE-anchored area becomes available for confirmation.
signal spell_aoe_preview(spell_name: String, affected_ids: Array, ally_ids: Array)

## Emitted when HD-budget targeting state changes (selection_changed).
signal spell_hd_tally_updated(spell_name: String, controller: TargetingController)

## Emitted when the spell-targeting flow ends (commit or cancel).
signal spell_targeting_ended()

## Emitted for layered cell highlighting (Session 2.9). Each layer is {cells, color}.
## Used for AoE ally-vs-enemy shading: enemy-occupied cells in red,
## ally-occupied cells in red-orange, empty AoE cells in faint orange.
signal highlight_cells_layered(layers: Array)


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _controller: CombatController = null
var _state: int = State.IDLE
var _current_pc_id: String = ""

## Class-level reference to the most recently-instantiated controller, used by
## the Management Notebook's openability gate (gdd-management-notebook.md §10).
## Set in setup(); cleared when combat ends. NotebookState / Notebook check
## CombatUIController.notebook_open_allowed() before opening during combat.
static var active_instance: CombatUIController = null

## States in which the player is in control and the notebook may safely open.
## All non-PC-input states (IDLE, ADVANCING, ENEMY_ACTING, COMBAT_OVER) block
## opening to avoid interrupt-related state bugs. DECLARATION_PHASE is
## included because the player is selecting declarations during it.
const PC_INPUT_STATES := [
	State.DECLARATION_PHASE,
	State.PC_AWAITING_INPUT,
	State.PC_CONTEXT_MENU_OPEN,
	State.PC_SELECTING_FACING,
	State.PC_SELECTING_CLEAVE_TARGET,
	State.PC_SELECTING_WEAPON,
	State.PC_SELECTING_READY_CELL,
	State.PC_SPELL_TARGETING,
]
var _selected_action: String = ""
var _has_moved_this_turn: bool = false
var _cleave_targets: Array = []
var _cleave_move_cells: Array = []
var _cleave_move_available: bool = false

## During PC_SELECTING_READY_CELL, the set of cells the player may click.
var _ready_cell_options: Array = []

## During PC_SELECTING_READY_CELL, "melee" or "ranged" — picks the fallback
## attack path at fire time.
var _ready_cell_weapon: String = ""

## Spell-targeting state. Live during PC_SPELL_TARGETING — drives the
## TargetingController flow from waiting_for_pc_spell_target through commit.
var _targeting_controller: TargetingController = null
var _targeting_spell_payload: Dictionary = {}
var _targeting_caster_id: String = ""
var _targeting_kind: String = ""  # "auto" | "single_entity" | "area_at_point" | "hd_budget"
var _targeting_anchor_set: bool = false  # true after player clicks anchor for area_at_point

## Cached initiative order for the HUD.
var _initiative_display: Array = []


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func setup(controller: CombatController) -> void:
	_controller = controller
	_state = State.IDLE
	active_instance = self
	# Forward cleave events from the controller to the UI
	if not controller.cleave_triggered.is_connected(_on_controller_cleave_triggered):
		controller.cleave_triggered.connect(_on_controller_cleave_triggered)


## Returns true when the player is in a state where opening the Management
## Notebook is safe (gdd-management-notebook.md §10.1). Non-PC states
## (enemy resolution, advancing, combat over) return false.
func is_pc_awaiting_input() -> bool:
	return PC_INPUT_STATES.has(_state)


## Class-level convenience for the Notebook's gate. Returns true when there
## is no active combat OR the active combat is awaiting player input.
static func notebook_open_allowed() -> bool:
	if active_instance == null:
		return true
	return active_instance.is_pc_awaiting_input()


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

		"waiting_for_pc_spell_target":
			# Caster's tick fired with a declared spell. Build a TargetingController
			# from the spell payload, register candidates from the roster, and
			# either auto-resolve (self / area_from_caster / caster_and_radius)
			# or wait for player click input.
			var cid: String = result.get("combatant_id", "")
			_current_pc_id = cid
			_state = State.PC_SPELL_TARGETING
			clear_highlights_requested.emit()
			active_token_changed.emit(cid)
			_enter_spell_targeting(cid)
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
			if active_instance == self:
				active_instance = null
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
func on_cell_right_clicked(target_cell: Vector3i, screen_pos: Vector2) -> void:
	# Right-click while picking a Ready cell cancels the selection.
	if _state == State.PC_SELECTING_READY_CELL:
		on_cancel()
		return
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

		"ready_attack":
			clear_highlights_requested.emit()
			var trigger_type: String = action_data.get("trigger_type", "melee_adjacent")
			_controller.submit_pc_action(_current_pc_id, "ready_attack",
				{"character_id": action_data.get("character_id", _current_pc_id),
				 "trigger_type": trigger_type})
			advance()

		"ready_attack_cell":
			# Player must pick a cell — enter cell-selection state.
			var weapon: String = action_data.get("trigger_weapon", "melee")
			_enter_ready_cell_selection(weapon)

		"ready_attack_submenu":
			# Parent submenu entry — only reached when disabled/no submenu; treat as cancel.
			_state = State.PC_AWAITING_INPUT

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


func _enter_ready_cell_selection(weapon: String) -> void:
	_ready_cell_weapon = weapon
	_ready_cell_options = _build_ready_cell_candidates(weapon)
	if _ready_cell_options.is_empty():
		# Nothing to target — bail silently and return to input.
		_ready_cell_weapon = ""
		_state = State.PC_AWAITING_INPUT
		return
	_state = State.PC_SELECTING_READY_CELL
	# Highlight candidate cells (orange — distinct from move/cleave colors).
	var typed_cells: Array[Vector3i] = []
	for c: Vector3i in _ready_cell_options:
		typed_cells.append(c)
	highlight_reachable.emit(typed_cells, Color(1.0, 0.55, 0.1, 0.30))
	ready_cell_selection_started.emit(_current_pc_id, weapon)


func _build_ready_cell_candidates(weapon: String) -> Array:
	## Return the set of cells (Vector3i) the player may pick as a Ready trigger.
	## Melee: same-level neighbors of the combatant.
	## Ranged: every voxel cell within weapon long range with LOS.
	var result: Array = []
	if _controller == null:
		return result
	var combatant = _controller.get_combatant(_current_pc_id)
	if combatant == null:
		return result
	var origin: Vector3i = combatant.grid_position
	if origin == Vector3i(-1, -1, 0):
		return result
	var voxel_map = _controller.voxel_map
	if voxel_map == null:
		return result

	if weapon == "melee":
		for n: Vector3i in VoxelGrid.get_neighbors_2d(origin):
			if voxel_map.has_cell(n):
				result.append(n)
		return result

	# Ranged: scan voxel cells within long range (feet / FEET_PER_CELL).
	var ranges: Dictionary = combatant.get_weapon_ranges()
	var long_r_ft: int = int(ranges.get("long", 0))
	if long_r_ft <= 0:
		return result
	var FEET_PER_CELL: int = 5
	var long_r_cells: int = long_r_ft / FEET_PER_CELL
	var mr = _controller.movement_resolver
	for cell_pos in voxel_map.get_all_positions():
		if cell_pos == origin:
			continue
		var dist: int = VoxelGrid.chebyshev_distance(origin, cell_pos)
		if dist <= 0 or dist > long_r_cells:
			continue
		# LOS check uses 2D projection (consistent with ranged attack logic).
		var los_ok := true
		if mr != null:
			los_ok = mr.has_line_of_sight(
				Vector2i(origin.x, origin.y),
				Vector2i(cell_pos.x, cell_pos.y))
		if los_ok:
			result.append(cell_pos)
	return result


## Called when a cell is clicked on the map during facing selection or cleave.
func on_cell_targeted(pos: Vector3i) -> void:
	if _state == State.PC_SELECTING_READY_CELL:
		if pos not in _ready_cell_options:
			return
		var trigger_type: String = "cell"
		clear_highlights_requested.emit()
		var weapon := _ready_cell_weapon
		_ready_cell_options.clear()
		_ready_cell_weapon = ""
		_controller.submit_pc_action(_current_pc_id, "ready_attack",
			{"character_id": _current_pc_id,
			 "trigger_type": trigger_type,
			 "trigger_cell": pos,
			 "trigger_weapon": weapon})
		advance()
		return

	if _state == State.PC_SELECTING_FACING:
		# Player clicked an adjacent cell to choose facing
		var combatant = _controller.get_combatant(_current_pc_id)
		if combatant == null:
			return
		var origin: Vector3i = combatant.grid_position
		if VoxelGrid.chebyshev_distance(origin, pos) != 1:
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

	if _state == State.PC_SPELL_TARGETING:
		# Cell click during spell targeting: anchor for area_at_point spells.
		if _targeting_kind != "area_at_point":
			return
		if _targeting_controller != null:
			_targeting_controller.set_anchor_cell(pos)
			_targeting_anchor_set = true
			_render_aoe_preview(pos)
		return


func _enter_facing_selection() -> void:
	var combatant = _controller.get_combatant(_current_pc_id)
	if combatant == null:
		return
	var origin: Vector3i = combatant.grid_position
	var typed_cells: Array[Vector3i] = []
	for n: Vector3i in VoxelGrid.get_neighbors_2d(origin):
		typed_cells.append(n)
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


func _direction_vector(from_pos, to_pos) -> Vector2i:
	## Accepts Vector2i or Vector3i; returns Vector2i (combat facing is 2D).
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

	if _state == State.PC_SELECTING_READY_CELL:
		# Treat the click as picking the entity's cell (useful when the
		# target cell currently contains an enemy).
		var combatant = _controller.get_combatant(entity_id)
		if combatant == null:
			return
		on_cell_targeted(combatant.grid_position)
		return

	if _state == State.PC_SPELL_TARGETING:
		# Entity click during spell targeting: route to TargetingController
		# for single-entity spells and HD-budget multi-pick spells.
		if _targeting_controller == null:
			return
		if _targeting_kind == "single_entity":
			var result := _targeting_controller.try_select(entity_id)
			if result.accepted:
				_commit_spell_targeting()
			return
		if _targeting_kind == "hd_budget":
			var result := _targeting_controller.try_select(entity_id)
			if not result.accepted:
				log_entry.emit({
					"type": 0, "round": 0,
					"actor_id": _current_pc_id, "target_id": entity_id,
					"data": {"hd_target_rejected": result.reason},
					"timestamp": 0,
				})
				return
			_refresh_targeting_highlights()
			# HD-budget casts confirm via on_confirm_spell_targeting; the click
			# alone never auto-commits.
			return
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
		highlight_reachable.emit(move_cells, Color(0.9, 0.9, 0.2, 0.30))

	cleave_selection_started.emit(_current_pc_id)


## Cancel current selection — return to awaiting input.
func on_cancel() -> void:
	if _state == State.PC_CONTEXT_MENU_OPEN or \
	   _state == State.PC_SELECTING_WEAPON or \
	   _state == State.PC_SELECTING_READY_CELL:
		clear_highlights_requested.emit()
		_ready_cell_options.clear()
		_ready_cell_weapon = ""
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
		result.append(_build_pc_declaration_record(c))
	return result


func _build_pc_declaration_record(c: Combatant) -> Dictionary:
	## Builds the per-PC record consumed by DeclarationOverlay. Includes the
	## caster fields (`is_caster`, `can_cast_now`, `cast_disabled_reason`,
	## `character_data`) the overlay uses to grey-out the Cast Spell option
	## with a tooltip when casting isn't possible.
	var record := {
		"combatant_id": c.id,
		"display_name": c.display_name,
		# Berserkers cannot declare defensive movement; the overlay greys
		# out Fighting Withdrawal and Full Retreat for these PCs.
		"is_berserk_raging": c.is_berserk_raging(),
		"is_caster": false,
		"can_cast_now": false,
		"cast_disabled_reason": "",
		"character_data": null,
	}
	if not c.is_character:
		return record
	var cd: CharacterData = c.get_character_data()
	record["character_data"] = cd

	# Caster detection: combat_progression "mage" or "cleric", OR class is
	# in the canonical caster set. Future cleanup: SpellRegistry.get_class_tradition.
	var is_caster: bool = cd.combat_progression in ["mage", "cleric"]
	if not is_caster:
		is_caster = cd.character_class in [
			"mage", "elven_spellsword", "elven_nightblade", "warlock", "witch",
			"cleric", "bladedancer", "dwarven_craftpriest"]
	record["is_caster"] = is_caster

	if not is_caster:
		record["cast_disabled_reason"] = "Not a caster"
		return record

	# Disruption checks (the conditions that block declaring a cast at all).
	# Per acore_spellcaster_rules, a caster cannot cast while gagged, hands
	# bound, in a silence area, prone (no hand-free posture), incapacitated,
	# or under action-preventing conditions.
	var blocked_conditions := ["paralyzed", "unconscious", "stunned", "held",
		"grappled", "petrified", "silenced"]
	for cond in blocked_conditions:
		if c.has_condition(cond):
			record["cast_disabled_reason"] = "Cannot cast while %s" % cond
			return record

	# Slot availability check.
	if not _has_any_unused_spell_slot(cd):
		record["cast_disabled_reason"] = "No spell slots available"
		return record

	record["can_cast_now"] = true
	return record


func _has_any_unused_spell_slot(cd: CharacterData) -> bool:
	## True if the caster has at least one unused slot at any level. Reads the
	## class registry's per-level spell slot table and compares against the
	## CampaignRepository expended-count dict. A non-caster (empty slot table)
	## returns false; a caster with slots but all levels fully expended returns
	## false; otherwise true. Used by DeclarationOverlay to grey-out the Cast
	## Spell option when no slots remain.
	var class_registry: ClassRegistry = Combatant.get_class_registry()
	var slots: Array = class_registry.get_spell_slots(cd.character_class, cd.level)
	if slots.is_empty():
		return false
	var expended: Dictionary = CampaignRepository.get_expended_slots(cd.id)
	for i in range(slots.size()):
		var level: int = i + 1
		var max_at_level: int = int(slots[i])
		var used_at_level: int = int(expended.get(level, 0))
		if used_at_level < max_at_level:
			return true
	return false


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
	## Emit log entries for the resolved action so the embedded UnifiedLog
	## (γ.5) can display them via the GameLog autoload.
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
	if _controller == null or _controller.voxel_map == null:
		return
	var map: VoxelMapData = _controller.voxel_map
	var short_cells: Array[Vector2i] = []
	var medium_cells: Array[Vector2i] = []
	var long_cells: Array[Vector2i] = []

	for cell_pos in map.get_all_positions():
		var cell_2d := Vector2i(cell_pos.x, cell_pos.y)
		var dist: int = IsometricGrid.chebyshev_distance(origin, cell_2d)
		if dist == 0:
			continue
		if dist <= short_r:
			short_cells.append(cell_2d)
		elif dist <= medium_r:
			medium_cells.append(cell_2d)
		elif dist <= long_r:
			long_cells.append(cell_2d)

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
		"attack_melee", "attack_ranged", "backstab", "charge", "coup_de_grace", \
				"ready_attack_fire":
			return 1  # CombatLog.EntryType.ATTACK
		"cast_spell":
			return 3  # SPELL
		"move", "move_here", "run_here":
			return 4  # MOVEMENT
		"fighting_withdrawal", "full_retreat":
			return 4  # MOVEMENT
		"switch_weapon", "stand_up", "ready_attack":
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
	var walk_cells := mr.get_cells_reachable(combatant, combatant.get_combat_movement_cells(), combatant.side)
	if not walk_cells.is_empty():
		var typed_walk: Array[Vector2i] = []
		for c in walk_cells:
			typed_walk.append(c)
		highlight_reachable.emit(typed_walk, Color(0.2, 0.6, 1.0, 0.15))

	# Running cells (green) — beyond walk range, within 3x
	var run_cells := mr.get_cells_reachable(combatant, combatant.get_combat_movement_cells() * 3, combatant.side)
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


# ---------------------------------------------------------------------------
# Spell targeting (Session 2.8 — combat-cast UI integration)
# ---------------------------------------------------------------------------

func _enter_spell_targeting(caster_id: String) -> void:
	## Activates targeting mode for a declared cast. Reads the spell's effect
	## payload, builds a TargetingController populated with valid candidates
	## from the roster, highlights them, and either auto-resolves (self /
	## area_from_caster / caster_and_radius — no click needed) or waits for
	## player input on the map.
	_targeting_caster_id = caster_id
	var caster: Combatant = _controller.get_combatant(caster_id)
	if caster == null or _controller.casting_resolver == null:
		_cancel_spell_targeting()
		return
	var choice: SpellChoice = caster.declared_spell_choice
	if choice == null:
		_cancel_spell_targeting()
		return

	var effect_registry: SpellEffectRegistry = _controller.casting_resolver.get_effect_registry()
	var spell_registry: SpellRegistry = _controller.casting_resolver.get_spell_registry()
	var payload: Dictionary = effect_registry.get_effect_payload(
		choice.spell_key, choice.is_reversed, choice.chosen_disjunctive_index)
	if payload.is_empty():
		_cancel_spell_targeting()
		return

	_targeting_spell_payload = payload
	var target_spec: Dictionary = payload.get("target_spec", {})
	var ts_kind := String(target_spec.get("kind", ""))
	var spell_data: Dictionary = spell_registry.get_spell(choice.spell_key)
	var spell_name := String(spell_data.get("spell_name", choice.spell_key))

	# Build TargetingController with caster position + level. The dice system
	# is the global autoload; we expose a property for tests.
	var caster_level: int = 1
	if caster.is_character:
		caster_level = caster.get_character_data().level
	_targeting_controller = TargetingController.new(
		target_spec, caster.grid_position, caster_level, _get_dice_system())

	# Self / area_from_caster / caster_and_radius auto-resolve without user
	# input — the descriptor is built immediately from caster position.
	if ts_kind in ["self", "area_from_caster", "caster_and_radius"]:
		_targeting_kind = "auto"
		_register_candidates_for_area()
		_targeting_controller.begin()
		spell_targeting_started.emit(caster_id, spell_name, "auto")
		_commit_spell_targeting()
		return

	# Touch-creature / touch-ally / touch-enemy / single_creature → entity click.
	if ts_kind in ["single_creature", "single_object", "touch_ally", "touch_enemy", "touch_creature"]:
		_targeting_kind = "single_entity"
		_register_candidates_for_entity_target(target_spec)
		_targeting_controller.begin()
		_refresh_targeting_highlights()
		spell_targeting_started.emit(caster_id, spell_name, "single_entity")
		return

	# Multi-target HD budget (Sleep group, Charm Monster group).
	if ts_kind == "multiple_creatures_hd_budget":
		_targeting_kind = "hd_budget"
		_register_candidates_for_entity_target(target_spec)
		_targeting_controller.begin()
		_refresh_targeting_highlights()
		_targeting_controller.selection_changed.connect(_on_targeting_selection_changed)
		spell_targeting_started.emit(caster_id, spell_name, "hd_budget")
		spell_hd_tally_updated.emit(spell_name, _targeting_controller)
		return

	# Area at point — Fireball, Cloudkill. Player clicks an anchor cell, then
	# the AoE preview asks for confirmation.
	if ts_kind == "area_at_point":
		_targeting_kind = "area_at_point"
		_register_candidates_for_area()
		_targeting_controller.begin()
		spell_targeting_started.emit(caster_id, spell_name, "area_at_point")
		return

	# Unknown / unhandled target_spec — auto-cancel rather than soft-lock.
	push_warning("CombatUIController: unsupported target_spec.kind '%s' — auto-cancelling cast" % ts_kind)
	_cancel_spell_targeting()


func _register_candidates_for_entity_target(target_spec: Dictionary) -> void:
	## Registers all alive combatants (PCs + enemies) as candidates with the
	## targeting controller. Eligibility is handled by the controller using
	## the target_spec's creature_filter / range_feet / hd cap rules.
	var creature_filter: Dictionary = target_spec.get("creature_filter", {})
	var friend_or_foe := String(target_spec.get("friend_or_foe", "any"))
	var caster: Combatant = _controller.get_combatant(_targeting_caster_id)
	for c: Combatant in _controller.roster.get_alive():
		# Friend/foe pre-filter: most damage spells target enemies, most buffs
		# target allies. The targeting_spec's creature_filter doesn't model
		# alignment side, so we apply it here.
		if friend_or_foe == "willing_only" and c.side != caster.side:
			continue
		if friend_or_foe == "unwilling_only" and c.side == caster.side:
			continue
		var entity: Variant = c.get_character_data() if c.is_character else null
		# Pass the Combatant itself as a fallback so monster Dictionaries get
		# their hit_dice read for HD checks.
		if entity == null:
			entity = c
		_targeting_controller.add_candidate(c.id, entity, c.grid_position)


func _register_candidates_for_area() -> void:
	## For area_at_point / area_from_caster / caster_and_radius — registers
	## every alive combatant so the controller can collect hits-in-area from
	## the resolved cell set on commit.
	for c: Combatant in _controller.roster.get_alive():
		var entity: Variant = c.get_character_data() if c.is_character else null
		if entity == null:
			entity = c
		_targeting_controller.add_candidate(c.id, entity, c.grid_position)


func _refresh_targeting_highlights() -> void:
	if _targeting_controller == null:
		return
	# HD-budget targeting emits per-band data for color-coded cell overlays.
	if _targeting_kind == "hd_budget" and _targeting_controller.has_hd_budget():
		_emit_hd_band_highlights()
		return
	# Default: green rings on all eligible candidates.
	var eligible_ids: Array[String] = []
	for cid in _targeting_controller.get_eligible_candidates():
		eligible_ids.append(String(cid))
	highlight_targets.emit(eligible_ids)


func _emit_hd_band_highlights() -> void:
	## Partitions registered candidates into HD-budget bands for the renderer:
	##   selected — already in the chosen set; keeps the green target ring.
	##   green    — eligible AND under-budget; clicking adds them.
	##   yellow   — eligible but selecting them would over-spend the budget.
	##   red      — ineligible (over per-target HD cap, out of range, or
	##              filtered out by creature_filter); shown struck-through
	##              with a tooltip indicating the failure reason.
	## Iterates ALL registered candidates (Session 2.9.1) so red-band
	## ineligibles render alongside the eligible green/yellow bands.
	var bands := {
		"green": [], "yellow": [], "red": [], "selected": [],
		# red_reasons: Dictionary mapping ineligible cid → human-readable reason
		# string for tooltip display ("HD cap" / "out of range" / "excluded type
		# X" / etc.). Populated alongside the red band so the renderer can show
		# WHY each struck-through candidate is ineligible (Session 9.6 polish).
		"red_reasons": {},
	}
	var selected: Array = _targeting_controller.get_selected()
	var budget_remaining: float = _targeting_controller.get_budget_remaining()
	for cid in _targeting_controller.get_all_candidate_ids():
		if cid in selected:
			bands["selected"].append(cid)
			continue
		if not _targeting_controller.is_eligible(cid):
			bands["red"].append(cid)
			bands["red_reasons"][cid] = _targeting_controller.get_ineligible_reason(cid)
			continue
		var info: Dictionary = _targeting_controller.get_candidate_info(cid)
		var hd: float = float(info.get("counted_hd", 0.0))
		if hd > budget_remaining:
			bands["yellow"].append(cid)
		else:
			bands["green"].append(cid)
	highlight_targets_by_band.emit(bands)
	# Selected entities keep the green target ring.
	var typed_selected: Array[String] = []
	for s in selected:
		typed_selected.append(s)
	if not typed_selected.is_empty():
		highlight_targets.emit(typed_selected)


func _render_aoe_preview(anchor_cell: Vector3i) -> void:
	if _targeting_controller == null:
		return
	# Snapshot the descriptor and resolve cells for the preview.
	var td := _targeting_controller.commit()  # commit reads the anchor we just set
	var caster: Combatant = _controller.get_combatant(_targeting_caster_id)
	var caster_side: int = caster.side if caster != null else Combatant.Side.PARTY
	var spell_data: Dictionary = _controller.casting_resolver.get_spell_registry().get_spell(
		caster.declared_spell if caster != null else "")
	var spell_name := String(spell_data.get("spell_name", "Spell"))

	# Build affected list + ally callout for the preview overlay.
	# Also partition target cells by occupant: ally cells, enemy cells, empty cells.
	var affected: Array = []
	var ally_ids: Array = []
	var ally_cells: Array = []
	var enemy_cells: Array = []
	var empty_cells: Array = []
	var occupied_positions: Dictionary = {}
	for c: Combatant in _controller.roster.get_alive():
		if c.grid_position != Vector3i(-1, -1, 0):
			occupied_positions[c.grid_position] = c

	for tid in td.target_ids:
		var c := _controller.roster.get_by_id(tid)
		if c == null:
			continue
		affected.append({"id": tid, "name": c.display_name})
		if c.side == caster_side:
			ally_ids.append(tid)
			if c.grid_position != Vector3i(-1, -1, 0):
				ally_cells.append(c.grid_position)
		else:
			if c.grid_position != Vector3i(-1, -1, 0):
				enemy_cells.append(c.grid_position)

	# Partition target cells into occupied vs empty for layered display.
	var occupied_set: Dictionary = {}  # cell -> true
	for cell in ally_cells:
		occupied_set[cell] = true
	for cell in enemy_cells:
		occupied_set[cell] = true
	for cell in td.target_cells:
		if not occupied_set.has(cell):
			empty_cells.append(cell)

	# Emit layered highlights: ally-occupied (red-orange), enemy-occupied (red),
	# empty AoE cells (faint orange). Use highlight_cells_layered so the renderer
	# can distinguish them.
	clear_highlights_requested.emit()
	var layers: Array = []
	if not enemy_cells.is_empty():
		layers.append({"cells": enemy_cells, "color": Color(0.92, 0.25, 0.20, 0.35)})
	if not ally_cells.is_empty():
		layers.append({"cells": ally_cells, "color": Color(0.95, 0.50, 0.20, 0.40)})
	if not empty_cells.is_empty():
		layers.append({"cells": empty_cells, "color": Color(0.92, 0.45, 0.20, 0.18)})
	highlight_cells_layered.emit(layers)
	spell_aoe_preview.emit(spell_name, affected, ally_ids)


func _on_targeting_selection_changed() -> void:
	_refresh_targeting_highlights()
	# Re-emit the HD-tally update so the panel refreshes its budget display.
	if _targeting_kind == "hd_budget" and _targeting_controller != null:
		var caster: Combatant = _controller.get_combatant(_targeting_caster_id)
		var spell_data: Dictionary = _controller.casting_resolver.get_spell_registry().get_spell(
			caster.declared_spell if caster != null else "")
		spell_hd_tally_updated.emit(
			String(spell_data.get("spell_name", "Spell")), _targeting_controller)


func on_confirm_spell_targeting() -> void:
	## Host (HdTallyPanel / AoePreviewOverlay) calls this when the player
	## clicks Confirm.
	if _state != State.PC_SPELL_TARGETING:
		return
	_commit_spell_targeting()


func on_cancel_spell_targeting() -> void:
	## Host calls this when the player presses Esc / clicks Cancel during a
	## targeting flow. ACKS rules say a cancelled cast still consumes the slot
	## (the caster declared and committed the spell-cast intent), so we route
	## through resolve_disrupted to consume the slot cleanly.
	if _state != State.PC_SPELL_TARGETING:
		return
	# If the player hasn't made any selections yet and no anchor is set, Esc
	# implicitly rescinds (returns the slot) rather than cancelling. The explicit
	# Rescind button is the primary affordance; Esc-as-rescind is the fallback.
	if _can_rescind():
		on_rescind_spell_targeting()
		return
	# Treat as a disrupted cast — slot consumed, no effect.
	var caster: Combatant = _controller.get_combatant(_targeting_caster_id)
	if caster != null and _controller.casting_resolver != null:
		var choice: SpellChoice = caster.declared_spell_choice
		if choice != null:
			caster.damaged_since_declaration = true
	_cancel_spell_targeting()


func _can_rescind() -> bool:
	## True when the player may rescind their declared spell without consuming
	## the slot. Requires: no selection made, not auto-resolving, and (for
	## area_at_point) no anchor set.
	if _targeting_kind == "auto":
		return false
	if _targeting_controller == null:
		return false
	if not _targeting_controller.get_selected().is_empty():
		return false
	if _targeting_kind == "area_at_point" and _targeting_anchor_set:
		return false
	return true


func on_rescind_spell_targeting() -> void:
	## Host calls this when the player clicks Rescind. Returns the declared spell
	## slot to the caster and routes the PC back to `waiting_for_pc_action` so
	## they get their full turn back. Only callable when `_can_rescind()` is true.
	if _state != State.PC_SPELL_TARGETING:
		return
	if not _can_rescind():
		return
	var caster: Combatant = _controller.get_combatant(_targeting_caster_id)
	if caster != null:
		caster.declared_spell = ""
		caster.declared_spell_choice = null
	_teardown_targeting_state()
	# Route back to normal PC turn — same state transition as entering the turn.
	_state = State.PC_AWAITING_INPUT
	_selected_action = ""
	_has_moved_this_turn = false
	clear_highlights_requested.emit()
	active_token_changed.emit(_current_pc_id)
	pc_turn_started.emit(_current_pc_id)
	_show_proactive_movement_overlay()


func _commit_spell_targeting() -> void:
	if _targeting_controller == null:
		_cancel_spell_targeting()
		return
	var td := _targeting_controller.commit()
	var caster: Combatant = _controller.get_combatant(_targeting_caster_id)
	# Self-targeting spells (Shield) and area_from_caster spells (Bless)
	# return target_cells anchored on caster_pos but no target_ids — the
	# resolver applies effects to the caster directly. Force the caster_id
	# into target_ids so the resolver's per-target loop fires.
	if td.kind == "self" and td.target_ids.is_empty():
		td.target_ids = [_targeting_caster_id]
	# Build targets_by_id from the descriptor's target_ids by reading roster.
	var targets_by_id: Dictionary = {}
	for tid in td.target_ids:
		var c := _controller.roster.get_by_id(tid)
		if c != null:
			targets_by_id[tid] = c
	_controller.submit_pc_spell_action(_targeting_caster_id, td, targets_by_id)
	_teardown_targeting_state()
	advance()


func _cancel_spell_targeting() -> void:
	## Tears down targeting state without submitting. Used for unsupported
	## target kinds and for explicit cancel.
	_teardown_targeting_state()
	# Without submitting, the controller will keep returning
	# waiting_for_pc_spell_target. We force a disrupted resolution by setting
	# damaged_since_declaration on the caster and advancing — the controller's
	# is_cast_disrupted_this_round check then routes to resolve_disrupted.
	var caster: Combatant = _controller.get_combatant(_targeting_caster_id)
	if caster != null and not caster.declared_spell.is_empty():
		caster.damaged_since_declaration = true
	advance()


func _teardown_targeting_state() -> void:
	if _targeting_controller != null and _targeting_controller.selection_changed.is_connected(_on_targeting_selection_changed):
		_targeting_controller.selection_changed.disconnect(_on_targeting_selection_changed)
	_targeting_controller = null
	_targeting_spell_payload = {}
	_targeting_caster_id = ""
	_targeting_kind = ""
	_targeting_anchor_set = false
	clear_highlights_requested.emit()
	spell_targeting_ended.emit()


func _get_dice_system():
	## Returns the DiceSystem autoload. Lives in a helper for testability —
	## tests can override by setting a `_dice_override` field.
	if _dice_override != null:
		return _dice_override
	return DiceSystem


## Test-only override for the dice system. Set by combat_cast integration
## tests to inject a deterministic FakeDice.
var _dice_override = null

