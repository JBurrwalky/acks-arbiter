class_name DomainHandlers
extends RefCounted

## Event handlers for domain monthly resolution.
##
## Registered globally when a campaign with active domains is loaded.
## The domain_monthly_tick fires on the 1st of each calendar month and
## resolves revenue, expenses, morale, population growth, construction
## progress, and domain encounters per ACKS rules.
##
## Event types handled:
##   "domain_monthly_tick"  — monthly domain cycle resolution


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

var _runner = null  # SessionRunner
var _campaign_id: String = ""

# ---------------------------------------------------------------------------
# D-12 Phase B — per-tick caches
#
# The monthly tick resolves a CHARACTER'S DOMAIN, not a `domains` row. Every
# cache here is keyed by `_owner_key` (the owner's character id, or `#<domain
# id>` for an ownerless seat) and is rebuilt from scratch at the top of each
# tick by `_reset_month_caches`.
#
# WHY THEY MUST BE BUILT BEFORE THE FIRST WRITE. `PersonalDomain.for_character`
# re-reads the `domains` table, while `_save_domain` UPDATEs each parcel as the
# tick walks it. A union computed lazily during resolution would therefore see
# some of the character's parcels carrying LAST month's morale/families/revenue
# and some carrying this month's — a different answer per parcel for a quantity
# that is supposed to be one number. Pass 0 builds every union up front, before
# anything is written.
# ---------------------------------------------------------------------------

## owner key -> PersonalDomain union (the D-12 aggregate).
var _union_by_owner: Dictionary = {}
## owner key -> Array[Dictionary] of this tick's parcel rows, in `domains` order.
var _parcels_by_owner: Dictionary = {}
## domain id -> that parcel's row, for seat lookups.
var _parcel_rows: Dictionary = {}
## domain id -> `_build_month_context` output (pass 1).
var _context_by_domain: Dictionary = {}
## owner key -> Σ THIS MONTH's revenue across his parcels. The one quantity that
## forces the two-pass shape: RAW's personal-authority band cross-references the
## ruler's level against his domain's income, which does not exist until every
## parcel's revenue has been computed.
var _revenue_by_owner: Dictionary = {}
## owner key -> the single resolved morale bundle, mirrored to every parcel.
var _morale_by_owner: Dictionary = {}


func _init(runner) -> void:
	_runner = runner
	_campaign_id = runner.get_campaign_id()


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(registry: EventHandlerRegistry) -> void:
	registry.register("domain_monthly_tick", _handle_monthly_tick)
	# Phase 11B: bridge Phase 9A siege outcomes + Phase 1 stronghold-destroyed
	# signals into LifecycleHandler. The siege resolver / stronghold subsystem
	# already emit; we translate.
	if not EventBus.siege_concluded.is_connected(_on_siege_concluded):
		EventBus.siege_concluded.connect(_on_siege_concluded)
	if not EventBus.stronghold_destroyed.is_connected(_on_stronghold_destroyed):
		EventBus.stronghold_destroyed.connect(_on_stronghold_destroyed)
	# Phase 11C: bridge character_died into RulerDeathHandler. Owns the
	# "find domains owned by deceased + put each in succession_pending"
	# sweep.
	if not EventBus.character_died.is_connected(_on_character_died):
		EventBus.character_died.connect(_on_character_died)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister("domain_monthly_tick")
	if EventBus.siege_concluded.is_connected(_on_siege_concluded):
		EventBus.siege_concluded.disconnect(_on_siege_concluded)
	if EventBus.stronghold_destroyed.is_connected(_on_stronghold_destroyed):
		EventBus.stronghold_destroyed.disconnect(_on_stronghold_destroyed)
	if EventBus.character_died.is_connected(_on_character_died):
		EventBus.character_died.disconnect(_on_character_died)


# ---------------------------------------------------------------------------
# Scheduling helpers
# ---------------------------------------------------------------------------

## Schedule the first domain_monthly_tick at the start of the next month.
## Should be called once during session load if the campaign has domains.
func seed_monthly_tick(scheduler: EventScheduler, _party_id: String) -> void:
	var fire_time: int = _rounds_until_next_month()
	if fire_time <= 0:
		# Already at the start of a month — schedule for next month.
		fire_time = Timekeeping.DAYS_PER_MONTH * Timekeeping.ROUNDS_PER_DAY
	# Use absolute time (current + delta).
	var current_time: int = Timekeeping.get_total_rounds()
	scheduler.schedule_at(
		current_time + fire_time,
		"domain_monthly_tick",
		"domain_global",  # Not owned by a specific party — world-level event.
		{},
		ScheduledEvent.PRIORITY_ENVIRONMENTAL,
	)


# ---------------------------------------------------------------------------
# Event handler
# ---------------------------------------------------------------------------

## Resolve the monthly cycle: commerce-side drivers always fire (Phase 10B.2
## Wave 5); domain-specific resolution runs only if the campaign has domains.
## Always reschedules for next month — even domain-less campaigns need ongoing
## commerce ticks (ship operating costs, merchant pool refresh, customs roll,
## market price drift).
func _handle_monthly_tick(event: ScheduledEvent) -> Dictionary:
	var date: Dictionary = Timekeeping.get_date()
	var month_name := "Month %d, Year %d" % [date.get("month", 1), date.get("year", 1)]
	var calendar_day: int = _calendar_day_from_date(date)
	var current_year: int = int(date.get("year", 1))

	# Phase 10B.2 Wave 5: commerce monthly tick fires every month regardless
	# of domain presence — closes [NEEDS-MONTHLY-TICK-WIRING] from Wave 1.
	var commerce_rng: RandomNumberGenerator = CommerceMonthlyResolver.seeded_monthly_rng(
		_campaign_id, calendar_day)
	var commerce_results: Dictionary = CommerceMonthlyResolver.process_for_campaign(
		_campaign_id, calendar_day, current_year, commerce_rng)

	# Thief→Syndicate refactor: syndicate bosses own no domain, so the
	# domain-only resolution below never reaches them. Run the monthly syndicate
	# fast-path (net L1-8 income + L9+ wage upkeep, both on the boss's PERSONAL
	# wallet) for EVERY syndicate in the campaign, regardless of domain presence.
	var syndicate_results: Array = NpcSyndicateMonthlyResolver.process_campaign_month(_campaign_id)

	# Venturer→Guildhouse refactor: venturers own no domain either — process every
	# guildhouse's monopoly revenue + apprentice wage upkeep (on the venturer's
	# personal wallet), regardless of domain presence.
	var venture_results: Array = VentureMonthlyResolver.process_campaign_month(_campaign_id)

	# --- Quest-Rumor Q-3: rumor decay pass ---------------------------------
	# §10.1 order step (2): rumor decay + invalidation runs on the monthly tick
	# AFTER world-change resolution and BEFORE the board refresh. Batch style,
	# no auto_pause, no LLM (the NpcSyndicateMonthlyResolver precedent). Runs
	# EVERY month regardless of domain presence — rumors exist without domains,
	# so this is placed ahead of the domains.is_empty() early-return below.
	# QuestSeeder.regenerate_pass (§6.4 new/expiring quests) is a later phase;
	# the quest-expiry sweep (QuestRegistry.expire_due_quests, Q-4) is wired by
	# the seeder-regeneration phase alongside re-minting.
	var rumor_registry := RumorRegistry.new(CampaignRepository, _campaign_id)
	var rumors_decayed: int = rumor_registry.decay_pass(_campaign_id, calendar_day)

	# Always reschedule for next month — commerce alone is reason enough to
	# keep ticking.
	var next_month_rounds: int = Timekeeping.DAYS_PER_MONTH * Timekeeping.ROUNDS_PER_DAY
	var next_events := [{
		"fire_time": event.fire_time + next_month_rounds,
		"event_type": "domain_monthly_tick",
		"owner_id": "domain_global",
		"data": {},
		"priority": ScheduledEvent.PRIORITY_ENVIRONMENTAL,
	}]

	# Domain-specific resolution (only when domains exist).
	var domains: Array = CampaignRepository.list_campaign_domains(_campaign_id)
	if domains.is_empty():
		# Commerce-only tick: no monthly report modal, no auto-pause; just keep
		# the scheduler advancing so the next month fires.
		return {
			"next_events": next_events,
			"commerce_results": commerce_results,
			"syndicate_results": syndicate_results,
			"venture_results": venture_results,
			"rumors_decayed": rumors_decayed,  # Quest-Rumor Q-3
		}

	# Ruler AI Phase 2 (gdd-ruler-ai.md §3.2/§3.3/§8.4) [NEEDS-OPUS-REVIEW —
	# the planner/stabilizer integration + the auto_pause gate below]:
	# classify each domain before resolution. PC-owned domains resolve exactly
	# as before; ACTIVE-set NPC rulers get full planner turns AFTER the loop;
	# every other non-player domain (backdrop NPC rulers, ownerless abstract
	# domains) gets the cheap §8.4 auto-stabilize pass on its morale roll so
	# off-camera realms hold steady instead of spiraling.
	var pc_ids: Dictionary = _player_character_ids()
	# Ruler AI Phase 3: Regional-LOD activation (gdd-ruler-ai.md §8) replaces
	# the Phase-2 provisional set — sync() also emits the promote/demote
	# signals and lazily builds dispositions for newly-promoted rulers.
	# Passing calendar_day enables the demotion grace (gdd-ruler-ai Phase 4):
	# a ruler the play window moved away from keeps planning ~1 month
	# before demoting.
	var lod_scheduler = _runner.get_scheduler() \
		if _runner != null and _runner.has_method("get_scheduler") else null
	# Regional-LOD conflict hook (gdd-ruler-ai.md §8.1-8.2, handoff-army-warfare-seams.md §3):
	# NPC rulers party to a live player-involved battle/siege join the active set regardless
	# of map distance. The full-tier gate inside sync drops any named-tier opponent
	# (bandit captain / NPC challenger), so this only ever promotes real full-tier rulers.
	var active_ruler_ids: Array = RulerLodManager.sync(
		_campaign_id, lod_scheduler,
		ConflictParticipants.active_ruler_ids(_campaign_id), calendar_day).get("active", [])
	var has_player_domain := false

	# -----------------------------------------------------------------------
	# D-12 Phase B — THREE PASSES OVER THE MONTH.
	#
	# RAW does not permit a character to hold multiple domains: any land he
	# personally rules is *his domain*, one record. The `domains` rows survive as
	# PARCELS (identity + history), so the tick still walks rows — but every
	# RAW-relevant quantity is answered over the union of a character's parcels.
	#
	# Pass 0  group the resolvable parcels by owner and build each owner's
	#         PersonalDomain union BEFORE anything is written (see the cache
	#         block at the top of this file for why the ordering is load-bearing).
	# Pass 1  per-parcel context + revenue. Only revenue needs THIS month's
	#         numbers, and personal authority keys on the character's TOTAL, so
	#         every parcel's revenue must exist before any parcel's morale rolls.
	# Pass 2  resolve. Morale is rolled ONCE per character and mirrored to every
	#         parcel; growth, settlements, encounters and persistence stay
	#         per-parcel, which is where that state actually lives.
	# -----------------------------------------------------------------------
	_reset_month_caches()
	var resolvable: Array = []
	for domain_data: Dictionary in domains:
		# Phase 11B: skip terminal-state domains entirely. abandoned /
		# lost_to_foreign rows are preserved for the audit history but no
		# longer run revenue / expense / morale / growth resolution.
		var lifecycle_state: String = String(domain_data.get(
			"lifecycle_state", LifecycleHandler.STATE_ACTIVE))
		if lifecycle_state == LifecycleHandler.STATE_ABANDONED \
			or lifecycle_state == LifecycleHandler.STATE_SALTED_TO_RUIN:
			continue
		resolvable.append(domain_data)
		var owner: String = _str_field(domain_data, "owner_character_id")
		has_player_domain = has_player_domain or (
			not owner.is_empty() and pc_ids.has(owner))
		var key: String = _owner_key(domain_data)
		if not _union_by_owner.has(key):
			# The union EXCLUDES terminal parcels exactly as the filter above
			# does, so the two lists agree about what the character holds.
			_union_by_owner[key] = PersonalDomain.for_domain(domain_data)
			_parcels_by_owner[key] = []
		(_parcels_by_owner[key] as Array).append(domain_data)
		_parcel_rows[String(domain_data.get("id", ""))] = domain_data

	for domain_data: Dictionary in resolvable:
		_month_context_for(domain_data, calendar_day)

	var domain_results: Array = []
	for domain_data: Dictionary in resolvable:
		var owner_id: String = _str_field(domain_data, "owner_character_id")
		var is_player_domain: bool = not owner_id.is_empty() and pc_ids.has(owner_id)
		var resolve_opts: Dictionary = {}
		if not is_player_domain and not active_ruler_ids.has(owner_id):
			resolve_opts = RulerBackdropStabilizer.resolution_options()
		var result := _resolve_domain_month(domain_data, calendar_day, resolve_opts)
		# R-7a: domain income becomes character XP. Runs BEFORE _save_domain so the
		# earned figure and the double-award guard land in that method's single
		# monthly UPDATE — the record and the guard commit together or not at all.
		# STILL PER PARCEL: awarding once per CHARACTER, and dropping the XP from
		# vassal-managed land, is R-7b (D-12 Phase F).
		result["domain_xp_award"] = DomainXpResolver.resolve(
			domain_data, result, calendar_day)
		domain_results.append(result)
		_save_domain(domain_data, result, calendar_day)
		_emit_signals(domain_data, result)
		# Phase 11A: chronicle classification + morale-tier transitions to the
		# departure log. Conquest / abandonment / ruler death are written by the
		# lifecycle handler in 11B/C, not here.
		DepartureLogRecorder.record_monthly_transitions(
			_campaign_id, domain_data, result, calendar_day)
		# Phase 11B: check ruined-stronghold grace expiry. Fires automatic
		# abandonment if the grace day has passed without rebuild.
		LifecycleHandler.tick_lifecycle_state(domain_data, calendar_day)
		# Phase 11C: check succession-pending grace expiry. Resolves with
		# the designated heir if any, or routes to abandonment / overlord-
		# revert if not.
		RulerDeathHandler.tick_succession_grace(domain_data, calendar_day)

	# R-1: Favors & Duties, once per RULER, gated on the same LOD predicate the loop
	# above used. Placed HERE — after the last `_save_domain` absolute treasury write
	# and before RulerAI — so gift/loan transfers survive the tick and the planner
	# sees this month's obligations. See _resolve_favors_and_duties_for_rulers.
	var favors_duties_reports: Array = _resolve_favors_and_duties_for_rulers(
		domains, pc_ids, active_ruler_ids, calendar_day)

	# Faction FF-2.2 (gdd-faction-framework.md §6.6/§11.1): organization turns batch
	# AFTER the syndicate/venture slots (so passthrough treasuries are already
	# resolved) and HERE, before RulerAI. Gated to ACTIVE-LOD settlements — those of
	# player domains + active-LOD NPC-ruler domains (§11.2, inherits ruler-AI LOD).
	# Batch, no auto_pause; Seam-A narration fires via GameLog on faction_action_taken.
	var faction_active_settlements: Array = []
	for fdom: Dictionary in domains:
		var fowner_v: Variant = fdom.get("owner_character_id")
		var fowner: String = String(fowner_v) if fowner_v != null else ""
		var f_active: bool = (not fowner.is_empty() and pc_ids.has(fowner)) \
			or active_ruler_ids.has(fowner)
		if not f_active:
			continue
		for st in CampaignRepository.list_settlements_for_domain(String(fdom.get("id", ""))):
			faction_active_settlements.append(String((st as Dictionary).get("id", "")))
	var faction_reports: Array = FactionAI.process_campaign_month(
		_campaign_id, calendar_day, faction_active_settlements)
	# Q-6: poll faction_goal quest completion (batch, idempotent — fires each
	# satisfied goal quest once).
	var faction_goal_watcher := QuestCompletionWatcher.new(
		QuestRegistry.new(CampaignRepository, _campaign_id), CampaignRepository, _campaign_id)
	var faction_goals_completed: int = faction_goal_watcher.poll_faction_goals(calendar_day)

	# Ruler AI Phase 2 (§3.2): active-set NPC rulers take their deterministic
	# monthly turns AFTER the economic resolution, with the post-resolution
	# result dicts in hand for threat context. Batch, no UI interrupt, no LLM;
	# handler mutations persist through the handlers' own repository writes.
	# Phase D: thread the runner's EventScheduler so call_to_arms tranche events + withstand_siege
	# march cancellations actually schedule (null in headless tests — the state rows still persist).
	var ruler_scheduler = _runner.get_scheduler() \
		if _runner != null and _runner.has_method("get_scheduler") else null
	var ruler_reports: Array = RulerAI.process_campaign_month(
		_campaign_id, calendar_day, active_ruler_ids, domain_results, ruler_scheduler)

	# Faction Framework FF-1.3 (gdd-faction-framework.md §5.6 final ¶): realm-
	# relations QUIET-DECAY maintenance — a batch, no auto_pause, no LLM (the
	# NpcSyndicateMonthlyResolver pattern). Runs AFTER RulerAI's batch and BEFORE
	# threat escalation. Event-driven drift (conquest/revolt/vagary/pillage) fires
	# at emission time via RealmRelationsDrift's EventBus listeners; this slot only
	# ages quiet pairs one band toward their structural default.
	RealmRelationsDrift.process_campaign_month(_campaign_id, calendar_day)

	# Phase F (gdd-army-warfare.md §4.10.2): NPC challenger escalation runs AFTER RulerAI, only
	# for active-LOD NPC domains — fields unfielded challengers, routes the §7.3 accept/refuse,
	# and dispatches a siege/battle (accept) or stamps the RAW -4 pillage penalty (refuse). The
	# ruler-planner never initiates a siege (§4.10.1); this acts on threat artifacts.
	ThreatEscalationDriver.process_campaign_month(
		_campaign_id, calendar_day, active_ruler_ids, ruler_scheduler)

	# Minimal frontier-raid escalation (handoff §5 step 4; Jedidiah 2026-07-06): an aggressive
	# active-LOD NPC ruler bordering a PLAYER domain fields a raider war-band that loot-marches the
	# frontier hex — the in-play trigger for the hostile_extraction "resist or concede" surface.
	# Like ThreatEscalationDriver this is a driver over disposition+geography, NOT a ruler-planner
	# action, so the ruler-AI "defense-only" invariant (§4.10.1) holds.
	NpcRaidDriver.process_campaign_month(
		_campaign_id, calendar_day, active_ruler_ids, ruler_scheduler)

	# gdd-ruler-ai.md §3.2: no auto_pause for NPC rulers — the monthly-report
	# modal pauses the clock only when the PLAYER owns a domain in the
	# campaign. [NEEDS-OPUS-REVIEW: this changes the previous behavior of
	# pausing whenever ANY domain exists; NPC-only campaigns now tick through.]
	return {
		"auto_pause": has_player_domain,
		"pause_reason": ("Domain monthly report — %s" % month_name) if has_player_domain else "",
		"next_events": next_events,
		"presentation": {
			"type": "domain_monthly_report",
			"month": month_name,
			"domain_results": domain_results,
		},
		"commerce_results": commerce_results,
		"syndicate_results": syndicate_results,
		"venture_results": venture_results,
		"ruler_reports": ruler_reports,
		"favors_duties_reports": favors_duties_reports,  # R-1: per-RULER, not per-domain
		"faction_reports": faction_reports,  # Faction FF-2.2 org month
		"faction_goals_completed": faction_goals_completed,  # Q-6
		"rumors_decayed": rumors_decayed,  # Quest-Rumor Q-3
	}


