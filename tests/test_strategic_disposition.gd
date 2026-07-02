extends "res://tests/test_suite_base.gd"
## StrategicDisposition Phase 0 tests (gdd-ruler-ai.md §4/§10/§12;
## gdd-npc-personality.md §8.2-§8.4).
##
## The golden test is the §8.3 worked example (Lawful baron): military 0.846,
## oppression 0.801, diplomatic 0.078 — the §11.3 reproducibility anchor.
## Pure-math tests run in memory; persistence tests use a fixture campaign in
## the isolated test DB.

const _TOL := 0.0005  # the GDD states the golden values to 3 decimals

var _campaign_id: String = ""


func run_all_tests() -> void:
	_campaign_id = CampaignRepository.create_campaign("StrategicDisposition Tests", "World")

	test_golden_lawful_baron()
	test_baron_remaining_weights()
	test_crisis_response_quadrants()
	test_orthodoxy_term_branches()
	test_null_personality_baseline()
	test_clamp01_floor()
	test_tier_c_unsampled_axes_default()
	test_determinism()
	test_to_dict_from_dict_round_trip()
	test_ruler_profile_view()
	test_db_round_trip()
	test_build_and_persist_for_character()
	test_pc_refused()
	test_backfill_campaign()
	test_seed_relational_dicts()

	if not has_failures():
		print("StrategicDisposition: all tests passed (%d checks)." % test_count())


# ---------------------------------------------------------------------------
# Fixtures / helpers
# ---------------------------------------------------------------------------

## The gdd-npc-personality.md §8.3 worked example: Lawful baron, motivation
## power/security; compassion 2, loyalty 8, orthodoxy 9, self-interest 4,
## curiosity 3, mysticism 3. stress_reactivity is unspecified in the GDD;
## 7 here (volatile) so the §8.4 quadrant is also pinned.
func _baron_personality() -> NpcPersonality:
	var p := NpcPersonality.new()
	p.tier = "B"
	p.axes = {
		"epistemic_curiosity": 3,
		"societal_orthodoxy": 9,
		"affective_compassion": 2,
		"stress_reactivity": 7,
		"self_interest": 4,
		"in_group_loyalty": 8,
		"mysticism": 3,
		"expressiveness": 5,
		"civility": 5,
		"jocularity": 5,
		"amorousness": 5,
		"epicureanism": 5,
	}
	p.motivation_primary = "power"
	p.motivation_secondary = "security"
	return p


func _approx(actual: float, expected: float, label: String, tol: float = _TOL) -> void:
	check(absf(actual - expected) < tol,
		"%s: expected %f got %f (tol %f)" % [label, expected, actual, tol])


func _make_npc(name: String, personality: NpcPersonality, alignment: String,
		character_type: String = "npc") -> String:
	return CampaignRepository.create_character({
		"campaign_id": _campaign_id,
		"name": name,
		"character_type": character_type,
		"persistence_tier": "named",
		"alignment": alignment,
		"personality": personality.to_json() if personality != null else "{}",
	})


# ---------------------------------------------------------------------------
# §8.3 golden + formula tests (pure math)
# ---------------------------------------------------------------------------

func test_golden_lawful_baron() -> void:
	# Passed with the GDD's capitalization to prove alignment normalization.
	var d := StrategicDispositionBuilder.build(_baron_personality(), "Lawful")
	_approx(d.military_weight, 0.846, "golden military_weight")
	_approx(d.oppression_weight, 0.801, "golden oppression_weight")
	_approx(d.diplomatic_weight, 0.078, "golden diplomatic_weight")
	# The axis snapshot and motivations carry through.
	check(d.motivation_primary == "power", "baron motivation_primary")
	check(d.motivation_secondary == "security", "baron motivation_secondary")
	check(d.affective_compassion == 2, "baron compassion snapshot")
	check(d.societal_orthodoxy == 9, "baron orthodoxy snapshot")
	# stress 7 (>=6), self-interest 4 (<=5) -> aggressive (§8.4).
	check(d.crisis_response == "aggressive",
		"baron crisis_response: expected aggressive got %s" % d.crisis_response)


