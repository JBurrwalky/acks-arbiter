class_name CombatScreen
extends CanvasLayer

## Standalone combat screen for wilderness encounters.
##
## Layout: CombatMapRenderer (left ~70%) + right panel with shared HUD widgets
## (InitiativeStrip, StatSummary, ActionButtonPanel) + bottom CombatLogPanel.
## DeclarationOverlay and CombatEndOverlay appear centered as modals.
##
## Owns a CombatUIController that bridges the HUD to the CombatController.
## Supports both interactive (player-driven) and auto-advance (legacy) modes.
##
## Emits combat_finished when combat ends and the player clicks Continue.

signal combat_finished(result: Dictionary)

var _controller: CombatController = null
var _ui_controller: CombatUIController = null
var _auto_advance: bool = false

## Map renderer (loaded lazily to avoid parse-time dependency)
var _map_renderer: Node2D = null

## HUD widgets
var _init_strip: InitiativeStrip = null
var _stat_summary: StatSummary = null
var _action_panel: ActionButtonPanel = null
var _log_panel: CombatLogPanel = null
var _decl_overlay: DeclarationOverlay = null
var _weapon_popup: WeaponSwitchPopup = null
var _end_overlay: CombatEndOverlay = null

## Cached combat result for the Continue button
var _combat_result: Dictionary = {}


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(controller: CombatController) -> void:
	_controller = controller


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 5
	_build_ui()


# ---------------------------------------------------------------------------
# Interactive mode (new)
# ---------------------------------------------------------------------------

## Start interactive combat with full HUD. Player controls PC actions.
func start_interactive() -> void:
	if _controller == null:
		return

	_auto_advance = false

	# Set up the map renderer with the tactical map and roster.
	# Node2D must be embedded via SubViewport to render inside the Control layout.
	if _controller.tactical_map != null:
		var MapRendererScript = load("res://scenes/ui/combat/combat_map_renderer.gd")
		_map_renderer = MapRendererScript.new()
		_map_renderer.setup(_controller.tactical_map, _controller.roster)

		var map_area: Control = get_node_or_null("HSplit/MapArea")
		if map_area != null:
			var svc := SubViewportContainer.new()
			svc.name = "MapViewportContainer"
			svc.set_anchors_preset(Control.PRESET_FULL_RECT)
			svc.stretch = true
			map_area.add_child(svc)

			var sv := SubViewport.new()
			sv.name = "MapViewport"
			sv.transparent_bg = true
			sv.handle_input_locally = true
			svc.add_child(sv)

			sv.add_child(_map_renderer)

	# Create the UI controller
	_ui_controller = CombatUIController.new()
	_ui_controller.setup(_controller)

	# Wire UI controller signals -> HUD widgets
	_ui_controller.show_declaration_requested.connect(_on_show_declarations)
	_ui_controller.initiative_updated.connect(_on_initiative_updated)
	_ui_controller.pc_turn_started.connect(_on_pc_turn_started)
	_ui_controller.action_resolved.connect(_on_action_resolved)
	_ui_controller.combat_ended.connect(_on_combat_ended)
	_ui_controller.log_entry.connect(_on_log_entry)

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

	# Wire deferred auto-advance
	_ui_controller.auto_advance_requested.connect(_on_auto_advance)

	# Wire UI controller signals -> map renderer
	if _map_renderer != null:
		_ui_controller.highlight_reachable.connect(_on_highlight_reachable)
		_ui_controller.highlight_targets.connect(_on_highlight_targets)
		_ui_controller.clear_highlights_requested.connect(_on_clear_highlights)
		_ui_controller.active_token_changed.connect(_on_active_token_changed)
		# Wire renderer input -> UI controller
		_map_renderer.cell_clicked.connect(_on_map_cell_clicked)
		_map_renderer.entity_clicked.connect(_on_map_entity_clicked)
		_map_renderer.right_click_cancel.connect(_on_map_cancel)

	# Build name lookup for the combat log
	var name_lookup: Dictionary = {}
	for c in _controller.roster.get_all():
		name_lookup[c.id] = c.display_name
	_log_panel.set_name_lookup(name_lookup)

	# Wire action panel
	_action_panel.action_selected.connect(_on_action_selected)

	# Hide panels until combat starts
	_action_panel.set_panel_visible(false)
	_decl_overlay.visible = false
	_end_overlay.visible = false

	# Start the combat loop
	_ui_controller.advance()


