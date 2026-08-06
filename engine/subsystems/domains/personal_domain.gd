class_name PersonalDomain
extends RefCounted

## D-12 — ONE CHARACTER, ONE DOMAIN (Jedidiah ruling 2026-08-05).
##
## RAW does not permit a character to hold multiple domains. Any land he
## personally rules is *his domain*, one record — "each character sheet has one
## domain record page." He may hold many strongholds within it, non-contiguous
## hexes, and secured-but-unpopulated hexes; it is all one domain however far
## apart the pieces lie, and RAW prices that through the oversize and
## non-contiguity penalties rather than by forbidding it.
##
## **Path 2 — aggregate on read.** `domains` rows are retained as PARCELS, for
## identity and history; the CHARACTER is the domain. This file is the union: it
## answers every RAW-relevant question about a character's holdings once, over
## all his parcels at once. Path 1 (a verbatim merge into one row) was rejected
## for cascade risk across a dozen FK tables and the loss of parcel history;
## Path 3 (forbid the state at the acquisition boundary) is *less* RAW-faithful.
##
## WHY IT MATTERS — splitting a domain is currently a pure exploit:
##   * **Oversize is defeated.** RAW's oversize mechanic IS personal authority
##     (`acore_axioms` §personal_authority L430-449): level cross-referenced with
##     domain INCOME, down to −4 base morale. Per parcel, a 6th-level lord with
##     one 600 gp domain takes the harsh band, but three 200 gp parcels give him
##     three lookups in a mild band — a morale BONUS for holding land in pieces.
##   * **Tribute-out is overcharged ~55%.** `18 × families^0.6` is concave, so
##     the sum of the parts exceeds the whole: three 100-family parcels pay
##     3 × 285 = 856 gp where a merged 300-family domain pays 551 gp.
##   * **Non-contiguity stops biting.** RAW has no standalone penalty; it works
##     THROUGH stronghold sufficiency (owned + intervening hexes). Separate
##     parcels are each internally contiguous, so intervening hexes are never
##     counted and the penalty never fires.
##
## THE TWO-TIER RULE IS MANDATORY. Per-hex math is only available for
## MATERIALIZED domains — `_materialize_domain_hexes` runs solely over the region
## map, so an abstract off-window domain owns ZERO `domain_hexes` rows. Every
## per-hex quantity here therefore carries a documented aggregate fallback keyed
## on `domains.territory_type`, and `is_materialized` tells the caller which
## regime produced the numbers. A per-hex rule that silently returns 0 for the
## off-camera world is worse than the aggregate it replaced.
##
## WHAT THIS FILE MUST NEVER TOUCH: a settlement's own state. Unification is
## about the RULER's economics. Urban settlements are generated once and are
## stable thereafter, changing only through population growth/decline and
## war/siege — if John holds a settlement on day 90 and conquers a second on day
## 98, no population moves between them. `urban_families` and `market_class` live
## on `settlement_entrances` (migration 097 deliberately moved them off
## `domains`), and nothing here writes to that table. In particular the
## settlement growth tick must keep receiving its PARCEL's `peasant_families`,
## never this union — realm-wide it would inflate the clanhold cap for every
## settlement the character owns.
##
## Public API:
##   for_character(character_id) -> Dictionary
##   for_domain(domain_data) -> Dictionary
##   worst_classification(classification_counts) -> String

## Lifecycle states whose parcels are NOT part of the personal domain. An
## abandoned or salted holding is preserved as an audit row — `DomainHandlers`
## already skips them in the monthly loop — so counting their families toward
## the ruler's oversize band or his tribute would charge him for land he no
## longer holds. Mirrors `LifecycleHandler.STATE_ABANDONED` / `STATE_SALTED_TO_RUIN`.
const EXCLUDED_LIFECYCLE_STATES: Array[String] = ["abandoned", "salted_to_ruin"]

