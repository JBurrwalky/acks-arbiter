extends "res://tests/test_suite_base.gd"

## Stage 4d — history sim: war escalation + realm-scale resolution (§7.3.1),
## vassalage/secession (§7.4), and the §4.4 effective_svg evaluator. Unit tests
## pin the svg modifier math, the outcome dispositions (vassalize/annex/pillage),
## the escalation trigger, and secession on a hand-built state; integration
## tests confirm the full pipeline still partitions among realms, emits a
## coherent vassal chain, and stays deterministic.

var _cid: String = ""
var _polities: Array = []
var _hexes_by_qr: Dictionary = {}


func run_all_tests() -> void:
	# effective_svg (§4.4)
	test_effective_svg_no_modifiers_is_base()
	test_effective_svg_in_seed_biome_sets_genocide()
	test_effective_svg_set_first_match_then_adjust()
	test_alignments_opposed()
	# War factors / escalation
	test_ruler_war_factor()
	test_war_escalation_by_contest_threshold()
	test_capital_reach_by_distance_and_by_halving()
	# Outcome ladder
	test_crushing_annex_dissolves_defender()
	test_crushing_vassalize_keeps_defender()
	test_beastman_crushing_by_victor_alignment()
	test_pillage_reduces_front_pop_and_books_credit()
	test_decisive_deep_raid_takes_front_hexes()
	# Vassalage / secession
	test_assimilation_of()
	test_secession_frees_war_vassal_of_weak_liege()
	test_strong_liege_keeps_its_vassals()
	# Integration
	_generate_medium(42)
	test_pipeline_determinism()
	test_realms_still_coexist()
	test_liege_chain_is_coherent()
	test_war_events_persisted()
	print("SettingStage4dTests: all tests passed (%d checks)" % test_count())


# --- Hand-built helpers ------------------------------------------------------

func _instance(culture_id: String, aggression: float, defense: float,
		svg: float = 0.5, modifiers: Array = [], seed_biomes: Array = [],
		tier: String = "human", civ_or_clan: String = "civ") -> Dictionary:
	return {
		"culture_id": culture_id, "tier": tier, "race": "human",
		"aggression": aggression, "defense": defense, "size_exponent_bias": 0.0,
		"base_subjugation_vs_genocide": svg, "conquest_modifiers": modifiers,
		"peak_strength": 0.5, "collapse_proneness": 0.4, "end_state": "enduring",
		"seed_biomes": seed_biomes, "affinity_secondary": [], "avoided": [],
		"sphere_weights": {}, "road_propensity": 0.3, "rigidity": 0.5,
		"civ_or_clan": civ_or_clan,
	}


func _polity(pid: String, culture_id: String, alignment: String, capital: Vector2i,
		ruler_quality: String = "average") -> Dictionary:
	return {
		"id": pid, "culture_id": culture_id, "alignment": alignment,
		"tier_index": 0, "title": "", "ruler_class": "", "ruler_level": 0,
		"ruler_quality": ruler_quality, "capital_q": capital.x, "capital_r": capital.y,
		"liege_id": "", "vassalized_by_war": 0, "founded_tick": 0,
		"fell_tick": null, "fade_onset_tick": null, "civ_or_clan_state": "civ",
		"garrison_coverage": 0.0, "f_overextension": 1.0, "garrison_spent": 0.0,
		"last_income": 0.0, "collapse_risk": 0.0, "alive": true,
		"collapse_risk_tick": 0.0, "hexes": [], "morale_seed": "[]",
		"internal_vassals": "[]", "name": "", "last_expansion_budget": 0,
		"pillage_credit_pending": 0.0, "pillage_credit_active": 0.0,
	}


func _bare_sim(instances: Dictionary) -> HistorySimulator:
	var sim := HistorySimulator.new()
	sim._c = SimConstants.new()
	sim._campaign_seed = 1
	sim._n_ticks = 160
	sim._culture_instances = instances
	sim._grid = {}
	sim._culture_w = {}
	sim._alignment_w = {}
	return sim


func _hex(owner: String, pop: int = 500, biome: String = "clear") -> Dictionary:
	return {
		"owner_polity_id": owner, "population_band": pop, "land_value": 6,
		"territory_class": "wilderness", "biome": biome, "elevation": "flat",
		"biome_subtype": "", "water": "",
	}


# --- effective_svg (§4.4) ----------------------------------------------------

