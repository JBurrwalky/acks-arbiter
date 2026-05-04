class_name StatReadout
extends HBoxContainer

## StatReadout — single-row presentation of a character stat (HP / AC /
## movement / save) with consistent formatting and color thresholds.
##
## Per gdd-ui-architecture.md §5.4. Replaces re-implemented HP color logic
## across CSTabCombat, StatSummary, InitiativeStrip, and CombatEndOverlay.
## All HP color thresholds come from UiPalette so a future palette tweak is
## one-file work.
##
## Two consumption modes:
##
## 1. **Component instance** — `var sr := StatReadout.new(); sr.show_hp(c, m)`.
##    Renders "HP: 12 / 30" as a single colored Label. Use when the surface
##    wants a one-row drop-in display.
##
## 2. **Static helpers** — `StatReadout.hp_color_for(current, max_value)`,
##    `StatReadout.format_hp(current, max_value)`. Use when the surface
##    already has its own bar / Label / layout but wants to share the
##    canonical color + format rules.
##
## The instance version is intentionally minimal — surfaces with bars or
## non-trivial layouts should use the static helpers and keep their own
## structure rather than wrap a StatReadout that fights the layout.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Recognized kinds — strings rather than enum so external callers can pass
## them via Dictionary payloads (e.g. signal data).
const KIND_HP := "hp"
const KIND_AC := "ac"
const KIND_MOVEMENT := "movement"
const KIND_SAVE := "save"

const _DEFAULT_TITLE_WIDTH_PX := 40.0
const _DEFAULT_FONT_SIZE := 12


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _title_label: Label = null
var _value_label: Label = null
var _kind: String = ""


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if _title_label == null:
		_build()


func _build() -> void:
	add_theme_constant_override("separation", 6)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", _DEFAULT_FONT_SIZE)
	_title_label.custom_minimum_size = Vector2(_DEFAULT_TITLE_WIDTH_PX, 0)
	add_child(_title_label)

	_value_label = Label.new()
	_value_label.add_theme_font_size_override("font_size", _DEFAULT_FONT_SIZE)
	add_child(_value_label)


# ---------------------------------------------------------------------------
# Instance API
# ---------------------------------------------------------------------------

## Show HP as "HP: <current> / <max>" with the canonical color from UiPalette.
## When [param show_temp_hp] is positive, appends " (+N)".
func show_hp(current: int, max_value: int, show_temp_hp: int = 0) -> void:
	_ensure_built()
	_kind = KIND_HP
	_title_label.text = "HP:"
	_value_label.text = format_hp(current, max_value, show_temp_hp)
	_value_label.add_theme_color_override("font_color", hp_color_for(current, max_value))


## Show AC as "AC: <value>" with optional [param suffix] (e.g. " (effective)").
## AC has no color thresholds.
func show_ac(value: int, suffix: String = "") -> void:
	_ensure_built()
	_kind = KIND_AC
	_title_label.text = "AC:"
	_value_label.text = "%d%s" % [value, suffix]
	_value_label.remove_theme_color_override("font_color")


## Show movement as "Move: <remaining> / <total> ft" or "Move: <remaining> ft"
## when [param total] is negative.
func show_movement(remaining: int, total: int = -1, unit: String = "ft") -> void:
	_ensure_built()
	_kind = KIND_MOVEMENT
	_title_label.text = "Move:"
	if total < 0:
		_value_label.text = "%d %s" % [remaining, unit]
	else:
		_value_label.text = "%d / %d %s" % [remaining, total, unit]
	_value_label.remove_theme_color_override("font_color")


## Show a save throw as "<label>: <value>+" (descending-AC convention).
func show_save(save_label: String, value: int) -> void:
	_ensure_built()
	_kind = KIND_SAVE
	_title_label.text = "%s:" % save_label
	_value_label.text = "%d+" % value
	_value_label.remove_theme_color_override("font_color")


## Width of the leading title label, in pixels. Useful when stacking multiple
## StatReadouts vertically and you want their colons to align.
func set_title_width(width_px: float) -> void:
	_ensure_built()
	_title_label.custom_minimum_size = Vector2(width_px, 0)


func current_kind() -> String:
	return _kind


# ---------------------------------------------------------------------------
# Static helpers (preferred for surfaces that own their own layout)
# ---------------------------------------------------------------------------

## Canonical HP text color for the (current, max) pair. Sources thresholds
## from UiPalette. Surfaces with their own labels/bars should call this
## rather than re-implementing the threshold check.
static func hp_color_for(current: int, max_value: int) -> Color:
	return UiPalette.hp_color(current, max_value)


## Canonical "<current> / <max>" formatting, with optional " (+temp)" suffix
## when [param show_temp_hp] is positive.
static func format_hp(current: int, max_value: int, show_temp_hp: int = 0) -> String:
	if show_temp_hp > 0:
		return "%d / %d (+%d)" % [current, max_value, show_temp_hp]
	return "%d / %d" % [current, max_value]


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _ensure_built() -> void:
	## Allow show_*() calls before _ready() (i.e. before the Control is added
	## to the tree) — useful in tests and in callers that build their UI in
	## a single pass.
	if _title_label == null:
		_build()