## PLAYER-SIDE character ids as a lookup set ({id: true}): every PC, plus
## every henchman employed by a PC — a henchman heir who inherits the player's
## domain (RulerDeathHandler heir_kind='henchman') keeps the domain player-side
## (the monthly report still pauses; the NPC planner never touches it).
func _player_character_ids() -> Dictionary:
	var out: Dictionary = {}
	if CampaignRepository.db.query_with_bindings("""
		SELECT id FROM characters
		WHERE campaign_id = ?
		  AND (character_type = 'pc'
		       OR (character_type = 'henchman' AND employer_id IN (
		           SELECT id FROM characters
		           WHERE campaign_id = ? AND character_type = 'pc')))
	""", [_campaign_id, _campaign_id]):
		for row in CampaignRepository.db.query_result:
			out[String((row as Dictionary).get("id", ""))] = true
	return out


# ---------------------------------------------------------------------------
# D-12 Phase B — the per-tick union (pass 0) and per-parcel context (pass 1)
# ---------------------------------------------------------------------------

## Drop every cached union / context / morale bundle. Called once at the top of
## each monthly tick: the caches describe ONE month and a stale entry would
## silently resolve a later month against an earlier month's numbers.
func _reset_month_caches() -> void:
	_union_by_owner.clear()
	_parcels_by_owner.clear()
	_parcel_rows.clear()
	_context_by_domain.clear()
	_revenue_by_owner.clear()
	_morale_by_owner.clear()


## The cache key for a parcel: its owner's character id under D-12, since the
## CHARACTER is the domain. An ownerless seat (an abstract holding whose ruler
## has not been minted, or one in succession) has no personal domain to belong
## to, so it keys on itself and resolves alone — the same numbers it produced
## before D-12.
func _owner_key(domain_data: Dictionary) -> String:
	var owner: String = _str_field(domain_data, "owner_character_id")
	if not owner.is_empty():
		return owner
	return "#" + String(domain_data.get("id", ""))


## The union for this parcel's owner, building it on demand. The demand path
## only fires when `_resolve_domain_month` is called outside `_handle_monthly_tick`
## (a focused test, a one-off resolution); the tick itself always populates the
## cache in pass 0, before any write.
func _union_for(domain_data: Dictionary) -> Dictionary:
	var key: String = _owner_key(domain_data)
	if not _union_by_owner.has(key):
		_union_by_owner[key] = PersonalDomain.for_domain(domain_data)
		_parcels_by_owner[key] = [domain_data]
		_parcel_rows[String(domain_data.get("id", ""))] = domain_data
	return _union_by_owner[key]


## Pass 1: this parcel's month context, computed once and cached. Also
## accumulates the owner's total revenue, which pass 2 needs for the RAW
## personal-authority lookup.
func _month_context_for(domain_data: Dictionary, calendar_day: int) -> Dictionary:
	var domain_id: String = String(domain_data.get("id", ""))
	if _context_by_domain.has(domain_id):
		return _context_by_domain[domain_id]
	var ctx: Dictionary = _build_month_context(
		domain_data, calendar_day, _union_for(domain_data))
	_context_by_domain[domain_id] = ctx
	var key: String = _owner_key(domain_data)
	_revenue_by_owner[key] = int(_revenue_by_owner.get(key, 0)) \
		+ int((ctx["revenue"] as Dictionary).get("total", 0))
	return ctx


## The character's DOMAIN RECORD PAGE — his lowest-id parcel, as designated by
## `PersonalDomain.seat_parcel_id`. It carries prior morale and the per-parcel
## morale inputs that cannot be summed across parcels (ruler-vs-domain alignment,
## population kind, tax and liturgy RATES, repression stance). Falls back to the
## parcel in hand when the seat is not part of this tick — an ownerless seat, or
## a union whose lowest-id parcel the tick did not load.
func _seat_row(union: Dictionary, fallback: Dictionary) -> Dictionary:
	var seat_id: String = String(union.get("seat_parcel_id", ""))
	if seat_id.is_empty():
		return fallback
	var row: Variant = _parcel_rows.get(seat_id)
	return row if row is Dictionary else fallback


## PASS 1 — everything a parcel needs before morale can be rolled, gathered in
## one place so pass 2 never recomputes it. Split out of `_resolve_domain_month`
## for D-12 Phase B: the character's personal-authority band keys on the SUM of
## his parcels' revenue, which cannot be known until every parcel has been
## through this function.
##
## THIS FUNCTION IS NOT PURE and must run exactly once per parcel per month: it
## mutates `domain_data["tribute_out_owed"]` and commits the pending
## consecrate_fields effects it consumed. That is why pass 2 reads the cache
## rather than calling it again.
func _build_month_context(domain_data: Dictionary, calendar_day: int,
		union: Dictionary) -> Dictionary:
	var domain_id: String = String(domain_data.get("id", ""))
	var hexes: Array = CampaignRepository.get_domain_hexes(domain_id)

	# D-12: stronghold sufficiency is a property of the CHARACTER's domain, not
	# of one parcel. RAW lets a ruler hold many strongholds "so long as their
	# combined value secures the land", and prices non-contiguity THROUGH that
	# sufficiency test (§noncontiguous_domains L95-98) — the minimum covers owned
	# PLUS intervening hexes. Per-parcel evaluation defeated both halves: each
	# parcel is internally contiguous, so intervening hexes were never counted,
	# and a keep on parcel A could not secure parcel B however close it stood.
	# `PersonalDomain` sums each hex's OWN RAW minimum (per-hex `hex_cells.civilization`
	# for materialized domains, the per-parcel aggregate fallback otherwise) and
	# sums `strongholds.cp_value` across every parcel.
	var stronghold_value_cp: int = int(union.get("stronghold_value_cp", 0))
	var stronghold_minimum_cp: int = int(union.get("stronghold_minimum_cp", 0))
	var ruler: Dictionary = _build_ruler_context(domain_data)

	# Phase 5 garrison wiring (2026-05-16): aggregate the actual garrison-assigned
	# troop_units via GarrisonExpenditureCalculator. RAW §garrison L228-231:
	# unpaid faithful followers + trained militia + scutage troops + lord-favor
	# troops count toward the garrison cost by gp value even when no money
	# changes hands. The calculator handles that distinction and returns the
	# total cp value of garrison + the morale incentive bonus + below-minimum
	# penalty. The PAID portion feeds this parcel's expenses; the MORALE signals
	# are combined across the character's parcels in `_unified_morale_for`.
	var garrison: Dictionary = GarrisonExpenditureCalculator.compute_from_domain(domain_data)

	# Phase 7: tribute_in via RealmAggregator + TributeCalculator. The ruler
	# of THIS domain may have direct vassals; tribute flows from each vassal's
	# realm to this ruler at the rate dictated by the RAW table reduced by the
	# efficiency factor.
	var tribute_aggregate: Dictionary = _compute_tribute_in_for_domain(domain_data)
	# cp. Until 2026-07-31 this read the gp-named key and fed it straight into
	# DomainRevenueCalculator's `tribute_in_cp` parameter, crediting every liege
	# 1/100th of the tribute actually owed. Conventions §127.
	var tribute_in_cp: int = int(tribute_aggregate.get("total_received_cp", 0))

	# Phase 7 / D-12: tribute_out_owed is recomputed each month from the vassal's
	# realm aggregate, so growth and shrinkage flow naturally into what he owes.
	# It is charged ONCE PER CHARACTER — see `_tribute_out_for_parcel`. We mutate
	# the local dict so the expense calculator (which reads tribute_out_owed)
	# picks it up; persistence happens in _save_domain.
	var tribute_out: int = _tribute_out_for_parcel(domain_data, union)
	domain_data["tribute_out_owed"] = tribute_out

	# Phase 8: ongoing scutage owed by THIS ruler. Like tribute it is an
	# obligation of the OATH, not of a parcel, so it rides the same seat gate.
	var scutage_cp: int = 0
	if String(union.get("tribute_seat_id", "")) == domain_id:
		scutage_cp = _compute_active_scutage_cp_for_domain(domain_data)

	# Phase 3: pending_investment_cp is set by oversee_investment handler on
	# completion (migration 068); consumed and reset here.
	var investment_cp: int = int(domain_data.get("pending_investment_cp", 0))

	# Phase 10A.2: Faith block pre-resolve modifiers. consecrate_fields adds
	# land-value bonus to this month's revenue; consecrate_ruler adds base
	# morale bonus while its 12-month window is active.
	var faith_modifiers: Dictionary = FaithMonthlyResolver.compute_pre_resolve_modifiers(
		domain_id, calendar_day)
	var faith_land_value_bonus: int = int(
		faith_modifiers.get("consecrate_fields_bonus_per_family", 0))

	# Standing levy penalties for peasants under arms — militia (RAW
	# daw_armies_recruitment.xml:428-432) and excess-levy tribal warriors
	# (ax_domains_of_chaos.xml:399). Read ONCE and fed to both revenue and
	# morale so the two cannot disagree about how many peasants are levied.
	var levy: Dictionary = LevyPenaltyCalculator.penalties_for_domain(
		domain_id, int(domain_data.get("peasant_families", 0)))
	var levied_peasants: int = int(levy.get("levied", 0))

	var revenue := DomainRevenueCalculator.calculate_monthly_revenue(
		domain_data, hexes, stronghold_value_cp, stronghold_minimum_cp, tribute_in_cp,
		levied_peasants)

	# Phase 10A.2: apply consecrate_fields bonus to revenue total + subcategory.
	if faith_land_value_bonus != 0 and not revenue.get("income_gate_active", false):
		var peasant_families: int = int(domain_data.get("peasant_families", 0))
		var bonus_total: int = faith_land_value_bonus * peasant_families
		revenue["consecrate_fields_bonus"] = bonus_total
		revenue["total"] = int(revenue.get("total", 0)) + bonus_total
		FaithMonthlyResolver.apply_pending_consecrate_fields(
			faith_modifiers.get("consecrate_fields_fired_effect_ids", []))

	return {
		"hexes": hexes,
		"hex_count": hexes.size(),
		"stronghold_value_cp": stronghold_value_cp,
		"stronghold_minimum_cp": stronghold_minimum_cp,
		"ruler": ruler,
		"garrison": garrison,
		"actual_garrison_paid_cp": int(garrison.get("total_paid_cp", 0)),
		"tribute_aggregate": tribute_aggregate,
		"tribute_in_cp": tribute_in_cp,
		"tribute_out": tribute_out,
		"scutage_cp": scutage_cp,
		"investment_cp": investment_cp,
		"faith_ruler_morale_bonus": int(
			faith_modifiers.get("consecrate_ruler_base_morale_bonus", 0)),
		"levy": levy,
		"revenue": revenue,
	}