## RAW classification order, harshest LAST. Used by `worst_classification`.
const CLASSIFICATION_SEVERITY: Array[String] = ["civilized", "borderlands", "wilderness"]

## Fallback classification when a hex has no `hex_cells` row and its parcel names
## nothing — matches the schema default on both `hex_cells.civilization` and
## `domains.territory_type`, and is the STRICTEST of the three, so a data gap
## overcharges rather than undercharges.
const DEFAULT_CLASSIFICATION := "wilderness"


## The union of everything `character_id` personally rules.
##
## Returns:
##   character_id           String
##   parcels                Array[Dictionary] — the contributing domain rows
##   parcel_ids             Array[String]
##   parcel_count           int
##   is_materialized        bool  — true when ANY parcel has domain_hexes rows;
##                                  false means every number below came from the
##                                  per-domain aggregate fallback
##   peasant_families       int
##   urban_families         int
##   families               int   — peasant + urban, the RAW tribute input
##   revenue_cp             int
##   expenses_cp            int
##   net_income_cp          int   — the RAW personal-authority income input
##   hexes                  Array[Dictionary] — owned hexes with `civilization`
##   owned_hex_count        int
##   effective_hex_count    int   — owned + intervening (RAW §noncontiguous L95-98)
##   intervening_hex_count  int
##   classification_counts  Dictionary — {civilized,borderlands,wilderness} over
##                                       the EFFECTIVE hex set
##   worst_classification   String
##   stronghold_minimum_cp  int   — Σ per-hex minimum over the effective hex set
##   stronghold_value_cp    int   — Σ strongholds.cp_value across parcels
##   garrison_minimum_cp    int   — Σ per-hex families × that hex's RAW gp/family
##   seat_parcel_id         String — the lowest-id parcel: the character's DOMAIN
##                                   RECORD PAGE. Carrier of prior morale and of
##                                   the per-parcel morale inputs that cannot be
##                                   summed (alignment, population kind, tax and
##                                   liturgy RATES). "" when he holds nothing.
##   tribute_seat_id        String — the lowest-id parcel bearing a liege pointer;
##                                   the ONE parcel charged the character's realm
##                                   tribute and scutage. "" when he owes none.
static func for_character(character_id: String) -> Dictionary:
	var out: Dictionary = _empty(character_id)
	if character_id.is_empty():
		return out

	var parcels: Array = _list_parcels(character_id)
	out["parcels"] = parcels
	out["parcel_count"] = parcels.size()
	if parcels.is_empty():
		return out

	var parcel_ids: Array = []
	for p in parcels:
		var row: Dictionary = p
		var pid: String = String(row.get("id", ""))
		parcel_ids.append(pid)
		# `parcels` is ORDER BY d.id, so the first of each is the lowest id.
		if String(out["seat_parcel_id"]).is_empty():
			out["seat_parcel_id"] = pid
		if String(out["tribute_seat_id"]).is_empty() and _has_liege(row):
			out["tribute_seat_id"] = pid
		out["peasant_families"] = int(out["peasant_families"]) + int(row.get("peasant_families", 0))
		out["urban_families"] = int(out["urban_families"]) + int(row.get("urban_families", 0))
		out["revenue_cp"] = int(out["revenue_cp"]) + int(row.get("revenue_cp", 0))
		out["expenses_cp"] = int(out["expenses_cp"]) + int(row.get("expenses_cp", 0))
	out["parcel_ids"] = parcel_ids
	out["families"] = int(out["peasant_families"]) + int(out["urban_families"])
	out["net_income_cp"] = int(out["revenue_cp"]) - int(out["expenses_cp"])
	out["stronghold_value_cp"] = _stronghold_value_for_parcels(parcel_ids)

	var hexes: Array = _list_hexes(parcel_ids)
	out["hexes"] = hexes
	out["owned_hex_count"] = hexes.size()
	out["is_materialized"] = not hexes.is_empty()

	if hexes.is_empty():
		_apply_aggregate_fallback(out, parcels)
		return out

	_apply_per_hex(out, hexes)
	return out


