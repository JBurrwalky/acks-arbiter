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
	test_metadata_preserved_across_generation()
	test_missing_version_key_counts_as_current()
	test_stale_version_regenerates()
	test_stale_version_without_spec_derives_from_stored_floors()
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


func test_metadata_preserved_across_generation() -> void:
	# The narrator metadata the materializer writes (provenance / context / dungeon_level /
	# size_hint / dungeon_type) must SURVIVE the voxel overwrite on first entry, so an entered
	# dungeon keeps its origin for the M5 narrator (review finding 2026-06-22).
	var entrance := _make_entrance("dfs_test_meta", {
		"spec": {"kind": "tomb", "tier": 4, "size": "medium", "floors": 3, "entrance_floor_index": 1},
		"size_hint": "medium",
		"dungeon_type": "tomb",
		"dungeon_level": 4,
		"context": "scattered",
		"provenance": {"culture_id": "khemt", "toponym": "Khraal", "event_type": "ruin"},
	})
	var result_json: String = DungeonFixtureService.get_or_generate_voxel(entrance)
	var parsed: Variant = JSON.parse_string(result_json)
	check(parsed is Dictionary and (parsed as Dictionary).has("cells"),
		"metadata test: voxel generated (has 'cells')")
	if not (parsed is Dictionary):
		return
	check(str((parsed as Dictionary).get("context", "")) == "scattered",
		"context survives the voxel overwrite")
	check(int((parsed as Dictionary).get("dungeon_level", -1)) == 4,
		"dungeon_level survives the voxel overwrite")
	check(str((parsed as Dictionary).get("size_hint", "")) == "medium",
		"size_hint survives the voxel overwrite")
	check(str((parsed as Dictionary).get("dungeon_type", "")) == "tomb",
		"dungeon_type survives the voxel overwrite")
	var prov: Variant = (parsed as Dictionary).get("provenance", null)
	check(prov is Dictionary and str((prov as Dictionary).get("culture_id", "")) == "khemt",
		"provenance survives the voxel overwrite")
	# Cache hit on re-entry still returns the persisted (metadata-merged) blob unchanged.
	var db_entrance := CampaignRepository.get_dungeon_entrance("dfs_test_meta")
	var second: String = DungeonFixtureService.get_or_generate_voxel(db_entrance)
	check(second == str(db_entrance.get("dungeon_data", "")),
		"cache hit returns the persisted (metadata-merged) JSON unchanged")
	print("  test_metadata_preserved_across_generation: OK")


# ---------------------------------------------------------------------------
# Generator-version regeneration (DG-C3D.A; contiguous GDD §13)
# ---------------------------------------------------------------------------

func test_missing_version_key_counts_as_current() -> void:
	# A voxel payload persisted BEFORE the version stamp existed has no
	# "generator_version" key — it must read as version 0 (== the current
	# constant until DG-C3D.F bumps it) and cache-hit unchanged. This is the
	# zero-behavior-change guarantee for pre-DG-C3D stored dungeons.
	check(DungeonGeneratorV1.GENERATOR_VERSION == 0,
		"DG-C3D.A expects GENERATOR_VERSION 0 (pre-cutover); when F bumps it, retire this test's premise")
	var legacy_payload := JSON.stringify({"cells": [], "id": "dfs_test_legacy"})
	var entrance := {
		"id": "dfs_test_legacy",
		"dungeon_data": legacy_payload,
	}
	var result_json: String = DungeonFixtureService.get_or_generate_voxel(entrance)
	check(result_json == legacy_payload,
		"payload without generator_version must cache-hit byte-identically (read as version 0)")
	print("  test_missing_version_key_counts_as_current: OK")


