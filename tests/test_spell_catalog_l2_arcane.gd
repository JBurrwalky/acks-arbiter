extends "res://tests/test_suite_base.gd"

## Session 6 — L2 arcane spell binding tests + Web/Phantasmal Force custom resolvers.
##
## Coverage:
##   - Continual Light: modify_cell_state add_light_source w/ continuous flag.
##   - Continual Darkness (reverse): modify_cell_state add_darkness_source.
##   - Detect Invisible: apply_flag can_see_invisible on caster.
##   - ESP: query_game_state read_thoughts.
##   - Invisibility: apply_flag is_invisible w/ ends_on_attack metadata.
##   - Knock: open_close_lock with defeats list including wizard_lock_for_1_turn.
##   - Levitate: apply_flag can_fly w/ vertical_only metadata + movement_mode_grant.
##   - Locate Object: query_game_state locate_named_object.
##   - Magic Mouth: stub.
##   - Mirror Image: grant_mirror_images + flag.
##   - Phantasmal Force (custom): per-viewer disbelief map.
##   - Web (custom): webbed condition + escape_rounds by strength category.
##   - Wizard Lock: open_close_lock operation=lock_magical with lock_metadata.

const WebResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/web_resolver.gd")
const PhantasmalForceResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/phantasmal_force_resolver.gd")


class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}

	func roll_expression(expr: String, roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(roll_type, fixed.get(expr, 2)))
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


# Web-target stand-in: tracks conditions + a strength score the resolver reads.
class _WebTarget extends RefCounted:
	var id: String = ""
	var strength: int = 9
	var conditions: Array[String] = []

	func get_effective_ability_score(name: String) -> int:
		if name == "strength": return strength
		return 9

	func add_condition(key: String) -> void:
		if key not in conditions:
			conditions.append(key)


# Phantasmal Force viewer with save target.
class _PFViewer extends RefCounted:
	var id: String = ""
	var save_spells: int = 17

	func get_effective_save(key: String) -> int:
		if key == "save_spells": return save_spells
		return 20


func run_all_tests() -> void:
	test_continual_light_modify_cell_state()
	test_continual_darkness_reverse_modify_cell_state()
	test_detect_invisible_apply_flag_on_caster()
	test_esp_query_game_state()
	test_invisibility_apply_flag_with_metadata()
	test_knock_open_close_lock_with_defeats()
	test_levitate_apply_flag_and_vertical_movement()
	test_locate_object_query_game_state()
	test_magic_mouth_stub()
	test_mirror_image_grant_and_flag()
	test_wizard_lock_open_close_lock_lock_magical()
	# Custom resolvers
	test_web_resolver_applies_webbed_condition()
	test_web_resolver_escape_rounds_by_strength_normal()
	test_web_resolver_escape_rounds_by_strength_strong()
	test_web_resolver_escape_rounds_by_strength_giant()
	test_phantasmal_force_per_viewer_disbelief_save_success()
	test_phantasmal_force_per_viewer_disbelief_save_failure()
	if not has_failures():
		print("L2ArcaneCatalog: all tests passed.")


# ---------------------------------------------------------------------------
# Continual Light / Darkness
# ---------------------------------------------------------------------------

