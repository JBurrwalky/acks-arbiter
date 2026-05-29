extends "res://tests/test_suite_base.gd"

## Unit tests for DungeonFixtureService.get_or_generate_voxel().
##
## Tests:
##   1. Spec stub (no "cells") -> generates, returns non-empty voxel JSON,
##      parsed result has "cells" and "entry", entrance dict is updated.
##   2. Idempotency: second call on the populated entrance returns the same
##      JSON without regenerating (cache-hit short-circuit on "cells" key).
##   3. Single-floor spec (floors=1) also succeeds.
##
## DB setup: inserts a minimal campaign + hex_map + dungeon_entrance row so
## update_dungeon_entrance_data has a valid FK target. Cleaned up after each
## test group to avoid cross-test pollution.
##
## Seed derivation: abs(entrance_id.hash()) & 0x7FFFFFFF — stable, reproducible.


const _TEST_CAMPAIGN_ID := "fixture_svc_test_campaign"
const _TEST_MAP_ID      := "fixture_svc_test_map"


func run_all_tests() -> void:
	_setup_db()
	test_spec_stub_generates_voxel()
	test_cache_hit_idempotency()
	test_single_floor_spec()
	_teardown_db()
	if not has_failures():
		print("DungeonFixtureService: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_spec_stub_generates_voxel() -> void:
	var entrance := _make_entrance("dfs_test_multi", {
		"spec": {
			"kind": "wizards_dungeon",
			"tier": 1,
			"tier_min": 1,
			"tier_max": 2,
			"size": "small",
			"floors": 2,
			"entrance_floor_index": 1,
		}
	})

	var result_json: String = DungeonFixtureService.get_or_generate_voxel(entrance)

	check(not result_json.is_empty(),
		"get_or_generate_voxel should return non-empty JSON for a spec stub")

	var parsed: Variant = JSON.parse_string(result_json)
	check(parsed is Dictionary,
		"returned JSON should parse to a Dictionary")
	if not (parsed is Dictionary):
		return

	check(parsed.has("cells"),
		"generated voxel dict should have 'cells' key")
	check(parsed.has("entry"),
		"generated voxel dict should have 'entry' key")

	# entrance dict must be updated in-memory so the caller sees it immediately.
	check(entrance.get("dungeon_data", "") == result_json,
		"entrance['dungeon_data'] should be updated to the generated voxel JSON")

	# DB must also be updated.
	var db_entrance := CampaignRepository.get_dungeon_entrance("dfs_test_multi")
	check(db_entrance.get("dungeon_data", "") == result_json,
		"DB dungeon_data should match the generated voxel JSON after persistence")

	print("  test_spec_stub_generates_voxel: OK")


func test_cache_hit_idempotency() -> void:
	# Re-use the entrance from the first test — it was populated by
	# test_spec_stub_generates_voxel (same id). Re-read from DB to get the
	# persisted voxel JSON; that simulates a fresh entry into the dungeon.
	var db_entrance := CampaignRepository.get_dungeon_entrance("dfs_test_multi")
	check(not db_entrance.is_empty(), "DB entrance should exist from prior test")
	if db_entrance.is_empty():
		return

	var first_json: String = db_entrance.get("dungeon_data", "")
	check(not first_json.is_empty(), "DB dungeon_data should be non-empty from prior test")

	# Second call must short-circuit on the "cells" key and return unchanged.
	var second_json: String = DungeonFixtureService.get_or_generate_voxel(db_entrance)
	check(second_json == first_json,
		"second call should return identical JSON (cache hit, no regeneration)")

	# Parsed result should still have "cells".
	var parsed: Variant = JSON.parse_string(second_json)
	check(parsed is Dictionary and (parsed as Dictionary).has("cells"),
		"cached JSON should still be a valid voxel dict with 'cells'")

	print("  test_cache_hit_idempotency: OK")


func test_single_floor_spec() -> void:
	var entrance := _make_entrance("dfs_test_single", {
		"spec": {
			"kind": "wizards_dungeon",
			"tier": 2,
			"size": "lair",
			"floors": 1,
			"entrance_floor_index": 1,
		}
	})

	var result_json: String = DungeonFixtureService.get_or_generate_voxel(entrance)

	check(not result_json.is_empty(),
		"single-floor spec should generate successfully")

	var parsed: Variant = JSON.parse_string(result_json)
	check(parsed is Dictionary and (parsed as Dictionary).has("cells"),
		"single-floor voxel dict should have 'cells' key")

	print("  test_single_floor_spec: OK")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Inserts a dungeon_entrance row with the given id and spec stub, then returns
## the row dict so DungeonFixtureService.get_or_generate_voxel can operate on it.
func _make_entrance(entrance_id: String, spec_data: Dictionary) -> Dictionary:
	# Clean up any prior row with this id (allows test_cache_hit to reload safely).
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM dungeon_entrances WHERE id = ?", [entrance_id])

	var stub_json := JSON.stringify(spec_data)
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO dungeon_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, dungeon_data)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [
		entrance_id,
		_TEST_CAMPAIGN_ID,
		_TEST_MAP_ID,
		0, 0,
		entrance_id,
		stub_json,
	])
	return {
		"id": entrance_id,
		"campaign_id": _TEST_CAMPAIGN_ID,
		"map_id": _TEST_MAP_ID,
		"hex_q": 0,
		"hex_r": 0,
		"name": entrance_id,
		"dungeon_data": stub_json,
	}


func _setup_db() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[_TEST_CAMPAIGN_ID, "DungeonFixtureService Test Campaign"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_maps
			(id, campaign_id, name, scale)
		VALUES (?, ?, ?, ?)
	""", [_TEST_MAP_ID, _TEST_CAMPAIGN_ID, "Test Map", "regional_6mi"])


func _teardown_db() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM dungeon_entrances WHERE campaign_id = ?", [_TEST_CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [_TEST_MAP_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_TEST_CAMPAIGN_ID])
