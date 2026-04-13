class_name DungeonCombatOverlay
extends CanvasLayer

## Combat HUD overlay for dungeon in-place encounters.
##
## Sits on CanvasLayer 10 (above the dungeon HUD at layer 1).
## Composes the shared combat HUD widgets: InitiativeStrip, StatSummary,
## ActionButtonPanel, CombatLogPanel. DeclarationOverlay and CombatEndOverlay
## are shown/hidden as needed.
##
## Owns a CombatUIController that bridges these widgets to the CombatController.
## Wires the DungeonMapRenderer's cell_clicked/entity_clicked signals during
## combat mode for target selection.
##
## Usage from DungeonExploreState:
##   var overlay := DungeonCombatOverlay.new()
##   runner.add_child(overlay)
##   overlay.start_combat(controller, renderer)
##   overlay.combat_finished.connect(_on_dungeon_combat_finished)


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal combat_finished(result: Dictionary)


# ---------------------------------------------------------------------------
# Scene references (created in _build_ui)
# ---------------------------------------------------------------------------

var _init_strip: InitiativeStrip = null
var _stat_summary: StatSummary = null
var _action_panel: ActionButtonPanel = null
var _log_panel: CombatLogPanel = null
var _decl_overlay: DeclarationOverlay = null
var _weapon_popup: WeaponSwitchPopup = null
var _end_overlay: CombatEndOverlay = null
var _round_label: Label = null


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _ui_controller: CombatUIController = null
var _renderer = null  # DungeonMapRenderer (duck-typed — no class_name)
var _controller: CombatController = null

## Cached combat result for the Continue button.
var _combat_result: Dictionary = {}

## Connections we need to disconnect on cleanup.
var _cell_conn: Callable = Callable()
var _entity_conn: Callable = Callable()


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 10
	_build_ui()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Begin in-place dungeon combat.
## [param controller]: fully built CombatController with roster, resolvers, etc.
## [param renderer]: the DungeonMapRenderer instance to overlay on.
func start_combat(controller: CombatController, renderer) -> void:
	_controller = controller
	_renderer = renderer

	# Put the renderer into combat mode for entity-click detection.
	renderer.set_combat_mode(true)

	# Create the UI controller
	_ui_controller = CombatUIController.new()
	_ui_controller.setup(controller)

	# Wire UI controller signals -> HUD widgets
	_ui_controller.show_declaration_requested.connect(_on_show_declarations)
	_ui_controller.initiative_updated.connect(_on_initiative_updated)
	_ui_controller.pc_turn_started.connect(_on_pc_turn_started)
	_ui_controller.action_resolved.connect(_on_action_resolved)
	_ui_controller.combat_ended.connect(_on_combat_ended)
	_ui_controller.log_entry.connect(_on_log_entry)

	# Wire UI controller signals -> map renderer
	_ui_controller.highlight_reachable.connect(_on_highlight_reachable)
	_ui_controller.highlight_targets.connect(_on_highlight_targets)
	_ui_controller.clear_highlights_requested.connect(_on_clear_highlights)
	_ui_controller.active_token_changed.connect(_on_active_token_changed)

	# Wire deferred auto-advance for enemy turns / phase transitions
	_ui_controller.auto_advance_requested.connect(_on_auto_advance)

	# Wire move_completed to disable Move button after move sub-action
	_ui_controller.move_completed.connect(_on_move_completed)

	# Wire weapon switch signals
	_ui_controller.weapon_switch_requested.connect(_on_weapon_switch_requested)
	_ui_controller.weapon_switched.connect(_on_weapon_switched)

	# Wire facing-selection flow
	_ui_controller.facing_selection_started.connect(_on_facing_selection_started)
	_ui_controller.token_facing_preview.connect(_on_token_facing_preview)
	_action_panel.confirm_move_pressed.connect(_on_confirm_move_pressed)

	# Wire cleave selection flow
	_ui_controller.cleave_selection_started.connect(_on_cleave_selection_started)
	_action_panel.skip_cleave_pressed.connect(_on_skip_cleave_pressed)

	# Wire cleave flash signal
	_ui_controller.may_cleave.connect(_on_may_cleave)

	# Wire renderer input -> UI controller
	_cell_conn = _on_renderer_cell_clicked
	_entity_conn = _on_renderer_entity_clicked
	renderer.cell_clicked.connect(_cell_conn)
	renderer.entity_clicked.connect(_entity_conn)

	# Wire action panel -> UI controller
	_action_panel.action_selected.connect(_on_action_selected)

	# Build name lookup for the combat log
	var name_lookup: Dictionary = {}
	for c in controller.roster.get_all():
		name_lookup[c.id] = c.display_name
	_log_panel.set_name_lookup(name_lookup)

	# Show the overlay
	visible = true
	_action_panel.set_panel_visible(false)
	_decl_overlay.visible = false
	_end_overlay.visible = false

	# Kick off combat
	_ui_controller.advance()


