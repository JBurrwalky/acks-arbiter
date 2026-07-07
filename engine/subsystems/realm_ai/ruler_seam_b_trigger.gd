class_name RulerSeamBTrigger
extends RefCounted

## Seam B trigger wiring — handoff-ruler-ai-build.md §10.3 (RESOLVED thresholds
## §10.5). Connects the three significance sites to RulerStrategyReassessor.reassess():
##
##   1. Attack on a ruler's stronghold  → EventBus.siege_started
##                                         (stronghold_id → domain → owner)
##   2. Vassal / domain seizure         → EventBus.domain_conquered
##                                         (the ruler who LOST the domain)
##   3. Domain morale collapse          → EventBus.domain_morale_changed
##                                         (new morale <= Turbulent = -2)
##
## Per-ruler cooldown: at most ONE reassess per ruler per game-month (§10.5). A
## game-month is 28 days (Timekeeping.DAYS_PER_MONTH); the cooldown bucket is
## floor(calendar_day / 28).
##
## reassess() is a designed NO-OP under the mock/unconfigured provider
## (returns {reassessed:false, reason:"llm_not_configured"}, zero awaits), so
## these triggers are INERT until a real provider is configured — that is
## expected and correct (the pipeline was caller-less-by-design until now).
## They are wired anyway so the moment a provider lands they fire.
##
## Fires reassess() fire-and-forget: reassess() is a coroutine (L-3), but the
## significance emitters are synchronous engine steps that must not block on a
## (possibly awaited) LLM call. The reassessment result reaches the scorer via
## RulerStrategyReassessor's one-turn pending slot, consumed on the ruler's next
## monthly turn — the triggers never await it.

const TURBULENT_MORALE := -2   # gdd-ruler-ai.md §7.3 / DaW domain-morale bands.

## {ruler_npc_id: last_trigger_month_bucket}. Session-local by design — a lost
## cooldown just permits an extra (still no-op-under-mock) reassess.
static var _last_trigger_month: Dictionary = {}

## Guard so connect_signals() is idempotent across re-inits (test re-runs).
static var _connected: bool = false


## Wire the three significance sites. Called once from GameLog._ready() (the
## same autoload that hosts the Seam-A caller), so a single init point owns both
## ruler-AI → log seams. Idempotent.
static func connect_signals() -> void:
	if _connected:
		return
	_connected = true
	EventBus.siege_started.connect(_on_siege_started)
	EventBus.domain_conquered.connect(_on_domain_conquered)
	EventBus.domain_morale_changed.connect(_on_domain_morale_changed)


## Test/teardown hook — reset the cooldown ledger.
static func clear_cooldowns() -> void:
	_last_trigger_month.clear()


# ---------------------------------------------------------------------------
# Significance-site handlers
# ---------------------------------------------------------------------------

## Site 1 — attack on a ruler's stronghold (§10.5). Resolves the besieged
## stronghold's domain, then that domain's ruler.
static func _on_siege_started(_siege_id: String, stronghold_id: String,
		_besieging_army_id: String) -> void:
	if not LLMManager.is_configured() or stronghold_id.is_empty():
		return   # inert under the mock (reassess is a no-op)
	var stronghold: Dictionary = CampaignRepository.get_stronghold(stronghold_id)
	var domain_id: String = String(stronghold.get("domain_id", ""))
	if domain_id.is_empty():
		return
	var ruler_id: String = _ruler_for_domain(domain_id)
	dispatch(ruler_id, "stronghold_attacked", {
		"domain_id": domain_id, "stronghold_id": stronghold_id})


## Site 2 — vassal / domain seizure (§10.5). The ruler whose situation changed
## is the one who LOST the domain. domain_conquered fires AFTER the domain's
## hexes/state are updated, but owner_character_id on the domain row still names
## the prior owner at emit time (lifecycle_handler records the new owner into
## the departure log, not onto the domain row).
static func _on_domain_conquered(domain_id: String, _outcome: String,
		_new_owner_id: String) -> void:
	if not LLMManager.is_configured() or domain_id.is_empty():
		return   # inert under the mock (reassess is a no-op)
	var ruler_id: String = _ruler_for_domain(domain_id)
	dispatch(ruler_id, "vassal_seized", {"domain_id": domain_id})


## Site 3 — domain morale collapse (§10.5): new morale at or below Turbulent
## (-2). Fires only on the downward crossing (the signal only emits on change).
static func _on_domain_morale_changed(domain_id: String, _old_morale: int,
		new_morale: int) -> void:
	if new_morale > TURBULENT_MORALE:
		return
	if not LLMManager.is_configured() or domain_id.is_empty():
		return   # inert under the mock (reassess is a no-op)
	var ruler_id: String = _ruler_for_domain(domain_id)
	dispatch(ruler_id, "morale_collapse", {
		"domain_id": domain_id, "morale": new_morale})


# ---------------------------------------------------------------------------
# Dispatch + cooldown
# ---------------------------------------------------------------------------

## Fire reassess() for [param ruler_npc_id] under the 1-game-month cooldown.
## No-ops for an empty ruler id or a ruler already reassessed this game-month.
## reassess() is fired-and-forgotten (it is a coroutine; the trigger site must
## not block). Returns true if a reassess was dispatched (cooldown stamped).
static func dispatch(ruler_npc_id: String, trigger: String,
		situation: Dictionary = {}) -> bool:
	if ruler_npc_id.is_empty() or trigger.is_empty():
		return false
	# Inert until a provider is configured (reassess() is a designed no-op under
	# the mock). Gating here keeps the per-ruler cooldown ledger from being
	# polluted by no-op reassessments during normal mock-mode play/tests — the
	# cooldown is meant to throttle REAL reassess calls.
	if not LLMManager.is_configured():
		return false
	var month_bucket: int = _current_month_bucket()
	if _last_trigger_month.has(ruler_npc_id) \
			and int(_last_trigger_month[ruler_npc_id]) == month_bucket:
		return false   # already reassessed this game-month
	_last_trigger_month[ruler_npc_id] = month_bucket
	# Fire-and-forget the coroutine. Routing through a Callable (rather than a
	# direct RulerStrategyReassessor.reassess(...) call) keeps the static analyzer
	# from demanding an `await` here — we deliberately do NOT await: the emitter is
	# a synchronous engine step, and the reassessment nudge lands via the one-turn
	# pending slot RulerAI._take_turn consumes, not via this call's return value.
	Callable(RulerStrategyReassessor, "reassess").call(ruler_npc_id, trigger, situation)
	return true


static func _current_month_bucket() -> int:
	# Absolute game-month index: floor(serial_day / days_per_month). Deterministic,
	# no wall-clock.
	return Timekeeping.get_calendar_day() / Timekeeping.DAYS_PER_MONTH


## Resolve a domain's NPC ruler (owner_character_id). Returns "" for a
## player/henchman-owned or ownerless domain, so dispatch() no-ops there — Seam
## B only reassesses NPC rulers. Uses a QUIET direct query (not get_domain,
## which push_errors on not-found) because these handlers are connected at
## autoload init and see EVERY domain-signal emission across the game/suite,
## including ones for domains this trigger has no stake in.
static func _ruler_for_domain(domain_id: String) -> String:
	if domain_id.is_empty() or CampaignRepository.db == null:
		return ""
	if not CampaignRepository.db.query_with_bindings(
			"SELECT owner_character_id FROM domains WHERE id = ?", [domain_id]) \
			or CampaignRepository.db.query_result.is_empty():
		return ""
	var owner: Variant = CampaignRepository.db.query_result[0].get("owner_character_id")
	return String(owner) if owner != null else ""
