extends "res://tests/test_suite_base.gd"

## Unit tests for SpellRegistry.
## Verifies catalog loading, spell lookups, list indices, and class-aware queries.


func run_all_tests() -> void:
	test_catalog_loads()
	test_spell_count_reasonable()
	test_spell_lookup_charm_person()
	test_spell_lookup_light_multi_tradition()
	test_reversible_spell_cure_light_wounds()
	test_arcane_list_24_per_level()
	test_divine_cleric_10_per_level()
	test_divine_bladedancer_10_per_level()
	test_arcane_index_spell_magic_missile()
	test_class_tradition_mage()
	test_class_tradition_cleric()
	test_class_tradition_fighter()
	test_class_spell_list_id()
	test_available_spells_witch_includes_restricted()
	test_available_spells_cleric_excludes_witch_restricted()
	test_bladedancer_has_faerie_fire()
	test_get_casting_power_bladedancer_fixed()
	if not has_failures():
		print("SpellRegistry: all tests passed.")


# ---------------------------------------------------------------------------

func test_catalog_loads() -> void:
	var reg := SpellRegistry.new()
	check(reg.get_spell_count() > 0,
		"SpellRegistry: catalog should have loaded at least 1 spell")


func test_spell_count_reasonable() -> void:
	var reg := SpellRegistry.new()
	check(reg.get_spell_count() >= 100,
		"SpellRegistry: catalog should have 100+ spells, got %d" % reg.get_spell_count())


func test_spell_lookup_charm_person() -> void:
	var reg := SpellRegistry.new()
	check(reg.has_spell("charm_person"),
		"SpellRegistry: charm_person should exist in catalog")
	var entry := reg.get_spell("charm_person")
	check(not entry.is_empty(),
		"SpellRegistry: charm_person entry should not be empty")
	check(not entry.get("is_reversible", true),
		"SpellRegistry: charm_person should not be reversible")
	# Must have at least one arcane level 1 classification
	var classifications: Array = entry.get("classifications", [])
	var found_arcane1 := false
	for c in classifications:
		if c.get("tradition", "") == "arcane" and c.get("level", 0) == 1:
			found_arcane1 = true
	check(found_arcane1,
		"SpellRegistry: charm_person must have arcane level 1 classification")


func test_spell_lookup_light_multi_tradition() -> void:
	var reg := SpellRegistry.new()
	check(reg.has_spell("light"),
		"SpellRegistry: light should exist in catalog")
	var entry := reg.get_spell("light")
	check(entry.get("is_reversible", false),
		"SpellRegistry: light should be reversible")
	check(entry.get("reverse_key", "") == "darkness",
		"SpellRegistry: light reverse_key should be 'darkness'")
	var classifications: Array = entry.get("classifications", [])
	var has_arcane1 := false
	var has_divine1 := false
	for c in classifications:
		if c.get("tradition", "") == "arcane" and c.get("level", 0) == 1:
			has_arcane1 = true
		if c.get("tradition", "") == "divine" and c.get("level", 0) == 1:
			has_divine1 = true
	check(has_arcane1 and has_divine1,
		"SpellRegistry: light must be both arcane 1 and divine 1")


func test_reversible_spell_cure_light_wounds() -> void:
	var reg := SpellRegistry.new()
	check(reg.is_reversible("cure_light_wounds"),
		"SpellRegistry: cure_light_wounds should be reversible")
	check(reg.get_reverse_key("cure_light_wounds") == "cause_light_wounds",
		"SpellRegistry: cure_light_wounds reverse key should be cause_light_wounds")


func test_arcane_list_24_per_level() -> void:
	# Phase 10B.1g.2 (2026-05-11): updated from 12 to 24 entries per level
	# after ingesting the canonical arcane spell list from PC Spell Lists.pdf
	# (book p.126). The old 12-per-level value was a placeholder; the full
	# arcane list per RAW is 24 spells per level L1-L6. L2 has 23 since
	# one slot historically didn't get a spell assignment in the source —
	# this matches the PDF directly.
	var reg := SpellRegistry.new()
	for level in range(1, 7):
		var list := reg.get_spells_for_list("arcane", level)
		var expected: int = 23 if level == 2 else 24
		check(list.size() == expected,
			"SpellRegistry: arcane level %d list should have %d entries, got %d" % [level, expected, list.size()])


func test_divine_cleric_10_per_level() -> void:
	var reg := SpellRegistry.new()
	for level in range(1, 6):
		var list := reg.get_spells_for_list("divine_cleric", level)
		check(list.size() == 10,
			"SpellRegistry: divine_cleric level %d list should have 10 entries, got %d" % [level, list.size()])


