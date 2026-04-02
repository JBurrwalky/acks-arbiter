extends CanvasLayer

## Scene transition overlay — fades to black, calls a swap callback, fades back.
##
## Placed at layer=200 (above all game UI). The black ColorRect blocks mouse input
## while the transition plays.
##
## Usage:
##   _transition.play(swap_callable, on_complete_callable)
##
## NavigationStack is the primary caller. Do not drive this directly from gameplay code.

const FADE_DURATION := 0.25  # seconds per half-transition (total = 0.5s)

var _overlay: ColorRect


func _ready() -> void:
	layer = 200

	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	# Start passthrough — only block input while a transition is actually playing.
	# A transparent-but-STOP rect would silently eat all mouse events between transitions.
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor to fill the entire viewport
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.offset_left = 0.0
	_overlay.offset_top = 0.0
	_overlay.offset_right = 0.0
	_overlay.offset_bottom = 0.0
	_overlay.self_modulate.a = 0.0
	add_child(_overlay)


## Play a full fade-out → [param swap_callable] → fade-in transition.
##
## [param swap_callable]    — called at the midpoint (screen fully black).
##                            Perform scene setup / node visibility changes here.
## [param on_complete]      — called after the fade-in completes (optional).
func play(swap_callable: Callable, on_complete: Callable = Callable()) -> void:
	# Block input for the duration of the transition.
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_overlay, "self_modulate:a", 1.0, FADE_DURATION)
	tween.tween_callback(swap_callable)
	tween.tween_property(_overlay, "self_modulate:a", 0.0, FADE_DURATION)
	# Restore passthrough once the fade-in completes.
	tween.tween_callback(func(): _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE)
	if on_complete.is_valid():
		tween.tween_callback(on_complete)


## Immediately reset the overlay to fully transparent (no animation).
## Intended for error recovery — normally transitions complete on their own.
func reset() -> void:
	if is_instance_valid(_overlay):
		_overlay.self_modulate.a = 0.0
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
