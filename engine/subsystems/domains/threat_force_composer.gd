class_name ThreatForceComposer
extends RefCounted

## Fields a REAL body of troops onto a threat army (a bandit swarm or an emerged challenger) so it
## has genuine BR. Closes the Phase-9B stub where BanditSpawner.materialize_swarm_as_army and
## NPCChallengerEmergence.materialize_challenger_as_army created a unit-less army shell (BR 0) —
## which made the §7.3 resistance decision always trivially "accept" (attacker_br=0 → threshold
## 0) and left the resulting siege/battle with a phantom, strengthless aggressor.
##
## Bandits/brigands are irregular freebooters: source_type='mercenary' (the closest CHECK-valid
## troop_units category; the "Brigands" semantics live on troop_type), tier 'average', and
## self-funding (no wages — they live by pillage, so a threat army carries no payroll). Their
## casualties flow through the standard pipeline (ArmyCasualtyResolver decrements count / marks
## departed) exactly like any other unit.
##
## Force size is RAW-anchored (acore_axioms_strongholds_and_domains.xml §effects_of_morale
## L557/568/576 — bandit strength scales with domain morale):
##   - a bandit swarm fields its threat.bandit_count (already set at spawn from that rule);
##   - an emerged challenger LEADS the domain's bandits (RAW L627-630: it "emerges from the
##     bandits"; RAW gives NO retinue-size formula, and Jedidiah 2026-07-04 chose "leads the
##     domain's bandits"), so it fields the same morale-scaled band via bandit_force_for_domain.
##
## Public API:
##   field_bandit_force(army_id, campaign_id, owner_id, troop_count, calendar_day) -> Array
##   bandit_force_for_domain(domain_id) -> int

const UNIT_SIZE := 120                    # chunk cap, matching the conscript / militia pipeline
const BRIGAND_BR_PER_SOLDIER := 0.008     # PROJECT (tunable): brigands ≈ irregular light infantry
const BRIGAND_MORALE := -1                # freebooters — shaky loyalty


## Field `troop_count` brigands onto `army_id`, owned by `owner_id`. Creates the army's leader
## officer (army_unit_assignments.parent_officer_id is NOT NULL) + chunked troop_units (≤120 each)
## and assigns them. Returns the created unit ids; [] for troop_count ≤ 0 or on officer failure.
static func field_bandit_force(army_id: String, campaign_id: String, owner_id: String,
		troop_count: int, calendar_day: int) -> Array:
	if army_id.is_empty() or troop_count <= 0:
		return []
	var officer_id: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": owner_id, "rank": "army_leader",
		"leadership_ability": 3, "strategic_ability": 0, "morale_modifier": 0,
		"derivation_source": "named_npc", "appointed_calendar_day": calendar_day,
	})
	if officer_id.is_empty():
		return []
	var ids: Array = []
	var remaining: int = troop_count
	while remaining > 0:
		var unit_count: int = mini(remaining, UNIT_SIZE)
		var uid: String = TroopUnitRepository.create_unit({
			"campaign_id": campaign_id, "owner_character_id": owner_id,
			"source_type": "mercenary", "troop_type": "Brigands", "race": "human", "tier": "average",
			"starting_count": unit_count, "count": unit_count,
			"battle_rating": BRIGAND_BR_PER_SOLDIER * float(unit_count),
			"monthly_wage_cp": 0, "monthly_supply_cp": 0, "monthly_specialist_cp": 0,
			"monthly_cost_cp": 0, "morale": BRIGAND_MORALE, "is_veteran": false, "is_trained": true,
			"unit_xp": 0, "assignment_kind": "on_campaign", "hire_calendar_day": calendar_day,
			"equipment_kit": "brigand arms — irregular light infantry",
		})
		if not uid.is_empty():
			ArmyRepository.create_assignment({
				"army_id": army_id, "troop_unit_id": uid, "parent_officer_id": officer_id,
				"role": "line", "assigned_calendar_day": calendar_day,
			})
			ids.append(uid)
		remaining -= unit_count
	return ids


## The size of the bandit band a challenger leads. Prefers the domain's active bandit_swarm count
## (already RAW-derived at spawn); else computes from the domain's morale tier per RAW
## §effects_of_morale (Rebellious ≤-4: 1/family; Defiant -3: 1/2; Turbulent -2: 1/5), with a
## small floor so a fielded challenger is never empty.
static func bandit_force_for_domain(domain_id: String) -> int:
	if domain_id.is_empty():
		return 0
	var swarm: Dictionary = DomainThreatRepository.get_active_bandit_swarm_for_domain(domain_id)
	if not swarm.is_empty():
		var bc: int = int(swarm.get("bandit_count", 0))
		if bc > 0:
			return bc
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	var morale: int = int(domain.get("morale", 0))
	var families: int = int(domain.get("peasant_families", 0))
	if morale <= -4:
		return maxi(1, families)
	if morale == -3:
		return maxi(1, families / 2)
	if morale <= -2:
		return maxi(1, families / 5)
	return maxi(1, families / 10)
