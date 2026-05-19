class_name MonopolyRegistry
extends RefCounted

## Monopoly grant registry — (character_id, settlement_id, merchandise_type)
## triples that confer the RAW monopolist benefits.
##
## Per gdd-phase-10b-2-trade-block.md §8. RefCounted static-function library
## — no instance state, no autoload.
##
## RAW citations (acore-campaign-hijinks.xml):
##   L713: +3 on persuade reaction roll (consumed by §4.4)
##   L714: 2x normal transaction load cap (consumed by §3.2/§4.11)
##   substrate gdd-settlement-economy.md §6.4: monopolist_favor int feeds
##         MarketPriceResolver.compute_market_price (consumed by §3.2/§3.3)
##
## v1 ships the API + the empty table. Population is later work — Phase
## 10B.3's issue_decree extension, scripted plot events, future domain
## block enhancements. With an empty table:
##   * has_monopoly() returns false for every lookup.
##   * favor_for_buy() / favor_for_sell() return 0.
##   * Persuade roll's monopolist bonus is +0.
## The Trade block's transaction formulas all collapse to their non-monopolist
## base values, RAW-faithful, with zero behavioral change in v1.


# ---------------------------------------------------------------------------
# Read API
# ---------------------------------------------------------------------------

## Returns true iff [param character_id] holds an unexpired monopoly on
## [param merchandise_type] at [param settlement_id]. Expiration is defined
## by `expires_at_calendar_day` — NULL = perpetual; non-null = sunset day
## (monopoly active while current_day < expires_day).
static func has_monopoly(character_id: String, settlement_id: String, merchandise_type: String) -> bool:
	if character_id.is_empty() or settlement_id.is_empty() or merchandise_type.is_empty():
		return false
	var current_day: int = Timekeeping.get_total_days()
	if not CampaignRepository.db.query_with_bindings("""
		SELECT 1 FROM monopoly_holdings
		WHERE character_id = ?
			AND settlement_id = ?
			AND merchandise_type = ?
			AND (expires_at_calendar_day IS NULL OR expires_at_calendar_day > ?)
		LIMIT 1
	""", [character_id, settlement_id, merchandise_type, current_day]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


## Returns -1 if the character holds the monopoly (lower buy price favors
## the holder); 0 otherwise. Fed directly to MarketPriceResolver's
## monopolist_favor parameter per §8.3 sign convention.
static func favor_for_buy(character_id: String, settlement_id: String, merchandise_type: String) -> int:
	return -1 if has_monopoly(character_id, settlement_id, merchandise_type) else 0


## Returns +1 if the character holds the monopoly (higher sell price favors
## the holder); 0 otherwise. Fed to MarketPriceResolver per §8.3.
static func favor_for_sell(character_id: String, settlement_id: String, merchandise_type: String) -> int:
	return 1 if has_monopoly(character_id, settlement_id, merchandise_type) else 0


## Returns the full holding row dict, or {} if not found / expired.
static func get_monopoly_row(character_id: String, settlement_id: String, merchandise_type: String) -> Dictionary:
	if character_id.is_empty() or settlement_id.is_empty() or merchandise_type.is_empty():
		return {}
	var current_day: int = Timekeeping.get_total_days()
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM monopoly_holdings
		WHERE character_id = ?
			AND settlement_id = ?
			AND merchandise_type = ?
			AND (expires_at_calendar_day IS NULL OR expires_at_calendar_day > ?)
		LIMIT 1
	""", [character_id, settlement_id, merchandise_type, current_day]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


## Returns all unexpired monopolies held by [param character_id]. Used by
## the "your monopolies" UI surface (future polish; not in v1 critical path).
static func list_monopolies_for_character(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	var current_day: int = Timekeeping.get_total_days()
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM monopoly_holdings
		WHERE character_id = ?
			AND (expires_at_calendar_day IS NULL OR expires_at_calendar_day > ?)
		ORDER BY settlement_id ASC, merchandise_type ASC
	""", [character_id, current_day]):
		return []
	return CampaignRepository.db.query_result.duplicate()


