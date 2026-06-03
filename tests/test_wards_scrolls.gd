extends "res://tests/test_suite_base.gd"

## 2026-06-02 — Scrolls of Warding cluster (4 items).
##
## Coverage:
##   - Catalog: 4 scrolls have `direct_consumable_effect` with correct
##     effect_kind + (creature_types | ward_kind) + radius_feet + caster_level.
##   - MagicItemActivator.activate_consumable: validates scroll category,
##     refuses missing direct_consumable_effect, applies flag with correct
##     metadata, consumes scroll on success, returns structured result.
##   - SpellCombatHooks.on_pre_attack ward_against_creature_type cancel:
##     attacker with matching creature_type save vs Spells fails → attack
##     cancelled; success → attack proceeds; non-matching creature_type
##     ignored; cache hits on repeat attempts per (attacker, source_id).
##   - CastingResolver._check_ward_against_magic_block: caster as bearer +
##     external target → blocked; target as bearer + external caster →
##     blocked; self-cast → exempt; no ward → no block.


# ---------------------------------------------------------------------------
# Fakes
# ---------------------------------------------------------------------------

class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}
	func roll_digital(s: int, c: int = 1, m: int = 0, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, c * s)) + m
		r.raw_total = r.modified_total - m
		return r


class _Attacker extends RefCounted:
	var id: String = ""
	var creature_type: String = ""
	var flags: EntityFlags = EntityFlags.new()
	var sanctuary_blocked_targets: Array = []
	func get_flags() -> EntityFlags: return flags
	func is_creature_type(t: String) -> bool: return creature_type.to_lower() == t.to_lower()
	func get_effective_save(_k: String) -> int: return 11


class _Bearer extends RefCounted:
	var id: String = ""
	var flags: EntityFlags = EntityFlags.new()
	func get_flags() -> EntityFlags: return flags


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_reader(level: int = 5) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "reader_test"
	cd.name = "Test Reader"
	cd.character_class = "fighter"
	cd.combat_progression = "fighter"
	cd.level = level
	cd.hp_max = 10; cd.hp_current = 10
	return cd


func run_all_tests() -> void:
	# Catalog
	test_catalog_warding_elementals_has_direct_consumable_effect()
	test_catalog_warding_lycanthropes_has_direct_consumable_effect()
	test_catalog_warding_undead_has_direct_consumable_effect()
	test_catalog_warding_magic_has_direct_consumable_effect()
	test_catalog_wards_not_in_expected_defer_list()
	# activate_consumable behavior
	test_activate_consumable_applies_creature_type_ward()
	test_activate_consumable_applies_magic_ward()
	test_activate_consumable_refuses_non_scroll_category()
	test_activate_consumable_refuses_missing_direct_effect()
	test_activate_consumable_metadata_radius_caster_level()
	# Combat hook
	test_hook_cancels_attack_from_matching_creature_type_on_save_fail()
	test_hook_allows_attack_on_save_success()
	test_hook_ignores_non_matching_creature_type()
	test_hook_caches_save_per_attacker_per_source()
	# CastingResolver gate
	test_gate_blocks_caster_bearer_external_target()
	test_gate_blocks_target_bearer_external_caster()
	test_gate_allows_self_cast_even_with_ward()
	test_gate_no_block_when_no_ward_present()
	if not has_failures():
		print("WardsScrolls: all tests passed.")


# ---------------------------------------------------------------------------
# Catalog tests
# ---------------------------------------------------------------------------

func _read_catalog() -> Array:
	var path := "res://data/treasure/magic_item_catalog.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return []
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	return d.get("items", [])


func _find(items: Array, key: String) -> Dictionary:
	for v in items:
		if String((v as Dictionary).get("item_key", "")) == key:
			return v
	return {}


func _assert_creature_type_ward(key: String, expected_types: Array) -> void:
	var items := _read_catalog()
	var it: Dictionary = _find(items, key)
	check(not it.is_empty(), "%s present in catalog" % key)
	if it.is_empty(): return
	var dce: Variant = it.get("direct_consumable_effect", null)
	check(dce is Dictionary, "%s has direct_consumable_effect Dictionary" % key)
	if not (dce is Dictionary): return
	var dce_d: Dictionary = dce
	check(String(dce_d.get("effect_kind", "")) == "ward_against_creature_type",
		"%s effect_kind=ward_against_creature_type" % key)
	var ct: Array = dce_d.get("creature_types", [])
	check(ct.size() == expected_types.size(),
		"%s creature_types size=%d" % [key, expected_types.size()])
	for t in expected_types:
		check(t in ct, "%s creature_types contains '%s'" % [key, t])
	check(int(dce_d.get("radius_feet", 0)) == 10, "%s radius_feet=10" % key)
	check(int(dce_d.get("caster_level", 0)) == 5, "%s caster_level=5" % key)


