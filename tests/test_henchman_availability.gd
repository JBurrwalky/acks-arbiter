extends "res://tests/test_suite_base.gd"

## Tests for HenchmanAvailability.generate_pool — exercises the per-level
## availability rolls and Normal Man → Level-1 Fighter placeholder mapping.


## Returns deterministic dice values from a queue. Each call to roll() pops
## one value. Used to prove the per-level dice expressions are honoured.
class QueueDice:
	extends RefCounted
	var values: Array = []
	var _idx := 0
	func _init(v: Array) -> void:
		values = v
	func roll(_count: int, _sides: int) -> int:
		if _idx >= values.size():
			# Default to 1 — produces a single Normal Man for level 0 rolls
			# and minimum class-pool index otherwise.
			return 1
		var v: int = values[_idx]
		_idx += 1
		return v


func run_all_tests() -> void:
	test_pool_includes_normal_men_at_market_class_six()
	test_normal_men_become_level_1_fighter_placeholders()
	test_leveled_slots_pick_class_from_market_pool()
	test_pool_assigns_weekly_allotment()
	test_market_class_one_yields_many_normal_men()
	if not has_failures():
		print("HenchmanAvailability: all tests passed.")


func test_pool_includes_normal_men_at_market_class_six() -> void:
	# Class VI table: Normal Men 1d2 → roll 2; Lvl1 1(20%) → roll 50 (>20, fail);
	# Lvl2 1(15%) → roll 80 (fail); Lvl3 1(5%) → roll 99 (fail);
	# Lvl4 → 0% so no roll consumed.
	var dice := QueueDice.new([2, 50, 80, 99])
	var pool := HenchmanAvailability.generate_pool(6, dice)
	check(pool.size() == 2,
		"MC VI with Normal Men roll 2 should yield 2 candidates, got %d" % pool.size())
	for entry: Dictionary in pool:
		check(entry.get("is_normal_man_placeholder", false),
			"MC VI candidates with no leveled rolls should all be placeholders")


func test_normal_men_become_level_1_fighter_placeholders() -> void:
	var dice := QueueDice.new([1, 99, 99, 99])  # 1 Normal Man, no leveled
	var pool := HenchmanAvailability.generate_pool(6, dice)
	check(pool.size() == 1, "expected 1 candidate")
	var entry: Dictionary = pool[0]
	check(entry["class_id"] == "fighter",
		"Normal Man placeholder must use fighter class, got %s" % entry["class_id"])
	check(entry["level"] == 1,
		"Normal Man placeholder level must be 1, got %d" % int(entry["level"]))
	check(entry["is_normal_man_placeholder"] == true,
		"placeholder flag must be set")


func test_leveled_slots_pick_class_from_market_pool() -> void:
	# MC IV per acore_equipment.xml:730 — Normal Men 3d4, Lvl1 1d2,
	# Lvl2 1d1 = guaranteed 1, Lvl3 1(33%), Lvl4 1(15%).
	# QueueDice returns one value per _roll() call regardless of dice count.
	# Queue layout (consumed in order):
	#   [0] level 0 count    → 9
	#   [1] level 1 count    → 2
	#   [2..3] L1 class picks (2 slots)
	#   [4] level 2 count    → 1
	#   [5] L2 class pick
	#   [6] level 3 percent  → 50 (>33 → 0 leveled)
	#   [7] level 4 percent  → 99 (>15 → 0 leveled)
	var dice := QueueDice.new([9, 2, 1, 1, 1, 1, 50, 99])
	var pool := HenchmanAvailability.generate_pool(4, dice)
	check(pool.size() == 12,
		"MC IV with these rolls should yield 12 candidates, got %d" % pool.size())
	var leveled := 0
	var placeholders := 0
	for entry: Dictionary in pool:
		if entry.get("is_normal_man_placeholder", false):
			placeholders += 1
		else:
			leveled += 1
			check(entry["level"] >= 1, "leveled slot must have level >= 1")
			check(not String(entry["class_id"]).is_empty(),
				"leveled slot must have a class")
	check(placeholders == 9,
		"expected 9 Normal Man placeholders, got %d" % placeholders)
	check(leveled == 3, "expected 3 leveled slots, got %d" % leveled)


func test_pool_assigns_weekly_allotment() -> void:
	# Generate a small pool and confirm each entry gets allotment_week 1-3.
	var dice := QueueDice.new([2, 99, 99, 99])  # 2 Normal Men, nothing else
	var pool := HenchmanAvailability.generate_pool(6, dice)
	for entry: Dictionary in pool:
		check(entry.has("allotment_week"),
			"each candidate must carry allotment_week")
		var w: int = int(entry["allotment_week"])
		check(w >= 1 and w <= 3, "allotment_week must be 1..3, got %d" % w)


func test_market_class_one_yields_many_normal_men() -> void:
	# Class I per acore_equipment.xml:730. _roll() makes ONE call per dice
	# expression, so each level's count comes from a single queue entry.
	# Queue layout (consumed in order):
	#   [0]  level 0 (4d100) count  → 200
	#   [1]  level 1 (5d10) count   → 25
	#   [2..26]  25× class picks for Lvl1
	#   [27] level 2 (3d10) count   → 15
	#   [28..42] 15× class picks for Lvl2
	#   [43] level 3 (1d10) count   → 5
	#   [44..48] 5× class picks for Lvl3
	#   [49] level 4 (1d6) count    → 3
	#   [50..52] 3× class picks for Lvl4
	var rolls: Array = [200, 25]
	for _i in range(25):
		rolls.append(1)
	rolls.append(15)
	for _i in range(15):
		rolls.append(1)
	rolls.append(5)
	for _i in range(5):
		rolls.append(1)
	rolls.append(3)
	for _i in range(3):
		rolls.append(1)
	var dice := QueueDice.new(rolls)
	var pool := HenchmanAvailability.generate_pool(1, dice)
	var normal_count := 0
	for entry: Dictionary in pool:
		if entry.get("is_normal_man_placeholder", false):
			normal_count += 1
	check(normal_count == 200,
		"MC I should yield 200 Normal Man placeholders, got %d" % normal_count)
	check(pool.size() == 248,
		"MC I total pool should be 248, got %d" % pool.size())
