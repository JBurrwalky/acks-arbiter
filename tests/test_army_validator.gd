extends "res://tests/test_suite_base.gd"

## Tests for ArmyValidator (Phase 6A).
##
## Covers the six validation rules per gdd-army-warfare.md §2.2:
##   1. Exactly one army_leader with no parent.
##   2. division_commanders' parent is the army_leader.
##   3. lieutenants' parent is a division_commander.
##   4. division_commander count ≤ leader's Leadership Ability.
##   5. Per-division unit count ≤ commander's Leadership Ability.
##   6. Officer level/HD must satisfy unit_scale qualification.


func run_all_tests() -> void:
	test_no_leader_is_error()
	test_leader_with_parent_is_error()
	test_command_character_mismatch_is_error()
	test_dc_overflow_is_warning()
	test_lt_with_non_dc_parent_is_warning()
	test_division_unit_overflow_is_warning()
	test_underqualified_dc_is_warning()
	test_qualification_passes_at_threshold()
	test_unknown_unit_scale_is_error()
	if not has_failures():
		print("ArmyValidator: all tests passed.")


func _make_officer(id: String, rank: String, parent: String, la: int = 4, character_id: String = "") -> Dictionary:
	return {
		"id": id,
		"army_id": "A1",
		"character_id": character_id if not character_id.is_empty() else id,
		"rank": rank,
		"parent_officer_id": parent,
		"leadership_ability": la,
		"strategic_ability": 0,
		"morale_modifier": 0,
		"derivation_source": "pc",
		"removed_calendar_day": 0,
	}


func _make_assignment(parent_oid: String) -> Dictionary:
	return {
		"id": "AS_" + parent_oid + "_" + str(randi()),
		"army_id": "A1",
		"troop_unit_id": CampaignRepository.generate_id(),
		"parent_officer_id": parent_oid,
		"role": "line",
		"released_calendar_day": 0,
	}


func _base_army(unit_scale: String = "platoon", command_id: String = "L1") -> Dictionary:
	return {
		"id": "A1",
		"unit_scale": unit_scale,
		"command_character_id": command_id,
	}


func test_no_leader_is_error() -> void:
	var result := ArmyValidator.validate_hierarchy(_base_army(), [], [])
	check(not result.get("valid", true), "no leader → invalid")
	var has_msg := false
	for e in result.get("errors", []):
		if String(e).contains("army_leader"):
			has_msg = true
			break
	check(has_msg, "errors mention army_leader")


func test_leader_with_parent_is_error() -> void:
	var officers := [_make_officer("L1", "army_leader", "X")]
	var result := ArmyValidator.validate_hierarchy(_base_army(), officers, [])
	check(not result.get("valid", true), "leader with parent → invalid")


func test_command_character_mismatch_is_error() -> void:
	var officers := [_make_officer("L1", "army_leader", "", 4, "actual_leader")]
	var army := _base_army("platoon", "different_character")
	var result := ArmyValidator.validate_hierarchy(army, officers, [])
	check(not result.get("valid", true), "command_character_id mismatch → invalid")


func test_dc_overflow_is_warning() -> void:
	# Leader LA = 2 → only 2 DCs allowed; we add 4.
	var officers := [_make_officer("L1", "army_leader", "", 2, "L1")]
	for i in range(4):
		officers.append(_make_officer("DC%d" % i, "division_commander", "L1", 4, "DC%d" % i))
	var result := ArmyValidator.validate_hierarchy(_base_army("platoon", "L1"), officers, [])
	check(result.get("valid", true), "DC overflow is a warning, not error")
	var found := false
	for w in result.get("warnings", []):
		if String(w).contains("exceeds army_leader"):
			found = true
			break
	check(found, "warnings mention DC overflow")


