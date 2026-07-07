class_name BattleRetreatSiegeRouter
extends RefCounted

## Phase F — Route 2: post-battle retreat into a stronghold (gdd-army-warfare.md §4.10.3).
##
## When a field battle's loser retreats INTO a friendly stronghold in the battle hex (RAW
## daw_axioms_pitching_battle.xml:564-571 — the defeated army may hole up and "the victorious
## army may then begin a siege"), the victor MAY besiege:
##   - Player victor → a decision-required prompt (Besiege / Encamp / March-on) surfaced via
##     EventBus.siege_decision_required + auto-pause; this router NEVER auto-besieges for a player.
##   - NPC victor → a deterministic heuristic (§4.10.3): besiege iff it retains live hostile intent
##     against the domain AND its supply covers >= 2 weeks; otherwise it encamps.
##
## FieldBattleResolver emits `battle_loser_retreated_into_stronghold` from the aftermath (which
## has no scheduler). SessionRunner registers this router with a scheduler provider, so the
## dispatched siege gets the live EventScheduler for its ticks. The decision logic itself is a
## pure static function (`on_retreat_into_stronghold`) so it is headless-testable.
##
## Public API:
##   register_listener(scheduler_provider: Callable) / unregister_listener()
##   on_retreat_into_stronghold(victor_army_id, stronghold_id, defeated_army_id, day, scheduler) -> Dictionary
##   resolve_player_decision(choice, victor_army_id, stronghold_id, defeated_army_id, day, scheduler) -> Dictionary

## §4.10.3 heuristic constant (PROJECT-DESIGNED, tunable): weeks of supply the NPC victor needs
## in the stockpile before it will commit to a siege rather than encamp.
const MIN_SUPPLY_WEEKS_TO_BESIEGE := 2

## §4.10.3 player-victor choices — the three post-victory orders the SessionRunner-owned modal
## offers. Kept here (with the dispatch) so ALL retreat→siege routing is in one headless-testable
## class alongside the NPC heuristic.
const CHOICE_BESIEGE := "besiege"
const CHOICE_ENCAMP := "encamp"
const CHOICE_MARCH_ON := "march_on"

static var _scheduler_provider: Callable = Callable()


# ---------------------------------------------------------------------------
# Listener (SessionRunner-owned, so the dispatch gets the live scheduler)
# ---------------------------------------------------------------------------

static func register_listener(scheduler_provider: Callable) -> void:
	_scheduler_provider = scheduler_provider
	if not EventBus.battle_loser_retreated_into_stronghold.is_connected(_on_retreat):
		EventBus.battle_loser_retreated_into_stronghold.connect(_on_retreat)


static func unregister_listener() -> void:
	if EventBus.battle_loser_retreated_into_stronghold.is_connected(_on_retreat):
		EventBus.battle_loser_retreated_into_stronghold.disconnect(_on_retreat)
	_scheduler_provider = Callable()


static func _on_retreat(victor_army_id: String, stronghold_id: String,
		defeated_army_id: String, _battle_id: String) -> void:
	var scheduler = _scheduler_provider.call() if _scheduler_provider.is_valid() else null
	on_retreat_into_stronghold(victor_army_id, stronghold_id, defeated_army_id,
		Timekeeping.get_calendar_day(), scheduler)


# ---------------------------------------------------------------------------
# Decision (pure logic — headless-testable)
# ---------------------------------------------------------------------------

static func on_retreat_into_stronghold(victor_army_id: String, stronghold_id: String,
		defeated_army_id: String, calendar_day: int, scheduler) -> Dictionary:
	if victor_army_id.is_empty() or stronghold_id.is_empty():
		return {"decision": "none"}
	# Player victor — never auto-besiege; surface the choice (auto-pause via SessionRunner).
	if ArmyMapPresence.is_player_owned_id(victor_army_id):
		if EventBus.has_signal("siege_decision_required"):
			EventBus.emit_signal("siege_decision_required", victor_army_id, stronghold_id, defeated_army_id)
		return {"decision": "player_prompt", "victor": victor_army_id, "stronghold_id": stronghold_id}
	# NPC victor — deterministic heuristic.
	if not _npc_should_besiege(victor_army_id, stronghold_id):
		return {"decision": "encamp", "victor": victor_army_id, "stronghold_id": stronghold_id}
	var siege: Dictionary = SiegeDispatcher.dispatch_new_siege(
		victor_army_id, stronghold_id, defeated_army_id, calendar_day, scheduler)
	return {
		"decision": "besiege", "victor": victor_army_id, "stronghold_id": stronghold_id,
		"siege_id": String(siege.get("siege_id", "")), "mode": String(siege.get("mode", "")),
	}


# ---------------------------------------------------------------------------
# Player-victor decision resolution (§4.10.3) — invoked by the SessionRunner-owned modal
# ---------------------------------------------------------------------------

