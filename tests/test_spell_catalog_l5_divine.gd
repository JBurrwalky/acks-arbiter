extends "res://tests/test_suite_base.gd"

## Session 13 — L5 divine spell binding tests + 2 custom resolvers
## (dispel_evil, insect_plague) + new conditions (dispel_destroyed, questing).
##
## Coverage:
##   - Commune: stub.
##   - Cure Critical Wounds: heal 3d6+3.
##   - Cause Critical Wounds (reverse): damage 3d6+3 on hit.
##   - Dispel Evil (CUSTOM): area mode + single-target -2 save.
##   - Insect Plague (CUSTOM): 4-swarm placement + plague_profile + auto-drive-off.
##   - Quest: apply_condition questing + reverse removes.
##   - True Seeing: apply_flag has_true_seeing + RAW capabilities metadata.
##   - dispel_destroyed condition exists in catalog with helpless+vulnerable.
##   - questing condition exists in catalog (no intrinsic penalty — quest-tracker enforces).
##
## SACRED scope note: Faithful Hound and Raise Dead are NOT in the SACRED rule
## sources for this project; per CLAUDE.md SACRED precedence they are NOT bound.

const DispelEvilResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/dispel_evil_resolver.gd")
const InsectPlagueResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/insect_plague_resolver.gd")


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


class _Target extends RefCounted:
	var id: String = ""
	var hp_max: int = 12
	var hp_current: int = 12
	var conditions: Array[String] = []
	var flags: EntityFlags = EntityFlags.new()
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
	test_dispel_destroyed_condition_in_catalog()
	test_questing_condition_in_catalog()
	test_commune_stub()
	test_cure_critical_wounds_heal_3d6_plus_3()
	test_cause_critical_wounds_reverse_damage_on_hit()
	test_dispel_evil_area_mode_destroys_on_save_fail()
	test_dispel_evil_single_mode_minus_2_save()
	test_insect_plague_four_swarms_placement()
	test_insect_plague_persist_metadata()
	test_quest_applies_questing_condition()
	test_quest_reverse_removes_questing_condition()
	test_true_seeing_apply_flag_with_capability_metadata()
	if not has_failures():
		print("L5DivineCatalog: all tests passed.")


# ---------------------------------------------------------------------------
# New conditions
# ---------------------------------------------------------------------------

func test_dispel_destroyed_condition_in_catalog() -> void:
	var catalog := ConditionCatalog.new()
	var c: Dictionary = catalog.get_condition("dispel_destroyed")
	check(not c.is_empty(), "dispel_destroyed condition exists")
	check(bool(c.get("is_helpless", false)),
		"dispel_destroyed.is_helpless=true (mechanically equivalent to dead)")


func test_questing_condition_in_catalog() -> void:
	var catalog := ConditionCatalog.new()
	var c: Dictionary = catalog.get_condition("questing")
	check(not c.is_empty(), "questing condition exists")
	check(int(c.get("attack_modifier", 99)) == 0,
		"questing has no intrinsic attack penalty (quest-tracker enforces cumulative penalties)")


# ---------------------------------------------------------------------------
# Commune (stub)
# ---------------------------------------------------------------------------

