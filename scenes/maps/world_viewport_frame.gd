extends SubViewportContainer

## WorldViewportFrame — confines the wilderness map's render area to the screen
## space ABOVE the session status bar.
##
## The wilderness map (HexMap: Node2D + Camera2D) renders into the child
## SubViewport instead of straight into the root window viewport. Because
## `stretch = true`, resizing this container resizes the SubViewport — the
## Camera2D then shows more or less of the world at the SAME zoom (the image is
## rendered 1:1, never scaled). The container's bottom edge tracks the status
## bar's top edge: dragging the bar taller/shorter shrinks/grows the map
## viewport to match. Consequences the old full-screen render couldn't give us:
##   - the map is never drawn behind the bar;
##   - right-click context menus (which live inside this viewport) can't be
##     buried under the bar;
##   - camera centering / limits read the true visible rect, so "center on
##     party" lands in the visible area rather than partly behind the bar.
##
## Scene tree:
##   WorldViewport (SubViewportContainer - this script; full-rect; stretch=true)
##   └── WorldSubViewport (SubViewport)
##       └── HexMap (Node2D - wilderness renderer)


func _ready() -> void:
	# Belt-and-suspenders: the .tscn sets these, but guarantee the 1:1 resize
	# (no image scaling) and full-rect anchoring even if the scene drifts.
	stretch = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	EventBus.bar_height_changed.connect(_on_bar_height_changed)
	# The status bar may have finished _ready (and emitted) before us; pull its
	# current height directly. Safe-defaults to 0 (full screen) when absent.
	var bar: Node = get_tree().root.find_child("SessionStatusBar", true, false)
	if bar != null and bar.has_method("get_effective_bar_height"):
		_apply_bottom_inset(float(bar.get_effective_bar_height()))


func _on_bar_height_changed(height_px: float) -> void:
	_apply_bottom_inset(height_px)


## Lift the container's bottom edge by [param height_px] px so it aligns with the
## status bar's top edge. Anchored full-rect, so a negative offset_bottom pulls
## the bottom up from the viewport's bottom.
func _apply_bottom_inset(height_px: float) -> void:
	offset_bottom = -maxf(0.0, height_px)