## D-12 — the character's realm tribute, charged to exactly ONE parcel.
##
## THE DEFECT THIS CLOSES. `_compute_tribute_out_for_vassal_domain` never used
## the parcel's families: it aggregates the whole CHARACTER's realm and always
## did. But it was invoked once per parcel, gated only on that parcel carrying a
## `liege_domain_id`, and the full figure was written to each. A lord holding two
## liege-bearing parcels therefore owed his ENTIRE realm's tribute TWICE — a
## clean N× multiplication. (`idx_vassal_assignments_unique_active` forbids two
## parcels under the SAME liege, but two parcels under DIFFERENT lieges is
## exactly the escheat/conquest case D-12 exists for.)
##
## Under personal allegiance a character has one liege and owes one tribute, so
## the charge lands on `PersonalDomain.tribute_seat_id` — his lowest-id
## liege-bearing parcel, stable across months because parcel ids do not change.
## The seat also becomes the one parcel whose treasury is tested for the payment
## loyalty roll, so a shortfall triggers one roll per character rather than N.
##
## Phase E replaces the derivation (`vassal_assignments.liege_character_id`
## becomes authoritative and `domains.liege_domain_id` demotes to a derived seat
## pointer), not the fact that there is exactly one seat.
func _tribute_out_for_parcel(domain_data: Dictionary, union: Dictionary) -> int:
	if String(union.get("tribute_seat_id", "")) != String(domain_data.get("id", "")):
		return 0
	return _compute_tribute_out_for_vassal_domain(domain_data)


## D-12 — resolve the character's domain morale ONCE and cache it for every one
## of his parcels.
##
## WHY ONE ROLL. RAW's oversize mechanic IS personal authority
## (`acore_axioms` §personal_authority L430-449): class level cross-referenced
## against domain INCOME, down to -4 base morale. Rolling per parcel handed a
## 6th-level lord with one 600 gp domain the harsh band, but gave him three
## lookups in a mild band if he split it into three 200 gp parcels — a straight
## morale BONUS for holding land in pieces, and the RAW ceiling on how much land
## a level can rule never bound. Summing his parcels' revenue restores it.
##
## WHAT COMBINES AND WHAT DOES NOT:
##   * Revenue (authority band), stronghold value + minimum (sufficiency), and
##     classification (worst hex) come from the union — RAW states all three over
##     "the domain", which under D-12 is the whole holding.
##   * Garrison and levy are RATIOS over families, so they are re-derived from
##     summed totals rather than averaged: a lord who garrisons his populous seat
##     lavishly and leaves a bare frontier parcel is one ruler slightly
##     underpaying, not one earning a bonus and one taking a penalty.
##   * Alignment mismatch, population kind, tax/liturgy rates, repression stance
##     and prior morale cannot be summed. They are read from the SEAT parcel —
##     the character's domain record page. A per-parcel value on a non-seat
##     parcel is therefore invisible to morale, which is the intended
##     consequence of "one character, one domain record", not an oversight.
##
## Returns {base_morale, morale, morale_tier, event_modifiers_sum,
##          garrison_summary, union_revenue_cp}.
func _unified_morale_for(domain_data: Dictionary, union: Dictionary,
		opts: Dictionary) -> Dictionary:
	var key: String = _owner_key(domain_data)
	if _morale_by_owner.has(key):
		return _morale_by_owner[key]

	var seat: Dictionary = _seat_row(union, domain_data)
	var parcels: Array = _parcels_by_owner.get(key, [domain_data])
	# The seat's context, falling back to the parcel in hand — which pass 1 (or
	# `_resolve_domain_month`'s own call) has always already built.
	var seat_ctx: Dictionary = _context_by_domain.get(String(seat.get("id", "")),
		_context_by_domain.get(String(domain_data.get("id", "")), {}))

	# The union's classification drives BOTH the morale modifier and the garrison
	# incentive band, so the two cannot disagree about how rough the land is.
	var classification: String = String(union.get(
		"worst_classification", PersonalDomain.DEFAULT_CLASSIFICATION))

	var garrison_summaries: Array = []
	var levied_total: int = 0
	for p in parcels:
		var pctx: Dictionary = _context_by_domain.get(String((p as Dictionary).get("id", "")), {})
		if pctx.is_empty():
			continue
		garrison_summaries.append(pctx["garrison"])
		levied_total += int((pctx["levy"] as Dictionary).get("levied", 0))
	var combined_garrison: Dictionary = GarrisonExpenditureCalculator.combine(
		garrison_summaries, classification)
	var levy_penalty: int = LevyPenaltyCalculator.morale_penalty(
		levied_total, int(union.get("peasant_families", 0)))

	var base_morale: int = DomainMoraleResolver.resolve_base_morale(
		seat, seat_ctx.get("ruler", {}), int(_revenue_by_owner.get(key, 0)),
		int(union.get("stronghold_value_cp", 0)),
		int(union.get("stronghold_minimum_cp", 0)),
		int(combined_garrison.get("morale_incentive_bonus", 0)),
		levy_penalty, classification)
	# Phase 10A.2: consecrate_ruler 12-month buff applies +1 / -1 to base morale
	# while the window is active. Per-parcel effect, taken from the seat.
	base_morale += int(seat_ctx.get("faith_ruler_morale_bonus", 0))

	# §8.4 backdrop auto-stabilize (gdd-ruler-ai.md): the morale ROLL sees the
	# garrison as funded to minimum; the real per-parcel summaries still drive
	# each parcel's expenses.
	var morale_garrison: Dictionary = combined_garrison
	if bool(opts.get(RulerBackdropStabilizer.OPT_ASSUME_GARRISON_FUNDED, false)):
		morale_garrison = RulerBackdropStabilizer.adjust_garrison_summary(combined_garrison)
	var event_modifiers_sum: int = _union_event_modifiers_sum(
		union, seat, parcels, morale_garrison)
	# §8.4 item 2: the assumed-administration grant is ONLY the +1 morale-roll
	# modifier — added here, never via the administer_domain_completed flag
	# (which DomainXpResolver would read as the +5% XP bonus).
	if bool(opts.get(RulerBackdropStabilizer.OPT_ASSUME_ADMINISTERED, false)) \
			and not _any_parcel_administered(parcels):
		event_modifiers_sum += RulerBackdropStabilizer.ADMINISTER_MORALE_BONUS

	# Repression is a monthly STANCE the ruler takes toward his people, and under
	# D-12 he has one people. It fires if he repressed anywhere, at the harshest
	# rate he paid for — the rate is cp/family, so summing across parcels would
	# invent a stance he never took.
	var repression_bonus: int = 0
	var is_repressed: bool = false
	for p in parcels:
		var row: Dictionary = p
		if bool(row.get("is_repressed_this_month", 0)):
			is_repressed = true
		repression_bonus = maxi(repression_bonus,
			int(row.get("repression_cp_per_family_this_month", 0)))

	var morale_roll: int = DiceSystem.roll_digital(6, 2, 0, "domain_morale").modified_total
	var morale: Dictionary = DomainMoraleResolver.resolve_current_morale(
		seat, base_morale, event_modifiers_sum,
		repression_bonus, is_repressed, morale_roll)
	if bool(opts.get(RulerBackdropStabilizer.OPT_NEGLECT_MORALE_FLOOR, false)):
		morale = RulerBackdropStabilizer.apply_neglect_floor(
			morale, int(seat.get("morale", 0)), event_modifiers_sum)

	var bundle: Dictionary = {
		"base_morale": base_morale,
		"morale": morale,
		"morale_tier": DomainMoraleResolver.morale_tier(int(morale["current_morale"])),
		"event_modifiers_sum": event_modifiers_sum,
		"garrison_summary": combined_garrison,
		"levy_morale_penalty": levy_penalty,
		"union_revenue_cp": int(_revenue_by_owner.get(key, 0)),
		"seat_parcel_id": String(seat.get("id", "")),
	}
	_morale_by_owner[key] = bundle
	return bundle


## True when the ruler administered his domain this month — on ANY parcel.
## Administering is one act by one ruler (`ax_campaign_play.xml:511`); which
## `domains` row the activity handler happened to stamp is bookkeeping.
func _any_parcel_administered(parcels: Array) -> bool:
	for p in parcels:
		if bool((p as Dictionary).get("administer_domain_completed_this_month", 0)):
			return true
	return false


## D-12 — the monthly event modifiers for the character's ONE morale roll.
## Carries RAW §monthly_event_modifiers L486-499 term for term; what D-12
## changed is the SCOPE of each term:
##   * tax and liturgy are per-family RATES the ruler sets, so they are read from
##     the SEAT rather than summed (summing would multiply one policy by his
##     parcel count).
##   * garrison underfunding comes from the COMBINED summary.
##   * administration fires from any parcel.
##   * challenger and settled-lair penalties are summed across parcels — a
##     challenger pillaging one corner of the realm shakes the whole realm, and
##     two of them are genuinely worse than one.
func _union_event_modifiers_sum(union: Dictionary, seat: Dictionary,
		parcels: Array, garrison_summary: Dictionary) -> int:
	var sum: int = 0
	# Rates are cp/family per the 2026-05-15 currency-precision pass. RAW baseline
	# is 1 gp/family = 100 cp/family; the modifier fires per gp of deviation.
	sum += (int(seat.get("liturgy_rate_cp_per_family", 100)) - 100) / 100
	# Tax bonus/penalty per L494-495 (2 gp/fam baseline = 200 cp/fam).
	sum += (200 - int(seat.get("tax_rate_cp_per_family", 200))) / 100
	# Garrison underpayment: -1 morale per gp/family below the universal RAW
	# minimum, per §monthly_event_modifiers L486.
	sum -= int(garrison_summary.get("gp_below_minimum_per_family", 0))
	# Phase 3: +1 morale-roll modifier per `acore_axioms` §administration L499.
	if _any_parcel_administered(parcels):
		sum += 1
	# The settled-lair penalty (RAW ax_domain_level_encounters §dungeons
	# L312-321) is lair XP over FAMILIES, so under D-12 it is diluted by the
	# character's whole population — a dragon in a duchy troubles it less than
	# the same dragon in a single barony. Each parcel's lairs are rated against
	# the union's families and the results summed; in practice at most one parcel
	# has a settled lair, so the per-parcel rounding is not observable.
	var union_families: int = int(union.get("families", 0))
	for p in parcels:
		var pid: String = String((p as Dictionary).get("id", ""))
		if pid.is_empty():
			continue
		# Phase 9C E4: refuse-battle morale penalty from an active npc_challenger
		# threat per RAW acore_axioms §effects_of_morale L627-630.
		var challenger: Dictionary = DomainThreatRepository.get_active_challenger_for_domain(pid)
		if not challenger.is_empty():
			sum -= int(challenger.get("morale_penalty", 0))
		if union_families > 0:
			sum -= DomainEncounterResolver.compute_settled_lair_morale_penalty(
				pid, union_families)
	return sum


# ---------------------------------------------------------------------------
# Domain resolution (per ACKS rules — RAW-correct as of Domain Phase 0)
# ---------------------------------------------------------------------------

