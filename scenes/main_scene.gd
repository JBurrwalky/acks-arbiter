extends Node

## Main scene script — boots the application and wires all top-level systems.
##
## DEV_SKIP_CAMPAIGN_SELECT controls whether the game boots straight to the
## test hex map (existing dev harness) or shows the campaign select screen first.
## Set to false (default) to exercise the full navigation flow.
## Set to true to bypass campaign select when iterating on other systems.
##
## NOTE: This script will be replaced by the session runner (E-2) once that
## subsystem is built. Until then it acts as the orchestrator.

## Set false to show the campaign select screen on boot (normal flow).
## Set true to bypass directly to the test hex map (dev harness).
const DEV_SKIP_CAMPAIGN_SELECT := false

const TEST_MAP_ID := "test_region_001"
const TEST_CAMPAIGN_ID := "test_campaign_01"
const TEST_PARTY_ID := "test_party_01"
const TEST_MAP_JSON_PATH := "res://data/test_hex_map.json"
const TEST_DUNGEON_JSON_PATH := "res://data/test_dungeon.json"
const TEST_SETTLEMENT_JSON_PATH := "res://data/test_settlement.json"
## Hex coordinate where the test dungeon entrance is placed on the Ashford Vale map.
const TEST_DUNGEON_ENTRANCE_HEX := Vector2i(-1, 0)
## Hex coordinate where the test settlement entrance is placed (the hex with has_city=true).
const TEST_SETTLEMENT_ENTRANCE_HEX := Vector2i(0, 0)
const TEST_SETTLEMENT_THORNWALL_JSON_PATH := "res://data/test_settlement_thornwall.json"
const TEST_SETTLEMENT_THORNWALL_HEX := Vector2i(2, 1)

@onready var _hex_map_renderer = $HexMap
@onready var _controller: HexMapController = $HexMapController
@onready var _override_manager: OverrideManager = $OverrideManager
@onready var _override_panel = $OverridePanel
@onready var _char_creation = $CharacterCreationScreen
@onready var _dice_prompt = $DicePrompt
@onready var _char_sheet = $CharacterSheetOverlay
@onready var _nav_stack: NavigationStack = $NavigationStack
@onready var _scene_container: Node = $SceneContainer
@onready var _scene_transition = $SceneTransition


func _ready() -> void:
	# --- Navigation stack setup ---
	_nav_stack.setup(_scene_container, _scene_transition)

	# --- Wire dev overlay systems ---
	_override_panel.setup(_override_manager, _controller)
	EventBus.dev_character_creation_requested.connect(_on_dev_char_creation_requested)
	EventBus.dev_dice_test_requested.connect(_on_dev_dice_test_requested)

	if DEV_SKIP_CAMPAIGN_SELECT:
		# Direct path: bypass campaign select, load test map immediately.
		_hex_map_renderer.setup(_controller)
		_hex_map_renderer.hex_clicked.connect(_on_hex_clicked)
		_hex_map_renderer.dungeon_entry_requested.connect(_on_dungeon_entry_requested)
		_hex_map_renderer.settlement_entry_requested.connect(_on_settlement_entry_requested)
		_dev_load_test_map()
	else:
		# Normal path: show campaign select screen.
		# The hex map renderer is NOT wired yet — _on_campaign_selected does it.
		var campaign_select_scene := preload(
			"res://scenes/ui/campaign_select/campaign_select_screen.tscn"
		)
		var cs = campaign_select_scene.instantiate()
		cs.campaign_selected.connect(_on_campaign_selected)
		_nav_stack.push_node(cs, "campaign_select")


# ---------------------------------------------------------------------------
# Campaign select handler
# ---------------------------------------------------------------------------

## Called when the player selects or creates a campaign from the select screen.
## For D-2: loads the test map and starts the session. Will be replaced by the
## session runner (E-2) which will manage the full session lifecycle.
func _on_campaign_selected(campaign_id: String) -> void:
	# Pop the campaign select screen
	_nav_stack.pop()

	# Wire hex map renderer (first time only)
	if not _hex_map_renderer.hex_clicked.is_connected(_on_hex_clicked):
		_hex_map_renderer.setup(_controller)
		_hex_map_renderer.hex_clicked.connect(_on_hex_clicked)
		_hex_map_renderer.dungeon_entry_requested.connect(_on_dungeon_entry_requested)
		_hex_map_renderer.settlement_entry_requested.connect(_on_settlement_entry_requested)

	# Each campaign gets its own party. Look up the existing one, or create fresh.
	var party_id := _get_or_create_party(campaign_id)
	_dev_load_test_map_for_campaign(campaign_id, party_id)