func test_catalog_warding_elementals_has_direct_consumable_effect() -> void:
	_assert_creature_type_ward("scroll_of_warding_elementals", ["elemental"])


func test_catalog_warding_lycanthropes_has_direct_consumable_effect() -> void:
	_assert_creature_type_ward("scroll_of_warding_lycanthropes", ["lycanthrope"])


func test_catalog_warding_undead_has_direct_consumable_effect() -> void:
	_assert_creature_type_ward("scroll_of_warding_undead", ["undead"])


func test_catalog_warding_magic_has_direct_consumable_effect() -> void:
	var items := _read_catalog()
	var it: Dictionary = _find(items, "scroll_of_warding_magic")
	check(not it.is_empty(), "scroll_of_warding_magic present")
	if it.is_empty(): return
	var dce: Dictionary = it.get("direct_consumable_effect", {})
	check(String(dce.get("effect_kind", "")) == "ward_against_magic",
		"scroll_of_warding_magic effect_kind=ward_against_magic")
	check(int(dce.get("radius_feet", 0)) == 10, "magic ward radius_feet=10")
	check(int(dce.get("caster_level", 0)) == 5, "magic ward caster_level=5")


func test_catalog_wards_not_in_expected_defer_list() -> void:
	# Test infrastructure tracks deferred items via EXPECTED_DEFER_KEYS in
	# tests/test_magic_item_catalog.gd. Verify the 4 scroll keys are NOT
	# present there (they shipped this commit).
	var path := "res://tests/test_magic_item_catalog.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		check(false, "test_magic_item_catalog.gd should be readable")
		return
	var content := f.get_as_text()
	f.close()
	# We only check the constant block; the comment lines describing the
	# clearance reference the keys, so use the array literal-ish pattern:
	# the keys should NOT appear bare-quoted as Array members. A coarse
	# but reliable check: count quoted instances; only the comment block
	# should mention them (the comment block uses bullets / sentences).
	for k in ["scroll_of_warding_elementals", "scroll_of_warding_lycanthropes",
			"scroll_of_warding_magic", "scroll_of_warding_undead"]:
		# Look for the array-literal form: '"<key>"' followed by comma.
		var bare: String = '"' + String(k) + '",'
		check(not content.contains(bare),
			"%s should NOT appear as bare array member in EXPECTED_DEFER_KEYS" % k)


# ---------------------------------------------------------------------------
# activate_consumable behavior
# ---------------------------------------------------------------------------

const _CAMPAIGN_ID := "ward_scroll_test_campaign"
const _READER_ID := "ward_reader_id"
var _reader: CharacterData = null


func _setup() -> void:
	# Wipe + seed minimal campaign so add_inventory_item works. Use the
	# raw INSERT OR IGNORE pattern used by other magic-item tests.
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_CAMPAIGN_ID, "Ward Test", "Test World"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [_READER_ID, _CAMPAIGN_ID, "Ward Reader", "fighter", 5, 0, 10, 10])
	GameState.campaign_id = _CAMPAIGN_ID
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_READER_ID])
	_reader = _make_reader(5)
	_reader.id = _READER_ID
	_reader.campaign_id = _CAMPAIGN_ID


func _teardown() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_READER_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_READER_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_CAMPAIGN_ID])


func _make_catalog() -> MagicItemCatalog:
	return MagicItemCatalog.new()


func test_activate_consumable_applies_creature_type_ward() -> void:
	_setup()
	var scroll_id := CampaignRepository.add_inventory_item({
		"character_id": _reader.id, "item_key": "scroll_of_warding_undead",
		"name": "Scroll of Warding against Undead", "is_magical": true,
	})
	var result: Dictionary = MagicItemActivator.activate_consumable(
		scroll_id, _reader, _make_catalog())
	check(bool(result["success"]) == true,
		"activate_consumable should succeed; msg=%s" % str(result["message"]))
	check(bool(result["consumed"]) == true,
		"scroll consumed on success")
	check(String(result["flag_set"]) == "warded_against_creature_type",
		"flag_set=warded_against_creature_type")
	check(_reader.flags.has_flag("warded_against_creature_type"),
		"reader carries the flag")
	var meta: Dictionary = _reader.flags.get_flag_metadata("warded_against_creature_type")
	check("undead" in (meta.get("creature_types", []) as Array),
		"flag metadata creature_types contains undead")
	check(int(meta.get("radius_feet", 0)) == 10, "metadata.radius_feet=10")
	_teardown()


