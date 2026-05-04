class_name DungeonCombatOverlay
extends CanvasLayer

## Combat HUD overlay for dungeon in-place encounters.
##
## Sits on CanvasLayer 10 (above the dungeon HUD at layer 1).
## Composes the shared combat HUD widgets: InitiativeStrip, StatSummary,
## ActionButtonPanel. DeclarationOverlay and CombatEndOverlay
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

## InitiativeStrip relocated in H.0 to top-level InitiativeOverlay (CanvasLayer
## at layer 25, right-edge). _initiative_overlay is looked up via the
## "initiative_overlay" group; its set_initiative_order / set_active /
## update_hp methods are forwarded to the wrapped strip.
var _initiative_overlay: Node = null
var _stat_summary: StatSummary = null
var _action_panel: ActionButtonPanel = null

## Pixel reserve at the right edge of the screen for the InitiativeOverlay.
## Sourced from InitiativeOverlay so any future change to STRIP_WIDTH /
## RIGHT_MARGIN propagates to both combat surfaces automatically. H.0 polish
## per the umbrella plan.
const STRIP_OVERLAY_RESERVE := preload("res://scenes/ui/hud/initiative_overlay.gd").STRIP_OVERLAY_RESERVE
# _log_panel removed in γ.5 — embedded UnifiedLog in SessionStatusBar replaces
# the per-screen CombatLogPanel. Combat events still flow through
# CombatUIController → GameLog autoload signals → unified log Combat tab.
var _decl_overlay: DeclarationOverlay = null
var _weapon_popup: WeaponSwitchPopup = null
var _end_overlay: CombatEndOverlay = null
var _round_label: Label = null
var _leave_field_btn: Button = null


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _ui_controller: CombatUIController = null
var _renderer = null  # DungeonMapRenderer (duck-typed — no class_name)
var _controller: CombatController = null

## Cached combat result for the Continue button.
var _combat_result: Dictionary = {}

## Context menu support
var _context_menu = null
var _ContextMenuBuilder = preload("res://engine/subsystems/combat/combat_context_menu_builder.gd")
var _ContextMenuScene = preload("res://scenes/maps/dungeon_context_menu.gd")

## Connections we need to disconnect on cleanup.
var _cell_conn: Callable = Callable()
var _entity_conn: Callable = Callable()
var _right_click_conn: Callable = Callable()


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

	# Wire context menu
	_ui_controller.context_menu_requested.connect(_on_context_menu_requested)

	# Wire token animation triggers (lunge on melee hit, drop on downed).
	if not EventBus.damage_dealt.is_connected(_on_damage_for_lunge):
		EventBus.damage_dealt.connect(_on_damage_for_lunge)
	if not EventBus.combatant_downed.is_connected(_on_combatant_downed_for_drop):
		EventBus.combatant_downed.connect(_on_combatant_downed_for_drop)

	# Wire renderer input -> UI controller
	_cell_conn = _on_renderer_cell_clicked
	_entity_conn = _on_renderer_entity_clicked
	_right_click_conn = _on_renderer_right_clicked
	renderer.cell_clicked.connect(_cell_conn)
	renderer.entity_clicked.connect(_entity_conn)
	if renderer.has_signal("cell_right_clicked"):
		renderer.cell_right_clicked.connect(_right_click_conn)

	# Wire action panel -> UI controller
	_action_panel.action_selected.connect(_on_action_selected)

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
		if _renderer.has_signal("cell_right_clicked") and \
				_renderer.cell_right_clicked.is_connected(_right_click_conn):
			_renderer.cell_right_clicked.disconnect(_right_click_conn)

	_ui_controller = null
	_controller = null
	_renderer = null
	queue_free()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Right panel (VBoxContainer) — stat summary + actions. InitiativeStrip
	# relocated to the top-level InitiativeOverlay HUD (H.0); right_panel
	# shifts left by STRIP_OVERLAY_RESERVE so the overlay sits flush right.
	var right_panel := VBoxContainer.new()
	right_panel.name = "RightPanel"
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.offset_left = -float(220 + STRIP_OVERLAY_RESERVE)
	right_panel.offset_right = -float(STRIP_OVERLAY_RESERVE)
	right_panel.offset_top = 10.0
	# Leave room for SessionStatusBar plus a small gap.
	right_panel.offset_bottom = -float(SessionStatusBar.BAR_HEIGHT + 10)
	right_panel.add_theme_constant_override("separation", 6)
	add_child(right_panel)

	_initiative_overlay = get_tree().get_first_node_in_group("initiative_overlay")

	_stat_summary = StatSummary.new()
	_stat_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(_stat_summary)

	_action_panel = ActionButtonPanel.new()
	right_panel.add_child(_action_panel)

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

	# "Leave the Field" button — shown only when all enemies are dead
	_leave_field_btn = Button.new()
	_leave_field_btn.name = "LeaveFieldButton"
	_leave_field_btn.text = "Leave the Field"
	_leave_field_btn.anchor_left = 0.45
	_leave_field_btn.anchor_right = 0.55
	_leave_field_btn.anchor_top = 0.25
	_leave_field_btn.anchor_bottom = 0.31
	_leave_field_btn.offset_left = 0.0
	_leave_field_btn.offset_right = 0.0
	_leave_field_btn.offset_top = 0.0
	_leave_field_btn.offset_bottom = 0.0
	_leave_field_btn.visible = false
	_leave_field_btn.pressed.connect(_on_leave_field_pressed)
	add_child(_leave_field_btn)

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

