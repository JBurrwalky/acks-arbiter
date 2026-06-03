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
## Urban Growth Stocking Stage C (Migration 126): subscribes to
## EventBus.market_class_advanced and EventBus.settlement_dissolved. Emerges
## new settlement_pois rows when a settlement crosses a market-class
## threshold. Lifecycle is tied to SessionRunner — created at session load,
## torn down at session end.
var _poi_emergence_handler: PoiEmergenceHandler = null
## Urban Growth Stocking Stage D (Migration 126): subscribes to
## EventBus.poi_emerged. Generates baseline head + adherent NPC character
## rows per GDD §7.3 stocking tables, applies §5.2.2 within-band level
## elevation, and writes baseline_head_npc_character_id back onto the POI.
var _baseline_npc_stocker: BaselineNpcStocker = null
## Urban Growth Stocking Stage F (Migration 126): subscribes to
## EventBus.stronghold_completed. Registers a settlement_pois row when a
## player-built stronghold completes inside a settlement hex per GDD §12.4
## / §13.6. Mage L9 sanctum → mages_guild_hall; divine-caster stronghold →
## religious_site (tier='shrine' per Q-UGS-30). Other stronghold archetypes
## leave registered_settlement_poi_id NULL.
var _stronghold_poi_registrar: StrongholdPoiRegistrar = null
## Long-lived WildernessHandlers instance owning the global day-tick handler
## (Phase 3, 2026-05-04). State-scoped registration still lives in
## WildernessExploreState.enter; this instance only holds the cross-state
## day-tick.
var _wilderness_global_handlers: WildernessHandlers = null
## Global SpellHandlers — registers spell_cast_complete and
## spell_cast_encounter_check handlers used by OutOfCombatCastFlow (Session 3).
var _spell_handlers: SpellHandlers = null
## Global CommissionPipeline — registers stronghold_construction_daily_tick
## and seeds the daily tick that advances all in-progress commissions
## (Domain Phase 1, 2026-05-06). Daily granularity is required by the PDF
## "1 day per 500 gp" rule.
var _commission_pipeline: CommissionPipeline = null
## Global SiegeHandlers — registers siege_daily_tick / siege_weekly_tick /
## siege_simplified_concluded handlers (Phase 9B, 2026-05-09). Sieges may
## continue across travel/dungeon/settlement state transitions; the registry
## entries survive any state change.
var _siege_handlers: SiegeHandlers = null
## Global ActivityCatalog + ActivityTimeCostExecutor + StrenuousAccountant
## (Domain Phase 3, 2026-05-07). Owns activity_complete and
## ongoing_session_complete handlers per gdd-realtime-scheduler.md §4.8.
var _activity_catalog: ActivityCatalog = null
var _activity_handler_registry: ActivityHandlerRegistry = null
var _activity_executor: ActivityTimeCostExecutor = null
var _strenuous_accountant: StrenuousAccountant = null
## Global FollowerArrivalResolver (Domain Phase 5, 2026-05-07). Subscribes to
## EventBus.stronghold_construction_progressed for halfway / completed
## milestones; registers a `follower_post_completion_arrival` scheduler event
## for wave 3 (one game-month after completion) per acore_axioms
## §followers_arrival L111-116.
var _follower_arrival_resolver: FollowerArrivalResolver = null
## Global SanctumApprenticeResolver (Phase 10B.1d, 2026-05-11). Subscribes to
## EventBus.stronghold_completed and spawns sanctum apprentices + aspirants
## into the followers table per Q20 [RESOLVED 2026-05-11]. Promotion-roll
## resolution lives in DomainHandlers._resolve_magic_research_month, which
## calls SanctumApprenticeResolver.resolve_promotion_throw for each due
## aspirant.
var _sanctum_apprentice_resolver: SanctumApprenticeResolver = null
var _entity_outliner: EntityOutliner = null
var _entity_outliner_layer: CanvasLayer = null

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
	# Register Session 6 L2-arcane custom resolvers. Future sessions append
	# their own resolvers below as they bind.
	_custom_resolvers.register("web",
		preload("res://engine/subsystems/spells/custom_resolvers/web_resolver.gd").new())
	_custom_resolvers.register("phantasmal_force",
		preload("res://engine/subsystems/spells/custom_resolvers/phantasmal_force_resolver.gd").new())
	# Session 7 (Divine L2):
	_custom_resolvers.register("spiritual_weapon",
		preload("res://engine/subsystems/spells/custom_resolvers/spiritual_weapon_resolver.gd").new())
	# Session 8 (Arcane L3):
	_custom_resolvers.register("dispel_magic",
		preload("res://engine/subsystems/spells/custom_resolvers/dispel_magic_resolver.gd").new())
	_custom_resolvers.register("haste",
		preload("res://engine/subsystems/spells/custom_resolvers/haste_resolver.gd").new())
	# Session 9.6 polish (Floating Disc — replaces the Session 4 stub):
	_custom_resolvers.register("floating_disc",
		preload("res://engine/subsystems/spells/custom_resolvers/floating_disc_resolver.gd").new())
	# Session 10 (Arcane L4):
	_custom_resolvers.register("hallucinatory_terrain",
		preload("res://engine/subsystems/spells/custom_resolvers/hallucinatory_terrain_resolver.gd").new())
	_custom_resolvers.register("polymorph_self",
		preload("res://engine/subsystems/spells/custom_resolvers/polymorph_self_resolver.gd").new())
	_custom_resolvers.register("polymorph_other",
		preload("res://engine/subsystems/spells/custom_resolvers/polymorph_other_resolver.gd").new())
	_custom_resolvers.register("wall_of_fire",
		preload("res://engine/subsystems/spells/custom_resolvers/wall_of_fire_resolver.gd").new())
	_custom_resolvers.register("wall_of_ice",
		preload("res://engine/subsystems/spells/custom_resolvers/wall_of_ice_resolver.gd").new())
	# Session 11 (Divine L4):
	_custom_resolvers.register("animate_dead",
		preload("res://engine/subsystems/spells/custom_resolvers/animate_dead_resolver.gd").new())
	_custom_resolvers.register("sticks_to_snakes",
		preload("res://engine/subsystems/spells/custom_resolvers/sticks_to_snakes_resolver.gd").new())
	# Session 12 (Arcane L5):
	_custom_resolvers.register("cloudkill",
		preload("res://engine/subsystems/spells/custom_resolvers/cloudkill_resolver.gd").new())
	_custom_resolvers.register("conjure_elemental",
		preload("res://engine/subsystems/spells/custom_resolvers/conjure_elemental_resolver.gd").new())
	_custom_resolvers.register("teleport",
		preload("res://engine/subsystems/spells/custom_resolvers/teleport_resolver.gd").new())
	_custom_resolvers.register("wall_of_stone",
		preload("res://engine/subsystems/spells/custom_resolvers/wall_of_stone_resolver.gd").new())
	# Session 13 (Divine L5):
	_custom_resolvers.register("dispel_evil",
		preload("res://engine/subsystems/spells/custom_resolvers/dispel_evil_resolver.gd").new())
	_custom_resolvers.register("insect_plague",
		preload("res://engine/subsystems/spells/custom_resolvers/insect_plague_resolver.gd").new())
	# 2026-06-02 (Divine L5): Restore Life and Limb (+ reverse Finger of
	# Death + standalone shaman Finger of Death routed through the same
	# resolver's reverse branch via resolver_args.forced_reversed=true).
	_custom_resolvers.register("restore_life_and_limb",
		preload("res://engine/subsystems/spells/custom_resolvers/restore_life_and_limb_resolver.gd").new())
	# 2026-06-02 (Tier 4 batch 2): Horn of Blasting item-only "spell"
	# that does 2d6 cone damage + per-target save-vs-Blast for deafening.
	_custom_resolvers.register("horn_blast",
		preload("res://engine/subsystems/spells/custom_resolvers/horn_of_blasting_resolver.gd").new())
	# Session 14 (Arcane L6):
	_custom_resolvers.register("death_spell",
		preload("res://engine/subsystems/spells/custom_resolvers/death_spell_resolver.gd").new())
	_custom_resolvers.register("invisible_stalker",
		preload("res://engine/subsystems/spells/custom_resolvers/invisible_stalker_resolver.gd").new())
	_custom_resolvers.register("projected_image",
		preload("res://engine/subsystems/spells/custom_resolvers/projected_image_resolver.gd").new())
	_custom_resolvers.register("reincarnate",
		preload("res://engine/subsystems/spells/custom_resolvers/reincarnate_resolver.gd").new())
	_custom_resolvers.register("wall_of_iron",
		preload("res://engine/subsystems/spells/custom_resolvers/wall_of_iron_resolver.gd").new())

	# P7 — per-spell expiration callbacks. Each fires on every cleanup cause
	# (duration_expired / concentration_broken / dispelled). Animate Dead is
	# intentionally NOT registered: skeletons/zombies persist past expiration
	# per RAW ("until destroyed or turned").
	_custom_resolvers.register_expiration_callback("polymorph_self",
		Callable(PolymorphSelfResolver, "on_expiration"))
	_custom_resolvers.register_expiration_callback("polymorph_other",
		Callable(PolymorphOtherResolver, "on_expiration"))
	_custom_resolvers.register_expiration_callback("sticks_to_snakes",
		Callable(SticksToSnakesResolver, "on_expiration"))
	_custom_resolvers.register_expiration_callback("conjure_elemental",
		Callable(ConjureElementalResolver, "on_expiration"))
	_custom_resolvers.register_expiration_callback("wall_of_fire",
		Callable(WallOfFireResolver, "on_expiration"))
	_custom_resolvers.register_expiration_callback("wall_of_ice",
		Callable(WallOfIceResolver, "on_expiration"))
	_custom_resolvers.register_expiration_callback("wall_of_stone",
		Callable(WallOfStoneResolver, "on_expiration"))
	_custom_resolvers.register_expiration_callback("wall_of_iron",
		Callable(WallOfIronResolver, "on_expiration"))

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
	# Eyes of the Eagle V2 (2026-06-03) — refresh the party visibility bonus
	# on the hexmap whenever an inventory change or party-membership change
	# could affect a member's `has_eyes_of_the_eagle` flag. Cheap (single
	# integer recompute + setter is idempotent for equal values, so no
	# spurious renderer refresh). Handlers no-op when no party is loaded.
	EventBus.inventory_updated.connect(_on_inventory_updated_for_visibility)
	EventBus.active_party_changed.connect(_on_active_party_changed_for_visibility)
	# Ring of Regeneration round-tick consumer (2026-06-03). Per ACKS Core
	# p.215+ Jedidiah-supplied RAW 2026-06-02: "Regenerates 1 hp per round.
	# Will not regenerate if reduced to 0 hp or less." The handler scans
	# the active party for has_ring_regeneration bearers and increments
	# hp_current by hp_per_round × rounds_elapsed (clamped at hp_max,
	# gated on hp_current > stops_at_or_below_hp). No-op when no party
	# is loaded.
	Timekeeping.round_advanced.connect(_on_round_advanced_for_regeneration)

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


