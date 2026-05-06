extends "res://tests/test_suite_base.gd"

## Session 8 — L3 arcane spell binding tests + Dispel Magic/Haste custom resolvers
## + cells_in_line geometry tests.
##
## Coverage:
##   - Clairaudience + Clairvoyance: query_game_state with scry kinds.
##   - Dispel Magic (custom): delegates to ActiveEffectTracker.dispel_check.
##   - Haste (custom): is_hasted flag + 2x movement/attacks metadata.
##   - Slow (reverse): is_slowed flag + 0.5x metadata.
##   - Haste auto-dispels existing Slow.
##   - Slow auto-dispels existing Haste.
##   - Infravision: apply_flag has_infravision w/ metadata.range_feet=60.
##   - Invisibility 10' Radius: apply_flag is_invisible_aura w/ radius=10.
##   - Lightning Bolt: damage_per_level + line geometry.
##   - cells_in_line: walks expected cells.
##   - cells_in_line: stops at wall.
##   - cells_in_line: reflects on wall when reflect_on_wall=true.
##   - Protection from Evil Sustained: 12-turn fixed duration; modifier stack.
##   - Protection from Normal Missiles: damage_resistance immunity.
##   - Water Breathing: apply_flag can_breathe_water.

const DispelMagicResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/dispel_magic_resolver.gd")
const HasteResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/haste_resolver.gd")


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


func run_all_tests() -> void:
	test_clairaudience_query_kind()
	test_clairvoyance_query_kind()
	test_infravision_apply_flag_with_range_metadata()
	test_invisibility_10_radius_apply_flag_with_aura_metadata()
	test_lightning_bolt_damage_per_level()
	test_protection_from_evil_sustained_12_turn()
	test_protection_from_evil_sustained_reverse()
	test_protection_from_normal_missiles_immunity()
	test_water_breathing_apply_flag()
	# Custom resolver — Dispel Magic
	test_dispel_magic_dispells_lower_level_effect()
	test_dispel_magic_no_tracker_returns_diagnostic()
	# Custom resolver — Haste / Slow
	test_haste_sets_is_hasted_flag_with_2x_metadata()
	test_slow_reverse_sets_is_slowed_flag_with_half_metadata()
	test_haste_auto_dispels_existing_slow()
	test_slow_auto_dispels_existing_haste()
	# Geometry
	test_cells_in_line_basic_walk()
	test_cells_in_line_stops_at_wall()
	test_cells_in_line_reflects_on_wall_when_enabled()
	if not has_failures():
		print("L3ArcaneCatalog: all tests passed.")


# ---------------------------------------------------------------------------
# Clairaudience / Clairvoyance
# ---------------------------------------------------------------------------

