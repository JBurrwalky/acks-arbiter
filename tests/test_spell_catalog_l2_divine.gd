extends "res://tests/test_suite_base.gd"

## Session 7 — L2 divine spell binding tests + Spiritual Weapon custom resolver.
##
## Coverage:
##   - Find Traps: query_game_state detect_traps_within_range.
##   - Hold Person: paralyzed condition applied; disjunctive single (-2 save) vs group.
##   - Resist Fire: fire resistance + save_vs_fire modifier.
##   - Silence 15' Radius: modify_cell_state add_silence_aura + per-creature flag.
##   - Snake Charm: HD-budget targeting via multiple_creatures_hd_budget; applies charmed.
##   - Speak with Animals: apply_flag on caster.
##   - Spiritual Weapon (custom): damage bonus by caster level; weapon profile output.

const SpiritualWeaponResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/spiritual_weapon_resolver.gd")


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
	func increment_expended_slot(c: String, l: int) -> bool:
		if not expended.has(c): expended[c] = {}
		expended[c][l] = int(expended[c].get(l, 0)) + 1
		return true
	func reset_expended_slots(c: String) -> bool:
		expended[c] = {}; return true
	func get_expended_slots(c: String) -> Dictionary:
		return expended.get(c, {})


# Duck-typed humanoid w/ save (for Hold Person).
class _Humanoid extends RefCounted:
	var id: String = ""
	var save_petrification: int = 17
	var creature_type: String = "humanoid"
	var conditions: Array[String] = []

	func get_effective_save(key: String) -> int:
		match key:
			"save_petrification": return save_petrification
			"save_vs_fear": return 0
		return 20

	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func remove_condition(k: String) -> void: conditions.erase(k)
	func has_condition(k: String) -> bool: return k in conditions


# Snake stand-in for Snake Charm (HD-budget).
class _Snake extends RefCounted:
	var id: String = ""
	var hit_dice: int = 1
	var creature_type: String = "snake"
	var conditions: Array[String] = []

	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)


func run_all_tests() -> void:
	test_find_traps_query_game_state()
	test_hold_person_disjunctive_single_target()
	test_hold_person_disjunctive_group_branch()
	test_hold_person_save_negates_paralysis()
	test_resist_fire_resistance_and_save_modifier()
	test_silence_modify_cell_state_aura()
	test_silence_apply_flag_on_creature()
	test_snake_charm_hd_budget_target_spec()
	test_snake_charm_applies_charmed_to_each()
	test_speak_with_animals_apply_flag_on_caster()
	# Spiritual Weapon custom resolver
	test_spiritual_weapon_l1_damage_bonus_zero()
	test_spiritual_weapon_l3_damage_bonus_plus_one()
	test_spiritual_weapon_l9_damage_bonus_plus_three()
	test_spiritual_weapon_l15_damage_bonus_caps_at_plus_four()
	test_spiritual_weapon_returns_weapon_profile()
	if not has_failures():
		print("L2DivineCatalog: all tests passed.")


# ---------------------------------------------------------------------------
# Find Traps
# ---------------------------------------------------------------------------

func test_find_traps_query_game_state() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "divine", 1)
	var choice := SpellChoice.new("find_traps", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"; td.target_ids = [caster.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(result.success, "Find Traps resolves")
	var step: Dictionary = result.effects_applied[0]
	check(step.get("query_kind", "") == "detect_traps_within_range",
		"query_kind='detect_traps_within_range'")


# ---------------------------------------------------------------------------
# Hold Person
# ---------------------------------------------------------------------------

func test_hold_person_disjunctive_single_target() -> void:
	# Branch index 0 = single creature with -2 save penalty.
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var goblin := _Humanoid.new()
	goblin.id = "g1"; goblin.save_petrification = 17
	# Force save FAILURE (low roll).
	harness.dice.fixed["spell_save_paralysis_petrification"] = 5
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("hold_person", 2, false, 0)  # disjunctive_index=0
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = ["g1"]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {"g1": goblin})
	check(result.success, "Hold Person (single) resolves")
	check("paralyzed" in goblin.conditions,
		"goblin has paralyzed condition after save fail")


