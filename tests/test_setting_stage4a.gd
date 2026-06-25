extends "res://tests/test_suite_base.gd"

## Stage 4a — history simulation: substrate (diffusion + assimilation) and
## demography (logistic growth + classification advancement + urban emergence),
## §6 / §6.3. Unit tests pin the math on a hand-built state; integration tests
## run the full pipeline and validate the persisted present-day output +
## determinism. (Expansion/war/collapse are stubs until 4b–4f, so the sim only
## grows and spreads from the seed homelands.)

var _cid: String = ""
var _hexes_by_qr: Dictionary = {}
var _polities: Array = []


func run_all_tests() -> void:
	# Unit tests (hand-built state, no DB).
	test_logistic_growth_increment()
	test_growth_approaches_cap()
	test_classification_advances_when_full()
	test_diffusion_spreads_culture_to_neighbors()
	test_diffusion_conserves_then_normalizes()
	test_assimilation_is_noop_for_pure_homeland()
	test_assimilation_converts_foreign_hex()
	test_replay_frames_emitted()
	# Integration (full pipeline).
	_generate_medium(42)
	test_present_day_polities_persisted()
	test_population_grew_from_seed()
	test_some_classification_advanced()
	test_settlements_emerged()
	test_inhabited_substrate_sums_to_one()
	test_replay_frames_persisted()
	test_full_pipeline_determinism()
	test_large_map_sim_performance()
	print("SettingStage4aTests: all tests passed (%d checks)" % test_count())


# --- Unit tests --------------------------------------------------------------

## Minimal ctx: a width×1 land strip, one polity at `capital` with `pop`.
func _make_ctx(width: int, capital: Vector2i, pop: int, culture_id: String,
		alignment: String, seed_value: int = 1) -> Dictionary:
	var grid := {}
	for q in range(width):
		var key := Vector2i(q, 0)
		var owned := (key == capital)
		grid[key] = {
			"elevation_raw": 0.4, "elevation": "flat", "water": "",
			"temperature": 15.0, "precipitation": 0.5, "effective_latitude": 45.0,
			"koppen": "Cfb", "biome": "clear", "biome_subtype": "",
			"original_biome": "",
			"culture_weights": JSON.stringify({culture_id: 1.0}) if owned else "{}",
			"alignment_weights": JSON.stringify({alignment: 1.0}) if owned else "{}",
			"population_band": pop if owned else 0,
			"territory_class": "wilderness",
			"owner_polity_id": "pol_0001" if owned else "",
			"land_value": 6,
		}
	var params := SettingParameters.new()
	return {
		"campaign_id": "_inmem_", "campaign_seed": seed_value, "params": params,
		"hex_grid": grid, "width": width, "height": 1, "river_edges": [],
		"culture_instances": {
			culture_id: {"base_subjugation_vs_genocide": 0.5, "culture_id": culture_id},
		},
		"seed_polities": [_seed_polity("pol_0001", culture_id, alignment, capital)],
	}


## Unit tests exercise substrate/demography on a single hand-built polity over a
## long history; §7.6 collapse (4e) would interrupt that growth, so these isolate
## the mechanic under test by disabling the collapse roll. The integration tests
## below keep the full sim (collapse + 4f renewal) active.
func _stable_constants() -> SimConstants:
	var c := SimConstants.new()
	c.collapse_base = 0.0
	return c


func _seed_polity(pid: String, culture_id: String, alignment: String, capital: Vector2i) -> Dictionary:
	return {
		"id": pid, "culture_id": culture_id, "alignment": alignment,
		"tier_index": 0, "title": "", "ruler_class": "", "ruler_level": 0,
		"ruler_quality": "average", "capital_q": capital.x, "capital_r": capital.y,
		"liege_id": "", "vassalized_by_war": 0, "founded_tick": 0,
		"fell_tick": null, "fade_onset_tick": null, "civ_or_clan_state": "civ",
		"garrison_coverage": 0.0, "morale_seed": "[]", "internal_vassals": "[]", "name": "",
	}


func test_logistic_growth_increment() -> void:
	# Exact single-tick logistic step, exercising _grow_hex directly:
	# ΔP = 0.10 × 500 × (1 − 500/2000) = 37.5 → banker's round → 38 → pop 538.
	var sim := HistorySimulator.new()
	sim._c = SimConstants.new()
	var key := Vector2i(0, 0)
	sim._grid = {key: {"population_band": 500, "territory_class": "wilderness"}}
	sim._grow_hex(key, 1.0)
	check(int(sim._grid[key]["population_band"]) == 538,
		"single logistic step from 500 (cap 2000) should yield 538, got %d"
			% int(sim._grid[key]["population_band"]))
	# A hex at the cap does not grow.
	sim._grid[key]["population_band"] = 2000
	sim._grow_hex(key, 1.0)
	check(int(sim._grid[key]["population_band"]) == 2000, "a capped hex must not grow")


