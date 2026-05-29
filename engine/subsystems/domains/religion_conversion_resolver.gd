class_name ReligionConversionResolver
extends RefCounted

## Religion conversion mechanic per `gdd-religion-conversion.md` §3-§7.
##
## A conversion arc is the cost-and-time-bearing process that flips a domain's
## `effective_religion` (and therefore alignment) from one to another. The
## canonical state is **congregants of the target religion in the domain**
## against the **60% × peasant_families** threshold (Q-RC-7 resolution).
## Completion is atomic when the threshold is crossed.
##
## Public API:
##   * start_conversion(domain_id, to_religion, to_alignment, driving_character_id, calendar_day) -> String
##       Inserts a new `domain_religion_conversion` row (status='active').
##       Returns the new conversion id, or "" on rejection. Validates only
##       ONE active arc per domain.
##   * tick_conversion(domain_data, calendar_day) -> Dictionary
##       Called by DomainHandlers monthly tick for each active conversion.
##       Computes congregant gain, applies it, checks the 60% completion
##       threshold, checks morale-collapse failure mode, returns a result
##       dict summarizing the month.
##   * abort_conversion(conversion_id, calendar_day, reason) -> bool
##       Marks an arc 'aborted'. Reverts `domains.religion` to
##       `effective_religion`. Forfeits accumulated invested cp (per Q-RC-3).
##   * eligible_conversion_targets(domain_id) -> Array
##       Returns valid `to_religion` strings per the beastman-clanhold lock
##       (§9.7) + other constraints.
##   * religious_structures_gp_value_for_domain(domain_id, religion) -> int
##       v1 returns the consecrated_altars contribution. Pluggable so the
##       future urban-growth-stocking GDD's temple infrastructure drops in
##       cleanly (Q-RC-9 deferred dependency).
##
## All methods are static. RNG is injectable via a Callable for tests (the
## roller has the same signature as DomainGrowthResolver: `(faces, count,
## exploding) -> int` returning the SUM of rolls).

# Completion threshold: 60% of peasant_families must be in the target
# religion's congregation (Q-RC-7).
const COMPLETION_THRESHOLD_RATIO_NUM := 6
const COMPLETION_THRESHOLD_RATIO_DEN := 10

# Conversion-in-progress base morale penalty (§5.5). Consumed by
# DomainMoraleResolver via the active-conversion lookup.
const CONVERSION_BASE_MORALE_PENALTY := -1

# §5.3 morale multiplier table (per-100 to keep integer math; divide by 100
# at multiplication time). Index = morale tier offset from Rebellious.
# 0 = Rebellious (0%) → 8 = Stalwart (200%).
const _MORALE_MULTIPLIERS_PCT := [
	0,    # -4 Rebellious
	25,   # -3 Defiant
	50,   # -2 Turbulent
	75,   # -1 Demoralized
	100,  #  0 Apathetic
	125,  # +1 Loyal
	150,  # +2 Dedicated
	175,  # +3 Steadfast
	200,  # +4 Stalwart
]

# Morale-collapse failure: 3 consecutive months at Rebellious (-4 or worse)
# trigger status='failed_morale' per §7.3.
const REBELLIOUS_MONTHS_FOR_FAILURE := 3

# §5.4 driver bonus tiers (per-100; divide by 100 at multiplication time).
const DRIVER_BONUS_PCT_RULER_DIVINE_CASTER := 150  # divine-caster ruler of target religion
const DRIVER_BONUS_PCT_SPIRITUAL_ADVISOR := 125    # spiritual advisor of target religion
const DRIVER_BONUS_PCT_HENCHMAN_DIVINE := 110      # henchman divine caster
const DRIVER_BONUS_PCT_MISSIONARY_ONLY := 100      # no driver / fighter+missionary

# §5.4 altar bonus: 1.0 + 0.1 × count_of_target_altars, capped at 1.5×.
const ALTAR_BONUS_BASE_PCT := 100
const ALTAR_BONUS_PER_ALTAR_PCT := 10
const ALTAR_BONUS_CAP_PCT := 150


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

