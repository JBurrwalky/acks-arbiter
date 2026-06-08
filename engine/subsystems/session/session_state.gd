class_name SessionState
extends RefCounted

## Base class for all session runner states.
##
## Each concrete state extends this and overrides the lifecycle methods.
## The [param runner] argument is the SessionRunner node (untyped to avoid
## circular class_name references).
##
## State lifecycle:
##   enter(runner, context)   — state becomes active; wire signals, show UI
##   exit(runner)             — state is leaving; disconnect signals, clean up
##   handle_action(runner, action, payload) — process a validated action
##                              returns next state key ("" to stay)


## Called when this state becomes active.
## [param context] carries transition-specific data (e.g., dungeon entrance dict).
func enter(runner, context: Dictionary) -> void:
	pass


## Called when this state is being left. Clean up controllers, scenes, signals.
func exit(runner) -> void:
	pass


## Called by SessionRunner.save_session() to persist this context's live,
## in-memory-only state to the DB (gdd-savegame-system.md §5.3). Each primary
## exploration state overrides this to flush what it owns: wilderness saves the
## hex map (fog/survey), dungeon saves voxel cells + per-entity positions,
## settlement saves the current POI. Default is a no-op for overlay/meta states.
func flush_to_db(runner) -> void:
	pass


## Returns true if this state is currently resolving turn-based combat. Used to
## block saving mid-combat (gdd-savegame-system.md §5.7). The dedicated "combat"
## state is always in combat; dungeon combat runs in-place inside
## DungeonExploreState, so it overrides this to report its live combat flag.
func is_in_combat() -> bool:
	return false


## Called by SessionRunner to process a validated game action.
## Returns the next state key (String) if a transition is warranted, or "" to stay.
## Actions come from either UI interactions or LLM interpretation — the state
## doesn't know or care which input channel produced the action.
func handle_action(runner, action: String, payload: Dictionary) -> String:
	return ""


## Returns a location key for the given character's current position.
## Override in exploration states. Default "unknown" means the state
## doesn't define a location (overlay/meta states).
##
## Format:
##   Wilderness:  "hex:Q,R"
##   Dungeon:     "dungeon:<dungeon_id>:level:<level_number>"
##   Settlement:  "settlement:<settlement_id>"
##   Overlay/meta states: "unknown" (inherits parent via GameState bridge)
##
## v1 simplification: all PCs in the same party state return the same key
## (party moves as a unit). The character_id parameter is reserved for
## future split-party support.
func get_location_key_for_character(_character_id: String) -> String:
	return "unknown"
