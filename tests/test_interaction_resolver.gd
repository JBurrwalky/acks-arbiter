extends "res://tests/test_suite_base.gd"

## Phase G-1: InteractionResolver — sacred 7-step procedure across the three
## interaction tones (diplomatic, intimidation, seduction).
##
## Uses a fixed-roll fake dice so the tests are deterministic.


class FakeDice:
	extends RefCounted

	var fixed_total: int = 7
	func roll(_count: int, _sides: int) -> int:
		return fixed_total


func run_all_tests() -> void:
	test_diplomatic_table_mapping()
	test_intimidation_table_mapping()
	test_seduction_table_mapping()
	test_diplomatic_modifiers()
	test_intimidation_modifiers()
	test_already_attitude_modifier()
	test_proficiency_modifiers()
	test_mystic_aura_charm_flag()
	test_attempt_to_influence_shifts()
	test_attempt_to_influence_clamps_at_friendly()
	test_cooldown_ladder()
	test_modifier_breakdown_present()
	if not has_failures():
		print("InteractionResolver: all tests passed.")


func _resolve_initial(tone: String, total: int, ctx: Dictionary = {}) -> InteractionResult:
	var dice := FakeDice.new()
	dice.fixed_total = total
	return InteractionResolver.resolve_initial(tone, {}, ctx, null, dice)


func test_diplomatic_table_mapping() -> void:
	check(_resolve_initial("diplomatic", 2).resulting_attitude == Attitude.HOSTILE, "2 -> hostile")
	check(_resolve_initial("diplomatic", 5).resulting_attitude == Attitude.UNFRIENDLY, "5 -> unfriendly")
	check(_resolve_initial("diplomatic", 7).resulting_attitude == Attitude.NEUTRAL, "7 -> neutral")
	check(_resolve_initial("diplomatic", 10).resulting_attitude == Attitude.INDIFFERENT, "10 -> indifferent")
	check(_resolve_initial("diplomatic", 12).resulting_attitude == Attitude.FRIENDLY, "12 -> friendly")


func test_intimidation_table_mapping() -> void:
	check(_resolve_initial("intimidation", 2).resulting_attitude == Attitude.HOSTILE, "intim 2 -> hostile")
	check(_resolve_initial("intimidation", 5).resulting_attitude == Attitude.UNFRIENDLY, "intim 5 -> unfriendly")
	check(_resolve_initial("intimidation", 8).resulting_attitude == Attitude.NEUTRAL, "intim 8 -> neutral")
	check(_resolve_initial("intimidation", 11).resulting_attitude == Attitude.FEARFUL, "intim 11 -> fearful")
	check(_resolve_initial("intimidation", 12).resulting_attitude == Attitude.COWED, "intim 12 -> cowed")


func test_seduction_table_mapping() -> void:
	check(_resolve_initial("seduction", 12).resulting_attitude == Attitude.FRIENDLY, "seduce 12 -> friendly")
	check(_resolve_initial("seduction", 10).resulting_attitude == Attitude.INDIFFERENT, "seduce 10 -> indifferent")


func test_diplomatic_modifiers() -> void:
	# CHA mod +2, target trespassing (-1), legal authority (+2), already-hostile (-2)
	# raw 7 + (2 - 1 + 2 - 2) = 7 + 1 = 8 -> still neutral
	var r := _resolve_initial("diplomatic", 7, {
		"cha_modifier": 2,
		"trespassing": true,
		"has_legal_authority": true,
		"already_attitude": Attitude.HOSTILE,
	})
	check(r.total_modifier == 1, "diplomatic combined mod = +1, got %d" % r.total_modifier)
	check(r.final_total == 8, "final = 8")
	check(r.resulting_attitude == Attitude.NEUTRAL, "still neutral")


func test_intimidation_modifiers() -> void:
	# Outnumber 3:1 (+5) + brandishing weapon (+1) + target morale 7 (-7) + target armed (-1)
	# = +5 +1 -7 -1 = -2
	var r := _resolve_initial("intimidation", 7, {
		"outnumber_ratio": "3:1",
		"brandishing_weapon": true,
		"target_morale_score": 7,
		"target_armed": true,
	})
	check(r.total_modifier == -2, "intim combined mod = -2, got %d" % r.total_modifier)
	check(r.final_total == 5, "final 5")
	check(r.resulting_attitude == Attitude.UNFRIENDLY, "5 -> unfriendly")


