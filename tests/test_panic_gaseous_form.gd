extends "res://tests/test_suite_base.gd"

## Spell-effect tests for panic + gaseous_form (Tier 4 follow-up, 2026-06-01)
## plus the MovementResolver portcullis bypass for gaseous combatants.
##
## Scope:
##   - Catalog binding shape: Drums of Panic → panic; Potion of Gaseous Form
##     → gaseous_form.
##   - panic spell: area_at_point sphere 240' centered on caster; save vs
##     Spells negates; failed targets gain `frightened` condition.
##   - gaseous_form spell: single_creature self-target; applies `is_gaseous`
##     EntityFlag with consumer metadata (ac_override 11, movement 30, etc.).
##   - MovementResolver portcullis bypass: a Combatant carrying `is_gaseous`
##     can path through a cell with `door_type = "portcullis"` and
##     `door_state = "closed"`; a non-gaseous Combatant cannot.


# ---------------------------------------------------------------------------
# Test stubs
# ---------------------------------------------------------------------------

class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}
	func set_fixed(roll_type: String, value: int) -> void:
		fixed[roll_type] = value
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


## Test stub exposing condition + flag tracking — used as the target of
## panic + gaseous_form. CharacterData doesn't track conditions or flags
## directly, so we stand in this minimal duck-typed mob.
class _FlagAndConditionTarget extends RefCounted:
	var id: String = ""
	var hit_dice: int = 1
	var save_spells: int = 17
	var conditions: Array[String] = []
	var flags: EntityFlags = EntityFlags.new()
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	## Required by CastingResolver._get_flags (matches CharacterData /
	## Combatant get_flags() interface).
	func get_flags() -> EntityFlags:
		return flags
	func get_effective_save(key: String) -> int:
		match key:
			"save_spells": return save_spells
			_: return 17


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

var _repo = null
var _dice = null
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
		_spell_registry, _effect_registry, _effect_tracker,
		_condition_catalog, _custom_resolvers, null, _repo, _dice)


func _make_mage(id: String, level: int = 9) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = id
	cd.character_class = "mage"
	cd.combat_progression = "mage"
	cd.level = level
	cd.intelligence = 16
	cd.alignment = "neutral"
	return cd


func _make_ctx(caster: CharacterData) -> CasterContext:
	return CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	# Catalog binding shape.
	test_drums_of_panic_binds_to_panic()
	test_potion_of_gaseous_form_binds_to_gaseous_form()
	# Panic spell effect.
	test_panic_applies_frightened_on_failed_save()
	test_panic_does_not_apply_on_save_success()
	test_panic_uses_area_at_point_sphere_240_feet()
	# Gaseous form spell effect.
	test_gaseous_form_sets_is_gaseous_flag()
	test_gaseous_form_flag_carries_consumer_metadata()
	# Portcullis bypass (MovementResolver auto-detect via is_gaseous flag).
	test_voxel_cell_is_passable_by_gaseous_through_closed_portcullis()
	test_voxel_cell_is_passable_by_gaseous_blocked_by_solid_wall()
	# Bow-tie consumer integrations (Tier 4 follow-up 2026-06-01).
	test_panic_carries_inner_radius_safe_zone()
	test_panic_resolution_includes_running_speed_flag_step()
	test_gaseous_form_carries_drop_items_metadata()
	test_cells_in_annulus_excludes_inner_zone()
	test_cells_in_annulus_degenerates_to_sphere_when_inner_zero()
	# Bow-tie Combatant consumer integrations.
	test_gaseous_combatant_uses_ac_override_11()
	test_gaseous_combatant_uses_movement_override_30()
	test_panicked_combatant_movement_doubles_from_running_multiplier()
	test_gaseous_combatant_is_damaged_only_by_magic_or_silver()
	test_gaseous_combatant_cannot_attack_via_condition_manager()
	# Haste consumer integration (Option 3, 2026-06-01).
	test_hasted_combatant_movement_doubles_via_existing_haste_metadata()
	test_slowed_combatant_movement_halves_via_existing_slow_metadata()
	test_hasted_and_panicked_compound_multipliers()
	if not has_failures():
		print("PanicGaseousForm: all tests passed.")


# ---------------------------------------------------------------------------
# Catalog binding shape
# ---------------------------------------------------------------------------

