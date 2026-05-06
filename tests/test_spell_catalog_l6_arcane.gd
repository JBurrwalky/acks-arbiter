extends "res://tests/test_suite_base.gd"

## Session 14 — L6 arcane spell binding tests + 5 custom resolvers
## (death_spell, invisible_stalker, projected_image, reincarnate, wall_of_iron)
## + 2 new conditions (geased, disintegrated).
##
## Coverage:
##   - geased + disintegrated conditions exist in catalog.
##   - Anti-Magic Shell: apply_flag has_anti_magic_shell + RAW gating metadata.
##   - Death Spell (CUSTOM): HD budget + weakest-first + immune cases.
##   - Disintegrate: apply_condition disintegrated + save vs Death.
##   - Flesh to Stone (+ reverse): apply/remove petrified condition.
##   - Geas (+ reverse): apply/remove geased condition.
##   - Globe of Invulnerability: apply_flag with blocks_spell_levels_up_to=4.
##   - Invisible Stalker (CUSTOM): spawn_profile + assigned_task.
##   - Lower Water: modify_cell_state lower_water_depression.
##   - Move Earth: modify_cell_state move_earth.
##   - Projected Image (CUSTOM): image_profile + LoS-break end_condition.
##   - Reincarnate (CUSTOM): reincarnation_roll + alignment column.
##   - Wall of Iron (CUSTOM): area cap with thickness scaling.

const DeathSpellResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/death_spell_resolver.gd")
const InvisibleStalkerResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/invisible_stalker_resolver.gd")
const ProjectedImageResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/projected_image_resolver.gd")
const ReincarnateResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/reincarnate_resolver.gd")
const WallOfIronResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/wall_of_iron_resolver.gd")


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
	var creature_type: String = "humanoid"
	var alignment: String = "neutral"
	var conditions: Array[String] = []
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func remove_condition(k: String) -> void: conditions.erase(k)
	func has_condition(k: String) -> bool: return k in conditions
	func get_effective_save(_key: String) -> int: return 17


func run_all_tests() -> void:
	test_geased_condition_exists()
	test_disintegrated_condition_exists()
	test_anti_magic_shell_apply_flag()
	test_death_spell_kills_within_budget()
	test_death_spell_skips_immune_undead()
	test_death_spell_weakest_first_when_overloaded()
	test_disintegrate_apply_condition_on_save_fail()
	test_flesh_to_stone_petrifies()
	test_stone_to_flesh_reverse_removes_petrified()
	test_geas_applies_geased_condition()
	test_geas_reverse_removes_geased()
	test_globe_of_invulnerability_blocks_4_levels()
	test_invisible_stalker_spawn_profile()
	test_lower_water_modify_cell_state()
	test_move_earth_modify_cell_state()
	test_projected_image_records_image_profile()
	test_reincarnate_records_outcome()
	test_wall_of_iron_thickness_scaling()
	if not has_failures():
		print("L6ArcaneCatalog: all tests passed.")


# ---------------------------------------------------------------------------
# Conditions
# ---------------------------------------------------------------------------

func test_geased_condition_exists() -> void:
	var catalog := ConditionCatalog.new()
	check(not catalog.get_condition("geased").is_empty(), "geased condition exists")


func test_disintegrated_condition_exists() -> void:
	var catalog := ConditionCatalog.new()
	var c: Dictionary = catalog.get_condition("disintegrated")
	check(not c.is_empty(), "disintegrated condition exists")
	check(bool(c.get("is_helpless", false)),
		"disintegrated.is_helpless=true (mechanically dead)")


# ---------------------------------------------------------------------------
# Anti-Magic Shell
# ---------------------------------------------------------------------------