func test_baron_remaining_weights() -> void:
	# Hand-derived from the §8.3 formulas for the same baron (not stated in
	# the GDD's example; derivation: u(3)=2/9, u(4)=1/3, inv(2)=8/9,
	# inv(4)=2/3, mot(power)=0.7, mot(security)=0.3).
	var d := StrategicDispositionBuilder.build(_baron_personality(), "lawful")
	_approx(d.research_weight, 0.10 + 0.45 * (2.0 / 9.0), "baron research_weight")
	_approx(d.religious_weight, 0.08 + 0.50 * (2.0 / 9.0), "baron religious_weight")
	_approx(d.economic_weight, 0.12 + 0.10 * (2.0 / 9.0), "baron economic_weight")
	_approx(d.expansion_weight, 0.08 + 0.28 + 0.20 * (8.0 / 9.0) + 0.15 * (2.0 / 3.0),
		"baron expansion_weight")
	_approx(d.fortification_weight, 0.12 + 0.40 * 0.3, "baron fortification_weight")
	for k in StrategicDisposition.WEIGHT_KEYS:
		var v: float = float(d.weights()[k])
		check(v >= 0.0 and v <= 1.0, "%s in [0,1], got %f" % [k, v])


func test_crisis_response_quadrants() -> void:
	# §8.4: split at the 5/6 boundary on both axes.
	var cases := [
		[6, 5, "aggressive"],   # volatile + opportunistic -> lashes out
		[6, 6, "cautious"],     # volatile + principled -> over-prepares
		[5, 5, "diplomatic"],   # calm + opportunistic -> negotiates
		[5, 6, "defensive"],    # calm + principled -> holds the line
		[10, 1, "aggressive"],
		[1, 10, "defensive"],
	]
	for c in cases:
		var p := NpcPersonality.new()
		p.axes = {"stress_reactivity": c[0], "self_interest": c[1]}
		var d := StrategicDispositionBuilder.build(p, "neutral")
		check(d.crisis_response == c[2],
			"crisis(stress=%d, self=%d): expected %s got %s" % [c[0], c[1], c[2], d.crisis_response])


func test_orthodoxy_term_branches() -> void:
	# Same baron under each alignment; only the orthodoxy_term changes.
	# lawful: u(9)=8/9 -> 0.801 (golden). chaotic: inv(9)=1/9.
	# neutral: abs((9-5.5)/4.5)=7/9. Unknown alignment normalizes to neutral.
	var p := _baron_personality()
	var chaotic := StrategicDispositionBuilder.build(p, "chaotic")
	_approx(chaotic.oppression_weight,
		0.08 + 0.40 * (8.0 / 9.0) + 0.25 * (1.0 / 9.0) + 0.21 - 0.20 * (1.0 / 3.0),
		"chaotic oppression_weight")
	var neutral := StrategicDispositionBuilder.build(p, "neutral")
	_approx(neutral.oppression_weight,
		0.08 + 0.40 * (8.0 / 9.0) + 0.25 * (7.0 / 9.0) + 0.21 - 0.20 * (1.0 / 3.0),
		"neutral oppression_weight")
	var unknown := StrategicDispositionBuilder.build(p, "definitely-not-an-alignment")
	_approx(unknown.oppression_weight, neutral.oppression_weight,
		"unknown alignment degrades to neutral")


func test_null_personality_baseline() -> void:
	# Graceful degradation: no personality (e.g. beastman chieftain path) ->
	# every axis reads baseline 5, motivations empty -> mot()=0 everywhere.
	var d := StrategicDispositionBuilder.build(null, "neutral")
	check(d.epistemic_curiosity == 5 and d.mysticism == 5 and d.self_interest == 5,
		"null personality: axes default to baseline 5")
	_approx(d.research_weight, 0.10 + 0.45 * (4.0 / 9.0), "baseline research_weight")
	_approx(d.military_weight, 0.10 + 0.30 * (5.0 / 9.0) + 0.25 * (4.0 / 9.0),
		"baseline military_weight")
	check(d.crisis_response == "diplomatic",
		"baseline crisis_response (5,5): expected diplomatic got %s" % d.crisis_response)
	check(d.aggression_toward.is_empty() and d.alliance_preference.is_empty(),
		"baseline relational dicts empty")