func test_drums_of_panic_binds_to_panic() -> void:
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("drums_of_panic")
	check(not entry.is_empty(), "drums_of_panic must exist in catalog")
	check(not entry.has("defer_reason"),
		"drums_of_panic should NOT carry defer_reason after unblock")
	var binding: Dictionary = entry.get("spell_binding", {})
	check(str(binding.get("spell_key", "")) == "panic",
		"binding spell_key should be 'panic', got '%s'" % str(binding.get("spell_key", "")))
	check(str(binding.get("tradition", "")) == "arcane",
		"binding tradition should be 'arcane'")
	check(int(binding.get("caster_level", 0)) == 9,
		"binding caster_level should be 9 (mage L9 = min for arcane L5), got %d" %
			int(binding.get("caster_level", 0)))
	print("  drums_of_panic_binds_to_panic: OK")


func test_potion_of_gaseous_form_binds_to_gaseous_form() -> void:
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("potion_of_gaseous_form")
	check(not entry.is_empty(), "potion_of_gaseous_form must exist in catalog")
	check(not entry.has("defer_reason"),
		"potion_of_gaseous_form should NOT carry defer_reason after unblock")
	var binding: Dictionary = entry.get("spell_binding", {})
	check(str(binding.get("spell_key", "")) == "gaseous_form",
		"binding spell_key should be 'gaseous_form', got '%s'" % str(binding.get("spell_key", "")))
	check(int(binding.get("caster_level", 0)) == 5,
		"binding caster_level should be 5 (mage L5 = min for arcane L3), got %d" %
			int(binding.get("caster_level", 0)))
	print("  potion_of_gaseous_form_binds_to_gaseous_form: OK")


# ---------------------------------------------------------------------------
# Panic spell effect
# ---------------------------------------------------------------------------

