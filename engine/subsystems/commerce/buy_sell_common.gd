class_name BuySellCommon
extends RefCounted

## Shared helpers for buy_merchandise + sell_merchandise handlers and the
## mercantile_panel UI. RefCounted static-function library — no instance
## state, no autoload.
##
## Per gdd-phase-10b-2-trade-block.md §3.4 (handler-side helpers) and
## §3.5/§3.6 (UI consumers).
##
## Wave 10B.2.1 (Foundation) ships:
##   * resolve_party_for_character — wallet + active-character bridge
##   * charge_entry_toll_if_first_visit — toll first-fire logic per §1.2
##   * transaction_rng — deterministic per-day per-(party, settlement) RNG
##   * carrier_has_capacity — capacity gate via CargoEncumbranceCalculator
##   * build_buy_receipt / build_sell_receipt — UI-consumable receipt dicts


# ---------------------------------------------------------------------------
# Party resolution
# ---------------------------------------------------------------------------

## Returns the party_id [param character_id] belongs to, or "" if not in
## any party. Wraps CampaignRepository.get_party_for_character so handler
## call sites can pivot through one canonical helper.
static func resolve_party_for_character(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	return CampaignRepository.get_party_for_character(character_id)


# ---------------------------------------------------------------------------
# Entry-toll first-fire (§1.2 + §9 cross-references)
# ---------------------------------------------------------------------------

## Charges the entry toll iff this is the party's first mercantile activity
## at this settlement this visit. Records the charge via
## VisitStateManager.mark_entry_toll_paid so subsequent transactions skip
## the toll. Returns the CP charged (0 if already paid this visit OR if
## the active character is the settlement's domain owner).
##
## Per gdd-phase-10b-2-trade-block.md §1.2 (toll-fold-into-first-transaction)
## + §9.5 (visit lifecycle) + acore-campaign-hijinks.xml L647-650 (RAW toll).
##
## [param is_selling] / [param merchandise_loads]: passed through to
## MarketFeesCalculator.entry_toll_cp for the RAW "minimum 1 gp per load"
## floor on selling transactions (L649).
static func charge_entry_toll_if_first_visit(
		party_id: String, settlement_id: String,
		is_selling: bool, merchandise_loads: int,
		rng: RandomNumberGenerator
) -> int:
	if party_id.is_empty() or settlement_id.is_empty():
		return 0
	if VisitStateManager.has_paid_entry_toll(party_id, settlement_id):
		return 0
	var market_class: int = _read_settlement_market_class(settlement_id)
	if market_class <= 0:
		return 0
	var active_char_id: String = VisitStateManager.active_character_for_visit(
		party_id, settlement_id)
	var is_domain_owner: bool = MarketFeesCalculator.is_domain_owner_in_own_market(
		active_char_id, settlement_id)
	var toll_cp: int = MarketFeesCalculator.entry_toll_cp(
		market_class, is_selling, merchandise_loads, rng, is_domain_owner)
	if toll_cp > 0:
		PartyWallet.pay(toll_cp, party_id, active_char_id)
	VisitStateManager.mark_entry_toll_paid(party_id, settlement_id, toll_cp)
	return toll_cp


# ---------------------------------------------------------------------------
# Deterministic per-transaction RNG
# ---------------------------------------------------------------------------

## Returns an RNG seeded by (party_id, settlement_id, current_calendar_day).
## Same inputs → same seed → same dice. Replay-safe. Multiple transactions
## on the same day share this seed (their RNG state diverges as dice are
## consumed, but the test fixture can re-seed for verification).
##
## Per gdd-phase-10b-2-trade-block.md §3.4. Used by buy/sell handlers for
## the entry-toll dice path; price dice are cached on the demand row by
## MarketPriceResolver and don't consume this RNG.
static func transaction_rng(party_id: String, settlement_id: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|%d|trade_transaction" % [
		party_id, settlement_id, Timekeeping.get_total_days()])
	return rng


# ---------------------------------------------------------------------------
# Carrier capacity check
# ---------------------------------------------------------------------------

