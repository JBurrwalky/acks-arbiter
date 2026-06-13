extends "res://tests/test_suite_base.gd"

## Stage 4c — history sim: realm economy / garrison ledger (§7.5.1). Pure
## functions over a realm's hexes, unit-tested against hand-computed examples;
## integration confirms the full pipeline produces sane garrison_coverage /
## f_overextension and that coverage now varies (it feeds 4b's contest
## readiness).

var _cid: String = ""
var _polities: Array = []


func run_all_tests() -> void:
	test_ledger_solvent_realm()
	test_frontier_multiplier_raises_garrison_need()
	test_insolvency_drives_overextension_to_max()
	test_tribute_formula()
	test_ruler_and_military_shift_coverage()
	test_zero_garrison_need_is_safe()
	_generate_medium(42)
	test_present_day_coverage_and_overextension_sane()
	test_coverage_varies_across_realms()
	test_determinism()
	print("SettingStage4cTests: all tests passed (%d checks)" % test_count())


# --- Hand-built helpers ------------------------------------------------------

func _bare_sim(grid: Dictionary, instances: Dictionary) -> HistorySimulator:
	var sim := HistorySimulator.new()
	sim._c = SimConstants.new()
	sim._campaign_seed = 1
	sim._grid = grid
	sim._culture_instances = instances
	return sim


func _hex(pop: int, land_value: int, tclass: String, owner: String) -> Dictionary:
	return {
		"population_band": pop, "land_value": land_value,
		"territory_class": tclass, "owner_polity_id": owner,
		"biome": "clear", "elevation": "flat", "biome_subtype": "", "water": "",
	}


func _polity(pid: String, culture_id: String, capital: Vector2i,
		ruler_quality: String = "average") -> Dictionary:
	return {
		"id": pid, "culture_id": culture_id, "alignment": "lawful",
		"capital_q": capital.x, "capital_r": capital.y, "ruler_quality": ruler_quality,
		"liege_id": "", "hexes": [],
	}


func _inst(military: float) -> Dictionary:
	return {"sphere_weights": {"military": military}}


# --- Unit tests --------------------------------------------------------------

func test_ledger_solvent_realm() -> void:
	# Realm of 2 hexes, no rivals, no tribute. Hand-computed:
	#   income = 1000×(6+6) + 500×(4+6) = 12000 + 5000 = 17000
	#   garrison_need = 1000×2(civ)×1.0 + 500×3(border)×1.0 = 2000 + 1500 = 3500
	#   target_coverage = 0.7 + 0.6×0.25 = 0.85
	#   garrison_spent = min(3500×0.85, 17000−4500) = min(2975, 12500) = 2975
	#   garrison_coverage = 2975/3500 = 0.85
	#   solvency = 17000 − 4500 − 3000 = 9500 (solvent)
	#   f_overextension = 1 + 1.0×(1−0.85) + 0 = 1.15
	var grid := {
		Vector2i(0, 0): _hex(1000, 6, "civilized", "p"),
		Vector2i(1, 0): _hex(500, 4, "borderlands", "p"),
	}
	var sim := _bare_sim(grid, {"c": _inst(0.25)})
	var pol := _polity("p", "c", Vector2i(0, 0))
	pol["hexes"] = [Vector2i(0, 0), Vector2i(1, 0)]
	var l := sim._compute_ledger(pol, 0.0, 0.0)
	check(is_equal_approx(float(l["income"]), 17000.0), "income should be 17000, got %f" % l["income"])
	check(is_equal_approx(float(l["garrison_need"]), 3500.0),
		"garrison_need should be 3500, got %f" % l["garrison_need"])
	check(abs(float(l["garrison_coverage"]) - 0.85) < 0.0001,
		"coverage should be 0.85, got %f" % l["garrison_coverage"])
	check(abs(float(l["f_overextension"]) - 1.15) < 0.0001,
		"f_overextension should be 1.15, got %f" % l["f_overextension"])


func test_frontier_multiplier_raises_garrison_need() -> void:
	# Same single hex, with vs without a bordering rival. Rival → frontier_mult
	# 1.5, so garrison_need is 1.5× higher.
	var capital := Vector2i(0, 0)
	var sim_iso := _bare_sim({capital: _hex(1000, 6, "wilderness", "p")}, {"c": _inst(0.2)})
	var pol := _polity("p", "c", capital)
	pol["hexes"] = [capital]
	var need_iso := float(sim_iso._compute_ledger(pol, 0.0, 0.0)["garrison_need"])
	check(is_equal_approx(need_iso, 4000.0), "isolated wilderness need = 1000×4×1.0 = 4000, got %f" % need_iso)

	var grid_rival := {
		capital: _hex(1000, 6, "wilderness", "p"),
		Vector2i(1, 0): _hex(200, 6, "wilderness", "q"),  # rival neighbor
	}
	var sim_rival := _bare_sim(grid_rival, {"c": _inst(0.2)})
	var need_rival := float(sim_rival._compute_ledger(pol, 0.0, 0.0)["garrison_need"])
	check(is_equal_approx(need_rival, 6000.0),
		"bordered wilderness need = 1000×4×1.5 = 6000, got %f" % need_rival)


