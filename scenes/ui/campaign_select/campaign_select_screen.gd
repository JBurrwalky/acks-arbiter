extends CanvasLayer

## Campaign selection screen — entry point when no session is active.
##
## Implements the ManagedScene interface via duck typing (cannot extend ManagedScene
## because GDScript has single inheritance and this must extend CanvasLayer).
##
## Signals:
##   campaign_selected(campaign_id) — player chose an existing campaign to load.
##
## NavigationStack calls enter()/exit()/save_state()/restore_state() if present.
## main_scene.gd (and later the session runner) listens to campaign_selected.

## Emitted when the player clicks "Load" on a campaign entry.
## The receiver is responsible for calling GameState.start_session().
signal campaign_selected(campaign_id: String)

## Emitted when the player creates a new campaign via the dialog.
## Routes to party creation flow instead of direct session load.
signal campaign_created(campaign_id: String)

## Emitted when the player chooses to GENERATE a full simulated world.
## Routes to the campaign-creation (setting-generation) flow.
signal create_world_requested


const ROW_BG_COLOR := Color(0.94, 0.89, 0.78, 0.42)
const ROW_BORDER_COLOR := Color(0.44, 0.31, 0.18, 0.88)
const MODAL_BACKDROP_COLOR := Color(0.09, 0.07, 0.05, 0.52)


# ---------------------------------------------------------------------------
# UI node references (built programmatically in _build_ui)
# ---------------------------------------------------------------------------

var _list_container: VBoxContainer   # populated by _refresh_list()
var _scroll: ScrollContainer
var _create_dialog_backdrop: ColorRect
var _create_dialog: PanelContainer   # new-campaign dialog (hidden until needed)
var _name_input: LineEdit
var _world_input: LineEdit
var _map_choice: OptionButton
var _confirm_dialog: ConfirmationDialog
var _pending_delete_id: String = ""


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 10
	_build_ui()


# ---------------------------------------------------------------------------
# ManagedScene interface (duck-typed)
# ---------------------------------------------------------------------------

func enter(_params: Dictionary = {}) -> void:
	_refresh_list()


func exit() -> void:
	_set_create_dialog_visible(false)


func save_state() -> Dictionary:
	return {"scroll_v": _scroll.scroll_vertical}


func restore_state(data: Dictionary) -> void:
	_scroll.scroll_vertical = data.get("scroll_v", 0)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Full-viewport root control (layout anchor for children)
	var root := Control.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	UiSurfaceStyles.apply_vellum_text_theme(root)

	# Full-screen vellum background
	var bg := UiSurfaceStyles.make_background_rect()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# Centered panel  (600 wide × 520 tall, anchored to viewport center)
	var panel_frame := PanelContainer.new()
	panel_frame.anchor_left = 0.5
	panel_frame.anchor_top = 0.5
	panel_frame.anchor_right = 0.5
	panel_frame.anchor_bottom = 0.5
	panel_frame.offset_left = -300.0
	panel_frame.offset_top = -260.0
	panel_frame.offset_right = 300.0
	panel_frame.offset_bottom = 260.0
	panel_frame.add_theme_stylebox_override("panel", _make_frame_style())
	root.add_child(panel_frame)

	var panel_frame_margin := MarginContainer.new()
	panel_frame_margin.add_theme_constant_override("margin_left", 8)
	panel_frame_margin.add_theme_constant_override("margin_right", 8)
	panel_frame_margin.add_theme_constant_override("margin_top", 8)
	panel_frame_margin.add_theme_constant_override("margin_bottom", 8)
	panel_frame.add_child(panel_frame_margin)

	var panel_inner := PanelContainer.new()
	panel_inner.add_theme_stylebox_override("panel", _make_vellum_style())
	panel_frame_margin.add_child(panel_inner)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 18)
	panel_margin.add_theme_constant_override("margin_right", 18)
	panel_margin.add_theme_constant_override("margin_top", 18)
	panel_margin.add_theme_constant_override("margin_bottom", 18)
	panel_inner.add_child(panel_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel_margin.add_child(vbox)

	# --- Title ---
	var title := Label.new()
	title.text = "Axiom of Conquest"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Select a Campaign"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# --- Campaign list ---
	var list_frame := PanelContainer.new()
	list_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_frame.add_theme_stylebox_override("panel", _make_list_inset_style())
	vbox.add_child(list_frame)

	var list_frame_margin := MarginContainer.new()
	list_frame_margin.add_theme_constant_override("margin_left", 4)
	list_frame_margin.add_theme_constant_override("margin_right", 4)
	list_frame_margin.add_theme_constant_override("margin_top", 4)
	list_frame_margin.add_theme_constant_override("margin_bottom", 4)
	list_frame.add_child(list_frame_margin)

	var list_panel := PanelContainer.new()
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_theme_stylebox_override("panel", _make_vellum_style())
	list_frame_margin.add_child(list_panel)

	var list_margin := MarginContainer.new()
	list_margin.add_theme_constant_override("margin_left", 10)
	list_margin.add_theme_constant_override("margin_right", 10)
	list_margin.add_theme_constant_override("margin_top", 10)
	list_margin.add_theme_constant_override("margin_bottom", 10)
	list_panel.add_child(list_margin)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 320)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_margin.add_child(_scroll)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list_container)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# --- Footer: new campaign button ---
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(footer)

	var new_btn := Button.new()
	new_btn.text = "New Campaign"
	new_btn.custom_minimum_size = Vector2(160, 36)
	new_btn.pressed.connect(_on_new_campaign_pressed)
	footer.add_child(new_btn)

	# Generate a full simulated world (the setting-generation pipeline).
	var gen_btn := Button.new()
	gen_btn.text = "✦ Generate World"
	gen_btn.custom_minimum_size = Vector2(170, 36)
	gen_btn.pressed.connect(func(): create_world_requested.emit())
	footer.add_child(gen_btn)

	_create_dialog_backdrop = ColorRect.new()
	_create_dialog_backdrop.color = MODAL_BACKDROP_COLOR
	_create_dialog_backdrop.anchor_right = 1.0
	_create_dialog_backdrop.anchor_bottom = 1.0
	_create_dialog_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_create_dialog_backdrop.visible = false
	root.add_child(_create_dialog_backdrop)

	# --- New campaign dialog (hidden initially) ---
	_create_dialog = _build_create_dialog()
	_create_dialog.visible = false
	root.add_child(_create_dialog)

	# --- Confirm delete dialog ---
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Delete Campaign?"
	_confirm_dialog.dialog_text = "Delete this campaign permanently?\nAll progress will be lost."
	_confirm_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(_confirm_dialog)
	UiSurfaceStyles.apply_framed_window_chrome(_confirm_dialog)


