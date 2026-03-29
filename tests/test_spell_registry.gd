extends Node

## Unit tests for SpellRegistry.
## Verifies catalog loading, spell lookups, list indices, and class-aware queries.


func run_all_tests() -> void:
	test_catalog_loads()
	test_spell_count_reasonable()
	test_spell_lookup_charm_person()
	test_spell_lookup_light_multi_tradition()
	test_reversible_spell_cure_light_wounds()
	test_arcane_list_12_per_level()
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
	print("SpellRegistry: all tests passed.")


# ---------------------------------------------------------------------------

func test_catalog_loads() -> void:
	var reg := SpellRegistry.new()
	assert(reg.get_spell_count() > 0,
		"SpellRegistry: catalog should have loaded at least 1 spell")


func test_spell_count_reasonable() -> void:
	var reg := SpellRegistry.new()
	assert(reg.get_spell_count() >= 100,
		"SpellRegistry: catalog should have 100+ spells, got %d" % reg.get_spell_count())


func test_spell_lookup_charm_person() -> void:
	var reg := SpellRegistry.new()
	assert(reg.has_spell("charm_person"),
		"SpellRegistry: charm_person should exist in catalog")
	var entry := reg.get_spell("charm_person")
	assert(not entry.is_empty(),
		"SpellRegistry: charm_person entry should not be empty")
	assert(not entry.get("is_reversible", true),
		"SpellRegistry: charm_person should not be reversible")
	# Must have at least one arcane level 1 classification
	var classifications: Array = entry.get("classifications", [])
	var found_arcane1 := false
	for c in classifications:
		if c.get("tradition", "") == "arcane" and c.get("level", 0) == 1:
			found_arcane1 = true
	assert(found_arcane1,
		"SpellRegistry: charm_person must have arcane level 1 classification")


func test_spell_lookup_light_multi_tradition() -> void:
	var reg := SpellRegistry.new()
	assert(reg.has_spell("light"),
		"SpellRegistry: light should exist in catalog")
	var entry := reg.get_spell("light")
	assert(entry.get("is_reversible", false),
		"SpellRegistry: light should be reversible")
	assert(entry.get("reverse_key", "") == "darkness",
		"SpellRegistry: light reverse_key should be 'darkness'")
	var classifications: Array = entry.get("classifications", [])
	var has_arcane1 := false
	var has_divine1 := false
	for c in classifications:
		if c.get("tradition", "") == "arcane" and c.get("level", 0) == 1:
			has_arcane1 = true
		if c.get("tradition", "") == "divine" and c.get("level", 0) == 1:
			has_divine1 = true
	assert(has_arcane1 and has_divine1,
		"SpellRegistry: light must be both arcane 1 and divine 1")


func test_reversible_spell_cure_light_wounds() -> void:
	var reg := SpellRegistry.new()
	assert(reg.is_reversible("cure_light_wounds"),
		"SpellRegistry: cure_light_wounds should be reversible")
	assert(reg.get_reverse_key("cure_light_wounds") == "cause_light_wounds",
		"SpellRegistry: cure_light_wounds reverse key should be cause_light_wounds")


func test_arcane_list_12_per_level() -> void:
	var reg := SpellRegistry.new()
	for level in range(1, 7):
		var list := reg.get_spells_for_list("arcane", level)
		assert(list.size() == 12,
			"SpellRegistry: arcane level %d list should have 12 entries, got %d" % [level, list.size()])


func test_divine_cleric_10_per_level() -> void:
	var reg := SpellRegistry.new()
	for level in range(1, 6):
		var list := reg.get_spells_for_list("divine_cleric", level)
		assert(list.size() == 10,
			"SpellRegistry: divine_cleric level %d list should have 10 entries, got %d" % [level, list.size()])


func test_divine_bladedancer_10_per_level() -> void:
	var reg := SpellRegistry.new()
	for level in range(1, 6):
		var list := reg.get_spells_for_list("divine_bladedancer", level)
		assert(list.size() == 10,
			"SpellRegistry: divine_bladedancer level %d list should have 10 entries, got %d" % [level, list.size()])


