extends "res://tests/test_suite_base.gd"

## Cascade-delete tests for DungeonGeneratorRepository.
##
## Verifies delete_dungeon_layout removes every row for a dungeon_id across all
## six tables, and that deleting one dungeon leaves another dungeon's rows intact.


const _ALL_TABLES := [
	"dungeon_floors", "dungeon_rooms", "dungeon_doors",
	"monster_groups", "treasure_hoards", "key_items",
]


func run_all_tests() -> void:
	test_delete_removes_all_rows()
	test_delete_includes_stocking_tables()
	test_delete_is_scoped_to_one_dungeon()
	if not has_failures():
		print("DungeonRepositoryCascadeDelete: all tests passed.")


func test_delete_removes_all_rows() -> void:
	var dungeon_id := _unique_id("cd_all")
	var layout := _gen("small", 7777)
	DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [layout])
	# Confirm the layout tables have rows.
	check(_count_rows("dungeon_floors", dungeon_id) == 1, "should have 1 floor before delete")
	check(_count_rows("dungeon_rooms", dungeon_id) > 0, "should have rooms before delete")
	check(_count_rows("dungeon_doors", dungeon_id) > 0, "should have doors before delete")
	# Delete.
	var ok := DungeonGeneratorRepository.delete_dungeon_layout(dungeon_id)
	check(ok, "delete_dungeon_layout should return true")
	# Confirm every table is empty for this dungeon.
	for table in _ALL_TABLES:
		check(_count_rows(table, dungeon_id) == 0,
			"%s should have 0 rows after delete, got %d" % [table, _count_rows(table, dungeon_id)])


func test_delete_includes_stocking_tables() -> void:
	# Seed stocking rows directly (DG-V1.D's tables) to prove the cascade
	# covers monster_groups / treasure_hoards / key_items too.
	var dungeon_id := _unique_id("cd_stock")
	var layout := _gen("lair", 13)
	DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [layout])
	var floor_id := str(DungeonGeneratorRepository.list_floors(dungeon_id)[0]["id"])
	_seed_monster_group(dungeon_id, floor_id)
	_seed_treasure_hoard(dungeon_id, floor_id)
	_seed_key_item(dungeon_id, floor_id)
	check(_count_rows("monster_groups", dungeon_id) == 1, "1 monster group seeded")
	check(_count_rows("treasure_hoards", dungeon_id) == 1, "1 treasure hoard seeded")
	check(_count_rows("key_items", dungeon_id) == 1, "1 key item seeded")
	DungeonGeneratorRepository.delete_dungeon_layout(dungeon_id)
	check(_count_rows("monster_groups", dungeon_id) == 0, "monster_groups cleared")
	check(_count_rows("treasure_hoards", dungeon_id) == 0, "treasure_hoards cleared")
	check(_count_rows("key_items", dungeon_id) == 0, "key_items cleared")


func test_delete_is_scoped_to_one_dungeon() -> void:
	var keep_id := _unique_id("cd_keep")
	var drop_id := _unique_id("cd_drop")
	DungeonGeneratorRepository.insert_dungeon_layout(keep_id, [_gen("lair", 1)])
	DungeonGeneratorRepository.insert_dungeon_layout(drop_id, [_gen("lair", 2)])
	DungeonGeneratorRepository.delete_dungeon_layout(drop_id)
	check(_count_rows("dungeon_floors", drop_id) == 0, "dropped dungeon floors gone")
	check(_count_rows("dungeon_floors", keep_id) == 1, "kept dungeon floors intact")
	check(_count_rows("dungeon_rooms", keep_id) > 0, "kept dungeon rooms intact")
	DungeonGeneratorRepository.delete_dungeon_layout(keep_id)  # cleanup


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _gen(size: String, seed: int) -> DungeonLayout:
	var req := DungeonLayoutRequest.new()
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = size
	req.seed = seed
	req.is_entrance_floor = true
	return DungeonLayoutGenerator.generate(req)


func _unique_id(prefix: String) -> String:
	return "test_dg_%s_%d" % [prefix, randi()]


func _count_rows(table: String, dungeon_id: String) -> int:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT COUNT(*) AS n FROM %s WHERE dungeon_id = ?" % table, [dungeon_id]):
		return -1
	return int(CampaignRepository.db.query_result[0]["n"])


func _seed_monster_group(dungeon_id: String, floor_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"""INSERT INTO monster_groups
			(id, dungeon_id, floor_id, room_id, monster_name, number_appearing, is_lair)
		   VALUES (?, ?, ?, ?, ?, ?, ?)""",
		[CampaignRepository.generate_id(), dungeon_id, floor_id, "room0", "Goblin", 4, 1])


func _seed_treasure_hoard(dungeon_id: String, floor_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"""INSERT INTO treasure_hoards (id, dungeon_id, floor_id, room_id, source, gold)
		   VALUES (?, ?, ?, ?, ?, ?)""",
		[CampaignRepository.generate_id(), dungeon_id, floor_id, "room0", "lair", 500])


func _seed_key_item(dungeon_id: String, floor_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"""INSERT INTO key_items (id, dungeon_id, opens_door_floor_id,
			opens_door_position_x, opens_door_position_y, placed_in)
		   VALUES (?, ?, ?, ?, ?, ?)""",
		[CampaignRepository.generate_id(), dungeon_id, floor_id, 5, 5, "loose_in_room"])
