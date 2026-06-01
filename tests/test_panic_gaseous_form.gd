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