var _combat_banner_shown: bool = false

func _on_show_declarations(alive_pcs: Array) -> void:
	_show_combat_banner()
	_round_label.text = "Round %d — Declarations" % _controller.round_number
	_action_panel.set_panel_visible(false)
	_decl_overlay.set_pc_list(alive_pcs)
	_decl_overlay.visible = true


func _on_initiative_updated(order: Array) -> void:
	if _initiative_overlay != null:
		_initiative_overlay.set_initiative_order(order)


func _on_pc_turn_started(combatant_id: String) -> void:
	_round_label.text = "Round %d" % _controller.round_number
	_decl_overlay.visible = false
	if _weapon_popup != null:
		_weapon_popup.visible = false

	# Update stat summary
	var combatant = _controller.get_combatant(combatant_id)
	_stat_summary.show_combatant(combatant)

	# Update initiative strip active marker (forwarded to InitiativeOverlay)
	if _initiative_overlay != null:
		_initiative_overlay.set_active(combatant_id)

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
		if target != null and _initiative_overlay != null:
			_initiative_overlay.update_hp(target_id, target.get_hp_current(), target.get_hp_max())

	# Show "Leave the Field" when all enemies are down
	_update_leave_field_visibility()


func _on_combat_ended(result: Dictionary) -> void:
	_combat_result = result
	_action_panel.set_panel_visible(false)
	_decl_overlay.visible = false
	_round_label.text = "Combat Over"
	_end_overlay.show_result(result)


# ---------------------------------------------------------------------------
# Map renderer signal handlers
# ---------------------------------------------------------------------------

func _on_highlight_reachable(cells: Array, color: Color) -> void:
	if _renderer != null:
		_renderer.highlight_cells(cells, color)


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

func _on_renderer_cell_clicked(pos) -> void:
	## pos is Vector3i at runtime from both combat_map_renderer_3d and
	## dungeon_map_renderer_3d (signal declared Vector2i in the dungeon renderer,
	## but emit site passes Vector3i). Accept untyped to sidestep the mismatch.
	if _ui_controller != null:
		var pos_3d: Vector3i = pos if pos is Vector3i else Vector3i(pos.x, pos.y, 0)
		_ui_controller.on_cell_targeted(pos_3d)


func _on_renderer_entity_clicked(entity_id: String) -> void:
	if _ui_controller != null:
		_ui_controller.on_entity_targeted(entity_id)


func _on_renderer_right_clicked(cell_pos, screen_pos: Vector2) -> void:
	if _ui_controller != null:
		var cell_3d: Vector3i = cell_pos if cell_pos is Vector3i else Vector3i(cell_pos.x, cell_pos.y, 0)
		_ui_controller.on_cell_right_clicked(cell_3d, screen_pos)


