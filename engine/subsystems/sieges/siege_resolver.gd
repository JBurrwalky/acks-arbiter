class_name SiegeResolver
extends RefCounted

## Full DaW siege resolver per rules/daw_sieges.xml §blockade L65-193
## + §reduction L195-463 + §assault L465-499 + §ending_sieges L771-803.
##
## Used for player-involved sieges (any PC, PC henchman, or PC named NPC vassal
## in either army). NPC-vs-NPC sieges go through siege_resolver_simplified.
##
## Per RAW §methods_of_siege L23-27, methods may overlap, repeat, or occur in
## any order — current_phase is for UI dominance only, NOT a strict gate.
##
## Drives long-running state via EventScheduler tick events:
##   siege_daily_tick   — daily, owner=siege_id (PRIORITY_CONSEQUENCE)
##   siege_weekly_tick  — weekly, owner=siege_id (PRIORITY_CONSEQUENCE)
##
## Public API:
##   start_full_siege(besieging_army_id, stronghold_id, defending_army_id,
##                     calendar_day, scheduler, weeks_of_warning) -> siege_id
##   tick_daily(siege_id, calendar_day, dice_roller) -> Dictionary
##   tick_weekly(siege_id, calendar_day, dice_roller) -> void
##   apply_method(siege_id, method, params, dice_roller) -> Dictionary
##   begin_assault(siege_id, calendar_day, dice_roller) -> battle_id
##   handle_assault_concluded(siege_id, battle_id, outcome, day) -> Dictionary
##   check_end_conditions(siege_id) -> String
##   conclude_siege(siege_id, outcome, calendar_day, scheduler) -> Dictionary


# ---------------------------------------------------------------------------
# Initiation
# ---------------------------------------------------------------------------

## Start a full DaW siege.
## Parameters:
##   besieging_army_id   - the attacking army
##   stronghold_id       - the stronghold under siege
##   defending_army_id   - garrison army; "" if pure-garrison-only (RAW silent)
##   calendar_day        - day siege begins
##   scheduler           - EventScheduler instance for tick events; null in test mode
##   weeks_of_warning    - prep time before blockade (RAW L126); 0 = blockaded same day
static func start_full_siege(
	besieging_army_id: String,
	stronghold_id: String,
	defending_army_id: String,
	calendar_day: int,
	scheduler = null,
	weeks_of_warning: int = 0,
	site: String = ""
) -> String:
	if besieging_army_id.is_empty() or stronghold_id.is_empty():
		return ""
	# Pull stronghold data.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM strongholds WHERE id = ?", [stronghold_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	var stronghold: Dictionary = CampaignRepository.db.query_result[0]
	var shp: int = int(stronghold.get("shp", 0))
	var unit_capacity: int = UnitCapacityCalculator.compute_unit_capacity(shp)
	var material: String = StrongholdRepository.resolve_material(stronghold)
	var supplies: int = SiegeSupplyTracker.accrue_prep_supplies_cp(unit_capacity, weeks_of_warning)
	var campaign_id: String = _campaign_for_army(besieging_army_id)
	var domain_id: String = _domain_for_stronghold(stronghold_id)
	var siege_id: String = SiegeRepository.create_siege({
		"campaign_id": campaign_id,
		"stronghold_id": stronghold_id,
		"domain_id": domain_id,
		"besieging_army_id": besieging_army_id,
		"defending_army_id": defending_army_id,
		"map_id": stronghold.get("location_map_id"),
		"hex_q": stronghold.get("location_hex_q"),
		"hex_r": stronghold.get("location_hex_r"),
		"resolution_mode": "full",
		"current_phase": "blockade",
		"starting_shp": shp,
		"current_shp": shp,
		"unit_capacity": unit_capacity,
		"material": material,
		"stored_supplies_cp": supplies,
		"started_calendar_day": calendar_day,
		"payload_json": JSON.stringify({"site": site, "weeks_of_warning": weeks_of_warning}),
	})
	if siege_id.is_empty():
		return ""
	# Transition besieging army to state='besieging'.
	CampaignRepository.db.query_with_bindings(
		"UPDATE armies SET state = 'besieging' WHERE id = ?",
		[besieging_army_id]
	)
	# Schedule tick events.
	if scheduler != null:
		scheduler.schedule_at(
			calendar_day + 1, "siege_daily_tick", siege_id,
			{"siege_id": siege_id}, ScheduledEvent.PRIORITY_CONSEQUENCE
		)
		scheduler.schedule_at(
			calendar_day + 7, "siege_weekly_tick", siege_id,
			{"siege_id": siege_id}, ScheduledEvent.PRIORITY_CONSEQUENCE
		)
	if EventBus.has_signal("siege_started"):
		EventBus.emit_signal("siege_started", siege_id, stronghold_id, besieging_army_id)
	return siege_id


