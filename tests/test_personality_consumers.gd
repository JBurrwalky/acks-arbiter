extends "res://tests/test_suite_base.gd"

## Tests for the personality "consumers" (gdd-npc-personality.md §2/§3.2):
##   #5 PersonalityReactionModifiers + InteractionResolver hook,
##   #7 DispositionTracker (runtime disposition + trend + history),
##   #6 In-Group Loyalty → henchman loyalty modifier mapping.
## Pure / in-memory — fakes stand in for the repository where persistence is touched.


# A dice stub: roll(n, sides) -> fixed value (InteractionResolver calls roll(2,6)).
class _FixedDice extends RefCounted:
	var _val: int
	func _init(v: int) -> void:
		_val = v
	func roll(_n: int, _sides: int) -> int:
		return _val


# A minimal repo fake exposing only what the units under test call.
class _FakeRepo extends RefCounted:
	var characters: Dictionary = {}            # id -> row dict
	var personality_writes: Array = []         # [{id, json}]
	func get_character(id: String) -> Dictionary:
		return characters.get(id, {})
	func update_character_personality(id: String, json: String) -> bool:
		personality_writes.append({"id": id, "json": json})
		return true


func run_all_tests() -> void:
	# #5
	test_reaction_axis_mapping_diplomatic()
	test_reaction_axis_mapping_intimidation()
	test_reaction_axis_mapping_seduction()
	test_reaction_midrange_and_unmapped_axes_silent()
	test_reaction_magnitude()
	test_interaction_resolver_applies_personality()
	test_interaction_resolver_no_personality_unchanged()
	# #7
	test_disposition_initial_diplomatic()
	test_disposition_influence_shift()
	test_disposition_intimidation_resentment()
	test_disposition_clamp_and_trend()
	test_disposition_history_cap()
	test_disposition_modifier_projection()
	test_disposition_persistence_round_trip()
	test_disposition_persist_via_repo()
	# #6
	test_loyalty_magnitude_mapping()
	test_henchman_loyalty_modifier_integration()

	if not has_failures():
		print("PersonalityConsumers: all tests passed.")


# ---------------------------------------------------------------------------
# #5 Reaction modifiers
# ---------------------------------------------------------------------------

func _p(axes: Dictionary, disposition: int = 0) -> NpcPersonality:
	var p := NpcPersonality.new()
	for k in axes:
		p.axes[String(k)] = int(axes[k])
	p.disposition = disposition
	return p


func _find(entries: Array, source_id: String) -> int:
	for e in entries:
		if str_field(e, "source_id") == source_id:
			return int(e.get("value", 0))
	return 0


func test_reaction_axis_mapping_diplomatic() -> void:
	# High compassion + high curiosity help diplomacy; low hurt it.
	var hi := PersonalityReactionModifiers.modifiers_for(
		_p({"affective_compassion": 10, "epistemic_curiosity": 8}), "diplomatic")
	check(_find(hi, "personality_affective_compassion") == 2, "compassion 10 -> +2 diplomatic")
	check(_find(hi, "personality_epistemic_curiosity") == 1, "curiosity 8 -> +1 diplomatic")
	var lo := PersonalityReactionModifiers.modifiers_for(
		_p({"affective_compassion": 1}), "diplomatic")
	check(_find(lo, "personality_affective_compassion") == -2, "compassion 1 -> -2 diplomatic")


func test_reaction_axis_mapping_intimidation() -> void:
	# Volatile easier to intimidate (+); principled and zealot resist (-).
	var m := PersonalityReactionModifiers.modifiers_for(
		_p({"stress_reactivity": 10, "self_interest": 10, "in_group_loyalty": 9}), "intimidation")
	check(_find(m, "personality_stress_reactivity") == 2, "volatile 10 -> +2 intimidation")
	check(_find(m, "personality_self_interest") == -2, "principled 10 -> -2 intimidation")
	check(_find(m, "personality_in_group_loyalty") == -1, "zealot 9 -> -1 intimidation")


func test_reaction_axis_mapping_seduction() -> void:
	# Opportunistic (low self_interest) more swayable (+); principled (high) less (-).
	var lo := PersonalityReactionModifiers.modifiers_for(_p({"self_interest": 1}), "seduction")
	check(_find(lo, "personality_self_interest") == 2, "opportunistic 1 -> +2 seduction")
	var hi := PersonalityReactionModifiers.modifiers_for(_p({"self_interest": 10}), "seduction")
	check(_find(hi, "personality_self_interest") == -2, "principled 10 -> -2 seduction")