## Convenience for the monthly tick, which holds a parcel row rather than an id.
## An ownerless parcel has no personal domain to belong to, so it answers for
## itself — the caller still gets usable numbers instead of a zeroed dict.
static func for_domain(domain_data: Dictionary) -> Dictionary:
	var owner_v: Variant = domain_data.get("owner_character_id")
	var owner_id: String = String(owner_v) if owner_v != null else ""
	if not owner_id.is_empty():
		return for_character(owner_id)
	var solo: Dictionary = _empty("")
	solo["parcels"] = [domain_data]
	solo["parcel_ids"] = [String(domain_data.get("id", ""))]
	solo["parcel_count"] = 1
	solo["seat_parcel_id"] = String(domain_data.get("id", ""))
	if _has_liege(domain_data):
		solo["tribute_seat_id"] = String(domain_data.get("id", ""))
	solo["peasant_families"] = int(domain_data.get("peasant_families", 0))
	solo["urban_families"] = int(domain_data.get("urban_families", 0))
	solo["families"] = int(solo["peasant_families"]) + int(solo["urban_families"])
	solo["revenue_cp"] = int(domain_data.get("revenue_cp", 0))
	solo["expenses_cp"] = int(domain_data.get("expenses_cp", 0))
	solo["net_income_cp"] = int(solo["revenue_cp"]) - int(solo["expenses_cp"])
	solo["stronghold_value_cp"] = _stronghold_value_for_parcels(solo["parcel_ids"])
	var hexes: Array = _list_hexes(solo["parcel_ids"])
	solo["hexes"] = hexes
	solo["owned_hex_count"] = hexes.size()
	solo["is_materialized"] = not hexes.is_empty()
	if hexes.is_empty():
		_apply_aggregate_fallback(solo, [domain_data])
	else:
		_apply_per_hex(solo, hexes)
	return solo


## THE ONE STRONGHOLD-SUFFICIENCY ANSWER, for the domain a caller is looking at
## but judged over its OWNER'S WHOLE HOLDING.
##
## RAW lets a ruler hold many strongholds within one domain *"so long as their
## combined value secures the land"*, and prices non-contiguity **through** that
## test rather than as a standalone penalty (§noncontiguous_domains L95-98): the
## minimum covers owned PLUS intervening hexes. The monthly tick judges it on the
## union, so every other reader must too. A Stronghold sub-tab quoting a
## per-parcel minimum while the tick holds the income gate open is the
## conventions §130 two-copies-of-one-answer failure with a player-visible face —
## and for the ruler AI it is a wrong decision, not just a wrong label: it would
## keep proposing investment for a parcel his other keeps already secure.
##
## Returns:
##   value_cp              int  — Σ completed strongholds.cp_value across parcels
##   minimum_cp            int  — Σ each effective hex's own RAW minimum
##   shortfall_cp          int  — max(0, minimum - value)
##   is_sufficient         bool
##   owned_hex_count       int
##   intervening_hex_count int
##   effective_hex_count   int
##   parcel_count          int
##   is_materialized       bool — false means the aggregate fallback produced these
##   character_id          String — "" for an ownerless seat, which answers alone
static func sufficiency_for_domain(domain_id: String) -> Dictionary:
	if domain_id.is_empty():
		return sufficiency(_empty(""))
	var row: Dictionary = CampaignRepository.get_domain(domain_id)
	if row.is_empty():
		return sufficiency(_empty(""))
	return sufficiency(for_domain(row))


