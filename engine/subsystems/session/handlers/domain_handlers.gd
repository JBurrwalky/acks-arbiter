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


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister("domain_monthly_tick")


# ---------------------------------------------------------------------------
# Scheduling helpers
# ---------------------------------------------------------------------------

## Schedule the first domain_monthly_tick at the start of the next month.
## Should be called once during session load if the campaign has domains.
func seed_monthly_tick(scheduler: EventScheduler, party_id: String) -> void:
	var fire_time: int = _rounds_until_next_month()
	if fire_time <= 0:
		# Already at the start of a month — schedule for next month.
		fire_time = Timekeeping.DAYS_PER_MONTH * Timekeeping.ROUNDS_PER_DAY
	# Use absolute time (current + delta).
	var current_time: int = Timekeeping.get_party_time(party_id)
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

## Resolve the monthly domain cycle for all domains in the campaign.
func _handle_monthly_tick(event: ScheduledEvent) -> Dictionary:
	var domains: Array = CampaignRepository.list_campaign_domains(_campaign_id)
	if domains.is_empty():
		# No domains — don't reschedule.
		return {}

	var date: Dictionary = Timekeeping.get_date()
	var month_name := "Month %d, Year %d" % [date.get("month", 1), date.get("year", 1)]
	var calendar_day: int = _calendar_day_from_date(date)

	var domain_results: Array = []
	for domain_data: Dictionary in domains:
		var result := _resolve_domain_month(domain_data, calendar_day)
		domain_results.append(result)
		_save_domain(domain_data, result)
		_emit_signals(domain_data, result)

	# Reschedule for next month.
	var next_month_rounds: int = Timekeeping.DAYS_PER_MONTH * Timekeeping.ROUNDS_PER_DAY
	var next_events := [{
		"fire_time": event.fire_time + next_month_rounds,
		"event_type": "domain_monthly_tick",
		"owner_id": "domain_global",
		"data": {},
		"priority": ScheduledEvent.PRIORITY_ENVIRONMENTAL,
	}]

	return {
		"auto_pause": true,
		"pause_reason": "Domain monthly report — %s" % month_name,
		"next_events": next_events,
		"presentation": {
			"type": "domain_monthly_report",
			"month": month_name,
			"domain_results": domain_results,
		},
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
	var stronghold_value_gp: int = _stub_stronghold_value(domain_id)
	var stronghold_minimum_gp: int = _classification_minimum_gp(territory, hex_count)
	var ruler: Dictionary = _build_ruler_context(domain_data)
	var actual_garrison_paid_gp: int = int(domain_data.get("garrison_troops", 0)) \
		* DomainExpenseCalculator.GARRISON_MIN_GP_PER_FAMILY
	var additional_garrison_gp_per_family: int = _additional_garrison_per_family(
		domain_data, actual_garrison_paid_gp)

	# Phase 7: tribute_in via RealmAggregator + TributeCalculator. The ruler
	# of THIS domain may have direct vassals; tribute flows from each vassal's
	# realm to this ruler at the rate dictated by the RAW table reduced by the
	# efficiency factor.
	var tribute_aggregate: Dictionary = _compute_tribute_in_for_ruler(
		String(domain_data.get("owner_character_id", "")))
	var tribute_in: int = int(tribute_aggregate.get("total_received_gp", 0))

	# Phase 7: tribute_out_owed is recomputed each month based on the vassal
	# domain's realm aggregate, so that domain growth/shrinkage flows naturally
	# into the tribute owed. We mutate the local domain_data dict so the expense
	# calculator (which reads tribute_out_owed) picks it up. Persistence of the
	# updated value happens in _save_domain.
	var tribute_out: int = _compute_tribute_out_for_vassal_domain(domain_data)
	domain_data["tribute_out_owed"] = tribute_out

	# Phase 3: pending_investment_gp is set by oversee_investment handler on
	# completion (migration 068); consumed and reset here.
	var investment_gp: int = int(domain_data.get("pending_investment_gp", 0))

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
		domain_data, hexes, stronghold_value_gp, stronghold_minimum_gp, tribute_in)

	# Phase 10A.2: apply consecrate_fields bonus to revenue total + subcategory.
	if faith_land_value_bonus != 0 and not revenue.get("income_gate_active", false):
		var peasant_families: int = int(domain_data.get("peasant_families", 0))
		var bonus_total: int = faith_land_value_bonus * peasant_families
		revenue["consecrate_fields_bonus"] = bonus_total
		revenue["total"] = int(revenue.get("total", 0)) + bonus_total
		FaithMonthlyResolver.apply_pending_consecrate_fields(
			faith_modifiers.get("consecrate_fields_fired_effect_ids", []))
	var expenses := DomainExpenseCalculator.calculate_monthly_expenses(
		domain_data, actual_garrison_paid_gp, revenue["income_gate_active"])

	# Phase 8: ongoing scutage owed by THIS domain (when D is a vassal). RAW
	# §favors_and_duties L362: "Scutage: vassal pays 1gp per family in the
	# realm in place of military service; counts as garrison expense for the
	# vassal." We add scutage to the expenses dict as a subcategory and bump
	# the total so the existing ledger writer + monthly settlement flow
	# treats it like any other expense.
	var scutage_gp: int = _compute_active_scutage_gp_for_domain(domain_data)
	if scutage_gp > 0:
		expenses["scutage"] = scutage_gp
		expenses["total"] = int(expenses.get("total", 0)) + scutage_gp

	var base_morale := DomainMoraleResolver.resolve_base_morale(
		domain_data, ruler, revenue["total"],
		stronghold_value_gp, stronghold_minimum_gp,
		additional_garrison_gp_per_family)
	# Phase 10A.2: consecrate_ruler 12-month buff applies +1 / -1 to base morale
	# while the window is active.
	if faith_ruler_morale_bonus != 0:
		base_morale = int(base_morale) + faith_ruler_morale_bonus

	var event_modifiers_sum: int = _event_modifiers_sum(domain_data, expenses)
	var repression_bonus: int = int(domain_data.get(
		"repression_gp_per_family_this_month", 0))
	var is_repressed: bool = bool(domain_data.get(
		"is_repressed_this_month", 0))
	var morale_roll: int = DiceSystem.roll_digital(6, 2, 0, "domain_morale").modified_total
	var morale := DomainMoraleResolver.resolve_current_morale(
		domain_data, base_morale, event_modifiers_sum,
		repression_bonus, is_repressed, morale_roll)

	var morale_tier: String = DomainMoraleResolver.morale_tier(morale["current_morale"])
	var growth := DomainGrowthResolver.resolve_growth(
		domain_data, revenue["total"], investment_gp, morale_tier,
		bool(domain_data.get("is_active_adventuring_this_month", 0)),
		revenue["income_gate_active"])

	var class_change := ClassificationAdvancement.check_classification_change(
		domain_data, hex_count, _has_urban_settlement(domain_data),
		_urban_pct_of_peasants(domain_data),
		_distance_to_friendly_city(domain_data),
		_contiguous_expansion_blocked(domain_data))

	# Phase 10A.2: Faith block post-resolve — congregant growth + upkeep for
	# divine-caster rulers. Runs AFTER revenue/expenses so the upkeep can debit
	# the domain treasury if the ruler's divine_power is insufficient.
	var faith_congregants: Dictionary = FaithMonthlyResolver.resolve_congregants_monthly(
		String(domain_data.get("owner_character_id", "")),
		_cha_modifier(int(ruler.get("charisma", 10))),
		domain_id,
		calendar_day)
	# Phase 10A.2: sweep expired pending_divine_effects.
	FaithMonthlyResolver.expire_stale_effects(domain_id, calendar_day)

	# Phase 10B.1a: Magical Research monthly-tick stub. Advances
	# days_completed by 30 on every in_progress magic_research_projects row
	# owned by this domain's ruler. Completion-throw resolution + library/
	# workshop bonuses land in 10B.1b; aspirant promotion roll lands in
	# 10B.1d (per Q20 [RESOLVED 2026-05-11]: universal d20+ability_mod 14+
	# throw at joined_calendar_day + 120).
	var mr_summary: Dictionary = _resolve_magic_research_month(
		String(domain_data.get("owner_character_id", "")), calendar_day)

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
	}


