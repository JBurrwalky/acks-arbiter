extends "res://tests/test_suite_base.gd"

## Round-trip persistence tests for DungeonGeneratorRepository — DG-V1.D stocking tables.
##
## Verifies that monster_groups, treasure_hoards, and key_items survive a full
## insert → reload cycle and that delete_dungeon_layout removes all three.
## The DB-setup pattern (open / migrate / shared db handle) is inherited from
## the test_suite_base; no campaign fixture is needed (dungeon tables are
## self-contained with no FK to campaigns).


func run_all_tests() -> void:
	test_monster_group_roundtrip()
	test_treasure_hoard_roundtrip()
	test_key_item_roundtrip()
	test_null_treasure_type_letter()
	test_json_arrays_survive()
	test_delete_removes_stocking_rows()
	if not has_failures():
		print("DungeonRepositoryStockedRoundtrip: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_monster_group_roundtrip() -> void:
	var dungeon_id := _unique_id("mg_rt")

	# Two groups: one lair (with treasure letter + associated_creatures), one patrol.
	var g1 := MonsterGroupData.new()
	g1.floor_index = 1
	g1.room_id = 2
	g1.monster_name = "Goblin"
	g1.monster_xp_each = 5
	g1.number_appearing = 8
	g1.hd = "1d8-1"
	g1.associated_creatures = [{"name": "Goblin Chief", "number_appearing": 1, "xp_each": 13}]
	g1.is_lair = true
	g1.morale = -1
	g1.alignment = "Chaotic"
	g1.treasure_type_letter = "C"
	g1.initial_inventory = [{"item_type": "key", "key_id": "k1"}]

	var g2 := MonsterGroupData.new()
	g2.floor_index = 1
	g2.room_id = 5
	g2.monster_name = "Orc"
	g2.monster_xp_each = 10
	g2.number_appearing = 4
	g2.hd = "1"
	g2.associated_creatures = []
	g2.is_lair = false
	g2.morale = 0
	g2.alignment = "Chaotic"
	g2.treasure_type_letter = ""   # no treasure → should round-trip as ""
	g2.initial_inventory = []

	var layout := _minimal_layout(1)
	layout.monster_groups = [g1, g2]

	DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [layout])
	var loaded := DungeonGeneratorRepository.get_dungeon_layout(dungeon_id)
	check(loaded.size() == 1, "should reload 1 floor")
	if loaded.size() == 1:
		var groups := loaded[0].monster_groups
		check(groups.size() == 2, "should have 2 monster groups, got %d" % groups.size())
		var by_room: Dictionary = {}
		for g in groups:
			by_room[g.room_id] = g
		check(by_room.has(2), "group in room 2 should be present")
		if by_room.has(2):
			var r1: MonsterGroupData = by_room[2]
			check(r1.is_lair, "group in room 2 should be is_lair")
			check(r1.treasure_type_letter == "C", "treasure_type_letter 'C' should round-trip")
			check(r1.monster_name == "Goblin", "monster_name should round-trip")
			check(r1.morale == -1, "morale -1 should round-trip")
		check(by_room.has(5), "group in room 5 should be present")
		if by_room.has(5):
			var r2: MonsterGroupData = by_room[5]
			check(not r2.is_lair, "patrol group should not be is_lair")
			check(r2.treasure_type_letter == "", "empty treasure_type_letter should round-trip as ''")
	DungeonGeneratorRepository.delete_dungeon_layout(dungeon_id)


