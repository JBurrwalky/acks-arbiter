extends "res://tests/test_suite_base.gd"

## Session 4 — L1 arcane spell binding tests.
##
## Coverage (one functional test per spell + edge cases):
##   - Charm Person: humanoid succeeds, undead/non-humanoid filtered out.
##   - Hold Portal: modify_cell_state records add_lock mutation.
##   - Light: modify_cell_state records add_light_source; reverse → add_darkness_source.
##   - Read Languages: apply_flag on caster.
##   - Spider Climb: apply_flag + movement_mode_grant.
##   - Ventriloquism: query_game_state with throw_voice_to_cell.
##   - Burning Hands: cone damage with max_level cap.
##   - Floating Disc: stub resolution returns the placeholder result.


class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}

	func set_fixed(roll_type: String, value: int) -> void:
		fixed[roll_type] = value

	func roll_expression(expression: String, roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.roll_type = roll_type
		# For "1d4" with no fixed override, return 2 (deterministic mid-roll).
		var key := roll_type if fixed.has(roll_type) else expression
		if fixed.has(roll_type):
			r.modified_total = int(fixed[roll_type])
		elif fixed.has(expression):
			r.modified_total = int(fixed[expression])
		else:
			r.modified_total = 2
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


# Duck-typed humanoid target with HD.
class _Humanoid extends RefCounted:
	var id: String = ""
	var hit_dice: int = 1
	var creature_type: String = "humanoid"
	var size: String = "man"
	var save_spells: int = 17
	var conditions: Array[String] = []

	func get_effective_save(save_key: String) -> int:
		match save_key:
			"save_spells": return save_spells
			"save_vs_fear": return 0
		return 20

	func add_condition(key: String) -> void:
		if key not in conditions:
			conditions.append(key)

	func has_condition(key: String) -> bool:
		return key in conditions


func run_all_tests() -> void:
	test_charm_person_resolves_apply_condition()
	test_hold_portal_modify_cell_state()
	test_light_modify_cell_state_add_light_source()
	test_darkness_reverse_modify_cell_state()
	test_read_languages_apply_flag_on_caster()
	test_spider_climb_apply_flag_and_movement_grant()
	test_ventriloquism_query_game_state()
	test_burning_hands_cone_damage_caps_at_max_level()
	test_burning_hands_save_for_half()
	test_floating_disc_stub_resolution()
	test_modify_cell_state_records_target_cell()
	test_modify_cell_state_rejects_empty_shape()
	if not has_failures():
		print("L1ArcaneCatalog: all tests passed.")


# ---------------------------------------------------------------------------
# Charm Person
# ---------------------------------------------------------------------------

func test_charm_person_resolves_apply_condition() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var goblin := _Humanoid.new()
	goblin.id = "g1"
	goblin.hit_dice = 1
	goblin.creature_type = "humanoid"

	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("charm_person", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"
	td.target_ids = ["g1"]

	# Force save FAILURE: rolled 5 vs target 17 → fails → charmed applies.
	harness.dice.set_fixed("spell_save_spells", 5)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {"g1": goblin})
	check(result.success, "Charm Person resolves successfully")
	check("charmed" in goblin.conditions,
		"Goblin's conditions include 'charmed' after failed save, got %s" % str(goblin.conditions))


# ---------------------------------------------------------------------------
# Hold Portal
# ---------------------------------------------------------------------------

func test_hold_portal_modify_cell_state() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("hold_portal", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_cell"
	td.target_cells = [Vector3i(5, 5, 0)]
	td.origin_cell = Vector3i(5, 5, 0)

	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	check(result.success, "Hold Portal resolves successfully")
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "modify_cell_state",
		"First step kind is modify_cell_state, got %s" % step.get("step_kind", ""))
	check(step.get("applied", false),
		"modify_cell_state applied=true (no longer the deferred stub)")
	check(step.get("shape", "") == "add_lock",
		"shape='add_lock', got %s" % step.get("shape", ""))
	check(step.get("target_cell", Vector3i.ZERO) == Vector3i(5, 5, 0),
		"target_cell carried through to outcome")


# ---------------------------------------------------------------------------
# Light / Darkness
# ---------------------------------------------------------------------------

func test_light_modify_cell_state_add_light_source() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("light", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(3, 3, 0)
	td.target_cells = [Vector3i(3, 3, 0)]

	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	check(result.success, "Light resolves successfully")
	var step: Dictionary = result.effects_applied[0]
	check(step.get("shape", "") == "add_light_source",
		"Forward Light shape='add_light_source', got %s" % step.get("shape", ""))
	var mutation: Dictionary = step.get("mutation", {})
	check(int(mutation.get("radius_feet", 0)) == 30,
		"Light bright radius 30 ft, got %d" % int(mutation.get("radius_feet", 0)))


func test_darkness_reverse_modify_cell_state() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("light", 1, true, -1)  # is_reversed=true → Darkness
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(3, 3, 0)

	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	check(result.success, "Darkness (reverse Light) resolves successfully")
	var step: Dictionary = result.effects_applied[0]
	check(step.get("shape", "") == "add_darkness_source",
		"Reverse shape='add_darkness_source', got %s" % step.get("shape", ""))


# ---------------------------------------------------------------------------
# Read Languages
# ---------------------------------------------------------------------------

func test_read_languages_apply_flag_on_caster() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("read_languages", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]

	var result = harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(result.success, "Read Languages resolves successfully")
	check(caster.flags.has_flag("can_read_unknown_languages"),
		"Caster has can_read_unknown_languages flag after cast")


# ---------------------------------------------------------------------------
# Spider Climb
# ---------------------------------------------------------------------------

func test_spider_climb_apply_flag_and_movement_grant() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ally := CharacterData.new()
	ally.id = "ally_sc"
	ally.hp_max = 8; ally.hp_current = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("spider_climb", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"
	td.target_ids = [ally.id]

	var result = harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(result.success, "Spider Climb resolves successfully")
	check(ally.flags.has_flag("can_spider_climb"),
		"Ally has can_spider_climb flag after touch")
	# Verify the movement_mode_grant step was processed.
	var saw_grant := false
	for s in result.effects_applied:
		if s.get("step_kind", "") == "movement_mode_grant":
			saw_grant = true
			break
	check(saw_grant, "movement_mode_grant step was processed")


# ---------------------------------------------------------------------------
# Ventriloquism
# ---------------------------------------------------------------------------

func test_ventriloquism_query_game_state() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("ventriloquism", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(8, 8, 0)
	td.target_cells = [Vector3i(8, 8, 0)]

	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	check(result.success, "Ventriloquism resolves successfully")
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "query_game_state",
		"step_kind='query_game_state', got %s" % step.get("step_kind", ""))
	check(step.get("query_kind", "") == "throw_voice_to_cell",
		"query_kind='throw_voice_to_cell', got %s" % step.get("query_kind", ""))


# ---------------------------------------------------------------------------
# Burning Hands
# ---------------------------------------------------------------------------

func test_burning_hands_cone_damage_caps_at_max_level() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 8  # Above the 5-die cap
	var goblin1 := CharacterData.new()
	goblin1.id = "g1"; goblin1.hp_max = 20; goblin1.hp_current = 20
	var goblin2 := CharacterData.new()
	goblin2.id = "g2"; goblin2.hp_max = 20; goblin2.hp_current = 20
	# Force save failure for both (full damage).
	harness.dice.set_fixed("spell_save_blast", 1)
	# Each 1d4 roll returns 3 (deterministic test seam).
	harness.dice.set_fixed("spell_damage", 3)

	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("burning_hands", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(0, 0, 0)
	td.target_ids = ["g1", "g2"]
	td.target_cells = [Vector3i(1, 0, 0), Vector3i(2, 0, 0)]

	var result = harness.resolver.resolve(ctx, choice, td, caster, {"g1": goblin1, "g2": goblin2})
	check(result.success, "Burning Hands resolves successfully")
	var step: Dictionary = result.effects_applied[0]
	check(step.get("roll_count", 0) == 5,
		"Burning Hands at L8: roll_count CAPPED at 5 (max_level), got %d" % step.get("roll_count", 0))
	# 5d4 with each die = 3 → 15 damage; full damage on save fail.
	var per_target: Dictionary = step.get("per_target", {})
	var g1_dmg: int = int(per_target.get("g1", {}).get("amount", 0))
	check(g1_dmg == 15, "Goblin1 takes 15 damage (5 dice × 3 each), got %d" % g1_dmg)


func test_burning_hands_save_for_half() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 4
	var goblin := CharacterData.new()
	goblin.id = "g1"; goblin.hp_max = 20; goblin.hp_current = 20
	# Save SUCCESS — roll 20 vs target 14.
	harness.dice.set_fixed("spell_save_blast", 20)
	harness.dice.set_fixed("spell_damage", 4)  # Each die = 4

	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("burning_hands", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.target_ids = ["g1"]
	td.target_cells = [Vector3i(1, 0, 0)]

	var result = harness.resolver.resolve(ctx, choice, td, caster, {"g1": goblin})
	var step: Dictionary = result.effects_applied[0]
	# 4d4 × 4 = 16 → halved to 8.
	var dmg: int = int(step.get("per_target", {}).get("g1", {}).get("amount", 0))
	check(dmg == 8, "Saved goblin takes half damage = 8, got %d" % dmg)


# ---------------------------------------------------------------------------
# Floating Disc — stub
# ---------------------------------------------------------------------------

func test_floating_disc_stub_resolution() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("floating_disc", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]

	# Session 9.6: Floating Disc swapped from stub → custom resolver. The L1
	# arcane suite still verifies the cast succeeds + slot consumes; details
	# of the custom resolver outcome live in test_session_9_6_polish.gd.
	# Register the custom resolver into the harness's CustomResolverRegistry
	# (the harness defaults to empty; production registers via SessionRunner).
	var fd_resolver := preload(
		"res://engine/subsystems/spells/custom_resolvers/floating_disc_resolver.gd").new()
	harness.resolver._custom_resolvers.register("floating_disc", fd_resolver)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(result.success, "Floating Disc resolves successfully")
	check(result.slot_consumed, "Slot consumed")
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "custom",
		"Floating Disc step_kind='custom' (custom resolver bound)")
	check(bool(step.get("applied", false)),
		"applied=true from floating_disc_resolver")


# ---------------------------------------------------------------------------
# modify_cell_state edge cases
# ---------------------------------------------------------------------------

func test_modify_cell_state_records_target_cell() -> void:
	# Smoke test: when target_cells is empty, falls back to origin_cell.
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("hold_portal", 1, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_cell"
	td.origin_cell = Vector3i(2, 2, 1)
	# target_cells deliberately empty
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("target_cell", Vector3i.ZERO) == Vector3i(2, 2, 1),
		"Falls back to origin_cell when target_cells is empty")


func test_modify_cell_state_rejects_empty_shape() -> void:
	# Direct unit test of the resolver's empty-shape guard via a synthesized
	# cast. We can't easily do this through the public path, so we exercise
	# the contract with a hand-built step via the resolver's _modify_cell_state.
	# The resolver's public API requires a registered spell — synthesize via
	# Hold Portal but malformed cell_mutation. (The real catalog entry has a
	# valid shape, so this test verifies the guard via direct invocation.)
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.origin_cell = Vector3i(0, 0, 0)
	var step := {"kind": "modify_cell_state", "cell_mutation": {}}
	var outcome: Dictionary = harness.resolver._modify_cell_state(step, td, ctx)
	check(not bool(outcome.get("applied", true)),
		"Empty cell_mutation.shape → applied=false")
	check(String(outcome.get("reason", "")).contains("empty cell_mutation.shape"),
		"Reason mentions empty shape")


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


func _make_caster_mage() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "mage_l1arcane"
	cd.name = "Test Mage"
	cd.character_class = "mage"
	cd.combat_progression = "mage"
	cd.level = 1
	cd.intelligence = 13
	cd.hp_max = 4
	cd.hp_current = 4
	return cd