func _build_create_dialog() -> PanelContainer:
	var dialog := PanelContainer.new()
	dialog.anchor_left = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_bottom = 0.5
	dialog.offset_left = -240.0
	dialog.offset_top = -180.0
	dialog.offset_right = 240.0
	dialog.offset_bottom = 180.0
	dialog.add_theme_stylebox_override("panel", _make_frame_style())
	# Raise draw order so it sits above the campaign list panel
	dialog.z_index = 10

	var dialog_frame_margin := MarginContainer.new()
	dialog_frame_margin.add_theme_constant_override("margin_left", 6)
	dialog_frame_margin.add_theme_constant_override("margin_right", 6)
	dialog_frame_margin.add_theme_constant_override("margin_top", 6)
	dialog_frame_margin.add_theme_constant_override("margin_bottom", 6)
	dialog.add_child(dialog_frame_margin)

	var dialog_inner := PanelContainer.new()
	dialog_inner.add_theme_stylebox_override("panel", _make_vellum_style())
	dialog_frame_margin.add_child(dialog_inner)

	var dialog_margin := MarginContainer.new()
	dialog_margin.add_theme_constant_override("margin_left", 16)
	dialog_margin.add_theme_constant_override("margin_right", 16)
	dialog_margin.add_theme_constant_override("margin_top", 16)
	dialog_margin.add_theme_constant_override("margin_bottom", 16)
	dialog_inner.add_child(dialog_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	dialog_margin.add_child(vbox)

	var dlg_title := Label.new()
	dlg_title.text = "New Campaign"
	dlg_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dlg_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(dlg_title)

	var name_label := Label.new()
	name_label.text = "Campaign Name:"
	vbox.add_child(name_label)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "e.g. The Iron Reaches"
	_name_input.custom_minimum_size = Vector2(380, 0)
	vbox.add_child(_name_input)

	var world_label := Label.new()
	world_label.text = "World Name (optional):"
	vbox.add_child(world_label)

	_world_input = LineEdit.new()
	_world_input.placeholder_text = "e.g. Mythworld"
	_world_input.custom_minimum_size = Vector2(380, 0)
	vbox.add_child(_world_input)

	var map_label := Label.new()
	map_label.text = "Starting Content:"
	vbox.add_child(map_label)

	_map_choice = OptionButton.new()
	_map_choice.custom_minimum_size = Vector2(380, 0)
	_map_choice.add_item("Principality of Avalon (600-hex test campaign)")
	_map_choice.set_item_metadata(0, "avalon")
	_map_choice.add_item("Ashford Vale (legacy 31-hex test region)")
	_map_choice.set_item_metadata(1, "ashford_vale")
	_map_choice.select(0)
	vbox.add_child(_map_choice)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var create_btn := Button.new()
	create_btn.text = "Create"
	create_btn.custom_minimum_size = Vector2(100, 34)
	create_btn.pressed.connect(_on_create_confirmed)
	btn_row.add_child(create_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 34)
	cancel_btn.pressed.connect(func(): _set_create_dialog_visible(false))
	btn_row.add_child(cancel_btn)

	return dialog


func _make_frame_style() -> StyleBoxFlat:
	return UiSurfaceStyles.make_filled_frame_style()


func _make_vellum_style() -> StyleBox:
	return UiSurfaceStyles.make_vellum_style()


func _make_list_inset_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.92, 0.82, 0.28)
	style.border_color = UiSurfaceStyles.FRAME_BORDER_COLOR
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	return style