func test_treasure_hoard_roundtrip() -> void:
	var dungeon_id := _unique_id("th_rt")

	# One lair hoard with letter, one unprotected_empty with no letter, is_hidden.
	var h1 := TreasureHoardData.new()
	h1.floor_index = 1
	h1.room_id = 3
	h1.source = TreasureHoardData.SOURCE_LAIR
	h1.treasure_type_letter = "D"
	h1.copper = 100
	h1.silver = 50
	h1.electrum = 10
	h1.gold = 200
	h1.platinum = 5
	h1.gems = [{"value_gp": 100, "gem_class": "ornamental"}]
	h1.jewelry = [{"value_gp": 500, "jewelry_class": "mundane"}]
	h1.magic_items = [{"category": "sword", "specific_item_id": "", "is_placeholder": true, "notes": ""}]
	h1.total_gp_value = 1250
	h1.is_hidden = false

	var h2 := TreasureHoardData.new()
	h2.floor_index = 1
	h2.room_id = 7
	h2.source = TreasureHoardData.SOURCE_UNPROTECTED_EMPTY
	h2.treasure_type_letter = ""   # unprotected_empty hoards have no letter
	h2.copper = 0
	h2.silver = 0
	h2.electrum = 0
	h2.gold = 0
	h2.platinum = 0
	h2.gems = []
	h2.jewelry = []
	h2.magic_items = []
	h2.total_gp_value = 0
	h2.is_hidden = true

	var layout := _minimal_layout(1)
	layout.treasure_hoards = [h1, h2]

	DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [layout])
	var loaded := DungeonGeneratorRepository.get_dungeon_layout(dungeon_id)
	check(loaded.size() == 1, "should reload 1 floor")
	if loaded.size() == 1:
		var hoards := loaded[0].treasure_hoards
		check(hoards.size() == 2, "should have 2 treasure hoards, got %d" % hoards.size())
		var by_room: Dictionary = {}
		for h in hoards:
			by_room[h.room_id] = h
		check(by_room.has(3), "hoard in room 3 should be present")
		if by_room.has(3):
			var r1: TreasureHoardData = by_room[3]
			check(r1.treasure_type_letter == "D", "treasure_type_letter 'D' should round-trip")
			check(r1.copper == 100, "copper should round-trip")
			check(r1.silver == 50, "silver should round-trip")
			check(r1.electrum == 10, "electrum should round-trip")
			check(r1.gold == 200, "gold should round-trip")
			check(r1.platinum == 5, "platinum should round-trip")
			check(r1.total_gp_value == 1250, "total_gp_value should round-trip")
			check(not r1.is_hidden, "is_hidden false should round-trip")
		check(by_room.has(7), "hoard in room 7 should be present")
		if by_room.has(7):
			var r2: TreasureHoardData = by_room[7]
			check(r2.treasure_type_letter == "", "empty treasure_type_letter should round-trip as ''")
			check(r2.is_hidden, "is_hidden true should round-trip")
			check(r2.source == TreasureHoardData.SOURCE_UNPROTECTED_EMPTY, "source should round-trip")
	DungeonGeneratorRepository.delete_dungeon_layout(dungeon_id)


func test_key_item_roundtrip() -> void:
	var dungeon_id := _unique_id("ki_rt")

	# Two floors.
	var layout1 := _minimal_layout(1)
	var layout2 := _minimal_layout(2)

	# Key 1: placed on floor 1 (in a monster inventory), opens door on floor 2.
	var k1 := KeyItemData.new()
	k1.opens_door_floor_index = 2
	k1.opens_door_position = Vector2i(10, 15)
	k1.placed_in = KeyItemData.PLACED_MONSTER_INV
	k1.placed_in_room_id = 3
	k1.placed_on_floor_index = 1

	# Key 2: loose in a room on floor 2, placed_in_room_id < 0 (unassigned) -> NULL.
	var k2 := KeyItemData.new()
	k2.opens_door_floor_index = 2
	k2.opens_door_position = Vector2i(5, 5)
	k2.placed_in = KeyItemData.PLACED_LOOSE
	k2.placed_in_room_id = -1    # should persist as NULL and come back as -1
	k2.placed_on_floor_index = 2

	DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [layout1, layout2], [k1, k2])
	var keys := DungeonGeneratorRepository.get_key_items(dungeon_id)
	check(keys.size() == 2, "should have 2 key items, got %d" % keys.size())

	# Sort by opens_door_position for deterministic comparison.
	var by_pos: Dictionary = {}
	for key in keys:
		by_pos[key.opens_door_position] = key

	check(by_pos.has(Vector2i(10, 15)), "key for door at (10,15) should be present")
	if by_pos.has(Vector2i(10, 15)):
		var rk1: KeyItemData = by_pos[Vector2i(10, 15)]
		check(rk1.opens_door_floor_index == 2, "k1 opens_door_floor_index should be 2")
		check(rk1.placed_in == KeyItemData.PLACED_MONSTER_INV, "k1 placed_in should round-trip")
		check(rk1.placed_in_room_id == 3, "k1 placed_in_room_id 3 should round-trip")
		check(rk1.placed_on_floor_index == 1, "k1 placed_on_floor_index should be 1")

	check(by_pos.has(Vector2i(5, 5)), "key for door at (5,5) should be present")
	if by_pos.has(Vector2i(5, 5)):
		var rk2: KeyItemData = by_pos[Vector2i(5, 5)]
		check(rk2.placed_in == KeyItemData.PLACED_LOOSE, "k2 placed_in should round-trip")
		check(rk2.placed_in_room_id == -1, "k2 placed_in_room_id NULL should come back as -1")
		check(rk2.placed_on_floor_index == 2, "k2 placed_on_floor_index should be 2")

	DungeonGeneratorRepository.delete_dungeon_layout(dungeon_id)


