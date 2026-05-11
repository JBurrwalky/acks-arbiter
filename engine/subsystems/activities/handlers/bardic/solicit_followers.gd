class_name SolicitFollowersHandler
extends RefCounted

## solicit_followers handler (Phase 10A.3 — Bardic Patronage block).
##
## Ongoing minor activity. Per acore_campaign_classes.xml §hall L577-584:
##   - Available to Bards L9+ who have established a hall.
##   - On completion: 1d4+1 × 10 0-level mercenaries come to apply for jobs
##     and training. PLUS 1d6 bards of 1st-3rd level apply for jobs and
##     training. Hire requires standard mercenary wages.
##
## Activity duration: 1-3 weeks per the recruitment cadence pattern shared
## with solicit_mercenaries (default_ticks_required = 14 days).
##
## State.params_json shape:
##   { "wage_offered_gp": <int>  # optional override; default = standard mercenary wages }
##
## On completion the handler creates:
##   * One troop_unit row of 0-level mercenaries (source_type='mercenary' per
##     bard L9 attractor, troop_type='light_infantry' default). Count =
##     (1d4 + 1) × 10. v1 keeps 0-level mercenaries in troop_units since they
##     are paid wages and do NOT gain XP / get treasure shares; they are
##     hirelings, not followers in the Q25 sense.
##   * 1d6 named-bard FOLLOWERS for the 1st-3rd-level applicants. Per Q25
##     [RESOLVED 2026-05-11], these go into the `followers` table with
##     source_kind='bardic_recruit' rather than `characters` with
##     character_type='henchman'. The player may subsequently call
##     CampaignRepository.promote_follower_to_henchman to fold a follower
##     into the henchmen pool when slots are available (no hiring reaction
##     roll required per the same Q25 resolution).
##
## Q25a (retro migration, 2026-05-11): this rewrites the prior Phase 10A.3
## behavior of inserting bard recruits into `characters`. No data migration
## was required because no campaigns had bard-recruit rows yet at the time
## of the rewrite.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	if character_id.is_empty():
		return {"summary": "solicit_followers: no character_id"}

	var character := _get_character(character_id)
	if character.is_empty():
		return {"summary": "solicit_followers: character not found"}
	if String(character.get("character_class", "")) != "bard":
		return {"summary": "solicit_followers failed: bard class required"}
	if int(character.get("level", 1)) < 9:
		return {"summary": "solicit_followers failed: level 9+ required"}

	var domain_id: String = _resolve_domain_for_ruler(character_id)
	# Domain is not strictly required — a bard can solicit at their hall even
	# pre-domain — but if there's a domain, we ledger the recruitment there.

	# Roll mercenary count: (1d4 + 1) × 10 = 20..50 in tens.
	var merc_roll: RollResult = DiceSystem.roll_digital(4, 1, 1, "solicit_followers_merc")
	var merc_count: int = max(0, merc_roll.modified_total) * 10

	# Roll bard-applicant count: 1d6.
	var bard_roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "solicit_followers_bards")
	var bard_count: int = max(0, bard_roll.modified_total)

	# Create mercenary troop_unit (single unit; player can split later).
	var unit_id: String = ""
	if merc_count > 0:
		unit_id = TroopUnitRepository.create_unit({
			"campaign_id": String(character.get("campaign_id", "")),
			"owner_character_id": character_id,
			"assigned_domain_id": domain_id,
			"source_type": "mercenary",
			"troop_type": "light_infantry",
			"race": "human",
			"tier": "untrained",
			"starting_count": merc_count,
			"count": merc_count,
			"battle_rating": 0.5 * merc_count,  # light infantry baseline BR
			"monthly_wage_gp": 3 * merc_count,  # standard mercenary wage
			"monthly_supply_gp": 4 * merc_count,  # 1 gp/week × 4 weeks
			"monthly_specialist_gp": 0,
			"monthly_cost_gp": 7 * merc_count,
			"morale": 0,
			"is_veteran": false,
			"is_trained": false,
			"unit_xp": 0,
			# Per troop_units schema CHECK: assignment_kind IN
			# ('garrison', 'on_campaign', 'available'). New applicants are
			# 'available' until the player formally hires them via the
			# Mercenary Market UI.
			"assignment_kind": "available",
			"hire_calendar_day": _calendar_day(),
		})

	# Create bard-applicant follower rows. Each gets a rolled level 1-3 (1d3).
	# Stats default; player can re-roll on promotion to henchman. Per Q25
	# [RESOLVED 2026-05-11] these are FOLLOWERS, not characters — they gain
	# XP and treasure shares only when adventuring with the bard.
	var bard_followers: Array = []
	for i in range(bard_count):
		var lvl_roll: RollResult = DiceSystem.roll_digital(3, 1, 0, "solicit_followers_bard_level")
		var bard_level: int = max(1, lvl_roll.modified_total)
		var follower_id := CampaignRepository.create_follower({
			"campaign_id": String(character.get("campaign_id", "")),
			"owner_character_id": character_id,
			"source_kind": "bardic_recruit",
			"intended_class": "",
			"name": "Bard Applicant %d" % (i + 1),
			"race": "human",
			"character_class": "bard",
			"combat_progression": "thief",
			"level": bard_level,
			"alignment": String(character.get("alignment", "neutral")),
			# Default stats; the player can re-roll on henchman promotion.
			"strength": 10, "intelligence": 11, "wisdom": 10,
			"dexterity": 12, "constitution": 10, "charisma": 13,
			# Rough HP placeholder; rerolled if/when promoted to henchman.
			"hp_max": 6 + bard_level * 2,
			"hp_current": 6 + bard_level * 2,
			"status": "present",
			"joined_calendar_day": _calendar_day(),
		})
		if not follower_id.is_empty():
			bard_followers.append(follower_id)
			EventBus.follower_joined.emit(follower_id, character_id, "bardic_recruit")

	EventBus.bard_followers_solicited.emit(character_id, merc_count, bard_count)

	# Ledger entry on domain (if any).
	if not domain_id.is_empty():
		CampaignRepository.add_ledger_entry({
			"domain_id": domain_id,
			"calendar_day": _calendar_day(),
			"category": "other",
			"subcategory": "bardic_recruitment",
			"gp_amount": 0,
			"description": "Solicit Followers: %d 0-level mercenaries + %d 1st-3rd-level bard applicants" % [
				merc_count, bard_count,
			],
		})

	return {
		"summary": "Bardic recruitment: %d mercenaries + %d bard applicants arrived" % [
			merc_count, bard_count,
		],
		"presentation": {
			"type": "toast",
			"text": "Recruitment: +%d mercs, +%d bards" % [merc_count, bard_count],
		},
	}


static func _get_character(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM characters WHERE id = ? LIMIT 1", [character_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _resolve_domain_for_ruler(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? LIMIT 1",
		[character_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
