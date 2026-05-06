extends "res://tests/test_suite_base.gd"

## Session 9 — L3 divine spell binding tests + remove_modifier / apply_modifier_to_item.
##
## Coverage:
##   - Cure Disease: removes diseased condition.
##   - Cause Disease (reverse): applies diseased on save fail; -2 attack penalty in catalog.
##   - Glyph of Warding: modify_cell_state w/ shape=place_glyph + trigger condition.
##   - Prayer: 6 modifier writes (allies +1 attack/damage/save, enemies -1).
##   - Remove Curse: remove_modifier with source_pattern='curse:*'.
##   - Bestow Curse (reverse): apply_modifier with source_prefix=curse:bestow_curse.
##   - Speak with Dead: stub resolution.
##   - Striking: apply_modifier_to_item w/ damage_bonus_dice=1d6 + strikes_as_magical.
##   - Water Walking: apply_flag can_water_walk + movement_mode_grant.
##   - Diseased condition: -2 attack_modifier per RAW.
##   - remove_modifier: clears matching source-prefix modifiers.
##   - apply_modifier_to_item: records contract per-target-item.


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
	func get_expended_slots(c: String) -> Dictionary:
		return expended.get(c, {})


# Cursed-target stand-in carrying ModifierContainer.
class _CurseTarget extends RefCounted:
	var id: String = ""
	var modifiers: ModifierContainer = ModifierContainer.new()
	var conditions: Array[String] = []

	func get_modifiers() -> ModifierContainer:
		return modifiers

	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func remove_condition(k: String) -> void: conditions.erase(k)
	func has_condition(k: String) -> bool: return k in conditions

	func get_effective_save(key: String) -> int:
		match key:
			"save_spells": return 17
		return 20


func run_all_tests() -> void:
	test_diseased_condition_in_catalog()
	test_cure_disease_removes_diseased()
	test_cause_disease_reverse_applies_on_save_fail()
	test_glyph_of_warding_place_glyph()
	test_prayer_writes_six_modifiers()
	test_remove_curse_clears_curse_prefixed_modifiers()
	test_bestow_curse_reverse_applies_curse_modifier()
	test_speak_with_dead_stub()
	test_striking_apply_modifier_to_item_damage_dice()
	test_striking_strikes_as_magical()
	test_water_walking_flag_with_metadata()
	test_water_walking_movement_mode_grant()
	# Resolver-step direct unit tests
	test_remove_modifier_step_clears_by_prefix()
	test_apply_modifier_to_item_records_contract()
	if not has_failures():
		print("L3DivineCatalog: all tests passed.")


# ---------------------------------------------------------------------------
# Diseased condition
# ---------------------------------------------------------------------------

func test_diseased_condition_in_catalog() -> void:
	var catalog := ConditionCatalog.new()
	var c: Dictionary = catalog.get_condition("diseased")
	check(not c.is_empty(), "diseased condition exists in catalog")
	check(int(c.get("attack_modifier", 0)) == -2,
		"diseased: attack_modifier=-2 per RAW, got %d" % c.get("attack_modifier", 0))


# ---------------------------------------------------------------------------
# Cure Disease / Cause Disease
# ---------------------------------------------------------------------------

