class_name UnitLoyaltyResolver
extends RefCounted

## RAW Unit Loyalty rolls for troop units of EVERY source type.
## gdd-tribal-warriors.md §7.2 / §7.4; conventions §131.
##
## Was `TribalWarriorLoyaltyResolver` until 2026-08-03. The ROLL was always
## source-agnostic — `daw_armies_recruitment.xml:99-107` is printed in the
## mercenary chapter and the conscript / militia / follower chapters each point
## back at it — so what was gated to tribal warriors was never the roll but the
## DEPARTURE. Each source type leaves differently, and that dispatch is now
## `_resolve_departure` below. Duplicating the roll into a sibling class would
## have recreated exactly the divergence §131 warns about.
##
## RAW: rules/daw_armies_recruitment.xml:98-100 — "A calamity is routing from
## battle, suffering 25% or greater casualties, being out of supply, or going
## without pay for a month. When a calamity occurs, make a loyalty roll of 2d6
## plus morale and adjustments. If troops are suffering more than one calamity
## at once, apply -2 to the loyalty roll per calamity after the first."
##
## RAW: rules/daw_armies_recruitment.xml:265-275 — the Unit Loyalty table:
## 2- Enmity / 3-5 Resignation / 6-8 Grudging Loyalty / 9-11 Loyalty /
## 12+ Fanatic loyalty.
##
## ── Who rolls, and what happens when they leave ─────────────────────────────
##
## | source_type    | rolls? | RAW        | departure                          |
## |----------------|--------|------------|------------------------------------|
## | tribal_warrior | yes    | ax:454-455 | return to the clanhold (§7.4)      |
## | mercenary      | yes    | :98-107    | leave service                      |
## | conscript      | yes    | :353       | DESERTION (:355)                   |
## | militia        | yes    | :458-459   | DESERTION (:461)                   |
## | follower       | yes*   | :477-478   | leave service                      |
## | slave_soldier  | yes    | :611       | DESERTION (:612, "as conscripts")  |
## | vassal         | NO     | —          | see below                          |
##
## \* except religious fanatics — see the exemption below.
##
## **Vassal troops make no roll of their own.** `§vassal_troops` gives them no
## loyalty rule; it says a vassal's garrison "is some mix of followers,
## mercenaries, conscripts, and militia", i.e. vassal troops ARE those types
## once mustered. Rolling for `source_type='vassal'` would be inventing a rule.
## Nothing mints the type today either.
##
## **Religious fanatics never roll.** `:481` — "Cleric and bladedancer followers
## are religious fanatics." `:483` — "Religious fanatics do not make loyalty
## rolls for calamities, but still make morale rolls in battle." This is an
## exemption from the calamity roll ONLY; battle morale is a different system
## and is untouched. Flagged per-unit by `troop_units.is_religious_fanatic`
## (migration 214) rather than inferred from `monthly_cost_cp = 0`, because the
## MAGE follower table is also `wages_required: false` and mages are not
## fanatics — see the migration header.
##
## ── Three things that are easy to get wrong ─────────────────────────────────
##
## 1. **The officer morale modifier does NOT apply here.**
##    `rules/daw_armies_recruitment.xml:775` — "Morale modifier affects Unit
##    Morale rolls for units under the officer's command; it does not affect
##    Unit Loyalty rolls." So the bard aura, the commander's Charisma, Command
##    proficiency and legendary-leader bonuses are all excluded. The only
##    morale term in this roll is the unit's OWN stored `troop_units.morale`
##    (conventions §129), which is exactly what makes §129's stored-vs-roll-time
##    split load-bearing rather than cosmetic.
##
## 2. **This is NOT the henchman loyalty ladder**, despite sharing all five
##    2d6 bands. Henchman loyalty gives Fanatic +2 and Grudging a one-shot -1;
##    DaW Unit Loyalty gives Fanatic +1 (:107) and makes two CONSECUTIVE
##    Grudging results a departure (:105). The bands are resolved locally here,
##    with their own citation, so a future change to `HenchmanTables` cannot
##    silently move unit loyalty.
##
## 3. **The 3-months-without-spoils trigger is a LOYALTY roll, not a morale
##    roll.** `ax_domains_of_chaos.xml:456` prints it as a morale roll; per
##    Jedidiah (2026-08-01) that is a known RAW error and later errata make it
##    a straight loyalty roll after 3 months without spoils worth at least the
##    unit's monthly wage. There is no morale-roll step and no cascade. It is
##    modelled here as one more calamity kind (CALAMITY_NO_SPOILS), and it is
##    a tribal-warrior rule — no other source type accrues it.
##
## Determinism: rolls go through `DiceSystem.roll_digital` by default; tests
## inject a fake via the `dice` seam (any object exposing
## `roll(count, sides) -> int`). No wall-clock, no `randi()`.