# ---------------------------------------------------------------------------
# Daily / weekly ticks
# ---------------------------------------------------------------------------

## Daily tick driven by EventScheduler. Order:
##   1. Reap any expired pending subversion breaches.
##   2. Supply consumption (if blockaded).
##   3. Bombardment (besieger artillery).
##   4. Mining construction progress.
##   5. Defender repair (overnight).
##   6. Recompute breach_count from damage_dealt_total - damage_repaired_total.
##   7. Check end conditions.
##   8. Schedule next siege_daily_tick.
##
## Returns a summary dict for inspection / UI logging.
static func tick_daily(siege_id: String, calendar_day: int, dice_roller: Callable = Callable(), scheduler = null) -> Dictionary:
	var summary: Dictionary = {
		"siege_id": siege_id,
		"calendar_day": calendar_day,
		"subversion_breaches_expired": 0,
		"supply_tick": {},
		"bombardment": {},
		"mining": [],
		"repair": {},
		"end_condition": "",
		"siege_concluded": false,
	}
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		summary.end_condition = "siege_not_found"
		return summary
	if String(siege.get("current_phase", "")) == "concluded":
		summary.end_condition = "already_concluded"
		summary.siege_concluded = true
		return summary
	# 1. Subversion breach reaper.
	summary.subversion_breaches_expired = SiegeReductionResolver.reap_expired_subversion_breach(siege_id, calendar_day)
	# 2. Supplies (blockade only).
	if int(siege.get("is_blockaded", 0)) == 1:
		summary.supply_tick = SiegeSupplyTracker.tick_consumption(siege_id, calendar_day)
	# 3. Bombardment.
	summary.bombardment = SiegeReductionResolver.tick_bombardment(siege_id, calendar_day, dice_roller)
	# 4. Mining (just construction progress; detonation is a separate apply_method call).
	summary.mining = SiegeMiningResolver.tick_construction(siege_id, calendar_day)
	# 5. Repair: Phase 9C NPC defender auto-repair heuristic. PC-defended
	# strongholds DO NOT auto-repair — players invoke apply_method('reduction_repair')
	# explicitly. NPC defenders spend up to 10x damage_dealt_today (in cp) per day,
	# capped at 1% of stored_supplies_cp.
	if not _defender_is_pc_owned(siege_id):
		var damage_today: int = int(summary.bombardment.get("total_damage_dealt", 0))
		if damage_today > 0:
			var refreshed: Dictionary = SiegeRepository.get_siege(siege_id)
			var stored_cp: int = int(refreshed.get("stored_supplies_cp", 0))
			var auto_budget: int = mini(damage_today * 10, stored_cp / 100) if stored_cp > 0 else 0
			if auto_budget > 0:
				summary.repair = SiegeReductionResolver.repair_overnight(siege_id, calendar_day, auto_budget)
	# 6. Recompute breaches (already done by sub-resolvers).
	# 7. End conditions.
	var end: String = check_end_conditions(siege_id)
	summary.end_condition = end
	if not end.is_empty():
		conclude_siege(siege_id, end, calendar_day, scheduler)
		summary.siege_concluded = true
	# 8. Reschedule next daily tick.
	if not summary.siege_concluded and scheduler != null:
		scheduler.schedule_at(
			calendar_day + 1, "siege_daily_tick", siege_id,
			{"siege_id": siege_id}, ScheduledEvent.PRIORITY_CONSEQUENCE
		)
	# Emit state-changed signal for UI.
	var refreshed: Dictionary = SiegeRepository.get_siege(siege_id)
	if EventBus.has_signal("siege_state_changed"):
		EventBus.emit_signal("siege_state_changed", siege_id,
			String(refreshed.get("current_phase", "")),
			int(refreshed.get("current_shp", 0)),
			int(refreshed.get("breach_count", 0))
		)
	return summary


