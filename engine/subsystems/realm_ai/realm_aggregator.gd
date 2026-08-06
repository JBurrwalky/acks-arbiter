class_name RealmAggregator
extends RefCounted

## Aggregates personal + vassal-domain families / revenue / expenses /
## garrison for a given ruler character per Phase 7 of
## docs/domain-roadmap-corrected.md.
##
## Used by:
##   - TributeCalculator: realm_families is the input to the RAW tribute table
##     per acore_axioms §tribute_by_realm_families L300-350
##   - RealmTitleResolver: needs personal_domain_families, domains_ruled,
##     overall_realm_families per §titles_of_nobility L273-285
##   - The realm sub-tab Realm Aggregates collapsible card
##   - The Vagaries-of-Recruitment "tribute" handler (max gp = 1 × realm
##     peasant families)
##
## v1 design: walks the realm tree top-down from the ruler, summing only
## ACTIVE vassal_assignments. Multi-level hierarchies (vassal-of-vassal) sum
## recursively up to a depth cap (8) to defend against cycles.
##
## Public API:
##   aggregate(ruler_character_id) -> Dictionary
##     {
##       personal_families: int,           — sum of peasant + urban for ruler-owned domains
##       personal_peasant_families: int,
##       personal_urban_families: int,
##       personal_revenue_cp: int,
##       personal_expenses_cp: int,
##       personal_garrison_units: int,
##       direct_vassals: Array,            — [{vassal_assignment_id, vassal_character_id, families}]
##       direct_vassal_count: int,
##       vassal_families: int,             — sum across direct vassals (one level deep)
##       all_realm_families: int,          — recursive sum: personal + all sub-levels
##       all_realm_peasant_families: int,
##       all_realm_urban_families: int,
##       domains_ruled: int,               — count of domains the ruler personally owns
##     }

## Sanity backstop only — the `visited` set in `_recursive_realm_sum` is the real
## cycle guard. R-1 made the liege tree genuinely walkable (world generation now
## mints an appointment row per realm edge), and a generated realm stacks the civ
## ladder under war-vassal crown chains, so the old cap of 8 was reachable: it
## would silently under-report a deep realm's families — corrupting the RAW tribute
## table lookup — while spamming push_error every month. Matches
## `RealmGraph._MAX_LIEGE_HOPS`, so the two walkers agree on what counts as a cycle.
const _MAX_DEPTH := 64


