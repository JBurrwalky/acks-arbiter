class_name ArmyComposer
extends RefCounted

## Forms an army from a selection of troop_units and an officer-assignment plan.
## Implements the Step 1-5 flow per gdd-army-warfare.md §3.1 + §3.3 RAW
## officer-derivation formulas per daw_armies_recruitment.xml §officer_characteristics
## L763-789.
##
## Public API:
##   compose(plan: Dictionary) -> Dictionary {success, army_id, errors, warnings}
##
## plan dictionary shape:
##   campaign_id              String
##   name                     String   — defaults to "<owner first name>'s First Host"
##   political_owner_id       String   — character_id
##   command_character_id     String   — character_id (typically equals owner)
##   garrison_stronghold_id   String   — assembly stronghold
##   unit_scale               String   — 'platoon' | 'company' | 'battalion' | 'brigade'
##   strategic_stance         String   — 'offensive' | 'defensive' | 'evasive'
##   formed_calendar_day      int
##   leader_derivation        String   — 'pc' | 'henchman' | 'mercenary_officer' | ...
##   leader_legendary         bool     — adds +1 to morale modifier
##   leader_overrides         Dictionary — optional explicit {leadership, strategic, morale} for monster/named_npc
##   division_commanders      Array[Dictionary] — each {character_id, derivation_source, legendary?, overrides?}
##   lieutenants              Array[Dictionary] — each {character_id, derivation_source, parent_character_id, ...}
##   units                    Array[Dictionary] — each {troop_unit_id, parent_character_id (lieutenant or division commander), role}
##
## On success the function inserts:
##   1× armies row (state='assembling')
##   1× army_officers row for army_leader
##   N× army_officers rows for division_commanders (parent = leader)
##   M× army_officers rows for lieutenants        (parent = a division_commander)
##   K× army_unit_assignments rows                (parent = lieutenant or division_commander)
##   1× army_supply_state row
## Then fires ArmyValidator.validate_hierarchy and surfaces errors/warnings.
## Errors leave the rows in place for inspection; the caller should call
## the disbander to roll them back, or fix the plan and retry. Warnings are
## advisory only (matching the gdd's "amber banner allows Confirm").

const MERCENARY_OFFICER_TABLE := {
	# Per daw_armies_recruitment.xml §mercenary_officer_characteristics L993-1006.
	# rank_label : {leadership, strategic, morale, monthly_wage_gp}
	"lieutenant": {"leadership": 4, "strategic": 1, "morale": 3, "wage": 400},
	"captain":    {"leadership": 4, "strategic": 2, "morale": 3, "wage": 1600},
	"colonel":    {"leadership": 5, "strategic": 2, "morale": 3, "wage": 7250},
	"general":    {"leadership": 5, "strategic": 3, "morale": 3, "wage": 32000},
}


