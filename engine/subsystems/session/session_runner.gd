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
## Long-lived WildernessHandlers instance owning ALL wilderness event handlers
## (Option 2 — background-party resolution, 2026-06-12; previously only the
## cross-state day-tick lived here and travel/encounter/activity handlers were
## state-scoped, which silently destroyed background parties' events in other
## contexts). WildernessExploreState borrows this instance for its scheduling
## helpers via get_wilderness_handlers().
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
## Party selector tab bar (Option 1 party-context switching follow-up,
## 2026-06-12): top-left, one tab per party, visible only with 2+ parties.
## Clicking a tab focuses that party (full context switch via go_to_party).
var _party_selector_tabs: PartySelectorTabs = null
var _party_selector_layer: CanvasLayer = null

## State keys where the scheduler loop should tick.
const _SCHEDULER_STATES := ["wilderness", "dungeon", "settlement", "camp", "encounter", "downtime"]

# Order-lock removed 2026-06-12 (Jedidiah ruling): under the single shared
# timeline nothing needs locking — the lock's rationale belonged to the
# abandoned catch-up-time model. Orders are cancellable by issuing a new
# order: order surfaces cancel the party's pending travel/activity events
# (`cancel_all_for_owner`) before scheduling the replacement. Time already
# spent is spent (the world clock moved); a cancelled activity yields nothing.


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
	# Park-don't-consume wiring (2026-06-12): registering a handler re-injects
	# any events of that type parked while no handler existed.
	_handler_registry.set_scheduler(_scheduler)
	_scheduler_loop = SchedulerLoop.new()
	EventBus.clock_speed_requested.connect(_on_clock_speed_requested)
	# Eyes of the Eagle V2 (2026-06-03) — refresh the party visibility bonus
	# on the hexmap whenever an inventory change or party-membership change
	# could affect a member's `has_eyes_of_the_eagle` flag. Cheap (single
	# integer recompute + setter is idempotent for equal values, so no
	# spurious renderer refresh). Handlers no-op when no party is loaded.
	EventBus.inventory_updated.connect(_on_inventory_updated_for_visibility)
	EventBus.active_party_changed.connect(_on_active_party_changed_for_visibility)
	# Multi-party lifecycle (single-timeline rework, 2026-06-11): seed the
	# split-off party's daily ticks at split time; on merge, cancel the
	# dissolved party's queued events and re-point the session if the
	# primary was merged away.
	EventBus.party_split.connect(_on_party_split_for_scheduler)
	EventBus.party_merged.connect(_on_party_merged_for_scheduler)
	# Party-context switching (Option 1, 2026-06-12): every active-party
	# change is a full focus switch (re-point the watched party + transition
	# the UI to its persisted context); toast actions request focus via
	# party_focus_requested.
	EventBus.active_party_changed.connect(_on_active_party_changed_for_context)
	EventBus.party_focus_requested.connect(go_to_party)
	# Party selector tab bar refresh hooks (Option 1 follow-up). Connected
	# AFTER the context handler so the tabs render the post-switch state.
	EventBus.party_split.connect(_on_party_lifecycle_for_tabs)
	EventBus.party_merged.connect(_on_party_lifecycle_for_tabs)
	EventBus.party_member_joined.connect(_on_party_lifecycle_for_tabs)
	EventBus.party_member_left.connect(_on_party_lifecycle_for_tabs)
	EventBus.active_party_changed.connect(_on_active_party_changed_for_tabs)
	EventBus.session_state_transitioned.connect(_on_state_transition_for_party_tabs)
	# Ring of Regeneration round-tick consumer (2026-06-03). Per ACKS Core
	# p.215+ Jedidiah-supplied RAW 2026-06-02: "Regenerates 1 hp per round.
	# Will not regenerate if reduced to 0 hp or less." The handler scans
	# the active party for has_ring_regeneration bearers and increments
	# hp_current by hp_per_round × rounds_elapsed (clamped at hp_max,
	# gated on hp_current > stops_at_or_below_hp). No-op when no party
	# is loaded.
	Timekeeping.round_advanced.connect(_on_round_advanced_for_regeneration)
	# Cube of Frost Resistance turn-tick consumer (2026-06-03). Per ACKS
	# Core p.215+ V2 Jedidiah-supplied RAW: per-turn cold damage accumulator
	# resets at each turn boundary; collapsed-field cooldown reactivates
	# after 6 turns (= 1 hour). Cheap (one dict mutation per bearer per
	# turn). No-op when no party is loaded.
	Timekeeping.turn_advanced.connect(_on_turn_advanced_for_frost_cube)
	# Once-per-turn misc-magic refill (2026-06-03). RAW: Horn of Blasting
	# "may be blown once per turn." Single bulk UPDATE per turn boundary
	# resets uses_remaining=1 on any once-per-turn item with current
	# charges < 1 (V1: Horn of Blasting). Replaces the prior daily-reset
	# V1 simplification.
	Timekeeping.turn_advanced.connect(_on_turn_advanced_for_once_per_turn_recharge)
	# Once-per-day misc-magic refill (2026-06-03). RAW: Elemental
	# Commanders (Bowl/Brazier/Censer/Stone) summon + control "once per
	# day." Single bulk UPDATE per day boundary resets uses_remaining=1
	# on any once-per-day item with current charges < 1. Twin of the
	# once-per-turn refactor — same shape, different time signal.
	Timekeeping.day_changed.connect(_on_day_changed_for_once_per_day_recharge)
	# Persistence choke points (2026-06-12): flush clock + event queue together
	# at every scheduler pause and day boundary (save_session covers explicit
	# saves). Replaces Timekeeping's per-advance eager save; bounds crash loss
	# to the current running stretch. Handlers no-op when no campaign is loaded.
	EventBus.scheduler_paused.connect(_on_scheduler_paused_for_flush)
	Timekeeping.day_changed.connect(_on_day_changed_for_flush)

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

	# Re-entrancy guard (2026-06-12): enter() may itself transition —
	# SessionLoadState routes to wilderness/dungeon/settlement, and error paths
	# (e.g. dungeon enter failing) bail to wilderness. The nested call has
	# already run the full postamble for the REAL destination; running ours now
	# would clobber GameState.current_location_key with this frame's stale
	# state_key (the "drop-to-ground broken after loading into a dungeon" bug)
	# and emit the transition signals in inverted order.
	if _current_state_key != state_key:
		return

	# Update GameState.current_location_key for autoload consumers.
	# Only exploration states return real keys; overlay states return "unknown"
	# (preserving the parent exploration state's key); meta states get "none".
	if state_key in ["campaign_select", "party_creation", "session_load", "session_end"]:
		GameState.current_location_key = "none"
	elif state_key in ["wilderness", "dungeon", "settlement"]:
		GameState.current_location_key = _current_state.get_location_key_for_character("")
		# Persist the party's exploration context so the savegame loader can
		# restore it instead of always booting to wilderness. Sub-context states
		# (combat / camp / encounter) are NOT in this list, so they leave
		# current_location_type untouched (gdd-savegame-system.md §5.1).
		if not _party_id.is_empty():
			CampaignRepository.update_party_location_type(_party_id, state_key)

	_sync_game_state(state_key)
	# Focus-coupled clock: entering/leaving the dungeon layer (or a real
	# dungeon exit changing parties' location types) can flip the lock.
	_refresh_clock_lock()
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