## End combat and clean up.
func end_combat() -> void:
	if _renderer != null:
		_renderer.set_combat_mode(false)
		_renderer.clear_highlights()
		_renderer.set_active_token("")
		# Disconnect renderer signals
		if _renderer.cell_clicked.is_connected(_cell_conn):
			_renderer.cell_clicked.disconnect(_cell_conn)
		if _renderer.entity_clicked.is_connected(_entity_conn):
			_renderer.entity_clicked.disconnect(_entity_conn)

	_ui_controller = null
	_controller = null
	_renderer = null
	queue_free()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Right panel (VBoxContainer) — initiative strip + stat summary + actions
	var right_panel := VBoxContainer.new()
	right_panel.name = "RightPanel"
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.offset_left = -220.0
	right_panel.offset_top = 10.0
	right_panel.offset_bottom = -10.0
	right_panel.offset_right = -10.0
	right_panel.add_theme_constant_override("separation", 6)
	add_child(right_panel)

	_init_strip = InitiativeStrip.new()
	_init_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(_init_strip)

	_stat_summary = StatSummary.new()
	right_panel.add_child(_stat_summary)

	_action_panel = ActionButtonPanel.new()
	right_panel.add_child(_action_panel)

	# Bottom-left: combat log
	_log_panel = CombatLogPanel.new()
	_log_panel.name = "CombatLog"
	_log_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_log_panel.offset_left = 10.0
	_log_panel.offset_bottom = -10.0
	_log_panel.offset_top = -180.0
	_log_panel.offset_right = 280.0
	add_child(_log_panel)

	# Bottom-center: round indicator
	_round_label = Label.new()
	_round_label.name = "RoundLabel"
	_round_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_round_label.offset_top = -30.0
	_round_label.offset_left = 290.0
	_round_label.offset_right = -230.0
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.add_theme_font_size_override("font_size", 14)
	_round_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	_round_label.text = "Combat"
	add_child(_round_label)

	# Centered overlays (declaration + combat end)
	_decl_overlay = DeclarationOverlay.new()
	_decl_overlay.name = "DeclarationOverlay"
	_decl_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_decl_overlay.offset_left = -220.0
	_decl_overlay.offset_top = -150.0
	_decl_overlay.offset_right = 220.0
	_decl_overlay.offset_bottom = 150.0
	_decl_overlay.visible = false
	_decl_overlay.declarations_complete.connect(_on_declarations_confirmed)
	add_child(_decl_overlay)

	_weapon_popup = WeaponSwitchPopup.new()
	_weapon_popup.name = "WeaponSwitchPopup"
	_weapon_popup.set_anchors_preset(Control.PRESET_CENTER)
	_weapon_popup.offset_left = -180.0
	_weapon_popup.offset_top = -140.0
	_weapon_popup.offset_right = 180.0
	_weapon_popup.offset_bottom = 140.0
	_weapon_popup.visible = false
	_weapon_popup.weapon_selected.connect(_on_weapon_popup_selected)
	_weapon_popup.cancelled.connect(_on_weapon_popup_cancelled)
	add_child(_weapon_popup)

	_end_overlay = CombatEndOverlay.new()
	_end_overlay.name = "CombatEndOverlay"
	_end_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_end_overlay.offset_left = -230.0
	_end_overlay.offset_top = -170.0
	_end_overlay.offset_right = 230.0
	_end_overlay.offset_bottom = 170.0
	_end_overlay.visible = false
	_end_overlay.continue_pressed.connect(_on_continue_pressed)
	add_child(_end_overlay)


