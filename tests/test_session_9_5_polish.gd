extends "res://tests/test_suite_base.gd"

## Session 9.5 — Polish pass: Diseased magic-heal block + generalized
## save_vs_X read-side wiring (damage_type + attacker_alignment).
##
## Coverage:
##   - Cure Light Wounds on a Diseased target → no heal applied
##     (RAW: acore_spell_catalog_a-i_summary.xml Cause Disease — "The target
##     cannot be magically healed while afflicted").
##   - Cure Light Wounds on a non-Diseased target → heal applied normally.
##   - Cure Serious Wounds (heal_fixed path) on Diseased → no heal.
##   - Save_vs_fire stacks on Fireball save when Resist Fire is active.
##   - Save_vs_cold stacks on a cold-tagged save when Resist Cold is active.
##   - Save_vs_chaotic stacks on a chaotic-tagged save when Protection from
##     Evil is active.
##   - save_vs_lawful as the reverse axis (Protection from Good).
##   - consult_caster_alignment auto-fills attacker_alignment from
##     caster_context.alignment.
##   - CharacterData.get_effective_save returns 0 baseline for the new
##     modifier-only axes; modifier value when one is written.


class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}
	func roll_expression(e: String, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, fixed.get(e, 0)))
		r.raw_total = r.modified_total
		return r
	func roll_digital(s: int, c: int = 1, m: int = 0, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, c * s)) + m
		r.raw_total = r.modified_total - m
		return r


class _FakeRepo extends RefCounted:
	var expended: Dictionary = {}
	func increment_expended_slot(c: String, l: int) -> bool:
		if not expended.has(c): expended[c] = {}
		expended[c][l] = int(expended[c].get(l, 0)) + 1
		return true
	func reset_expended_slots(c: String) -> bool: expended[c] = {}; return true
	func get_expended_slots(c: String) -> Dictionary: return expended.get(c, {})


# Duck-typed combatant carrying conditions + saves + modifiers.
class _SaveTarget extends RefCounted:
	var id: String = ""
	var save_blast_breath: int = 14
	var save_spells: int = 17
	var conditions: Array[String] = []
	var modifiers: ModifierContainer = ModifierContainer.new()

	func get_modifiers() -> ModifierContainer:
		return modifiers

	func get_effective_save(key: String) -> int:
		var base: int
		match key:
			"save_blast_breath": base = save_blast_breath
			"save_spells":       base = save_spells
			"save_vs_fear", "save_vs_fire", "save_vs_cold", "save_vs_electricity", \
			"save_vs_chaotic", "save_vs_lawful": base = 0
			_: return 20
		return modifiers.get_effective_value(key, base)

	func has_condition(k: String) -> bool: return k in conditions
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)

	func is_immune_to_fear() -> bool: return false


func run_all_tests() -> void:
	test_diseased_blocks_cure_light_wounds()
	test_non_diseased_heals_normally()
	test_diseased_blocks_heal_fixed()
	test_save_vs_fire_stacks_on_fireball_save()
	test_save_vs_cold_stacks_on_cold_save()
	test_save_vs_chaotic_stacks_on_chaotic_attacker_save()
	test_save_vs_lawful_axis_reads_from_modifier()
	test_consult_caster_alignment_auto_fills()
	test_character_data_get_effective_save_baseline_zero()
	test_character_data_get_effective_save_with_modifier()
	test_fireball_save_spec_carries_damage_type_fire()
	test_lightning_bolt_save_spec_carries_damage_type_electricity()
	if not has_failures():
		print("Session9_5Polish: all tests passed.")


# ---------------------------------------------------------------------------
# Diseased magic-heal block (RAW: Cause Disease — cannot be magically healed)
# ---------------------------------------------------------------------------

