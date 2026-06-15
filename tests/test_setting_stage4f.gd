extends "res://tests/test_suite_base.gd"

## Stage 4f — history sim: migration + beastman repopulation (§8, §7.6). The
## renewal half of the rise/fall loop. Unit tests pin band routing, migrant
## founding, and beastman clanhold spawning on a hand-built state; integration
## tests confirm the full pipeline now reaches EQUILIBRIUM (realms AND wilderness
## coexist — neither drained nor fully filled) and stays deterministic.

var _cid: String = ""
var _polities: Array = []
var _hexes_by_qr: Dictionary = {}


func run_all_tests() -> void:
	# Migration bands (§8)
	test_create_band()
	test_has_unclaimed_cluster()
	test_find_migration_target()
	test_retarget_band_routes_or_dissolves()
	test_found_migrant_polity()
	test_advance_band_travels_then_lands()
	test_dissolve_band_conserves_families()
	# Beastman repopulation (§7.6)
	test_spawn_beastman_clanhold()
	test_repopulate_respects_delay()
	test_repopulate_skips_reclaimed_hex()
	test_finalize_new_polity_flags_beastman()
	# Pressure (§8)
	test_pressure_band_on_capital_loss()
	# Integration
	_generate_medium(42)
	test_map_reaches_equilibrium()
	test_liege_and_owner_coherent()
	test_pipeline_determinism()
	print("SettingStage4fTests: all tests passed (%d checks)" % test_count())


# --- Hand-built helpers ------------------------------------------------------

func _instance(culture_id: String, seed_biomes: Array = [], aggression: float = 0.6,
		defense: float = 0.5) -> Dictionary:
	return {
		"culture_id": culture_id, "tier": "human", "race": "human",
		"aggression": aggression, "defense": defense, "size_exponent_bias": 0.0,
		"base_subjugation_vs_genocide": 0.5, "conquest_modifiers": [],
		"peak_strength": 0.5, "collapse_proneness": 0.4, "end_state": "enduring",
		"seed_biomes": seed_biomes, "affinity_secondary": [], "avoided": [],
		"sphere_weights": {}, "road_propensity": 0.3, "rigidity": 0.5, "civ_or_clan": "civ",
	}


func _bare_sim(instances: Dictionary) -> HistorySimulator:
	var sim := HistorySimulator.new()
	sim._c = SimConstants.new()
	sim._campaign_seed = 1
	sim._n_ticks = 160
	sim._params = SettingParameters.new()
	sim._culture_instances = instances
	sim._grid = {}
	sim._culture_w = {}
	sim._alignment_w = {}
	sim._polities = {}
	sim._ordered_keys = []
	sim._next_polity_seq = 200
	return sim


## A width×height all-clear/flat grid; every hex unowned wilderness unless listed
## in `owned` (Vector2i -> owner id). Builds _ordered_keys canonically.
func _build_grid(sim: HistorySimulator, w: int, h: int, owned: Dictionary = {}) -> void:
	for r in range(h):
		for q in range(w):
			var key := Vector2i(q, r)
			sim._ordered_keys.append(key)
			var o: String = str(owned.get(key, ""))
			sim._grid[key] = {
				"owner_polity_id": o, "population_band": 500 if o != "" else 0,
				"land_value": 6, "territory_class": "wilderness", "biome": "clear",
				"elevation": "flat", "biome_subtype": "", "water": "",
			}
			sim._culture_w[key] = {}
			sim._alignment_w[key] = {}


# --- Migration bands ---------------------------------------------------------

func test_create_band() -> void:
	var sim := _bare_sim({})
	sim._create_band("c", "lawful", 300, Vector2i(2, 3))
	check(sim._bands.size() == 1, "a band is recorded")
	var b: Dictionary = sim._bands[0]
	check(int(b["families"]) == 300 and str(b["culture_id"]) == "c", "band carries its people and culture")
	check(int(b["ticks_remaining"]) == -1, "a fresh band is un-routed (retargets on first advance)")


