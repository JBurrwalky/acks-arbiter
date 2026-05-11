class_name RecruitmentVagariesResolver
extends RefCounted

## Resolves the monthly Vagaries of Recruitment roll per
## daw_vagaries.xml §vagaries_of_recruitment L24-185 and the 19-row dispatch
## table at gdd-army-warfare.md §5.
##
## Trigger: once per game-month per character who launched a recruitment
## activity (Conscript / Levy Militia / Hire Mercenaries / Solicit Mercenaries
## / Call to Arms) that month. The activity handlers set
## `is_recruiting_this_month = true` on the launching character; the monthly
## scheduler tick iterates all recruiting characters and rolls 1d100.
##
## v1 implementation surface:
##   resolve(activity_id, character_id, calendar_day, dice_roller=Callable())
##     -> Dictionary {roll, result_key, payload, summary}
##
## The handler emits EventBus.recruitment_vagary_resolved(activity_id, result_key, payload)
## with the structured payload. Concrete world-side mutations (spawning a
## brigand army, generating a soldier-of-fortune NPC, applying a bidding-war
## price multiplier, etc.) are surfaced as payload data so downstream systems
## (Phase 7 Realm AI, Phase 8 Favors & Duties, the unified log) can consume
## them. v1 does NOT mutate world state directly except in the simplest cases
## (treasury credit for tribute) — RAW dictates that real consequences belong
## to subsystems we have not built yet.

# ---------------------------------------------------------------------------
# 19-row dispatch table per gdd-army-warfare.md §5
# Each row: roll_low, roll_high, result_key, summary
# ---------------------------------------------------------------------------

const VAGARY_TABLE := [
	[1,   2,   "war_declared",         "War declared by a rival realm."],
	[3,   7,   "resignation",          "An officer resigns."],
	[8,   12,  "treacherous_mercenaries", "A mercenary unit threatens to desert."],
	[13,  17,  "bidding_war",          "Mercenary find-cost inflated for 1d6 months."],
	[18,  22,  "weak_recruits",        "Conscripts/militia recruited this month qualify only as light infantry."],
	[23,  27,  "commander_casualty",   "An officer dies suddenly."],
	[28,  32,  "brigands",             "Renegade enemy army spawns within the realm."],
	[33,  37,  "commerce_disrupted",   "Largest urban settlement treated as 1 market class smaller for 1d6 months."],
	[38,  42,  "war_profiteers",       "Equipment prices +10% (cumulative)."],
	[43,  58,  "all_quiet",            "All quiet — no effect."],
	[59,  63,  "tribute",              "Owner's treasury gains modest tribute."],
	[64,  68,  "commerce_improves",    "Largest urban settlement treated as 1 market class larger for 1d6 months."],
	[69,  73,  "foreign_legion",       "Mercenary unit of an unusual type appears for hire."],
	[74,  78,  "soldier_of_fortune",   "An NPC officer offers henchman service."],
	[79,  83,  "stout_recruits",       "Twice the conscripts/militia this month qualify for advanced training."],
	[84,  88,  "surplus_sellswords",   "Mercenary crop doubled for 4 time periods."],
	[89,  93,  "mercenaries",          "Roll on Follower Type by Class for the army leader."],
	[94,  98,  "bold_captain",         "A free mercenary officer at scale-tier rank arrives."],
	[99,  100, "alliance_offered",     "An adjacent same-size domain offers half its garrison as alliance support."],
]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

static func resolve(
	activity_id: String,
	character_id: String,
	calendar_day: int,
	dice_roller: Callable = Callable()
) -> Dictionary:
	var roll: int = _roll_d100(dice_roller)
	var result: Dictionary = lookup(roll)
	var result_key: String = String(result.get("result_key", "all_quiet"))
	var payload: Dictionary = build_payload(result_key, {
		"activity_id": activity_id,
		"character_id": character_id,
		"calendar_day": calendar_day,
		"dice_roller": dice_roller,
	})
	# Phase 9A: dispatch side-effecting handlers for results whose subsystems
	# have landed (commerce_disrupted, commerce_improves). Other results stay
	# payload-only — their subsystems land in later phases.
	var side_effect: Dictionary = _apply_side_effects(
		result_key, character_id, calendar_day, payload)
	if not side_effect.is_empty():
		payload["side_effect"] = side_effect
	if EventBus.has_signal("recruitment_vagary_resolved"):
		EventBus.emit_signal(
			"recruitment_vagary_resolved",
			activity_id, result_key, payload
		)
	return {
		"roll": roll,
		"result_key": result_key,
		"summary": result.get("summary", ""),
		"payload": payload,
	}


