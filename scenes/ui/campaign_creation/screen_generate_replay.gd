extends Control

## Screen C: Generation + History Replay (gdd-campaign-creation-ui.md §5).
## Generation runs to completion up front; this screen PACES the presentation —
## the political map animates epoch by epoch from the stored replay frames, decoded
## via the tested ReplayFrameDecoder, emitting EventBus.replay_frame_advanced per
## step. [Skip ▸] jumps to review. The frame stepping + map paint are real; the
## caption strip / scrubber polish is a light editor pass.

signal review_requested

const _FRAME_SECONDS := 0.6   # §5 pacing ≈ 1 frame / 0.5–0.75 s

var _frames: Array = []
var _ordered_hexes: Array = []
var _index: int = 0
var _speed: float = 1.0
var _timer: Timer
var _map: Control
var _caption: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.09, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_top = 18
	root.offset_right = -24
	root.offset_bottom = -18
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var title := Label.new()
	title.text = "The Ages Turn…"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.93, 0.86, 0.7))
	root.add_child(title)

	_map = preload("res://scenes/ui/campaign_creation/political_map_view.gd").new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_map)

	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override("font_color", Color(0.82, 0.77, 0.66))
	root.add_child(_caption)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(footer)
	var skip := Button.new()
	skip.text = "Skip ▸"
	skip.custom_minimum_size = Vector2(120, 40)
	skip.pressed.connect(finish)
	footer.add_child(skip)

	_timer = Timer.new()
	_timer.one_shot = false
	_timer.timeout.connect(_advance)
	add_child(_timer)


## Load the stored frames + palette and play them. Generation has already
## completed; this is pure presentation, re-watchable from Screen D for free.
func begin_replay(campaign_id: String) -> void:
	_frames = SettingRepository.list_replay_frames(campaign_id)
	_ordered_hexes = SettingRepository.list_hexes(campaign_id)
	_index = 0
	if _map != null:
		_map.bind(_ordered_hexes, SettingRepository.list_replay_palette(campaign_id))
	if _frames.is_empty():
		finish()
		return
	_timer.wait_time = _FRAME_SECONDS / maxf(_speed, 0.25)
	_timer.start()
	_show_frame(0)


func _advance() -> void:
	_index += 1
	if _index >= _frames.size():
		_timer.stop()
		finish()
		return
	_show_frame(_index)


func _show_frame(i: int) -> void:
	var frame: Dictionary = _frames[i]
	var owners := ReplayFrameDecoder.decode_owner_map(
		str(frame.get("owner_by_hex", "")), _ordered_hexes)
	if _map != null:
		_map.show_owners(owners)
	if _caption != null:
		_caption.text = "epoch %d / %d" % [i + 1, _frames.size()]
	EventBus.replay_frame_advanced.emit(int(frame.get("tick", 0)))


func set_speed(mult: float) -> void:
	_speed = mult
	if _timer != null and not _timer.is_stopped():
		_timer.wait_time = _FRAME_SECONDS / maxf(_speed, 0.25)


func finish() -> void:
	if _timer != null:
		_timer.stop()
	review_requested.emit()
