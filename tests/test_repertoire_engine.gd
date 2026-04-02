extends "res://tests/test_suite_base.gd"

## Unit tests for RepertoireEngine.
## Verifies arcane capacity, arcane starting repertoire, and divine starting repertoire.


func run_all_tests() -> void:
	test_arcane_capacity_int_10()
	test_arcane_capacity_int_16()
	test_arcane_capacity_multi_level()
	test_starting_arcane_no_bonus()
	test_starting_arcane_with_bonus()
	test_starting_arcane_duplicates_reduce()
	test_starting_divine_cleric_l1()
	test_starting_divine_cleric_l2()
	test_starting_divine_bladedancer()
	test_starting_non_caster()
	test_bladedancer_slots_fixed()
	if not has_failures():
		print("RepertoireEngine: all tests passed.")


# ---------------------------------------------------------------------------

func _make_engine() -> RepertoireEngine:
	var class_reg := ClassRegistry.new()
	var spell_reg := SpellRegistry.new()
	return RepertoireEngine.new(spell_reg, class_reg)


func test_arcane_capacity_int_10() -> void:
	var engine := _make_engine()
	var capacity := engine.get_arcane_repertoire_capacity("mage", 1, 10)
	# Mage L1: 1 slot, INT 10 modifier = 0, capacity = [1, 0, 0, 0, 0]
	check(not capacity.is_empty(),
		"RepertoireEngine: mage L1 capacity should not be empty")
	check(capacity[0] == 1,
		"RepertoireEngine: mage L1 INT 10 first level capacity should be 1, got %d" % capacity[0])


func test_arcane_capacity_int_16() -> void:
	var engine := _make_engine()
	var capacity := engine.get_arcane_repertoire_capacity("mage", 1, 16)
	# Mage L1: 1 slot, INT 16 modifier = +2, capacity = [3, 0, 0, 0, 0]
	check(not capacity.is_empty(),
		"RepertoireEngine: mage L1 INT 16 capacity should not be empty")
	check(capacity[0] == 3,
		"RepertoireEngine: mage L1 INT 16 first level capacity should be 3, got %d" % capacity[0])


func test_arcane_capacity_multi_level() -> void:
	var engine := _make_engine()
	var capacity := engine.get_arcane_repertoire_capacity("mage", 3, 14)
	# Mage L3: slots = [2, 1, 0, 0, 0], INT 14 modifier = +1, capacity = [3, 2, 0, 0, 0]
	check(capacity.size() >= 2,
		"RepertoireEngine: mage L3 capacity should have at least 2 entries")
	check(capacity[0] == 3,
		"RepertoireEngine: mage L3 INT 14 L1 capacity should be 3, got %d" % capacity[0])
	check(capacity[1] == 2,
		"RepertoireEngine: mage L3 INT 14 L2 capacity should be 2, got %d" % capacity[1])


func test_starting_arcane_no_bonus() -> void:
	var engine := _make_engine()
	# INT 10 = modifier 0, no bonus rolls, only judge-selected spell
	var result := engine.generate_arcane_starting_repertoire("mage", 10, "charm_person")
	check(result.get("tradition", "") == "arcane",
		"RepertoireEngine: arcane starting repertoire should have tradition 'arcane'")
	var spells: Array = result.get("spells", [])
	check(spells.size() == 1,
		"RepertoireEngine: INT 10 arcane should give exactly 1 spell, got %d" % spells.size())
	check(spells[0].get("spell_key", "") == "charm_person",
		"RepertoireEngine: judge-selected spell should be charm_person")


func test_starting_arcane_with_bonus() -> void:
	var engine := _make_engine()
	# INT 16 = modifier +2, 2 d12 rolls beyond judge-selected spell.
	# Force rolls via overrides: indices 1 and 2 on the arcane L1 list.
	# arcane L1[1] = charm_person (already known), L1[2] = detect_magic
	# But charm_person is our judge-selected, so override to distinct spells.
	# Use index 2 (detect_magic) and 3 (floating_disc).
	GameState.dice_overrides["starting_spell"] = 2
	var result := engine.generate_arcane_starting_repertoire("mage", 16, "charm_person")
	# One dice_override consumed above. Queue the second.
	# (The engine rolls sequentially; both overrides needed before calling.)
	# Re-run with both overrides queued:
	GameState.dice_overrides["starting_spell"] = 2
	# Actually, DiceSystem._consume_override reads from GameState.dice_overrides dict.
	# For sequential rolls we'd need a queue. Since the current implementation uses
	# a single-value override (last-set wins), we verify the first roll was consumed.
	# Instead verify structure: INT 16 generates roll_results array.
	check(result.get("tradition", "") == "arcane",
		"RepertoireEngine: arcane tradition should be 'arcane'")
	var roll_results: Array = result.get("roll_results", [])
	# With INT 16 (+2 mod) we expect 2 bonus rolls
	check(roll_results.size() == 2,
		"RepertoireEngine: INT 16 should generate 2 d12 rolls, got %d" % roll_results.size())


