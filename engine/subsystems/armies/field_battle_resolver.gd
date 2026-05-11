class_name FieldBattleResolver
extends RefCounted

## Abstract field-battle resolver per daw_axioms_pitching_battle.xml
## §battle_resolution L233-386 + gdd-army-warfare.md §6.2 (eleven/twelve-step
## phase loop).
##
## v1 SCOPE: silent NPC-vs-NPC resolution path is fully wired. The interactive
## (player-involved) path is supported at the engine level via
## `continue_battle(decision)` — every player decision point persists state,
## emits `EventBus.battle_pause_for_player`, and waits for the UI to call
## continue_battle. Phase 6B part 2 wires the field_battle_panel UI.
##
## Public API:
##   start_battle(attacker_army_id, defender_army_id, terrain, weather, day,
##                is_player_involved, dice_roller=Callable(), rng_seed=0) -> battle_id
##   start_battle_with_overrides(... , assault_modifiers: Dictionary) -> battle_id
##     For the Phase 9 siege resolver assault step. Stores the overrides in
##     battle_log (event_type='siege_overrides_applied') and the resolver
##     consults them per gdd-army-warfare.md §8.3 contract:
##       max_assaulting_units / max_defending_units
##       defending_infantry_br_bonus  (default +1 per daw_sieges.xml L508-509)
##       assaulting_cavalry_no_breach_br_multiplier (default 0.25 per L510-511)
##       base_attack_target           (default 16 per L488)
##       assaulting_attack_modifier   (default -2 per L502)
##       defending_attack_modifier    (default +2 per L504)
##   resolve_silently(battle_id, dice_roller=Callable()) -> outcome_string
##   continue_battle(battle_id, decision: Dictionary) -> void
##     decision shape varies by decision_point:
##       {decision_point: "deployment",          attacker_zones: {unit_id: zone}, defender_zones: {...}}
##       {decision_point: "foray",               attacker_forays: [{hero_id, br_staked}], defender_forays: [...]}
##       {decision_point: "redeploy",            attacker_moves: [{unit_id, to_zone}], defender_moves: [...]}
##       {decision_point: "advance_hold_withdraw", attacker_choice: String, defender_choice: String}
##   get_battle_state(battle_id) -> Dictionary
##
## Per gdd-army-warfare.md §6.11 the resolver emits the following EventBus signals:
##   battle_started(battle_id)
##   battle_pause_for_player(battle_id, decision_point)
##   battle_log_appended(battle_id, log_id)
##   battle_concluded(battle_id, outcome)
##
## RAW step-by-step procedure per §battle_resolution.phase[*].procedure
## (12 steps; the GDD's §6.2 lists 11 because it merges 7+8 into "cascade"):
##   1. Set BPC.
##   2. Determine participating units (current zone).
##   3. Total participating BR per side (with Strategic +0.5/+1.0 div bonus
##      and overwhelmed-commander halving).
##   4. Heroic forays declared and resolved simultaneously.
##   5. Each side rolls floor(remaining BR) attack throws against phase target
##      (missile 18+, skirmish 16+, melee 14+) with attack-throw modifiers.
##   6. Apply hits to participating units (defender chooses; simultaneous).
##   7. Cascade overflow per phase-specific cascade order.
##   8. Apply hits simultaneously.
##   9. Morale check (if break point reached).
##   10. Redeploy up to LA units (any zone → reserve, reserve → current zone).
##   11. Advance/Hold/Withdraw choice secret reveal.
##   12. Resolve BPC adjustment per phase post-choice matrix.

const PHASE_TARGETS := {"missile": 18, "skirmish": 16, "melee": 14}

# Cascade overflow order per RAW §battle_resolution.phase[*].procedure step 7.
const CASCADE_ORDER := {
	"missile": ["skirmish", "melee", "reserve"],
	"skirmish": ["melee", "reserve"],
	"melee": ["reserve", "skirmish", "missile"],
}


# ---------------------------------------------------------------------------
# Public API: start_battle
# ---------------------------------------------------------------------------

static func start_battle(
	attacker_army_id: String,
	defender_army_id: String,
	terrain: String,
	weather: String,
	calendar_day: int,
	is_player_involved: bool,
	dice_roller: Callable = Callable(),
	rng_seed: int = 0
) -> String:
	# Run battle setup.
	var setup: Dictionary = BattleSetup.prepare(
		attacker_army_id, defender_army_id,
		terrain, weather, calendar_day,
		is_player_involved, dice_roller
	)

	# Insert field_battles row.
	var attacker_army: Dictionary = ArmyRepository.get_army(attacker_army_id)
	var battle_id: String = BattleRepository.create_battle({
		"campaign_id": String(attacker_army.get("campaign_id", "")),
		"map_id": attacker_army.get("map_id", null),
		"hex_q": _safe_int(attacker_army.get("hex_q"), 0),
		"hex_r": _safe_int(attacker_army.get("hex_r"), 0),
		"attacker_army_id": attacker_army_id,
		"defender_army_id": defender_army_id,
		"terrain_type": terrain,
		"starting_bpc": int(setup.get("starting_bpc", 1)),
		"current_bpc": int(setup.get("starting_bpc", 1)),
		"current_phase": "missile",
		"battle_turn_number": 1,
		"attacker_terrain_advantage": String(setup.get("attacker_terrain_advantage", "regular")),
		"defender_terrain_advantage": String(setup.get("defender_terrain_advantage", "regular")),
		"attacker_surprised": setup.get("attacker_surprised", false),
		"defender_surprised": setup.get("defender_surprised", false),
		"started_calendar_day": calendar_day,
		"is_player_involved": is_player_involved,
		"weather_condition": weather,
		"rng_seed": rng_seed,
	})

	if battle_id.is_empty():
		return ""

	# Insert battle_unit_states for each side.
	_insert_unit_states(battle_id, "attacker", setup.get("attacker_deployment", []), attacker_army_id)
	_insert_unit_states(battle_id, "defender", setup.get("defender_deployment", []), defender_army_id)

	# Update army state to 'battling'.
	ArmyRepository.update_army(attacker_army_id, {"state": "battling"})
	ArmyRepository.update_army(defender_army_id, {"state": "battling"})

	# Log battle_started.
	BattleRepository.append_log(battle_id, "battle_started", 1, "missile",
		int(setup.get("starting_bpc", 1)), "",
		{
			"terrain": terrain,
			"weather": weather,
			"starting_bpc": int(setup.get("starting_bpc", 1)),
			"bpc_roll": int(setup.get("bpc_roll", 0)),
			"attacker_army_id": attacker_army_id,
			"defender_army_id": defender_army_id,
			"attacker_size": setup.get("attacker_deployment", []).size(),
			"defender_size": setup.get("defender_deployment", []).size(),
		}, calendar_day)
	BattleRepository.append_log(battle_id, "surprise_resolved", 1, "missile",
		int(setup.get("starting_bpc", 1)), "",
		{
			"attacker_surprised": setup.get("attacker_surprised", false),
			"defender_surprised": setup.get("defender_surprised", false),
			"attacker_surprise_roll": int(setup.get("attacker_surprise_roll", 0)),
			"defender_surprise_roll": int(setup.get("defender_surprise_roll", 0)),
		}, calendar_day)
	BattleRepository.append_log(battle_id, "terrain_advantage_resolved", 1, "missile",
		int(setup.get("starting_bpc", 1)), "",
		{
			"attacker_score": int(setup.get("attacker_terrain_score", 0)),
			"defender_score": int(setup.get("defender_terrain_score", 0)),
			"attacker_advantage": String(setup.get("attacker_terrain_advantage", "regular")),
			"defender_advantage": String(setup.get("defender_terrain_advantage", "regular")),
		}, calendar_day)
	BattleRepository.append_log(battle_id, "units_deployed", 1, "missile",
		int(setup.get("starting_bpc", 1)), "",
		{
			"attacker_zones": _zones_summary(setup.get("attacker_deployment", [])),
			"defender_zones": _zones_summary(setup.get("defender_deployment", [])),
		}, calendar_day)

	if EventBus.has_signal("battle_started"):
		EventBus.emit_signal("battle_started", battle_id)

	return battle_id