func test_divine_bladedancer_10_per_level() -> void:
	var reg := SpellRegistry.new()
	for level in range(1, 6):
		var list := reg.get_spells_for_list("divine_bladedancer", level)
		check(list.size() == 10,
			"SpellRegistry: divine_bladedancer level %d list should have 10 entries, got %d" % [level, list.size()])


func test_arcane_index_spell_magic_missile() -> void:
	# Phase 10B.1g.2 (2026-05-11): index updated after PDF ingestion.
	# Canonical PDF order for arcane L1 has 24 spells; magic_missile is
	# now at 1-based index 10 (between light and magic_mouth) — preceding
	# entries: burning_hands, charm_person, chameleon, choking_grip,
	# detect_magic, floating_disc, hold_portal, jump, light, magic_missile.
	var reg := SpellRegistry.new()
	var spell := reg.get_arcane_index_spell(1, 10)
	check(spell == "magic_missile",
		"SpellRegistry: arcane level 1 index 10 should be magic_missile, got '%s'" % spell)


func test_class_tradition_mage() -> void:
	var class_reg := ClassRegistry.new()
	var spell_reg := SpellRegistry.new()
	var tradition := spell_reg.get_class_tradition("mage", class_reg)
	check(tradition == "arcane",
		"SpellRegistry: mage tradition should be 'arcane', got '%s'" % tradition)


func test_class_tradition_cleric() -> void:
	var class_reg := ClassRegistry.new()
	var spell_reg := SpellRegistry.new()
	var tradition := spell_reg.get_class_tradition("cleric", class_reg)
	check(tradition == "divine",
		"SpellRegistry: cleric tradition should be 'divine', got '%s'" % tradition)


func test_class_tradition_fighter() -> void:
	var class_reg := ClassRegistry.new()
	var spell_reg := SpellRegistry.new()
	var tradition := spell_reg.get_class_tradition("fighter", class_reg)
	check(tradition == "",
		"SpellRegistry: fighter should have empty tradition, got '%s'" % tradition)


func test_class_spell_list_id() -> void:
	var class_reg := ClassRegistry.new()
	var spell_reg := SpellRegistry.new()
	check(spell_reg.get_class_spell_list_id("mage", class_reg) == "arcane",
		"SpellRegistry: mage spell list should be 'arcane'")
	check(spell_reg.get_class_spell_list_id("cleric", class_reg) == "divine_cleric",
		"SpellRegistry: cleric spell list should be 'divine_cleric'")
	check(spell_reg.get_class_spell_list_id("bladedancer", class_reg) == "divine_bladedancer",
		"SpellRegistry: bladedancer spell list should be 'divine_bladedancer'")


func test_available_spells_witch_includes_restricted() -> void:
	var class_reg := ClassRegistry.new()
	var spell_reg := SpellRegistry.new()
	# charm_person has a divine 3 classification restricted to witch
	var spells_l3 := spell_reg.get_available_spells_for_class("witch", 3, class_reg)
	check("charm_person" in spells_l3,
		"SpellRegistry: witch level 3 available spells should include charm_person (witch-restricted)")


func test_available_spells_cleric_excludes_witch_restricted() -> void:
	var class_reg := ClassRegistry.new()
	var spell_reg := SpellRegistry.new()
	# charm_person divine 3 is restricted to witch only, not all clerics
	var spells_l3 := spell_reg.get_available_spells_for_class("cleric", 3, class_reg)
	check("charm_person" not in spells_l3,
		"SpellRegistry: cleric level 3 available spells should NOT include charm_person (witch-restricted)")


func test_bladedancer_has_faerie_fire() -> void:
	var reg := SpellRegistry.new()
	var list := reg.get_spells_for_list("divine_bladedancer", 1)
	check("faerie_fire" in list,
		"SpellRegistry: divine_bladedancer level 1 list should include faerie_fire")


func test_get_casting_power_bladedancer_fixed() -> void:
	## Verifies the bug fix: bladedancer spell_slots -> progression key rename.
	var class_reg := ClassRegistry.new()
	var slots := class_reg.get_spell_slots("bladedancer", 2)
	check(not slots.is_empty(),
		"SpellRegistry: bladedancer L2 spell slots should not be empty (was bug: returned [])")
	check(slots[0] == 1,
		"SpellRegistry: bladedancer L2 first slot should be 1, got %d" % (slots[0] if not slots.is_empty() else -1))