func test_arcane_index_spell_magic_missile() -> void:
	var reg := SpellRegistry.new()
	# Arcane level 1 index 6 = magic_missile (7th entry, 0-indexed: 5)
	# Order: charm_person(1), detect_magic(2), floating_disc(3), hold_portal(4),
	#        light(5), magic_missile(6), magic_mouth(7), ...
	var spell := reg.get_arcane_index_spell(1, 6)
	assert(spell == "magic_missile",
		"SpellRegistry: arcane level 1 index 6 should be magic_missile, got '%s'" % spell)


func test_class_tradition_mage() -> void:
	var class_reg := ClassRegistry.new()
	var spell_reg := SpellRegistry.new()
	var tradition := spell_reg.get_class_tradition("mage", class_reg)
	assert(tradition == "arcane",
		"SpellRegistry: mage tradition should be 'arcane', got '%s'" % tradition)


func test_class_tradition_cleric() -> void:
	var class_reg := ClassRegistry.new()
	var spell_reg := SpellRegistry.new()
	var tradition := spell_reg.get_class_tradition("cleric", class_reg)
	assert(tradition == "divine",
		"SpellRegistry: cleric tradition should be 'divine', got '%s'" % tradition)


func test_class_tradition_fighter() -> void:
	var class_reg := ClassRegistry.new()
	var spell_reg := SpellRegistry.new()
	var tradition := spell_reg.get_class_tradition("fighter", class_reg)
	assert(tradition == "",
		"SpellRegistry: fighter should have empty tradition, got '%s'" % tradition)


func test_class_spell_list_id() -> void:
	var class_reg := ClassRegistry.new()
	var spell_reg := SpellRegistry.new()
	assert(spell_reg.get_class_spell_list_id("mage", class_reg) == "arcane",
		"SpellRegistry: mage spell list should be 'arcane'")
	assert(spell_reg.get_class_spell_list_id("cleric", class_reg) == "divine_cleric",
		"SpellRegistry: cleric spell list should be 'divine_cleric'")
	assert(spell_reg.get_class_spell_list_id("bladedancer", class_reg) == "divine_bladedancer",
		"SpellRegistry: bladedancer spell list should be 'divine_bladedancer'")


func test_available_spells_witch_includes_restricted() -> void:
	var class_reg := ClassRegistry.new()
	var spell_reg := SpellRegistry.new()
	# charm_person has a divine 3 classification restricted to witch
	var spells_l3 := spell_reg.get_available_spells_for_class("witch", 3, class_reg)
	assert("charm_person" in spells_l3,
		"SpellRegistry: witch level 3 available spells should include charm_person (witch-restricted)")


func test_available_spells_cleric_excludes_witch_restricted() -> void:
	var class_reg := ClassRegistry.new()
	var spell_reg := SpellRegistry.new()
	# charm_person divine 3 is restricted to witch only, not all clerics
	var spells_l3 := spell_reg.get_available_spells_for_class("cleric", 3, class_reg)
	assert("charm_person" not in spells_l3,
		"SpellRegistry: cleric level 3 available spells should NOT include charm_person (witch-restricted)")


func test_bladedancer_has_faerie_fire() -> void:
	var reg := SpellRegistry.new()
	var list := reg.get_spells_for_list("divine_bladedancer", 1)
	assert("faerie_fire" in list,
		"SpellRegistry: divine_bladedancer level 1 list should include faerie_fire")


func test_get_casting_power_bladedancer_fixed() -> void:
	## Verifies the bug fix: bladedancer spell_slots -> progression key rename.
	var class_reg := ClassRegistry.new()
	var slots := class_reg.get_spell_slots("bladedancer", 2)
	assert(not slots.is_empty(),
		"SpellRegistry: bladedancer L2 spell slots should not be empty (was bug: returned [])")
	assert(slots[0] == 1,
		"SpellRegistry: bladedancer L2 first slot should be 1, got %d" % (slots[0] if not slots.is_empty() else -1))