static func compose(plan: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	var campaign_id: String = String(plan.get("campaign_id", ""))
	if campaign_id.is_empty():
		errors.append("plan.campaign_id is required.")
	var owner_id: String = String(plan.get("political_owner_id", ""))
	if owner_id.is_empty():
		errors.append("plan.political_owner_id is required.")
	var command_id: String = String(plan.get("command_character_id", owner_id))
	if command_id.is_empty():
		errors.append("plan.command_character_id is required.")
	var unit_scale: String = String(plan.get("unit_scale", "platoon"))
	if not ArmyValidator.QUALIFICATION_BY_SCALE.has(unit_scale):
		errors.append("plan.unit_scale '%s' is invalid." % unit_scale)
	var formed_day: int = int(plan.get("formed_calendar_day", 0))

	var units_plan: Array = plan.get("units", [])
	if units_plan.size() < 3:
		errors.append("Army formation requires ≥3 troop_units (RAW: daw_armies_recruitment.xml §divisions L737).")

	if not errors.is_empty():
		return {"success": false, "army_id": "", "errors": errors, "warnings": warnings}

	# Insert army row (assembling state).
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": campaign_id,
		"name": String(plan.get("name", "")) if not String(plan.get("name", "")).is_empty()
			else _default_army_name(owner_id),
		"political_owner_id": owner_id,
		"command_character_id": command_id,
		"state": "assembling",
		"map_id": plan.get("map_id", null),
		"hex_q": plan.get("hex_q", null),
		"hex_r": plan.get("hex_r", null),
		"garrison_stronghold_id": plan.get("garrison_stronghold_id", null),
		"formed_calendar_day": formed_day,
		"unit_scale": unit_scale,
		"strategic_stance": String(plan.get("strategic_stance", "defensive")),
		"rng_seed_stream": int(plan.get("rng_seed_stream", randi())),
	})
	if army_id.is_empty():
		errors.append("Failed to insert armies row.")
		return {"success": false, "army_id": "", "errors": errors, "warnings": warnings}

	# Create supply_state row (default zeros).
	if not ArmyRepository.create_supply_state({"army_id": army_id}):
		errors.append("Failed to insert army_supply_state row.")
		return {"success": false, "army_id": army_id, "errors": errors, "warnings": warnings}

	# Build the army_leader officer.
	var leader_derivation: String = String(plan.get("leader_derivation", "pc"))
	var leader_legendary: bool = bool(plan.get("leader_legendary", false))
	var leader_overrides: Dictionary = plan.get("leader_overrides", {})
	var leader_abilities: Dictionary = derive_abilities(
		command_id, leader_derivation, leader_legendary, leader_overrides
	)
	var leader_id: String = ArmyRepository.create_officer({
		"army_id": army_id,
		"character_id": command_id,
		"rank": "army_leader",
		"parent_officer_id": null,
		"leadership_ability": int(leader_abilities.get("leadership", 4)),
		"strategic_ability": int(leader_abilities.get("strategic", 0)),
		"morale_modifier": int(leader_abilities.get("morale", 0)),
		"derivation_source": leader_derivation,
		"monthly_wage_gp": int(leader_abilities.get("wage", 0)),
		"appointed_calendar_day": formed_day,
	})
	if leader_id.is_empty():
		errors.append("Failed to insert army_leader officer.")
		return {"success": false, "army_id": army_id, "errors": errors, "warnings": warnings}

	# Create division_commanders.
	var dc_id_by_character: Dictionary = {}
	for dc_plan in plan.get("division_commanders", []):
		var dc_char: String = String(dc_plan.get("character_id", ""))
		if dc_char.is_empty():
			warnings.append("division_commander entry missing character_id; skipped.")
			continue
		var dc_derivation: String = String(dc_plan.get("derivation_source", "henchman"))
		var dc_legendary: bool = bool(dc_plan.get("legendary", false))
		var dc_overrides: Dictionary = dc_plan.get("overrides", {})
		var dc_abilities: Dictionary = derive_abilities(
			dc_char, dc_derivation, dc_legendary, dc_overrides
		)
		var dc_id: String = ArmyRepository.create_officer({
			"army_id": army_id,
			"character_id": dc_char,
			"rank": "division_commander",
			"parent_officer_id": leader_id,
			"leadership_ability": int(dc_abilities.get("leadership", 4)),
			"strategic_ability": int(dc_abilities.get("strategic", 0)),
			"morale_modifier": int(dc_abilities.get("morale", 0)),
			"derivation_source": dc_derivation,
			"monthly_wage_gp": int(dc_abilities.get("wage", 0)),
			"appointed_calendar_day": formed_day,
		})
		if dc_id.is_empty():
			warnings.append("Failed to insert division_commander %s." % dc_char)
			continue
		dc_id_by_character[dc_char] = dc_id

	# Create lieutenants.
	var lt_id_by_character: Dictionary = {}
	for lt_plan in plan.get("lieutenants", []):
		var lt_char: String = String(lt_plan.get("character_id", ""))
		if lt_char.is_empty():
			warnings.append("lieutenant entry missing character_id; skipped.")
			continue
		var parent_char: String = String(lt_plan.get("parent_character_id", ""))
		var parent_oid: String = String(dc_id_by_character.get(parent_char, ""))
		if parent_oid.is_empty():
			warnings.append(
				"lieutenant %s parent_character_id %s is not a division_commander." % [
					lt_char, parent_char,
				]
			)
		var lt_derivation: String = String(lt_plan.get("derivation_source", "henchman"))
		var lt_legendary: bool = bool(lt_plan.get("legendary", false))
		var lt_overrides: Dictionary = lt_plan.get("overrides", {})
		var lt_abilities: Dictionary = derive_abilities(
			lt_char, lt_derivation, lt_legendary, lt_overrides
		)
		var lt_id: String = ArmyRepository.create_officer({
			"army_id": army_id,
			"character_id": lt_char,
			"rank": "lieutenant",
			"parent_officer_id": parent_oid,
			"leadership_ability": int(lt_abilities.get("leadership", 4)),
			"strategic_ability": int(lt_abilities.get("strategic", 0)),
			"morale_modifier": int(lt_abilities.get("morale", 0)),
			"derivation_source": lt_derivation,
			"monthly_wage_gp": int(lt_abilities.get("wage", 0)),
			"appointed_calendar_day": formed_day,
		})
		if lt_id.is_empty():
			warnings.append("Failed to insert lieutenant %s." % lt_char)
			continue
		lt_id_by_character[lt_char] = lt_id

	# Create unit assignments. parent_character_id may be a lieutenant OR a
	# division_commander; resolve to the matching officer id.
	for unit_plan in units_plan:
		var troop_unit_id: String = String(unit_plan.get("troop_unit_id", ""))
		if troop_unit_id.is_empty():
			warnings.append("unit entry missing troop_unit_id; skipped.")
			continue
		var parent_char: String = String(unit_plan.get("parent_character_id", ""))
		var parent_oid: String = ""
		if lt_id_by_character.has(parent_char):
			parent_oid = String(lt_id_by_character[parent_char])
		elif dc_id_by_character.has(parent_char):
			parent_oid = String(dc_id_by_character[parent_char])
		if parent_oid.is_empty():
			warnings.append(
				"unit %s parent_character_id %s could not be resolved to an officer." % [
					troop_unit_id, parent_char,
				]
			)
			continue
		var assn_id: String = ArmyRepository.create_assignment({
			"army_id": army_id,
			"troop_unit_id": troop_unit_id,
			"parent_officer_id": parent_oid,
			"role": String(unit_plan.get("role", "line")),
			"assigned_calendar_day": formed_day,
		})
		if assn_id.is_empty():
			warnings.append(
				"Failed to insert assignment for unit %s — likely already assigned to another army." % troop_unit_id
			)

	# Validate the resulting hierarchy.
	var officers: Array = ArmyRepository.list_officers_for_army(army_id)
	var assignments: Array = ArmyRepository.list_active_assignments_for_army(army_id)
	var army: Dictionary = ArmyRepository.get_army(army_id)
	var validation: Dictionary = ArmyValidator.validate_hierarchy(army, officers, assignments)
	for e in validation.get("errors", []):
		errors.append(String(e))
	for w in validation.get("warnings", []):
		warnings.append(String(w))

	return {
		"success": errors.is_empty(),
		"army_id": army_id,
		"errors": errors,
		"warnings": warnings,
	}


