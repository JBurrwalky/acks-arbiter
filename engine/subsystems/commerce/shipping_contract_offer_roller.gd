class_name ShippingContractOfferRoller
extends RefCounted

## Per-visit transient shipping-contract offer generation. Per
## gdd-phase-10b-2-trade-block.md §7.1-§7.6 + RAW acore-campaign-hijinks.xml
## §passenger_and_cargo_transport (L765-837).
##
## Lifecycle (called by VisitStateManager — Wave 1 stubs closed by Wave 4):
##   * roll_for_visit(settlement_id, party_id, current_day) — INSERTed on
##     market entry. Idempotent: re-entry returns the existing rows without
##     re-rolling. Returns the array of offer rows.
##   * clear_for_party_at_settlement(party_id, settlement_id) — DELETEs all
##     of a party's offers at a settlement on departure. Returns the count
##     cleared.
##   * list_offers / get_offer — read-only consumers (mercantile_panel + the
##     accept_shipping_contract handler).
##
## v1 simplifications (vs full RAW):
##   * No staggered 1-3 week availability per RAW L828-832; all offers
##     available immediately. [NEEDS-CONTRACT-STAGGERED-AVAILABILITY-PASS]
##   * No 9+ trust roll per RAW L815; offers accept without a reaction roll.
##     [NEEDS-CONTRACT-TRUST-ROLL-PASS]
##   * No half-advance per RAW L824; full fee paid on delivery only.
##     [NEEDS-CONTRACT-HALF-ADVANCE-PASS]
##   * Destination is uniform-random from the reachable settlement set
##     (per substrate TradeRouteDetector). The RAW L788-791 1d20
##     distant-vs-near mechanic awaits an in-game travel-destination
##     concept. [NEEDS-CONTRACT-DESTINATION-RAW-COMPLETE-PASS]
##   * Cargo type is always 'mixed_cargo' per RAW L822 simplification.
##   * Road preferred when both road + water are valid (project rule per §7.3).


# ---------------------------------------------------------------------------
# Tables (RAW L777-783 + L822)
# ---------------------------------------------------------------------------

const CONTRACT_COUNT_DICE := {
	1: "2d6+2",
	2: "2d4+1",
	3: "2d4",
	4: "1d4",
	5: "1d4-1",
	6: "1d3-1",
}

const CARGO_LOADS_DICE := {
	1: "6d8",
	2: "4d6",
	3: "3d4",
	4: "2d4",
	5: "1d4",
	6: "1d2",
}

## RAW L822: "mixed cargo at 70 stone per load."
const MIXED_CARGO_STONE_PER_LOAD := 70
const MIXED_CARGO_MERCHANDISE_TYPE := "mixed_cargo"

