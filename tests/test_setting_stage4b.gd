extends "res://tests/test_suite_base.gd"

## Stage 4b — history sim: expansion + border contest (§7.2-7.3). Unit tests
## pin the expansion-pressure curve, terrain multiplier, contest resolution,
## and settling on a hand-built state; integration tests confirm the full
## pipeline now grows multi-hex realms (not just single-hex seeds) while
## leaving wilderness, deterministically.

var _cid: String = ""
var _polities: Array = []
var _hexes_by_qr: Dictionary = {}


func run_all_tests() -> void:
	# Unit
	test_expansion_pressure_falls_with_size()
	test_terrain_multiplier()
	test_settling_claims_wilderness()
	test_polity_expands_into_wilderness_over_ticks()
	test_contest_certain_win_and_loss()
	test_contest_attrition_on_loss()
	# Integration
	_generate_medium(42)
	test_realms_span_multiple_hexes()
	test_multiple_owners_coexist()
	test_owned_hexes_are_populated()
	test_determinism()
	print("SettingStage4bTests: all tests passed (%d checks)" % test_count())


# --- Hand-built helpers ------------------------------------------------------

func _instance(culture_id: String, aggression: float, defense: float,
		seed_biomes: Array = [], tier: String = "human") -> Dictionary:
	return {
		"culture_id": culture_id, "tier": tier, "race": "human",
		"aggression": aggression, "defense": defense, "size_exponent_bias": 0.0,
		"base_subjugation_vs_genocide": 0.5, "conquest_modifiers": [],
		"peak_strength": 0.5, "collapse_proneness": 0.4, "end_state": "enduring",
		"seed_biomes": seed_biomes, "affinity_secondary": [], "avoided": [],
		"sphere_weights": {}, "road_propensity": 0.3, "rigidity": 0.5,
	}


func _polity(pid: String, culture_id: String, alignment: String, capital: Vector2i) -> Dictionary:
	return {
		"id": pid, "culture_id": culture_id, "alignment": alignment,
		"tier_index": 0, "title": "", "ruler_class": "", "ruler_level": 0,
		"ruler_quality": "average", "capital_q": capital.x, "capital_r": capital.y,
		"liege_id": "", "vassalized_by_war": 0, "founded_tick": 0,
		"fell_tick": null, "fade_onset_tick": null, "civ_or_clan_state": "civ",
		"garrison_coverage": 0.0, "morale_seed": "[]", "internal_vassals": "[]", "name": "",
	}


## A width×height all-land 'clear/flat' grid with one polity at `capital`.
func _grid_ctx(w: int, h: int, capital: Vector2i, culture_id: String,
		instance: Dictionary) -> Dictionary:
	var grid := {}
	for r in range(h):
		for q in range(w):
			var key := Vector2i(q, r)
			var owned := (key == capital)
			grid[key] = {
				"elevation": "flat", "biome": "clear", "biome_subtype": "", "water": "",
				"culture_weights": JSON.stringify({culture_id: 1.0}) if owned else "{}",
				"alignment_weights": JSON.stringify({"lawful": 1.0}) if owned else "{}",
				"population_band": 500 if owned else 0,
				"territory_class": "wilderness",
				"owner_polity_id": "pol_0001" if owned else "",
				"land_value": 6,
			}
	var params := SettingParameters.new()
	return {
		"campaign_id": "_inmem_", "campaign_seed": 1, "params": params,
		"hex_grid": grid, "width": w, "height": h, "river_edges": [],
		"culture_instances": {culture_id: instance},
		"seed_polities": [_polity("pol_0001", culture_id, "lawful", capital)],
	}


## A bare sim wired with constants/seed/grid/instances, ready for direct
## factor calls (no run()).
func _bare_sim(grid: Dictionary, instances: Dictionary) -> HistorySimulator:
	var sim := HistorySimulator.new()
	sim._c = SimConstants.new()
	sim._campaign_seed = 1
	sim._n_ticks = 160
	sim._grid = grid
	sim._culture_instances = instances
	return sim


# --- Unit tests --------------------------------------------------------------