func test_lt_with_non_dc_parent_is_warning() -> void:
	var officers := [
		_make_officer("L1", "army_leader", "", 4, "L1"),
		_make_officer("DC1", "division_commander", "L1", 4, "DC1"),
		# LT pointing at the leader (wrong) instead of a DC.
		_make_officer("LT1", "lieutenant", "L1", 4, "LT1"),
	]
	var result := ArmyValidator.validate_hierarchy(_base_army("platoon", "L1"), officers, [])
	check(result.get("valid", true), "lt-parent issue is warning")
	var found := false
	for w in result.get("warnings", []):
		if String(w).contains("not a division_commander"):
			found = true
			break
	check(found, "warnings mention lieutenant parent issue")


func test_division_unit_overflow_is_warning() -> void:
	var officers := [
		_make_officer("L1", "army_leader", "", 4, "L1"),
		_make_officer("DC1", "division_commander", "L1", 2, "DC1"),  # LA=2 only
	]
	# Three units assigned directly to DC1 (exceeds LA=2).
	var assignments := [
		_make_assignment("DC1"),
		_make_assignment("DC1"),
		_make_assignment("DC1"),
	]
	var result := ArmyValidator.validate_hierarchy(_base_army("platoon", "L1"), officers, assignments)
	var found := false
	for w in result.get("warnings", []):
		if String(w).contains("overwhelmed"):
			found = true
			break
	check(found, "warnings mention overwhelmed division")


func test_underqualified_dc_is_warning() -> void:
	# Battalion scale needs DC at level 9; we'll create one at level 5.
	# We need a real character row to test qualification (validator queries DB).
	var campaign_id: String = CampaignRepository.create_campaign("ValQual Test", "World")
	var leader_id: String = CampaignRepository.generate_id()
	var dc_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Big Boss', 'pc', 'full', 'human', 'fighter', 12,
			14, 12, 12, 12, 12, 14, 80, 80)
	""", [leader_id, campaign_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Junior', 'pc', 'full', 'human', 'fighter', 5,
			14, 12, 12, 12, 12, 14, 30, 30)
	""", [dc_id, campaign_id])
	var officers := [
		_make_officer("L1", "army_leader", "", 4, leader_id),
		_make_officer("DC1", "division_commander", "L1", 4, dc_id),
	]
	var army := {"id": "A1", "unit_scale": "battalion", "command_character_id": leader_id}
	var result := ArmyValidator.validate_hierarchy(army, officers, [])
	var found := false
	for w in result.get("warnings", []):
		if String(w).contains("level 5") or String(w).contains("needs 9"):
			found = true
			break
	check(found, "warnings mention level qualification gap")


func test_qualification_passes_at_threshold() -> void:
	var campaign_id: String = CampaignRepository.create_campaign("ValQual Pass Test", "World")
	var leader_id: String = CampaignRepository.generate_id()
	var dc_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Boss', 'pc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 14, 60, 60)
	""", [leader_id, campaign_id])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'CompanyDC', 'pc', 'full', 'human', 'fighter', 7,
			14, 12, 12, 12, 12, 14, 45, 45)
	""", [dc_id, campaign_id])
	var officers := [
		_make_officer("L1", "army_leader", "", 4, leader_id),
		_make_officer("DC1", "division_commander", "L1", 4, dc_id),
	]
	var army := {"id": "A1", "unit_scale": "company", "command_character_id": leader_id}
	var result := ArmyValidator.validate_hierarchy(army, officers, [])
	# No level-related warning at threshold (company DC needs level 7; we have 7).
	for w in result.get("warnings", []):
		if String(w).contains("needs 7"):
			check(false, "should not warn at exactly threshold")


func test_unknown_unit_scale_is_error() -> void:
	var officers := [_make_officer("L1", "army_leader", "", 4, "L1")]
	var army := {"id": "A1", "unit_scale": "horde", "command_character_id": "L1"}
	var result := ArmyValidator.validate_hierarchy(army, officers, [])
	check(not result.get("valid", true), "unknown scale → invalid")