func _on_context_menu_requested(
		combatant_id: String, target_cell: Vector3i, screen_pos: Vector2) -> void:
	var options: Array = _ContextMenuBuilder.build_menu(
		combatant_id, target_cell, _controller, null)
	if options.is_empty():
		_ui_controller.on_context_menu_cancelled()
		return

	if _context_menu != null and is_instance_valid(_context_menu):
		_context_menu.queue_free()
		_context_menu = null

	_context_menu = _ContextMenuScene.new()
	add_child(_context_menu)
	_context_menu.option_selected.connect(_on_context_option_selected)
	_context_menu.cancelled.connect(_on_context_menu_dismissed)
	_context_menu.show_at(screen_pos, options, null)


func _on_context_option_selected(action_data: Dictionary) -> void:
	if _ui_controller != null:
		_ui_controller.on_context_action(action_data)


func _on_context_menu_dismissed() -> void:
	if _ui_controller != null:
		_ui_controller.on_context_menu_cancelled()


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


func _update_leave_field_visibility() -> void:
	if _leave_field_btn == null or _controller == null:
		return
	_leave_field_btn.visible = _controller.roster.is_enemies_eliminated()


func _on_leave_field_pressed() -> void:
	_leave_field_btn.visible = false
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
	if _renderer == null or _controller == null or _controller.voxel_map == null:
		return
	for eid in _controller.voxel_map.entity_positions:
		var pos: Vector3i = _controller.voxel_map.entity_positions[eid]
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


## Play a lunge on the attacker when melee-range damage is dealt.
func _on_damage_for_lunge(target_id: String, _amount: int, _damage_type: String,
		source_id: String) -> void:
	if _controller == null or _renderer == null or source_id.is_empty():
		return
	var attacker = _controller.get_combatant(source_id)
	var target = _controller.get_combatant(target_id)
	if attacker == null or target == null:
		return
	var a_pos: Vector3i = attacker.grid_position
	var t_pos: Vector3i = target.grid_position
	var dx: int = absi(a_pos.x - t_pos.x)
	var dy: int = absi(a_pos.y - t_pos.y)
	if maxi(dx, dy) > 1 or a_pos.z != t_pos.z:
		return
	var target_world := VoxelGrid.cell_to_world(t_pos.x, t_pos.y, t_pos.z)
	target_world.y += 0.2  # Match the dungeon renderer's token Y offset.
	_renderer.play_token_attack(source_id, target_world)


## Play the drop-to-floor animation when a combatant is downed.
func _on_combatant_downed_for_drop(combatant_id: String, _attacker_id: String) -> void:
	if _renderer == null:
		return
	_renderer.play_token_downed(combatant_id)


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
	var token_screen_pos: Vector2
	if token is Node2D:
		token_screen_pos = token.get_global_transform_with_canvas().origin
	else:
		# 3D token — project world position to screen
		var vp: Viewport = token.get_viewport()
		var cam: Camera3D = vp.get_camera_3d() if vp != null else null
		if cam != null:
			token_screen_pos = cam.unproject_position(token.global_position)
		else:
			token_screen_pos = Vector2(400, 300)
	flash.position = token_screen_pos + Vector2(-40, -50)
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 1.0)
	tween.tween_callback(flash.queue_free)


func _show_combat_banner() -> void:
	if _combat_banner_shown:
		return
	_combat_banner_shown = true
	var banner := Label.new()
	banner.text = "COMBAT!"
	banner.add_theme_font_size_override("font_size", 48)
	banner.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	banner.add_theme_constant_override("shadow_offset_x", 3)
	banner.add_theme_constant_override("shadow_offset_y", 3)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.offset_left = -150.0
	banner.offset_right = 150.0
	banner.offset_top = -40.0
	banner.offset_bottom = 40.0
	add_child(banner)
	var tween := create_tween()
	tween.tween_interval(0.8)
	tween.tween_property(banner, "modulate:a", 0.0, 0.5)
	tween.tween_callback(banner.queue_free)


func _on_auto_advance() -> void:
	call_deferred("_do_deferred_advance")


func _do_deferred_advance() -> void:
	if _ui_controller != null and _ui_controller.get_state() != CombatUIController.State.COMBAT_OVER:
		_ui_controller.advance()
