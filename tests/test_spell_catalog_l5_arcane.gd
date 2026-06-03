extends "res://tests/test_suite_base.gd"

## Session 12 — L5 arcane spell binding tests + 4 custom resolvers
## (cloudkill, conjure_elemental, teleport, wall_of_stone).
##
## Coverage:
##   - Cloudkill (CUSTOM): cloud_profile + persist_metadata.
##   - Cone of Cold: damage_per_level=1d6 + cone geometry + save_vs_cold tag.
##   - Conjure Elemental (CUSTOM): elemental_type validation + spawn_profile + concentration tags.
##   - Contact Other Plane: stub.
##   - Feeblemind: apply_condition feebleminded + save_spec.modifier_for_arcane_caster_target=-4.
##   - Hold Monster: apply_condition paralyzed + save vs Paralysis (no humanoid filter).
##   - Magic Jar: stub.
##   - Telekinesis: apply_flag is_telekinetically_held + caster constraint metadata.
##   - Teleport (CUSTOM): familiarity table outcomes (on/off/lost).
##   - Wall of Stone (CUSTOM): wall_profile + volume cap with span/shaping reductions.
##   - Protection from Normal Weapons: apply_damage_resistance immunity + flag exceptions metadata.

const CloudkillResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/cloudkill_resolver.gd")
const ConjureElementalResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/conjure_elemental_resolver.gd")
const TeleportResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/teleport_resolver.gd")
const WallOfStoneResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/wall_of_stone_resolver.gd")


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


class _Mob extends RefCounted:
	var id: String = ""
	var hit_dice: int = 1
	var conditions: Array[String] = []
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	func get_effective_save(key: String) -> int:
		# Modifier-only axes (save_vs_<element/alignment>) return 0 to match
		# CharacterData.get_effective_save semantics; otherwise return 17.
		if key.begins_with("save_vs_"):
			return 0
		return 17


func run_all_tests() -> void:
	test_cloudkill_cloud_profile()
	test_cloudkill_persist_metadata()
	test_cone_of_cold_damage_per_level()
	test_cone_of_cold_save_spec_damage_type_cold()
	test_conjure_elemental_validates_type()
	test_conjure_elemental_invalid_type_rejected()
	test_contact_other_plane_stub()
	test_feeblemind_applies_condition()
	test_feeblemind_carries_arcane_caster_modifier()
	test_hold_monster_applies_paralyzed()
	test_magic_jar_stub()
	test_telekinesis_apply_flag_with_constraint_metadata()
	test_teleport_on_target_outcome()
	test_teleport_lost_outcome()
	test_wall_of_stone_volume_cap()
	test_wall_of_stone_span_reduction()
	test_protection_from_normal_weapons_immunity()
	if not has_failures():
		print("L5ArcaneCatalog: all tests passed.")


# ---------------------------------------------------------------------------
# Cloudkill
# ---------------------------------------------------------------------------

func test_cloudkill_cloud_profile() -> void:
	var resolver = CloudkillResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 9
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"; td.origin_cell = Vector3i(5, 5, 0)
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("cloudkill", 5, false, -1),
		"step_payload": {"resolver_args": {}},
	}
	var result: Dictionary = resolver.resolve(args)
	var cp: Dictionary = result.get("cloud_profile", {})
	check(int(cp.get("diameter_feet", 0)) == 30, "cloudkill diameter=30 per RAW")
	check(int(cp.get("drift_feet_per_round", 0)) == 20, "drift 20'/round per RAW")
	check(int(cp.get("hd_threshold_for_death_save", 0)) == 5,
		"hd_threshold_for_death_save=5 (<5 HD save or die)")


func test_cloudkill_persist_metadata() -> void:
	var resolver = CloudkillResolverScript.new()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.origin_cell = Vector3i.ZERO
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("cloudkill", 5, false, -1),
		"step_payload": {"resolver_args": {}},
	}
	var result: Dictionary = resolver.resolve(args)
	var pm: Dictionary = result.get("persist_metadata", {})
	check(pm.has("cloud_profile"), "persist_metadata.cloud_profile present")


# ---------------------------------------------------------------------------
# Cone of Cold
# ---------------------------------------------------------------------------