func test_effective_svg_no_modifiers_is_base() -> void:
	var sim := _bare_sim({"c": _instance("c", 0.5, 0.5, 0.4, [])})
	var p := _polity("p", "c", "lawful", Vector2i(0, 0))
	var q := _polity("q", "c", "chaotic", Vector2i(0, 0))
	sim._grid = {Vector2i(0, 0): _hex("q")}
	check(is_equal_approx(sim._effective_svg(p, q), 0.4),
		"no modifiers → base svg 0.4, got %f" % sim._effective_svg(p, q))


func test_effective_svg_in_seed_biome_sets_genocide() -> void:
	# A demihuman-style culture: in its forest seed biome → set 0.9 (genocide);
	# outside it the base 0.2 (vassalize) stands.
	var mods := [{"when": "target_in_my_seed_biome", "set": 0.9}]
	var sim := _bare_sim({"elf": _instance("elf", 0.7, 0.7, 0.2, mods, ["forest"], "demihuman")})
	var p := _polity("p", "elf", "lawful", Vector2i(0, 0))
	var q_in := _polity("q", "human", "lawful", Vector2i(0, 0))
	var q_out := _polity("q2", "human", "lawful", Vector2i(1, 0))
	sim._grid = {
		Vector2i(0, 0): _hex("q", 500, "woods"),    # forest seed biome
		Vector2i(1, 0): _hex("q2", 500, "clear"),   # neutral
	}
	check(is_equal_approx(sim._effective_svg(p, q_in), 0.9),
		"target in seed biome → svg set to 0.9, got %f" % sim._effective_svg(p, q_in))
	check(is_equal_approx(sim._effective_svg(p, q_out), 0.2),
		"target outside seed biome → base 0.2, got %f" % sim._effective_svg(p, q_out))


func test_effective_svg_set_first_match_then_adjust() -> void:
	# set 1.0 for demihuman target, then adjust −0.2 for same alignment → 0.8.
	var mods := [
		{"when": "target_is_demihuman", "set": 1.0},
		{"when": "target_same_alignment", "adjust": -0.2},
	]
	var sim := _bare_sim({
		"elf": _instance("elf", 0.7, 0.7, 0.2, mods, [], "demihuman"),
		"dwarf": _instance("dwarf", 0.6, 0.7, 0.5, [], [], "demihuman"),
	})
	var p := _polity("p", "elf", "lawful", Vector2i(0, 0))
	var q := _polity("q", "dwarf", "lawful", Vector2i(0, 0))  # demihuman + same alignment
	sim._grid = {Vector2i(0, 0): _hex("q")}
	check(is_equal_approx(sim._effective_svg(p, q), 0.8),
		"set 1.0 then adjust −0.2 → 0.8, got %f" % sim._effective_svg(p, q))


func test_alignments_opposed() -> void:
	var sim := _bare_sim({})
	check(sim._alignments_opposed("lawful", "chaotic"), "law vs chaos is opposed")
	check(sim._alignments_opposed("chaotic", "lawful"), "chaos vs law is opposed")
	check(not sim._alignments_opposed("lawful", "neutral"), "law vs neutral not opposed")
	check(not sim._alignments_opposed("neutral", "chaotic"), "neutral vs chaos not opposed")
	check(not sim._alignments_opposed("lawful", "lawful"), "same alignment not opposed")


# --- War factors / escalation ------------------------------------------------

func test_ruler_war_factor() -> void:
	var sim := _bare_sim({})
	check(is_equal_approx(sim._ruler_war(_polity("p", "c", "lawful", Vector2i.ZERO, "strong")), 1.15),
		"strong ruler war ×1.15")
	check(is_equal_approx(sim._ruler_war(_polity("p", "c", "lawful", Vector2i.ZERO, "average")), 1.0),
		"average ruler war ×1.0")
	check(is_equal_approx(sim._ruler_war(_polity("p", "c", "lawful", Vector2i.ZERO, "weak")), 0.85),
		"weak ruler war ×0.85")


