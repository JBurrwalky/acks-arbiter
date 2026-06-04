extends "res://tests/test_suite_base.gd"

## Tests for TemplateIntAdjuster — the §8 INT adjustment pipeline
## (gdd-class-templates.md §10 step 7).


func run_all_tests() -> void:
	test_is_arcane_class()
	test_mundane_extra_generals()
	test_arcane_low_int_culls()
	test_arcane_baseline()
	test_arcane_high_int_extras()
	test_cull_default_arcane_bonus()
	test_cull_override_general()
	test_adjust_spells()
	test_pick_extra_generals()
	if not has_failures():
		print("TemplateIntAdjuster: all tests passed.")


func test_is_arcane_class() -> void:
	for cid in ["mage", "warlock", "elven_enchanter", "elven_spellsword",
			"lightblessed_wonderworker"]:
		check(TemplateIntAdjuster.is_arcane_class(cid), "%s should be arcane" % cid)
	# witch / priestess cast spells but are NOT §8.2 arcane templates (no baked-in
	# INT-13-15 bonus); they take the mundane INT path.
	for cid in ["fighter", "cleric", "thief", "bard", "witch", "priestess",
			"darkblood_ruinguard"]:
		check(not TemplateIntAdjuster.is_arcane_class(cid), "%s should be mundane" % cid)


func test_mundane_extra_generals() -> void:
	# max(0, ACKS INT modifier) — the §8.1 explicit TABLE, not the (incorrect)
	# floor((INT-11)/2) formula (which would wrongly give 2 at 15 and 3 at 17).
	var expected := {8: 0, 12: 0, 13: 1, 14: 1, 15: 1, 16: 2, 17: 2, 18: 3}
	for int_score in expected:
		var plan := TemplateIntAdjuster.compute_adjustment("fighter", int_score)
		check(int(plan["extra_general_proficiencies"]) == expected[int_score],
			"fighter INT %d -> %d extra generals, got %d" % [int_score,
				expected[int_score], int(plan["extra_general_proficiencies"])])
		check(not bool(plan["cull_arcane_bonus"]), "mundane never culls")
		check(int(plan["extra_spells_to_roll"]) == 0, "mundane rolls no spells")


func test_arcane_low_int_culls() -> void:
	for int_score in [8, 12]:
		var plan := TemplateIntAdjuster.compute_adjustment("mage", int_score)
		check(bool(plan["cull_arcane_bonus"]), "mage INT %d culls arcane bonus" % int_score)
		check(bool(plan["drop_bonus_spell"]), "mage INT %d drops bonus spell" % int_score)
		check(int(plan["extra_general_proficiencies"]) == 0, "mage INT %d no extra generals" % int_score)
		check(int(plan["extra_spells_to_roll"]) == 0, "mage INT %d no extra spells" % int_score)


func test_arcane_baseline() -> void:
	for int_score in [13, 14, 15]:
		var plan := TemplateIntAdjuster.compute_adjustment("mage", int_score)
		check(not bool(plan["cull_arcane_bonus"]), "mage INT %d as-written" % int_score)
		check(not bool(plan["drop_bonus_spell"]), "mage INT %d keeps bonus spell" % int_score)
		check(int(plan["extra_general_proficiencies"]) == 0, "mage INT %d no extras" % int_score)
		check(int(plan["extra_spells_to_roll"]) == 0, "mage INT %d no extra spells" % int_score)


func test_arcane_high_int_extras() -> void:
	for int_score in [16, 17]:
		var plan := TemplateIntAdjuster.compute_adjustment("warlock", int_score)
		check(int(plan["extra_general_proficiencies"]) == 1, "INT %d -> +1 general" % int_score)
		check(int(plan["extra_spells_to_roll"]) == 1, "INT %d -> +1 spell" % int_score)
		check(not bool(plan["cull_arcane_bonus"]), "INT %d no cull" % int_score)
	var p18 := TemplateIntAdjuster.compute_adjustment("mage", 18)
	check(int(p18["extra_general_proficiencies"]) == 2, "mage INT 18 -> +2 generals")
	check(int(p18["extra_spells_to_roll"]) == 2, "mage INT 18 -> +2 spells")


func test_cull_default_arcane_bonus() -> void:
	var profs := [_mk("battle_magic", "class"), _mk("military_strategy", "general"),
		_mk("siege_engineering", "arcane_bonus")]
	var kept := TemplateIntAdjuster.cull_proficiencies(profs, {"cull_arcane_bonus": true})
	check(kept.size() == 2, "cull drops one prof")
	check(_has_key(kept, "battle_magic") and _has_key(kept, "military_strategy"), "class + general kept")
	check(not _has_key(kept, "siege_engineering"), "arcane_bonus culled by default")
	# no cull when the plan does not request one
	var nocull := TemplateIntAdjuster.cull_proficiencies(profs, {"cull_arcane_bonus": false})
	check(nocull.size() == 3, "no cull keeps all three")


func test_cull_override_general() -> void:
	var profs := [_mk("battle_magic", "class"), _mk("military_strategy", "general"),
		_mk("siege_engineering", "arcane_bonus")]
	var plan := {"cull_arcane_bonus": true}
	var kept := TemplateIntAdjuster.cull_proficiencies(profs, plan, "military_strategy")
	check(kept.size() == 2, "override cull drops one prof")
	check(not _has_key(kept, "military_strategy"), "override culled the chosen general")
	check(_has_key(kept, "siege_engineering"), "arcane_bonus kept when a general is culled instead")
	# unmatched override key falls back to the arcane_bonus
	var fallback := TemplateIntAdjuster.cull_proficiencies(profs, plan, "nonexistent")
	check(not _has_key(fallback, "siege_engineering"), "unmatched override falls back to arcane_bonus")


func test_adjust_spells() -> void:
	var t := ClassTemplate.new()
	t.starting_spells = ["magic missile"]
	t.bonus_spell = "shield"
	var dropped := TemplateIntAdjuster.adjust_spells(t, {"drop_bonus_spell": true, "extra_spells_to_roll": 0})
	check(String(dropped["bonus_spell"]) == "", "bonus spell dropped at INT <= 12")
	check((dropped["starting_spells"] as Array).size() == 1, "base spell kept")
	var kept := TemplateIntAdjuster.adjust_spells(t, {"drop_bonus_spell": false, "extra_spells_to_roll": 2})
	check(String(kept["bonus_spell"]) == "shield", "bonus spell kept otherwise")
	check(int(kept["extra_spells_to_roll"]) == 2, "extra-spell count surfaced")


func test_pick_extra_generals() -> void:
	var general_list := ["healing", "survival", "riding", "endurance", "adventuring"]
	var picked := TemplateIntAdjuster.pick_extra_general_keys(2, ["healing"], general_list, "t")
	check(picked.size() == 2, "should pick 2")
	check(not picked.has("healing"), "excludes a held key")
	check(not picked.has("adventuring"), "never picks adventuring")
	check(TemplateIntAdjuster.pick_extra_general_keys(0, [], general_list).is_empty(), "0 picks none")
	# pool = list minus adventuring = 4; asking for 10 caps at 4
	check(TemplateIntAdjuster.pick_extra_general_keys(10, [], general_list, "t2").size() == 4,
		"capped at the available pool size")


func _mk(key: String, kind: String) -> TemplateProficiency:
	var p := TemplateProficiency.new()
	p.proficiency_key = key
	p.name = key
	p.proficiency_kind = kind
	p.rank = 1
	return p


func _has_key(profs: Array, key: String) -> bool:
	for p: TemplateProficiency in profs:
		if p.proficiency_key == key:
			return true
	return false
