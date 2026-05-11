class_name ArmyValidator
extends RefCounted

## Hierarchy + commander qualification validator for Phase 6A armies.
##
## Per gdd-army-warfare.md §2.2 enforced validation rules:
##  1. Exactly one officer per army has rank='army_leader' AND parent_officer_id IS NULL.
##  2. Every division_commander's parent_officer_id references the army_leader.
##  3. Every lieutenant's parent_officer_id references a division_commander.
##  4. The number of division_commanders ≤ army_leader's Leadership Ability.
##  5. Per-division unit count ≤ commander's Leadership Ability OR overwhelmed flag set.
##  6. Officer level/HD must satisfy unit_scale qualification per
##     daw_armies_recruitment.xml §army_size_and_unit_scale L808-822:
##        platoon       commander 5th level / HD+2; lieutenant 3rd level / HD+1
##        company       commander 7th level / HD+4; lieutenant 5th level / HD+2
##        battalion     commander 9th level / HD+6; lieutenant 7th level / HD+4
##        brigade       commander 11th level / HD+8; lieutenant 9th level / HD+6
##
## Returns Dictionary {valid: bool, errors: Array[String], warnings: Array[String]}.
## Errors block army formation; warnings allow Confirm but display in amber banner
## per the formation dialog spec (gdd-army-warfare.md §3.1 Step 5).

const QUALIFICATION_BY_SCALE := {
	"platoon": {"commander_level": 5, "commander_hd": 2, "lieutenant_level": 3, "lieutenant_hd": 1},
	"company": {"commander_level": 7, "commander_hd": 4, "lieutenant_level": 5, "lieutenant_hd": 2},
	"battalion": {"commander_level": 9, "commander_hd": 6, "lieutenant_level": 7, "lieutenant_hd": 4},
	"brigade": {"commander_level": 11, "commander_hd": 8, "lieutenant_level": 9, "lieutenant_hd": 6},
}


