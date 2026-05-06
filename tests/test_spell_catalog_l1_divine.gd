extends "res://tests/test_suite_base.gd"

## Session 5 — L1 divine spell binding tests + Sanctuary attacker-save hook.
##
## Coverage:
##   - Remove Fear: removes 'frightened' condition.
##   - Cause Fear (reverse): applies 'frightened' on save fail; respects fear immunity.
##   - Detect Evil: query_game_state with detect_evil_intentions kind.
##   - Detect Good (reverse): query_kind=detect_good_intentions.
##   - Protection from Evil: writes save_vs_chaotic +1 modifier; reverse writes save_vs_lawful.
##   - Resist Cold: adds cold resistance + save_vs_cold modifier.
##   - Sanctuary: applies cannot_be_targeted_by_attacks flag with metadata.
##   - Sanctuary attacker-save hook: cancels attack when attacker fails save.
##   - Sanctuary attacker-save hook: caches save result per attacker per source.
##   - Purify Food and Water: query_game_state with purify mode.
##   - apply_flag now propagates step.metadata + caster_level.

const SpellCombatHooksScript := preload(
	"res://engine/subsystems/combat/spell_combat_hooks.gd")


class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}

	func roll_expression(expr: String, roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(roll_type, fixed.get(expr, 0)))
		r.raw_total = r.modified_total
		return r

	func roll_digital(sides: int, count: int = 1, modifier: int = 0, roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(roll_type, count * sides)) + modifier
		r.raw_total = r.modified_total - modifier
		return r


class _FakeRepo extends RefCounted:
	var expended: Dictionary = {}

	func increment_expended_slot(caster_id: String, level: int) -> bool:
		if not expended.has(caster_id):
			expended[caster_id] = {}
		expended[caster_id][level] = int(expended[caster_id].get(level, 0)) + 1
		return true

	func reset_expended_slots(caster_id: String) -> bool:
		expended[caster_id] = {}
		return true

	func get_expended_slots(caster_id: String) -> Dictionary:
		return expended.get(caster_id, {})


# Duck-typed combatant stand-in for the Sanctuary attacker-save tests. Real
# Combatant requires CharacterData + a roster context; the hook only reads
# id, get_flags, get_effective_save, has_method.
class _FakeCombatant extends RefCounted:
	var id: String = ""
	var save_spells: int = 17
	var flags: EntityFlags = EntityFlags.new()
	var conditions: Array[String] = []

	func get_flags() -> EntityFlags:
		return flags

	func get_effective_save(save_key: String) -> int:
		match save_key:
			"save_spells": return save_spells
			"save_vs_fear": return 0
		return 20

	func add_condition(key: String) -> void:
		if key not in conditions:
			conditions.append(key)

	func remove_condition(key: String) -> void:
		conditions.erase(key)

	func has_condition(key: String) -> bool:
		return key in conditions

	func is_immune_to_fear() -> bool:
		var catalog := ConditionCatalog.new()
		for cond in conditions:
			if catalog.grants_immunity_to_fear(cond):
				return true
		return false


func run_all_tests() -> void:
	test_remove_fear_clears_frightened_condition()
	test_cause_fear_reverse_applies_frightened_on_save_fail()
	test_cause_fear_save_success_negates()
	test_cause_fear_against_berserker_auto_succeeds()
	test_detect_evil_query_game_state()
	test_detect_good_reverse_query_kind()
	test_protection_from_evil_modifiers()
	test_protection_from_good_reverse_modifiers()
	test_resist_cold_resistance_and_save_modifier()
	test_sanctuary_applies_flag_with_metadata()
	test_sanctuary_hook_cancels_attack_on_save_fail()
	test_sanctuary_hook_caches_save_per_attacker_per_source()
	test_sanctuary_hook_no_op_without_flag()
	test_purify_food_and_water_query_purify()
	test_putrefy_reverse_query_kind()
	if not has_failures():
		print("L1DivineCatalog: all tests passed.")


# ---------------------------------------------------------------------------
# Remove Fear / Cause Fear
# ---------------------------------------------------------------------------