## Returns true iff [param carrier_id] has room for [param incremental_stone]
## additional stone of cargo. Dispatches on [param carrier_kind] to the
## appropriate CargoEncumbranceCalculator helper.
##
## Per gdd-phase-10b-2-trade-block.md §3.4. Consumed by the buy handler's
## pre-payment capacity gate (§3.2 step 4).
##
## [param carrier_kind] must be CargoHoldRepository.CARRIER_DRAFT_VEHICLE or
## CARRIER_SHIP. Unknown carrier kinds return false (defensive).
static func carrier_has_capacity(
		carrier_id: String, carrier_kind: String, incremental_stone: int
) -> bool:
	if carrier_id.is_empty() or incremental_stone < 0:
		return false
	if carrier_kind == CargoHoldRepository.CARRIER_DRAFT_VEHICLE:
		var check: Dictionary = CargoEncumbranceCalculator.draft_vehicle_capacity_check(carrier_id)
		if check.is_empty():
			return false
		var used: int = int(check.get("used_stone", 0))
		var max_stone: int = int(check.get("load_max_stone", 0))
		return (used + incremental_stone) <= max_stone
	if carrier_kind == CargoHoldRepository.CARRIER_SHIP:
		var check: Dictionary = CargoEncumbranceCalculator.ship_capacity_check(carrier_id)
		if check.is_empty():
			return false
		var used: int = int(check.get("used_stone", 0))
		var max_stone: int = int(check.get("cargo_capacity_stone", 0))
		return (used + incremental_stone) <= max_stone
	return false


# ---------------------------------------------------------------------------
# Receipt builders
# ---------------------------------------------------------------------------

## Builds the buy receipt Dictionary for the mercantile_panel + transaction
## log. All currency fields are CP per the 2026-05-15 currency-precision rule.
## `grand_total_cp = purchase + toll + labor`. monopolist_favor of -1
## means the active character is the monopolist (lower buy price).
static func build_buy_receipt(
		merchandise_type: String, loads_count: int, cp_per_load: int,
		total_purchase_cp: int, toll_cp: int, labor_cp: int, monopolist_favor: int
) -> Dictionary:
	return {
		"kind": "buy",
		"merchandise_type": merchandise_type,
		"loads_count": loads_count,
		"cp_per_load": cp_per_load,
		"total_purchase_cp": total_purchase_cp,
		"entry_toll_cp": toll_cp,
		"labor_fee_cp": labor_cp,
		"monopolist_favor": monopolist_favor,
		"grand_total_cp": total_purchase_cp + toll_cp + labor_cp,
	}


## Builds the sell receipt Dictionary. All currency fields are CP.
## `net_proceeds_cp = gross - toll - labor - customs`. domain_owner_exempt
## flags whether the toll + customs + stabling exemption applied at the
## active character.
static func build_sell_receipt(
		merchandise_type: String, loads_count: int, cp_per_load: int,
		gross_sale_cp: int, toll_cp: int, labor_cp: int, customs_cp: int,
		monopolist_favor: int, is_domain_owner: bool
) -> Dictionary:
	return {
		"kind": "sell",
		"merchandise_type": merchandise_type,
		"loads_sold": loads_count,
		"cp_per_load": cp_per_load,
		"gross_proceeds_cp": gross_sale_cp,
		"entry_toll_cp": toll_cp,
		"labor_fee_cp": labor_cp,
		"customs_duty_cp": customs_cp,
		"monopolist_favor": monopolist_favor,
		"domain_owner_exempt": is_domain_owner,
		"net_proceeds_cp": gross_sale_cp - toll_cp - labor_cp - customs_cp,
	}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Reads market_class from settlement_entrances. Returns 0 on missing
## row (sentinel for "not a market — toll cannot be computed").
##
## Mirrors the inline read pattern used by MarketPriceResolver and
## market_class_modifier_resolver. If a fourth caller emerges, lifting this
## into CampaignRepository.get_settlement_market_class is the consolidation
## path.
static func _read_settlement_market_class(settlement_id: String) -> int:
	if settlement_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings(
			"SELECT market_class FROM settlement_entrances WHERE id = ?",
			[settlement_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("market_class", 0))
