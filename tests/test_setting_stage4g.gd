extends "res://tests/test_suite_base.gd"

## Stage 4g — history sim: present-day handoff (§12) + event significance
## (§11.3), plus the corrected §12.1 stronghold values. Unit tests pin the
## ruler-class draw, morale-seed math, and significance scoring; integration
## tests confirm the persisted present-day polities carry ruler level/class +
## morale and the event log is scored, deterministically.

var _cid: String = ""
var _polities: Array = []
var _events: Array = []


func run_all_tests() -> void:
	# Corrected §12.1 reference numbers
	test_stronghold_values_corrected()
	test_ruler_level_by_tier()
	# Handoff (§12)
	test_ruler_class_distribution()
	test_alignment_morale_penalty()
	test_dominant_population_alignment()
	test_morale_seed_shape()
	# Significance (§11.3)
	test_significance_ranks_by_type_and_severity()
	test_score_event_significance()
	# Integration
	_generate_medium(42)
	test_polities_have_ruler_level_and_class()
	test_morale_seed_persisted()
	test_events_scored()
	test_pipeline_determinism()
	print("SettingStage4gTests: all tests passed (%d checks)" % test_count())


# --- Helpers -----------------------------------------------------------------

func _bare_sim(instances: Dictionary) -> HistorySimulator:
	var sim := HistorySimulator.new()
	sim._c = SimConstants.new()
	sim._campaign_seed = 1
	sim._n_ticks = 160
	sim._culture_instances = instances
	sim._grid = {}
	sim._culture_w = {}
	sim._alignment_w = {}
	sim._polities = {}
	return sim


func _polity(pid: String, culture: String, alignment: String) -> Dictionary:
	return {
		"id": pid, "culture_id": culture, "alignment": alignment, "tier_index": 2,
		"capital_q": 0, "capital_r": 0, "garrison_coverage": 0.8, "hexes": [], "alive": true,
	}


# --- Corrected §12.1 numbers -------------------------------------------------

func test_stronghold_values_corrected() -> void:
	# The transcription-error fix (2026-06-13): Principality/Duchy/County moved.
	check(DomainTierTable.stronghold_value_for_tier(DomainTierTable.PRINCIPALITY) == 360000,
		"Principality stronghold is the corrected 360,000")
	check(DomainTierTable.stronghold_value_for_tier(DomainTierTable.DUCHY) == 115000,
		"Duchy stronghold is the corrected 115,000")
	check(DomainTierTable.stronghold_value_for_tier(DomainTierTable.COUNTY) == 70000,
		"County stronghold is the corrected 70,000")
	check(DomainTierTable.stronghold_value_for_tier(DomainTierTable.EMPIRE) == 720000,
		"Empire stronghold is unchanged 720,000")
	check(DomainTierTable.stronghold_value_for_tier(DomainTierTable.BARONY) == 22500,
		"Barony stronghold is unchanged 22,500")


func test_ruler_level_by_tier() -> void:
	check(DomainTierTable.ruler_level_for_tier(DomainTierTable.BARONY) == 4, "Baron level 4")
	check(DomainTierTable.ruler_level_for_tier(DomainTierTable.DUCHY) == 9, "Duke level 9")
	check(DomainTierTable.ruler_level_for_tier(DomainTierTable.EMPIRE) == 14, "Emperor level 14")


# --- Handoff (§12) -----------------------------------------------------------

func test_ruler_class_distribution() -> void:
	# §4.3: a flat/absent sphere profile collapses to the martial-leaning base
	# (fighter 0.60); religious spheres tilt the odds toward cleric without setting
	# it. The distribution is pure/deterministic.
	var sim := _bare_sim({
		"flat": {"sphere_weights": {}},
		"holy": {"sphere_weights": {"religious": 1.0}},
	})
	var flat := sim._ruler_class_distribution(_polity("p", "flat", "lawful"))
	check(is_equal_approx(float(flat["fighter"]), 0.60), "flat profile = base distribution (fighter 0.60), got %f" % flat["fighter"])
	check(float(flat["fighter"]) > float(flat["cleric"]), "the base is martial-leaning")
	var holy := sim._ruler_class_distribution(_polity("p", "holy", "lawful"))
	check(float(holy["cleric"]) > float(holy["fighter"]),
		"a religious culture tilts toward cleric rulers (%f vs %f)" % [holy["cleric"], holy["fighter"]])
	check(float(holy["fighter"]) > 0.0, "but sphere weights move the odds, they don't zero out fighter")
	# An instance-less culture (beastman) still draws a valid ACKS progression.
	var sim2 := _bare_sim({})
	check(sim2._ruler_class_for(_polity("p", "none", "chaotic")) in ["fighter", "cleric", "mage", "thief"],
		"an instance-less culture still draws a valid ruler class")