func test_clamp01_floor() -> void:
	# diplomatic_weight goes negative for a callous, incurious opportunist:
	# 0.10 + 0.30*u(1) + 0.25*u(1) - 0.20*inv(1) = 0.10 - 0.20 -> clamped 0.0.
	var p := NpcPersonality.new()
	p.axes = {"self_interest": 1, "epistemic_curiosity": 1, "affective_compassion": 1}
	var d := StrategicDispositionBuilder.build(p, "neutral")
	_approx(d.diplomatic_weight, 0.0, "clamp01 floors diplomatic_weight at 0")


func test_tier_c_unsampled_axes_default() -> void:
	# A Tier C personality with only one sampled strategic axis: unsampled
	# axes read baseline 5 through NpcPersonality.axis().
	var p := NpcPersonality.new()
	p.tier = "C"
	p.axes = {"stress_reactivity": 9}
	p.sampled_axes = ["stress_reactivity"]
	var d := StrategicDispositionBuilder.build(p, "lawful")
	check(d.stress_reactivity == 9, "sampled axis carried")
	check(d.epistemic_curiosity == 5 and d.in_group_loyalty == 5,
		"unsampled axes default to 5")
	# stress 9 (>=6), self-interest 5 (<=5) -> aggressive.
	check(d.crisis_response == "aggressive",
		"tier C crisis_response: expected aggressive got %s" % d.crisis_response)


func test_determinism() -> void:
	var a := StrategicDispositionBuilder.build(_baron_personality(), "lawful")
	var b := StrategicDispositionBuilder.build(_baron_personality(), "lawful")
	check(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()),
		"identical inputs -> identical disposition")


# ---------------------------------------------------------------------------
# Struct round-trips + the RulerProfile view
# ---------------------------------------------------------------------------

func test_to_dict_from_dict_round_trip() -> void:
	var d := StrategicDispositionBuilder.build(_baron_personality(), "lawful")
	d.aggression_toward = {"realm_a": 0.8}
	d.alliance_preference = {"realm_b": 0.25}
	var back := StrategicDisposition.from_dict(d.to_dict())
	check(JSON.stringify(back.to_dict()) == JSON.stringify(d.to_dict()),
		"to_dict/from_dict round-trip is lossless")
	# from_dict also accepts the DB row shape (JSON strings for the dicts).
	var row_shape: Dictionary = d.to_dict()
	row_shape["aggression_toward"] = JSON.stringify(d.aggression_toward)
	row_shape["alliance_preference"] = JSON.stringify(d.alliance_preference)
	var from_row := StrategicDisposition.from_dict(row_shape)
	check(JSON.stringify(from_row.to_dict()) == JSON.stringify(d.to_dict()),
		"from_dict parses serialized relational dicts")
	# Malformed crisis_response degrades to the default.
	var bad: Dictionary = d.to_dict()
	bad["crisis_response"] = "panicked"
	check(StrategicDisposition.from_dict(bad).crisis_response == "defensive",
		"invalid crisis_response degrades to 'defensive'")


func test_ruler_profile_view() -> void:
	var d := StrategicDispositionBuilder.build(_baron_personality(), "lawful")
	d.aggression_toward = {"realm_a": 0.8}
	var profile := d.to_profile()
	_approx(profile.military_weight, d.military_weight, "profile military_weight")
	_approx(profile.oppression_weight, d.oppression_weight, "profile oppression_weight")
	check(profile.crisis_response == d.crisis_response, "profile crisis_response")
	check(float(profile.aggression_toward.get("realm_a", 0.0)) == 0.8,
		"profile carries relational dicts")
	# The view holds copies — mutating it must not touch the disposition.
	profile.aggression_toward["realm_x"] = 1.0
	check(not d.aggression_toward.has("realm_x"), "profile dicts are duplicated")


