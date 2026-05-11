class_name BattleSetup
extends RefCounted

## Battle-preparation orchestrator per daw_axioms_pitching_battle.xml
## §battle_preparation L23-191. Runs:
##   1. Surprise check (each side rolls 1d6; surprised on 1-2)
##   2. Defender determination (surprised → defender; else first-arrived; else
##      smaller army)
##   3. BPC starting count via BpcTable
##   4. Terrain advantage via TerrainAdvantageResolver
##   5. Initial unit deployment to four zones (missile / skirmish / melee / reserve)
##
## Public API:
##   prepare(attacker_army_id, defender_army_id, terrain, weather, ...) -> Dictionary
##     Performs all five steps; returns a state dictionary that the
##     field_battle_resolver consumes to populate field_battles +
##     battle_unit_states rows.
##
## Zone eligibility per §battle_preparation.deploy_troops L156-191. v1 silent
## deployment heuristic (per gdd-army-warfare.md §6.1 + behavior tags):
##   - Missile-eligible units (bows, arbalests, crossbows) → missile zone.
##   - Skirmish-eligible (light inf with javelins/slings, light cav with javs) → skirmish.
##   - Anything else → melee zone.
##   - Baggage units → reserve.
##   - Reserve role assignment → reserve zone.
##
## Zone eligibility detection is by `troop_units.troop_type` substring match
## against a small RAW-derived vocabulary. Phase 6A's troop_units schema has
## `equipment_kit` but its values are not yet typed; v1 reads `troop_type` as
## the source of truth for eligibility.

const MISSILE_ELIGIBLE_TYPE_KEYWORDS := [
	"arbalest", "crossbow", "longbow", "shortbow", "bowmen", "bow",
	"composite", "spellcaster", "flyer",
]

const SKIRMISH_ELIGIBLE_TYPE_KEYWORDS := [
	"slinger", "skirmish", "javelin", "darts",
	# Light infantry/cavalry without specific markers — fall through.
]

const SKIRMISH_LIGHT_KEYWORDS := ["light_infantry", "light_inf", "light_cavalry", "light_cav"]


static func prepare(
	attacker_army_id: String,
	defender_army_id: String,
	terrain: String,
	weather: String,
	calendar_day: int,
	is_player_involved: bool,
	dice_roller: Callable = Callable()
) -> Dictionary:
	# 1. Surprise check.
	var attacker_surprise_roll: int = _roll(dice_roller, 1, 6)
	var defender_surprise_roll: int = _roll(dice_roller, 1, 6)
	var attacker_surprised: bool = attacker_surprise_roll <= 2
	var defender_surprised: bool = defender_surprise_roll <= 2

	# 2. Defender determination is implicit here — caller specifies which army
	#    is which. The collision detector / dispatcher decides who is "defender"
	#    based on strategic_stance + arrival order before invoking this module.
	#    We accept the caller's assignment as authoritative.

	# 3. BPC starting count.
	var bpc_result: Dictionary = BpcTable.roll_starting_bpc(terrain, weather, dice_roller)

	# 4. Terrain advantage.
	var attacker_strategic: int = _get_army_leader_strategic(attacker_army_id)
	var defender_strategic: int = _get_army_leader_strategic(defender_army_id)
	var advantage_result: Dictionary = TerrainAdvantageResolver.resolve(
		terrain, defender_strategic, attacker_strategic,
		defender_surprised, attacker_surprised, dice_roller
	)

	# 5. Build deployment for each side.
	var attacker_deployment: Array = build_deployment(attacker_army_id)
	var defender_deployment: Array = build_deployment(defender_army_id)

	return {
		"attacker_army_id": attacker_army_id,
		"defender_army_id": defender_army_id,
		"terrain": terrain,
		"weather": weather,
		"started_calendar_day": calendar_day,
		"is_player_involved": is_player_involved,

		"attacker_surprise_roll": attacker_surprise_roll,
		"defender_surprise_roll": defender_surprise_roll,
		"attacker_surprised": attacker_surprised,
		"defender_surprised": defender_surprised,

		"starting_bpc": int(bpc_result.get("bpc", 1)),
		"bpc_roll": int(bpc_result.get("roll", 1)),

		"attacker_terrain_advantage": String(advantage_result.get("attacker_advantage", "regular")),
		"defender_terrain_advantage": String(advantage_result.get("defender_advantage", "regular")),
		"attacker_strategic": attacker_strategic,
		"defender_strategic": defender_strategic,
		"attacker_terrain_score": int(advantage_result.get("attacker_score", 0)),
		"defender_terrain_score": int(advantage_result.get("defender_score", 0)),

		"attacker_deployment": attacker_deployment,
		"defender_deployment": defender_deployment,
	}


