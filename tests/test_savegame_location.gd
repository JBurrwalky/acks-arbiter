extends "res://tests/test_suite_base.gd"

## Phase S-1 savegame persistence — data-layer coverage for location/context
## restore (gdd-savegame-system.md §5). Exercises the new CampaignRepository
## functions and the PartyData location fields directly:
##   - update_party_location_type round-trip
##   - update/clear_party_settlement_position round-trip
##   - save/load/clear_dungeon_entity_positions (per-member Vector3i, §5.2)
##   - get_dungeon_entrance_for_dungeon_id (entrance lookup by parsed dungeon_data)
##   - PartyData.from_db reads dungeon + settlement fields
##
## The state-machine wiring (flush_to_db hooks + context-aware loader) needs a
## live SessionRunner + scene tree and is covered by Jedidiah's in-game
## acceptance pass (gdd-savegame-system.md §10), not here.


const TEST_CAMPAIGN := "test_savegame_loc_campaign"
const TEST_MAP := "test_savegame_loc_map"


func run_all_tests() -> void:
	_cleanup()
	test_location_type_round_trip()
	test_settlement_position_round_trip()
	test_dungeon_entity_positions_round_trip()
	test_dungeon_entrance_lookup_by_dungeon_id()
	test_party_data_reads_location_fields()
	_cleanup()
	if not has_failures():
		print("SavegameLocation: all tests passed.")


func test_location_type_round_trip() -> void:
	var pid := _make_party()
	CampaignRepository.update_party_location_type(pid, "dungeon")
	var row := CampaignRepository.get_party(pid)
	check(String(row.get("current_location_type", "")) == "dungeon",
		"location_type persisted as dungeon")
	CampaignRepository.update_party_location_type(pid, "settlement")
	row = CampaignRepository.get_party(pid)
	check(String(row.get("current_location_type", "")) == "settlement",
		"location_type updated to settlement")
	print("  location_type_round_trip: OK")


func test_settlement_position_round_trip() -> void:
	var pid := _make_party()
	CampaignRepository.update_party_settlement_position(pid, "entr_123", "poi_market")
	var row := CampaignRepository.get_party(pid)
	check(String(row.get("settlement_id", "")) == "entr_123", "settlement_id persisted")
	check(String(row.get("settlement_node_id", "")) == "poi_market", "settlement_node_id persisted")
	CampaignRepository.clear_party_settlement_position(pid)
	row = CampaignRepository.get_party(pid)
	check(String(row.get("settlement_id", "")) == "", "settlement_id cleared")
	check(String(row.get("settlement_node_id", "")) == "", "settlement_node_id cleared")
	print("  settlement_position_round_trip: OK")


func test_dungeon_entity_positions_round_trip() -> void:
	var pid := _make_party()
	var positions := {
		"char_a": Vector3i(3, 5, 0),
		"char_b": Vector3i(4, 5, 1),  # different level — multi-level fidelity
	}
	var ok := CampaignRepository.save_dungeon_entity_positions(pid, "dgn_1", positions)
	check(ok, "save_dungeon_entity_positions returned true")
	var loaded := CampaignRepository.load_dungeon_entity_positions(pid)
	check(loaded.size() == 2, "two entity positions loaded")
	check(loaded.get("char_a", Vector3i.ZERO) == Vector3i(3, 5, 0),
		"char_a position round-trips")
	check(loaded.get("char_b", Vector3i.ZERO) == Vector3i(4, 5, 1),
		"char_b position round-trips (level 1)")
	# Replace semantics: a second save fully replaces the prior rows.
	CampaignRepository.save_dungeon_entity_positions(pid, "dgn_1", {"char_a": Vector3i(9, 9, 2)})
	loaded = CampaignRepository.load_dungeon_entity_positions(pid)
	check(loaded.size() == 1, "replace semantics: old rows cleared on re-save")
	check(loaded.get("char_a", Vector3i.ZERO) == Vector3i(9, 9, 2), "replaced position correct")
	# Clear on dungeon exit.
	CampaignRepository.clear_dungeon_entity_positions(pid)
	loaded = CampaignRepository.load_dungeon_entity_positions(pid)
	check(loaded.is_empty(), "positions cleared on exit")
	print("  dungeon_entity_positions_round_trip: OK")


func test_dungeon_entrance_lookup_by_dungeon_id() -> void:
	_make_party()  # ensures the campaign row exists
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, ?)",
		[TEST_MAP, TEST_CAMPAIGN, "Test Map", "regional_6mi"])
	var entrance_id := "test_entr_1"
	var dungeon_json := JSON.stringify({"id": "dgn_xyz", "name": "Test Dungeon", "cells": []})
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO dungeon_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, dungeon_data)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [entrance_id, TEST_CAMPAIGN, TEST_MAP, 0, 0, "Test Dungeon", dungeon_json])
	var found := CampaignRepository.get_dungeon_entrance_for_dungeon_id(TEST_CAMPAIGN, "dgn_xyz")
	check(not found.is_empty(), "entrance found by dungeon_id")
	check(String(found.get("id", "")) == entrance_id, "correct entrance id returned")
	var missing := CampaignRepository.get_dungeon_entrance_for_dungeon_id(TEST_CAMPAIGN, "no_such_dungeon")
	check(missing.is_empty(), "no entrance for unknown dungeon_id")
	print("  dungeon_entrance_lookup_by_dungeon_id: OK")


func test_party_data_reads_location_fields() -> void:
	var pid := _make_party()
	CampaignRepository.update_party_location_type(pid, "dungeon")
	CampaignRepository.update_party_dungeon_position(pid, "dgn_1", 2, 7, 8)
	CampaignRepository.update_party_settlement_position(pid, "entr_9", "poi_inn")
	var pd: PartyData = CampaignRepository.load_party_data(pid)
	check(pd != null, "load_party_data returned a PartyData")
	if pd == null:
		return
	check(pd.current_location_type == "dungeon", "PartyData.current_location_type read")
	check(pd.dungeon_id == "dgn_1", "PartyData.dungeon_id read")
	check(pd.dungeon_level == 2, "PartyData.dungeon_level read")
	check(pd.dungeon_col == 7, "PartyData.dungeon_col read")
	check(pd.dungeon_row == 8, "PartyData.dungeon_row read")
	check(pd.settlement_id == "entr_9", "PartyData.settlement_id read")
	check(pd.settlement_node_id == "poi_inn", "PartyData.settlement_node_id read")
	print("  party_data_reads_location_fields: OK")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Creates the test campaign (idempotent) and a fresh party; returns party_id.
func _make_party() -> String:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Savegame Loc Test"])
	return CampaignRepository.create_party(TEST_CAMPAIGN, "Test Party")


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM dungeon_entity_positions WHERE party_id IN (SELECT id FROM parties WHERE campaign_id = ?)",
		[TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id IN (SELECT id FROM parties WHERE campaign_id = ?)",
		[TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM dungeon_entrances WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ? AND campaign_id = ?", [TEST_MAP, TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])