## True if the session is currently resolving combat — the dedicated "combat"
## state, or in-place dungeon combat (DungeonExploreState.is_in_combat()). Used
## to block mid-combat saves (gdd-savegame-system.md §5.7).
func is_in_combat() -> bool:
	return _current_state_key == "combat" or (_current_state != null and _current_state.is_in_combat())

func get_scheduler() -> EventScheduler:
	return _scheduler

func get_handler_registry() -> EventHandlerRegistry:
	return _handler_registry

## The session-lifetime WildernessHandlers instance (all wilderness events are
## globally registered — Option 2, 2026-06-12). WildernessExploreState borrows
## it for scheduling helpers; null before load_session.
func get_wilderness_handlers() -> WildernessHandlers:
	return _wilderness_global_handlers

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
	_load_party_data_for_session(party_id)

	# 2.x. Eyes of the Eagle V2 (2026-06-03) — refresh the hexmap party
	# visibility bonus from the freshly-loaded roster. Bonus is pushed to
	# HexMapController.set_party_visibility_bonus_hexes; the controller's
	# setter auto-re-runs _update_visibility(party_hex) if a map is loaded,
	# so subsequent map loads pick up the right radius. Future inventory
	# changes and party switches refresh via EventBus subscriptions wired
	# in _ready.
	_refresh_party_visibility_bonus()

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

	# 7b-ii. Specialist payday (gdd-specialists.md §6.3): retained-specialist
	#     wages debit on every calendar month boundary, for every party in the
	#     campaign with active specialists. (Henchman payday remains unwired
	#     project-wide — flagged in the GDD §10; this listener is the natural
	#     future home for it.)
	if not Timekeeping.month_changed.is_connected(_on_specialist_payday):
		Timekeeping.month_changed.connect(_on_specialist_payday)

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
	DiseaseResolver.reconcile_cure_ticks_on_session_load(
		_scheduler, Timekeeping.get_calendar_day())

	# Batch E (2026-06-12): reseed siege tick events for in-progress sieges.
	# Ticks are seeded only when a siege starts and live in the scheduler
	# queue; a crash before a queue flush (or a save from before the flush
	# choke points existed) leaves a live siege with no tick chain — it would
	# stall forever. Idempotent per siege via get_events_for_owner.
	SiegeResolver.reconcile_ticks_on_session_load(_scheduler, campaign_id)

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

	# 8b. Party selector tabs (Option 1 follow-up): top-left tab bar for
	# focusing parties. Same CanvasLayer pattern as the entity outliner —
	# Control anchors need a viewport-sized parent rect. The widget hides
	# itself while fewer than 2 parties exist and joins the
	# "hud_party_selector_tabs" group (HudVisibilityController hides it while
	# the notebook is open).
	if _party_selector_tabs == null:
		_party_selector_layer = CanvasLayer.new()
		_party_selector_layer.name = "PartySelectorLayer"
		_party_selector_layer.layer = 79  # just below SessionStatusBar (layer 80)
		get_parent().add_child(_party_selector_layer)

		_party_selector_tabs = PartySelectorTabs.new()
		_party_selector_tabs.name = "PartySelectorTabs"
		_party_selector_layer.add_child(_party_selector_tabs)
		_party_selector_tabs.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_party_selector_tabs.offset_left = 8.0
		_party_selector_tabs.offset_top = 8.0
		_party_selector_tabs.party_selected.connect(_on_party_tab_selected)
		_party_selector_tabs.split_requested.connect(_on_party_tab_split_requested)
	_refresh_party_selector_tabs()

	# Party-context switching (Option 1): record the watched party for the
	# loader's next pick, and seed the focus-coupled clock lock (a save with
	# a suspended dungeon party loaded into wilderness starts locked).
	CampaignRepository.set_last_active_party(campaign_id, party_id)
	_refresh_clock_lock()

	session_loaded.emit(campaign_id)


