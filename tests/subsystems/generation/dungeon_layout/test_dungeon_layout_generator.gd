extends "res://tests/test_suite_base.gd"

## End-to-end tests for DungeonLayoutGenerator.generate().
##
## Exercises the full pipeline for each dungeon_size, validates the output
## DungeonLayout's structural invariants, and confirms determinism +
## theme-catalog fallback per V1 GDD §7.1.


func run_all_tests() -> void:
	test_theme_catalog_returns_wizards_dungeon_natively()
	test_theme_catalog_falls_back_for_unknown_type()
	test_generate_lair_size_produces_layout()
	test_generate_small_size_produces_layout()
	test_generate_medium_size_produces_layout()
	test_generate_large_size_produces_layout()
	test_generate_is_deterministic_for_same_seed()
	test_generate_assigns_room_purposes()
	test_generate_marks_entrance_stair_when_is_entrance_floor()
	test_generated_doors_have_valid_types()
	test_generated_stairs_have_valid_directions()
	test_unknown_dungeon_type_falls_back_to_wizards_dungeon()
	if not has_failures():
		print("DungeonLayoutGenerator: all tests passed.")


# ---------------------------------------------------------------------------
# Theme catalog
# ---------------------------------------------------------------------------

func test_theme_catalog_returns_wizards_dungeon_natively() -> void:
	check(DungeonThemeCatalog.has_theme("wizards_dungeon"),
		"catalog should know wizards_dungeon natively")
	var t: DungeonTheme = DungeonThemeCatalog.get_theme("wizards_dungeon")
	check(t != null, "wizards_dungeon theme should not be null")
	check(t.type_name == "Wizard's Dungeon",
		"type_name should be 'Wizard's Dungeon', got '%s'" % t.type_name)
	check(t.encounter_flavor.is_empty(),
		"Wizard's Dungeon encounter_flavor should be empty per §5.3 exception")
	check(not t.door_type_weights.is_empty(),
		"Wizard's Dungeon should have door_type_weights populated")


func test_theme_catalog_falls_back_for_unknown_type() -> void:
	check(not DungeonThemeCatalog.has_theme("tomb"),
		"tomb should NOT be natively known in DG-V1.B-base")
	var t: DungeonTheme = DungeonThemeCatalog.get_theme("tomb")
	check(t != null, "fallback theme should not be null")
	check(t.type_name == "Wizard's Dungeon",
		"unknown type should fall back to wizards_dungeon per V1 GDD §7.1")


# ---------------------------------------------------------------------------
# Per-size generation
# ---------------------------------------------------------------------------

func test_generate_lair_size_produces_layout() -> void:
	var layout: DungeonLayout = _generate("lair", 100)
	check(layout != null, "lair-size generation should succeed")
	check(layout.grid_width == 21, "lair grid_width should be 21, got %d" % layout.grid_width)
	check(layout.grid_height == 21, "lair grid_height should be 21, got %d" % layout.grid_height)
	check(layout.rooms.size() >= 1, "lair should have at least 1 room; got %d" % layout.rooms.size())


func test_generate_small_size_produces_layout() -> void:
	var layout: DungeonLayout = _generate("small", 101)
	check(layout != null, "small-size generation should succeed")
	check(layout.grid_width == 31, "small grid_width should be 31, got %d" % layout.grid_width)


func test_generate_medium_size_produces_layout() -> void:
	var layout: DungeonLayout = _generate("medium", 102)
	check(layout != null, "medium-size generation should succeed")
	check(layout.grid_width == 51, "medium grid_width should be 51, got %d" % layout.grid_width)
	# Medium dungeons should produce several rooms — be permissive on bounds.
	check(layout.rooms.size() >= 3,
		"medium should produce at least 3 rooms; got %d" % layout.rooms.size())


func test_generate_large_size_produces_layout() -> void:
	var layout: DungeonLayout = _generate("large", 103)
	check(layout != null, "large-size generation should succeed")
	check(layout.grid_width == 79, "large grid_width should be 79, got %d" % layout.grid_width)
	check(layout.rooms.size() >= 5,
		"large should produce at least 5 rooms; got %d" % layout.rooms.size())


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------