func test_cure_disease_removes_diseased() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ally := _CurseTarget.new()
	ally.id = "ally_cd"
	ally.add_condition("diseased")
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("cure_disease", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(not ally.has_condition("diseased"),
		"diseased removed from ally after Cure Disease")


func test_cause_disease_reverse_applies_on_save_fail() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var enemy := _CurseTarget.new()
	enemy.id = "enemy_cd"
	# Force save fail (low roll vs target 17).
	harness.dice.fixed["spell_save_spells"] = 5
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("cure_disease", 3, true, -1)  # reverse
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [enemy.id]
	harness.resolver.resolve(ctx, choice, td, caster, {enemy.id: enemy})
	check("diseased" in enemy.conditions,
		"diseased applied on save fail")


# ---------------------------------------------------------------------------
# Glyph of Warding
# ---------------------------------------------------------------------------

func test_glyph_of_warding_place_glyph() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "divine", 1)
	var choice := SpellChoice.new("glyph_of_warding", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_cell"
	td.origin_cell = Vector3i(7, 7, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("shape", "") == "place_glyph",
		"shape='place_glyph', got %s" % step.get("shape", ""))
	var mut: Dictionary = step.get("mutation", {})
	check(int(mut.get("blast_damage_per_caster_level", 0)) == 2,
		"blast glyph: 2 dmg per caster level per RAW")


# ---------------------------------------------------------------------------
# Prayer
# ---------------------------------------------------------------------------

func test_prayer_writes_six_modifiers() -> void:
	# Prayer applies 3 buffs to allies + 3 debuffs to enemies = 6 modifier
	# writes per cast. Verify the resolution payload has 6 modifier steps.
	var harness := _make_harness()
	var payload: Dictionary = harness.effect_registry.get_effect_payload("prayer", false, -1)
	var resolution: Array = payload.get("resolution", [])
	var modifier_steps: int = 0
	for step in resolution:
		if step.get("kind", "") == "apply_modifier":
			modifier_steps += 1
	check(modifier_steps == 6,
		"Prayer has 6 apply_modifier steps (3 ally + 3 enemy), got %d" % modifier_steps)


# ---------------------------------------------------------------------------
# Remove Curse / Bestow Curse
# ---------------------------------------------------------------------------

func test_remove_curse_clears_curse_prefixed_modifiers() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	caster.level = 5
	var target := _CurseTarget.new()
	target.id = "cursed"
	# Pre-existing curse modifier (attack_throw -2 from "curse:bestow_curse:c1").
	target.modifiers.add_modifier("attack_throw", {
		"source_id": "curse:bestow_curse:c1",
		"source_type": "spell",
		"operation": "add",
		"value": -2,
		"stacking_group": "curse",
	})
	check(target.modifiers.has_modifier_for_stat("attack_throw"),
		"pre: cursed attack_throw modifier present")

	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("remove_curse", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [target.id]
	harness.resolver.resolve(ctx, choice, td, caster, {target.id: target})

	check(not target.modifiers.has_modifier_for_stat("attack_throw"),
		"after Remove Curse: attack_throw modifier cleared (curse:* prefix matched)")


func test_bestow_curse_reverse_applies_curse_modifier() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var target := _CurseTarget.new()
	target.id = "victim_bc"
	# Force save fail.
	harness.dice.fixed["spell_save_spells"] = 5
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("remove_curse", 3, true, -1)  # reverse → Bestow
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [target.id]
	harness.resolver.resolve(ctx, choice, td, caster, {target.id: target})
	check(target.modifiers.has_modifier_for_stat("attack_throw"),
		"Bestow Curse wrote attack_throw modifier on save fail")


# ---------------------------------------------------------------------------
# Speak with Dead — stub
# ---------------------------------------------------------------------------

func test_speak_with_dead_stub() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "divine", 1)
	var choice := SpellChoice.new("speak_with_dead", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = ["corpse_1"]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {"corpse_1": null})
	check(result.success, "Speak with Dead resolves (stub does not fail cast)")
	check(result.slot_consumed, "Slot consumed for stub")
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "stub",
		"step_kind='stub'")
	check(String(step.get("reason", "")) == "requires_llm_narration_layer",
		"stub reason set")


# ---------------------------------------------------------------------------
# Striking
# ---------------------------------------------------------------------------

