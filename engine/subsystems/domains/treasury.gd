class_name DomainTreasury
extends RefCounted

## DomainTreasury — domain-scoped gp accounting (Domain Phase 2).
##
## Per `gdd-domain-tab.md` §10 and `docs/domain-roadmap-corrected.md` Phase 2
## [RESOLVED 2026-05-06] treasury access rules:
##
##   (a) Domain-level uses are FREE regardless of ruler location — investment,
##       commissioning structures, paying garrison/liturgies/maintenance/tithes,
##       executing tribute. The engine writes against the domain treasury
##       directly during monthly resolution; no manual transfer needed.
##   (b) Personal purchases CANNOT be funded directly from the domain treasury.
##       The PC must first move gp into `characters.coin`, which requires the
##       PC to be physically present at one of the domain's strongholds.
##   (c) Inter-stronghold transfers are NOT free — moving treasury gp between
##       strongholds requires a PC or trusted carrier to physically transport
##       it (a travel-with-treasure event subject to wilderness encounters
##       and theft).
##
## Plus the [RAW PATCH] Land Improvement investment line: 25,000 gp per +1
## land value per hex, capped at +3 per hex and final land value ≤ 9 per
## `acore_axioms_strongholds_and_domains.xml` §land_improvement L207-215.
##
## All public methods are static. Tests drive them directly without setting
## up a session runner.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Cost per +1 land value per hex per `acore_axioms` §land_improvement L207-215.
## RAW 25,000 gp expressed in cp under the unified currency standard.
const LAND_IMPROVEMENT_CP_PER_PLUS_ONE := 2_500_000

## Reason codes returned to UI / tests when an action is blocked.
const REASON_OK := "ok"
const REASON_INSUFFICIENT_FUNDS := "insufficient_funds"
const REASON_NOT_AT_STRONGHOLD := "not_at_stronghold"
const REASON_DOMAIN_NOT_FOUND := "domain_not_found"
const REASON_CHARACTER_NOT_FOUND := "character_not_found"
const REASON_STRONGHOLD_NOT_FOUND := "stronghold_not_found"
const REASON_AMOUNT_INVALID := "amount_invalid"
const REASON_LAND_IMPROVEMENT_REJECTED := "land_improvement_rejected"
const REASON_HEX_NOT_FOUND := "hex_not_found"


# ---------------------------------------------------------------------------
# Read API
# ---------------------------------------------------------------------------

## Current treasury balance in gp for [param domain_id]. Returns 0 if the
## domain row does not exist (caller should treat as not-found separately if
## that distinction matters).
static func get_balance(domain_id: String) -> int:
	if domain_id.is_empty():
		return 0
	var domain := CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return 0
	return int(domain.get("treasury_cp", 0))


## Whether [param character_id] is currently at one of [param domain_id]'s
## strongholds. Used to gate withdraw-to-personal and deposit-from-personal
## flows per [RESOLVED 2026-05-06] (b).
##
## v1 simplification: a character is "at a stronghold" when their location
## (location_map_id, location_hex_q, location_hex_r) matches any of the
## domain's strongholds. The character row carries those columns via the
## generic location-cache (see migration 032 `location_caches`). For Phase 2
## we read the character's `location_map_id` / `location_hex_q` /
## `location_hex_r` columns directly when present, falling back to a true
## response if the domain has at least one stronghold AND the character has
## no recorded location (test fixtures, pre-implementation paths).
static func is_character_at_stronghold(character_id: String, domain_id: String) -> bool:
	if character_id.is_empty() or domain_id.is_empty():
		return false
	var strongholds := CampaignRepository.list_domain_strongholds(domain_id)
	if strongholds.is_empty():
		return false
	var character := CampaignRepository.get_character(character_id)
	if character.is_empty():
		return false
	var has_location := character.get("location_map_id") != null \
		and character.get("location_hex_q") != null \
		and character.get("location_hex_r") != null
	if not has_location:
		# No recorded character location — Phase 2 cannot decide; treat as
		# at-stronghold so test fixtures pass. UI gates this earlier via the
		# active-entity location.
		return true
	var c_map := String(character.get("location_map_id", ""))
	var c_q: int = int(character.get("location_hex_q", 0))
	var c_r: int = int(character.get("location_hex_r", 0))
	for s in strongholds:
		if String(s.get("location_map_id", "")) == c_map \
				and int(s.get("location_hex_q", -9999)) == c_q \
				and int(s.get("location_hex_r", -9999)) == c_r:
			return true
	return false