func test_cone_of_cold_damage_per_level() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 5
	var goblin := _Mob.new(); goblin.id = "g"; goblin.hit_dice = 1
	# Force d6=4 per roll, 5 rolls = 20 damage; force save fail (target=17, mod=1).
	harness.dice.fixed["spell_damage"] = 4
	harness.dice.fixed["spell_save_blast"] = 1
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("cone_of_cold", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_from_caster"; td.target_ids = [goblin.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {goblin.id: goblin})
	check(result.success, "Cone of Cold resolves")
	var step: Dictionary = result.effects_applied[0]
	var pt: Dictionary = step.get("per_target", {})
	check(int(pt.get(goblin.id, {}).get("amount", 0)) == 20,
		"L5: 5d6 forced=4 each = 20, got %d" % pt.get(goblin.id, {}).get("amount", 0))


func test_cone_of_cold_save_spec_damage_type_cold() -> void:
	# Read the catalog directly to assert the wiring.
	var registry := SpellRegistry.new()
	var er := SpellEffectRegistry.new(registry)
	var payload: Dictionary = er.get_effect_payload("cone_of_cold", false, -1)
	var save_spec: Dictionary = payload.get("save_spec", {})
	check(String(save_spec.get("damage_type", "")) == "cold",
		"Cone of Cold save_spec.damage_type='cold' (Resist Cold consultation)")


# ---------------------------------------------------------------------------
# Conjure Elemental
# ---------------------------------------------------------------------------

func test_conjure_elemental_validates_type() -> void:
	var resolver = ConjureElementalResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 9
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new(); td.origin_cell = Vector3i(10, 10, 0)
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("conjure_elemental", 5, false, -1),
		"step_payload": {"resolver_args": {"elemental_type": "fire"}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(result.get("applied", false), "fire elemental conjured")
	var sp: Dictionary = result.get("spawn_profile", {})
	check(bool(sp.get("becomes_hostile_on_concentration_break", false)),
		"becomes_hostile_on_concentration_break=true per RAW")


func test_conjure_elemental_invalid_type_rejected() -> void:
	var resolver = ConjureElementalResolverScript.new()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var args := {
		"caster_context": ctx,
		"target_descriptor": TargetDescriptor.new(),
		"spell_choice": SpellChoice.new("conjure_elemental", 5, false, -1),
		"step_payload": {"resolver_args": {"elemental_type": "void"}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(not bool(result.get("applied", true)),
		"invalid elemental_type 'void' rejected")


# ---------------------------------------------------------------------------
# Contact Other Plane (STUB) + Magic Jar (STUB)
# ---------------------------------------------------------------------------

func test_contact_other_plane_stub() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("contact_other_plane", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"; td.target_ids = [caster.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "stub",
		"Contact Other Plane is stub (LLM narration deferred)")


func test_magic_jar_stub() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("magic_jar", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_object"; td.target_ids = ["jar_42"]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {"jar_42": null})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "stub",
		"Magic Jar is stub (soul-state machine deferred)")


# ---------------------------------------------------------------------------
# Feeblemind
# ---------------------------------------------------------------------------

func test_feeblemind_applies_condition() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 9
	var enemy := _Mob.new(); enemy.id = "e_fm"; enemy.hit_dice = 4
	harness.dice.fixed["spell_save_spells"] = 1
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("feeblemind", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [enemy.id]
	harness.resolver.resolve(ctx, choice, td, caster, {enemy.id: enemy})
	check(enemy.has_condition("feebleminded"),
		"Feeblemind applies 'feebleminded' on save fail")


func test_feeblemind_carries_arcane_caster_modifier() -> void:
	var registry := SpellRegistry.new()
	var er := SpellEffectRegistry.new(registry)
	var payload: Dictionary = er.get_effect_payload("feeblemind", false, -1)
	var save_spec: Dictionary = payload.get("save_spec", {})
	check(int(save_spec.get("modifier_for_arcane_caster_target", 0)) == -4,
		"Feeblemind save_spec.modifier_for_arcane_caster_target=-4 per RAW")


# ---------------------------------------------------------------------------
# Hold Monster
# ---------------------------------------------------------------------------

func test_hold_monster_applies_paralyzed() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 9
	var dragon := _Mob.new(); dragon.id = "drg"; dragon.hit_dice = 7
	harness.dice.fixed["spell_save_paralysis_petrification"] = 1
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("hold_monster", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [dragon.id]
	harness.resolver.resolve(ctx, choice, td, caster, {dragon.id: dragon})
	check(dragon.has_condition("paralyzed"),
		"Hold Monster paralyzes any-type creature on save fail (no humanoid filter)")


# ---------------------------------------------------------------------------
# Telekinesis
# ---------------------------------------------------------------------------

func test_telekinesis_apply_flag_with_constraint_metadata() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 5
	var obj := CharacterData.new()
	obj.id = "obj_tk"; obj.hp_max = 1; obj.hp_current = 1
	# 2026-06-02: CastingResolver._apply_flag now gates on save_results
	# the same way _apply_condition does. Telekinesis' save_spec carries
	# `applies_only_to_unwilling_creature_or_carrier: true` so the gate
	# skips the save check; explicit save-fail injection is belt-and-
	# suspenders for any future save_spec refactor that drops the hint.
	harness.dice.fixed["spell_save_spells"] = 1  # force fail (target=17)
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("telekinesis", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_object_or_creature"; td.target_ids = [obj.id]
	harness.resolver.resolve(ctx, choice, td, caster, {obj.id: obj})
	check(obj.flags.has_flag("is_telekinetically_held"),
		"object gains is_telekinetically_held flag")
	var meta: Dictionary = obj.flags.get_flag_source_entries("is_telekinetically_held")[0].get("metadata", {})
	check(int(meta.get("max_weight_stone_per_caster_level", 0)) == 2,
		"max_weight_stone_per_caster_level=2 per RAW")
	check(bool(meta.get("ends_on_concentration_break", false)),
		"ends_on_concentration_break=true")
	check(bool(meta.get("caster_blocked_from_attacks_and_spells", false)),
		"caster_blocked_from_attacks_and_spells=true per RAW")


# ---------------------------------------------------------------------------
# Teleport
# ---------------------------------------------------------------------------

func test_teleport_on_target_outcome() -> void:
	var resolver = TeleportResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 9
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.target_ids = [caster.id]; td.origin_cell = Vector3i(100, 100, 0)
	var dice = _FakeDice.new()
	dice.fixed["spell_teleport_familiarity"] = 50  # 50 ≤ studied.on_max=80 → on_target
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("teleport", 5, false, -1),
		"step_payload": {"resolver_args": {"familiarity": "studied", "dice": dice}},
	}
	var result: Dictionary = resolver.resolve(args)
	var pt: Dictionary = result.get("per_target", {})
	var entry: Dictionary = pt.get(caster.id, {})
	check(str(entry.get("outcome_kind", "")) == "on_target",
		"studied familiarity + d%=50 → on_target")


func test_teleport_lost_outcome() -> void:
	var resolver = TeleportResolverScript.new()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.target_ids = [caster.id]; td.origin_cell = Vector3i.ZERO
	var dice = _FakeDice.new()
	dice.fixed["spell_teleport_familiarity"] = 100  # 100 > studied.off_max=90 → lost
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("teleport", 5, false, -1),
		"step_payload": {"resolver_args": {"familiarity": "studied", "dice": dice}},
	}
	var result: Dictionary = resolver.resolve(args)
	var pt: Dictionary = result.get("per_target", {})
	var entry: Dictionary = pt.get(caster.id, {})
	check(str(entry.get("outcome_kind", "")) == "lost",
		"studied familiarity + d%=100 → lost")


# ---------------------------------------------------------------------------
# Wall of Stone
# ---------------------------------------------------------------------------

func test_wall_of_stone_volume_cap() -> void:
	# 9 cells * 125 cubic feet each = 1125 > 1000 max → reject.
	var resolver = WallOfStoneResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 9
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	var cells: Array = []
	for i in range(9):
		cells.append(Vector3i(i, 0, 0))
	td.target_cells = cells
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("wall_of_stone", 5, false, -1),
		"step_payload": {"resolver_args": {"wall_segments": cells}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(not bool(result.get("applied", true)),
		"9 cells × 125 cu ft = 1125 > 1000 cap → rejected")


func test_wall_of_stone_span_reduction() -> void:
	# Span > 20 ft halves effective max; 5 cells (625 cu ft) fits in 500 cap (halved).
	# 5 cells = 625; effective_max = 500 → reject. 4 cells = 500 → fits.
	var resolver = WallOfStoneResolverScript.new()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	var cells: Array = []
	for i in range(4):
		cells.append(Vector3i(i, 0, 0))
	td.target_cells = cells
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("wall_of_stone", 5, false, -1),
		"step_payload": {"resolver_args": {"wall_segments": cells, "span_feet": 25}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(bool(result.get("applied", false)),
		"4 cells (500 cu ft) fits within span-halved 500 cap")


# ---------------------------------------------------------------------------
# Protection from Normal Weapons
# ---------------------------------------------------------------------------

func test_protection_from_normal_weapons_immunity() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ally := CharacterData.new()
	ally.id = "ally_pnw"; ally.hp_max = 12; ally.hp_current = 12
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("protection_from_normal_weapons", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(ally.flags.has_flag("protected_from_normal_weapons"),
		"PNW grants protected_from_normal_weapons flag")
	check(ally.damage_resistances.is_immune("physical_non_magical"),
		"PNW grants immunity to physical_non_magical damage")


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
	cr.register("cloudkill", CloudkillResolverScript.new())
	cr.register("conjure_elemental", ConjureElementalResolverScript.new())
	cr.register("teleport", TeleportResolverScript.new())
	cr.register("wall_of_stone", WallOfStoneResolverScript.new())
	h.resolver = CastingResolver.new(sr, er, tracker, cc, cr, null, h.repo, h.dice)
	return h


func _make_caster_mage() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "mage_l5arcane"
	cd.name = "Test Mage L5"
	cd.character_class = "mage"
	cd.combat_progression = "mage"
	cd.level = 9
	cd.intelligence = 15
	cd.hp_max = 16; cd.hp_current = 16
	return cd
