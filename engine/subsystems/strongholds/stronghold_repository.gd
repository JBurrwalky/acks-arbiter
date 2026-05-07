class_name StrongholdRepository
extends RefCounted

## Read-side accessors for stronghold sufficiency calculation per
## `acore_axioms_strongholds_and_domains.xml` §minimum_stronghold_value L88-94
## and §noncontiguous_domains L95-98.
##
## Sufficiency rule: SUM(gp_value) of completed strongholds in a domain must
## meet the per-classification minimum × hex_count threshold.
##   * Civilized:   15,000 gp / 6-mile hex
##   * Borderlands: 22,500 gp / 6-mile hex
##   * Wilderness:  32,000 gp / 6-mile hex
##
## In-progress strongholds contribute zero (RAW operates on completed value;
## the morale resolver's tier formula does the partial-sufficiency math at
## the domain level via the half / quarter / below-quarter penalty).
##
## NOTE: Phase 1 simplification — sufficiency sums all completed strongholds
## in the domain regardless of contiguity. `acore_axioms` §noncontiguous_domains
## L95-98 says combined value must secure all noncontiguous hexes AND the
## intervening hexes between them. Phase 2+ (per-hex peasant allocation)
## will add the contiguity check.

const _CLASSIFICATION_MIN_GP_PER_HEX := {
	"civilized": 15000,
	"borderlands": 22500,
	"wilderness": 32000,
}


## SUM gp_value of completed strongholds for a domain. Used by the Phase 0
## domain monthly tick to release the income gate when sufficiency is met.
static func get_stronghold_value_for_domain(domain_id: String) -> int:
	if domain_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(gp_value), 0) AS total
		FROM strongholds
		WHERE domain_id = ? AND status = 'completed'
	""", [domain_id]):
		push_error("StrongholdRepository.get_stronghold_value_for_domain: query failed. domain=%s" % domain_id)
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("total", 0))


## Returns the per-hex minimum stronghold value for a classification, or 0
## for unknown classifications (caller should treat as wilderness for safety).
static func per_hex_minimum_for(territory_type: String) -> int:
	return int(_CLASSIFICATION_MIN_GP_PER_HEX.get(territory_type, 32000))


## Compute the classification minimum gp required to secure a domain.
## minimum = per_hex × max(1, hex_count).
static func classification_minimum_gp(territory_type: String, hex_count: int) -> int:
	return per_hex_minimum_for(territory_type) * maxi(1, hex_count)


## Boolean check: does the domain's completed-stronghold value meet its
## classification minimum?
static func is_sufficient_for_domain(domain_id: String) -> bool:
	if domain_id.is_empty():
		return false
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return false
	var hex_count: int = CampaignRepository.get_domain_hexes(domain_id).size()
	var minimum_gp: int = classification_minimum_gp(
		String(domain.get("territory_type", "wilderness")), hex_count)
	var value_gp: int = get_stronghold_value_for_domain(domain_id)
	return value_gp >= minimum_gp


## In-memory cache of last-known sufficiency status per domain. Used to detect
## flips so `stronghold_sufficiency_changed` only fires on actual transitions.
## Cleared on session unload (Phase 4 may persist this if dashboards need it).
static var _sufficiency_cache: Dictionary = {}


## Recompute sufficiency for a domain and emit `stronghold_sufficiency_changed`
## if the boolean has flipped since last check. Called by:
##   * commission_pipeline.advance_commissions after each completed crossing
##   * claiming_resolver.claim_existing after each claim
##   * (Future) siege_resolver after destruction
static func recompute_sufficiency_after_change(domain_id: String) -> void:
	if domain_id.is_empty():
		return
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return
	var hex_count: int = CampaignRepository.get_domain_hexes(domain_id).size()
	var minimum_gp: int = classification_minimum_gp(
		String(domain.get("territory_type", "wilderness")), hex_count)
	var value_gp: int = get_stronghold_value_for_domain(domain_id)
	var is_sufficient: bool = value_gp >= minimum_gp

	var prior: Variant = _sufficiency_cache.get(domain_id)
	# First check: prior is null → seed cache, no signal (no flip detected yet).
	if prior == null:
		_sufficiency_cache[domain_id] = is_sufficient
		return
	if bool(prior) != is_sufficient:
		_sufficiency_cache[domain_id] = is_sufficient
		EventBus.stronghold_sufficiency_changed.emit(
			domain_id, is_sufficient, value_gp, minimum_gp)


## Manually seed the sufficiency cache for a domain (used by tests to control
## the baseline state before exercising flip detection).
static func _set_sufficiency_cache_for_test(domain_id: String, is_sufficient: bool) -> void:
	_sufficiency_cache[domain_id] = is_sufficient


## Clear the sufficiency cache (used by tests between runs).
static func _clear_sufficiency_cache_for_test() -> void:
	_sufficiency_cache.clear()