static func start_conversion(
	domain_id: String,
	to_religion: String,
	to_alignment: String,
	driving_character_id: String,
	calendar_day: int
) -> String:
	if domain_id.is_empty() or to_religion.is_empty():
		push_error("ReligionConversionResolver.start_conversion: domain_id + to_religion required")
		return ""
	if not (to_alignment in ["lawful", "neutral", "chaotic"]):
		push_error("ReligionConversionResolver.start_conversion: invalid to_alignment '%s'" % to_alignment)
		return ""
	# At most one active conversion per domain (§4.1).
	if get_active_for_domain(domain_id) != "":
		push_error("ReligionConversionResolver.start_conversion: domain already has an active arc")
		return ""
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		push_error("ReligionConversionResolver.start_conversion: domain not found: %s" % domain_id)
		return ""
	# Beastman-clanhold lock per §9.7: beastman-populated clanholds cannot
	# convert to non-chaotic religion.
	var establishment_method: String = String(domain.get("establishment_method", "")).to_lower()
	var domain_is_beastman: bool = establishment_method in ["clanhold_annex", "recruit_chieftain"]
	if domain_is_beastman and to_alignment != "chaotic":
		push_error("ReligionConversionResolver.start_conversion: beastman-populated clanhold "
			+ "cannot convert to non-chaotic alignment (gdd-religion-conversion.md §9.7)")
		return ""
	var from_religion: String = String(domain.get("effective_religion", domain.get("religion", "")))
	var from_alignment: String = String(domain.get("alignment", "neutral"))
	var campaign_id: String = String(domain.get("campaign_id", ""))
	var conversion_id: String = CampaignRepository.generate_id()
	var driver_param: Variant = driving_character_id if not driving_character_id.is_empty() else null
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO domain_religion_conversion
			(id, campaign_id, domain_id, from_religion, to_religion,
			 from_alignment, to_alignment, progress_pct, driving_character_id,
			 started_calendar_day, last_progressed_calendar_day, status,
			 total_invested_cp, months_at_rebellious)
		VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, 'active', 0, 0)
	""", [conversion_id, campaign_id, domain_id, from_religion, to_religion,
		  from_alignment, to_alignment, driver_param,
		  calendar_day, calendar_day]):
		return ""
	# Mirror the decree's effect on domains.religion (declared religion).
	# domains.effective_religion stays at from_religion until completion.
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET religion = ?, updated_at = datetime('now') WHERE id = ?",
		[to_religion, domain_id])
	if EventBus.has_signal("religion_conversion_started"):
		EventBus.emit_signal("religion_conversion_started",
			domain_id, from_religion, to_religion)
	return conversion_id


static func tick_conversion(
	domain_data: Dictionary,
	calendar_day: int,
	dice_roller: Callable = Callable()
) -> Dictionary:
	var result: Dictionary = {
		"applied": false,
		"congregant_gain": 0,
		"completed": false,
		"failed_morale": false,
		"status_change": "",
		"conversion_id": "",
	}
	var domain_id: String = String(domain_data.get("id", ""))
	if domain_id.is_empty():
		return result
	var conversion_id: String = get_active_for_domain(domain_id)
	if conversion_id.is_empty():
		return result  # no active arc for this domain
	var arc: Dictionary = _get_conversion(conversion_id)
	if arc.is_empty():
		return result
	result["applied"] = true
	result["conversion_id"] = conversion_id

	# Track Rebellious-month counter for §7.3 failure mode.
	var morale_tier: String = DomainMoraleResolver.morale_tier(int(domain_data.get("morale", 0)))
	var months_at_rebellious: int = int(arc.get("months_at_rebellious", 0))
	if morale_tier == DomainMoraleResolver.TIER_REBELLIOUS:
		months_at_rebellious += 1
	else:
		months_at_rebellious = 0
	if months_at_rebellious >= REBELLIOUS_MONTHS_FOR_FAILURE:
		_mark_failed_morale(conversion_id, calendar_day)
		result["failed_morale"] = true
		result["status_change"] = "failed_morale"
		return result
	# Persist updated rebellious counter.
	CampaignRepository.db.query_with_bindings(
		"UPDATE domain_religion_conversion SET months_at_rebellious = ?, updated_at = datetime('now') WHERE id = ?",
		[months_at_rebellious, conversion_id])

	# Compute morale multiplier (per-100).
	var morale_pct: int = _morale_multiplier_pct(int(domain_data.get("morale", 0)))

	# Sum monthly proselytizing gp into the conversion's target domain.
	# Per §5.4: charitable spell gp + missionary gp + religious-structure gp.
	# v1 reads pending cp from the driving caster's per-domain congregants
	# row (or the ruler's, if no driver registered — see _proselytizing_caster_id).
	# Multi-caster contributions per §5.7 are deferred (no per-character
	# religion column on `characters` yet).
	var to_religion: String = String(arc.get("to_religion", ""))
	var proselytizing_caster_id: String = _proselytizing_caster_id(arc, domain_id)
	var proselytizing_cp: int = 0
	if not proselytizing_caster_id.is_empty():
		proselytizing_cp = CampaignRepository.congregant_pending_cp_for_caster_in_domain(
			proselytizing_caster_id, domain_id)
	# Religious-structure contribution per §9.8 (v1: consecrated_altars only).
	var structure_cp: int = religious_structures_gp_value_for_domain(domain_id, to_religion) * 100
	var total_cp: int = proselytizing_cp + structure_cp
	var total_invested_cp: int = int(arc.get("total_invested_cp", 0)) + total_cp

	# §5.4 base gain: floor(total_gp / 1000) × (1d10 + Cha_mod).
	@warning_ignore("integer_division")
	var rolls_count: int = total_cp / 100_000  # cp → 1000gp units
	var cha_mod: int = _driver_cha_mod(arc)
	var base_gain: int = 0
	if rolls_count > 0:
		var roller: Callable
		if dice_roller.is_valid():
			roller = dice_roller
		else:
			roller = func(faces: int, count: int, _exp: bool) -> int:
				return _dice_system_default(faces, count)
		var rolled: int = roller.call(10, rolls_count, false)
		base_gain = maxi(0, rolled + cha_mod * rolls_count)

	# Apply driver + altar + morale multipliers.
	var driver_pct: int = _driver_bonus_pct(arc, domain_id)
	var altar_pct: int = _altar_bonus_pct(domain_id, to_religion)
	# Cap composite multiplier integer math: gain × morale_pct × driver_pct
	# × altar_pct, then divide by 100^3 = 1_000_000. Order-independent.
	var gain_modified_n: int = base_gain * morale_pct * driver_pct * altar_pct
	@warning_ignore("integer_division")
	var gain_modified: int = gain_modified_n / 1_000_000

	# §5.4 RAW cap: cannot gain more congregants than uncovered peasants.
	# v1: the "target congregant count" is the driving caster's congregants
	# in this domain (or the ruler's, if no driver). Multi-caster contributions
	# per §5.7 are deferred.
	var peasants: int = int(domain_data.get("peasant_families", 0))
	var existing_target: int = 0
	if not proselytizing_caster_id.is_empty():
		existing_target = CampaignRepository.congregants_in_domain_for_caster(
			proselytizing_caster_id, domain_id)
	var room: int = maxi(0, peasants - existing_target)
	var actual_gain: int = mini(gain_modified, room)
	result["congregant_gain"] = actual_gain

	# Credit gain to the proselytizing caster's per-domain congregants row.
	if actual_gain > 0 and not proselytizing_caster_id.is_empty():
		CampaignRepository.adjust_congregant_count(
			proselytizing_caster_id, actual_gain, domain_id)

	# Compute new total target congregants + progress_pct.
	var new_target_count: int = existing_target + actual_gain
	var threshold_count: int = (peasants * COMPLETION_THRESHOLD_RATIO_NUM) \
		/ COMPLETION_THRESHOLD_RATIO_DEN
	var progress_pct: int = 0
	if threshold_count > 0:
		@warning_ignore("integer_division")
		var raw_pct: int = (100 * new_target_count) / threshold_count
		progress_pct = mini(100, maxi(0, raw_pct))

	# Persist progress + invested_cp + last_progressed_calendar_day.
	CampaignRepository.db.query_with_bindings("""
		UPDATE domain_religion_conversion
		SET progress_pct = ?, total_invested_cp = ?,
		    last_progressed_calendar_day = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [progress_pct, total_invested_cp, calendar_day, conversion_id])

	# §5.6 completion check: congregants ≥ 60% of peasant_families.
	if threshold_count > 0 and new_target_count >= threshold_count:
		_complete_conversion(conversion_id, domain_id, arc, calendar_day,
			new_target_count, peasants)
		result["completed"] = true
		result["status_change"] = "completed"
	else:
		if EventBus.has_signal("religion_conversion_progressed"):
			EventBus.emit_signal("religion_conversion_progressed",
				domain_id, conversion_id, new_target_count)
	return result