## Returns the first party id for [param campaign_id], creating one if none exists.
func _get_or_create_party(campaign_id: String) -> String:
	CampaignRepository.db.query_with_bindings(
		"SELECT id FROM parties WHERE campaign_id = ? LIMIT 1",
		[campaign_id]
	)
	if not CampaignRepository.db.query_result.is_empty():
		return CampaignRepository.db.query_result[0]["id"]
	return CampaignRepository.create_party(campaign_id, "Default Party")


# ---------------------------------------------------------------------------
# Dev test-map loading helpers
# ---------------------------------------------------------------------------

## Load the test map for the hardcoded test campaign (DEV_SKIP path).
func _dev_load_test_map() -> void:
	_ensure_test_campaign()
	_dev_load_test_map_for_campaign(TEST_CAMPAIGN_ID, TEST_PARTY_ID)


## Load (or seed) the test hex map, then start the session for [param campaign_id].
func _dev_load_test_map_for_campaign(campaign_id: String, party_id: String) -> void:
	var map_data := _load_or_seed_map(campaign_id)
	if map_data == null:
		push_error("MainScene: failed to load hex map — cannot start.")
		return

	CampaignRepository.save_hex_map(map_data, campaign_id)

	GameState.start_session(campaign_id, party_id)
	GameState.set_exploration_context(GameState.ExplorationContext.WILDERNESS)

	# Seed test fixtures BEFORE loading the controller map so the renderer
	# settlement cache finds them during _on_map_loaded.
	_ensure_test_dungeon_entrance(campaign_id)
	_ensure_test_settlement_entrance(campaign_id)
	_ensure_test_settlement_thornwall_entrance(campaign_id)

	_controller.load_map(map_data)


## Returns a HexMapData from DB if it exists, otherwise loads from JSON and seeds the DB.
func _load_or_seed_map(campaign_id: String) -> HexMapData:
	var from_db := CampaignRepository.load_hex_map(TEST_MAP_ID)
	if from_db != null:
		return from_db

	var from_json := HexMapData.load_from_file(TEST_MAP_JSON_PATH)
	if from_json == null:
		push_error("MainScene: could not load %s" % TEST_MAP_JSON_PATH)
		return null

	if not CampaignRepository.save_hex_map(from_json, campaign_id):
		push_error("MainScene: save_hex_map failed — continuing with in-memory map.")
	return from_json


## Ensure the test campaign record exists in the DB (idempotent).
func _ensure_test_campaign() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[TEST_CAMPAIGN_ID, "Test Campaign", "Ashford Vale"]
	)
	_ensure_test_party(TEST_CAMPAIGN_ID)


## Ensure the test party record exists for [param campaign_id] (idempotent).
func _ensure_test_party(campaign_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[TEST_PARTY_ID, campaign_id, "Test Party"]
	)


# ---------------------------------------------------------------------------
# Hex map interaction
# ---------------------------------------------------------------------------

func _on_hex_clicked(coord: Vector2i) -> void:
	_controller.move_party(coord)
	var map_data := _controller.get_map()
	if map_data != null:
		CampaignRepository.save_hex_map(map_data, GameState.campaign_id)


# ---------------------------------------------------------------------------
# Dungeon entrance seeding and entry
# ---------------------------------------------------------------------------