func test_activate_consumable_applies_magic_ward() -> void:
	_setup()
	var scroll_id := CampaignRepository.add_inventory_item({
		"character_id": _reader.id, "item_key": "scroll_of_warding_magic",
		"name": "Scroll of Warding against Magic", "is_magical": true,
	})
	var result: Dictionary = MagicItemActivator.activate_consumable(
		scroll_id, _reader, _make_catalog())
	check(bool(result["success"]) == true, "magic ward applies")
	check(String(result["flag_set"]) == "warded_against_magic",
		"flag_set=warded_against_magic")
	check(_reader.flags.has_flag("warded_against_magic"),
		"reader carries warded_against_magic flag")
	var meta: Dictionary = _reader.flags.get_flag_metadata("warded_against_magic")
	check(String(meta.get("bearer_id", "")) == _reader.id,
		"metadata.bearer_id == reader.id")
	check(int(meta.get("radius_feet", 0)) == 10, "magic ward radius=10")
	_teardown()


func test_activate_consumable_refuses_non_scroll_category() -> void:
	_setup()
	# Use a potion key — wrong category for activate_consumable.
	var pot_id := CampaignRepository.add_inventory_item({
		"character_id": _reader.id, "item_key": "potion_of_healing",
		"name": "Potion of Healing", "is_magical": true, "uses_remaining": 1,
	})
	var result: Dictionary = MagicItemActivator.activate_consumable(
		pot_id, _reader, _make_catalog())
	check(bool(result["success"]) == false,
		"non-scroll category should be refused")
	check(String(result["message"]).contains("not a consumable scroll"),
		"message describes refusal; got: %s" % str(result["message"]))
	check(bool(result["consumed"]) == false,
		"refused scroll not consumed")
	_teardown()


func test_activate_consumable_refuses_missing_direct_effect() -> void:
	_setup()
	# Spell-scroll generator has no direct_consumable_effect; should
	# refuse (its mechanic goes through spell-scroll generator instead).
	var scroll_id := CampaignRepository.add_inventory_item({
		"character_id": _reader.id, "item_key": "spell_scroll",
		"name": "Spell Scroll", "is_magical": true,
	})
	var result: Dictionary = MagicItemActivator.activate_consumable(
		scroll_id, _reader, _make_catalog())
	check(bool(result["success"]) == false,
		"missing direct_consumable_effect → refused")
	check(String(result["message"]).contains("direct_consumable_effect"),
		"refusal message mentions direct_consumable_effect")
	_teardown()


func test_activate_consumable_metadata_radius_caster_level() -> void:
	_setup()
	var scroll_id := CampaignRepository.add_inventory_item({
		"character_id": _reader.id, "item_key": "scroll_of_warding_elementals",
		"name": "Scroll of Warding against Elementals", "is_magical": true,
	})
	MagicItemActivator.activate_consumable(scroll_id, _reader, _make_catalog())
	var meta: Dictionary = _reader.flags.get_flag_metadata("warded_against_creature_type")
	check(int(meta.get("caster_level", 0)) == 5,
		"scroll caster_level=5 default per RAW V1")
	check(String(meta.get("ward_kind", "")) == "ward_against_elementals",
		"ward_kind=ward_against_elementals")
	_teardown()


# ---------------------------------------------------------------------------
# Combat hook tests
# ---------------------------------------------------------------------------

const _SpellCombatHooksScript := preload(
	"res://engine/subsystems/combat/spell_combat_hooks.gd")


func _make_hook_with_dice(dice: _FakeDice):
	# SpellCombatHooks expects positional args; we only need dice for save
	# resolution paths.
	var hooks = _SpellCombatHooksScript.new(null, dice)
	return hooks


