extends "res://tests/test_suite_base.gd"

## §4c — Hybrid emergence (border merge, substrate only). Covers the load-time
## parent-pair -> hybrid lookup (CultureCatalogLoader) and _phase_hybridization
## growing the static HYB(A,B) into a base-vs-base substrate seam: SAME-CLASS only
## (Peer / Confederated), gated below a seam threshold, per-pair locked, and
## deterministic. Uses real catalog ids so the lookup resolves; the sim state is
## hand-built (mirrors test_setting_overseas). No polity flips here (that is §4d).


func run_all_tests() -> void:
	test_hybrid_lookup_unordered()
	test_hybrid_lookup_confed_and_conquest()
	test_hybrid_lookup_misses()
	test_top_two_bases_picks_bases_over_hybrid()
	test_shared_language_family_detection()
	test_merge_grows_hybrid_and_shrinks_parents()
	test_conquest_pair_skipped_at_border()
	test_below_seam_threshold_no_merge()
	test_displace_decision_no_merge()
	test_decision_locked_and_deterministic()
	# §4d — conquest merge (gated) + finalize relabel + persistence
	test_conquest_merge_gating()
	test_conquest_merge_symmetric()
	test_dominant_populated_culture()
	test_finalize_relabels_hybrid_realm()
	test_finalize_keeps_base_realm()
	# §4e integration — the whole emergence chain on a full generated map
	test_hybrid_emerges_on_generated_map()
	print("SettingHybridizationTests: all tests passed (%d checks)" % test_count())


# --- helpers -----------------------------------------------------------------

func _base(cid: String, coc: String, fam: String) -> Dictionary:
	return {
		"culture_id": cid, "tier": "human", "race": "human",
		"culture_class": "base", "civ_or_clan": coc, "language_family": fam,
		"rigidity": 0.5,
	}


func _hybrid_inst(cid: String, coc: String) -> Dictionary:
	return {
		"culture_id": cid, "tier": "human", "race": "human",
		"culture_class": "hybrid", "civ_or_clan": coc, "language_family": "",
		"rigidity": 0.5,
	}


func _sim(instances: Dictionary) -> HistorySimulator:
	var sim := HistorySimulator.new()
	sim._c = SimConstants.new()
	sim._campaign_seed = 1
	sim._culture_instances = instances
	sim._culture_w = {}
	sim._land_keys = []
	sim._merge_decisions = {}
	return sim


## A peaceful civ x civ seam: ellinike x vallica -> ausonians (a real Peer pair).
func _peer_sim() -> HistorySimulator:
	return _sim({
		"ellinike": _base("ellinike", "civ", "hellenic"),
		"vallica": _base("vallica", "civ", "classical"),
		"ausonians": _hybrid_inst("ausonians", "civ"),
	})


# --- lookup (CultureCatalogLoader) -------------------------------------------

func test_hybrid_lookup_unordered() -> void:
	var h1 := CultureCatalogLoader.hybrid_for_parents("ellinike", "vallica")
	var h2 := CultureCatalogLoader.hybrid_for_parents("vallica", "ellinike")
	check(h1 == "ausonians", "ellinike x vallica -> ausonians, got '%s'" % h1)
	check(h1 == h2, "the parent-pair lookup is order-independent")


func test_hybrid_lookup_confed_and_conquest() -> void:
	check(CultureCatalogLoader.hybrid_for_parents("thiodons", "albawyn") == "brythald",
		"thiodons x albawyn -> brythald (Confederated)")
	# The LOOKUP resolves Conquest pairs too; the same-class SCOPE gate lives in the
	# phase, not the lookup.
	check(CultureCatalogLoader.hybrid_for_parents("thiodons", "aryastan") == "arjungs",
		"thiodons x aryastan -> arjungs (Conquest pair still resolves in the lookup)")


func test_hybrid_lookup_misses() -> void:
	check(CultureCatalogLoader.hybrid_for_parents("vallica", "vallica") == "",
		"a culture paired with itself has no hybrid")
	check(CultureCatalogLoader.hybrid_for_parents("vallica", "not_a_culture") == "",
		"an unknown parent yields no hybrid")


# --- phase helpers -----------------------------------------------------------

func test_top_two_bases_picks_bases_over_hybrid() -> void:
	var sim := _peer_sim()
	var top := sim._top_two_bases({"ellinike": 0.5, "vallica": 0.3, "ausonians": 0.2})
	check(top == ["ellinike", "vallica"],
		"top_two_bases returns the two BASES dominant-first, skipping the hybrid, got %s" % str(top))
	var one := sim._top_two_bases({"ellinike": 0.8, "ausonians": 0.2})
	check(one.is_empty(), "a hex with only one base present is not a seam")


func test_shared_language_family_detection() -> void:
	var sim := _sim({
		"a": _base("a", "civ", "classical"),
		"b": _base("b", "civ", "classical, east_asian"),
		"c": _base("c", "civ", "germanic"),
	})
	check(sim._shares_language_family("a", "b"), "cultures sharing a language family are detected")
	check(not sim._shares_language_family("a", "c"), "cultures with no shared family are not")