func test_anti_magic_shell_apply_flag() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("anti_magic_shell", 6, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"; td.target_ids = [caster.id]
	harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(caster.flags.has_flag("has_anti_magic_shell"),
		"caster gains has_anti_magic_shell")
	var meta: Dictionary = caster.flags.get_flag_source_entries("has_anti_magic_shell")[0].get("metadata", {})
	check(int(meta.get("radius_feet", 0)) == 10,
		"radius_feet=10 per RAW")
	check(bool(meta.get("blocks_caster_own_spells", false)),
		"blocks_caster_own_spells=true (RAW: shell blocks caster's spells too)")
	check(bool(meta.get("cannot_itself_be_dispelled", false)),
		"cannot_itself_be_dispelled=true per RAW")


# ---------------------------------------------------------------------------
# Death Spell
# ---------------------------------------------------------------------------

func test_death_spell_kills_within_budget() -> void:
	# 4 goblins (1 HD each) within 16-HD budget; force fails save → all 4 killed.
	var resolver = DeathSpellResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 12
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	var goblins: Array = []
	var by_id: Dictionary = {}
	for i in range(4):
		var g := _Mob.new(); g.id = "g%d" % i; g.hit_dice = 1
		goblins.append(g.id); by_id[g.id] = g
	td.target_ids = goblins
	var dice = _FakeDice.new()
	dice.fixed["spell_death_spell_budget"] = 16
	dice.fixed["spell_save_death_spell"] = 1  # force fail
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"targets_by_id": by_id,
		"spell_choice": SpellChoice.new("death_spell", 6, false, -1),
		"step_payload": {"resolver_args": {"dice": dice}},
	}
	var result: Dictionary = resolver.resolve(args)
	check((result.get("killed_ids", []) as Array).size() == 4,
		"all 4 goblins killed within budget, got %d" % (result.get("killed_ids", []) as Array).size())


func test_death_spell_skips_immune_undead() -> void:
	var resolver = DeathSpellResolverScript.new()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	var skel := _Mob.new(); skel.id = "skel"; skel.hit_dice = 1; skel.creature_type = "undead"
	td.target_ids = [skel.id]
	var dice = _FakeDice.new()
	dice.fixed["spell_death_spell_budget"] = 16
	dice.fixed["spell_save_death_spell"] = 1
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"targets_by_id": {skel.id: skel},
		"spell_choice": SpellChoice.new("death_spell", 6, false, -1),
		"step_payload": {"resolver_args": {"dice": dice}},
	}
	var result: Dictionary = resolver.resolve(args)
	check((result.get("killed_ids", []) as Array).size() == 0,
		"undead skipped (immune); 0 killed")


func test_death_spell_weakest_first_when_overloaded() -> void:
	# Budget=2 HD, mob: 1HD goblin + 5HD ogre. Goblin should die, ogre should not.
	var resolver = DeathSpellResolverScript.new()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	var goblin := _Mob.new(); goblin.id = "g"; goblin.hit_dice = 1
	var ogre := _Mob.new(); ogre.id = "o"; ogre.hit_dice = 5
	td.target_ids = [ogre.id, goblin.id]  # ogre first to prove sort works
	var dice = _FakeDice.new()
	dice.fixed["spell_death_spell_budget"] = 2
	dice.fixed["spell_save_death_spell"] = 1
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"targets_by_id": {goblin.id: goblin, ogre.id: ogre},
		"spell_choice": SpellChoice.new("death_spell", 6, false, -1),
		"step_payload": {"resolver_args": {"dice": dice}},
	}
	var result: Dictionary = resolver.resolve(args)
	var killed: Array = result.get("killed_ids", [])
	check(killed.size() == 1 and killed[0] == "g",
		"weakest-first: goblin killed, ogre survives (5 HD > budget remaining)")


# ---------------------------------------------------------------------------
# Disintegrate
# ---------------------------------------------------------------------------

