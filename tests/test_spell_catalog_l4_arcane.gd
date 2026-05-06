extends "res://tests/test_suite_base.gd"

## Session 10 — L4 arcane spell binding tests + 5 custom resolvers + _teleport
## step kind + Confusion HD-exempt save + appears_as_terrain flag + wizard_eye_active.
##
## Coverage:
##   - Charm Monster: disjunctive (single >4 HD OR 3d6 HD group of ≤4 HD) + apply_condition charmed.
##   - Confusion: 30' radius, save vs Spells if HD>2, ≤2 HD auto-fail (HD-exempt path).
##   - Dimension Door: teleport step kind, precise error_profile, save negates if unwilling.
##   - Hallucinatory Terrain (CUSTOM): illusion_overlay with apparent_terrain.
##   - Massmorph: appears_as_terrain flag with ends_on_movement/attack metadata.
##   - Polymorph Self (CUSTOM): physical-stat snapshot + form override + flag.
##   - Polymorph Other (CUSTOM): HD-cap enforcement + 2x-old-HD check + alignment swap.
##   - Wall of Fire (CUSTOM): wall_profile with damage_dice 1d6 + min_hd_to_pass=5 + double-damage list.
##   - Wall of Ice (CUSTOM): wall_profile with damage_trigger=break_through + requires_solid_surface.
##   - Wizard Eye: wizard_eye_active flag with tether_max_feet=240 + concentration.
##   - Confused condition: present in catalog with no mechanical penalty (per RAW behavior table).
##   - _teleport step direct unit test: precise vs imprecise scatter; save_negates path.

const HallucinatoryTerrainResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/hallucinatory_terrain_resolver.gd")
const PolymorphSelfResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/polymorph_self_resolver.gd")
const PolymorphOtherResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/polymorph_other_resolver.gd")
const WallOfFireResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/wall_of_fire_resolver.gd")
const WallOfIceResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/wall_of_ice_resolver.gd")


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


# Lightweight monster fixture exposing hit_dice + add_condition for the
# Confusion + Charm Monster save-loop / condition-apply tests.
class _Monster extends RefCounted:
	var id: String = ""
	var hit_dice: int = 1
	var conditions: Array[String] = []
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	func get_effective_save(_key: String) -> int: return 17  # always-fail unless we boost


func run_all_tests() -> void:
	test_confused_condition_in_catalog()
	test_charm_monster_disjunctive_single_branch()
	test_charm_monster_disjunctive_group_branch()
	test_confusion_low_hd_auto_fail_save()
	test_confusion_high_hd_save_path()
	test_dimension_door_teleport_step_precise()
	test_dimension_door_teleport_records_destination_cell()
	test_hallucinatory_terrain_records_overlay()
	test_massmorph_apply_flag_with_movement_metadata()
	test_polymorph_self_snapshots_physical_stats()
	test_polymorph_self_rejects_form_hd_above_caster_level()
	test_polymorph_other_enforces_2x_old_hd_constraint()
	test_polymorph_other_snapshot_and_alignment_swap()
	test_wall_of_fire_wall_profile()
	test_wall_of_fire_rejects_oversized_area()
	test_wall_of_ice_break_through_trigger()
	test_wizard_eye_apply_flag_with_tether_metadata()
	# Direct _teleport step unit tests
	test_teleport_step_precise_no_scatter()
	test_teleport_step_unwilling_save_negates()
	if not has_failures():
		print("L4ArcaneCatalog: all tests passed.")


# ---------------------------------------------------------------------------
# Confused condition
# ---------------------------------------------------------------------------

func test_confused_condition_in_catalog() -> void:
	var catalog := ConditionCatalog.new()
	var c: Dictionary = catalog.get_condition("confused")
	check(not c.is_empty(), "confused condition exists in catalog")
	check(int(c.get("attack_modifier", 99)) == 0,
		"confused: no flat attack penalty per RAW (behavior table consumed by AI)")


# ---------------------------------------------------------------------------
# Charm Monster
# ---------------------------------------------------------------------------