# ---------------------------------------------------------------------------
# CombatUIController signal handlers
# ---------------------------------------------------------------------------

func _on_show_declarations(alive_pcs: Array) -> void:
	_round_label.text = "Round %d — Declarations" % _controller.round_number
	_action_panel.set_panel_visible(false)
	_decl_overlay.set_pc_list(alive_pcs)
	_decl_overlay.visible = true


func _on_initiative_updated(order: Array) -> void:
	_init_strip.set_initiative_order(order)


func _on_pc_turn_started(combatant_id: String) -> void:
	_round_label.text = "Round %d" % _controller.round_number
	_decl_overlay.visible = false
	if _weapon_popup != null:
		_weapon_popup.visible = false

	# Update stat summary
	var combatant = _controller.get_combatant(combatant_id)
	_stat_summary.show_combatant(combatant)

	# Update initiative strip active marker
	_init_strip.set_active(combatant_id)

	# Show action buttons with available actions; hide Confirm Move and Skip Cleave
	_action_panel.set_panel_visible(true)
	_action_panel.show_confirm_move(false)
	_action_panel.show_skip_cleave(false)
	var actions := _controller.get_available_actions(combatant_id)
	_action_panel.set_available_actions(actions)


func _on_action_resolved(result: Dictionary) -> void:
	# Hide action buttons during non-PC turns
	_action_panel.set_panel_visible(false)

	# Sync all token positions from grid state
	_sync_token_positions()

	# Update stat summary to reflect damage/movement changes
	var cid: String = result.get("combatant_id", "")
	if not cid.is_empty():
		var combatant = _controller.get_combatant(cid)
		_stat_summary.show_combatant(combatant)

	# Update HP in initiative strip for any affected combatant
	var action_result: Dictionary = result.get("result", {})
	var target_id: String = action_result.get("target_id", "")
	if not target_id.is_empty():
		var target = _controller.get_combatant(target_id)
		if target != null:
			_init_strip.update_hp(target_id, target.get_hp_current(), target.get_hp_max())


func _on_combat_ended(result: Dictionary) -> void:
	_combat_result = result
	_action_panel.set_panel_visible(false)
	_decl_overlay.visible = false
	_round_label.text = "Combat Over"
	_end_overlay.show_result(result)


func _on_log_entry(entry: Dictionary) -> void:
	_log_panel.append_event(entry)


# ---------------------------------------------------------------------------
# Map renderer signal handlers
# ---------------------------------------------------------------------------

func _on_highlight_reachable(cells: Array, color: Color) -> void:
	if _renderer != null:
		var typed: Array[Vector2i] = []
		for c in cells:
			typed.append(c)
		_renderer.highlight_cells(typed, color)


func _on_highlight_targets(entity_ids: Array) -> void:
	if _renderer != null:
		var typed: Array[String] = []
		for eid in entity_ids:
			typed.append(eid)
		_renderer.highlight_entity_tokens(typed)


func _on_clear_highlights() -> void:
	if _renderer != null:
		_renderer.clear_highlights()


func _on_active_token_changed(entity_id: String) -> void:
	if _renderer != null:
		_renderer.set_active_token(entity_id)


# ---------------------------------------------------------------------------
# Renderer input -> UI controller
# ---------------------------------------------------------------------------

func _on_renderer_cell_clicked(pos: Vector2i) -> void:
	if _ui_controller != null:
		_ui_controller.on_cell_targeted(pos)


func _on_renderer_entity_clicked(entity_id: String) -> void:
	if _ui_controller != null:
		_ui_controller.on_entity_targeted(entity_id)


# ---------------------------------------------------------------------------
# Widget input -> UI controller
# ---------------------------------------------------------------------------

func _on_action_selected(action_id: String) -> void:
	if _ui_controller != null:
		_ui_controller.on_action_button(action_id)


func _on_declarations_confirmed(declarations: Array) -> void:
	_decl_overlay.visible = false
	if _ui_controller != null:
		_ui_controller.on_declarations_confirmed(declarations)