func test_diseased_blocks_cure_light_wounds() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ally := CharacterData.new()
	ally.id = "diseased_ally"
	ally.hp_max = 10; ally.hp_current = 5  # 5 hp damage taken
	# Add diseased condition to the ally. CharacterData has a `conditions`
	# Array we can poke directly for the test (production uses Combatant
	# wrapper, which the resolver detects via _entity_has_condition).
	ally.conditions.append("diseased")
	# Force the heal roll to 6.
	harness.dice.fixed["spell_healing"] = 6
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("cure_light_wounds", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_ally"; td.target_ids = [ally.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(result.success, "Spell still resolves (slot consumed)")
	check(ally.hp_current == 5,
		"Diseased ally NOT healed (hp_current=5), got %d" % ally.hp_current)
	var step: Dictionary = result.effects_applied[0]
	var per_target: Dictionary = step.get("per_target", {})
	check(String(per_target.get(ally.id, {}).get("reason", "")) == "diseased_magic_heal_blocked",
		"per_target.reason='diseased_magic_heal_blocked'")


func test_non_diseased_heals_normally() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ally := CharacterData.new()
	ally.id = "healthy_ally"
	ally.hp_max = 10; ally.hp_current = 5
	harness.dice.fixed["spell_healing"] = 6
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("cure_light_wounds", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_ally"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(ally.hp_current > 5,
		"Healthy ally healed (hp_current>5), got %d" % ally.hp_current)


func test_diseased_blocks_heal_fixed() -> void:
	# Synthesize a heal_fixed step (Heal spell, Session 15) via direct call
	# since cure_light_wounds uses the dice path. This verifies the gate is
	# in both heal handlers.
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ally := CharacterData.new()
	ally.id = "diseased_ally2"
	ally.hp_max = 20; ally.hp_current = 10
	ally.conditions.append("diseased")
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var step := {"kind": "heal_fixed", "amount": 15}
	var td := TargetDescriptor.new()
	td.kind = "touch_ally"; td.target_ids = [ally.id]
	var outcome: Dictionary = harness.resolver._apply_heal_fixed(
		step, td, {ally.id: ally}, caster, ctx)
	check(ally.hp_current == 10,
		"Diseased ally NOT healed by heal_fixed (hp_current=10), got %d" % ally.hp_current)
	check(String(outcome.get("per_target", {}).get(ally.id, {}).get("reason", "")) \
		== "diseased_magic_heal_blocked",
		"heal_fixed reports diseased_magic_heal_blocked")


# ---------------------------------------------------------------------------
# Save_vs_X read-side wiring
# ---------------------------------------------------------------------------

func test_save_vs_fire_stacks_on_fireball_save() -> void:
	# Goblin with Resist Fire active (save_vs_fire +2) takes a Fireball save.
	# Forced d20 roll = 12; save target = 14. Without the bonus, 12 < 14 → fail.
	# With +2 bonus, 12 + 2 = 14 ≥ 14 → success.
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 5
	# Pre-grant the goblin Resist Fire's save bonus.
	var goblin := _SaveTarget.new()
	goblin.id = "g_rf"; goblin.save_blast_breath = 14
	goblin.modifiers.add_modifier("save_vs_fire", {
		"source_id": "spell:resist_fire:cleric_test",
		"source_type": "spell",
		"operation": "add",
		"value": 2,
		"stacking_group": "resist_fire",
	})
	# Force the d20 roll to 12.
	harness.dice.fixed["spell_save_blast"] = 12
	# Mock damage so the resolver doesn't crash; force per-die to 1.
	harness.dice.fixed["spell_damage"] = 1
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("fireball", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(0, 0, 0)
	td.target_ids = ["g_rf"]
	td.target_cells = [Vector3i(1, 0, 0)]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {"g_rf": goblin})
	# The save SHOULD have succeeded (12 + 2 = 14). On success, Fireball
	# halves damage. Verify by checking the per-target outcome.
	var step: Dictionary = result.effects_applied[0]
	var per_target: Dictionary = step.get("per_target", {})
	check(bool(per_target.get("g_rf", {}).get("saved", false)),
		"Resist Fire +2 bonus made the save succeed (12 + 2 = 14 ≥ 14)")


func test_save_vs_cold_stacks_on_cold_save() -> void:
	# Direct unit test of _roll_saves_for_targets with damage_type='cold'.
	var harness := _make_harness()
	var goblin := _SaveTarget.new()
	goblin.id = "g_rc"; goblin.save_blast_breath = 14
	goblin.modifiers.add_modifier("save_vs_cold", {
		"source_id": "spell:resist_cold:test",
		"source_type": "spell",
		"operation": "add",
		"value": 2,
		"stacking_group": "resist_cold",
	})
	harness.dice.fixed["spell_save_blast"] = 12
	var save_spec := {
		"category": "blast",
		"on_success": "half_damage",
		"damage_type": "cold",
	}
	var td := TargetDescriptor.new()
	td.target_ids = ["g_rc"]
	var ctx := CasterContext.from_character_data(_make_caster_mage(), "combat_grid", "arcane", 0)
	var saves: Dictionary = harness.resolver._roll_saves_for_targets(
		td, {"g_rc": goblin}, save_spec, ctx)
	var entry: Dictionary = saves.get("g_rc", {})
	check(int(entry.get("element_bonus", 0)) == 2,
		"element_bonus=2 from save_vs_cold, got %d" % entry.get("element_bonus", 0))
	check(bool(entry.get("succeeded", false)),
		"12 (rolled) + 2 (cold) = 14 ≥ 14 (target) → save succeeds")


func test_save_vs_chaotic_stacks_on_chaotic_attacker_save() -> void:
	var harness := _make_harness()
	var pc := _SaveTarget.new()
	pc.id = "pc_pfe"; pc.save_spells = 17
	pc.modifiers.add_modifier("save_vs_chaotic", {
		"source_id": "spell:protection_from_evil:test",
		"source_type": "spell",
		"operation": "add",
		"value": 1,
		"stacking_group": "protection_from_evil",
	})
	harness.dice.fixed["spell_save_spells"] = 16
	var save_spec := {
		"category": "spells",
		"on_success": "negate",
		"attacker_alignment": "chaotic",
	}
	var td := TargetDescriptor.new()
	td.target_ids = ["pc_pfe"]
	var ctx := CasterContext.from_character_data(_make_caster_mage(), "combat_grid", "arcane", 0)
	var saves: Dictionary = harness.resolver._roll_saves_for_targets(
		td, {"pc_pfe": pc}, save_spec, ctx)
	var entry: Dictionary = saves.get("pc_pfe", {})
	check(int(entry.get("alignment_bonus", 0)) == 1,
		"alignment_bonus=1 from save_vs_chaotic, got %d" % entry.get("alignment_bonus", 0))
	check(bool(entry.get("succeeded", false)),
		"16 (rolled) + 1 (chaotic) = 17 ≥ 17 (target) → save succeeds")


func test_save_vs_lawful_axis_reads_from_modifier() -> void:
	# Mirror axis: Protection from Good writes save_vs_lawful.
	var pc := _SaveTarget.new()
	pc.id = "pc_pfg"
	pc.modifiers.add_modifier("save_vs_lawful", {
		"source_id": "spell:protection_from_good:test",
		"source_type": "spell",
		"operation": "add",
		"value": 1,
		"stacking_group": "protection_from_good",
	})
	check(pc.get_effective_save("save_vs_lawful") == 1,
		"save_vs_lawful = 1, got %d" % pc.get_effective_save("save_vs_lawful"))


func test_consult_caster_alignment_auto_fills() -> void:
	# Spells can flag `consult_caster_alignment: true` on save_spec without
	# specifying attacker_alignment; resolver auto-fills from caster_context.
	var harness := _make_harness()
	var pc := _SaveTarget.new()
	pc.id = "pc_pfe2"
	pc.modifiers.add_modifier("save_vs_chaotic", {
		"source_id": "spell:protection_from_evil:test2",
		"source_type": "spell",
		"operation": "add",
		"value": 1,
		"stacking_group": "protection_from_evil",
	})
	harness.dice.fixed["spell_save_spells"] = 16
	var save_spec := {
		"category": "spells",
		"on_success": "negate",
		"consult_caster_alignment": true,
	}
	var td := TargetDescriptor.new(); td.target_ids = ["pc_pfe2"]
	# Caster is chaotic.
	var caster := _make_caster_mage()
	caster.alignment = "chaotic"
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var saves: Dictionary = harness.resolver._roll_saves_for_targets(
		td, {"pc_pfe2": pc}, save_spec, ctx)
	var entry: Dictionary = saves.get("pc_pfe2", {})
	check(str(entry.get("attacker_alignment", "")) == "chaotic",
		"attacker_alignment auto-filled from caster_context.alignment")
	check(int(entry.get("alignment_bonus", 0)) == 1,
		"PfE +1 vs chaotic caster auto-stacked")


# ---------------------------------------------------------------------------
# CharacterData get_effective_save axis coverage
# ---------------------------------------------------------------------------

func test_character_data_get_effective_save_baseline_zero() -> void:
	var cd := CharacterData.new()
	for k in ["save_vs_fire", "save_vs_cold", "save_vs_chaotic", "save_vs_lawful",
			  "save_vs_electricity"]:
		check(cd.get_effective_save(k) == 0,
			"%s baseline = 0, got %d" % [k, cd.get_effective_save(k)])


func test_character_data_get_effective_save_with_modifier() -> void:
	var cd := CharacterData.new()
	cd.modifiers.add_modifier("save_vs_fire", {
		"source_id": "spell:resist_fire:c1",
		"source_type": "spell",
		"operation": "add",
		"value": 2,
		"stacking_group": "resist_fire",
	})
	check(cd.get_effective_save("save_vs_fire") == 2,
		"save_vs_fire with +2 modifier = 2, got %d" % cd.get_effective_save("save_vs_fire"))


# ---------------------------------------------------------------------------
# Spell-catalog tagging
# ---------------------------------------------------------------------------

func test_fireball_save_spec_carries_damage_type_fire() -> void:
	var er := SpellEffectRegistry.new(SpellRegistry.new())
	var payload: Dictionary = er.get_effect_payload("fireball", false, -1)
	var ss: Dictionary = payload.get("save_spec", {})
	check(String(ss.get("damage_type", "")) == "fire",
		"Fireball save_spec.damage_type='fire'")


func test_lightning_bolt_save_spec_carries_damage_type_electricity() -> void:
	var er := SpellEffectRegistry.new(SpellRegistry.new())
	var payload: Dictionary = er.get_effect_payload("lightning_bolt", false, -1)
	var ss: Dictionary = payload.get("save_spec", {})
	check(String(ss.get("damage_type", "")) == "electricity",
		"Lightning Bolt save_spec.damage_type='electricity'")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

class _Harness extends RefCounted:
	var dice = null
	var repo = null
	var resolver = null


func _make_harness() -> _Harness:
	var h := _Harness.new()
	h.dice = _FakeDice.new()
	h.repo = _FakeRepo.new()
	var sr := SpellRegistry.new()
	var er := SpellEffectRegistry.new(sr)
	var tracker := ActiveEffectTracker.new()
	var cc := ConditionCatalog.new()
	var cr := CustomResolverRegistry.new()
	h.resolver = CastingResolver.new(sr, er, tracker, cc, cr, null, h.repo, h.dice)
	return h


func _make_caster_cleric() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "cleric_p95"; cd.name = "Test Cleric"
	cd.character_class = "cleric"; cd.combat_progression = "cleric"
	cd.level = 1; cd.wisdom = 13
	cd.hp_max = 6; cd.hp_current = 6
	return cd


func _make_caster_mage() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "mage_p95"; cd.name = "Test Mage"
	cd.character_class = "mage"; cd.combat_progression = "mage"
	cd.level = 1; cd.intelligence = 13
	cd.hp_max = 4; cd.hp_current = 4
	return cd
