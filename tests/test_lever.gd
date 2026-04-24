extends "res://tests/test_suite_base.gd"

## Lever / portcullis linkage tests.
##
## Covers VoxelMapData.get_lever_target() and the JSON round-trip for
## lever_links. The full _resolve_use_lever handler flow (adjacency, state
## toggle, signal emit) is exercised by the dungeon integration smoke test —
## the handler has too many scene-tree dependencies to unit-test headlessly
## without heavy mocking.


func run_all_tests() -> void:
	test_get_lever_target_returns_sentinel_when_unlinked()
	test_set_lever_link_registers_target()
	test_lever_links_round_trip_through_json()

	if not has_failures():
		print("Lever: all tests passed.")


func test_get_lever_target_returns_sentinel_when_unlinked() -> void:
	var map := VoxelMapData.new()
	var result := map.get_lever_target(Vector3i(5, 15, 0))
	check(result == Vector3i(-1, -1, -1), "unlinked lever returns sentinel")


func test_set_lever_link_registers_target() -> void:
	var map := VoxelMapData.new()
	map.set_lever_link(Vector3i(5, 15, 0), Vector3i(6, 15, 0))
	var result := map.get_lever_target(Vector3i(5, 15, 0))
	check(result == Vector3i(6, 15, 0), "set_lever_link registers target")

	var other := map.get_lever_target(Vector3i(7, 15, 0))
	check(other == Vector3i(-1, -1, -1), "unrelated cell still returns sentinel")


func test_lever_links_round_trip_through_json() -> void:
	var src_dict: Dictionary = {
		"id": "test_lever_rt",
		"name": "Lever Roundtrip",
		"theme": "",
		"tileset_group": "",
		"generation_seed": 0,
		"entry": {"col": 0, "row": 0, "level": 0},
		"cells": [],
		"transition_cells": [],
		"lever_links": [
			{"lever": [5, 15, 0], "target": [6, 15, 0]},
			{"lever": [2, 3, 1], "target": [2, 4, 1]},
		],
	}
	var map := VoxelMapData.from_dict(src_dict)
	check(map.get_lever_target(Vector3i(5, 15, 0)) == Vector3i(6, 15, 0),
		"first lever link parsed")
	check(map.get_lever_target(Vector3i(2, 3, 1)) == Vector3i(2, 4, 1),
		"second lever link parsed")

	var out_dict := map.to_dict()
	check(out_dict.has("lever_links"), "to_dict emits lever_links")
	check(out_dict["lever_links"].size() == 2, "two links round-tripped")

	var map2 := VoxelMapData.from_dict(out_dict)
	check(map2.get_lever_target(Vector3i(5, 15, 0)) == Vector3i(6, 15, 0),
		"re-parsed lever link still resolves")