static func aggregate(ruler_character_id: String) -> Dictionary:
	var result: Dictionary = {
		"personal_families": 0,
		"personal_peasant_families": 0,
		"personal_urban_families": 0,
		"personal_revenue_cp": 0,
		"personal_expenses_cp": 0,
		"personal_garrison_units": 0,
		"direct_vassals": [],
		"direct_vassal_count": 0,
		"vassal_families": 0,
		"all_realm_families": 0,
		"all_realm_peasant_families": 0,
		"all_realm_urban_families": 0,
		"domains_ruled": 0,
	}
	if ruler_character_id.is_empty():
		return result

	# Personal aggregate: all domains where owner_character_id == ruler.
	var personal_domains: Array = _list_owned_domains(ruler_character_id)
	result["domains_ruled"] = personal_domains.size()
	for d in personal_domains:
		var peasant: int = int(d.get("peasant_families", 0))
		var urban: int = int(d.get("urban_families", 0))
		result["personal_peasant_families"] = int(result["personal_peasant_families"]) + peasant
		result["personal_urban_families"] = int(result["personal_urban_families"]) + urban
		result["personal_families"] = int(result["personal_families"]) + peasant + urban
		result["personal_revenue_cp"] = int(result["personal_revenue_cp"]) + int(d.get("revenue_cp", 0))
		result["personal_expenses_cp"] = int(result["personal_expenses_cp"]) + int(d.get("expenses_cp", 0))
		result["personal_garrison_units"] = int(result["personal_garrison_units"]) + int(d.get("garrison_troops", 0))

	# Direct vassals + recursive realm sum.
	var direct_assignments: Array = VassalRepository.list_active_for_liege(ruler_character_id)
	result["direct_vassal_count"] = direct_assignments.size()
	var visited: Dictionary = {}  # character_id → true
	visited[ruler_character_id] = true
	var vassal_families_total: int = 0
	# R-1 perf: accumulate the peasant/urban split from the SAME walk that produces
	# `families`. `_recursive_realm_sum` already returns all three, and the second
	# full-tree walk that used to compute this split below made every consumer pay
	# for the realm twice — once per direct vassal here, then the whole tree again.
	# With `vassal_assignments` empty that cost nothing; R-1 makes the trees real.
	var vassal_peasant_total: int = 0
	var vassal_urban_total: int = 0
	for assn in direct_assignments:
		var vassal_char: String = String(assn.get("vassal_character_id", ""))
		var sub: Dictionary = _recursive_realm_sum(vassal_char, visited, 1)
		var fam: int = int(sub.get("families", 0))
		vassal_families_total += fam
		vassal_peasant_total += int(sub.get("peasant_families", 0))
		vassal_urban_total += int(sub.get("urban_families", 0))
		result["direct_vassals"].append({
			"vassal_assignment_id": String(assn.get("id", "")),
			"vassal_character_id": vassal_char,
			"vassal_domain_id": String(assn.get("vassal_domain_id", "")),
			"is_henchman_vassal": int(assn.get("is_henchman_vassal", 1)) == 1,
			"families": fam,
		})

	result["vassal_families"] = vassal_families_total
	result["all_realm_families"] = int(result["personal_families"]) + vassal_families_total

	# Recursive peasant/urban breakdown — used by tribute UI display. Personal plus
	# what the loop above already summed; identical to the result of re-walking the
	# whole tree from the ruler, because that walk visits exactly the ruler's own
	# domains plus each direct vassal's subtree.
	result["all_realm_peasant_families"] = \
		int(result["personal_peasant_families"]) + vassal_peasant_total
	result["all_realm_urban_families"] = \
		int(result["personal_urban_families"]) + vassal_urban_total

	return result


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _list_owned_domains(character_id: String) -> Array:
	# urban_families lives on settlement_entrances post-migration 097 (Q-MERC-15
	# Option A). LEFT JOIN + SUM aggregates per domain; COALESCE returns 0
	# when no settlement_entrances rows exist for the domain.
	if character_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT d.id, d.peasant_families,
			   COALESCE((
				   SELECT SUM(urban_families)
				   FROM settlement_entrances
				   WHERE parent_domain_id = d.id
			   ), 0) AS urban_families,
			   d.revenue_cp, d.expenses_cp, d.garrison_troops, d.realm_title
		FROM domains d
		WHERE d.owner_character_id = ?
	""", [character_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func _recursive_realm_sum(character_id: String, visited: Dictionary, depth: int) -> Dictionary:
	var sub: Dictionary = {"families": 0, "peasant_families": 0, "urban_families": 0}
	if character_id.is_empty():
		return sub
	if depth > _MAX_DEPTH:
		push_error("RealmAggregator._recursive_realm_sum: depth %d exceeded for %s" % [depth, character_id])
		return sub
	if visited.has(character_id):
		return sub
	var local_visited: Dictionary = visited.duplicate()
	local_visited[character_id] = true

	var domains: Array = _list_owned_domains(character_id)
	for d in domains:
		var p: int = int(d.get("peasant_families", 0))
		var u: int = int(d.get("urban_families", 0))
		sub["peasant_families"] = int(sub["peasant_families"]) + p
		sub["urban_families"] = int(sub["urban_families"]) + u
		sub["families"] = int(sub["families"]) + p + u

	var subvassals: Array = VassalRepository.list_active_for_liege(character_id)
	for assn in subvassals:
		var sub_char: String = String(assn.get("vassal_character_id", ""))
		var deeper: Dictionary = _recursive_realm_sum(sub_char, local_visited, depth + 1)
		sub["families"] = int(sub["families"]) + int(deeper.get("families", 0))
		sub["peasant_families"] = int(sub["peasant_families"]) + int(deeper.get("peasant_families", 0))
		sub["urban_families"] = int(sub["urban_families"]) + int(deeper.get("urban_families", 0))

	return sub
