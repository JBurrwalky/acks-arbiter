class_name HijinkCommon
extends RefCounted

## Shared infrastructure for the six per-hijink handlers under
## `engine/subsystems/activities/handlers/syndicate/`. Per-handler files
## (assassinating.gd, carousing.gd, smuggling.gd, spying.gd, stealing.gd,
## treasure_hunting.gd) are thin wrappers that supply the per-kind yield
## function + charges-on-capture table. The dispatch / throw / capture /
## payout side is identical and lives here.
##
## Phase 10B.3. Activity-handler module convention (per coding_conventions
## §32): static methods returning a Dictionary outcome with at minimum
## `summary`. Money values throughout are cp.


# RAW §hijinks <charges_on_capture> — one row per hijink kind. Each entry
# is a 6-row 1d6 → charge_label table.
const CHARGES_ON_CAPTURE := {
	"assassinating": ["Assault", "Assault", "Assault", "Mayhem", "Mayhem", "Murder"],
	"carousing":     ["Drunkenness", "Drunkenness", "Drunkenness", "Gambling", "Gambling", "Vandalism"],
	"smuggling":     ["Contraband", "Contraband", "Contraband", "Smuggling", "Smuggling", "Racketeering"],
	"spying":        ["Eavesdropping", "Eavesdropping", "Eavesdropping", "Sedition", "Sedition", "Treason"],
	"stealing":      ["Theft", "Theft", "Theft", "Burglary", "Burglary", "Robbery"],
	"treasure_hunting": ["Trespassing", "Trespassing", "Trespassing", "Theft", "Theft", "Burglary"],
}


# RAW §await_trial L1138-1148 time_languishing_by_crime: dice expression by
# crime. Resolver rolls the expression at arrest time.
const TIME_LANGUISHING_BY_CRIME := {
	"Drunkenness":   {"dice": 2, "sides": 1, "mod": 0, "unit_days": 1},   # 1d2 days
	"Outrage":       {"dice": 2, "sides": 1, "mod": 0, "unit_days": 1},
	"Eavesdropping": {"dice": 4, "sides": 1, "mod": 0, "unit_days": 1},   # 1d4 days
	"Trespassing":   {"dice": 4, "sides": 1, "mod": 0, "unit_days": 1},
	"Gambling":      {"dice": 4, "sides": 1, "mod": 0, "unit_days": 1},
	"Bribery":       {"dice": 6, "sides": 1, "mod": 0, "unit_days": 1},
	"Theft":         {"dice": 6, "sides": 1, "mod": 0, "unit_days": 1},
	"Contraband":    {"dice": 6, "sides": 1, "mod": 0, "unit_days": 1},
	"Assault":       {"dice": 8, "sides": 1, "mod": 0, "unit_days": 1},   # 1d8 days
	"Vandalism":     {"dice": 8, "sides": 1, "mod": 0, "unit_days": 1},
	"Burglary":      {"dice": 4, "sides": 1, "mod": 0, "unit_days": 7},   # 1d4 weeks
	"Smuggling":     {"dice": 4, "sides": 1, "mod": 0, "unit_days": 7},
	"Kidnapping":    {"dice": 4, "sides": 1, "mod": 0, "unit_days": 30},  # 1d4 months
	"Manslaughter":  {"dice": 4, "sides": 1, "mod": 0, "unit_days": 30},
	"Mayhem":        {"dice": 4, "sides": 1, "mod": 0, "unit_days": 30},
	"Robbery":       {"dice": 6, "sides": 1, "mod": 0, "unit_days": 30},  # 1d6 months
	"Racketeering":  {"dice": 6, "sides": 1, "mod": 0, "unit_days": 30},
	"Arson":         {"dice": 12, "sides": 1, "mod": 0, "unit_days": 30}, # 1d12 months
	"Desertion":     {"dice": 12, "sides": 1, "mod": 0, "unit_days": 30},
	"Murder":        {"dice": 12, "sides": 1, "mod": 0, "unit_days": 30},
	"Sedition":      {"dice": 12, "sides": 1, "mod": 0, "unit_days": 30},
	"Heresy":        {"dice": 12, "sides": 2, "mod": 0, "unit_days": 30}, # 2d12 months
	"Treason":       {"dice": 12, "sides": 2, "mod": 0, "unit_days": 30}, # High Treason
	"Regicide":      {"dice": 12, "sides": 2, "mod": 0, "unit_days": 30},
}


# Hijinks that REQUIRE lay-low after a successful run per RAW §lay_low L1195:
# arson, assassination, infiltration, sabotage, smuggling, subversion, stealing.
# v1 supports 6 hijink kinds; from those, lay-low applies to:
const LAY_LOW_REQUIRED_KINDS := ["assassinating", "smuggling", "stealing"]


# ---------------------------------------------------------------------------
# Common resolution pipeline
# ---------------------------------------------------------------------------