func test_hook_cancels_attack_from_matching_creature_type_on_save_fail() -> void:
	var bearer := _Bearer.new(); bearer.id = "bearer_uw"
	bearer.flags.set_flag("warded_against_creature_type", "scroll_ward:ward_against_undead:abc", {
		"creature_types": ["undead"],
		"radius_feet": 10,
		"caster_level": 5,
		"ward_kind": "ward_against_undead",
	})
	var attacker := _Attacker.new(); attacker.id = "wight_a"
	attacker.creature_type = "undead"
	var dice := _FakeDice.new()
	dice.fixed["save_spells_ward_creature_type"] = 1  # force fail
	var hooks = _make_hook_with_dice(dice)
	var result: Dictionary = hooks.on_pre_attack(attacker, bearer, "melee")
	check(bool(result.get("cancel", false)),
		"undead attacker on undead-warded target: attack cancelled on save fail")
	check(String(result.get("cancelled_by", "")) == "ward_against_creature_type",
		"cancelled_by=ward_against_creature_type")


func test_hook_allows_attack_on_save_success() -> void:
	var bearer := _Bearer.new(); bearer.id = "bearer_uw2"
	bearer.flags.set_flag("warded_against_creature_type", "scroll_ward:ward_against_undead:def", {
		"creature_types": ["undead"], "radius_feet": 10, "caster_level": 5,
	})
	var attacker := _Attacker.new(); attacker.id = "vampire_a"
	attacker.creature_type = "undead"
	var dice := _FakeDice.new()
	dice.fixed["save_spells_ward_creature_type"] = 20  # force pass
	var hooks = _make_hook_with_dice(dice)
	var result: Dictionary = hooks.on_pre_attack(attacker, bearer, "melee")
	check(not bool(result.get("cancel", false)),
		"successful save: attack proceeds")


func test_hook_ignores_non_matching_creature_type() -> void:
	var bearer := _Bearer.new(); bearer.id = "bearer_uw3"
	bearer.flags.set_flag("warded_against_creature_type", "scroll_ward:ward_against_undead:xyz", {
		"creature_types": ["undead"], "radius_feet": 10, "caster_level": 5,
	})
	var attacker := _Attacker.new(); attacker.id = "human_a"
	attacker.creature_type = "humanoid"
	var dice := _FakeDice.new()
	dice.fixed["save_spells_ward_creature_type"] = 1  # would fail if rolled
	var hooks = _make_hook_with_dice(dice)
	var result: Dictionary = hooks.on_pre_attack(attacker, bearer, "melee")
	check(not bool(result.get("cancel", false)),
		"non-matching creature_type: ward ignored, attack proceeds")


func test_hook_caches_save_per_attacker_per_source() -> void:
	var bearer := _Bearer.new(); bearer.id = "bearer_cache"
	bearer.flags.set_flag("warded_against_creature_type", "scroll_ward:ward_against_undead:cache", {
		"creature_types": ["undead"], "radius_feet": 10, "caster_level": 5,
	})
	var attacker := _Attacker.new(); attacker.id = "skel_cache"
	attacker.creature_type = "undead"
	var dice := _FakeDice.new()
	dice.fixed["save_spells_ward_creature_type"] = 20  # pass first attempt
	var hooks = _make_hook_with_dice(dice)
	var r1: Dictionary = hooks.on_pre_attack(attacker, bearer, "melee")
	check(not bool(r1.get("cancel", false)), "1st attempt: saved, allowed")
	# Now flip dice to fail; cache should still serve the prior PASS.
	dice.fixed["save_spells_ward_creature_type"] = 1
	var r2: Dictionary = hooks.on_pre_attack(attacker, bearer, "melee")
	check(not bool(r2.get("cancel", false)),
		"2nd attempt: cache returns prior PASS even though dice would fail")


# ---------------------------------------------------------------------------
# CastingResolver Ward against Magic gate tests
# ---------------------------------------------------------------------------

func _make_resolver_for_magic_ward() -> CastingResolver:
	# Minimal resolver — we only exercise the ward gate, which runs
	# before the effect-registry lookup. We still need a registry with
	# the spell key for the validation check, so we register a tiny
	# stub spell.
	var sr := SpellRegistry.new()
	sr.register_spell("magic_missile", {"spell_key": "magic_missile",
		"classifications": [{"tradition": "arcane", "level": 1}]})
	var er := SpellEffectRegistry.new(sr)
	er.register_effect("magic_missile", {
		"target_spec": {"kind": "single_creature"},
		"resolution": [{"kind": "apply_damage", "damage": "1d6"}],
	})
	var tracker := ActiveEffectTracker.new()
	var cc := ConditionCatalog.new()
	var cr := CustomResolverRegistry.new()
	# No campaign_repo for this test — we don't exercise slot expenditure.
	return CastingResolver.new(sr, er, tracker, cc, cr, null, null, null)


