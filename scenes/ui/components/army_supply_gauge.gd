extends PanelContainer

## Compact supply gauge shown when an army is selected on the wilderness map
## (gdd-army-warfare.md §7.1/§7.3). A colour-banded weeks-of-supply bar + a text
## readout. Read-only display widget — it only pulls from ArmyMapPresence.supply_gauge;
## the banding + weeks math live there (headless-tested). Anchored top-left of the map.

const BAR_COLORS := {
	"green":   Color(0.30, 0.75, 0.40),
	"amber":   Color(0.90, 0.65, 0.20),
	"red":     Color(0.80, 0.25, 0.25),
	"unknown": Color(0.50, 0.50, 0.50),
}
const BAR_WIDTH := 190.0
const BAR_HEIGHT := 14.0
const MAX_WEEKS_DISPLAY := 6.0   # bar fills at >= 6 weeks of runway

var _label: Label = null
var _bar: Control = null
var _band: String = "unknown"
var _fill_frac: float = 0.0


func _ready() -> void:
	UiSurfaceStyles.apply_textured_panel(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(12, 12)
	custom_minimum_size.x = BAR_WIDTH + 24.0
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)
	_label = Label.new()
	_label.text = "Supply: —"
	vbox.add_child(_label)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar.draw.connect(_draw_bar)
	vbox.add_child(_bar)


## Point the gauge at [param army_id]; re-reads the supply state and redraws.
func set_army(army_id: String) -> void:
	var g: Dictionary = ArmyMapPresence.supply_gauge(army_id)
	_band = String(g.get("band", "unknown"))
	if bool(g.get("has_data", false)):
		var weeks := float(g.get("weeks_remaining", 0.0))
		_fill_frac = clampf(weeks / MAX_WEEKS_DISPLAY, 0.0, 1.0)
	else:
		_fill_frac = 0.0
	if _label != null:
		_label.text = String(g.get("text", "Supply: —"))
	if _bar != null:
		_bar.queue_redraw()


func _draw_bar() -> void:
	_bar.draw_rect(Rect2(0.0, 0.0, BAR_WIDTH, BAR_HEIGHT), Color(0.12, 0.12, 0.12, 0.65))
	var col: Color = BAR_COLORS.get(_band, BAR_COLORS["unknown"])
	if _fill_frac > 0.0:
		_bar.draw_rect(Rect2(0.0, 0.0, BAR_WIDTH * _fill_frac, BAR_HEIGHT), col)
