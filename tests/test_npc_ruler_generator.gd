extends "res://tests/test_suite_base.gd"

## Unit tests for NpcRulerGenerator.
##
## Coverage:
##   * Class distribution over many rolls matches CLASS_WEIGHTS within a
##     reasonable tolerance.
##   * Level matches LEVEL_BY_TITLE for every supported realm title.
##   * Proficiency picks hit RULER_PREFERRED_KEYS the majority of the time
##     when the class list contains preferred options.
##   * A rolled ruler has the basic stats expected of a generated NPC.


func run_all_tests() -> void:
	test_class_distribution()
	test_level_by_title()
	test_proficiency_bias_hits_preferred_keys()
	test_generated_ruler_basic_validity()
	if not has_failures():
		print("NpcRulerGenerator: all tests passed.")


# ---------------------------------------------------------------------------
# Class distribution
# ---------------------------------------------------------------------------

func test_class_distribution() -> void:
	var gen := NpcRulerGenerator.new()
	var counts := {"fighter": 0, "cleric": 0, "mage": 0, "thief": 0}
	var n_rolls := 1000
	for i in range(n_rolls):
		var c: String = gen.roll_class()
		if counts.has(c):
			counts[c] = int(counts[c]) + 1
	# Expected (per CLASS_WEIGHTS): fighter 70%, cleric 20%, mage 5%, thief 5%.
	# Allow ±5% absolute tolerance (50 of 1000) on each bucket — generous vs.
	# 3σ of the underlying binomial.
	check(absi(int(counts["fighter"]) - 700) <= 50,
		"fighter count off: expected ~700, got %d" % int(counts["fighter"]))
	check(absi(int(counts["cleric"]) - 200) <= 50,
		"cleric count off: expected ~200, got %d" % int(counts["cleric"]))
	check(absi(int(counts["mage"]) - 50) <= 30,
		"mage count off: expected ~50, got %d" % int(counts["mage"]))
	check(absi(int(counts["thief"]) - 50) <= 30,
		"thief count off: expected ~50, got %d" % int(counts["thief"]))
	print("  class_distribution: OK (fighter=%d, cleric=%d, mage=%d, thief=%d)" % [
		int(counts["fighter"]), int(counts["cleric"]),
		int(counts["mage"]), int(counts["thief"])])


# ---------------------------------------------------------------------------
# Level by title
# ---------------------------------------------------------------------------

func test_level_by_title() -> void:
	var expected := {
		"Baron":   6,
		"Count":   8,
		"Duke":   10,
		"Prince": 12,
		"King":   13,
		"Emperor": 14,
	}
	for title in expected.keys():
		check(int(NpcRulerGenerator.LEVEL_BY_TITLE.get(title, -1)) == int(expected[title]),
			"LEVEL_BY_TITLE[%s] should be %d" % [String(title), int(expected[title])])
	print("  level_by_title: OK")


# ---------------------------------------------------------------------------
# Proficiency bias
# ---------------------------------------------------------------------------

func test_proficiency_bias_hits_preferred_keys() -> void:
	# Use a Fighter — has a long class proficiency list including several
	# preferred ruler keys (leadership, command, mystic_aura, intimidation,
	# manipulation, etc.).
	var class_reg := ClassRegistry.new()
	var power_reg := PowerRegistry.new()
	var prof_reg := ProficiencyRegistry.new()
	var gen := CharacterGenerator.new(class_reg, power_reg, prof_reg)

	var pref: Array = NpcRulerGenerator.RULER_PREFERRED_KEYS
	var trials := 30
	var slots_total: int = 0
	var preferred_hits: int = 0
	for i in range(trials):
		# Level 8 fighter: 4 class slots (1,3,6,9 → 3 unlocked by L8: 1,3,6) and
		# multiple general slots — gives the bias path many chances to fire.
		var proficiencies: Array = gen.auto_select_proficiencies("fighter", 8, pref)
		for p in proficiencies:
			var slot_type: String = String(p.get("slot_type", ""))
			if slot_type != "class" and slot_type != "general":
				continue
			# Skip the auto-added "adventuring" slot — that's deterministic and
			# would dilute the bias measurement.
			if String(p.get("proficiency_key", "")) == "adventuring":
				continue
			slots_total += 1
			if String(p.get("proficiency_key", "")) in pref:
				preferred_hits += 1

	check(slots_total > 0, "no proficiency slots filled across %d trials" % trials)
	if slots_total <= 0:
		return
	var hit_rate: float = float(preferred_hits) / float(slots_total)
	check(hit_rate >= 0.50,
		"preferred-key hit rate too low: %d/%d = %.2f (expected >= 0.50)" % [
			preferred_hits, slots_total, hit_rate])
	print("  proficiency_bias_hits_preferred_keys: OK (%d/%d preferred = %.0f%%)" % [
		preferred_hits, slots_total, hit_rate * 100.0])


# ---------------------------------------------------------------------------
# Generated ruler basic validity
# ---------------------------------------------------------------------------

func test_generated_ruler_basic_validity() -> void:
	var class_reg := ClassRegistry.new()
	var power_reg := PowerRegistry.new()
	var prof_reg := ProficiencyRegistry.new()
	var gen := CharacterGenerator.new(class_reg, power_reg, prof_reg)
	# Roll several characters via the same NPC pathway the ruler generator uses.
	for class_id in NpcRulerGenerator.CLASS_WEIGHTS.keys():
		var level: int = 8
		var npc: CharacterData = gen.generate_npc(String(class_id), level,
			"test_ruler_validity_campaign", "full", "npc")
		check(npc != null, "generate_npc returned null for class=%s" % String(class_id))
		if npc == null:
			continue
		check(npc.hp_max > 0, "hp_max should be > 0; got %d" % npc.hp_max)
		check(npc.attack_throw > 0, "attack_throw should be > 0; got %d" % npc.attack_throw)
		check(npc.level == level, "level mismatch: expected %d got %d" % [level, npc.level])
		check(not npc.id.is_empty(), "id should be set")
		check(npc.character_type == "npc", "character_type should be 'npc'")
	print("  generated_ruler_basic_validity: OK")
