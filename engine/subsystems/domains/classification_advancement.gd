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
##
## Phase 11D.2 — Clanhold-style distance gates (`ax_domains_of_chaos.xml`
## §exceptions_from_clanholds L77-78):
##   *"Chaotic domains may be civilized only if within 25 miles of a city or
##     large town in the same realm."*
##   *"Chaotic domains may be borderlands only if within 50 miles of civilized
##     areas in the same realm."*
## For `domain_style == 'clanhold'`, the advancement distance gates tighten:
##   borderlands gate: 72mi → 50mi
##   civilized gate:   48mi → 25mi
## AND the friendly-settlement reference must be in the SAME REALM as the
## advancing domain — a friendly-but-foreign-realm settlement does not count
## for clanhold advancement. The caller passes `friendly_settlement_same_realm`
## as a precomputed bool. Style-driven, alignment-agnostic per
## gdd-domain-style-and-alignment.md §2.

const FAMILY_CAP_WILDERNESS  := 125
const FAMILY_CAP_BORDERLANDS := 250
const FAMILY_CAP_CIVILIZED   := 780

const ADVANCE_HEX_COUNT_TO_BORDERLANDS := 16  # also to Civilized
const ADVANCE_DISTANCE_BORDERLANDS_MILES := 72
const ADVANCE_DISTANCE_CIVILIZED_MILES := 48
# Phase 11D.2: clanhold-style distance gates per RAW L77-78.
const CLANHOLD_ADVANCE_DISTANCE_BORDERLANDS_MILES := 50
const CLANHOLD_ADVANCE_DISTANCE_CIVILIZED_MILES := 25
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
	contiguous_expansion_blocked: bool,
	friendly_settlement_same_realm: bool = true
) -> Dictionary:
	var current: String = String(domain.get("territory_type", TT_WILDERNESS))
	var peasants: int = int(domain.get("peasant_families", 0))
	var is_clanhold: bool = String(domain.get("domain_style", "civilized")) == "clanhold"

	# Phase 11D.2: clanhold-style domains use the tighter L77-78 distance gates
	# AND require the friendly settlement to be in the SAME REALM. If the
	# friendly settlement is in a different realm, the gate fails outright
	# regardless of distance.
	var effective_borderlands_gate: int = (
		CLANHOLD_ADVANCE_DISTANCE_BORDERLANDS_MILES if is_clanhold
		else ADVANCE_DISTANCE_BORDERLANDS_MILES
	)
	var effective_civilized_gate: int = (
		CLANHOLD_ADVANCE_DISTANCE_CIVILIZED_MILES if is_clanhold
		else ADVANCE_DISTANCE_CIVILIZED_MILES
	)
	var realm_gate_satisfied: bool = (not is_clanhold) or friendly_settlement_same_realm

	# Try advancement first; if not advancing, check regression.
	if current == TT_WILDERNESS:
		if realm_gate_satisfied and _can_advance_to_borderlands(peasants, hex_count, has_urban_settlement,
			urban_pct_of_peasants, distance_to_friendly_city_miles,
			contiguous_expansion_blocked, effective_borderlands_gate):
			var reason_borderlands := "Wilderness saturated and within %dmi of friendly city/town%s." % [
				effective_borderlands_gate,
				" in same realm" if is_clanhold else "",
			]
			return {
				"advanced": true, "regressed": false,
				"new_classification": TT_BORDERLANDS,
				"reason": reason_borderlands,
			}
	elif current == TT_BORDERLANDS:
		if realm_gate_satisfied and _can_advance_to_civilized(peasants, hex_count, has_urban_settlement,
			urban_pct_of_peasants, distance_to_friendly_city_miles,
			contiguous_expansion_blocked, effective_civilized_gate):
			var reason_civilized := "Borderlands saturated and within %dmi of friendly city/town%s." % [
				effective_civilized_gate,
				" in same realm" if is_clanhold else "",
			]
			return {
				"advanced": true, "regressed": false,
				"new_classification": TT_CIVILIZED,
				"reason": reason_civilized,
			}
		# Borderlands regresses to Wilderness if its justifying conditions end.
		# For clanholds: also regress if the friendly settlement is no longer
		# in the same realm (e.g., a realm reshuffle severed the link).
		if (not _justifies_borderlands(distance_to_friendly_city_miles, effective_borderlands_gate)
				or (is_clanhold and not friendly_settlement_same_realm)):
			var reason_b_lapse := "Outside %dmi friendly-settlement range%s — borderlands status lapses." % [
				effective_borderlands_gate,
				" in same realm" if is_clanhold else "",
			]
			return {
				"advanced": false, "regressed": true,
				"new_classification": TT_WILDERNESS,
				"reason": reason_b_lapse,
			}
	elif current == TT_CIVILIZED:
		if (not _justifies_civilized(distance_to_friendly_city_miles, effective_civilized_gate)
				or (is_clanhold and not friendly_settlement_same_realm)):
			# Don't double-regress in one step; demote to Borderlands first.
			var reason_c_lapse := "Outside %dmi friendly-settlement range%s — civilized status lapses." % [
				effective_civilized_gate,
				" in same realm" if is_clanhold else "",
			]
			return {
				"advanced": false, "regressed": true,
				"new_classification": TT_BORDERLANDS,
				"reason": reason_c_lapse,
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
	contiguous_blocked: bool,
	effective_distance_gate: int = ADVANCE_DISTANCE_BORDERLANDS_MILES
) -> bool:
	# Distance gate per §classification_advancement.to_borderlands L169.
	# Phase 11D.2: clanhold-style domains tighten the gate to 50mi per RAW L78.
	if distance_miles > effective_distance_gate:
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
	contiguous_blocked: bool,
	effective_distance_gate: int = ADVANCE_DISTANCE_CIVILIZED_MILES
) -> bool:
	# Phase 11D.2: clanhold-style domains tighten the gate to 25mi per RAW L77.
	if distance_miles > effective_distance_gate:
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


static func _justifies_borderlands(
	distance_miles: int,
	effective_gate: int = ADVANCE_DISTANCE_BORDERLANDS_MILES
) -> bool:
	# Continued borderlands status requires being within the friendly-settlement
	# range (civilized: 72mi; clanhold: 50mi per RAW L78).
	return distance_miles <= effective_gate


static func _justifies_civilized(
	distance_miles: int,
	effective_gate: int = ADVANCE_DISTANCE_CIVILIZED_MILES
) -> bool:
	return distance_miles <= effective_gate
