extends "res://tests/test_suite_base.gd"

## Unit tests for TreasurePlacementService (the cell-based treasure placement
## that drives the dungeon generator's container-stocking pass and feeds
## TreasureLootService.materialize_hoard_cell at runtime).
##
## Key constraints (Jedidiah 2026-05-29):
##   - 25% rule: secondary hidden/trapped container holds <=25% of hoard gp.
##   - Trapped-room hoards (source = unprotected_trap_placeholder) go into a
##     trapped (or locked-fallback) chest — the chest IS the trap.
##   - Trap fallback: when opts.traps_available=false, "trapped" emits as
##     locked instead.


func run_all_tests() -> void:
	test_unprotected_trap_room_with_traps_available_emits_trapped_chest()
	test_unprotected_trap_room_with_traps_unavailable_falls_back_to_locked()
	test_lair_no_split_places_single_visible_container()
	test_25_percent_split_secondary_stays_under_cap()
	test_25_percent_split_preserves_total_gp_value()
	test_lair_split_secondary_traps_fall_back_when_unavailable()
	test_magic_item_hoard_uses_opaque_container()
	test_pile_containers_are_never_locked_or_trapped()
	test_cell_placement_uses_provided_room_cells()
	test_empty_room_cells_returns_hoard_unmodified()
	test_unprotected_empty_emits_simple_visible_container()
	test_unprotected_unique_placeholder_emits_visible_container()
	if not has_failures():
		print("TreasurePlacementService: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_lair_hoard(total_gp: int, coins: Dictionary = {}, magic_count: int = 0) -> TreasureHoardData:
	var h := TreasureHoardData.new()
	h.source = TreasureHoardData.SOURCE_LAIR
	h.copper = int(coins.get("copper", 0))
	h.silver = int(coins.get("silver", 0))
	h.electrum = int(coins.get("electrum", 0))
	h.gold = int(coins.get("gold", 0))
	h.platinum = int(coins.get("platinum", 0))
	h.gems = []
	h.jewelry = []
	h.magic_items = []
	for i in range(magic_count):
		h.magic_items.append({"category": "any", "specific_item_id": "", "is_placeholder": true})
	h.total_gp_value = total_gp
	return h


func _rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r


func _room_cells(count: int = 16) -> Array:
	# A small grid of room cells. The placement service treats them as opaque
	# valid floor cells; cells are Vector3i.
	var out: Array = []
	for i in range(count):
		out.append(Vector3i(i % 4, i / 4, 0))
	return out


# ---------------------------------------------------------------------------
# Trapped-room source
# ---------------------------------------------------------------------------

func test_unprotected_trap_room_with_traps_available_emits_trapped_chest() -> void:
	var h := _make_lair_hoard(500, {"gold": 500})
	h.source = TreasureHoardData.SOURCE_UNPROTECTED_TRAP
	var result := TreasurePlacementService.place_hoard(
		h, _room_cells(), _rng(1), {"traps_available": true})
	check(result.size() == 1, "trap room emits a single container")
	var placed: TreasureHoardData = result[0]
	check(placed.container_type == "chest", "trap room uses a chest")
	check(placed.is_trapped == true, "with traps available: is_trapped=true")
	check(placed.is_locked == true, "trapped chests are also locked (you must open to trigger)")
	check(placed.is_hidden == false, "trap rooms aren't typically hidden — the trap IS the point")


func test_unprotected_trap_room_with_traps_unavailable_falls_back_to_locked() -> void:
	var h := _make_lair_hoard(500, {"gold": 500})
	h.source = TreasureHoardData.SOURCE_UNPROTECTED_TRAP
	var result := TreasurePlacementService.place_hoard(
		h, _room_cells(), _rng(2), {"traps_available": false})
	var placed: TreasureHoardData = result[0]
	check(placed.container_type == "chest", "still a chest")
	check(placed.is_trapped == false,
		"trap fallback guardrail: traps_unavailable -> is_trapped=false")
	check(placed.is_locked == true,
		"fallback: a 'would-be-trapped' chest becomes a locked chest")


# ---------------------------------------------------------------------------
# Lair source
# ---------------------------------------------------------------------------

func test_lair_no_split_places_single_visible_container() -> void:
	# A small lair hoard (< SPLIT_MIN_TOTAL_GP) never splits.
	var h := _make_lair_hoard(20, {"gold": 20})
	var result := TreasurePlacementService.place_hoard(h, _room_cells(), _rng(3))
	check(result.size() == 1, "below split threshold: single container")
	var placed: TreasureHoardData = result[0]
	check(placed.container_type in TreasureContainerTypes.VALID,
		"container_type is valid, got '%s'" % placed.container_type)
	check(placed.is_trapped == false, "primary visible container is not trapped")
	check(placed.is_hidden == false, "primary visible container is not hidden")


func test_25_percent_split_secondary_stays_under_cap() -> void:
	# Try many seeds; whenever a split occurs, the secondary must hold <=25%.
	var splits_found := 0
	for seed_val in range(1, 80):
		var h := _make_lair_hoard(1000, {"gold": 1000})
		var result := TreasurePlacementService.place_hoard(h, _room_cells(), _rng(seed_val))
		if result.size() != 2:
			continue
		splits_found += 1
		var primary: TreasureHoardData = result[0]
		var secondary: TreasureHoardData = result[1]
		check(secondary.total_gp_value <= 250,
			"split secondary gp <= 25%% of 1000 = 250, got %d (seed %d)"
				% [secondary.total_gp_value, seed_val])
		check(primary.total_gp_value >= 750,
			"primary gp >= 75%%, got %d (seed %d)"
				% [primary.total_gp_value, seed_val])
	check(splits_found >= 1,
		"across 80 seeds a 1000-gp lair hoard should split at least once (~40%% chance)")


func test_25_percent_split_preserves_total_gp_value() -> void:
	# Across all seeds: primary + secondary gp == original total.
	for seed_val in range(1, 40):
		var h := _make_lair_hoard(800, {"gold": 800})
		var result := TreasurePlacementService.place_hoard(h, _room_cells(), _rng(seed_val))
		if result.size() != 2:
			continue
		var combined: int = result[0].total_gp_value + result[1].total_gp_value
		check(combined == 800,
			"primary + secondary = original total 800, got %d (seed %d)"
				% [combined, seed_val])


func test_lair_split_secondary_traps_fall_back_when_unavailable() -> void:
	# If a split occurs and the secondary "should be trapped," traps_available=false
	# must yield a non-trapped (but locked) secondary.
	for seed_val in range(1, 80):
		var h := _make_lair_hoard(1000, {"gold": 1000})
		var result := TreasurePlacementService.place_hoard(
			h, _room_cells(), _rng(seed_val), {"traps_available": false})
		if result.size() != 2:
			continue
		var secondary: TreasureHoardData = result[1]
		check(secondary.is_trapped == false,
			"with traps_unavailable, secondary.is_trapped must be false (got true at seed %d)" % seed_val)


# ---------------------------------------------------------------------------
# Container selection rules
# ---------------------------------------------------------------------------

func test_magic_item_hoard_uses_opaque_container() -> void:
	# A magic item should always land in an opaque (chest/barrel) container.
	# Splitting may move the magic item to the secondary, so scan ALL output
	# containers to find which one holds it. (For the secondary specifically
	# the container picker prefers chest.)
	for seed_val in range(1, 20):
		var h := _make_lair_hoard(50, {"gold": 50}, 1)
		var result := TreasurePlacementService.place_hoard(h, _room_cells(), _rng(seed_val))
		var magic_container: String = ""
		for placed: TreasureHoardData in result:
			if not placed.magic_items.is_empty():
				magic_container = placed.container_type
				break
		check(magic_container in [TreasureContainerTypes.CHEST, TreasureContainerTypes.BARREL],
			"magic item should land in chest/barrel, got '%s' (seed %d)"
				% [magic_container, seed_val])


func test_pile_containers_are_never_locked_or_trapped() -> void:
	# coin_pile / gear_pile should never carry a lock or trap (they're loose).
	# Scan many seeds with small coin-only hoards; whenever the result is a
	# pile, it must be unlocked + untrapped.
	for seed_val in range(1, 60):
		var h := _make_lair_hoard(5, {"gold": 5})
		var result := TreasurePlacementService.place_hoard(h, _room_cells(), _rng(seed_val))
		for placed: TreasureHoardData in result:
			if placed.container_type == TreasureContainerTypes.COIN_PILE \
					or placed.container_type == TreasureContainerTypes.GEAR_PILE:
				check(placed.is_locked == false,
					"%s is never locked (seed %d)" % [placed.container_type, seed_val])
				check(placed.is_trapped == false,
					"%s is never trapped (seed %d)" % [placed.container_type, seed_val])


# ---------------------------------------------------------------------------
# Cell selection
# ---------------------------------------------------------------------------

func test_cell_placement_uses_provided_room_cells() -> void:
	# The placed cell must be one of the supplied room_cells.
	var cells := _room_cells(4)  # Vector3i(0,0,0), (1,0,0), (2,0,0), (3,0,0)
	var h := _make_lair_hoard(50, {"gold": 50})
	var result := TreasurePlacementService.place_hoard(h, cells, _rng(5))
	var placed: TreasureHoardData = result[0]
	var placed_cell := Vector3i(placed.cell_x, placed.cell_y, placed.cell_z)
	check(placed_cell in cells,
		"placed cell %s should be one of the supplied cells %s" % [placed_cell, cells])


func test_empty_room_cells_returns_hoard_unmodified() -> void:
	# No cells -> the placement service warns and returns the hoard with cell -1.
	var h := _make_lair_hoard(50, {"gold": 50})
	var result := TreasurePlacementService.place_hoard(h, [], _rng(6))
	check(result.size() == 1, "empty cells: still returns the hoard")
	check(int(result[0].cell_x) == -1, "cell_x stays at the -1 sentinel")
	check(result[0].container_type == "",
		"container_type stays unassigned when there are no cells to place into")


# ---------------------------------------------------------------------------
# Other sources
# ---------------------------------------------------------------------------

func test_unprotected_empty_emits_simple_visible_container() -> void:
	var h := _make_lair_hoard(0)
	h.source = TreasureHoardData.SOURCE_UNPROTECTED_EMPTY
	var result := TreasurePlacementService.place_hoard(h, _room_cells(), _rng(7))
	check(result.size() == 1, "single placement for unprotected_empty")
	var placed: TreasureHoardData = result[0]
	check(placed.container_type in TreasureContainerTypes.VALID, "valid container_type")
	check(placed.is_trapped == false and placed.is_hidden == false and placed.is_locked == false,
		"unprotected_empty is plain visible container — no lock/trap/hide")


func test_unprotected_unique_placeholder_emits_visible_container() -> void:
	var h := _make_lair_hoard(100, {"gold": 100})
	h.source = TreasureHoardData.SOURCE_UNPROTECTED_UNIQUE
	var result := TreasurePlacementService.place_hoard(h, _room_cells(), _rng(8))
	check(result.size() == 1, "single placement for unprotected_unique_placeholder")
	check(result[0].is_trapped == false and result[0].is_hidden == false,
		"unique placeholder is plain visible — no trap/hide")