## The same verdict from a union the caller already holds, so a path that has one
## need not rebuild it (`for_character` runs three queries).
static func sufficiency(union: Dictionary) -> Dictionary:
	var value_cp: int = int(union.get("stronghold_value_cp", 0))
	var minimum_cp: int = int(union.get("stronghold_minimum_cp", 0))
	return {
		"value_cp": value_cp,
		"minimum_cp": minimum_cp,
		"shortfall_cp": maxi(0, minimum_cp - value_cp),
		"is_sufficient": value_cp >= minimum_cp,
		"owned_hex_count": int(union.get("owned_hex_count", 0)),
		"intervening_hex_count": int(union.get("intervening_hex_count", 0)),
		"effective_hex_count": int(union.get("effective_hex_count", 0)),
		"parcel_count": int(union.get("parcel_count", 0)),
		"is_materialized": bool(union.get("is_materialized", false)),
		"character_id": String(union.get("character_id", "")),
	}


## The harshest classification present — RAW's morale modifier under D-12 is
## driven by the ruler's ROUGHEST holding, not by an average or by his seat
## (Jedidiah 2026-08-05, marked provisional: "worst classification, for the time
## being"). Returns "civilized" for an empty set, which is the mildest reading
## and therefore never invents a penalty out of missing data.
static func worst_classification(classification_counts: Dictionary) -> String:
	var worst := ""
	for name in CLASSIFICATION_SEVERITY:
		if int(classification_counts.get(name, 0)) > 0:
			worst = name
	return worst if not worst.is_empty() else CLASSIFICATION_SEVERITY[0]


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _empty(character_id: String) -> Dictionary:
	return {
		"character_id": character_id,
		"parcels": [],
		"parcel_ids": [],
		"parcel_count": 0,
		"is_materialized": false,
		"peasant_families": 0,
		"urban_families": 0,
		"families": 0,
		"revenue_cp": 0,
		"expenses_cp": 0,
		"net_income_cp": 0,
		"hexes": [],
		"owned_hex_count": 0,
		"effective_hex_count": 0,
		"intervening_hex_count": 0,
		"classification_counts": {},
		"worst_classification": CLASSIFICATION_SEVERITY[0],
		"stronghold_minimum_cp": 0,
		"stronghold_value_cp": 0,
		"garrison_minimum_cp": 0,
		"seat_parcel_id": "",
		"tribute_seat_id": "",
	}


## True when this parcel row points at a liege domain. `liege_domain_id` is a
## nullable TEXT column, so `null` and `""` both mean "holds of no one".
static func _has_liege(row: Dictionary) -> bool:
	var v: Variant = row.get("liege_domain_id")
	return v != null and not String(v).is_empty()


## The character's non-terminal parcels. `urban_families` is aggregated from
## `settlement_entrances` exactly as `RealmAggregator._list_owned_domains` does
## (migration 097 moved the column off `domains`); the two must not disagree
## about what a character owns.
static func _list_parcels(character_id: String) -> Array:
	var placeholders: Array = []
	var binds: Array = [character_id]
	for state in EXCLUDED_LIFECYCLE_STATES:
		placeholders.append("?")
		binds.append(state)
	if not CampaignRepository.db.query_with_bindings("""
		SELECT d.id, d.campaign_id, d.peasant_families,
			   COALESCE((
				   SELECT SUM(urban_families)
				   FROM settlement_entrances
				   WHERE parent_domain_id = d.id
			   ), 0) AS urban_families,
			   d.revenue_cp, d.expenses_cp, d.territory_type, d.garrison_troops,
			   d.lifecycle_state, d.realm_title, d.domain_style, d.liege_domain_id
		FROM domains d
		WHERE d.owner_character_id = ?
		  AND d.lifecycle_state NOT IN (%s)
		ORDER BY d.id
	""" % ", ".join(placeholders), binds):
		return []
	return CampaignRepository.db.query_result.duplicate()