func test_disintegrate_apply_condition_on_save_fail() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 12
	var enemy := _Mob.new(); enemy.id = "e_dis"; enemy.hit_dice = 5
	harness.dice.fixed["spell_save_poison_death"] = 1  # force fail
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("disintegrate", 6, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [enemy.id]
	harness.resolver.resolve(ctx, choice, td, caster, {enemy.id: enemy})
	check(enemy.has_condition("disintegrated"),
		"failed save → 'disintegrated' condition applied")


# ---------------------------------------------------------------------------
# Flesh to Stone / Stone to Flesh
# ---------------------------------------------------------------------------

func test_flesh_to_stone_petrifies() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 12
	var enemy := _Mob.new(); enemy.id = "e_fts"
	harness.dice.fixed["spell_save_paralysis_petrification"] = 1
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("flesh_to_stone", 6, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [enemy.id]
	harness.resolver.resolve(ctx, choice, td, caster, {enemy.id: enemy})
	check(enemy.has_condition("petrified"),
		"Flesh to Stone applies 'petrified' on save fail")


func test_stone_to_flesh_reverse_removes_petrified() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ally := _Mob.new()
	ally.id = "ally_stf"; ally.add_condition("petrified")
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("flesh_to_stone", 6, true, -1)  # reverse
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(not ally.has_condition("petrified"),
		"Stone to Flesh removes 'petrified'")


# ---------------------------------------------------------------------------
# Geas
# ---------------------------------------------------------------------------

func test_geas_applies_geased_condition() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 12
	var enemy := _Mob.new(); enemy.id = "e_geas"
	harness.dice.fixed["spell_save_spells"] = 1
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("geas", 6, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [enemy.id]
	harness.resolver.resolve(ctx, choice, td, caster, {enemy.id: enemy})
	check(enemy.has_condition("geased"),
		"Geas applies 'geased' condition on save fail")


func test_geas_reverse_removes_geased() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var subject := _Mob.new()
	subject.id = "subj_g"; subject.add_condition("geased")
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("geas", 6, true, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [subject.id]
	harness.resolver.resolve(ctx, choice, td, caster, {subject.id: subject})
	check(not subject.has_condition("geased"),
		"Reverse Geas removes 'geased'")


# ---------------------------------------------------------------------------
# Globe of Invulnerability
# ---------------------------------------------------------------------------

func test_globe_of_invulnerability_blocks_4_levels() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 12
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("globe_of_invulnerability", 6, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"; td.target_ids = [caster.id]
	harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(caster.flags.has_flag("has_globe_of_invulnerability"),
		"caster gains has_globe_of_invulnerability")
	var meta: Dictionary = caster.flags.get_flag_source_entries("has_globe_of_invulnerability")[0].get("metadata", {})
	check(int(meta.get("blocks_spell_levels_up_to", 0)) == 4,
		"blocks_spell_levels_up_to=4 per RAW (Major variant)")


# ---------------------------------------------------------------------------
# Invisible Stalker
# ---------------------------------------------------------------------------

func test_invisible_stalker_spawn_profile() -> void:
	var resolver = InvisibleStalkerResolverScript.new()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.origin_cell = Vector3i(5, 5, 0)
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("invisible_stalker", 6, false, -1),
		"step_payload": {"resolver_args": {"assigned_task": "scout_dungeon"}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(String(result.get("assigned_task", "")) == "scout_dungeon",
		"assigned_task='scout_dungeon' propagated")
	var sp: Dictionary = result.get("spawn_profile", {})
	check(bool(sp.get("is_invisible", false)), "stalker is_invisible=true")
	check("dispel_evil" in (sp.get("banishable_only_by", []) as Array),
		"banishable_only_by includes dispel_evil per RAW")


# ---------------------------------------------------------------------------
# Lower Water / Move Earth
# ---------------------------------------------------------------------------

func test_lower_water_modify_cell_state() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 12
	var ctx := CasterContext.from_character_data(caster, "wilderness_hex", "arcane", 0)
	var choice := SpellChoice.new("lower_water", 6, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"; td.origin_cell = Vector3i(0, 0, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "modify_cell_state",
		"Lower Water uses modify_cell_state")


func test_move_earth_modify_cell_state() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 12
	var ctx := CasterContext.from_character_data(caster, "wilderness_hex", "arcane", 0)
	var choice := SpellChoice.new("move_earth", 6, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"; td.origin_cell = Vector3i(10, 10, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "modify_cell_state",
		"Move Earth uses modify_cell_state")


# ---------------------------------------------------------------------------
# Projected Image
# ---------------------------------------------------------------------------

func test_projected_image_records_image_profile() -> void:
	var resolver = ProjectedImageResolverScript.new()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	td.origin_cell = Vector3i(20, 20, 0)
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("projected_image", 6, false, -1),
		"step_payload": {"resolver_args": {}},
	}
	var result: Dictionary = resolver.resolve(args)
	var ip: Dictionary = result.get("image_profile", {})
	check(bool(ip.get("redirects_spell_origin_visually", false)),
		"image redirects_spell_origin_visually=true per RAW")
	var ec: Dictionary = ip.get("end_conditions", {})
	check(bool(ec.get("line_of_sight_broken", false)),
		"end_conditions.line_of_sight_broken=true per RAW")


# ---------------------------------------------------------------------------
# Reincarnate
# ---------------------------------------------------------------------------

func test_reincarnate_records_outcome() -> void:
	var resolver = ReincarnateResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 12
	var corpse := _Mob.new()
	corpse.id = "corpse_r"; corpse.alignment = "lawful"
	var ctx := CasterContext.from_character_data(caster, "settlement", "arcane", 0)
	var td := TargetDescriptor.new()
	td.target_ids = [corpse.id]
	var dice = _FakeDice.new()
	dice.fixed["spell_reincarnate_form"] = 5
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"targets_by_id": {corpse.id: corpse},
		"spell_choice": SpellChoice.new("reincarnate", 6, false, -1),
		"step_payload": {"resolver_args": {"body_present": true, "dice": dice}},
	}
	var result: Dictionary = resolver.resolve(args)
	var pt: Dictionary = result.get("per_target", {})
	var entry: Dictionary = pt.get(corpse.id, {})
	check(int(entry.get("reincarnation_roll", 0)) == 5,
		"reincarnation_roll=5 from forced d10")
	check(String(entry.get("reincarnation_alignment_column", "")) == "lawful",
		"alignment column=lawful from corpse")


# ---------------------------------------------------------------------------
# Wall of Iron
# ---------------------------------------------------------------------------

func test_wall_of_iron_thickness_scaling() -> void:
	# 8 cells × 25 sq ft = 200 sq ft. At 1" thick, 1000 max → fits.
	# At 6" thick, max = 1000/6 = 166 → 200 > 166 → reject.
	var resolver = WallOfIronResolverScript.new()
	var caster := _make_caster_mage()
	caster.level = 12
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var td := TargetDescriptor.new()
	var cells: Array = []
	for i in range(8):
		cells.append(Vector3i(i, 0, 0))
	td.target_cells = cells
	var args := {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("wall_of_iron", 6, false, -1),
		"step_payload": {"resolver_args": {"thickness_inches": 6, "wall_segments": cells}},
	}
	var result: Dictionary = resolver.resolve(args)
	check(not bool(result.get("applied", true)),
		"6\"-thick 200 sq ft wall exceeds 166 max (1000/6)")


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
	cr.register("death_spell", DeathSpellResolverScript.new())
	cr.register("invisible_stalker", InvisibleStalkerResolverScript.new())
	cr.register("projected_image", ProjectedImageResolverScript.new())
	cr.register("reincarnate", ReincarnateResolverScript.new())
	cr.register("wall_of_iron", WallOfIronResolverScript.new())
	h.resolver = CastingResolver.new(sr, er, tracker, cc, cr, null, h.repo, h.dice)
	return h


func _make_caster_mage() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "mage_l6arcane"
	cd.name = "Test Mage L6"
	cd.character_class = "mage"
	cd.combat_progression = "mage"
	cd.level = 11
	cd.intelligence = 16
	cd.hp_max = 22; cd.hp_current = 22
	return cd
