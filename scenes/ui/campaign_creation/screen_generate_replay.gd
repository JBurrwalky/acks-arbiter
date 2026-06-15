extends Control

## Screen C: Generation + History Replay (gdd-campaign-creation-ui.md §5).
## Generation runs to completion up front; this screen PACES the presentation —
## the political map animates epoch by epoch from the stored replay frames, decoded
## via the tested ReplayFrameDecoder, emitting EventBus.replay_frame_advanced per
## step. [Skip ▸] jumps straight to review. SCAFFOLD: the frame STEPPING is real
## and tested-decoder-backed; the per-frame map RENDER is an in-editor pass.

signal review_requested

const _FRAME_SECONDS := 0.6   # §5 pacing ≈ 1 frame / 0.5–0.75 s

var _frames: Array = []
var _ordered_hexes: Array = []
var _index: int = 0
var _speed: float = 1.0
var _timer: Timer


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# EDITOR: the map view (owner-colored hexes), a caption strip (top
	# significance-ranked events for the current epoch), a timeline scrubber, a
	# ×1/×2/×4 speed toggle calling set_speed(), and a [Skip ▸] button → finish().
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.timeout.connect(_advance)
	add_child(_timer)


## Load the stored frames and play them. Generation has already completed; this is
## pure presentation, re-watchable from Screen D at no cost (frames are persisted).
func begin_replay(campaign_id: String) -> void:
	_frames = SettingRepository.list_replay_frames(campaign_id)
	_ordered_hexes = SettingRepository.list_hexes(campaign_id)
	_index = 0
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
	EventBus.replay_frame_advanced.emit(int(frame.get("tick", 0)))
	_render_frame(int(frame.get("tick", 0)), owners)


func _render_frame(_tick: int, _owners: Dictionary) -> void:
	# EDITOR: paint the political map for this epoch from _owners (Vector2i → polity)
	# using the stored polity palette (SettingRepository.list_replay_palette), and
	# update the caption strip + the scrubber position.
	pass


func set_speed(mult: float) -> void:
	_speed = mult
	if _timer != null and not _timer.is_stopped():
		_timer.wait_time = _FRAME_SECONDS / maxf(_speed, 0.25)


func finish() -> void:
	if _timer != null:
		_timer.stop()
	review_requested.emit()
