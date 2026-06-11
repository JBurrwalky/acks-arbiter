extends "res://tests/test_suite_base.gd"

## Unit tests for CastingResolver — the deterministic spell resolution
## pipeline. Covers all 8 MVP spells (Magic Missile, Fireball, Sleep, Cure
## Light Wounds, Bless, Shield, Fly, Detect Magic), validation failures,
## reverse-form dispatch, slot expenditure, and disrupted-cast slot
## consumption.


# Fake DiceSystem that always returns a fixed value per roll_type. Lets
# multi-roll resolution steps (Magic Missile, Fireball) be deterministic
# without queueing one override per roll. Override values are persistent
# until cleared via clear_fixed().
class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}  # roll_type -> int

	func set_fixed(roll_type: String, value: int) -> void:
		fixed[roll_type] = value

	func clear_fixed() -> void:
		fixed.clear()

	func roll_expression(expression: String, roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.roll_type = roll_type
		r.modified_total = int(fixed.get(roll_type, 0))
		r.raw_total = r.modified_total
		return r

	func roll_digital(sides: int, count: int = 1, modifier: int = 0, roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.roll_type = roll_type
		r.sides = sides
		r.count = count
		r.modifier = modifier
		r.modified_total = int(fixed.get(roll_type, count * sides))
		r.raw_total = r.modified_total - modifier
		return r


# Fake CampaignRepository tracking expended slots per (caster_id, level).
class _FakeRepo extends RefCounted:
	var expended: Dictionary = {}  # caster_id -> { level: count }

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


var _repo = null     # _FakeRepo
var _dice = null     # _FakeDice
var _spell_registry: SpellRegistry = null
var _effect_registry: SpellEffectRegistry = null
var _effect_tracker: ActiveEffectTracker = null
var _condition_catalog: ConditionCatalog = null
var _custom_resolvers: CustomResolverRegistry = null
var _resolver: CastingResolver = null


func _build_resolver() -> void:
	_repo = _FakeRepo.new()
	_dice = _FakeDice.new()
	_spell_registry = SpellRegistry.new()
	_effect_registry = SpellEffectRegistry.new(_spell_registry)
	_effect_tracker = ActiveEffectTracker.new()
	_condition_catalog = ConditionCatalog.new()
	_custom_resolvers = CustomResolverRegistry.new()
	_resolver = CastingResolver.new(
		_spell_registry,
		_effect_registry,
		_effect_tracker,
		_condition_catalog,
		_custom_resolvers,
		null,  # geometry — uses static class methods
		_repo,
		_dice)


func _make_caster(id: String, level: int, klass: String = "mage", tradition: String = "arcane") -> CharacterData:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = "Test " + id
	cd.character_class = klass
	cd.level = level
	cd.hp_max = 20
	cd.hp_current = 20
	return cd


func _make_caster_context(caster: CharacterData, tradition: String = "arcane") -> CasterContext:
	return CasterContext.from_character_data(caster, "combat_grid", tradition, 0)


func _make_target(id: String, hp: int = 8, level: int = 1) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = "Target " + id
	cd.level = level
	cd.hp_max = hp
	cd.hp_current = hp
	return cd


func run_all_tests() -> void:
	test_unknown_spell_key_fails_no_slot()
	test_spell_without_effect_fails_no_slot()
	test_disjunctive_with_default_index_fails_no_slot()
	test_reversible_forward_branch_heals()
	test_reversible_reverse_branch_attacks()
	test_disrupted_cast_consumes_slot()
	test_magic_missile_l1_one_missile()
	test_magic_missile_l5_one_missile()
	test_magic_missile_l6_three_missiles()
	test_magic_missile_l11_five_missiles()
	test_fireball_l5_damages_cluster()
	test_sleep_group_branch_dud_roll()
	test_bless_writes_three_modifiers()
	test_shield_uses_set_floor_for_directional_ac()
	test_fly_grants_flag_and_movement()
	test_detect_magic_returns_query_result()
	test_active_effect_registered_for_durational_spell()
	test_active_effect_not_registered_for_instantaneous()
	test_slot_expended_signal_fires()
	test_e2e_smoke_magic_missile_then_rest_resets()
	# Tier 4 Charm side-flip follow-up (2026-06-01) — new flip_to_caster_team
	# effect step kind. Verifies the step flips target.side on failed save
	# (charm_person resolution chain), no-ops on successful save, and the
	# cleanup callback reverts side on dispel/expiry.
	test_flip_to_caster_team_flips_side_on_failed_save()
	test_flip_to_caster_team_skips_save_success()
	test_flip_to_caster_team_no_ops_when_caster_has_no_side()
	test_flip_to_caster_team_no_ops_when_target_has_no_side()
	test_flip_to_caster_team_no_ops_when_already_on_caster_side()
	test_charm_side_flip_reverts_on_unwind()
	test_warlock_effective_caster_level()
	if not has_failures():
		print("CastingResolver: all tests passed.")


# Validation failures -------------------------------------------------------

func test_unknown_spell_key_fails_no_slot() -> void:
	_build_resolver()
	var caster := _make_caster("c1", 5)
	var ctx := _make_caster_context(caster)
	var choice := SpellChoice.new("not_a_real_spell", 1)
	var target := TargetDescriptor.new()
	var result := _resolver.resolve(ctx, choice, target, caster, {})
	check(not result.success, "Unknown spell: success should be false")
	check(not result.slot_consumed, "Unknown spell: slot should NOT be consumed")
	check(_repo.get_expended_slots("c1").get(1, 0) == 0,
		"Unknown spell: no slot increment recorded")


func test_spell_without_effect_fails_no_slot() -> void:
	_build_resolver()
	# Pick a spell that's in the catalog but has no `effect` field yet.
	# After Sessions 4-14 bind through L6 arcane / L5 divine, `adaptation`
	# (L5 arcane environmental-survival shell) remains unbound — a true
	# late-tier spell awaiting its dedicated session.
	var caster := _make_caster("c2", 5)
	var ctx := _make_caster_context(caster)
	var choice := SpellChoice.new("adaptation", 5)
	var target := TargetDescriptor.new()
	var result := _resolver.resolve(ctx, choice, target, caster, {})
	check(not result.success, "Unimplemented spell: success false")
	check(not result.slot_consumed, "Unimplemented spell: no slot consumed")


func test_disjunctive_with_default_index_fails_no_slot() -> void:
	_build_resolver()
	var caster := _make_caster("c3", 5)
	var ctx := _make_caster_context(caster)
	var choice := SpellChoice.new("sleep", 1, false, -1)  # disjunctive_index = -1
	var target := TargetDescriptor.new()
	var result := _resolver.resolve(ctx, choice, target, caster, {})
	check(not result.success, "Sleep with index=-1: success false")
	check(not result.slot_consumed, "Sleep with index=-1: no slot consumed")
	check("disjunctive branch not chosen" in str(result.failures),
		"Sleep with index=-1: failure mentions branch")


# Reversibles ---------------------------------------------------------------

func test_reversible_forward_branch_heals() -> void:
	_build_resolver()
	_dice.set_fixed("spell_healing", 5)  # 1d6+1 = 5
	var caster := _make_caster("cleric_1", 1, "cleric", "divine")
	var ctx := _make_caster_context(caster, "divine")
	var ally := _make_target("ally_1", 10)
	ally.hp_current = 4  # damaged
	var choice := SpellChoice.new("cure_light_wounds", 1, false, -1)
	var target := TargetDescriptor.new()
	target.kind = "touch_ally"
	target.target_ids = ["ally_1"]
	var result := _resolver.resolve(ctx, choice, target, caster, {"ally_1": ally})
	check(result.success, "CLW forward: success")
	check(ally.hp_current == 9, "CLW forward: ally healed from 4 to 9, got %d" % ally.hp_current)


func test_reversible_reverse_branch_attacks() -> void:
	_build_resolver()
	# Force attack roll high; force damage 5.
	_dice.set_fixed("spell_attack_throw", 20)
	_dice.set_fixed("spell_damage", 5)
	var caster := _make_caster("cleric_2", 1, "cleric", "divine")
	var ctx := _make_caster_context(caster, "divine")
	var enemy := _make_target("enemy_1", 10, 1)
	var choice := SpellChoice.new("cure_light_wounds", 1, true, -1)  # is_reversed
	var target := TargetDescriptor.new()
	target.kind = "touch_enemy"
	target.target_ids = ["enemy_1"]
	var result := _resolver.resolve(ctx, choice, target, caster, {"enemy_1": enemy})
	check(result.success, "CLW reverse: success")
	check(enemy.hp_current == 5, "CLW reverse: enemy hit for 5, got hp=%d" % enemy.hp_current)


# Disrupted cast ------------------------------------------------------------

func test_disrupted_cast_consumes_slot() -> void:
	_build_resolver()
	var slot_emitted := []
	var cb := func(cid, lvl, _rem): slot_emitted.append([cid, lvl])
	EventBus.spell_slot_expended.connect(cb)

	var caster := _make_caster("disrupted_caster", 3)
	var ctx := _make_caster_context(caster)
	var choice := SpellChoice.new("magic_missile", 1)
	var result := _resolver.resolve_disrupted(ctx, choice, "damage")

	check(not result.success, "Disrupted: success false")
	check(result.disrupted, "Disrupted: disrupted flag true")
	check(result.slot_consumed, "Disrupted: slot consumed (ACKS rule)")
	check(_repo.get_expended_slots("disrupted_caster").get(1, 0) == 1,
		"Disrupted: slot increment recorded")
	check(slot_emitted.size() == 1,
		"Disrupted: spell_slot_expended emitted once")

	EventBus.spell_slot_expended.disconnect(cb)


# Magic Missile -------------------------------------------------------------

func _cast_magic_missile_at_level(caster_level: int, dmg_per_missile: int) -> CharacterData:
	_build_resolver()
	_dice.set_fixed("spell_damage", dmg_per_missile)
	var caster := _make_caster("mage_mm", caster_level)
	var ctx := _make_caster_context(caster)
	var goblin := _make_target("goblin_mm", 50, 1)
	var choice := SpellChoice.new("magic_missile", 1)
	var target := TargetDescriptor.new()
	target.kind = "single_creature"
	target.target_ids = ["goblin_mm"]
	var _result := _resolver.resolve(ctx, choice, target, caster, {"goblin_mm": goblin})
	return goblin


func test_magic_missile_l1_one_missile() -> void:
	# Override 1d6+1 to 5 per missile; L1 fires 1 missile → 5 damage.
	var goblin := _cast_magic_missile_at_level(1, 5)
	check(goblin.hp_current == 45,
		"Magic Missile L1: 1 missile of 5 dmg → 45 hp left, got %d" % goblin.hp_current)


func test_magic_missile_l5_one_missile() -> void:
	# RAW: L5 still fires 1 missile (the +2 kicks in at level 6, not 5).
	var goblin := _cast_magic_missile_at_level(5, 5)
	check(goblin.hp_current == 45,
		"Magic Missile L5: 1 missile (RAW: +2 every 5 beyond 1st), got hp=%d" % goblin.hp_current)


func test_magic_missile_l6_three_missiles() -> void:
	var goblin := _cast_magic_missile_at_level(6, 5)
	check(goblin.hp_current == 35,
		"Magic Missile L6: 3 missiles × 5 = 15 → 35 hp left, got %d" % goblin.hp_current)


func test_magic_missile_l11_five_missiles() -> void:
	var goblin := _cast_magic_missile_at_level(11, 5)
	check(goblin.hp_current == 25,
		"Magic Missile L11: 5 missiles × 5 = 25 → 25 hp left, got %d" % goblin.hp_current)


# Fireball ------------------------------------------------------------------

func test_fireball_l5_damages_cluster() -> void:
	_build_resolver()
	# Each 1d6 → 4; L5 caster → 5 dice = 20 damage per target. No save => full.
	_dice.set_fixed("spell_damage", 4)
	var caster := _make_caster("fireball_caster", 5)
	var ctx := _make_caster_context(caster)
	var g1 := _make_target("g1", 30, 1)
	var g2 := _make_target("g2", 30, 1)
	var g3 := _make_target("g3", 30, 1)
	var choice := SpellChoice.new("fireball", 3)
	var target := TargetDescriptor.new()
	target.kind = "area_at_point"
	target.target_ids = ["g1", "g2", "g3"]
	# Force save to fail: target 16 vs roll 1.
	_dice.set_fixed("spell_save_blast", 1)
	var result := _resolver.resolve(ctx, choice, target, caster, {"g1": g1, "g2": g2, "g3": g3})
	check(result.success, "Fireball: success")
	check(g1.hp_current == 10 and g2.hp_current == 10 and g3.hp_current == 10,
		"Fireball L5 no save: each goblin takes 5×4=20 damage, hp left g1=%d g2=%d g3=%d" % [g1.hp_current, g2.hp_current, g3.hp_current])


# Sleep ---------------------------------------------------------------------

func test_sleep_group_branch_dud_roll() -> void:
	_build_resolver()
	# Pick group branch (index=1). Sleep applies sleeping condition.
	# We don't fully simulate the HD-budget walk in Session 1 (no targeting
	# controller), but the resolver should at least apply the condition to
	# every target listed in the descriptor and not crash.
	var caster := _make_caster("sleep_caster", 1)
	var ctx := _make_caster_context(caster)
	var g1 := _make_target("sleep_g1", 4, 1)
	var g2 := _make_target("sleep_g2", 4, 1)
	var choice := SpellChoice.new("sleep", 1, false, 1)  # group branch
	var target := TargetDescriptor.new()
	target.kind = "multiple_creatures_hd_budget"
	target.target_ids = ["sleep_g1", "sleep_g2"]
	var emitted: Array = []
	var cb := func(cid, change): emitted.append([cid, change.get("condition", "")])
	EventBus.condition_changed.connect(cb)
	var result := _resolver.resolve(ctx, choice, target, caster, {"sleep_g1": g1, "sleep_g2": g2})
	EventBus.condition_changed.disconnect(cb)
	check(result.success, "Sleep group: success")
	check(emitted.size() == 2,
		"Sleep group: condition_changed fires for each target, got %d" % emitted.size())
	check(emitted[0][1] == "sleeping" and emitted[1][1] == "sleeping",
		"Sleep group: sleeping condition applied to all targets")


# Bless ---------------------------------------------------------------------

func test_bless_writes_three_modifiers() -> void:
	_build_resolver()
	var caster := _make_caster("cleric_b", 3, "cleric", "divine")
	var ctx := _make_caster_context(caster, "divine")
	var ally := _make_target("ally_b", 10, 2)
	var choice := SpellChoice.new("bless", 2, false, -1)
	var target := TargetDescriptor.new()
	target.kind = "area_from_caster"
	target.target_ids = ["ally_b"]
	var result := _resolver.resolve(ctx, choice, target, caster, {"ally_b": ally})
	check(result.success, "Bless: success")
	# Verify three modifiers landed on the ally.
	check(ally.modifiers.has_modifier_for_stat("attack_throw"),
		"Bless: attack_throw modifier added")
	check(ally.modifiers.has_modifier_for_stat("damage_bonus"),
		"Bless: damage_bonus modifier added")
	check(ally.modifiers.has_modifier_for_stat("morale_modifier"),
		"Bless: morale_modifier added")
	# Verify effective values.
	check(ally.modifiers.get_effective_value("attack_throw", 10) == 11,
		"Bless: attack_throw +1 effective, got %d" % ally.modifiers.get_effective_value("attack_throw", 10))


# Shield --------------------------------------------------------------------

func test_shield_uses_set_floor_for_directional_ac() -> void:
	_build_resolver()
	var caster := _make_caster("mage_shield", 1)
	var ctx := _make_caster_context(caster)
	var choice := SpellChoice.new("shield", 1)
	var target := TargetDescriptor.new()
	target.kind = "self"
	target.target_ids = ["mage_shield"]
	var result := _resolver.resolve(ctx, choice, target, caster, {"mage_shield": caster})
	check(result.success, "Shield: success")
	# Base AC 0, set_floor 2 missiles, set_floor 4 melee. ACKS ascending AC.
	check(caster.modifiers.get_effective_value("armor_class_vs_missiles", 0) == 2,
		"Shield: AC vs missiles set_floor to 2, got %d" % caster.modifiers.get_effective_value("armor_class_vs_missiles", 0))
	check(caster.modifiers.get_effective_value("armor_class_vs_melee", 0) == 4,
		"Shield: AC vs melee set_floor to 4, got %d" % caster.modifiers.get_effective_value("armor_class_vs_melee", 0))
	# A higher base should NOT degrade with set_floor.
	check(caster.modifiers.get_effective_value("armor_class_vs_melee", 6) == 6,
		"Shield: set_floor doesn't degrade better base AC")


# Fly -----------------------------------------------------------------------

func test_fly_grants_flag_and_movement() -> void:
	_build_resolver()
	var caster := _make_caster("fly_caster", 5)
	var ctx := _make_caster_context(caster)
	var subject := _make_target("flyer", 10, 1)
	var choice := SpellChoice.new("fly", 3)
	var target := TargetDescriptor.new()
	target.kind = "touch_creature"
	target.target_ids = ["flyer"]
	var result := _resolver.resolve(ctx, choice, target, caster, {"flyer": subject})
	check(result.success, "Fly: success")
	check(subject.flags.has_flag("can_fly"),
		"Fly: can_fly flag set on subject")
	check(result.active_effect_ids.size() == 1,
		"Fly: active_effect created for durational spell")
	# Duration: per_level × caster_level = 5 turns.
	var aef := _effect_tracker.get_effect(result.active_effect_ids[0])
	check(int(aef.get("duration_remaining", 0)) == 5,
		"Fly: L5 caster duration = 5 turns, got %d" % aef.get("duration_remaining", 0))


# Detect Magic --------------------------------------------------------------

func test_detect_magic_returns_query_result() -> void:
	_build_resolver()
	var caster := _make_caster("dm_caster", 1)
	var ctx := _make_caster_context(caster)
	var choice := SpellChoice.new("detect_magic", 1)
	var target := TargetDescriptor.new()
	target.kind = "caster_and_radius"
	target.target_ids = []
	var result := _resolver.resolve(ctx, choice, target, caster, {})
	check(result.success, "Detect Magic: success")
	check(result.effects_applied.size() == 1, "Detect Magic: one effect step")
	check(result.effects_applied[0].get("query_kind", "") == "detect_magical_auras",
		"Detect Magic: query_kind populated")


# Active effect lifecycle ---------------------------------------------------

func test_active_effect_registered_for_durational_spell() -> void:
	_build_resolver()
	var caster := _make_caster("bless_l3", 3, "cleric", "divine")
	var ctx := _make_caster_context(caster, "divine")
	var ally := _make_target("bless_ally", 10, 1)
	var choice := SpellChoice.new("bless", 2, false, -1)
	var target := TargetDescriptor.new()
	target.target_ids = ["bless_ally"]
	var result := _resolver.resolve(ctx, choice, target, caster, {"bless_ally": ally})
	check(result.active_effect_ids.size() == 1, "Bless: one active_effect created")
	var aef := _effect_tracker.get_effect(result.active_effect_ids[0])
	check(aef.get("spell_key", "") == "bless", "Bless: active_effect spell_key correct")
	check(int(aef.get("duration_remaining", 0)) == 6,
		"Bless: 6 turns duration, got %d" % aef.get("duration_remaining", 0))


func test_active_effect_not_registered_for_instantaneous() -> void:
	_build_resolver()
	_dice.set_fixed("spell_damage", 4)
	var caster := _make_caster("mm_caster", 1)
	var ctx := _make_caster_context(caster)
	var goblin := _make_target("g_inst", 30, 1)
	var choice := SpellChoice.new("magic_missile", 1)
	var target := TargetDescriptor.new()
	target.target_ids = ["g_inst"]
	var result := _resolver.resolve(ctx, choice, target, caster, {"g_inst": goblin})
	check(result.success, "Magic Missile: success")
	check(result.active_effect_ids.is_empty(),
		"Magic Missile: instantaneous, no active_effect created")


func test_slot_expended_signal_fires() -> void:
	_build_resolver()
	_dice.set_fixed("spell_damage", 5)
	var emitted := []
	var cb := func(cid, lvl, _rem): emitted.append([cid, lvl])
	EventBus.spell_slot_expended.connect(cb)
	var caster := _make_caster("signal_caster", 1)
	var ctx := _make_caster_context(caster)
	var goblin := _make_target("g_sig", 30, 1)
	var choice := SpellChoice.new("magic_missile", 1)
	var target := TargetDescriptor.new()
	target.target_ids = ["g_sig"]
	var _result := _resolver.resolve(ctx, choice, target, caster, {"g_sig": goblin})
	EventBus.spell_slot_expended.disconnect(cb)
	check(emitted.size() == 1, "spell_slot_expended emitted once")
	check(emitted[0][0] == "signal_caster" and emitted[0][1] == 1,
		"spell_slot_expended payload: caster_id and level")


# End-to-end ----------------------------------------------------------------

func test_e2e_smoke_magic_missile_then_rest_resets() -> void:
	# GDD §18.1 acceptance: cast Magic Missile, slot consumed, then full rest
	# resets all party slots. Combines resolver + slot reset handler.
	_build_resolver()
	_dice.set_fixed("spell_damage", 5)
	var caster := _make_caster("smoke_mage", 5)
	var ctx := _make_caster_context(caster)
	var goblin := _make_target("smoke_g", 30, 1)
	var choice := SpellChoice.new("magic_missile", 1)
	var target := TargetDescriptor.new()
	target.target_ids = ["smoke_g"]
	var result := _resolver.resolve(ctx, choice, target, caster, {"smoke_g": goblin})
	check(result.success, "E2E: cast succeeded")
	check(_repo.get_expended_slots("smoke_mage").get(1, 0) == 1,
		"E2E: 1 L1 slot expended after cast")

	var lookup := func() -> Array: return [caster]
	var handler := SpellSlotResetHandler.new(_repo, lookup)
	EventBus.rest_taken.emit(12)
	check(_repo.get_expended_slots("smoke_mage").get(1, 0) == 0,
		"E2E: full rest (12h) reset L1 slot to 0")
	handler.dispose()


# ---------------------------------------------------------------------------
# Tier 4 follow-up (2026-06-01) — Charm side-flip via flip_to_caster_team
# effect step. Charm spells (charm_person + charm_monster) now flip target
# Combatant.side to the caster's side; cleanup reverts on dispel/expiry.
# ---------------------------------------------------------------------------

## A test stub that exposes the minimal surface flip_to_caster_team reads:
## `side` (mutable int) + `flags` (EntityFlags) + `add_condition` /
## `has_condition` methods. Used in place of a full Combatant for unit
## tests so we don't have to spin up the combat roster + roster lookup.
class _SidedTarget extends RefCounted:
	var id: String = ""
	var name: String = "Sided Target"
	var side: int = 1  # default ENEMY side (the target being charmed)
	var flags: EntityFlags = EntityFlags.new()
	var creature_type: String = "humanoid"
	var save_spells: int = 17
	var hit_dice: int = 1
	var _conditions: Array[String] = []

	func get_effective_save(save_key: String) -> int:
		match save_key:
			"save_spells": return save_spells
			_: return 20

	func add_condition(key: String) -> void:
		if key not in _conditions:
			_conditions.append(key)

	func has_condition(key: String) -> bool:
		return key in _conditions


## A test stub that wraps a CharacterData-like surface plus the `side`
## property the flip step needs to read on the caster. Used as the
## caster_entity in side-flip tests.
class _SidedCaster extends RefCounted:
	var id: String = "sided_caster"
	var name: String = "Sided Caster"
	var side: int = 0  # PARTY side


func test_flip_to_caster_team_flips_side_on_failed_save() -> void:
	# Charm Person: failed save → charmed condition applied AND target
	# side flips to caster's side. Test specifies a caster on PARTY side
	# (side=0) charming an ENEMY-side target (side=1) → target.side
	# becomes 0.
	_build_resolver()
	var caster := _make_caster("sided_charm_caster", 1)
	var ctx := _make_caster_context(caster)
	var target := _SidedTarget.new()
	target.id = "sided_target_a"
	target.side = 1
	target.save_spells = 17

	# Use a caster wrapper that exposes a side property; the resolver's
	# caster_entity argument is what _flip_to_caster_team reads.
	var caster_proxy := _SidedCaster.new()
	caster_proxy.id = caster.id
	caster_proxy.side = 0  # PARTY

	# Force save FAILURE: dice fixed to 5 vs target 17.
	_dice.set_fixed("spell_save_spells", 5)
	var choice := SpellChoice.new("charm_person", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"
	td.target_ids = [target.id]
	var result := _resolver.resolve(ctx, choice, td, caster_proxy, {target.id: target})
	check(result.success, "Charm Person resolves successfully")
	check(target.has_condition("charmed"),
		"target gains charmed condition on failed save")
	check(target.side == 0,
		"target's side should flip to caster's side (0=PARTY); got %d" % target.side)


func test_flip_to_caster_team_skips_save_success() -> void:
	# Charm Person: successful save → no charmed condition AND no side flip.
	_build_resolver()
	var caster := _make_caster("sided_charm_save_caster", 1)
	var ctx := _make_caster_context(caster)
	var target := _SidedTarget.new()
	target.id = "sided_target_b"
	target.side = 1
	target.save_spells = 17
	var caster_proxy := _SidedCaster.new()
	caster_proxy.id = caster.id
	caster_proxy.side = 0

	# Force save SUCCESS: dice fixed to 20 vs target 17 → passes.
	_dice.set_fixed("spell_save_spells", 20)
	var choice := SpellChoice.new("charm_person", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"
	td.target_ids = [target.id]
	_resolver.resolve(ctx, choice, td, caster_proxy, {target.id: target})
	check(not target.has_condition("charmed"),
		"saved target does NOT gain charmed condition")
	check(target.side == 1,
		"saved target keeps original side 1; got %d" % target.side)


func test_flip_to_caster_team_no_ops_when_caster_has_no_side() -> void:
	# If the caster_entity doesn't have a `.side` property (e.g., an
	# out-of-combat CharacterData), the step no-ops gracefully — the
	# condition still applies but no side flip is attempted.
	_build_resolver()
	var caster := _make_caster("no_side_caster", 1)
	var ctx := _make_caster_context(caster)
	var target := _SidedTarget.new()
	target.id = "sided_target_c"
	target.side = 1
	target.save_spells = 17
	# Pass the bare CharacterData as caster_entity (no .side property).
	_dice.set_fixed("spell_save_spells", 5)
	var choice := SpellChoice.new("charm_person", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"
	td.target_ids = [target.id]
	_resolver.resolve(ctx, choice, td, caster, {target.id: target})
	check(target.has_condition("charmed"),
		"condition still applied even when side flip is skipped")
	check(target.side == 1,
		"target side unchanged when caster has no side property; got %d" % target.side)


func test_flip_to_caster_team_no_ops_when_target_has_no_side() -> void:
	# If the target lacks a `.side` property (e.g., a bare CharacterData),
	# the step no-ops gracefully for that target. Reuses the existing
	# _Humanoid test stub which has no side property.
	_build_resolver()
	var caster := _make_caster("no_target_side_caster", 1)
	var ctx := _make_caster_context(caster)
	var caster_proxy := _SidedCaster.new()
	caster_proxy.id = caster.id
	caster_proxy.side = 0
	var target := _make_target("no_side_target", 8, 1)
	_dice.set_fixed("spell_save_spells", 5)
	var choice := SpellChoice.new("charm_person", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"
	td.target_ids = [target.id]
	var result := _resolver.resolve(ctx, choice, td, caster_proxy, {target.id: target})
	check(result.success, "resolution succeeds even when target has no side")


func test_flip_to_caster_team_no_ops_when_already_on_caster_side() -> void:
	# If the target is already on the caster's side, the step is a no-op
	# (no record emitted; nothing to revert on cleanup).
	_build_resolver()
	var caster := _make_caster("same_side_caster", 1)
	var ctx := _make_caster_context(caster)
	var target := _SidedTarget.new()
	target.id = "same_side_target"
	target.side = 0  # SAME as caster's intended side
	target.save_spells = 17
	var caster_proxy := _SidedCaster.new()
	caster_proxy.id = caster.id
	caster_proxy.side = 0
	_dice.set_fixed("spell_save_spells", 5)
	var choice := SpellChoice.new("charm_person", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"
	td.target_ids = [target.id]
	_resolver.resolve(ctx, choice, td, caster_proxy, {target.id: target})
	check(target.has_condition("charmed"),
		"condition still applies — only the side flip step is a no-op")
	check(target.side == 0,
		"side stays 0 (already matched caster)")


func test_charm_side_flip_reverts_on_unwind() -> void:
	# Cast charm_person, capture the active_effect, then manually invoke
	# _unwind_effect_state via the cleanup callback. Target side should
	# revert to the original (pre-charm) side.
	_build_resolver()
	var caster := _make_caster("revert_caster", 1)
	var ctx := _make_caster_context(caster)
	var target := _SidedTarget.new()
	target.id = "revert_target"
	target.side = 1
	target.save_spells = 17
	var caster_proxy := _SidedCaster.new()
	caster_proxy.id = caster.id
	caster_proxy.side = 0

	_dice.set_fixed("spell_save_spells", 5)
	var choice := SpellChoice.new("charm_person", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"
	td.target_ids = [target.id]
	var result := _resolver.resolve(ctx, choice, td, caster_proxy, {target.id: target})
	check(result.success, "charm resolves successfully")
	check(target.side == 0, "target side flipped to caster's (precondition)")

	# Find the registered active effect.
	check(result.active_effect_ids.size() == 1,
		"charm_person registers one active effect")
	var effect_id: String = result.active_effect_ids[0]
	var effect: Dictionary = _effect_tracker.get_effect(effect_id)
	check(not effect.is_empty(), "active effect should be retrievable")
	check(effect.has("applied_side_flips"),
		"effect dict should carry applied_side_flips records")
	check((effect["applied_side_flips"] as Array).size() == 1,
		"one side flip record expected, got %d" %
			(effect["applied_side_flips"] as Array).size())

	# Manually invoke the cleanup path. Use a target lookup that returns
	# our test target.
	var lookup: Callable = func(tid: String) -> Variant:
		return target if tid == target.id else null
	_resolver._unwind_effect_state(effect, lookup)
	check(target.side == 1,
		"target side reverted to original (1); got %d" % target.side)


# ---------------------------------------------------------------------------
# Warlock 2/3 caster level (CasterContext.effective_caster_level, 2026-06-11)
# ---------------------------------------------------------------------------

func test_warlock_effective_caster_level() -> void:
	# ACKS PC p.47: the warlock casts arcane spells as a mage of two thirds
	# class level. Round-to-nearest reproduces the printed slot table
	# (= mage slots at round(2/3 x level)); 2/3 multiples never land on .5.
	var expected := {1: 1, 2: 1, 3: 2, 4: 3, 5: 3, 6: 4, 7: 5, 8: 5,
		9: 6, 10: 7, 11: 7, 12: 8, 13: 9, 14: 9}
	for lvl: int in expected.keys():
		var got := CasterContext.effective_caster_level("warlock", lvl)
		check(got == int(expected[lvl]),
			"warlock L%d should cast at caster level %d, got %d"
			% [lvl, int(expected[lvl]), got])
	# Full-level classes are untouched.
	check(CasterContext.effective_caster_level("mage", 7) == 7,
		"mage caster level should equal class level")
	# from_character_data applies the rule.
	var cd := CharacterData.new()
	cd.id = "wl_ctx_test"
	cd.name = "Test Warlock"
	cd.character_class = "warlock"
	cd.level = 5
	var ctx := CasterContext.from_character_data(cd, "dungeon_grid", "arcane", 1)
	check(ctx.caster_level == 3,
		"L5 warlock CasterContext.caster_level should be 3, got %d" % ctx.caster_level)
	print("  warlock_effective_caster_level: OK")