func test_expansion_pressure_falls_with_size() -> void:
	var sim := _bare_sim({}, {"c": _instance("c", 0.6, 0.5)})
	var small := {"id": "p", "culture_id": "c", "hexes": _fake_hexes(1),
		"founded_tick": 0, "ruler_quality": "average"}
	var big := {"id": "p", "culture_id": "c", "hexes": _fake_hexes(100),
		"founded_tick": 0, "ruler_quality": "average"}
	var p_small := sim._expansion_pressure(small, 0)
	var p_big := sim._expansion_pressure(big, 0)
	check(p_small > p_big, "a small polity should out-expand a large one (%f vs %f)" % [p_small, p_big])
	check(p_small > 0.0, "expansion pressure should be positive for a live polity")


func test_terrain_multiplier() -> void:
	var grid := {
		Vector2i(0, 0): {"biome": "woods", "elevation": "flat", "biome_subtype": "", "water": ""},
		Vector2i(1, 0): {"biome": "desert", "elevation": "flat", "biome_subtype": "", "water": ""},
		Vector2i(2, 0): {"biome": "clear", "elevation": "flat", "biome_subtype": "", "water": ""},
	}
	var inst := _instance("c", 0.6, 0.5, ["forest"])  # seed biome = forest (woods)
	inst["avoided"] = ["desert"]
	var sim := _bare_sim(grid, {"c": inst})
	var pol := {"culture_id": "c"}
	check(sim._terrain_mult(pol, Vector2i(0, 0)) == 1.5, "seed-biome hex should be 1.5")
	check(sim._terrain_mult(pol, Vector2i(1, 0)) == 0.5, "avoided hex should be 0.5")
	check(sim._terrain_mult(pol, Vector2i(2, 0)) == 1.0, "neutral hex should be 1.0")


func test_settling_claims_wilderness() -> void:
	var ctx := _grid_ctx(5, 5, Vector2i(2, 2), "c", _instance("c", 0.6, 0.5))
	var sim := _bare_sim(ctx["hex_grid"], ctx["culture_instances"])
	var pol := _polity("pol_0001", "c", "lawful", Vector2i(2, 2))
	pol["hexes"] = [Vector2i(2, 2)]
	sim._culture_w = {Vector2i(2, 2): {"c": 1.0}}
	sim._alignment_w = {Vector2i(2, 2): {"lawful": 1.0}}
	sim._settle_wilderness(pol, Vector2i(2, 1))
	check(str(ctx["hex_grid"][Vector2i(2, 1)]["owner_polity_id"]) == "pol_0001",
		"settled hex should be owned by the polity")
	check(int(ctx["hex_grid"][Vector2i(2, 1)]["population_band"]) == 500,
		"settled hex should start at 500 families")
	check(Vector2i(2, 1) in pol["hexes"], "settled hex should join the polity's holdings")


func test_polity_expands_into_wilderness_over_ticks() -> void:
	var ctx := _grid_ctx(9, 9, Vector2i(4, 4), "c", _instance("c", 0.7, 0.5, ["grassland"]))
	ctx["params"].history_length = "short"
	# Isolate expansion from §7.6 collapse (4e) so this measures only the 4b spread.
	var c := SimConstants.new()
	c.collapse_base = 0.0
	HistorySimulator.new().run(ctx, c)
	var owned := 0
	for key in ctx["hex_grid"]:
		if str(ctx["hex_grid"][key]["owner_polity_id"]) == "pol_0001":
			owned += 1
	check(owned > 1, "the polity should expand beyond its 1 seed hex, owns %d" % owned)


func test_contest_certain_win_and_loss() -> void:
	var grid := {Vector2i(0, 0): {"biome": "clear", "elevation": "flat",
		"biome_subtype": "", "water": "", "owner_polity_id": "q"}}
	# Attacker with defense-0 target → p_win = 1.0 → always wins.
	var sim := _bare_sim(grid, {
		"ca": _instance("ca", 0.8, 0.5), "cq": _instance("cq", 0.5, 0.0)})
	var p := _polity("p", "ca", "lawful", Vector2i(5, 5))
	p["hexes"] = _fake_hexes(10)
	var q := _polity("q", "cq", "chaotic", Vector2i(0, 0))
	q["hexes"] = [Vector2i(0, 0)]
	check(sim._resolve_contest(p, q, Vector2i(0, 0), 0),
		"a defense-0 target should always be taken")
	# Attacker with aggression 0 → atk = 0 → p_win = 0 → always loses.
	var sim2 := _bare_sim(grid, {
		"ca": _instance("ca", 0.0, 0.5), "cq": _instance("cq", 0.5, 0.6)})
	check(not sim2._resolve_contest(p, q, Vector2i(0, 0), 0),
		"a zero-aggression attacker should never win")