class _SimpleTarget extends RefCounted:
	var id: String = ""
	var flags: EntityFlags = EntityFlags.new()
	func get_flags() -> EntityFlags: return flags
	func add_condition(_k: String) -> void: pass
	func has_condition(_k: String) -> bool: return false
	func get_effective_save(_k: String) -> int: return 11
	func get_effective_ac() -> int: return 0
	func apply_damage(_amt: int, _t: String = "", _s: String = "") -> int: return 0


func _make_caster_cd(id: String, level: int = 5) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = id; cd.name = "Caster"
	cd.character_class = "mage"; cd.combat_progression = "mage"
	cd.level = level; cd.hp_max = 8; cd.hp_current = 8
	return cd


func test_gate_blocks_caster_bearer_external_target() -> void:
	var resolver := _make_resolver_for_magic_ward()
	var caster := _make_caster_cd("caster_b1", 5)
	# Apply ward against magic on the caster (caster IS bearer).
	caster.flags.set_flag("warded_against_magic", "scroll_ward:ward_against_magic:s1", {
		"radius_feet": 10, "caster_level": 5, "bearer_id": "caster_b1",
	})
	var target := _SimpleTarget.new(); target.id = "ally_external"
	var ctx := CasterContext.from_character_data(
		caster, "combat_grid", "arcane", 1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [target.id]
	var choice := SpellChoice.new("magic_missile", 1, false, -1)
	var res: ResolutionResult = resolver.resolve(
		ctx, choice, td, caster, {target.id: target})
	check(not res.success, "cast blocked when caster is bearer + target is external")
	var step: Dictionary = res.effects_applied[0]
	check(String(step.get("step_kind", "")) == "blocked_by_ward_against_magic",
		"step_kind=blocked_by_ward_against_magic")


func test_gate_blocks_target_bearer_external_caster() -> void:
	var resolver := _make_resolver_for_magic_ward()
	var caster := _make_caster_cd("caster_b2", 5)
	var target := _SimpleTarget.new(); target.id = "bearer_target"
	# Ward is on the target (target IS bearer).
	target.flags.set_flag("warded_against_magic", "scroll_ward:ward_against_magic:s2", {
		"radius_feet": 10, "caster_level": 5, "bearer_id": "bearer_target",
	})
	var ctx := CasterContext.from_character_data(
		caster, "combat_grid", "arcane", 1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [target.id]
	var choice := SpellChoice.new("magic_missile", 1, false, -1)
	var res: ResolutionResult = resolver.resolve(
		ctx, choice, td, caster, {target.id: target})
	check(not res.success,
		"cast blocked when target is bearer + caster is external")


func test_gate_allows_self_cast_even_with_ward() -> void:
	var resolver := _make_resolver_for_magic_ward()
	var caster := _make_caster_cd("caster_self", 5)
	caster.flags.set_flag("warded_against_magic", "scroll_ward:ward_against_magic:s3", {
		"radius_feet": 10, "caster_level": 5, "bearer_id": "caster_self",
	})
	var ctx := CasterContext.from_character_data(
		caster, "combat_grid", "arcane", 1)
	var td := TargetDescriptor.new()
	td.kind = "self"; td.target_ids = [caster.id]
	var choice := SpellChoice.new("magic_missile", 1, false, -1)
	var res: ResolutionResult = resolver.resolve(
		ctx, choice, td, caster, {caster.id: caster})
	check(res.effects_applied.size() >= 1, "self-cast resolves at least one step")
	# self-cast not blocked by ward
	var first_step: Dictionary = res.effects_applied[0]
	check(String(first_step.get("step_kind", "")) != "blocked_by_ward_against_magic",
		"self-cast exempt from ward block")


func test_gate_no_block_when_no_ward_present() -> void:
	var resolver := _make_resolver_for_magic_ward()
	var caster := _make_caster_cd("caster_nw", 5)
	var target := _SimpleTarget.new(); target.id = "tgt_nw"
	var ctx := CasterContext.from_character_data(
		caster, "combat_grid", "arcane", 1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"; td.target_ids = [target.id]
	var choice := SpellChoice.new("magic_missile", 1, false, -1)
	var res: ResolutionResult = resolver.resolve(
		ctx, choice, td, caster, {target.id: target})
	var first_step: Dictionary = res.effects_applied[0]
	check(String(first_step.get("step_kind", "")) != "blocked_by_ward_against_magic",
		"no ward present: cast not blocked by ward")