## Weekly tick driven by EventScheduler. Currently:
##   1. Mining-worker loyalty rolls (per-mine; unmodified 2 = mining accident).
##   2. Defender's daily reconnaissance roll for undetected besieger mines
##      (folded into weekly here for v1 simplicity; could be moved to daily).
static func tick_weekly(siege_id: String, calendar_day: int, dice_roller: Callable = Callable(), scheduler = null) -> Dictionary:
	var summary: Dictionary = {
		"loyalty_rolls": [],
		"newly_detected_mines": [],
	}
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty() or String(siege.get("current_phase", "")) == "concluded":
		return summary
	summary.loyalty_rolls = SiegeMiningResolver.weekly_loyalty_rolls(siege_id, calendar_day, dice_roller)
	summary.newly_detected_mines = SiegeMiningResolver.defender_reconnaissance_roll(siege_id, calendar_day, dice_roller)
	if scheduler != null:
		scheduler.schedule_at(
			calendar_day + 7, "siege_weekly_tick", siege_id,
			{"siege_id": siege_id}, ScheduledEvent.PRIORITY_CONSEQUENCE
		)
	return summary


# ---------------------------------------------------------------------------
# Player-action dispatcher
# ---------------------------------------------------------------------------

## Apply a player- or AI-driven siege method.
## method ∈ {
##   'blockade_complete'      — mark blockade complete (after circumvallation +
##                              units / ships verified; emits blockade_completed)
##   'reduction_bombardment'  — manual bombardment trigger (bypassing daily tick)
##   'reduction_mining'       — start a new mine; params: side, engineer_id,
##                              workers, petard_damage, [countermine_target_id]
##   'reduction_mine_detonate'- detonate a completed mine; params: mine_id
##   'reduction_magic'        — apply spell; params: spell, hp_damage, turns
##   'reduction_arson'        — params: perpetrator_class_level, extra_damage_multiplier
##   'reduction_subversion'   — params: additional_breaches
##   'reduction_repair'       — params: cp_to_spend
##   'assault'                — initiate assault; returns battle_id
##   'sally'                  — defender exits; switches to a field battle
##   'surrender'              — defender voluntarily surrenders
##   'circumvallation_progress' — params: feet (sets circumvallation_feet)
##   'artillery_duel'         — runs run_artillery_duel
## }
static func apply_method(siege_id: String, method: String, params: Dictionary = {}, dice_roller: Callable = Callable()) -> Dictionary:
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return {"ok": false, "error": "siege_not_found"}
	if String(siege.get("current_phase", "")) == "concluded":
		return {"ok": false, "error": "already_concluded"}
	var day: int = int(params.get("calendar_day", 0))
	match method:
		"blockade_complete":
			SiegeRepository.update(siege_id, {"is_blockaded": 1})
			SiegeRepository.append_action(siege_id, day, "besieger", "blockade_completed", {}, params)
			if EventBus.has_signal("siege_blockade_completed"):
				EventBus.emit_signal("siege_blockade_completed", siege_id)
			return {"ok": true}
		"circumvallation_progress":
			var feet: int = int(params.get("feet", 0))
			var unit_capacity: int = int(siege.get("unit_capacity", 0))
			var effect: Dictionary = SiegeBlockadeCalculator.compute_circumvallation_effect(feet, unit_capacity)
			# Phase 9C E3: completed circumvallation provides cover for besieger
			# artillery per RAW L236-237 (defender 5 misses if cover present).
			var update_fields: Dictionary = {
				"circumvallation_feet": feet,
				"is_circumvallation_complete": 1 if bool(effect.get("is_complete", false)) else 0,
			}
			if bool(effect.get("is_complete", false)):
				var payload: Dictionary = _parse_payload(String(siege.get("payload_json", "{}")))
				payload["besieger_has_cover_for_artillery"] = true
				update_fields["payload_json"] = JSON.stringify(payload)
			SiegeRepository.update(siege_id, update_fields)
			SiegeRepository.append_action(siege_id, day, "besieger", "circumvallation_progress",
				{}, {"feet": feet, "effect": effect})
			return {"ok": true, "effect": effect}
		"reduction_bombardment":
			return {"ok": true, "result": SiegeReductionResolver.tick_bombardment(siege_id, day, dice_roller)}
		"reduction_mining":
			var mine_id: String = SiegeMiningResolver.start_mine(
				siege_id,
				String(params.get("side", "besieger")),
				String(params.get("supervising_engineer_id", "")),
				int(params.get("workers", 0)),
				int(params.get("petard_damage", 0)),
				day,
				String(params.get("countermine_target_id", ""))
			)
			return {"ok": not mine_id.is_empty(), "mine_id": mine_id}
		"reduction_mine_detonate":
			return {"ok": true, "result": SiegeMiningResolver.detonate_mine(
				String(params.get("mine_id", "")), day, dice_roller)}
		"reduction_magic":
			return {"ok": true, "result": SiegeReductionResolver.apply_magic(
				siege_id, String(params.get("spell", "")), day,
				int(params.get("hp_damage", 0)), int(params.get("turns", 1)))}
		"reduction_arson":
			return {"ok": true, "result": SiegeReductionResolver.attempt_arson(
				siege_id, day, int(params.get("perpetrator_class_level", 1)),
				dice_roller, int(params.get("extra_damage_multiplier", 1)))}
		"reduction_subversion":
			return {"ok": true, "result": SiegeReductionResolver.attempt_subversion(
				siege_id, day, int(params.get("additional_breaches", 1)))}
		"reduction_repair":
			return {"ok": true, "result": SiegeReductionResolver.repair_overnight(
				siege_id, day, int(params.get("cp_to_spend", 0)))}
		"artillery_duel":
			return {"ok": true, "result": SiegeReductionResolver.run_artillery_duel(siege_id, day, dice_roller)}
		"assault":
			var battle_id: String = begin_assault(siege_id, day, dice_roller)
			return {"ok": not battle_id.is_empty(), "battle_id": battle_id}
		"sally":
			# Defender exits the stronghold for a pitched battle. Per RAW L780-783,
			# the siege ends and a normal field battle is fought immediately.
			var battle_id_sally: String = _begin_sally(siege_id, day, dice_roller)
			return {"ok": not battle_id_sally.is_empty(), "battle_id": battle_id_sally}
		"surrender":
			conclude_siege(siege_id, "surrendered", day, params.get("scheduler"))
			return {"ok": true, "outcome": "surrendered"}
		_:
			return {"ok": false, "error": "unknown_method", "method": method}