static func validate_hierarchy(
	army: Dictionary,
	officers: Array,
	assignments: Array
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if army.is_empty():
		errors.append("Army record is empty.")
		return {"valid": false, "errors": errors, "warnings": warnings}

	var unit_scale: String = String(army.get("unit_scale", "platoon"))
	if not QUALIFICATION_BY_SCALE.has(unit_scale):
		errors.append("Unknown unit_scale '%s'." % unit_scale)
		return {"valid": false, "errors": errors, "warnings": warnings}

	# Index officers by id and collect by rank.
	var officer_by_id: Dictionary = {}
	var leaders: Array = []
	var division_commanders: Array = []
	var lieutenants: Array = []
	for officer in officers:
		if int(officer.get("removed_calendar_day", 0)) != 0:
			continue
		officer_by_id[String(officer.get("id", ""))] = officer
		match String(officer.get("rank", "")):
			"army_leader":
				leaders.append(officer)
			"division_commander":
				division_commanders.append(officer)
			"lieutenant":
				lieutenants.append(officer)

	# Rule 1 — exactly one army_leader with no parent.
	if leaders.is_empty():
		errors.append("No army_leader officer assigned.")
	elif leaders.size() > 1:
		errors.append("More than one army_leader officer (%d)." % leaders.size())
	else:
		var leader: Dictionary = leaders[0]
		if leader.get("parent_officer_id") != null and String(leader.get("parent_officer_id", "")) != "":
			errors.append("army_leader has a parent_officer_id; must be NULL.")
		# Cross-check: army.command_character_id must equal leader.character_id.
		var cmd: String = String(army.get("command_character_id", ""))
		var leader_char: String = String(leader.get("character_id", ""))
		if cmd != leader_char:
			errors.append(
				"command_character_id (%s) != army_leader.character_id (%s)." % [cmd, leader_char]
			)

	# Rule 2 — every division_commander's parent is the army_leader.
	if not leaders.is_empty():
		var leader_id: String = String(leaders[0].get("id", ""))
		for dc in division_commanders:
			var parent: String = String(dc.get("parent_officer_id", ""))
			if parent != leader_id:
				warnings.append(
					"division_commander %s reports to %s, expected army_leader %s." % [
						dc.get("character_id", "?"), parent, leader_id,
					]
				)

	# Rule 3 — every lieutenant's parent is a division_commander.
	var dc_id_set: Dictionary = {}
	for dc in division_commanders:
		dc_id_set[String(dc.get("id", ""))] = true
	for lt in lieutenants:
		var parent: String = String(lt.get("parent_officer_id", ""))
		if not dc_id_set.has(parent):
			warnings.append(
				"lieutenant %s reports to %s, which is not a division_commander." % [
					lt.get("character_id", "?"), parent,
				]
			)

	# Rule 4 — division_commander count ≤ leader's Leadership Ability.
	if not leaders.is_empty():
		var la: int = int(leaders[0].get("leadership_ability", 4))
		if division_commanders.size() > la:
			warnings.append(
				"%d division_commanders exceeds army_leader's Leadership Ability of %d (overwhelmed)." % [
					division_commanders.size(), la,
				]
			)

	# Rule 5 — per-division unit count ≤ commander's Leadership Ability.
	# Group active assignments by parent_officer_id (which is a lieutenant id when
	# present, or a division_commander id when no lieutenant). Then sum each
	# division by walking up to its division_commander.
	var assignments_per_parent: Dictionary = {}
	for assn in assignments:
		if int(assn.get("released_calendar_day", 0)) != 0:
			continue
		var parent_oid: String = String(assn.get("parent_officer_id", ""))
		assignments_per_parent[parent_oid] = int(assignments_per_parent.get(parent_oid, 0)) + 1

	var unit_count_per_division: Dictionary = {}
	for dc in division_commanders:
		var dc_id: String = String(dc.get("id", ""))
		unit_count_per_division[dc_id] = 0

	for parent_oid in assignments_per_parent:
		var unit_count: int = int(assignments_per_parent[parent_oid])
		var owner_officer: Dictionary = officer_by_id.get(parent_oid, {})
		if owner_officer.is_empty():
			# Direct assignment to an unknown officer; surface as warning.
			warnings.append("assignment(s) reporting to unknown officer %s." % parent_oid)
			continue
		match String(owner_officer.get("rank", "")):
			"division_commander":
				unit_count_per_division[parent_oid] = int(
					unit_count_per_division.get(parent_oid, 0)
				) + unit_count
			"lieutenant":
				var lt_parent_id: String = String(owner_officer.get("parent_officer_id", ""))
				if unit_count_per_division.has(lt_parent_id):
					unit_count_per_division[lt_parent_id] = int(
						unit_count_per_division[lt_parent_id]
					) + unit_count
			_:
				warnings.append(
					"assignment reports to officer of rank '%s' (expected lieutenant or division_commander)." % owner_officer.get("rank", "?")
				)

	for dc in division_commanders:
		var dc_id: String = String(dc.get("id", ""))
		var la: int = int(dc.get("leadership_ability", 4))
		var count: int = int(unit_count_per_division.get(dc_id, 0))
		if count > la:
			warnings.append(
				"division %s holds %d units, exceeds Leadership Ability %d (overwhelmed; BR halved)." % [
					dc_id, count, la,
				]
			)

	# Rule 6 — qualification by scale.
	var qual: Dictionary = QUALIFICATION_BY_SCALE[unit_scale]
	for dc in division_commanders:
		_check_qualification(
			dc, "division_commander",
			int(qual.get("commander_level", 0)),
			int(qual.get("commander_hd", 0)),
			warnings
		)
	for lt in lieutenants:
		_check_qualification(
			lt, "lieutenant",
			int(qual.get("lieutenant_level", 0)),
			int(qual.get("lieutenant_hd", 0)),
			warnings
		)

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	}


static func _check_qualification(
	officer: Dictionary, role: String,
	min_level: int, min_hd: int,
	warnings: Array[String]
) -> void:
	var derivation: String = String(officer.get("derivation_source", "pc"))
	var character_id: String = String(officer.get("character_id", ""))
	if character_id.is_empty():
		return
	if derivation == "monster":
		var hd: int = _get_character_hd(character_id)
		if hd < min_hd:
			warnings.append(
				"%s %s has HD %d (needs %d for this scale)." % [role, character_id, hd, min_hd]
			)
		return
	# pc / henchman / mercenary_officer / named_npc all use level.
	var level: int = _get_character_level(character_id)
	if level < min_level:
		warnings.append(
			"%s %s is level %d (needs %d for this scale)." % [role, character_id, level, min_level]
		)


static func _get_character_level(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings(
		"SELECT level FROM characters WHERE id = ?", [character_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("level", 0))


static func _get_character_hd(character_id: String) -> int:
	## Monsters store HD in the level column by convention. Phase 6A v1
	## treats character.level as HD when derivation_source = 'monster'.
	return _get_character_level(character_id)