# --- Calamity kinds (rules/ax_domains_of_chaos.xml:455 + the errata'd :456) ---
const CALAMITY_ROUT := "routed_from_battle"
const CALAMITY_CASUALTIES := "casualties_25_percent"
const CALAMITY_OUT_OF_SUPPLY := "out_of_supply"
const CALAMITY_UNPAID := "without_pay_for_a_month"
const CALAMITY_NO_SPOILS := "three_months_without_qualifying_spoils"
## RAW :459 — "Militia also treat each season of continuous campaigning as a
## calamity." MILITIA ONLY; no other source type accrues it.
const CALAMITY_CONTINUOUS_CAMPAIGN := "season_of_continuous_campaigning"

const VALID_CALAMITIES := [
	CALAMITY_ROUT,
	CALAMITY_CASUALTIES,
	CALAMITY_OUT_OF_SUPPLY,
	CALAMITY_UNPAID,
	CALAMITY_NO_SPOILS,
	CALAMITY_CONTINUOUS_CAMPAIGN,
]

## RAW :459's "season". Timekeeping's year is 364 days split at days
## 0 / 91 / 182 / 273, so a season is 91 days — deliberately NOT 3 months
## (84 days), which would be 7 days harsher than the printed rule.
const SEASON_DAYS := 91

# --- Unit Loyalty outcomes (rules/daw_armies_recruitment.xml:270-274) ---
const OUTCOME_ENMITY := "enmity"
const OUTCOME_RESIGNATION := "resignation"
const OUTCOME_GRUDGING := "grudging_loyalty"
const OUTCOME_LOYALTY := "loyalty"
const OUTCOME_FANATIC := "fanatic_loyalty"

# --- departure_kind values written to troop_units on a departure ---
const DEPARTURE_ENMITY := "loyalty_enmity"
const DEPARTURE_RESIGNATION := "loyalty_resignation"
const DEPARTURE_GRUDGING := "loyalty_grudging_twice"

# --- disposition: WHERE the departing soldiers went (see _resolve_departure) --
const DISPOSITION_RETURNED_TO_CLANHOLD := "returned_to_clanhold"
const DISPOSITION_DESERTED := "deserted"
const DISPOSITION_LEFT_SERVICE := "left_service"

## Source types that make Unit Loyalty rolls at all, mapped to the RAW line
## that grants each one the roll. `vassal` is absent by RAW (see the class
## docstring), not by oversight.
const ROLLING_SOURCE_TYPES := {
	"tribal_warrior": "ax_domains_of_chaos.xml:454",
	"mercenary": "daw_armies_recruitment.xml:99",
	"conscript": "daw_armies_recruitment.xml:353",
	"militia": "daw_armies_recruitment.xml:458",
	"follower": "daw_armies_recruitment.xml:477",
	"slave_soldier": "daw_armies_recruitment.xml:611",
}

## Source types whose troops "cannot voluntarily leave service" — a departure
## result is DESERTION rather than an orderly exit.
## RAW :355 (conscripts), :461 (militia), :612 (slave soldiers, "like
## conscripts").
const DESERTING_SOURCE_TYPES := ["conscript", "militia", "slave_soldier"]

## RAW :100 — "-2 to the loyalty roll per calamity after the first."
const PENALTY_PER_EXTRA_CALAMITY := -2

## RAW :107 — Fanatic loyalty means "all future loyalty rolls are at +1".
## Note this is +1, NOT the henchman ladder's +2.
const FANATIC_BONUS := 1

## RAW :105 — Grudging Loyalty "rolled on two consecutive morale rolls" ends
## the unit's service.
const GRUDGING_RUN_TO_DEPART := 2


## Resolve the Unit Loyalty table for an adjusted 2d6 total.
## RAW: rules/daw_armies_recruitment.xml:270-274.
static func outcome_for_total(total: int) -> String:
	if total <= 2:
		return OUTCOME_ENMITY
	if total <= 5:
		return OUTCOME_RESIGNATION
	if total <= 8:
		return OUTCOME_GRUDGING
	if total <= 11:
		return OUTCOME_LOYALTY
	return OUTCOME_FANATIC