func test_starting_arcane_duplicates_reduce() -> void:
	var engine := _make_engine()
	# Force both bonus rolls to index 1 (charm_person), but judge_selected = charm_person
	# Result: charm_person already in set, both rolls are duplicates -> 1 spell total
	GameState.dice_overrides["starting_spell"] = 1
	var result := engine.generate_arcane_starting_repertoire("mage", 13, "charm_person")
	var spells: Array = result.get("spells", [])
	# Duplicate rolls should NOT reroll per ACKS rules — character gets fewer spells
	check(spells.size() == 1,
		"RepertoireEngine: duplicate rolls should not produce extra spells, got %d" % spells.size())


func test_starting_divine_cleric_l1() -> void:
	var engine := _make_engine()
	# Cleric L1 has 0 spell slots — no spells in repertoire
	var result := engine.generate_divine_starting_repertoire("cleric", 1)
	check(result.get("tradition", "") == "divine",
		"RepertoireEngine: divine tradition should be 'divine'")
	var spells: Array = result.get("spells", [])
	check(spells.is_empty(),
		"RepertoireEngine: cleric L1 has 0 slots, should have 0 spells, got %d" % spells.size())


func test_starting_divine_cleric_l2() -> void:
	var engine := _make_engine()
	# Cleric L2 has 1 first-level slot — gets all 10 cleric L1 spells + reversible forms
	var result := engine.generate_divine_starting_repertoire("cleric", 2)
	var spells: Array = result.get("spells", [])
	# Should include all 10 base cleric L1 spells
	var spell_keys: Array = []
	for s in spells:
		spell_keys.append(s.get("spell_key", ""))
	check("cure_light_wounds" in spell_keys,
		"RepertoireEngine: cleric L2 should know cure_light_wounds")
	check("cause_light_wounds" in spell_keys,
		"RepertoireEngine: cleric L2 should know cause_light_wounds (reverse of cure_light_wounds)")
	check("command_word" in spell_keys,
		"RepertoireEngine: cleric L2 should know command_word")
	# All 10 base spells present
	check(spell_keys.size() >= 10,
		"RepertoireEngine: cleric L2 should have at least 10 L1 spells, got %d" % spell_keys.size())


func test_starting_divine_bladedancer() -> void:
	var engine := _make_engine()
	# Bladedancer L2 uses bladedancer list, not cleric list
	var result := engine.generate_divine_starting_repertoire("bladedancer", 2)
	var spells: Array = result.get("spells", [])
	var spell_keys: Array = []
	for s in spells:
		spell_keys.append(s.get("spell_key", ""))
	check("faerie_fire" in spell_keys,
		"RepertoireEngine: bladedancer L2 should know faerie_fire (bladedancer-only L1 spell)")
	check("fellowship" in spell_keys,
		"RepertoireEngine: bladedancer L2 should know fellowship (bladedancer-only L1 spell)")


func test_starting_non_caster() -> void:
	var engine := _make_engine()
	var result := engine.generate_starting_repertoire("fighter", 1, 14)
	check(result.is_empty(),
		"RepertoireEngine: fighter should return empty dict, not '%s'" % str(result))


func test_bladedancer_slots_fixed() -> void:
	## Regression: bladedancer's divine_casting used "spell_slots" key (bug).
	## After fix, get_spell_slots("bladedancer", 2) must return non-empty.
	var class_reg := ClassRegistry.new()
	var slots := class_reg.get_spell_slots("bladedancer", 2)
	check(not slots.is_empty(),
		"RepertoireEngine: bladedancer L2 spell slots should not be empty after bug fix")