# --- _phase_hybridization mechanic -------------------------------------------

func test_merge_grows_hybrid_and_shrinks_parents() -> void:
	var sim := _peer_sim()
	var hex := Vector2i(0, 0)
	sim._culture_w = {hex: {"ellinike": 0.5, "vallica": 0.5}}
	sim._land_keys = [hex]
	sim._merge_decisions = {"ellinike|vallica": "merge"}   # force the locked outcome
	sim._phase_hybridization(0)
	var w: Dictionary = sim._culture_w[hex]
	check(float(w.get("ausonians", 0.0)) > 0.0,
		"a locked-merge seam grows the hybrid weight, got %s" % str(w))
	check(float(w.get("ellinike", 0.0)) < 0.5 and float(w.get("vallica", 0.0)) < 0.5,
		"the merge shrinks BOTH parent weights")
	var total := 0.0
	for k in w:
		total += float(w[k])
	check(is_equal_approx(total, 1.0), "the seam weights still sum to 1 after the merge, got %f" % total)


func test_conquest_pair_skipped_at_border() -> void:
	# thiodons (clan) x vallica (civ) = a Conquest pair (wallans). Even with the
	# decision forced to merge, the peaceful-border phase skips it (4d territory).
	var sim := _sim({
		"thiodons": _base("thiodons", "clan", "germanic"),
		"vallica": _base("vallica", "civ", "classical"),
		"wallans": _hybrid_inst("wallans", "civ"),
	})
	var hex := Vector2i(0, 0)
	sim._culture_w = {hex: {"thiodons": 0.5, "vallica": 0.5}}
	sim._land_keys = [hex]
	sim._merge_decisions = {"thiodons|vallica": "merge"}
	sim._phase_hybridization(0)
	check(not sim._culture_w[hex].has("wallans"),
		"a clan x civ (Conquest) seam does NOT merge at a peaceful border")


func test_below_seam_threshold_no_merge() -> void:
	var sim := _peer_sim()
	var hex := Vector2i(0, 0)
	# vallica at 0.1 is below hybrid_seam_threshold (0.2): not a real seam.
	sim._culture_w = {hex: {"ellinike": 0.9, "vallica": 0.1}}
	sim._land_keys = [hex]
	sim._merge_decisions = {"ellinike|vallica": "merge"}
	sim._phase_hybridization(0)
	check(not sim._culture_w[hex].has("ausonians"),
		"a seam below hybrid_seam_threshold does not merge")


func test_displace_decision_no_merge() -> void:
	var sim := _peer_sim()
	var hex := Vector2i(0, 0)
	sim._culture_w = {hex: {"ellinike": 0.5, "vallica": 0.5}}
	sim._land_keys = [hex]
	sim._merge_decisions = {"ellinike|vallica": "displace"}
	sim._phase_hybridization(0)
	check(not sim._culture_w[hex].has("ausonians"),
		"a displace-locked pair never grows the hybrid")


func test_decision_locked_and_deterministic() -> void:
	var sim := _peer_sim()
	var d1 := sim._decide_merge("ellinike", "vallica", "ellinike|vallica")
	var d2 := sim._decide_merge("ellinike", "vallica", "ellinike|vallica")
	check(d1 == d2, "the per-pair merge decision is deterministic (same seed+pair)")
	check(d1 == "merge" or d1 == "displace", "the decision is merge or displace")
	# The phase records (locks) a pair's decision the first time its seam is seen.
	sim._culture_w = {Vector2i(0, 0): {"ellinike": 0.5, "vallica": 0.5}}
	sim._land_keys = [Vector2i(0, 0)]
	sim._phase_hybridization(0)
	check(sim._merge_decisions.has("ellinike|vallica"),
		"the phase locks the pair decision on first contact")


# --- §4d conquest merge (gated) ----------------------------------------------

func test_conquest_merge_gating() -> void:
	# thiodons (clan) x vallica (civ) -> wallans. §6.4: merges ONLY clan-over-civ.
	var sim := _sim({
		"thiodons": _base("thiodons", "clan", "germanic"),
		"vallica": _base("vallica", "civ", "classical"),
		"wallans": _hybrid_inst("wallans", "civ"),
	})
	sim._merge_decisions = {"thiodons|vallica": "merge"}   # isolate the gate from the roll
	check(sim._conquest_merge_target("thiodons", "vallica") == "wallans",
		"clan-over-civ conquest converts toward the Conquest hybrid")
	check(sim._conquest_merge_target("vallica", "thiodons") == "",
		"civ-over-clan conquest is gated out (§6.4) — assimilates toward the owner")