func _make_campaign_row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ROW_BG_COLOR
	style.border_color = ROW_BORDER_COLOR
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	return style


# ---------------------------------------------------------------------------
# Campaign list
# ---------------------------------------------------------------------------

func _refresh_list() -> void:
	# Clear existing rows
	for child in _list_container.get_children():
		child.queue_free()

	var campaigns: Array = CampaignRepository.list_campaigns()

	if campaigns.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No campaigns yet. Create one below."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list_container.add_child(empty_label)
		return

	for c in campaigns:
		_list_container.add_child(_make_campaign_row(c))


func _make_campaign_row(c: Dictionary) -> PanelContainer:
	var row_panel := PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.add_theme_stylebox_override("panel", _make_campaign_row_style())

	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_left", 10)
	row_margin.add_theme_constant_override("margin_right", 10)
	row_margin.add_theme_constant_override("margin_top", 8)
	row_margin.add_theme_constant_override("margin_bottom", 8)
	row_panel.add_child(row_margin)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	row_margin.add_child(row)

	# Campaign info label
	var info := Label.new()
	var world: String = c.get("world_name", "")
	info.text = c.get("name", "(unnamed)")
	if not world.is_empty():
		info.text += "  —  " + world
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	# Load button
	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.custom_minimum_size = Vector2(70, 30)
	var cid: String = c.get("id", "")
	load_btn.pressed.connect(_on_load_pressed.bind(cid))
	row.add_child(load_btn)

	# Delete button
	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.custom_minimum_size = Vector2(70, 30)
	del_btn.pressed.connect(_on_delete_pressed.bind(cid))
	row.add_child(del_btn)

	return row_panel


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

func _on_load_pressed(campaign_id: String) -> void:
	if campaign_id.is_empty():
		push_error("CampaignSelectScreen: load pressed with empty campaign_id")
		return
	campaign_selected.emit(campaign_id)


func _on_new_campaign_pressed() -> void:
	_name_input.text = ""
	_world_input.text = ""
	_set_create_dialog_visible(true)
	_name_input.grab_focus()


func _on_create_confirmed() -> void:
	var name: String = _name_input.text.strip_edges()
	if name.is_empty():
		# Flash the input red briefly to indicate it's required
		_name_input.modulate = Color.RED
		var tween := create_tween()
		tween.tween_property(_name_input, "modulate", Color.WHITE, 0.4)
		return

	var world: String = _world_input.text.strip_edges()
	if world.is_empty():
		world = name + " World"

	var campaign_id := CampaignRepository.create_campaign(name, world)
	if campaign_id.is_empty():
		push_error("CampaignSelectScreen: create_campaign failed for name=%s" % name)
		return

	var choice: String = String(_map_choice.get_item_metadata(_map_choice.get_selected_id()))
	var seeded: bool = false
	match choice:
		"ashford_vale":
			seeded = TestContentSeeder.seed_legacy_ashford_vale(campaign_id)
		"avalon":
			seeded = TestContentSeeder.seed_avalon_test_campaign(campaign_id)
		_:
			push_error("CampaignSelectScreen: unknown map choice '%s'" % choice)
	if not seeded:
		push_error("CampaignSelectScreen: seeding failed for choice=%s" % choice)
		return

	_set_create_dialog_visible(false)
	campaign_created.emit(campaign_id)


func _on_delete_pressed(campaign_id: String) -> void:
	if campaign_id.is_empty():
		return
	_pending_delete_id = campaign_id
	# Populate dialog text with campaign name for clarity
	var c := CampaignRepository.get_campaign(campaign_id)
	var cname: String = c.get("name", campaign_id) if not c.is_empty() else campaign_id
	_confirm_dialog.dialog_text = "Delete \"%s\" permanently?\nAll progress will be lost." % cname
	_confirm_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	if _pending_delete_id.is_empty():
		return
	var ok := CampaignRepository.delete_campaign(_pending_delete_id)
	if not ok:
		push_error("CampaignSelectScreen: delete_campaign failed for id=%s" % _pending_delete_id)
	_pending_delete_id = ""
	_refresh_list()


func _set_create_dialog_visible(is_visible: bool) -> void:
	_create_dialog.visible = is_visible
	if _create_dialog_backdrop != null:
		_create_dialog_backdrop.visible = is_visible