## Resolve one month for a single domain by delegating to the Phase 0 resolvers.
## All math lives in the resolvers; this method's job is orchestration plus
## ledger writes plus the random event roll.
##
## [param opts] carries the §8.4 backdrop auto-stabilize flags
## (RulerBackdropStabilizer.resolution_options(); empty = normal resolution):
##   assume_garrison_funded — suppress the -1/gp-short morale modifier for
##       THIS roll only (expenses/ledger stay real).
##   neglect_morale_floor — off-camera current morale cannot fall below
##       min(prior, 0) (Apathetic) from neglect.
func _resolve_domain_month(domain_data: Dictionary, calendar_day: int,
		opts: Dictionary = {}) -> Dictionary:
	var domain_id: String = domain_data.get("id", "")
	var domain_name: String = domain_data.get("name", "Unknown")

	# --- Context (pass 1): hexes, stronghold, ruler, garrison, tribute, revenue ---
	# Computed once per parcel per month by `_build_month_context` and cached, so
	# that the character's total revenue is known before ANY parcel rolls morale.
	# Recomputing it here would double-charge tribute and re-consume the pending
	# consecrate_fields effects — see that function's docstring.
	var union: Dictionary = _union_for(domain_data)
	var ctx: Dictionary = _month_context_for(domain_data, calendar_day)
	var hexes: Array = ctx["hexes"]
	var hex_count: int = int(ctx["hex_count"])
	var ruler: Dictionary = ctx["ruler"]
	var revenue: Dictionary = ctx["revenue"]
	var investment_cp: int = int(ctx["investment_cp"])
	var tribute_aggregate: Dictionary = ctx["tribute_aggregate"]
	var tribute_out: int = int(ctx["tribute_out"])

	var expenses := DomainExpenseCalculator.calculate_monthly_expenses(
		domain_data, int(ctx["actual_garrison_paid_cp"]), revenue["income_gate_active"])

	# Phase 8 / D-12: ongoing scutage owed by THIS RULER. RAW §favors_and_duties
	# L362: "Scutage: vassal pays 1gp per family in the realm in place of
	# military service; counts as garrison expense for the vassal." The magnitude
	# is realm-wide and the obligation belongs to the OATH, so like tribute it is
	# charged once per character — `_build_month_context` zeroes it on every
	# parcel but the tribute seat. Added as an expense subcategory so the ledger
	# writer and the monthly settlement flow treat it like any other expense.
	var scutage_cp: int = int(ctx["scutage_cp"])
	if scutage_cp > 0:
		expenses["scutage"] = scutage_cp
		expenses["total"] = int(expenses.get("total", 0)) + scutage_cp

	# D-12: ONE morale roll for the character's domain, mirrored to every parcel.
	var morale_bundle: Dictionary = _unified_morale_for(domain_data, union, opts)
	var base_morale: int = int(morale_bundle["base_morale"])
	var morale: Dictionary = morale_bundle["morale"]
	var morale_tier: String = String(morale_bundle["morale_tier"])
	var growth := DomainGrowthResolver.resolve_growth(
		domain_data, revenue["total"], investment_cp, morale_tier,
		bool(domain_data.get("is_active_adventuring_this_month", 0)),
		revenue["income_gate_active"])

	# Urban Growth Stocking — Stage B (Migration 126) per Q-UGS-15: a
	# SEPARATE resolver running AFTER DomainGrowthResolver in the same
	# start-of-month investment subphase. The domain's investment_cp pool
	# is now committed; the settlement resolver pulls it (one settlement
	# per domain in v1 — see Q-UGS for multi-settlement routing).
	# `_resolve_settlement_growth_for_domain` returns the per-settlement
	# growth results so we can include them in the monthly report; it
	# also persists state and emits market_class_advanced /
	# market_class_regressed / settlement_dissolved signals as needed.
	var settlement_growth_results: Array = _resolve_settlement_growth_for_domain(
		domain_data, investment_cp)

	var class_change := ClassificationAdvancement.check_classification_change(
		domain_data, hex_count, _has_urban_settlement(domain_data),
		_urban_pct_of_peasants(domain_data),
		_distance_to_friendly_city(domain_data),
		_contiguous_expansion_blocked(domain_data),
		# Phase 11D.2: clanhold-style classification gates require the friendly
		# settlement to be in the same realm as the advancing domain (RAW L77-78).
		# Default true until the friendly-city lookup is wired with realm awareness;
		# the gate then becomes effective when _distance_to_friendly_city returns
		# real values from a same-realm-aware lookup.
		_friendly_settlement_in_same_realm(domain_data))

	# Phase 10A.2: Faith block post-resolve — congregant growth + upkeep for
	# divine-caster rulers. Runs AFTER revenue/expenses so the upkeep can debit
	# the domain treasury if the ruler's divine_power is insufficient.
	var faith_congregants: Dictionary = FaithMonthlyResolver.resolve_congregants_monthly(
		_str_field(domain_data, "owner_character_id"),
		_cha_modifier(int(ruler.get("charisma", 10))),
		domain_id,
		calendar_day)
	# Phase 10A.2: sweep expired pending_divine_effects.
	FaithMonthlyResolver.expire_stale_effects(domain_id, calendar_day)

	# Phase 11D.3: religion conversion monthly tick per
	# gdd-religion-conversion.md §5.2. Runs AFTER FaithMonthlyResolver so the
	# congregant gain from this month's proselytizing is already credited to
	# the per-domain congregants rows. The conversion resolver sums target-
	# religion congregants in this domain and checks the 60% threshold.
	# Updated domain_data is passed so the resolver sees the current morale
	# (used to compute morale_multiplier per §5.3).
	var domain_data_with_morale := domain_data.duplicate()
	domain_data_with_morale["morale"] = int(morale.get("current_morale", 0))
	var conversion_tick: Dictionary = ReligionConversionResolver.tick_conversion(
		domain_data_with_morale, calendar_day)

	# RAW: rules/ax_domains_of_chaos.xml:455 + rules/daw_armies_recruitment.xml:98
	# — "going without pay for a month" is a calamity. Pay is aggregate in this
	# project (no per-unit payment, no arrears columns), so the unpaid units are
	# designated ex post facto from the shortfall; see
	# TroopPayShortfallResolver's docstring for the rule and the player-override
	# seam. Troop pay takes first claim on treasury + this month's revenue —
	# `treasury_cp` here is still the PRE-settlement figure, since _save_domain
	# applies net_income at the end of the tick.
	var pay_shortfall: Dictionary = TroopPayShortfallResolver.resolve_for_domain(
		domain_id,
		int(domain_data.get("treasury_cp", 0)) + int(revenue.get("total", 0)))

	# Phase 11D.5 polish: tribal-warrior retention tick per
	# gdd-tribal-warriors.md §7. For each active tribal-warrior troop_unit
	# in this domain, increment `months_without_qualifying_spoils`. When the
	# counter hits 3, fire `tribal_warriors_morale_check_triggered` and roll
	# loyalty. Units that received qualifying spoils in-month have already had
	# their counter reset to 0 via
	# SiegeSpoilsResolver.apply_spoils_to_tribal_warriors; the increment
	# here brings them back to 1 on the following month, which represents
	# "one month has now passed since last qualifying credit" — the
	# semantically correct "consecutive months without" reading.
	#
	# The unpaid designation is fed IN rather than rolled separately so a unit
	# suffering both monthly calamities makes ONE roll at -2 per RAW
	# daw_armies_recruitment.xml:100, not two independent rolls.
	_tick_unit_loyalty(domain_id, calendar_day,
		pay_shortfall.get("unpaid_unit_ids", []))

	# Aspirant promotion rolls (10B.1d, per Q20 [RESOLVED 2026-05-11]:
	# universal d20+ability_mod 14+ throw at joined_calendar_day + 112 —
	# exactly 4 months on the 13×28 calendar; corrected 2026-06-12 from the
	# 30-day-month +120 gloss). The 10B.1a "+30 days_completed" stub advance
	# was removed 2026-06-12 as dead code — see _resolve_magic_research_month.
	var mr_summary: Dictionary = _resolve_magic_research_month(
		_str_field(domain_data, "owner_character_id"), calendar_day)

	# --- Ledger writes (one row per nonzero subcategory) ---
	if not domain_id.is_empty():
		_write_revenue_ledger(domain_id, calendar_day, revenue)
		_write_expense_ledger(domain_id, calendar_day, expenses)

	# --- Random event roll (kept simple in Phase 0; Phase 8 replaces this) ---
	var domain_event: Dictionary = _maybe_generate_event(domain_name)

	# Phase 7: realm title update — recompute based on the new realm aggregate.
	var title_update: Dictionary = _resolve_realm_title(domain_data)

	# Phase 7: vassal-side tribute payment loyalty roll. If this domain owes
	# tribute_out and treasury can't cover it, trigger Henchman Loyalty roll.
	var tribute_payment: Dictionary = _resolve_vassal_tribute_payment(
		domain_data, tribute_out, calendar_day)

	# R-1: the Favors & Duties roll USED to run here, inside the per-domain loop.
	# It is a RULER-level event (RAW §favors_and_duties L352: "Each month, a vassal
	# ruler rolls once on the Favors and Duties table"), so it now runs exactly once
	# per ruler in `_resolve_favors_and_duties_for_rulers`, AFTER this loop closes.
	# See that function for why the position matters.

	# Phase 9A: domain encounters / bandits / NPC challengers / market
	# modifier expiry. Encounters fire the RAW frequency check
	# (civilized = monthly throw, borderlands = weekly compressed,
	# wilderness = daily compressed). Bandit-spawn syncs the swarm to current
	# morale tier. Challenger emergence accumulates monthly chance per tier.
	# Market-class modifier expiry runs first so this month's effective class
	# is current.
	var post_morale_data: Dictionary = domain_data.duplicate()
	post_morale_data["morale"] = int(morale["current_morale"])
	post_morale_data["peasant_families"] = int(post_morale_data.get("peasant_families", 0)) + int(growth.get("net_change", 0))
	MarketClassModifierResolver.expire_modifiers(_campaign_id, calendar_day)
	var encounter_summary: Dictionary = DomainEncounterResolver.roll_monthly_encounters_for_domain(
		post_morale_data, calendar_day)
	var bandit_summary: Dictionary = BanditSpawner.sync_for_domain(
		post_morale_data, calendar_day)
	var challenger_summary: Dictionary = NPCChallengerEmergence.process_monthly_tick(
		post_morale_data, calendar_day)

	var net_income: int = revenue["total"] - expenses["total"]
	return {
		"domain_id": domain_id,
		"domain_name": domain_name,
		"revenue": revenue["total"],
		"revenue_breakdown": revenue,
		"garrison_cost": expenses["garrison"],
		"maintenance": expenses["maintenance"],
		"total_expenses": expenses["total"],
		"expense_breakdown": expenses,
		"net_income": net_income,
		"base_morale": base_morale,
		"morale_change": morale["morale_change"],
		"current_morale": morale["current_morale"],
		"morale_tier": morale_tier,
		"morale_roll": morale,
		"population_growth": growth["net_change"],
		"growth_breakdown": growth,
		"classification_change": class_change,
		"domain_event": domain_event,
		"income_gate_active": revenue["income_gate_active"],
		# Phase 7 additions:
		"tribute_in_breakdown": tribute_aggregate,
		"tribute_out_owed": tribute_out,
		"tribute_payment": tribute_payment,
		"realm_title": title_update,
		# R-1: Favors & Duties results are no longer a per-DOMAIN key. They are
		# reported once per ruler on the tick's `favors_duties_reports`.
		# Phase 9A: encounter / bandit / challenger summaries.
		"encounter_summary": encounter_summary,
		"bandit_summary": bandit_summary,
		"challenger_summary": challenger_summary,
		# Phase 10B.1a: Magical Research monthly summary.
		"magic_research_summary": mr_summary,
		# Urban Growth Stocking — Stage B per `gdd-urban-growth-stocking.md`
		# §6.2. One result dict per settlement under this domain.
		"settlement_growth": settlement_growth_results,
		# RAW "without pay for a month" designation for this month, whether or
		# not anything went unpaid (shortfall_cp == 0 in the common case).
		"pay_shortfall": pay_shortfall,
		# D-12: what the RAW math was actually computed over. Surfaced so the
		# monthly report can say "this is one parcel of a 3-parcel domain, and
		# the morale you see was rolled for the whole of it" rather than looking
		# like a mis-scoped number.
		"personal_domain": {
			"character_id": String(union.get("character_id", "")),
			"parcel_count": int(union.get("parcel_count", 1)),
			"parcel_ids": union.get("parcel_ids", [domain_id]),
			"seat_parcel_id": String(union.get("seat_parcel_id", domain_id)),
			"tribute_seat_id": String(union.get("tribute_seat_id", "")),
			"is_materialized": bool(union.get("is_materialized", false)),
			"families": int(union.get("families", 0)),
			"effective_hex_count": int(union.get("effective_hex_count", 0)),
			"worst_classification": String(union.get("worst_classification", "")),
			"stronghold_value_cp": int(union.get("stronghold_value_cp", 0)),
			"stronghold_minimum_cp": int(union.get("stronghold_minimum_cp", 0)),
			"union_revenue_cp": int(morale_bundle.get("union_revenue_cp", 0)),
			"morale_rolled_on_seat": String(morale_bundle.get("seat_parcel_id", "")),
		},
	}


## 10B.1d aspirant promotion: fires the promotion throw for every
## aspirant_in_training follower whose promotion_eligible_day has come due
## (Q20 [RESOLVED 2026-05-11]) via SanctumApprenticeResolver.
##
## The 10B.1a "+30 days_completed per month" stub advance was REMOVED
## 2026-06-12 as provably dead: it only touched status='in_progress' rows,
## but no code path ever creates one — the 10B.1b/c handlers run research
## through the ActivityTimeCostExecutor tick system (real days, 1 tick =
## 1 day) and insert magic_research_projects rows already terminal
## (completed/failed) as historical records. The stub was also unit-wrong
## (30-day month on the 13×28 calendar). If a future wave introduces
## genuinely month-paced in_progress projects, advance by
## Timekeeping.DAYS_PER_MONTH, not 30.
func _resolve_magic_research_month(
	owner_character_id: String,
	calendar_day: int,
) -> Dictionary:
	# Aspirant promotion throws (Q20). list_aspirants_due_for_promotion is
	# global across all owners — we filter to this owner's aspirants since
	# the monthly tick fires per domain. (Future polish: a dedicated
	# realm-AI pass can handle NPC sanctums in one batch.)
	var aspirants_promoted: int = 0
	var aspirants_departed: int = 0
	if not owner_character_id.is_empty():
		var due_aspirants: Array = CampaignRepository.list_aspirants_due_for_promotion(calendar_day)
		for aspirant in due_aspirants:
			if String(aspirant.get("owner_character_id", "")) != owner_character_id:
				continue
			var result: Dictionary = SanctumApprenticeResolver.resolve_promotion_throw(
				aspirant, calendar_day)
			if bool(result.get("success", false)):
				aspirants_promoted += 1
			else:
				aspirants_departed += 1

	return {
		"aspirants_promoted": aspirants_promoted,
		"aspirants_departed": aspirants_departed,
	}


## Persist domain updates after monthly resolution.
## [param calendar_day] is needed by the clanhold population-shrink release
## hook, which chronicles to the departure log.
func _save_domain(domain_data: Dictionary, result: Dictionary,
		calendar_day: int = 0) -> void:
	var domain_id: String = domain_data.get("id", "")
	if domain_id.is_empty():
		return

	var net: int = result.get("net_income", 0)
	var prior_peasants: int = int(domain_data.get("peasant_families", 0))
	var new_peasants: int = maxi(0, prior_peasants + int(result.get("population_growth", 0)))
	var class_change: Dictionary = result.get("classification_change", {})
	var prior_territory: String = String(domain_data.get("territory_type", "wilderness"))
	var new_territory: String = String(class_change.get(
		"new_classification", prior_territory))
	var prior_treasury: int = int(domain_data.get("treasury_cp", 0))
	var new_treasury: int = prior_treasury + net

	# D-12: a classification change is a DOMAIN-level decision with a PER-HEX
	# consequence. Nothing else in the engine writes `hex_cells.civilization`
	# after world generation, so without this the per-hex stronghold minimum and
	# garrison rate would keep quoting the domain's ORIGINAL classification
	# forever and advancement would silently do nothing. See
	# ClassificationAdvancement.propagate_to_hexes.
	if new_territory != prior_territory:
		ClassificationAdvancement.propagate_to_hexes(domain_id, new_territory)

	# R-7a: domain XP is now RAW's figure — net income above the RULER's gp
	# threshold, computed and awarded by DomainXpResolver just before this call —
	# not the raw copper net income this method used to store into a column nothing
	# read. The Phase 3 administer_domain "+5% domain XP" moved INTO the resolver
	# (RAW ax_campaign_play.xml:511) so it composes with the prime-requisite
	# adjustment under a single banker's rounding; the `int(round(...))` that used
	# to apply it here rounded half away from zero. Note migration 068 cites
	# acore_axioms §administration L499 for that bonus and the pointer is wrong —
	# the rule is real but lives in Axioms. The morale half of the same rule still
	# fires from _union_event_modifiers_sum, and the flag reset below is unchanged.
	var xp_award: Dictionary = result.get("domain_xp_award", {})

	var fields := {
		"morale": result.get("current_morale", domain_data.get("morale", 0)),
		"peasant_families": new_peasants,
		"treasury_cp": new_treasury,
		"revenue_cp": result.get("revenue", 0),
		"expenses_cp": result.get("total_expenses", 0),
		"net_income_cp": net,
		"territory_type": new_territory,
		# Phase 7: tribute_out_owed (recomputed each month from realm aggregate).
		"tribute_out_owed": int(result.get("tribute_out_owed", 0)),
		# Reset Phase 3 transient modifiers after consumption.
		"administer_domain_completed_this_month": 0,
		"pending_investment_cp": 0,
		# Ruler AI Phase 2 [NEEDS-OPUS-REVIEW]: repression is a MONTHLY stance —
		# the roll above consumed the +1/gp bonus and the morale-cap, so the
		# "_this_month" columns reset like the other transients (this was the
		# repress_population handler's own documented contract, previously
		# unimplemented: nothing ever cleared the flags, so one repression
		# permanently capped morale at 0 and recurred forever). Sustained
		# repression = repress again next month.
		"is_repressed_this_month": 0,
		"repression_cp_per_family_this_month": 0,
	}

	# R-7a: record the month's XP and stamp the double-award guard in the SAME
	# UPDATE. Written only when the resolver actually ran — a skipped resolution
	# (ownerless seat, or a re-entered tick the guard already rejected) must not
	# overwrite a real figure with 0, and must not advance the guard day on a
	# month it did not pay for.
	if not xp_award.is_empty() and not bool(xp_award.get("skipped", false)):
		fields["domain_xp_this_month"] = int(xp_award.get("earned", 0))
		if int(xp_award.get("awarded", 0)) > 0:
			fields["domain_xp_awarded_through_day"] = calendar_day

	# Phase 11D.5 polish: population-growth refill of the tribal-warrior pool.
	# Per gdd-tribal-warriors.md §3 + §5.5: when peasant_families grows on a
	# clanhold, available_tribal_warriors grows with it (capped at
	# `peasant_families - currently_levied` per the pool invariant). The slack
	# = peasant_families - available - levied tracks the dead-not-yet-replaced
	# count; population growth fills the slack first.
	if String(domain_data.get("domain_style", "civilized")) == "clanhold":
		var population_growth_count: int = new_peasants - prior_peasants
		var prior_available: int = int(domain_data.get("available_tribal_warriors", 0))
		# Sum currently-levied tribal_warrior unit counts to enforce the
		# invariant cap. We could call TribalWarriorRegistry.pool_for_domain
		# but that re-reads the domain row; the count we need is just the
		# active tribal_warrior troop_units sum.
		var levied: int = _sum_active_tribal_warrior_count(domain_id)
		if population_growth_count > 0:
			var cap: int = new_peasants - levied
			var proposed: int = prior_available + population_growth_count
			var new_available: int = clampi(proposed, 0, maxi(0, cap))
			if new_available != prior_available:
				fields["available_tribal_warriors"] = new_available
		elif population_growth_count < 0:
			# RAW: rules/ax_domains_of_chaos.xml:402 — "If population is
			# reduced, some tribal warriors must be released to return to their
			# villages." Without this branch a shrinking clanhold kept every
			# warrior and `available + levied` could exceed peasant_families,
			# breaking the §3 pool invariant that pool_for_domain reports.
			var released: Dictionary = _release_tribal_warriors_for_population_loss(
				domain_id, new_peasants, prior_available, levied, calendar_day)
			if released.has("new_available"):
				fields["available_tribal_warriors"] = int(released["new_available"])
	# Phase 7: realm_title persistence.
	var title_update: Dictionary = result.get("realm_title", {})
	if not title_update.is_empty():
		fields["realm_title"] = String(title_update.get("new_title",
			domain_data.get("realm_title", "Baron")))
	CampaignRepository.update_domain_monthly_state(domain_id, fields)


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

