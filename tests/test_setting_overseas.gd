extends "res://tests/test_suite_base.gd"

## Stage 5.3 — overseas expansion. A coastal polity colonizes EMPTY coastal hexes
## across short sea gaps (within `sea_lane_range`, sharing an ocean), and the §7.4d
## contiguity primitive keeps the colony bridged while linked but drops it into its own
## component — the split — once the nearest sea link stretches past the range (e.g. war
## takes the intervening coast). Hand-built one-row "strait" worlds exercise the static
## sea-lane graph, the overseas frontier, and the connected-components split. The full
## secession pipeline (`_phase_contiguity` → `_secede_component`) is existing, separately
## exercised behavior; these tests pin the NEW 5.3 mechanism at the component boundary.


func run_all_tests() -> void:
	test_sea_cross_factor_decays_with_distance()
	test_sea_lane_precompute_links_within_range()
	test_overseas_frontier_includes_reachable_empty_coast()
	test_overseas_requires_populated_coastal_launch()
	test_colony_within_range_not_severed()
	test_colony_beyond_range_is_severed()
	print("SettingOverseasTests: all tests passed (%d checks)" % test_count())


# --- helpers -----------------------------------------------------------------

func _instance(culture_id: String) -> Dictionary:
	return {
		"culture_id": culture_id, "tier": "human", "race": "human",
		"aggression": 0.5, "defense": 0.5, "size_exponent_bias": 0.0,
		"base_subjugation_vs_genocide": 0.5, "conquest_modifiers": [],
		"peak_strength": 0.5, "collapse_proneness": 0.4, "end_state": "enduring",
		"seed_biomes": [], "affinity_secondary": [], "avoided": [],
		"sphere_weights": {}, "road_propensity": 0.3, "rigidity": 0.5,
		"civ_or_clan": "civ",
	}


func _polity(pid: String, capital: Vector2i) -> Dictionary:
	return {
		"id": pid, "culture_id": "c", "alignment": "lawful",
		"capital_q": capital.x, "capital_r": capital.y,
		"liege_id": "", "hexes": [], "alive": true,
	}


func _land(owner: String, pop: int = 500) -> Dictionary:
	return {
		"owner_polity_id": owner, "population_band": pop, "land_value": 6,
		"territory_class": "wilderness", "biome": "clear", "elevation": "flat",
		"biome_subtype": "", "water": "",
	}


func _ocean() -> Dictionary:
	return {
		"owner_polity_id": "", "population_band": 0, "land_value": 0,
		"territory_class": "wilderness", "biome": "", "elevation": "",
		"biome_subtype": "", "water": "ocean",
	}


func _sim() -> HistorySimulator:
	var sim := HistorySimulator.new()
	sim._c = SimConstants.new()
	sim._campaign_seed = 1
	sim._n_ticks = 160
	sim._culture_instances = {"c": _instance("c")}
	sim._grid = {}
	sim._culture_w = {}
	sim._alignment_w = {}
	sim._river_edge_any = {}
	sim._river_incident = {}
	sim._expand_jitter_by_hex = {}
	return sim


## One-row world: land at col 0, ocean cols 1..gap, land at col gap+1. The two land
## hexes are coastal, share the ocean body, and sit `gap+1` hexes apart (the q-row hex
## distance). Ocean + sea-lane precomputes are run before returning.
func _strait_world(gap: int, near_owner: String, far_owner: String,
		near_pop: int = 500) -> HistorySimulator:
	var sim := _sim()
	sim._grid[Vector2i(0, 0)] = _land(near_owner, near_pop)
	for c in range(1, gap + 1):
		sim._grid[Vector2i(c, 0)] = _ocean()
	sim._grid[Vector2i(gap + 1, 0)] = _land(far_owner)
	sim._precompute_ocean_components()
	sim._precompute_sea_lanes()
	return sim


func _none_overseas(frontier: Array) -> bool:
	for e in frontier:
		if bool(e.get("overseas", false)):
			return false
	return true


# --- tests -------------------------------------------------------------------

