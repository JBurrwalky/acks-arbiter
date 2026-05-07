class_name ClassificationAdvancement
extends RefCounted

## Domain classification (Wilderness / Borderlands / Civilized) advancement and
## regression checker per `acore_axioms_strongholds_and_domains.xml`:
##   * §limits_of_growth.maximum_population L156-161   — family caps per hex.
##   * §classification_advancement L165-175             — promotion criteria.
##   * §optional_rules.regression L178                  — demotion when criteria lapse.
##
## The resolver is informational only — it returns whether a change is
## indicated, not whether it should be applied. The caller (handler) decides
## (e.g., in case of a ruler-driven veto, or to apply only on monthly ticks).

const FAMILY_CAP_WILDERNESS  := 125
const FAMILY_CAP_BORDERLANDS := 250
const FAMILY_CAP_CIVILIZED   := 780

const ADVANCE_HEX_COUNT_TO_BORDERLANDS := 16  # also to Civilized
const ADVANCE_DISTANCE_BORDERLANDS_MILES := 72
const ADVANCE_DISTANCE_CIVILIZED_MILES := 48
const URBAN_RATIO_REQUIRED_PCT := 20

const TT_WILDERNESS  := "wilderness"
const TT_BORDERLANDS := "borderlands"
const TT_CIVILIZED   := "civilized"


## Returns a Dictionary with keys:
##   advanced: bool
##   regressed: bool
##   new_classification: String  — equal to current if no change
##   reason: String              — human-readable explanation for ledger / UI
static func check_classification_change(
	domain: Dictionary,
	hex_count: int,
	has_urban_settlement: bool,
	urban_pct_of_peasants: int,
	distance_to_friendly_city_miles: int,
	contiguous_expansion_blocked: bool
) -> Dictionary:
	var current: String = String(domain.get("territory_type", TT_WILDERNESS))
	var peasants: int = int(domain.get("peasant_families", 0))

	# Try advancement first; if not advancing, check regression.
	if current == TT_WILDERNESS:
		if _can_advance_to_borderlands(peasants, hex_count, has_urban_settlement,
			urban_pct_of_peasants, distance_to_friendly_city_miles,
			contiguous_expansion_blocked):
			return {
				"advanced": true, "regressed": false,
				"new_classification": TT_BORDERLANDS,
				"reason": "Wilderness saturated and within 72mi of friendly city/town.",
			}
	elif current == TT_BORDERLANDS:
		if _can_advance_to_civilized(peasants, hex_count, has_urban_settlement,
			urban_pct_of_peasants, distance_to_friendly_city_miles,
			contiguous_expansion_blocked):
			return {
				"advanced": true, "regressed": false,
				"new_classification": TT_CIVILIZED,
				"reason": "Borderlands saturated and within 48mi of friendly city/town.",
			}
		# Borderlands regresses to Wilderness if its justifying conditions end.
		if not _justifies_borderlands(distance_to_friendly_city_miles):
			return {
				"advanced": false, "regressed": true,
				"new_classification": TT_WILDERNESS,
				"reason": "Outside 72mi friendly-settlement range — borderlands status lapses.",
			}
	elif current == TT_CIVILIZED:
		if not _justifies_civilized(distance_to_friendly_city_miles):
			# Don't double-regress in one step; demote to Borderlands first.
			return {
				"advanced": false, "regressed": true,
				"new_classification": TT_BORDERLANDS,
				"reason": "Outside 48mi friendly-settlement range — civilized status lapses.",
			}

	return {
		"advanced": false, "regressed": false,
		"new_classification": current, "reason": "",
	}


## Returns the per-6-mile-hex family cap for a given classification per
## §limits_of_growth L156-161.
static func family_cap_per_hex(classification: String) -> int:
	if classification == TT_WILDERNESS:
		return FAMILY_CAP_WILDERNESS
	elif classification == TT_BORDERLANDS:
		return FAMILY_CAP_BORDERLANDS
	elif classification == TT_CIVILIZED:
		return FAMILY_CAP_CIVILIZED
	return FAMILY_CAP_WILDERNESS


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

static func _can_advance_to_borderlands(
	peasants: int,
	hex_count: int,
	has_urban: bool,
	urban_pct: int,
	distance_miles: int,
	contiguous_blocked: bool
) -> bool:
	# Distance gate per §classification_advancement.to_borderlands L169.
	if distance_miles > ADVANCE_DISTANCE_BORDERLANDS_MILES:
		return false
	# Path A: every hex at 125 families AND domain encompasses 16+ 6-mile hexes
	# (i.e., 2,000 families total).
	var all_hexes_at_wilderness_cap := \
		hex_count > 0 \
		and peasants >= hex_count * FAMILY_CAP_WILDERNESS
	var path_a := all_hexes_at_wilderness_cap \
		and hex_count >= ADVANCE_HEX_COUNT_TO_BORDERLANDS
	if path_a:
		return true
	# Path B: every hex at 125 families, contiguous expansion blocked,
	# domain has an urban settlement with ≥20% urban-to-peasant ratio.
	var path_b := all_hexes_at_wilderness_cap \
		and contiguous_blocked \
		and has_urban \
		and urban_pct >= URBAN_RATIO_REQUIRED_PCT
	return path_b


static func _can_advance_to_civilized(
	peasants: int,
	hex_count: int,
	has_urban: bool,
	urban_pct: int,
	distance_miles: int,
	contiguous_blocked: bool
) -> bool:
	if distance_miles > ADVANCE_DISTANCE_CIVILIZED_MILES:
		return false
	var all_hexes_at_borderlands_cap := \
		hex_count > 0 \
		and peasants >= hex_count * FAMILY_CAP_BORDERLANDS
	var path_a := all_hexes_at_borderlands_cap \
		and hex_count >= ADVANCE_HEX_COUNT_TO_BORDERLANDS
	if path_a:
		return true
	var path_b := all_hexes_at_borderlands_cap \
		and contiguous_blocked \
		and has_urban \
		and urban_pct >= URBAN_RATIO_REQUIRED_PCT
	return path_b


static func _justifies_borderlands(distance_miles: int) -> bool:
	# Continued borderlands status requires being within the 72-mile friendly-
	# settlement range (the conditions that originally justified advancement).
	return distance_miles <= ADVANCE_DISTANCE_BORDERLANDS_MILES


static func _justifies_civilized(distance_miles: int) -> bool:
	return distance_miles <= ADVANCE_DISTANCE_CIVILIZED_MILES