## Phase 10B.1a stub. Advances days_completed on every in_progress
## magic_research_projects row owned by the given character by 30 (one
## month). Returns a summary dict the parent resolver folds into its result.
## Completion logic + library/workshop bonuses land in 10B.1b.
func _resolve_magic_research_month(
	owner_character_id: String,
	_calendar_day: int,
) -> Dictionary:
	if owner_character_id.is_empty():
		return {"projects_advanced": 0}
	# Snapshot the in-progress count BEFORE advancing so the summary reflects
	# how many projects actually had days_completed bumped.
	var before: Array = CampaignRepository.list_magic_research_projects_for_character(
		owner_character_id, "in_progress")
	if before.is_empty():
		return {"projects_advanced": 0}
	CampaignRepository.advance_magic_research_projects_for_character(
		owner_character_id, 30)
	return {"projects_advanced": before.size()}


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
	var prior_treasury: int = int(domain_data.get("treasury_gp", 0))
	var new_treasury: int = prior_treasury + net

	# Phase 3: administer_domain bonus = +5% domain XP per acore_axioms
	# §administration L499. Apply here, then reset the flag below.
	var domain_xp: int = maxi(0, net)
	if bool(domain_data.get("administer_domain_completed_this_month", 0)):
		domain_xp = int(round(domain_xp * 1.05))

	var fields := {
		"morale": result.get("current_morale", domain_data.get("morale", 0)),
		"peasant_families": new_peasants,
		"treasury_gp": new_treasury,
		"revenue_gp": result.get("revenue", 0),
		"expenses_gp": result.get("total_expenses", 0),
		"net_income_gp": net,
		"domain_xp_this_month": domain_xp,
		"territory_type": new_territory,
		# Phase 7: tribute_out_owed (recomputed each month from realm aggregate).
		"tribute_out_owed": int(result.get("tribute_out_owed", 0)),
		# Reset Phase 3 transient modifiers after consumption.
		"administer_domain_completed_this_month": 0,
		"pending_investment_gp": 0,
	}
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
		var prior_treasury: int = int(domain_data.get("treasury_gp", 0))
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
				"gp_amount": amount, "description": "",
			})
	var tin: int = int(revenue.get("tribute_in", 0))
	if tin != 0:
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id, "calendar_day": calendar_day,
			"category": "tribute_in", "subcategory": "vassal_tribute",
			"gp_amount": tin, "description": "",
		})
	# Phase 10A.2: consecrate_fields bonus (positive or negative).
	var cf_bonus: int = int(revenue.get("consecrate_fields_bonus", 0))
	if cf_bonus != 0:
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id, "calendar_day": calendar_day,
			"category": "revenue", "subcategory": "consecrate_fields_bonus",
			"gp_amount": cf_bonus,
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
				"gp_amount": amount, "description": "",
			})
	var tout: int = int(expenses.get("tribute_out", 0))
	if tout != 0:
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id, "calendar_day": calendar_day,
			"category": "tribute_out", "subcategory": "liege_tribute",
			"gp_amount": tout, "description": "",
		})


