class_name TradeRangeResolver
extends RefCounted

## Trade-range lookup per acore-setting-construction-rules.xml
## §range_of_trade L264-278 (the SACRED RAW table).
##
## Resolves the Phase 7 carry-forward item: non-henchman vassal base loyalty
## per RAW acore_axioms §non_henchman_vassals L392-397:
##   "Non-henchman vassals have base loyalty -2 instead of 0."
##   "If the non-henchman vassal is outside the range of trade of the ruler's
##    largest urban settlement, base loyalty is -4."
##
## Implementation note: the RAW table at L264-278 distinguishes road-range vs
## water-range. v1 uses ROAD range only (since travel-mode metadata isn't on
## settlement_entrances yet). When water-route data lands, callers can opt in
## via the optional `via_water` parameter.
##
## Public API:
##   range_of_trade_hexes(market_class: int, via_water: bool = false) -> int
##     RAW lookup; returns 0 (= "no trade range") for invalid market_class.
##
##   largest_urban_settlement_for_ruler(ruler_character_id) -> Dictionary
##     Returns the highest market_class settlement_entrance owned by any
##     domain in the ruler's realm (apex chain). Empty if none.
##
##   is_within_trade_range(vassal_domain_id, ruler_character_id, via_water: bool = false) -> bool
##     Composite: looks up ruler's largest urban; reads its trade range;
##     compares hex distance to the vassal_domain's anchor hex.
##
##   compute_non_henchman_base_loyalty(vassal_domain_id, ruler_character_id) -> int
##     Returns -2 (within trade range) or -4 (outside) per RAW.

# Source: acore-setting-construction-rules.xml §range_of_trade L264-278.
# Format: market_class (Roman numeral as int 1-6) → {road_hexes, water_hexes}.
const _RANGE_TABLE := {
	6: {"road":  4, "water":  8},
	5: {"road":  8, "water": 16},
	4: {"road": 12, "water": 20},
	3: {"road": 18, "water": 40},
	2: {"road": 24, "water": 60},
	1: {"road": 28, "water": 80},
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

static func range_of_trade_hexes(market_class: int, via_water: bool = false) -> int:
	if not _RANGE_TABLE.has(market_class):
		return 0
	var entry: Dictionary = _RANGE_TABLE[market_class]
	if via_water:
		return int(entry["water"])
	return int(entry["road"])


static func largest_urban_settlement_for_ruler(ruler_character_id: String) -> Dictionary:
	## Walks the ruler's owned domains + active vassal-domains (via realm
	## aggregator) and returns the highest market_class settlement_entrance.
	## "Largest" = highest market class = LOWEST market_class number (Class I
	## is largest per RAW).
	if ruler_character_id.is_empty():
		return {}
	var aggregate: Dictionary = RealmAggregator.aggregate(ruler_character_id)
	var owned_character_ids: Array = [ruler_character_id]
	for assn in aggregate.get("direct_vassals", []):
		var vc: String = String(assn.get("vassal_character_id", ""))
		if not vc.is_empty():
			owned_character_ids.append(vc)
	if owned_character_ids.is_empty():
		return {}
	# Build placeholders for the IN clause.
	var placeholders: String = ",".join((["?"] as Array).slice(0, 0))
	var qmarks: Array = []
	for _i in owned_character_ids:
		qmarks.append("?")
	placeholders = ",".join(qmarks)
	var sql := """
		SELECT se.* FROM settlement_entrances se
		JOIN domains d ON d.id = se.parent_domain_id
		WHERE d.owner_character_id IN (%s)
		ORDER BY se.market_class ASC LIMIT 1
	""" % placeholders
	if not CampaignRepository.db.query_with_bindings(sql, owned_character_ids):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func is_within_trade_range(
	vassal_domain_id: String,
	ruler_character_id: String,
	via_water: bool = false
) -> bool:
	if vassal_domain_id.is_empty() or ruler_character_id.is_empty():
		# No data — be lenient (treat as in-range for v1).
		return true
	var urban: Dictionary = largest_urban_settlement_for_ruler(ruler_character_id)
	if urban.is_empty():
		# No urban settlement at all → ruler has no trade range, any vassal
		# is "outside" → -4 base loyalty.
		return false
	var market_class: int = int(urban.get("market_class", 6))
	var range_hexes: int = range_of_trade_hexes(market_class, via_water)
	if range_hexes <= 0:
		return false

	# Hex distance: the vassal_domain's location_hex_q/_r vs urban's
	# location hex.
	var vassal_dom: Dictionary = CampaignRepository.get_domain(vassal_domain_id)
	if vassal_dom.is_empty():
		return false
	var v_q: int = int(vassal_dom.get("location_hex_q", 0))
	var v_r: int = int(vassal_dom.get("location_hex_r", 0))
	var u_q: int = int(urban.get("hex_q", 0))
	var u_r: int = int(urban.get("hex_r", 0))
	var distance: int = _axial_hex_distance(v_q, v_r, u_q, u_r)
	return distance <= range_hexes


static func compute_non_henchman_base_loyalty(
	vassal_domain_id: String,
	ruler_character_id: String
) -> int:
	## Per RAW §non_henchman_vassals L393-394:
	##   in trade range  → -2
	##   outside range   → -4
	if is_within_trade_range(vassal_domain_id, ruler_character_id):
		return -2
	return -4


# ---------------------------------------------------------------------------
# Hex distance (axial coordinates → cube → distance)
# ---------------------------------------------------------------------------

static func _axial_hex_distance(q1: int, r1: int, q2: int, r2: int) -> int:
	# Cube distance in axial coords:
	# d = (|q1-q2| + |r1-r2| + |(-q1-r1)-(-q2-r2)|) / 2
	var dq: int = absi(q1 - q2)
	var dr: int = absi(r1 - r2)
	var ds: int = absi((-q1 - r1) - (-q2 - r2))
	return (dq + dr + ds) / 2
