class_name SessionRunner
extends Node

## Session Runner — the game's central orchestrator (E-2).
##
## Manages the gameplay state machine: campaign selection, wilderness/dungeon/
## settlement exploration, combat handoff, session save/load. Uses an
## object-per-state pattern where each state is a SessionState subclass.
##
## The real-time-with-pause event scheduler is the backbone of gameplay.
## During active exploration states (wilderness, dungeon, settlement), the
## scheduler loop advances the game clock, resolves events, and dispatches
## to registered event handlers. Meta-states (campaign_select, party_creation,
## session_load, session_end) bypass the scheduler entirely.
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
# Event scheduler (real-time-with-pause clock)
# ---------------------------------------------------------------------------

var _scheduler: EventScheduler = null
var _handler_registry: EventHandlerRegistry = null
var _scheduler_loop: SchedulerLoop = null
var _domain_handlers: DomainHandlers = null
## Long-lived WildernessHandlers instance owning the global day-tick handler
## (Phase 3, 2026-05-04). State-scoped registration still lives in
## WildernessExploreState.enter; this instance only holds the cross-state
## day-tick.
var _wilderness_global_handlers: WildernessHandlers = null
var _entity_outliner: EntityOutliner = null

## State keys where the scheduler loop should tick.
const _SCHEDULER_STATES := ["wilderness", "dungeon", "settlement", "camp", "encounter", "downtime"]

## Parties whose time is ahead of the global clock (post-combat rounding,
## post-dungeon exit). A locked party cannot receive new movement or activity
## orders until the world clock catches up. The UI should gray out controls.
## Keys: party_id (String), values: true.
var _locked_parties: Dictionary = {}


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
# Spell-system shared instances. Constructed once in _ready and re-used across
# combat sessions, settlement / dungeon Cast Spell surfaces, and the slot reset
# handler. Out-of-combat surfaces (Session 3) reach for them via the public
# accessors.
var _spell_registry: SpellRegistry = null
var _effect_registry: SpellEffectRegistry = null
var _custom_resolvers: CustomResolverRegistry = null
var _casting_resolver: CastingResolver = null
var _spell_slot_reset_handler: SpellSlotResetHandler = null


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

	# Initialize the spell system shared instances. Resolver is built once
	# and consulted by both combat (CombatController) and out-of-combat
	# surfaces (DungeonContextMenu Cast Spell, Character tab Cast button,
	# party inventory submenus). The slot reset handler subscribes to
	# EventBus.rest_taken via its constructor.
	_spell_registry = SpellRegistry.new()
	_effect_registry = SpellEffectRegistry.new(_spell_registry)
	_custom_resolvers = CustomResolverRegistry.new()
	var condition_catalog := ConditionCatalog.new()
	_casting_resolver = CastingResolver.new(
		_spell_registry,
		_effect_registry,
		_active_effects,
		condition_catalog,
		_custom_resolvers,
		null,  # geometry — uses static class methods
		CampaignRepository,
		DiceSystem)
	_spell_slot_reset_handler = SpellSlotResetHandler.new(
		CampaignRepository,
		Callable(self, "_lookup_party_casters"))

	# Monster data for encounter generation
	_monster_registry = MonsterRegistry.new()

	# Initialize event scheduler subsystem
	_scheduler = EventScheduler.new()
	_handler_registry = EventHandlerRegistry.new()
	_scheduler_loop = SchedulerLoop.new()
	EventBus.clock_speed_requested.connect(_on_clock_speed_requested)

	# Register all states
	_register_states()

	# Boot into campaign select
	transition_to_state("campaign_select")


func _process(delta: float) -> void:
	if _scheduler_loop == null:
		return
	if _current_state_key not in _SCHEDULER_STATES:
		return

	_scheduler_loop.tick(delta)

	# After each tick, check if the loop requested combat or a state transition.
	if _scheduler_loop.combat_requested:
		var combat_data: Dictionary = _scheduler_loop.combat_data
		_scheduler_loop.combat_requested = false
		_scheduler_loop.combat_data = {}
		transition_to_state("combat", combat_data)

	elif not _scheduler_loop.transition_requested.is_empty():
		var target_state: String = _scheduler_loop.transition_requested
		var target_data: Dictionary = _scheduler_loop.transition_data
		_scheduler_loop.transition_requested = ""
		_scheduler_loop.transition_data = {}
		transition_to_state(target_state, target_data)