## Activity Time-Cost Executor (Domain Phase 3). UI launchers (Decrees & Remote
## Orders sub-tab, Settlement HiringPanel, etc.) use this to schedule RAW
## activities through the canonical ScheduledEvent pipeline.
func get_activity_executor() -> ActivityTimeCostExecutor:
	return _activity_executor


func get_activity_catalog() -> ActivityCatalog:
	return _activity_catalog


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

	# 2.x. Eyes of the Eagle V2 (2026-06-03) — refresh the hexmap party
	# visibility bonus from the freshly-loaded roster. Bonus is pushed to
	# HexMapController.set_party_visibility_bonus_hexes; the controller's
	# setter auto-re-runs _update_visibility(party_hex) if a map is loaded,
	# so subsequent map loads pick up the right radius. Future inventory
	# changes and party switches refresh via EventBus subscriptions wired
	# in _ready.
	_refresh_party_visibility_bonus()

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
	# Phase 10B.2 Wave 5: always register DomainHandlers + seed monthly tick.
	# Previously the tick only fired when domains existed; commerce monthly
	# drivers (ship operating costs, merchant pool refresh, customs roll,
	# market price drift) need to fire on every campaign regardless of
	# domain presence. DomainHandlers._handle_monthly_tick now degenerates
	# gracefully to commerce-only when domains.is_empty().
	_domain_handlers = DomainHandlers.new(self)
	_domain_handlers.register(_handler_registry)
	# Urban Growth Stocking Stage C (Migration 126): connect the POI
	# emergence handler so market_class_advanced signals from
	# SettlementGrowthResolver trigger POI emergence.
	if _poi_emergence_handler != null:
		_poi_emergence_handler.unregister()
	_poi_emergence_handler = PoiEmergenceHandler.new()
	_poi_emergence_handler.register()
	# Urban Growth Stocking Stage D (Migration 126): connect the baseline
	# NPC stocker so poi_emerged signals from PoiEmergenceHandler trigger
	# NPC generation per §7.3.
	if _baseline_npc_stocker != null:
		_baseline_npc_stocker.unregister()
	_baseline_npc_stocker = BaselineNpcStocker.new()
	_baseline_npc_stocker.register()
	# Urban Growth Stocking Stage F (Migration 126): connect the stronghold
	# POI registrar so stronghold_completed signals from the commission
	# pipeline trigger settlement_pois registration per §12.4 / §13.6.
	if _stronghold_poi_registrar != null:
		_stronghold_poi_registrar.unregister()
	_stronghold_poi_registrar = StrongholdPoiRegistrar.new()
	_stronghold_poi_registrar.register()
	var has_domain_tick := false
	for ev in _scheduler.get_all_events():
		if ev.event_type == "domain_monthly_tick":
			has_domain_tick = true
			break
	if not has_domain_tick:
		_domain_handlers.seed_monthly_tick(_scheduler, party_id)

	# Phase 10B.2 Wave 5: trade-route full-sweep on load (idempotent — only
	# runs once-ever per campaign, short-circuits if trade_routes already
	# populated). Closes [NEEDS-CAMPAIGN-LOAD-WIRING] from Wave 1.
	TradeRouteTriggerHandlers.full_sweep_for_campaign(campaign_id)

	# 7b. Register the global wilderness day-tick handler (Phase 3, 2026-05-04).
	#     Same pattern as domain handlers: registered at session load, owned
	#     by SessionRunner, survives state transitions. Sustenance and weather
	#     rollover keep firing while the party is in camp/dungeon/settlement.
	if _wilderness_global_handlers != null:
		_wilderness_global_handlers.unregister_global(_handler_registry)
		_wilderness_global_handlers = null
	_wilderness_global_handlers = WildernessHandlers.new(self)
	_wilderness_global_handlers.register_global(_handler_registry)

	# 7c. Register global spell handlers (Session 3, 2026-05-05). Owns the
	#     spell_cast_complete sentinel and spell_cast_encounter_check one-off
	#     scheduled by OutOfCombatCastFlow after every successful cast.
	if _spell_handlers != null:
		_spell_handlers.unregister(_handler_registry)
		_spell_handlers = null
	_spell_handlers = SpellHandlers.new(self)
	_spell_handlers.register(_handler_registry)

	# 7d. Register the stronghold construction daily-tick handler (Domain
	#     Phase 1, 2026-05-06). Daily ticks advance all in-progress commissions
	#     by the per-day rate (1 day per 500 gp base, faster at +50%/+100%
	#     speed tiers per acore_stronghold_construction_costs.pdf).
	if _commission_pipeline != null:
		_commission_pipeline.unregister(_handler_registry)
		_commission_pipeline = null
	_commission_pipeline = CommissionPipeline.new(self)
	_commission_pipeline.register(_handler_registry)
	# Seed the daily tick if one isn't already in the restored queue.
	var has_construction_tick := false
	for ev in _scheduler.get_all_events():
		if ev.event_type == "stronghold_construction_daily_tick":
			has_construction_tick = true
			break
	if not has_construction_tick:
		_commission_pipeline.seed_construction_tick(_scheduler, party_id)

	# 7d-2. Register siege handlers (Phase 9B, 2026-05-09). Owns
	#       siege_daily_tick / siege_weekly_tick / siege_simplified_concluded.
	#       Tick events are seeded by SiegeResolver.start_full_siege /
	#       SiegeResolverSimplified.start_simplified_siege when a siege begins.
	if _siege_handlers != null:
		_siege_handlers.unregister(_handler_registry)
		_siege_handlers = null
	_siege_handlers = SiegeHandlers.new(self)
	_siege_handlers.register(_handler_registry)

	# Phase 9C polish 2026-05-09: reconcile disease cure ticks on session load.
	# When a campaign is loaded mid-disease, troop_units rows have is_diseased=1
	# but the disease_cure_weekly_tick events live only in-memory on the
	# scheduler. Re-seed one tick per army with diseased units (idempotent
	# via _schedule_cure_tick_if_absent's get_events_for_owner check).
	var _today_date: Dictionary = Timekeeping.get_date()
	var _today_day: int = int(_today_date.get("year", 0)) * Timekeeping.DAYS_PER_YEAR \
		+ int(_today_date.get("month", 0)) * Timekeeping.DAYS_PER_MONTH \
		+ int(_today_date.get("day", 0))
	DiseaseResolver.reconcile_cure_ticks_on_session_load(_scheduler, _today_day)

	# 7e. Register activity executor + strenuous accountant (Domain Phase 3,
	#     2026-05-07). Owns "activity_complete" and "ongoing_session_complete"
	#     event handlers per gdd-realtime-scheduler.md §4.8. The registry is
	#     populated with all 16 RAW domain-category handlers (Phase 5/9 will
	#     add troops / faith / magical / mercantile / syndicate categories).
	if _activity_executor != null:
		_activity_executor.unregister(_handler_registry)
		_activity_executor = null
	if _strenuous_accountant != null:
		_strenuous_accountant.unsubscribe()
		_strenuous_accountant = null
	_activity_catalog = ActivityCatalog.new()
	_activity_handler_registry = ActivityHandlerRegistry.new()
	DomainActivityHandlersRegistration.register_all(_activity_handler_registry)
	# Phase 10A.2: faith-category activity handlers (8 divine activities).
	FaithActivityHandlersRegistration.register_all(_activity_handler_registry)
	# Phase 10A.3: bardic-category activity handlers (solicit_followers).
	BardicActivityHandlersRegistration.register_all(_activity_handler_registry)
	# Phase 10B.1a: magical_research-category handlers (shell — no handlers in
	# 10B.1a; populated in 10B.1b-f).
	MagicalResearchActivityHandlersRegistration.register_all(_activity_handler_registry)
	# Phase 10B.2 Wave 2: mercantile-category activity handlers (Trade block).
	# Wave 2 ships buy/sell as real; persuade/solicit/locate/accept_shipping_contract
	# are stubs replaced in Waves 10B.2.3 + 10B.2.4.
	MercantileActivityHandlersRegistration.register_all(_activity_handler_registry)
	# Phase 10B.3 UI polish wave: syndicate-category activity handlers
	# (Hijinks). All 8 launchers wired; perform_hijink dispatches to the
	# 6 per-kind handlers (assassinating/carousing/smuggling/spying/
	# stealing/treasure_hunting) shipped in the Phase 10B.3 main wave.
	SyndicateActivityHandlersRegistration.register_all(_activity_handler_registry)
	_activity_executor = ActivityTimeCostExecutor.new(
		self, _activity_catalog, _activity_handler_registry)
	_activity_executor.register(_handler_registry)
	_strenuous_accountant = StrenuousAccountant.new(self, _activity_catalog)
	_strenuous_accountant.subscribe()

	# 7f. Register FollowerArrivalResolver (Domain Phase 5, 2026-05-07).
	#     Listens for halfway / completed stronghold milestones to spawn
	#     class-attracted follower troop_units; schedules wave 3 via the
	#     scheduler for the post-completion-month arrival.
	if _follower_arrival_resolver != null:
		_follower_arrival_resolver.unsubscribe()
		_follower_arrival_resolver = null
	_follower_arrival_resolver = FollowerArrivalResolver.new()
	_follower_arrival_resolver.setup(_scheduler, _handler_registry)

	# 7g. Register SanctumApprenticeResolver (Phase 10B.1d, 2026-05-11).
	#     Listens for stronghold_completed events on sanctum-archetype
	#     strongholds owned by L9+ mage/witch/elven_enchanter/Lightblessed
	#     casters. Spawns 1d6 apprentices (L1-3) + 2d6 aspirants (0-level
	#     Normal Men) in the followers table. Promotion-throw resolution
	#     lives in DomainHandlers._resolve_magic_research_month, called
	#     each monthly tick for aspirants whose 4-month timer has fired.
	if _sanctum_apprentice_resolver != null:
		_sanctum_apprentice_resolver.unsubscribe()
		_sanctum_apprentice_resolver = null
	_sanctum_apprentice_resolver = SanctumApprenticeResolver.new()
	_sanctum_apprentice_resolver.subscribe()

	# 8. Create the entity outliner and give it the scheduler reference.
	if _entity_outliner == null:
		# The outliner is a Control node and must live inside a CanvasLayer so
		# that anchor presets resolve against the viewport rect (not a zero-size
		# Node parent rect).  This mirrors SessionStatusBar, which is itself
		# declared as a CanvasLayer root in session_status_bar.tscn (layer=80).
		_entity_outliner_layer = CanvasLayer.new()
		_entity_outliner_layer.name = "EntityOutlinerLayer"
		_entity_outliner_layer.layer = 79  # just below SessionStatusBar (layer 80)
		get_parent().add_child(_entity_outliner_layer)

		_entity_outliner = EntityOutliner.new()
		_entity_outliner.name = "EntityOutliner"
		_entity_outliner_layer.add_child(_entity_outliner)
		# Anchor to right edge of viewport, stopping above the status bar.
		_entity_outliner.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		_entity_outliner.offset_left = -EntityOutliner.PANEL_WIDTH
		_entity_outliner.offset_bottom = -SessionStatusBar.BAR_HEIGHT
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
	# Urban Growth Stocking Stage C: disconnect POI emergence handler.
	if _poi_emergence_handler != null:
		_poi_emergence_handler.unregister()
		_poi_emergence_handler = null
	# Urban Growth Stocking Stage D: disconnect baseline NPC stocker.
	if _baseline_npc_stocker != null:
		_baseline_npc_stocker.unregister()
		_baseline_npc_stocker = null
	# Urban Growth Stocking Stage F: disconnect stronghold POI registrar.
	if _stronghold_poi_registrar != null:
		_stronghold_poi_registrar.unregister()
		_stronghold_poi_registrar = null
	if _wilderness_global_handlers != null:
		_wilderness_global_handlers.unregister_global(_handler_registry)
		_wilderness_global_handlers = null
	if _spell_handlers != null:
		_spell_handlers.unregister(_handler_registry)
		_spell_handlers = null
	if _commission_pipeline != null:
		_commission_pipeline.unregister(_handler_registry)
		_commission_pipeline = null
	if _siege_handlers != null:
		_siege_handlers.unregister(_handler_registry)
		_siege_handlers = null
	if _activity_executor != null:
		_activity_executor.unregister(_handler_registry)
		_activity_executor = null
	if _strenuous_accountant != null:
		_strenuous_accountant.unsubscribe()
		_strenuous_accountant = null
	if _follower_arrival_resolver != null:
		_follower_arrival_resolver.unsubscribe()
		_follower_arrival_resolver = null
	_activity_catalog = null
	_activity_handler_registry = null
	if _entity_outliner != null:
		_entity_outliner.visible = false
	_scheduler.clear()
	_handler_registry.clear()
	_scheduler_loop.pause()
	_party_data = null
	_campaign_id = ""
	_party_id = ""
	# Eyes of the Eagle V2: reset party visibility bonus so a new session
	# doesn't inherit the prior party's bonus.
	if _hex_controller != null:
		_hex_controller.set_party_visibility_bonus_hexes(0)
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
	if roll.modified_total > threshold:
		return {"triggered": false, "encounter_data": {}}

	var encounter_data: Dictionary = spawn_encounter_data(
		terrain, dungeon_wandering_table, roll.modified_total)
	if encounter_data.is_empty():
		return {"triggered": false, "encounter_data": {}}
	return {"triggered": true, "encounter_data": encounter_data}


