extends "res://tests/test_suite_base.gd"

## Stage 6: Layer 5 naming + region-painting Phase 2 (NameAssembler +
## NameGenerator). Unit tests on the pure assembler (determinism, dedup, civ vs
## beastman realm shape, subtype-matched features) + a full-pipeline integration
## test on a small map asserting the §17 exit criteria: a generated world is
## fully named with zero LLM, the region caps hold (hydronym <= 25% of clusters,
## historical overrides <= hexes/100), multilingual alternates only on majors,
## and the whole thing is deterministic from the seed.

const MAP := "small"          # 15x12 = 180 hexes — fast full pipeline
const SHORT := "short"        # 80-tick history


func run_all_tests() -> void:
	NameBankLoader.clear_cache()
	# Unit
	test_compound()
	test_pick_unused_dedup()
	test_assembler_determinism()
	test_civ_realm_name()
	test_beastman_realm_name()
	test_feature_subtype_matched()
	# Integration
	var cid := _generate(424242)
	if not cid.is_empty():
		test_everything_is_named(cid)
		test_region_caps(cid)
		test_alternates_only_on_majors(cid)
		test_determinism(424242, cid)
	if not has_failures():
		print("SettingStage6Tests: all tests passed (%d checks)" % test_count())


# --- unit: NameAssembler ----------------------------------------------------

func test_compound() -> void:
	var w := NameAssembler.compound("ater", "silva")
	check(not w.is_empty(), "compound produced a name")
	check(w == w.substr(0, 1).to_upper() + w.substr(1), "compound is capitalized")
	check(not w.to_lower().contains("aaa") and not w.to_lower().contains("sss"),
		"compound collapses 3+ letter runs (%s)" % w)
	check(NameAssembler.compound("", "silva").is_empty(), "empty stem -> empty")


func test_pick_unused_dedup() -> void:
	var used := {}
	var pool := ["Alpha", "Beta", "Gamma"]
	var rng := WorldGenRng.stream(1, "t", 0, "x")
	var got := {}
	for i in range(3):
		var n := NameAssembler.pick_unused(pool, rng, used, "c")
		check(not got.has(n.to_lower()), "pick_unused never repeats (%s)" % n)
		got[n.to_lower()] = true
	# Pool exhausted — the 4th draw must be qualified, still unique.
	var extra := NameAssembler.pick_unused(pool, rng, used, "c")
	check(not got.has(extra.to_lower()), "exhausted pool qualifies a unique name (%s)" % extra)


func test_assembler_determinism() -> void:
	var bank := NameBankLoader.bank_for("quirium")
	var a := NameAssembler.settlement_name(bank,
		WorldGenRng.stream(7, "settlement_name", 0, "stl_0005"), {}, "quirium", false)
	var b := NameAssembler.settlement_name(bank,
		WorldGenRng.stream(7, "settlement_name", 0, "stl_0005"), {}, "quirium", false)
	check(a == b and not a.is_empty(), "same seed+entity -> same name (%s/%s)" % [a, b])


func test_civ_realm_name() -> void:
	var bank := NameBankLoader.bank_for("quirium")
	var name := NameAssembler.realm_name(bank, "kingdom", "Agrippa", "Agrippola",
		"Valerius", WorldGenRng.stream(3, "polity_name", 0, "pol_0001"), {}, "quirium")
	check(not name.is_empty(), "civ realm name non-empty")
	check(name.contains("Kingdom"), "kingdom realm uses the English domain title 'Kingdom' (%s)" % name)


func test_beastman_realm_name() -> void:
	var bank := NameBankLoader.bank_for("orc")
	var dyn := NameAssembler.dynasty_name(bank,
		WorldGenRng.stream(3, "dynasty_name", 0, "pol_0009"), {}, "orc")
	var name := NameAssembler.realm_name(bank, "kingdom", "", "", dyn,
		WorldGenRng.stream(3, "polity_name", 0, "pol_0009"), {}, "orc")
	check(not name.is_empty(), "beastman realm name non-empty")
	# Beastman ladder has no domain title -> the realm is the horde, not "X of Y".
	check(NameBankLoader.domain_title(bank, "kingdom").is_empty(),
		"orc has no domain title (scope-only)")