## Whether [param unit] makes Unit Loyalty rolls at all. Two gates: the source
## type must be one RAW grants the roll to, and the unit must not be a religious
## fanatic (:483). Callers that fan calamities out (conventions §131) may use
## this to skip work; `roll_loyalty` enforces it either way.
static func rolls_loyalty(unit: Dictionary) -> bool:
	if int(unit.get("is_religious_fanatic", 0)) == 1:
		return false
	return ROLLING_SOURCE_TYPES.has(StringUtils.s(unit.get("source_type")))


## Roll one Unit Loyalty check for [param unit_id] against [param calamities]
## (an Array of CALAMITY_* strings; duplicates are collapsed).
##
## Applies the roll, persists the RAW carryover state, resolves the departure
## through the source-type dispatch, writes the departure-log line, and emits
## `troop_unit_loyalty_failed` when the unit leaves.
##
## [param dice] optional seam exposing `roll(count, sides) -> int`; defaults to
## `DiceSystem.roll_digital`.
##
## [param situational_modifier] is RAW :99's "adjustments" term — a flat bonus
## or penalty the CALLER knows about and this resolver cannot see. Today its one
## user is `daw_campaigning_armies.xml:367`, "Unsupplied units suffer an
## ADDITIONAL -1 penalty on their loyalty rolls", passed by
## `ArmySupplyTracker`. It deliberately sits OUTSIDE the extra-calamity stack:
## it is -1, not the -2 a second calamity would cost, and folding it into
## `calamity_penalty` would both misreport the arithmetic and make a single
## calamity look like two. Defaults to 0, which keeps every other caller's
## arithmetic identical.
##
## Returns:
##   {ok, unit_id, source_type, outcome, departs, departure_kind, disposition,
##    roll, morale, modifier, total, calamities, calamity_penalty,
##    situational_modifier, fanatic_bonus_applied, consecutive_grudging,
##    loyalty_is_fanatic, returned_to_pool, fielded_army_id,
##    fanatic_suppressed_by_unpaid}
## or {ok: false, error: <reason>} — `error` is "religious_fanatic_exempt" or
## "source_type_does_not_roll" when RAW bars the roll.
static func roll_loyalty(unit_id: String, calamities: Array, calendar_day: int,
		dice = null, situational_modifier: int = 0) -> Dictionary:
	if unit_id.is_empty():
		return {"ok": false, "error": "missing_unit_id"}

	var unit: Dictionary = TroopUnitRepository.get_unit(unit_id)
	if unit.is_empty():
		return {"ok": false, "error": "unknown_unit"}
	if StringUtils.s(unit.get("status")) != "active":
		return {"ok": false, "error": "unit_not_active"}

	var source_type: String = StringUtils.s(unit.get("source_type"))
	# RAW :483 — religious fanatics do not make loyalty rolls for calamities.
	# Checked BEFORE the source-type gate so the reason reported is the RAW one.
	if int(unit.get("is_religious_fanatic", 0)) == 1:
		return {"ok": false, "error": "religious_fanatic_exempt",
			"unit_id": unit_id, "source_type": source_type}
	if not ROLLING_SOURCE_TYPES.has(source_type):
		return {"ok": false, "error": "source_type_does_not_roll",
			"unit_id": unit_id, "source_type": source_type}

	# Collapse duplicates but keep a stable order so the -2/extra-calamity
	# penalty and the log line are deterministic across runs.
	var kinds: Array[String] = []
	for c in calamities:
		var kind: String = String(c)
		if not VALID_CALAMITIES.has(kind):
			push_error("UnitLoyaltyResolver: unknown calamity '%s'" % kind)
			continue
		if not kinds.has(kind):
			kinds.append(kind)
	if kinds.is_empty():
		return {"ok": false, "error": "no_calamity"}

	# --- Build the modifier stack. -------------------------------------------
	# RAW :99 — "2d6 plus morale and adjustments". The unit's OWN morale only;
	# officer/leader modifiers are excluded per :775 (see the class docstring).
	var morale: int = int(unit.get("morale", 0))
	var calamity_penalty: int = PENALTY_PER_EXTRA_CALAMITY * (kinds.size() - 1)
	var was_fanatic: bool = int(unit.get("loyalty_is_fanatic", 0)) == 1
	var fanatic_bonus: int = FANATIC_BONUS if was_fanatic else 0
	var modifier: int = morale + calamity_penalty + fanatic_bonus + situational_modifier

	var roll: int = _roll_2d6(dice)
	var total: int = roll + modifier
	var outcome: String = outcome_for_total(total)

	# RAW :107 — "fanatic loyalty can never result from going without pay and
	# becomes ordinary loyalty in that case." Applies to the OUTCOME, not the
	# roll, so the unit still keeps any fanatic status it already held.
	var fanatic_suppressed: bool = false
	if outcome == OUTCOME_FANATIC and kinds.has(CALAMITY_UNPAID):
		outcome = OUTCOME_LOYALTY
		fanatic_suppressed = true

	# --- Roll the RAW carryover state forward. --------------------------------
	var prior_run: int = int(unit.get("loyalty_consecutive_grudging", 0))
	var new_run: int = prior_run
	var new_fanatic: bool = was_fanatic
	var departs: bool = false
	var departure_kind: String = ""

	match outcome:
		OUTCOME_ENMITY:
			# RAW :103 — "Troops immediately leave service."
			new_run = 0
			departs = true
			departure_kind = DEPARTURE_ENMITY
		OUTCOME_RESIGNATION:
			# RAW :104 — "leave service at the first advantageous safe moment".
			# v1 resolves that immediately for every source type (Jedidiah,
			# 2026-08-03): there is no in-data 'leaving soon' state for a unit
			# to sit in, and the ":104 will not risk another battle" clause has
			# no home until there is one.
			new_run = 0
			departs = true
			departure_kind = DEPARTURE_RESIGNATION
		OUTCOME_GRUDGING:
			# RAW :105 — two CONSECUTIVE grudging results end service.
			new_run = prior_run + 1
			if new_run >= GRUDGING_RUN_TO_DEPART:
				departs = true
				departure_kind = DEPARTURE_GRUDGING
				new_run = 0
		OUTCOME_LOYALTY:
			new_run = 0
		OUTCOME_FANATIC:
			new_run = 0
			new_fanatic = true

	# --- Persist. -------------------------------------------------------------
	var updates: Dictionary = {
		"loyalty_consecutive_grudging": new_run,
		"loyalty_is_fanatic": 1 if new_fanatic else 0,
	}
	# The trigger that caused this roll is spent either way — a unit that
	# survives a no-spoils calamity starts its 3-month clock over rather than
	# re-rolling every subsequent month on the same unpaid stretch.
	if kinds.has(CALAMITY_NO_SPOILS):
		updates["months_without_qualifying_spoils"] = 0
	if departs:
		updates["status"] = "departed"
		updates["departure_kind"] = departure_kind
		updates["departure_calendar_day"] = calendar_day
	TroopUnitRepository.update_unit(unit_id, updates)

	var exit: Dictionary = {}
	if departs:
		exit = _resolve_departure(unit, outcome, calendar_day)

	var result: Dictionary = {
		"ok": true,
		"unit_id": unit_id,
		"source_type": source_type,
		"outcome": outcome,
		"departs": departs,
		"departure_kind": departure_kind,
		"disposition": String(exit.get("disposition", "")),
		"roll": roll,
		"morale": morale,
		"modifier": modifier,
		"total": total,
		"calamities": kinds,
		"calamity_penalty": calamity_penalty,
		"situational_modifier": situational_modifier,
		"fanatic_bonus_applied": fanatic_bonus,
		"fanatic_suppressed_by_unpaid": fanatic_suppressed,
		"consecutive_grudging": new_run,
		"loyalty_is_fanatic": new_fanatic,
		"returned_to_pool": int(exit.get("returned_to_pool", 0)),
		"fielded_army_id": String(exit.get("fielded_army_id", "")),
	}

	_chronicle(unit, result, calendar_day)

	if departs:
		if EventBus.has_signal("troop_unit_loyalty_failed"):
			EventBus.emit_signal("troop_unit_loyalty_failed",
				unit_id, source_type, departure_kind,
				String(exit.get("fielded_army_id", "")))
		# The migration-129 signal is tribal-only and stays that way: it is the
		# narrower, older contract and `troop_unit_loyalty_failed` above is its
		# superset. Emitting it for a mercenary company would make its name lie.
		if source_type == "tribal_warrior" \
				and EventBus.has_signal("tribal_warriors_loyalty_failed"):
			EventBus.emit_signal("tribal_warriors_loyalty_failed", unit_id, departure_kind)

	return result