## Generates encounter_data for a wilderness or dungeon encounter that has
## ALREADY been decided to trigger (the 1-in-6 throw passed elsewhere). Used
## by `do_encounter_check` after a positive throw, and by the deferred
## `wilderness_encounter` handler (gdd-realtime-scheduler.md §4.3.1) whose
## throw fires at camp_setup but whose spawn fires at the rolled hour-of-day.
##
## Returns the encounter_data Dictionary, or an empty Dictionary if no monster
## could be selected for the terrain (caller should treat this as a no-op).
##
## [param trigger_roll] is the 1d6 result that decided the trigger, stamped
## into encounter_data["roll"] for diagnostics. Pass 0 when there was no
## per-step throw (e.g. the camp throw rolled earlier and the value isn't
## meaningful here).
func spawn_encounter_data(terrain: HexTerrainData,
		dungeon_wandering_table: Array = [],
		trigger_roll: int = 0) -> Dictionary:
	# Pick a monster from the terrain's encounter table
	var monster_id := _pick_encounter_monster(terrain, dungeon_wandering_table)
	if monster_id.is_empty():
		# No monsters in catalog for this terrain — caller treats as no-op
		return {}

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
		"roll": trigger_roll,
	}
	EventBus.encounter_triggered.emit(encounter_data)
	return encounter_data


