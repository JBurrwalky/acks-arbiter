extends "res://tests/test_suite_base.gd"

## Stage 4e — history sim: stability + collapse (§7.5 risk curve, §7.6 outcomes,
## §7.7 fading, §9 epoch bias). Unit tests pin the risk/severity/fade math and
## the rump/shatter/depopulate side effects on a hand-built state; integration
## tests confirm the full pipeline now RESTORES wilderness, emits fallen-polity +
## ruin provenance, and stays deterministic.

var _cid: String = ""
var _polities: Array = []
var _hexes_by_qr: Dictionary = {}


func run_all_tests() -> void:
	# Risk curve (§7.5 / §9 / §7.7)
	test_f_age_curve()
	test_ruler_quality_factor()
	test_collapse_risk_rises_with_tier()
	test_collapse_risk_clamped_and_includes_weariness()
	test_epoch_bias_curve()
	test_epoch_bias_only_demihumans()
	test_fade_factor()
	test_fading_onset_gate()
	# Severity + outcomes (§7.6)
	test_ruin_size_for_tier()
	test_revert_to_wilderness()
	test_do_rump_sheds_frontier()
	test_do_depopulate_emits_provenance()
	test_do_shatter_fragments()
	# Partitioning (§7.4 / shatter)
	test_partition_contiguous()
	test_k_partition_capital_in_group_zero()
	test_internal_vassal_domains_excludes_core()
	# Integration
	_generate_medium(42)
	test_wilderness_returns()
	test_collapse_events_emitted()
	test_fallen_and_ruins_persisted()
	test_dead_polities_excluded_alive_have_fell_tick()
	test_pipeline_determinism()
	print("SettingStage4eTests: all tests passed (%d checks)" % test_count())


# --- Hand-built helpers ------------------------------------------------------

func _instance(culture_id: String, proneness: float = 0.4, end_state: String = "enduring",
		tier: String = "human") -> Dictionary:
	return {
		"culture_id": culture_id, "tier": tier, "race": "human",
		"aggression": 0.5, "defense": 0.5, "size_exponent_bias": 0.0,
		"base_subjugation_vs_genocide": 0.5, "conquest_modifiers": [],
		"peak_strength": 0.5, "collapse_proneness": proneness, "end_state": end_state,
		"seed_biomes": [], "affinity_secondary": [], "avoided": [],
		"sphere_weights": {}, "road_propensity": 0.3, "rigidity": 0.5, "civ_or_clan": "civ",
	}