## Saves all mutable session state to the database.
func save_session() -> void:
	if _campaign_id.is_empty():
		return

	# Saving during combat is disallowed (gdd-savegame-system.md §5.7): combat is
	# a turn-based sub-game with the scheduler globally paused, so there is no
	# clean mid-combat state to serialize. The pause-menu Save guards this too and
	# shows the player a message; this is the defensive backstop.
	if is_in_combat():
		push_warning("SessionRunner.save_session: ignored — cannot save during combat")
		return

	# Party state
	if _party_data != null:
		CampaignRepository.save_party_state(_party_data.to_state_dict())

	# Per-context live state: each primary exploration state flushes what it owns
	# (wilderness → hex fog/survey; dungeon → voxel cells + per-entity positions;
	# settlement → current POI). Replaces the old wilderness-only hex save so that
	# saving inside a dungeon/settlement no longer loses that context
	# (gdd-savegame-system.md §5.3).
	if _current_state != null:
		_current_state.flush_to_db(self)

	# Clock + active effects + scheduled events in ONE transaction (2026-06-12):
	# previously each row was its own implicit fsync'd transaction, and a crash
	# between a clear and its re-insert loop could lose the whole set. Only
	# single-statement repository helpers may run inside this block — callees
	# with their own BEGIN/COMMIT (like the per-context flush_to_db above)
	# would commit it prematurely.
	var own_txn: bool = CampaignRepository.db.query("BEGIN TRANSACTION")

	Timekeeping.flush()

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

	if own_txn:
		CampaignRepository.db.query("COMMIT")

	session_saved.emit(_campaign_id)
	EventBus.campaign_saved.emit(_campaign_id)


