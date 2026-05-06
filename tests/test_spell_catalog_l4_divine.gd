extends "res://tests/test_suite_base.gd"

## Session 11 — L4 divine spell binding tests + animate_dead/sticks_to_snakes
## custom resolvers + bonus_per_caster_level on heal/damage steps + poisoned
## condition.
##
## Coverage:
##   - Poisoned condition: present in catalog, no intrinsic mechanical penalty.
##   - Create Water: query_game_state with produce_water_in_cell.
##   - Cure Serious Wounds: heal step with 2d6 + caster_level.
##   - Cause Serious Wounds (reverse): damage step with 2d6 + caster_level.
##   - Neutralize Poison: remove_condition('poisoned').
##   - Poison (reverse): apply_condition('poisoned') after attack throw.
##   - Smite Undead: stub forward + animate_dead reverse via custom resolver.
##   - Speak with Plants: apply_flag can_speak_with_plants + range metadata.
##   - Sticks to Snakes (CUSTOM): brackets + spawn_profile + persist_metadata.
##   - Animate Dead (CUSTOM): HD-budget enforcement + spawn_profile.
##   - Diseased magic-heal block still applies on Cure Serious (cross-session check).

const AnimateDeadResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/animate_dead_resolver.gd")
const SticksToSnakesResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/sticks_to_snakes_resolver.gd")


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


class _PoisonTarget extends RefCounted:
	var id: String = ""
	var conditions: Array[String] = []
	var hp_max: int = 8
	var hp_current: int = 8
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func remove_condition(k: String) -> void: conditions.erase(k)
	func has_condition(k: String) -> bool: return k in conditions
	func apply_damage(amt: int, _t: String = "", _s: String = "") -> int:
		hp_current = max(0, hp_current - amt); return amt
	func apply_healing(amt: int) -> int:
		var diff: int = min(hp_max - hp_current, amt)
		hp_current += diff; return diff
	func get_effective_save(_key: String) -> int: return 17
	func get_effective_ac() -> int: return 0


func run_all_tests() -> void:
	test_poisoned_condition_in_catalog()
	test_create_water_query_kind()
	test_cure_serious_wounds_dice_plus_caster_level()
	test_cure_serious_wounds_diseased_block_still_applies()
	test_cause_serious_wounds_damage_plus_caster_level()
	test_neutralize_poison_removes_condition()
	test_poison_reverse_apply_condition_on_hit()
	test_smite_undead_forward_stub()
	test_smite_undead_reverse_uses_animate_dead()
	test_speak_with_plants_apply_flag()
	test_sticks_to_snakes_brackets_low_level()
	test_sticks_to_snakes_brackets_high_level()
	test_sticks_to_snakes_persist_metadata()
	test_animate_dead_hd_budget_enforces()
	test_animate_dead_persist_metadata()
	if not has_failures():
		print("L4DivineCatalog: all tests passed.")


# ---------------------------------------------------------------------------
# Poisoned condition
# ---------------------------------------------------------------------------

func test_poisoned_condition_in_catalog() -> void:
	var catalog := ConditionCatalog.new()
	var c: Dictionary = catalog.get_condition("poisoned")
	check(not c.is_empty(), "poisoned condition exists in catalog")
	check(int(c.get("attack_modifier", 99)) == 0,
		"poisoned: no flat attack penalty (poison source carries damage)")


# ---------------------------------------------------------------------------
# Create Water
# ---------------------------------------------------------------------------

func test_create_water_query_kind() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	caster.level = 8
	var ctx := CasterContext.from_character_data(caster, "wilderness_hex", "divine", 1)
	var choice := SpellChoice.new("create_water", 4, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_cell"; td.origin_cell = Vector3i(0, 0, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("query_kind", "") == "produce_water_in_cell",
		"Create Water query_kind='produce_water_in_cell'")


# ---------------------------------------------------------------------------
# Cure Serious Wounds + Cause Serious Wounds
# ---------------------------------------------------------------------------

func test_cure_serious_wounds_dice_plus_caster_level() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	caster.level = 7
	var ally := _PoisonTarget.new()
	ally.id = "ally_csw"; ally.hp_max = 30; ally.hp_current = 5
	# Force 2d6 = 8, level_bonus = 7, total 15
	harness.dice.fixed["spell_healing"] = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("cure_serious_wounds", 4, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_ally"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(int(ally.hp_current) == 20,
		"Cure Serious heals 8 + 7(level) = 15; hp went 5 → 20, got %d" % ally.hp_current)


