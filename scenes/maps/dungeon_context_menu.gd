extends PanelContainer

## Right-click context menu for dungeon exploration.
##
## Built dynamically from DungeonContextMenuBuilder output.
## Auto-pauses the scheduler when shown, restores previous speed on close.
## Lives as a child of DungeonHUD CanvasLayer.

signal option_selected(action_data: Dictionary)
signal cancelled()


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const CATEGORY_ORDER := ["universal", "environment", "entity", "self"]

## Colors for category separator labels.
const CATEGORY_COLORS := {
	"environment": Color(0.9, 0.85, 0.6),
	"entity": Color(0.6, 0.85, 0.9),
	"self": Color(0.7, 0.9, 0.7),
}


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _scheduler_loop = null
var _was_paused: bool = true
var _previous_speed: int = 0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	visible = false
	# Dark semi-transparent background matching project style.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	style.border_color = Color(0.4, 0.4, 0.5, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", style)
	# Minimum width for readability.
	custom_minimum_size.x = 180


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Click outside the menu dismisses it.
	if event is InputEventMouseButton and event.pressed:
		if not get_global_rect().has_point(event.global_position):
			_dismiss()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Show the context menu at [param screen_pos] with the given [param options].
## [param scheduler_loop]: SchedulerLoop reference for auto-pause (or null).
func show_at(screen_pos: Vector2, options: Array, scheduler_loop = null) -> void:
	_scheduler_loop = scheduler_loop

	# Auto-pause.
	if _scheduler_loop != null and _scheduler_loop.has_method("is_paused"):
		_was_paused = _scheduler_loop.is_paused()
		if not _was_paused:
			_previous_speed = _scheduler_loop.get_speed() if _scheduler_loop.has_method("get_speed") else 1
			_scheduler_loop.pause()

	# Clear previous content.
	_clear_buttons()

	# Build the button list grouped by category.
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)

	var last_category := ""
	for opt in options:
		var cat: String = opt.get("category", "universal")

		# Add separator between categories.
		if cat != last_category and last_category != "":
			var sep := HSeparator.new()
			sep.add_theme_constant_override("separation", 4)
			vbox.add_child(sep)
		last_category = cat

		var btn := Button.new()
		btn.text = opt.get("label", "???")
		btn.disabled = not opt.get("enabled", true)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size.y = 28

		# Tooltip for disabled items.
		var tip: String = opt.get("tooltip", "")
		if not tip.is_empty():
			btn.tooltip_text = tip

		# Style: flat buttons, dim disabled ones.
		btn.flat = true
		if btn.disabled:
			btn.modulate = Color(0.5, 0.5, 0.5, 0.7)

		var action_data: Dictionary = opt.get("action_data", {})
		btn.pressed.connect(_on_option_pressed.bind(action_data))
		vbox.add_child(btn)

	# Position the popup, keeping it on-screen.
	visible = true
	await get_tree().process_frame  # Wait for layout.
	var vp_size := get_viewport().get_visible_rect().size
	var menu_size := size
	var pos := screen_pos
	if pos.x + menu_size.x > vp_size.x:
		pos.x = vp_size.x - menu_size.x - 4.0
	if pos.y + menu_size.y > vp_size.y:
		pos.y = vp_size.y - menu_size.y - 4.0
	pos.x = maxf(pos.x, 4.0)
	pos.y = maxf(pos.y, 4.0)
	position = pos


## Close the context menu without selecting anything.
func dismiss() -> void:
	_dismiss()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _on_option_pressed(action_data: Dictionary) -> void:
	var action_type: String = action_data.get("action_type", "")
	if action_type == "cancel":
		_dismiss()
		return
	option_selected.emit(action_data)
	_close()


func _dismiss() -> void:
	cancelled.emit()
	_close()


func _close() -> void:
	visible = false
	_clear_buttons()
	# Restore scheduler state.
	if _scheduler_loop != null and not _was_paused:
		if _scheduler_loop.has_method("resume"):
			_scheduler_loop.resume(_previous_speed)
	_scheduler_loop = null


func _clear_buttons() -> void:
	for child in get_children():
		if child is VBoxContainer:
			child.queue_free()