# ---------------------------------------------------------------------------
# Departure dispatch — the part that is genuinely per-source-type
# ---------------------------------------------------------------------------

## Where the departing soldiers actually go. Returns
## `{disposition, returned_to_pool, fielded_army_id}`.
##
## RAW, per source type:
##   * tribal_warrior — `ax_domains_of_chaos.xml:461`, return to their villages.
##   * conscript      — `:355`, "cannot voluntarily leave service; loyalty
##     results that would cause departure represent desertion."
##   * militia        — `:461`, "cannot voluntarily leave service, but may
##     desert, betray, or attack their leader." NOTE `:462`'s return-to-farms is
##     the VOLUNTARY RELEASE case, a different event from a failed roll, so a
##     deserting militiaman does not go home — he scatters.
##   * slave_soldier  — `:612`, "like conscripts … may desert".
##   * mercenary      — `:103` / `:104`, leave service.
##   * follower       — `:477-478` give followers the standard calamities and
##     the shared outcome table; no separate exit text, so: leave service.
##
## **Enmity fields a hostile force** (Jedidiah, 2026-08-03) for every source
## type EXCEPT tribal warriors. `:103` — troops that leave in enmity "may attack
## or stage a coup if the employer is vulnerable, or seek service with a strong
## enemy" — so the 2- band, and only the 2- band, produces real troops on the
## map via `MutinyForceComposer`. Resignation and the two-Grudging departure
## just leave. Tribal warriors are exempt because GDD §7.4 / Q-TW-8 (resolved
## 2026-05-22) already ruled their brigand branch out of v1; extending it to
## them is Jedidiah's call, not a silent side-effect of this change.
##
## **Desertion must not look like death.** `ArmyCasualtyResolver` applies a
## PERMANENT `peasant_families` + morale loss for militia, and it does so from
## the battle `crippled` count only (RAW :432 makes the loss permanent when
## militia are KILLED). Nothing here touches that path. What desertion DOES
## relieve is the standing levy penalty, and that happens for free:
## `LevyPenaltyCalculator` sums ACTIVE rows, and the row above is already
## `status='departed'` by the time we get here (conventions §133).
static func _resolve_departure(unit: Dictionary, outcome: String,
		calendar_day: int) -> Dictionary:
	var source_type: String = StringUtils.s(unit.get("source_type"))

	if source_type == "tribal_warrior":
		return {
			"disposition": DISPOSITION_RETURNED_TO_CLANHOLD,
			"returned_to_pool": _return_warriors_to_clanhold(unit),
			"fielded_army_id": "",
		}

	var disposition: String = DISPOSITION_DESERTED \
		if DESERTING_SOURCE_TYPES.has(source_type) else DISPOSITION_LEFT_SERVICE
	var army_id: String = ""
	if outcome == OUTCOME_ENMITY:
		army_id = MutinyForceComposer.field_mutineers(unit, calendar_day)
	return {
		"disposition": disposition,
		"returned_to_pool": 0,
		"fielded_army_id": army_id,
	}


