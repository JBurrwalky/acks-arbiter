extends Node

## Main scene — boots the application and delegates to SessionRunner.
##
## SessionRunner (child node) handles all game orchestration: campaign
## selection, exploration, combat, session lifecycle. This script only
## manages dev overlays and shortcuts that are independent of the game loop.

@onready var _session_runner: SessionRunner = $SessionRunner
@onready var _override_manager: OverrideManager = $OverrideManager
@onready var _override_panel = $OverridePanel
@onready var _hex_controller: HexMapController = $HexMapController
@onready var _char_creation = $CharacterCreationScreen
@onready var _dice_prompt = $DicePrompt


func _ready() -> void:
	# Wire dev overlay systems (independent of session runner)
	_override_panel.setup(_override_manager, _hex_controller)
	EventBus.dev_character_creation_requested.connect(_on_dev_char_creation_requested)
	EventBus.dev_dice_test_requested.connect(_on_dev_dice_test_requested)


# ---------------------------------------------------------------------------
# Dev shortcuts
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
		return
	open_character_creation(GameState.campaign_id)


func _on_dev_dice_test_requested(context: Dictionary) -> void:
	if _dice_prompt.visible:
		return
	var saved_mode: int = GameState.dice_mode
	GameState.dice_mode = GameState.DiceMode.PHYSICAL
	DiceSystem.player_roll(
		context.get("sides", 20),
		context.get("count", 1),
		context.get("modifier", 0),
		context.get("roll_type", "dev_test"),
		context.get("description", "Dev Test Roll"),
	)
	GameState.dice_mode = saved_mode


func open_character_creation(campaign_id: String) -> void:
	if campaign_id.is_empty():
		push_warning("MainScene.open_character_creation: no campaign loaded.")
		return

	# One-shot connections for creation result
	var on_created := func(character_id: String):
		GameState.transition_to(GameState.State.EXPLORATION)
	var on_cancelled := func():
		pass

	if not _char_creation.character_created.is_connected(on_created):
		_char_creation.character_created.connect(on_created, CONNECT_ONE_SHOT)
	if not _char_creation.creation_cancelled.is_connected(on_cancelled):
		_char_creation.creation_cancelled.connect(on_cancelled, CONNECT_ONE_SHOT)

	_char_creation.open(campaign_id)
