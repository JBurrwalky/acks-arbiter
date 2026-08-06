extends "res://tests/test_suite_base.gd"
## D-12 Phase A + C — the unified personal domain aggregate, and the per-hex
## classification write that keeps advancement from going inert.
##
## The two properties worth stating plainly, because both are exploits today:
##   * Splitting a holding into parcels must not change any RAW quantity. Under
##     the per-domain model it changes several in the ruler's favour — the
##     oversize band, tribute-out, and the non-contiguity penalty all soften.
##   * A domain that advances Wilderness -> Borderlands -> Civilized must stop
##     paying wilderness rates. Nothing wrote `hex_cells.civilization` after
##     world generation, so per-hex costs would have quoted the original
##     classification forever.

var _campaign_id: String = ""
var _map_id: String = ""


func run_all_tests() -> void:
	_campaign_id = CampaignRepository.create_campaign("Personal Domain Tests", "World")
	_map_id = _make_map("pd_main")

	test_worst_classification_is_the_harshest_present()
	test_unknown_character_returns_a_populated_zero()
	test_single_parcel_matches_its_own_row()
	test_two_parcels_union_families_and_income()
	test_terminal_parcels_are_excluded()
	test_stronghold_minimum_is_a_per_hex_sum()
	test_garrison_uses_each_hexs_own_rate()
	test_separated_parcels_incur_intervening_hexes()
	test_hexes_in_different_map_namespaces_are_never_joined()
	test_abstract_domain_falls_back_to_the_aggregate()
	test_classification_propagates_to_hexes()

	if not has_failures():
		print("PersonalDomain: all tests passed (%d checks)." % test_count())


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_map(tag: String) -> String:
	var map_id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, ?, 'regional_6mi')
	""", [map_id, _campaign_id, "Map %s" % tag])
	return map_id


func _make_ruler(tag: String) -> String:
	return CampaignRepository.create_character({
		"campaign_id": _campaign_id,
		"name": "Lord %s" % tag,
		"character_type": "npc",
		"alignment": "lawful",
	})


func _make_parcel(tag: String, owner_id: String, opts: Dictionary = {}) -> String:
	var domain_id := CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Parcel %s" % tag,
		"owner_character_id": owner_id,
		"territory_type": String(opts.get("territory_type", "civilized")),
	})
	CampaignRepository.db.query_with_bindings("""
		UPDATE domains SET peasant_families = ?, revenue_cp = ?, expenses_cp = ?,
			lifecycle_state = ? WHERE id = ?
	""", [
		int(opts.get("peasants", 100)), int(opts.get("revenue_cp", 0)),
		int(opts.get("expenses_cp", 0)),
		String(opts.get("lifecycle_state", "active")), domain_id,
	])
	return domain_id


## Give `domain_id` a hex at (q, r) on `map_id`, and make sure `hex_cells` has a
## matching row carrying `civilization` — the join D-12 depends on.
func _add_hex(domain_id: String, map_id: String, q: int, r: int,
		civilization: String, families: int = 0) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_cells (map_id, q, r, civilization)
		VALUES (?, ?, ?, ?)
	""", [map_id, q, r, civilization])
	CampaignRepository.add_domain_hex({
		"domain_id": domain_id, "map_id": map_id,
		"hex_q": q, "hex_r": r, "families": families,
	})


