extends "res://tests/test_suite_base.gd"

## Tests for VagariesOfBattleResolver per daw_vagaries.xml §vagaries_of_battle.


func run_all_tests() -> void:
	test_full_d100_coverage()
	test_resolve_one_high_ground()
	test_resolve_one_volley_of_arrows()
	test_resolve_one_bombardment()
	test_roll_battle_vagaries_returns_count()
	if not has_failures():
		print("VagariesOfBattleResolver: all tests passed.")


func test_full_d100_coverage() -> void:
	for roll in range(1, 101):
		var r := VagariesOfBattleResolver.resolve_one(roll)
		check(not String(r.get("result_key", "")).is_empty(), "roll %d returns a result_key" % roll)


func test_resolve_one_high_ground() -> void:
	var r := VagariesOfBattleResolver.resolve_one(63)  # 61-65 → high_ground
	check(String(r.get("result_key", "")) == "high_ground", "63 → high_ground")
	var p: Dictionary = r.get("payload", {})
	check(int(p.get("defender_ac_bonus", 0)) == 1, "high_ground +1 AC")
	check(int(p.get("defender_attack_bonus", 0)) == 1, "high_ground +1 attack")


func test_resolve_one_volley_of_arrows() -> void:
	var r := VagariesOfBattleResolver.resolve_one(98)  # 96-100 → volley_of_arrows
	check(String(r.get("result_key", "")) == "volley_of_arrows", "98 → volley_of_arrows")
	var p: Dictionary = r.get("payload", {})
	check(int(p.get("attack_throw_against_each_combatant", 0)) == 15, "volley target 15+")


func test_resolve_one_bombardment() -> void:
	var r := VagariesOfBattleResolver.resolve_one(15)  # 13-17 → bombardment
	check(String(r.get("result_key", "")) == "bombardment", "15 → bombardment")


func test_roll_battle_vagaries_returns_count() -> void:
	# Force count = 1d4 = 3.
	var idx := [0]
	var rolls := [3, 50, 65, 98]  # first is 1d4 = 3; remaining are d100 rolls
	var roller := func(_count, _sides):
		var v: int = int(rolls[idx[0]]) if idx[0] < rolls.size() else 1
		idx[0] += 1
		return v
	var result := VagariesOfBattleResolver.roll_battle_vagaries(0, roller)
	check(result.size() == 3, "rolled 3 vagaries (1d4=3)")
	check(String(result[0].get("result_key", "")) == "deserters", "roll 50 = deserters (46-50)")
	check(String(result[1].get("result_key", "")) == "high_ground", "roll 65 = high_ground")
	check(String(result[2].get("result_key", "")) == "volley_of_arrows", "roll 98 = volley")