func test_charm_monster_disjunctive_single_branch() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 5
	var monster := _Monster.new()
	monster.id = "ogre"; monster.hit_dice = 5
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	# disjunctive_index 0 = single creature >4 HD
	var choice := SpellChoice.new("charm_monster", 4, false, 0)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [monster.id]
	# Force save FAIL so the condition lands.
	harness.dice.fixed["spell_save_spells"] = 1
	var result = harness.resolver.resolve(ctx, choice, td, caster, {monster.id: monster})
	check(result.success, "charm_monster single-branch resolved successfully")
	check(monster.has_condition("charmed"), "single >4 HD target gains charmed condition")


func test_charm_monster_disjunctive_group_branch() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 5
	var goblin1 := _Monster.new(); goblin1.id = "g1"; goblin1.hit_dice = 1
	var goblin2 := _Monster.new(); goblin2.id = "g2"; goblin2.hit_dice = 1
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	# disjunctive_index 1 = HD-budget group ≤4 HD
	var choice := SpellChoice.new("charm_monster", 4, false, 1)
	var td := TargetDescriptor.new()
	td.kind = "multiple_creatures_hd_budget"; td.target_ids = [goblin1.id, goblin2.id]
	harness.dice.fixed["spell_save_spells"] = 1
	harness.resolver.resolve(ctx, choice, td, caster, {goblin1.id: goblin1, goblin2.id: goblin2})
	check(goblin1.has_condition("charmed") and goblin2.has_condition("charmed"),
		"all group-branch goblins charmed")


# ---------------------------------------------------------------------------
# Confusion
# ---------------------------------------------------------------------------