func test_stale_version_regenerates() -> void:
	# Generate a dungeon normally, then tamper its stored version stamp. The
	# next access must discard the stored dungeon (relational rows + persisted
	# runtime voxel cells) and regenerate — deterministically identical to the
	# original, since the seed derives from the entrance id and the preserved
	# "spec" survives the overwrite.
	var entrance := _make_entrance("dfs_test_stale", {
		"spec": {
			"kind": "wizards_dungeon",
			"tier": 1,
			"size": "lair",
			"floors": 1,
			"entrance_floor_index": 1,
		}
	})
	var original_json: String = DungeonFixtureService.get_or_generate_voxel(entrance)
	check(not original_json.is_empty(), "stale-version test: initial generation succeeds")
	if original_json.is_empty():
		return
	var original: Variant = JSON.parse_string(original_json)
	check(original is Dictionary and (original as Dictionary).has("spec"),
		"generated payload preserves the 'spec' key for future regeneration")
	check(int((original as Dictionary).get("generator_version", -1)) == DungeonGeneratorV1.GENERATOR_VERSION,
		"generated payload carries the current generator_version stamp")

	# Stamp stored relational rows carry the version too.
	CampaignRepository.db.query_with_bindings(
		"SELECT generator_version FROM dungeon_floors WHERE dungeon_id = ?", ["dfs_test_stale"])
	check(not CampaignRepository.db.query_result.is_empty(),
		"stale-version test: dungeon_floors rows persisted")
	for row in CampaignRepository.db.query_result:
		check(int(row["generator_version"]) == DungeonGeneratorV1.GENERATOR_VERSION,
			"dungeon_floors.generator_version stamped with the current constant")

	# Tamper: mark the stored payload as an older generator's output, and
	# plant a fake persisted runtime voxel cell that must be purged.
	var tampered: Dictionary = (original as Dictionary).duplicate(true)
	tampered["generator_version"] = -999
	var tampered_json := JSON.stringify(tampered)
	CampaignRepository.update_dungeon_entrance_data("dfs_test_stale", tampered_json)
	var stale_cell := VoxelCell.new()
	stale_cell.col = 1
	stale_cell.row = 1
	stale_cell.level = 0
	CampaignRepository.save_voxel_cell("dfs_test_stale", stale_cell)

	var db_entrance := CampaignRepository.get_dungeon_entrance("dfs_test_stale")
	var regenerated_json: String = DungeonFixtureService.get_or_generate_voxel(db_entrance)
	check(not regenerated_json.is_empty(), "stale version triggers regeneration, not failure")
	check(regenerated_json != tampered_json, "regenerated payload replaces the tampered one")
	check(regenerated_json == original_json,
		"regeneration is deterministic — same entrance id + preserved spec reproduce the original payload")

	var regen_parsed: Variant = JSON.parse_string(regenerated_json)
	check(regen_parsed is Dictionary and int((regen_parsed as Dictionary).get("generator_version", -1)) == DungeonGeneratorV1.GENERATOR_VERSION,
		"regenerated payload stamped with the current generator_version")

	# The planted stale runtime voxel cell must be gone.
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM voxel_map_cells WHERE map_id = ?", ["dfs_test_stale"])
	check(int(CampaignRepository.db.query_result[0]["n"]) == 0,
		"persisted runtime voxel cells purged on version-mismatch regeneration")

	# Relational rows exist again (regenerated, current version).
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM dungeon_floors WHERE dungeon_id = ? AND generator_version = ?",
		["dfs_test_stale", DungeonGeneratorV1.GENERATOR_VERSION])
	check(int(CampaignRepository.db.query_result[0]["n"]) >= 1,
		"dungeon_floors rows re-persisted at the current version after regeneration")

	DungeonGeneratorRepository.delete_dungeon_layout("dfs_test_stale")
	print("  test_stale_version_regenerates: OK")


func test_stale_version_without_spec_derives_from_stored_floors() -> void:
	# Payloads persisted before DG-C3D.A carry no "spec" key. On a version
	# mismatch the seam must recover the dungeon's shape from the stored
	# dungeon_floors rows (DungeonGeneratorRepository.derive_request_spec)
	# instead of regenerating with defaults. Discriminating assertion: the
	# original spec asks for TWO floors; the fixture-service default is one.
	var entrance := _make_entrance("dfs_test_derive", {
		"spec": {
			"kind": "wizards_dungeon",
			"tier": 1,
			"size": "small",
			"floors": 2,
			"entrance_floor_index": 1,
		}
	})
	var original_json: String = DungeonFixtureService.get_or_generate_voxel(entrance)
	check(not original_json.is_empty(), "derive test: initial generation succeeds")
	if original_json.is_empty():
		return

	# Tamper: stale version AND strip the preserved spec (simulates a pre-A payload).
	var tampered: Dictionary = JSON.parse_string(original_json)
	tampered["generator_version"] = -999
	tampered.erase("spec")
	CampaignRepository.update_dungeon_entrance_data("dfs_test_derive", JSON.stringify(tampered))

	var db_entrance := CampaignRepository.get_dungeon_entrance("dfs_test_derive")
	var regenerated_json: String = DungeonFixtureService.get_or_generate_voxel(db_entrance)
	check(not regenerated_json.is_empty(), "derive test: regeneration succeeds without a payload spec")

	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM dungeon_floors WHERE dungeon_id = ?", ["dfs_test_derive"])
	check(int(CampaignRepository.db.query_result[0]["n"]) == 2,
		"derived spec preserves the original floor count (2), not the 1-floor default")

	DungeonGeneratorRepository.delete_dungeon_layout("dfs_test_derive")
	print("  test_stale_version_without_spec_derives_from_stored_floors: OK")


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