# ---------------------------------------------------------------------------
# Phase 9A: side-effect dispatcher
# ---------------------------------------------------------------------------

static func _apply_side_effects(
	result_key: String,
	character_id: String,
	calendar_day: int,
	payload: Dictionary
) -> Dictionary:
	match result_key:
		"commerce_disrupted":
			var settlement_id: String = _largest_urban_settlement_for_character(character_id)
			if settlement_id.is_empty():
				return {"applied": false, "reason": "no_urban_settlement"}
			var campaign_id: String = _campaign_for_character(character_id)
			var dice = payload.get("_dice_passthrough", null)
			var outcome: Dictionary = MarketClassModifierResolver.apply_commerce_disrupted(
				campaign_id, settlement_id, calendar_day, dice)
			return {
				"applied": bool(outcome.get("success", false)),
				"settlement_entrance_id": settlement_id,
				"modifier_id": String(outcome.get("modifier_id", "")),
				"delta": -1,
				"duration_months": int(outcome.get("duration_months", 0)),
			}
		"commerce_improves":
			var settlement_id: String = _largest_urban_settlement_for_character(character_id)
			if settlement_id.is_empty():
				return {"applied": false, "reason": "no_urban_settlement"}
			var campaign_id: String = _campaign_for_character(character_id)
			var dice = payload.get("_dice_passthrough", null)
			var outcome: Dictionary = MarketClassModifierResolver.apply_commerce_improves(
				campaign_id, settlement_id, calendar_day, dice)
			return {
				"applied": bool(outcome.get("success", false)),
				"settlement_entrance_id": settlement_id,
				"modifier_id": String(outcome.get("modifier_id", "")),
				"delta": 1,
				"duration_months": int(outcome.get("duration_months", 0)),
			}
		_:
			return {}


