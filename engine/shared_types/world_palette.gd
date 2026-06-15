class_name WorldPalette
extends RefCounted

## Shared maximally-distinct colour ramp (after Trubetskoy), used for both the
## per-polity replay colours (history_simulator._build_palette) and the Culture
## map view (political_map_view). Index 0..17 are the curated distinct set; beyond
## that a golden-angle hue sweep with cycled saturation & value keeps neighbours
## apart. Single source of truth so the two layers can't drift.

const DISTINCT := [
	"#e6194b", "#3cb44b", "#ffe119", "#4363d8", "#f58231", "#911eb4",
	"#42d4f4", "#f032e6", "#bfef45", "#fabed4", "#469990", "#dcbeff",
	"#9a6324", "#800000", "#aaffc3", "#808000", "#ffd8b1", "#000075",
]
const _SAT := [0.85, 0.62, 0.95, 0.72]
const _VAL := [0.90, 0.75, 0.66, 0.84]


## Stable colour for sorted index `i`.
static func color_at(i: int) -> Color:
	if i < DISTINCT.size():
		return Color.html(DISTINCT[i])
	var hue := fmod(float(i) * 0.6180339887498949, 1.0)
	return Color.from_hsv(hue, _SAT[i % 4], _VAL[i % 4])


## Same colour as an "#rrggbb" string (for the persisted replay-palette rows).
static func hex_at(i: int) -> String:
	if i < DISTINCT.size():
		return DISTINCT[i]
	return "#" + color_at(i).to_html(false)