# ---------------------------------------------------------------------------
# Persistence (fixture campaign in the isolated test DB)
# ---------------------------------------------------------------------------

func test_db_round_trip() -> void:
	var d := StrategicDispositionBuilder.build(_baron_personality(), "lawful")
	d.aggression_toward = {"realm_a": 0.8, "realm_b": 0.5}
	d.alliance_preference = {"realm_c": 0.3}
	var cid := _make_npc("RT Baron", _baron_personality(), "lawful")
	check(not cid.is_empty(), "fixture character created")
	check(RulerDispositionRepository.save_disposition(_campaign_id, cid, d),
		"save_disposition succeeds")
	check(RulerDispositionRepository.has_disposition(cid), "has_disposition true after save")
	var back := RulerDispositionRepository.get_disposition(cid)
	check(back != null, "get_disposition returns a row")
	if back != null:
		check(JSON.stringify(back.to_dict()) == JSON.stringify(d.to_dict()),
			"DB round-trip is lossless (weights, axes, motivations, dicts)")
	# Upsert: saving again with a changed weight replaces, not duplicates.
	d.military_weight = 0.5
	check(RulerDispositionRepository.save_disposition(_campaign_id, cid, d),
		"second save (upsert) succeeds")
	var again := RulerDispositionRepository.get_disposition(cid)
	if again != null:
		_approx(again.military_weight, 0.5, "upsert replaced the row")
	check(RulerDispositionRepository.list_ruler_ids_for_campaign(_campaign_id).has(cid),
		"list_ruler_ids_for_campaign includes the ruler")
	check(RulerDispositionRepository.delete_disposition(cid), "delete_disposition succeeds")
	check(not RulerDispositionRepository.has_disposition(cid),
		"has_disposition false after delete")
	check(RulerDispositionRepository.get_disposition(cid) == null,
		"get_disposition null after delete")


func test_build_and_persist_for_character() -> void:
	var p := _baron_personality()
	var cid := _make_npc("Persist Baron", p, "lawful")
	var d := StrategicDispositionBuilder.build_and_persist_for_character(cid)
	check(d != null, "build_and_persist_for_character returns a disposition")
	var stored := RulerDispositionRepository.get_disposition(cid)
	check(stored != null, "disposition row persisted")
	if d != null and stored != null:
		_approx(stored.military_weight, 0.846, "persisted golden military_weight")
		check(JSON.stringify(stored.to_dict()) == JSON.stringify(d.to_dict()),
			"returned and persisted dispositions match")
	# A character with NO personality JSON degrades to the neutral baseline.
	var bare := _make_npc("Bare Chieftain", null, "chaotic")
	var bare_d := StrategicDispositionBuilder.build_and_persist_for_character(bare)
	check(bare_d != null, "no-personality character still gets a disposition")
	if bare_d != null:
		check(bare_d.affective_compassion == 5, "no-personality axes default to baseline")


func test_pc_refused() -> void:
	var cid := _make_npc("Player Baron", _baron_personality(), "lawful", "pc")
	var d := StrategicDispositionBuilder.build_and_persist_for_character(cid)
	check(d == null, "PC is refused")
	check(not RulerDispositionRepository.has_disposition(cid), "no row written for PC")