func test_war_escalation_by_contest_threshold() -> void:
	# ≥ WAR_THRESHOLD (3) directed contests escalates; the side with more is the
	# attacker. pa directed 3 at pb, pb directed 0 → pa attacks.
	var sim := _bare_sim({
		"ca": _instance("ca", 0.6, 0.5), "cb": _instance("cb", 0.5, 0.5)})
	sim._polities = {
		"pa": _polity("pa", "ca", "lawful", Vector2i(0, 0)),
		"pb": _polity("pb", "cb", "lawful", Vector2i(5, 0)),
	}
	sim._contest_counts = {"pa>pb": 3}
	check(sim._war_attacker("pa", "pb", 0) == "pa",
		"3 directed contests pa→pb should make pa the attacker")
	# Below threshold and (with this seed) no escalation roll fires.
	sim._contest_counts = {"pa>pb": 1}
	# Not asserting the seeded roll outcome here; just that the threshold path is
	# the only deterministic trigger — covered above.


func test_capital_reach_by_distance_and_by_halving() -> void:
	var sim := _bare_sim({})
	var q := _polity("q", "c", "lawful", Vector2i(0, 0))
	q["hexes"] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	sim._tick_start_size = {"q": 4}
	# Front adjacent to the capital → reachable.
	check(sim._capital_reach(q, [Vector2i(1, 0)]), "front within CAPITAL_REACH of capital is reachable")
	# Distant front, realm intact → not reachable.
	check(not sim._capital_reach(q, [Vector2i(9, 0)]),
		"distant front with an intact realm is not within reach")
	# Distant front but the realm is already cut below half pre-war size → reach.
	q["hexes"] = [Vector2i(0, 0)]   # 1 of 4 left
	check(sim._capital_reach(q, [Vector2i(9, 0)]),
		"a realm cut below half its pre-war size is reachable regardless of distance")


# --- Outcome ladder ----------------------------------------------------------

func _two_realm_sim(svg_p: float, p_mods: Array = [], p_clan: bool = false,
		p_aggr: float = 0.5) -> HistorySimulator:
	var pi := _instance("ca", p_aggr, 0.5, svg_p, p_mods, [], "human",
		"clan" if p_clan else "civ")
	var sim := _bare_sim({"ca": pi, "cq": _instance("cq", 0.5, 0.5)})
	sim._ordered_keys = []
	for q in range(4):
		var key := Vector2i(q, 0)
		sim._ordered_keys.append(key)
		var owner := "p" if q == 0 else "q"
		sim._grid[key] = _hex(owner)
		sim._culture_w[key] = {("ca" if q == 0 else "cq"): 1.0}
		sim._alignment_w[key] = {"lawful": 1.0}
	var p := _polity("p", "ca", "lawful", Vector2i(0, 0))
	p["hexes"] = [Vector2i(0, 0)]
	var q := _polity("q", "cq", "lawful", Vector2i(3, 0))
	q["hexes"] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	sim._polities = {"p": p, "q": q}
	return sim


func test_crushing_annex_dissolves_defender() -> void:
	# High svg (≥0.65) → annexation: Q dissolves, its hexes join P.
	var sim := _two_realm_sim(0.8)
	var p: Dictionary = sim._polities["p"]
	var q: Dictionary = sim._polities["q"]
	sim._resolve_crushing(p, q, [Vector2i(1, 0)], 5)
	check(not bool(q["alive"]), "annexed defender should be dead")
	check(int(q["fell_tick"]) == 5, "annexed defender records fell_tick")
	check(p["hexes"].size() == 4, "attacker should absorb all of the defender's hexes, has %d" % p["hexes"].size())
	check(str(sim._grid[Vector2i(2, 0)]["owner_polity_id"]) == "p",
		"a former defender hex should now be owned by the attacker")


func test_crushing_vassalize_keeps_defender() -> void:
	# Low svg (≤0.35) → wholesale vassalization: Q survives as P's vassal.
	var sim := _two_realm_sim(0.2)
	var p: Dictionary = sim._polities["p"]
	var q: Dictionary = sim._polities["q"]
	sim._resolve_crushing(p, q, [Vector2i(1, 0)], 5)
	check(bool(q["alive"]), "vassalized defender stays alive")
	check(str(q["liege_id"]) == "p", "vassalized defender's liege should be the attacker")
	check(int(q["vassalized_by_war"]) == 1, "vassalized_by_war flag should be set")
	check(q["hexes"].size() == 3, "a vassal keeps its hexes, has %d" % q["hexes"].size())