# ---------------------------------------------------------------------------
# Officer-derivation formulas per gdd-army-warfare.md §3.3 (RAW per
# daw_armies_recruitment.xml §officer_characteristics L763-789).
# ---------------------------------------------------------------------------

static func derive_abilities(
	character_id: String,
	derivation_source: String,
	legendary: bool,
	overrides: Dictionary
) -> Dictionary:
	## Returns Dictionary {leadership, strategic, morale, wage}.
	## wage is non-zero only for mercenary_officer (or named_npc derived as
	## mercenary). All others zero.
	if derivation_source == "mercenary_officer":
		var rank_label: String = String(overrides.get("rank_label", "lieutenant")).to_lower()
		var row: Dictionary = MERCENARY_OFFICER_TABLE.get(rank_label, MERCENARY_OFFICER_TABLE["lieutenant"])
		return {
			"leadership": int(row.get("leadership", 4)),
			"strategic": int(row.get("strategic", 0)),
			"morale": int(row.get("morale", 0)) + (1 if legendary else 0),
			"wage": int(row.get("wage", 0)),
		}

	if derivation_source == "monster":
		# Per RAW: Leadership = 3 + (HD/4 floor), cap 8.
		# Strategic = 0 + (HD/5 floor) with INT-tier modifier (sub-human/-1, generally-high/+1, super-human/+2).
		# Morale Modifier = 0 by default, or monster-entry-listed value.
		var hd: int = _get_character_level(character_id)
		var int_tier: int = int(overrides.get("int_tier_modifier", 0))
		var leadership: int = clampi(3 + int(floor(float(hd) / 4.0)), 1, 8)
		var strategic: int = clampi(0 + int(floor(float(hd) / 5.0)) + int_tier, -3, 6)
		var morale: int = int(overrides.get("morale_modifier", 0)) + (1 if legendary else 0)
		return {"leadership": leadership, "strategic": strategic, "morale": morale, "wage": 0}

	if derivation_source == "named_npc":
		# Generated via vagary; if generated as mercenary use mercenary table.
		# Otherwise fall through to PC/henchman formula below.
		if overrides.has("rank_label"):
			return derive_abilities(character_id, "mercenary_officer", legendary, overrides)
		# else: fall through (treat like henchman).

	# pc / henchman / fall-through named_npc — use the full RAW formula.
	var character: Dictionary = _get_character(character_id)
	if character.is_empty():
		# No character row — return minimal defaults.
		return {"leadership": 4, "strategic": 0, "morale": (1 if legendary else 0), "wage": 0}

	var cha_mod: int = CharacterData.ability_modifier(int(character.get("charisma", 10)))
	var int_mod: int = CharacterData.ability_modifier(int(character.get("intelligence", 10)))
	var wis_mod: int = CharacterData.ability_modifier(int(character.get("wisdom", 10)))
	var has_leadership_prof: bool = _has_proficiency(character_id, "leadership")
	var has_command_prof: bool = _has_proficiency(character_id, "command")
	var military_strategy_rank: int = _proficiency_rank(character_id, "military_strategy")

	# Leadership = 4 + Cha mod (+1 Leadership prof; max 8).
	var leadership: int = clampi(4 + cha_mod + (1 if has_leadership_prof else 0), 1, 8)

	# Strategic = max(0, max(int_mod, wis_mod)) + min(0, min(int_mod, wis_mod)) + military_strategy_rank.
	# Range −3 to +6.
	var best_int_wis: int = max(int_mod, wis_mod)
	var worst_int_wis: int = min(int_mod, wis_mod)
	var strategic: int = clampi(
		max(0, best_int_wis) + min(0, worst_int_wis) + military_strategy_rank,
		-3, 6
	)

	# Morale Modifier = Cha mod
	#                 + class bonus (Barb/Bard/Explorer/Fighter/Paladin 5+: +1)
	#                 + Command prof (+2)
	#                 + legendary-leader (+1).
	var character_class: String = String(character.get("character_class", "")).to_lower()
	var level: int = int(character.get("level", 1))
	var class_bonus: int = 0
	if level >= 5 and (
		character_class == "barbarian" or character_class == "bard"
		or character_class == "explorer" or character_class == "fighter"
		or character_class == "paladin"
	):
		class_bonus = 1
	var morale: int = (
		cha_mod + class_bonus
		+ (2 if has_command_prof else 0)
		+ (1 if legendary else 0)
	)

	return {"leadership": leadership, "strategic": strategic, "morale": morale, "wage": 0}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _default_army_name(owner_character_id: String) -> String:
	var character: Dictionary = _get_character(owner_character_id)
	var first: String = String(character.get("name", "")).split(" ")[0]
	if first.is_empty():
		first = "Unnamed"
	return "%s's First Host" % first


static func _get_character(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM characters WHERE id = ?", [character_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _get_character_level(character_id: String) -> int:
	var character: Dictionary = _get_character(character_id)
	return int(character.get("level", 0))


static func _has_proficiency(character_id: String, proficiency_key: String) -> bool:
	if character_id.is_empty() or proficiency_key.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM character_proficiencies
		WHERE character_id = ? AND lower(proficiency_key) = ?
		LIMIT 1
	""", [character_id, proficiency_key.to_lower()]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


static func _proficiency_rank(character_id: String, proficiency_key: String) -> int:
	if character_id.is_empty() or proficiency_key.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT rank FROM character_proficiencies
		WHERE character_id = ? AND lower(proficiency_key) = ?
		ORDER BY rank DESC
		LIMIT 1
	""", [character_id, proficiency_key.to_lower()]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("rank", 0))
