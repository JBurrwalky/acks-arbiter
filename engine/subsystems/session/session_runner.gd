class_name SessionRunner
extends Node

## Session Runner — the game's central orchestrator (E-2).
##
## Manages the gameplay state machine: campaign selection, wilderness/dungeon/
## settlement exploration, combat handoff, session save/load. Uses an
## object-per-state pattern where each state is a SessionState subclass.
##
## Placed in Main.tscn as a child of Main. NOT an autoload.
## This is the SOLE caller of GameState.transition_to() and
## GameState.set_exploration_context() (per E-1 architectural decision).
##
## Dependencies (siblings in Main.tscn):
##   HexMapController, HexMap (renderer), NavigationStack,
##   SceneContainer, SceneTransition


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted after every state transition completes.
signal state_transitioned(from_key: String, to_key: String)

## Emitted after session data is fully loaded and ready.
signal session_loaded(campaign_id: String)

## Emitted after session data is saved.
signal session_saved(campaign_id: String)


# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------

var _current_state: SessionState = null
var _current_state_key: String = ""
var _state_registry: Dictionary = {}


# ---------------------------------------------------------------------------
# Session data
# ---------------------------------------------------------------------------

var _campaign_id: String = ""
var _party_id: String = ""
var _party_data: PartyData = null
var _active_effects: ActiveEffectTracker = null
var _effect_ticker: EffectTicker = null
var _monster_registry: MonsterRegistry = null
var _class_registry: ClassRegistry = null


# ---------------------------------------------------------------------------
# Node references (siblings in Main.tscn, resolved in _ready)
# ---------------------------------------------------------------------------

var _hex_controller: HexMapController
var _hex_renderer: Node
var _nav_stack: NavigationStack
var _scene_container: Node
var _scene_transition: Node


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Resolve sibling references
	_hex_controller = get_parent().get_node("HexMapController")
	_hex_renderer = get_parent().get_node("HexMap")
	_nav_stack = get_parent().get_node("NavigationStack")
	_scene_container = get_parent().get_node("SceneContainer")
	_scene_transition = get_parent().get_node("SceneTransition")

	# Set up navigation stack
	_nav_stack.setup(_scene_container, _scene_transition)

	# Initialize effect tracking (empty until session loads)
	_active_effects = ActiveEffectTracker.new()
	_effect_ticker = EffectTicker.new(_active_effects)

	# Monster data for encounter generation
	_monster_registry = MonsterRegistry.new()

	# Register all states
	_register_states()

	# Boot into campaign select
	transition_to_state("campaign_select")


func _register_states() -> void:
	_state_registry = {
		"campaign_select": func() -> SessionState: return CampaignSelectState.new(),
		"party_creation": func() -> SessionState: return PartyCreationState.new(),
		"session_load": func() -> SessionState: return SessionLoadState.new(),
		"wilderness": func() -> SessionState: return WildernessExploreState.new(),
		"dungeon": func() -> SessionState: return DungeonExploreState.new(),
		"settlement": func() -> SessionState: return SettlementExploreState.new(),
		"combat": func() -> SessionState: return CombatState.new(),
		"session_end": func() -> SessionState: return SessionEndState.new(),
	}


# ---------------------------------------------------------------------------
# State transitions
# ---------------------------------------------------------------------------

## Transitions to [param state_key]. Calls exit() on current, enter() on new.
## [param context] carries transition-specific data.
func transition_to_state(state_key: String, context: Dictionary = {}) -> void:
	if not _state_registry.has(state_key):
		push_error("SessionRunner.transition_to_state: unknown state '%s'" % state_key)
		return

	cancel_pending_roll()

	var old_key := _current_state_key
	if _current_state != null:
		_current_state.exit(self)

	_current_state_key = state_key
	_current_state = _state_registry[state_key].call()
	_current_state.enter(self, context)
	_sync_game_state(state_key)
	state_transitioned.emit(old_key, state_key)
	EventBus.session_state_transitioned.emit(old_key, state_key)


## Routes a validated action to the current state. Returns true if the state
## handled it (possibly triggering a transition).
## This is the entry point for LLM-interpreted actions.
func submit_action(action: String, payload: Dictionary = {}) -> bool:
	if _current_state == null:
		return false
	var next_key: String = _current_state.handle_action(self, action, payload)
	if not next_key.is_empty():
		transition_to_state(next_key, payload)
		return true
	return false