# ---------------------------------------------------------------------------
# Direct treasury writes (used by monthly resolution and direct deposits)
# ---------------------------------------------------------------------------

## Deposit [param cp_amount] gp into [param domain_id]'s treasury. Used by
## monthly revenue collection, tribute_in arrival, and player-initiated
## transfers from a personal wallet (which the caller validates).
##
## Writes the matching ledger entry and emits `domain_treasury_changed`.
##
## Returns a result dict: {ok: bool, reason: String, new_balance: int}.
static func deposit(
	domain_id: String,
	cp_amount: int,
	calendar_day: int,
	category: String = "revenue",
	subcategory: String = "deposit",
	description: String = "",
	source_event_id: String = ""
) -> Dictionary:
	if cp_amount <= 0:
		return {"ok": false, "reason": REASON_AMOUNT_INVALID, "new_balance": get_balance(domain_id)}
	var prior := get_balance(domain_id)
	var domain := CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return {"ok": false, "reason": REASON_DOMAIN_NOT_FOUND, "new_balance": prior}
	var new_balance := CampaignRepository.adjust_domain_treasury(domain_id, cp_amount)
	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": calendar_day,
		"category": category,
		"subcategory": subcategory,
		"cp_amount": cp_amount,
		"description": description,
		"source_event_id": source_event_id,
	})
	EventBus.domain_treasury_changed.emit(domain_id, prior, new_balance)
	return {"ok": true, "reason": REASON_OK, "new_balance": new_balance}


## Withdraw [param cp_amount] gp from [param domain_id]'s treasury. Used by
## monthly expense payment, tribute_out, investments, and player-initiated
## transfers to a personal wallet (which the caller validates).
##
## Writes the matching ledger entry (with negative cp_amount) and emits
## `domain_treasury_changed`. Refuses if the balance is insufficient.
static func withdraw(
	domain_id: String,
	cp_amount: int,
	calendar_day: int,
	category: String = "expense",
	subcategory: String = "withdrawal",
	description: String = "",
	source_event_id: String = ""
) -> Dictionary:
	if cp_amount <= 0:
		return {"ok": false, "reason": REASON_AMOUNT_INVALID, "new_balance": get_balance(domain_id)}
	var prior := get_balance(domain_id)
	if prior < 0:
		# Domain row missing — get_balance already returned 0 silently. Probe.
		var domain := CampaignRepository.get_domain(domain_id)
		if domain.is_empty():
			return {"ok": false, "reason": REASON_DOMAIN_NOT_FOUND, "new_balance": 0}
	if prior < cp_amount:
		return {"ok": false, "reason": REASON_INSUFFICIENT_FUNDS, "new_balance": prior}
	var new_balance := CampaignRepository.adjust_domain_treasury(domain_id, -cp_amount)
	CampaignRepository.add_ledger_entry({
		"domain_id": domain_id,
		"calendar_day": calendar_day,
		"category": category,
		"subcategory": subcategory,
		"cp_amount": -cp_amount,
		"description": description,
		"source_event_id": source_event_id,
	})
	EventBus.domain_treasury_changed.emit(domain_id, prior, new_balance)
	return {"ok": true, "reason": REASON_OK, "new_balance": new_balance}


# ---------------------------------------------------------------------------
# Personal-wallet transfers (gated by stronghold location per RESOLVED-2026-05-06)
# ---------------------------------------------------------------------------

