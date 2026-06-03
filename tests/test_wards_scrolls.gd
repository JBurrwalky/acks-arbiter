extends "res://tests/test_suite_base.gd"

## 2026-06-02 (rewrote 2026-06-03) — Scrolls of Warding cluster (4 items).
##
## RAW-aligned semantics per acore_treasure_and_magic_items_rules.xml:268-272:
##   - ENTRY BLOCK: warded creatures cannot enter cells within 10' of bearer
##     (MovementResolver._can_enter_3d / _ward_blocks_entry). No save.
##   - NO ATTACK SAVE: warded creatures can still attack with missiles or
##     spells from outside the radius (no engine gate).
##   - BEARER-MELEE-OUT DISMISSAL: when bearer attacks (melee) at a creature
##     whose type matches a warded type, that ward source is cleared
##     (SpellCombatHooks.on_pre_attack).
##   - DURATION: "until dismissed" (V1: cleared by bearer-melee-out or
##     inventory removal; no UI dismiss yet).
##
## Coverage:
##   - Catalog: 4 scrolls have `direct_consumable_effect` with correct
##     effect_kind + (creature_types | ward_kind) + radius_feet + caster_level.
##   - MagicItemActivator.activate_consumable: validates scroll category,
##     refuses missing direct_consumable_effect, applies the unified
##     warded_against_creature_type flag with correct metadata
##     (including creature_types=["magic"] for the Magic scroll),
##     consumes scroll on success.
##   - SpellCombatHooks.on_pre_attack bearer-melee-out dismissal: bearer
##     melee at warded type clears the ward source; bearer melee at
##     non-warded type leaves it; bearer ranged at warded type leaves it
##     (RAW only "melee" dismisses); non-bearer attacker doesn't dismiss.


# ---------------------------------------------------------------------------
# Fakes
# ---------------------------------------------------------------------------

class _Attacker extends RefCounted:
	var id: String = ""
	var creature_type: String = ""
	var flags: EntityFlags = EntityFlags.new()
	var sanctuary_blocked_targets: Array = []
	func get_flags() -> EntityFlags: return flags
	func is_creature_type(t: String) -> bool:
		return creature_type.to_lower() == t.to_lower()
	func get_effective_save(_k: String) -> int: return 11


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
	test_activate_consumable_magic_ward_uses_unified_flag()
	test_activate_consumable_refuses_non_scroll_category()
	test_activate_consumable_refuses_missing_direct_effect()
	test_activate_consumable_metadata_radius_caster_level()
	# Combat hook bearer-melee-out dismissal
	test_bearer_melee_at_warded_type_clears_ward()
	test_bearer_melee_at_non_warded_type_leaves_ward()
	test_bearer_ranged_at_warded_type_leaves_ward()
	test_non_bearer_attacker_does_not_dismiss()
	test_bearer_multi_ward_only_matching_source_cleared()
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
	# Catalog still stamps effect_kind=ward_against_magic; activate_consumable
	# routes that to _apply_ward_against_magic which now stamps the unified
	# warded_against_creature_type flag with creature_types=["magic"].
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
	var path := "res://tests/test_magic_item_catalog.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		check(false, "test_magic_item_catalog.gd should be readable")
		return
	var content := f.get_as_text()
	f.close()
	for k in ["scroll_of_warding_elementals", "scroll_of_warding_lycanthropes",
			"scroll_of_warding_magic", "scroll_of_warding_undead"]:
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
	check(bool(result["consumed"]) == true, "scroll consumed on success")
	check(String(result["flag_set"]) == "warded_against_creature_type",
		"flag_set=warded_against_creature_type")
	check(_reader.flags.has_flag("warded_against_creature_type"),
		"reader carries the flag")
	var meta: Dictionary = _reader.flags.get_flag_metadata("warded_against_creature_type")
	check("undead" in (meta.get("creature_types", []) as Array),
		"flag metadata creature_types contains undead")
	check(int(meta.get("radius_feet", 0)) == 10, "metadata.radius_feet=10")
	_teardown()


func test_activate_consumable_magic_ward_uses_unified_flag() -> void:
	# 2026-06-03 RAW alignment: the magic scroll now stamps
	# warded_against_creature_type with creature_types=["magic"]
	# (consolidating the prior warded_against_magic flag).
	_setup()
	var scroll_id := CampaignRepository.add_inventory_item({
		"character_id": _reader.id, "item_key": "scroll_of_warding_magic",
		"name": "Scroll of Warding against Magic", "is_magical": true,
	})
	var result: Dictionary = MagicItemActivator.activate_consumable(
		scroll_id, _reader, _make_catalog())
	check(bool(result["success"]) == true, "magic ward applies")
	check(String(result["flag_set"]) == "warded_against_creature_type",
		"flag_set=warded_against_creature_type (consolidated)")
	check(_reader.flags.has_flag("warded_against_creature_type"),
		"reader carries warded_against_creature_type flag")
	var meta: Dictionary = _reader.flags.get_flag_metadata("warded_against_creature_type")
	check("magic" in (meta.get("creature_types", []) as Array),
		"magic ward metadata.creature_types contains 'magic'")
	check(int(meta.get("radius_feet", 0)) == 10, "magic ward radius=10")
	check(String(meta.get("ward_kind", "")) == "ward_against_magic",
		"ward_kind=ward_against_magic preserved for narration")
	_teardown()


func test_activate_consumable_refuses_non_scroll_category() -> void:
	_setup()
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
# Combat hook bearer-melee-out dismissal tests
# ---------------------------------------------------------------------------