## Seeds the test dungeon entrance at TEST_DUNGEON_ENTRANCE_HEX if it doesn't exist.
func _ensure_test_dungeon_entrance(campaign_id: String) -> void:
	var entrances := CampaignRepository.get_dungeon_entrances_for_map(TEST_MAP_ID)
	for e in entrances:
		if e.get("hex_q", 999) == TEST_DUNGEON_ENTRANCE_HEX.x and \
		   e.get("hex_r", 999) == TEST_DUNGEON_ENTRANCE_HEX.y:
			return  # Already exists

	var file := FileAccess.open(TEST_DUNGEON_JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("MainScene: could not open test dungeon JSON at '%s'" % TEST_DUNGEON_JSON_PATH)
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


## Called when the player picks a transition cell from the hex map modal dialog.
func _on_dungeon_entry_requested(entrance: Dictionary, spawn_cell: Vector2i) -> void:
	_enter_dungeon(entrance, spawn_cell)


## Creates a DungeonMapController, loads the dungeon, and pushes the dungeon scene.
func _enter_dungeon(entrance: Dictionary, spawn_pos: Vector2i = Vector2i(-1, -1)) -> void:
	var dungeon_json: String = entrance.get("dungeon_data", "")
	if dungeon_json.is_empty():
		push_error("MainScene._enter_dungeon: entrance has empty dungeon_data")
		return

	var dungeon_dict = JSON.parse_string(dungeon_json)
	if dungeon_dict == null:
		push_error("MainScene._enter_dungeon: JSON parse failed for dungeon '%s'" % entrance.get("id", "?"))
		return

	# Hide the hex map — it's a direct child of Main, not managed by NavigationStack.
	# CanvasLayer children (HexHUD) ignore parent visibility, so disable them explicitly.
	_hex_map_renderer.visible = false
	_hex_map_renderer.process_mode = Node.PROCESS_MODE_DISABLED
	var hex_hud = _hex_map_renderer.get_node_or_null("HexHUD")
	if hex_hud != null:
		hex_hud.visible = false

	var dungeon_controller := DungeonMapController.new()
	dungeon_controller.name = "DungeonMapController"
	add_child(dungeon_controller)
	dungeon_controller.add_party_member("party_leader")
	dungeon_controller.load_dungeon(dungeon_dict, spawn_pos)

	var dungeon_scene_packed: PackedScene = preload("res://scenes/maps/dungeon_map.tscn")
	var dungeon_scene = dungeon_scene_packed.instantiate()
	dungeon_scene.setup(dungeon_controller)
	dungeon_scene.exit_requested.connect(_exit_dungeon.bind(dungeon_controller, dungeon_scene))

	# Wire cell_clicked: move party, then auto-use stairs if party landed on one
	dungeon_scene.cell_clicked.connect(
		func(pos: Vector2i):
			if dungeon_controller.can_move_to(pos):
				dungeon_controller.move_party(pos)
				# Auto-use stairs when stepping onto a stair cell
				var m := dungeon_controller.get_map()
				if m != null:
					var tf: String = m.get_cell(pos).get("terrain_feature", "")
					if tf == "stairs_up" or tf == "stairs_down":
						dungeon_controller.use_stairs(pos)
	)
	dungeon_scene.door_interact_requested.connect(
		func(pos: Vector2i): dungeon_controller.interact_door(pos)
	)

	_nav_stack.push_node(dungeon_scene, "dungeon_%s" % entrance.get("id", "unknown"))
	GameState.set_exploration_context(GameState.ExplorationContext.DUNGEON)


## Pops the dungeon scene and restores the hex map.
func _exit_dungeon(dungeon_controller: DungeonMapController, _dungeon_scene: Node) -> void:
	_nav_stack.pop()

	# Clean up the controller
	if is_instance_valid(dungeon_controller):
		dungeon_controller.queue_free()

	# Restore hex map visibility (including CanvasLayer HUD)
	_hex_map_renderer.visible = true
	_hex_map_renderer.process_mode = Node.PROCESS_MODE_INHERIT
	var hex_hud = _hex_map_renderer.get_node_or_null("HexHUD")
	if hex_hud != null:
		hex_hud.visible = true
	GameState.set_exploration_context(GameState.ExplorationContext.WILDERNESS)


# ---------------------------------------------------------------------------
# Settlement entrance seeding and entry
# ---------------------------------------------------------------------------

## Seeds the test settlement entrance at TEST_SETTLEMENT_ENTRANCE_HEX if it doesn't exist.
func _ensure_test_settlement_entrance(campaign_id: String) -> void:
	var file := FileAccess.open(TEST_SETTLEMENT_JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("MainScene: could not open test settlement JSON at '%s'" % TEST_SETTLEMENT_JSON_PATH)
		return
	var json_text := file.get_as_text()
	file.close()

	# Check if already exists — if so, update the JSON data (dev iteration).
	var entrances := CampaignRepository.get_settlement_entrances_for_map(TEST_MAP_ID)
	for e in entrances:
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


## Seeds the Thornwall settlement entrance at TEST_SETTLEMENT_THORNWALL_HEX if it doesn't exist.
func _ensure_test_settlement_thornwall_entrance(campaign_id: String) -> void:
	var file := FileAccess.open(TEST_SETTLEMENT_THORNWALL_JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("MainScene: could not open Thornwall JSON at '%s'" % TEST_SETTLEMENT_THORNWALL_JSON_PATH)
		return
	var json_text := file.get_as_text()
	file.close()

	var entrances := CampaignRepository.get_settlement_entrances_for_map(TEST_MAP_ID)
	for e in entrances:
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


## Called when the player picks a gate from the hex map modal dialog.
func _on_settlement_entry_requested(entrance: Dictionary, gate_node_id: int) -> void:
	_enter_settlement(entrance, gate_node_id)


## Creates a SettlementMapController, loads the settlement, and pushes the scene.
func _enter_settlement(entrance: Dictionary, gate_node_id: int = -1) -> void:
	var settlement_json: String = entrance.get("settlement_data", "")
	if settlement_json.is_empty():
		push_error("MainScene._enter_settlement: entrance has empty settlement_data")
		return

	var settlement_dict = JSON.parse_string(settlement_json)
	if settlement_dict == null:
		push_error("MainScene._enter_settlement: JSON parse failed for settlement '%s'" % entrance.get("id", "?"))
		return

	# Hide the hex map
	_hex_map_renderer.visible = false
	_hex_map_renderer.process_mode = Node.PROCESS_MODE_DISABLED
	var hex_hud = _hex_map_renderer.get_node_or_null("HexHUD")
	if hex_hud != null:
		hex_hud.visible = false

	var settlement_controller := SettlementMapController.new()
	settlement_controller.name = "SettlementMapController"
	add_child(settlement_controller)
	settlement_controller.load_settlement(settlement_dict)
	if gate_node_id >= 0:
		settlement_controller.set_party_node(gate_node_id)

	var settlement_scene_packed: PackedScene = preload("res://scenes/maps/settlement_map.tscn")
	var settlement_scene = settlement_scene_packed.instantiate()
	settlement_scene.setup(settlement_controller)
	settlement_scene.exit_requested.connect(_exit_settlement.bind(settlement_controller, settlement_scene))

	# Wire node_clicked: move party on click
	settlement_scene.node_clicked.connect(
		func(node_id: int):
			if settlement_controller.can_move_to(node_id):
				settlement_controller.move_party(node_id)
	)

	_nav_stack.push_node(settlement_scene, "settlement_%s" % entrance.get("id", "unknown"))
	GameState.set_exploration_context(GameState.ExplorationContext.SETTLEMENT)


## Pops the settlement scene and restores the hex map.
func _exit_settlement(settlement_controller: SettlementMapController, _settlement_scene: Node) -> void:
	_nav_stack.pop()

	# Clean up the controller
	if is_instance_valid(settlement_controller):
		settlement_controller.queue_free()

	# Restore hex map visibility
	_hex_map_renderer.visible = true
	_hex_map_renderer.process_mode = Node.PROCESS_MODE_INHERIT
	var hex_hud = _hex_map_renderer.get_node_or_null("HexHUD")
	if hex_hud != null:
		hex_hud.visible = true
	GameState.set_exploration_context(GameState.ExplorationContext.WILDERNESS)


# ---------------------------------------------------------------------------
# Dev shortcuts (F5 / F6 and Override Panel Testing tab)
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dev_char_creation"):
		_on_dev_char_creation_requested()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dev_dice_test"):
		_on_dev_dice_test_requested({
			"roll_type": "attack_throw", "sides": 20, "count": 1,
			"modifier": 2, "description": "Test Attack Throw (dev)",
		})
		get_viewport().set_input_as_handled()


func _on_dev_char_creation_requested() -> void:
	if _char_creation.visible:
		print("MainScene: character creation is already open.")
		return
	open_character_creation(GameState.campaign_id)


func _on_dev_dice_test_requested(context: Dictionary) -> void:
	if _dice_prompt.visible:
		print("MainScene: dice prompt is already active.")
		return
	EventBus.player_roll_requested.emit(context)


## Opens the character creation wizard for the given campaign.
func open_character_creation(campaign_id: String) -> void:
	if not _char_creation.character_created.is_connected(_on_character_created):
		_char_creation.character_created.connect(_on_character_created, CONNECT_ONE_SHOT)
	if not _char_creation.creation_cancelled.is_connected(_on_creation_cancelled):
		_char_creation.creation_cancelled.connect(_on_creation_cancelled, CONNECT_ONE_SHOT)
	_char_creation.open(campaign_id)


func _on_character_created(character_id: String) -> void:
	if _char_creation.creation_cancelled.is_connected(_on_creation_cancelled):
		_char_creation.creation_cancelled.disconnect(_on_creation_cancelled)
	print("MainScene: character created — id=%s" % character_id)
	GameState.transition_to(GameState.State.EXPLORATION)


func _on_creation_cancelled() -> void:
	if _char_creation.character_created.is_connected(_on_character_created):
		_char_creation.character_created.disconnect(_on_character_created)
	print("MainScene: character creation cancelled.")