func _emit_signals(domain_data: Dictionary, result: Dictionary) -> void:
	var domain_id: String = domain_data.get("id", "")
	if domain_id.is_empty():
		return

	var net: int = result.get("net_income", 0)
	if net != 0:
		EventBus.income_collected.emit(domain_id, net)

	var prior_morale: int = int(domain_data.get("morale", 0))
	var current_morale: int = int(result.get("current_morale", prior_morale))
	if current_morale != prior_morale:
		EventBus.domain_morale_changed.emit(domain_id, prior_morale, current_morale)

	if net != 0:
		var prior_treasury: int = int(domain_data.get("treasury_cp", 0))
		EventBus.domain_treasury_changed.emit(domain_id, prior_treasury, prior_treasury + net)

	var class_change: Dictionary = result.get("classification_change", {})
	var prior_class: String = String(domain_data.get("territory_type", "wilderness"))
	if bool(class_change.get("advanced", false)):
		EventBus.classification_advanced.emit(domain_id, prior_class,
			String(class_change["new_classification"]))
	elif bool(class_change.get("regressed", false)):
		EventBus.classification_regressed.emit(domain_id, prior_class,
			String(class_change["new_classification"]))

	var domain_event: Dictionary = result.get("domain_event", {})
	if not domain_event.is_empty():
		EventBus.domain_event_occurred.emit(domain_id, domain_event)

	# Phase 7: realm_title_changed signal.
	var title_update: Dictionary = result.get("realm_title", {})
	if not title_update.is_empty() and bool(title_update.get("changed", false)):
		if EventBus.has_signal("realm_title_changed"):
			EventBus.emit_signal("realm_title_changed", domain_id,
				String(title_update.get("old_title", "")),
				String(title_update.get("new_title", "")))


# ---------------------------------------------------------------------------
# Ledger writes
# ---------------------------------------------------------------------------

func _write_revenue_ledger(domain_id: String, calendar_day: int, revenue: Dictionary) -> void:
	for sub: String in ["service", "tax", "land"]:
		var amount: int = int(revenue.get(sub, 0))
		if amount != 0:
			CampaignRepository.add_ledger_entry({
				"domain_id": domain_id, "calendar_day": calendar_day,
				"category": "revenue", "subcategory": sub,
				"cp_amount": amount, "description": "",
			})
	var tin: int = int(revenue.get("tribute_in", 0))
	if tin != 0:
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id, "calendar_day": calendar_day,
			"category": "tribute_in", "subcategory": "vassal_tribute",
			"cp_amount": tin, "description": "",
		})
	# Phase 10A.2: consecrate_fields bonus (positive or negative).
	var cf_bonus: int = int(revenue.get("consecrate_fields_bonus", 0))
	if cf_bonus != 0:
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id, "calendar_day": calendar_day,
			"category": "revenue", "subcategory": "consecrate_fields_bonus",
			"cp_amount": cf_bonus,
			"description": "Consecrate Fields land-value adjustment (%+d gp/family)" % cf_bonus,
		})


func _write_expense_ledger(domain_id: String, calendar_day: int, expenses: Dictionary) -> void:
	# Phase 8: scutage joins the existing expense subcategories.
	for sub: String in ["garrison", "liturgy", "maintenance", "tithe", "repression", "scutage"]:
		var amount: int = int(expenses.get(sub, 0))
		if amount != 0:
			CampaignRepository.add_ledger_entry({
				"domain_id": domain_id, "calendar_day": calendar_day,
				"category": "expense", "subcategory": sub,
				"cp_amount": amount, "description": "",
			})
	var tout: int = int(expenses.get("tribute_out", 0))
	if tout != 0:
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id, "calendar_day": calendar_day,
			"category": "tribute_out", "subcategory": "liege_tribute",
			"cp_amount": tout, "description": "",
		})


# ---------------------------------------------------------------------------
# Resolver inputs (helpers)
# ---------------------------------------------------------------------------

## D-12 Phase B removed this section's two stronghold helpers.
## `_stub_stronghold_value` (a delegate to `StrongholdRepository.get_stronghold_value_for_domain`)
## and `_classification_minimum_cp` (a delegate to
## `StrongholdRepository.classification_minimum_cp`) both answered PER PARCEL.
## Sufficiency is now a property of the character's whole holding, so both
## quantities come from `PersonalDomain` — which sums stronghold value across
## parcels and sums each HEX's own RAW minimum over the effective (owned +
## intervening) set. `StrongholdRepository` remains the single source of the RAW
## §minimum_stronghold_value table.


## Coerces a Dictionary field to String, treating `null` as empty. SQLite
## TEXT columns that are NULL come back as `null` in the row dict, and
## `Dictionary.get(key, "")` returns the existing `null` rather than the
## default — so `String(null)` errors with "Nonexistent String constructor".
## Use this anywhere a nullable TEXT column is read into a String local.
static func _str_field(d: Dictionary, key: String, fallback: String = "") -> String:
	var v = d.get(key, fallback)
	if v == null:
		return fallback
	return String(v)


## Build the ruler context dict the morale resolver expects. Looks up CHA mod,
## level, leadership proficiency, and alignment from the ruler character row.
func _build_ruler_context(domain_data: Dictionary) -> Dictionary:
	var ruler_id: String = _str_field(domain_data, "owner_character_id")
	if ruler_id.is_empty():
		return {}
	var character: Dictionary = CampaignRepository.get_character(ruler_id)
	if character.is_empty():
		return {}
	# CHA modifier — characters store ability scores 3-18; convert to ACKS adj.
	var cha: int = int(character.get("cha", 10))
	return {
		"cha_modifier": _cha_modifier(cha),
		"level": int(character.get("level", 1)),
		"has_leadership_proficiency": _has_leadership_proficiency(ruler_id),
		"alignment": String(character.get("alignment", "neutral")),
	}


## ACKS ability modifier: 3 → -3; 4-5 → -2; 6-8 → -1; 9-12 → 0;
## 13-15 → +1; 16-17 → +2; 18 → +3 per `acore_*` ability tables.
func _cha_modifier(cha: int) -> int:
	if cha <= 3:   return -3
	elif cha <= 5: return -2
	elif cha <= 8: return -1
	elif cha <= 12: return 0
	elif cha <= 15: return 1
	elif cha <= 17: return 2
	return 3


func _has_leadership_proficiency(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	# Column is `proficiency_key` per character_proficiencies schema (migration
	# 007). The original `proficiency_id` was a typo that never fired because
	# no domain had a real ruler until rulers got auto-seeded by the Avalon
	# bootstrap; the monthly tick has been reaching here since that landed.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT 1 FROM character_proficiencies
		WHERE character_id = ? AND proficiency_key = 'leadership'
		LIMIT 1
	""", [character_id]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


## D-12 Phase B replaced this section's per-parcel `_event_modifiers_sum` with
## `_union_event_modifiers_sum`, which computes the same RAW
## §monthly_event_modifiers L486-499 terms for the character's ONE morale roll:
## tax and liturgy rates from his domain record page, garrison underfunding from
## the combined summary, administration from any parcel, and challenger /
## settled-lair penalties summed across every parcel he holds.


# Phase 0 simplifications — Phase 2+ will surface real values.
func _has_urban_settlement(_domain_data: Dictionary) -> bool:
	return false


func _urban_pct_of_peasants(domain_data: Dictionary) -> int:
	var peasants: int = int(domain_data.get("peasant_families", 0))
	var urban: int = int(domain_data.get("urban_families", 0))
	if peasants <= 0:
		return 0
	return int(round(100.0 * float(urban) / float(peasants)))


## Distance in miles from the domain's location to the nearest friendly
## city/large-town. Used by ClassificationAdvancement per RAW §classification
## gates (72mi to borderlands; 48mi to civilized; clanhold-style tightens to
## 50mi / 25mi same-realm per gdd-domain-style-and-alignment.md §2).
##
## Implementation (post-Phase-11 cleanup):
## - Iterate settlement_entrances in the same campaign on the same map.
## - "City or large town" = market_class ≤ 5 (Classes V/IV/III/II/I = town/city/metropolis).
## - "Friendly" = settlement's realm is same-realm with the defender, OR the
##   realms have a relation disposition in {cordial, friendly, allied}.
## - Returns axial-hex-distance × 6 miles per project's 6-mile-hex convention.
## - Returns a very large value (effectively-infinite) when no friendly city
##   is reachable; the classification gates fail closed.
func _distance_to_friendly_city(domain_data: Dictionary) -> int:
	var closest: Dictionary = _find_closest_friendly_city(domain_data)
	return int(closest.get("distance_miles", 9999))


## Phase 11D.2: clanhold classification gates require the friendly reference
## settlement to be in the same realm. Returns true when the closest friendly
## city/large-town to this domain is in the same realm as the domain. For
## civilized domains the same-realm requirement is moot (the resolver only
## consults this for clanhold style).
##
## Per RAW ax_domains_of_chaos.xml:77-78 + gdd-domain-style-and-alignment.md §2.
func _friendly_settlement_in_same_realm(domain_data: Dictionary) -> bool:
	var closest: Dictionary = _find_closest_friendly_city(domain_data)
	# Default true when no city found — keeps the gate permissive in worlds
	# without any cities (classification advancement falls back to the
	# distance check, which fails closed at INF).
	return bool(closest.get("same_realm", true))


## Returns {distance_miles: int, same_realm: bool, settlement_id: String, realm_id: String}.
## Returns sentinel distance 9999 + same_realm=true when no friendly city is
## found (caller treats the distance gate as failing-closed).
func _find_closest_friendly_city(domain_data: Dictionary) -> Dictionary:
	var no_city: Dictionary = {
		"distance_miles": 9999, "same_realm": true,
		"settlement_id": "", "realm_id": "",
	}
	var campaign_id: String = String(domain_data.get("campaign_id", ""))
	var map_id_v: Variant = domain_data.get("location_map_id", null)
	if campaign_id.is_empty() or map_id_v == null:
		return no_city
	var map_id: String = String(map_id_v)
	var domain_q: int = int(domain_data.get("location_hex_q", 0))
	var domain_r: int = int(domain_data.get("location_hex_r", 0))
	var defender_realm: Dictionary = RealmRepository.get_realm_for_domain(
		String(domain_data.get("id", "")))
	var defender_realm_id: String = String(defender_realm.get("id", ""))
	# Pull every Class-V-or-better settlement on the same map in the campaign.
	# market_class is INVERSE — lower number = bigger settlement.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, hex_q, hex_r, parent_domain_id, market_class
		FROM settlement_entrances
		WHERE campaign_id = ? AND map_id = ? AND market_class <= 5
	""", [campaign_id, map_id]):
		return no_city
	if CampaignRepository.db.query_result.is_empty():
		return no_city
	var best_distance: int = 9999
	var best_same_realm: bool = false
	var best_settlement_id: String = ""
	var best_realm_id: String = ""
	for row: Dictionary in CampaignRepository.db.query_result.duplicate():
		var settlement_id: String = str(row.get("id", ""))
		var s_q: int = int(row.get("hex_q", 0))
		var s_r: int = int(row.get("hex_r", 0))
		var hex_dist: int = HexMapController.hex_distance(
			Vector2i(domain_q, domain_r), Vector2i(s_q, s_r))
		var distance_miles: int = hex_dist * 6  # 6-mile-hex project convention
		# Determine friendliness via realm-relations.
		var settlement_realm_id: String = ""
		var parent_id: String = str(row.get("parent_domain_id", ""))
		if not parent_id.is_empty():
			var s_realm: Dictionary = RealmRepository.get_realm_for_domain(parent_id)
			settlement_realm_id = String(s_realm.get("id", ""))
		var same_realm: bool = (not defender_realm_id.is_empty()
			and settlement_realm_id == defender_realm_id)
		var disposition: String = "neutral"
		if not defender_realm_id.is_empty() and not settlement_realm_id.is_empty():
			disposition = RealmRepository.get_relation(
				defender_realm_id, settlement_realm_id)
		var is_friendly: bool = same_realm or disposition in [
			"cordial", "friendly", "allied"]
		if not is_friendly:
			continue
		if distance_miles < best_distance:
			best_distance = distance_miles
			best_same_realm = same_realm
			best_settlement_id = settlement_id
			best_realm_id = settlement_realm_id
	if best_settlement_id.is_empty():
		return no_city
	return {
		"distance_miles": best_distance,
		"same_realm": best_same_realm,
		"settlement_id": best_settlement_id,
		"realm_id": best_realm_id,
	}


