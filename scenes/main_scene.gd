extends Node

## Temporary test harness: loads the test hex map and wires up the renderer.
## This will be replaced by the full session runner + navigation stack.
##
## Map persistence: on first run, seeds the DB from test_hex_map.json.
## On subsequent runs, loads directly from DB. Fog state is preserved across runs.

const TEST_MAP_ID := "test_ashford_vale"
const TEST_CAMPAIGN_ID := "test_campaign_01"
const TEST_PARTY_ID := "test_party_01"
const TEST_MAP_JSON_PATH := "res://data/test_hex_map.json"

@onready var _hex_map_renderer = $HexMap
@onready var _controller: HexMapController = $HexMapController
@onready var _override_manager: OverrideManager = $OverrideManager
@onready var _override_panel = $OverridePanel
@onready var _char_creation = $CharacterCreationScreen
@onready var _dice_prompt = $DicePrompt


func _ready() -> void:
	# Wire renderer to controller before loading (connects signals)
	_hex_map_renderer.setup(_controller)
	_hex_map_renderer.hex_clicked.connect(_on_hex_clicked)

	var map_data := _load_or_seed_map()
	if map_data == null:
		push_error("MainScene: Failed to load hex map — cannot start.")
		return

	# Load the map (triggers fog reveal + signals to renderer)
	_controller.load_map(map_data)

	# Persist fog state after controller initializes it
	CampaignRepository.save_hex_map(map_data, TEST_CAMPAIGN_ID)

	# Start session via GameState (sets campaign_id, party_id, transitions to EXPLORATION)
	GameState.start_session(TEST_CAMPAIGN_ID, TEST_PARTY_ID)
	GameState.set_exploration_context(GameState.ExplorationContext.WILDERNESS)

	# Inject dependencies into the override panel
	_override_panel.setup(_override_manager, _controller)

	# Wire dev-testing signals from OverridePanel Testing tab + F5/F6 hotkeys
	EventBus.dev_character_creation_requested.connect(_on_dev_char_creation_requested)
	EventBus.dev_dice_test_requested.connect(_on_dev_dice_test_requested)

	# Use OverridePanel (Ctrl+Alt+O) → Testing tab, or F5/F6 hotkeys to launch screens.
	# Remove these signals and the handlers below once the session runner manages navigation.


## Returns a HexMapData from DB if it exists, otherwise loads from JSON and seeds the DB.
func _load_or_seed_map() -> HexMapData:
	var from_db := CampaignRepository.load_hex_map(TEST_MAP_ID)
	if from_db != null:
		return from_db

	# First run: seed from JSON
	var from_json := HexMapData.load_from_file(TEST_MAP_JSON_PATH)
	if from_json == null:
		push_error("MainScene: Could not load %s" % TEST_MAP_JSON_PATH)
		return null

	# Ensure the test campaign and party exist in the DB
	_ensure_test_campaign()

	# Save the map so future runs load from DB
	if not CampaignRepository.save_hex_map(from_json, TEST_CAMPAIGN_ID):
		push_error("MainScene: save_hex_map failed — continuing with in-memory map.")
	return from_json


func _ensure_test_campaign() -> void:
	# INSERT OR IGNORE is idempotent — safe to run on every first-seed call.
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[TEST_CAMPAIGN_ID, "Test Campaign", "Ashford Vale"]
	)
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[TEST_PARTY_ID, TEST_CAMPAIGN_ID, "Test Party"]
	)


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
## Connect character_created / creation_cancelled signals before calling.
func open_character_creation(campaign_id: String) -> void:
	_char_creation.character_created.connect(_on_character_created, CONNECT_ONE_SHOT)
	_char_creation.creation_cancelled.connect(_on_creation_cancelled, CONNECT_ONE_SHOT)
	_char_creation.open(campaign_id)


func _on_character_created(character_id: String) -> void:
	print("MainScene: character created — id=%s" % character_id)
	# Resume normal session flow (future: show party roster, navigate to map)
	GameState.transition_to(GameState.State.EXPLORATION)


func _on_creation_cancelled() -> void:
	print("MainScene: character creation cancelled.")


func _on_hex_clicked(coord: Vector2i) -> void:
	_controller.move_party(coord)
	# Persist updated fog state to DB after each move
	var map_data := _controller.get_map()
	if map_data != null:
		CampaignRepository.save_hex_map(map_data, TEST_CAMPAIGN_ID)
