extends "res://tests/test_suite_base.gd"

## Focused UI tests for the character-sheet Proficiencies tab.

var _class_registry := ClassRegistry.new()
var _spec_registry := SpecializationRegistry.new()
var _prof_registry := ProficiencyRegistry.new(_spec_registry)
var _power_registry := PowerRegistry.new()
var _generator := CharacterGenerator.new(_class_registry, _power_registry, _prof_registry)


func run_all_tests() -> void:
	test_skill_panels_exist_and_render_expected_rows()
	test_thief_panel_rows_show_na_for_unavailable_fighter_skills()
	test_adventuring_panel_rows_render_numeric_targets()
	test_skill_tooltips_show_breakdown()
	if not has_failures():
		print("CSTabProficiencies: all tests passed.")


func _make_bundle(class_id: String, level: int, strength: int = 10,
		proficiencies: Array = []) -> CharacterBundle:
	var character := CharacterData.new()
	character.character_class = class_id
	character.level = level
	character.strength = strength
	character.race = str(_class_registry.get_class_def(class_id).get("race", "human"))
	character.proficiencies = proficiencies.duplicate(true)

	var bundle := CharacterBundle.new()
	bundle.character = character
	bundle.proficiencies = proficiencies.duplicate(true)
	bundle.inventory = []
	bundle.powers = _generator.stamp_powers(character, class_id)
	return bundle


func _prof_row(key: String) -> Dictionary:
	return {
		"proficiency_key": key,
		"rank": 1,
		"slot_type": "general",
		"selections_count": 1,
		"specialization": "",
	}


func _make_registries() -> Dictionary:
	return {
		"class_registry": _class_registry,
		"proficiency_registry": _prof_registry,
		"power_registry": _power_registry,
	}


func test_skill_panels_exist_and_render_expected_rows() -> void:
	var tab := CSTabProficiencies.new()
	tab.display(_make_bundle("fighter", 1), _make_registries())

	var thief_panel := tab.find_child("ThiefSkillsPanel", true, false) as PanelContainer
	var adventuring_panel := tab.find_child("AdventuringSkillsPanel", true, false) as PanelContainer

	check(thief_panel != null, "CSTabProficiencies: thief skill panel should exist")
	check(adventuring_panel != null, "CSTabProficiencies: adventuring skill panel should exist")
	if thief_panel == null or adventuring_panel == null:
		return

	for skill_key in ThiefSkillResolver.THIEF_SKILL_ORDER:
		var row := thief_panel.find_child(skill_key, true, false) as HBoxContainer
		check(row != null, "CSTabProficiencies: expected thief row '%s' to exist" % skill_key)

	for skill_key in ThiefSkillResolver.ADVENTURING_SKILL_ORDER:
		var row := adventuring_panel.find_child(skill_key, true, false) as HBoxContainer
		check(row != null, "CSTabProficiencies: expected adventuring row '%s' to exist" % skill_key)

	check(thief_panel.find_child("hear_noise", true, false) == null,
		"CSTabProficiencies: hear noise should no longer appear in the thief panel")
	check(thief_panel.find_child("find_traps", true, false) == null,
		"CSTabProficiencies: find traps should no longer appear in the thief panel")


func test_thief_panel_rows_show_na_for_unavailable_fighter_skills() -> void:
	var tab := CSTabProficiencies.new()
	tab.display(_make_bundle("fighter", 1), _make_registries())

	var thief_panel := tab.find_child("ThiefSkillsPanel", true, false) as PanelContainer
	check(thief_panel != null, "CSTabProficiencies: thief panel should exist")
	if thief_panel == null:
		return

	for skill_key in ThiefSkillResolver.THIEF_SKILL_ORDER:
		var row := thief_panel.find_child(skill_key, true, false) as HBoxContainer
		check(row != null, "CSTabProficiencies: expected thief row '%s' to exist" % skill_key)
		if row == null:
			continue
		var value_lbl := row.find_child("Value", true, false) as Label
		check(value_lbl != null, "CSTabProficiencies: thief row '%s' should include a value label" % skill_key)
		if value_lbl != null:
			check(value_lbl.text == "NA",
				"CSTabProficiencies: unavailable fighter thief rows should display NA for '%s'" % skill_key)