func test_has_unclaimed_cluster() -> void:
	var sim := _bare_sim({})
	_build_grid(sim, 4, 1)   # 4 contiguous unclaimed land hexes
	check(sim._has_unclaimed_cluster(Vector2i(1, 0)), "an interior unclaimed hex sits in a ≥3 cluster")
	# Claim all but one → that one is isolated.
	sim._grid[Vector2i(0, 0)]["owner_polity_id"] = "x"
	sim._grid[Vector2i(2, 0)]["owner_polity_id"] = "x"
	check(not sim._has_unclaimed_cluster(Vector2i(1, 0)),
		"a lone unclaimed hex between claimed ones is not a ≥3 cluster")


func test_find_migration_target() -> void:
	var sim := _bare_sim({"c": _instance("c", ["grassland"])})   # clear matches grassland → mult 1.5
	_build_grid(sim, 6, 1, {Vector2i(0, 0): "home"})
	# Origin near (0,0); nearest unclaimed cluster with good terrain is around (1,0).
	var target := sim._find_migration_target("c", Vector2i(0, 0))
	check(target != Vector2i(-999, -999), "a viable homeland is found on favorable terrain")
	check(str(sim._grid[target]["owner_polity_id"]) == "", "the target is unclaimed")
	# With no favorable terrain (avoided everywhere) there is no target.
	var sim2 := _bare_sim({"d": _instance("d", [], 0.5, 0.5)})  # no seed biomes → mult 1.0 < 1.15
	_build_grid(sim2, 6, 1)
	check(sim2._find_migration_target("d", Vector2i(0, 0)) == Vector2i(-999, -999),
		"no favorable terrain → no migration target")


func test_retarget_band_routes_or_dissolves() -> void:
	var sim := _bare_sim({"c": _instance("c", ["grassland"])})
	_build_grid(sim, 8, 1)
	var band := {"culture_id": "c", "alignment": "lawful", "families": 300,
		"origin_q": 0, "origin_r": 0, "target_q": -999, "target_r": -999, "ticks_remaining": -1}
	sim._retarget_band(band)
	check(int(band["target_q"]) != -999, "a band on a map with viable land gets a route")
	check(int(band["ticks_remaining"]) >= 1, "routing sets a positive travel time")


func test_found_migrant_polity() -> void:
	var sim := _bare_sim({"c": _instance("c", ["grassland"])})
	_build_grid(sim, 4, 1)
	var band := {"culture_id": "c", "alignment": "lawful", "families": 400,
		"origin_q": 0, "origin_r": 0, "target_q": 2, "target_r": 0, "ticks_remaining": 0}
	sim._found_migrant_polity(band, 30)
	check(str(sim._grid[Vector2i(2, 0)]["owner_polity_id"]) != "", "the band founds a realm on its target")
	var pid := str(sim._grid[Vector2i(2, 0)]["owner_polity_id"])
	var pol: Dictionary = sim._polities[pid]
	check(int(pol["founded_tick"]) == 30, "a migrant realm founds NOW (ascendancy resets)")
	check(Vector2i(2, 0) in pol["hexes"], "the migrant realm owns its landing hex")
	check(int(sim._grid[Vector2i(2, 0)]["population_band"]) == 400, "the realm starts with the band's families")


func test_advance_band_travels_then_lands() -> void:
	var sim := _bare_sim({"c": _instance("c", ["grassland"])})
	_build_grid(sim, 10, 1)
	sim._create_band("c", "lawful", 350, Vector2i(0, 0))
	var landed := false
	for t in range(40):
		sim._advance_bands(t)
		if sim._bands.is_empty():
			landed = true
			break
	check(landed, "a band eventually routes, travels, and lands (or dissolves)")
	# Some new realm should now exist from the band.
	var migrant_found := false
	for key in sim._grid:
		if str(sim._grid[key]["owner_polity_id"]).begins_with("pol_"):
			migrant_found = true
			break
	check(migrant_found, "the landed band founded a realm")


