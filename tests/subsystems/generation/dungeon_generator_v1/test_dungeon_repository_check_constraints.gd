extends "res://tests/test_suite_base.gd"

## CHECK-constraint enforcement tests for the migration-132 tables.
##
## Attempts raw inserts with invalid enum values and asserts SQLite rejects
## them (query_with_bindings returns false on a CHECK violation). Also confirms
## the valid values are accepted. Cleans up any successful inserts.


const _CC_DUNGEON := "test_dg_check_constraints"


func run_all_tests() -> void:
	_cleanup()
	test_invalid_contents_kind_rejected()
	test_invalid_door_type_rejected()
	test_invalid_door_material_rejected()
	test_invalid_treasure_source_rejected()
	test_invalid_placed_in_rejected()
	test_valid_enum_values_accepted()
	test_empty_string_door_material_accepted_for_arches()
	_cleanup()
	if not has_failures():
		print("DungeonRepositoryCheckConstraints: all tests passed.")


# ---------------------------------------------------------------------------
# Rejection tests
# ---------------------------------------------------------------------------

func test_invalid_contents_kind_rejected() -> void:
	var ok := CampaignRepository.db.query_with_bindings(
		"""INSERT INTO dungeon_rooms
			(id, dungeon_id, floor_id, room_id_in_floor, bounds_x, bounds_y, bounds_w, bounds_h, contents_kind)
		   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
		[_gen_id(), _CC_DUNGEON, "f1", 0, 1, 1, 3, 3, "NOT_A_KIND"])
	check(not ok, "invalid contents_kind should be rejected by CHECK")


func test_invalid_door_type_rejected() -> void:
	var ok := CampaignRepository.db.query_with_bindings(
		"""INSERT INTO dungeon_doors
			(id, dungeon_id, floor_id, position_x, position_y, type)
		   VALUES (?, ?, ?, ?, ?, ?)""",
		[_gen_id(), _CC_DUNGEON, "f1", 5, 5, "banana"])
	check(not ok, "invalid door type should be rejected by CHECK")


func test_invalid_door_material_rejected() -> void:
	var ok := CampaignRepository.db.query_with_bindings(
		"""INSERT INTO dungeon_doors
			(id, dungeon_id, floor_id, position_x, position_y, type, door_material)
		   VALUES (?, ?, ?, ?, ?, ?, ?)""",
		[_gen_id(), _CC_DUNGEON, "f1", 6, 6, "locked", "adamantium"])
	check(not ok, "invalid door_material should be rejected by CHECK")


func test_invalid_treasure_source_rejected() -> void:
	var ok := CampaignRepository.db.query_with_bindings(
		"""INSERT INTO treasure_hoards
			(id, dungeon_id, floor_id, room_id, source)
		   VALUES (?, ?, ?, ?, ?)""",
		[_gen_id(), _CC_DUNGEON, "f1", "r1", "nonsense_source"])
	check(not ok, "invalid treasure source should be rejected by CHECK")


func test_invalid_placed_in_rejected() -> void:
	var ok := CampaignRepository.db.query_with_bindings(
		"""INSERT INTO key_items
			(id, dungeon_id, opens_door_floor_id, opens_door_position_x, opens_door_position_y, placed_in)
		   VALUES (?, ?, ?, ?, ?, ?)""",
		[_gen_id(), _CC_DUNGEON, "f1", 3, 3, "in_my_pocket"])
	check(not ok, "invalid placed_in should be rejected by CHECK")


# ---------------------------------------------------------------------------
# Acceptance tests
# ---------------------------------------------------------------------------

func test_valid_enum_values_accepted() -> void:
	# One valid row per constrained enum.
	check(CampaignRepository.db.query_with_bindings(
		"""INSERT INTO dungeon_rooms
			(id, dungeon_id, floor_id, room_id_in_floor, bounds_x, bounds_y, bounds_w, bounds_h, contents_kind)
		   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
		[_gen_id(), _CC_DUNGEON, "f1", 0, 1, 1, 3, 3, "monster_lair"]),
		"valid contents_kind 'monster_lair' should be accepted")
	check(CampaignRepository.db.query_with_bindings(
		"""INSERT INTO dungeon_doors
			(id, dungeon_id, floor_id, position_x, position_y, type, door_material)
		   VALUES (?, ?, ?, ?, ?, ?, ?)""",
		[_gen_id(), _CC_DUNGEON, "f1", 5, 5, "portcullis", "metal"]),
		"valid door type 'portcullis' + material 'metal' should be accepted")
	check(CampaignRepository.db.query_with_bindings(
		"""INSERT INTO treasure_hoards
			(id, dungeon_id, floor_id, room_id, source)
		   VALUES (?, ?, ?, ?, ?)""",
		[_gen_id(), _CC_DUNGEON, "f1", "r1", "unprotected_trap_placeholder"]),
		"valid treasure source should be accepted")
	check(CampaignRepository.db.query_with_bindings(
		"""INSERT INTO key_items
			(id, dungeon_id, opens_door_floor_id, opens_door_position_x, opens_door_position_y, placed_in)
		   VALUES (?, ?, ?, ?, ?, ?)""",
		[_gen_id(), _CC_DUNGEON, "f1", 3, 3, "monster_group_inventory"]),
		"valid placed_in should be accepted")


func test_empty_string_door_material_accepted_for_arches() -> void:
	# MATERIAL_NONE ("") is a legal door_material (arches).
	var ok := CampaignRepository.db.query_with_bindings(
		"""INSERT INTO dungeon_doors
			(id, dungeon_id, floor_id, position_x, position_y, type, door_material)
		   VALUES (?, ?, ?, ?, ?, ?, ?)""",
		[_gen_id(), _CC_DUNGEON, "f1", 7, 7, "arch", ""])
	check(ok, "empty-string door_material (arch / MATERIAL_NONE) should be accepted")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _gen_id() -> String:
	return CampaignRepository.generate_id()


func _cleanup() -> void:
	for table in ["dungeon_rooms", "dungeon_doors", "treasure_hoards", "key_items",
			"monster_groups", "dungeon_floors"]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM %s WHERE dungeon_id = ?" % table, [_CC_DUNGEON])
