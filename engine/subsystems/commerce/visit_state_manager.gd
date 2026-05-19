class_name VisitStateManager
extends RefCounted

## Per-visit state manager — owns party_visit_state lifecycle (entry-toll
## first-fire, active-character-at-entry, days-at-settlement math) and
## fires the departure debit (stabling + moorage).
##
## Per gdd-phase-10b-2-trade-block.md §9. RefCounted static-function library
## — no instance state, no autoload (per coding conventions §5; the access
## frequency doesn't justify a new autoload).
##
## Lifecycle (called by SettlementExploreState — wave 2 wires the entry/exit
## hooks per §9.10 + the [NEEDS-SETTLEMENT-FLOW-WIRING] flag):
##   * on_party_entered_settlement → INSERT-OR-IGNORE party_visit_state row;
##     triggers shipping-offer roll (Wave 4).
##   * mercantile handlers → charge_entry_toll_if_first_visit via BuySellCommon
##     → records via mark_entry_toll_paid.
##   * on_party_departed_settlement → compute stabling+moorage, debit wallet,
##     clear shipping offers (Wave 4), DELETE party_visit_state row.


# ---------------------------------------------------------------------------
# Entry / departure triggers
# ---------------------------------------------------------------------------

## INSERTs (OR IGNORE) a party_visit_state row. Re-entry without departure
## is a no-op — the existing row's entry_calendar_day + active_character
## are preserved. Triggers Wave 4's shipping-offer roll (currently stubbed).
## Emits party_entered_settlement.
##
## Per gdd-phase-10b-2-trade-block.md §9.5. Idempotent.
static func on_party_entered_settlement(
		party_id: String,
		settlement_id: String,
		active_character_id: String,
		current_calendar_day: int
) -> void:
	if party_id.is_empty() or settlement_id.is_empty():
		return
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO party_visit_state
			(party_id, settlement_id, entry_calendar_day,
			 entry_toll_paid_flag, entry_toll_paid_cp,
			 active_character_at_entry)
		VALUES (?, ?, ?, 0, 0, ?)
	""", [party_id, settlement_id, current_calendar_day, active_character_id])

	# Phase 10B.2 Wave 4: roll fresh shipping-contract offers per §7.6.
	# Idempotent on re-entry (the roller checks for existing rows first).
	ShippingContractOfferRoller.roll_for_visit(settlement_id, party_id, current_calendar_day)

	EventBus.party_entered_settlement.emit(party_id, settlement_id, current_calendar_day)


## Computes + debits stabling + moorage, clears shipping offers (Wave 4),
## DELETEs the party_visit_state row. Returns a dict with the computed
## per-fee breakdown for UI display. Emits party_departed_settlement;
## emits visit_fees_unpaid on insufficient funds (without blocking departure).
##
## Per gdd-phase-10b-2-trade-block.md §9.6.
##
## Return dict keys: stabling_cp, moorage_cp, days_at_settlement, unpaid_cp,
## offers_cleared. Per the 2026-05-15 currency-precision rule, charges are
## reported in cp (project base currency); UI divides by 100 for gp display.
static func on_party_departed_settlement(
		party_id: String,
		settlement_id: String,
		current_calendar_day: int
) -> Dictionary:
	var empty_result := {
		"stabling_cp": 0, "moorage_cp": 0, "days_at_settlement": 0,
		"unpaid_cp": 0, "offers_cleared": 0,
	}
	if party_id.is_empty() or settlement_id.is_empty():
		return empty_result
	var visit: Dictionary = get_visit_row(party_id, settlement_id)
	if visit.is_empty():
		return empty_result

	var entry_day: int = int(visit.get("entry_calendar_day", current_calendar_day))
	var days_at_settlement: int = maxi(1, current_calendar_day - entry_day)
	var active_char_id: String = String(visit.get("active_character_at_entry", ""))
	var is_domain_owner: bool = MarketFeesCalculator.is_domain_owner_in_own_market(
		active_char_id, settlement_id)

	# 1. Stabling — exact integer cp (stabling rates are whole cp/day per
	#    the 2026-05-15 currency-precision rule).
	var mounts: Dictionary = _compile_mounts_at_settlement(party_id, settlement_id)
	var stabling_cp: int = MarketFeesCalculator.stabling_cp_total(
		mounts, days_at_settlement, is_domain_owner)

	# 2. Moorage — exact integer cp (rate = shp × 10 cp/day; always integer).
	var moorage_cp: int = 0
	for ship in ShipRepository.list_ships_for_party(party_id):
		if String((ship as Dictionary).get("moored_at_settlement_id", "")) == settlement_id:
			moorage_cp += MarketFeesCalculator.moorage_cp_total(
				int((ship as Dictionary).get("shp_max", 0)),
				days_at_settlement,
				is_domain_owner)

	# 3. Debit in cp (the project's base currency). Insufficient funds emits
	# unpaid signal but does NOT block departure per §9.9 (mirrors the
	# substrate ship-operating-cost "log and continue" pattern).
	var total_fees_cp: int = stabling_cp + moorage_cp
	var unpaid_cp: int = 0
	if total_fees_cp > 0:
		var pay_result: Dictionary = PartyWallet.pay(total_fees_cp, party_id, active_char_id)
		if not bool(pay_result.get("ok", false)):
			unpaid_cp = total_fees_cp
			EventBus.visit_fees_unpaid.emit(party_id, settlement_id, total_fees_cp)

	# 4. Phase 10B.2 Wave 4: clear shipping-contract offers per §7.6.
	#    Substrate emits shipping_offer_cleared from the roller.
	var offers_cleared: int = ShippingContractOfferRoller.clear_for_party_at_settlement(
		party_id, settlement_id)

	# 5. DELETE the visit row.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_visit_state WHERE party_id = ? AND settlement_id = ?",
		[party_id, settlement_id])

	EventBus.party_departed_settlement.emit(
		party_id, settlement_id, stabling_cp, moorage_cp, days_at_settlement)

	return {
		"stabling_cp": stabling_cp,
		"moorage_cp": moorage_cp,
		"days_at_settlement": days_at_settlement,
		"unpaid_cp": unpaid_cp,
		"offers_cleared": offers_cleared,
	}


# ---------------------------------------------------------------------------
# Toll first-fire (consumed by BuySellCommon.charge_entry_toll_if_first_visit)
# ---------------------------------------------------------------------------

## True iff the party has paid the entry toll at this settlement this visit.
## False if no visit row OR entry_toll_paid_flag = 0.
##
## Note: "paid 0 cp because domain owner" still counts as "paid" — the flag
## is set after the toll computation regardless of the cp amount. Callers
## reading the actual cp should query get_visit_row().entry_toll_paid_cp.
static func has_paid_entry_toll(party_id: String, settlement_id: String) -> bool:
	if party_id.is_empty() or settlement_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
			"SELECT entry_toll_paid_flag FROM party_visit_state WHERE party_id = ? AND settlement_id = ?",
			[party_id, settlement_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	return int(CampaignRepository.db.query_result[0].get("entry_toll_paid_flag", 0)) == 1


## Records that the toll has been paid this visit + the cp amount.
## UPSERT-flavored: if no row exists (e.g., handler called outside the
## entry path), this is a no-op rather than an INSERT to avoid leaking
## an orphan visit row without an entry_calendar_day.
static func mark_entry_toll_paid(party_id: String, settlement_id: String, toll_cp: int) -> void:
	if party_id.is_empty() or settlement_id.is_empty():
		return
	CampaignRepository.db.query_with_bindings("""
		UPDATE party_visit_state
		SET entry_toll_paid_flag = 1, entry_toll_paid_cp = ?
		WHERE party_id = ? AND settlement_id = ?
	""", [toll_cp, party_id, settlement_id])


## Returns the active_character_at_entry recorded on the visit row, or ""
## if no row exists. Consumed by BuySellCommon for monopolist-favor lookup
## + domain-owner exemption at toll time.
static func active_character_for_visit(party_id: String, settlement_id: String) -> String:
	if party_id.is_empty() or settlement_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
			"SELECT active_character_at_entry FROM party_visit_state WHERE party_id = ? AND settlement_id = ?",
			[party_id, settlement_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	var v: Variant = CampaignRepository.db.query_result[0].get("active_character_at_entry", null)
	return String(v) if v != null else ""


# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------

## Returns the full visit row dict, or {} if no active visit.
static func get_visit_row(party_id: String, settlement_id: String) -> Dictionary:
	if party_id.is_empty() or settlement_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM party_visit_state WHERE party_id = ? AND settlement_id = ?",
			[party_id, settlement_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


## True iff a party_visit_state row exists for the (party, settlement) pair.
static func has_active_visit(party_id: String, settlement_id: String) -> bool:
	return not get_visit_row(party_id, settlement_id).is_empty()


# ---------------------------------------------------------------------------
# Mount enumeration for stabling (§9.7)
# ---------------------------------------------------------------------------

## Builds the {stabling_key: count} dict that MarketFeesCalculator.stabling_cp_total
## consumes. Enumerates two sources:
##
##   1. **Vehicles** — `draft_vehicles` rows owned by the party. Per ACKS
##      stabling rates (acore-campaign-hijinks.xml §stabling): cart/wagon
##      rates BUNDLE the draft team. So the vehicle counts once; its
##      hitched team is NOT re-enumerated as loose mounts (see source 2's
##      filter).
##
##   2. **Loose trained creatures** — `trained_creatures` rows owned by
##      the party (alive) that are NOT currently hitched to any of the
##      party's vehicles. Closes `[NEEDS-LOOSE-MOUNT-STABLING-PASS]` from
##      Wave 6 — covers the "PC's riding warhorse not pulling a wagon",
##      "hireling's pack mule", etc. cases.
##
## Hitched-vs-loose distinction: `draft_vehicles.hitched_creatures` is a
## JSON array of creature IDs. The loose-mount query excludes any creature
## whose id appears in any vehicle's hitched_creatures array. No schema
## changes needed — the JSON-array column remains the canonical hitching
## relationship.
##
## Non-stabled species (cow, dog_hunting, dog_war, hawk_ordinary, goat,
## sheep) map to "" via `_species_to_stabling_key` and don't contribute.
##
## v1 assumes party draft_vehicles + trained_creatures are co-located with
## the party (no per-entity settlement tracking columns). `[NEEDS-VEHICLE-
## SETTLEMENT-LOCATION-PASS]` covers the future enhancement for both.
static func _compile_mounts_at_settlement(party_id: String, _settlement_id: String) -> Dictionary:
	var mounts: Dictionary = {}
	var hitched_ids: Dictionary = {}  # Used as a set: {creature_id: true}

	# Source 1: vehicles + collect hitched-creature ID set for source 2's filter.
	if CampaignRepository.db.query_with_bindings("""
		SELECT item_key, hitched_creatures FROM draft_vehicles
		WHERE party_id = ? AND is_destroyed = 0
	""", [party_id]):
		for row in CampaignRepository.db.query_result:
			var item_key: String = String((row as Dictionary).get("item_key", ""))
			var vehicle_key: String = _vehicle_item_to_stabling_key(item_key)
			if not vehicle_key.is_empty():
				mounts[vehicle_key] = int(mounts.get(vehicle_key, 0)) + 1
			# Parse hitched_creatures JSON; collect creature IDs.
			var hitched_json: String = String((row as Dictionary).get("hitched_creatures", "[]"))
			var hitched_arr: Variant = JSON.parse_string(hitched_json)
			if hitched_arr is Array:
				for entry in hitched_arr as Array:
					# Entries may be bare ID strings OR Dictionary {id|creature_id|species_id: ...}.
					# Be tolerant of both for backward compat with existing fixtures.
					if entry is String and not (entry as String).is_empty():
						hitched_ids[entry] = true
					elif entry is Dictionary:
						var cid: String = String((entry as Dictionary).get("id",
							(entry as Dictionary).get("creature_id", "")))
						if not cid.is_empty():
							hitched_ids[cid] = true

	# Source 2: loose (not hitched) trained creatures owned by the party.
	if CampaignRepository.db.query_with_bindings("""
		SELECT id, species_id FROM trained_creatures
		WHERE party_id = ? AND is_alive = 1
	""", [party_id]):
		for row in CampaignRepository.db.query_result:
			var creature_id: String = String((row as Dictionary).get("id", ""))
			if creature_id.is_empty():
				continue
			if hitched_ids.has(creature_id):
				continue  # Hitched to a vehicle — already covered by the vehicle's stabling rate.
			var species: String = String((row as Dictionary).get("species_id", ""))
			var stable_key: String = _species_to_stabling_key(species)
			if not stable_key.is_empty():
				mounts[stable_key] = int(mounts.get(stable_key, 0)) + 1

	return mounts


static func _vehicle_item_to_stabling_key(item_key: String) -> String:
	if item_key in ["cart_small", "cart_large"]:
		return "cart"
	if item_key == "wagon":
		return "wagon"
	return ""


## Maps `trained_creatures.species_id` to the canonical stabling-rate key
## consumed by `MarketFeesCalculator.STABLING_RATES_GP_PER_DAY`. Returns
## "" for non-stabled species (dogs, hawks, goats, sheep, cows — none of
## these appear in ACKS stabling fee tables).
##
## Per RAW the per-night stabling rates are:
##   * mule or donkey: 2 sp/night
##   * horse (riding OR draft): 5 sp/night
##   * war horse: 1 gp/night (premium; war horses charge twice the rate)
##   * ox: 8 sp/night (project-designed per Jedidiah)
##
## Per the Phase 10B.2 follow-up audit (2026-05-14), `trained_creatures.species_id`
## takes 15 distinct values cross-referenced from `data/equipment/transport.json`:
##   * Riding/draft horses (3): horse_light, horse_medium, horse_heavy → "horse"
##   * War horses (3): horse_light_war, horse_medium_war, horse_heavy_war → "warhorse"
##   * mule → "mule", donkey → "donkey", camel → "camel", ox → "ox"
##   * Non-stabled (return ""): cow, dog_hunting, dog_war, hawk_ordinary,
##     goat, sheep.
##
## "warhorse" (without species suffix) is preserved as a generic fallback
## for any future code that uses the simpler key directly.
static func _species_to_stabling_key(species_id: String) -> String:
	if species_id in [
			"horse_light_war", "horse_medium_war", "horse_heavy_war",
			"warhorse"]:
		return "warhorse"
	if species_id in ["horse_heavy", "horse_medium", "horse_light"]:
		return "horse"
	if species_id == "mule":
		return "mule"
	if species_id == "donkey":
		return "donkey"
	if species_id == "camel":
		return "camel"
	if species_id == "ox":
		return "ox"
	# Non-stabled species: cow, dog_hunting, dog_war, hawk_ordinary, goat, sheep.
	return ""