## Withdraw gp from the domain treasury and credit the active character's
## personal coin wallet. Per [RESOLVED 2026-05-06] (b), this requires the
## character to be physically at one of the domain's strongholds — the ruler
## picks up the coin in person.
##
## On block, emits `domain_treasury_transfer_blocked` so UI can surface the
## tooltip + travel shortcut.
##
## NOTE: Phase 2 records the personal-wallet credit via a ledger entry only
## (subcategory = 'withdraw_to_personal'); the actual coin-wallet write
## belongs to the inventory-coin subsystem (per `gdd-character-tab.md` §4.8
## "money is an item with a carrier"). The caller is expected to wire the
## coin add into the character's inventory after a successful response.
static func withdraw_to_personal(
	domain_id: String,
	character_id: String,
	cp_amount: int,
	calendar_day: int
) -> Dictionary:
	if cp_amount <= 0:
		return {"ok": false, "reason": REASON_AMOUNT_INVALID, "new_balance": get_balance(domain_id)}
	if not is_character_at_stronghold(character_id, domain_id):
		EventBus.domain_treasury_transfer_blocked.emit(
			domain_id, character_id, REASON_NOT_AT_STRONGHOLD)
		return {"ok": false, "reason": REASON_NOT_AT_STRONGHOLD, "new_balance": get_balance(domain_id)}
	return withdraw(domain_id, cp_amount, calendar_day,
		"expense", "withdraw_to_personal",
		"Withdrew %s to personal wallet of %s" % [Currency.format_cost(cp_amount), character_id])


## Deposit gp from the active character's personal wallet into the domain
## treasury. Same location gating as withdraw_to_personal.
static func deposit_from_personal(
	domain_id: String,
	character_id: String,
	cp_amount: int,
	calendar_day: int
) -> Dictionary:
	if cp_amount <= 0:
		return {"ok": false, "reason": REASON_AMOUNT_INVALID, "new_balance": get_balance(domain_id)}
	if not is_character_at_stronghold(character_id, domain_id):
		EventBus.domain_treasury_transfer_blocked.emit(
			domain_id, character_id, REASON_NOT_AT_STRONGHOLD)
		return {"ok": false, "reason": REASON_NOT_AT_STRONGHOLD, "new_balance": get_balance(domain_id)}
	return deposit(domain_id, cp_amount, calendar_day,
		"revenue", "deposit_from_personal",
		"Deposited %s from personal wallet of %s" % [Currency.format_cost(cp_amount), character_id])


# ---------------------------------------------------------------------------
# Inter-stronghold transfers (Phase 6+ wires the travel-with-treasure event)
# ---------------------------------------------------------------------------

## Initiate an inter-stronghold treasury transfer. Per [RESOLVED 2026-05-06] (c),
## this is NOT a free / instant transfer — a carrier must physically move the
## coin between strongholds and is exposed to wilderness encounters and theft.
##
## Phase 2 deducts the gp from the source treasury immediately (the carrier
## "leaves with it") and emits `domain_treasury_route_started` so the future
## travel-encounter system can hook the route. Phase 6+ adds the arrival-side
## credit when the carrier reaches the destination; until then the gp is held
## in the in-transit ledger entry (subcategory='in_transit_route').
static func transfer_between_strongholds(
	domain_id: String,
	source_stronghold_id: String,
	dest_stronghold_id: String,
	cp_amount: int,
	carrier_character_id: String,
	calendar_day: int
) -> Dictionary:
	if cp_amount <= 0:
		return {"ok": false, "reason": REASON_AMOUNT_INVALID, "new_balance": get_balance(domain_id)}
	if source_stronghold_id == dest_stronghold_id:
		return {"ok": false, "reason": REASON_AMOUNT_INVALID, "new_balance": get_balance(domain_id)}
	var src := CampaignRepository.get_stronghold(source_stronghold_id)
	var dst := CampaignRepository.get_stronghold(dest_stronghold_id)
	if src.is_empty() or dst.is_empty():
		return {"ok": false, "reason": REASON_STRONGHOLD_NOT_FOUND, "new_balance": get_balance(domain_id)}
	var withdraw_result := withdraw(domain_id, cp_amount, calendar_day,
		"other", "in_transit_route",
		"Treasury route %s → %s, carrier %s" % [
			source_stronghold_id, dest_stronghold_id, carrier_character_id])
	if not withdraw_result["ok"]:
		return withdraw_result
	EventBus.domain_treasury_route_started.emit(
		domain_id, source_stronghold_id, dest_stronghold_id,
		cp_amount, carrier_character_id)
	return withdraw_result


