extends "res://tests/test_suite_base.gd"

## Focused tests for class sex/alignment restriction enforcement in finalize.


func run_all_tests() -> void:
	test_paladin_only_offers_lawful_alignment()
	test_anti_paladin_only_offers_chaotic_alignment()
	test_warlock_offers_neutral_or_chaotic_and_forces_male()
	test_witch_chthonic_only_offers_chaotic_and_forces_female()
	test_bladedancer_forces_female()
	test_invalid_preloaded_state_is_corrected()
	if not has_failures():
		print("FinalizePanel: all tests passed.")


func test_paladin_only_offers_lawful_alignment() -> void:
	var panel := _make_panel(_make_state("paladin"))
	check(_alignment_values(panel) == ["lawful"],
		"paladin finalize step should only offer Lawful alignment")
	_cleanup_panel(panel)
	print("  paladin_only_offers_lawful_alignment: OK")


func test_anti_paladin_only_offers_chaotic_alignment() -> void:
	var panel := _make_panel(_make_state("anti_paladin"))
	check(_alignment_values(panel) == ["chaotic"],
		"anti-paladin finalize step should only offer Chaotic alignment")
	_cleanup_panel(panel)
	print("  anti_paladin_only_offers_chaotic_alignment: OK")


func test_warlock_offers_neutral_or_chaotic_and_forces_male() -> void:
	var panel := _make_panel(_make_state("warlock"))
	check(_alignment_values(panel) == ["neutral", "chaotic"],
		"warlock finalize step should only offer Neutral and Chaotic")
	check(panel._sex_male_btn.disabled == false,
		"warlock finalize step should leave the male option enabled")
	check(panel._sex_female_btn.disabled,
		"warlock finalize step should disable the female option")
	check(panel._state.get("sex", "") == "male",
		"warlock finalize step should coerce the selected sex to male")
	_cleanup_panel(panel)
	print("  warlock_offers_neutral_or_chaotic_and_forces_male: OK")


func test_witch_chthonic_only_offers_chaotic_and_forces_female() -> void:
	var state := _make_state("witch")
	state["witch_tradition"] = "chthonic"
	var panel := _make_panel(state)
	check(_alignment_values(panel) == ["chaotic"],
		"chthonic witches should only offer Chaotic alignment at finalize")
	check(panel._sex_male_btn.disabled,
		"witch finalize step should disable the male option")
	check(panel._sex_female_btn.disabled == false,
		"witch finalize step should leave the female option enabled")
	check(panel._state.get("sex", "") == "female",
		"witch finalize step should coerce the selected sex to female")
	check(panel._state.get("alignment", "") == "chaotic",
		"chthonic witch finalize step should coerce the selected alignment to chaotic")
	_cleanup_panel(panel)
	print("  witch_chthonic_only_offers_chaotic_and_forces_female: OK")


func test_bladedancer_forces_female() -> void:
	var panel := _make_panel(_make_state("bladedancer"))
	check(panel._sex_male_btn.disabled,
		"bladedancer finalize step should disable the male option")
	check(panel._sex_female_btn.disabled == false,
		"bladedancer finalize step should leave the female option enabled")
	check(panel._state.get("sex", "") == "female",
		"bladedancer finalize step should coerce the selected sex to female")
	_cleanup_panel(panel)
	print("  bladedancer_forces_female: OK")


func test_invalid_preloaded_state_is_corrected() -> void:
	var state := _make_state("warlock")
	state["sex"] = "female"
	state["alignment"] = "lawful"
	var panel := _make_panel(state)
	check(panel._state.get("sex", "") == "male",
		"invalid preloaded warlock sex should be corrected to male on restore")
	check(panel._state.get("alignment", "") == "neutral",
		"invalid preloaded warlock alignment should be corrected to the first allowed option")
	check(panel._alignment_option.get_item_metadata(panel._alignment_option.selected) == "neutral",
		"finalize alignment dropdown should stay synced after correcting preloaded state")
	_cleanup_panel(panel)
	print("  invalid_preloaded_state_is_corrected: OK")


func _make_panel(state: Dictionary) -> FinalizePanel:
	var panel := FinalizePanel.new()
	add_child(panel)
	panel.setup(state, ClassRegistry.new())
	return panel


func _cleanup_panel(panel: FinalizePanel) -> void:
	if is_instance_valid(panel):
		remove_child(panel)
		panel.queue_free()


func _make_state(class_id: String) -> Dictionary:
	var character := CharacterData.new()
	character.name = "Restriction Test"
	character.character_class = class_id
	character.race = "human"
	character.level = 1
	character.title = "Venturer"
	character.sex = "male"
	character.alignment = "neutral"
	character.hp_current = 4
	character.hp_max = 4
	character.languages = "[]"
	return {
		"class_id": class_id,
		"name": character.name,
		"sex": "male",
		"alignment": "neutral",
		"description": "",
		"portrait_id": "",
		"character": character,
	}


func _alignment_values(panel: FinalizePanel) -> Array[String]:
	var values: Array[String] = []
	for i in range(panel._alignment_option.item_count):
		values.append(panel._alignment_option.get_item_metadata(i))
	return values
