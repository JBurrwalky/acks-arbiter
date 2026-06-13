extends "res://tests/test_suite_base.gd"

## Stage 3 of the setting-generation pipeline: Layer 3 culture seeding
## (gdd-setting-generation.md §6; gdd-culture-catalog.md §6). Validates the
## TICK-0 SEED STATE the history sim runs forward — every homeland satisfies
## its culture's seed biomes, alignments are in-set, demihuman caps hold,
## beastmen are Chaotic clanholds on wilderness, and the whole pass is
## deterministic. (When Stage 4 lands, setting_polities becomes the present-day
## state; these seed-state assertions move to a seed-only checkpoint.)

var _cid: String = ""
var _polities: Array = []
var _hexes_by_qr: Dictionary = {}
var _catalog: Dictionary = {}


func run_all_tests() -> void:
	_generate("medium", 42)
	test_seed_polities_exist()
	test_homelands_satisfy_seed_biomes()
	test_alignments_in_allowed_set()
	test_demihuman_caps()
	test_human_seed_cap_respected()
	test_homeland_substrate_seeded()
	test_beastmen_are_chaotic_clanholds()
	test_phonemic_adjacency_best_effort()
	test_culture_instances_jittered_within_bounds()
	test_beastman_density_zero_yields_none()
	test_determinism_same_seed()
	print("SettingStage3Tests: all tests passed (%d checks)" % test_count())


func _generate(map_size: String, seed_value: int) -> void:
	CultureCatalogLoader.clear_cache()
	BeastmanDistributionLoader.clear_cache()
	_catalog = CultureCatalogLoader.load_all()
	_cid = CampaignRepository.create_campaign("Stage3 %s %d" % [map_size, seed_value], "w")
	var params := SettingParameters.new()
	params.map_size = map_size
	check(SettingGenerator.new().generate(_cid, seed_value, params), "generate() failed")
	_polities = SettingRepository.list_polities(_cid)
	_hexes_by_qr = {}
	for hex in SettingRepository.list_hexes(_cid):
		_hexes_by_qr[Vector2i(int(hex.q), int(hex.r))] = hex


func _tier_of(culture_id: String) -> String:
	if not _catalog.has(culture_id):
		return "?"
	return CultureCatalogLoader.tier(_catalog[culture_id])


func _non_beastman_polities() -> Array:
	var out: Array = []
	for p in _polities:
		if _tier_of(str(p.culture_id)) != "beastman":
			out.append(p)
	return out


func _beastman_polities() -> Array:
	var out: Array = []
	for p in _polities:
		if _tier_of(str(p.culture_id)) == "beastman":
			out.append(p)
	return out


# --- Exit criteria ----------------------------------------------------------

func test_seed_polities_exist() -> void:
	check(_polities.size() > 0, "no seed polities placed")
	check(_non_beastman_polities().size() > 0, "no human/demihuman homelands placed")


func test_homelands_satisfy_seed_biomes() -> void:
	# THE core exit criterion: every culture's homeland sits on a hex matching
	# its seed biomes (coastal flag respected).
	var coastal := _coastal_set()
	for p in _non_beastman_polities():
		var cid := str(p.culture_id)
		check(_catalog.has(cid), "polity references unknown culture %s" % cid)
		if not _catalog.has(cid):
			continue
		var key := Vector2i(int(p.capital_q), int(p.capital_r))
		var hex: Dictionary = _hexes_by_qr.get(key, {})
		check(not hex.is_empty(), "homeland hex %s missing for %s" % [key, cid])
		if hex.is_empty():
			continue
		check(str(hex.water) == "", "homeland %s on a water hex" % cid)
		check(CultureSeeder._hex_matches_culture(hex, _catalog[cid], coastal.has(key)),
			"homeland for %s at %s does not satisfy its seed biomes" % [cid, key])


func test_alignments_in_allowed_set() -> void:
	for p in _non_beastman_polities():
		var cid := str(p.culture_id)
		if not _catalog.has(cid):
			continue
		var allowed_lower: Array = []
		for a in CultureCatalogLoader.alignment_allowed(_catalog[cid]):
			allowed_lower.append(str(a).to_lower())
		check(str(p.alignment) in allowed_lower,
			"polity %s alignment '%s' not in allowed %s" % [cid, p.alignment, allowed_lower])


func test_demihuman_caps() -> void:
	var elf := 0
	var dwarf := 0
	for p in _non_beastman_polities():
		match CultureCatalogLoader.race(_catalog.get(str(p.culture_id), {})):
			"elf":
				elf += 1
			"dwarf":
				dwarf += 1
	check(elf <= 3, "more than 3 elf seed points: %d" % elf)
	check(dwarf <= 3, "more than 3 dwarf seed points: %d" % dwarf)


func test_human_seed_cap_respected() -> void:
	# Medium map caps humans at 7 (gdd-culture-catalog.md §6.1).
	var humans := 0
	for p in _non_beastman_polities():
		if CultureCatalogLoader.tier(_catalog.get(str(p.culture_id), {})) == "human":
			humans += 1
	check(humans <= 7, "medium map exceeded human seed cap of 7: %d" % humans)
	check(humans >= 1, "no human cultures seeded on a medium map")


func test_homeland_substrate_seeded() -> void:
	for p in _non_beastman_polities():
		var key := Vector2i(int(p.capital_q), int(p.capital_r))
		var hex: Dictionary = _hexes_by_qr.get(key, {})
		if hex.is_empty():
			continue
		check(str(hex.owner_polity_id) == str(p.id),
			"homeland hex owner_polity_id mismatch for %s" % p.id)
		check(int(hex.population_band) == 500,
			"homeland %s population_band should be 500, got %s" % [p.id, hex.population_band])
		var weights = JSON.parse_string(str(hex.culture_weights))
		check(weights is Dictionary and weights.has(str(p.culture_id)),
			"homeland culture_weights missing its culture for %s" % p.id)
		var total := 0.0
		for k in weights:
			total += float(weights[k])
		check(abs(total - 1.0) < 0.001, "culture_weights do not sum to 1.0 for %s" % p.id)
		var aw = JSON.parse_string(str(hex.alignment_weights))
		check(aw is Dictionary and aw.has(str(p.alignment)),
			"homeland alignment_weights missing '%s' for %s" % [p.alignment, p.id])