## A bare `hex_cells` row owned by nobody — an INTERVENING hex.
func _add_empty_cell(map_id: String, q: int, r: int, civilization: String) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_cells (map_id, q, r, civilization)
		VALUES (?, ?, ?, ?)
	""", [map_id, q, r, civilization])


func _civ_min_cp(civilization: String) -> int:
	return StrongholdRepository.per_hex_minimum_for(civilization)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_worst_classification_is_the_harshest_present() -> void:
	check(PersonalDomain.worst_classification({}) == "civilized",
		"an empty set never invents a penalty")
	check(PersonalDomain.worst_classification({"civilized": 9}) == "civilized",
		"all-civilized reads civilized")
	check(PersonalDomain.worst_classification({"civilized": 9, "borderlands": 1})
			== "borderlands",
		"one borderlands hex among nine civilized makes it borderlands")
	check(PersonalDomain.worst_classification(
			{"civilized": 9, "borderlands": 4, "wilderness": 1}) == "wilderness",
		"a single wilderness hex is the worst holding")


func test_unknown_character_returns_a_populated_zero() -> void:
	var pd: Dictionary = PersonalDomain.for_character("")
	check(not pd.is_empty(), "an empty id returns a populated dict, never {}")
	check(int(pd.get("families", -1)) == 0, "with zeroed quantities")
	check(int(pd.get("parcel_count", -1)) == 0, "and no parcels")
	var missing: Dictionary = PersonalDomain.for_character("no_such_character")
	check(int(missing.get("parcel_count", -1)) == 0,
		"an unknown character owns nothing")


func test_single_parcel_matches_its_own_row() -> void:
	var cid := _make_ruler("single")
	var did := _make_parcel("single", cid,
		{"peasants": 120, "revenue_cp": 500_000, "expenses_cp": 200_000})
	_add_hex(did, _map_id, 10, 10, "civilized", 120)

	var pd: Dictionary = PersonalDomain.for_character(cid)
	check(int(pd.get("parcel_count", 0)) == 1, "one parcel")
	check(int(pd.get("peasant_families", 0)) == 120, "families match the row")
	check(int(pd.get("revenue_cp", 0)) == 500_000, "revenue matches")
	check(int(pd.get("net_income_cp", 0)) == 300_000, "net income is revenue - expenses")
	check(bool(pd.get("is_materialized", false)), "a hex-bearing parcel is materialized")
	check(int(pd.get("owned_hex_count", 0)) == 1, "one owned hex")
	check(int(pd.get("effective_hex_count", 0)) == 1,
		"a single hex needs no intervening hexes")
	check(String(pd.get("worst_classification", "")) == "civilized",
		"its classification came from hex_cells, not from the domain row")


func test_two_parcels_union_families_and_income() -> void:
	# THE HEADLINE PROPERTY: the character is the domain. Two rows, one holding.
	var cid := _make_ruler("union")
	var a := _make_parcel("union_a", cid,
		{"peasants": 100, "revenue_cp": 300_000, "expenses_cp": 100_000})
	var b := _make_parcel("union_b", cid,
		{"peasants": 200, "revenue_cp": 700_000, "expenses_cp": 250_000})
	_add_hex(a, _map_id, 20, 20, "civilized", 100)
	_add_hex(b, _map_id, 21, 20, "civilized", 200)

	var pd: Dictionary = PersonalDomain.for_character(cid)
	check(int(pd.get("parcel_count", 0)) == 2, "both parcels contribute")
	check(int(pd.get("peasant_families", 0)) == 300, "families are summed (100 + 200)")
	check(int(pd.get("revenue_cp", 0)) == 1_000_000, "revenue is summed")
	check(int(pd.get("net_income_cp", 0)) == 650_000, "net income is summed")
	check(int(pd.get("owned_hex_count", 0)) == 2, "hexes are unioned")
	# Adjacent hexes: one connected component, so no non-contiguity penalty.
	check(int(pd.get("effective_hex_count", 0)) == 2,
		"adjacent parcels form one contiguous holding")
	check(int(pd.get("intervening_hex_count", 0)) == 0, "with nothing in between")


func test_terminal_parcels_are_excluded() -> void:
	# An abandoned holding is kept as an audit row and skipped by the monthly
	# loop. Counting its families would charge the ruler oversize and tribute for
	# land he no longer holds.
	var cid := _make_ruler("terminal")
	var live := _make_parcel("terminal_live", cid, {"peasants": 100})
	_make_parcel("terminal_gone", cid,
		{"peasants": 900, "lifecycle_state": "abandoned"})
	_make_parcel("terminal_salt", cid,
		{"peasants": 900, "lifecycle_state": "salted_to_ruin"})
	_add_hex(live, _map_id, 30, 30, "civilized", 100)

	var pd: Dictionary = PersonalDomain.for_character(cid)
	check(int(pd.get("parcel_count", 0)) == 1, "only the live parcel counts")
	check(int(pd.get("peasant_families", 0)) == 100,
		"the abandoned and salted parcels' 1,800 families are excluded")


func test_stronghold_minimum_is_a_per_hex_sum() -> void:
	# Under D-12 the minimum is the sum of each hex's OWN RAW minimum, not one
	# classification applied to a hex count. A civilized seat with a wilderness
	# frontier hex must pay the wilderness rate for that hex.
	var cid := _make_ruler("minsum")
	var did := _make_parcel("minsum", cid, {"territory_type": "civilized"})
	_add_hex(did, _map_id, 40, 40, "civilized")
	_add_hex(did, _map_id, 41, 40, "civilized")
	_add_hex(did, _map_id, 42, 40, "wilderness")

	var pd: Dictionary = PersonalDomain.for_character(cid)
	var expected: int = 2 * _civ_min_cp("civilized") + _civ_min_cp("wilderness")
	check(int(pd.get("stronghold_minimum_cp", 0)) == expected,
		"minimum is 2 civilized + 1 wilderness (got %d, want %d)"
			% [int(pd.get("stronghold_minimum_cp", -1)), expected])
	# The old model would have quoted 3 x civilized off `domains.territory_type`.
	check(int(pd.get("stronghold_minimum_cp", 0)) != 3 * _civ_min_cp("civilized"),
		"and is NOT the domain's own classification times the hex count")
	check(String(pd.get("worst_classification", "")) == "wilderness",
		"the worst holding drives the morale classification")
	var counts: Dictionary = pd.get("classification_counts", {})
	check(int(counts.get("civilized", 0)) == 2 and int(counts.get("wilderness", 0)) == 1,
		"the per-classification counts are reported")


func test_garrison_uses_each_hexs_own_rate() -> void:
	# RAW 2/3/4 gp per family by classification. Per-hex, so a frontier hex costs
	# 4 gp/family even under a civilized seat. Values are cp (§127).
	var cid := _make_ruler("garrison")
	var did := _make_parcel("garrison", cid, {"territory_type": "civilized"})
	_add_hex(did, _map_id, 50, 50, "civilized", 100)   # 100 x 2 gp = 20,000 cp
	_add_hex(did, _map_id, 51, 50, "wilderness", 50)   #  50 x 4 gp = 20,000 cp

	var pd: Dictionary = PersonalDomain.for_character(cid)
	var expected: int = 100 * DomainStocker.garrison_gp_per_family("civilized") * 100 \
		+ 50 * DomainStocker.garrison_gp_per_family("wilderness") * 100
	check(int(pd.get("garrison_minimum_cp", 0)) == expected,
		"garrison minimum sums each hex at its own rate (got %d, want %d)"
			% [int(pd.get("garrison_minimum_cp", -1)), expected])


func test_separated_parcels_incur_intervening_hexes() -> void:
	# RAW §noncontiguous_domains L95-98 has no standalone penalty — it works
	# THROUGH stronghold sufficiency: the stronghold must secure owned PLUS
	# intervening hexes. Two separate parcels are each internally contiguous, so
	# per-domain the penalty never fires; unioned, it does.
	var cid := _make_ruler("split")
	var a := _make_parcel("split_a", cid)
	var b := _make_parcel("split_b", cid)
	_add_hex(a, _map_id, 60, 60, "civilized")
	_add_hex(b, _map_id, 60, 63, "civilized")
	# The gap the strongholds must also secure — deliberately WILDERNESS, to
	# prove intervening hexes contribute their OWN classification's minimum.
	_add_empty_cell(_map_id, 60, 61, "wilderness")
	_add_empty_cell(_map_id, 60, 62, "wilderness")

	var pd: Dictionary = PersonalDomain.for_character(cid)
	check(int(pd.get("owned_hex_count", 0)) == 2, "two owned hexes")
	check(int(pd.get("intervening_hex_count", 0)) == 2,
		"two intervening hexes join them (got %d)"
			% int(pd.get("intervening_hex_count", -1)))
	check(int(pd.get("effective_hex_count", 0)) == 4,
		"effective count is owned + intervening")
	var expected: int = 2 * _civ_min_cp("civilized") + 2 * _civ_min_cp("wilderness")
	check(int(pd.get("stronghold_minimum_cp", 0)) == expected,
		"the intervening wilderness hexes raise the minimum at THEIR rate")
	check(String(pd.get("worst_classification", "")) == "wilderness",
		"an intervening wilderness hex counts toward the worst classification")


func test_hexes_in_different_map_namespaces_are_never_joined() -> void:
	# NOT a multi-map test — a campaign has exactly ONE rolling 6-mile map
	# (RegionZoomIn inserts one row; grow_frontier grows it in place). This pins
	# the contiguity walk's NAMESPACE GUARD: `add_domain_hex` writes '' as a
	# sentinel map_id for a domain with no location_map_id, and coordinates in
	# that namespace are undefined, so they must never be pathed against real map
	# coordinates. A second hex_maps row is the cleanest way to express "a
	# different coordinate namespace" in a test.
	var other_namespace := _make_map("pd_other")
	var cid := _make_ruler("crossmap")
	var a := _make_parcel("crossmap_a", cid)
	var b := _make_parcel("crossmap_b", cid)
	_add_hex(a, _map_id, 70, 70, "civilized")
	_add_hex(b, other_namespace, 70, 73, "civilized")

	var pd: Dictionary = PersonalDomain.for_character(cid)
	check(int(pd.get("owned_hex_count", 0)) == 2, "both hexes are owned")
	check(int(pd.get("intervening_hex_count", 0)) == 0,
		"no intervening hexes are invented across a map_id boundary")
	check(int(pd.get("effective_hex_count", 0)) == 2, "effective equals owned")


func test_abstract_domain_falls_back_to_the_aggregate() -> void:
	# THE TWO-TIER RULE. Only in-window domains have domain_hexes rows at all, so
	# an off-map domain must keep using the per-domain aggregate. A per-hex rule
	# that silently returned 0 for the whole off-camera world would be worse than
	# what it replaced.
	var cid := _make_ruler("abstract")
	_make_parcel("abstract", cid, {"territory_type": "borderlands", "peasants": 80})

	var pd: Dictionary = PersonalDomain.for_character(cid)
	check(not bool(pd.get("is_materialized", true)),
		"a domain with no hexes is not materialized")
	check(int(pd.get("owned_hex_count", 0)) == 0, "and owns no hexes")
	check(int(pd.get("stronghold_minimum_cp", 0))
			== StrongholdRepository.classification_minimum_cp("borderlands", 1),
		"the minimum falls back to the parcel's own territory_type")
	check(String(pd.get("worst_classification", "")) == "borderlands",
		"as does the classification")
	check(int(pd.get("garrison_minimum_cp", 0))
			== 80 * DomainStocker.garrison_gp_per_family("borderlands") * 100,
		"and the garrison rate")
	check(int(pd.get("effective_hex_count", 0)) == 1,
		"each abstract parcel counts as one hex, matching the existing maxi(1, n) floor")


func test_classification_propagates_to_hexes() -> void:
	# THE INERTNESS REGRESSION LOCK. Before D-12, ClassificationAdvancement wrote
	# only domains.territory_type and nothing ever updated hex_cells.civilization
	# after generation — so per-hex costs would quote the ORIGINAL classification
	# forever and advancement would appear to do nothing.
	var cid := _make_ruler("advance")
	var did := _make_parcel("advance", cid, {"territory_type": "wilderness"})
	_add_hex(did, _map_id, 80, 80, "wilderness", 60)
	_add_hex(did, _map_id, 81, 80, "wilderness", 60)

	var before: Dictionary = PersonalDomain.for_character(cid)
	check(int(before.get("stronghold_minimum_cp", 0)) == 2 * _civ_min_cp("wilderness"),
		"starts at the wilderness rate")

	var updated: int = ClassificationAdvancement.propagate_to_hexes(did, "borderlands")
	check(updated == 2, "both hexes were propagated (got %d)" % updated)

	var after: Dictionary = PersonalDomain.for_character(cid)
	check(int(after.get("stronghold_minimum_cp", 0)) == 2 * _civ_min_cp("borderlands"),
		"and the per-hex minimum actually moved to the borderlands rate")
	check(String(after.get("worst_classification", "")) == "borderlands",
		"the worst classification follows the advance")
	check(int(after.get("garrison_minimum_cp", 0))
			== 120 * DomainStocker.garrison_gp_per_family("borderlands") * 100,
		"as does the garrison rate")
	# An abstract domain has no hexes to propagate to, and says so honestly.
	var abstract_cid := _make_ruler("advance_abstract")
	var abstract_did := _make_parcel("advance_abstract", abstract_cid)
	check(ClassificationAdvancement.propagate_to_hexes(abstract_did, "civilized") == 0,
		"an abstract domain propagates to nothing and reports 0")