## Route the player's post-victory choice. Sibling to on_retreat_into_stronghold's NPC heuristic:
## the modal is UI-only and emits `decided(choice)`; SessionRunner (which owns the scheduler) calls
## this. `calendar_day < 0` sources the day from Timekeeping; a null `scheduler` falls back to the
## registered `_scheduler_provider` so the modal never has to hold a scheduler.
##   besiege  → SiegeDispatcher.dispatch_new_siege (player-involvement routing stays centralised)
##   encamp   → hold the battle hex (the victor is already 'encamped' post-battle — idempotent)
##   march_on → decline the siege; the victor stays encamped and free to receive a march order
static func resolve_player_decision(choice: String, victor_army_id: String,
		stronghold_id: String, defeated_army_id: String,
		calendar_day: int = -1, scheduler = null) -> Dictionary:
	if victor_army_id.is_empty():
		return {"decision": "none", "error": "no_victor"}
	var day: int = calendar_day if calendar_day >= 0 else Timekeeping.get_calendar_day()
	var sched = scheduler
	if sched == null and _scheduler_provider.is_valid():
		sched = _scheduler_provider.call()
	match choice:
		CHOICE_BESIEGE:
			if stronghold_id.is_empty():
				return {"decision": "none", "error": "no_stronghold"}
			var siege: Dictionary = SiegeDispatcher.dispatch_new_siege(
				victor_army_id, stronghold_id, defeated_army_id, day, sched)
			return {
				"decision": CHOICE_BESIEGE, "victor": victor_army_id, "stronghold_id": stronghold_id,
				"siege_id": String(siege.get("siege_id", "")), "mode": String(siege.get("mode", "")),
			}
		CHOICE_ENCAMP, CHOICE_MARCH_ON:
			# Both decline the siege. The victor is already 'encamped' (FieldBattleResolver set it
			# on victory); this confirms it and clears any stray leg. In v1 the two choices share
			# the encamped end-state — March-on differs only in intent (the player then issues the
			# march from the map, which needs a destination the modal can't pick). See §4.10.3.
			_encamp_victor(victor_army_id, sched)
			return {"decision": choice, "victor": victor_army_id, "stronghold_id": stronghold_id}
		_:
			return {"decision": "none", "error": "unknown_choice"}


## Encamp the victor at the battle hex (idempotent — already 'encamped' post-battle). Cancels any
## stray in-flight travel leg first so an orphaned leg can't fire on the held army.
static func _encamp_victor(victor_army_id: String, scheduler) -> void:
	if scheduler != null:
		ArmyMarcher.new().cancel_march(victor_army_id, scheduler)
	ArmyRepository.update_army(victor_army_id, {"state": "encamped"})


## §4.10.3: besiege iff supply covers >= MIN_SUPPLY_WEEKS_TO_BESIEGE weeks AND the victor retains
## live hostile intent against the stronghold's domain. Otherwise encamp.
static func _npc_should_besiege(victor_army_id: String, stronghold_id: String) -> bool:
	var supply: Dictionary = ArmyRepository.get_supply_state(victor_army_id)
	var weekly: int = int(supply.get("weekly_supply_cost_cp", 0))
	var stock: int = int(supply.get("current_stockpile_cp", 0))
	# A garrison/levy with no weekly cost is unbounded in supply (weeks -> effectively infinite).
	var weeks: float = (float(stock) / float(weekly)) if weekly > 0 else 9999.0
	if weeks < float(MIN_SUPPLY_WEEKS_TO_BESIEGE):
		return false
	return _has_hostile_intent(victor_army_id, stronghold_id)


## Live hostile intent. A victor that just defeated the domain's field army and holds the ground
## while the defender holes up is hostile BY DEFAULT — it is proven hostile unless it is proven
## FRIENDLY (same or allied realm as the domain). So: (a) an active domain_threats row fielded by
## the victor → hostile; else (b) hostile unless the victor's realm is friendly to the domain's.
## A landless aggressor (empty apex — a challenger / free-company army) is never "friendly", so it
## keeps its hostile intent.
static func _has_hostile_intent(victor_army_id: String, stronghold_id: String) -> bool:
	var domain_id: String = _domain_for_stronghold(stronghold_id)
	if domain_id.is_empty():
		return true  # an ownerless stronghold's ground is there for the taking
	if CampaignRepository.db.query_with_bindings(
		"SELECT 1 FROM domain_threats WHERE domain_id = ? AND status = 'active' AND linked_army_id = ? LIMIT 1",
		[domain_id, victor_army_id]) and not CampaignRepository.db.query_result.is_empty():
		return true
	var victor: Dictionary = ArmyRepository.get_army(victor_army_id)
	var victor_char: String = String(victor.get("command_character_id", ""))
	if victor_char.is_empty():
		victor_char = String(victor.get("political_owner_id", ""))
	var v_apex: String = RealmGraph.apex_for_character(victor_char)
	var d_apex: String = RealmGraph.apex_for_domain(domain_id)
	# Proven friendly (both realms known, same/allied) → NOT hostile. Otherwise (different realms,
	# or a landless free actor) the victor keeps its hostile intent.
	if not v_apex.is_empty() and not d_apex.is_empty():
		return RealmGraph.classify_hostility_by_apex(v_apex, d_apex) == RealmGraph.RESULT_HOSTILE
	return true


static func _domain_for_stronghold(stronghold_id: String) -> String:
	if stronghold_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT domain_id FROM strongholds WHERE id = ? LIMIT 1", [stronghold_id]) \
			or CampaignRepository.db.query_result.is_empty():
		return ""
	var v: Variant = CampaignRepository.db.query_result[0].get("domain_id")
	return "" if v == null else String(v)