func test_reaction_midrange_and_unmapped_axes_silent() -> void:
	# Mid-range axes contribute nothing; societal_orthodoxy/mysticism are unmapped
	# for generic reactions even when deviant.
	var mid := PersonalityReactionModifiers.modifiers_for(
		_p({"affective_compassion": 5, "epistemic_curiosity": 6}), "diplomatic")
	check(mid.is_empty(), "mid-range axes add no reaction modifiers")
	var unmapped := PersonalityReactionModifiers.modifiers_for(
		_p({"societal_orthodoxy": 10, "mysticism": 1}), "diplomatic")
	check(unmapped.is_empty(), "orthodoxy/mysticism are not mapped to generic reactions")


func test_reaction_magnitude() -> void:
	check(PersonalityAxes.deviant_magnitude(10) == 2, "10 -> +2")
	check(PersonalityAxes.deviant_magnitude(8) == 1, "8 -> +1")
	check(PersonalityAxes.deviant_magnitude(7) == 0, "7 -> 0 (mid)")
	check(PersonalityAxes.deviant_magnitude(4) == 0, "4 -> 0 (mid)")
	check(PersonalityAxes.deviant_magnitude(3) == -1, "3 -> -1")
	check(PersonalityAxes.deviant_magnitude(1) == -2, "1 -> -2")


func test_interaction_resolver_applies_personality() -> void:
	# A high-compassion NPC, diplomatic, fixed 2d6=7, no other modifiers: the
	# personality term (+2) should land in the breakdown and the total.
	var personality := _p({"affective_compassion": 10})
	var ctx := {"target_personality": personality}
	var result := InteractionResolver.resolve_initial(
		"diplomatic", {}, ctx, null, _FixedDice.new(7))
	check(result.total_modifier == 2, "personality +2 should be the only modifier, got %d" % result.total_modifier)
	check(result.final_total == 9, "7 + 2 = 9")
	var found := false
	for entry in result.modifier_breakdown:
		if String(entry.get("source", "")) == "personality_affective_compassion":
			found = true
			check(String(entry.get("category", "")) == "personality", "category should be 'personality'")
	check(found, "breakdown should include the personality modifier")


func test_interaction_resolver_no_personality_unchanged() -> void:
	# No target_personality: behaviour identical to before (no personality term).
	var result := InteractionResolver.resolve_initial(
		"diplomatic", {}, {"cha_modifier": 1}, null, _FixedDice.new(7))
	check(result.total_modifier == 1, "only CHA +1 applies, got %d" % result.total_modifier)
	for entry in result.modifier_breakdown:
		check(String(entry.get("category", "")) != "personality", "no personality modifier expected")


# ---------------------------------------------------------------------------
# #7 Disposition tracking
# ---------------------------------------------------------------------------

func _result(tone: String, kind: String, attitude: String, shift: int = 0):
	var r := InteractionResult.new()
	r.tone = tone
	r.kind = kind
	r.resulting_attitude = attitude
	r.attitude_shift = shift
	return r


func test_disposition_initial_diplomatic() -> void:
	var p := _p({})
	var out := DispositionTracker.apply_interaction(p,
		_result("diplomatic", InteractionResult.KIND_INITIAL, Attitude.FRIENDLY))
	check(out["delta"] == 2, "friendly initial -> +2")
	check(p.disposition == 2, "disposition now 2")
	check(p.disposition_trend == "warming", "trend warming")
	check(p.disposition_history.size() == 1, "one history entry")


func test_disposition_influence_shift() -> void:
	var p := _p({})
	DispositionTracker.apply_interaction(p,
		_result("diplomatic", InteractionResult.KIND_INFLUENCE, Attitude.INDIFFERENT, 1))
	check(p.disposition == 1, "influence +1 shift -> disposition +1")
	check(p.disposition_trend == "warming", "trend warming")


func test_disposition_intimidation_resentment() -> void:
	# Compliance via fear never warms disposition.
	var p := _p({})
	DispositionTracker.apply_interaction(p,
		_result("intimidation", InteractionResult.KIND_INITIAL, Attitude.COWED))
	check(p.disposition == -1, "cowed initial -> -1 (resentment), got %d" % p.disposition)
	var p2 := _p({})
	DispositionTracker.apply_interaction(p2,
		_result("intimidation", InteractionResult.KIND_INFLUENCE, Attitude.FEARFUL, 2))
	check(p2.disposition == -1, "intimidation +2 shift -> -1 resentment, not +2; got %d" % p2.disposition)