# ---------------------------------------------------------------------------
# Assault entry point
# ---------------------------------------------------------------------------

## Initiate an assault. Builds the assault_modifiers dict per RAW
## §battle_ratings_during_assaults L507-512 + §attack_throw_modifiers L502-505
## + §resolving_assaults L476-477, then calls FieldBattleResolver.start_battle_with_overrides.
##
## Returns the battle_id, or "" on failure.
static func begin_assault(siege_id: String, calendar_day: int, dice_roller: Callable = Callable()) -> String:
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return ""
	var besieger_id: String = String(siege.get("besieging_army_id", ""))
	var defender_id: String = String(siege.get("defending_army_id", ""))
	if besieger_id.is_empty() or defender_id.is_empty():
		# RAW assumes both sides have a force; if no defending army (pure
		# undefended garrison), the assault is auto-capture.
		conclude_siege(siege_id, "captured", calendar_day, null)
		return ""
	# Mark phase as 'assault' for UI clarity.
	SiegeRepository.update(siege_id, {"current_phase": "assault"})
	var unit_capacity: int = int(siege.get("unit_capacity", 0))
	var breach_count: int = int(siege.get("breach_count", 0))
	var assault_modifiers: Dictionary = {
		"max_assaulting_units": UnitCapacityCalculator.max_assaulting_units(unit_capacity, breach_count),
		"max_defending_units":  UnitCapacityCalculator.max_defending_units(unit_capacity),
		"defending_infantry_br_bonus": 1,                       # RAW L508-509
		"assaulting_cavalry_no_breach_br_multiplier": 0.25,     # RAW L510-511
		"base_attack_target": 16,                               # RAW L488
		"assaulting_attack_modifier": -2,                       # RAW L502
		"defending_attack_modifier": 2,                         # RAW L504
	}
	var is_player_involved: bool = _is_player_involved_for_siege(siege)
	var battle_id: String = FieldBattleResolver.start_battle_with_overrides(
		besieger_id, defender_id,
		"clear_or_grass", "calm", calendar_day,
		is_player_involved, assault_modifiers, dice_roller
	)
	if battle_id.is_empty():
		return ""
	SiegeRepository.append_action(siege_id, calendar_day, "besieger", "assault_turn",
		{},
		{
			"battle_id": battle_id,
			"assault_modifiers": assault_modifiers,
			"is_player_involved": is_player_involved,
		},
		battle_id
	)
	if EventBus.has_signal("siege_assault_began"):
		EventBus.emit_signal("siege_assault_began", siege_id, battle_id)
	return battle_id


