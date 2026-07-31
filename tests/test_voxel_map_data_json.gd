extends "res://tests/test_suite_base.gd"

## Unit tests for VoxelMapData JSON serialization (from_dict, to_dict, file I/O).


func run_all_tests() -> void:
	test_from_dict_populates_cells()
	test_to_dict_roundtrip()
	test_from_dict_empty_cells()
	test_id_name_theme_preserved()
	test_entry_pos_preserved()
	test_tileset_and_seed_preserved()
	test_load_test_dungeon()
	test_load_nonexistent_returns_null()
	if not has_failures():
		print("VoxelMapDataJson: all tests passed.")


func test_from_dict_populates_cells() -> void:
	var data := {
		"id": "test", "name": "Test Map",
		"cells": [
			{"col": 0, "row": 0, "level": 0, "solidity": "air", "feature": "open", "floor_type": "stone"},
			{"col": 1, "row": 0, "level": 0, "solidity": "solid", "feature": "wall_stone"},
			{"col": 0, "row": 0, "level": 1, "solidity": "air", "feature": "open", "floor_type": "wood"},
		],
	}
	var map := VoxelMapData.from_dict(data)
	check(map.cell_count() == 3, "should have 3 cells, got %d" % map.cell_count())
	var c := map.get_cell(Vector3i(1, 0, 0))
	check(c.solidity == "solid", "cell at (1,0,0) should be solid")
	check(c.feature == "wall_stone", "cell at (1,0,0) feature should be wall_stone")


func test_to_dict_roundtrip() -> void:
	var map := VoxelMapData.new()
	map.id = "roundtrip_test"
	map.name = "Round Trip"
	map.theme = "tomb"
	map.entry_pos = Vector3i(3, 4, 2)

	var cell := VoxelCell.new()
	cell.solidity = "liquid"
	cell.feature = "water_deep"
	cell.floor_type = "stone"
	cell.fog_state = "explored"
	map.set_cell(Vector3i(5, 5, 0), cell)

	var dict := map.to_dict()
	var map2 := VoxelMapData.from_dict(dict)

	check(map2.id == "roundtrip_test", "id should survive round-trip")
	check(map2.name == "Round Trip", "name should survive round-trip")
	check(map2.cell_count() == 1, "should have 1 cell after round-trip")
	var c2 := map2.get_cell(Vector3i(5, 5, 0))
	check(c2.solidity == "liquid", "solidity should survive round-trip")
	check(c2.feature == "water_deep", "feature should survive round-trip")
	check(c2.fog_state == "explored", "fog_state should survive round-trip")


func test_from_dict_empty_cells() -> void:
	var map := VoxelMapData.from_dict({"cells": []})
	check(map.cell_count() == 0, "empty cells array should produce 0 cells")


func test_id_name_theme_preserved() -> void:
	var data := {"id": "abc", "name": "Test", "theme": "crypt", "cells": []}
	var map := VoxelMapData.from_dict(data)
	check(map.id == "abc", "id should be preserved")
	check(map.name == "Test", "name should be preserved")
	check(map.theme == "crypt", "theme should be preserved")

	var dict := map.to_dict()
	check(dict["id"] == "abc", "id should survive to_dict")
	check(dict["name"] == "Test", "name should survive to_dict")
	check(dict["theme"] == "crypt", "theme should survive to_dict")


func test_entry_pos_preserved() -> void:
	var data := {
		"entry": {"col": 7, "row": 3, "level": 2},
		"cells": [],
	}
	var map := VoxelMapData.from_dict(data)
	check(map.entry_pos == Vector3i(7, 3, 2),
		"entry_pos should be (7,3,2), got %s" % str(map.entry_pos))

	var dict := map.to_dict()
	var e: Dictionary = dict["entry"]
	check(e["col"] == 7, "entry col in to_dict")
	check(e["row"] == 3, "entry row in to_dict")
	check(e["level"] == 2, "entry level in to_dict")


func test_tileset_and_seed_preserved() -> void:
	var data := {
		"tileset_group": "natural_excavated",
		"generation_seed": 42,
		"cells": [],
	}
	var map := VoxelMapData.from_dict(data)
	check(map.tileset_group == "natural_excavated", "tileset_group preserved")
	check(map.generation_seed == 42, "generation_seed preserved")

	var dict := map.to_dict()
	check(dict["tileset_group"] == "natural_excavated", "tileset_group in to_dict")
	check(dict["generation_seed"] == 42, "generation_seed in to_dict")


func test_load_test_dungeon() -> void:
	var map := VoxelMapData.load_from_file("res://data/test_dungeon.json")
	check(map != null, "should load test_dungeon.json successfully")
	if map == null:
		return
	check(map.id == "test_dungeon_goblin_warrens", "id should match")
	check(map.cell_count() > 100, "should have > 100 cells, got %d" % map.cell_count())
	check(map.entry_pos == Vector3i(2, 5, 0),
		"entry_pos should be (2,5,0), got %s" % str(map.entry_pos))

	# Verify the entry cell is walkable
	var entry_cell := map.get_cell(map.entry_pos)
	check(entry_cell.solidity == "air", "entry cell should be air")
	check(entry_cell.floor_type == "stone", "entry cell should have stone floor")

	# Verify both bands exist (composed two-band volume: entrance band walks at
	# level 0 with headroom 1; the deeper band walks at -2 with headroom -1).
	var levels := map.get_levels()
	check(0 in levels, "entrance band walk level 0 should exist")
	check(-2 in levels, "deeper band walk level -2 should exist")


func test_load_nonexistent_returns_null() -> void:
	var map := VoxelMapData.load_from_file("res://nonexistent_file.json")
	check(map == null, "loading nonexistent file should return null")
