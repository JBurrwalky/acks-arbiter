class_name NotificationDisplay
extends CanvasLayer

## Renders toast notifications at the top of the screen.
##
## Notifications slide in from the top-right, stack downward, and auto-dismiss
## after their configured duration. Click to dismiss early (or invoke action).
##
## Built entirely in code — no .tscn dependency for the display nodes.
## The .tscn just instantiates this script on a CanvasLayer.

const MAX_VISIBLE := 5
const TOAST_WIDTH := 420
const TOAST_MIN_HEIGHT := 48
const TOAST_MARGIN := 8
const TOAST_PADDING := 12
const SLIDE_DURATION := 0.25
const TOP_OFFSET := 12
const RIGHT_OFFSET := 12

var _active_toasts: Array[Dictionary] = []  # {panel, timer, data, tween}
var _container: VBoxContainer = null


func _ready() -> void:
	layer = 150
	_build_ui()
	# Tell the notification manager we're ready to receive.
	var manager := _find_notification_manager()
	if manager != null:
		manager.setup(self)
		manager.flush_queue()


# ---------------------------------------------------------------------------
# Public API (called by NotificationManager)
# ---------------------------------------------------------------------------

func show_notification(data: Dictionary) -> void:
	if _active_toasts.size() >= MAX_VISIBLE:
		# Remove oldest to make room.
		_dismiss_toast(_active_toasts[0])

	var toast := _create_toast(data)
	_container.add_child(toast)

	var entry := {
		"panel": toast,
		"data": data,
		"timer": null,
		"tween": null,
	}
	_active_toasts.append(entry)

	# Slide in.
	toast.modulate.a = 0.0
	toast.position.x = 40.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(toast, "modulate:a", 1.0, SLIDE_DURATION)
	tw.tween_property(toast, "position:x", 0.0, SLIDE_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	entry["tween"] = tw

	# Auto-dismiss timer.
	var duration: float = data.get("duration", 4.0)
	if duration > 0.0:
		var timer := get_tree().create_timer(duration)
		entry["timer"] = timer
		timer.timeout.connect(func(): _dismiss_toast(entry))


func dismiss_category(category: String) -> void:
	var to_dismiss: Array[Dictionary] = []
	for entry in _active_toasts:
		if entry["data"].get("category", "") == category:
			to_dismiss.append(entry)
	for entry in to_dismiss:
		_dismiss_toast(entry)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor.anchor_left = 1.0
	anchor.anchor_right = 1.0
	anchor.anchor_top = 0.0
	anchor.anchor_bottom = 0.0
	anchor.offset_left = -(TOAST_WIDTH + RIGHT_OFFSET)
	anchor.offset_right = -RIGHT_OFFSET
	anchor.offset_top = TOP_OFFSET
	anchor.offset_bottom = 600  # Generous space for stacking.
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_container = VBoxContainer.new()
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.add_theme_constant_override("separation", TOAST_MARGIN)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(_container)


func _create_toast(data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(TOAST_WIDTH, TOAST_MIN_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Style: dark panel with colored left border accent.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.08, 0.94)
	style.border_color = data.get("color", Color.WHITE)
	style.border_width_left = 4
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = TOAST_PADDING
	style.content_margin_right = TOAST_PADDING
	style.content_margin_top = TOAST_PADDING * 0.5
	style.content_margin_bottom = TOAST_PADDING * 0.5
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	# Icon label.
	var icon_label := Label.new()
	icon_label.text = data.get("icon", "i")
	icon_label.add_theme_color_override("font_color", data.get("color", Color.WHITE))
	icon_label.add_theme_font_size_override("font_size", 18)
	icon_label.custom_minimum_size = Vector2(24, 0)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(icon_label)

	# Text column.
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	# Title.
	var title_label := Label.new()
	title_label.text = data.get("title", "")
	title_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 1.0))
	title_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title_label)

	# Body (if present).
	var body_text: String = data.get("body", "")
	if not body_text.is_empty():
		var body_label := Label.new()
		body_label.text = body_text
		body_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65, 1.0))
		body_label.add_theme_font_size_override("font_size", 12)
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(body_label)

	# Dismiss button.
	var close_btn := Button.new()
	close_btn.text = "x"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(24, 24)
	close_btn.add_theme_color_override("font_color", Color(0.6, 0.55, 0.50, 1.0))
	close_btn.add_theme_font_size_override("font_size", 12)
	hbox.add_child(close_btn)

	# Click handlers.
	var action: Callable = data.get("action", Callable())
	close_btn.pressed.connect(func():
		_dismiss_by_panel(panel)
	)
	if action.is_valid():
		panel.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				action.call()
				_dismiss_by_panel(panel)
		)

	return panel


# ---------------------------------------------------------------------------
# Dismissal
# ---------------------------------------------------------------------------

func _dismiss_by_panel(panel: PanelContainer) -> void:
	for entry in _active_toasts:
		if entry["panel"] == panel:
			_dismiss_toast(entry)
			return


func _dismiss_toast(entry: Dictionary) -> void:
	if not entry in _active_toasts:
		return
	_active_toasts.erase(entry)

	var panel: PanelContainer = entry["panel"]
	if not is_instance_valid(panel):
		return

	# Fade out.
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 0.0, SLIDE_DURATION * 0.5)
	tw.tween_callback(func():
		if is_instance_valid(panel):
			panel.queue_free()
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_notification_manager() -> NotificationManager:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is NotificationManager:
			return child
	return null