func test_adventuring_panel_rows_render_numeric_targets() -> void:
	var tab := CSTabProficiencies.new()
	tab.display(_make_bundle("fighter", 1), _make_registries())

	var adventuring_panel := tab.find_child("AdventuringSkillsPanel", true, false) as PanelContainer
	check(adventuring_panel != null, "CSTabProficiencies: adventuring panel should exist")
	if adventuring_panel == null:
		return

	for skill_key in ThiefSkillResolver.ADVENTURING_SKILL_ORDER:
		var row := adventuring_panel.find_child(skill_key, true, false) as HBoxContainer
		check(row != null, "CSTabProficiencies: expected adventuring row '%s' to exist" % skill_key)
		if row == null:
			continue
		var value_lbl := row.find_child("Value", true, false) as Label
		check(value_lbl != null, "CSTabProficiencies: adventuring row '%s' should include a value label" % skill_key)
		if value_lbl != null:
			check(value_lbl.text != "NA",
				"CSTabProficiencies: adventuring rows should render a numeric target for '%s'" % skill_key)


func test_skill_tooltips_show_breakdown() -> void:
	var tab := CSTabProficiencies.new()
	tab.display(
		_make_bundle("fighter", 1, 13, [
			_prof_row("lockpicking"),
			_prof_row("trap_finding"),
			_prof_row("survival"),
			_prof_row("dungeon_bashing"),
		]),
		_make_registries()
	)

	var thief_panel := tab.find_child("ThiefSkillsPanel", true, false) as PanelContainer
	var adventuring_panel := tab.find_child("AdventuringSkillsPanel", true, false) as PanelContainer
	check(thief_panel != null and adventuring_panel != null,
		"CSTabProficiencies: both skill panels should exist for tooltip assertions")
	if thief_panel == null or adventuring_panel == null:
		return

	var open_locks_row := thief_panel.find_child("open_locks", true, false) as HBoxContainer
	var force_door_row := adventuring_panel.find_child("force_door", true, false) as HBoxContainer
	var foraging_row := adventuring_panel.find_child("foraging", true, false) as HBoxContainer

	check(open_locks_row != null, "CSTabProficiencies: open locks row should exist")
	check(force_door_row != null, "CSTabProficiencies: force door row should exist")
	check(foraging_row != null, "CSTabProficiencies: foraging row should exist")
	if open_locks_row == null or force_door_row == null or foraging_row == null:
		return

	var open_locks_value := open_locks_row.find_child("Value", true, false) as Label
	var force_door_value := force_door_row.find_child("Value", true, false) as Label
	var foraging_value := foraging_row.find_child("Value", true, false) as Label
	check(open_locks_value != null and force_door_value != null and foraging_value != null,
		"CSTabProficiencies: tooltip rows should expose value labels")
	if open_locks_value == null or force_door_value == null or foraging_value == null:
		return

	var open_locks_tooltip := str(open_locks_value.tooltip_text)
	var force_door_tooltip := str(force_door_value.tooltip_text)
	var foraging_tooltip := str(foraging_value.tooltip_text)

	check(open_locks_tooltip.contains("Source:"),
		"CSTabProficiencies: open locks tooltip should include the source line")
	check(open_locks_tooltip.contains("Proficiency modifier subtotal: +2"),
		"CSTabProficiencies: open locks tooltip should include the proficiency subtotal")
	check(force_door_tooltip.contains("Strength modifier: +4"),
		"CSTabProficiencies: force door tooltip should include the strength breakdown")
	check(foraging_tooltip.contains("automatic self-foraging"),
		"CSTabProficiencies: foraging tooltip should note Survival's automatic self-foraging")
