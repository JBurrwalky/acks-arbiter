extends Control

## Screen C: Generation + History Replay (gdd-campaign-creation-ui.md §5).
## Generation runs to completion up front; this screen PACES the presentation — the
## political map animates epoch by epoch from the stored replay frames, decoded via
## the tested ReplayFrameDecoder, emitting EventBus.replay_frame_advanced per step.
##
## Transport controls let the player examine the generation STEP BY STEP: a scrubber
## plus rewind / step-back / play-pause / step-forward / jump-to-end. Auto-play stops
## (rather than auto-advancing to review) at the present day so the timeline can be
## rewound and inspected; [Continue to Review ▸] commits.

signal review_requested

const _FRAME_SECONDS := 0.6   # §5 pacing ≈ 1 frame / 0.5–0.75 s
const _YEARS_PER_TICK := 25   # 4,000 yr of deep history ÷ 160 standard ticks (UI §4)
const _SPEEDS := [0.5, 1.0, 2.0, 4.0]
const _SPEED_DEFAULT_IDX := 1   # 1×

var _frames: Array = []
var _ordered_hexes: Array = []
var _index: int = 0
var _speed: float = 1.0
var _playing: bool = false
var _last_tick: int = 0
var _timer: Timer
var _map: Control
var _caption: Label
var _scrub: HSlider
var _play_btn: Button
var _pos_label: Label


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
	root.add_theme_constant_override("separation", 8)
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

	# --- scrubber row -------------------------------------------------------
	var scrub_row := HBoxContainer.new()
	scrub_row.add_theme_constant_override("separation", 12)
	root.add_child(scrub_row)
	_scrub = HSlider.new()
	_scrub.min_value = 0
	_scrub.max_value = 0
	_scrub.step = 1
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scrub.tooltip_text = "Drag to rewind or skip to any epoch of the generation."
	_scrub.value_changed.connect(_on_scrub)
	scrub_row.add_child(_scrub)
	_pos_label = Label.new()
	_pos_label.custom_minimum_size = Vector2(96, 0)
	_pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pos_label.add_theme_color_override("font_color", Color(0.72, 0.68, 0.6))
	scrub_row.add_child(_pos_label)

	# --- transport row ------------------------------------------------------
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	_transport(bar, "◀◀ Start", "Rewind to the first epoch", func(): _goto(0, false))
	_transport(bar, "◀ Back", "Step back one epoch", func(): _goto(_index - 1, false))
	_play_btn = _transport(bar, "▶ Play", "Play / pause the history", _toggle_play)
	_transport(bar, "Next ▶", "Step forward one epoch", func(): _goto(_index + 1, false))
	_transport(bar, "End ▶▶", "Jump to the present day", func(): _goto(_frames.size() - 1, false))

	var speed_lbl := Label.new()
	speed_lbl.text = "  Speed"
	speed_lbl.add_theme_color_override("font_color", Color(0.72, 0.68, 0.6))
	bar.add_child(speed_lbl)
	var speed := OptionButton.new()
	speed.tooltip_text = "Playback speed."
	for s in _SPEEDS:
		speed.add_item("%s×" % str(s))
	speed.select(_SPEED_DEFAULT_IDX)
	speed.item_selected.connect(func(idx): set_speed(_SPEEDS[idx]))
	bar.add_child(speed)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var go := Button.new()
	go.text = "Continue to Review ▸"
	go.custom_minimum_size = Vector2(180, 40)
	go.tooltip_text = "Finish the replay and review the present-day world."
	go.pressed.connect(finish)
	bar.add_child(go)

	_timer = Timer.new()
	_timer.one_shot = false
	_timer.timeout.connect(_advance)
	add_child(_timer)