## Persistence choke point (2026-06-12): flush the world clock and the
## scheduled-event queue together, atomically, so the persisted clock can never
## outrun the persisted queue — a crash previously restored a current clock
## with a stale queue (lost arrivals, re-fired stale events, dead recurrence
## chains). Wired to every scheduler pause and every day boundary; save_session
## covers the explicit-save path. Cheap: one transaction, one clock upsert
## (skipped when clean), one delete + tens of inserts under WAL.
func flush_clock_and_queue() -> void:
	if _campaign_id.is_empty() or CampaignRepository.db == null:
		return
	# Guarded BEGIN: this runs from signal handlers, so an enclosing transaction
	# is possible — in that case the writes join it and ITS owner commits.
	var own_txn: bool = CampaignRepository.db.query("BEGIN TRANSACTION")
	Timekeeping.flush()
	if _scheduler != null:
		CampaignRepository.clear_scheduled_events(_campaign_id)
		for event_dict: Dictionary in _scheduler.to_dicts():
			CampaignRepository.save_scheduled_event(_campaign_id, event_dict)
	if own_txn:
		CampaignRepository.db.query("COMMIT")


func _on_scheduler_paused_for_flush(_reason: String) -> void:
	flush_clock_and_queue()


func _on_day_changed_for_flush(_day: int, _month: int, _year: int) -> void:
	flush_clock_and_queue()


## Loads [param party_id]'s full PartyData (roster, shared inventory, trained
## creatures, draft vehicles) into _party_data. Used by load_session and by
## the merge re-point handler (_on_party_merged_for_scheduler).
func _load_party_data_for_session(party_id: String) -> void:
	_party_data = CampaignRepository.load_party_data(party_id)
	if _party_data == null:
		return
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


## EventBus.party_split handler (single-timeline rework, 2026-06-11). Seeds the
## new party's wilderness day/noon ticks immediately so sustenance, foraging,
## and weather fire from the moment of the split — previously the detachment
## got no daily ticks until wilderness was next re-entered.
func _on_party_split_for_scheduler(_original_party_id: String, new_party_id: String) -> void:
	if _campaign_id.is_empty() or _scheduler == null or _wilderness_global_handlers == null:
		return
	_wilderness_global_handlers.schedule_day_tick(_scheduler, new_party_id)
	_wilderness_global_handlers.schedule_noon_tick(_scheduler, new_party_id)


## EventBus.party_merged handler (single-timeline rework, 2026-06-11).
## 1. Cancels queued events owned by the dissolved party — otherwise they fire
##    later, fail to resolve a PartyData, and silently no-op.
## 2. Merge-primary guard: if the watched party was merged away, re-points the
##    session at the survivor — previously this left every session pointer at
##    a deleted party.
## 3. If the watched party absorbed the dissolved party, reloads _party_data
##    so the live roster includes the merged-in members.
func _on_party_merged_for_scheduler(surviving_party_id: String, dissolved_party_id: String) -> void:
	if _campaign_id.is_empty():
		return
	if _scheduler != null:
		_scheduler.cancel_all_for_owner(dissolved_party_id)
	if dissolved_party_id == _party_id:
		_repoint_watched_party(surviving_party_id)
		if GameState.active_party_id == dissolved_party_id:
			GameState.set_active_party(surviving_party_id)
	elif surviving_party_id == _party_id:
		_load_party_data_for_session(_party_id)
		_refresh_party_visibility_bonus()


# ---------------------------------------------------------------------------
# Party-context switching (Option 1 — docs/handoff_party_context_switching.md,
# rulings closed 2026-06-12: active = watched = selected; focus-coupled clock)
# ---------------------------------------------------------------------------

## States from which the player may switch the watched party. Combat and
## overlay/meta states block switching (their UIs already prevent it; this is
## the engine-side guard). Camp is excluded: the camp UI is watched-party
## furniture — finish or break camp before switching.
const _SWITCHABLE_STATES := ["wilderness", "dungeon", "settlement"]

## Re-entrancy flag for reverting a blocked active-party change.
var _reverting_active_party: bool = false

## Re-points the session's watched-party trio (_party_id, GameState.party_id,
## _party_data) at [param party_id] and refreshes derived state. The watched
## party IS the session primary (active = watched = selected). Records the
## choice so the session loader reopens on the same party.
func _repoint_watched_party(party_id: String) -> void:
	_party_id = party_id
	GameState.party_id = party_id
	_load_party_data_for_session(party_id)
	_refresh_party_visibility_bonus()
	if not _campaign_id.is_empty():
		CampaignRepository.set_last_active_party(_campaign_id, party_id)


