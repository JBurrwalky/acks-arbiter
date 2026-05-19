class_name SyndicateLauncher
extends RefCounted

## Static-function dispatcher for syndicate activity launches (Phase 10B.3 UI
## polish wave). The UI (SyndicateBlock + future settlement/stronghold
## context menus) calls these helpers; each one:
##   1. Validates inputs.
##   2. Pre-rolls any duration that RAW prescribes randomized (planning days,
##      lay-low days) and embeds them in params so
##      ActivityTimeCostExecutor._compute_ticks_required can read them back.
##   3. Side-effects any state that must exist before the activity ticks
##      (e.g., hijink_assignments.planning_state='planning' for plan_hijink,
##      lay_low_state row for lay_low — RAW L1196 says other syndicate
##      activities must be able to see the lay-low immediately).
##   4. Calls ActivityTimeCostExecutor.launch(...).
##
## Follows the prepare_launch pattern from Phase 10B.2 Wave 4 (SolicitMerchants
## per coding_conventions §53). Pure static functions; no instance state.
##
## All launch helpers return { success: bool, activity_state_id: String,
## error: String, ...extras }. The error code is the executor's return
## ("unknown_activity", "on_cooldown", "no_scheduler", "persist_failed") OR a
## launcher-side validation code ("invalid_params", "ineligible",
## "no_caught_perpetrator", "already_resolved", "insufficient_funds_preflight").


# ===========================================================================
# order_hijink
# ===========================================================================

## Args:
##   character_id           — boss character_id
##   syndicate_id           — syndicates.id
##   syndicate_member_id    — syndicate_members.id being assigned
##   hijink_kind            — one of the 6 kinds
##   target_id              — OPTIONAL (assassinating victim, etc.)
##   executor               — ActivityTimeCostExecutor instance (from SessionRunner)
##   scheduler              — EventScheduler instance
##   party_id               — boss's party_id (for time tracking)
static func launch_order_hijink(
		character_id: String,
		syndicate_id: String,
		syndicate_member_id: String,
		hijink_kind: String,
		target_id: String,
		executor,
		scheduler,
		party_id: String = "",
) -> Dictionary:
	if character_id.is_empty() or syndicate_id.is_empty() or syndicate_member_id.is_empty() or hijink_kind.is_empty():
		return _err("invalid_params")
	# Validate eligibility (boss owns syndicate, member is active in it).
	var syndicate := SyndicateRepository.get_syndicate(syndicate_id)
	if syndicate.is_empty() or String(syndicate.get("boss_character_id", "")) != character_id:
		return _err("ineligible")
	var member := SyndicateRepository.get_member(syndicate_member_id)
	if member.is_empty() or String(member.get("syndicate_id", "")) != syndicate_id:
		return _err("ineligible")
	var params: Dictionary = {
		"syndicate_id": syndicate_id,
		"syndicate_member_id": syndicate_member_id,
		"hijink_kind": hijink_kind,
		"target_id": target_id,
		"hideout_id": String(syndicate.get("hideout_stronghold_id", "")),
	}
	return executor.launch(
		character_id, "order_hijink",
		"at_stronghold", _hideout_location_ref(syndicate),
		params, scheduler, party_id,
	)


# ===========================================================================
# plan_hijink — Ongoing 2d8+3 / 2d6+3 / 2d4+3 days.
# ===========================================================================

## Rolls the planning duration via HijinkPlanningResolver.start_planning at
## launch time. The launch *also* flips hijink_assignments.planning_state to
## 'planning' so the row reflects in-flight state immediately. The Ongoing
## activity ticks each day and HijinkPlanningResolver.advance_planning
## increments planning_days_completed.
static func launch_plan_hijink(
		character_id: String,
		hijink_assignment_id: String,
		executor,
		scheduler,
		party_id: String = "",
) -> Dictionary:
	if character_id.is_empty() or hijink_assignment_id.is_empty():
		return _err("invalid_params")
	var hijink := SyndicateRepository.get_hijink(hijink_assignment_id)
	if hijink.is_empty():
		return _err("ineligible")
	var member_id := String(hijink.get("syndicate_member_id", ""))
	var member := SyndicateRepository.get_member(member_id) if not member_id.is_empty() else {}
	var level: int = int(member.get("level", 1))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var days: int = HijinkPlanningResolver.start_planning(hijink_assignment_id, level, rng)
	var params: Dictionary = {
		"hijink_assignment_id": hijink_assignment_id,
		"planning_days_required": days,
	}
	var syndicate := SyndicateRepository.get_syndicate(String(hijink.get("syndicate_id", "")))
	return executor.launch(
		character_id, "plan_hijink",
		"at_stronghold", _hideout_location_ref(syndicate),
		params, scheduler, party_id,
	)


