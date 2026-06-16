extends "res://tests/test_suite_base.gd"

## §7.4b genocide rebellions (history_simulator): ignition, the genocide-block
## halting assimilation + its expiry, the four-band outcome ladder reached through
## the real _apply_rebellion_outcome entry point (break-away / extinction extremes),
## the break-away & extinction handlers, the vassal-host search, and the
## multi-revolt suppression helper. Pure/deterministic — no DB, no full generation.

func run_all_tests() -> void:
	test_genocide_block_halts_assimilation()
	test_block_expires()
	test_ignite_creates_rebellion()
	test_breakaway_spawns_polity()
	test_extinction_wipes_and_migrates()
	test_adjacent_same_culture_realm()
	test_outcome_major_success_breaks_away()
	test_outcome_major_failure_extinguishes()
	test_other_active_rebellions()
	print("SettingRebellionTests: all tests passed (%d checks)" % test_count())


# --- helpers ---------------------------------------------------------------

func _sim() -> HistorySimulator:
	var sim := HistorySimulator.new()
	sim._c = SimConstants.new()
	sim._campaign_seed = 7
	sim._n_ticks = 160
	sim._params = SettingParameters.new()
	sim._culture_instances = {
		"owner": {"base_subjugation_vs_genocide": 0.6, "sphere_weights": {"military": 0.5}, "tier": "human"},
		"subject": {"base_subjugation_vs_genocide": 0.5, "tier": "human"},
	}
	sim._grid = {}
	sim._culture_w = {}
	sim._alignment_w = {}
	sim._polities = {}
	return sim


## hexes: Array of [Vector2i, {culture_id: weight}]. Wires grid/culture/alignment.
func _add_realm(sim: HistorySimulator, pid: String, culture: String, alignment: String,
		hexes: Array) -> Dictionary:
	var pol := {
		"id": pid, "culture_id": culture, "alignment": alignment, "tier_index": 2,
		"capital_q": 0, "capital_r": 0, "garrison_coverage": 0.8, "hexes": [],
		"alive": true, "ruler_quality": "average", "collapse_risk": 0.0,
	}
	for entry in hexes:
		var h: Vector2i = entry[0]
		pol["hexes"].append(h)
		sim._grid[h] = {"owner_polity_id": pid, "population_band": 1000,
			"elevation": "flat", "biome": "clear", "biome_subtype": "", "water": ""}
		sim._culture_w[h] = (entry[1] as Dictionary).duplicate()
		sim._alignment_w[h] = {alignment: 1.0}
	sim._polities[pid] = pol
	return pol


# --- tests -----------------------------------------------------------------

func test_genocide_block_halts_assimilation() -> void:
	var sim := _sim()
	var h := Vector2i(0, 0)
	_add_realm(sim, "R", "owner", "neutral", [[h, {"owner": 0.5, "subject": 0.5}]])
	sim._genocide_block[h] = {"sovereign": "R", "until_tick": 10}
	sim._assimilate_held_hexes(5)
	check(abs(float(sim._culture_w[h]["owner"]) - 0.5) < 0.0001,
		"an active genocide block halts the sovereign's assimilation")
	sim._assimilate_held_hexes(11)   # past the block
	check(float(sim._culture_w[h]["owner"]) > 0.5,
		"once the block lapses, assimilation resumes")


func test_block_expires() -> void:
	var sim := _sim()
	sim._genocide_block[Vector2i(0, 0)] = {"sovereign": "R", "until_tick": 3}
	sim._genocide_block[Vector2i(1, 0)] = {"sovereign": "R", "until_tick": 10}
	sim._expire_genocide_blocks(5)
	check(not sim._genocide_block.has(Vector2i(0, 0)), "block past its tick is dropped")
	check(sim._genocide_block.has(Vector2i(1, 0)), "still-live block is kept")


func test_ignite_creates_rebellion() -> void:
	var sim := _sim()
	sim._c.rebellion_base = 1.0   # force ignition
	_add_realm(sim, "R", "owner", "neutral", [[Vector2i(0, 0), {"owner": 0.5, "subject": 0.5}]])
	sim._ignite_rebellions(1)
	check(sim._active_rebellions.size() == 1, "a subject culture ≥ floor ignites one revolt")
	check(str(sim._active_rebellions[0]["culture_id"]) == "subject", "the revolt is by the subject culture")
	sim._ignite_rebellions(2)
	check(sim._active_rebellions.size() == 1, "no duplicate revolt for the same realm+culture")