## Public entry point: focus [param party_id] — switch the watched party AND
## transition the UI to its context (hexmap for wilderness, dungeon layer for
## a suspended delve, settlement menu for a town visit). Wired to
## EventBus.party_focus_requested (toast actions) and driven indirectly by
## every GameState.set_active_party caller via active_party_changed.
func go_to_party(party_id: String) -> void:
	if party_id.is_empty() or _campaign_id.is_empty():
		return
	if GameState.active_party_id == party_id:
		# Already the active party (e.g. toast tapped twice) — still make sure
		# the context matches.
		_apply_party_focus(party_id)
	else:
		GameState.set_active_party(party_id)  # handler performs the focus


## EventBus.active_party_changed handler: every active-party switch is a full
## focus switch (active = watched = selected).
func _on_active_party_changed_for_context(_previous_party_id: String, new_party_id: String) -> void:
	if _reverting_active_party:
		return
	if _campaign_id.is_empty() or new_party_id.is_empty():
		return
	_apply_party_focus(new_party_id)


## Performs the focus switch: re-point the watched-party trio, then transition
## the UI to the party's persisted context. Mirrors the savegame loader's
## context-aware restore (session_load_state.gd) — a suspended dungeon party
## resumes via the same entrance/spawn_cell/restore_positions path a save
## made mid-dungeon uses.
func _apply_party_focus(party_id: String) -> void:
	# Blocked contexts: combat/camp/menu states, and dungeon IN-PLACE combat
	# (the dungeon state stays current and reports is_in_combat — same flag
	# that blocks mid-combat saves, gdd-savegame-system.md §5.7).
	var blocked: bool = _current_state_key not in _SWITCHABLE_STATES
	if not blocked and _current_state != null \
			and _current_state.has_method("is_in_combat") and _current_state.is_in_combat():
		blocked = true
	if blocked:
		# Revert the selection so the active = watched invariant holds, and
		# tell the player why.
		if GameState.active_party_id != _party_id and not _party_id.is_empty():
			_reverting_active_party = true
			GameState.set_active_party(_party_id)
			_reverting_active_party = false
			EventBus.notification_requested.emit({
				"type": "warning",
				"category": "system",
				"title": "Cannot Switch Parties",
				"body": "Finish what this party is doing first (%s)." % _current_state_key,
			})
		return

	if party_id != _party_id:
		_repoint_watched_party(party_id)
	if _party_data == null:
		return

	var target_key := "wilderness"
	var context: Dictionary = {}
	match _party_data.current_location_type:
		"dungeon":
			context = _build_dungeon_focus_context(_party_data)
			if not context.is_empty():
				target_key = "dungeon"
		"settlement":
			context = _build_settlement_focus_context(_party_data)
			if not context.is_empty():
				target_key = "settlement"

	if target_key == _current_state_key:
		# Same-context switch (wilderness→wilderness is the common case): no
		# transition — the states' own active_party_changed listeners handle
		# camera recenter and UI refresh.
		return

	transition_to_state(target_key, context)

	# Landing on the hexmap: center on the focused party. (The wilderness
	# state's own recenter listener was not yet connected when the
	# active-party signal fired.)
	if target_key == "wilderness" and _hex_renderer != null \
			and _hex_renderer.has_method("center_on_hex"):
		_hex_renderer.center_on_hex(Vector2i(
			_party_data.current_hex_q, _party_data.current_hex_r))


## Builds the dungeon enter() context for focusing a suspended dungeon party.
## Mirrors SessionLoadState._restore_into_dungeon — keep the two in sync.
## Returns {} when the dungeon cannot be resolved (caller falls back to
## wilderness, matching the loader's behavior).
func _build_dungeon_focus_context(pd: PartyData) -> Dictionary:
	if pd == null or pd.dungeon_id.is_empty():
		return {}
	var entrance: Dictionary = CampaignRepository.get_dungeon_entrance_for_dungeon_id(
		_campaign_id, pd.dungeon_id)
	if entrance.is_empty():
		push_warning("SessionRunner: cannot resolve dungeon '%s' for party focus; falling back to wilderness" % pd.dungeon_id)
		return {}
	return {
		"entrance": entrance,
		"spawn_cell": Vector2i(pd.dungeon_col, pd.dungeon_row),
		"restore_positions": CampaignRepository.load_dungeon_entity_positions(pd.id),
	}