func _contiguous_expansion_blocked(_domain_data: Dictionary) -> bool:
	return false  # Phase 2+ replaces with terrain / neighbor analysis


# ---------------------------------------------------------------------------
# Phase 7: Realm aggregation, tribute, title resolution
# ---------------------------------------------------------------------------

## Compute the cp THIS DOMAIN receives from active vassals this month.
##
## TWO DIFFERENT SCOPES, and keeping them apart is the whole point of this
## function (Jedidiah ruling 2026-08-04):
##
##   * The EFFICIENCY FACTOR is keyed on the CHARACTER — "the sum-total of ALL
##     vassals paying tribute to a single character, regardless of which domain
##     seat they are paying to". A lord holding two domains with six vassals each
##     is a twelve-vassal lord for RAW §tribute_inefficiency L398-409, not two
##     six-vassal lords, so he takes the 9–16 band's 66% on every payment.
##   * The CREDIT is keyed on the DOMAIN — each vassal's tribute lands in the
##     domain his fief is actually held of (`vassal domain -> liege_domain_id`),
##     which is the authoritative realm pointer from ruling R-1.
##
## Until 2026-08-04 this was `_compute_tribute_in_for_ruler`, returning the
## ruler's ENTIRE tribute income and crediting it to whichever domain was being
## resolved — so a lord holding N domains banked his whole realm's tribute N
## times a month, and N× the domain XP that flows from it. Rulers normally hold
## exactly one domain (world generation mints a distinct character per domain),
## which is why the multiplication stayed invisible; it becomes reachable the
## moment a domain escheats to its liege on a vassal's death, or a conqueror
## takes a second domain without enfeoffing anyone to rule it.
##
## Returns cp per conventions §127. `total_received_cp` is THIS DOMAIN's share;
## `realm_total_received_cp` is the ruler's whole intake, for display.
func _compute_tribute_in_for_domain(domain_data: Dictionary) -> Dictionary:
	var summary: Dictionary = {
		"total_received_cp": 0,
		"realm_total_received_cp": 0,
		"per_vassal": [],
		"direct_vassal_count": 0,
		"efficiency_factor": 1.0,
	}
	var ruler_character_id: String = _str_field(domain_data, "owner_character_id")
	var domain_id: String = String(domain_data.get("id", ""))
	if ruler_character_id.is_empty() or domain_id.is_empty():
		return summary
	var assignments: Array = VassalRepository.list_active_for_liege(ruler_character_id)
	# CHARACTER-WIDE count — every vassal of this lord, across every domain he
	# holds. This is the RAW inefficiency input.
	var direct_count: int = assignments.size()
	summary["direct_vassal_count"] = direct_count
	var efficiency: float = TributeCalculator.efficiency_factor(direct_count)
	summary["efficiency_factor"] = efficiency
	if direct_count <= 0 or efficiency <= 0.0:
		return summary

	var destinations: Dictionary = _tribute_destinations(ruler_character_id)
	var total_cp: int = 0
	var realm_total_cp: int = 0
	for assn in assignments:
		var assn_id: String = String(assn.get("id", ""))
		var vassal_char: String = String(assn.get("vassal_character_id", ""))
		var v_aggregate: Dictionary = RealmAggregator.aggregate(vassal_char)
		var v_realm_families: int = int(v_aggregate.get("all_realm_families", 0))
		var v_base_cp: int = TributeCalculator.compute_tribute_base_cp(v_realm_families)
		# The liege's efficiency factor applies to what arrives in his coffers.
		var received_cp: int = MathUtils.bankers_round(float(v_base_cp) * efficiency)
		realm_total_cp += received_cp
		if String(destinations.get(assn_id, "")) != domain_id:
			continue  # this vassal's fief is held of one of the lord's OTHER seats
		total_cp += received_cp
		summary["per_vassal"].append({
			"vassal_assignment_id": assn_id,
			"vassal_character_id": vassal_char,
			"vassal_realm_families": v_realm_families,
			"base_cp": v_base_cp,
			"received_cp": received_cp,
		})
	summary["total_received_cp"] = total_cp
	summary["realm_total_received_cp"] = realm_total_cp
	return summary


## assignment id -> the domain OF THIS RULER that the vassal's tribute is owed to.
##
## Normally the vassal domain's `liege_domain_id`. Two cases fall back to the
## ruler's primary domain (his lowest-id holding — arbitrary but stable, and it
## keeps the realm total conserved rather than quietly dropping the payment):
## an oath with no fief attached (`vassal_domain_id` NULL), and a fief whose
## liege pointer has drifted off this ruler's holdings.
func _tribute_destinations(ruler_character_id: String) -> Dictionary:
	var out: Dictionary = {}
	var owned: Dictionary = {}
	var primary: String = ""
	if CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY id",
		[ruler_character_id]
	):
		for row in CampaignRepository.db.query_result:
			var did: String = String((row as Dictionary).get("id", ""))
			owned[did] = true
			if primary.is_empty():
				primary = did
	if primary.is_empty():
		return out
	if not CampaignRepository.db.query_with_bindings("""
		SELECT va.id AS assignment_id, vd.liege_domain_id AS dest
		FROM vassal_assignments va
		LEFT JOIN domains vd ON vd.id = va.vassal_domain_id
		WHERE va.liege_character_id = ? AND va.status = 'active'
	""", [ruler_character_id]):
		return out
	for row in CampaignRepository.db.query_result:
		var r: Dictionary = row
		var dest_v: Variant = r.get("dest")
		var dest: String = String(dest_v) if dest_v != null else ""
		out[String(r.get("assignment_id", ""))] = dest if owned.has(dest) else primary
	return out


## If THIS domain has a liege_domain_id, compute its tribute_out_owed for the
## month based on its own realm aggregate (the vassal's perspective). The
## VASSAL pays its OWN realm's base tribute; the liege's efficiency factor is
## applied to what the liege receives, not to what the vassal pays.
func _compute_tribute_out_for_vassal_domain(domain_data: Dictionary) -> int:
	var liege_v: Variant = domain_data.get("liege_domain_id")
	if liege_v == null or String(liege_v).is_empty():
		return 0
	var owner_id: String = _str_field(domain_data, "owner_character_id")
	if owner_id.is_empty():
		return 0
	var aggregate: Dictionary = RealmAggregator.aggregate(owner_id)
	var realm_families: int = int(aggregate.get("all_realm_families", 0))
	# cp — matches the `domains.tribute_out_owed` column, which the materializer,
	# AbstractTributeResolver and DomainExpenseCalculator all treat as cp.
	# Before 2026-07-31 this returned gp and silently redenominated the column
	# on the first monthly tick (conventions §127).
	return TributeCalculator.compute_tribute_base_cp(realm_families)


## Update the domain's realm_title based on the current aggregate. Returns
## {old_title, new_title, muster_period, changed}.
func _resolve_realm_title(domain_data: Dictionary) -> Dictionary:
	var old_title: String = String(domain_data.get("realm_title", "Baron"))
	var owner_id: String = _str_field(domain_data, "owner_character_id")
	if owner_id.is_empty():
		return {"old_title": old_title, "new_title": old_title,
				"muster_period": "Week", "changed": false}
	var aggregate: Dictionary = RealmAggregator.aggregate(owner_id)
	var personal_families: int = int(aggregate.get("personal_families", 0))
	var domains_ruled: int = int(aggregate.get("domains_ruled", 1))
	var realm_families: int = int(aggregate.get("all_realm_families", 0))
	var new_title: String = RealmTitleResolver.resolve_title(
		personal_families, domains_ruled, realm_families)
	return {
		"old_title": old_title,
		"new_title": new_title,
		"muster_period": RealmTitleResolver.muster_period(new_title),
		"changed": new_title != old_title,
		"personal_families": personal_families,
		"domains_ruled": domains_ruled,
		"realm_families": realm_families,
	}


## If the vassal cannot pay tribute_out from treasury_cp, trigger a Henchman
## Loyalty roll on the vassal-character. On Resignation/Hostility, the vassal
## revolts (vassal_assignment.status → revolted). Returns:
##   {paid: bool, gp_paid, gp_short, loyalty_outcome, revolted}
func _resolve_vassal_tribute_payment(
	domain_data: Dictionary,
	tribute_out: int,
	calendar_day: int
) -> Dictionary:
	var summary: Dictionary = {
		"paid": true,
		"gp_paid": tribute_out,
		"gp_short": 0,
		"loyalty_outcome": "",
		"revolted": false,
	}
	if tribute_out <= 0:
		return summary
	var treasury: int = int(domain_data.get("treasury_cp", 0))
	# Find the vassal_assignment row for the domain's owner.
	var owner_id: String = _str_field(domain_data, "owner_character_id")
	if owner_id.is_empty():
		return summary
	var assn: Dictionary = VassalRepository.get_active_assignment_for_vassal(owner_id)
	if assn.is_empty():
		# Domain has liege_domain_id but no active vassal_assignment row —
		# probably an inconsistent state from pre-Phase-7 data. Skip the
		# loyalty roll (no relationship to roll against).
		return summary
	var assn_id: String = String(assn.get("id", ""))
	if treasury >= tribute_out:
		# Paid in full; no roll needed.
		if EventBus.has_signal("vassal_tribute_paid"):
			EventBus.emit_signal("vassal_tribute_paid", assn_id, tribute_out, calendar_day)
		return summary
	# Cannot pay in full — roll Henchman Loyalty.
	summary["paid"] = false
	summary["gp_paid"] = maxi(0, treasury)
	summary["gp_short"] = tribute_out - summary["gp_paid"]
	var base_mod: int = int(assn.get("base_loyalty_modifier", 0))
	# Phase 8 polish: Office bonus per RAW L369 — if the rolling vassal's
	# liege holds an active "office" favor, +1 to the loyalty roll.
	base_mod += FavorsDutiesResolver.office_bonus_for_vassal_roll(owner_id)
	var roll: Dictionary = HenchmanLoyaltyResolver.resolve_loyalty_check(
		base_mod, false, false)
	var outcome: String = String(roll.get("outcome", ""))
	summary["loyalty_outcome"] = outcome
	VassalRepository.record_loyalty_roll(assn_id, outcome, calendar_day)
	if bool(roll.get("departs", false)):
		summary["revolted"] = true
		VassalRepository.update_status(assn_id, "revolted", calendar_day)
		if EventBus.has_signal("vassal_revolted"):
			EventBus.emit_signal("vassal_revolted", assn_id, owner_id,
				String(assn.get("liege_character_id", "")))
	return summary


# ---------------------------------------------------------------------------
# Phase 8: Favors & Duties monthly resolution
# ---------------------------------------------------------------------------

## Phase 8: sum scutage owed by THIS domain to its liege per any active
## scutage duty obligations on the vassal_assignment where this domain's
## owner is the vassal. Returns cp (RAW magnitude is gp; × 100 at the
## boundary since vassal_obligations.magnitude still stores gp).
## Returns 0 if this domain has no liege or no active scutage duty.
func _compute_active_scutage_cp_for_domain(domain_data: Dictionary) -> int:
	var liege_v: Variant = domain_data.get("liege_domain_id")
	if liege_v == null or String(liege_v).is_empty():
		return 0
	var owner_id: String = _str_field(domain_data, "owner_character_id")
	if owner_id.is_empty():
		return 0
	var assn: Dictionary = VassalRepository.get_active_assignment_for_vassal(owner_id)
	if assn.is_empty():
		return 0
	var assn_id: String = String(assn.get("id", ""))
	var active_duties: Array = VassalObligationsRepository.list_active_duties_for_assignment(assn_id)
	var total_gp: int = 0
	for d in active_duties:
		if str(d.get("type", "")) == "scutage":
			total_gp += int(d.get("magnitude", 0))
	return total_gp * 100


## R-1 — the Favors & Duties monthly roll, ONE pass per RULER, LOD-gated.
##
## WHY THIS IS NOT IN THE DOMAIN LOOP. RAW §favors_and_duties L352 says "Each month,
## a vassal ruler rolls once on the Favors and Duties table" — the roll belongs to
## the liege-vassal relationship, not to a domain. It used to run inside
## `_resolve_domain_month` keyed on that domain's `owner_character_id`, so a ruler
## holding N domains rolled the full table for every one of his vassals N TIMES a
## month. While world generation left `vassal_assignments` empty the bug was
## invisible (the lookup always returned []). R-1 fills that table, so without this
## hoist the first generated campaign would roll a d20 per vassal per domain across
## hundreds of off-camera realms every month — with real treasury transfers, real
## recurring scutage and real scheduled musters behind each roll.
##
## WHY IT RUNS AFTER THE DOMAIN LOOP. `_save_domain` writes `treasury_cp` as an
## ABSOLUTE `prior + net`, where `prior` came from the `domains` array fetched once
## before the loop. A gift or loan that F&D moved into ANOTHER domain's treasury
## mid-loop was therefore overwritten when that domain's own turn came up. Running
## the whole pass after the loop closes puts every F&D transfer strictly after the
## last absolute treasury write, so the transfers survive.
##
## LOD GATE. Only rulers the player can actually observe roll: PC-side rulers plus
## the `RulerLodManager` active set — the same predicate the domain loop uses to
## choose between full resolution and the §8.4 backdrop stabilizer. Backdrop realms
## hold their obligations static until the play window reaches them.
##
## Returns one entry per ruler that produced results:
##   {ruler_character_id: String, results: Array}
func _resolve_favors_and_duties_for_rulers(
	domains: Array,
	pc_ids: Dictionary,
	active_ruler_ids: Array,
	calendar_day: int,
) -> Array:
	var reports: Array = []
	var rolled: Dictionary = {}
	for domain_data: Dictionary in domains:
		# Terminal domains are skipped by the resolution loop; a ruler known to us
		# ONLY through a ruined or abandoned domain does not hold court either.
		var lifecycle_state: String = String(domain_data.get(
			"lifecycle_state", LifecycleHandler.STATE_ACTIVE))
		if lifecycle_state == LifecycleHandler.STATE_ABANDONED \
			or lifecycle_state == LifecycleHandler.STATE_SALTED_TO_RUIN:
			continue
		var owner: String = _str_field(domain_data, "owner_character_id")
		# `rolled` is what makes this once-per-RULER instead of once-per-domain.
		if owner.is_empty() or rolled.has(owner):
			continue
		if not (pc_ids.has(owner) or active_ruler_ids.has(owner)):
			continue
		rolled[owner] = true
		var results: Array = _resolve_favors_and_duties_for_ruler(owner, calendar_day)
		if results.is_empty():
			continue
		reports.append({"ruler_character_id": owner, "results": results})
	return reports


