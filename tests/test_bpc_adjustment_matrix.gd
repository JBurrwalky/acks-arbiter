extends "res://tests/test_suite_base.gd"

## Tests for BpcAdjustmentMatrix per daw_axioms_pitching_battle.xml
## §battle_resolution.phase[*].post_choice_outcomes.


func run_all_tests() -> void:
	test_missile_both_withdraw_increases_2()
	test_missile_both_advance_decreases_2()
	test_missile_both_withdraw_threshold_draws()
	test_missile_advance_into_skirmish()
	test_skirmish_advance_into_melee()
	test_skirmish_withdraw_back_to_missile()
	test_melee_floor_clamps_at_zero()
	test_melee_withdraw_back_to_skirmish()
	test_initiative_winner_advancing()
	test_initiative_winner_withdrawing()
	if not has_failures():
		print("BpcAdjustmentMatrix: all tests passed.")


func _resolve(phase: String, a: String, d: String, current: int, starting: int = 1, sa: int = 0, sd: int = 0, dice = Callable()) -> Dictionary:
	return BpcAdjustmentMatrix.resolve(phase, a, d, current, starting, sa, sd, dice)


func test_missile_both_withdraw_increases_2() -> void:
	var r := _resolve("missile", "withdraw", "withdraw", 1, 1)
	check(int(r.get("delta", 0)) == 2, "both_withdraw delta = +2")
	check(int(r.get("new_bpc", 0)) == 3, "new_bpc 1 + 2 = 3")
	check(String(r.get("transition", "")) == "draw", "draw at 2× starting (3 ≥ 2)")


func test_missile_both_advance_decreases_2() -> void:
	var r := _resolve("missile", "advance", "advance", 5, 5)
	check(int(r.get("delta", 0)) == -2, "both_advance delta = -2")
	check(int(r.get("new_bpc", 0)) == 3, "new_bpc 5 - 2 = 3")
	check(String(r.get("transition", "")) == "continue", "BPC > 0 → continue")


func test_missile_both_withdraw_threshold_draws() -> void:
	var r := _resolve("missile", "withdraw", "withdraw", 5, 5)
	# 5 + 2 = 7; 2× starting = 10; 7 < 10 → continue
	check(String(r.get("transition", "")) == "continue", "below threshold → continue")
	# Now near threshold:
	var r2 := _resolve("missile", "withdraw", "withdraw", 9, 5)
	# 9 + 2 = 11 ≥ 10 → draw
	check(String(r2.get("transition", "")) == "draw", "above threshold → draw")


func test_missile_advance_into_skirmish() -> void:
	var r := _resolve("missile", "advance", "advance", 1, 5)
	# 1 - 2 = -1 ≤ 0 → advance_phase
	check(String(r.get("transition", "")) == "advance_phase", "missile advance → skirmish")


func test_skirmish_advance_into_melee() -> void:
	var r := _resolve("skirmish", "advance", "advance", 1, 5)
	check(String(r.get("transition", "")) == "advance_phase", "skirmish advance → melee")


func test_skirmish_withdraw_back_to_missile() -> void:
	var r := _resolve("skirmish", "withdraw", "withdraw", 1, 1)
	# 1 + 2 = 3 > starting 1 → regress
	check(String(r.get("transition", "")) == "regress_phase", "skirmish withdraw → missile")


func test_melee_floor_clamps_at_zero() -> void:
	var r := _resolve("melee", "advance", "advance", 0, 1)
	# 0 - 2 = -2; melee floor clamps to 0 and continues
	check(int(r.get("new_bpc", -1)) == 0, "melee floor at 0")
	check(String(r.get("transition", "")) == "melee_floor", "melee_floor transition")


func test_melee_withdraw_back_to_skirmish() -> void:
	var r := _resolve("melee", "withdraw", "withdraw", 1, 1)
	# 1 + 2 = 3 > starting 1 → regress
	check(String(r.get("transition", "")) == "regress_phase", "melee withdraw → skirmish")


func test_initiative_winner_advancing() -> void:
	# attacker advances, defender withdraws → roll initiative.
	# Force advancing wins: dice returns 6 then 1 (attacker rolls 6+SA=6, defender 1+SD=1).
	var rolls := [6, 1]
	var idx := [0]
	var roller := func(_count, _sides):
		var v: int = int(rolls[idx[0]]) if idx[0] < rolls.size() else 1
		idx[0] += 1
		return v
	var r := _resolve("missile", "advance", "withdraw", 5, 5, 0, 0, roller)
	# Attacker advancing wins → -1 BPC.
	check(int(r.get("delta", 0)) == -1, "advancing wins → -1")
	check(String(r.get("initiative_winner", "")) == "advancing", "winner=advancing")


func test_initiative_winner_withdrawing() -> void:
	var rolls := [1, 6]
	var idx := [0]
	var roller := func(_count, _sides):
		var v: int = int(rolls[idx[0]]) if idx[0] < rolls.size() else 1
		idx[0] += 1
		return v
	var r := _resolve("missile", "advance", "withdraw", 5, 5, 0, 0, roller)
	# Withdrawing wins → +1 BPC.
	check(int(r.get("delta", 0)) == 1, "withdrawing wins → +1")
	check(String(r.get("initiative_winner", "")) == "withdrawing", "winner=withdrawing")