func test_feature_subtype_matched() -> void:
	var bank := NameBankLoader.bank_for("quirium")
	var used := {}
	var forest := NameAssembler.feature_name(bank, "forest",
		WorldGenRng.stream(5, "region_name", 0, "reg_0001"), used, "quirium")
	check(not forest.is_empty(), "forest feature name non-empty (%s)" % forest)
	# 'silva' is the classical (quirium) forest-word; a subtype-matched compound contains it.
	check(forest.to_lower().contains("silv"),
		"forest feature is built on the forest-word 'silva' (%s)" % forest)


# --- integration: full pipeline ---------------------------------------------

func _generate(seed_value: int) -> String:
	var cid := CampaignRepository.create_campaign("Stage6 %d" % seed_value, "w")
	var params := SettingParameters.new()
	params.map_size = MAP
	params.history_length = SHORT
	if not SettingGenerator.new().generate(cid, seed_value, params):
		check(false, "generate() failed (seed %d)" % seed_value)
		return ""
	return cid


func test_everything_is_named(cid: String) -> void:
	var polities := SettingRepository.list_polities(cid)
	check(polities.size() > 0, "world has polities")
	for p in polities:
		check(not str(p.get("name", "")).strip_edges().is_empty(),
			"polity %s is named" % str(p.get("id", "?")))
	for s in SettingRepository.list_settlements(cid):
		check(not str(s.get("name", "")).strip_edges().is_empty(),
			"settlement %s is named" % str(s.get("id", "?")))
	var regions := SettingRepository.list_regions(cid)
	check(regions.size() > 0, "world has regions")
	for r in regions:
		check(not str(r.get("name_primary", "")).strip_edges().is_empty(),
			"region %s (%s) is named" % [str(r.get("id", "?")), str(r.get("layer", ""))])
		check(not str(r.get("name_origin", "")).strip_edges().is_empty(),
			"region %s has a name_origin" % str(r.get("id", "?")))


func test_region_caps(cid: String) -> void:
	var regions := SettingRepository.list_regions(cid)
	var clusters := 0
	var hydronym_derived := 0
	var hist_overrides := 0
	for r in regions:
		var layer := str(r.get("layer", ""))
		var origin := str(r.get("name_origin", ""))
		if layer == "terrain_cluster":
			clusters += 1
			if origin == "hydronym_derived":
				hydronym_derived += 1
		# Historical OVERRIDES (the capped kind) exclude fallen reaches, which
		# are their own exempt layer (§5.4).
		if origin == "historical" and layer != "historical_cultural":
			hist_overrides += 1
	if clusters > 0:
		check(float(hydronym_derived) <= 0.25 * float(clusters) + 0.5,
			"hydronym-derived %d <= 25%% of %d clusters" % [hydronym_derived, clusters])
	# §5.4 "map-wide cap hexes/100": hexes = TOTAL campaign-map cells (every
	# (q,r), water included) = list_hexes size, NOT a region proxy.
	var total_map_hexes := SettingRepository.list_hexes(cid).size()
	var hist_cap = max(1, int(float(total_map_hexes) / 100.0))
	check(hist_overrides <= hist_cap,
		"historical overrides %d <= cap %d (map %d hexes)" % [hist_overrides, hist_cap, total_map_hexes])


func test_alternates_only_on_majors(cid: String) -> void:
	for r in SettingRepository.list_regions(cid):
		var alts = JSON.parse_string(str(r.get("name_alternates", "[]")))
		if typeof(alts) == TYPE_ARRAY and alts.size() > 0:
			check(float(r.get("significance", 0.0)) >= 0.65,
				"region %s with alternates is a major (sig %.2f >= 0.65)"
				% [str(r.get("id", "?")), float(r.get("significance", 0.0))])


func test_determinism(seed_value: int, first_cid: String) -> void:
	var second := _generate(seed_value)
	if second.is_empty():
		return
	check(_name_map(first_cid, "polities") == _name_map(second, "polities"),
		"same seed -> identical realm names")
	check(_name_map(first_cid, "regions") == _name_map(second, "regions"),
		"same seed -> identical region names")
	check(_name_map(first_cid, "settlements") == _name_map(second, "settlements"),
		"same seed -> identical settlement names")


# --- helpers ----------------------------------------------------------------

func _name_map(cid: String, kind: String) -> Dictionary:
	var out := {}
	match kind:
		"polities":
			for p in SettingRepository.list_polities(cid):
				out[str(p["id"])] = str(p.get("name", ""))
		"settlements":
			for s in SettingRepository.list_settlements(cid):
				out[str(s["id"])] = str(s.get("name", ""))
		"regions":
			for r in SettingRepository.list_regions(cid):
				out[str(r["id"])] = str(r.get("name_primary", ""))
	return out