## Builds the settlement enter() context for focusing a party inside a
## settlement. Mirrors SessionLoadState._restore_into_settlement — keep the
## two in sync. Returns {} when the settlement cannot be resolved.
func _build_settlement_focus_context(pd: PartyData) -> Dictionary:
	if pd == null or pd.settlement_id.is_empty():
		return {}
	var entrance: Dictionary = CampaignRepository.get_settlement_entrance(pd.settlement_id)
	if entrance.is_empty():
		push_warning("SessionRunner: cannot resolve settlement '%s' for party focus; falling back to wilderness" % pd.settlement_id)
		return {}
	return {
		"entrance": entrance,
		"entry_poi_id": pd.settlement_node_id,
	}


# ---------------------------------------------------------------------------
# Party selector tabs (Option 1 follow-up, 2026-06-12)
# ---------------------------------------------------------------------------

## Rebuilds the tab bar from the campaign's parties. The widget hides itself
## when fewer than 2 parties exist. Wired to party_split / party_merged /
## party_member_joined / party_member_left / active_party_changed /
## session_state_transitioned and called at session load.
func _refresh_party_selector_tabs() -> void:
	if _party_selector_tabs == null:
		return
	if _campaign_id.is_empty():
		_party_selector_tabs.update_parties([] as Array[Dictionary], "")
		return
	var parties: Array[Dictionary] = []
	for row: Dictionary in CampaignRepository.list_parties_for_campaign(_campaign_id):
		var pid: String = str(row.get("id", ""))
		if pid.is_empty():
			continue
		var name_v = row.get("name", "Party")
		var loc_v = row.get("current_location_type", "wilderness")
		parties.append({
			"id": pid,
			"name": str(name_v) if name_v != null else "Party",
			"member_count": CampaignRepository.list_party_characters(pid).size(),
			"activity": _party_tab_activity(str(loc_v) if loc_v != null else "wilderness"),
		})
	_party_selector_tabs.update_parties(parties, GameState.active_party_id)


## Maps a party's persisted location context to the widget's activity icon key.
func _party_tab_activity(location_type: String) -> String:
	match location_type:
		"settlement":
			return "in_settlement"
		_:
			return "exploring"


## Tab click → full focus switch (active = watched = selected). Routed through
## party_focus_requested so the tab bar shares one path with toast actions.
func _on_party_tab_selected(party_id: String) -> void:
	EventBus.party_focus_requested.emit(party_id)


## The split button: party splitting lives in the Notebook's Party tab (its
## dialog needs the formation grid context). Point the player there rather
## than duplicating the dialog here.
func _on_party_tab_split_requested() -> void:
	EventBus.notification_requested.emit({
		"type": "info",
		"category": "system",
		"title": "Split Party",
		"body": "Open the Notebook's Party tab to split the party.",
	})


## session_state_transitioned handler: disable tab switching in contexts the
## engine blocks anyway (combat, camp) so the UI tells the player up front,
## and refresh activity icons on context changes. SessionRunner's
## _apply_party_focus remains the authoritative guard.
func _on_state_transition_for_party_tabs(_old_key: String, new_key: String) -> void:
	if _party_selector_tabs == null:
		return
	match new_key:
		"combat":
			_party_selector_tabs.set_switching_disabled("Cannot switch parties during combat.")
		"camp":
			_party_selector_tabs.set_switching_disabled("Cannot switch parties while camping.")
		"wilderness", "dungeon", "settlement":
			_party_selector_tabs.set_switching_disabled("")
	_refresh_party_selector_tabs()


## Lifecycle refresh hooks (split/merge/membership). Distinct narrow handlers
## so signal arities match.
func _on_party_lifecycle_for_tabs(_a: String, _b: String) -> void:
	_refresh_party_selector_tabs()


func _on_active_party_changed_for_tabs(_previous_party_id: String, new_party_id: String) -> void:
	if _party_selector_tabs == null:
		return
	_party_selector_tabs.set_active(new_party_id)
	_refresh_party_selector_tabs()


# ---------------------------------------------------------------------------
# Focus-coupled clock (Option 1 ruling 2026-06-12, Jedidiah's "Option C"):
# while any party is inside a dungeon, the world clock advances ONLY while the
# dungeon layer has focus. Other layers may resolve modals and queue orders,
# but cannot resume the clock.
# ---------------------------------------------------------------------------

## Cached lock reason so clock_lock_changed only fires on actual changes.
var _clock_lock_reason_cache: String = ""

## Returns "" when the clock may run in the current context, else the
## human-readable reason it is locked.
func get_clock_lock_reason() -> String:
	if _campaign_id.is_empty():
		return ""
	if _current_state_key == "dungeon":
		return ""
	if CampaignRepository.any_party_in_dungeon(_campaign_id):
		return "Time advances in the dungeon. Switch to the delving party to run the clock."
	return ""


