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
		}

	var domain_results: Array = []
	for domain_data: Dictionary in domains:
		# Phase 11B: skip terminal-state domains entirely. abandoned /
		# lost_to_foreign rows are preserved for the audit history but no
		# longer run revenue / expense / morale / growth resolution.
		var lifecycle_state: String = String(domain_data.get(
			"lifecycle_state", LifecycleHandler.STATE_ACTIVE))
		if lifecycle_state == LifecycleHandler.STATE_ABANDONED \
			or lifecycle_state == LifecycleHandler.STATE_SALTED_TO_RUIN:
			continue
		var result := _resolve_domain_month(domain_data, calendar_day)
		domain_results.append(result)
		_save_domain(domain_data, result)
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

	return {
		"auto_pause": true,
		"pause_reason": "Domain monthly report — %s" % month_name,
		"next_events": next_events,
		"presentation": {
			"type": "domain_monthly_report",
			"month": month_name,
			"domain_results": domain_results,
		},
		"commerce_results": commerce_results,
		"syndicate_results": syndicate_results,
		"venture_results": venture_results,
	}


# ---------------------------------------------------------------------------
# Domain resolution (per ACKS rules — RAW-correct as of Domain Phase 0)
# ---------------------------------------------------------------------------

## Resolve one month for a single domain by delegating to the Phase 0 resolvers.
## All math lives in the resolvers; this method's job is orchestration plus
## ledger writes plus the random event roll.
func _resolve_domain_month(domain_data: Dictionary, calendar_day: int) -> Dictionary:
	var domain_id: String = domain_data.get("id", "")
	var domain_name: String = domain_data.get("name", "Unknown")
	var territory: String = String(domain_data.get("territory_type", "wilderness"))

	# --- Context: hexes, stronghold, ruler, additional garrison ---
	var hexes: Array = CampaignRepository.get_domain_hexes(domain_id)
	var hex_count: int = hexes.size()
	# Strongholds remain gp-denominated (their own subsystem); convert at the
	# boundary to cp for the domain treasury layer.
	var stronghold_value_cp: int = _stub_stronghold_value(domain_id) * 100
	# Stronghold sufficiency uses the effective hex count (owned + intervening)
	# per RAW §noncontiguous_domains L95-98. For contiguous domains this equals
	# `hex_count`; for noncontiguous ones it adds the connecting hexes between
	# components so the minimum scales with the territory the strongholds must
	# secure, not just the territory directly held.
	var sufficiency_hex_count: int = StrongholdRepository.get_effective_hex_count_for_domain(domain_id)
	var stronghold_minimum_cp: int = _classification_minimum_cp(territory, sufficiency_hex_count)
	var ruler: Dictionary = _build_ruler_context(domain_data)

	# Phase 5 garrison wiring (2026-05-16): aggregate the actual garrison-assigned
	# troop_units via GarrisonExpenditureCalculator. RAW §garrison L228-231:
	# unpaid faithful followers + trained militia + scutage troops + lord-favor
	# troops count toward the garrison cost by gp value even when no money
	# changes hands. The calculator handles that distinction and returns the
	# total cp value of garrison + the morale incentive bonus + below-minimum
	# penalty. We feed the paid portion into the expense calculator (which
	# clamps to the universal minimum) and the morale signals into the resolver.
	var garrison: Dictionary = GarrisonExpenditureCalculator.compute_from_domain(domain_data)
	var actual_garrison_paid_cp: int = int(garrison.get("total_paid_cp", 0))
	var additional_garrison_cp_per_family: int = int(garrison.get("morale_incentive_bonus", 0))

	# Phase 7: tribute_in via RealmAggregator + TributeCalculator. The ruler
	# of THIS domain may have direct vassals; tribute flows from each vassal's
	# realm to this ruler at the rate dictated by the RAW table reduced by the
	# efficiency factor.
	var tribute_aggregate: Dictionary = _compute_tribute_in_for_ruler(
		_str_field(domain_data, "owner_character_id"))
	var tribute_in: int = int(tribute_aggregate.get("total_received_gp", 0))

	# Phase 7: tribute_out_owed is recomputed each month based on the vassal
	# domain's realm aggregate, so that domain growth/shrinkage flows naturally
	# into the tribute owed. We mutate the local domain_data dict so the expense
	# calculator (which reads tribute_out_owed) picks it up. Persistence of the
	# updated value happens in _save_domain.
	var tribute_out: int = _compute_tribute_out_for_vassal_domain(domain_data)
	domain_data["tribute_out_owed"] = tribute_out

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
	var faith_ruler_morale_bonus: int = int(
		faith_modifiers.get("consecrate_ruler_base_morale_bonus", 0))

	# --- Resolvers: revenue → expenses → morale → growth → classification ---
	var revenue := DomainRevenueCalculator.calculate_monthly_revenue(
		domain_data, hexes, stronghold_value_cp, stronghold_minimum_cp, tribute_in)

	# Phase 10A.2: apply consecrate_fields bonus to revenue total + subcategory.
	if faith_land_value_bonus != 0 and not revenue.get("income_gate_active", false):
		var peasant_families: int = int(domain_data.get("peasant_families", 0))
		var bonus_total: int = faith_land_value_bonus * peasant_families
		revenue["consecrate_fields_bonus"] = bonus_total
		revenue["total"] = int(revenue.get("total", 0)) + bonus_total
		FaithMonthlyResolver.apply_pending_consecrate_fields(
			faith_modifiers.get("consecrate_fields_fired_effect_ids", []))
	var expenses := DomainExpenseCalculator.calculate_monthly_expenses(
		domain_data, actual_garrison_paid_cp, revenue["income_gate_active"])

	# Phase 8: ongoing scutage owed by THIS domain (when D is a vassal). RAW
	# §favors_and_duties L362: "Scutage: vassal pays 1gp per family in the
	# realm in place of military service; counts as garrison expense for the
	# vassal." We add scutage to the expenses dict as a subcategory and bump
	# the total so the existing ledger writer + monthly settlement flow
	# treats it like any other expense.
	# Scutage is RAW 1 gp/family; the helper returns cp internally.
	var scutage_cp: int = _compute_active_scutage_cp_for_domain(domain_data)
	if scutage_cp > 0:
		expenses["scutage"] = scutage_cp
		expenses["total"] = int(expenses.get("total", 0)) + scutage_cp

	var base_morale := DomainMoraleResolver.resolve_base_morale(
		domain_data, ruler, revenue["total"],
		stronghold_value_cp, stronghold_minimum_cp,
		additional_garrison_cp_per_family)
	# Phase 10A.2: consecrate_ruler 12-month buff applies +1 / -1 to base morale
	# while the window is active.
	if faith_ruler_morale_bonus != 0:
		base_morale = int(base_morale) + faith_ruler_morale_bonus

	var event_modifiers_sum: int = _event_modifiers_sum(domain_data, garrison)
	var repression_bonus: int = int(domain_data.get(
		"repression_cp_per_family_this_month", 0))
	var is_repressed: bool = bool(domain_data.get(
		"is_repressed_this_month", 0))
	var morale_roll: int = DiceSystem.roll_digital(6, 2, 0, "domain_morale").modified_total
	var morale := DomainMoraleResolver.resolve_current_morale(
		domain_data, base_morale, event_modifiers_sum,
		repression_bonus, is_repressed, morale_roll)

	var morale_tier: String = DomainMoraleResolver.morale_tier(morale["current_morale"])
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

	# Phase 11D.5 polish: tribal-warrior retention tick per
	# gdd-tribal-warriors.md §7. For each active tribal-warrior troop_unit
	# in this domain, increment `months_without_qualifying_spoils`. When the
	# counter hits 3, fire `tribal_warriors_morale_check_triggered` so the
	# downstream morale-roll handler can resolve loyalty (signal-only stub
	# in v1; the full roll mechanic lands when the morale-roll handler is
	# wired in a future polish). Units that received qualifying spoils
	# in-month have already had their counter reset to 0 via
	# SiegeSpoilsResolver.apply_spoils_to_tribal_warriors; the increment
	# here brings them back to 1 on the following month, which represents
	# "one month has now passed since last qualifying credit" — the
	# semantically correct "consecutive months without" reading.
	_tick_tribal_warrior_retention(domain_id, calendar_day)

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

	# Phase 8: Favors & Duties monthly roll for each active vassal of THIS
	# ruler. RAW §favors_and_duties L352 ("Each month, a vassal ruler rolls
	# once on the Favors and Duties table"). Each roll dispatches via
	# FavorsDutiesResolver, which writes the obligation, applies mechanical
	# effects (gift/loan treasury transfers; scutage as ongoing expense), and
	# emits favor_or_duty_resolved.
	var favors_duties: Array = _resolve_favors_and_duties(domain_data, calendar_day)

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
		# Phase 8: per-vassal Favors & Duties results.
		"favors_duties": favors_duties,
		# Phase 9A: encounter / bandit / challenger summaries.
		"encounter_summary": encounter_summary,
		"bandit_summary": bandit_summary,
		"challenger_summary": challenger_summary,
		# Phase 10B.1a: Magical Research monthly summary.
		"magic_research_summary": mr_summary,
		# Urban Growth Stocking — Stage B per `gdd-urban-growth-stocking.md`
		# §6.2. One result dict per settlement under this domain.
		"settlement_growth": settlement_growth_results,
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
func _save_domain(domain_data: Dictionary, result: Dictionary) -> void:
	var domain_id: String = domain_data.get("id", "")
	if domain_id.is_empty():
		return

	var net: int = result.get("net_income", 0)
	var prior_peasants: int = int(domain_data.get("peasant_families", 0))
	var new_peasants: int = maxi(0, prior_peasants + int(result.get("population_growth", 0)))
	var class_change: Dictionary = result.get("classification_change", {})
	var new_territory: String = String(class_change.get(
		"new_classification", domain_data.get("territory_type", "wilderness")))
	var prior_treasury: int = int(domain_data.get("treasury_cp", 0))
	var new_treasury: int = prior_treasury + net

	# Phase 3: administer_domain bonus = +5% domain XP per acore_axioms
	# §administration L499. Apply here, then reset the flag below.
	var domain_xp: int = maxi(0, net)
	if bool(domain_data.get("administer_domain_completed_this_month", 0)):
		domain_xp = int(round(domain_xp * 1.05))

	var fields := {
		"morale": result.get("current_morale", domain_data.get("morale", 0)),
		"peasant_families": new_peasants,
		"treasury_cp": new_treasury,
		"revenue_cp": result.get("revenue", 0),
		"expenses_cp": result.get("total_expenses", 0),
		"net_income_cp": net,
		"domain_xp_this_month": domain_xp,
		"territory_type": new_territory,
		# Phase 7: tribute_out_owed (recomputed each month from realm aggregate).
		"tribute_out_owed": int(result.get("tribute_out_owed", 0)),
		# Reset Phase 3 transient modifiers after consumption.
		"administer_domain_completed_this_month": 0,
		"pending_investment_cp": 0,
	}

	# Phase 11D.5 polish: population-growth refill of the tribal-warrior pool.
	# Per gdd-tribal-warriors.md §3 + §5.5: when peasant_families grows on a
	# clanhold, available_tribal_warriors grows with it (capped at
	# `peasant_families - currently_levied` per the pool invariant). The slack
	# = peasant_families - available - levied tracks the dead-not-yet-replaced
	# count; population growth fills the slack first.
	if String(domain_data.get("domain_style", "civilized")) == "clanhold":
		var population_growth_count: int = new_peasants - prior_peasants
		if population_growth_count > 0:
			var prior_available: int = int(domain_data.get("available_tribal_warriors", 0))
			# Sum currently-levied tribal_warrior unit counts to enforce the
			# invariant cap. We could call TribalWarriorRegistry.pool_for_domain
			# but that re-reads the domain row; the count we need is just the
			# active tribal_warrior troop_units sum.
			var levied: int = _sum_active_tribal_warrior_count(domain_id)
			var cap: int = new_peasants - levied
			var proposed: int = prior_available + population_growth_count
			var new_available: int = clampi(proposed, 0, maxi(0, cap))
			if new_available != prior_available:
				fields["available_tribal_warriors"] = new_available
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