func test_hold_person_disjunctive_group_branch() -> void:
	# Branch index 1 = 1d4 humanoids in a group, no save modifier.
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	# Force save FAILURE for both targets.
	harness.dice.fixed["spell_save_paralysis_petrification"] = 5
	var g1 := _Humanoid.new(); g1.id = "g1"; g1.save_petrification = 17
	var g2 := _Humanoid.new(); g2.id = "g2"; g2.save_petrification = 17
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("hold_person", 2, false, 1)  # disjunctive_index=1
	var td := TargetDescriptor.new()
	td.kind = "multiple_creatures_count"; td.target_ids = ["g1", "g2"]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {"g1": g1, "g2": g2})
	check(result.success, "Hold Person (group branch) resolves")
	check("paralyzed" in g1.conditions and "paralyzed" in g2.conditions,
		"both group humanoids paralyzed on save fail")


func test_hold_person_save_negates_paralysis() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var goblin := _Humanoid.new(); goblin.id = "g1"; goblin.save_petrification = 17
	# Force save SUCCESS (high roll).
	harness.dice.fixed["spell_save_paralysis_petrification"] = 25
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("hold_person", 2, false, 0)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = ["g1"]
	harness.resolver.resolve(ctx, choice, td, caster, {"g1": goblin})
	check("paralyzed" not in goblin.conditions,
		"save success negates paralysis")


# ---------------------------------------------------------------------------
# Resist Fire
# ---------------------------------------------------------------------------