func test_beastmen_are_chaotic_clanholds() -> void:
	var beastmen := _beastman_polities()
	for p in beastmen:
		check(str(p.alignment) == "chaotic", "beastman polity %s not chaotic" % p.id)
		check(str(p.civ_or_clan_state) == "clan", "beastman polity %s not clan" % p.id)
		var key := Vector2i(int(p.capital_q), int(p.capital_r))
		var hex: Dictionary = _hexes_by_qr.get(key, {})
		check(not hex.is_empty() and str(hex.water) == "",
			"beastman polity %s not on a wilderness land hex" % p.id)
	# A default-density medium map should produce at least some beastmen.
	check(beastmen.size() > 0, "no baseline beastman clanholds placed at default density")


func test_phonemic_adjacency_best_effort() -> void:
	# §6.4: no two same-palette homelands adjacent (the seeder relaxes this
	# only if it leaves no legal hex; on a Medium map with few seeds, violations
	# should be rare — assert none for the non-beastman homelands).
	var offsets := [
		Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
	]
	var palette_at := {}
	for p in _non_beastman_polities():
		var pal := CultureCatalogLoader.phonemic_palette(_catalog.get(str(p.culture_id), {}))
		palette_at[Vector2i(int(p.capital_q), int(p.capital_r))] = pal
	var violations := 0
	for key in palette_at:
		var pal: String = palette_at[key]
		if pal == "":
			continue
		for off in offsets:
			var n: Vector2i = key + off
			if palette_at.has(n) and str(palette_at[n]) == pal:
				violations += 1
	check(violations == 0,
		"%d same-palette adjacency violations among homelands" % (violations / 2))


func test_culture_instances_jittered_within_bounds() -> void:
	# Re-run via the in-memory ctx path to inspect culture_instances directly.
	var ctx := _build_ctx_through_seeding("medium", 42)
	var instances: Dictionary = ctx.get("culture_instances", {})
	check(instances.size() > 0, "no culture instances produced")
	for cid in instances:
		var inst: Dictionary = instances[cid]
		var canon := CultureCatalogLoader.mechanical(_catalog[cid])
		var canon_aggr := float(canon.get("expansion", {}).get("aggression", 0.5))
		var inst_aggr := float(inst["aggression"])
		check(inst_aggr >= 0.0 and inst_aggr <= 1.0, "jittered aggression out of 0-1 for %s" % cid)
		check(abs(inst_aggr - canon_aggr) <= 0.08 + 0.0001,
			"aggression jitter exceeds ±0.08 for %s (%f vs %f)" % [cid, inst_aggr, canon_aggr])
		# Sphere weights renormalize to 1.0.
		if not inst["sphere_weights"].is_empty():
			var total := 0.0
			for k in inst["sphere_weights"]:
				total += float(inst["sphere_weights"][k])
			check(abs(total - 1.0) < 0.001, "jittered sphere_weights not normalized for %s" % cid)


func test_beastman_density_zero_yields_none() -> void:
	var cid := CampaignRepository.create_campaign("Stage3 NoBeast", "w")
	var params := SettingParameters.new()
	params.wilderness_beastman_density = 0.0
	check(SettingGenerator.new().generate(cid, 42, params), "generate() failed")
	var beastmen := 0
	for p in SettingRepository.list_polities(cid):
		if _tier_of(str(p.culture_id)) == "beastman":
			beastmen += 1
	check(beastmen == 0, "density 0 should place no beastmen, got %d" % beastmen)


func test_determinism_same_seed() -> void:
	var cid2 := CampaignRepository.create_campaign("Stage3 Det B", "w")
	var params := SettingParameters.new()
	check(SettingGenerator.new().generate(cid2, 42, params), "second generate() failed")
	var subs_a := SettingDatasetHasher.compute_sub_hashes(_cid)
	var subs_b := SettingDatasetHasher.compute_sub_hashes(cid2)
	check(subs_a["setting_polities"] == subs_b["setting_polities"],
		"polity seeding not deterministic for the same seed")
	check(subs_a["setting_hexes"] == subs_b["setting_hexes"],
		"hex substrate seeding not deterministic for the same seed")


# --- Helpers ----------------------------------------------------------------

func _coastal_set() -> Dictionary:
	var offsets := [
		Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
	]
	var coastal := {}
	for key in _hexes_by_qr:
		var hex: Dictionary = _hexes_by_qr[key]
		if str(hex.water) != "":
			continue
		for off in offsets:
			var n: Vector2i = key + off
			if _hexes_by_qr.has(n) and str(_hexes_by_qr[n].water) == "ocean":
				coastal[key] = true
				break
	return coastal


## Run Layers 1-3 against an in-memory ctx (no DB) to inspect the seed state's
## transient products (culture_instances) the canonical tables don't persist.
func _build_ctx_through_seeding(map_size: String, seed_value: int) -> Dictionary:
	var params := SettingParameters.new()
	params.map_size = map_size
	var ctx := {
		"campaign_id": "_inmem_",
		"campaign_seed": seed_value,
		"params": params,
	}
	HeightmapGenerator.run(ctx)
	ClimateGenerator.run(ctx)
	RegionPainter.run_phase1(ctx)
	CultureSeeder.run(ctx)
	return ctx