func test_striking_apply_modifier_to_item_damage_dice() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("striking", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_cell"; td.target_ids = ["item_axe"]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {"item_axe": null})
	# Find the damage_bonus_dice step
	var saw_dice := false
	for s in result.effects_applied:
		var per_target: Dictionary = s.get("per_target", {})
		var entry: Dictionary = per_target.get("item_axe", {})
		if String(entry.get("item_attribute", "")) == "damage_bonus_dice":
			check(String(entry.get("value_dice", "")) == "1d6",
				"damage_bonus_dice='1d6' per RAW")
			saw_dice = true
	check(saw_dice, "Striking wrote damage_bonus_dice modifier to item")


func test_striking_strikes_as_magical() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("striking", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_cell"; td.target_ids = ["item_axe"]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {"item_axe": null})
	var saw_magical := false
	for s in result.effects_applied:
		var per_target: Dictionary = s.get("per_target", {})
		var entry: Dictionary = per_target.get("item_axe", {})
		if String(entry.get("item_attribute", "")) == "strikes_as_magical":
			saw_magical = true
	check(saw_magical, "Striking writes strikes_as_magical modifier on item")


# ---------------------------------------------------------------------------
# Water Walking
# ---------------------------------------------------------------------------

func test_water_walking_flag_with_metadata() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ally := CharacterData.new()
	ally.id = "ally_ww"; ally.hp_max = 8; ally.hp_current = 8
	var ctx := CasterContext.from_character_data(caster, "wilderness_hex", "divine", 1)
	var choice := SpellChoice.new("water_walking", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(ally.flags.has_flag("can_water_walk"),
		"Ally has can_water_walk flag")
	var entries = ally.flags.get_flag_source_entries("can_water_walk")
	var meta: Dictionary = entries[0].get("metadata", {})
	check(bool(meta.get("ends_on_swim_or_submerge", false)),
		"metadata.ends_on_swim_or_submerge=true per RAW")


func test_water_walking_movement_mode_grant() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ally := CharacterData.new()
	ally.id = "ally_ww2"; ally.hp_max = 8; ally.hp_current = 8
	var ctx := CasterContext.from_character_data(caster, "wilderness_hex", "divine", 1)
	var choice := SpellChoice.new("water_walking", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [ally.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	var saw_grant := false
	for s in result.effects_applied:
		if s.get("step_kind", "") == "movement_mode_grant":
			saw_grant = true
			break
	check(saw_grant, "Water Walking includes movement_mode_grant step")


# ---------------------------------------------------------------------------
# Direct unit tests of the new resolver step kinds
# ---------------------------------------------------------------------------

func test_remove_modifier_step_clears_by_prefix() -> void:
	# Direct call to _remove_modifier with a synthesized target.
	var target := _CurseTarget.new()
	target.id = "t_rm"
	target.modifiers.add_modifier("save_petrification", {
		"source_id": "curse:custom:abc",
		"source_type": "spell",
		"operation": "add",
		"value": -1,
		"stacking_group": "curse",
	})
	target.modifiers.add_modifier("attack_throw", {
		"source_id": "blessing:bless:xyz",  # unrelated source
		"source_type": "spell",
		"operation": "add",
		"value": 1,
		"stacking_group": "blessing",
	})
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var td := TargetDescriptor.new()
	td.target_ids = ["t_rm"]
	var step := {
		"kind": "remove_modifier",
		"source_pattern": "curse:*",
	}
	var outcome: Dictionary = harness.resolver._remove_modifier(step, td, {"t_rm": target}, ctx)
	# Curse modifier should be gone; blessing modifier should remain.
	check(not target.modifiers.has_modifier_for_stat("save_petrification"),
		"curse:* source-prefixed modifier removed")
	check(target.modifiers.has_modifier_for_stat("attack_throw"),
		"unrelated blessing:* modifier preserved")


func test_apply_modifier_to_item_records_contract() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var td := TargetDescriptor.new()
	td.target_ids = ["item_42"]
	var step := {
		"kind": "apply_modifier_to_item",
		"item_attribute": "damage_bonus_dice",
		"value_dice": "1d6",
		"stacking_group": "striking",
	}
	var choice := SpellChoice.new("striking", 3, false, -1)
	var outcome: Dictionary = harness.resolver._apply_modifier_to_item(
		step, choice, td, {"item_42": null}, ctx)
	var per_target: Dictionary = outcome.get("per_target", {})
	var entry: Dictionary = per_target.get("item_42", {})
	check(bool(entry.get("applied", false)), "contract recorded for item_42")
	check(String(entry.get("item_attribute", "")) == "damage_bonus_dice",
		"item_attribute carried through")
	check(String(entry.get("value_dice", "")) == "1d6",
		"value_dice carried through")
	check(String(entry.get("stacking_group", "")) == "striking",
		"stacking_group carried through")


# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

class _Harness extends RefCounted:
	var dice = null
	var repo = null
	var spell_registry = null
	var effect_registry = null
	var resolver = null


func _make_harness() -> _Harness:
	var h := _Harness.new()
	h.dice = _FakeDice.new()
	h.repo = _FakeRepo.new()
	h.spell_registry = SpellRegistry.new()
	h.effect_registry = SpellEffectRegistry.new(h.spell_registry)
	var tracker := ActiveEffectTracker.new()
	var cc := ConditionCatalog.new()
	var cr := CustomResolverRegistry.new()
	h.resolver = CastingResolver.new(
		h.spell_registry, h.effect_registry, tracker, cc, cr, null, h.repo, h.dice)
	return h


func _make_caster_cleric() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "cleric_l3div"; cd.name = "Test Cleric"
	cd.character_class = "cleric"; cd.combat_progression = "cleric"
	cd.level = 1; cd.wisdom = 13
	cd.hp_max = 6; cd.hp_current = 6
	return cd