## Called once a battle started by begin_assault concludes.
## Maps battle outcome → siege outcome and concludes the siege if appropriate.
static func handle_assault_concluded(siege_id: String, battle_id: String, battle_outcome: String, calendar_day: int, scheduler = null) -> Dictionary:
	var siege_outcome: String = _battle_outcome_to_siege_outcome(battle_outcome)
	# RAW §resolving_assaults L491-497: end states.
	#   defenders defeated → captured
	#   assaulters defeated → liberated
	#   defender surrenders → captured
	#   neither → besieger may renew or call off (siege continues, no conclusion)
	if siege_outcome.is_empty():
		# Indecisive — return without concluding; UI presents renew/call-off choice.
		return {"siege_concluded": false, "siege_outcome": "", "battle_outcome": battle_outcome}
	conclude_siege(siege_id, siege_outcome, calendar_day, scheduler)
	return {"siege_concluded": true, "siege_outcome": siege_outcome, "battle_outcome": battle_outcome}


# ---------------------------------------------------------------------------
# End-state checks
# ---------------------------------------------------------------------------

## Examine the siege state and return a non-empty outcome string if any
## end-condition is met. Returns "" if siege should continue.
##
## RAW §ending_sieges L771-803 conditions:
##   - Defending army sallies forth → handled by 'sally' method (returns 'sallied_won/lost')
##   - Defending army surrenders → 'surrendered'
##   - Besieging army departs → 'liberated' (caller invokes when armies leave hex)
##   - Besieger captures/destroys → 'captured' or 'destroyed'
##
## v1 auto-detected end conditions:
##   - current_shp <= 0 → 'destroyed' (RAW L199 + L800-802)
##
## Voluntary actions (sally, surrender, departure) are surfaced via
## apply_method calls; this method only catches the auto-conditions.
static func check_end_conditions(siege_id: String) -> String:
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return ""
	if String(siege.get("current_phase", "")) == "concluded":
		return ""
	if int(siege.get("current_shp", 0)) <= 0:
		return "destroyed"
	return ""