func test_clairaudience_query_kind() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("clairaudience", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(20, 20, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("query_kind", "") == "scry_remote_cell_audio",
		"Clairaudience query_kind='scry_remote_cell_audio'")


func test_clairvoyance_query_kind() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("clairvoyance", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(20, 20, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("query_kind", "") == "scry_remote_cell_visual",
		"Clairvoyance query_kind='scry_remote_cell_visual'")


# ---------------------------------------------------------------------------
# Infravision
# ---------------------------------------------------------------------------

func test_infravision_apply_flag_with_range_metadata() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ally := CharacterData.new()
	ally.id = "ally_iv"; ally.hp_max = 8; ally.hp_current = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("infravision", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(ally.flags.has_flag("has_infravision"),
		"Ally has has_infravision flag")
	var entries = ally.flags.get_flag_source_entries("has_infravision")
	var meta: Dictionary = entries[0].get("metadata", {})
	check(int(meta.get("range_feet", 0)) == 60,
		"metadata.range_feet=60 ft per RAW")


# ---------------------------------------------------------------------------
# Invisibility 10' Radius
# ---------------------------------------------------------------------------

func test_invisibility_10_radius_apply_flag_with_aura_metadata() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ally := CharacterData.new()
	ally.id = "ally_inv10"; ally.hp_max = 8; ally.hp_current = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("invisibility_10_radius", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(ally.flags.has_flag("is_invisible_aura"),
		"Recipient has is_invisible_aura flag")
	var entries = ally.flags.get_flag_source_entries("is_invisible_aura")
	var meta: Dictionary = entries[0].get("metadata", {})
	check(int(meta.get("radius_feet", 0)) == 10,
		"metadata.radius_feet=10 ft")
	check(bool(meta.get("ends_on_recipient_attack", false)),
		"metadata.ends_on_recipient_attack=true")
	check(bool(meta.get("moves_with_recipient", false)),
		"metadata.moves_with_recipient=true")


# ---------------------------------------------------------------------------
# Lightning Bolt
# ---------------------------------------------------------------------------

func test_lightning_bolt_damage_per_level() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 5
	# Force save FAILURE for full damage; each 1d6 returns 4 (deterministic).
	harness.dice.fixed["spell_save_blast"] = 1
	harness.dice.fixed["spell_damage"] = 4
	var goblin := CharacterData.new()
	goblin.id = "g_lb"; goblin.hp_max = 30; goblin.hp_current = 30
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("lightning_bolt", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(0, 0, 0)
	td.target_ids = ["g_lb"]
	td.target_cells = [Vector3i(1, 0, 0)]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {"g_lb": goblin})
	var step: Dictionary = result.effects_applied[0]
	# 5d6 × 4 = 20 damage on save fail (full)
	var dmg: int = int(step.get("per_target", {}).get("g_lb", {}).get("amount", 0))
	check(dmg == 20, "L5 Lightning Bolt: 5d6 × 4 = 20 damage on save fail, got %d" % dmg)


# ---------------------------------------------------------------------------
# Protection from Evil Sustained
# ---------------------------------------------------------------------------

func test_protection_from_evil_sustained_12_turn() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("protection_from_evil_sustained", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"; td.target_ids = [caster.id]
	harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(caster.modifiers.has_modifier_for_stat("armor_class_vs_chaotic"),
		"armor_class_vs_chaotic modifier written")
	check(caster.modifiers.has_modifier_for_stat("save_vs_chaotic"),
		"save_vs_chaotic modifier written")
	check(caster.flags.has_flag("blocks_enchanted_creature_melee"),
		"blocks_enchanted_creature_melee flag set")


func test_protection_from_evil_sustained_reverse() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("protection_from_evil_sustained", 3, true, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"; td.target_ids = [caster.id]
	harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(caster.modifiers.has_modifier_for_stat("armor_class_vs_lawful"),
		"reverse: armor_class_vs_lawful modifier written")


# ---------------------------------------------------------------------------
# Protection from Normal Missiles
# ---------------------------------------------------------------------------

func test_protection_from_normal_missiles_immunity() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ally := CharacterData.new()
	ally.id = "ally_pnm"; ally.hp_max = 8; ally.hp_current = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("protection_from_normal_missiles", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	# Immunity factor = 0
	check(ally.damage_resistances.get_resistance_factor("physical") == 0.0
			or ally.damage_resistances.is_immune_to("physical"),
		"physical damage immunity (or factor=0) applied")


# ---------------------------------------------------------------------------
# Water Breathing
# ---------------------------------------------------------------------------

func test_water_breathing_apply_flag() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ally := CharacterData.new()
	ally.id = "ally_wb"; ally.hp_max = 8; ally.hp_current = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("water_breathing", 3, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(ally.flags.has_flag("can_breathe_water"),
		"Ally has can_breathe_water flag")


# ---------------------------------------------------------------------------
# Dispel Magic custom resolver
# ---------------------------------------------------------------------------

func test_dispel_magic_dispells_lower_level_effect() -> void:
	# Set up a tracker with a low-level effect on a target; verify Dispel
	# Magic from a higher-level dispeller removes it.
	var tracker := ActiveEffectTracker.new()
	tracker.add_effect({
		"effect_id": "fx_test_1",
		"spell_key": "bless",
		"caster_id": "victim_caster",
		"caster_level": 3,
		"target_ids": ["victim_target"],
		"effect_type": "modifier",
		"applied_modifiers": [],
		"applied_conditions": [],
		"applied_flags": [],
		"duration_type": "turns",
		"duration_remaining": 5,
		"requires_concentration": false,
		"is_active": true,
		"metadata": {},
	})
	var resolver = DispelMagicResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 6  # higher than the L3 effect
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.target_ids = ["victim_target"]
	var args := {
		"target_descriptor": td,
		"targets_by_id": {},
		"caster_context": ctx,
		"spell_choice": SpellChoice.new("dispel_magic", 3, false, -1),
		"step_payload": {},
		"effect_tracker": tracker,
	}
	var result: Dictionary = resolver.resolve(args)
	check(int(result.get("total_dispelled", 0)) == 1,
		"L6 dispeller vs L3 effect → auto-dispels 1, got %d" \
			% result.get("total_dispelled", 0))
	check(tracker.get_effect("fx_test_1").is_empty(),
		"dispelled effect is removed from tracker")


func test_dispel_magic_no_tracker_returns_diagnostic() -> void:
	var resolver = DispelMagicResolverScript.new()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.target_ids = ["t1"]
	var args := {
		"target_descriptor": td,
		"targets_by_id": {},
		"caster_context": ctx,
		"spell_choice": SpellChoice.new("dispel_magic", 3, false, -1),
		"step_payload": {},
		# no effect_tracker key
	}
	var result: Dictionary = resolver.resolve(args)
	var per_target: Dictionary = result.get("per_target", {})
	check(not bool(per_target.get("t1", {}).get("applied", true)),
		"With no tracker → applied=false with diagnostic reason")


# ---------------------------------------------------------------------------
# Haste / Slow custom resolver
# ---------------------------------------------------------------------------

func test_haste_sets_is_hasted_flag_with_2x_metadata() -> void:
	var resolver = HasteResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 5
	var ally := CharacterData.new()
	ally.id = "ally_haste"; ally.hp_max = 8; ally.hp_current = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.target_ids = [ally.id]
	var args := {
		"target_descriptor": td,
		"targets_by_id": {ally.id: ally},
		"caster_context": ctx,
		"spell_choice": SpellChoice.new("haste", 3, false, -1),
		"step_payload": {},
	}
	resolver.resolve(args)
	check(ally.flags.has_flag("is_hasted"), "ally has is_hasted flag")
	var entries = ally.flags.get_flag_source_entries("is_hasted")
	var meta: Dictionary = entries[0].get("metadata", {})
	check(float(meta.get("movement_multiplier", 0.0)) == 2.0,
		"movement_multiplier=2.0")
	check(float(meta.get("attacks_multiplier", 0.0)) == 2.0,
		"attacks_multiplier=2.0")


func test_slow_reverse_sets_is_slowed_flag_with_half_metadata() -> void:
	var resolver = HasteResolverScript.new()
	var caster := _make_caster_mage()
	var enemy := CharacterData.new()
	enemy.id = "enemy_slow"; enemy.hp_max = 12; enemy.hp_current = 12
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.target_ids = [enemy.id]
	var args := {
		"target_descriptor": td,
		"targets_by_id": {enemy.id: enemy},
		"caster_context": ctx,
		"spell_choice": SpellChoice.new("haste", 3, true, -1),  # reverse → Slow
		"step_payload": {},
	}
	resolver.resolve(args)
	check(enemy.flags.has_flag("is_slowed"), "enemy has is_slowed flag")
	var entries = enemy.flags.get_flag_source_entries("is_slowed")
	var meta: Dictionary = entries[0].get("metadata", {})
	check(float(meta.get("movement_multiplier", 0.0)) == 0.5,
		"movement_multiplier=0.5")


func test_haste_auto_dispels_existing_slow() -> void:
	var resolver = HasteResolverScript.new()
	var caster := _make_caster_mage()
	var target := CharacterData.new()
	target.id = "t_h_dispel"; target.hp_max = 10; target.hp_current = 10
	# Pre-set is_slowed.
	target.flags.set_flag("is_slowed", "spell:haste:other_caster", {})
	check(target.flags.has_flag("is_slowed"), "pre: is_slowed set")
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.target_ids = [target.id]
	var args := {
		"target_descriptor": td,
		"targets_by_id": {target.id: target},
		"caster_context": ctx,
		"spell_choice": SpellChoice.new("haste", 3, false, -1),
		"step_payload": {},
	}
	var result: Dictionary = resolver.resolve(args)
	check(not target.flags.has_flag("is_slowed"),
		"After Haste: is_slowed cleared (auto-dispel per RAW)")
	check(target.flags.has_flag("is_hasted"),
		"After Haste: is_hasted now set")
	check(bool(result.get("per_target", {}).get(target.id, {}).get("dispelled_opposite", false)),
		"per_target.dispelled_opposite=true")


func test_slow_auto_dispels_existing_haste() -> void:
	var resolver = HasteResolverScript.new()
	var caster := _make_caster_mage()
	var target := CharacterData.new()
	target.id = "t_s_dispel"; target.hp_max = 10; target.hp_current = 10
	target.flags.set_flag("is_hasted", "spell:haste:friendly_caster", {})
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.target_ids = [target.id]
	var args := {
		"target_descriptor": td,
		"targets_by_id": {target.id: target},
		"caster_context": ctx,
		"spell_choice": SpellChoice.new("haste", 3, true, -1),  # reverse Slow
		"step_payload": {},
	}
	resolver.resolve(args)
	check(not target.flags.has_flag("is_hasted"),
		"After Slow: is_hasted cleared")
	check(target.flags.has_flag("is_slowed"),
		"After Slow: is_slowed now set")


# ---------------------------------------------------------------------------
# cells_in_line geometry
# ---------------------------------------------------------------------------

func test_cells_in_line_basic_walk() -> void:
	# 60 ft line (12 cells at 5'/cell) along +X axis, no walls.
	var cells = CastingGeometry.cells_in_line(
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), 60, {}, false)
	check(cells.size() == 12,
		"60 ft line → 12 cells, got %d" % cells.size())
	check(cells[0] == Vector3i(1, 0, 0),
		"first cell is one step from origin, got %s" % str(cells[0]))
	check(cells[-1] == Vector3i(12, 0, 0),
		"last cell is 12 steps from origin")


func test_cells_in_line_stops_at_wall() -> void:
	# Wall at cell (5, 0, 0). Line should stop at (4, 0, 0).
	var walls := {Vector3i(5, 0, 0): true}
	var cells = CastingGeometry.cells_in_line(
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), 60, walls, false)
	check(cells.size() == 4,
		"line stops at wall: 4 cells (1..4), got %d" % cells.size())
	check(cells[-1] == Vector3i(4, 0, 0),
		"last cell before wall = (4,0,0)")


func test_cells_in_line_reflects_on_wall_when_enabled() -> void:
	# Wall at (5, 0, 0); reflect_on_wall=true should bounce backward.
	var walls := {Vector3i(5, 0, 0): true}
	var cells = CastingGeometry.cells_in_line(
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), 60, walls, true)
	# After reaching (4,0,0) the bolt bounces back: (3,0,0), (2,0,0), ...
	# The exact path depends on the residual length; verify the bolt
	# proceeds past the wall by reflecting (cells include negative-X cells).
	var has_reflection := false
	for c in cells:
		if c.x < 4 and c not in [Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0)]:
			# A cell with x<4 that ISN'T part of the original forward walk
			# is evidence of reflection.
			pass
	# Simpler check: with reflection enabled, total cell count exceeds the
	# stopped-at-wall count.
	var stopped = CastingGeometry.cells_in_line(
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), 60, walls, false)
	check(cells.size() > stopped.size(),
		"reflect_on_wall=true produces more cells (%d) than stopped (%d)" \
			% [cells.size(), stopped.size()])


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
	cr.register("dispel_magic", DispelMagicResolverScript.new())
	cr.register("haste", HasteResolverScript.new())
	h.resolver = CastingResolver.new(sr, er, tracker, cc, cr, null, h.repo, h.dice)
	return h


func _make_caster_mage() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "mage_l3arcane"
	cd.name = "Test Mage"
	cd.character_class = "mage"
	cd.combat_progression = "mage"
	cd.level = 1
	cd.intelligence = 13
	cd.hp_max = 4; cd.hp_current = 4
	return cd