func test_contest_attrition_on_loss() -> void:
	var grid := {Vector2i(0, 0): {"biome": "clear", "elevation": "flat",
		"biome_subtype": "", "water": "", "owner_polity_id": "q"}}
	var sim := _bare_sim(grid, {
		"ca": _instance("ca", 0.0, 0.5), "cq": _instance("cq", 0.5, 0.9)})
	var p := _polity("p", "ca", "lawful", Vector2i(5, 5))
	p["hexes"] = _fake_hexes(5)
	p["collapse_risk_tick"] = 0.0
	var q := _polity("q", "cq", "chaotic", Vector2i(0, 0))
	q["hexes"] = [Vector2i(0, 0)]
	q["collapse_risk_tick"] = 0.0
	sim._resolve_contest(p, q, Vector2i(0, 0), 0)
	check(float(p["collapse_risk_tick"]) > 0.0, "a failed contest adds attrition to the attacker")
	check(float(q["collapse_risk_tick"]) > 0.0, "a failed contest adds attrition to the defender")


# --- Integration -------------------------------------------------------------

func _generate_medium(seed_value: int) -> void:
	_cid = CampaignRepository.create_campaign("Stage4b %d" % seed_value, "w")
	check(SettingGenerator.new().generate(_cid, seed_value, SettingParameters.new()),
		"generate() failed")
	_polities = SettingRepository.list_polities(_cid)
	_hexes_by_qr = {}
	for hex in SettingRepository.list_hexes(_cid):
		_hexes_by_qr[Vector2i(int(hex.q), int(hex.r))] = hex


func test_realms_span_multiple_hexes() -> void:
	# Count owned hexes per polity; the largest realm should span many hexes
	# (expansion turned single-hex seeds into territories).
	var owned := {}
	for key in _hexes_by_qr:
		var o := str(_hexes_by_qr[key].owner_polity_id)
		if o != "":
			owned[o] = int(owned.get(o, 0)) + 1
	var largest := 0
	for o in owned:
		largest = maxi(largest, int(owned[o]))
	check(largest > 5, "the largest realm should span >5 hexes after expansion, got %d" % largest)


func test_multiple_owners_coexist() -> void:
	# In 4b (no collapse yet) expansion fills the reachable land — wilderness
	# re-emerges only when depopulation lands in 4e. The meaningful 4b invariant
	# is that the map partitions among MANY surviving realms, not a single empire.
	var owners := {}
	for key in _hexes_by_qr:
		var o := str(_hexes_by_qr[key].owner_polity_id)
		if o != "":
			owners[o] = true
	check(owners.size() >= 3,
		"expansion should leave several coexisting realms, got %d" % owners.size())


## Owned SETTLED land carries population. req-H titular wilderness claims (owned but
## unpopulated "Siberia" — pop 0, wilderness-class) are the deliberate exception.
func test_owned_hexes_are_populated() -> void:
	for key in _hexes_by_qr:
		var hex = _hexes_by_qr[key]
		if str(hex.owner_polity_id) == "":
			continue
		if str(hex.territory_class) == "wilderness" and int(hex.population_band) == 0:
			continue   # titular wilderness claim — owned empty land, allowed
		check(int(hex.population_band) > 0,
			"owned settled hex %s should have population" % key)


func test_determinism() -> void:
	var cid2 := CampaignRepository.create_campaign("Stage4b Det B", "w")
	check(SettingGenerator.new().generate(cid2, 42, SettingParameters.new()), "second generate failed")
	check(SettingDatasetHasher.compute_world_hash(_cid)
			== SettingDatasetHasher.compute_world_hash(cid2),
		"expansion made the pipeline non-deterministic for the same seed")


# --- Helpers ----------------------------------------------------------------

func _fake_hexes(n: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append(Vector2i(i, 0))
	return out