func test_commune_stub() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "settlement", "divine", 1)
	var choice := SpellChoice.new("commune", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"; td.target_ids = [caster.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "stub", "Commune is stub")


# ---------------------------------------------------------------------------
# Cure Critical Wounds
# ---------------------------------------------------------------------------

func test_cure_critical_wounds_heal_3d6_plus_3() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	caster.level = 9
	var ally := _Target.new()
	ally.id = "ally_ccw"; ally.hp_max = 30; ally.hp_current = 5
	# Force 3d6+3 = 18 (3*5 + 3)
	harness.dice.fixed["spell_healing"] = 18
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("cure_critical_wounds", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_ally"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(int(ally.hp_current) == 23,
		"Cure Critical heals 18; hp went 5 → 23, got %d" % ally.hp_current)


func test_cause_critical_wounds_reverse_damage_on_hit() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	caster.level = 9
	var enemy := _Target.new()
	enemy.id = "enemy_ccw"; enemy.hp_max = 30; enemy.hp_current = 30
	harness.dice.fixed["spell_attack_throw"] = 25
	harness.dice.fixed["spell_damage"] = 18
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("cure_critical_wounds", 5, true, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_enemy"; td.target_ids = [enemy.id]
	harness.resolver.resolve(ctx, choice, td, caster, {enemy.id: enemy})
	check(int(enemy.hp_current) == 12,
		"Cause Critical deals 18; hp went 30 → 12, got %d" % enemy.hp_current)


# ---------------------------------------------------------------------------
# Dispel Evil
# ---------------------------------------------------------------------------

func test_dispel_evil_area_mode_destroys_on_save_fail() -> void:
	var resolver = DispelEvilResolverScript.new()
	var caster := _make_caster_cleric()
	caster.level = 10
	var undead := _Target.new(); undead.id = "skel_de"
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var td := TargetDescriptor.new()
	td.target_ids = [undead.id]
	var dice = _FakeDice.new()
	dice.fixed["spell_save_dispel_evil"] = 1  # Force fail (target=17)
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"targets_by_id": {undead.id: undead},
		"spell_choice": SpellChoice.new("dispel_evil", 5, false, -1),
		"step_payload": {"resolver_args": {"target_mode": "area", "dice": dice}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(undead.has_condition("dispel_destroyed"),
		"undead destroyed on failed save → dispel_destroyed condition")
	check((result.get("destroyed_ids", []) as Array).size() == 1,
		"destroyed_ids contains 1 entity")


func test_dispel_evil_single_mode_minus_2_save() -> void:
	var resolver = DispelEvilResolverScript.new()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var td := TargetDescriptor.new()
	td.target_ids = ["m1"]
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"targets_by_id": {"m1": _Target.new()},
		"spell_choice": SpellChoice.new("dispel_evil", 5, false, -1),
		"step_payload": {"resolver_args": {"target_mode": "single"}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(int(result.get("save_modifier", 0)) == -2,
		"single-target mode applies -2 save modifier per RAW")


# ---------------------------------------------------------------------------
# Insect Plague
# ---------------------------------------------------------------------------

func test_insect_plague_four_swarms_placement() -> void:
	var resolver = InsectPlagueResolverScript.new()
	var caster := _make_caster_cleric()
	caster.level = 10
	var ctx := CasterContext.from_character_data(caster, "wilderness_hex", "divine", 1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"; td.origin_cell = Vector3i(20, 20, 0)
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("insect_plague", 5, false, -1),
		"step_payload": {"resolver_args": {}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(int(result.get("swarms_count", 0)) == 4,
		"insect_plague spawns exactly 4 swarms per RAW")
	var profile: Dictionary = result.get("plague_profile", {})
	check(int(profile.get("auto_drive_off_hd_threshold", 0)) == 3,
		"auto_drive_off_hd_threshold=3 (<3 HD auto-driven off)")
	check(int(profile.get("swarm_movement_feet_per_round_controlled", 0)) == 20,
		"controlled swarms move 20'/round per RAW")


func test_insect_plague_persist_metadata() -> void:
	var resolver = InsectPlagueResolverScript.new()
	var caster := _make_caster_cleric()
	var ctx := CasterContext.from_character_data(caster, "wilderness_hex", "divine", 1)
	var td := TargetDescriptor.new()
	td.origin_cell = Vector3i(0, 0, 0)
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("insect_plague", 5, false, -1),
		"step_payload": {"resolver_args": {}},
	}
	var result: Dictionary = resolver.resolve(args)
	var pm: Dictionary = result.get("persist_metadata", {})
	check(pm.has("plague_profile"), "persist_metadata.plague_profile present")


# ---------------------------------------------------------------------------
# Quest
# ---------------------------------------------------------------------------

func test_quest_applies_questing_condition() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	caster.level = 10
	var subject := _Target.new(); subject.id = "subj_q"
	harness.dice.fixed["spell_save_spells"] = 1  # force fail
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("quest", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [subject.id]
	harness.resolver.resolve(ctx, choice, td, caster, {subject.id: subject})
	check(subject.has_condition("questing"),
		"Quest applies 'questing' condition on save fail")


func test_quest_reverse_removes_questing_condition() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var subject := _Target.new()
	subject.id = "subj_q2"; subject.add_condition("questing")
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("quest", 5, true, -1)  # reverse
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [subject.id]
	harness.resolver.resolve(ctx, choice, td, caster, {subject.id: subject})
	check(not subject.has_condition("questing"),
		"Reverse Quest removes 'questing' condition")


# ---------------------------------------------------------------------------
# True Seeing
# ---------------------------------------------------------------------------

func test_true_seeing_apply_flag_with_capability_metadata() -> void:
	var harness := _make_harness()
	var caster := _make_caster_cleric()
	var ally := CharacterData.new()
	ally.id = "ally_ts"; ally.hp_max = 12; ally.hp_current = 12
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "divine", 1)
	var choice := SpellChoice.new("true_seeing", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(ally.flags.has_flag("has_true_seeing"),
		"ally gains has_true_seeing flag")
	var meta: Dictionary = ally.flags.get_flag_source_entries("has_true_seeing")[0].get("metadata", {})
	check(int(meta.get("vision_range_feet", 0)) == 120,
		"vision_range_feet=120 per RAW")
	check(bool(meta.get("sees_through_illusions", false)),
		"sees_through_illusions=true per RAW")
	check(bool(meta.get("does_not_penetrate_solid_objects", false)),
		"does_not_penetrate_solid_objects=true (RAW limit)")


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
	cr.register("dispel_evil", DispelEvilResolverScript.new())
	cr.register("insect_plague", InsectPlagueResolverScript.new())
	h.resolver = CastingResolver.new(sr, er, tracker, cc, cr, null, h.repo, h.dice)
	return h


func _make_caster_cleric() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "cleric_l5div"
	cd.name = "Test Cleric L5"
	cd.character_class = "cleric"
	cd.combat_progression = "cleric"
	cd.level = 9
	cd.wisdom = 15
	cd.hp_max = 24; cd.hp_current = 24
	return cd