func test_cure_serious_wounds_diseased_block_still_applies() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	caster.level = 7
	var ally := _PoisonTarget.new()
	ally.id = "ally_csw_d"; ally.hp_current = 5
	ally.add_condition("diseased")
	harness.dice.fixed["spell_healing"] = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("cure_serious_wounds", 4, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_ally"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(int(ally.hp_current) == 5,
		"diseased ally takes 0 healing from Cure Serious (block holds across sessions)")


func test_cause_serious_wounds_damage_plus_caster_level() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	caster.level = 5
	var enemy := _PoisonTarget.new()
	enemy.id = "enemy_csw"; enemy.hp_max = 30; enemy.hp_current = 30
	# Force damage_roll=10 + level_bonus=5 = 15 damage; assume hit.
	harness.dice.fixed["spell_damage"] = 10
	harness.dice.fixed["spell_attack_throw"] = 25  # auto-hit
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("cure_serious_wounds", 4, true, -1)  # is_reversed=true
	var td := TargetDescriptor.new()
	td.kind = "touch_enemy"; td.target_ids = [enemy.id]
	harness.resolver.resolve(ctx, choice, td, caster, {enemy.id: enemy})
	check(int(enemy.hp_current) == 15,
		"Cause Serious deals 10 + 5(level) = 15; hp went 30 → 15, got %d" % enemy.hp_current)


# ---------------------------------------------------------------------------
# Neutralize Poison + Poison
# ---------------------------------------------------------------------------

func test_neutralize_poison_removes_condition() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ally := _PoisonTarget.new()
	ally.id = "ally_np"; ally.add_condition("poisoned")
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("neutralize_poison", 4, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(not ally.has_condition("poisoned"),
		"Neutralize Poison clears 'poisoned' condition from ally")


func test_poison_reverse_apply_condition_on_hit() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	caster.level = 7
	var enemy := _PoisonTarget.new()
	enemy.id = "enemy_pois"
	# Force hit + force save fail (target=17, modified=1)
	harness.dice.fixed["spell_attack_throw"] = 25
	harness.dice.fixed["spell_save_poison_death"] = 1
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("neutralize_poison", 4, true, -1)  # reverse
	var td := TargetDescriptor.new()
	td.kind = "touch_enemy"; td.target_ids = [enemy.id]
	harness.resolver.resolve(ctx, choice, td, caster, {enemy.id: enemy})
	check(enemy.has_condition("poisoned"),
		"reverse Poison: hit + failed save → 'poisoned' condition applied")


# ---------------------------------------------------------------------------
# Smite Undead / Animate Dead
# ---------------------------------------------------------------------------

func test_smite_undead_forward_stub() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	caster.level = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("smite_undead", 4, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"; td.origin_cell = Vector3i(0, 0, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "stub",
		"Smite Undead forward is stub this session (HD-budget destroy routine deferred)")


func test_smite_undead_reverse_uses_animate_dead() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	caster.level = 5
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("smite_undead", 4, true, -1)  # reverse = Animate Dead
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = ["corpse_42"]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {"corpse_42": null})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "custom",
		"Smite Undead reverse uses custom step")
	check(int(step.get("hd_budget", 0)) == 10,
		"L5 caster: HD budget = 5 × 2 = 10, got %d" % step.get("hd_budget", 0))


# ---------------------------------------------------------------------------
# Speak with Plants
# ---------------------------------------------------------------------------

