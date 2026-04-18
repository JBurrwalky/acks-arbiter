extends Node

## GameState — global session state machine.
##
## No class_name declaration — autoload scripts must not use class_name
## (causes "hides an autoload singleton" error in Godot 4). Reference as:
##   GameState.current_state
##   GameState.transition_to(GameState.State.COMBAT)
##
## Registered as autoload "GameState" in project.godot.


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

## Dice rolling mode. Saved to and loaded from user://settings.cfg.
## Changed at runtime via the in-game settings menu.
enum DiceMode {
	DIGITAL,  ## App rolls automatically. No player input required for any roll.
	PHYSICAL, ## App always prompts the player to enter results from physical dice.
	HYBRID,   ## Default. Player-facing rolls (PC attacks, saves, skills) prompt;
			  ## NPC/GM rolls (encounter checks, morale, reaction) are always digital.
}

## Every top-level phase the application can be in.
enum State {
	MAIN_MENU,          ## Title screen and campaign selection
	CHARACTER_CREATION, ## New-character wizard
	LOADING,            ## Loading or saving a campaign (blocks input)
	EXPLORATION,        ## Active exploration: dungeon, wilderness, or settlement
	COMBAT,             ## Turn-based combat encounter is running
	DOWNTIME,           ## Between-adventure downtime activities
	DOMAIN,             ## Domain management phase (monthly cycle)
	PAUSED,             ## Game paused over any other state
}

## Granular exploration context — avoids bloating the top-level State enum
## with subtypes. Meaningful only when current_state == EXPLORATION.
enum ExplorationContext {
	NONE,
	DUNGEON,
	WILDERNESS,
	SETTLEMENT,
}


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted after the state machine transitions to a new phase.
signal state_changed(from_state: State, to_state: State)

## Emitted when a campaign is loaded and the session is ready to begin.
signal session_started(campaign_id: String)

## Emitted when the player returns to the main menu (save + teardown complete).
signal session_ended

## Emitted when the exploration context changes within EXPLORATION state.
signal exploration_context_changed(context: ExplorationContext)


# ---------------------------------------------------------------------------
# Public variables
# ---------------------------------------------------------------------------

## The currently active game phase. Read externally; mutate only via transition_to().
var current_state: State = State.MAIN_MENU

## The state active before PAUSED. Restored on resume().
var pre_pause_state: State = State.MAIN_MENU

## Current exploration context. Meaningful only when current_state == EXPLORATION.
var exploration_context: ExplorationContext = ExplorationContext.NONE

## Persistent identifier for the loaded campaign.
var campaign_id: String = ""

## Identifier for the active party record in the database.
var party_id: String = ""

## The party currently being controlled by the player. When there is only one
## party, this equals party_id. When split, the player can switch this via the
## Party Management overlay to control the other party.
var active_party_id: String = ""

## Currently active (selected) player character. Set by the UI when the player
## picks a character in the party roster. Used by PartyWallet and inventory
## transfer logic to determine who initiates transactions.
var active_character_id: String = ""

## Location key for the active party's current position. Updated by SessionRunner
## on state transitions. Read by autoloads that can't reference SessionRunner directly.
## Format: "hex:Q,R" | "dungeon:ID:level:N" | "settlement:ID" | "none" | "unknown"
var current_location_key: String = "unknown"

## Pending dice override queue. Keys are roll_type strings (snake_case from the
## action vocabulary, e.g. "attack_throw", "encounter_check"). Values are the
## forced modified_total (final result including modifiers). Consumed by DiceSystem
## on the next matching roll. Written by OverrideManager; read by DiceSystem.
var dice_overrides: Dictionary = {}

## Active dice rolling mode. Default is HYBRID. Persisted to user://settings.cfg.
## Change at runtime with set_dice_mode(); never write this var directly.
var dice_mode: DiceMode = DiceMode.HYBRID

const _SETTINGS_PATH := "user://settings.cfg"


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Transition to [param new_state]. No-ops if already in that state.
func transition_to(new_state: State) -> void:
	if new_state == current_state:
		return
	var previous := current_state
	current_state = new_state
	state_changed.emit(previous, new_state)


## Pause the game, remembering the current state for restoration.
func pause() -> void:
	if current_state == State.PAUSED:
		return
	pre_pause_state = current_state
	transition_to(State.PAUSED)


## Resume from pause, restoring the pre-pause state.
func resume() -> void:
	if current_state != State.PAUSED:
		return
	transition_to(pre_pause_state)


## Set the granular exploration context. Only valid during EXPLORATION state.
func set_exploration_context(context: ExplorationContext) -> void:
	assert(
		current_state == State.EXPLORATION,
		"GameState.set_exploration_context: called outside EXPLORATION state"
	)
	if context == exploration_context:
		return
	exploration_context = context
	exploration_context_changed.emit(context)


## Begin a session. Transitions to EXPLORATION and emits session_started.
func start_session(p_campaign_id: String, p_party_id: String) -> void:
	assert(not p_campaign_id.is_empty(), "GameState.start_session: campaign_id must not be empty")
	assert(not p_party_id.is_empty(), "GameState.start_session: party_id must not be empty")
	campaign_id = p_campaign_id
	party_id = p_party_id
	active_party_id = p_party_id
	transition_to(State.EXPLORATION)
	session_started.emit(campaign_id)


## End the current session and return to MAIN_MENU.
func end_session() -> void:
	campaign_id = ""
	party_id = ""
	active_party_id = ""
	current_location_key = "unknown"
	exploration_context = ExplorationContext.NONE
	transition_to(State.MAIN_MENU)
	session_ended.emit()


## Switch the active party. Emits EventBus.active_party_changed on change.
func set_active_party(new_party_id: String) -> void:
	if active_party_id == new_party_id:
		return
	var prev := active_party_id
	active_party_id = new_party_id
	EventBus.active_party_changed.emit(prev, new_party_id)


## Returns true if a campaign is currently loaded.
func is_in_session() -> bool:
	return not campaign_id.is_empty()


## Change the active dice mode and persist the setting.
func set_dice_mode(mode: DiceMode) -> void:
	dice_mode = mode
	save_settings()


## Persist current settings to user://settings.cfg.
func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("dice", "mode", dice_mode)
	var err := config.save(_SETTINGS_PATH)
	if err != OK:
		push_error("GameState.save_settings: could not write settings file (err=%d)" % err)


## Load settings from user://settings.cfg. Called once at startup.
## No-ops gracefully if the file doesn't exist yet (first launch).
func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(_SETTINGS_PATH) != OK:
		return  # File not present — use defaults
	dice_mode = config.get_value("dice", "mode", DiceMode.HYBRID) as DiceMode