## Sum the cp_value of completed strongholds in a domain. Phase 1 wired this
## via `StrongholdRepository.get_stronghold_value_for_domain`; Phase 2+
## may add caching or contiguous-territory enforcement at this seam.
func _stub_stronghold_value(domain_id: String) -> int:
	return StrongholdRepository.get_stronghold_value_for_domain(domain_id)


## Per-hex classification minimums per `acore_axioms` §minimum_stronghold_value
## L88-94. RAW gp values × 100 to express as cp.
## Total = per_hex_minimum_cp × hex_count.
func _classification_minimum_cp(territory_type: String, hex_count: int) -> int:
	var per_hex_cp: int = 0
	match territory_type:
		"civilized":   per_hex_cp = 1500000   # RAW 15,000 gp
		"borderlands": per_hex_cp = 2250000   # RAW 22,500 gp
		"wilderness":  per_hex_cp = 3200000   # RAW 32,000 gp
		_:             per_hex_cp = 3200000
	return per_hex_cp * maxi(1, hex_count)


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


## Sum the morale roll modifiers driven by the current month's domain settings.
## Per §monthly_event_modifiers L488-499. Phase 0 wires up the modifiers we can
## compute deterministically (tax, liturgy, tithes, garrison underpayment).
## Pillage / occupation / new-religion are deferred to Phase 8 / Phase 10.
##
## [param garrison_summary] is GarrisonExpenditureCalculator's output for this
## domain — provides `gp_below_minimum_per_family` for the garrison
## underpayment penalty per §monthly_event_modifiers L486.
func _event_modifiers_sum(domain_data: Dictionary, garrison_summary: Dictionary) -> int:
	var sum: int = 0
	# Rates are cp/family per the 2026-05-15 currency-precision pass.
	# RAW baseline is "1 gp/family" = 100 cp/family; morale modifier fires
	# per gp deviation, so divide the cp delta by 100.
	var liturgy_rate_cp: int = int(domain_data.get("liturgy_rate_cp_per_family", 100))
	sum += (liturgy_rate_cp - 100) / 100
	# Tax bonus/penalty per L494-495 (2 gp/fam baseline = 200 cp/fam).
	var tax_rate_cp: int = int(domain_data.get("tax_rate_cp_per_family", 200))
	sum += (200 - tax_rate_cp) / 100
	# Garrison underpayment: -1 morale per gp/family below the universal RAW
	# minimum, per §monthly_event_modifiers L486. GarrisonExpenditureCalculator
	# pre-computes the ceiling of (min_cp_per_family - actual_cp_per_family)/100.
	sum -= int(garrison_summary.get("gp_below_minimum_per_family", 0))
	# Phase 3: administer_domain handler sets this column on completion;
	# +1 morale roll modifier per `acore_axioms` §administration L499.
	if bool(domain_data.get("administer_domain_completed_this_month", 0)):
		sum += 1
	# Phase 9C E4: refuse-battle morale penalty from active npc_challenger
	# threats per RAW acore_axioms §effects_of_morale L627-630 (-4 if ruler
	# refused battle and challenger is now pillaging). Sum across all active
	# challenger threats for this domain (typically just one).
	var domain_id: String = String(domain_data.get("id", ""))
	if not domain_id.is_empty():
		var challenger: Dictionary = DomainThreatRepository.get_active_challenger_for_domain(domain_id)
		if not challenger.is_empty():
			sum -= int(challenger.get("morale_penalty", 0))
	# Phase 9C polish round 4 2026-05-09: settled-lair dungeon morale penalty
	# per RAW ax_domain_level_encounters §dungeons L312-321. Sum XP × count
	# across active settled_lair threats, divide by total families, banker's
	# round → subtract from event modifiers sum.
	if not domain_id.is_empty():
		var peasants: int = int(domain_data.get("peasant_families", 0))
		var urban: int = int(domain_data.get("urban_families", 0))
		var families: int = peasants + urban
		if families > 0:
			var lair_penalty: int = DomainEncounterResolver.compute_settled_lair_morale_penalty(
				domain_id, families)
			sum -= lair_penalty
	return sum


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