static func abort_conversion(
	conversion_id: String,
	calendar_day: int,
	reason: String = "player_cancel"
) -> bool:
	if conversion_id.is_empty():
		return false
	var arc: Dictionary = _get_conversion(conversion_id)
	if arc.is_empty():
		return false
	if String(arc.get("status", "")) != "active":
		return false
	# Revert domains.religion to the original effective_religion.
	var domain_id: String = String(arc.get("domain_id", ""))
	var from_religion: String = String(arc.get("from_religion", ""))
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET religion = ?, updated_at = datetime('now') WHERE id = ?",
		[from_religion, domain_id])
	# Mark the arc aborted (total_invested_cp stays for audit; conversation
	# §7.2 says it is forfeit but the row remains for the departure log).
	CampaignRepository.db.query_with_bindings("""
		UPDATE domain_religion_conversion
		SET status = 'aborted', last_progressed_calendar_day = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [calendar_day, conversion_id])
	if EventBus.has_signal("religion_conversion_aborted"):
		EventBus.emit_signal("religion_conversion_aborted", domain_id, reason)
	return true


static func eligible_conversion_targets(domain_id: String) -> Array:
	# v1 returns a placeholder: any religion is eligible EXCEPT non-chaotic
	# religions for beastman-populated clanholds. The full religion catalog
	# lives in the setting generator (not yet shipped). Callers (the decree
	# handler) consult this list to gate the picker.
	var result: Array = []
	if domain_id.is_empty():
		return result
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return result
	# Beastman-clanhold lock per §9.7.
	var method: String = String(domain.get("establishment_method", "")).to_lower()
	var is_beastman_clanhold: bool = method in ["clanhold_annex", "recruit_chieftain"]
	result.append({"alignment": "chaotic", "allowed": true})
	result.append({"alignment": "neutral", "allowed": not is_beastman_clanhold})
	result.append({"alignment": "lawful", "allowed": not is_beastman_clanhold})
	return result


## Pluggable helper per §9.8 (Q-RC-9 deferred-dependency). Returns the gp
## value of consecrated altars of `religion` currently active for `domain_id`.
## Future: the urban-growth-stocking GDD's temple infrastructure adds to this
## via a separate `temples_for_religion_in_domain` join — the resolver doesn't
## need to know about temples, it just needs the gp-value total.
##
## v1 implementation: count active `consecrated_altar` effects with matching
## religion attribute. Each altar contributes its `gp_value` (or a default
## 250gp per the Phase 10A.2 schema if unspecified).
static func religious_structures_gp_value_for_domain(domain_id: String, religion: String) -> int:
	if domain_id.is_empty() or religion.is_empty():
		return 0
	# Stub for v1: pending_divine_effects rows of effect_kind='consecrate_altar'
	# with matching religion in the payload. The Phase 10A.2 effect schema
	# stores religion + gp_value in effect_payload_json.
	var current_day: int = Timekeeping.get_total_days()
	if not CampaignRepository.db.query_with_bindings("""
		SELECT effect_payload_json FROM pending_divine_effects
		WHERE domain_id = ?
		  AND effect_kind = 'consecrate_altar'
		  AND status = 'applied'
		  AND expires_at_calendar_day > ?
	""", [domain_id, current_day]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	var total_gp: int = 0
	for row in CampaignRepository.db.query_result:
		var raw: String = str(row.get("effect_payload_json", "{}"))
		var parsed: Variant = JSON.parse_string(raw)
		if not (parsed is Dictionary):
			continue
		var data: Dictionary = parsed as Dictionary
		if str(data.get("religion", "")) != religion:
			continue
		total_gp += int(data.get("gp_value", 250))
	return total_gp


## Returns the id of the active conversion arc for `domain_id`, or "" if none.
static func get_active_for_domain(domain_id: String) -> String:
	if domain_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM domain_religion_conversion
		WHERE domain_id = ? AND status = 'active'
		LIMIT 1
	""", [domain_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

static func _get_conversion(conversion_id: String) -> Dictionary:
	if conversion_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domain_religion_conversion WHERE id = ? LIMIT 1",
		[conversion_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _morale_multiplier_pct(current_morale: int) -> int:
	# Map morale [-4, +4] to multiplier index [0, 8]. Out-of-range clamps.
	var idx: int = clampi(current_morale + 4, 0, _MORALE_MULTIPLIERS_PCT.size() - 1)
	return _MORALE_MULTIPLIERS_PCT[idx]


static func _driver_bonus_pct(arc: Dictionary, domain_id: String) -> int:
	var driver_id: String = String(arc.get("driving_character_id", ""))
	if driver_id.is_empty():
		return DRIVER_BONUS_PCT_MISSIONARY_ONLY
	var driver: Dictionary = CampaignRepository.get_character(driver_id)
	if driver.is_empty():
		return DRIVER_BONUS_PCT_MISSIONARY_ONLY
	# v1 driver-bonus selection: a more nuanced reading would distinguish
	# ruler-of-this-domain vs spiritual-advisor vs henchman. Pending the
	# Phase 11D.3 spiritual-advisor helper (gdd-religion-conversion.md §9.6),
	# v1 returns the ruler tier when driver IS the domain's owner_character_id;
	# otherwise henchman tier. Spiritual-advisor (1.25×) tier lands when the
	# helper ships in a polish pass.
	var owner_id: String = String(_get_domain_owner(domain_id))
	if driver_id == owner_id:
		return DRIVER_BONUS_PCT_RULER_DIVINE_CASTER
	return DRIVER_BONUS_PCT_HENCHMAN_DIVINE


static func _altar_bonus_pct(domain_id: String, religion: String) -> int:
	if domain_id.is_empty() or religion.is_empty():
		return ALTAR_BONUS_BASE_PCT
	var current_day: int = Timekeeping.get_total_days()
	if not CampaignRepository.db.query_with_bindings("""
		SELECT effect_payload_json FROM pending_divine_effects
		WHERE domain_id = ?
		  AND effect_kind = 'consecrate_altar'
		  AND status = 'applied'
		  AND expires_at_calendar_day > ?
	""", [domain_id, current_day]):
		return ALTAR_BONUS_BASE_PCT
	if CampaignRepository.db.query_result.is_empty():
		return ALTAR_BONUS_BASE_PCT
	var matching_altars: int = 0
	for row in CampaignRepository.db.query_result:
		var raw: String = str(row.get("effect_payload_json", "{}"))
		var parsed: Variant = JSON.parse_string(raw)
		if not (parsed is Dictionary):
			continue
		if String((parsed as Dictionary).get("religion", "")) == religion:
			matching_altars += 1
	var bonus: int = ALTAR_BONUS_BASE_PCT + (matching_altars * ALTAR_BONUS_PER_ALTAR_PCT)
	return mini(bonus, ALTAR_BONUS_CAP_PCT)


static func _driver_cha_mod(arc: Dictionary) -> int:
	var driver_id: String = String(arc.get("driving_character_id", ""))
	if driver_id.is_empty():
		# Missionary-only: use the ruler's Cha mod (the domain owner).
		var domain_id: String = String(arc.get("domain_id", ""))
		var owner_id: String = _get_domain_owner(domain_id)
		if owner_id.is_empty():
			return 0
		return _cha_mod_for_character(owner_id)
	return _cha_mod_for_character(driver_id)


static func _cha_mod_for_character(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	var c: Dictionary = CampaignRepository.get_character(character_id)
	if c.is_empty():
		return 0
	var cha: int = int(c.get("charisma", 10))
	return _ability_modifier(cha)


## ACKS ability modifier table (mirrors `DomainHandlers._cha_modifier`):
##   3 → -3; 4-5 → -2; 6-8 → -1; 9-12 → 0; 13-15 → +1; 16-17 → +2; 18 → +3.
## Inlined here to keep the resolver self-contained (no `AbilityUtils`
## dependency — the existing `engine/subsystems/characters/ability_utils.gd`
## doesn't export a generic `ability_modifier` function).
static func _ability_modifier(score: int) -> int:
	if score <= 3:    return -3
	elif score <= 5:  return -2
	elif score <= 8:  return -1
	elif score <= 12: return 0
	elif score <= 15: return 1
	elif score <= 17: return 2
	return 3


static func _get_domain_owner(domain_id: String) -> String:
	if domain_id.is_empty():
		return ""
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return ""
	return String(domain.get("owner_character_id", ""))


## Returns the caster who is "the conversion's proselytizer of record" for v1.
## When the arc has a registered driving_character_id, that's the caster.
## Otherwise the domain's ruler is the implicit driver (missionary-only path
## per §6.3 — the ruler pays for missionaries; the congregants get credited
## to the ruler's row).
static func _proselytizing_caster_id(arc: Dictionary, domain_id: String) -> String:
	var driver: String = String(arc.get("driving_character_id", ""))
	if not driver.is_empty():
		return driver
	return _get_domain_owner(domain_id)


static func _complete_conversion(
	conversion_id: String,
	domain_id: String,
	arc: Dictionary,
	calendar_day: int,
	congregants_at_completion: int,
	peasant_families_at_completion: int
) -> void:
	var to_religion: String = String(arc.get("to_religion", ""))
	var to_alignment: String = String(arc.get("to_alignment", ""))
	var from_religion: String = String(arc.get("from_religion", ""))
	# §5.6 step 1-4: flip status, effective_religion, alignment.
	CampaignRepository.db.query_with_bindings("""
		UPDATE domain_religion_conversion
		SET status = 'completed', progress_pct = 100,
		    last_progressed_calendar_day = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [calendar_day, conversion_id])
	CampaignRepository.db.query_with_bindings("""
		UPDATE domains
		SET effective_religion = ?, alignment = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [to_religion, to_alignment, domain_id])
	if EventBus.has_signal("religion_conversion_completed"):
		EventBus.emit_signal("religion_conversion_completed",
			domain_id, from_religion, to_religion)


static func _mark_failed_morale(conversion_id: String, calendar_day: int) -> void:
	var arc: Dictionary = _get_conversion(conversion_id)
	if arc.is_empty():
		return
	# Revert domains.religion to the original effective_religion.
	var domain_id: String = String(arc.get("domain_id", ""))
	var from_religion: String = String(arc.get("from_religion", ""))
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET religion = ?, updated_at = datetime('now') WHERE id = ?",
		[from_religion, domain_id])
	CampaignRepository.db.query_with_bindings("""
		UPDATE domain_religion_conversion
		SET status = 'failed_morale', last_progressed_calendar_day = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [calendar_day, conversion_id])
	if EventBus.has_signal("religion_conversion_failed"):
		EventBus.emit_signal("religion_conversion_failed",
			domain_id, "morale_collapse")


static func _dice_system_default(faces: int, count: int) -> int:
	if count <= 0 or faces <= 0:
		return 0
	var total: int = 0
	for _i in range(count):
		var rr: RollResult = DiceSystem.roll_digital(faces, 1, 0, "religion_conversion")
		total += rr.modified_total
	return total