## Recomputes the lock and broadcasts clock_lock_changed on change. Called
## after every state transition and at session load/end.
func _refresh_clock_lock() -> void:
	var reason := get_clock_lock_reason()
	if reason != _clock_lock_reason_cache:
		_clock_lock_reason_cache = reason
		EventBus.clock_lock_changed.emit(reason)


## Specialist payday (gdd-specialists.md §6.3). Fires on every calendar
## month boundary while a session is loaded: processes retained-specialist
## wages for every party in the campaign that has active specialists.
## Employer (the purse the wages draw against, v1 of payroll attribution) =
## the party's first listed member.
func _on_specialist_payday(_new_month: int, _new_year: int) -> void:
	var campaign_id: String = get_campaign_id()
	if campaign_id.is_empty():
		return
	var manager := SpecialistHireManager.new(CampaignRepository, EventBus)
	for party_row: Dictionary in CampaignRepository.list_parties_for_campaign(campaign_id):
		var pid: String = str(party_row.get("id", ""))
		if pid.is_empty():
			continue
		if CampaignRepository.list_active_specialists(campaign_id, pid).is_empty():
			continue
		var employer_id: String = ""
		var members: Array = CampaignRepository.list_party_characters(pid)
		if not members.is_empty():
			employer_id = str(members[0].get("id", ""))
		manager.process_monthly_wages(pid, employer_id, Timekeeping.get_total_rounds())


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
	if Timekeeping.month_changed.is_connected(_on_specialist_payday):
		Timekeeping.month_changed.disconnect(_on_specialist_payday)
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
	if _party_selector_tabs != null:
		_party_selector_tabs.visible = false
	# Pause BEFORE clearing the scheduler: pause() triggers the
	# flush-clock-and-queue choke point, which must see the real queue (or
	# no-op if already paused) — pausing after clear() would persist an empty
	# queue over the rows save_session just wrote.
	_scheduler_loop.pause()
	_scheduler.clear()
	_handler_registry.clear()
	_party_data = null
	_campaign_id = ""
	_party_id = ""
	# Eyes of the Eagle V2: reset party visibility bonus so a new session
	# doesn't inherit the prior party's bonus.
	if _hex_controller != null:
		_hex_controller.set_party_visibility_bonus_hexes(0)
	# Focus-coupled clock: clear the lock for the menu / next session.
	if not _clock_lock_reason_cache.is_empty():
		_clock_lock_reason_cache = ""
		EventBus.clock_lock_changed.emit("")
	GameState.end_session()  # triggers Timekeeping reset, DiceSystem clear


## Saves the current campaign to a NEW named slot (whole-DB snapshot). Flushes
## the live (autosave) state first so the slot captures the current moment.
## Returns the slot id, or "" on failure / during combat. gdd-savegame-system.md §6.3.
func save_to_slot(label: String) -> String:
	if _campaign_id.is_empty():
		return ""
	if is_in_combat():
		push_warning("SessionRunner.save_to_slot: ignored — cannot save during combat")
		return ""
	save_session()  # flush live state so the slot is current
	return CampaignRepository.save_snapshot(_campaign_id, label, "manual", _current_location_label())


## Loads a named slot: restores its whole-DB state, then re-enters the session at
## the saved context via the context-aware loader. Works both mid-session (tears
## the current session down first) and from a fresh boot. Returns false on
## failure. gdd-savegame-system.md §6.4.
func load_slot(snapshot_id: String) -> bool:
	var meta := CampaignRepository.get_snapshot(snapshot_id)
	var slot_campaign := String(meta.get("campaign_id", ""))
	if slot_campaign.is_empty():
		push_error("SessionRunner.load_slot: unknown slot %s" % snapshot_id)
		return false
	if not _campaign_id.is_empty():
		end_session()  # saves current (harmless — about to be overwritten) + tears down
		# Exit the live exploration state BEFORE restoring (2026-06-12). It
		# normally exits inside the session_load transition below — i.e. AFTER
		# restore_snapshot — and exploration exit() handlers write per-context
		# DB state (dungeon fog/door cells), stomping the freshly restored save
		# with pre-restore memory. Exiting here lands those writes in the
		# pre-restore DB, where they are harmless duplicates of save_session.
		if _current_state != null:
			_current_state.exit(self)
			_current_state = null
			_current_state_key = ""
	if not CampaignRepository.restore_snapshot(snapshot_id):
		push_error("SessionRunner.load_slot: restore failed for %s" % snapshot_id)
		# The old session (if any) is already torn down — land somewhere real
		# instead of leaving a zombie (no campaign, dead scheduler, old scene).
		transition_to_state("campaign_select")
		return false
	transition_to_state("session_load", {"campaign_id": slot_campaign})
	return true


