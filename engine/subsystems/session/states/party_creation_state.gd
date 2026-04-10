class_name PartyCreationState
extends SessionState

## Manages the new-campaign party creation flow.
##
## Two phases:
##   1. "welcome" — shows welcome screen with world name, Create Party / Cancel.
##   2. "roster"  — shows party roster, loops through character creation.
##
## This state creates the party in DB and sets GameState.campaign_id / party_id
## so that CharacterCreationScreen._finalize_character() can add members to the
## party. Full session loading is deferred to SessionLoadState ("session_load").


# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _campaign_id: String = ""
var _party_id: String = ""
var _world_name: String = ""
var _phase: String = "welcome"  # "welcome" or "roster"

var _runner = null  # SessionRunner reference, set in enter()
var _welcome_screen: Node = null
var _roster_screen: Node = null
var _char_creation: Node = null  # reference to Main.tscn's CharacterCreationScreen

var _on_char_created: Callable
var _on_char_cancelled: Callable


# ---------------------------------------------------------------------------
# SessionState lifecycle
# ---------------------------------------------------------------------------

func enter(runner, context: Dictionary) -> void:
	_runner = runner
	_campaign_id = context.get("campaign_id", "")
	if _campaign_id.is_empty():
		push_error("PartyCreationState: no campaign_id in context")
		runner.transition_to_state("campaign_select")
		return

	# Look up world name
	var campaign: Dictionary = CampaignRepository.get_campaign(_campaign_id)
	_world_name = campaign.get("world_name", "Unknown World")

	# Get reference to CharacterCreationScreen (sibling of SessionRunner in Main.tscn)
	_char_creation = runner.get_parent().get_node("CharacterCreationScreen")

	# Show welcome screen (added directly to Main, not via NavigationStack,
	# because the nav stack may still be mid-transition from the campaign select pop)
	var welcome_scene: PackedScene = preload(
		"res://scenes/ui/party_creation/party_welcome_screen.tscn"
	)
	_welcome_screen = welcome_scene.instantiate()
	_welcome_screen.create_party_pressed.connect(
		func(): runner.submit_action("create_party", {})
	)
	_welcome_screen.cancel_pressed.connect(
		func(): runner.submit_action("cancel_party_creation", {})
	)
	runner.get_parent().add_child(_welcome_screen)
	_welcome_screen.open(_world_name)
	_phase = "welcome"


func exit(_runner) -> void:
	_disconnect_char_creation()

	# Ensure character creation screen is hidden if still open
	if _char_creation != null and _char_creation.visible:
		_char_creation.hide()

	# Free screens (added directly to Main, not via NavigationStack)
	if _welcome_screen != null and is_instance_valid(_welcome_screen):
		_welcome_screen.queue_free()
	if _roster_screen != null and is_instance_valid(_roster_screen):
		_roster_screen.queue_free()

	_welcome_screen = null
	_roster_screen = null
	_char_creation = null
	_runner = null


func handle_action(runner, action: String, payload: Dictionary) -> String:
	match action:
		"create_party":
			return _handle_create_party(runner)
		"cancel_party_creation":
			return _handle_cancel(runner)
		"add_character":
			_handle_add_character()
			return ""
		"character_created":
			_handle_character_created()
			return ""
		"character_cancelled":
			_handle_character_cancelled()
			return ""
		"delete_character":
			_handle_delete_character(payload)
			return ""
		"begin_adventure":
			return "session_load"
	return ""


# ---------------------------------------------------------------------------
# Action handlers
# ---------------------------------------------------------------------------

func _handle_create_party(runner) -> String:
	# Create party in DB
	_party_id = CampaignRepository.create_party(_campaign_id, "Adventuring Party")
	if _party_id.is_empty():
		push_error("PartyCreationState: failed to create party")
		return "campaign_select"

	# Set GameState so CharacterCreationScreen can reference party_id
	GameState.campaign_id = _campaign_id
	GameState.party_id = _party_id

	# Swap welcome -> roster
	if _welcome_screen != null:
		_welcome_screen.close()
		_welcome_screen.queue_free()
		_welcome_screen = null

	var roster_scene: PackedScene = preload(
		"res://scenes/ui/party_creation/party_roster_screen.tscn"
	)
	_roster_screen = roster_scene.instantiate()
	_roster_screen.add_character_pressed.connect(
		func(): runner.submit_action("add_character", {})
	)
	_roster_screen.delete_character_pressed.connect(
		func(char_id: String): runner.submit_action("delete_character", {"character_id": char_id})
	)
	_roster_screen.begin_adventure_pressed.connect(
		func(): runner.submit_action("begin_adventure", {"campaign_id": _campaign_id})
	)
	runner.get_parent().add_child(_roster_screen)
	_roster_screen.open(_campaign_id, _party_id)
	_phase = "roster"
	return ""


func _handle_cancel(runner) -> String:
	# Delete the just-created campaign to avoid orphaned DB records
	if not _campaign_id.is_empty():
		CampaignRepository.delete_campaign(_campaign_id)
	return "campaign_select"


func _handle_add_character() -> void:
	if _char_creation == null:
		push_error("PartyCreationState: no CharacterCreationScreen reference")
		return

	# Connect one-shot signals (use stored _runner member for closure safety)
	_on_char_created = func(character_id: String):
		_runner.submit_action("character_created", {"character_id": character_id})
	_on_char_cancelled = func():
		_runner.submit_action("character_cancelled", {})

	_char_creation.character_created.connect(_on_char_created, CONNECT_ONE_SHOT)
	_char_creation.creation_cancelled.connect(_on_char_cancelled, CONNECT_ONE_SHOT)
	_char_creation.open(_campaign_id)


func _handle_character_created() -> void:
	_disconnect_char_creation()
	# Restore GameState from CHARACTER_CREATION back to MAIN_MENU
	if GameState.current_state == GameState.State.CHARACTER_CREATION:
		GameState.transition_to(GameState.State.MAIN_MENU)
	if _roster_screen != null:
		_roster_screen.refresh()


func _handle_character_cancelled() -> void:
	_disconnect_char_creation()
	if GameState.current_state == GameState.State.CHARACTER_CREATION:
		GameState.transition_to(GameState.State.MAIN_MENU)


func _handle_delete_character(payload: Dictionary) -> void:
	var char_id: String = payload.get("character_id", "")
	if char_id.is_empty():
		return
	CampaignRepository.remove_party_member(_party_id, char_id)
	CampaignRepository.delete_character(char_id)
	if _roster_screen != null:
		_roster_screen.refresh()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _disconnect_char_creation() -> void:
	if _char_creation == null:
		return
	if _on_char_created.is_valid() and _char_creation.character_created.is_connected(_on_char_created):
		_char_creation.character_created.disconnect(_on_char_created)
	if _on_char_cancelled.is_valid() and _char_creation.creation_cancelled.is_connected(_on_char_cancelled):
		_char_creation.creation_cancelled.disconnect(_on_char_cancelled)