func test_panic_applies_frightened_on_failed_save() -> void:
	_build_resolver()
	var caster := _make_mage("panic_caster", 9)
	var ctx := _make_ctx(caster)
	var target := _FlagAndConditionTarget.new()
	target.id = "p_target"
	target.hit_dice = 4
	target.save_spells = 17
	# Force save FAILURE (rolled 5 vs target 17).
	_dice.set_fixed("spell_save_spells", 5)
	var choice := SpellChoice.new("panic", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.target_ids = [target.id]
	td.origin_cell = Vector3i(0, 0, 0)
	var result := _resolver.resolve(ctx, choice, td, caster, {target.id: target})
	check(result.success, "Panic resolves successfully")
	check(target.has_condition("frightened"),
		"failed-save target should have 'frightened' condition; got %s" %
			str(target.conditions))
	print("  panic_applies_frightened_on_failed_save: OK")


func test_panic_does_not_apply_on_save_success() -> void:
	_build_resolver()
	var caster := _make_mage("panic_save_caster", 9)
	var ctx := _make_ctx(caster)
	var target := _FlagAndConditionTarget.new()
	target.id = "p_target_save"
	target.save_spells = 17
	# Force save SUCCESS (rolled 20 vs target 17).
	_dice.set_fixed("spell_save_spells", 20)
	var choice := SpellChoice.new("panic", 5, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.target_ids = [target.id]
	td.origin_cell = Vector3i(0, 0, 0)
	_resolver.resolve(ctx, choice, td, caster, {target.id: target})
	check(not target.has_condition("frightened"),
		"saved target should NOT have 'frightened' condition; got %s" %
			str(target.conditions))
	print("  panic_does_not_apply_on_save_success: OK")


func test_panic_uses_area_at_point_sphere_240_feet() -> void:
	# Pin the target_spec shape — verifies the area is a 240' sphere
	# (V1 simplification: no 10' safe zone exclusion; the targeting layer
	# would need annulus support to model "240' minus 10' inner exclusion").
	var spell_registry := SpellRegistry.new()
	var effect_registry := SpellEffectRegistry.new(spell_registry)
	check(effect_registry.has_effect("panic"),
		"panic spell effect must be implemented")
	var payload := effect_registry.get_effect_payload("panic", false, -1)
	var target_spec: Dictionary = payload.get("target_spec", {})
	check(str(target_spec.get("kind", "")) == "area_at_point",
		"target_spec.kind should be 'area_at_point', got '%s'" %
			str(target_spec.get("kind", "")))
	check(str(target_spec.get("shape", "")) == "sphere",
		"target_spec.shape should be 'sphere'")
	check(int(target_spec.get("radius_feet", 0)) == 240,
		"target_spec.radius_feet should be 240, got %d" %
			int(target_spec.get("radius_feet", 0)))
	print("  panic_uses_area_at_point_sphere_240_feet: OK")


# ---------------------------------------------------------------------------
# Gaseous form spell effect
# ---------------------------------------------------------------------------

func test_gaseous_form_sets_is_gaseous_flag() -> void:
	_build_resolver()
	var caster := _make_mage("gas_caster", 5)
	var ctx := _make_ctx(caster)
	var target := _FlagAndConditionTarget.new()
	target.id = "gas_target"
	target.save_spells = 17
	# Force save FAIL — wait, gaseous_form's "save vs Spells negates"
	# applies to UNWILLING targets; for self-cast / willing, no save. V1
	# uses the standard save_spec; for the test we force a save FAILURE
	# so the flag actually lands.
	_dice.set_fixed("spell_save_spells", 5)
	var choice := SpellChoice.new("gaseous_form", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"
	td.target_ids = [target.id]
	var result := _resolver.resolve(ctx, choice, td, caster, {target.id: target})
	check(result.success, "Gaseous Form resolves successfully")
	check(target.flags.has_flag("is_gaseous"),
		"target should have is_gaseous flag after gaseous_form casts")
	print("  gaseous_form_sets_is_gaseous_flag: OK")


func test_gaseous_form_flag_carries_consumer_metadata() -> void:
	# Pin the metadata keys the future consumer integrations will read:
	# ac_override, movement_rate_override, drops_carried_items_on_apply,
	# immune_to_non_magical_weapons, passes_closed_doors_and_portcullis.
	var spell_registry := SpellRegistry.new()
	var effect_registry := SpellEffectRegistry.new(spell_registry)
	check(effect_registry.has_effect("gaseous_form"),
		"gaseous_form spell effect must be implemented")
	var payload := effect_registry.get_effect_payload("gaseous_form", false, -1)
	var resolution: Array = payload.get("resolution", [])
	check(resolution.size() == 1,
		"gaseous_form resolution should have 1 step, got %d" % resolution.size())
	var step: Dictionary = resolution[0]
	check(str(step.get("kind", "")) == "apply_flag",
		"step.kind should be 'apply_flag', got '%s'" % str(step.get("kind", "")))
	check(str(step.get("flag_key", "")) == "is_gaseous",
		"step.flag_key should be 'is_gaseous'")
	var metadata: Dictionary = step.get("metadata", {})
	check(int(metadata.get("ac_override", 0)) == 11,
		"metadata.ac_override should be 11, got %d" % int(metadata.get("ac_override", 0)))
	check(int(metadata.get("movement_rate_override_feet_per_round", 0)) == 30,
		"metadata.movement_rate_override_feet_per_round should be 30")
	check(bool(metadata.get("drops_carried_items_on_apply", false)) == true,
		"metadata.drops_carried_items_on_apply should be true")
	check(bool(metadata.get("immune_to_non_magical_weapons", false)) == true,
		"metadata.immune_to_non_magical_weapons should be true")
	check(bool(metadata.get("passes_closed_doors_and_portcullis", false)) == true,
		"metadata.passes_closed_doors_and_portcullis should be true")
	print("  gaseous_form_flag_carries_consumer_metadata: OK")


# ---------------------------------------------------------------------------
# Portcullis bypass (VoxelCell.is_passable_by_gaseous)
# ---------------------------------------------------------------------------

func test_voxel_cell_is_passable_by_gaseous_through_closed_portcullis() -> void:
	# A closed portcullis blocks ground walkers but lets gas through.
	# RAW: gaseous form can flow below doors and through small unsealed
	# spaces (pc_spell_catalog_f-u.xml:90-126).
	var cell := VoxelCell.new()
	cell.solidity = "air"
	cell.door_type = "portcullis"
	cell.door_state = "closed"
	check(not cell.is_passable_by_walker(),
		"closed portcullis should block a ground walker")
	check(cell.is_passable_by_gaseous(),
		"closed portcullis should NOT block a gaseous mover")
	# Also test the locked door case — same bypass.
	cell.door_type = "wooden"
	cell.door_state = "locked"
	check(not cell.is_passable_by_walker(),
		"locked door should block ground walker")
	check(cell.is_passable_by_gaseous(),
		"locked door should NOT block gaseous mover")
	print("  voxel_cell_is_passable_by_gaseous_through_closed_portcullis: OK")


func test_voxel_cell_is_passable_by_gaseous_blocked_by_solid_wall() -> void:
	# Gas can't pass through SOLID matter — only doors and small openings.
	# A solid wall cell (solidity != "air") refuses gaseous passage too.
	var cell := VoxelCell.new()
	cell.solidity = "solid"
	check(not cell.is_passable_by_gaseous(),
		"solid wall should block gaseous mover (gas can't pass solid matter)")
	check(not cell.is_passable_by_walker(),
		"solid wall blocks ground walker too (sanity)")
	# A liquid cell — gas doesn't flow into water cleanly either; V1 treats
	# any non-air as a blocker.
	cell.solidity = "liquid"
	check(not cell.is_passable_by_gaseous(),
		"liquid cell should block gaseous mover (V1: gas only enters air cells)")
	print("  voxel_cell_is_passable_by_gaseous_blocked_by_solid_wall: OK")


# ---------------------------------------------------------------------------
# Bow-tie consumer integrations (Tier 4 follow-up, 2026-06-01)
# ---------------------------------------------------------------------------

func test_panic_carries_inner_radius_safe_zone() -> void:
	# Panic's target_spec now declares inner_radius_feet: 10 — the
	# 10' safe zone around the caster per RAW. The targeting controller
	# routes sphere + inner_radius_feet through CastingGeometry's new
	# cells_in_annulus helper.
	var spell_registry := SpellRegistry.new()
	var effect_registry := SpellEffectRegistry.new(spell_registry)
	var payload := effect_registry.get_effect_payload("panic", false, -1)
	var target_spec: Dictionary = payload.get("target_spec", {})
	check(int(target_spec.get("inner_radius_feet", 0)) == 10,
		"panic target_spec should carry inner_radius_feet=10 (10' safe zone), got %d" %
			int(target_spec.get("inner_radius_feet", 0)))
	print("  panic_carries_inner_radius_safe_zone: OK")


func test_panic_resolution_includes_running_speed_flag_step() -> void:
	# Panic now applies two resolution steps: (1) frightened condition,
	# (2) is_running_in_panic flag with metadata.movement_multiplier = 2.0
	# (RAW running speed). The Combatant._apply_movement_multipliers
	# consumer reads the multiplier; on cleanup both clear together.
	var spell_registry := SpellRegistry.new()
	var effect_registry := SpellEffectRegistry.new(spell_registry)
	var payload := effect_registry.get_effect_payload("panic", false, -1)
	var resolution: Array = payload.get("resolution", [])
	check(resolution.size() == 2,
		"panic resolution should have 2 steps (condition + running-speed flag), got %d" %
			resolution.size())
	# Step 0: apply_condition frightened.
	check(str((resolution[0] as Dictionary).get("kind", "")) == "apply_condition",
		"resolution[0].kind should be 'apply_condition'")
	check(str((resolution[0] as Dictionary).get("condition_key", "")) == "frightened",
		"resolution[0].condition_key should be 'frightened'")
	# Step 1: apply_flag is_running_in_panic, metadata.movement_multiplier = 2.0
	var step1: Dictionary = resolution[1]
	check(str(step1.get("kind", "")) == "apply_flag",
		"resolution[1].kind should be 'apply_flag'")
	check(str(step1.get("flag_key", "")) == "is_running_in_panic",
		"resolution[1].flag_key should be 'is_running_in_panic'")
	var meta: Dictionary = step1.get("metadata", {})
	check(float(meta.get("movement_multiplier", 0)) == 2.0,
		"movement_multiplier should be 2.0 (RAW running speed), got %.1f" %
			float(meta.get("movement_multiplier", 0)))
	print("  panic_resolution_includes_running_speed_flag_step: OK")


func test_gaseous_form_carries_drop_items_metadata() -> void:
	# Pin the drops_carried_items_on_apply flag-metadata key — consumed
	# by CastingResolver._apply_flag's drop-items hook (which unequips
	# every equipped item on the target at apply time).
	var spell_registry := SpellRegistry.new()
	var effect_registry := SpellEffectRegistry.new(spell_registry)
	var payload := effect_registry.get_effect_payload("gaseous_form", false, -1)
	var resolution: Array = payload.get("resolution", [])
	var step0: Dictionary = resolution[0]
	var meta: Dictionary = step0.get("metadata", {})
	check(bool(meta.get("drops_carried_items_on_apply", false)) == true,
		"gaseous_form step metadata should carry drops_carried_items_on_apply=true")
	print("  gaseous_form_carries_drop_items_metadata: OK")


func test_cells_in_annulus_excludes_inner_zone() -> void:
	# Annulus: cells within outer radius BUT outside inner radius.
	# Use small radii for fast iteration. 25' outer + 10' inner.
	# At 5'/cell: outer_cells_radius = 2 (1 + 2 + 2 = 5 cells wide cube),
	# inner_cells_radius = 1 (3 cells wide cube).
	var origin := Vector3i(0, 0, 0)
	var annulus: Array = CastingGeometry.cells_in_annulus(origin, 25, 10)
	# Origin itself is within inner — must be excluded.
	check(not (origin in annulus),
		"origin (within 10' inner radius) must be excluded from annulus")
	# A cell 1 step away (at 5') is still in the inner radius (1 cell
	# = 5' Chebyshev). Excluded.
	check(not (Vector3i(1, 0, 0) in annulus),
		"cell 5' from origin (still within 10' inner) must be excluded")
	# A cell 2 steps away (10' Chebyshev) — depends on rounding. The
	# helper uses floor(diameter / 2 / 5); for inner_radius 10 →
	# diameter 20 → floor(20/2/5) = 2 → inner cube radius 2 cells.
	# So cells at Chebyshev distance 2 are INSIDE the inner zone.
	check(not (Vector3i(2, 0, 0) in annulus),
		"cell 10' from origin (at or inside 10' inner cube boundary) excluded")
	# A cell 3 steps away (15') is outside the 10' inner exclusion but
	# inside the 25' outer (25' diameter 50 → outer radius 5).
	check(Vector3i(3, 0, 0) in annulus,
		"cell 15' from origin (outside 10' inner, inside 25' outer) included")
	# A cell 10 steps away (50') is outside both — excluded.
	check(not (Vector3i(10, 0, 0) in annulus),
		"cell 50' from origin (outside outer radius) excluded")
	print("  cells_in_annulus_excludes_inner_zone: OK")


func test_cells_in_annulus_degenerates_to_sphere_when_inner_zero() -> void:
	# inner_radius_feet <= 0 → annulus collapses to a plain sphere; the
	# origin and inner cells are included.
	var origin := Vector3i(0, 0, 0)
	var sphere := CastingGeometry.cells_in_radius(origin, 15)
	var annulus_no_exclusion := CastingGeometry.cells_in_annulus(origin, 15, 0)
	check(sphere.size() == annulus_no_exclusion.size(),
		"annulus with inner_radius=0 should match the sphere; sphere has %d, annulus has %d" %
			[sphere.size(), annulus_no_exclusion.size()])
	check(origin in annulus_no_exclusion,
		"annulus with inner_radius=0 should include the origin")
	print("  cells_in_annulus_degenerates_to_sphere_when_inner_zero: OK")


# ---------------------------------------------------------------------------
# Combatant consumer integrations
# ---------------------------------------------------------------------------

## Build a minimal monster Combatant for consumer tests (AC, movement,
## damage immunity, action gating). Goblin-stat baseline; tests then mutate
## flags as needed.
func _make_gaseous_test_monster(id: String) -> Combatant:
	var monster_data := {
		"id": id,
		"name": id,
		"hit_dice": {"base": 1, "modifier": 0},
		"armor_class": 6,
		"attack_routines": [{"sequence": [{"weapon": "claw", "damage": "1d6"}]}],
		"movement": {"land": {"exploration": 120, "combat": 40}},
		"morale": 0,
		"save_as": {"class": "fighter", "level": 1},
		"xp": 10,
	}
	return Combatant.from_monster(monster_data, 4, id, "test_group")


func test_gaseous_combatant_uses_ac_override_11() -> void:
	# A combatant with is_gaseous flag returns AC 11 from
	# get_effective_ac_vs("melee") regardless of its base AC. The
	# override comes from the flag's metadata.ac_override field.
	var c := _make_gaseous_test_monster("gaseous_ac_test")
	var pre_ac := c.get_effective_ac_vs("melee")
	check(pre_ac == 6, "baseline goblin AC should be 6 (from monster_data), got %d" % pre_ac)
	# Set is_gaseous flag with the standard metadata (mirrors spell apply).
	var flags: EntityFlags = c.get_flags()
	flags.set_flag("is_gaseous", "test:gaseous_ac",
		{"ac_override": 11, "movement_rate_override_feet_per_round": 30})
	var post_ac := c.get_effective_ac_vs("melee")
	check(post_ac == 11,
		"gaseous combatant should have AC 11 (RAW override), got %d" % post_ac)
	# Missiles too.
	var missiles_ac := c.get_effective_ac_vs("missiles")
	check(missiles_ac == 11,
		"gaseous combatant should have AC 11 vs missiles too, got %d" % missiles_ac)
	print("  gaseous_combatant_uses_ac_override_11: OK")


func test_gaseous_combatant_uses_movement_override_30() -> void:
	# Gaseous override sets combat movement to 30'/round regardless of
	# the combatant's base. Goblin baseline combat movement is 40 (from
	# the monster_data we built).
	var c := _make_gaseous_test_monster("gaseous_movement_test")
	var pre_move := c.get_combat_movement()
	check(pre_move == 40, "baseline goblin combat movement should be 40, got %d" % pre_move)
	var flags: EntityFlags = c.get_flags()
	flags.set_flag("is_gaseous", "test:gaseous_move",
		{"ac_override": 11, "movement_rate_override_feet_per_round": 30})
	var post_move := c.get_combat_movement()
	check(post_move == 30,
		"gaseous combatant should have 30'/round movement (RAW override), got %d" %
			post_move)
	print("  gaseous_combatant_uses_movement_override_30: OK")


func test_panicked_combatant_movement_doubles_from_running_multiplier() -> void:
	# Panic spell sets is_running_in_panic flag with metadata.movement_multiplier
	# = 2.0. The Combatant._apply_movement_multipliers reads the flag and
	# doubles the combat movement (RAW: "flee at running speed").
	var c := _make_gaseous_test_monster("panicked_test")
	var pre_move := c.get_combat_movement()
	check(pre_move == 40, "baseline goblin combat movement should be 40, got %d" % pre_move)
	var flags: EntityFlags = c.get_flags()
	flags.set_flag("is_running_in_panic", "test:panic_run",
		{"movement_multiplier": 2.0})
	var post_move := c.get_combat_movement()
	check(post_move == 80,
		"panicked combatant should have 80'/round movement (40 base × 2.0 running), got %d" %
			post_move)
	print("  panicked_combatant_movement_doubles_from_running_multiplier: OK")


func test_gaseous_combatant_is_damaged_only_by_magic_or_silver() -> void:
	# Gaseous combatants count as invulnerable for the magic/silver gate
	# (Combatant.is_damaged_only_by_magic_or_silver returns true). This
	# means the existing attack-resolver invulnerability check fires for
	# gaseous targets — no separate wiring needed in attack_resolver.gd /
	# ranged_attack_resolver.gd.
	var c := _make_gaseous_test_monster("gaseous_immune_test")
	check(c.is_damaged_only_by_magic_or_silver() == false,
		"baseline goblin is NOT damaged-only-by-magic")
	var flags: EntityFlags = c.get_flags()
	flags.set_flag("is_gaseous", "test:gaseous_immune", {})
	check(c.is_damaged_only_by_magic_or_silver() == true,
		"gaseous combatant should be damaged-only-by-magic (RAW immunity to non-magical weapons)")
	print("  gaseous_combatant_is_damaged_only_by_magic_or_silver: OK")


func test_gaseous_combatant_cannot_attack_via_condition_manager() -> void:
	# ConditionManager.check_action_allowed now consults the is_gaseous
	# flag and refuses "attacking" + "casting" actions. Other actions
	# (movement, speech) remain permitted.
	var c := _make_gaseous_test_monster("gaseous_action_test")
	var mgr := CombatConditionManager.new(ConditionCatalog.new())
	check(mgr.check_action_allowed(c, "attacking") == true,
		"baseline combatant should be allowed to attack")
	check(mgr.check_action_allowed(c, "casting") == true,
		"baseline combatant should be allowed to cast")
	check(mgr.check_action_allowed(c, "movement") == true,
		"baseline combatant should be allowed to move")
	var flags: EntityFlags = c.get_flags()
	flags.set_flag("is_gaseous", "test:gaseous_action", {})
	check(mgr.check_action_allowed(c, "attacking") == false,
		"gaseous combatant should NOT be allowed to attack")
	check(mgr.check_action_allowed(c, "casting") == false,
		"gaseous combatant should NOT be allowed to cast")
	check(mgr.check_action_allowed(c, "movement") == true,
		"gaseous combatant should still be allowed to move (the whole point)")
	print("  gaseous_combatant_cannot_attack_via_condition_manager: OK")


# ---------------------------------------------------------------------------
# Haste consumer integration (Option 3 — 2026-06-01)
#
# Haste's resolver already sets is_hasted with metadata.movement_multiplier =
# 2.0 (and Slow's reverse branch sets is_slowed with multiplier 0.5). Until
# this commit the multiplier was NOT consumed at runtime (combat-resolver
# integration deferred per haste_resolver.gd notes). The new
# Combatant._apply_movement_multipliers loop reads ANY flag with the
# multiplier metadata key, so Haste plugs in for free — no haste_resolver
# changes needed. These tests pin that flow.
# ---------------------------------------------------------------------------

func test_hasted_combatant_movement_doubles_via_existing_haste_metadata() -> void:
	# Set is_hasted with the multiplier metadata Haste already produces.
	# Combatant._apply_movement_multipliers picks it up automatically.
	var c := _make_gaseous_test_monster("hasted_test")
	check(c.get_combat_movement() == 40, "baseline goblin combat movement = 40")
	var flags: EntityFlags = c.get_flags()
	flags.set_flag("is_hasted", "spell:haste:test", {"movement_multiplier": 2.0})
	check(c.get_combat_movement() == 80,
		"hasted combatant should have 80'/round (40 base × 2.0 multiplier), got %d" %
			c.get_combat_movement())
	print("  hasted_combatant_movement_doubles_via_existing_haste_metadata: OK")


func test_slowed_combatant_movement_halves_via_existing_slow_metadata() -> void:
	# Slow's reverse branch sets is_slowed with movement_multiplier = 0.5.
	# Same generic loop applies; the multiplier compounds (here it halves).
	var c := _make_gaseous_test_monster("slowed_test")
	check(c.get_combat_movement() == 40, "baseline goblin combat movement = 40")
	var flags: EntityFlags = c.get_flags()
	flags.set_flag("is_slowed", "spell:slow:test", {"movement_multiplier": 0.5})
	check(c.get_combat_movement() == 20,
		"slowed combatant should have 20'/round (40 base × 0.5 multiplier), got %d" %
			c.get_combat_movement())
	print("  slowed_combatant_movement_halves_via_existing_slow_metadata: OK")


func test_hasted_and_panicked_compound_multipliers() -> void:
	# Multiple flags with movement_multiplier compound (V1 simplification).
	# Haste + panic running = ×2 × ×2 = ×4. A real player wouldn't
	# typically stack these (Haste+Slow cancel per RAW), but the resolver
	# doesn't enforce mutual exclusion — that's a per-spell concern
	# (haste_resolver auto-dispels the opposite flag). When both are
	# present, multipliers compound.
	var c := _make_gaseous_test_monster("compound_test")
	check(c.get_combat_movement() == 40, "baseline goblin combat movement = 40")
	var flags: EntityFlags = c.get_flags()
	flags.set_flag("is_hasted", "spell:haste:test", {"movement_multiplier": 2.0})
	flags.set_flag("is_running_in_panic", "spell:panic:test", {"movement_multiplier": 2.0})
	check(c.get_combat_movement() == 160,
		"hasted + panicked combatant should have 160'/round (40 × 2 × 2), got %d" %
			c.get_combat_movement())
	print("  hasted_and_panicked_compound_multipliers: OK")