func test_growth_approaches_cap() -> void:
	var ctx := _make_ctx(3, Vector2i(1, 0), 500, "agrippan", "lawful")
	ctx["params"].history_length = "deep"  # 240 ticks — plenty to fill
	HistorySimulator.new().run(ctx, _stable_constants())
	var pop := int(ctx["hex_grid"][Vector2i(1, 0)]["population_band"])
	# After deep history a held lowland hex should have climbed well past the
	# wilderness cap (it advances classification) toward the civilized cap.
	check(pop > 2000, "deep-history homeland should exceed the wilderness cap, got %d" % pop)
	check(pop <= 12480, "population must not exceed the civilized cap, got %d" % pop)


func test_classification_advances_when_full() -> void:
	var ctx := _make_ctx(3, Vector2i(1, 0), 500, "agrippan", "lawful")
	ctx["params"].history_length = "deep"
	HistorySimulator.new().run(ctx, _stable_constants())
	var tc := str(ctx["hex_grid"][Vector2i(1, 0)]["territory_class"])
	check(tc != "wilderness", "a fully-grown homeland should advance past wilderness, got %s" % tc)


func test_diffusion_spreads_culture_to_neighbors() -> void:
	var ctx := _make_ctx(5, Vector2i(2, 0), 500, "agrippan", "lawful")
	ctx["params"].history_length = "short"
	HistorySimulator.new().run(ctx, _stable_constants())
	# The hexes flanking the homeland should now carry some Agrippan weight.
	for nq in [1, 3]:
		var w = JSON.parse_string(str(ctx["hex_grid"][Vector2i(nq, 0)]["culture_weights"]))
		check(w is Dictionary and float(w.get("agrippan", 0.0)) > 0.0,
			"diffusion should spread culture to neighbor q=%d" % nq)


func test_diffusion_conserves_then_normalizes() -> void:
	# After finalize every inhabited hex's culture_weights sum to 1.0.
	var ctx := _make_ctx(5, Vector2i(2, 0), 500, "agrippan", "lawful")
	ctx["params"].history_length = "short"
	HistorySimulator.new().run(ctx, _stable_constants())
	var w = JSON.parse_string(str(ctx["hex_grid"][Vector2i(2, 0)]["culture_weights"]))
	var total := 0.0
	for k in w:
		total += float(w[k])
	check(abs(total - 1.0) < 0.001, "inhabited homeland weights should sum to 1.0, got %f" % total)


func test_assimilation_is_noop_for_pure_homeland() -> void:
	var ctx := _make_ctx(3, Vector2i(1, 0), 500, "agrippan", "lawful")
	ctx["params"].history_length = "short"
	HistorySimulator.new().run(ctx, _stable_constants())
	var w = JSON.parse_string(str(ctx["hex_grid"][Vector2i(1, 0)]["culture_weights"]))
	# Pure homeland stays ~100% its own culture (diffusion bleeds a sliver to
	# neighbors but assimilation pulls it back; normalization restores 1.0).
	check(float(w.get("agrippan", 0.0)) > 0.99, "homeland should remain dominantly its own culture")


func test_assimilation_converts_foreign_hex() -> void:
	# A held hex seeded with a FOREIGN culture should assimilate toward the
	# owner's culture over time (svg 0.5 × step 0.5 = 0.25/tick lerp).
	var ctx := _make_ctx(3, Vector2i(1, 0), 500, "agrippan", "lawful")
	# Overwrite the homeland's substrate to a foreign culture, owner still pol_0001.
	ctx["hex_grid"][Vector2i(1, 0)]["culture_weights"] = JSON.stringify({"vargari": 1.0})
	ctx["params"].history_length = "short"
	HistorySimulator.new().run(ctx, _stable_constants())
	var w = JSON.parse_string(str(ctx["hex_grid"][Vector2i(1, 0)]["culture_weights"]))
	check(float(w.get("agrippan", 0.0)) > float(w.get("vargari", 0.0)),
		"owner culture should overtake the foreign culture via assimilation")


func test_replay_frames_emitted() -> void:
	var ctx := _make_ctx(3, Vector2i(1, 0), 500, "agrippan", "lawful")
	ctx["params"].history_length = "short"  # 80 ticks, cadence 1 → 80 + final = 81
	HistorySimulator.new().run(ctx, _stable_constants())
	var frames: Array = ctx["sim_replay_frames"]
	check(frames.size() >= 20, "expected ~81 replay frames for 80 ticks/cadence 1, got %d" % frames.size())
	check(int(frames[0]["tick"]) == 0, "first replay frame should be tick 0")
	check(int(frames[frames.size() - 1]["tick"]) == 80, "last frame should be the present day (tick 80)")
	check(str(frames[0]["owner_by_hex"]).contains("pol_0001"),
		"replay frame RLE should reference the seed polity")