## Human-readable label for the party's current context, denormalized into the
## slot list (gdd-savegame-system.md §6.5).
func _current_location_label() -> String:
	match _current_state_key:
		"dungeon":
			return "Dungeon"
		"settlement":
			return "Settlement"
		"wilderness":
			return "Wilderness"
		"combat":
			return "Combat"
		"camp":
			return "Camp"
	return _current_state_key.capitalize()


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


## Timekeeping.turn_advanced handler — drives the Cube of Frost Resistance
## per-turn reset + cooldown reactivation. RAW: collapsed cube cannot be
## reactivated for 1 hour (= 6 turns at the project's 10 minutes/turn
## scale). The service handles the cooldown comparison internally;
## SessionRunner just iterates the party and dispatches.
##
## Tick on EVERY turn boundary regardless of whether the field is currently
## active — the per-turn accumulator needs the reset even when the field
## is collapsed (so the next turn's damage starts clean once the cube
## reactivates). Cheap: one dict mutation + one compare per bearer per turn.
func _on_turn_advanced_for_frost_cube(_turns_elapsed: int) -> void:
	if _party_data == null:
		return
	if _party_data.character_data == null:
		return
	for cd: CharacterData in _party_data.character_data:
		if cd == null or cd.flags == null:
			continue
		if not cd.flags.has_flag("has_cube_of_frost_resistance_field"):
			continue
		CubeOfFrostResistanceService.tick_turn(cd)


## Timekeeping.turn_advanced handler — refills once-per-turn misc-magic
## items per RAW (Horn of Blasting "may be blown once per turn"). Issues a
## single bulk UPDATE inside the service that resets uses_remaining=1 for
## any once-per-turn item with current charges < 1. Campaign-scoped via
## `_campaign_id`. No-op when no campaign is loaded.
##
## V1 once-per-turn items: Horn of Blasting only. Future items extend
## `OncePerTurnRechargeService.RECHARGEABLE_ITEM_KEYS` (which must stay
## in sync with `tools/extract_magic_item_catalog.py:ONCE_PER_PERIOD_MISC_MAGIC_KEYS`).
##
## Replaces the prior V1 deferral (Horn was stuck at one-shot until a
## "daily-reset subsystem" landed — too restrictive; RAW intent is once
## per 10-minute exploration turn).
func _on_turn_advanced_for_once_per_turn_recharge(_turns_elapsed: int) -> void:
	OncePerTurnRechargeService.recharge_for_campaign(_campaign_id)


## Timekeeping.day_changed handler — refills once-per-day misc-magic
## items at each midnight rollover. RAW: Elemental Commanders (Bowl /
## Brazier / Censer / Stone) summon + control "once per day." Issues a
## single bulk UPDATE that resets uses_remaining=1 for any once-per-day
## item with current charges < 1. Campaign-scoped via `_campaign_id`.
## No-op when no campaign is loaded.
##
## Twin of `_on_turn_advanced_for_once_per_turn_recharge` — same shape,
## different time signal. V1 once-per-day items: 4 Elemental Commanders.
## Future items extend `OncePerDayRechargeService.RECHARGEABLE_ITEM_KEYS`
## (which must stay in sync with
## `tools/extract_magic_item_catalog.py:ELEMENTAL_COMMANDER_KEYS`).
##
## Replaces the prior V1 deferral (the 4 Elemental Commanders were stuck
## one-shot until the daily-reset subsystem landed).
func _on_day_changed_for_once_per_day_recharge(
		_new_day: int, _new_month: int, _new_year: int) -> void:
	OncePerDayRechargeService.recharge_for_campaign(_campaign_id)


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
	# Focus-coupled clock (Option 1 ruling 2026-06-12): pausing is always
	# allowed; running the clock outside the dungeon layer is not while a
	# party is below.
	if speed != SchedulerLoop.SPEED_PAUSED:
		var lock_reason := get_clock_lock_reason()
		if not lock_reason.is_empty():
			EventBus.notification_requested.emit({
				"type": "warning",
				"category": "system",
				"title": "Clock Locked",
				"body": lock_reason,
			})
			return
	_scheduler_loop.set_speed(speed)