func _polity(pid: String, culture_id: String, capital: Vector2i, tier: int = 0,
		ruler_quality: String = "average") -> Dictionary:
	return {
		"id": pid, "culture_id": culture_id, "alignment": "lawful",
		"tier_index": tier, "title": "", "ruler_class": "", "ruler_level": 0,
		"ruler_quality": ruler_quality, "capital_q": capital.x, "capital_r": capital.y,
		"liege_id": "", "vassalized_by_war": 0, "founded_tick": 0,
		"fell_tick": null, "fade_onset_tick": null, "civ_or_clan_state": "civ",
		"garrison_coverage": 0.0, "f_overextension": 1.0, "garrison_spent": 0.0,
		"last_income": 0.0, "collapse_risk": 0.0, "collapse_risk_tick": 0.0,
		"alive": true, "hexes": [], "morale_seed": "[]", "internal_vassals": "[]",
		"name": "", "last_expansion_budget": 0, "pillage_credit_pending": 0.0,
		"pillage_credit_active": 0.0, "is_beastman": false,
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
	sim._next_polity_seq = 100
	return sim


func _hex(owner: String, pop: int = 1000) -> Dictionary:
	return {
		"owner_polity_id": owner, "population_band": pop, "land_value": 6,
		"territory_class": "civilized", "biome": "clear", "elevation": "flat",
		"biome_subtype": "", "water": "",
	}


## A horizontal strip of `n` hexes (0,0)..(n-1,0) all owned by `pid`, capital at (0,0).
func _strip_polity(sim: HistorySimulator, pid: String, culture: String, n: int,
		tier: int) -> Dictionary:
	var pol := _polity(pid, culture, Vector2i(0, 0), tier)
	for q in range(n):
		var key := Vector2i(q, 0)
		sim._grid[key] = _hex(pid)
		sim._culture_w[key] = {culture: 1.0}
		sim._alignment_w[key] = {"lawful": 1.0}
		pol["hexes"].append(key)
	sim._polities[pid] = pol
	return pol


# --- Risk curve --------------------------------------------------------------

func test_f_age_curve() -> void:
	var sim := _bare_sim({})
	check(is_equal_approx(sim._f_age(0), 0.4), "f_age at age 0 is the floor 0.4, got %f" % sim._f_age(0))
	check(is_equal_approx(sim._f_age(8), 1.0), "f_age at A_PEAK(8) reaches 1.0, got %f" % sim._f_age(8))
	check(sim._f_age(16) > 1.0, "f_age past the peak rises above 1.0, got %f" % sim._f_age(16))
	check(is_equal_approx(sim._f_age(16), 1.15), "f_age at age 16 is 1+0.15, got %f" % sim._f_age(16))
	check(sim._f_age(10000) <= 2.5 + 0.0001, "f_age is capped at 2.5, got %f" % sim._f_age(10000))


func test_ruler_quality_factor() -> void:
	var sim := _bare_sim({})
	check(is_equal_approx(sim._ruler_quality_factor(_polity("p", "c", Vector2i.ZERO, 0, "strong")), 0.7),
		"strong ruler suppresses risk ×0.7")
	check(is_equal_approx(sim._ruler_quality_factor(_polity("p", "c", Vector2i.ZERO, 0, "weak")), 1.3),
		"weak ruler raises risk ×1.3")
	check(is_equal_approx(sim._ruler_quality_factor(_polity("p", "c", Vector2i.ZERO, 0, "average")), 1.0),
		"average ruler is neutral ×1.0")


func test_collapse_risk_rises_with_tier() -> void:
	var sim := _bare_sim({"c": _instance("c")})
	# Same realm at County (tier 2, f_size 1.0) vs Empire (tier 6, f_size 1.35^4).
	var county := _polity("p", "c", Vector2i.ZERO, 2)
	county["founded_tick"] = -20   # mature (age past peak), so f_age is stable
	var empire := _polity("q", "c", Vector2i.ZERO, 6)
	empire["founded_tick"] = -20
	var r_county := sim._collapse_risk(county, 0)
	var r_empire := sim._collapse_risk(empire, 0)
	check(r_empire > r_county, "a larger realm carries higher collapse risk (%f vs %f)" % [r_empire, r_county])


func test_collapse_risk_clamped_and_includes_weariness() -> void:
	var sim := _bare_sim({"c": _instance("c", 0.9)})
	# Force a high BASE so the clamp is exercised regardless of the calibration-
	# tuned default (this test pins the [0, 0.35] ceiling, not the balance).
	sim._c.collapse_base = 0.05
	var pol := _polity("p", "c", Vector2i.ZERO, 6, "weak")
	pol["founded_tick"] = -200      # very old
	pol["f_overextension"] = 3.0    # maximally overextended
	check(sim._collapse_risk(pol, 0) <= 0.35 + 0.0001, "collapse risk is clamped to 0.35")
	check(is_equal_approx(sim._collapse_risk(pol, 0), 0.35),
		"an old, overextended, prone empire pins at the 0.35 ceiling")
	# Weariness adds, but the clamp still holds. Use a fresh constants set so the
	# additive weariness is visible (not already pinned by the high BASE above).
	sim._c.collapse_base = 0.005
	# Weariness adds, but the clamp still holds.
	var calm := _polity("q", "c", Vector2i.ZERO, 2)
	calm["founded_tick"] = -10
	var base := sim._collapse_risk(calm, 0)
	calm["collapse_risk_tick"] = 0.05
	check(sim._collapse_risk(calm, 0) > base, "war/contest weariness adds to the collapse risk")


func test_epoch_bias_curve() -> void:
	var sim := _bare_sim({})
	sim._n_ticks = 160   # start 0.375×160=60, full 0.75×160=120
	check(is_equal_approx(sim._epoch_bias(0), 1.0), "epoch bias is 1.0 in the golden age")
	check(is_equal_approx(sim._epoch_bias(60), 1.0), "epoch bias still 1.0 at the start of decline")
	check(is_equal_approx(sim._epoch_bias(120), 3.0), "epoch bias reaches the 3.0 max at full decline")
	check(is_equal_approx(sim._epoch_bias(160), 3.0), "epoch bias is held at the max after full decline")
	check(sim._epoch_bias(90) > 1.0 and sim._epoch_bias(90) < 3.0, "epoch bias ramps mid-decline")


func test_epoch_bias_only_demihumans() -> void:
	var sim := _bare_sim({
		"human": _instance("human", 0.4, "enduring", "human"),
		"elf": _instance("elf", 0.4, "enduring", "demihuman")})
	sim._n_ticks = 160
	var human := _polity("h", "human", Vector2i.ZERO, 4)
	human["founded_tick"] = -20
	var elf := _polity("e", "elf", Vector2i.ZERO, 4)
	elf["founded_tick"] = -20
	# At deep decline (tick 130, epoch bias 3.0) the demihuman risk is multiplied,
	# the human's is not.
	var r_human := sim._collapse_risk(human, 130)
	var r_elf := sim._collapse_risk(elf, 130)
	check(r_elf > r_human, "epoch bias multiplies demihuman risk only (%f vs %f)" % [r_elf, r_human])


func test_fade_factor() -> void:
	var sim := _bare_sim({})
	var pol := _polity("p", "c", Vector2i.ZERO)
	check(is_equal_approx(sim._fade_factor(pol, 50), 1.0), "no onset → fade factor 1.0")
	pol["fade_onset_tick"] = 40
	check(is_equal_approx(sim._fade_factor(pol, 40), 1.0), "at onset, fade factor is 1.0")
	check(is_equal_approx(sim._fade_factor(pol, 50), pow(0.985, 10.0)),
		"10 ticks past onset → 0.985^10, got %f" % sim._fade_factor(pol, 50))
	check(sim._fade_factor(pol, 50) < 1.0, "fading degrades the factor below 1.0")


func test_fading_onset_gate() -> void:
	var sim := _bare_sim({
		"fade": _instance("fade", 0.4, "fading", "human"),
		"firm": _instance("firm", 0.4, "enduring", "human")})
	# Fading culture, old enough, Duchy+ → onset opens.
	var p := _polity("p", "fade", Vector2i.ZERO, 3)   # Duchy
	p["founded_tick"] = 0
	sim._maybe_open_fading(p, 20)   # age 20 > A_PEAK 8
	check(int(p["fade_onset_tick"]) == 20, "a risen fading-culture realm opens fading onset")
	# Non-fading culture never opens.
	var q := _polity("q", "firm", Vector2i.ZERO, 3)
	sim._maybe_open_fading(q, 20)
	check(q["fade_onset_tick"] == null, "a non-fading culture never opens fading")
	# Fading culture that is too low-tier does not open.
	var r := _polity("r", "fade", Vector2i.ZERO, 1)   # March (< Duchy)
	sim._maybe_open_fading(r, 20)
	check(r["fade_onset_tick"] == null, "a fading culture below Duchy does not open onset")


# --- Severity + outcomes -----------------------------------------------------

func test_ruin_size_for_tier() -> void:
	var sim := _bare_sim({})
	check(sim._ruin_size_for_tier(0) == "lair", "Barony ruin is a lair")
	check(sim._ruin_size_for_tier(2) == "small", "County ruin is small")
	check(sim._ruin_size_for_tier(4) == "medium", "Principality ruin is medium")
	check(sim._ruin_size_for_tier(6) == "large", "Empire ruin is large")


func test_revert_to_wilderness() -> void:
	var sim := _bare_sim({})
	sim._grid = {Vector2i(0, 0): _hex("p", 1000)}
	sim._revert_to_wilderness(Vector2i(0, 0), 5, 0.1, true)
	var hex: Dictionary = sim._grid[Vector2i(0, 0)]
	check(str(hex["owner_polity_id"]) == "", "reverted hex is unowned")
	check(str(hex["territory_class"]) == "wilderness", "reverted hex is wilderness")
	check(int(hex["population_band"]) == 100, "depopulate keeps 10% (100 of 1000), got %d" % hex["population_band"])
	check(sim._depopulated_at.has(Vector2i(0, 0)), "depopulated hex is marked for 4f beastman repopulation")


func test_do_rump_sheds_frontier() -> void:
	var sim := _bare_sim({"c": _instance("c")})
	var pol := _strip_polity(sim, "p", "c", 6, 2)   # hexes (0,0)..(5,0), capital (0,0)
	sim._do_rump(pol, 5)
	check(pol["hexes"].size() == 3, "rump sheds half of 6 hexes, keeping 3, got %d" % pol["hexes"].size())
	check(Vector2i(0, 0) in pol["hexes"], "rump keeps the capital hex")
	check(not (Vector2i(5, 0) in pol["hexes"]), "rump sheds the farthest hex")
	check(str(sim._grid[Vector2i(5, 0)]["owner_polity_id"]) == "", "a shed hex becomes unowned wilderness")
	check(bool(pol["alive"]), "a rumped realm survives")


func test_do_depopulate_emits_provenance() -> void:
	var sim := _bare_sim({"c": _instance("c")})
	var pol := _strip_polity(sim, "p", "c", 4, 3)
	sim._do_depopulate(pol, 7)
	check(not bool(pol["alive"]), "a depopulated realm is dead")
	check(int(pol["fell_tick"]) == 7, "depopulation records fell_tick")
	check(pol["hexes"].is_empty(), "a depopulated realm holds no hexes")
	check(str(sim._grid[Vector2i(2, 0)]["owner_polity_id"]) == "", "depopulated hexes revert to wilderness")
	check(sim._ruin_seeds.size() == 1, "depopulation emits a ruin seed, got %d" % sim._ruin_seeds.size())
	check(str(sim._ruin_seeds[0]["provenance_polity_id"]) == "p", "ruin carries the fallen polity's provenance")
	check(sim._fallen_polities.size() == 1, "depopulation emits a fallen-polity heartland record")


func test_do_shatter_fragments() -> void:
	var sim := _bare_sim({"c": _instance("c")})
	var pol := _strip_polity(sim, "p", "c", 9, 3)   # Duchy, 9 hexes
	var successors: Array = []
	sim._do_shatter(pol, 11, successors)
	check(successors.size() >= 1, "shatter spawns ≥1 successor, got %d" % successors.size())
	check(pol["hexes"].size() < 9, "the shattered parent keeps only its rump, has %d" % pol["hexes"].size())
	# Every original hex is still owned (by parent or a successor); none lost.
	var owned := 0
	for q in range(9):
		if str(sim._grid[Vector2i(q, 0)]["owner_polity_id"]) != "":
			owned += 1
	check(owned == 9, "shatter conserves territory — all 9 hexes still owned, got %d" % owned)
	for s in successors:
		check(int(s["founded_tick"]) == 11, "a successor founds at the shatter tick (ascendancy resets)")
		check(Vector2i(int(s["capital_q"]), int(s["capital_r"])) in s["hexes"],
			"a successor's capital lies in its own territory")


# --- Partitioning ------------------------------------------------------------

func test_partition_contiguous() -> void:
	var sim := _bare_sim({})
	var hexes: Array = []
	for q in range(7):
		hexes.append(Vector2i(q, 0))
	var groups := sim._partition_contiguous(hexes, 3)
	# 7 hexes / size 3 → 3 groups (3,3,1). Every hex appears once.
	var total := 0
	var seen := {}
	for g in groups:
		check(g.size() <= 3, "no contiguous group exceeds the size cap")
		for h in g:
			seen[h] = true
			total += 1
	check(total == 7, "partition covers all 7 hexes, got %d" % total)
	check(seen.size() == 7, "partition assigns each hex exactly once")


func test_k_partition_capital_in_group_zero() -> void:
	var sim := _bare_sim({})
	var hexes: Array = []
	for q in range(8):
		hexes.append(Vector2i(q, 0))
	var part := sim._k_partition(hexes, Vector2i(0, 0), 3)
	check(int(part["capital_group"]) == 0, "the capital's group index is 0")
	var groups: Array = part["groups"]
	check(groups.size() == 3, "k_partition makes K=3 groups, got %d" % groups.size())
	check(Vector2i(0, 0) in groups[0], "the capital hex lands in group 0")
	var total := 0
	for g in groups:
		total += g.size()
	check(total == 8, "k_partition covers all hexes, got %d" % total)


func test_internal_vassal_domains_excludes_core() -> void:
	var sim := _bare_sim({"c": _instance("c")})
	var pol := _strip_polity(sim, "p", "c", 9, 0)   # tier 0 → VASSAL_SIZE 3, CORE_MAX 3
	var domains := sim._internal_vassal_domains(pol)
	# 9 hexes − 3 core = 6 remaining → 2 domains of 3.
	check(domains.size() == 2, "9 hexes minus a 3-core → 2 vassal domains, got %d" % domains.size())
	var dom_hexes := 0
	for d in domains:
		dom_hexes += d.size()
	check(dom_hexes == 6, "vassal domains cover the 6 non-core hexes, got %d" % dom_hexes)
	check(sim._vassal_count(pol) == 2, "vassal_count counts the internal domains")


# --- Integration -------------------------------------------------------------

func _generate_medium(seed_value: int) -> void:
	_cid = CampaignRepository.create_campaign("Stage4e %d" % seed_value, "w")
	check(SettingGenerator.new().generate(_cid, seed_value, SettingParameters.new()),
		"generate() failed")
	_polities = SettingRepository.list_polities(_cid)
	_hexes_by_qr = {}
	for hex in SettingRepository.list_hexes(_cid):
		_hexes_by_qr[Vector2i(int(hex.q), int(hex.r))] = hex


func test_wilderness_returns() -> void:
	# The headline of 4e: collapse (rump/depopulate) reverts territory to
	# wilderness, so the present-day map is NOT fully partitioned — unowned land
	# coexists with realms (the ~50% wilderness target becomes reachable).
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
	check(unowned_land > 0, "collapse should leave unowned wilderness; got %d unowned of %d land"
		% [unowned_land, owned_land + unowned_land])


func test_collapse_events_emitted() -> void:
	var events := SettingRepository.list_events(_cid)
	var collapse_family := 0
	for e in events:
		if str(e.type) in ["collapse_rump", "collapse_shatter", "depopulation"]:
			collapse_family += 1
	check(collapse_family > 0, "expected collapse-family events over 160 ticks, got %d" % collapse_family)


func test_fallen_and_ruins_persisted() -> void:
	# Depopulation seeds the dungeon/ruin provenance the deep map is built from.
	var fallen := SettingRepository.list_fallen_polities(_cid)
	var ruins := SettingRepository.list_ruin_seeds(_cid)
	check(ruins.size() > 0, "depopulation should persist ruin seeds, got %d" % ruins.size())
	check(fallen.size() > 0, "depopulation should persist fallen-polity records, got %d" % fallen.size())
	var provenance_count := 0
	for r in ruins:
		check(str(r.size_hint) in ["lair", "small", "medium", "large"], "ruin size_hint is valid")
		# Sim-emitted ruins carry provenance; Layer-6 §9.3 geometric dungeon
		# top-ups legitimately do not. Assert provenance only for the sim ones.
		if str(r.event_type) != "geometric":
			check(str(r.provenance_culture_id) != "", "sim ruin carries a provenance culture")
			provenance_count += 1
	check(provenance_count > 0, "depopulation persisted at least one provenance ruin")


func test_dead_polities_excluded_alive_have_fell_tick() -> void:
	# Present-day polities are the survivors; none should carry a fell_tick.
	for p in _polities:
		check(p.fell_tick == null, "a persisted (alive) polity %s must not have a fell_tick" % p.id)


func test_pipeline_determinism() -> void:
	check(SettingDatasetHasher.compute_world_hash(_cid)
			== SettingWorldFixture.reference_world_hash(42),
		"collapse made the pipeline non-deterministic for the same seed")