func test_insolvency_drives_overextension_to_max() -> void:
	# Force insolvency via a heavy tribute_out: income collapses below overhead +
	# min_garrison, coverage → 0, f_overextension → cap 3.0.
	var grid := {Vector2i(0, 0): _hex(1000, 3, "wilderness", "p")}  # income 9000
	var sim := _bare_sim(grid, {"c": _inst(0.2)})
	var pol := _polity("p", "c", Vector2i(0, 0))
	pol["hexes"] = [Vector2i(0, 0)]
	var l := sim._compute_ledger(pol, 0.0, 8000.0)  # tribute_out 8000 → income 1000
	check(float(l["garrison_coverage"]) == 0.0,
		"a bankrupt realm can afford no garrison (coverage 0), got %f" % l["garrison_coverage"])
	check(abs(float(l["f_overextension"]) - 3.0) < 0.0001,
		"deep insolvency should cap f_overextension at 3.0, got %f" % l["f_overextension"])


func test_tribute_formula() -> void:
	var sim := _bare_sim({}, {})
	# 18 × 1000^0.6
	var expected := 18.0 * pow(1000.0, 0.6)
	check(abs(sim._tribute_for(1000) - expected) < 0.001,
		"tribute_for(1000) should be 18×1000^0.6")
	check(sim._tribute_for(0) == 0.0, "tribute for an empty realm is 0")


func test_ruler_and_military_shift_coverage() -> void:
	# A militarist realm under a strong ruler garrisons more heavily than a
	# mercantile realm under a weak ruler (same hexes).
	var grid := {Vector2i(0, 0): _hex(1000, 6, "wilderness", "p")}
	var militarist := _bare_sim(grid, {"c": _inst(0.5)})
	var strong := _polity("p", "c", Vector2i(0, 0), "strong")
	strong["hexes"] = [Vector2i(0, 0)]
	var cov_strong := float(militarist._compute_ledger(strong, 0.0, 0.0)["garrison_coverage"])

	var mercantile := _bare_sim(grid, {"c": _inst(0.1)})
	var weak := _polity("p", "c", Vector2i(0, 0), "weak")
	weak["hexes"] = [Vector2i(0, 0)]
	var cov_weak := float(mercantile._compute_ledger(weak, 0.0, 0.0)["garrison_coverage"])
	check(cov_strong > cov_weak,
		"militarist+strong should out-garrison mercantile+weak (%f vs %f)" % [cov_strong, cov_weak])


func test_zero_garrison_need_is_safe() -> void:
	# An empty realm (no families) must not divide by zero.
	var sim := _bare_sim({}, {"c": _inst(0.2)})
	var pol := _polity("p", "c", Vector2i(0, 0))
	pol["hexes"] = []
	var l := sim._compute_ledger(pol, 0.0, 0.0)
	check(float(l["garrison_coverage"]) == 1.0, "empty realm coverage defaults to 1.0")
	check(float(l["f_overextension"]) == 1.0, "empty realm f_overextension defaults to 1.0")


# --- Integration -------------------------------------------------------------

func _generate_medium(seed_value: int) -> void:
	_cid = CampaignRepository.create_campaign("Stage4c %d" % seed_value, "w")
	check(SettingGenerator.new().generate(_cid, seed_value, SettingParameters.new()),
		"generate() failed")
	_polities = SettingRepository.list_polities(_cid)


func test_present_day_coverage_and_overextension_sane() -> void:
	# The ledger ran every tick; the persisted present-day garrison_coverage
	# must be a valid coverage value (0..1.2 — capped by target_coverage).
	for p in _polities:
		var cov := float(p.garrison_coverage)
		check(cov >= 0.0 and cov <= 1.2 + 0.0001,
			"polity %s garrison_coverage out of [0,1.2]: %f" % [p.id, cov])


func test_coverage_varies_across_realms() -> void:
	# Different realms (cultures, sizes, frontiers) should reach different
	# coverage — proof the ledger actually differentiates and isn't a constant.
	var seen := {}
	for p in _polities:
		seen[snappedf(float(p.garrison_coverage), 0.001)] = true
	check(seen.size() > 1, "garrison_coverage is identical across all realms (ledger inert?)")


func test_determinism() -> void:
	var cid2 := CampaignRepository.create_campaign("Stage4c Det B", "w")
	check(SettingGenerator.new().generate(cid2, 42, SettingParameters.new()), "second generate failed")
	check(SettingDatasetHasher.compute_world_hash(_cid)
			== SettingDatasetHasher.compute_world_hash(cid2),
		"the economy ledger made the pipeline non-deterministic")