func test_already_attitude_modifier() -> void:
	# Diplomatic: already-friendly now contributes +2 across ALL tones per the
	# gdd-npc-dialogue.md §6.1 ruling (previously seduction-only). Extends the
	# RAW +2 friendly line symmetrically with hostile −2 / unfriendly −1 / indifferent +1.
	var r1 := _resolve_initial("diplomatic", 7, {"already_attitude": Attitude.FRIENDLY})
	check(r1.total_modifier == 2, "diplomatic already-friendly = +2 (dialogue §6.1)")
	# Seduction: already-friendly contributes +2 (the original RAW line).
	var r2 := _resolve_initial("seduction", 7, {"already_attitude": Attitude.FRIENDLY})
	check(r2.total_modifier == 2, "seduction already-friendly = +2")
	# Intimidation: already-friendly also +2 now (uniform across tones).
	var r_int := _resolve_initial("intimidation", 7, {"already_attitude": Attitude.FRIENDLY})
	check(r_int.total_modifier == 2, "intimidation already-friendly = +2 (dialogue §6.1)")
	# Intimidation: already-fearful contributes +1 (unchanged).
	var r3 := _resolve_initial("intimidation", 7, {"already_attitude": Attitude.FEARFUL})
	check(r3.total_modifier == 1, "intimidation already-fearful = +1")
	# Already-hostile / unfriendly / indifferent unchanged across tones.
	var r4 := _resolve_initial("diplomatic", 7, {"already_attitude": Attitude.HOSTILE})
	check(r4.total_modifier == -2, "diplomatic already-hostile = -2")
	var r5 := _resolve_initial("diplomatic", 7, {"already_attitude": Attitude.INDIFFERENT})
	check(r5.total_modifier == 1, "diplomatic already-indifferent = +1")


func test_proficiency_modifiers() -> void:
	var r := _resolve_initial("diplomatic", 7, {
		"has_diplomacy": true,
		"has_mystic_aura": true,
	})
	check(r.total_modifier == 4, "diplomacy +2 + mystic aura +2 = +4")


func test_mystic_aura_charm_flag() -> void:
	var r := _resolve_initial("diplomatic", 12, {"has_mystic_aura": true})
	# raw 12 + 2 (mystic aura) = 14 -> charm-like
	check(r.charm_like_flag, "mystic aura with total >= 12 sets charm flag")
	var r2 := _resolve_initial("diplomatic", 8, {"has_mystic_aura": true})
	# raw 8 + 2 = 10 -> below 12, no charm
	check(not r2.charm_like_flag, "below 12 -> no charm flag")


func test_attempt_to_influence_shifts() -> void:
	var dice := FakeDice.new()
	dice.fixed_total = 11
	var r := InteractionResolver.resolve_attempt_to_influence(
		"diplomatic", Attitude.NEUTRAL, {}, {}, null, 0, dice)
	check(r.attitude_shift == 1, "11 -> +1 step")
	check(r.resulting_attitude == Attitude.INDIFFERENT, "neutral +1 = indifferent")

	dice.fixed_total = 2
	var r2 := InteractionResolver.resolve_attempt_to_influence(
		"diplomatic", Attitude.NEUTRAL, {}, {}, null, 0, dice)
	# 2 with already-neutral context: relationship modifier 0, total = 2 still
	check(r2.attitude_shift == -2, "2 -> -2 steps")
	check(r2.resulting_attitude == Attitude.HOSTILE, "neutral -2 = hostile (clamped)")


func test_attempt_to_influence_clamps_at_friendly() -> void:
	var dice := FakeDice.new()
	dice.fixed_total = 12
	var r := InteractionResolver.resolve_attempt_to_influence(
		"diplomatic", Attitude.FRIENDLY, {}, {}, null, 0, dice)
	check(r.resulting_attitude == Attitude.FRIENDLY, "friendly +2 clamps at friendly")


func test_cooldown_ladder() -> void:
	var dice := FakeDice.new()
	dice.fixed_total = 7
	var r0 := InteractionResolver.resolve_attempt_to_influence(
		"diplomatic", Attitude.NEUTRAL, {}, {}, null, 0, dice)
	check(r0.time_until_next_attempt_seconds == 10, "1st attempt -> 10s")
	var r3 := InteractionResolver.resolve_attempt_to_influence(
		"diplomatic", Attitude.NEUTRAL, {}, {}, null, 3, dice)
	check(r3.time_until_next_attempt_seconds == 3600, "4th attempt -> 1 hour")
	var r5 := InteractionResolver.resolve_attempt_to_influence(
		"diplomatic", Attitude.NEUTRAL, {}, {}, null, 5, dice)
	check(r5.time_until_next_attempt_seconds == 5 * 28800, "6+ attempt -> 1 week")


func test_modifier_breakdown_present() -> void:
	var r := _resolve_initial("diplomatic", 7, {
		"cha_modifier": 1,
		"has_diplomacy": true,
	})
	check(r.modifier_breakdown.size() >= 2, "breakdown has both modifiers")
	var sources: Array = []
	for m in r.modifier_breakdown:
		sources.append(m["source"])
	check(sources.has("cha_modifier"), "cha_modifier present in breakdown")
	check(sources.has("prof_diplomacy"), "prof_diplomacy present in breakdown")