# ---------------------------------------------------------------------------
# Deployment
# ---------------------------------------------------------------------------

static func build_deployment(army_id: String) -> Array:
	## Returns Array of Dictionaries: {troop_unit_id, parent_officer_id, zone, br, role}.
	## v1 heuristic places each unit in the highest zone it qualifies for (RAW
	## says missile-eligible can go missile or anywhere lower; we put them at
	## missile for maximum range advantage). Reserve-role units go reserve;
	## baggage-role go reserve.
	var assignments: Array = ArmyRepository.list_active_assignments_for_army(army_id)
	var deployment: Array = []
	for assn in assignments:
		var unit_id: String = String(assn.get("troop_unit_id", ""))
		var role: String = String(assn.get("role", "line"))
		var unit: Dictionary = _get_troop_unit(unit_id)
		var br: float = float(unit.get("battle_rating", 0.0))
		var zone: String = _select_zone_for_unit(unit, role)
		deployment.append({
			"troop_unit_id": unit_id,
			"parent_officer_id": String(assn.get("parent_officer_id", "")),
			"zone": zone,
			"br": br,
			"role": role,
			"troop_type": String(unit.get("troop_type", "")),
		})
	return deployment


static func _select_zone_for_unit(unit: Dictionary, role: String) -> String:
	if role == "reserve" or role == "baggage":
		return "reserve"
	if role == "scout":
		# Scouts are typically light cav; missile-eligible if equipped with bows.
		if _is_missile_eligible(unit):
			return "missile"
		return "skirmish"
	if _is_missile_eligible(unit):
		return "missile"
	if _is_skirmish_eligible(unit):
		return "skirmish"
	return "melee"


static func _is_missile_eligible(unit: Dictionary) -> bool:
	var t: String = String(unit.get("troop_type", "")).to_lower()
	for kw in MISSILE_ELIGIBLE_TYPE_KEYWORDS:
		if t.contains(kw):
			return true
	# Equipment kit textual hint (Phase 5 stores free-text equipment_kit).
	var kit: String = String(unit.get("equipment_kit", "")).to_lower()
	for kw in MISSILE_ELIGIBLE_TYPE_KEYWORDS:
		if kit.contains(kw):
			return true
	return false


static func _is_skirmish_eligible(unit: Dictionary) -> bool:
	if _is_missile_eligible(unit):
		return true
	var t: String = String(unit.get("troop_type", "")).to_lower()
	for kw in SKIRMISH_ELIGIBLE_TYPE_KEYWORDS:
		if t.contains(kw):
			return true
	for kw in SKIRMISH_LIGHT_KEYWORDS:
		if t.contains(kw):
			return true
	return false


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _get_army_leader_strategic(army_id: String) -> int:
	var leader: Dictionary = ArmyRepository.get_army_leader(army_id)
	return int(leader.get("strategic_ability", 0))


static func _get_troop_unit(troop_unit_id: String) -> Dictionary:
	if troop_unit_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM troop_units WHERE id = ?", [troop_unit_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _roll(dice_roller: Callable, count: int, sides: int) -> int:
	if dice_roller.is_valid():
		return int(dice_roller.call(count, sides))
	var total: int = 0
	for i in range(count):
		total += randi_range(1, sides)
	return total