# ---------------------------------------------------------------------------
# Resolver inputs (helpers)
# ---------------------------------------------------------------------------

## Sum the gp_value of completed strongholds in a domain. Phase 1 wired this
## via `StrongholdRepository.get_stronghold_value_for_domain`; Phase 2+
## may add caching or contiguous-territory enforcement at this seam.
func _stub_stronghold_value(domain_id: String) -> int:
	return StrongholdRepository.get_stronghold_value_for_domain(domain_id)


## Per-hex classification minimums per `acore_axioms` §minimum_stronghold_value
## L88-94. Total = per_hex_minimum × hex_count.
func _classification_minimum_gp(territory_type: String, hex_count: int) -> int:
	var per_hex: int = 0
	match territory_type:
		"civilized":   per_hex = 15000
		"borderlands": per_hex = 22500
		"wilderness":  per_hex = 32000
		_:             per_hex = 32000
	return per_hex * maxi(1, hex_count)


## Build the ruler context dict the morale resolver expects. Looks up CHA mod,
## level, leadership proficiency, and alignment from the ruler character row.
func _build_ruler_context(domain_data: Dictionary) -> Dictionary:
	var ruler_id: String = String(domain_data.get("owner_character_id", ""))
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
	if not CampaignRepository.db.query_with_bindings("""
		SELECT 1 FROM character_proficiencies
		WHERE character_id = ? AND proficiency_id = 'leadership'
		LIMIT 1
	""", [character_id]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


## Phase 0: Phase 5 will compute (paid_garrison_gp - 2gp/family × peasants) /
## peasants. For now we have no troop_units table feeding the handler, so
## additional garrison is whatever the ruler over-paid above the universal
## 2gp/fam minimum, divided by peasant families.
func _additional_garrison_per_family(
	domain_data: Dictionary,
	actual_garrison_paid_gp: int
) -> int:
	var peasants: int = int(domain_data.get("peasant_families", 0))
	if peasants <= 0:
		return 0
	var minimum: int = peasants * DomainExpenseCalculator.GARRISON_MIN_GP_PER_FAMILY
	var extra: int = maxi(0, actual_garrison_paid_gp - minimum)
	return extra / peasants  # integer truncation; +1 morale at 1+ extra


## Sum the morale roll modifiers driven by the current month's domain settings.
## Per §monthly_event_modifiers L488-499. Phase 0 wires up the modifiers we can
## compute deterministically (tax, liturgy, tithes, garrison underpayment).
## Pillage / occupation / new-religion are deferred to Phase 8 / Phase 10.
func _event_modifiers_sum(domain_data: Dictionary, expenses: Dictionary) -> int:
	var sum: int = 0
	var liturgy_rate: int = int(domain_data.get("liturgy_rate_gp_per_family", 1))
	# Liturgy bonus/penalty per L492-493 (1 gp/fam baseline).
	sum += (liturgy_rate - 1)
	# Tax bonus/penalty per L494-495 (2 gp/fam baseline; raising taxes harms,
	# lowering helps).
	var tax_rate: int = int(domain_data.get("tax_rate_gp_per_family", 2))
	sum += (2 - tax_rate)
	# Garrison underpayment: -1 per gp below the 2 gp/fam minimum. Since the
	# expense calculator clamps actual garrison to the minimum, this only
	# fires if the caller supplied an `actual_garrison_paid_gp` below that —
	# Phase 0 always pays the minimum so this evaluates to 0.
	var peasants: int = int(domain_data.get("peasant_families", 0))
	var garrison: int = int(expenses.get("garrison", peasants * DomainExpenseCalculator.GARRISON_MIN_GP_PER_FAMILY))
	var min_garrison: int = peasants * DomainExpenseCalculator.GARRISON_MIN_GP_PER_FAMILY
	if garrison < min_garrison and peasants > 0:
		sum -= int(ceil(float(min_garrison - garrison) / float(peasants)))
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
	# round → subtract from event modifiers sum. (Reuses outer `peasants`
	# from the garrison-underpayment block above.)
	if not domain_id.is_empty():
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


func _distance_to_friendly_city(_domain_data: Dictionary) -> int:
	return 0  # Phase 2+ replaces with an actual hex-distance lookup


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
	var owner_id: String = String(domain_data.get("owner_character_id", ""))
	if owner_id.is_empty():
		return 0
	var aggregate: Dictionary = RealmAggregator.aggregate(owner_id)
	var realm_families: int = int(aggregate.get("all_realm_families", 0))
	return TributeCalculator.compute_tribute_base_gp(realm_families)


## Update the domain's realm_title based on the current aggregate. Returns
## {old_title, new_title, muster_period, changed}.
func _resolve_realm_title(domain_data: Dictionary) -> Dictionary:
	var old_title: String = String(domain_data.get("realm_title", "Baron"))
	var owner_id: String = String(domain_data.get("owner_character_id", ""))
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


## If the vassal cannot pay tribute_out from treasury_gp, trigger a Henchman
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
	var treasury: int = int(domain_data.get("treasury_gp", 0))
	# Find the vassal_assignment row for the domain's owner.
	var owner_id: String = String(domain_data.get("owner_character_id", ""))
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
## owner is the vassal. Returns 0 if this domain has no liege or no active
## scutage duty.
func _compute_active_scutage_gp_for_domain(domain_data: Dictionary) -> int:
	var liege_v: Variant = domain_data.get("liege_domain_id")
	if liege_v == null or String(liege_v).is_empty():
		return 0
	var owner_id: String = String(domain_data.get("owner_character_id", ""))
	if owner_id.is_empty():
		return 0
	var assn: Dictionary = VassalRepository.get_active_assignment_for_vassal(owner_id)
	if assn.is_empty():
		return 0
	var assn_id: String = String(assn.get("id", ""))
	var active_duties: Array = VassalObligationsRepository.list_active_duties_for_assignment(assn_id)
	var total: int = 0
	for d in active_duties:
		if String(d.get("type", "")) == "scutage":
			total += int(d.get("magnitude", 0))
	return total


## For each active vassal of THIS ruler, roll monthly on the Favors & Duties
## table per RAW §favors_and_duties L352-372. Returns an array of per-vassal
## resolution dicts (passes through whatever FavorsDutiesResolver returns).
##
## Phase 8 polish: also runs the loan-repayment monthly chance (RAW L365)
## and the construction auto-expenditure (RAW L361) for each active vassal.
func _resolve_favors_and_duties(domain_data: Dictionary, calendar_day: int) -> Array:
	var ruler_id: String = String(domain_data.get("owner_character_id", ""))
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

## Convert a Timekeeping date dict into a single integer day-of-campaign for
## ledger entries (year × 12 × DAYS_PER_MONTH + month-1 × DAYS_PER_MONTH + day).
func _calendar_day_from_date(date: Dictionary) -> int:
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day


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