func test_generate_is_deterministic_for_same_seed() -> void:
	# Same seed → same room count, door count, stair count, room cell counts.
	# (We don't compare the full layouts because RefCounted equality is by
	# identity, not structure — but the headline counts are sufficient
	# evidence of byte-stable behavior.)
	var a: DungeonLayout = _generate("small", 9999)
	var b: DungeonLayout = _generate("small", 9999)
	check(a.rooms.size() == b.rooms.size(),
		"determinism: room count differs %d vs %d" % [a.rooms.size(), b.rooms.size()])
	check(a.doors.size() == b.doors.size(),
		"determinism: door count differs %d vs %d" % [a.doors.size(), b.doors.size()])
	check(a.stairs.size() == b.stairs.size(),
		"determinism: stair count differs %d vs %d" % [a.stairs.size(), b.stairs.size()])
	for i in a.rooms.size():
		check(a.rooms[i].cells.size() == b.rooms[i].cells.size(),
			"determinism: room %d cell count differs %d vs %d"
				% [i, a.rooms[i].cells.size(), b.rooms[i].cells.size()])


# ---------------------------------------------------------------------------
# Per-feature checks
# ---------------------------------------------------------------------------

func test_generate_assigns_room_purposes() -> void:
	var layout: DungeonLayout = _generate("medium", 555)
	# Every room should have a non-empty original_purpose from the Wizard's
	# Dungeon purpose table.
	var wizards_purposes: Array = DungeonThemeCatalog.get_theme("wizards_dungeon").purpose_weights.keys()
	for r in layout.rooms:
		check(not r.original_purpose.is_empty(),
			"room %d should have non-empty original_purpose" % r.id)
		check(r.original_purpose in wizards_purposes,
			"room %d original_purpose '%s' should be from wizards_dungeon purpose table"
				% [r.id, r.original_purpose])


func test_generate_marks_entrance_stair_when_is_entrance_floor() -> void:
	var req := DungeonLayoutRequest.new()
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "small"
	req.level_number = 1
	req.seed = 1000
	req.stairs_up = 1
	req.stairs_down = 1
	req.is_entrance_floor = true
	var layout: DungeonLayout = DungeonLayoutGenerator.generate(req)
	check(layout != null, "generate should not return null")
	check(layout.entrance != Vector2i(-1, -1),
		"entrance should be set on entrance floor, got %s" % str(layout.entrance))
	# At least one stair should have is_entrance_stair = true.
	var entrance_stair_count: int = 0
	for s in layout.stairs:
		if s.is_entrance_stair:
			entrance_stair_count += 1
	check(entrance_stair_count == 1,
		"exactly 1 stair should be flagged is_entrance_stair, got %d" % entrance_stair_count)


func test_generated_doors_have_valid_types() -> void:
	var layout: DungeonLayout = _generate("medium", 333)
	for d in layout.doors:
		check(d.type in DungeonDoorData.VALID_TYPES,
			"door at %s has invalid type '%s'" % [d.position, d.type])
		check(not d.position == Vector2i(-1, -1),
			"door should have a non-default position")


func test_generated_stairs_have_valid_directions() -> void:
	var layout: DungeonLayout = _generate("medium", 222)
	check(layout.stairs.size() > 0, "medium dungeon should have at least 1 stair")
	for s in layout.stairs:
		check(s.direction in DungeonStairData.VALID_DIRECTIONS,
			"stair at %s has invalid direction '%s'" % [s.position, s.direction])


func test_unknown_dungeon_type_falls_back_to_wizards_dungeon() -> void:
	# Per V1 GDD §7.1: any unknown dungeon_type falls back to wizards_dungeon.
	var req := DungeonLayoutRequest.new()
	req.dungeon_type = "made_up_type"
	req.dungeon_size = "small"
	req.seed = 12345
	var layout: DungeonLayout = DungeonLayoutGenerator.generate(req)
	check(layout != null, "fallback path should still produce a layout")
	# The layout records the REQUESTED dungeon_type (not the fallback);
	# downstream systems see "made_up_type" and can log it. The theme used
	# internally is wizards_dungeon, but layout.dungeon_type preserves
	# the request. The theme reference confirms the actual theme used.
	check(layout.theme.type_name == "Wizard's Dungeon",
		"theme used should be Wizard's Dungeon (fallback), got '%s'" % layout.theme.type_name)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _generate(size: String, seed: int) -> DungeonLayout:
	var req := DungeonLayoutRequest.new()
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = size
	req.level_number = 1
	req.seed = seed
	req.stairs_up = 1
	req.stairs_down = 1
	req.is_entrance_floor = true
	return DungeonLayoutGenerator.generate(req)