## Conclude a siege with the given outcome. Persists outcome, transitions
## besieging army back to 'encamped', flips stronghold status if appropriate,
## cancels remaining tick events, emits siege_concluded.
static func conclude_siege(siege_id: String, outcome: String, calendar_day: int, scheduler = null) -> Dictionary:
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return {"ok": false, "error": "siege_not_found"}
	SiegeRepository.conclude(siege_id, outcome, calendar_day)
	# Restore besieging army state.
	var besieger_id: String = String(siege.get("besieging_army_id", ""))
	if not besieger_id.is_empty():
		CampaignRepository.db.query_with_bindings(
			"UPDATE armies SET state = 'encamped' WHERE id = ?", [besieger_id]
		)
	# Stronghold status update.
	var stronghold_id: String = String(siege.get("stronghold_id", ""))
	if outcome == "destroyed":
		CampaignRepository.db.query_with_bindings(
			"UPDATE strongholds SET status = 'destroyed' WHERE id = ?", [stronghold_id]
		)
		if EventBus.has_signal("stronghold_destroyed"):
			EventBus.emit_signal("stronghold_destroyed", stronghold_id, "siege")
	elif outcome == "captured" or outcome == "surrendered":
		CampaignRepository.db.query_with_bindings(
			"UPDATE strongholds SET status = 'claimed' WHERE id = ?", [stronghold_id]
		)
	# Cancel pending tick events for this siege.
	if scheduler != null:
		scheduler.cancel_all_for_owner(siege_id, "siege_daily_tick")
		scheduler.cancel_all_for_owner(siege_id, "siege_weekly_tick")
		scheduler.cancel_all_for_owner(siege_id, "siege_simplified_concluded")
	if EventBus.has_signal("siege_concluded"):
		EventBus.emit_signal("siege_concluded", siege_id, outcome)
	return {"ok": true, "outcome": outcome}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _begin_sally(siege_id: String, calendar_day: int, dice_roller: Callable = Callable()) -> String:
	## Defender sallies forth — siege ends, normal field battle is fought.
	## Per RAW L780-783: outcome of pitched battle determines retreat options.
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return ""
	var besieger_id: String = String(siege.get("besieging_army_id", ""))
	var defender_id: String = String(siege.get("defending_army_id", ""))
	if besieger_id.is_empty() or defender_id.is_empty():
		return ""
	var is_player_involved: bool = _is_player_involved_for_siege(siege)
	# Sally swaps roles: defender is the attacker in the pitched battle (L781:
	# "defender exits the stronghold and gives battle").
	var battle_id: String = FieldBattleResolver.start_battle(
		defender_id, besieger_id,
		"clear_or_grass", "calm", calendar_day,
		is_player_involved, dice_roller
	)
	if battle_id.is_empty():
		return ""
	# Stamp this siege as awaiting sally outcome on payload_json. The
	# battle_concluded signal listener (handle_battle_concluded_for_sally)
	# reads this to map the field-battle outcome → 'sallied_won' / 'sallied_lost'.
	var payload: Dictionary = _parse_payload(String(siege.get("payload_json", "{}")))
	payload["pending_sally_battle_id"] = battle_id
	SiegeRepository.update(siege_id, {"payload_json": JSON.stringify(payload)})
	SiegeRepository.append_action(siege_id, calendar_day, "defender", "sally",
		{},
		{"battle_id": battle_id, "is_player_involved": is_player_involved},
		battle_id
	)
	return battle_id


## Phase 9C E2: Sally outcome glue. Maps the field-battle outcome of a sally
## to the siege outcome ('sallied_won' if defender wins, 'sallied_lost' if
## besieger wins) and concludes the siege. Per RAW L780-783 the siege ends
## regardless of the outcome of the pitched battle.
##
## Called by a battle_concluded listener registered at session boot. v1
## convention: any apply_method('sally', ...) caller that has the scheduler
## available should also wire EventBus.battle_concluded → this method via
## the runner's listener registry. Tests can call directly.
static func handle_battle_concluded_for_sally(siege_id: String, battle_id: String, battle_outcome: String, calendar_day: int, scheduler = null) -> Dictionary:
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return {"siege_concluded": false, "error": "siege_not_found"}
	var payload: Dictionary = _parse_payload(String(siege.get("payload_json", "{}")))
	var pending: String = String(payload.get("pending_sally_battle_id", ""))
	if pending.is_empty() or pending != battle_id:
		# Not a sally battle for this siege.
		return {"siege_concluded": false, "error": "not_a_pending_sally"}
	# Map outcome.
	var sally_outcome: String = ""
	match battle_outcome:
		"attacker_victory", "attacker_decisive_victory", "decisive_victory_attacker":
			# Sallied attacker (defender) won — defender wins the siege.
			sally_outcome = "sallied_won"
		"defender_victory", "defender_decisive_victory", "decisive_victory_defender":
			# Sallied defender (besieger) won — besieger wins the siege.
			sally_outcome = "sallied_lost"
		_:
			# Indecisive sally — still ends the siege per RAW L780 (siege ends
			# either way). Default to liberated (defender survives, besieger doesn't capture).
			sally_outcome = "sallied_lost"
	# Clear pending key.
	payload.erase("pending_sally_battle_id")
	SiegeRepository.update(siege_id, {"payload_json": JSON.stringify(payload)})
	conclude_siege(siege_id, sally_outcome, calendar_day, scheduler)
	return {"siege_concluded": true, "siege_outcome": sally_outcome, "battle_outcome": battle_outcome}