func test_disposition_clamp_and_trend() -> void:
	var p := _p({}, 4)
	var out := DispositionTracker.apply_delta(p, 5, "big gift")
	check(p.disposition == 5, "clamps at +5")
	check(out["delta"] == 1, "effective delta is the clamped 1, got %d" % int(out["delta"]))
	# Another warming attempt at the ceiling: no change, trend stable.
	var out2 := DispositionTracker.apply_delta(p, 3, "another gift")
	check(out2["delta"] == 0 and p.disposition_trend == "stable", "no change at ceiling -> stable")
	check(p.disposition_history.size() == 1, "no history entry for a zero-effect change")


func test_disposition_history_cap() -> void:
	var p := _p({})
	for i in range(12):
		DispositionTracker.apply_delta(p, 1 if i % 2 == 0 else -1, "oscillate")
	check(p.disposition_history.size() == DispositionTracker.HISTORY_CAP,
		"history capped at %d, got %d" % [DispositionTracker.HISTORY_CAP, p.disposition_history.size()])


func test_disposition_modifier_projection() -> void:
	# disposition (-5..+5) -> reaction modifier capped to ±2 (banker's round of /2).
	check(PersonalityReactionModifiers.disposition_modifier(_p({}, 5)) == 2, "+5 -> +2")
	check(PersonalityReactionModifiers.disposition_modifier(_p({}, 2)) == 1, "+2 -> +1")
	check(PersonalityReactionModifiers.disposition_modifier(_p({}, 1)) == 0, "+1 -> 0 (0.5 rounds to even 0)")
	check(PersonalityReactionModifiers.disposition_modifier(_p({}, -3)) == -2, "-3 -> -2")
	check(PersonalityReactionModifiers.disposition_modifier(_p({}, -5)) == -2, "-5 -> -2")


func test_disposition_persistence_round_trip() -> void:
	var p := _p({"self_interest": 8}, 3)
	p.disposition_trend = "warming"
	p.disposition_history = [{"delta": 1, "reason": "x", "value": 3}]
	var restored := NpcPersonality.from_json(p.to_json())
	check(restored != null, "round-trips")
	check(restored.disposition == 3, "disposition survives")
	check(restored.disposition_trend == "warming", "trend survives")
	check(restored.disposition_history.size() == 1, "history survives")


func test_disposition_persist_via_repo() -> void:
	var repo := _FakeRepo.new()
	var p := _p({}, 2)
	var ok := DispositionTracker.persist("npc_1", p, repo)
	check(ok, "persist returns true via fake repo")
	check(repo.personality_writes.size() == 1, "one personality write")
	check(String(repo.personality_writes[0]["id"]) == "npc_1", "wrote to the right id")


# ---------------------------------------------------------------------------
# #6 Henchman loyalty
# ---------------------------------------------------------------------------

func test_loyalty_magnitude_mapping() -> void:
	# Zealot steadier (+2), mercenary wavers (-2), mid-range neutral (0).
	check(PersonalityAxes.deviant_magnitude(10) == 2, "zealot 10 -> +2 loyalty")
	check(PersonalityAxes.deviant_magnitude(1) == -2, "mercenary 1 -> -2 loyalty")
	check(PersonalityAxes.deviant_magnitude(5) == 0, "mid 5 -> 0 loyalty")


func test_henchman_loyalty_modifier_integration() -> void:
	# The lifecycle manager reads the henchman's personality and derives the modifier.
	var repo := _FakeRepo.new()
	var zealot := _p({"in_group_loyalty": 10})
	repo.characters["h1"] = {"personality": zealot.to_json()}
	var mercenary := _p({"in_group_loyalty": 1})
	repo.characters["h2"] = {"personality": mercenary.to_json()}
	repo.characters["h3"] = {"personality": "{}"}  # no personality
	var mgr := HenchmanLifecycleManager.new(repo)
	check(mgr._personality_loyalty_modifier("h1") == 2, "zealot henchman -> +2")
	check(mgr._personality_loyalty_modifier("h2") == -2, "mercenary henchman -> -2")
	check(mgr._personality_loyalty_modifier("h3") == 0, "no personality -> 0")
	check(mgr._personality_loyalty_modifier("missing") == 0, "unknown character -> 0")
