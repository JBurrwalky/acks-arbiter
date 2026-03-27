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

## Pending dice override queue. Keys are roll_type strings (snake_case from the
## action vocabulary, e.g. "attack_throw", "encounter_check"). Values are the
## forced integer result. Consumed by the dice subsystem on the next matching roll.
## Written by OverrideManager; read by the dice subsystem when built.
var dice_overrides: Dictionary = {}


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
	transition_to(State.EXPLORATION)
	session_started.emit(campaign_id)


## End the current session and return to MAIN_MENU.
func end_session() -> void:
	campaign_id = ""
	party_id = ""
	exploration_context = ExplorationContext.NONE
	transition_to(State.MAIN_MENU)
	session_ended.emit()


## Returns true if a campaign is currently loaded.
func is_in_session() -> bool:
	return not campaign_id.is_empty()