## Synchronises GameState with the current session runner state.
## This is the SOLE caller of GameState.transition_to() and set_exploration_context().
func _sync_game_state(state_key: String) -> void:
	match state_key:
		"campaign_select":
			if GameState.current_state != GameState.State.MAIN_MENU:
				GameState.transition_to(GameState.State.MAIN_MENU)
		"party_creation":
			if GameState.current_state != GameState.State.MAIN_MENU:
				GameState.transition_to(GameState.State.MAIN_MENU)
		"session_load":
			# Transient — GameState.start_session() is called from load_session()
			pass
		"wilderness":
			if GameState.current_state != GameState.State.EXPLORATION:
				GameState.transition_to(GameState.State.EXPLORATION)
			GameState.set_exploration_context(GameState.ExplorationContext.WILDERNESS)
		"dungeon":
			if GameState.current_state != GameState.State.EXPLORATION:
				GameState.transition_to(GameState.State.EXPLORATION)
			GameState.set_exploration_context(GameState.ExplorationContext.DUNGEON)
		"settlement":
			if GameState.current_state != GameState.State.EXPLORATION:
				GameState.transition_to(GameState.State.EXPLORATION)
			GameState.set_exploration_context(GameState.ExplorationContext.SETTLEMENT)
		"combat":
			GameState.transition_to(GameState.State.COMBAT)
		"session_end":
			pass  # end_session() calls GameState.end_session() directly


# ---------------------------------------------------------------------------
# Accessors (for state objects)
# ---------------------------------------------------------------------------

func get_nav_stack() -> NavigationStack:
	return _nav_stack

func get_hex_map_controller() -> HexMapController:
	return _hex_controller

func get_hex_map_renderer() -> Node:
	return _hex_renderer

func get_campaign_id() -> String:
	return _campaign_id

func get_party_id() -> String:
	return _party_id

func get_party_data() -> PartyData:
	return _party_data

func get_active_effects() -> ActiveEffectTracker:
	return _active_effects

func get_monster_registry() -> MonsterRegistry:
	return _monster_registry

func get_class_registry() -> ClassRegistry:
	if _class_registry == null:
		_class_registry = ClassRegistry.new()
	return _class_registry

func get_current_state_key() -> String:
	return _current_state_key


# ---------------------------------------------------------------------------
# Session lifecycle
# ---------------------------------------------------------------------------

## Loads all session data for the given campaign and party.
## Called from SessionLoadState after campaign selection.
func load_session(campaign_id: String, party_id: String) -> void:
	_campaign_id = campaign_id
	_party_id = party_id

	# 1. Start GameState session (triggers Timekeeping.load_state via session_started)
	GameState.start_session(campaign_id, party_id)

	# 2. Load party data
	_party_data = CampaignRepository.load_party_data(party_id)
	if _party_data != null:
		# Populate character_data
		_party_data.character_data = []
		var char_rows: Array = CampaignRepository.list_party_characters(party_id)
		for row: Dictionary in char_rows:
			_party_data.character_data.append(CharacterData.from_dict(row))
		# Populate shared inventory
		var inv_rows: Array = CampaignRepository.get_party_inventory(party_id)
		_party_data.shared_inventory = []
		for row: Dictionary in inv_rows:
			_party_data.shared_inventory.append(InventoryItem.from_dict(row))
		# Populate trained creatures
		_party_data.creature_data = []
		var creature_rows: Array = CampaignRepository.get_trained_creatures_for_party(party_id)
		for row: Dictionary in creature_rows:
			var creature := TrainedCreatureData.from_db(row)
			creature.monster_data = _monster_registry.get_monster(creature.species_id)
			var creature_inv := CampaignRepository.get_creature_inventory(creature.id)
			creature.inventory = []
			for inv_row: Dictionary in creature_inv:
				creature.inventory.append(InventoryItem.from_dict(inv_row))
			_party_data.creature_data.append(creature)
		# Populate draft vehicles
		_party_data.vehicle_data = CampaignRepository.get_draft_vehicles_for_party(party_id)

	# 3. Register party with Timekeeping (if not already)
	Timekeeping.register_party(party_id)

	# 4. Load active effects
	_active_effects.clear()
	var effect_rows: Array = CampaignRepository.get_active_effects(campaign_id)
	for row: Dictionary in effect_rows:
		_active_effects.add_effect(row)

	# 5. Wire EffectTicker to Timekeeping
	_effect_ticker.connect_signals()

	session_loaded.emit(campaign_id)


## Saves all mutable session state to the database.
func save_session() -> void:
	if _campaign_id.is_empty():
		return

	# Party state
	if _party_data != null:
		CampaignRepository.save_party_state(_party_data.to_state_dict())

	# Hex map (if currently in wilderness, save map state)
	if _current_state_key == "wilderness":
		var map_data: HexMapData = _hex_controller.get_map()
		if map_data != null:
			CampaignRepository.save_hex_map(map_data, _campaign_id)

	# Active effects — clear and re-persist all
	CampaignRepository.clear_active_effects(_campaign_id)
	for effect: Dictionary in _active_effects.get_all_effects():
		var db_effect: Dictionary = effect.duplicate(true)
		db_effect["campaign_id"] = _campaign_id
		CampaignRepository.save_active_effect(db_effect)

	session_saved.emit(_campaign_id)
	EventBus.campaign_saved.emit(_campaign_id)


