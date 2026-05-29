class_name SpecialistBonusResolver
extends RefCounted

## Specialist bonus lookup (Wilderness closure Phase 6).
##
## Pure logic — queries the `specialists` table and aggregates the bonus
## value for the requested resolver kind across every active specialist
## attached to the party.
##
## Authority — see `SpecialistCatalog` for SACRED citations and
## project-designed numeric bonuses.
##
## Stacking model: bonuses STACK across multiple specialists of the same kind
## (a party with two Pathfinders gets +8 to lair_search). RAW does not
## prohibit this — wilderness scout availability tables suggest a party may
## hire several. The Notebook UI may discourage it for cost reasons but the
## engine doesn't refuse.


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Total specialist bonus for [param resolver_kind] across all active
## specialists in [param party_id]. Returns 0 when no specialists are
## attached or none contribute to this kind.
##
## [param resolver_kind] is one of `SpecialistCatalog.KIND_*` constants:
##   "lair_search" / "lair_search_passive" / "surveying" / "tracking".
static func bonus_for(campaign_id: String, party_id: String, resolver_kind: String) -> int:
	if campaign_id.is_empty() or party_id.is_empty() or resolver_kind.is_empty():
		return 0
	var rows: Array = CampaignRepository.list_active_specialists(campaign_id, party_id)
	var total: int = 0
	for row: Dictionary in rows:
		var kind: String = str(row.get("kind", ""))
		total += SpecialistCatalog.bonus_for_resolver(kind, resolver_kind)
	return total


## Convenience for callers that already have a Dictionary list of specialists
## (e.g., test fixtures, in-memory aggregates). Avoids the DB roundtrip.
static func bonus_from_rows(rows: Array, resolver_kind: String) -> int:
	var total: int = 0
	for row in rows:
		if not (row is Dictionary):
			continue
		var kind: String = str(row.get("kind", ""))
		total += SpecialistCatalog.bonus_for_resolver(kind, resolver_kind)
	return total