func test_conquest_merge_symmetric() -> void:
	# ellinike x vallica = same-class (both civ) -> symmetric, no direction gate.
	var sim := _peer_sim()
	sim._merge_decisions = {"ellinike|vallica": "merge"}
	check(sim._conquest_merge_target("ellinike", "vallica") == "ausonians",
		"same-class conquest merges to the hybrid")
	check(sim._conquest_merge_target("vallica", "ellinike") == "ausonians",
		"same-class conquest is symmetric (either conqueror)")
	# a displace-locked pair never converts.
	sim._merge_decisions = {"ellinike|vallica": "displace"}
	check(sim._conquest_merge_target("ellinike", "vallica") == "",
		"a displace-locked pair assimilates toward the owner, not a hybrid")


# --- §4d finalize relabel + persistence --------------------------------------

func test_dominant_populated_culture() -> void:
	var sim := _peer_sim()
	sim._grid = {
		Vector2i(0, 0): {"population_band": 100},
		Vector2i(1, 0): {"population_band": 100},
	}
	sim._culture_w = {
		Vector2i(0, 0): {"ausonians": 0.8, "ellinike": 0.2},
		Vector2i(1, 0): {"ausonians": 0.6, "vallica": 0.4},
	}
	var dom := sim._dominant_populated_culture({"hexes": [Vector2i(0, 0), Vector2i(1, 0)]})
	check(str(dom["cid"]) == "ausonians", "the mass-weighted dominant culture is the hybrid")
	check(is_equal_approx(float(dom["share"]), 0.7), "...at its mass share, got %f" % float(dom["share"]))


func _relabel_sim(hybrid_weight: float) -> HistorySimulator:
	var sim := _peer_sim()
	sim._n_ticks = 100
	sim._events = []
	sim._grid = {Vector2i(0, 0): {"population_band": 100}}
	sim._culture_w = {Vector2i(0, 0): {"ausonians": hybrid_weight, "ellinike": 1.0 - hybrid_weight}}
	sim._polities = {"pol_1": {"id": "pol_1", "culture_id": "ellinike", "alive": true, "hexes": [Vector2i(0, 0)]}}
	return sim


func test_finalize_relabels_hybrid_realm() -> void:
	var sim := _relabel_sim(0.9)   # substrate dominantly the hybrid
	sim._finalize_hybrid_identities()
	var pol: Dictionary = sim._polities["pol_1"]
	check(str(pol["culture_id"]) == "ausonians",
		"a hybrid-dominant realm is relabeled to the hybrid at finalize")
	check(pol["culture_synthesis_parents"] == ["ellinike", "vallica"],
		"...and records its base parents, got %s" % str(pol.get("culture_synthesis_parents")))


func test_finalize_keeps_base_realm() -> void:
	var sim := _relabel_sim(0.1)   # substrate still dominantly the base
	sim._finalize_hybrid_identities()
	var pol: Dictionary = sim._polities["pol_1"]
	check(str(pol["culture_id"]) == "ellinike",
		"a base-dominant realm keeps its base culture")
	check(pol["culture_synthesis_parents"] == [],
		"...and carries an empty synthesis-parents list")


# --- §4e integration: hybrids emerge on a full generated map -----------------

func test_hybrid_emerges_on_generated_map() -> void:
	# Full pipeline at a producing seed (large, seed 1000) — the whole emergence
	# chain end to end: hybrid SUBSTRATE at conquest/contest zones, plus at least
	# one realm that ADOPTED a hybrid identity (go-native, recorded at finalize).
	# PROVISIONAL: keyed to the calibrated hybrid_merge_base_p=0.5; if merge
	# prevalence is retuned, re-pick a producing seed via tools/calib_sweep.tscn.
	var cid := CampaignRepository.create_campaign("HybEmergenceTest", "w")
	var params := SettingParameters.new()
	params.map_size = "large"
	check(SettingGenerator.new().generate(cid, 1000, params),
		"large seed-1000 generation succeeds")

	var hyb_ids := {}
	var cat := CultureCatalogLoader.load_all()
	for k in cat:
		if CultureCatalogLoader.culture_class(cat[k]) == "hybrid":
			hyb_ids[str(k)] = true

	var substrate := 0
	for h in SettingRepository.list_hexes(cid):
		if str(h.water) != "":
			continue
		var cw = JSON.parse_string(str(h.culture_weights))
		if typeof(cw) != TYPE_DICTIONARY:
			continue
		var best := ""
		var bw := -1.0
		for c in cw:
			if float(cw[c]) > bw:
				bw = float(cw[c])
				best = str(c)
		if hyb_ids.has(best):
			substrate += 1
	check(substrate > 0,
		"hybrid cultures emerge in the substrate at contact zones (got %d hybrid-dominant hexes)" % substrate)

	var hyb_realms := 0
	for p in SettingRepository.list_polities(cid):
		if str(p.get("culture_synthesis_parents", "[]")) != "[]":
			hyb_realms += 1
	check(hyb_realms >= 1,
		"at least one realm adopts a recorded hybrid identity (got %d)" % hyb_realms)