## Distance conversion mirrors TravelSpeedCalculator.MILES_PER_HEX.
const MILES_PER_HEX := 6.0


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Idempotent. On first call for a (party, settlement) at this visit, rolls
## the per-class contract count and emits one row per offer. Subsequent calls
## return the existing rows without re-rolling.
##
## Returns the array of offer Dictionaries (full rows from shipping_contract_offers).
static func roll_for_visit(settlement_id: String, party_id: String, current_day: int) -> Array:
	if settlement_id.is_empty() or party_id.is_empty():
		return []

	# Idempotency: if offers already exist for this (party, settlement) at any
	# `rolled_at_calendar_day`, return them. The visit-state lifecycle clears
	# them on departure, so the only "stale" rows we'd see are from a save
	# loaded mid-visit — also OK to surface as-is.
	var existing: Array = list_offers(party_id, settlement_id)
	if not existing.is_empty():
		return existing

	# Read settlement.
	var settlement: Dictionary = _read_settlement(settlement_id)
	if settlement.is_empty():
		return []
	var campaign_id: String = String(settlement.get("campaign_id", ""))
	var market_class: int = int(settlement.get("market_class", 6))
	if market_class < 1 or market_class > 6:
		return []

	# Roll contract count via deterministic per-visit seed.
	var count_dice: String = String(CONTRACT_COUNT_DICE.get(market_class, "1d3-1"))
	var count_rng: RandomNumberGenerator = _seeded_rng(
		"contract_count|%s|%s|%d" % [party_id, settlement_id, current_day])
	var offer_count: int = maxi(0, _roll_dice_spec(count_dice, count_rng))
	if offer_count == 0:
		return []

	# Enumerate reachable destinations once for the whole batch.
	var reachable: Array = _enumerate_reachable_destinations(campaign_id, settlement_id)
	if reachable.is_empty():
		return []

	# Roll each offer.
	var loads_dice: String = String(CARGO_LOADS_DICE.get(market_class, "1d2"))
	var rolled_ids: Array = []
	for i in offer_count:
		var offer_id: String = CampaignRepository.generate_id()
		var offer_seed: String = "contract_offer|%s|%s|%d|%d" % [party_id, settlement_id, current_day, i]
		var offer_rng: RandomNumberGenerator = _seeded_rng(offer_seed)

		# Destination pick (uniform over reachable set).
		var dest: Dictionary = reachable[offer_rng.randi_range(0, reachable.size() - 1)]
		var dest_id: String = String(dest.get("settlement_id", ""))
		var route_mode: String = String(dest.get("route_mode", "road"))
		var distance_hexes: int = int(dest.get("distance_hexes", 0))
		var distance_miles: int = int(ceili(float(distance_hexes) * MILES_PER_HEX))

		# Cargo loads + fee + deadline. Fee stored as cp per the
		# 2026-05-15 currency-precision rule.
		var loads_count: int = maxi(1, _roll_dice_spec(loads_dice, offer_rng))
		var total_stone: int = loads_count * MIXED_CARGO_STONE_PER_LOAD
		var fee_cp: int = compute_fee_cp(total_stone, distance_miles, route_mode)
		var deadline_day: int = compute_deadline_calendar_day(
			current_day, distance_miles, route_mode)

		CampaignRepository.db.query_with_bindings("""
			INSERT INTO shipping_contract_offers
				(id, campaign_id, party_id, origin_settlement_id,
				 destination_settlement_id, merchandise_type, loads_count,
				 load_weight_stone, route_mode, distance_miles, fee_cp,
				 deadline_calendar_day, rolled_at_calendar_day)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		""", [
			offer_id, campaign_id, party_id, settlement_id,
			dest_id, MIXED_CARGO_MERCHANDISE_TYPE, loads_count,
			MIXED_CARGO_STONE_PER_LOAD, route_mode, distance_miles, fee_cp,
			deadline_day, current_day,
		])
		EventBus.shipping_offer_rolled.emit(offer_id, party_id, settlement_id)
		rolled_ids.append(offer_id)

	return list_offers(party_id, settlement_id)