# --- Integration (full pipeline) ---------------------------------------------

func _generate_medium(seed_value: int) -> void:
	_cid = CampaignRepository.create_campaign("Stage4a %d" % seed_value, "w")
	var params := SettingParameters.new()
	check(SettingGenerator.new().generate(_cid, seed_value, params), "generate() failed")
	_hexes_by_qr = {}
	for hex in SettingRepository.list_hexes(_cid):
		_hexes_by_qr[Vector2i(int(hex.q), int(hex.r))] = hex
	_polities = SettingRepository.list_polities(_cid)


func test_present_day_polities_persisted() -> void:
	check(_polities.size() > 0, "no present-day polities persisted")
	for p in _polities:
		check(str(p.title) != "", "polity %s should have a tier title" % p.id)


func test_population_grew_from_seed() -> void:
	var grew := false
	for key in _hexes_by_qr:
		if int(_hexes_by_qr[key].population_band) > 500:
			grew = true
			break
	check(grew, "no hex grew above the 500-family seed after the full history")


func test_some_classification_advanced() -> void:
	var advanced := 0
	for key in _hexes_by_qr:
		if str(_hexes_by_qr[key].territory_class) != "wilderness":
			advanced += 1
	check(advanced > 0, "no hex advanced past wilderness over the full history")


func test_settlements_emerged() -> void:
	var settlements := SettingRepository.list_settlements(_cid)
	check(settlements.size() > 0, "no settlements emerged over the full history")
	for s in settlements:
		check(int(s.urban_families) >= 75, "settlement %s below the 75-family floor" % s.id)
		check(int(s.emergence_tick) >= 0, "settlement %s missing emergence_tick" % s.id)


func test_inhabited_substrate_sums_to_one() -> void:
	# §11.1: every inhabited hex's culture_weights sum to 100%.
	for key in _hexes_by_qr:
		var hex: Dictionary = _hexes_by_qr[key]
		if int(hex.population_band) <= 0:
			continue
		var w = JSON.parse_string(str(hex.culture_weights))
		if not (w is Dictionary) or w.is_empty():
			continue
		var total := 0.0
		for k in w:
			total += float(w[k])
		check(abs(total - 1.0) < 0.01,
			"inhabited hex %s culture_weights sum to %f, not 1.0" % [key, total])


func test_replay_frames_persisted() -> void:
	var frames := SettingRepository.list_replay_frames(_cid)
	check(frames.size() > 0, "no replay frames persisted")
	var palette := SettingRepository.list_replay_palette(_cid)
	check(palette.size() > 0, "no replay palette persisted")
	for row in palette:
		check(str(row.color).begins_with("#"), "palette color should be a hex string")


func test_large_map_sim_performance() -> void:
	# The 160-tick sim on a Large map (1200 hexes) should complete in seconds
	# (history-sim §14). Time JUST the sim over a pre-built in-memory seed ctx.
	var params := SettingParameters.new()
	params.map_size = "large"
	var ctx := {"campaign_id": "_inmem_", "campaign_seed": 7, "params": params}
	GeoFieldToGrid.run(ctx)  # continuous-geography: complete Layers 1-2 in one pass
	RegionPainter.run_phase1(ctx)
	CultureSeeder.run(ctx)
	var sim := HistorySimulator.new()
	sim._profile = true
	var start := Time.get_ticks_msec()
	sim.run(ctx)
	var elapsed := Time.get_ticks_msec() - start
	print("  [perf] 160-tick sim on Large (with expansion): %d ms" % elapsed)
	var ps := sim.profile_summary()
	var pkeys := ps.keys()
	pkeys.sort()
	for k in pkeys:
		print("    [phase] %-11s %5d ms" % [k, int(ps[k]) / 1000])
	# Regression guard. The post-4f perf pass (2026-06-13) brought the full
	# rise/fall/renewal sim from ~14.7s to ~9s via static-value caching
	# (terrain_mult, diffusion edge list), hot-loop inlining (diffusion), pruning
	# sub-minority-floor culture traces, and skipping wilderness in the war scan.
	# Ceiling is 25s (per Jedidiah); the print above + the per-phase breakdown
	# (profiling path) surface any regression.
	check(elapsed < 25000, "160-tick sim on Large took %d ms (regression guard, ceiling 25s)" % elapsed)


func test_full_pipeline_determinism() -> void:
	var cid2 := CampaignRepository.create_campaign("Stage4a Det B", "w")
	check(SettingGenerator.new().generate(cid2, 42, SettingParameters.new()),
		"second generate() failed")
	check(SettingDatasetHasher.compute_world_hash(_cid)
			== SettingDatasetHasher.compute_world_hash(cid2),
		"full pipeline (incl. the history sim) is not deterministic for the same seed")