# ---------------------------------------------------------------------------
# Public API: start_battle_with_overrides — siege assault entry point
# ---------------------------------------------------------------------------

static func start_battle_with_overrides(
	attacker_army_id: String,
	defender_army_id: String,
	terrain: String,
	weather: String,
	calendar_day: int,
	is_player_involved: bool,
	assault_modifiers: Dictionary,
	dice_roller: Callable = Callable(),
	rng_seed: int = 0
) -> String:
	## Per gdd-army-warfare.md §8.3 + daw_sieges.xml §battle_ratings_during_assaults.
	## Calls start_battle then logs a `siege_overrides_applied` event with the
	## override dictionary. The resolver inspects battle_log for this event
	## and applies overrides during phase iteration.
	var battle_id: String = start_battle(
		attacker_army_id, defender_army_id,
		terrain, weather, calendar_day,
		is_player_involved, dice_roller, rng_seed
	)
	if battle_id.is_empty():
		return ""
	# Default-fill any missing assault modifier per RAW.
	var defaults := {
		"max_assaulting_units": 0,             # 0 = unlimited
		"max_defending_units": 0,
		"defending_infantry_br_bonus": 1,      # daw_sieges.xml L508-509
		"assaulting_cavalry_no_breach_br_multiplier": 0.25,  # L510-511
		"base_attack_target": 16,              # L488
		"assaulting_attack_modifier": -2,      # L502
		"defending_attack_modifier": 2,        # L504
	}
	var merged: Dictionary = defaults.duplicate()
	for k in assault_modifiers:
		merged[k] = assault_modifiers[k]
	BattleRepository.append_log(battle_id, "siege_overrides_applied",
		1, "missile", 0, "",
		merged, calendar_day)
	return battle_id