## Ends the current session: saves, disconnects, resets.
func end_session() -> void:
	cancel_pending_roll()
	save_session()
	_effect_ticker.disconnect_signals()
	_active_effects.clear()
	_party_data = null
	_campaign_id = ""
	_party_id = ""
	GameState.end_session()  # triggers Timekeeping reset, DiceSystem clear


# ---------------------------------------------------------------------------
# Exploration primitives (called by state objects)
# ---------------------------------------------------------------------------

## Rolls an encounter check. For wilderness, pass the terrain at the party's hex.
## For dungeon, pass null (uses standard 1-in-6).
## Returns {triggered: bool, encounter_data: Dictionary}.
## When triggered, encounter_data includes monster_group, number, and reaction_roll
## populated from MonsterRegistry and the terrain encounter tables.
func do_encounter_check(terrain: HexTerrainData) -> Dictionary:
	var threshold: int = 1  # default: encounter on 1 in 6

	if terrain != null:
		# Civilized terrain: no random encounters
		if terrain.civilization == HexTerrainData.TERRITORY_CIVILIZED:
			return {"triggered": false, "encounter_data": {}}
		# Borderlands and Wilderness both use 1-in-6
		# (Future: different thresholds by territory type)

	var roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "encounter_check")

	if roll.modified_total <= threshold:
		# Pick a monster from the terrain's encounter table
		var monster_id := _pick_encounter_monster(terrain)
		if monster_id.is_empty():
			# No monsters in catalog for this terrain — skip encounter
			return {"triggered": false, "encounter_data": {}}

		# Roll encounter number (1d6 for now; future: use per-monster encounter dice)
		var count_roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "encounter_number")
		var count: int = maxi(1, count_roll.modified_total)

		# Roll reaction (2d6)
		var reaction: RollResult = DiceSystem.roll_digital(6, 2, 0, "reaction")
		var disposition := _reaction_to_disposition(reaction.modified_total)

		var hex_id := ""
		if terrain != null and _party_data != null:
			hex_id = "%d,%d" % [_party_data.current_hex_q, _party_data.current_hex_r]

		var encounter_data := {
			"encounter_id": CampaignRepository.generate_id(),
			"monster_group": monster_id,
			"number": count,
			"reaction_roll": reaction.modified_total,
			"behavioral_disposition": disposition,
			"terrain_category": terrain.movement_cost_category() if terrain != null else "dungeon",
			"territory": terrain.civilization if terrain != null else "wilderness",
			"hex_id": hex_id,
			"roll": roll.modified_total,
		}
		EventBus.encounter_triggered.emit(encounter_data)
		return {"triggered": true, "encounter_data": encounter_data}

	return {"triggered": false, "encounter_data": {}}


## Picks a random monster for an encounter based on terrain weights.
## Returns a monster_id from the catalog, or "" if none available.
func _pick_encounter_monster(terrain: HexTerrainData) -> String:
	if _monster_registry == null or _monster_registry.get_monster_count() == 0:
		return ""

	# Get weighted terrain table keys for this hex
	var weights: Dictionary = terrain.encounter_table_weights() if terrain != null else {}
	if weights.is_empty():
		# Dungeon or unknown — pick from all monsters
		var all_ids := _monster_registry.get_all_monster_ids()
		if all_ids.is_empty():
			return ""
		return all_ids[randi() % all_ids.size()]

	# Collect candidate monsters from all relevant terrain tables
	var candidates: Array[String] = []
	for table_key in weights:
		if table_key == "_natural":
			continue  # sentinel for borderlands — skip
		var table_monsters := _monster_registry.get_monsters_for_terrain(table_key)
		for mid in table_monsters:
			if mid not in candidates:
				candidates.append(mid)

	if candidates.is_empty():
		# Fallback: pick from all monsters
		var all_ids := _monster_registry.get_all_monster_ids()
		if all_ids.is_empty():
			return ""
		return all_ids[randi() % all_ids.size()]

	return candidates[randi() % candidates.size()]


## Maps a 2d6 reaction roll total to the ACKS five-state disposition.
## Sacred table from rules/ax_reactions_and_influencing.xml.
static func _reaction_to_disposition(total: int) -> String:
	if total <= 2:
		return "hostile"
	elif total <= 5:
		return "unfriendly"
	elif total <= 8:
		return "neutral"
	elif total <= 11:
		return "indifferent"
	else:
		return "friendly"


## Advances game time by the given number of exploration turns.
## EffectTicker automatically handles ActiveEffectTracker tick-down.
func advance_exploration_time(turns: int) -> void:
	if turns <= 0:
		return
	Timekeeping.advance_turns(turns)


## Cancels any pending player_roll() coroutine by emitting the cancellation signal.
## Called at every state transition boundary.
func cancel_pending_roll() -> void:
	EventBus.player_roll_cancelled.emit()