func test_dissolve_band_conserves_families() -> void:
	# A band that can't found a realm dissolves into the local substrate (§8):
	# its families join the hex and blend their culture by population weight.
	var sim := _bare_sim({})
	_build_grid(sim, 1, 1, {Vector2i(0, 0): "x"})
	sim._grid[Vector2i(0, 0)]["population_band"] = 500
	sim._grid[Vector2i(0, 0)]["territory_class"] = "civilized"
	sim._culture_w[Vector2i(0, 0)] = {"native": 1.0}
	sim._alignment_w[Vector2i(0, 0)] = {"lawful": 1.0}
	var band := {"culture_id": "migrant", "alignment": "chaotic", "families": 300,
		"origin_q": 0, "origin_r": 0}
	sim._dissolve_band(band, Vector2i(0, 0))
	check(int(sim._grid[Vector2i(0, 0)]["population_band"]) == 800,
		"the dissolved band's 300 families join the hex's 500, got %d"
			% int(sim._grid[Vector2i(0, 0)]["population_band"]))
	var w: Dictionary = sim._culture_w[Vector2i(0, 0)]
	check(abs(float(w.get("migrant", 0.0)) - 0.375) < 0.001,
		"the migrants' culture blends in population-weighted (300/800=0.375), got %f" % w.get("migrant", 0.0))
	check(float(w.get("native", 0.0)) > 0.0, "the prior culture survives the blend")


# --- Beastman repopulation ---------------------------------------------------

func test_spawn_beastman_clanhold() -> void:
	var sim := _bare_sim({})
	_build_grid(sim, 1, 1)   # one empty clear/flat hex → 'clear_grass' distribution column
	var ok := sim._spawn_beastman_clanhold(Vector2i(0, 0), 12)
	check(ok, "a clanhold spawns on valid wilderness terrain")
	var pid := str(sim._grid[Vector2i(0, 0)]["owner_polity_id"])
	check(pid != "", "the spawned clanhold owns its hex")
	var pol: Dictionary = sim._polities[pid]
	check(str(pol["alignment"]) == "chaotic", "beastman clanholds are Chaotic")
	check(bool(pol["is_beastman"]), "the clanhold is flagged beastman")
	check(int(pol["founded_tick"]) == 12, "the clanhold founds at the spawn tick")


func test_repopulate_respects_delay() -> void:
	var sim := _bare_sim({})
	_build_grid(sim, 1, 1)
	sim._params.wilderness_beastman_density = 100.0   # force the spawn roll to pass
	sim._depopulated_at = {Vector2i(0, 0): 10}
	sim._repopulate_beastmen(11)   # only 1 tick since depopulation (< BEASTMAN_DELAY 2)
	check(str(sim._grid[Vector2i(0, 0)]["owner_polity_id"]) == "",
		"no beastman spawns before BEASTMAN_DELAY elapses")
	sim._repopulate_beastmen(12)   # 2 ticks elapsed → eligible
	check(str(sim._grid[Vector2i(0, 0)]["owner_polity_id"]) != "",
		"a beastman clanhold spawns once the delay has passed")


func test_repopulate_skips_reclaimed_hex() -> void:
	var sim := _bare_sim({})
	_build_grid(sim, 1, 1, {Vector2i(0, 0): "human"})   # hex already reclaimed
	sim._params.wilderness_beastman_density = 100.0
	sim._depopulated_at = {Vector2i(0, 0): 0}
	sim._repopulate_beastmen(20)
	check(str(sim._grid[Vector2i(0, 0)]["owner_polity_id"]) == "human",
		"a reclaimed hex is not overwritten by beastman repopulation")
	check(not sim._depopulated_at.has(Vector2i(0, 0)), "the reclaimed hex is dropped from the spawn set")