# ===========================================================================
# perform_hijink — Singular major (1 day, plannable kinds) OR
#                  Ongoing major (3d6+10 / 3d4+8 / 2d6+5, non-plannable).
# ===========================================================================

## Rolls the perform duration based on kind + level. For plannable kinds
## (assassinating / smuggling / stealing) the activity is singular at 1
## day; for non-plannable (carousing / spying / treasure_hunting) it's
## ongoing per RAW L1244-1246.
##
## extra_params (optional): merchandise_type, settlement_id, victim_level,
## for_hire — forwarded to the kind-specific handler via PerformHijinkHandler.
static func launch_perform_hijink(
		character_id: String,
		hijink_assignment_id: String,
		executor,
		scheduler,
		party_id: String = "",
		extra_params: Dictionary = {},
) -> Dictionary:
	if character_id.is_empty() or hijink_assignment_id.is_empty():
		return _err("invalid_params")
	var hijink := SyndicateRepository.get_hijink(hijink_assignment_id)
	if hijink.is_empty():
		return _err("ineligible")
	var kind := String(hijink.get("hijink_kind", ""))
	var member_id := String(hijink.get("syndicate_member_id", ""))
	var member := SyndicateRepository.get_member(member_id) if not member_id.is_empty() else {}
	var level: int = int(member.get("level", 1))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var days: int = _roll_perform_duration(kind, level, rng)
	var params: Dictionary = extra_params.duplicate(true)
	params["hijink_assignment_id"] = hijink_assignment_id
	params["perform_days_required"] = days
	# Flip status to active so the UI surfaces it correctly.
	SyndicateRepository.update_hijink(hijink_assignment_id, {
		"status": "active",
		"started_day": Timekeeping.get_total_days(),
	})
	var syndicate := SyndicateRepository.get_syndicate(String(hijink.get("syndicate_id", "")))
	# Plannable kinds = at_stronghold (1 day at hideout); non-plannable
	# kinds = at_settlement (perpetrator works the streets).
	var location_kind: String = "at_stronghold" if HijinkPlanningResolver.is_plannable(kind) else "at_settlement"
	var location_ref: String = _hideout_location_ref(syndicate) if location_kind == "at_stronghold" else _settlement_location_ref(syndicate)
	return executor.launch(
		character_id, "perform_hijink",
		location_kind, location_ref,
		params, scheduler, party_id,
	)


## Rolls perform-hijink duration per RAW L1243-1246.
##   Plannable (assassinating/smuggling/stealing): 1 day flat.
##   Non-plannable carousing/spying/treasure_hunting:
##     L1-4: 3d6+10 (range 13-28)
##     L5-8: 3d4+8  (range 11-20)
##     L9+:  2d6+5  (range  7-17)
static func _roll_perform_duration(kind: String, level: int, rng: RandomNumberGenerator) -> int:
	if HijinkPlanningResolver.is_plannable(kind):
		return 1
	if level >= 9:
		return rng.randi_range(1, 6) + rng.randi_range(1, 6) + 5
	if level >= 5:
		return rng.randi_range(1, 4) + rng.randi_range(1, 4) + rng.randi_range(1, 4) + 8
	return rng.randi_range(1, 6) + rng.randi_range(1, 6) + rng.randi_range(1, 6) + 10


# ===========================================================================
# lay_low — Ongoing 2d8+3 days.
# ===========================================================================

## Pre-rolls 2d8+3 days, creates the lay_low_state row immediately so other
## syndicate-activity launch surfaces can see it (RAW L1196: while laying
## low at a base the character may not plan or perform hijinks IN THAT
## BASE, but may in others).
##
## base_id is a free-form key, typically "stronghold:<id>" or
## "settlement_entrance:<id>".
static func launch_lay_low(
		character_id: String,
		base_id: String,
		executor,
		scheduler,
		party_id: String = "",
) -> Dictionary:
	if character_id.is_empty() or base_id.is_empty():
		return _err("invalid_params")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var days: int = rng.randi_range(1, 8) + rng.randi_range(1, 8) + 3
	var current_day: int = Timekeeping.get_total_days()
	SyndicateRepository.upsert_lay_low(character_id, base_id, current_day, current_day + days)
	EventBus.lay_low_started.emit(character_id, current_day + days)
	var params: Dictionary = {
		"base_id": base_id,
		"lay_low_days": days,
	}
	return executor.launch(
		character_id, "lay_low",
		"at_stronghold", base_id,
		params, scheduler, party_id,
	)