func test_breakaway_spawns_polity() -> void:
	var sim := _sim()
	var h := Vector2i(0, 0)
	var r := _add_realm(sim, "R", "owner", "neutral",
		[[Vector2i(5, 5), {"owner": 1.0}], [h, {"owner": 0.4, "subject": 0.6}]])
	sim._rebellion_breakaway(r, "subject", [h], "neutral", 1)
	var newowner := str(sim._grid[h]["owner_polity_id"])
	check(newowner != "R" and newowner != "", "the rebel hex passes to a new realm")
	check(str(sim._polities[newowner]["culture_id"]) == "subject", "the new realm is of the subject culture")
	check(not r["hexes"].has(h), "the oppressor loses the rebel hex")
	check(r["hexes"].has(Vector2i(5, 5)), "the oppressor keeps its homeland")


func test_extinction_wipes_and_migrates() -> void:
	var sim := _sim()
	var h := Vector2i(0, 0)
	var r := _add_realm(sim, "R", "owner", "neutral", [[h, {"owner": 0.4, "subject": 0.6}]])
	sim._rebellion_extinction(r, "subject", [h], "neutral", h, 1)
	check(float(sim._culture_w[h].get("subject", 1.0)) < 0.01, "subject culture crushed near the floor")
	check(sim._bands.size() == 1, "the survivors flee as a diaspora band")
	check(str(sim._bands[0]["culture_id"]) == "subject", "the band carries the subject culture")


func test_adjacent_same_culture_realm() -> void:
	var sim := _sim()
	_add_realm(sim, "R", "owner", "neutral", [[Vector2i(0, 0), {"owner": 0.4, "subject": 0.6}]])
	_add_realm(sim, "K", "subject", "neutral", [[Vector2i(1, 0), {"subject": 1.0}]])
	check(sim._adjacent_same_culture_realm([Vector2i(0, 0)], "subject", "NEW") == "K",
		"finds the adjacent same-culture realm to host the breakaway as a vassal")


func test_outcome_major_success_breaks_away() -> void:
	var sim := _sim()
	sim._c.rebellion_margin_jitter = 0.0
	sim._c.rebel_band_major_success = 0.5   # pin the band; suppression_base is a tuned knob
	sim._culture_instances["owner"]["sphere_weights"] = {"military": 0.0}
	var r := _add_realm(sim, "R", "owner", "neutral",
		[[Vector2i(5, 5), {"owner": 1.0}], [Vector2i(0, 0), {"owner": 0.05, "subject": 0.95}]])
	r["ruler_quality"] = "weak"
	var before := sim._polities.size()
	sim._apply_rebellion_outcome(r, "subject", [Vector2i(0, 0)], 1)
	check(sim._polities.size() == before + 1, "an overwhelming revolt (v ≥ 0.75) breaks a new realm away")
	check(str(sim._grid[Vector2i(0, 0)]["owner_polity_id"]) != "R", "the rebel hex left the oppressor")


func test_outcome_major_failure_extinguishes() -> void:
	var sim := _sim()
	sim._c.rebellion_margin_jitter = 0.0
	sim._c.rebel_band_mod_failure = 0.5   # pin the band; anything below → extinction
	sim._culture_instances["owner"]["sphere_weights"] = {"military": 0.6}
	var r := _add_realm(sim, "R", "owner", "neutral", [[Vector2i(0, 0), {"owner": 0.7, "subject": 0.3}]])
	r["ruler_quality"] = "strong"
	sim._apply_rebellion_outcome(r, "subject", [Vector2i(0, 0)], 1)
	check(float(sim._culture_w[Vector2i(0, 0)].get("subject", 1.0)) < 0.05,
		"a hopeless revolt (v < 0.30) ends in the subject culture's extinction")


func test_other_active_rebellions() -> void:
	var sim := _sim()
	sim._active_rebellions = [
		{"realm_id": "R", "culture_id": "a"}, {"realm_id": "R", "culture_id": "b"},
		{"realm_id": "K", "culture_id": "c"}]
	check(sim._other_active_rebellions("R") == 1, "R has 2 revolts → 1 other distracts its suppression")
	check(sim._other_active_rebellions("K") == 0, "K has 1 revolt → 0 others")
