extends "res://tests/test_suite_base.gd"

## Tests for SupplyCalculator (Phase 6A).
##
## Covers weekly supply cost (per RAW base rates from
## daw_campaigning_armies.xml §supply_cost L233-241) and weighted-line geometry
## (per §overextended_supply.weighted_length_rules L307-320). Verifies the
## STATUS_* enum transitions on path-blocking + overextension.


func run_all_tests() -> void:
	test_weighted_path_clear_terrain()
	test_weighted_path_mountain_doubles()
	test_weighted_path_road_quartered()
	test_weighted_path_settled_one_third()
	test_weighted_path_navigable_zero()
	test_dwarf_treats_hills_as_settled()
	test_elf_treats_forest_as_settled()
	test_beastman_treats_all_as_settled()
	test_evaluate_status_no_base()
	test_evaluate_status_blocked()
	test_evaluate_status_overextended()
	test_evaluate_status_in_supply()
	if not has_failures():
		print("SupplyCalculator: all tests passed.")


func test_weighted_path_clear_terrain() -> void:
	var path := [
		{"terrain": "clear"},
		{"terrain": "plain"},
		{"terrain": "scrub"},
	]
	var w := SupplyCalculator.compute_weighted_path_length(path, "human")
	check(w == 3, "3 clear hexes weight = 3, got %d" % w)


func test_weighted_path_mountain_doubles() -> void:
	var path := [
		{"terrain": "mountain"},
		{"terrain": "mountain"},
	]
	var w := SupplyCalculator.compute_weighted_path_length(path, "human")
	check(w == 4, "2 mountain hexes weight = 4, got %d" % w)


func test_weighted_path_road_quartered() -> void:
	var path := [
		{"terrain": "clear", "is_road": true},
		{"terrain": "clear", "is_road": true},
		{"terrain": "clear", "is_road": true},
		{"terrain": "clear", "is_road": true},
	]
	var w := SupplyCalculator.compute_weighted_path_length(path, "human")
	# 4 hexes × 0.25 = 1.0 → ceil = 1
	check(w == 1, "4 road hexes weight = 1, got %d" % w)


func test_weighted_path_settled_one_third() -> void:
	var path := [
		{"terrain": "clear", "is_settled": true},
		{"terrain": "clear", "is_settled": true},
		{"terrain": "clear", "is_settled": true},
	]
	var w := SupplyCalculator.compute_weighted_path_length(path, "human")
	# 3 × 0.33 = 0.99 → ceil = 1
	check(w == 1, "3 settled hexes weight = 1, got %d" % w)


func test_weighted_path_navigable_zero() -> void:
	var path := [
		{"terrain": "clear", "is_navigable_waterway": true},
		{"terrain": "clear", "is_navigable_waterway": true},
	]
	var w := SupplyCalculator.compute_weighted_path_length(path, "human")
	check(w == 0, "navigable waterway zeroes weight, got %d" % w)


func test_dwarf_treats_hills_as_settled() -> void:
	var path := [{"terrain": "hills"}, {"terrain": "mountain"}]
	var human_w := SupplyCalculator.compute_weighted_path_length(path, "human")
	var dwarf_w := SupplyCalculator.compute_weighted_path_length(path, "dwarf")
	# Human: 1.5 + 2.0 = 3.5 → ceil 4
	check(human_w == 4, "human weight = 4, got %d" % human_w)
	# Dwarf: 0.33 + 0.33 = 0.66 → ceil 1
	check(dwarf_w == 1, "dwarf weight = 1, got %d" % dwarf_w)


func test_elf_treats_forest_as_settled() -> void:
	var path := [{"terrain": "forest"}, {"terrain": "woods"}]
	var human_w := SupplyCalculator.compute_weighted_path_length(path, "human")
	var elf_w := SupplyCalculator.compute_weighted_path_length(path, "elf")
	# Human: 1.5 + 1.5 = 3.0
	check(human_w == 3, "human weight = 3, got %d" % human_w)
	# Elf: 0.33 + 0.33 = 0.66 → ceil 1
	check(elf_w == 1, "elf weight = 1, got %d" % elf_w)


func test_beastman_treats_all_as_settled() -> void:
	var path := [{"terrain": "barren"}, {"terrain": "swamp"}, {"terrain": "mountain"}]
	var beastman_w := SupplyCalculator.compute_weighted_path_length(path, "beastman")
	# 3 × 0.33 = 0.99 → ceil 1
	check(beastman_w == 1, "beastman weight = 1, got %d" % beastman_w)


func test_evaluate_status_no_base() -> void:
	var ss := {"supply_base_stronghold_id": null}
	var status := SupplyCalculator.evaluate_supply_line_status(ss, 100, 5, [])
	check(status == SupplyCalculator.STATUS_NO_BASE, "no base → no_base")


func test_evaluate_status_blocked() -> void:
	var ss := {"supply_base_stronghold_id": "S1"}
	var path := [{"terrain": "clear"}, {"terrain": "clear", "enemy_present": true}]
	var status := SupplyCalculator.evaluate_supply_line_status(ss, 100, 2, path)
	check(status == SupplyCalculator.STATUS_BLOCKED, "enemy on path → blocked")


func test_evaluate_status_overextended() -> void:
	var ss := {"supply_base_stronghold_id": "S1"}
	var status := SupplyCalculator.evaluate_supply_line_status(ss, 100, 17, [])
	check(status == SupplyCalculator.STATUS_OVEREXTENDED, "weighted > 16 → overextended")


func test_evaluate_status_in_supply() -> void:
	var ss := {"supply_base_stronghold_id": "S1"}
	var path := [{"terrain": "clear"}, {"terrain": "clear"}]
	var status := SupplyCalculator.evaluate_supply_line_status(ss, 100, 2, path)
	check(status == SupplyCalculator.STATUS_IN_SUPPLY, "clear path within range → in_supply")