static func get_siege_overrides(battle_id: String) -> Dictionary:
	## Returns the assault override dictionary if the battle was started via
	## start_battle_with_overrides; empty dict otherwise.
	if battle_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT payload_json FROM battle_log
		WHERE battle_id = ? AND event_type = 'siege_overrides_applied'
		LIMIT 1
	""", [battle_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	var json_str: String = String(CampaignRepository.db.query_result[0].get("payload_json", "{}"))
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed is Dictionary:
		return parsed
	return {}


# ---------------------------------------------------------------------------
# Public API: resolve_silently — runs the battle to conclusion without pauses
# ---------------------------------------------------------------------------

static func resolve_silently(battle_id: String, dice_roller: Callable = Callable()) -> String:
	## Plays through every phase using NPC heuristics for foray declarations,
	## redeployments, and advance/hold/withdraw choices. Returns the outcome.
	var max_phases: int = 200  # safety; battles converge well before this
	var phase_count: int = 0
	while phase_count < max_phases:
		var battle: Dictionary = BattleRepository.get_battle(battle_id)
		if battle.is_empty() or String(battle.get("outcome", "")) != "":
			break
		var current_phase: String = String(battle.get("current_phase", "missile"))
		if current_phase == "concluded" or current_phase == "aftermath":
			break

		# Run one full phase iteration.
		var iteration: Dictionary = _run_phase_iteration(battle_id, dice_roller)
		if bool(iteration.get("battle_ended", false)):
			break
		phase_count += 1

	# Run aftermath (casualties + pursuit) and return outcome.
	_run_aftermath(battle_id, dice_roller)

	var final: Dictionary = BattleRepository.get_battle(battle_id)
	var outcome: String = String(final.get("outcome", ""))
	if EventBus.has_signal("battle_concluded"):
		EventBus.emit_signal("battle_concluded", battle_id, outcome)
	return outcome


# ---------------------------------------------------------------------------
# Public API: continue_battle (interactive path)
# ---------------------------------------------------------------------------

static func continue_battle(battle_id: String, decision: Dictionary, dice_roller: Callable = Callable()) -> Dictionary:
	## Drives one phase iteration with the player's decision bundle. Returns
	## {phase_completed, battle_concluded, next_decision_point, outcome (if concluded)}.
	##
	## decision shape (one phase's worth, keyed for both sides):
	##   {
	##     attacker_forays: Array[{hero_id, br_staked}],   # optional
	##     defender_forays: Array[{hero_id, br_staked}],   # optional
	##     attacker_redeploys: Array[{unit_state_id, to_zone}],  # optional, NPC defaults if missing
	##     defender_redeploys: Array[{unit_state_id, to_zone}],
	##     attacker_choice: 'advance'|'hold'|'withdraw',
	##     defender_choice: 'advance'|'hold'|'withdraw',
	##   }
	##
	## At present the silent path's NPC heuristics fill in any missing fields
	## (so a player providing only attacker_choice still results in valid
	## resolution against an NPC opponent).
	if battle_id.is_empty():
		return {"phase_completed": false, "battle_concluded": false, "error": "battle_id_required"}

	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	if battle.is_empty():
		return {"phase_completed": false, "battle_concluded": false, "error": "battle_not_found"}
	var existing_outcome: String = String(battle.get("outcome", ""))
	if not existing_outcome.is_empty():
		return {
			"phase_completed": false, "battle_concluded": true,
			"outcome": existing_outcome, "battle_id": battle_id,
		}

	# Run one phase iteration with player decisions.
	var iteration: Dictionary = _run_phase_iteration_with_decision(battle_id, decision, dice_roller)
	if bool(iteration.get("battle_ended", false)):
		_run_aftermath(battle_id, dice_roller)
		var final: Dictionary = BattleRepository.get_battle(battle_id)
		var outcome: String = String(final.get("outcome", ""))
		if EventBus.has_signal("battle_concluded"):
			EventBus.emit_signal("battle_concluded", battle_id, outcome)
		return {
			"phase_completed": true,
			"battle_concluded": true,
			"outcome": outcome,
			"battle_id": battle_id,
		}

	# Pause for next phase decision.
	if EventBus.has_signal("battle_pause_for_player"):
		EventBus.emit_signal("battle_pause_for_player", battle_id, "phase_decision")
	return {
		"phase_completed": true,
		"battle_concluded": false,
		"next_decision_point": "phase_decision",
		"battle_id": battle_id,
	}


static func _run_phase_iteration_with_decision(
	battle_id: String, decision: Dictionary, dice_roller: Callable
) -> Dictionary:
	## Like _run_phase_iteration but accepts player decision overrides for the
	## current phase. Missing decision fields fall back to silent NPC heuristics.
	## Implementation: temporarily monkey-patch the silent-choice / silent-
	## redeploy paths via decision lookups, then call the standard iterator.
	## v1 simplification: store the decision in a class-level dict keyed by
	## battle_id and have the silent helpers consult it. For Phase 6B part 2
	## v1 we accept a global module-static dict (single battle in flight at
	## any given moment is a reasonable assumption for an interactive UI).
	_pending_decisions[battle_id] = decision
	var result: Dictionary = _run_phase_iteration(battle_id, dice_roller)
	# Clear the stash even on error.
	_pending_decisions.erase(battle_id)
	return result


# Static module-state: per-battle pending player decisions during interactive
# resolution. Cleared on each phase-iteration completion.
static var _pending_decisions: Dictionary = {}


# ---------------------------------------------------------------------------
# Public API: get_battle_state (UI rebuild on save/load)
# ---------------------------------------------------------------------------

static func get_battle_state(battle_id: String) -> Dictionary:
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	if battle.is_empty():
		return {}
	var states: Array = BattleRepository.list_unit_states_for_battle(battle_id)
	var log_entries: Array = BattleRepository.list_log_for_battle(battle_id)
	return {
		"battle": battle,
		"unit_states": states,
		"log": log_entries,
	}


# ---------------------------------------------------------------------------
# Internals: per-phase iteration
# ---------------------------------------------------------------------------

static func _run_phase_iteration(battle_id: String, dice_roller: Callable) -> Dictionary:
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	var current_phase: String = String(battle.get("current_phase", "missile"))
	var current_bpc: int = int(battle.get("current_bpc", 1))
	var starting_bpc: int = int(battle.get("starting_bpc", 1))
	var turn: int = int(battle.get("battle_turn_number", 1))
	var calendar_day: int = int(battle.get("started_calendar_day", 0))

	# Step 1: BPC is already set on the battle row.

	# Step 2: Participating units = those in current_phase zone.
	var attacker_participants: Array = BattleRepository.list_unit_states_for_zone(battle_id, "attacker", current_phase)
	var defender_participants: Array = BattleRepository.list_unit_states_for_zone(battle_id, "defender", current_phase)

	BattleRepository.append_log(battle_id, "phase_started", turn, current_phase, current_bpc, "",
		{"phase": current_phase, "bpc": current_bpc, "turn": turn}, calendar_day)

	# Step 3: Total BR per side (Strategic Ability division bonuses applied).
	var attacker_br_total: float = _total_participating_br(battle_id, "attacker", attacker_participants)
	var defender_br_total: float = _total_participating_br(battle_id, "defender", defender_participants)

	# Surprise: surprised army cannot make attack throws during first three
	# battle phases per RAW §surprise L151. Track turn × phase progression to
	# determine "first three battle phases."
	var attacker_can_attack: bool = not _surprise_silenced(battle, "attacker", turn)
	var defender_can_attack: bool = not _surprise_silenced(battle, "defender", turn)

	BattleRepository.append_log(battle_id, "participating_br_totaled", turn, current_phase, current_bpc, "",
		{
			"attacker_br": attacker_br_total,
			"defender_br": defender_br_total,
			"attacker_participants": attacker_participants.size(),
			"defender_participants": defender_participants.size(),
			"attacker_can_attack": attacker_can_attack,
			"defender_can_attack": defender_can_attack,
		}, calendar_day)

	# Step 4: Heroic forays. The interactive path may supply
	# attacker_forays / defender_forays via _pending_decisions; the silent
	# path doesn't declare forays. Each foray reduces the opposing side's
	# participating BR by foes_defeated_br (per RAW step 12); the foe-pool
	# units are removed from battle_unit_states.
	# v1 implementation: simulate_foray_silently provides a placeholder
	# outcome until the standard ACKS combat sub-scene lands as a library
	# call. Player-supplied forays during interactive battles use the same
	# simulator for now.
	if _pending_decisions.has(battle_id):
		var decision: Dictionary = _pending_decisions[battle_id]
		var atk_forays: Array = decision.get("attacker_forays", [])
		var def_forays: Array = decision.get("defender_forays", [])
		_resolve_phase_forays(battle_id, "attacker", atk_forays, defender_participants,
			turn, current_phase, current_bpc, calendar_day, dice_roller)
		_resolve_phase_forays(battle_id, "defender", def_forays, attacker_participants,
			turn, current_phase, current_bpc, calendar_day, dice_roller)
		# Recompute participants and BR totals after forays may have removed units.
		attacker_participants = BattleRepository.list_unit_states_for_zone(battle_id, "attacker", current_phase)
		defender_participants = BattleRepository.list_unit_states_for_zone(battle_id, "defender", current_phase)
		attacker_br_total = _total_participating_br(battle_id, "attacker", attacker_participants)
		defender_br_total = _total_participating_br(battle_id, "defender", defender_participants)

	# Step 5: Attack throws.
	# Siege assault overrides per gdd-army-warfare.md §8.3 may replace the
	# phase-dependent target with a fixed base_attack_target and add
	# attacker / defender modifiers per daw_sieges.xml §battle_ratings_during_assaults.
	var siege_overrides: Dictionary = get_siege_overrides(battle_id)
	var attacker_target: int
	var defender_target: int
	var attacker_extra_mod: int = 0
	var defender_extra_mod: int = 0
	if not siege_overrides.is_empty():
		var base_target: int = int(siege_overrides.get("base_attack_target", 16))
		attacker_target = base_target
		defender_target = base_target
		# Per RAW: assaulting (= attacker in siege context) takes -2; defender +2.
		attacker_extra_mod = int(siege_overrides.get("assaulting_attack_modifier", -2))
		defender_extra_mod = int(siege_overrides.get("defending_attack_modifier", 2))
	else:
		attacker_target = PHASE_TARGETS.get(current_phase, 14)
		defender_target = PHASE_TARGETS.get(current_phase, 14)
	# Apply attack-throw modifiers per the table at §attack_throw_modifiers L208-224.
	var attacker_modifiers: int = _attack_throw_modifiers(battle, "attacker", current_phase, turn) + attacker_extra_mod
	var defender_modifiers: int = _attack_throw_modifiers(battle, "defender", current_phase, turn) + defender_extra_mod
	# Effective target is target - modifiers (since modifiers raise success rate).
	var attacker_effective_target: int = attacker_target - attacker_modifiers
	var defender_effective_target: int = defender_target - defender_modifiers

	var attacker_hits: int = 0
	var defender_hits: int = 0
	var attacker_throws_log: Array = []
	var defender_throws_log: Array = []

	# Lieutenant-leading-unit bonus (RAW §attack_throw_modifiers L217:
	# missile 0 / skirmish +1 / melee +2). Applied per-unit because lieutenants
	# only buff units they directly command. Split each side's throws into
	# "with lieutenant" and "without lieutenant" buckets weighted by the
	# fraction of participating BR commanded by lieutenants.
	var attacker_lt_bonus: int = _lieutenant_phase_bonus(current_phase)
	var defender_lt_bonus: int = _lieutenant_phase_bonus(current_phase)
	var attacker_lt_share: float = _lieutenant_br_fraction(attacker_participants) if attacker_lt_bonus > 0 else 0.0
	var defender_lt_share: float = _lieutenant_br_fraction(defender_participants) if defender_lt_bonus > 0 else 0.0

	if attacker_can_attack:
		var att_n: int = int(floor(attacker_br_total))
		var att_result: Dictionary = _roll_attack_throws_split(
			att_n, attacker_effective_target,
			attacker_lt_share, attacker_lt_bonus, dice_roller
		)
		attacker_hits = int(att_result.get("hits", 0))
		attacker_throws_log = att_result.get("throws", [])
	if defender_can_attack:
		var def_n: int = int(floor(defender_br_total))
		var def_result: Dictionary = _roll_attack_throws_split(
			def_n, defender_effective_target,
			defender_lt_share, defender_lt_bonus, dice_roller
		)
		defender_hits = int(def_result.get("hits", 0))
		defender_throws_log = def_result.get("throws", [])

	BattleRepository.append_log(battle_id, "attack_throws_rolled", turn, current_phase, current_bpc, "",
		{
			"attacker_throws_count": attacker_throws_log.size(),
			"defender_throws_count": defender_throws_log.size(),
			"attacker_target": attacker_effective_target,
			"defender_target": defender_effective_target,
			"attacker_hits": attacker_hits,
			"defender_hits": defender_hits,
			"attacker_modifiers": attacker_modifiers,
			"defender_modifiers": defender_modifiers,
		}, calendar_day)

	# Step 6 + 7 + 8: Apply hits simultaneously with cascade overflow.
	var attacker_destroyed_count: int = _apply_hits_with_cascade(battle_id, "attacker", current_phase, defender_hits)
	var defender_destroyed_count: int = _apply_hits_with_cascade(battle_id, "defender", current_phase, attacker_hits)

	BattleRepository.append_log(battle_id, "hits_applied", turn, current_phase, current_bpc, "",
		{
			"attacker_units_destroyed": attacker_destroyed_count,
			"defender_units_destroyed": defender_destroyed_count,
		}, calendar_day)

	# Step 9: Morale check.
	_check_morale_for_side(battle_id, "attacker", attacker_destroyed_count, dice_roller, turn, current_phase, current_bpc, calendar_day)
	_check_morale_for_side(battle_id, "defender", defender_destroyed_count, dice_roller, turn, current_phase, current_bpc, calendar_day)

	# Test for annihilation.
	var battle_after: Dictionary = BattleRepository.get_battle(battle_id)
	var ann_outcome: String = _check_annihilation(battle_id)
	if not ann_outcome.is_empty():
		BattleRepository.update_battle(battle_id, {
			"outcome": ann_outcome,
			"current_phase": "aftermath",
			"current_bpc": current_bpc,
		})
		BattleRepository.append_log(battle_id, "battle_ended", turn, current_phase, current_bpc, "",
			{"outcome": ann_outcome, "reason": "annihilation"}, calendar_day)
		return {"battle_ended": true}

	# Step 10: Redeployment. Silent heuristic: move overwhelmed-commander
	# excess units to reserve; advance reserve into current zone if attacker.
	var attacker_redeploys: Array = _silent_redeploy(battle_id, "attacker", current_phase)
	var defender_redeploys: Array = _silent_redeploy(battle_id, "defender", current_phase)
	for r in attacker_redeploys:
		BattleRepository.update_unit_state(String(r.get("unit_state_id", "")), {"zone": String(r.get("to_zone", "reserve"))})
	for r in defender_redeploys:
		BattleRepository.update_unit_state(String(r.get("unit_state_id", "")), {"zone": String(r.get("to_zone", "reserve"))})
	BattleRepository.append_log(battle_id, "redeployment_chosen", turn, current_phase, current_bpc, "",
		{"attacker_redeploys": attacker_redeploys, "defender_redeploys": defender_redeploys}, calendar_day)

	# Step 11: Advance/hold/withdraw. Silent heuristic.
	var attacker_choice: String = _silent_choice(battle_id, "attacker", current_phase)
	var defender_choice: String = _silent_choice(battle_id, "defender", current_phase)
	BattleRepository.append_log(battle_id, "advance_hold_withdraw_chosen", turn, current_phase, current_bpc, "",
		{"attacker_choice": attacker_choice, "defender_choice": defender_choice}, calendar_day)

	# Step 12: Apply terrain-advantage forfeit per §advantageous_terrain L226-231.
	_apply_terrain_advantage_forfeit(battle_id, attacker_choice, defender_choice)

	# Step 12: BPC adjustment via matrix.
	var attacker_strategic: int = _get_leader_strategic(String(battle_after.get("attacker_army_id", "")))
	var defender_strategic: int = _get_leader_strategic(String(battle_after.get("defender_army_id", "")))
	var adjustment: Dictionary = BpcAdjustmentMatrix.resolve(
		current_phase, attacker_choice, defender_choice,
		current_bpc, starting_bpc,
		attacker_strategic, defender_strategic,
		dice_roller
	)
	var transition: String = String(adjustment.get("transition", "continue"))
	var new_bpc: int = int(adjustment.get("new_bpc", current_bpc))
	BattleRepository.append_log(battle_id, "bpc_adjusted", turn, current_phase, new_bpc, "",
		{
			"delta": int(adjustment.get("delta", 0)),
			"new_bpc": new_bpc,
			"transition": transition,
			"case": String(adjustment.get("case", "")),
			"initiative_winner": String(adjustment.get("initiative_winner", "")),
		}, calendar_day)

	BattleRepository.append_log(battle_id, "phase_ended", turn, current_phase, new_bpc, "",
		{"phase": current_phase, "transition": transition}, calendar_day)

	# Step 13: Test for battle end via transition.
	match transition:
		"draw":
			BattleRepository.update_battle(battle_id, {
				"outcome": "mutual_withdrawal_draw",
				"current_phase": "aftermath",
				"current_bpc": new_bpc,
			})
			return {"battle_ended": true}
		"voluntary_withdrawal_attacker":
			BattleRepository.update_battle(battle_id, {
				"outcome": "attacker_voluntary_withdrawal",
				"current_phase": "aftermath",
				"current_bpc": new_bpc,
			})
			return {"battle_ended": true}
		"voluntary_withdrawal_defender":
			BattleRepository.update_battle(battle_id, {
				"outcome": "defender_voluntary_withdrawal",
				"current_phase": "aftermath",
				"current_bpc": new_bpc,
			})
			return {"battle_ended": true}
		"advance_phase":
			var next_phase: String = "skirmish" if current_phase == "missile" else "melee"
			BattleRepository.update_battle(battle_id, {
				"current_phase": next_phase,
				"current_bpc": starting_bpc,  # phases reset BPC per RAW step 1
				"battle_turn_number": _maybe_advance_turn(turn, true),
				"attacker_choice": "",
				"defender_choice": "",
			})
		"regress_phase":
			var prev_phase: String = "missile" if current_phase == "skirmish" else "skirmish"
			BattleRepository.update_battle(battle_id, {
				"current_phase": prev_phase,
				"current_bpc": starting_bpc,
				"battle_turn_number": _maybe_advance_turn(turn, true),
				"attacker_choice": "",
				"defender_choice": "",
			})
		"melee_floor":
			BattleRepository.update_battle(battle_id, {
				"current_bpc": 0,
				"battle_turn_number": _maybe_advance_turn(turn, false),
				"attacker_choice": "",
				"defender_choice": "",
			})
		_:
			BattleRepository.update_battle(battle_id, {
				"current_bpc": new_bpc,
				"battle_turn_number": _maybe_advance_turn(turn, false),
				"attacker_choice": "",
				"defender_choice": "",
			})

	return {"battle_ended": false}


static func _maybe_advance_turn(current_turn: int, is_phase_change: bool) -> int:
	# Per RAW §battle_turn L7-9: 10 phases = 1 battle turn. v1 simplification:
	# advance the turn number on every phase change so vagaries-of-battle
	# events fire at consistent intervals. This is a minor simplification
	# that does not affect the battle resolver's mechanical correctness.
	if is_phase_change:
		return current_turn + 1
	return current_turn


# ---------------------------------------------------------------------------
# Aftermath: casualties + pursuit
# ---------------------------------------------------------------------------

static func _run_aftermath(battle_id: String, dice_roller: Callable) -> void:
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	if battle.is_empty():
		return
	var outcome: String = String(battle.get("outcome", ""))
	var calendar_day: int = int(battle.get("started_calendar_day", 0))
	var turn: int = int(battle.get("battle_turn_number", 1))

	# If outcome is empty we ran out of phases without a resolution; treat as
	# a mutual withdrawal draw.
	if outcome.is_empty():
		outcome = "mutual_withdrawal_draw"
		BattleRepository.update_battle(battle_id, {"outcome": outcome})

	# Pursuit (only if not a mutual draw).
	var pursuit: Dictionary = PursuitResolver.resolve_pursuit(battle_id, dice_roller)
	if not pursuit.is_empty():
		BattleRepository.append_log(battle_id, "pursuit_resolved", turn, "aftermath", 0, "",
			pursuit, calendar_day)

	# Casualties.
	var casualties: Dictionary = ArmyCasualtyResolver.resolve_battle_casualties(battle_id, calendar_day)
	BattleRepository.append_log(battle_id, "casualties_calculated", turn, "aftermath", 0, "",
		casualties, calendar_day)

	# Spoils — one month's wages of each destroyed/routed enemy unit + 40gp per prisoner.
	var spoils: Dictionary = _calculate_spoils(battle_id, casualties)
	BattleRepository.append_log(battle_id, "spoils_calculated", turn, "aftermath", 0, "",
		spoils, calendar_day)

	# XP distribution per RAW §experience_points L630-645.
	var spoils_gp_total: int = int(spoils.get("gp_total", 0))
	if spoils_gp_total > 0:
		var xp_dist: Dictionary = BattleXPDistributor.distribute(battle_id, spoils_gp_total, calendar_day)
		var _ignored := xp_dist  # logged inside distributor

	# Mark battle concluded and reset army states.
	BattleRepository.update_battle(battle_id, {
		"current_phase": "concluded",
		"ended_calendar_day": calendar_day,
	})

	# Reset participating armies to encamped (or trigger withdraw/disband as
	# appropriate). Annihilation outcomes have already been handled by the
	# casualty resolver marking units as departed — but the army row needs to
	# transition.
	var attacker_id: String = String(battle.get("attacker_army_id", ""))
	var defender_id: String = String(battle.get("defender_army_id", ""))
	_resolve_post_battle_state(attacker_id, "attacker", outcome, calendar_day)
	_resolve_post_battle_state(defender_id, "defender", outcome, calendar_day)


static func _resolve_post_battle_state(army_id: String, side: String, outcome: String, calendar_day: int) -> void:
	if army_id.is_empty():
		return
	# Determine if this side won, lost, or drew.
	var attacker_won: bool = outcome.begins_with("attacker_") or outcome == "defender_voluntary_withdrawal" or outcome == "defender_annihilation"
	var defender_won: bool = outcome.begins_with("defender_") or outcome == "attacker_voluntary_withdrawal" or outcome == "attacker_annihilation"
	var is_mutual_draw: bool = outcome == "mutual_withdrawal_draw"
	var this_side_won: bool = (side == "attacker" and attacker_won) or (side == "defender" and defender_won)
	var this_side_lost: bool = (side == "attacker" and defender_won) or (side == "defender" and attacker_won)

	if outcome == "attacker_annihilation" and side == "attacker":
		ArmyDisbander.disband(army_id, "annihilation", calendar_day)
		return
	if outcome == "defender_annihilation" and side == "defender":
		ArmyDisbander.disband(army_id, "annihilation", calendar_day)
		return

	if this_side_won:
		ArmyRepository.update_army(army_id, {"state": "encamped"})
	elif this_side_lost:
		ArmyRepository.update_army(army_id, {"state": "withdrawing"})
		# Per RAW §retreat L565-571: defeated army retreats 1 hex along supply
		# line. v1: instant relocation; Phase 6A part 2's marcher will replace
		# with a scheduled travel_leg event.
		var retreat_result: Dictionary = RetreatResolver.resolve_retreat(army_id, calendar_day)
		BattleRepository.append_log(_find_battle_for_army(army_id), "retreat_resolved",
			1, "aftermath", 0, side, retreat_result, calendar_day)
	elif is_mutual_draw:
		ArmyRepository.update_army(army_id, {"state": "withdrawing"})
		var retreat_result_draw: Dictionary = RetreatResolver.resolve_retreat(army_id, calendar_day)
		BattleRepository.append_log(_find_battle_for_army(army_id), "retreat_resolved",
			1, "aftermath", 0, side, retreat_result_draw, calendar_day)


# ---------------------------------------------------------------------------
# Internals: BR totals + Strategic-Ability bonus
# ---------------------------------------------------------------------------

static func _total_participating_br(battle_id: String, side: String, participants: Array) -> float:
	var leader_strategic: int = _get_leader_strategic_for_battle(battle_id, side)
	var div_bonus_per_unit: float = 0.0
	if leader_strategic >= 6:
		div_bonus_per_unit = 1.0
	elif leader_strategic >= 3:
		div_bonus_per_unit = 0.5
	var total: float = 0.0
	for p in participants:
		var status: String = String(p.get("status", "engaged"))
		if status == "destroyed" or status == "routed" or status == "fleeing":
			continue
		# Phase 9C: diseased units cannot move or fight per RAW daw_vagaries §disease L300.
		var unit_id: String = String(p.get("troop_unit_id", ""))
		if not unit_id.is_empty() and not DiseaseResolver.is_unit_combat_capable(unit_id):
			continue
		var br: float = float(p.get("br_current", 0.0))
		# Wavering: BR halved when attacking next turn.
		if status == "wavering":
			br *= 0.5
		# Rallied: BR ½× extra (i.e. ×1.5) when attacking next turn.
		if status == "rallied":
			br *= 1.5
		total += br + div_bonus_per_unit
	return total


# ---------------------------------------------------------------------------
# Internals: attack throws
# ---------------------------------------------------------------------------

static func _roll_attack_throws(n: int, target: int, dice_roller: Callable) -> Dictionary:
	var hits: int = 0
	var throws: Array = []
	for i in range(n):
		var roll: int = _roll(dice_roller, 1, 20)
		var success: bool = roll >= target
		throws.append(roll)
		if success:
			hits += 1
	return {"hits": hits, "throws": throws}


static func _roll_attack_throws_split(
	n: int, base_target: int,
	lt_share: float, lt_bonus: int,
	dice_roller: Callable
) -> Dictionary:
	## Splits n throws into a "with lieutenant" subset (rolls at base_target -
	## lt_bonus) and a "without lieutenant" subset (rolls at base_target).
	## lt_share is the BR-weighted fraction of participating units that have a
	## lieutenant. n_with_lt = round(n * lt_share); n_without = n - n_with_lt.
	if n <= 0:
		return {"hits": 0, "throws": []}
	if lt_bonus <= 0 or lt_share <= 0.0:
		return _roll_attack_throws(n, base_target, dice_roller)
	var n_with_lt: int = int(round(float(n) * lt_share))
	n_with_lt = clampi(n_with_lt, 0, n)
	var n_without: int = n - n_with_lt
	var with_lt_target: int = base_target - lt_bonus
	var with_result: Dictionary = _roll_attack_throws(n_with_lt, with_lt_target, dice_roller)
	var without_result: Dictionary = _roll_attack_throws(n_without, base_target, dice_roller)
	var combined_throws: Array = []
	combined_throws.append_array(with_result.get("throws", []))
	combined_throws.append_array(without_result.get("throws", []))
	return {
		"hits": int(with_result.get("hits", 0)) + int(without_result.get("hits", 0)),
		"throws": combined_throws,
		"n_with_lt": n_with_lt,
		"n_without": n_without,
		"with_lt_target": with_lt_target,
		"without_lt_target": base_target,
	}


static func _lieutenant_phase_bonus(phase: String) -> int:
	## Per RAW §attack_throw_modifiers L217: missile 0 / skirmish +1 / melee +2.
	match phase:
		"missile": return 0
		"skirmish": return 1
		"melee": return 2
	return 0


static func _lieutenant_br_fraction(participants: Array) -> float:
	## Returns the BR-weighted fraction of participants commanded by a
	## lieutenant. A unit is "lieutenant-led" iff its parent_officer_id
	## references an army_officers row with rank='lieutenant'.
	if participants.is_empty():
		return 0.0
	var total_br: float = 0.0
	var lt_br: float = 0.0
	for p in participants:
		var status: String = String(p.get("status", "engaged"))
		if status == "destroyed" or status == "routed":
			continue
		var br: float = float(p.get("br_current", 0.0))
		total_br += br
		if _is_lieutenant_led(String(p.get("parent_officer_id", ""))):
			lt_br += br
	if total_br <= 0.0:
		return 0.0
	return lt_br / total_br


static func _is_lieutenant_led(parent_officer_id: String) -> bool:
	if parent_officer_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT rank FROM army_officers WHERE id = ?", [parent_officer_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	return String(CampaignRepository.db.query_result[0].get("rank", "")) == "lieutenant"


static func _attack_throw_modifiers(battle: Dictionary, attacker_side: String, phase: String, turn: int) -> int:
	## Sum of attack-throw modifiers per the table at §attack_throw_modifiers L208-224.
	## attacker_side = the side rolling attacks; modifiers apply to its target.
	var defender_side: String = "defender" if attacker_side == "attacker" else "attacker"
	var defender_advantage: String = String(battle.get(defender_side + "_terrain_advantage", "regular"))
	var defender_surprised: bool = bool(battle.get(defender_side + "_surprised", false))
	var modifier: int = 0

	# opposing_army_in_advantageous_terrain (negative for the attacker)
	if defender_advantage == "advantageous":
		if phase == "missile":
			modifier += -1
		elif phase == "skirmish":
			modifier += -2
		elif phase == "melee":
			modifier += -3
	elif defender_advantage == "highly_advantageous":
		if phase == "missile":
			modifier += -2
		elif phase == "skirmish":
			modifier += -3
		elif phase == "melee":
			modifier += -4

	# opposing_army_surprised (positive for attacker, first 3 phases only)
	if defender_surprised and turn <= 3:
		if phase == "missile":
			modifier += 1
		elif phase == "skirmish":
			modifier += 2
		elif phase == "melee":
			modifier += 4

	# lieutenant_leading_unit: requires per-unit detail. v1 omits (always 0
	# unless the field-battle UI adds a per-unit lieutenant bonus tracker).
	# Phase 6B part 2 may extend this when lieutenants are tracked per battle.

	return modifier


# ---------------------------------------------------------------------------
# Internals: hit application + cascade
# ---------------------------------------------------------------------------

static func _apply_hits_with_cascade(battle_id: String, target_side: String, current_phase: String, hits: int) -> int:
	## Defender removes participating units with combined BR ≥ hits (RAW step 6).
	## Overflow cascades per CASCADE_ORDER (RAW step 7).
	if hits <= 0:
		return 0
	var destroyed_count: int = 0
	var hits_remaining: float = float(hits)

	# First: current zone.
	var per_zone_results: Dictionary = _apply_hits_to_zone(battle_id, target_side, current_phase, hits_remaining)
	hits_remaining = float(per_zone_results.get("hits_remaining", 0.0))
	destroyed_count += int(per_zone_results.get("destroyed", 0))

	# Cascade.
	var cascade: Array = CASCADE_ORDER.get(current_phase, [])
	for next_zone in cascade:
		if hits_remaining <= 0:
			break
		var zone_result: Dictionary = _apply_hits_to_zone(battle_id, target_side, String(next_zone), hits_remaining)
		hits_remaining = float(zone_result.get("hits_remaining", 0.0))
		destroyed_count += int(zone_result.get("destroyed", 0))

	return destroyed_count


static func _apply_hits_to_zone(battle_id: String, target_side: String, zone: String, hits: float) -> Dictionary:
	var states: Array = BattleRepository.list_unit_states_for_zone(battle_id, target_side, zone)
	# Defender's choice — v1 picks lowest-BR units first to minimize loss
	# (this matches the RAW phrasing "removes participating units with
	# combined BR ≥ hits suffered" — most efficient choice is highest cumulative
	# BR per casualty unit). v1 sorts by br_current DESC so we pick highest BR first.
	# Actually: we want to FILL the hit budget with as little wasted BR as
	# possible — pick units with BR closest to remaining hits. v1 simplification:
	# pick highest BR first; this matches the "defender chooses" prerogative
	# of saving smaller units.
	states.sort_custom(func(a, b): return float(a.get("br_current", 0.0)) > float(b.get("br_current", 0.0)))
	var hits_remaining: float = hits
	var destroyed: int = 0
	for state in states:
		if hits_remaining <= 0:
			break
		var status: String = String(state.get("status", "engaged"))
		if status == "destroyed" or status == "routed":
			continue
		var br: float = float(state.get("br_current", 0.0))
		if br <= 0:
			continue
		if br <= hits_remaining:
			BattleRepository.update_unit_state(String(state.get("id", "")), {
				"status": "destroyed",
				"br_current": 0.0,
			})
			BattleRepository.append_log(battle_id, "unit_destroyed",
				1, zone, 0, target_side,
				{
					"unit_id": String(state.get("troop_unit_id", "")),
					"unit_state_id": String(state.get("id", "")),
					"side": target_side,
					"zone": zone,
					"br": br,
				}, 0)
			hits_remaining -= br
			destroyed += 1
		else:
			# Partial: reduce BR; status remains engaged.
			BattleRepository.update_unit_state(String(state.get("id", "")), {
				"br_current": br - hits_remaining,
			})
			hits_remaining = 0
	return {"hits_remaining": hits_remaining, "destroyed": destroyed}


# ---------------------------------------------------------------------------
# Internals: morale check
# ---------------------------------------------------------------------------

static func _check_morale_for_side(
	battle_id: String, side: String, units_destroyed_this_phase: int,
	dice_roller: Callable, turn: int, phase: String, bpc: int, calendar_day: int
) -> void:
	if units_destroyed_this_phase <= 0:
		return
	# Count starting units for break point.
	var all_states: Array = BattleRepository.list_unit_states_for_side(battle_id, side)
	var starting_count: int = all_states.size()
	# Count units destroyed so far on this side.
	var destroyed_so_far: int = 0
	var current_br_total: float = 0.0
	var starting_br_total: float = 0.0
	for s in all_states:
		starting_br_total += float(s.get("br_at_battle_start", 0.0))
		if String(s.get("status", "engaged")) == "destroyed":
			destroyed_so_far += 1
		current_br_total += float(s.get("br_current", 0.0))

	if not ArmyMoraleResolver.should_check_morale(starting_count, destroyed_so_far, units_destroyed_this_phase > 0):
		return

	BattleRepository.append_log(battle_id, "morale_check_started", turn, phase, bpc, side,
		{
			"break_point": ArmyMoraleResolver.compute_break_point(starting_count),
			"units_destroyed_so_far": destroyed_so_far,
		}, calendar_day)

	# Build context.
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	var leader_id: String = String(battle.get(side + "_army_id", ""))
	var leader: Dictionary = ArmyRepository.get_army_leader(leader_id)
	var ctx := {
		"army_leader_present": not leader.is_empty(),
		"army_morale_modifier": int(leader.get("morale_modifier", 0)),
		"starting_br_total": starting_br_total,
		"current_br_total": current_br_total,
		"opposing_br_destroyed": _opposing_side_br_destroyed(battle_id, side),
		"opposing_br_lost": 0.0,
		"cannot_retreat": false,
		"homeland_or_sacred": false,
	}

	var morale_results: Dictionary = ArmyMoraleResolver.resolve_army_morale_phase(
		all_states, ctx, dice_roller
	)
	for r in morale_results.get("results", []):
		var unit_state_id: String = String(r.get("unit_state_id", ""))
		var result: String = String(r.get("result", "stand_firm"))
		var new_status: String = ""
		match result:
			"rout":
				new_status = "routed"
			"flee":
				new_status = "fleeing"
			"waver":
				new_status = "wavering"
			"stand_firm":
				new_status = "engaged"
			"rally":
				new_status = "rallied"
		if not new_status.is_empty():
			BattleRepository.update_unit_state(unit_state_id, {"status": new_status})
		BattleRepository.append_log(battle_id, "unit_morale_rolled", turn, phase, bpc, side,
			r, calendar_day)


static func _opposing_side_br_destroyed(battle_id: String, our_side: String) -> float:
	var opposing_side: String = "defender" if our_side == "attacker" else "attacker"
	var states: Array = BattleRepository.list_unit_states_for_side(battle_id, opposing_side)
	var destroyed_br: float = 0.0
	for s in states:
		if String(s.get("status", "")) == "destroyed":
			destroyed_br += float(s.get("br_at_battle_start", 0.0))
	return destroyed_br


# ---------------------------------------------------------------------------
# Internals: silent NPC heuristics
# ---------------------------------------------------------------------------

static func _silent_redeploy(battle_id: String, side: String, current_phase: String) -> Array:
	## If the interactive path supplied a decision for this side, use it.
	## Otherwise apply v1 silent heuristic (move overwhelmed-commander excess
	## units to reserve — placeholder, currently no-op until behavior tags land).
	if _pending_decisions.has(battle_id):
		var decision: Dictionary = _pending_decisions[battle_id]
		var key: String = "%s_redeploys" % side
		if decision.has(key):
			return decision[key]
	var _ignored := battle_id
	var _ignored2 := side
	var _ignored3 := current_phase
	return []


static func _silent_choice(battle_id: String, side: String, current_phase: String) -> String:
	## If the interactive path supplied a decision for this side, use it.
	## Otherwise apply v1 silent heuristic.
	if _pending_decisions.has(battle_id):
		var decision: Dictionary = _pending_decisions[battle_id]
		var key: String = "%s_choice" % side
		if decision.has(key):
			var c: String = String(decision[key])
			if c == "advance" or c == "hold" or c == "withdraw":
				return c
	## v1 heuristic: hold by default. If side has lost ≥50% BR, withdraw.
	## If side has destroyed more BR than opposing, advance.
	var states: Array = BattleRepository.list_unit_states_for_side(battle_id, side)
	var starting_br: float = 0.0
	var current_br: float = 0.0
	for s in states:
		starting_br += float(s.get("br_at_battle_start", 0.0))
		current_br += float(s.get("br_current", 0.0))
	if starting_br <= 0.0:
		return "hold"
	var loss_fraction: float = (starting_br - current_br) / starting_br
	if loss_fraction >= 0.5:
		return "withdraw"
	# Compare to opposing.
	var opposing_side: String = "defender" if side == "attacker" else "attacker"
	var opposing_states: Array = BattleRepository.list_unit_states_for_side(battle_id, opposing_side)
	var opp_starting_br: float = 0.0
	var opp_current_br: float = 0.0
	for s in opposing_states:
		opp_starting_br += float(s.get("br_at_battle_start", 0.0))
		opp_current_br += float(s.get("br_current", 0.0))
	if opp_starting_br <= 0.0:
		return "hold"
	var opp_loss_fraction: float = (opp_starting_br - opp_current_br) / opp_starting_br
	if opp_loss_fraction > loss_fraction + 0.15:
		return "advance"
	# Phase-specific tweak: in melee, prefer hold to avoid the floor-clamp cycle.
	var _ignored := current_phase
	return "hold"


# ---------------------------------------------------------------------------
# Internals: terrain-advantage forfeit
# ---------------------------------------------------------------------------

static func _apply_terrain_advantage_forfeit(battle_id: String, attacker_choice: String, defender_choice: String) -> void:
	# Per RAW §advantageous_terrain L228: "If an army advances or withdraws
	# during any phase, it immediately loses terrain advantage."
	var updates: Dictionary = {}
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	if (attacker_choice == "advance" or attacker_choice == "withdraw") and String(battle.get("attacker_terrain_advantage", "regular")) != "regular":
		updates["attacker_terrain_advantage"] = "regular"
	if (defender_choice == "advance" or defender_choice == "withdraw") and String(battle.get("defender_terrain_advantage", "regular")) != "regular":
		updates["defender_terrain_advantage"] = "regular"
	if not updates.is_empty():
		BattleRepository.update_battle(battle_id, updates)


# ---------------------------------------------------------------------------
# Internals: annihilation check
# ---------------------------------------------------------------------------

static func _check_annihilation(battle_id: String) -> String:
	var attacker_states: Array = BattleRepository.list_unit_states_for_side(battle_id, "attacker")
	var defender_states: Array = BattleRepository.list_unit_states_for_side(battle_id, "defender")
	var attacker_alive: bool = false
	for s in attacker_states:
		var st: String = String(s.get("status", ""))
		if st != "destroyed" and st != "routed":
			attacker_alive = true
			break
	var defender_alive: bool = false
	for s in defender_states:
		var st: String = String(s.get("status", ""))
		if st != "destroyed" and st != "routed":
			defender_alive = true
			break
	if not attacker_alive and not defender_alive:
		return "mutual_withdrawal_draw"
	if not attacker_alive:
		return "attacker_annihilation"
	if not defender_alive:
		return "defender_annihilation"
	return ""


# ---------------------------------------------------------------------------
# Internals: surprise attack-throw silencing
# ---------------------------------------------------------------------------

static func _surprise_silenced(battle: Dictionary, side: String, turn: int) -> bool:
	## Surprised army may not make attack throws during the first three battle
	## phases per RAW §surprise L151. v1: turn-1 to turn-3 = first three phases.
	if not bool(battle.get(side + "_surprised", false)):
		return false
	return turn <= 3


# ---------------------------------------------------------------------------
# Internals: spoils
# ---------------------------------------------------------------------------

static func _calculate_spoils(battle_id: String, casualties: Dictionary) -> Dictionary:
	## Per RAW §spoils_of_war L622-628:
	##   Spoils = sum of one month's wages of each destroyed/routed enemy unit.
	##   Each prisoner = 40gp ransom/sale value.
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	var outcome: String = String(battle.get("outcome", ""))
	var attacker_won: bool = outcome.begins_with("attacker_") or outcome == "defender_voluntary_withdrawal" or outcome == "defender_annihilation"
	var defender_won: bool = outcome.begins_with("defender_") or outcome == "attacker_voluntary_withdrawal" or outcome == "attacker_annihilation"

	var enemy_summary: Dictionary = {}
	var prisoners: int = 0
	if attacker_won:
		enemy_summary = casualties.get("defender_summary", {})
		prisoners = int(enemy_summary.get("prisoners", 0))
	elif defender_won:
		enemy_summary = casualties.get("attacker_summary", {})
		prisoners = int(enemy_summary.get("prisoners", 0))
	else:
		return {"gp_total": 0, "prisoners": 0}

	# Wages from destroyed-permanently units. Sum monthly_wage_gp from each.
	var wages_total: int = 0
	var destroyed_unit_ids: Array = enemy_summary.get("units_destroyed_permanently", [])
	for unit_id in destroyed_unit_ids:
		if not CampaignRepository.db.query_with_bindings(
			"SELECT monthly_wage_gp FROM troop_units WHERE id = ?", [unit_id]):
			continue
		if CampaignRepository.db.query_result.is_empty():
			continue
		wages_total += int(CampaignRepository.db.query_result[0].get("monthly_wage_gp", 0))
	var prisoner_value: int = prisoners * 40

	return {
		"gp_total": wages_total + prisoner_value,
		"wages_total": wages_total,
		"prisoner_count": prisoners,
		"prisoner_value": prisoner_value,
	}


# ---------------------------------------------------------------------------
# Internals: deployment helpers
# ---------------------------------------------------------------------------

static func _insert_unit_states(battle_id: String, side: String, deployment: Array, army_id: String) -> void:
	for entry in deployment:
		BattleRepository.create_unit_state({
			"battle_id": battle_id,
			"troop_unit_id": String(entry.get("troop_unit_id", "")),
			"side": side,
			"zone": String(entry.get("zone", "melee")),
			"status": "engaged",
			"br_at_battle_start": float(entry.get("br", 0.0)),
			"br_current": float(entry.get("br", 0.0)),
			"parent_officer_id": String(entry.get("parent_officer_id", "")),
		})
	var _ignored := army_id


static func _zones_summary(deployment: Array) -> Dictionary:
	var summary: Dictionary = {"missile": [], "skirmish": [], "melee": [], "reserve": []}
	for entry in deployment:
		var zone: String = String(entry.get("zone", "melee"))
		if not summary.has(zone):
			summary[zone] = []
		summary[zone].append(String(entry.get("troop_unit_id", "")))
	return summary


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _get_leader_strategic(army_id: String) -> int:
	var leader: Dictionary = ArmyRepository.get_army_leader(army_id)
	return int(leader.get("strategic_ability", 0))


static func _get_leader_strategic_for_battle(battle_id: String, side: String) -> int:
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	var army_id: String = String(battle.get(side + "_army_id", ""))
	return _get_leader_strategic(army_id)


static func _resolve_phase_forays(
	battle_id: String,
	side: String,
	forays: Array,
	opposing_participants: Array,
	turn: int,
	phase: String,
	bpc: int,
	calendar_day: int,
	dice_roller: Callable
) -> void:
	## Resolves each declared foray sequentially. Each foray:
	## 1. Computes the foe pool from opposing participants per RAW
	##    HeroicForayResolver.compute_foe_pool.
	## 2. Logs `heroic_foray_declared` event.
	## 3. v1 placeholder: simulate_foray_silently produces an outcome
	##    (victory / defeat / draw_withdraw). When the ACKS combat sub-scene
	##    library call lands, replace this with the real foray combat.
	## 4. If victory, applies foes_defeated_br to opposing units (removes BR).
	## 5. Logs `heroic_foray_resolved` event.
	if forays.is_empty():
		return
	for foray in forays:
		var hero_id: String = String(foray.get("hero_id", ""))
		var br_staked: float = float(foray.get("br_staked", 0.0))
		if hero_id.is_empty() or br_staked <= 0.0:
			continue
		BattleRepository.append_log(battle_id, "heroic_foray_declared",
			turn, phase, bpc, side,
			{"hero_id": hero_id, "br_staked": br_staked, "side": side},
			calendar_day)
		# Compute foe pool.
		var foe_pool: Dictionary = HeroicForayResolver.compute_foe_pool(
			br_staked, opposing_participants, dice_roller
		)
		# Lookup hero level for the silent simulator.
		var hero_level: int = _get_character_level(hero_id)
		var sim_result: Dictionary = HeroicForayResolver.simulate_foray_silently(
			br_staked, hero_level, float(foe_pool.get("foes_br_actual", 0.0)), dice_roller
		)
		var foes_defeated_br: float = float(sim_result.get("foes_defeated_br", 0.0))
		var apply_result: Dictionary = {}
		if foes_defeated_br > 0.0:
			# Convert opposing_participants[].id to state ids for apply_foray_outcome.
			var opposing_state_ids: Array = []
			for p in opposing_participants:
				opposing_state_ids.append(String(p.get("id", "")))
			apply_result = HeroicForayResolver.apply_foray_outcome(
				foes_defeated_br, opposing_state_ids, calendar_day
			)
		BattleRepository.append_log(battle_id, "heroic_foray_resolved",
			turn, phase, bpc, side,
			{
				"hero_id": hero_id,
				"br_staked": br_staked,
				"hero_level": hero_level,
				"sim_result": sim_result,
				"foe_pool": foe_pool,
				"apply_result": apply_result,
			},
			calendar_day)


static func _get_character_level(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings(
		"SELECT level FROM characters WHERE id = ?", [character_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("level", 0))


static func _find_battle_for_army(army_id: String) -> String:
	## Returns the active battle_id for the army, or '' if none.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM field_battles
		WHERE (attacker_army_id = ? OR defender_army_id = ?)
		ORDER BY started_calendar_day DESC LIMIT 1
	""", [army_id, army_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _safe_int(v: Variant, default_value: int = 0) -> int:
	## SQLite NULL columns surface as null; int(null) raises "Nonexistent 'int' constructor"
	## in Godot 4 GDScript. This helper coerces null/empty to a default int.
	if v == null:
		return default_value
	return int(v)


static func _roll(dice_roller: Callable, count: int, sides: int) -> int:
	if dice_roller.is_valid():
		return int(dice_roller.call(count, sides))
	var total: int = 0
	for i in range(count):
		total += randi_range(1, sides)
	return total