const _SpellCombatHooksScript := preload(
	"res://engine/subsystems/combat/spell_combat_hooks.gd")


func _make_hooks():
	return _SpellCombatHooksScript.new(null, null)


class _AttackTarget extends RefCounted:
	var id: String = ""
	var creature_type: String = ""
	var flags: EntityFlags = EntityFlags.new()
	func get_flags() -> EntityFlags: return flags
	func is_creature_type(t: String) -> bool:
		return creature_type.to_lower() == t.to_lower()
	func get_effective_save(_k: String) -> int: return 11


func _apply_ward(bearer: _Attacker, warded_types: Array,
		source_id: String = "scroll_ward:test:abc") -> void:
	bearer.flags.set_flag("warded_against_creature_type", source_id, {
		"creature_types": warded_types,
		"radius_feet": 10,
		"caster_level": 5,
		"ward_kind": "ward_against_test",
	})


func test_bearer_melee_at_warded_type_clears_ward() -> void:
	# Bearer attacks an undead in melee. Ward against Undead dismisses.
	var bearer := _Attacker.new(); bearer.id = "bearer_b1"
	bearer.creature_type = "humanoid"
	_apply_ward(bearer, ["undead"], "ward_b1")
	var target := _AttackTarget.new()
	target.id = "skel_t1"; target.creature_type = "undead"
	var hooks = _make_hooks()
	check(bearer.flags.has_flag("warded_against_creature_type"), "setup: bearer warded")
	hooks.on_pre_attack(bearer, target, "melee")
	check(not bearer.flags.has_flag("warded_against_creature_type"),
		"bearer-melee-out: ward cleared after melee at warded type per RAW")


func test_bearer_melee_at_non_warded_type_leaves_ward() -> void:
	# Bearer attacks a humanoid in melee. Ward against Undead doesn't dismiss.
	var bearer := _Attacker.new(); bearer.id = "bearer_b2"
	bearer.creature_type = "humanoid"
	_apply_ward(bearer, ["undead"], "ward_b2")
	var target := _AttackTarget.new()
	target.id = "goblin_t1"; target.creature_type = "humanoid"
	var hooks = _make_hooks()
	hooks.on_pre_attack(bearer, target, "melee")
	check(bearer.flags.has_flag("warded_against_creature_type"),
		"melee at non-warded type: ward remains")


func test_bearer_ranged_at_warded_type_leaves_ward() -> void:
	# RAW says "anyone inside the area attempts MELEE against a protected
	# creature type" — ranged/missiles don't dismiss.
	var bearer := _Attacker.new(); bearer.id = "bearer_b3"
	bearer.creature_type = "humanoid"
	_apply_ward(bearer, ["undead"], "ward_b3")
	var target := _AttackTarget.new()
	target.id = "wight_t1"; target.creature_type = "undead"
	var hooks = _make_hooks()
	hooks.on_pre_attack(bearer, target, "ranged")
	check(bearer.flags.has_flag("warded_against_creature_type"),
		"ranged attack: ward remains (RAW says only melee dismisses)")


func test_non_bearer_attacker_does_not_dismiss() -> void:
	# Attacker has no ward; target's ward state is irrelevant here. This
	# test exists as a regression guard so the dismissal logic doesn't
	# fire on any attack involving a warded target.
	var attacker := _Attacker.new(); attacker.id = "att_t1"
	attacker.creature_type = "humanoid"
	var target := _AttackTarget.new()
	target.id = "skel_t2"; target.creature_type = "undead"
	# Target carries a ward — but target dismissal would be wrong; only
	# bearer (= attacker with the ward flag) triggers dismissal.
	target.flags.set_flag("warded_against_creature_type", "ward_t1", {
		"creature_types": ["undead"], "radius_feet": 10, "caster_level": 5,
	})
	var hooks = _make_hooks()
	hooks.on_pre_attack(attacker, target, "melee")
	check(target.flags.has_flag("warded_against_creature_type"),
		"target's ward NOT dismissed when target is the attack victim")


func test_bearer_multi_ward_only_matching_source_cleared() -> void:
	# Bearer has TWO wards: one vs Undead, one vs Lycanthrope. Melee at
	# Undead clears the Undead source but leaves the Lycanthrope source.
	var bearer := _Attacker.new(); bearer.id = "bearer_b4"
	bearer.creature_type = "humanoid"
	_apply_ward(bearer, ["undead"], "ward_undead_b4")
	_apply_ward(bearer, ["lycanthrope"], "ward_lyc_b4")
	# Flag has 2 sources.
	var sources_before: Array = bearer.flags.get_flag_sources(
		"warded_against_creature_type")
	check(sources_before.size() == 2, "setup: 2 ward sources")
	var target := _AttackTarget.new()
	target.id = "skel_t3"; target.creature_type = "undead"
	var hooks = _make_hooks()
	hooks.on_pre_attack(bearer, target, "melee")
	# Only Undead source cleared; Lycanthrope source remains → flag still
	# present, but only 1 source.
	var sources_after: Array = bearer.flags.get_flag_sources(
		"warded_against_creature_type")
	check(sources_after.size() == 1,
		"only matching ward source cleared; non-matching preserved")
	check("ward_lyc_b4" in sources_after,
		"lycanthrope ward source preserved (target was undead)")
	check(not ("ward_undead_b4" in sources_after),
		"undead ward source cleared by bearer-melee-out")
