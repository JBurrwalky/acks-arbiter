class_name SessionLoadState
extends SessionState

## Transient bootstrap state — loads campaign data and transitions to wilderness.
## Replaces the old main_scene._dev_load_test_map_for_campaign() flow.

const TEST_MAP_ID := "test_region_001"
const TEST_MAP_JSON_PATH := "res://data/test_hex_map.json"
const TEST_DUNGEON_JSON_PATH := "res://data/test_dungeon.json"
const TEST_SETTLEMENT_JSON_PATH := "res://data/test_settlement.json"
const TEST_SETTLEMENT_THORNWALL_JSON_PATH := "res://data/test_settlement_thornwall.json"
const TEST_DUNGEON_ENTRANCE_HEX := Vector2i(-1, 0)
const TEST_SETTLEMENT_ENTRANCE_HEX := Vector2i(0, 0)
const TEST_SETTLEMENT_THORNWALL_HEX := Vector2i(2, 1)


func enter(runner, context: Dictionary) -> void:
	var campaign_id: String = context.get("campaign_id", "")
	if campaign_id.is_empty():
		push_error("SessionLoadState: no campaign_id in context")
		runner.transition_to_state("campaign_select")
		return

	# Get or create a party for this campaign
	var party_id := _get_or_create_party(campaign_id)

	# Load session data (triggers Timekeeping.load_state, loads party, effects)
	runner.load_session(campaign_id, party_id)

	# Load the hex map
	var map_data := _load_or_seed_map(campaign_id)
	if map_data == null:
		push_error("SessionLoadState: failed to load hex map")
		runner.transition_to_state("campaign_select")
		return

	CampaignRepository.save_hex_map(map_data, campaign_id)

	# Seed test fixtures (dungeon/settlement entrances)
	_ensure_test_dungeon_entrance(campaign_id)
	_ensure_test_settlement_entrance(campaign_id)
	_ensure_test_settlement_thornwall_entrance(campaign_id)

	# Wire hex map renderer to controller (first time only)
	var renderer: Node = runner.get_hex_map_renderer()
	var controller: HexMapController = runner.get_hex_map_controller()
	# setup() connects controller signals to renderer — only call once.
	if renderer._controller == null:
		renderer.setup(controller)

	# Load map into controller
	controller.load_map(map_data)

	# Auto-transition to wilderness
	runner.transition_to_state("wilderness")


func _get_or_create_party(campaign_id: String) -> String:
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM parties WHERE campaign_id = ? LIMIT 1",
		[campaign_id]
	)
	if not CampaignRepository.db.query_result.is_empty():
		return CampaignRepository.db.query_result[0]["id"]
	return CampaignRepository.create_party(campaign_id, "Default Party")


func _load_or_seed_map(campaign_id: String) -> HexMapData:
	var from_db: HexMapData = CampaignRepository.load_hex_map(TEST_MAP_ID)
	if from_db != null:
		return from_db

	var from_json: HexMapData = HexMapData.load_from_file(TEST_MAP_JSON_PATH)
	if from_json == null:
		push_error("SessionLoadState: could not load %s" % TEST_MAP_JSON_PATH)
		return null

	if not CampaignRepository.save_hex_map(from_json, campaign_id):
		push_error("SessionLoadState: save_hex_map failed — continuing with in-memory map.")
	return from_json


func _ensure_test_dungeon_entrance(campaign_id: String) -> void:
	var entrances: Array = CampaignRepository.get_dungeon_entrances_for_map(TEST_MAP_ID)
	for e: Dictionary in entrances:
		if e.get("hex_q", 999) == TEST_DUNGEON_ENTRANCE_HEX.x and \
		   e.get("hex_r", 999) == TEST_DUNGEON_ENTRANCE_HEX.y:
			return

	var file := FileAccess.open(TEST_DUNGEON_JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("SessionLoadState: could not open %s" % TEST_DUNGEON_JSON_PATH)
		return
	var json_text := file.get_as_text()
	file.close()

	CampaignRepository.create_dungeon_entrance({
		"campaign_id": campaign_id,
		"map_id": TEST_MAP_ID,
		"hex_q": TEST_DUNGEON_ENTRANCE_HEX.x,
		"hex_r": TEST_DUNGEON_ENTRANCE_HEX.y,
		"name": "Goblin Warrens",
		"dungeon_data": json_text,
	})


func _ensure_test_settlement_entrance(campaign_id: String) -> void:
	var file := FileAccess.open(TEST_SETTLEMENT_JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("SessionLoadState: could not open %s" % TEST_SETTLEMENT_JSON_PATH)
		return
	var json_text := file.get_as_text()
	file.close()

	var entrances: Array = CampaignRepository.get_settlement_entrances_for_map(TEST_MAP_ID)
	for e: Dictionary in entrances:
		if e.get("hex_q", 999) == TEST_SETTLEMENT_ENTRANCE_HEX.x and \
		   e.get("hex_r", 999) == TEST_SETTLEMENT_ENTRANCE_HEX.y:
			CampaignRepository.update_settlement_entrance_data(e.get("id", ""), json_text)
			return

	CampaignRepository.create_settlement_entrance({
		"campaign_id": campaign_id,
		"map_id": TEST_MAP_ID,
		"hex_q": TEST_SETTLEMENT_ENTRANCE_HEX.x,
		"hex_r": TEST_SETTLEMENT_ENTRANCE_HEX.y,
		"name": "Ashford Village",
		"market_class": 6,
		"settlement_data": json_text,
	})


func _ensure_test_settlement_thornwall_entrance(campaign_id: String) -> void:
	var file := FileAccess.open(TEST_SETTLEMENT_THORNWALL_JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("SessionLoadState: could not open %s" % TEST_SETTLEMENT_THORNWALL_JSON_PATH)
		return
	var json_text := file.get_as_text()
	file.close()

	var entrances: Array = CampaignRepository.get_settlement_entrances_for_map(TEST_MAP_ID)
	for e: Dictionary in entrances:
		if e.get("hex_q", 999) == TEST_SETTLEMENT_THORNWALL_HEX.x and \
		   e.get("hex_r", 999) == TEST_SETTLEMENT_THORNWALL_HEX.y:
			CampaignRepository.update_settlement_entrance_data(e.get("id", ""), json_text)
			return

	CampaignRepository.create_settlement_entrance({
		"campaign_id": campaign_id,
		"map_id": TEST_MAP_ID,
		"hex_q": TEST_SETTLEMENT_THORNWALL_HEX.x,
		"hex_r": TEST_SETTLEMENT_THORNWALL_HEX.y,
		"name": "Thornwall",
		"market_class": 4,
		"settlement_data": json_text,
	})