## Single entry point used by every per-kind handler's on_complete.
## Drives: eligibility check → throw → success/failure branch → yield
## payout → catch handling → lay-low scheduling.
##
## [param yield_callable] is the per-kind cp-yield computer; signature:
##   func(perpetrator_level: int, rng: RandomNumberGenerator,
##        params: Dictionary, character_id: String) -> Dictionary
##   returning { "cp_yield": int, "detail": String }.
##
## [param strict_catch]: if true, RAW §lay_low L1198 strict-catch rule
## applies (caught on fail-by-11+ or natural 1-3). Caller sets this when
## the perpetrator skipped a required prior lay-low.
static func resolve(
		hijink_id: String,
		params: Dictionary,
		yield_callable: Callable,
		rng: RandomNumberGenerator,
		current_day: int,
		strict_catch: bool = false,
) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var hijink := SyndicateRepository.get_hijink(hijink_id)
	if hijink.is_empty():
		return {"summary": "perform_hijink failed: hijink_assignments row not found"}
	var hijink_kind := _str_or_empty(hijink.get("hijink_kind"))
	var member_id := _str_or_empty(hijink.get("syndicate_member_id"))
	var boss_id := _str_or_empty(hijink.get("boss_character_id"))
	var character_id: String = ""
	var class_id: String = ""
	var level: int = 0

	if not member_id.is_empty():
		var member := SyndicateRepository.get_member(member_id)
		if member.is_empty():
			return {"summary": "perform_hijink failed: syndicate_members row not found"}
		level = int(member.get("level", 0))
		character_id = _str_or_empty(member.get("character_id_if_named"))
		if not character_id.is_empty():
			class_id = _read_class_id(character_id)

	# For unnamed members the class is inferred from follower_kind. For named
	# characters whose class differs from the follower_kind enum (e.g., a
	# multi-class concept), the character's class takes precedence.
	if class_id.is_empty() and not member_id.is_empty():
		var member2 := SyndicateRepository.get_member(member_id)
		match _str_or_empty(member2.get("follower_kind")):
			"thief":              class_id = "thief"
			"assassin":           class_id = "assassin"
			"elven_nightblade":   class_id = "elven_nightblade"
			"ruffian":            class_id = "thief"  # ruffian uses thief progression in RAW
			_:                    class_id = "thief"  # fallback

	# Eligibility check per RAW per-hijink <eligibility> nodes.
	if not HijinkThrowTarget.is_eligible(hijink_kind, class_id):
		return {
			"summary": "perform_hijink failed: class '%s' not eligible for '%s'" % [class_id, hijink_kind],
		}

	# Throw target from class progression.
	var class_registry: ClassRegistry = ClassRegistry.new()
	var target: int = HijinkThrowTarget.get_target(
		hijink_kind, class_id, max(1, level), class_registry, 18
	)

	# Penalty from incomplete planning (RAW §plan_hijink L1229).
	var planning_penalty: int = HijinkPlanningResolver.incomplete_planning_penalty(hijink_id)

	# Roll d20. Use roll_digital — hijinks are NPC-side throws by RAW.
	var roll: RollResult = DiceSystem.roll_digital(20, 1, 0, "hijink_throw")
	var raw_d20: int = int(roll.modified_total)

	var outcome: Dictionary = HijinkThrowTarget.classify_outcome(
		raw_d20, planning_penalty, target, strict_catch
	)

	# Compute yield on success.
	var cp_yield: int = 0
	var detail: String = ""
	if bool(outcome.get("success", false)):
		var yield_result: Dictionary = yield_callable.call(level, rng, params, character_id)
		cp_yield = int(yield_result.get("cp_yield", 0))
		detail = _str_or_empty(yield_result.get("detail"))
		# Credit yield to boss treasury via PartyWallet (deposit to character).
		if cp_yield > 0 and not boss_id.is_empty():
			PartyWallet.deposit_to_character(boss_id, cp_yield)

	# Update hijink row.
	var hijink_fields: Dictionary = {
		"throw_result": raw_d20,
		"cp_yield": cp_yield,
		"caught": 1 if bool(outcome.get("caught", false)) else 0,
		"status": "resolved",
		"completed_day": current_day,
		"planning_state": "complete",
	}
	SyndicateRepository.update_hijink(hijink_id, hijink_fields)

	# Caught branch: insert caught_perpetrators row, set lay-low requirement
	# off (since caught), and signal.
	var caught_id: String = ""
	if bool(outcome.get("caught", false)) and not character_id.is_empty():
		caught_id = _create_caught_perpetrator(
			character_id, hijink_id, hijink_kind, current_day, rng
		)
		# Flip the member to jailed status.
		if not member_id.is_empty():
			SyndicateRepository.update_member(member_id, {"status": "jailed"})

	# Lay-low requirement (only on a successful run of a lay-low-required kind).
	# RAW L1195 — laying low is required AFTER the activity, regardless of
	# whether the throw succeeded; the catch branch jails the perpetrator
	# instead.
	if (hijink_kind in LAY_LOW_REQUIRED_KINDS) and not bool(outcome.get("caught", false)) and not character_id.is_empty():
		# The base id ties to the hideout. v1 reads it from the hijink row's
		# hideout_id; if absent, falls back to "syndicate:<syndicate_id>".
		var base_id: String = _str_or_empty(hijink.get("hideout_id"))
		if base_id.is_empty():
			base_id = "syndicate:%s" % _str_or_empty(hijink.get("syndicate_id"))
		else:
			base_id = "stronghold:%s" % base_id
		# Lay-low duration: RAW 2d8+3 days.
		var lay_low_days: int = rng.randi_range(1, 8) + rng.randi_range(1, 8) + 3
		var ends_day: int = current_day + lay_low_days
		SyndicateRepository.upsert_lay_low(character_id, base_id, current_day, ends_day)
		EventBus.lay_low_started.emit(character_id, ends_day)

	# Signals.
	EventBus.hijink_resolved.emit(
		hijink_id,
		bool(outcome.get("success", false)),
		cp_yield,
		bool(outcome.get("caught", false)),
	)

	return {
		"summary": _summary_string(hijink_kind, outcome, cp_yield, detail),
		"hijink_id": hijink_id,
		"raw_d20": raw_d20,
		"target": target,
		"planning_penalty": planning_penalty,
		"success": bool(outcome.get("success", false)),
		"caught": bool(outcome.get("caught", false)),
		"cp_yield": cp_yield,
		"caught_perpetrator_id": caught_id,
		"detail": detail,
	}