func _on_weapon_switch_requested(combatant_id: String, weapons: Array, has_moved: bool) -> void:
	if _weapon_popup == null:
		return
	var combatant = _controller.get_combatant(combatant_id)
	var is_armed: bool = combatant != null and not combatant.get_equipped_weapon().is_empty()
	# Check for equipped off-hand shield
	var has_shield := false
	if combatant != null and combatant.is_character and combatant._character != null:
		var inv_rows: Array = CampaignRepository.get_inventory_items(combatant._character.id)
		for row in inv_rows:
			if int(row.get("is_equipped", 0)) == 1 and row.get("slot", "") == "hands_off" \
					and row.get("item_category", "") == "shield":
				has_shield = true
				break
	_action_panel.set_panel_visible(false)
	_weapon_popup.set_weapons(weapons, has_moved, is_armed, has_shield)
	_weapon_popup.visible = true


func _on_weapon_popup_selected(weapon_item: Dictionary) -> void:
	_weapon_popup.visible = false
	_action_panel.set_panel_visible(true)
	if _ui_controller != null:
		_ui_controller.on_weapon_selected(weapon_item)


func _on_weapon_popup_cancelled() -> void:
	_weapon_popup.visible = false
	_action_panel.set_panel_visible(true)
	if _ui_controller != null:
		_ui_controller.on_cancel()


func _on_weapon_switched(combatant_id: String) -> void:
	# Refresh stat summary to show the new weapon
	var combatant = _controller.get_combatant(combatant_id)
	if combatant != null:
		_stat_summary.show_combatant(combatant)


func _on_continue_pressed() -> void:
	_end_overlay.visible = false
	combat_finished.emit(_combat_result)


# ---------------------------------------------------------------------------
# Deferred auto-advance (yields one frame for UI rendering)
# ---------------------------------------------------------------------------

func _on_move_completed() -> void:
	# After a move sub-action, disable Move button but keep turn active
	_action_panel.disable_action("move")
	# Sync token positions so the moved token appears at its new cell
	_sync_token_positions()


func _sync_token_positions() -> void:
	if _renderer == null or _controller == null or _controller.tactical_map == null:
		return
	for eid in _controller.tactical_map.entity_positions:
		var pos: Vector2i = _controller.tactical_map.entity_positions[eid]
		_renderer.move_token(eid, pos)
		var combatant = _controller.get_combatant(eid)
		if combatant != null:
			_renderer.set_token_facing(eid, combatant.facing)


func _on_facing_selection_started(_combatant_id: String) -> void:
	_action_panel.set_panel_visible(true)
	_action_panel.disable_all()
	_action_panel.show_confirm_move(true)


func _on_token_facing_preview(combatant_id: String, facing: Vector2i) -> void:
	if _renderer != null:
		_renderer.set_token_facing(combatant_id, facing)


func _on_confirm_move_pressed() -> void:
	_action_panel.show_confirm_move(false)
	if _ui_controller != null:
		_ui_controller.on_confirm_move()


func _on_cleave_selection_started(_combatant_id: String) -> void:
	_action_panel.set_panel_visible(true)
	_action_panel.disable_all()
	_action_panel.show_skip_cleave(true)


func _on_skip_cleave_pressed() -> void:
	_action_panel.show_skip_cleave(false)
	if _ui_controller != null:
		_ui_controller.on_skip_cleave()


func _on_may_cleave(combatant_id: String, combatant_name: String, target_name: String) -> void:
	if _renderer == null:
		return
	var token = _renderer.get_entity_token(combatant_id)
	if token == null:
		return
	var flash := Label.new()
	flash.text = "CLEAVE!"
	flash.add_theme_font_size_override("font_size", 24)
	flash.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	flash.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	flash.add_theme_constant_override("shadow_offset_x", 2)
	flash.add_theme_constant_override("shadow_offset_y", 2)
	# Position above the token in the canvas layer's space
	var token_screen_pos: Vector2 = token.get_global_transform_with_canvas().origin
	flash.position = token_screen_pos + Vector2(-40, -50)
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 1.0)
	tween.tween_callback(flash.queue_free)


func _on_auto_advance() -> void:
	call_deferred("_do_deferred_advance")


func _do_deferred_advance() -> void:
	if _ui_controller != null and _ui_controller.get_state() != CombatUIController.State.COMBAT_OVER:
		_ui_controller.advance()