func test_backfill_campaign() -> void:
	# Isolated campaign so counts are exact.
	var camp := CampaignRepository.create_campaign("Disposition Backfill", "World")
	var save_camp := _campaign_id
	_campaign_id = camp
	var ruler_a := _make_npc("Backfill Domain Ruler", _baron_personality(), "lawful")
	var ruler_b := _make_npc("Backfill Realm Head", _baron_personality(), "neutral")
	var pc := _make_npc("Backfill PC", _baron_personality(), "lawful", "pc")
	var bystander := _make_npc("Backfill Bystander", _baron_personality(), "neutral")
	var dead := _make_npc("Backfill Dead Ruler", _baron_personality(), "chaotic")
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET is_dead = 1 WHERE id = ?", [dead])
	_campaign_id = save_camp

	check(not CampaignRepository.create_domain({
		"campaign_id": camp, "name": "Ruled March", "owner_character_id": ruler_a,
	}).is_empty(), "backfill fixture domain A created")
	check(not CampaignRepository.create_domain({
		"campaign_id": camp, "name": "PC March", "owner_character_id": pc,
	}).is_empty(), "backfill fixture PC domain created")
	check(not CampaignRepository.create_domain({
		"campaign_id": camp, "name": "Dead March", "owner_character_id": dead,
	}).is_empty(), "backfill fixture dead-ruler domain created")
	check(not RealmRepository.create_realm({
		"campaign_id": camp, "name": "Headed Realm",
		"head_character_id": ruler_b, "realm_kind": "foreign",
	}).is_empty(), "backfill fixture realm created")

	var built := StrategicDispositionBuilder.backfill_campaign(camp)
	check(built == 2, "backfill builds exactly the 2 living NPC rulers, got %d" % built)
	check(RulerDispositionRepository.has_disposition(ruler_a), "domain owner backfilled")
	check(RulerDispositionRepository.has_disposition(ruler_b), "realm head backfilled")
	check(not RulerDispositionRepository.has_disposition(pc), "PC not backfilled")
	check(not RulerDispositionRepository.has_disposition(bystander),
		"non-ruler NPC not backfilled")
	check(not RulerDispositionRepository.has_disposition(dead), "dead ruler not backfilled")
	check(StrategicDispositionBuilder.backfill_campaign(camp) == 0,
		"backfill is idempotent (second run builds 0)")


func test_seed_relational_dicts() -> void:
	# §4.3: aggression from hostile/unfriendly bands; alliance from warm bands
	# scaled by diplomatic_weight and u(self_interest); neutral seeds nothing.
	var camp := CampaignRepository.create_campaign("Disposition Relations", "World")
	var r1 := RealmRepository.create_realm({"campaign_id": camp, "name": "Us", "realm_kind": "foreign"})
	var r2 := RealmRepository.create_realm({"campaign_id": camp, "name": "Foe", "realm_kind": "foreign"})
	var r3 := RealmRepository.create_realm({"campaign_id": camp, "name": "Friend", "realm_kind": "foreign"})
	var r4 := RealmRepository.create_realm({"campaign_id": camp, "name": "Stranger", "realm_kind": "foreign"})
	check(RealmRepository.set_relation(r1, r2, "hostile", 0), "hostile relation set")
	check(RealmRepository.set_relation(r1, r3, "allied", 0), "allied relation set")
	check(RealmRepository.set_relation(r1, r4, "neutral", 0), "neutral relation set")

	var d := StrategicDispositionBuilder.build(_baron_personality(), "lawful")
	StrategicDispositionBuilder.seed_relational_dicts(d, r1)
	_approx(float(d.aggression_toward.get(r2, 0.0)), 0.8, "hostile band seeds aggression 0.8")
	check(not d.aggression_toward.has(r3) and not d.aggression_toward.has(r4),
		"warm/neutral bands seed no aggression")
	var scale: float = (0.5 + 0.5 * d.diplomatic_weight) * (0.5 + 0.5 * (1.0 / 3.0))
	_approx(float(d.alliance_preference.get(r3, 0.0)), 0.7 * scale,
		"allied band seeds scaled alliance preference")
	check(not d.alliance_preference.has(r4), "neutral band seeds no alliance preference")
	# Graceful degradation: no realm id / no relations -> empty dicts.
	var lone := StrategicDispositionBuilder.build(_baron_personality(), "lawful")
	StrategicDispositionBuilder.seed_relational_dicts(lone, "")
	check(lone.aggression_toward.is_empty() and lone.alliance_preference.is_empty(),
		"empty realm id leaves dicts empty")