## Every owned hex across the parcels, each carrying its OWN classification from
## `hex_cells`. This is the join the domain layer never made — and the reason it
## never made it is naming drift: the same concept is `setting_hexes.territory_class`
## at generation, `hex_cells.civilization` on the runtime map, and
## `domains.territory_type` in the aggregate. It does not look like the same
## field, so nobody joined it (D-12 open question 3).
static func _list_hexes(parcel_ids: Array) -> Array:
	if parcel_ids.is_empty():
		return []
	var placeholders: Array = []
	for _id in parcel_ids:
		placeholders.append("?")
	if not CampaignRepository.db.query_with_bindings("""
		SELECT dh.domain_id, dh.map_id, dh.hex_q, dh.hex_r, dh.families,
			   dh.land_value,
			   COALESCE(hc.civilization, '%s') AS civilization
		FROM domain_hexes dh
		LEFT JOIN hex_cells hc
			   ON hc.map_id = dh.map_id AND hc.q = dh.hex_q AND hc.r = dh.hex_r
		WHERE dh.domain_id IN (%s)
		ORDER BY dh.map_id, dh.hex_q, dh.hex_r
	""" % [DEFAULT_CLASSIFICATION, ", ".join(placeholders)], parcel_ids.duplicate()):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func _stronghold_value_for_parcels(parcel_ids: Array) -> int:
	var total: int = 0
	for id_v in parcel_ids:
		total += StrongholdRepository.get_stronghold_value_for_domain(String(id_v))
	return total


## PER-HEX REGIME (materialized domains). The stronghold minimum is the SUM of
## each hex's own RAW minimum rather than one classification × a count, and the
## sum runs over the EFFECTIVE set — owned plus the intervening hexes the
## strongholds must also secure. Intervening hexes contribute their minimum but
## no families: they are secured, not held.
static func _apply_per_hex(out: Dictionary, hexes: Array) -> void:
	var counts: Dictionary = {}
	var minimum_cp: int = 0
	var garrison_cp: int = 0
	# Owned hexes, grouped by `map_id` before the contiguity walk.
	#
	# BE CLEAR ABOUT WHAT THIS IS AND IS NOT. A campaign has exactly ONE rolling
	# 6-mile map: `RegionZoomIn` inserts a single `regional_6mi` row and
	# `grow_frontier` GROWS THAT SAME ROW (new `hex_cells` + an extended
	# `parent_hex_footprint`) rather than minting another. Both
	# `SettingMaterializer` and `RulerLodManager` look it up with `LIMIT 1`, and
	# world gen writes every `domain_hexes` row with that one id. So in
	# production this loop always runs exactly once and the grouping changes
	# nothing. `domain_hexes.map_id` is a migration-119 holdover from the older
	# 24-mile-map-plus-discrete-insets model, which the rolling frontier replaced.
	#
	# It is kept as a NAMESPACE GUARD, not as multi-map support:
	# `CampaignRepository.add_domain_hex` writes `''` as a sentinel `map_id` when
	# the domain has no `location_map_id`, and coordinates in that namespace are
	# undefined — pathing them against real map coordinates could collide on
	# (q, r) or invent intervening hexes between things that were never adjacent.
	# Six lines to make that unrepresentable is worth it; a claim that this
	# supports holdings on separate maps would not be true.
	var owned_by_map: Dictionary = {}
	for h in hexes:
		var row: Dictionary = h
		var civ: String = String(row.get("civilization", DEFAULT_CLASSIFICATION))
		counts[civ] = int(counts.get(civ, 0)) + 1
		minimum_cp += StrongholdRepository.per_hex_minimum_for(civ)
		# RAW garrison cost is 2/3/4 gp per family by classification — under D-12
		# it is THIS hex's rate against THIS hex's families, so a wilderness
		# frontier hex costs 4 gp/family even when the seat is civilized.
		garrison_cp += int(row.get("families", 0)) \
			* DomainStocker.garrison_gp_per_family(civ) * 100
		var map_id: String = String(row.get("map_id", ""))
		if not owned_by_map.has(map_id):
			owned_by_map[map_id] = {}
		(owned_by_map[map_id] as Dictionary)[
			Vector2i(int(row.get("hex_q", 0)), int(row.get("hex_r", 0)))] = true

	var intervening_total: int = 0
	for map_id in owned_by_map:
		var connecting: Dictionary = StrongholdRepository.connecting_hexes_for_set(
			owned_by_map[map_id])
		if connecting.is_empty():
			continue
		intervening_total += connecting.size()
		for civ in _classifications_for_coords(String(map_id), connecting.keys()):
			counts[civ] = int(counts.get(civ, 0)) + 1
			minimum_cp += StrongholdRepository.per_hex_minimum_for(civ)

	out["classification_counts"] = counts
	out["worst_classification"] = worst_classification(counts)
	out["intervening_hex_count"] = intervening_total
	out["effective_hex_count"] = int(out["owned_hex_count"]) + intervening_total
	out["stronghold_minimum_cp"] = minimum_cp
	out["garrison_minimum_cp"] = garrison_cp