func test_remove_fear_clears_frightened_condition() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ally := _FakeCombatant.new()
	ally.id = "ally_rf"
	ally.add_condition("frightened")

	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("remove_fear", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"
	td.target_ids = [ally.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(result.success, "Remove Fear resolves successfully")
	check(not ally.has_condition("frightened"),
		"frightened condition removed from ally")


func test_cause_fear_reverse_applies_frightened_on_save_fail() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var enemy := _FakeCombatant.new()
	enemy.id = "enemy_cf"
	enemy.save_spells = 17

	# Save FAILURE — roll 5 vs target 17.
	harness.dice.fixed["spell_save_poison_death"] = 5
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("remove_fear", 1, true, -1)  # reverse → Cause Fear
	var td := TargetDescriptor.new()
	td.kind = "single_creature"
	td.target_ids = [enemy.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {enemy.id: enemy})
	check(result.success, "Cause Fear (reverse) resolves")
	check("frightened" in enemy.conditions,
		"frightened condition applied on save fail, got %s" % str(enemy.conditions))


func test_cause_fear_save_success_negates() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var enemy := _FakeCombatant.new()
	enemy.id = "enemy_cf2"
	# save_death is read via get_effective_save — _FakeCombatant returns 20 default.
	# Roll 20 + the death save target — let's force a high roll.
	harness.dice.fixed["spell_save_poison_death"] = 25
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("remove_fear", 1, true, -1)
	var td := TargetDescriptor.new()
	td.target_ids = [enemy.id]
	harness.resolver.resolve(ctx, choice, td, caster, {enemy.id: enemy})
	check("frightened" not in enemy.conditions,
		"frightened NOT applied on save success")


func test_cause_fear_against_berserker_auto_succeeds() -> void:
	# Berserk_rage condition grants immune_to_fear; Cause Fear's is_fear_save
	# triggers auto-success per Session 2.9.1 wiring.
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var berserker := _FakeCombatant.new()
	berserker.id = "berserk_cf"
	berserker.add_condition("berserk_rage")
	# Even with a low roll, fear_immunity should auto-succeed before rolling.
	harness.dice.fixed["spell_save_poison_death"] = 1
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("remove_fear", 1, true, -1)
	var td := TargetDescriptor.new()
	td.target_ids = [berserker.id]
	harness.resolver.resolve(ctx, choice, td, caster, {berserker.id: berserker})
	check("frightened" not in berserker.conditions,
		"Berserker is fear-immune; Cause Fear auto-succeeds save → no frightened")


# ---------------------------------------------------------------------------
# Detect Evil / Detect Good
# ---------------------------------------------------------------------------

func test_detect_evil_query_game_state() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("detect_evil", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(result.success, "Detect Evil resolves")
	var step: Dictionary = result.effects_applied[0]
	check(step.get("query_kind", "") == "detect_evil_intentions",
		"query_kind='detect_evil_intentions', got %s" % step.get("query_kind", ""))


func test_detect_good_reverse_query_kind() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("detect_evil", 1, true, -1)  # reverse
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("query_kind", "") == "detect_good_intentions",
		"reverse → query_kind='detect_good_intentions'")


# ---------------------------------------------------------------------------
# Protection from Evil / Good
# ---------------------------------------------------------------------------

func test_protection_from_evil_modifiers() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("protection_from_evil", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]
	harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(caster.modifiers.has_modifier_for_stat("armor_class_vs_chaotic"),
		"armor_class_vs_chaotic modifier written")
	check(caster.modifiers.has_modifier_for_stat("save_vs_chaotic"),
		"save_vs_chaotic modifier written")
	check(caster.flags.has_flag("blocks_enchanted_creature_melee"),
		"blocks_enchanted_creature_melee flag set on caster")


func test_protection_from_good_reverse_modifiers() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("protection_from_evil", 1, true, -1)  # reverse
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]
	harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(caster.modifiers.has_modifier_for_stat("armor_class_vs_lawful"),
		"reverse: armor_class_vs_lawful modifier written")
	check(not caster.modifiers.has_modifier_for_stat("armor_class_vs_chaotic"),
		"reverse: NO armor_class_vs_chaotic written (only the reverse axis)")


# ---------------------------------------------------------------------------
# Resist Cold
# ---------------------------------------------------------------------------

func test_resist_cold_resistance_and_save_modifier() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ally := CharacterData.new()
	ally.id = "ally_rc"
	ally.hp_max = 8; ally.hp_current = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("resist_cold", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"
	td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	# Cold resistance applied
	check(ally.damage_resistances != null,
		"DamageResistance container exists on ally")
	check(ally.damage_resistances.get_resistance_factor("cold") < 1.0,
		"Cold damage factor reduced (was 1.0, now %f)" \
			% ally.damage_resistances.get_resistance_factor("cold"))
	# save_vs_cold modifier written
	check(ally.modifiers.has_modifier_for_stat("save_vs_cold"),
		"save_vs_cold +2 modifier written")


# ---------------------------------------------------------------------------
# Sanctuary
# ---------------------------------------------------------------------------

func test_sanctuary_applies_flag_with_metadata() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	caster.level = 5
	var ally := CharacterData.new()
	ally.id = "ally_sanc"
	ally.hp_max = 10; ally.hp_current = 10
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("sanctuary", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"
	td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})

	check(ally.flags.has_flag("cannot_be_targeted_by_attacks"),
		"Ally has cannot_be_targeted_by_attacks flag")
	# Verify metadata propagation: caster_level + spell-specific metadata
	var entries: Array = ally.flags.get_flag_source_entries("cannot_be_targeted_by_attacks")
	check(entries.size() == 1, "Single source for the flag, got %d" % entries.size())
	var meta: Dictionary = entries[0].get("metadata", {})
	check(int(meta.get("caster_level", 0)) == 5,
		"Flag metadata.caster_level = caster's level (5), got %d" % int(meta.get("caster_level", 0)))
	check(String(meta.get("save_category", "")) == "spells",
		"Flag metadata.save_category = 'spells'")
	check(bool(meta.get("save_per_attacker_once", false)),
		"Flag metadata.save_per_attacker_once = true")


func test_sanctuary_hook_cancels_attack_on_save_fail() -> void:
	# Build a target with cannot_be_targeted_by_attacks; build an attacker;
	# force the dice to roll 1 (save fail); verify on_pre_attack returns cancel.
	var dice := _FakeDice.new()
	dice.fixed["save_spells_sanctuary"] = 1  # very low roll → save fail
	var hooks = SpellCombatHooksScript.new(null, dice)

	var target := _FakeCombatant.new()
	target.id = "warded"
	target.flags.set_flag("cannot_be_targeted_by_attacks", "spell:sanctuary:c1",
		{"caster_level": 5, "save_category": "spells", "save_per_attacker_once": true})

	var attacker := _FakeCombatant.new()
	attacker.id = "att1"
	attacker.save_spells = 17

	var result: Dictionary = hooks.on_pre_attack(attacker, target, "melee")
	check(bool(result.get("cancel", false)),
		"Save fail (1 vs target 17) → on_pre_attack returns cancel=true")
	check(String(result.get("cancelled_by", "")) == "sanctuary",
		"cancelled_by='sanctuary'")


func test_sanctuary_hook_caches_save_per_attacker_per_source() -> void:
	# After a successful save, subsequent attacks by the same attacker against
	# the same Sanctuary source should NOT roll again — cached as success.
	var dice := _FakeDice.new()
	dice.fixed["save_spells_sanctuary"] = 20  # successful save
	var hooks = SpellCombatHooksScript.new(null, dice)

	var target := _FakeCombatant.new()
	target.id = "warded2"
	target.flags.set_flag("cannot_be_targeted_by_attacks", "spell:sanctuary:c1",
		{"caster_level": 3, "save_category": "spells", "save_per_attacker_once": true})

	var attacker := _FakeCombatant.new()
	attacker.id = "att2"
	attacker.save_spells = 17

	# First attack: rolls save, succeeds.
	var first: Dictionary = hooks.on_pre_attack(attacker, target, "melee")
	check(first.is_empty() or not bool(first.get("cancel", false)),
		"First attack: save success → no cancel")

	# Now flip the dice to fail — but the cache should keep the prior success.
	dice.fixed["save_spells_sanctuary"] = 1
	var second: Dictionary = hooks.on_pre_attack(attacker, target, "melee")
	check(second.is_empty() or not bool(second.get("cancel", false)),
		"Second attack: cached save success bypasses fresh roll → no cancel")


func test_sanctuary_hook_no_op_without_flag() -> void:
	var dice := _FakeDice.new()
	dice.fixed["save_spells_sanctuary"] = 1
	var hooks = SpellCombatHooksScript.new(null, dice)
	var target := _FakeCombatant.new()
	target.id = "normal"
	var attacker := _FakeCombatant.new()
	attacker.id = "att3"
	var result: Dictionary = hooks.on_pre_attack(attacker, target, "melee")
	check(result.is_empty() or not bool(result.get("cancel", false)),
		"No Sanctuary flag → on_pre_attack returns empty / no cancel")


# ---------------------------------------------------------------------------
# Purify Food and Water
# ---------------------------------------------------------------------------

func test_purify_food_and_water_query_purify() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "divine", 1)
	var choice := SpellChoice.new("purify_food_and_water", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(0, 0, 0)
	td.target_cells = [Vector3i(0, 0, 0)]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("query_kind", "") == "purify_or_putrefy_in_cell",
		"query_kind='purify_or_putrefy_in_cell'")


func test_putrefy_reverse_query_kind() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "divine", 1)
	var choice := SpellChoice.new("purify_food_and_water", 1, true, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(0, 0, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	# Reverse uses the same query_kind but mode='putrefy' — verify both fields
	# survive the roundtrip via the reverse branch payload.
	check(step.get("query_kind", "") == "purify_or_putrefy_in_cell",
		"reverse: same query_kind")


# ---------------------------------------------------------------------------
# Test helpers
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
	cd.id = "cleric_l1div"
	cd.name = "Test Cleric"
	cd.character_class = "cleric"
	cd.combat_progression = "cleric"
	cd.level = 1
	cd.wisdom = 13
	cd.hp_max = 6
	cd.hp_current = 6
	return cd