func test_sea_cross_factor_decays_with_distance() -> void:
	var sim := _sim()
	check(is_equal_approx(sim._sea_cross_factor(1), sim._c.sea_cross_base),
		"the 1-hop sea-cross factor equals sea_cross_base")
	check(sim._sea_cross_factor(5) < sim._sea_cross_factor(1),
		"the sea-cross factor decays with hop distance")
	check(sim._sea_cross_factor(10) > 0.0,
		"the sea-cross factor stays positive within range")


func test_sea_lane_precompute_links_within_range() -> void:
	# gap 4 → coasts at (0,0) and (5,0), distance 5 <= sea_lane_range (10).
	var sim := _strait_world(4, "", "")
	var a := Vector2i(0, 0)
	var b := Vector2i(5, 0)
	var na: Array = sim._sea_lane_neighbors.get(a, [])
	var nb: Array = sim._sea_lane_neighbors.get(b, [])
	check(na.has(b), "coasts within range sharing an ocean are sea-lane neighbours")
	check(nb.has(a), "the sea-lane neighbour relation is symmetric")
	# gap 11 → coasts at (0,0) and (12,0), distance 12 > 10.
	var far := _strait_world(11, "", "")
	var fn: Array = far._sea_lane_neighbors.get(Vector2i(0, 0), [])
	check(not fn.has(Vector2i(12, 0)),
		"coasts beyond sea_lane_range are NOT sea-lane neighbours")


func test_overseas_frontier_includes_reachable_empty_coast() -> void:
	# R holds the near (populated) coast; the far coast is EMPTY and within range.
	var sim := _strait_world(4, "R", "")
	var r := _polity("R", Vector2i(0, 0))
	r["hexes"] = [Vector2i(0, 0)]
	var found := {}
	for e in sim._compute_frontier(r):
		found[e["hex"]] = e
	check(found.has(Vector2i(5, 0)),
		"an empty coastal hex within sea range appears in the frontier")
	var entry: Dictionary = found.get(Vector2i(5, 0), {})
	check(bool(entry.get("overseas", false)), "the reachable empty coast is flagged overseas")
	check(bool(entry.get("settle", false)), "an overseas colony target is a settle (empty) target")
	check(float(entry.get("mult", 0.0)) > 0.0, "the overseas target has a positive expansion weight")

	# An OWNED far coast is not a colonization target (no amphibious contest here).
	var sim_owned := _strait_world(4, "R", "E")
	var r2 := _polity("R", Vector2i(0, 0))
	r2["hexes"] = [Vector2i(0, 0)]
	check(_none_overseas(sim_owned._compute_frontier(r2)),
		"an enemy-owned far coast is not an overseas settle target")


func test_overseas_requires_populated_coastal_launch() -> void:
	# The near coast is depopulated (pop 0) → it cannot launch a colony.
	var sim := _strait_world(4, "R", "", 0)
	var r := _polity("R", Vector2i(0, 0))
	r["hexes"] = [Vector2i(0, 0)]
	check(_none_overseas(sim._compute_frontier(r)),
		"a depopulated coastal hex cannot launch an overseas colony")


func test_colony_within_range_not_severed() -> void:
	# R owns both coasts, 5 hexes apart: the sea lane bridges them into one realm.
	var sim := _strait_world(4, "R", "R")
	var r := _polity("R", Vector2i(0, 0))
	r["hexes"] = [Vector2i(0, 0), Vector2i(5, 0)]
	var comps := sim._connected_components(r)
	check(comps.size() == 1,
		"a colony within sea_lane_range stays one realm (bridged, not severed), got %d"
			% comps.size())


func test_colony_beyond_range_is_severed() -> void:
	# The colony is 12 hexes from R's nearest coast (> sea_lane_range): it drops out of
	# the capital's component, so _phase_contiguity sheds it (the split).
	var sim := _strait_world(11, "R", "R")
	var r := _polity("R", Vector2i(0, 0))
	r["hexes"] = [Vector2i(0, 0), Vector2i(12, 0)]
	var comps := sim._connected_components(r)
	check(comps.size() == 2,
		"a colony beyond sea_lane_range forms a separate component (it will split off), got %d"
			% comps.size())
	var cap_comp: Array = []
	for comp in comps:
		if Vector2i(0, 0) in comp:
			cap_comp = comp
	check(not (Vector2i(12, 0) in cap_comp),
		"the over-range colony is not in the capital's kept component")