func _transport(parent: HBoxContainer, label: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## Keyboard transport — only while this screen is the visible one (the flow toggles
## screen visibility). ←/→ step (key-repeat allowed, so holding scrubs); Space toggles
## play/pause; Home/End jump to the first / present-day epoch.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or _frames.is_empty() or not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_LEFT:
			_goto(_index - 1, false)
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_goto(_index + 1, false)
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			if not event.echo:
				_toggle_play()
				get_viewport().set_input_as_handled()
		KEY_HOME:
			if not event.echo:
				_goto(0, false)
				get_viewport().set_input_as_handled()
		KEY_END:
			if not event.echo:
				_goto(_frames.size() - 1, false)
				get_viewport().set_input_as_handled()


## Load the stored frames + palette and play them. Generation has already
## completed; this is pure presentation, re-watchable from Screen D for free.
func begin_replay(campaign_id: String) -> void:
	_frames = SettingRepository.list_replay_frames(campaign_id)
	_ordered_hexes = SettingRepository.list_hexes(campaign_id)
	_index = 0
	if _map != null:
		_map.bind(_ordered_hexes, SettingRepository.list_replay_palette(campaign_id))
		# Replay tooltips report per-frame ownership only (the stored culture/
		# territory/peasants are present-day), and need realm names for the owner line.
		_map.set_replay_mode(true)
		var names := {}
		var lieges := {}
		for p in SettingRepository.list_polities(campaign_id):
			var pid := str(p.get("id", ""))
			var nm := str(p.get("name", ""))
			names[pid] = nm if nm != "" else pid
			lieges[pid] = str(p.get("liege_id", ""))
		_map.set_polity_meta(names, lieges)
	if _frames.is_empty():
		finish()
		return
	_last_tick = int(_frames[_frames.size() - 1].get("tick", 0))
	_scrub.max_value = _frames.size() - 1
	_timer.wait_time = _FRAME_SECONDS / maxf(_speed, 0.25)
	_show_frame(0)
	_set_playing(true)


# --- transport ---------------------------------------------------------------

func _toggle_play() -> void:
	# At the end, Play restarts from the beginning; otherwise it resumes.
	if not _playing and _index >= _frames.size() - 1:
		_show_frame(0)
	_set_playing(not _playing)


func _set_playing(on: bool) -> void:
	_playing = on and _frames.size() > 1
	if _play_btn != null:
		_play_btn.text = "❚❚ Pause" if _playing else "▶ Play"
	if _timer == null:
		return
	if _playing:
		_timer.start()
	else:
		_timer.stop()


## Jump to frame [param i] (clamped). [param keep_playing] preserves auto-play (used
## by the timer); manual transport pauses so the player can study the epoch.
func _goto(i: int, keep_playing: bool) -> void:
	if _frames.is_empty():
		return
	_show_frame(clampi(i, 0, _frames.size() - 1))
	if not keep_playing:
		_set_playing(false)


func _on_scrub(v: float) -> void:
	# Programmatic scrubber updates use set_value_no_signal, so this fires only on a
	# real drag → jump there and pause.
	_goto(int(v), false)


func _advance() -> void:
	if _index >= _frames.size() - 1:
		_set_playing(false)   # reached the present day — stop, don't auto-finish
		return
	_goto(_index + 1, true)


func _show_frame(i: int) -> void:
	_index = clampi(i, 0, maxi(_frames.size() - 1, 0))
	var frame: Dictionary = _frames[_index]
	var owners := ReplayFrameDecoder.decode_owner_map(
		str(frame.get("owner_by_hex", "")), _ordered_hexes)
	if _map != null:
		_map.show_owners(owners)
	if _scrub != null:
		_scrub.set_value_no_signal(_index)
	if _pos_label != null:
		_pos_label.text = "%d / %d" % [_index + 1, _frames.size()]
	if _caption != null:
		_caption.text = _epoch_caption(int(frame.get("tick", 0)), _count_realms(owners))
	EventBus.replay_frame_advanced.emit(int(frame.get("tick", 0)))


## A human-facing epoch label: years-before-present (present day at the last frame)
## plus how many realms hold territory in this snapshot.
func _epoch_caption(tick: int, realms: int) -> String:
	var years_ago := (_last_tick - tick) * _YEARS_PER_TICK
	var era := "Present day" if years_ago <= 0 else ("%s years ago" % _commas(years_ago))
	return "Epoch %d of %d  ·  %s  ·  %d realms" % [_index + 1, _frames.size(), era, realms]


func _count_realms(owners: Dictionary) -> int:
	var ids := {}
	for k in owners:
		var o := str(owners[k])
		if o != "":
			ids[o] = true
	return ids.size()


func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


func set_speed(mult: float) -> void:
	_speed = mult
	# Set on the timer even while stopped, so a speed change made during a pause
	# applies the moment playback resumes (a running timer picks it up next cycle).
	if _timer != null:
		_timer.wait_time = _FRAME_SECONDS / maxf(_speed, 0.25)


func finish() -> void:
	_set_playing(false)
	review_requested.emit()