## For each active vassal of [param ruler_id], roll monthly on the Favors & Duties
## table per RAW §favors_and_duties L352-372. Returns an array of per-vassal
## resolution dicts (passes through whatever FavorsDutiesResolver returns).
##
## Phase 8 polish: also runs the loan-repayment monthly chance (RAW L365)
## and the construction auto-expenditure (RAW L361) for each active vassal.
func _resolve_favors_and_duties_for_ruler(ruler_id: String, calendar_day: int) -> Array:
	if ruler_id.is_empty():
		return []
	var assignments: Array = VassalRepository.list_active_for_liege(ruler_id)
	if assignments.is_empty():
		return []
	var results: Array = []
	for assn in assignments:
		var assn_id: String = String(assn.get("id", ""))
		if assn_id.is_empty():
			continue
		# Resolve ongoing-obligation monthly mechanics FIRST so that
		# completions (loans repaid, construction finished) clear the active
		# slate before the new d20 roll counts active duties for safe-total.
		var loan_results: Array = FavorsDutiesResolver.roll_monthly_loan_repayments(assn_id, calendar_day)
		var construction_results: Array = FavorsDutiesResolver.roll_monthly_construction_expenditure(assn_id, calendar_day)
		# Phase 9C polish: pass the runner's scheduler so call_to_arms tranches
		# actually schedule (otherwise the muster state is created but tranche
		# events never fire).
		var scheduler = _runner.get_scheduler() if _runner != null and _runner.has_method("get_scheduler") else null
		var outcome: Dictionary = FavorsDutiesResolver.roll_monthly(assn_id, calendar_day, null, scheduler)
		outcome["loan_repayments"] = loan_results
		outcome["construction_expenditures"] = construction_results
		results.append(outcome)
	return results


# ---------------------------------------------------------------------------
# Random event roll (Phase 0 placeholder; Phase 8 replaces with full table)
# ---------------------------------------------------------------------------

func _maybe_generate_event(domain_name: String) -> Dictionary:
	var event_roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "domain_event_check")
	if event_roll.modified_total > 1:
		return {}
	var severity_roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "domain_event_severity")
	var severity: int = 1
	if severity_roll.modified_total >= 5:
		severity = 3
	elif severity_roll.modified_total >= 3:
		severity = 2
	return {
		"event_type": "random",
		"severity": severity,
		"description": "A domain event of severity %d occurred in %s." % [severity, domain_name],
	}


# ---------------------------------------------------------------------------
# Date helper
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Urban Growth Stocking — Stage B (Migration 126)
# Per `generation/gdd-urban-growth-stocking.md` §6.2 EVALUATE_GROWTH /
# EVALUATE_CLASS, run as a sibling of DomainGrowthResolver (Q-UGS-15).
# ---------------------------------------------------------------------------

## Fan out SettlementGrowthResolver.process_monthly_tick across each
## settlement attached to the domain. Persists each settlement's new
## urban_families / market_class / cumulative_investment_gp; emits
## market_class_advanced, market_class_regressed, and settlement_dissolved
## signals as the per-settlement result indicates. Returns the array of
## per-settlement result dicts (one entry per settlement, in repository
## order) so the monthly report can show what happened.
##
## investment_cp is the domain's total committed investment for the month.
## In v1 we route the full pool to the FIRST settlement under the domain
## (matching the historical settlement_entrances seed pattern where each
## domain has a single "Chief Settlement"). Multi-settlement routing is
## flagged as a future polish item.
func _resolve_settlement_growth_for_domain(
	domain_data: Dictionary,
	investment_cp: int,
) -> Array:
	var domain_id: String = String(domain_data.get("id", ""))
	if domain_id.is_empty():
		return []
	var settlements: Array = CampaignRepository.list_settlements_for_domain(domain_id)
	if settlements.is_empty():
		return []
	var results: Array = []
	# In v1, the first settlement receives the full investment pool. If
	# additional settlements exist, they grow only via population dice +
	# random growth (steps 3 + 4 of §6.2) — no investment-driven attraction
	# beyond what the chief settlement consumed.
	var remaining_investment_cp: int = investment_cp
	for settlement_row in settlements:
		var settlement: Dictionary = settlement_row
		var alloc_cp: int = remaining_investment_cp
		remaining_investment_cp = 0  # next settlement gets none
		var result: Dictionary = SettlementGrowthResolver.process_monthly_tick(
			settlement, domain_data, alloc_cp)
		var settlement_id: String = String(settlement.get("id", ""))
		if not settlement_id.is_empty():
			CampaignRepository.update_settlement_growth_state(
				settlement_id,
				int(result.get("urban_families_new", 0)),
				int(result.get("market_class_new", 6)),
				int(result.get("new_cumulative_investment_gp",
					settlement.get("cumulative_investment_gp", 10000))))
			if bool(result.get("dissolved", false)):
				EventBus.settlement_dissolved.emit(settlement_id)
			elif bool(result.get("class_advanced", false)):
				EventBus.market_class_advanced.emit(
					settlement_id,
					int(result.get("market_class_old", 6)),
					int(result.get("market_class_new", 6)))
			elif bool(result.get("class_regressed", false)):
				EventBus.market_class_regressed.emit(
					settlement_id,
					int(result.get("market_class_old", 6)),
					int(result.get("market_class_new", 6)))
		result["settlement_id"] = settlement_id
		result["settlement_name"] = String(settlement.get("name", ""))
		results.append(result)
	return results


## Convert a Timekeeping date dict into a single integer day-of-campaign for
## ledger entries (canonical 1-based day serial, conventions §6.8).
func _calendar_day_from_date(date: Dictionary) -> int:
	return Timekeeping.calendar_day_from_date(date)


# ---------------------------------------------------------------------------
# Phase 11B: siege + stronghold-destroyed bridges
# ---------------------------------------------------------------------------

## Translate a Phase 9A siege conclusion into a lifecycle event.
## Outcomes `captured` / `surrendered` mean the defender lost; the besieging
## army's owner becomes the new ruler in the same_campaign_npc case.
## Outcomes `liberated` / `destroyed` / `departed` / `sallied_won` /
## `sallied_lost` are not domain-lifecycle events at this layer.
func _on_siege_concluded(siege_id: String, outcome: String) -> void:
	if outcome != "captured" and outcome != "surrendered":
		return
	# Look up the siege to find the defender domain + besieging force.
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return
	var domain_id: String = String(siege.get("domain_id", ""))
	if domain_id.is_empty():
		return
	var besieging_army_id: String = String(siege.get("besieging_army_id", ""))
	var campaign_id: String = String(siege.get("campaign_id", ""))
	# Resolve the attacker's owner character id via armies.political_owner_id.
	var attacker_owner_id: String = ""
	if not besieging_army_id.is_empty() and CampaignRepository.db.query_with_bindings(
		"SELECT political_owner_id FROM armies WHERE id = ?", [besieging_army_id]
	) and not CampaignRepository.db.query_result.is_empty():
		attacker_owner_id = String(CampaignRepository.db.query_result[0].get("political_owner_id", ""))
	# Phase 11D-prereq.0b: derive attacker intent and dispatch through
	# RealmRepository's three-outcome resolver.
	var attacker_intent: String = _derive_attacker_intent(siege, attacker_owner_id, domain_id)
	var resolution: Dictionary = RealmRepository.resolve_conquest_outcome(
		domain_id, attacker_owner_id, attacker_intent)
	var calendar_day: int = _calendar_day_from_date(Timekeeping.get_date())
	# Off-map occupy: instantiate a new tracked realm + head NPC, then patch
	# new_owner_id in the resolution before forwarding to LifecycleHandler.
	if String(resolution.get("outcome", "")) == RealmRepository.OUTCOME_OCCUPIED \
		and String(resolution.get("new_owner_id", "")).is_empty():
		var inst: Dictionary = RealmRepository.instantiate_realm_for_off_map_force(
			campaign_id, "", {}, calendar_day)
		resolution["new_owner_id"] = StringUtils.s(inst.get("head_character_id"))
	# Loot-and-scoot: spawn a placeholder local NPC and patch new_owner_id.
	elif String(resolution.get("outcome", "")) == RealmRepository.OUTCOME_LOOTED_LOCAL_SUCCESSION:
		resolution["new_owner_id"] = RealmRepository.spawn_local_succession_npc(
			domain_id, calendar_day)
	# Forward to LifecycleHandler. The return value MUST be checked: conquest can
	# be refused (missing new_owner_id, or the §7.4 beastman eligibility gate),
	# and until 2026-07-31 this call discarded the bool so a refusal failed
	# silently — the siege reported a capture while the domain never changed
	# hands. conquer_domain is now all-or-nothing, so `false` means no state
	# changed and the caller is responsible for the fallback.
	var conquered: bool = LifecycleHandler.conquer_domain(
		domain_id, calendar_day,
		String(resolution.get("outcome", "")),
		String(resolution.get("new_owner_id", "")),
		int(resolution.get("pillage_severity", 0)),
		{"siege_id": siege_id, "siege_outcome": outcome,
		 "attacker_owner_id": attacker_owner_id,
		 "attacker_realm_id": String(resolution.get("attacker_realm_id", ""))})
	if not conquered:
		push_error(
			("DomainHandlers._on_siege_concluded: conquest REFUSED for domain %s "
			+ "(siege %s, outcome %s, resolved %s, new_owner '%s'). The siege was "
			+ "won but ownership did not transfer and no state changed. The siege "
			+ "bridge does not yet pre-check EstablishDomainFlow's eligibility "
			+ "matrix and re-route to LOOTED_LOCAL_SUCCESSION / SALTED_TO_RUIN — "
			+ "see docs/domain-acquisition-audit-2026-07-28.md "
			+ "(siege-bridge-still-bypasses-eligibility-validator).") % [
				domain_id, siege_id, outcome,
				String(resolution.get("outcome", "")),
				String(resolution.get("new_owner_id", ""))])


## Phase 11D-prereq.0b: pick the attacker's intent (`occupy` / `loot_and_scoot`
## / `salt_the_earth`) based on attacker alignment + relation to defender.
## v1 heuristic — refined later when factions/diplomacy expand:
##   * Hostile relation + chaotic alignment + overwhelming BR ratio → salt_the_earth
##   * Hostile relation + alignment-mismatch → loot_and_scoot
##   * Otherwise → occupy
##
## For v1, without BR-ratio tracking in the siege row, we default to
## INTENT_OCCUPY unless explicit signals tell us otherwise. Future polish
## per the plan §11D-prereq.0b notes.
func _derive_attacker_intent(
	_siege: Dictionary,
	attacker_owner_id: String,
	defender_domain_id: String,
) -> String:
	# v1 default: occupy. Future heuristic consumes realm alignment + relation
	# disposition + BR ratio to pick salt-the-earth or loot-and-scoot.
	if attacker_owner_id.is_empty() or defender_domain_id.is_empty():
		return RealmRepository.INTENT_OCCUPY
	var attacker_realm: Dictionary = RealmRepository.get_realm_for_character(attacker_owner_id)
	var defender_realm: Dictionary = RealmRepository.get_realm_for_domain(defender_domain_id)
	if attacker_realm.is_empty() or defender_realm.is_empty():
		return RealmRepository.INTENT_OCCUPY
	var disposition: String = RealmRepository.get_relation(
		String(attacker_realm.get("id", "")),
		String(defender_realm.get("id", "")))
	var attacker_alignment: String = String(attacker_realm.get("alignment", ""))
	# Heuristic: chaotic + hostile → salt_the_earth.
	if disposition == RealmRepository.DISP_HOSTILE and attacker_alignment == "chaotic":
		return RealmRepository.INTENT_SALT_THE_EARTH
	# Hostile but not chaotic → loot-and-scoot.
	if disposition == RealmRepository.DISP_HOSTILE:
		return RealmRepository.INTENT_LOOT_AND_SCOOT
	# Otherwise → occupy.
	return RealmRepository.INTENT_OCCUPY


## Translate a Phase 1 stronghold-destroyed signal into a domain-side
## lifecycle event. Listens for cause == "siege" (Phase 9A); other causes
## (voluntary demolish / abandonment-cleanup) bypass this hook because
## they're already routed through their own lifecycle entry points.
func _on_stronghold_destroyed(stronghold_id: String, cause: String) -> void:
	if cause != "siege":
		return
	# Look up the stronghold's domain. The strongholds table carries
	# domain_id directly.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT domain_id FROM strongholds WHERE id = ?", [stronghold_id]
	) or CampaignRepository.db.query_result.is_empty():
		return
	var domain_id: String = String(CampaignRepository.db.query_result[0].get("domain_id", ""))
	if domain_id.is_empty():
		return
	var calendar_day: int = _calendar_day_from_date(Timekeeping.get_date())
	LifecycleHandler.mark_stronghold_collapsed(domain_id, stronghold_id, calendar_day)


## Phase 11C: character_died → succession-pending sweep over the deceased's
## domains. Idempotent. Domains already in abandoned / lost_to_foreign are
## skipped by the handler.
func _on_character_died(character_id: String) -> void:
	if character_id.is_empty():
		return
	var calendar_day: int = _calendar_day_from_date(Timekeeping.get_date())
	RulerDeathHandler.handle_ruler_death(character_id, calendar_day)


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Calculate rounds from now until the start of the next calendar month.
func _rounds_until_next_month() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var current_day: int = date.get("day", 1)  # 1-28
	var days_remaining: int = Timekeeping.DAYS_PER_MONTH - current_day + 1
	# Subtract the elapsed portion of today.
	var hour: int = date.get("hour", 0)
	var minute: int = date.get("minute", 0)
	var rnd: int = date.get("round", 0)
	var rounds_elapsed_today: int = (hour * Timekeeping.ROUNDS_PER_HOUR) + \
		(minute * Timekeeping.ROUNDS_PER_MINUTE) + rnd
	return (days_remaining * Timekeeping.ROUNDS_PER_DAY) - rounds_elapsed_today