static func _parse_payload(json_str: String) -> Dictionary:
	if json_str.is_empty() or json_str == "{}":
		return {}
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed is Dictionary:
		return parsed
	return {}


static func _battle_outcome_to_siege_outcome(battle_outcome: String) -> String:
	# field_battle_resolver returns: 'attacker_victory', 'defender_victory',
	# 'attacker_decisive_victory', 'defender_decisive_victory', 'draw', or
	# 'indecisive'. Map to siege outcomes.
	match battle_outcome:
		"attacker_victory", "attacker_decisive_victory", "decisive_victory_attacker":
			return "captured"
		"defender_victory", "defender_decisive_victory", "decisive_victory_defender":
			return "liberated"
		_:
			# Draw / indecisive — siege continues.
			return ""


static func _is_player_involved_for_siege(siege: Dictionary) -> bool:
	var besieger_id: String = String(siege.get("besieging_army_id", ""))
	var defender_id: String = String(siege.get("defending_army_id", ""))
	return _army_is_player_involved(besieger_id) or _army_is_player_involved(defender_id)


## Phase 9C E1: True if the siege's defending army is owned/commanded by a PC
## (or PC henchman). Used by the auto-repair heuristic in tick_daily — PC
## defenders don't auto-repair (player invokes explicitly).
static func _defender_is_pc_owned(siege_id: String) -> bool:
	var siege: Dictionary = SiegeRepository.get_siege(siege_id)
	if siege.is_empty():
		return false
	var defender_id: String = String(siege.get("defending_army_id", ""))
	if defender_id.is_empty():
		# No defender army (pure undefended garrison) — treat as NPC for auto-repair.
		return false
	return _army_is_player_involved(defender_id)


static func _army_is_player_involved(army_id: String) -> bool:
	if army_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT political_owner_id, command_character_id FROM armies WHERE id = ?",
		[army_id]
	):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var row: Dictionary = CampaignRepository.db.query_result[0]
	if _is_pc_or_pc_henchman(str(row.get("political_owner_id", ""))):
		return true
	if _is_pc_or_pc_henchman(str(row.get("command_character_id", ""))):
		return true
	return false


static func _is_pc_or_pc_henchman(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT character_type FROM characters WHERE id = ?", [character_id]
	):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var ctype: String = String(CampaignRepository.db.query_result[0].get("character_type", ""))
	if ctype == "pc":
		return true
	if ctype == "henchman":
		# Check if henchman of a PC.
		if not CampaignRepository.db.query_with_bindings("""
			SELECT 1 FROM henchman_relationships hr
			JOIN characters c ON c.id = hr.lord_character_id
			WHERE hr.henchman_character_id = ? AND c.character_type = 'pc'
			LIMIT 1
		""", [character_id]):
			return false
		return not CampaignRepository.db.query_result.is_empty()
	return false


static func _campaign_for_army(army_id: String) -> String:
	if army_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT campaign_id FROM armies WHERE id = ?", [army_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("campaign_id", ""))


static func _domain_for_stronghold(stronghold_id: String) -> String:
	if stronghold_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT domain_id FROM strongholds WHERE id = ?", [stronghold_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	var v: Variant = CampaignRepository.db.query_result[0].get("domain_id", "")
	return "" if v == null else String(v)