func test_speak_with_plants_apply_flag() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("speak_with_plants", 4, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"; td.target_ids = [caster.id]
	harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(caster.flags.has_flag("can_speak_with_plants"),
		"caster gains can_speak_with_plants flag")
	var entries = caster.flags.get_flag_source_entries("can_speak_with_plants")
	var meta: Dictionary = entries[0].get("metadata", {})
	check(int(meta.get("communication_range_feet", 0)) == 30,
		"communication_range_feet=30 per RAW")


# ---------------------------------------------------------------------------
# Sticks to Snakes
# ---------------------------------------------------------------------------

func test_sticks_to_snakes_brackets_low_level() -> void:
	# L1-L4: 1 bracket → 2d8 snakes.
	var resolver = SticksToSnakesResolverScript.new()
	var caster := _make_caster_cleric()
	caster.level = 3
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var args := {
		"caster_context": ctx,
		"spell_choice": SpellChoice.new("sticks_to_snakes", 4, false, -1),
		"target_descriptor": TargetDescriptor.new(),
		"step_payload": {"resolver_args": {}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(int(result.get("brackets", 0)) == 1,
		"L3 caster → 1 bracket, got %d" % result.get("brackets", 0))


func test_sticks_to_snakes_brackets_high_level() -> void:
	# L8: 2 brackets per the formula (4 + 4 = 8 fits in 2 brackets).
	var resolver = SticksToSnakesResolverScript.new()
	var caster := _make_caster_cleric()
	caster.level = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var args := {
		"caster_context": ctx,
		"spell_choice": SpellChoice.new("sticks_to_snakes", 4, false, -1),
		"target_descriptor": TargetDescriptor.new(),
		"step_payload": {"resolver_args": {}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(int(result.get("brackets", 0)) == 2,
		"L8 caster → 2 brackets, got %d" % result.get("brackets", 0))


func test_sticks_to_snakes_persist_metadata() -> void:
	var resolver = SticksToSnakesResolverScript.new()
	var caster := _make_caster_cleric()
	caster.level = 5
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var args := {
		"caster_context": ctx,
		"spell_choice": SpellChoice.new("sticks_to_snakes", 4, false, -1),
		"target_descriptor": TargetDescriptor.new(),
		"step_payload": {"resolver_args": {}},
	}
	var result: Dictionary = resolver.resolve(args)
	var pm: Dictionary = result.get("persist_metadata", {})
	check(pm.has("sticks_to_snakes_spawn_profile"),
		"persist_metadata.sticks_to_snakes_spawn_profile present for active_effect")


# ---------------------------------------------------------------------------
# Animate Dead
# ---------------------------------------------------------------------------

func test_animate_dead_hd_budget_enforces() -> void:
	# L5 caster: HD budget = 10. Try 6 corpses of 2 HD each = 12 → 5 fit.
	var resolver = AnimateDeadResolverScript.new()
	var caster := _make_caster_cleric()
	caster.level = 5
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var corpses: Array = []
	for i in range(6):
		corpses.append({"corpse_id": "c%d" % i, "hd_cost": 2, "undead_template": "zombie"})
	var args := {
		"caster_context": ctx,
		"spell_choice": SpellChoice.new("animate_dead", 4, false, -1),
		"target_descriptor": TargetDescriptor.new(),
		"step_payload": {"resolver_args": {"corpses_to_animate": corpses}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(int(result.get("animated_count", 0)) == 5,
		"L5 caster: 10 HD budget / 2 HD per zombie = 5 animated, got %d" % result.get("animated_count", 0))
	check(int(result.get("hd_spent", 0)) == 10, "hd_spent=10")


func test_animate_dead_persist_metadata() -> void:
	var resolver = AnimateDeadResolverScript.new()
	var caster := _make_caster_cleric()
	caster.level = 4
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var args := {
		"caster_context": ctx,
		"spell_choice": SpellChoice.new("animate_dead", 4, false, -1),
		"target_descriptor": TargetDescriptor.new(),
		"step_payload": {"resolver_args": {"corpses_to_animate": [
			{"corpse_id": "c1", "hd_cost": 1, "undead_template": "skeleton"}
		]}},
	}
	var result: Dictionary = resolver.resolve(args)
	var pm: Dictionary = result.get("persist_metadata", {})
	check(pm.has("animate_dead_spawn_profile"),
		"persist_metadata.animate_dead_spawn_profile present")


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
	cr.register("animate_dead", AnimateDeadResolverScript.new())
	cr.register("sticks_to_snakes", SticksToSnakesResolverScript.new())
	h.resolver = CastingResolver.new(sr, er, tracker, cc, cr, null, h.repo, h.dice)
	return h


func _make_caster_cleric() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "cleric_l4div"
	cd.name = "Test Cleric L4"
	cd.character_class = "cleric"
	cd.combat_progression = "cleric"
	cd.level = 7
	cd.wisdom = 14
	cd.hp_max = 18; cd.hp_current = 18
	return cd