## Phase 11D.5 polish helper — sum of active tribal_warrior troop_unit counts
## for this domain. Used by the population-growth refill hook to enforce the
## pool invariant `available + levied <= peasant_families`.
##
## Migration 213: counts the FREE allotment only. Excess-levy warriors
## (`ax_domains_of_chaos.xml:399`) are peasants pulled off the land rather than
## draws on the 1-per-family allotment, so including them would shrink the
## refill cap by warriors that were never charged against it.
func _sum_active_tribal_warrior_count(domain_id: String) -> int:
	if domain_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(count), 0) AS total
		FROM troop_units
		WHERE assigned_domain_id = ?
		  AND source_type = 'tribal_warrior'
		  AND status = 'active'
		  AND is_excess_levy = 0
	""", [domain_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("total", 0))


## RAW: rules/ax_domains_of_chaos.xml:402 — "If population is reduced, some
## tribal warriors must be released to return to their villages."
##
## Implements gdd-tribal-warriors.md §3.2's release order:
##   1. excess = available + levied − new peasant_families ceiling.
##   2. Release dormant warriors first (decrement available_tribal_warriors).
##   3. If excess remains, force stand-down of LEVIED warriors, lowest tier
##      first (untrained → average → veteran), decrementing troop_units.count
##      until the excess is absorbed. A row driven to 0 is marked departed.
##
## Step 3 is the part that surprises: RAW says warriors "must be released",
## and the GDD reads that as reaching into units already in service when the
## dormant pool cannot cover the shortfall. A clanhold that loses half its
## families genuinely cannot keep a full levy in the field.
##
## Returns {new_available, released_dormant, released_levied,
## released_excess_over_cap, total} — or an empty dict when nothing needed
## releasing (so the caller can skip the write).
func _release_tribal_warriors_for_population_loss(domain_id: String,
		new_peasants: int, prior_available: int, levied: int,
		calendar_day: int) -> Dictionary:
	# The free-allotment overage and the excess-levy overage are INDEPENDENT:
	# a shrink can breach one, the other, or both. Compute the free side first
	# but do not early-return on it, or a domain whose free pool still fits
	# would silently keep excess warriors above its shrunken ceiling.
	var overage: int = (prior_available + levied) - new_peasants
	var from_dormant: int = 0
	var from_levied: int = 0
	var new_available: int = prior_available

	if overage > 0:
		# Step 2 — dormant warriors first.
		from_dormant = mini(overage, prior_available)
		new_available = prior_available - from_dormant
		var remaining: int = overage - from_dormant
		# Step 3 — force stand-down of levied units, lowest tier first.
		if remaining > 0:
			from_levied = _force_stand_down_tribal_warriors(domain_id, remaining, calendar_day)

	# The excess-levy ceiling is derived from peasant_families too
	# (daw_armies_recruitment.xml:428, 2 per 10), so a shrinking population
	# lowers it. Warriors above the NEW ceiling are released as well — this is
	# enforcement of the standing cap, separate from the §3.2 free-allotment
	# release above, and it fires even when the free side needed no release.
	var from_excess: int = _trim_excess_levy_to_cap(domain_id, new_peasants, calendar_day)

	var total: int = from_dormant + from_levied + from_excess
	if total <= 0:
		return {}

	if EventBus.has_signal("tribal_warriors_released_for_population_loss"):
		EventBus.emit_signal("tribal_warriors_released_for_population_loss",
			domain_id, total)

	var detail: String = "Population fell to %d families; %d tribal warriors released to their villages (%d dormant, %d from units in service" % [
		new_peasants, total, from_dormant, from_levied]
	detail += ", %d over the levy cap)." % from_excess if from_excess > 0 else ")."
	DepartureLogRecorder.record(
		_campaign_id, domain_id, calendar_day,
		"tribal_warriors_released_for_population_loss",
		detail,
		{
			"peasant_families": new_peasants,
			"released_total": total,
			"released_dormant": from_dormant,
			"released_levied": from_levied,
			"released_excess_over_cap": from_excess,
			"available_before": prior_available,
			"available_after": new_available,
			"levied_before": levied,
		})

	return {
		"new_available": new_available,
		"released_dormant": from_dormant,
		"released_levied": from_levied,
		"released_excess_over_cap": from_excess,
		"total": total,
	}


## Release excess-levy warriors above the ceiling a domain of
## [param new_peasants] families can sustain (RAW
## daw_armies_recruitment.xml:428 — 2 per 10 families, borrowed for the tribal
## excess per ax_domains_of_chaos.xml:399). Returns the number released.
func _trim_excess_levy_to_cap(domain_id: String, new_peasants: int,
		calendar_day: int) -> int:
	var cap: int = LevyPenaltyCalculator.levy_cap_for_families(new_peasants)
	var current: int = TribalWarriorRegistry.excess_levied_count(domain_id)
	var over: int = current - cap
	if over <= 0:
		return 0
	return _stand_down_tribal_rows(domain_id, over, calendar_day, 1)


## Decrement FREE-allotment tribal-warrior counts by up to [param needed]
## warriors, lowest tier first per gdd-tribal-warriors.md §3.2.
func _force_stand_down_tribal_warriors(domain_id: String, needed: int,
		calendar_day: int) -> int:
	return _stand_down_tribal_rows(domain_id, needed, calendar_day, 0)


## Shared row-walker for both release paths. [param excess_flag] selects which
## population to draw from: 0 = the free 1-per-family allotment (§3.2 release),
## 1 = excess-levy warriors (standing-cap enforcement). Rows driven to 0 are
## marked departed with departure_kind='released_for_population_loss'.
## Returns the number of warriors actually released.
func _stand_down_tribal_rows(domain_id: String, needed: int,
		calendar_day: int, excess_flag: int) -> int:
	if needed <= 0 or domain_id.is_empty():
		return 0
	# ORDER BY tier rank: untrained (0) → average (1) → veteran (2). Veterans
	# are the last warriors a chieftain sends home. `id` breaks ties so the
	# selection is deterministic across runs.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, count, tier
		FROM troop_units
		WHERE assigned_domain_id = ?
		  AND source_type = 'tribal_warrior'
		  AND status = 'active'
		  AND count > 0
		  AND is_excess_levy = ?
		ORDER BY CASE tier
			WHEN 'untrained' THEN 0
			WHEN 'average' THEN 1
			WHEN 'veteran' THEN 2
			ELSE 3 END, id
	""", [domain_id, excess_flag]):
		return 0
	var rows: Array = CampaignRepository.db.query_result.duplicate()
	var released: int = 0
	for row: Dictionary in rows:
		if released >= needed:
			break
		var unit_id: String = str(row.get("id", ""))
		var count: int = int(row.get("count", 0))
		if unit_id.is_empty() or count <= 0:
			continue
		var take: int = mini(count, needed - released)
		var new_count: int = count - take
		var updates: Dictionary = {"count": new_count}
		if new_count <= 0:
			updates["status"] = "departed"
			updates["departure_kind"] = "released_for_population_loss"
			updates["departure_calendar_day"] = calendar_day
		TroopUnitRepository.update_unit(unit_id, updates)
		released += take
	return released


## The domain tick's SINGLE monthly Unit Loyalty pass, for every troop unit
## assigned to this domain. Collects each calamity that is decided on a monthly
## boundary and makes ONE roll per unit.
##
## ── The three monthly calamities ────────────────────────────────────────────
##
## **Three months without spoils** (TRIBAL WARRIORS ONLY) — Phase 11D.5 per
## gdd-tribal-warriors.md §7. Increments `months_without_qualifying_spoils` on
## each active tribal_warrior unit. The counter resets to 0 when qualifying
## spoils land (`SiegeSpoilsResolver.apply_spoils_to_tribal_warriors`) or when
## the roll fires. RAW `ax_domains_of_chaos.xml:456` prints this as a MORALE
## roll; per Jedidiah (2026-08-01) that is a known RAW error and later errata
## make it a straight LOYALTY roll. No morale-roll step, no cascade — it is one
## more calamity kind (`UnitLoyaltyResolver.CALAMITY_NO_SPOILS`). No other
## source type accrues it; the schema comment on the column says as much.
##
## **A month without pay** (EVERY source type) — `ax_domains_of_chaos.xml:455`,
## `daw_armies_recruitment.xml:98`. [param unpaid_unit_ids] is
## `TroopPayShortfallResolver`'s ex-post-facto designation (conventions §132).
##
## **A season of continuous campaigning** (MILITIA ONLY) —
## `daw_armies_recruitment.xml:459`, "Militia also treat each season of
## continuous campaigning as a calamity." The only calamity in the game that
## depends on elapsed time rather than an event, so it needs an anchor:
## `troop_units.campaigning_since_calendar_day` (migration 214), maintained
## entirely here. A militia unit found `on_campaign` with no anchor gets one; a
## unit no longer campaigning has its anchor cleared, which is what makes the
## stretch "continuous"; a unit that has held the anchor for
## `UnitLoyaltyResolver.SEASON_DAYS` takes the calamity and re-anchors so the
## next season is counted from here. Keeping the anchor in one place means no
## muster / call-to-arms / extraction path has to remember to maintain it — the
## same live-derivation reasoning as §133's levy penalty. The cost is that a
## stretch is only ever noticed on a tick boundary, which under-counts by at
## most a month and never over-counts.
##
## ── Why one roll and not three ──────────────────────────────────────────────
##
## RAW `daw_armies_recruitment.xml:100` — "If troops are suffering more than one
## calamity at once, apply -2 to the loyalty roll per calamity after the first"
## — so a militia company three months into a campaign that also went unpaid is
## suffering two calamities at once, not two separate tests. Separate
## `roll_loyalty` calls would give it independent chances to depart at full
## strength: harsher in aggregate than the printed rule, and simply not it.
## Per conventions §132, when adding a trigger point check whether an existing
## one shares its tick.
##
## Who rolls is `UnitLoyaltyResolver.rolls_loyalty` — the RAW source-type gate
## (:99 / :353 / :458 / :477 / :611 / ax:454; vassal troops have no rule of
## their own) plus the :483 religious-fanatic exemption. This function decides
## only WHICH CALAMITIES apply, per conventions §70/§131.
func _tick_unit_loyalty(domain_id: String, calendar_day: int,
		unpaid_unit_ids: Array = []) -> void:
	if domain_id.is_empty():
		return
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, source_type, assignment_kind, is_religious_fanatic,
		       months_without_qualifying_spoils, campaigning_since_calendar_day
		FROM troop_units
		WHERE assigned_domain_id = ?
		  AND status = 'active'
	""", [domain_id]):
		return
	if CampaignRepository.db.query_result.is_empty():
		return
	for row: Dictionary in CampaignRepository.db.query_result.duplicate():
		# Skip units RAW never asks to roll — vassal troops and religious
		# fanatics (:483). `roll_loyalty` would reject them anyway, but the
		# trigger SIGNALS below fire before it is called, and announcing that a
		# fanatic's loyalty is being tested when RAW says it never is would be
		# the same false assertion §131 bars from the departure log. The two
		# counters are skipped with them: neither means anything for a unit that
		# cannot roll.
		if not UnitLoyaltyResolver.rolls_loyalty(row):
			continue
		var unit_id: String = str(row.get("id", ""))
		var source_type: String = str(row.get("source_type", ""))
		var calamities: Array[String] = []

		# --- Tribal warriors: the 3-month spoils stretch. --------------------
		if source_type == "tribal_warrior":
			var prior: int = int(row.get("months_without_qualifying_spoils", 0))
			var next: int = prior + 1
			TroopUnitRepository.update_unit(unit_id, {
				"months_without_qualifying_spoils": next,
			})
			if next >= 3:
				calamities.append(UnitLoyaltyResolver.CALAMITY_NO_SPOILS)
				# The `tribal_warriors_morale_check_triggered` signal and
				# departure-log event type keep their migration-129 names — they
				# mark "the 3-month spoils trigger fired", and renaming them
				# would cost a migration + a schema CHECK rebuild + a UI
				# filter-dropdown change for a cosmetic gain. The name is a
				# wart; the behaviour is the errata'd RAW.
				if EventBus.has_signal("tribal_warriors_morale_check_triggered"):
					EventBus.emit_signal("tribal_warriors_morale_check_triggered",
						unit_id, "three_months_without_qualifying_spoils")
				DepartureLogRecorder.record(
					_campaign_id, domain_id, calendar_day,
					"tribal_warriors_morale_check_triggered",
					"%d months without spoils worth their wages; the warriors' loyalty is tested." % next,
					{
						"troop_unit_id": unit_id,
						"months_without_qualifying_spoils": next,
						"reason": "three_months_without_qualifying_spoils",
					})

		# --- Militia: a season of continuous campaigning (RAW :459). ---------
		if source_type == "militia":
			if _advance_campaigning_anchor(row, calendar_day):
				calamities.append(UnitLoyaltyResolver.CALAMITY_CONTINUOUS_CAMPAIGN)
				if EventBus.has_signal("tribal_warriors_morale_check_triggered"):
					EventBus.emit_signal("tribal_warriors_morale_check_triggered",
						unit_id, UnitLoyaltyResolver.CALAMITY_CONTINUOUS_CAMPAIGN)

		# --- Everyone: a month without pay (conventions §132). ---------------
		if unpaid_unit_ids.has(unit_id):
			calamities.append(UnitLoyaltyResolver.CALAMITY_UNPAID)
			# Reuse the migration-129 trigger signal rather than mint a new one:
			# its `reason` parameter exists precisely to distinguish which
			# calamity fired, and it has no consumers to confuse. No matching
			# departure-log line — per conventions §131 only DEPARTURES are
			# chronicled, and roll_loyalty writes that line itself with the
			# calamity list in its metadata. Adding a survived-calamity event
			# type would also cost a migration to widen the CHECK.
			if EventBus.has_signal("tribal_warriors_morale_check_triggered"):
				EventBus.emit_signal("tribal_warriors_morale_check_triggered",
					unit_id, UnitLoyaltyResolver.CALAMITY_UNPAID)

		if calamities.is_empty():
			continue
		# roll_loyalty applies its own source-type and religious-fanatic gates
		# and resets the spoils counter itself, so a unit that survives starts
		# its clock over instead of re-rolling every subsequent month on the
		# same stretch.
		UnitLoyaltyResolver.roll_loyalty(
			unit_id,
			calamities,
			calendar_day)


## Maintain the RAW :459 continuous-campaigning anchor for one militia [param row]
## and report whether a full season has now elapsed under arms.
##
## Three states, and the "not campaigning" one is what makes the stretch
## CONTINUOUS rather than cumulative: a militia unit that comes off campaign for
## a single month loses its accrued time entirely, which is the plain reading of
## ":459 continuous". Re-anchoring (rather than clearing) after a calamity fires
## is what makes it "EACH season" — a unit kept in the field for a year takes
## the calamity roughly four times, not once.
func _advance_campaigning_anchor(row: Dictionary, calendar_day: int) -> bool:
	var unit_id: String = str(row.get("id", ""))
	var anchor: int = int(row.get("campaigning_since_calendar_day", 0))
	if str(row.get("assignment_kind", "")) != "on_campaign":
		if anchor != 0:
			TroopUnitRepository.update_unit(unit_id, {
				"campaigning_since_calendar_day": 0,
			})
		return false
	if anchor <= 0:
		# First tick under arms. Anchor from TODAY rather than back-dating to
		# the muster: the muster day is not recorded anywhere the tick can see,
		# and erring late keeps the rule from firing on time a unit never served.
		TroopUnitRepository.update_unit(unit_id, {
			"campaigning_since_calendar_day": maxi(1, calendar_day),
		})
		return false
	if calendar_day - anchor < UnitLoyaltyResolver.SEASON_DAYS:
		return false
	TroopUnitRepository.update_unit(unit_id, {
		"campaigning_since_calendar_day": maxi(1, calendar_day),
	})
	return true