## RAW: rules/ax_domains_of_chaos.xml:461 — "Tribal warriors who leave service
## return to their villages if possible."
##
## Per Jedidiah (2026-08-01): departing warriors return to their clanhold **if
## it still exists**, and may be levied again later as normal. A clanhold that
## has been conquered, abandoned or salted to ruin cannot take them back, and
## those warriors are simply lost — RAW's brigand/mercenary branch is the
## "return is not possible" case (:462), which is deliberately NOT modelled as
## a hostile on-map force in v1 (GDD §7.4 + Q-TW-8, resolved 2026-05-22).
##
## Returns the number of warriors actually returned to the dormant pool.
## EXCESS-LEVY units are exempt (migration 213): those warriors are ADDITIONAL
## peasants pulled off the land per `ax_domains_of_chaos.xml:399`, not the
## family's designated 1-per-family warrior. `available_tribal_warriors` was
## never decremented for them, so it must not be incremented when they leave —
## otherwise a departure on a clanhold carrying slack from past casualties
## would fill that slack, resurrecting dead warriors' slots against `:404`
## ("Tribal warrior casualties can only be replaced through population
## growth"). They return to being peasants, which `peasant_families` counts.
static func _return_warriors_to_clanhold(unit: Dictionary) -> int:
	var survivors: int = int(unit.get("count", 0))
	if survivors <= 0:
		return 0
	if int(unit.get("is_excess_levy", 0)) == 1:
		return 0
	var domain_id: String = StringUtils.s(unit.get("assigned_domain_id"))
	if domain_id.is_empty():
		return 0
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return 0
	if String(domain.get("domain_style", "civilized")) != "clanhold":
		return 0
	# A domain that has left play cannot receive returning warriors. Only
	# abandoned / salted_to_ruin qualify: `ruined_stronghold` and
	# `succession_pending` clanholds are still mechanically alive (they keep
	# ticking, per the migration-122 comment on the column and the same pair of
	# states DomainHandlers._handle_monthly_tick skips), and a clanhold whose
	# chieftain has just died is exactly the sort of place warriors go home to.
	var lifecycle: String = String(domain.get("lifecycle_state", LifecycleHandler.STATE_ACTIVE))
	if lifecycle == LifecycleHandler.STATE_ABANDONED \
			or lifecycle == LifecycleHandler.STATE_SALTED_TO_RUIN:
		return 0

	# Respect the §3 pool invariant: available + levied <= peasant_families.
	# The departing unit is already status='departed' at this point, so it no
	# longer counts toward `levied` in pool_for_domain.
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(domain_id)
	var families: int = int(pool.get("peasant_families", 0))
	var available: int = int(pool.get("available", 0))
	var levied: int = int(pool.get("levied", 0))
	var headroom: int = maxi(0, families - available - levied)
	var returned: int = mini(survivors, headroom)
	if returned <= 0:
		return 0
	CampaignRepository.update_domain_monthly_state(domain_id, {
		"available_tribal_warriors": available + returned,
	})
	return returned