func test_confusion_low_hd_auto_fail_save() -> void:
	# Per RAW: creatures with ≤2 HD get NO save (auto-fail → confused).
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 5
	var weakling := _Monster.new(); weakling.id = "wkl"; weakling.hit_dice = 1
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("confusion", 4, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"; td.target_ids = [weakling.id]
	# Even with a max-roll d20, the HD<3 short-circuit auto-fails the save.
	harness.dice.fixed["spell_save_spells"] = 20
	harness.resolver.resolve(ctx, choice, td, caster, {weakling.id: weakling})
	check(weakling.has_condition("confused"),
		"≤2 HD creature auto-fails save and gains confused condition")


func test_confusion_high_hd_save_path() -> void:
	# Per RAW: creatures with HD>2 may save vs Spells. Force a successful save.
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 5
	var strong := _Monster.new(); strong.id = "str"; strong.hit_dice = 5
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("confusion", 4, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"; td.target_ids = [strong.id]
	# Save target is 17; set d20 to 18 → save succeeds → no condition.
	harness.dice.fixed["spell_save_spells"] = 18
	harness.resolver.resolve(ctx, choice, td, caster, {strong.id: strong})
	check(not strong.has_condition("confused"),
		"HD>2 creature with successful save is NOT confused")


# ---------------------------------------------------------------------------
# Dimension Door
# ---------------------------------------------------------------------------

func test_dimension_door_teleport_step_precise() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 7
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("dimension_door", 4, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [caster.id]
	td.origin_cell = Vector3i(15, 20, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "teleport",
		"Dimension Door step_kind='teleport'")
	check(int(step.get("max_range_feet", 0)) == 360,
		"Dimension Door max_range_feet=360 per RAW")


func test_dimension_door_teleport_records_destination_cell() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("dimension_door", 4, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [caster.id]
	td.origin_cell = Vector3i(50, 25, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	var step: Dictionary = result.effects_applied[0]
	var pt: Dictionary = step.get("per_target", {})
	var dest: Dictionary = pt.get(caster.id, {})
	var dc = dest.get("destination_cell", null)
	check(dc != null and Vector3i(dc) == Vector3i(50, 25, 0),
		"per-target destination_cell matches origin_cell on precise profile")


# ---------------------------------------------------------------------------
# Hallucinatory Terrain
# ---------------------------------------------------------------------------

func test_hallucinatory_terrain_records_overlay() -> void:
	var resolver = HallucinatoryTerrainResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 8
	var ctx := CasterContext.from_character_data(caster, "wilderness_hex", "arcane", 0)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(40, 40, 0)
	td.target_cells = [Vector3i(40, 40, 0), Vector3i(41, 40, 0)]
	var args := {
		"target_descriptor": td,
		"caster_context": ctx,
		"spell_choice": SpellChoice.new("hallucinatory_terrain", 4, false, -1),
		"step_payload": {"resolver_args": {"apparent_terrain": "swamp"}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(result.get("applied", false), "hallucinatory_terrain applied")
	var overlay: Dictionary = result.get("illusion_overlay", {})
	check(String(overlay.get("apparent_terrain", "")) == "swamp",
		"apparent_terrain='swamp' propagated from resolver_args")
	check((overlay.get("area_cells", []) as Array).size() == 2,
		"area_cells count=2 from target_descriptor")
	var pm: Dictionary = result.get("persist_metadata", {})
	check(pm.has("illusion_overlay"),
		"persist_metadata.illusion_overlay set for active_effect splice")


# ---------------------------------------------------------------------------
# Massmorph
# ---------------------------------------------------------------------------

func test_massmorph_apply_flag_with_movement_metadata() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 7
	var ally := CharacterData.new()
	ally.id = "ally_mm"; ally.hp_max = 8; ally.hp_current = 8
	var ctx := CasterContext.from_character_data(caster, "wilderness_hex", "arcane", 0)
	var choice := SpellChoice.new("massmorph", 4, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "multiple_creatures_count"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(ally.flags.has_flag("appears_as_terrain"),
		"ally gains appears_as_terrain flag")
	var entries = ally.flags.get_flag_source_entries("appears_as_terrain")
	var meta: Dictionary = entries[0].get("metadata", {})
	check(bool(meta.get("ends_on_movement", false)),
		"appears_as_terrain metadata.ends_on_movement=true (RAW: ends if creature moves)")
	check(bool(meta.get("ends_on_attack", false)),
		"appears_as_terrain metadata.ends_on_attack=true (RAW: ends if creature attacks)")


# ---------------------------------------------------------------------------
# Polymorph Self
# ---------------------------------------------------------------------------

func test_polymorph_self_snapshots_physical_stats() -> void:
	var resolver = PolymorphSelfResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 7
	caster.armor_class = 0; caster.attack_throw = 10; caster.base_movement = 120
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var args := {
		"caster_context": ctx,
		"caster_entity": caster,
		"spell_choice": SpellChoice.new("polymorph_self", 4, false, -1),
		"target_descriptor": TargetDescriptor.new(),
		"step_payload": {"resolver_args": {"form_profile": {
			"form_key": "wolf",
			"hit_dice": 2,
			"armor_class": 3,
			"attack_throw": 9,
			"base_movement": 180,
		}}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(result.get("applied", false), "polymorph_self applied")
	var snapshot: Dictionary = result.get("snapshot", {})
	check(int(snapshot.get("base_movement", 0)) == 120,
		"snapshot captures original base_movement=120 for revert")
	check(int(caster.base_movement) == 180,
		"caster's base_movement now overridden to wolf form value 180")


func test_polymorph_self_rejects_form_hd_above_caster_level() -> void:
	var resolver = PolymorphSelfResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 3
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var args := {
		"caster_context": ctx,
		"caster_entity": caster,
		"spell_choice": SpellChoice.new("polymorph_self", 4, false, -1),
		"target_descriptor": TargetDescriptor.new(),
		"step_payload": {"resolver_args": {"form_profile": {
			"form_key": "bear",
			"hit_dice": 8,
		}}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(not bool(result.get("applied", true)),
		"L3 caster cannot polymorph into 8-HD bear (HD cap)")
	check(String(result.get("reason", "")) == "form_hd_exceeds_caster_level",
		"reason='form_hd_exceeds_caster_level'")


# ---------------------------------------------------------------------------
# Polymorph Other
# ---------------------------------------------------------------------------

func test_polymorph_other_enforces_2x_old_hd_constraint() -> void:
	# RAW: new form HD must be FEWER than 2x old form HD.
	# Old HD = 2; cap = 2*2 = 4. Form HD = 4 → INVALID (must be < 4).
	var resolver = PolymorphOtherResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 7
	var target := CharacterData.new()
	target.id = "target_poly"; target.level = 2
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.target_ids = [target.id]
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"targets_by_id": {target.id: target},
		"spell_choice": SpellChoice.new("polymorph_other", 4, false, -1),
		"step_payload": {"resolver_args": {"form_profile": {
			"form_key": "wolf",
			"hit_dice": 4,
		}}},
	}
	var result: Dictionary = resolver.resolve(args)
	var pt: Dictionary = result.get("per_target", {})
	var entry: Dictionary = pt.get(target.id, {})
	check(not bool(entry.get("applied", true)),
		"4-HD form rejected vs 2-HD old form (≥2x cap)")
	check(String(entry.get("reason", "")) == "form_hd_at_or_above_2x_old_hd",
		"reason='form_hd_at_or_above_2x_old_hd'")


func test_polymorph_other_snapshot_and_alignment_swap() -> void:
	var resolver = PolymorphOtherResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 7
	var target := CharacterData.new()
	target.id = "target_poly2"; target.level = 3
	target.alignment = "lawful"; target.armor_class = 4; target.attack_throw = 10
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.target_ids = [target.id]
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"targets_by_id": {target.id: target},
		"spell_choice": SpellChoice.new("polymorph_other", 4, false, -1),
		"step_payload": {"resolver_args": {"form_profile": {
			"form_key": "wolf",
			"hit_dice": 2,
			"armor_class": 3,
			"attack_throw": 9,
			"alignment": "neutral",
		}}},
	}
	resolver.resolve(args)
	check(target.alignment == "neutral",
		"polymorph_other swaps alignment per RAW (mental + behavioral traits)")
	check(int(target.armor_class) == 3,
		"polymorph_other swaps armor_class to wolf form value 3")


# ---------------------------------------------------------------------------
# Wall of Fire
# ---------------------------------------------------------------------------

func test_wall_of_fire_wall_profile() -> void:
	var resolver = WallOfFireResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 7
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.target_cells = [Vector3i(10, 10, 0), Vector3i(11, 10, 0), Vector3i(12, 10, 0)]
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("wall_of_fire", 4, false, -1),
		"step_payload": {"resolver_args": {}},
	}
	var result: Dictionary = resolver.resolve(args)
	var wp: Dictionary = result.get("wall_profile", {})
	check(String(wp.get("damage_dice", "")) == "1d6",
		"wall_of_fire damage_dice='1d6' per RAW")
	check(int(wp.get("min_hd_to_pass", 0)) == 5,
		"min_hd_to_pass=5 (≤4 HD impenetrable per RAW)")
	check("undead" in (wp.get("double_damage_creature_types", []) as Array),
		"undead in double_damage list per RAW")


func test_wall_of_fire_rejects_oversized_area() -> void:
	# 50 cells * 25 sq ft = 1250 > 1200 cap.
	var resolver = WallOfFireResolverScript.new()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	var huge_cells: Array = []
	for i in range(50):
		huge_cells.append(Vector3i(i, 0, 0))
	td.target_cells = huge_cells
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("wall_of_fire", 4, false, -1),
		"step_payload": {"resolver_args": {"wall_segments": huge_cells}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(not bool(result.get("applied", true)),
		"wall_of_fire rejects area > 1200 sq ft (RAW cap)")


# ---------------------------------------------------------------------------
# Wall of Ice
# ---------------------------------------------------------------------------

func test_wall_of_ice_break_through_trigger() -> void:
	var resolver = WallOfIceResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 7
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.target_cells = [Vector3i(5, 5, 0), Vector3i(6, 5, 0)]
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("wall_of_ice", 4, false, -1),
		"step_payload": {"resolver_args": {}},
	}
	var result: Dictionary = resolver.resolve(args)
	var wp: Dictionary = result.get("wall_profile", {})
	check(String(wp.get("damage_trigger", "")) == "break_through",
		"wall_of_ice damage_trigger='break_through' (no free passage)")
	check(bool(wp.get("requires_solid_surface", false)),
		"wall_of_ice requires_solid_surface=true per RAW")
	check("fire_using" in (wp.get("double_damage_creature_types", []) as Array),
		"fire_using in double_damage list per RAW")


# ---------------------------------------------------------------------------
# Wizard Eye
# ---------------------------------------------------------------------------

func test_wizard_eye_apply_flag_with_tether_metadata() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 7
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("wizard_eye", 4, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"; td.target_ids = [caster.id]
	harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(caster.flags.has_flag("wizard_eye_active"),
		"caster gains wizard_eye_active flag")
	var entries = caster.flags.get_flag_source_entries("wizard_eye_active")
	var meta: Dictionary = entries[0].get("metadata", {})
	check(int(meta.get("tether_max_feet", 0)) == 240,
		"tether_max_feet=240 per RAW")
	check(int(meta.get("eye_movement_feet_per_round", 0)) == 40,
		"eye_movement_feet_per_round=40 per RAW")
	check(bool(meta.get("has_infravision", false)),
		"has_infravision=true per RAW")


# ---------------------------------------------------------------------------
# Direct _teleport step unit tests
# ---------------------------------------------------------------------------

func test_teleport_step_precise_no_scatter() -> void:
	var harness := _make_harness()
	var step := {
		"kind": "teleport",
		"max_range_feet": 360,
		"error_profile": "precise",
		"fail_on_solid_object": true,
	}
	var td := TargetDescriptor.new()
	td.target_ids = ["a"]
	td.origin_cell = Vector3i(7, 8, 0)
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var outcome: Dictionary = harness.resolver._teleport(step, td, {"a": null}, caster, ctx, {}, {"category": "none"})
	check(Vector3i(outcome.get("destination_cell")) == Vector3i(7, 8, 0),
		"precise teleport destination matches origin_cell exactly")
	check(Vector3i(outcome.get("scatter_offset")) == Vector3i.ZERO,
		"precise teleport scatter_offset is ZERO")


func test_teleport_step_unwilling_save_negates() -> void:
	var harness := _make_harness()
	var step := {
		"kind": "teleport",
		"max_range_feet": 360,
		"error_profile": "precise",
	}
	var td := TargetDescriptor.new()
	td.target_ids = ["b"]
	td.origin_cell = Vector3i(0, 0, 0)
	var save_results := {"b": {"succeeded": true}}
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var outcome: Dictionary = harness.resolver._teleport(
		step, td, {"b": null}, caster, ctx, save_results,
		{"category": "spells", "on_success": "negate"})
	var pt: Dictionary = outcome.get("per_target", {})
	var entry: Dictionary = pt.get("b", {})
	check(not bool(entry.get("applied", true)),
		"unwilling target with successful save → applied=false")
	check(String(entry.get("reason", "")) == "saved",
		"reason='saved'")


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
	cr.register("hallucinatory_terrain", HallucinatoryTerrainResolverScript.new())
	cr.register("polymorph_self", PolymorphSelfResolverScript.new())
	cr.register("polymorph_other", PolymorphOtherResolverScript.new())
	cr.register("wall_of_fire", WallOfFireResolverScript.new())
	cr.register("wall_of_ice", WallOfIceResolverScript.new())
	h.resolver = CastingResolver.new(sr, er, tracker, cc, cr, null, h.repo, h.dice)
	return h


func _make_caster_mage() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "mage_l4arcane"
	cd.name = "Test Mage L4"
	cd.character_class = "mage"
	cd.combat_progression = "mage"
	cd.level = 7
	cd.intelligence = 14
	cd.hp_max = 12; cd.hp_current = 12
	return cd