func test_beastman_crushing_by_victor_alignment() -> void:
	# Jedidiah's ruling: a Lawful/Neutral victor DESTROYS a beaten beastman
	# clanhold (annex) regardless of svg; only a Chaotic victor vassalizes it.
	# svg 0.2 would normally vassalize any defender.
	var sim := _two_realm_sim(0.2)
	var ql: Dictionary = sim._polities["q"]
	ql["is_beastman"] = true
	sim._polities["p"]["alignment"] = "lawful"
	sim._resolve_crushing(sim._polities["p"], ql, [Vector2i(1, 0)], 5)
	check(not bool(ql["alive"]), "a lawful victor destroys (annexes) a beastman clanhold despite low svg")

	var sim2 := _two_realm_sim(0.2)
	var qc: Dictionary = sim2._polities["q"]
	qc["is_beastman"] = true
	sim2._polities["p"]["alignment"] = "chaotic"
	sim2._resolve_crushing(sim2._polities["p"], qc, [Vector2i(1, 0)], 5)
	check(bool(qc["alive"]) and str(qc["liege_id"]) == "p",
		"a chaotic victor keeps a beastman clanhold as a vassal")


func test_pillage_reduces_front_pop_and_books_credit() -> void:
	# Raider (aggr≥0.7, clan, svg≤0.3) → pillage override fires on the seeded 50%.
	# Use base_secede-independent path: call _pillage directly to test its effect.
	var sim := _two_realm_sim(0.2, [], true, 0.8)
	var p: Dictionary = sim._polities["p"]
	var q: Dictionary = sim._polities["q"]
	q["last_income"] = 1000.0
	var before := int(sim._grid[Vector2i(1, 0)]["population_band"])
	sim._pillage(p, q, [Vector2i(1, 0), Vector2i(2, 0)], 5)
	check(int(sim._grid[Vector2i(1, 0)]["population_band"]) < before,
		"pillage should reduce front-region population")
	check(str(sim._grid[Vector2i(1, 0)]["owner_polity_id"]) == "q",
		"pillage transfers no territory — front hex stays the defender's")
	check(float(p["pillage_credit_pending"]) > 0.0,
		"the raider books a one-time tribute credit (0.5 × Q income)")
	check(is_equal_approx(float(p["pillage_credit_pending"]), 500.0),
		"credit should be 0.5 × 1000 = 500, got %f" % p["pillage_credit_pending"])


func test_decisive_deep_raid_takes_front_hexes() -> void:
	# Decisive victory, defender has no vassals → deep raid of up to 2×budget.
	var sim := _two_realm_sim(0.5)
	var p: Dictionary = sim._polities["p"]
	var q: Dictionary = sim._polities["q"]
	p["last_expansion_budget"] = 1   # raid = max(2×1, 1) = 2
	sim._resolve_decisive(p, q, [Vector2i(1, 0), Vector2i(2, 0)], 5)
	check(p["hexes"].size() == 3, "deep raid of 2 should give the attacker 3 hexes, has %d" % p["hexes"].size())
	check(q["hexes"].size() == 1, "the defender should retain only its capital hex, has %d" % q["hexes"].size())


# --- Vassalage / secession (§7.4) --------------------------------------------

func test_assimilation_of() -> void:
	var sim := _bare_sim({})
	var pol := _polity("v", "cv", "lawful", Vector2i(0, 0))
	pol["hexes"] = [Vector2i(0, 0), Vector2i(1, 0)]
	sim._culture_w = {
		Vector2i(0, 0): {"liege_c": 0.5, "cv": 0.5},
		Vector2i(1, 0): {"liege_c": 0.1, "cv": 0.9},
	}
	check(is_equal_approx(sim._assimilation_of(pol, "liege_c"), 0.3),
		"avg liege-culture weight across the vassal should be 0.3, got %f"
			% sim._assimilation_of(pol, "liege_c"))