# ---------------------------------------------------------------------------
# Chronicle
# ---------------------------------------------------------------------------

## Write the departure-log line for a DEPARTURE only. The migration-129 event
## type is `tribal_warriors_loyalty_failed`, so chronicling a survived calamity
## under it would make the log lie — a unit that rolled Loyalty did not fail
## anything. Survived rolls are still observable via the returned dict and the
## persisted carryover columns.
##
## Non-tribal departures use migration 214's `troop_unit_loyalty_failed` for the
## same reason in the other direction: logging a mercenary company under the
## tribal-warrior type would make the chronicle assert something false.
static func _chronicle(unit: Dictionary, result: Dictionary, calendar_day: int) -> void:
	var domain_id: String = StringUtils.s(unit.get("assigned_domain_id"))
	var campaign_id: String = StringUtils.s(unit.get("campaign_id"))
	if domain_id.is_empty() or campaign_id.is_empty():
		return
	if not bool(result.get("departs", false)):
		return
	var source_type: String = String(result.get("source_type", ""))
	var is_tribal: bool = source_type == "tribal_warrior"
	var count: int = int(unit.get("count", 0))
	var summary: String = "%d %s %s left service (%s, 2d6 %d%+d = %d)." % [
		count,
		StringUtils.s(unit.get("race"), "tribal"),
		StringUtils.s(unit.get("troop_type"), "warriors"),
		String(result.get("outcome", "")),
		int(result.get("roll", 0)),
		int(result.get("modifier", 0)),
		int(result.get("total", 0)),
	]
	summary += " " + _disposition_sentence(result, count)

	DepartureLogRecorder.record(
		campaign_id, domain_id, calendar_day,
		"tribal_warriors_loyalty_failed" if is_tribal else "troop_unit_loyalty_failed",
		summary,
		{
			"troop_unit_id": StringUtils.s(unit.get("id")),
			"source_type": source_type,
			"outcome": result.get("outcome", ""),
			"departure_kind": result.get("departure_kind", ""),
			"disposition": result.get("disposition", ""),
			"calamities": result.get("calamities", []),
			"roll": result.get("roll", 0),
			"modifier": result.get("modifier", 0),
			"total": result.get("total", 0),
			"count": count,
			"returned_to_pool": result.get("returned_to_pool", 0),
			"fielded_army_id": result.get("fielded_army_id", ""),
		})


static func _disposition_sentence(result: Dictionary, count: int) -> String:
	match String(result.get("disposition", "")):
		DISPOSITION_RETURNED_TO_CLANHOLD:
			var returned: int = int(result.get("returned_to_pool", 0))
			if returned > 0:
				return "%d returned to their villages." % returned
			return "None returned to the clanhold."
		DISPOSITION_DESERTED:
			var deserted: String = "They deserted."
			if not String(result.get("fielded_army_id", "")).is_empty():
				deserted += " %d turned on their leader and took the field against them." % count
			return deserted
		_:
			var left: String = "They left service."
			if not String(result.get("fielded_army_id", "")).is_empty():
				left += " %d took up arms against their former employer." % count
			return left


static func _roll_2d6(dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(2, 6))
	# modifier is applied by the caller, so raw_total IS the 2d6 sum here.
	return DiceSystem.roll_digital(6, 2, 0, "unit_loyalty").raw_total