# ---------------------------------------------------------------------------
# Caught-perpetrator construction
# ---------------------------------------------------------------------------

static func _create_caught_perpetrator(
		character_id: String,
		hijink_id: String,
		hijink_kind: String,
		current_day: int,
		rng: RandomNumberGenerator,
) -> String:
	var charges_table: Array = CHARGES_ON_CAPTURE.get(hijink_kind, [])
	if charges_table.is_empty():
		return ""
	var charge_index: int = rng.randi_range(0, 5)
	var crime_type: String = charges_table[charge_index]
	var time_days: int = _roll_languish_days(crime_type, rng)
	var prior_mod: int = CharacterLegalStatusRepository.get_prior_crimes_modifier(character_id)
	var caught_id: String = SyndicateRepository.create_caught({
		"character_id": character_id,
		"hijink_assignment_id": hijink_id,
		"crime_type": crime_type,
		"time_languishing_days": time_days,
		"arrested_day": current_day,
		"prior_crimes_modifier": prior_mod,
	})
	EventBus.perpetrator_caught.emit(caught_id, character_id, crime_type)
	return caught_id


static func _roll_languish_days(crime_type: String, rng: RandomNumberGenerator) -> int:
	var spec: Dictionary = TIME_LANGUISHING_BY_CRIME.get(crime_type, {})
	if spec.is_empty():
		return rng.randi_range(1, 6)
	var dice: int = int(spec.get("dice", 1))
	var sides: int = int(spec.get("sides", 1))
	var modifier: int = int(spec.get("mod", 0))
	var unit_days: int = int(spec.get("unit_days", 1))
	var total: int = modifier
	# RAW notation uses XdY where X is *number of dice* and Y is the *die
	# size*. Our table inverts (dice=count, sides=die-size) — but for
	# RAW expressions like 1d2 / 1d4 / 1d6 / 1d8 / 1d12 / 2d12, dice IS the
	# die size and sides IS the count of dice. Re-decode:
	# RAW "2d12 months" → dice=12, sides=2 → 2 rolls of 1d12.
	var roll_count: int = sides
	var die_size: int = dice
	for _i in roll_count:
		total += rng.randi_range(1, die_size)
	return total * unit_days


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _read_class_id(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	# Schema column is `character_class` (per migration 001 + the characters
	# table). `class_id` does not exist as a column. We map both for safety.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT character_class FROM characters WHERE id = ?", [character_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return _str_or_empty(CampaignRepository.db.query_result[0].get("character_class"))


## SQLite NULLs surface as null in Dictionary; String(null) errors in
## Godot 4. Normalize to "".
static func _str_or_empty(v: Variant) -> String:
	if v == null:
		return ""
	return str(v)


static func _summary_string(
		hijink_kind: String,
		outcome: Dictionary,
		cp_yield: int,
		detail: String,
) -> String:
	if bool(outcome.get("caught", false)):
		return "%s: caught (rolled %d, target %d, fail-by %d)" % [
			hijink_kind,
			int(outcome.get("effective_roll", 0)),
			0,  # target gets included in the resolve return dict; summary stays terse
			int(outcome.get("margin_of_failure", 0)),
		]
	if bool(outcome.get("success", false)):
		var s: String = "%s succeeded — yield %s" % [hijink_kind, Currency.format_cost(cp_yield)]
		if not detail.is_empty():
			s += " (%s)" % detail
		return s
	return "%s failed (no catch, no yield)" % hijink_kind