func test_null_treasure_type_letter() -> void:
	# Explicit regression: treasure_type_letter "" -> NULL in DB -> "" on reload.
	var dungeon_id := _unique_id("ttl_null")
	var g := MonsterGroupData.new()
	g.floor_index = 1
	g.room_id = 1
	g.monster_name = "Skeleton"
	g.monster_xp_each = 6
	g.number_appearing = 3
	g.hd = "1"
	g.is_lair = false
	g.morale = 0
	g.alignment = "Chaotic"
	g.treasure_type_letter = ""   # should persist as NULL
	var layout := _minimal_layout(1)
	layout.monster_groups = [g]
	DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [layout])
	var loaded := DungeonGeneratorRepository.get_dungeon_layout(dungeon_id)
	if loaded.size() == 1 and loaded[0].monster_groups.size() == 1:
		var reloaded: MonsterGroupData = loaded[0].monster_groups[0]
		check(reloaded.treasure_type_letter == "",
			"NULL treasure_type_letter should deserialize as empty string, got '%s'" % reloaded.treasure_type_letter)
	else:
		check(false, "expected 1 floor with 1 monster group")
	DungeonGeneratorRepository.delete_dungeon_layout(dungeon_id)


func test_json_arrays_survive() -> void:
	# Verify associated_creatures, initial_inventory, gems, jewelry, magic_items
	# all survive the JSON serialize → store → reload cycle.
	var dungeon_id := _unique_id("json_rt")
	var g := MonsterGroupData.new()
	g.floor_index = 1
	g.room_id = 1
	g.monster_name = "Gnoll"
	g.monster_xp_each = 20
	g.number_appearing = 5
	g.hd = "2"
	g.is_lair = true
	g.morale = 1
	g.alignment = "Chaotic"
	g.treasure_type_letter = "B"
	g.associated_creatures = [
		{"name": "Hyena", "number_appearing": 2, "xp_each": 5},
		{"name": "Gnoll Chieftain", "number_appearing": 1, "xp_each": 29},
	]
	g.initial_inventory = [{"item_type": "key", "key_id": "testkey"}]

	var h := TreasureHoardData.new()
	h.floor_index = 1
	h.room_id = 1
	h.source = TreasureHoardData.SOURCE_LAIR
	h.treasure_type_letter = "B"
	h.copper = 0; h.silver = 0; h.electrum = 0; h.gold = 300; h.platinum = 0
	h.gems = [{"value_gp": 50, "gem_class": "ornamental"}, {"value_gp": 100, "gem_class": "semi-precious"}]
	h.jewelry = [{"value_gp": 200, "jewelry_class": "mundane"}]
	h.magic_items = [{"category": "potion", "specific_item_id": "healing", "is_placeholder": false, "notes": ""}]
	h.total_gp_value = 650
	h.is_hidden = false

	var layout := _minimal_layout(1)
	layout.monster_groups = [g]
	layout.treasure_hoards = [h]
	DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [layout])

	var loaded := DungeonGeneratorRepository.get_dungeon_layout(dungeon_id)
	check(loaded.size() == 1, "1 floor expected")
	if loaded.size() == 1:
		if loaded[0].monster_groups.size() == 1:
			var rg: MonsterGroupData = loaded[0].monster_groups[0]
			check(rg.associated_creatures.size() == 2,
				"associated_creatures should have 2 entries, got %d" % rg.associated_creatures.size())
			check(rg.initial_inventory.size() == 1,
				"initial_inventory should have 1 entry, got %d" % rg.initial_inventory.size())
		else:
			check(false, "expected 1 monster group")
		if loaded[0].treasure_hoards.size() == 1:
			var rh: TreasureHoardData = loaded[0].treasure_hoards[0]
			check(rh.gems.size() == 2, "gems should have 2 entries, got %d" % rh.gems.size())
			check(rh.jewelry.size() == 1, "jewelry should have 1 entry, got %d" % rh.jewelry.size())
			check(rh.magic_items.size() == 1, "magic_items should have 1 entry, got %d" % rh.magic_items.size())
		else:
			check(false, "expected 1 treasure hoard")
	DungeonGeneratorRepository.delete_dungeon_layout(dungeon_id)


