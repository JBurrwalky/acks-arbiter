class_name UiPalette
extends RefCounted

## UiPalette — content-specific palette constants that don't belong in the
## project Theme.tres.
##
## Per gdd-ui-architecture.md §5.2 step 4, the project distinguishes:
##   - Theme.tres → Control styling that is purely surface-presentation
##     (Button/Label/PanelContainer typography and styleboxes).
##   - UiSurfaceStyles (legacy) → vellum/parchment textures, framed-window
##     chrome. Slated for migration into Theme.tres in Phase α.4.
##   - UiPalette (this file) → palette constants tied to game-state meaning
##     (HP color thresholds, encumbrance band colors, district color schemes,
##     attitude-tier colors, etc.) — content the player reads as state, not
##     as aesthetic chrome.
##
## All consumer surfaces should source palette colors here so a future
## redesign / accessibility tweak / colorblind palette swap is one-file work.


# ---------------------------------------------------------------------------
# HP color thresholds
# ---------------------------------------------------------------------------

## Tier boundaries on the (current / max) ratio. Anything <= 0 is "downed";
## otherwise inclusive bands [DOWNED < ratio < CRITICAL < HURT < HEALTHY].
const HP_RATIO_CRITICAL := 0.25
const HP_RATIO_HURT     := 0.5

const HP_COLOR_DOWNED   := Color(0.60, 0.10, 0.10, 1.0)
const HP_COLOR_CRITICAL := Color(0.85, 0.15, 0.15, 1.0)
const HP_COLOR_HURT     := Color(0.90, 0.65, 0.10, 1.0)
const HP_COLOR_HEALTHY  := Color(0.20, 0.75, 0.20, 1.0)
const HP_COLOR_DEAD     := Color(0.45, 0.10, 0.10, 1.0)


## Returns the canonical HP text/bar color for [param current] / [param max].
## Anything with a non-positive max is treated as full health (no color
## modulation) — surfaces typically don't care about uninitialized HP.
static func hp_color(current: int, max_value: int) -> Color:
	if max_value <= 0:
		return HP_COLOR_HEALTHY
	if current <= 0:
		return HP_COLOR_DOWNED
	var ratio := float(current) / float(max_value)
	if ratio < HP_RATIO_CRITICAL:
		return HP_COLOR_CRITICAL
	if ratio < HP_RATIO_HURT:
		return HP_COLOR_HURT
	return HP_COLOR_HEALTHY