## Compute the gp THIS ruler will receive from active vassals this month.
## Sum each vassal's tribute_base_gp (from the vassal's own realm size), then
## apply the liege's efficiency factor (based on liege's direct_vassal_count).
func _compute_tribute_in_for_ruler(ruler_character_id: String) -> Dictionary:
	var summary: Dictionary = {
		"total_received_gp": 0,
		"per_vassal": [],
		"direct_vassal_count": 0,
		"efficiency_factor": 1.0,
	}
	if ruler_character_id.is_empty():
		return summary
	var assignments: Array = VassalRepository.list_active_for_liege(ruler_character_id)
	var direct_count: int = assignments.size()
	summary["direct_vassal_count"] = direct_count
	var efficiency: float = TributeCalculator.efficiency_factor(direct_count)
	summary["efficiency_factor"] = efficiency
	if direct_count <= 0 or efficiency <= 0.0:
		return summary
	var total: int = 0
	for assn in assignments:
		var vassal_char: String = String(assn.get("vassal_character_id", ""))
		var v_aggregate: Dictionary = RealmAggregator.aggregate(vassal_char)
		var v_realm_families: int = int(v_aggregate.get("all_realm_families", 0))
		var v_base_gp: int = TributeCalculator.compute_tribute_base_gp(v_realm_families)
		# Apply liege's efficiency factor to what arrives in liege's coffers.
		var received: int = int(round(float(v_base_gp) * efficiency))
		total += received
		summary["per_vassal"].append({
			"vassal_assignment_id": String(assn.get("id", "")),
			"vassal_character_id": vassal_char,
			"vassal_realm_families": v_realm_families,
			"base_gp": v_base_gp,
			"received_gp": received,
		})
	summary["total_received_gp"] = total
	return summary


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
	return TributeCalculator.compute_tribute_base_gp(realm_families)


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