## Picks a random monster for an encounter based on terrain.
##
## Wilderness flow (terrain != null and no dungeon table):
##   1. Call EncounterTerrainResolver.resolve(terrain) — picks an encounter
##      column (handling civilization cascade, water tiles, subtype
##      overrides) and rolls a creature type from the RAW d8 table, with
##      any subtype creature-type tilt applied.
##   2. Filter the catalog by terrain_affinity (column) AND creature type.
##   3. Fall back to terrain-only if no monster matches both; fall back to
##      all monsters if no monster is tagged for this terrain.
##
## If [param dungeon_wandering_table] is non-empty, it takes precedence —
## used to scope dungeon wandering rolls to a curated per-dungeon list.
##
## Returns a monster_id from the catalog, or "" if none available.
func _pick_encounter_monster(terrain: HexTerrainData,
		dungeon_wandering_table: Array = []) -> String:
	if _monster_registry == null or _monster_registry.get_monster_count() == 0:
		return ""

	# Per-dungeon table overrides everything else.
	if not dungeon_wandering_table.is_empty():
		return _weighted_pick_from_table(dungeon_wandering_table)

	# No terrain context (dungeon without a wandering table) — pick uniformly
	# from the full catalog.
	if terrain == null:
		return _pick_uniform_from_all()

	# Wilderness encounter — resolver picks the RAW column + creature type.
	var resolved: Dictionary = EncounterTerrainResolver.resolve(terrain)
	var column: String = resolved.get("column", "")
	var creature_type: String = resolved.get("creature_type", "")

	if column.is_empty():
		return _pick_uniform_from_all()

	var by_terrain: Array[String] = _monster_registry.get_monsters_for_terrain(column)
	if by_terrain.is_empty():
		# No monster is tagged for this terrain column — fall back to all.
		return _pick_uniform_from_all()

	# Narrow by creature type. If the catalog has no monster matching both
	# the terrain column and the rolled creature type, relax to terrain-only
	# rather than emit nothing — RAW intent is "some encounter happens here."
	var filtered: Array[String] = []
	for mid in by_terrain:
		var m: Dictionary = _monster_registry.get_monster(mid)
		if EncounterTerrainResolver.monster_matches_creature_type(m, creature_type):
			filtered.append(mid)

	if filtered.is_empty():
		return by_terrain[randi() % by_terrain.size()]
	return filtered[randi() % filtered.size()]