func test_finalize_new_polity_flags_beastman() -> void:
	var sim := _bare_sim({"human": _instance("human")})
	var human := {"culture_id": "human"}
	sim._finalize_new_polity(human, 5)
	check(not bool(human["is_beastman"]), "a culture with an instance is not beastman")
	var orc := {"culture_id": "orc_no_instance"}
	sim._finalize_new_polity(orc, 5)
	check(bool(orc["is_beastman"]), "a culture with no jittered instance is beastman (§5.3)")
	check(int(human["founded_tick"]) == 5 and bool(human["alive"]), "runtime fields are set")


# --- Pressure migration ------------------------------------------------------

func test_pressure_band_on_capital_loss() -> void:
	var sim := _bare_sim({"c": _instance("c", ["grassland"], 0.9, 0.1)})  # mobile/aggressive
	sim._params.migration_rate = "high"
	_build_grid(sim, 4, 1, {Vector2i(1, 0): "p", Vector2i(2, 0): "p"})
	# Capital is (0,0) but the polity no longer owns it (lost capital).
	var pol := {
		"id": "p", "culture_id": "c", "alignment": "lawful", "capital_q": 0, "capital_r": 0,
		"hexes": [Vector2i(1, 0), Vector2i(2, 0)], "alive": true,
	}
	sim._polities = {"p": pol}
	sim._tick_start_size = {"p": 2}
	sim._spawn_pressure_bands(7)
	check(sim._bands.size() >= 1, "a realm that lost its capital sends out a migrating band")


# --- Integration -------------------------------------------------------------

func _generate_medium(seed_value: int) -> void:
	_cid = CampaignRepository.create_campaign("Stage4f %d" % seed_value, "w")
	check(SettingGenerator.new().generate(_cid, seed_value, SettingParameters.new()),
		"generate() failed")
	_polities = SettingRepository.list_polities(_cid)
	_hexes_by_qr = {}
	for hex in SettingRepository.list_hexes(_cid):
		_hexes_by_qr[Vector2i(int(hex.q), int(hex.r))] = hex


func test_map_reaches_equilibrium() -> void:
	# The whole point of 4e+4f: the present-day map is neither drained (collapse
	# would empty it) nor fully filled (expansion alone would) — surviving and
	# freshly-founded realms coexist with restored wilderness.
	var owned_land := 0
	var unowned_land := 0
	for key in _hexes_by_qr:
		var hex: Dictionary = _hexes_by_qr[key]
		if str(hex.water) != "":
			continue
		if str(hex.owner_polity_id) == "":
			unowned_land += 1
		else:
			owned_land += 1
	check(_polities.size() >= 3,
		"renewal should keep several realms alive at present day, got %d" % _polities.size())
	check(owned_land > 0, "realms still hold territory at present day, got %d" % owned_land)
	check(unowned_land > 0, "collapse still leaves wilderness at present day, got %d" % unowned_land)


func test_liege_and_owner_coherent() -> void:
	# After all the spawning/freeing, every owner id and liege id resolves to a
	# present-day polity (no dangling references from 4e/4f churn).
	var ids := {}
	for p in _polities:
		ids[str(p.id)] = true
	for key in _hexes_by_qr:
		var o := str(_hexes_by_qr[key].owner_polity_id)
		check(o == "" or ids.has(o), "owner %s of hex %s is a present-day polity" % [o, key])
	for p in _polities:
		var liege := str(p.liege_id)
		check(liege == "" or ids.has(liege), "liege %s of %s is present" % [liege, p.id])


func test_pipeline_determinism() -> void:
	var cid2 := CampaignRepository.create_campaign("Stage4f Det B", "w")
	check(SettingGenerator.new().generate(cid2, 42, SettingParameters.new()), "second generate failed")
	check(SettingDatasetHasher.compute_world_hash(_cid)
			== SettingDatasetHasher.compute_world_hash(cid2),
		"migration/repopulation made the pipeline non-deterministic")