func test_resist_fire_resistance_and_save_modifier() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ally := CharacterData.new()
	ally.id = "ally_rf"; ally.hp_max = 8; ally.hp_current = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("resist_fire", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(ally.damage_resistances.get_resistance_factor("fire") < 1.0,
		"fire resistance applied (factor<1.0)")
	check(ally.modifiers.has_modifier_for_stat("save_vs_fire"),
		"save_vs_fire +2 modifier written")


# ---------------------------------------------------------------------------
# Silence 15' Radius
# ---------------------------------------------------------------------------

func test_silence_modify_cell_state_aura() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "divine", 1)
	var choice := SpellChoice.new("silence_15_radius", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(5, 5, 0)
	td.target_cells = [Vector3i(5, 5, 0)]
	td.target_ids = [caster.id]  # anchor on caster
	var result = harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	# First step is modify_cell_state with shape=add_silence_aura
	var step: Dictionary = result.effects_applied[0]
	check(step.get("shape", "") == "add_silence_aura",
		"shape='add_silence_aura', got %s" % step.get("shape", ""))
	var mutation: Dictionary = step.get("mutation", {})
	check(int(mutation.get("radius_feet", 0)) == 15,
		"silence radius 15 ft, got %d" % mutation.get("radius_feet", 0))
	check(bool(mutation.get("blocks_casting", false)),
		"blocks_casting=true (Silence prevents spell casting in area)")


func test_silence_apply_flag_on_creature() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "divine", 1)
	var choice := SpellChoice.new("silence_15_radius", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(5, 5, 0)
	td.target_ids = [caster.id]
	harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(caster.flags.has_flag("has_silence_aura"),
		"caster anchored: has_silence_aura flag set")


# ---------------------------------------------------------------------------
# Snake Charm
# ---------------------------------------------------------------------------

func test_snake_charm_hd_budget_target_spec() -> void:
	# Verify the target_spec is loaded correctly via the effect_registry
	# (HD-budget kind, fixed_formula='caster_level').
	var harness := _make_harness()
	var payload: Dictionary = harness.effect_registry.get_effect_payload("snake_charm", false, -1)
	var spec: Dictionary = payload.get("target_spec", {})
	check(spec.get("kind", "") == "multiple_creatures_hd_budget",
		"target_spec.kind = multiple_creatures_hd_budget")
	var budget: Dictionary = spec.get("hd_budget", {})
	check(String(budget.get("fixed_formula", "")) == "caster_level",
		"hd_budget.fixed_formula = caster_level")


func test_snake_charm_applies_charmed_to_each() -> void:
	# Cast Snake Charm with two snakes pre-resolved (TargetingController is
	# the production HD-budget chooser; tests bypass with a hand-built
	# TargetDescriptor).
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	caster.level = 5  # 5 HD budget for snakes
	var s1 := _Snake.new(); s1.id = "s1"; s1.hit_dice = 1
	var s2 := _Snake.new(); s2.id = "s2"; s2.hit_dice = 2
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("snake_charm", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "multiple_creatures_hd_budget"
	td.target_ids = ["s1", "s2"]
	harness.resolver.resolve(ctx, choice, td, caster, {"s1": s1, "s2": s2})
	check("charmed" in s1.conditions and "charmed" in s2.conditions,
		"all snakes get charmed condition (no save)")


# ---------------------------------------------------------------------------
# Speak with Animals
# ---------------------------------------------------------------------------

func test_speak_with_animals_apply_flag_on_caster() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "wilderness_hex", "divine", 1)
	var choice := SpellChoice.new("speak_with_animals", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [caster.id]
	harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(caster.flags.has_flag("can_speak_with_animals"),
		"caster has can_speak_with_animals flag")


# ---------------------------------------------------------------------------
# Spiritual Weapon custom resolver
# ---------------------------------------------------------------------------

func test_spiritual_weapon_l1_damage_bonus_zero() -> void:
	var resolver = SpiritualWeaponResolverScript.new()
	check(SpiritualWeaponResolverScript._compute_damage_bonus(1) == 0,
		"L1: damage bonus = +0")
	check(SpiritualWeaponResolverScript._compute_damage_bonus(2) == 0,
		"L2: damage bonus = +0")


func test_spiritual_weapon_l3_damage_bonus_plus_one() -> void:
	check(SpiritualWeaponResolverScript._compute_damage_bonus(3) == 1,
		"L3: damage bonus = +1")
	check(SpiritualWeaponResolverScript._compute_damage_bonus(5) == 1,
		"L5: damage bonus = +1")


func test_spiritual_weapon_l9_damage_bonus_plus_three() -> void:
	check(SpiritualWeaponResolverScript._compute_damage_bonus(9) == 3,
		"L9: damage bonus = +3")


func test_spiritual_weapon_l15_damage_bonus_caps_at_plus_four() -> void:
	check(SpiritualWeaponResolverScript._compute_damage_bonus(12) == 4,
		"L12: damage bonus = +4 (cap)")
	check(SpiritualWeaponResolverScript._compute_damage_bonus(15) == 4,
		"L15: damage bonus stays at +4 (cap)")
	check(SpiritualWeaponResolverScript._compute_damage_bonus(99) == 4,
		"L99: damage bonus stays at +4 (cap)")


func test_spiritual_weapon_returns_weapon_profile() -> void:
	var resolver = SpiritualWeaponResolverScript.new()
	var caster := _make_caster_cleric()
	caster.level = 6  # +2 damage bonus
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = ["enemy_sw"]
	var args := {
		"target_descriptor": td,
		"targets_by_id": {"enemy_sw": null},
		"caster_context": ctx,
		"spell_choice": SpellChoice.new("spiritual_weapon", 2, false, -1),
		"step_payload": {},
	}
	var result: Dictionary = resolver.resolve(args)
	check(bool(result.get("applied", false)), "Spiritual Weapon resolver applied")
	var profile: Dictionary = result.get("weapon_profile", {})
	check(String(profile.get("damage_expression", "")) == "1d6+2",
		"L6 damage_expression = '1d6+2', got %s" % profile.get("damage_expression", ""))
	check(int(profile.get("duration_rounds", 0)) == 6,
		"L6 duration = 6 rounds, got %d" % profile.get("duration_rounds", 0))
	check(String(profile.get("attack_strikes_as", "")) == "magical",
		"strikes as magical weapon")
	check(bool(profile.get("uses_caster_attack_throw", false)),
		"uses_caster_attack_throw=true")


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
	cr.register("spiritual_weapon", SpiritualWeaponResolverScript.new())
	h.resolver = CastingResolver.new(
		h.spell_registry, h.effect_registry, tracker, cc, cr, null, h.repo, h.dice)
	return h


func _make_caster_cleric() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "cleric_l2div"
	cd.name = "Test Cleric"
	cd.character_class = "cleric"
	cd.combat_progression = "cleric"
	cd.level = 1
	cd.wisdom = 13
	cd.hp_max = 6
	cd.hp_current = 6
	return cd