func _pick_uniform_from_all() -> String:
	var all_ids := _monster_registry.get_all_monster_ids()
	if all_ids.is_empty():
		return ""
	return all_ids[randi() % all_ids.size()]


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
# Party visibility bonus refresh (Eyes of the Eagle V2 — 2026-06-03)
# ---------------------------------------------------------------------------

## EventBus.inventory_updated handler. Any character's inventory change can
## flip a `has_eyes_of_the_eagle` flag (equip / unequip / item added / item
## removed). Refresh the bonus. Cheap — single integer recompute + setter
## is idempotent for equal values.
func _on_inventory_updated_for_visibility(_character_id: String) -> void:
	_refresh_party_visibility_bonus()


## EventBus.active_party_changed handler. Switching active parties means a
## completely different roster — recompute from scratch.
func _on_active_party_changed_for_visibility(
		_previous_party_id: String, _new_party_id: String) -> void:
	_refresh_party_visibility_bonus()


## Timekeeping.round_advanced handler — drives the Ring of Regeneration
## consumer for active-party bearers. RAW: 1 hp per round, never above
## hp_max, stops while hp_current ≤ stops_at_or_below_hp (default 0).
## V1 supports multiple rounds_elapsed by multiplying the per-round amount
## (cheap for the simple +N hp pattern). No-op when no party loaded.
func _on_round_advanced_for_regeneration(rounds_elapsed: int) -> void:
	if _party_data == null or rounds_elapsed <= 0:
		return
	if _party_data.character_data == null:
		return
	for cd: CharacterData in _party_data.character_data:
		if cd == null or cd.flags == null:
			continue
		if not cd.flags.has_flag("has_ring_regeneration"):
			continue
		# Per-source scan — multiple rings would in principle stack, but
		# the inventory layer prevents wearing two of the same ring at
		# once. We sum hp_per_round across sources for forward-
		# compatibility (a future "ring + spell" combo would compose).
		var per_round_total: int = 0
		var stops_at: int = 0
		for entry in cd.flags.get_flag_source_entries("has_ring_regeneration"):
			var meta: Dictionary = entry.get("metadata", {})
			per_round_total += int(meta.get("hp_per_round", 0))
			# When multiple sources disagree on stop-threshold, use the
			# largest (most-restrictive) value — RAW intent is the ring
			# stops at its specific threshold.
			stops_at = maxi(stops_at, int(meta.get("stops_at_or_below_hp", 0)))
		if per_round_total <= 0:
			continue
		if cd.hp_current <= stops_at:
			continue
		if cd.hp_current >= cd.hp_max:
			continue
		var amount: int = per_round_total * rounds_elapsed
		var old_hp: int = cd.hp_current
		cd.hp_current = mini(cd.hp_current + amount, cd.hp_max)
		if cd.hp_current == old_hp:
			continue
		# Persist if the campaign DB is available; in unit-test contexts
		# the autoload may not be wired (the in-memory CharacterData
		# change is still observable).
		if CampaignRepository != null and CampaignRepository.db != null:
			CampaignRepository.update_character_hp(cd.id, cd.hp_current)
		EventBus.hp_changed.emit(cd.id, old_hp, cd.hp_current)


## Compute the party visibility bonus from the live party_data.character_data
## roster and push it to HexMapController. No-op when no party / map / hex-
## controller is available (e.g. main menu, before session load, headless
## tests without a session running).
##
## Called from:
##   * `load_session` after `_party_data.character_data` is populated.
##   * `_on_inventory_updated_for_visibility` (any inventory change).
##   * `_on_active_party_changed_for_visibility` (party switch).
##
## V1 scope: single-party visibility. Multi-party (split-party UI) would
## need a per-party HexMapController instance OR a per-party bonus override;
## V1 currently routes all visibility through the singleton controller.
func _refresh_party_visibility_bonus() -> void:
	if _hex_controller == null:
		return
	if _party_data == null:
		# No party loaded — reset to baseline so a previous session's
		# bonus doesn't leak into the next.
		_hex_controller.set_party_visibility_bonus_hexes(0)
		return
	var bonus: int = HexMapController.compute_party_visibility_bonus(
		_party_data.character_data)
	_hex_controller.set_party_visibility_bonus_hexes(bonus)


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