func test_alignment_morale_penalty() -> void:
	var sim := _bare_sim({})
	check(sim._alignment_morale_penalty("lawful", "lawful") == 0, "matching alignment: no penalty")
	check(sim._alignment_morale_penalty("lawful", "neutral") == -1, "neutral vs L/C: −1")
	check(sim._alignment_morale_penalty("neutral", "chaotic") == -1, "neutral vs L/C: −1 (either way)")
	check(sim._alignment_morale_penalty("lawful", "chaotic") == -2, "opposed L↔C: −2")
	check(sim._alignment_morale_penalty("lawful", "") == 0, "no population alignment: no penalty")


func test_dominant_population_alignment() -> void:
	var sim := _bare_sim({})
	var pol := _polity("p", "c", "lawful")
	pol["hexes"] = [Vector2i(0, 0), Vector2i(1, 0)]
	sim._alignment_w = {
		Vector2i(0, 0): {"lawful": 0.2, "chaotic": 0.8},
		Vector2i(1, 0): {"chaotic": 0.9, "neutral": 0.1},
	}
	check(sim._dominant_population_alignment(pol) == "chaotic",
		"the population's dominant alignment aggregates across hexes")


func test_morale_seed_shape() -> void:
	# A lawful ruler over a chaotic, unassimilated population: −2 alignment + the
	# low-assimilation (conversion-in-progress) flag.
	var sim := _bare_sim({})
	var pol := _polity("p", "owner_culture", "lawful")
	pol["hexes"] = [Vector2i(0, 0)]
	pol["garrison_coverage"] = 0.4
	sim._culture_w = {Vector2i(0, 0): {"conquered_culture": 1.0}}   # owner not yet assimilated
	sim._alignment_w = {Vector2i(0, 0): {"chaotic": 1.0}}
	var seed = JSON.parse_string(sim._morale_seed_for(pol))
	check(seed is Dictionary, "morale_seed is a JSON object")
	check(int(seed["alignment_penalty"]) == -2, "lawful ruler over chaotic population → −2")
	check(bool(seed["low_assimilation"]), "an unassimilated conquered province flags low_assimilation")
	check(abs(float(seed["garrison_coverage"]) - 0.4) < 0.001, "morale_seed carries garrison coverage")


# --- Significance (§11.3) ----------------------------------------------------

func test_significance_ranks_by_type_and_severity() -> void:
	var sim := _bare_sim({})
	check(sim._significance_for("depopulation", 0.0) > sim._significance_for("war", 0.0),
		"a depopulation outranks a routine war")
	check(sim._significance_for("war", 1.0) > sim._significance_for("war", 0.0),
		"higher severity raises significance")
	check(is_equal_approx(sim._significance_for("depopulation", 1.0), 1.5),
		"depopulation(sev 1.0) = base 1.0 + 0.5×1.0 = 1.5, got %f" % sim._significance_for("depopulation", 1.0))


func test_score_event_significance() -> void:
	var sim := _bare_sim({})
	sim._events = [
		{"type": "war", "severity": 0.6, "significance": 0.0},
		{"type": "depopulation", "severity": 1.0, "significance": 0.0},
	]
	sim._score_event_significance()
	check(float(sim._events[0]["significance"]) > 0.0, "every event gets a positive significance")
	check(float(sim._events[1]["significance"]) > float(sim._events[0]["significance"]),
		"the depopulation scores above the war")


# --- Integration -------------------------------------------------------------

func _generate_medium(seed_value: int) -> void:
	_cid = CampaignRepository.create_campaign("Stage4g %d" % seed_value, "w")
	check(SettingGenerator.new().generate(_cid, seed_value, SettingParameters.new()),
		"generate() failed")
	_polities = SettingRepository.list_polities(_cid)
	_events = SettingRepository.list_events(_cid)


func test_polities_have_ruler_level_and_class() -> void:
	check(_polities.size() > 0, "no present-day polities")
	for p in _polities:
		check(int(p.ruler_level) >= 4, "polity %s should have a ruler level (≥ Barony's 4), got %d" % [p.id, p.ruler_level])
		check(str(p.ruler_class) in ["fighter", "cleric", "thief", "mage"],
			"polity %s ruler_class should be an ACKS progression, got '%s'" % [p.id, p.ruler_class])


func test_morale_seed_persisted() -> void:
	for p in _polities:
		var seed = JSON.parse_string(str(p.morale_seed))
		check(seed is Dictionary, "polity %s morale_seed should be a JSON object" % p.id)
		check(seed.has("alignment_penalty") and seed.has("low_assimilation"),
			"polity %s morale_seed should carry the §12 morale inputs" % p.id)


func test_events_scored() -> void:
	check(_events.size() > 0, "no events persisted")
	for e in _events:
		check(float(e.significance) > 0.0,
			"event %s (%s) should be scored, got %f" % [e.id, e.type, e.significance])


func test_pipeline_determinism() -> void:
	var cid2 := CampaignRepository.create_campaign("Stage4g Det B", "w")
	check(SettingGenerator.new().generate(cid2, 42, SettingParameters.new()), "second generate failed")
	check(SettingDatasetHasher.compute_world_hash(_cid)
			== SettingDatasetHasher.compute_world_hash(cid2),
		"the handoff/significance pass made the pipeline non-deterministic")
