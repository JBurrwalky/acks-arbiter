class_name CreatureSize
extends RefCounted

## The single home for the ACKS size-category → tactical-grid-footprint mapping.
##
## ACKS 1e defines six size categories by weight/length (rules/le_monster_creation.xml,
## `weight_size_and_ac_rules > size_category_table`, SACRED):
##
##   | category   | mass            | length/height        | RAW AC mod |
##   |------------|-----------------|----------------------|------------|
##   | small      | <= 35 lb        | < 2'                 | +1         |
##   | man_sized  | 36 - 400 lb     | < 8'                 |  0         |
##   | large      | 401 - 2,000 lb  | 8' - 12'             | -1         |
##   | huge       | 2,001 - 8,000   | 12' - 20'            | -2         |
##   | gigantic   | 8,001 - 32,000  | 20' - 32'            | -4         |
##   | colossal   | > 32,000 lb     | 32'+                 | -8         |
##
## The **grid footprint** scale is a project design input supplied by Jedidiah
## (docs/monster_size_audit.xlsx "Methodology" tab), NOT a RAW rule:
##
##   man-sized / small = 1x1, Large-long = 2x1, Large-wide = 1x2,
##   Huge = 2x2, Gigantic = 3x4, Colossal = 6x9
##
## Footprint dimensions here are stored in the creature's LOCAL frame as
## `Vector2i(length, width)` where `length` is the extent ALONG the facing axis
## (nose-to-tail depth) and `width` is the extent ACROSS it. The audit strings are
## written "height x width facing north", so "2x1" (a horse, long) reads
## length 2 / width 1, and "1x2" (an ogre, wide-shouldered) reads length 1 /
## width 2. CreatureFootprint rotates this local rectangle into world cells based
## on the creature's facing.
##
## The Large tier is the only category whose footprint depends on body-plan
## orientation (long vs wide); every other category has a single fixed footprint.
##
## NOTE: The RAW size→AC modifier column above is a monster-CREATION rule (used
## when deriving a brand-new monster's AC from HD + body form + size). Every
## creature already in rules/ + data/monsters/monster_catalog.json is a complete
## entity whose stated `armor_class` ALREADY bakes in its size modifier — so it
## must NOT be re-applied at runtime (Jedidiah ruling, 2026-07-18). This table is
## intentionally footprint-only; nothing here touches AC.


## The six ACKS size categories, smallest to largest.
const CATEGORIES: Array[String] = [
	"small", "man_sized", "large", "huge", "gigantic", "colossal",
]


## Local-frame footprints (length, width) for the categories with a single fixed
## footprint. The Large tier is resolved via `footprint_local()` using orientation.
const FIXED_FOOTPRINTS: Dictionary = {
	"small": Vector2i(1, 1),
	"man_sized": Vector2i(1, 1),
	"huge": Vector2i(2, 2),
	"gigantic": Vector2i(3, 4),
	"colossal": Vector2i(6, 9),
}


## Large-tier footprints keyed by orientation.
const LARGE_FOOTPRINTS: Dictionary = {
	"long": Vector2i(2, 1),
	"wide": Vector2i(1, 2),
}

## Gigantic-tier footprints keyed by orientation (Jedidiah 2026-07-22). Long
## creatures (hydra, remorhaz) read 4x3; the default / "wide" gigantic stays 3x4
## (dragons, whales, crocodiles, etc. — all authored as orientation "n_a").
const GIGANTIC_FOOTPRINTS: Dictionary = {
	"long": Vector2i(4, 3),
	"wide": Vector2i(3, 4),
}


## Token vertical-stretch multiplier per size category (renderer placeholder
## cylinder height scale). Man-sized is the 1.0 baseline.
const HEIGHT_SCALE: Dictionary = {
	"small": 0.7,
	"man_sized": 1.0,
	"large": 1.4,
	"huge": 1.9,
	"gigantic": 2.5,
	"colossal": 3.2,
}


## Returns true if [param size_category] is one of the six ACKS categories.
static func is_valid_category(size_category: String) -> bool:
	return size_category in CATEGORIES


## Returns the local-frame footprint `Vector2i(length, width)` for a size
## category and (for the Large tier) an orientation ("long" | "wide").
##
## Returns (1, 1) for an unknown category, so callers degrade to single-cell
## rather than crashing. For a Large creature with an unknown/empty orientation,
## defaults to "long" (2x1) — the audit's quadruped default. Ambiguous-orientation
## creatures (oozes) are flagged out of the data pass and never reach here with a
## real footprint.
static func footprint_local(size_category: String, orientation: String = "") -> Vector2i:
	if size_category == "large":
		return LARGE_FOOTPRINTS.get(orientation, LARGE_FOOTPRINTS["long"])
	# Gigantic is also orientation-aware: "long" -> 4x3, everything else -> 3x4.
	if size_category == "gigantic":
		return GIGANTIC_FOOTPRINTS.get(orientation, FIXED_FOOTPRINTS["gigantic"])
	return FIXED_FOOTPRINTS.get(size_category, Vector2i(1, 1))


## Token height-scale multiplier for a size category. Defaults to 1.0.
static func height_scale(size_category: String) -> float:
	return float(HEIGHT_SCALE.get(size_category, 1.0))


## Parses an audit-style footprint string "HxW" (height=length x width) into a
## local-frame `Vector2i(length, width)`. Returns (1, 1) on any parse failure so
## the data pipeline degrades to single-cell. Used by the data-integration
## consistency test, not by runtime.
static func parse_footprint_string(footprint: String) -> Vector2i:
	var parts := footprint.strip_edges().to_lower().split("x")
	if parts.size() != 2:
		return Vector2i(1, 1)
	if not (parts[0].is_valid_int() and parts[1].is_valid_int()):
		return Vector2i(1, 1)
	return Vector2i(int(parts[0]), int(parts[1]))
