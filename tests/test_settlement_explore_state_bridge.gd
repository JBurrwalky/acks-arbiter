extends "res://tests/test_suite_base.gd"

## Phase 11D bridge integration test — exercises the rows-vs-JSON gate that
## SettlementExploreState.enter performs before calling
## SettlementMapController.load_settlement.
##
## The test does not spin up the full SessionRunner / SceneTree; it replicates
## the gate condition (`SettlementDictBuilder.has_relational_pois(...)`) and
## verifies the chosen path against three fixtures:
##
##   Fixture A — settlement has settlement_pois rows, no JSON blob → bridge wins
##   Fixture B — settlement has JSON blob, no rows         → legacy JSON parse
##   Fixture C — settlement has BOTH                        → bridge wins (rows authoritative)


const CAMPAIGN_ID := "test_bridge_campaign"
const SETTLEMENT_A := "test_bridge_settlement_a"
const SETTLEMENT_B := "test_bridge_settlement_b"
const SETTLEMENT_C := "test_bridge_settlement_c"


func run_all_tests() -> void:
	_cleanup_all()
	test_fixture_a_rows_only_bridge_used()
	_cleanup_all()
	test_fixture_b_json_only_legacy_used()
	_cleanup_all()
	test_fixture_c_both_present_bridge_wins()
	_cleanup_all()
	if not has_failures():
		print("SettlementExploreState bridge: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_fixture_a_rows_only_bridge_used() -> void:
	# Settlement A: has settlement_pois rows; settlement_data is empty.
	_make_entrance(SETTLEMENT_A, "Town A", 4, "")
	_insert_poi(SETTLEMENT_A, {"type": "named_tavern",
		"preferred_district_class": "merchant"})
	_insert_poi(SETTLEMENT_A, {"type": "workshop",
		"attached_specialist_kind": "blacksmith",
		"preferred_district_class": "craft"})

	var dict := _route_load_settlement(SETTLEMENT_A)
	check(not dict.is_empty(), "rows-only fixture should resolve to a dict")
	# Bridge synthesizes synthetic-district ids that start with the settlement
	# name slug; the legacy JSON path (empty here) would never produce these.
	var has_synth_district := false
	for dist_v in dict.get("districts", []):
		var dist: Dictionary = dist_v
		var did: String = String(dist.get("id", ""))
		if did.begins_with("town_a_"):
			has_synth_district = true
			break
	check(has_synth_district,
		"bridge-output dict should contain a 'town_a_*' synthetic district id")
	# At least the 2 POIs we inserted, plus synthesized gates.
	var poi_total := _count_pois(dict)
	check(poi_total >= 4,
		"rows-only dict should have >= 4 POIs (2 inserted + 2 gates); got %d" % poi_total)
	print("  fixture_a_rows_only_bridge_used: OK")


func test_fixture_b_json_only_legacy_used() -> void:
	# Settlement B: no settlement_pois rows; settlement_data is a valid JSON
	# blob in the legacy shape.
	var json_blob := JSON.stringify({
		"id": SETTLEMENT_B,
		"name": "Town B",
		"market_class": 6,
		"districts": [{
			"id": "town_b_center",
			"name": "Town B Center",
			"type": "village_center",
			"encounter_modifier": "default",
			"pois": [
				{"id": "town_b_north_gate", "name": "North Gate", "type": "gate",
				 "subtype": "main", "district_id": "town_b_center",
				 "is_entry_exit": true, "importance": "major", "label": null},
				{"id": "town_b_legacy_tavern", "name": "The Legacy Tavern",
				 "type": "tavern", "subtype": "common",
				 "district_id": "town_b_center",
				 "is_entry_exit": false, "importance": "major", "label": null},
			],
		}],
		"undercity_pois": [],
		"transitions": [],
	})
	_make_entrance(SETTLEMENT_B, "Town B", 6, json_blob)

	check(not SettlementDictBuilder.has_relational_pois(SETTLEMENT_B),
		"fixture B should have no settlement_pois rows")

	var dict := _route_load_settlement(SETTLEMENT_B)
	check(not dict.is_empty(), "json-only fixture should parse")
	# The hand-authored JSON includes an id 'town_b_legacy_tavern' that the
	# bridge would NEVER mint (bridge doesn't know about hand-authored ids).
	var saw_legacy := false
	for dist_v in dict.get("districts", []):
		var dist: Dictionary = dist_v
		for poi_v in dist.get("pois", []):
			var poi: Dictionary = poi_v
			if String(poi.get("id", "")) == "town_b_legacy_tavern":
				saw_legacy = true
	check(saw_legacy,
		"json-only fixture should produce the hand-authored 'town_b_legacy_tavern' POI")
	print("  fixture_b_json_only_legacy_used: OK")


func test_fixture_c_both_present_bridge_wins() -> void:
	# Settlement C: both rows AND JSON. Bridge must win — JSON is shadowed.
	var json_blob := JSON.stringify({
		"id": SETTLEMENT_C,
		"name": "Town C",
		"market_class": 6,
		"districts": [{
			"id": "town_c_center",
			"name": "Town C Center",
			"type": "village_center",
			"encounter_modifier": "default",
			"pois": [
				{"id": "town_c_legacy_only_poi", "name": "Legacy Only POI",
				 "type": "shop", "subtype": "general_store",
				 "district_id": "town_c_center",
				 "is_entry_exit": false, "importance": "major", "label": null},
			],
		}],
		"undercity_pois": [],
		"transitions": [],
	})
	_make_entrance(SETTLEMENT_C, "Town C", 6, json_blob)
	# Insert a row that would never appear in the JSON.
	_insert_poi(SETTLEMENT_C, {"type": "mages_guild_hall",
		"preferred_district_class": "noble"})

	check(SettlementDictBuilder.has_relational_pois(SETTLEMENT_C),
		"fixture C should have settlement_pois rows")
	var dict := _route_load_settlement(SETTLEMENT_C)
	# The legacy-only POI must NOT appear (bridge ignores JSON when rows present).
	var saw_legacy := false
	var saw_relational := false
	for dist_v in dict.get("districts", []):
		var dist: Dictionary = dist_v
		for poi_v in dist.get("pois", []):
			var poi: Dictionary = poi_v
			var pid := String(poi.get("id", ""))
			var ptype := String(poi.get("type", ""))
			var psubtype := String(poi.get("subtype", ""))
			if pid == "town_c_legacy_only_poi":
				saw_legacy = true
			if ptype == "guild_hall" and psubtype == "mages":
				saw_relational = true
	check(not saw_legacy,
		"bridge should have shadowed the legacy JSON's 'town_c_legacy_only_poi'")
	check(saw_relational,
		"bridge should have rendered the relational mages_guild_hall row")
	print("  fixture_c_both_present_bridge_wins: OK")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Replicates the gate condition inside SettlementExploreState.enter:
## prefer relational POIs, fall back to JSON parse.
func _route_load_settlement(settlement_id: String) -> Dictionary:
	var entrance: Dictionary = _load_entrance(settlement_id)
	if SettlementDictBuilder.has_relational_pois(settlement_id):
		return SettlementDictBuilder.build_from_pois(settlement_id, entrance)
	var settlement_json: String = String(entrance.get("settlement_data", ""))
	if settlement_json.is_empty():
		return {}
	var parsed = JSON.parse_string(settlement_json)
	if parsed is Dictionary:
		return parsed
	return {}


func _make_entrance(settlement_id: String, name: String, mc: int, json_blob: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[CAMPAIGN_ID, "Bridge Test Campaign"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale)
		VALUES ('test_bridge_map', ?, 'Bridge Test Map', 'regional_6mi')
	""", [CAMPAIGN_ID])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class, settlement_data)
		VALUES (?, ?, 'test_bridge_map', 0, 0, ?, ?, ?)
	""", [settlement_id, CAMPAIGN_ID, name, mc, json_blob])


func _load_entrance(settlement_id: String) -> Dictionary:
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM settlement_entrances WHERE id = ?", [settlement_id])
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


func _insert_poi(settlement_id: String, overrides: Dictionary) -> String:
	var data: Dictionary = {"settlement_id": settlement_id}
	for k in overrides:
		data[k] = overrides[k]
	return CampaignRepository.insert_settlement_poi(data)


func _count_pois(dict: Dictionary) -> int:
	var total := 0
	for dist_v in dict.get("districts", []):
		var dist: Dictionary = dist_v
		total += (dist.get("pois", []) as Array).size()
	return total


func _cleanup_all() -> void:
	for sid in [SETTLEMENT_A, SETTLEMENT_B, SETTLEMENT_C]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM settlement_pois WHERE settlement_id = ?", [sid])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM settlement_entrances WHERE id = ?", [sid])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = 'test_bridge_map'", [])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [CAMPAIGN_ID])