func _register_states() -> void:
	_state_registry = {
		"campaign_select": func() -> SessionState: return CampaignSelectState.new(),
		"party_creation": func() -> SessionState: return PartyCreationState.new(),
		"session_load": func() -> SessionState: return SessionLoadState.new(),
		"wilderness": func() -> SessionState: return WildernessExploreState.new(),
		"dungeon": func() -> SessionState: return DungeonExploreState.new(),
		"settlement": func() -> SessionState: return SettlementExploreState.new(),
		"combat": func() -> SessionState: return CombatState.new(),
		"camp": func() -> SessionState: return CampState.new(),
		"encounter": func() -> SessionState: return EncounterState.new(),
		"downtime": func() -> SessionState: return DowntimeState.new(),
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

	# Update GameState.current_location_key for autoload consumers.
	# Only exploration states return real keys; overlay states return "unknown"
	# (preserving the parent exploration state's key); meta states get "none".
	if state_key in ["campaign_select", "party_creation", "session_load", "session_end"]:
		GameState.current_location_key = "none"
	elif state_key in ["wilderness", "dungeon", "settlement"]:
		GameState.current_location_key = _current_state.get_location_key_for_character("")

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

func get_scene_container() -> Node:
	return _scene_container

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


func get_spell_registry() -> SpellRegistry:
	return _spell_registry


func get_effect_registry() -> SpellEffectRegistry:
	return _effect_registry


func get_casting_resolver() -> CastingResolver:
	return _casting_resolver


func get_custom_resolver_registry() -> CustomResolverRegistry:
	return _custom_resolvers


func _lookup_party_casters() -> Array:
	## Callable used by SpellSlotResetHandler to fetch the active party's
	## caster CharacterData. Returns CharacterData (or [] when no party loaded).
	if _party_data == null or _party_data.character_data.is_empty():
		return []
	var casters: Array = []
	for cd: CharacterData in _party_data.character_data:
		# Caster heuristic — same logic as combat_ui_controller.
		var is_caster: bool = cd.combat_progression in ["mage", "cleric"]
		if not is_caster:
			is_caster = cd.character_class in [
				"mage", "elven_spellsword", "elven_nightblade", "warlock", "witch",
				"cleric", "bladedancer", "dwarven_craftpriest"]
		if is_caster:
			casters.append(cd)
	return casters

func get_monster_registry() -> MonsterRegistry:
	return _monster_registry

func get_class_registry() -> ClassRegistry:
	if _class_registry == null:
		_class_registry = ClassRegistry.new()
	return _class_registry

func get_current_state_key() -> String:
	return _current_state_key

func get_scheduler() -> EventScheduler:
	return _scheduler

func get_handler_registry() -> EventHandlerRegistry:
	return _handler_registry

func get_scheduler_loop() -> SchedulerLoop:
	return _scheduler_loop


## Returns the location key for a character by delegating to the current state.
## Falls back to GameState.current_location_key for overlay states that return "unknown".
func get_location_key_for_character(character_id: String) -> String:
	if _current_state == null:
		return "unknown"
	var key := _current_state.get_location_key_for_character(character_id)
	if key == "unknown":
		return GameState.current_location_key
	return key


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
			var loaded_character := CharacterData.from_dict(row)
			_party_data.character_data.append(loaded_character)
			# Stage 2.x — restore the Familiar proficiency proximity bonus on the
			# live CharacterData. Modifiers + flags are runtime-only fields, so
			# they're cleared on save/load round-trip; this rehydrates the
			# bonus for any master with a living familiar in the DB. No-op for
			# masters without a familiar.
			FamiliarController.apply_proximity_for_master(loaded_character)
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

	# 6. Initialize scheduler for this session
	_scheduler.clear()
	_handler_registry.clear()
	_scheduler_loop.setup(_scheduler, _handler_registry, party_id)
	var saved_events: Array = CampaignRepository.get_scheduled_events(campaign_id)
	if not saved_events.is_empty():
		_scheduler.load_from_dicts(saved_events)

	# 7. Register domain handlers if the campaign has active domains.
	#    Domain ticks are global (not per-exploration-state) so they persist
	#    across state transitions.
	if _domain_handlers != null:
		_domain_handlers.unregister(_handler_registry)
		_domain_handlers = null
	var domains: Array = CampaignRepository.list_campaign_domains(campaign_id)
	if not domains.is_empty():
		_domain_handlers = DomainHandlers.new(self)
		_domain_handlers.register(_handler_registry)
		# Only seed the monthly tick if one isn't already in the restored queue.
		var has_domain_tick := false
		for ev in _scheduler.get_all_events():
			if ev.event_type == "domain_monthly_tick":
				has_domain_tick = true
				break
		if not has_domain_tick:
			_domain_handlers.seed_monthly_tick(_scheduler, party_id)

	# 7b. Register the global wilderness day-tick handler (Phase 3, 2026-05-04).
	#     Same pattern as domain handlers: registered at session load, owned
	#     by SessionRunner, survives state transitions. Sustenance and weather
	#     rollover keep firing while the party is in camp/dungeon/settlement.
	if _wilderness_global_handlers != null:
		_wilderness_global_handlers.unregister_global(_handler_registry)
		_wilderness_global_handlers = null
	_wilderness_global_handlers = WildernessHandlers.new(self)
	_wilderness_global_handlers.register_global(_handler_registry)

	# 8. Create the entity outliner and give it the scheduler reference.
	if _entity_outliner == null:
		_entity_outliner = EntityOutliner.new()
		_entity_outliner.name = "EntityOutliner"
		# Position on the right side of the screen as a CanvasLayer child.
		_entity_outliner.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		_entity_outliner.offset_left = -EntityOutliner.PANEL_WIDTH
		_entity_outliner.offset_bottom = -SessionStatusBar.BAR_HEIGHT
		get_parent().add_child(_entity_outliner)
	_entity_outliner.set_scheduler(_scheduler)
	_entity_outliner.visible = true

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

	# Scheduled events — clear and re-persist all non-cancelled
	CampaignRepository.clear_scheduled_events(_campaign_id)
	if _scheduler != null:
		for event_dict: Dictionary in _scheduler.to_dicts():
			CampaignRepository.save_scheduled_event(_campaign_id, event_dict)

	session_saved.emit(_campaign_id)
	EventBus.campaign_saved.emit(_campaign_id)


## Ends the current session: saves, disconnects, resets.
func end_session() -> void:
	cancel_pending_roll()
	save_session()
	_effect_ticker.disconnect_signals()
	_active_effects.clear()
	if _domain_handlers != null:
		_domain_handlers.unregister(_handler_registry)
		_domain_handlers = null
	if _wilderness_global_handlers != null:
		_wilderness_global_handlers.unregister_global(_handler_registry)
		_wilderness_global_handlers = null
	if _entity_outliner != null:
		_entity_outliner.visible = false
	_scheduler.clear()
	_handler_registry.clear()
	_scheduler_loop.pause()
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
## [param dungeon_wandering_table]: optional dungeon-local weighted monster
## table (entries: {monster_key, weight}). When non-empty and [param terrain]
## is null (dungeon context), the monster is picked from this table instead of
## the full monster catalog. Unknown in wilderness flows — leave default.
func do_encounter_check(terrain: HexTerrainData,
		dungeon_wandering_table: Array = []) -> Dictionary:
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
		var monster_id := _pick_encounter_monster(terrain, dungeon_wandering_table)
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
## If [param dungeon_wandering_table] is non-empty, it takes precedence over
## the terrain/catalog fallback — used to scope dungeon wandering rolls to a
## curated per-dungeon monster list.
func _pick_encounter_monster(terrain: HexTerrainData,
		dungeon_wandering_table: Array = []) -> String:
	if _monster_registry == null or _monster_registry.get_monster_count() == 0:
		return ""

	# Per-dungeon table overrides everything else.
	if not dungeon_wandering_table.is_empty():
		return _weighted_pick_from_table(dungeon_wandering_table)

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


## Weighted pick from [{"monster_key": String, "weight": int}, ...].
## Falls back to uniform selection if every weight is <= 0.
func _weighted_pick_from_table(table: Array) -> String:
	var total_weight: int = 0
	for entry in table:
		total_weight += maxi(0, int(entry.get("weight", 1)))

	if total_weight <= 0:
		# Degenerate weights — uniform pick across entries.
		var idx := randi() % table.size()
		return str(table[idx].get("monster_key", ""))

	var r := randi() % total_weight
	var accum := 0
	for entry in table:
		accum += maxi(0, int(entry.get("weight", 1)))
		if r < accum:
			return str(entry.get("monster_key", ""))

	# Safety net (shouldn't reach here).
	return str(table[-1].get("monster_key", ""))


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


# ---------------------------------------------------------------------------
# Scheduler integration
# ---------------------------------------------------------------------------

## Handles UI-driven clock speed change requests via EventBus.
func _on_clock_speed_requested(speed: int) -> void:
	if _scheduler_loop == null:
		return
	if _current_state_key not in _SCHEDULER_STATES:
		return
	_scheduler_loop.set_speed(speed)


## Check whether the active party's clock is ahead of the global clock
## (e.g., after combat turn-rounding or dungeon exit). If so, mark it locked.
## Called by exploration states on re-entry after combat or dungeon exit.
func check_party_time_lock() -> void:
	if _party_id.is_empty():
		return
	var party_time: int = Timekeeping.get_party_time(_party_id)
	var leading: String = Timekeeping.get_leading_party()
	if leading.is_empty() or leading == _party_id:
		# Single party or this party IS the leader — no lock needed.
		_locked_parties.erase(_party_id)
		return
	var leader_time: int = Timekeeping.get_party_time(leading)
	if party_time > leader_time:
		# Party is ahead — lock it until the world catches up.
		_locked_parties[_party_id] = true
	else:
		_locked_parties.erase(_party_id)


## Returns true if [param party_id] is time-locked (ahead of the global clock).
func is_party_locked(party_id: String) -> bool:
	return _locked_parties.get(party_id, false)


## Unlock a party (called when the global clock catches up).
func unlock_party(party_id: String) -> void:
	_locked_parties.erase(party_id)