func test_continual_light_modify_cell_state() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("continual_light", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(5, 5, 0)
	td.target_cells = [Vector3i(5, 5, 0)]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	check(result.success, "Continual Light resolves")
	var step: Dictionary = result.effects_applied[0]
	check(step.get("shape", "") == "add_light_source",
		"shape='add_light_source', got %s" % step.get("shape", ""))
	var mutation: Dictionary = step.get("mutation", {})
	check(int(mutation.get("radius_feet", 0)) == 30,
		"Continual Light bright radius 30 ft")
	check(bool(mutation.get("is_continuous", false)),
		"is_continuous=true (vs Light's torch-equivalent timed mode)")


func test_continual_darkness_reverse_modify_cell_state() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("continual_light", 2, true, -1)  # reverse
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.origin_cell = Vector3i(5, 5, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("shape", "") == "add_darkness_source",
		"reverse shape='add_darkness_source'")


# ---------------------------------------------------------------------------
# Detect Invisible
# ---------------------------------------------------------------------------

func test_detect_invisible_apply_flag_on_caster() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("detect_invisible", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]
	harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(caster.flags.has_flag("can_see_invisible"),
		"caster has can_see_invisible flag")


# ---------------------------------------------------------------------------
# ESP
# ---------------------------------------------------------------------------

func test_esp_query_game_state() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("esp", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "area_from_caster"
	td.target_ids = []
	td.origin_cell = Vector3i(0, 0, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("query_kind", "") == "read_thoughts",
		"ESP query_kind='read_thoughts'")


# ---------------------------------------------------------------------------
# Invisibility
# ---------------------------------------------------------------------------

func test_invisibility_apply_flag_with_metadata() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ally := CharacterData.new()
	ally.id = "ally_inv"
	ally.hp_max = 8; ally.hp_current = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("invisibility", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"
	td.target_ids = [ally.id]
	harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(ally.flags.has_flag("is_invisible"),
		"Ally has is_invisible flag")
	var entries = ally.flags.get_flag_source_entries("is_invisible")
	check(entries.size() == 1, "single source for the flag")
	var meta: Dictionary = entries[0].get("metadata", {})
	check(bool(meta.get("ends_on_attack", false)),
		"metadata.ends_on_attack=true")
	check(bool(meta.get("ends_on_offensive_cast", false)),
		"metadata.ends_on_offensive_cast=true")


# ---------------------------------------------------------------------------
# Knock
# ---------------------------------------------------------------------------

func test_knock_open_close_lock_with_defeats() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("knock", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_cell"
	td.origin_cell = Vector3i(7, 7, 0)
	td.target_cells = [Vector3i(7, 7, 0)]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "open_close_lock",
		"step_kind='open_close_lock'")
	check(step.get("operation", "") == "open", "operation='open'")
	var defeats: Array = step.get("defeats", [])
	check("wizard_lock_for_1_turn" in defeats,
		"defeats includes wizard_lock_for_1_turn (Knock suspends Wizard Lock)")
	check("mundane_lock" in defeats, "defeats includes mundane_lock")
	check(int(step.get("wizard_lock_suspended_turns", 0)) == 1,
		"wizard_lock_suspended_turns=1")


# ---------------------------------------------------------------------------
# Levitate
# ---------------------------------------------------------------------------

func test_levitate_apply_flag_and_vertical_movement() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 4
	var ally := CharacterData.new()
	ally.id = "ally_lev"
	ally.hp_max = 8; ally.hp_current = 8
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("levitate", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"
	td.target_ids = [ally.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {ally.id: ally})
	check(ally.flags.has_flag("can_fly"),
		"Levitate grants can_fly flag")
	var entries = ally.flags.get_flag_source_entries("can_fly")
	var meta: Dictionary = entries[0].get("metadata", {})
	check(bool(meta.get("vertical_only", false)),
		"metadata.vertical_only=true (Levitate is vertical-only)")
	# movement_mode_grant step processed
	var saw_grant := false
	for s in result.effects_applied:
		if s.get("step_kind", "") == "movement_mode_grant":
			saw_grant = true
			break
	check(saw_grant, "movement_mode_grant step processed")


# ---------------------------------------------------------------------------
# Locate Object
# ---------------------------------------------------------------------------

func test_locate_object_query_game_state() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("locate_object", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("query_kind", "") == "locate_named_object",
		"query_kind='locate_named_object'")


# ---------------------------------------------------------------------------
# Magic Mouth — stub
# ---------------------------------------------------------------------------

func test_magic_mouth_stub() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("magic_mouth", 1, false, -1)  # arcane L1 per catalog
	var td := TargetDescriptor.new()
	td.kind = "single_cell"
	td.origin_cell = Vector3i(3, 3, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	check(result.success, "Magic Mouth (stub) resolves successfully")
	check(result.slot_consumed, "Slot consumed for stub")
	var step: Dictionary = result.effects_applied[0]
	check(step.get("step_kind", "") == "stub",
		"step_kind='stub'")
	check(String(step.get("reason", "")) == "requires_triggered_message_subsystem",
		"stub reason set")


# ---------------------------------------------------------------------------
# Mirror Image
# ---------------------------------------------------------------------------

func test_mirror_image_grant_and_flag() -> void:
	var harness := _make_harness()
	# Force the dice to roll 3 figments out of 1d4.
	harness.dice.fixed["spell_mirror_images"] = 3
	harness.dice.fixed["1d4"] = 3
	var caster := _make_caster_mage()
	var ctx := CasterContext.from_character_data(caster, "combat_grid", "arcane", 0)
	var choice := SpellChoice.new("mirror_image", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "self"
	td.target_ids = [caster.id]
	var result = harness.resolver.resolve(ctx, choice, td, caster, {caster.id: caster})
	check(result.success, "Mirror Image resolves")
	check(caster.flags.has_flag("is_mirror_image_protected"),
		"is_mirror_image_protected flag set")
	check(int(caster.mirror_images) > 0,
		"mirror_images count populated, got %d" % caster.mirror_images)


# ---------------------------------------------------------------------------
# Wizard Lock
# ---------------------------------------------------------------------------

func test_wizard_lock_open_close_lock_lock_magical() -> void:
	var harness := _make_harness()
	var caster := _make_caster_mage()
	caster.level = 5
	var ctx := CasterContext.from_character_data(caster, "dungeon_grid", "arcane", 0)
	var choice := SpellChoice.new("wizard_lock", 2, false, -1)
	var td := TargetDescriptor.new()
	td.kind = "single_cell"
	td.origin_cell = Vector3i(8, 8, 0)
	var result = harness.resolver.resolve(ctx, choice, td, caster, {})
	var step: Dictionary = result.effects_applied[0]
	check(step.get("operation", "") == "lock_magical",
		"operation='lock_magical'")
	check(int(step.get("caster_level", 0)) == 5,
		"caster_level recorded for free-pass calculation, got %d" \
			% step.get("caster_level", 0))


# ---------------------------------------------------------------------------
# Web custom resolver
# ---------------------------------------------------------------------------

func test_web_resolver_applies_webbed_condition() -> void:
	var resolver = WebResolverScript.new()
	var goblin := _WebTarget.new()
	goblin.id = "g_web"; goblin.strength = 9
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.target_ids = ["g_web"]
	td.target_cells = [Vector3i(0, 0, 0)]
	var args := {
		"target_descriptor": td,
		"targets_by_id": {"g_web": goblin},
		"caster_context": null,
		"spell_choice": null,
	}
	var result: Dictionary = resolver.resolve(args)
	check(bool(result.get("applied", false)), "web resolver applied")
	check("webbed" in goblin.conditions,
		"goblin has webbed condition, got %s" % str(goblin.conditions))
	check(bool(result.get("flammable", false)),
		"web records flammable=true")


func test_web_resolver_escape_rounds_by_strength_normal() -> void:
	var resolver = WebResolverScript.new()
	var weakling := _WebTarget.new()
	weakling.id = "weak"; weakling.strength = 8  # normal/weak → 2d4 turns avg
	var td := TargetDescriptor.new()
	td.target_ids = ["weak"]
	var result: Dictionary = resolver.resolve({
		"target_descriptor": td,
		"targets_by_id": {"weak": weakling},
		"caster_context": null,
		"spell_choice": null,
	})
	var per_target: Dictionary = result.get("per_target", {})
	check(int(per_target.get("weak", {}).get("escape_rounds", 0)) == 300,
		"normal-strength escape rounds = 300 (5 turns avg of 2d4 turns × 60 rounds/turn)")


func test_web_resolver_escape_rounds_by_strength_strong() -> void:
	var resolver = WebResolverScript.new()
	var brawny := _WebTarget.new()
	brawny.id = "brawn"; brawny.strength = 15  # STR 13-17 → 1 turn = 60 rounds
	var td := TargetDescriptor.new()
	td.target_ids = ["brawn"]
	var result: Dictionary = resolver.resolve({
		"target_descriptor": td,
		"targets_by_id": {"brawn": brawny},
		"caster_context": null,
		"spell_choice": null,
	})
	var per_target: Dictionary = result.get("per_target", {})
	check(int(per_target.get("brawn", {}).get("escape_rounds", 0)) == 60,
		"strong-strength escape rounds = 60 (1 turn)")


func test_web_resolver_escape_rounds_by_strength_giant() -> void:
	var resolver = WebResolverScript.new()
	var ogre := _WebTarget.new()
	ogre.id = "ogre"; ogre.strength = 19  # giant → 2 rounds
	var td := TargetDescriptor.new()
	td.target_ids = ["ogre"]
	var result: Dictionary = resolver.resolve({
		"target_descriptor": td,
		"targets_by_id": {"ogre": ogre},
		"caster_context": null,
		"spell_choice": null,
	})
	var per_target: Dictionary = result.get("per_target", {})
	check(int(per_target.get("ogre", {}).get("escape_rounds", 0)) == 2,
		"giant-strength escape rounds = 2")
	check(String(per_target.get("ogre", {}).get("strength_category", "")) == "giant",
		"strength_category labelled 'giant'")


# ---------------------------------------------------------------------------
# Phantasmal Force custom resolver
# ---------------------------------------------------------------------------

func test_phantasmal_force_per_viewer_disbelief_save_success() -> void:
	var resolver = PhantasmalForceResolverScript.new()
	var viewer := _PFViewer.new()
	viewer.id = "v1"; viewer.save_spells = 17
	var td := TargetDescriptor.new()
	td.target_ids = ["v1"]
	td.origin_cell = Vector3i(0, 0, 0)
	var args := {
		"target_descriptor": td,
		"targets_by_id": {"v1": viewer},
		"caster_context": null,
		"spell_choice": null,
		"step_payload": {},
		"dice_override": 18,  # roll 18 vs target 17 → succeeds → disbelieves
	}
	var result: Dictionary = resolver.resolve(args)
	check(bool(result.get("applied", false)), "PF resolver applied")
	var per_viewer: Dictionary = result.get("per_viewer", {})
	check(bool(per_viewer.get("v1", {}).get("disbelieves", false)),
		"viewer disbelieves on save success (rolled 18 vs target 17)")


func test_phantasmal_force_per_viewer_disbelief_save_failure() -> void:
	var resolver = PhantasmalForceResolverScript.new()
	var viewer := _PFViewer.new()
	viewer.id = "v2"; viewer.save_spells = 17
	var td := TargetDescriptor.new()
	td.target_ids = ["v2"]
	var args := {
		"target_descriptor": td,
		"targets_by_id": {"v2": viewer},
		"caster_context": null,
		"spell_choice": null,
		"step_payload": {},
		"dice_override": 5,  # roll 5 vs target 17 → fails → does NOT disbelieve
	}
	var result: Dictionary = resolver.resolve(args)
	var per_viewer: Dictionary = result.get("per_viewer", {})
	check(not bool(per_viewer.get("v2", {}).get("disbelieves", true)),
		"viewer does NOT disbelieve on save failure")


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
	# Register custom resolvers directly for the resolver-driven tests
	# (Phantasmal Force uses dice_override args path which doesn't need
	# the registry — direct resolver call). Web's Web binding routes
	# through cr in the L2 catalog test that hits the full resolver, so
	# we register here too.
	cr.register("web", WebResolverScript.new())
	cr.register("phantasmal_force", PhantasmalForceResolverScript.new())
	h.resolver = CastingResolver.new(sr, er, tracker, cc, cr, null, h.repo, h.dice)
	return h


func _make_caster_mage() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "mage_l2arcane"
	cd.name = "Test Mage"
	cd.character_class = "mage"
	cd.combat_progression = "mage"
	cd.level = 1
	cd.intelligence = 13
	cd.hp_max = 4
	cd.hp_current = 4
	return cd