## Returns all unexpired monopolies at [param settlement_id]. Used by
## "who holds monopolies here" reverse lookup (future polish).
static func list_monopolies_at_settlement(settlement_id: String) -> Array:
	if settlement_id.is_empty():
		return []
	var current_day: int = Timekeeping.get_total_days()
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM monopoly_holdings
		WHERE settlement_id = ?
			AND (expires_at_calendar_day IS NULL OR expires_at_calendar_day > ?)
		ORDER BY character_id ASC, merchandise_type ASC
	""", [settlement_id, current_day]):
		return []
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Write API — populated by future grant systems (Phase 10B.3 decree extension,
# scripted plot events, etc.). v1 has no caller for these but ships the API.
# ---------------------------------------------------------------------------

## Inserts a monopoly_holdings row. Returns the new holding's id, or ""
## on UNIQUE violation (character already holds this triple) or input error.
##
## [param expires_at_calendar_day] of null means perpetual. Pass an int
## for a sunset day.
##
## Emits monopoly_granted on success. No emission on failure.
static func grant_monopoly(
		character_id: String,
		settlement_id: String,
		merchandise_type: String,
		granted_at_calendar_day: int,
		granted_by_character_id: String = "",
		granted_by_authority: String = "domain_ruler",
		expires_at_calendar_day: Variant = null,
		notes: String = ""
) -> String:
	if character_id.is_empty() or settlement_id.is_empty() or merchandise_type.is_empty():
		push_error("MonopolyRegistry.grant_monopoly: character/settlement/merchandise required")
		return ""
	if not (granted_by_authority in ["domain_ruler", "judge", "inherited", "purchased"]):
		push_error("MonopolyRegistry.grant_monopoly: invalid authority '%s'" % granted_by_authority)
		return ""
	# Resolve campaign_id via the settlement.
	if not CampaignRepository.db.query_with_bindings(
			"SELECT campaign_id FROM settlement_entrances WHERE id = ?",
			[settlement_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		push_error("MonopolyRegistry.grant_monopoly: settlement '%s' not found" % settlement_id)
		return ""
	var campaign_id: String = str(CampaignRepository.db.query_result[0].get("campaign_id", ""))
	var holding_id: String = CampaignRepository.generate_id()
	var grantor: Variant = granted_by_character_id if not granted_by_character_id.is_empty() else null
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO monopoly_holdings
			(id, campaign_id, character_id, settlement_id, merchandise_type,
			 granted_at_calendar_day, granted_by_character_id,
			 granted_by_authority, expires_at_calendar_day, notes)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		holding_id, campaign_id, character_id, settlement_id, merchandise_type,
		granted_at_calendar_day, grantor,
		granted_by_authority, expires_at_calendar_day, notes,
	]):
		# UNIQUE violation or other failure — return "" without error spam
		# (callers that care can re-query to distinguish).
		return ""
	EventBus.monopoly_granted.emit(holding_id, character_id, settlement_id, merchandise_type)
	return holding_id


## Revokes the holding by id. Returns false if not found.
## Emits monopoly_revoked on success.
static func revoke_monopoly(holding_id: String) -> bool:
	if holding_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
			"SELECT character_id, settlement_id, merchandise_type FROM monopoly_holdings WHERE id = ?",
			[holding_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var row: Dictionary = CampaignRepository.db.query_result[0]
	if not CampaignRepository.db.query_with_bindings(
			"DELETE FROM monopoly_holdings WHERE id = ?", [holding_id]):
		return false
	EventBus.monopoly_revoked.emit(
		holding_id,
		str(row.get("character_id", "")),
		str(row.get("settlement_id", "")),
		str(row.get("merchandise_type", "")))
	return true


## Revokes by triple. Convenience for callers who don't track holding_id.
## Returns false if no matching row.
static func revoke_monopoly_by_triple(
		character_id: String, settlement_id: String, merchandise_type: String
) -> bool:
	if character_id.is_empty() or settlement_id.is_empty() or merchandise_type.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM monopoly_holdings
		WHERE character_id = ? AND settlement_id = ? AND merchandise_type = ?
		LIMIT 1
	""", [character_id, settlement_id, merchandise_type]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var holding_id: String = str(CampaignRepository.db.query_result[0].get("id", ""))
	return revoke_monopoly(holding_id)
