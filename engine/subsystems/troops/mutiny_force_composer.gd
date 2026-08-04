class_name MutinyForceComposer
extends RefCounted

## Turns a troop unit that departed on an ENMITY Unit Loyalty result into a real
## hostile army on the map.
##
## RAW: rules/daw_armies_recruitment.xml:103 — Enmity means "Troops immediately
## leave service; they may attack or stage a coup if the employer is vulnerable,
## or seek service with a strong enemy." Per Jedidiah (2026-08-03) the 2- band,
## and ONLY the 2- band, fields troops: Resignation (:104) and the two-Grudging
## departure (:105) leave without turning on anyone.
##
## Tribal warriors never come here — GDD §7.4 / Q-TW-8 (2026-05-22) ruled their
## brigand branch out of v1, and `UnitLoyaltyResolver._resolve_departure` keeps
## that exemption. Everyone else does.
##
## Why a fresh row instead of re-owning the departed one: the departure is the
## whole point of the loyalty pipeline — `status='departed'` is what relieves
## the standing levy penalty (conventions §133), stops the wage bill, and leaves
## an auditable history row. Transferring ownership in place would undo all
## three. The new row is a copy of the soldiers, not of their employment.
##
## Unlike `ThreatForceComposer.field_bandit_force`, the mutineers KEEP their own
## troop_type, race, tier, morale and veterancy. RAW :103 describes soldiers
## turning on an employer, not a company degenerating into rabble — a heavy
## cavalry company that mutinies is still heavy cavalry. What they lose is the
## payroll: mutineers live by pillage, so every cp column is zeroed, exactly as
## a threat army carries no wage bill.
##
## Public API:
##   field_mutineers(unit: Dictionary, calendar_day: int) -> String  # army id

## `troop_units.source_type` for the new row. 'mercenary' is the closest
## CHECK-valid category for freebooters, matching ThreatForceComposer's choice —
## the mutiny semantics live on the army name and `equipment_kit`, not here.
## It also matters mechanically: leaving the row as 'militia' would keep the
## domain paying the RAW :429-431 levy penalty for troops that just turned on
## it (`LevyPenaltyCalculator` sums active militia rows).
const MUTINEER_SOURCE_TYPE := "mercenary"


## Field the survivors of [param unit] as a hostile army. [param unit] is the
## troop_units row as it stood BEFORE the departure was written, so `count` is
## the surviving strength.
##
## Returns the new `armies.id`, or "" when nothing was fielded (no survivors, no
## campaign, or the captain / army row could not be created).
static func field_mutineers(unit: Dictionary, calendar_day: int) -> String:
	var survivors: int = int(unit.get("count", 0))
	if survivors <= 0:
		return ""
	var campaign_id: String = StringUtils.s(unit.get("campaign_id"))
	if campaign_id.is_empty():
		return ""

	var troop_type: String = StringUtils.s(unit.get("troop_type"), "soldiers")
	var captain_id: String = _create_mutiny_captain(campaign_id, survivors, troop_type)
	if captain_id.is_empty():
		return ""

	# Mutineers appear where they were serving. A unit with no surviving
	# stronghold (or one never assigned to a domain) still forms an army — it
	# just has no map position yet, the same nullable-location case
	# BanditSpawner already handles.
	var domain_id: String = StringUtils.s(unit.get("assigned_domain_id"))
	var where: Dictionary = StrongholdRepository.location_for_domain(domain_id)

	var army_id: String = ArmyRepository.create_army({
		"campaign_id": campaign_id,
		"name": "Mutineers (%d %s)" % [survivors, troop_type],
		"political_owner_id": captain_id,
		"command_character_id": captain_id,
		"state": "encamped",
		"map_id": where.get("map_id"),
		"hex_q": where.get("hex_q"),
		"hex_r": where.get("hex_r"),
		"formed_calendar_day": calendar_day,
		"unit_scale": "platoon",
		"strategic_stance": "offensive",
	})
	if army_id.is_empty():
		return ""

	var officer_id: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": captain_id, "rank": "army_leader",
		"leadership_ability": 3, "strategic_ability": 0, "morale_modifier": 0,
		"derivation_source": "named_npc", "appointed_calendar_day": calendar_day,
	})
	if officer_id.is_empty():
		return ""

	var mutineer_id: String = TroopUnitRepository.create_unit({
		"campaign_id": campaign_id,
		"owner_character_id": captain_id,
		# Deliberately NOT assigned to the domain they turned on: the levy
		# penalty, the wage bill and the garrison count all key off
		# assigned_domain_id, and these soldiers are no longer any of those.
		"assigned_domain_id": null,
		"assigned_stronghold_id": null,
		"source_type": MUTINEER_SOURCE_TYPE,
		"troop_type": troop_type,
		"race": StringUtils.s(unit.get("race"), "human"),
		"tier": StringUtils.s(unit.get("tier"), "average"),
		"starting_count": survivors,
		"count": survivors,
		"battle_rating": _battle_rating_for_survivors(unit, survivors),
		# Freebooters: no wages, no supply line, no specialists.
		"monthly_wage_cp": 0, "monthly_supply_cp": 0,
		"monthly_specialist_cp": 0, "monthly_cost_cp": 0,
		"morale": int(unit.get("morale", 0)),
		"is_veteran": int(unit.get("is_veteran", 0)) == 1,
		"is_trained": int(unit.get("is_trained", 1)) == 1,
		"unit_xp": 0,
		"assignment_kind": "on_campaign",
		"hire_calendar_day": calendar_day,
		"equipment_kit": "mutineers — %s, arms carried out of service" % troop_type,
		"save_vs_death": int(unit.get("save_vs_death", 0)),
	})
	if mutineer_id.is_empty():
		return army_id
	ArmyRepository.create_assignment({
		"army_id": army_id, "troop_unit_id": mutineer_id,
		"parent_officer_id": officer_id, "role": "line",
		"assigned_calendar_day": calendar_day,
	})
	return army_id


## The unit's stored `battle_rating` is for its `starting_count`; casualties
## reduce `count` without rescaling it (ArmyCasualtyResolver tracks in-battle
## strength on `battle_unit_states.br_current` instead). Prorate so a company
## that mutinies at half strength fields half the BR rather than its full
## roster's worth.
static func _battle_rating_for_survivors(unit: Dictionary, survivors: int) -> float:
	var br: float = float(unit.get("battle_rating", 0.0))
	var starting: int = int(unit.get("starting_count", 0))
	if starting <= 0 or survivors >= starting:
		return br
	return br * float(survivors) / float(starting)


## One-shot NPC to own the army — `armies.political_owner_id` is NOT NULL. Same
## shape as `BanditSpawner._create_bandit_captain`: persistence_tier 'named' so
## the captain survives for log/audit after the mutineers are destroyed, and
## level scaled loosely to the band size for flavour only (combat resolution
## uses the army's troop_units BR).
static func _create_mutiny_captain(campaign_id: String, survivors: int,
		troop_type: String) -> String:
	var id: String = CampaignRepository.generate_id()
	var level: int = clampi(survivors / 30, 1, 6)
	var hp_max: int = maxi(8, level * 6)
	var name: String = "Mutineer Captain (%d %s)" % [survivors, troop_type]
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'named', 'human', 'fighter', ?,
			13, 10, 9, 13, 13, 11, ?, ?)
	""", [id, campaign_id, name, level, hp_max, hp_max]):
		push_error("MutinyForceComposer._create_mutiny_captain failed (campaign=%s)" % campaign_id)
		return ""
	return id
