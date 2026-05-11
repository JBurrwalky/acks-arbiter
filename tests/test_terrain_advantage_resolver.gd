extends "res://tests/test_suite_base.gd"

## Tests for TerrainAdvantageResolver per daw_axioms_pitching_battle.xml
## §assess_terrain_advantage L104-137.


func run_all_tests() -> void:
	test_score_to_advantage_table_clear()
	test_score_to_advantage_table_hills()
	test_score_to_advantage_table_mountains()
	test_attacker_double_score_reduces_two_steps()
	test_attacker_score_higher_reduces_one_step()
	test_attacker_score_equal_no_effect()
	test_surprise_modifier_minus_two_plus_two()
	test_already_regular_attacker_occupies_advantageous()
	if not has_failures():
		print("TerrainAdvantageResolver: all tests passed.")


func test_score_to_advantage_table_clear() -> void:
	# clear_or_grass: advantageous 6+, highly_advantageous 10+
	check(TerrainAdvantageResolver.score_to_advantage("clear_or_grass", 5) == "regular", "score 5 = regular")
	check(TerrainAdvantageResolver.score_to_advantage("clear_or_grass", 6) == "advantageous", "score 6 = advantageous")
	check(TerrainAdvantageResolver.score_to_advantage("clear_or_grass", 9) == "advantageous", "score 9 = advantageous")
	check(TerrainAdvantageResolver.score_to_advantage("clear_or_grass", 10) == "highly_advantageous", "score 10 = highly")


func test_score_to_advantage_table_hills() -> void:
	# hills: advantageous 4+, highly_advantageous 7+
	check(TerrainAdvantageResolver.score_to_advantage("hills", 3) == "regular", "hills 3 = regular")
	check(TerrainAdvantageResolver.score_to_advantage("hills", 4) == "advantageous", "hills 4 = advantageous")
	check(TerrainAdvantageResolver.score_to_advantage("hills", 7) == "highly_advantageous", "hills 7 = highly")


func test_score_to_advantage_table_mountains() -> void:
	# mountains: advantageous 4+, highly_advantageous 6+
	check(TerrainAdvantageResolver.score_to_advantage("mountains", 4) == "advantageous", "mountains 4 = advantageous")
	check(TerrainAdvantageResolver.score_to_advantage("mountains", 6) == "highly_advantageous", "mountains 6 = highly")


func test_attacker_double_score_reduces_two_steps() -> void:
	# defender rolls 2 + 0 = 2 (regular on hills); attacker rolls 6 + 0 = 6
	# 6 ≥ 2×2 → attacker may reduce defender's 2 steps OR occupy highly_adv.
	# Defender starts regular → already at floor; double-step reduction is no-op.
	# Try a case where defender has advantage to lose.
	# defender 4 → advantageous; attacker 8 → ≥ 2×4
	var rolls := [4, 8]  # defender, attacker
	var idx := [0]
	var roller := func(_count, _sides):
		var v: int = int(rolls[idx[0]]) if idx[0] < rolls.size() else 1
		idx[0] += 1
		return v
	var result := TerrainAdvantageResolver.resolve("hills", 0, 0, false, false, roller)
	# defender_score = 4 + 0 = 4 → advantageous (hills 4+); attacker_score = 8 + 0 = 8 ≥ 2×4
	# Heuristic reduces defender by 2 steps from advantageous → regular (cannot go below).
	check(String(result.get("defender_advantage", "")) == "regular",
		"defender stepped down 2 to regular; got %s" % result.get("defender_advantage", "?"))


func test_attacker_score_higher_reduces_one_step() -> void:
	# defender 4 → advantageous on hills; attacker 5 → only > defender, not 2×.
	# Heuristic reduces by 1 step → regular.
	var rolls := [4, 5]
	var idx := [0]
	var roller := func(_count, _sides):
		var v: int = int(rolls[idx[0]]) if idx[0] < rolls.size() else 1
		idx[0] += 1
		return v
	var result := TerrainAdvantageResolver.resolve("hills", 0, 0, false, false, roller)
	check(String(result.get("defender_advantage", "")) == "regular",
		"defender stepped down 1 to regular; got %s" % result.get("defender_advantage", "?"))


func test_attacker_score_equal_no_effect() -> void:
	var rolls := [4, 4]
	var idx := [0]
	var roller := func(_count, _sides):
		var v: int = int(rolls[idx[0]]) if idx[0] < rolls.size() else 1
		idx[0] += 1
		return v
	var result := TerrainAdvantageResolver.resolve("hills", 0, 0, false, false, roller)
	# Defender score = 4 = advantageous; attacker score = 4 = NOT > defender → no reduction.
	check(String(result.get("defender_advantage", "")) == "advantageous",
		"defender keeps advantage; got %s" % result.get("defender_advantage", "?"))
	check(String(result.get("attacker_advantage", "")) == "regular",
		"attacker stays regular")


func test_surprise_modifier_minus_two_plus_two() -> void:
	# defender 4 + 0 - 2 (surprised) = 2; attacker 5 + 0 + 2 (def surprised) = 7
	# Defender_score 2 → regular on hills; attacker_score 7 → highly_advantageous on hills (7+).
	# Per rules: attacker score 7 ≥ 2×2=4 → attacker may reduce defender by 2 (already regular)
	# OR occupy highly_advantageous (we can't reduce below regular; heuristic occupies highly per fallback).
	# Actually our heuristic only occupies advantageous when defender is at regular floor; let's check.
	var rolls := [4, 5]
	var idx := [0]
	var roller := func(_count, _sides):
		var v: int = int(rolls[idx[0]]) if idx[0] < rolls.size() else 1
		idx[0] += 1
		return v
	var result := TerrainAdvantageResolver.resolve("hills", 0, 0, true, false, roller)
	# defender surprised → -2 to defender, +2 to attacker. So def=2, att=7.
	check(int(result.get("defender_score", 0)) == 2, "defender score 2 with surprise")
	check(int(result.get("attacker_score", 0)) == 7, "attacker score 7 with bonus")


func test_already_regular_attacker_occupies_advantageous() -> void:
	# defender 1 → regular on hills (need 4+); attacker 5 → > defender, not 2×.
	# Heuristic: defender already regular → attacker occupies advantageous (terrain target 4+ → 5 qualifies).
	var rolls := [1, 5]
	var idx := [0]
	var roller := func(_count, _sides):
		var v: int = int(rolls[idx[0]]) if idx[0] < rolls.size() else 1
		idx[0] += 1
		return v
	var result := TerrainAdvantageResolver.resolve("hills", 0, 0, false, false, roller)
	check(String(result.get("attacker_advantage", "")) == "advantageous",
		"attacker occupies advantageous; got %s" % result.get("attacker_advantage", "?"))
	check(String(result.get("defender_advantage", "")) == "regular",
		"defender stays regular")