## Classification of arbitrary map coordinates — the intervening hexes, which own
## no `domain_hexes` row. A coordinate with no `hex_cells` row (off the edge of a
## materialized map) falls back to the strictest classification, so a data gap
## raises the minimum rather than quietly lowering it.
static func _classifications_for_coords(map_id: String, coords: Array) -> Array:
	var out: Array = []
	if coords.is_empty():
		return out
	# `(q, r) IN ((?,?), …)` row-value syntax needs SQLite 3.15+; the OR form
	# works on every build godot-sqlite might ship, and the coordinate count here
	# is the number of INTERVENING hexes, which is small by construction.
	var placeholders: Array = []
	var binds: Array = [map_id]
	for c in coords:
		placeholders.append("(q = ? AND r = ?)")
		binds.append((c as Vector2i).x)
		binds.append((c as Vector2i).y)
	var found: Dictionary = {}
	if CampaignRepository.db.query_with_bindings("""
		SELECT q, r, civilization FROM hex_cells
		WHERE map_id = ? AND (%s)
	""" % " OR ".join(placeholders), binds):
		for row in CampaignRepository.db.query_result:
			found[Vector2i(int((row as Dictionary).get("q", 0)),
				int((row as Dictionary).get("r", 0)))] = \
				String((row as Dictionary).get("civilization", DEFAULT_CLASSIFICATION))
	for c in coords:
		out.append(String(found.get(c, DEFAULT_CLASSIFICATION)))
	return out


## AGGREGATE FALLBACK (abstract, off-window domains — the two-tier rule). No
## `domain_hexes` rows exist, so per-hex math is unavailable and the parcel's own
## `domains.territory_type` stands in. Each parcel counts as one hex for the
## minimum, matching `StrongholdRepository.classification_minimum_cp`'s existing
## `maxi(1, hex_count)` floor, and garrison cost falls back to the parcel's
## families at the parcel's rate — which is exactly today's behaviour, so an
## abstract domain's numbers do not move under D-12.
static func _apply_aggregate_fallback(out: Dictionary, parcels: Array) -> void:
	var counts: Dictionary = {}
	var minimum_cp: int = 0
	var garrison_cp: int = 0
	for p in parcels:
		var row: Dictionary = p
		var civ: String = String(row.get("territory_type", DEFAULT_CLASSIFICATION))
		counts[civ] = int(counts.get(civ, 0)) + 1
		minimum_cp += StrongholdRepository.classification_minimum_cp(civ, 1)
		garrison_cp += int(row.get("peasant_families", 0)) \
			* DomainStocker.garrison_gp_per_family(civ) * 100
	out["classification_counts"] = counts
	out["worst_classification"] = worst_classification(counts)
	out["effective_hex_count"] = parcels.size()
	out["intervening_hex_count"] = 0
	out["stronghold_minimum_cp"] = minimum_cp
	out["garrison_minimum_cp"] = garrison_cp