func test_delete_removes_stocking_rows() -> void:
	# delete_dungeon_layout must cascade to monster_groups, treasure_hoards, key_items.
	var dungeon_id := _unique_id("del_stock")
	var g := MonsterGroupData.new()
	g.floor_index = 1; g.room_id = 1; g.monster_name = "Rat"
	g.monster_xp_each = 5; g.number_appearing = 6; g.hd = "1d4 hp"
	g.is_lair = false; g.morale = -2; g.alignment = "Neutral"

	var h := TreasureHoardData.new()
	h.floor_index = 1; h.room_id = 1
	h.source = TreasureHoardData.SOURCE_UNPROTECTED_EMPTY
	h.total_gp_value = 0; h.is_hidden = true

	var layout := _minimal_layout(1)
	layout.monster_groups = [g]
	layout.treasure_hoards = [h]

	var k := KeyItemData.new()
	k.opens_door_floor_index = 1; k.opens_door_position = Vector2i(3, 3)
	k.placed_in = KeyItemData.PLACED_LOOSE; k.placed_in_room_id = -1
	k.placed_on_floor_index = 1

	DungeonGeneratorRepository.insert_dungeon_layout(dungeon_id, [layout], [k])

	# Verify rows exist before delete.
	check(_count_rows("monster_groups", dungeon_id) == 1, "1 monster_group row expected before delete")
	check(_count_rows("treasure_hoards", dungeon_id) == 1, "1 treasure_hoard row expected before delete")
	check(_count_rows("key_items", dungeon_id) == 1, "1 key_item row expected before delete")

	DungeonGeneratorRepository.delete_dungeon_layout(dungeon_id)

	check(_count_rows("monster_groups", dungeon_id) == 0, "monster_groups should be empty after delete")
	check(_count_rows("treasure_hoards", dungeon_id) == 0, "treasure_hoards should be empty after delete")
	check(_count_rows("key_items", dungeon_id) == 0, "key_items should be empty after delete")
	check(_count_rows("dungeon_floors", dungeon_id) == 0, "dungeon_floors should be empty after delete")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build the simplest valid DungeonLayout for a given level number.
## Uses a 21×21 (lair-sized) blank grid so the insert succeeds without needing
## the full generator pipeline.
func _minimal_layout(level: int) -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.dungeon_id = ""
	layout.dungeon_type = "wizards_dungeon"
	layout.dungeon_size = "lair"
	layout.structure_type = "subterranean"
	layout.level_number = level
	layout.floor_tier = level
	layout.is_entrance_floor = (level == 1)
	layout.grid_width = 21
	layout.grid_height = 21
	layout.entrance = Vector2i(0, 0)
	layout.generation_seed = 1000 + level
	# Build a blank cell grid.
	layout.cells = []
	for x in layout.grid_width:
		var col: Array[DungeonCellData] = []
		for y in layout.grid_height:
			col.append(DungeonCellData.new())
		layout.cells.append(col)
	layout.rooms = []
	layout.doors = []
	layout.stairs = []
	layout.monster_groups = []
	layout.treasure_hoards = []
	return layout


func _unique_id(prefix: String) -> String:
	return "test_stk_%s_%d" % [prefix, randi()]


func _count_rows(table: String, dungeon_id: String) -> int:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT COUNT(*) AS n FROM %s WHERE dungeon_id = ?" % table, [dungeon_id]):
		return -1
	return int(CampaignRepository.db.query_result[0]["n"])