## For each active vassal of THIS ruler, roll monthly on the Favors & Duties
## table per RAW §favors_and_duties L352-372. Returns an array of per-vassal
## resolution dicts (passes through whatever FavorsDutiesResolver returns).
##
## Phase 8 polish: also runs the loan-repayment monthly chance (RAW L365)
## and the construction auto-expenditure (RAW L361) for each active vassal.
func _resolve_favors_and_duties(domain_data: Dictionary, calendar_day: int) -> Array:
	var ruler_id: String = _str_field(domain_data, "owner_character_id")
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
		resolution["new_owner_id"] = String(inst.get("head_character_id", ""))
	# Loot-and-scoot: spawn a placeholder local NPC and patch new_owner_id.
	elif String(resolution.get("outcome", "")) == RealmRepository.OUTCOME_LOOTED_LOCAL_SUCCESSION:
		resolution["new_owner_id"] = RealmRepository.spawn_local_succession_npc(
			domain_id, calendar_day)
	# Forward to LifecycleHandler.
	LifecycleHandler.conquer_domain(
		domain_id, calendar_day,
		String(resolution.get("outcome", "")),
		String(resolution.get("new_owner_id", "")),
		int(resolution.get("pillage_severity", 0)),
		{"siege_id": siege_id, "siege_outcome": outcome,
		 "attacker_owner_id": attacker_owner_id,
		 "attacker_realm_id": String(resolution.get("attacker_realm_id", ""))})


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
func _sum_active_tribal_warrior_count(domain_id: String) -> int:
	if domain_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(count), 0) AS total
		FROM troop_units
		WHERE assigned_domain_id = ?
		  AND source_type = 'tribal_warrior'
		  AND status = 'active'
	""", [domain_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("total", 0))


## Phase 11D.5 polish — tribal-warrior retention monthly tick per
## gdd-tribal-warriors.md §7. Increments months_without_qualifying_spoils on
## each active tribal_warrior troop_unit assigned to this domain. When the
## counter reaches 3, fires `tribal_warriors_morale_check_triggered` for the
## downstream morale-roll handler (signal-only stub in v1). Counter resets
## to 0 elsewhere when qualifying spoils land (see
## SiegeSpoilsResolver.apply_spoils_to_tribal_warriors).
func _tick_tribal_warrior_retention(domain_id: String, _calendar_day: int) -> void:
	if domain_id.is_empty():
		return
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, months_without_qualifying_spoils
		FROM troop_units
		WHERE assigned_domain_id = ?
		  AND source_type = 'tribal_warrior'
		  AND status = 'active'
	""", [domain_id]):
		return
	if CampaignRepository.db.query_result.is_empty():
		return
	for row: Dictionary in CampaignRepository.db.query_result.duplicate():
		var unit_id: String = str(row.get("id", ""))
		var prior: int = int(row.get("months_without_qualifying_spoils", 0))
		var next: int = prior + 1
		TroopUnitRepository.update_unit(unit_id, {
			"months_without_qualifying_spoils": next,
		})
		if next == 3 and EventBus.has_signal("tribal_warriors_morale_check_triggered"):
			EventBus.emit_signal("tribal_warriors_morale_check_triggered",
				unit_id, "three_months_without_qualifying_spoils")