# ===========================================================================
# await_trial — Ongoing per crime_type.
# ===========================================================================

## Reads the pre-rolled time_languishing_days from the caught_perpetrators
## row (set at arrest time by HijinkCommon._create_caught_perpetrator), and
## launches the Ongoing activity with that duration.
static func launch_await_trial(
		character_id: String,
		caught_perpetrator_id: String,
		executor,
		scheduler,
		party_id: String = "",
) -> Dictionary:
	if character_id.is_empty() or caught_perpetrator_id.is_empty():
		return _err("invalid_params")
	var row := SyndicateRepository.get_caught(caught_perpetrator_id)
	if row.is_empty():
		return _err("no_caught_perpetrator")
	if row.get("verdict") != null:
		return _err("already_resolved")
	if String(row.get("character_id", "")) != character_id:
		return _err("ineligible")
	var days: int = int(row.get("time_languishing_days", 1))
	var params: Dictionary = {
		"caught_perpetrator_id": caught_perpetrator_id,
		"time_languishing_days": days,
	}
	return executor.launch(
		character_id, "await_trial",
		"anywhere", "",
		params, scheduler, party_id,
	)


# ===========================================================================
# bribe_magistrate — Singular minor.
# ===========================================================================

static func launch_bribe_magistrate(
		character_id: String,
		caught_perpetrator_id: String,
		bonus: int,
		executor,
		scheduler,
		party_id: String = "",
) -> Dictionary:
	if character_id.is_empty() or caught_perpetrator_id.is_empty():
		return _err("invalid_params")
	if not (bonus in [1, 2, 3]):
		return _err("invalid_params")
	var row := SyndicateRepository.get_caught(caught_perpetrator_id)
	if row.is_empty():
		return _err("no_caught_perpetrator")
	if row.get("verdict") != null:
		return _err("already_resolved")
	var params: Dictionary = {
		"caught_perpetrator_id": caught_perpetrator_id,
		"bonus": bonus,
	}
	return executor.launch(
		character_id, "bribe_magistrate",
		"anywhere", "",
		params, scheduler, party_id,
	)


# ===========================================================================
# hire_attorney — Singular minor.
# ===========================================================================

static func launch_hire_attorney(
		character_id: String,
		caught_perpetrator_id: String,
		rank: int,
		executor,
		scheduler,
		party_id: String = "",
) -> Dictionary:
	if character_id.is_empty() or caught_perpetrator_id.is_empty():
		return _err("invalid_params")
	if not (rank in [1, 2, 3]):
		return _err("invalid_params")
	var row := SyndicateRepository.get_caught(caught_perpetrator_id)
	if row.is_empty():
		return _err("no_caught_perpetrator")
	if row.get("verdict") != null:
		return _err("already_resolved")
	var params: Dictionary = {
		"caught_perpetrator_id": caught_perpetrator_id,
		"rank": rank,
	}
	return executor.launch(
		character_id, "hire_attorney",
		"anywhere", "",
		params, scheduler, party_id,
	)


# ===========================================================================
# interplead — Singular minor.
# ===========================================================================

static func launch_interplead(
		character_id: String,
		caught_perpetrator_id: String,
		executor,
		scheduler,
		party_id: String = "",
) -> Dictionary:
	if character_id.is_empty() or caught_perpetrator_id.is_empty():
		return _err("invalid_params")
	var row := SyndicateRepository.get_caught(caught_perpetrator_id)
	if row.is_empty():
		return _err("no_caught_perpetrator")
	if row.get("verdict") != null:
		return _err("already_resolved")
	var params: Dictionary = {
		"caught_perpetrator_id": caught_perpetrator_id,
	}
	return executor.launch(
		character_id, "interplead",
		"in_domain", "",
		params, scheduler, party_id,
	)


# ===========================================================================
# Helpers
# ===========================================================================

static func _err(code: String) -> Dictionary:
	return {"success": false, "activity_state_id": "", "error": code}


static func _hideout_location_ref(syndicate: Dictionary) -> String:
	if syndicate.is_empty():
		return ""
	var hid := String(syndicate.get("hideout_stronghold_id", ""))
	if hid.is_empty():
		return ""
	return "stronghold:%s" % hid


static func _settlement_location_ref(syndicate: Dictionary) -> String:
	if syndicate.is_empty():
		return ""
	var sid := String(syndicate.get("base_settlement_entrance_id", ""))
	if sid.is_empty():
		return ""
	return "settlement_entrance:%s" % sid