static func _largest_urban_settlement_for_character(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	# Find the settlement_entrance with the LOWEST market_class number
	# (class I = 1 = largest, class VI = 6 = smallest) attached to a domain
	# owned by this character.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT se.id FROM settlement_entrances se
		JOIN domains d ON d.id = se.parent_domain_id
		WHERE d.owner_character_id = ?
		ORDER BY se.market_class
		LIMIT 1
	""", [character_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _campaign_for_character(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT campaign_id FROM characters WHERE id = ?", [character_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("campaign_id", ""))


## Returns the list of distinct character_ids who launched any recruitment
## activity within the [now - 30 game-days, now] window. The monthly scheduler
## tick (wired in Phase 6A part 2) iterates this list and calls resolve() for
## each character. This avoids adding a per-character "is_recruiting_this_month"
## flag column — activity_state already records the launches we care about.
static func list_recruiting_characters(
	campaign_id: String,
	current_calendar_day: int,
	window_days: int = 30
) -> Array:
	if campaign_id.is_empty():
		return []
	var window_start: int = max(0, current_calendar_day - window_days)
	var recruiting_ids := [
		"conscript_troops", "levy_militia",
		"hire_mercenaries", "solicit_mercenaries", "call_to_arms",
	]
	var placeholders: String = ""
	for i in range(recruiting_ids.size()):
		placeholders += "?"
		if i < recruiting_ids.size() - 1:
			placeholders += ","
	var sql: String = """
		SELECT DISTINCT character_id FROM activity_state
		WHERE campaign_id = ?
		  AND activity_def_id IN (%s)
		  AND started_calendar_day >= ?
		  AND status IN ('active', 'completed')
	""" % placeholders
	var bindings: Array = [campaign_id]
	for rid in recruiting_ids:
		bindings.append(rid)
	bindings.append(window_start)
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		return []
	var result: Array = []
	for row in CampaignRepository.db.query_result:
		result.append(String(row.get("character_id", "")))
	return result


static func lookup(roll: int) -> Dictionary:
	for row in VAGARY_TABLE:
		var lo: int = int(row[0])
		var hi: int = int(row[1])
		if roll >= lo and roll <= hi:
			return {"result_key": String(row[2]), "summary": String(row[3])}
	return {"result_key": "all_quiet", "summary": "All quiet — no effect."}


# ---------------------------------------------------------------------------
# Per-result payload builders. These compute the data downstream systems need
# but do NOT mutate world state directly (except for tribute — a simple
# treasury credit). Mutating sub-systems consume the EventBus signal.
# ---------------------------------------------------------------------------

static func build_payload(result_key: String, ctx: Dictionary) -> Dictionary:
	var payload: Dictionary = {"result_key": result_key}
	var dice: Callable = ctx.get("dice_roller", Callable())
	match result_key:
		"war_declared":
			# rival_realm_id is left to Phase 7 Realm AI to fill in; v1 emits
			# a placeholder so the unified log can still display the headline.
			payload["rival_realm_id"] = ""
			payload["needs_realm_resolution"] = true
		"resignation":
			payload["target_role"] = "officer"
			payload["loyalty_check_required"] = true
		"treacherous_mercenaries":
			payload["target_role"] = "mercenary_unit"
			payload["desertion_check_required"] = true
		"bidding_war":
			# 1d6 months; cost multiplier = 1 + (2d4 / 10) per RAW.
			var months: int = _roll(dice, 1, 6)
			var mult_2d4: int = _roll(dice, 2, 4)
			payload["months_active"] = months
			payload["mercenary_find_cost_multiplier"] = 1.0 + (float(mult_2d4) / 10.0)
		"weak_recruits":
			payload["affected_calendar_month_day"] = int(ctx.get("calendar_day", 0))
			payload["downgrade_to"] = "light_infantry"
		"commander_casualty":
			payload["target_role"] = "commander"
			payload["save_vs_death_required"] = true
		"brigands":
			# RAW composition: 1 bowmen unit + 1 light cavalry unit + officers
			# + spawn at random hex within realm. Phase 7 spawns the army.
			payload["composition"] = ["bowmen", "light_cavalry"]
			payload["needs_realm_resolution"] = true
		"commerce_disrupted":
			var months: int = _roll(dice, 1, 6)
			payload["months_active"] = months
			payload["market_class_delta"] = -1
		"war_profiteers":
			# +10% on artillery / armor / mounts / supplies / weapons for 1d4 seasons.
			var seasons: int = _roll(dice, 1, 4)
			payload["seasons_active"] = seasons
			payload["price_multiplier"] = 1.10
			payload["categories"] = ["artillery", "armor", "mounts", "supplies", "weapons"]
		"all_quiet":
			pass
		"tribute":
			# treasury gains min(army monthly wages, 1 gp × realm peasant families).
			# v1 cannot derive realm wages without realm graph; leave empty,
			# Phase 7 fills in.
			payload["tribute_gp"] = 0
			payload["needs_realm_resolution"] = true
		"commerce_improves":
			var months: int = _roll(dice, 1, 6)
			payload["months_active"] = months
			payload["market_class_delta"] = 1
		"foreign_legion":
			payload["mercenary_morale_modifier"] = -1
			payload["unusual_type_required"] = true
		"soldier_of_fortune":
			payload["officer_level_offset"] = -2  # leader_level - 2
			payload["offered_role"] = "henchman"
		"stout_recruits":
			payload["affected_calendar_month_day"] = int(ctx.get("calendar_day", 0))
			payload["upgrade_count_multiplier"] = 2
		"surplus_sellswords":
			payload["time_periods"] = 4
			payload["mercenary_crop_multiplier"] = 2
		"mercenaries":
			payload["target_role"] = "follower_type_roll"
			payload["veteran_chance"] = 0.25
		"bold_captain":
			# Free mercenary officer at scale-tier rank; +1 base morale.
			payload["officer_morale_bonus"] = 1
			payload["scale_tier_rank"] = "auto"
		"alliance_offered":
			payload["needs_realm_resolution"] = true
			payload["alliance_garrison_fraction"] = 0.5
	return payload


# ---------------------------------------------------------------------------
# Dice helpers
# ---------------------------------------------------------------------------

static func _roll_d100(dice_roller: Callable) -> int:
	if dice_roller.is_valid():
		return int(dice_roller.call(1, 100))
	return randi_range(1, 100)


static func _roll(dice_roller: Callable, count: int, sides: int) -> int:
	if dice_roller.is_valid():
		return int(dice_roller.call(count, sides))
	var total: int = 0
	for i in range(count):
		total += randi_range(1, sides)
	return total