func test_secession_frees_war_vassal_of_weak_liege() -> void:
	# Weak liege + war-vassal + alignment mismatch + zero assimilation → with
	# BASE_SECEDE forced to 1.0, p_secede = 1×(1+1)×(1−0) = 2.0 → always secedes.
	var sim := _bare_sim({
		"cl": _instance("cl", 0.5, 0.5), "cv": _instance("cv", 0.5, 0.5)})
	sim._c.base_secede = 1.0
	var liege := _polity("l", "cl", "lawful", Vector2i(0, 0), "weak")
	liege["hexes"] = [Vector2i(0, 0)]
	var vassal := _polity("v", "cv", "chaotic", Vector2i(2, 0))  # mismatch alignment
	vassal["hexes"] = [Vector2i(2, 0)]
	vassal["liege_id"] = "l"
	vassal["vassalized_by_war"] = 1
	sim._polities = {"l": liege, "v": vassal}
	sim._culture_w = {Vector2i(2, 0): {"cv": 1.0}}   # no liege culture → assim 0
	sim._run_secessions(7, {})
	check(str(vassal["liege_id"]) == "", "a war-vassal of a weak liege should secede")
	check(int(vassal["vassalized_by_war"]) == 0, "secession clears the war-vassal flag")


func test_strong_liege_keeps_its_vassals() -> void:
	# Same setup but a strong liege that didn't lose a war and has low risk →
	# weakness gate fails → no secession even at BASE_SECEDE 1.0.
	var sim := _bare_sim({
		"cl": _instance("cl", 0.5, 0.5), "cv": _instance("cv", 0.5, 0.5)})
	sim._c.base_secede = 1.0
	var liege := _polity("l", "cl", "lawful", Vector2i(0, 0), "strong")
	liege["hexes"] = [Vector2i(0, 0)]
	var vassal := _polity("v", "cv", "chaotic", Vector2i(2, 0))
	vassal["hexes"] = [Vector2i(2, 0)]
	vassal["liege_id"] = "l"
	vassal["vassalized_by_war"] = 1
	sim._polities = {"l": liege, "v": vassal}
	sim._culture_w = {Vector2i(2, 0): {"cv": 1.0}}
	sim._run_secessions(7, {})
	check(str(vassal["liege_id"]) == "l", "a strong, war-winning liege keeps its vassal")


# --- Integration (full pipeline) ---------------------------------------------

func _generate_medium(seed_value: int) -> void:
	_cid = CampaignRepository.create_campaign("Stage4d %d" % seed_value, "w")
	check(SettingGenerator.new().generate(_cid, seed_value, SettingParameters.new()),
		"generate() failed")
	_polities = SettingRepository.list_polities(_cid)
	_hexes_by_qr = {}
	for hex in SettingRepository.list_hexes(_cid):
		_hexes_by_qr[Vector2i(int(hex.q), int(hex.r))] = hex


func test_pipeline_determinism() -> void:
	var cid2 := CampaignRepository.create_campaign("Stage4d Det B", "w")
	check(SettingGenerator.new().generate(cid2, 42, SettingParameters.new()), "second generate failed")
	check(SettingDatasetHasher.compute_world_hash(_cid)
			== SettingDatasetHasher.compute_world_hash(cid2),
		"war/vassalage/secession made the pipeline non-deterministic")


func test_realms_still_coexist() -> void:
	# Wars consolidate (annexation) and re-fragment (secession), but the map must
	# not collapse to a single empire — several realms still own hexes.
	var owners := {}
	for key in _hexes_by_qr:
		var o := str(_hexes_by_qr[key].owner_polity_id)
		if o != "":
			owners[o] = true
	check(owners.size() >= 2, "the map should still partition among ≥2 realms, got %d" % owners.size())


func test_liege_chain_is_coherent() -> void:
	# Every liege_id must reference a polity that is actually present (alive) in
	# the present-day set — no dangling vassal edges after annex/secession.
	var ids := {}
	for p in _polities:
		ids[str(p.id)] = true
	for p in _polities:
		var liege := str(p.liege_id)
		if liege != "":
			check(ids.has(liege),
				"polity %s has liege %s not present in the polity set" % [p.id, liege])
			check(liege != str(p.id), "polity %s cannot be its own liege" % p.id)


func test_war_events_persisted() -> void:
	# The event log is now populated; war-family events should appear and be
	# well-formed (valid type, JSON id/polity arrays).
	var events := SettingRepository.list_events(_cid)
	var war_family := 0
	for e in events:
		var t := str(e.type)
		if t in ["war", "conquest", "vassalage", "secession", "pillage"]:
			war_family += 1
			check(str(e.id).begins_with("evt_"), "event id should be evt_*, got %s" % e.id)
			var pids = JSON.parse_string(str(e.polity_ids))
			check(pids is Array, "event polity_ids should be a JSON array")
	check(war_family > 0, "expected at least one war-family event over 160 ticks, got %d" % war_family)