## DELETEs all of [param party_id]'s offers at [param settlement_id]. Returns
## the count cleared. Emits shipping_offer_cleared with the count.
static func clear_for_party_at_settlement(party_id: String, settlement_id: String) -> int:
	if party_id.is_empty() or settlement_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM shipping_contract_offers
		WHERE party_id = ? AND origin_settlement_id = ?
	""", [party_id, settlement_id]):
		return 0
	var count: int = 0
	if not CampaignRepository.db.query_result.is_empty():
		count = int(CampaignRepository.db.query_result[0].get("n", 0))
	if count == 0:
		return 0
	CampaignRepository.db.query_with_bindings("""
		DELETE FROM shipping_contract_offers
		WHERE party_id = ? AND origin_settlement_id = ?
	""", [party_id, settlement_id])
	EventBus.shipping_offer_cleared.emit(party_id, settlement_id, count)
	return count


## Returns the array of offer rows for [param party_id] at [param settlement_id].
static func list_offers(party_id: String, settlement_id: String) -> Array:
	if party_id.is_empty() or settlement_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM shipping_contract_offers
		WHERE party_id = ? AND origin_settlement_id = ?
		ORDER BY id ASC
	""", [party_id, settlement_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


## Returns the offer row by id, or {} if not found.
static func get_offer(offer_id: String) -> Dictionary:
	if offer_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM shipping_contract_offers WHERE id = ?", [offer_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


# ---------------------------------------------------------------------------
# Pure helpers (RAW formulas)
# ---------------------------------------------------------------------------

## RAW L817-819 fee formula. Road: 1 gp per 10 stone per 150 miles. Sea:
## 1 gp per 10 stone per 500 miles. Both factors rounded UP per RAW.
## Returns cp (per_stone_units × distance_units gp × 100). The RAW formula
## yields integer gp, so the × 100 conversion is exact (no precision loss).
static func compute_fee_cp(total_stone: int, distance_miles: int, route_mode: String) -> int:
	if total_stone <= 0 or distance_miles <= 0:
		return 0
	var divisor_miles: float = 500.0 if route_mode == "water" else 150.0
	var per_stone_units: int = int(ceili(float(total_stone) / 10.0))
	var distance_units: int = int(ceili(float(distance_miles) / divisor_miles))
	return per_stone_units * distance_units * 100


## v1 calibration per §7.5: round-trip estimate × 2 + 7-day buffer.
## Road wagons assumed ~18 mi/day; sea ~48 mi/day.
## [NEEDS-CONTRACT-DEADLINE-CALIBRATION]
static func compute_deadline_calendar_day(
		current_day: int, distance_miles: int, route_mode: String) -> int:
	if distance_miles <= 0:
		return current_day + 7
	var miles_per_day: float = 48.0 if route_mode == "water" else 18.0
	var travel_days: int = int(ceili(float(distance_miles) / miles_per_day))
	return current_day + (travel_days * 2 + 7)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Returns array of {settlement_id, route_mode, distance_hexes} for every
## OTHER settlement reachable from [param origin_id] via an established
## trade route (a row in `trade_routes` with invalidated=0). Road preferred
## when path_kind='mixed' (both road + water valid per substrate).
##
## Per §7.3: shipping contracts ship from origin to a destination over an
## established trade route. The substrate's TradeRouteDetector pre-computes
## these routes (BFS over hex overlays) and caches them in `trade_routes`;
## the offer roller consumes the cache.
static func _enumerate_reachable_destinations(
		_campaign_id: String, origin_id: String) -> Array:
	if origin_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT settlement_a_id, settlement_b_id, path_kind, distance_hexes
		FROM trade_routes
		WHERE invalidated = 0 AND (settlement_a_id = ? OR settlement_b_id = ?)
		ORDER BY settlement_a_id ASC, settlement_b_id ASC
	""", [origin_id, origin_id]):
		return []
	var routes: Array = CampaignRepository.db.query_result.duplicate()
	var reachable: Array = []
	for row in routes:
		var r: Dictionary = row
		var a_id: String = String(r.get("settlement_a_id", ""))
		var b_id: String = String(r.get("settlement_b_id", ""))
		var dest_id: String = b_id if a_id == origin_id else a_id
		if dest_id.is_empty() or dest_id == origin_id:
			continue
		# path_kind values from substrate: 'road' / 'water' / 'mixed'.
		# Project rule §7.3: road preferred when both available.
		var path_kind: String = String(r.get("path_kind", "road"))
		var route_mode: String = "water" if path_kind == "water" else "road"
		reachable.append({
			"settlement_id": dest_id,
			"route_mode": route_mode,
			"distance_hexes": int(r.get("distance_hexes", 0)),
		})
	return reachable


static func _read_settlement(settlement_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, campaign_id, market_class FROM settlement_entrances WHERE id = ?
	""", [settlement_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


static func _seeded_rng(seed_str: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_str)
	return rng


## NdM / NdM+K / NdM-K parser (mirrors MarketFeesCalculator + MerchantPoolRepository).
static func _roll_dice_spec(spec: String, rng: RandomNumberGenerator) -> int:
	var add_idx: int = spec.find("+")
	var sub_idx: int = spec.find("-")
	var modifier: int = 0
	var dice_part: String = spec
	if add_idx > -1:
		dice_part = spec.substr(0, add_idx)
		modifier = int(spec.substr(add_idx + 1))
	elif sub_idx > -1:
		dice_part = spec.substr(0, sub_idx)
		modifier = -int(spec.substr(sub_idx + 1))
	var d_idx: int = dice_part.find("d")
	if d_idx < 0:
		push_error("ShippingContractOfferRoller._roll_dice_spec: malformed '%s'" % spec)
		return 0
	var n: int = int(dice_part.substr(0, d_idx))
	var sides: int = int(dice_part.substr(d_idx + 1))
	if n <= 0 or sides <= 0:
		push_error("ShippingContractOfferRoller._roll_dice_spec: invalid dice in '%s'" % spec)
		return 0
	var total: int = 0
	for _i in n:
		total += rng.randi_range(1, sides)
	return total + modifier