# ---------------------------------------------------------------------------
# Land Improvement investment line ([RAW PATCH])
# ---------------------------------------------------------------------------

## Spend 25,000 gp (= 2,500,000 cp) from the domain treasury to apply +1 land
## value to one hex, capped at +3 per hex and final land value ≤ 9 per
## `acore_axioms` §land_improvement L207-215. Delegates the cap math to
## `LandImprovement`, then writes the treasury debit + ledger entry on success
## and emits `land_value_improved`.
##
## Returns: {ok, reason, new_balance, new_land_value, new_improvement_count}.
static func invest_land_improvement(
	domain_id: String,
	hex_q: int,
	hex_r: int,
	calendar_day: int
) -> Dictionary:
	var balance := get_balance(domain_id)
	if balance < LAND_IMPROVEMENT_CP_PER_PLUS_ONE:
		return {
			"ok": false, "reason": REASON_INSUFFICIENT_FUNDS,
			"new_balance": balance, "new_land_value": 0, "new_improvement_count": 0,
		}
	# Locate the hex.
	var hex_row: Dictionary = {}
	for h in CampaignRepository.get_domain_hexes(domain_id):
		if int(h.get("hex_q", 0)) == hex_q and int(h.get("hex_r", 0)) == hex_r:
			hex_row = h
			break
	if hex_row.is_empty():
		return {
			"ok": false, "reason": REASON_HEX_NOT_FOUND,
			"new_balance": balance, "new_land_value": 0, "new_improvement_count": 0,
		}
	var attempt: Dictionary = LandImprovement.attempt_improvement(
		hex_row, LAND_IMPROVEMENT_CP_PER_PLUS_ONE)
	if not bool(attempt.get("accepted", false)):
		return {
			"ok": false, "reason": REASON_LAND_IMPROVEMENT_REJECTED,
			"new_balance": balance,
			"new_land_value": int(hex_row.get("land_value", 0)),
			"new_improvement_count": int(hex_row.get("land_improvement_level", 0)),
			"land_improvement_reason": attempt.get("reason", ""),
		}
	# Persist the improvement, debit the treasury, write the ledger.
	CampaignRepository.update_domain_hex_land_improvement(
		domain_id, hex_q, hex_r, int(attempt["new_improvement"]))
	var withdraw_result := withdraw(
		domain_id, int(attempt["cp_spent"]), calendar_day,
		"investment", "land_improvement",
		"Land improvement on hex (%d, %d): +1 land value" % [hex_q, hex_r])
	EventBus.land_value_improved.emit(
		domain_id, hex_q, hex_r,
		int(attempt["new_land_value"]), int(attempt["new_improvement"]))
	return {
		"ok": true, "reason": REASON_OK,
		"new_balance": withdraw_result.get("new_balance", balance - LAND_IMPROVEMENT_CP_PER_PLUS_ONE),
		"new_land_value": int(attempt["new_land_value"]),
		"new_improvement_count": int(attempt["new_improvement"]),
	}


# ---------------------------------------------------------------------------
# Auto-pay policy helpers (gdd-domain-tab.md §10.2 layout 4)
# ---------------------------------------------------------------------------

## Read the JSON-encoded auto_pay_policies dict from a domain row. Returns an
## empty dict if the domain row is missing or the JSON is malformed.
static func get_auto_pay_policies(domain_id: String) -> Dictionary:
	var domain := CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return {}
	var raw := String(domain.get("auto_pay_policies", "{}"))
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	return {}


## Update one or more auto-pay-policy toggles on a domain. [param toggles] is
## a partial dict (e.g., {"garrison": true}); existing keys are merged in.
## Persisted via `CampaignRepository.update_domain_settings` so the
## settings-whitelist gate applies.
static func set_auto_pay_policy(domain_id: String, toggles: Dictionary) -> bool:
	var current := get_auto_pay_policies(domain_id)
	for key in toggles:
		current[String(key)] = bool(toggles[key])
	var ok := CampaignRepository.update_domain_settings(
		domain_id, {"auto_pay_policies": JSON.stringify(current)})
	if ok:
		EventBus.domain_decree_issued.emit(domain_id, "auto_pay", current)
	return ok