# ---------------------------------------------------------------------------
# Auto-advance mode (legacy backward compat)
# ---------------------------------------------------------------------------

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
	if _log_panel != null:
		_log_panel.append_text(text)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Main horizontal split: map area (left) + right panel
	var hsplit := HBoxContainer.new()
	hsplit.name = "HSplit"
	hsplit.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(hsplit)

	# Map area (takes up remaining space)
	var map_area := Control.new()
	map_area.name = "MapArea"
	map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Dark background for map area
	var map_bg := ColorRect.new()
	map_bg.color = Color(0.08, 0.08, 0.1)
	map_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_area.add_child(map_bg)
	hsplit.add_child(map_area)

	# Right panel: initiative + stats + actions
	var right_panel := VBoxContainer.new()
	right_panel.name = "RightPanel"
	right_panel.custom_minimum_size.x = 220.0
	right_panel.add_theme_constant_override("separation", 6)
	hsplit.add_child(right_panel)

	_init_strip = InitiativeStrip.new()
	_init_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(_init_strip)

	_stat_summary = StatSummary.new()
	right_panel.add_child(_stat_summary)

	_action_panel = ActionButtonPanel.new()
	right_panel.add_child(_action_panel)

	# Bottom: combat log
	_log_panel = CombatLogPanel.new()
	_log_panel.name = "CombatLog"
	_log_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_log_panel.offset_left = 10.0
	_log_panel.offset_bottom = -10.0
	_log_panel.offset_top = -180.0
	_log_panel.offset_right = 350.0
	add_child(_log_panel)

	# Centered overlays
	_decl_overlay = DeclarationOverlay.new()
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
	_action_panel.set_panel_visible(false)
	_decl_overlay.set_pc_list(alive_pcs)
	_decl_overlay.visible = true


func _on_initiative_updated(order: Array) -> void:
	_init_strip.set_initiative_order(order)


func _on_pc_turn_started(combatant_id: String) -> void:
	_decl_overlay.visible = false
	if _weapon_popup != null:
		_weapon_popup.visible = false
	var combatant = _controller.get_combatant(combatant_id)
	_stat_summary.show_combatant(combatant)
	_init_strip.set_active(combatant_id)
	_action_panel.set_panel_visible(true)
	_action_panel.show_confirm_move(false)
	_action_panel.show_skip_cleave(false)
	var actions := _controller.get_available_actions(combatant_id)
	_action_panel.set_available_actions(actions)


func _on_action_resolved(result: Dictionary) -> void:
	_action_panel.set_panel_visible(false)

	# Sync all token positions from grid state
	_sync_token_positions()

	var target_id: String = result.get("result", {}).get("target_id", "")
	if not target_id.is_empty():
		var target = _controller.get_combatant(target_id)
		if target != null:
			_init_strip.update_hp(target_id, target.get_hp_current(), target.get_hp_max())


func _on_combat_ended(result: Dictionary) -> void:
	_combat_result = result
	_action_panel.set_panel_visible(false)
	_decl_overlay.visible = false
	_end_overlay.show_result(result)


func _on_log_entry(entry: Dictionary) -> void:
	_log_panel.append_event(entry)


# ---------------------------------------------------------------------------
# Map renderer signal handlers
# ---------------------------------------------------------------------------

func _on_highlight_reachable(cells: Array, color: Color) -> void:
	if _map_renderer != null:
		var typed: Array[Vector2i] = []
		for c in cells:
			typed.append(c)
		_map_renderer.highlight_cells(typed, color)


func _on_highlight_targets(entity_ids: Array) -> void:
	if _map_renderer != null:
		var typed: Array[String] = []
		for eid in entity_ids:
			typed.append(eid)
		_map_renderer.highlight_entity_tokens(typed)


func _on_clear_highlights() -> void:
	if _map_renderer != null:
		_map_renderer.clear_highlights()


func _on_active_token_changed(entity_id: String) -> void:
	if _map_renderer != null:
		_map_renderer.set_active_token(entity_id)


# ---------------------------------------------------------------------------
# User input handlers
# ---------------------------------------------------------------------------

func _on_map_cell_clicked(pos: Vector2i) -> void:
	if _ui_controller != null:
		_ui_controller.on_cell_targeted(pos)


func _on_map_entity_clicked(entity_id: String) -> void:
	if _ui_controller != null:
		_ui_controller.on_entity_targeted(entity_id)


func _on_map_cancel() -> void:
	if _ui_controller != null:
		_ui_controller.on_cancel()


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
	var is_armed := combatant != null and not combatant.get_equipped_weapon().is_empty()
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
	_action_panel.disable_action("move")
	_sync_token_positions()


func _sync_token_positions() -> void:
	if _map_renderer == null or _controller == null or _controller.tactical_map == null:
		return
	for eid in _controller.tactical_map.entity_positions:
		var pos: Vector2i = _controller.tactical_map.entity_positions[eid]
		_map_renderer.move_token(eid, pos)
		var combatant = _controller.get_combatant(eid)
		if combatant != null:
			_map_renderer.set_token_facing(eid, combatant.facing)


func _on_facing_selection_started(_combatant_id: String) -> void:
	_action_panel.set_panel_visible(true)
	_action_panel.disable_all()
	_action_panel.show_confirm_move(true)


func _on_token_facing_preview(combatant_id: String, facing: Vector2i) -> void:
	if _map_renderer != null:
		_map_renderer.set_token_facing(combatant_id, facing)


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


func _on_may_cleave(combatant_id: String, _combatant_name: String, _target_name: String) -> void:
	if _map_renderer == null:
		return
	var token: Node2D = _map_renderer.get_entity_token(combatant_id)
	if token == null:
		return
	var flash := Label.new()
	flash.text = "CLEAVE!"
	flash.add_theme_font_size_override("font_size", 24)
	flash.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	flash.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	flash.add_theme_constant_override("shadow_offset_x", 2)
	flash.add_theme_constant_override("shadow_offset_y", 2)
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
