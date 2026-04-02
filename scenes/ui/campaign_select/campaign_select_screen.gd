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


# ---------------------------------------------------------------------------
# UI node references (built programmatically in _build_ui)
# ---------------------------------------------------------------------------

var _list_container: VBoxContainer   # populated by _refresh_list()
var _scroll: ScrollContainer
var _create_dialog: PanelContainer   # new-campaign dialog (hidden until needed)
var _name_input: LineEdit
var _world_input: LineEdit
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
	_create_dialog.visible = false


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

	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 0.97)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# Centered panel  (600 wide × 520 tall, anchored to viewport center)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300.0
	panel.offset_top = -260.0
	panel.offset_right = 300.0
	panel.offset_bottom = 260.0
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# --- Title ---
	var title := Label.new()
	title.text = "ACKS ARBITER"
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
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 320)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll)

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


func _build_create_dialog() -> PanelContainer:
	var dialog := PanelContainer.new()
	dialog.anchor_left = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_bottom = 0.5
	dialog.offset_left = -220.0
	dialog.offset_top = -140.0
	dialog.offset_right = 220.0
	dialog.offset_bottom = 140.0
	# Raise draw order so it sits above the campaign list panel
	dialog.z_index = 10

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	dialog.add_child(vbox)

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
	vbox.add_child(_world_input)

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
	cancel_btn.pressed.connect(func(): _create_dialog.visible = false)
	btn_row.add_child(cancel_btn)

	return dialog


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
		empty_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_list_container.add_child(empty_label)
		return

	for c in campaigns:
		_list_container.add_child(_make_campaign_row(c))


func _make_campaign_row(c: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

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

	return row


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
	_create_dialog.visible = true
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

	_create_dialog.visible = false
	campaign_selected.emit(campaign_id)


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
