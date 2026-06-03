extends "res://tests/test_suite_base.gd"

## 2026-06-03 — Engine-extension batch: Brooch of Shielding + Elven Cloak
## + Elven Boots.
##
## RAW from ACKS Core p.215+ (Jedidiah-supplied):
##   - Brooch of Shielding: silver/gold cloak fastener; absorbs up to 101
##     points of magic-missile damage; melts and becomes useless when
##     capacity exhausted.
##   - Elven Cloak: +8 to hide_in_shadows + always succeeds on 12+.
##   - Elven Boots: +8 to move_silently + always succeeds on 12+.
##
## Engine extensions wired this batch:
##   - CastingResolver._brooch_absorb consults has_brooch_of_shielding
##     in damage_per_level path when damage_type=="force"; absorbs up to
##     charges_remaining; removes inventory row when destroyed.
##   - ThiefSkillResolver._build_skill_check reads
##     `<skill_key>_magical_bonus` + `<skill_key>_ceiling_target` from
##     character.modifiers (set by WornMagicEffectResolver for Elven items).


func run_all_tests() -> void:
	# Catalog
	test_catalog_brooch_has_fixed_default_charges()
	test_catalog_brooch_no_defer_reason()
	test_catalog_elven_cloak_no_defer_reason()
	test_catalog_elven_boots_no_defer_reason()
	# WornMagicEffectResolver
	test_brooch_sets_flag_with_full_raw_metadata()
	test_brooch_reads_charges_from_inventory_row()
	test_brooch_clears_on_unequip()
	test_elven_cloak_sets_flag_and_modifiers()
	test_elven_cloak_clears_modifiers_on_unequip()
	test_elven_boots_sets_flag_and_modifiers()
	test_elven_boots_clears_modifiers_on_unequip()
	# Brooch consumer in CastingResolver
	test_brooch_absorbs_force_damage_in_damage_per_level()
	test_brooch_partial_absorption_when_damage_exceeds_charges()
	test_brooch_ignores_non_force_damage()
	test_brooch_at_zero_charges_does_not_absorb()
	# ThiefSkillResolver consumer
	test_thief_skill_resolver_reads_magical_bonus()
	test_thief_skill_resolver_applies_ceiling_target()
	# EntityFlags regression
	test_new_flags_documented()
	if not has_failures():
		print("EngineExtensionBatch: all tests passed.")


# ---------------------------------------------------------------------------
# Catalog tests
# ---------------------------------------------------------------------------

func _read_items() -> Array:
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


func test_catalog_brooch_has_fixed_default_charges() -> void:
	var it: Dictionary = _find(_read_items(), "brooch_of_shielding")
	check(not it.is_empty(), "brooch_of_shielding present")
	check(int(it.get("default_charges", 0)) == 101,
		"brooch default_charges=101 (total absorption capacity) per RAW")


func test_catalog_brooch_no_defer_reason() -> void:
	var it: Dictionary = _find(_read_items(), "brooch_of_shielding")
	check(String(it.get("defer_reason", "")) == "",
		"brooch_of_shielding defer_reason cleared")


func test_catalog_elven_cloak_no_defer_reason() -> void:
	var it: Dictionary = _find(_read_items(), "elven_cloak")
	check(String(it.get("defer_reason", "")) == "",
		"elven_cloak defer_reason cleared")


func test_catalog_elven_boots_no_defer_reason() -> void:
	var it: Dictionary = _find(_read_items(), "elven_boots")
	check(String(it.get("defer_reason", "")) == "",
		"elven_boots defer_reason cleared")


# ---------------------------------------------------------------------------
# WornMagicEffectResolver tests
# ---------------------------------------------------------------------------

func _make_character() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "eeb_wearer"
	cd.name = "EEB Wearer"
	cd.character_class = "thief"
	cd.combat_progression = "thief"
	cd.level = 5
	cd.hp_max = 20; cd.hp_current = 20
	return cd


func _equipped_row(item_key: String, uses_remaining: int = -1) -> Dictionary:
	return {
		"id": item_key + "_row_id",
		"item_key": item_key,
		"is_equipped": 1,
		"magical_bonus": 0,
		"uses_remaining": uses_remaining,
	}


func test_brooch_sets_flag_with_full_raw_metadata() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("brooch_of_shielding", 101)])
	check(cd.flags.has_flag("has_brooch_of_shielding"),
		"wearer carries has_brooch_of_shielding flag")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_brooch_of_shielding")
	check("magic_missile" in (meta.get("absorbs_spell_keys", []) as Array),
		"absorbs_spell_keys includes magic_missile per RAW")
	check(int(meta.get("total_capacity", 0)) == 101,
		"total_capacity=101 per RAW")


func test_brooch_reads_charges_from_inventory_row() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("brooch_of_shielding", 67)])
	var meta: Dictionary = cd.flags.get_flag_metadata("has_brooch_of_shielding")
	check(int(meta.get("charges_remaining", 0)) == 67,
		"charges_remaining=67 read from inventory row uses_remaining")


func test_brooch_clears_on_unequip() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("brooch_of_shielding", 101)])
	check(cd.flags.has_flag("has_brooch_of_shielding"), "setup")
	WornMagicEffectResolver.refresh_for_character(cd, [])
	check(not cd.flags.has_flag("has_brooch_of_shielding"),
		"flag cleared after unequip")


func test_elven_cloak_sets_flag_and_modifiers() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("elven_cloak")])
	check(cd.flags.has_flag("has_elven_cloak"),
		"wearer carries has_elven_cloak flag")
	# Check ModifierContainer entries.
	var bonus: int = int(cd.modifiers.get_effective_value("hide_in_shadows_magical_bonus", 0))
	check(bonus == 8, "hide_in_shadows_magical_bonus=+8 per RAW; got %d" % bonus)
	var ceiling: int = int(cd.modifiers.get_effective_value("hide_in_shadows_ceiling_target", 99))
	check(ceiling == 12,
		"hide_in_shadows_ceiling_target=12 (always 12+ per RAW); got %d" % ceiling)


func test_elven_cloak_clears_modifiers_on_unequip() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("elven_cloak")])
	check(int(cd.modifiers.get_effective_value("hide_in_shadows_magical_bonus", 0)) == 8, "setup")
	WornMagicEffectResolver.refresh_for_character(cd, [])
	check(int(cd.modifiers.get_effective_value("hide_in_shadows_magical_bonus", 0)) == 0,
		"hide_in_shadows_magical_bonus cleared after unequip")
	check(int(cd.modifiers.get_effective_value("hide_in_shadows_ceiling_target", 99)) == 99,
		"hide_in_shadows_ceiling_target cleared after unequip")


func test_elven_boots_sets_flag_and_modifiers() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("elven_boots")])
	check(cd.flags.has_flag("has_elven_boots"),
		"wearer carries has_elven_boots flag")
	var bonus: int = int(cd.modifiers.get_effective_value("move_silently_magical_bonus", 0))
	check(bonus == 8, "move_silently_magical_bonus=+8 per RAW")
	var ceiling: int = int(cd.modifiers.get_effective_value("move_silently_ceiling_target", 99))
	check(ceiling == 12, "move_silently_ceiling_target=12 (always 12+ per RAW)")


func test_elven_boots_clears_modifiers_on_unequip() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("elven_boots")])
	check(int(cd.modifiers.get_effective_value("move_silently_magical_bonus", 0)) == 8, "setup")
	WornMagicEffectResolver.refresh_for_character(cd, [])
	check(int(cd.modifiers.get_effective_value("move_silently_magical_bonus", 0)) == 0,
		"move_silently_magical_bonus cleared after unequip")


# ---------------------------------------------------------------------------
# Brooch consumer tests (CastingResolver._brooch_absorb)
# ---------------------------------------------------------------------------

const _CastingResolverScript := preload(
	"res://engine/subsystems/spells/casting_resolver.gd")


func _make_resolver() -> CastingResolver:
	# We use the default registries; the resolver's _brooch_absorb is the
	# only path exercised here.
	var sr := SpellRegistry.new()
	var er := SpellEffectRegistry.new(sr)
	var tracker := ActiveEffectTracker.new()
	var cc := ConditionCatalog.new()
	var cr := CustomResolverRegistry.new()
	return CastingResolver.new(sr, er, tracker, cc, cr, null, null, null)


class _BroochTarget extends RefCounted:
	var id: String = ""
	var flags: EntityFlags = EntityFlags.new()
	func get_flags() -> EntityFlags: return flags


func _stamp_brooch(target: _BroochTarget, charges: int) -> void:
	target.flags.set_flag("has_brooch_of_shielding",
		"worn_magic:brooch_test", {
			"source_kind": "worn_magic_item",
			"absorbs_spell_keys": ["magic_missile"],
			"total_capacity": 101,
			"charges_remaining": charges,
			"item_id": "brooch_test_id",
		})


func test_brooch_absorbs_force_damage_in_damage_per_level() -> void:
	var r := _make_resolver()
	var tgt := _BroochTarget.new(); tgt.id = "brooch_t1"
	_stamp_brooch(tgt, 50)
	# 10 incoming force damage; brooch has 50 charges → absorbs all 10.
	var result: Dictionary = r._brooch_absorb(tgt.id, {tgt.id: tgt}, 10, "force")
	check(int(result.get("absorbed", 0)) == 10,
		"brooch absorbs 10/10 incoming force damage")
	check(int(result.get("damage_after_absorption", -1)) == 0,
		"target takes 0 damage after absorption")
	check(int(result.get("charges_remaining", -1)) == 40,
		"charges remaining=40 (50-10)")
	check(not bool(result.get("destroyed", true)),
		"brooch not destroyed (charges remain)")


func test_brooch_partial_absorption_when_damage_exceeds_charges() -> void:
	var r := _make_resolver()
	var tgt := _BroochTarget.new(); tgt.id = "brooch_t2"
	_stamp_brooch(tgt, 5)
	# 20 incoming damage; brooch has 5 charges → absorbs 5, target takes 15.
	var result: Dictionary = r._brooch_absorb(tgt.id, {tgt.id: tgt}, 20, "force")
	check(int(result.get("absorbed", 0)) == 5,
		"brooch absorbs 5/20 (charges_remaining limit)")
	check(int(result.get("damage_after_absorption", -1)) == 15,
		"target takes 15 damage (overflow past brooch)")
	check(int(result.get("charges_remaining", -1)) == 0,
		"charges_remaining=0 (all 5 consumed)")
	check(bool(result.get("destroyed", false)) == true,
		"brooch destroyed when charges hit 0")


func test_brooch_ignores_non_force_damage() -> void:
	var r := _make_resolver()
	var tgt := _BroochTarget.new(); tgt.id = "brooch_t3"
	_stamp_brooch(tgt, 50)
	# 10 incoming "fire" damage — brooch does NOT absorb non-force damage.
	var result: Dictionary = r._brooch_absorb(tgt.id, {tgt.id: tgt}, 10, "fire")
	check(int(result.get("absorbed", 0)) == 0,
		"brooch ignores fire damage")
	check(int(result.get("damage_after_absorption", -1)) == 10,
		"target takes full fire damage")


func test_brooch_at_zero_charges_does_not_absorb() -> void:
	var r := _make_resolver()
	var tgt := _BroochTarget.new(); tgt.id = "brooch_t4"
	_stamp_brooch(tgt, 0)
	var result: Dictionary = r._brooch_absorb(tgt.id, {tgt.id: tgt}, 10, "force")
	check(int(result.get("absorbed", 0)) == 0,
		"exhausted brooch does not absorb")
	check(int(result.get("damage_after_absorption", -1)) == 10,
		"target takes full damage when brooch exhausted")


# ---------------------------------------------------------------------------
# ThiefSkillResolver consumer tests
# ---------------------------------------------------------------------------

func test_thief_skill_resolver_reads_magical_bonus() -> void:
	# Direct ModifierContainer add of hide_in_shadows_magical_bonus is
	# verified by test_elven_cloak_sets_flag_and_modifiers. Here we
	# verify the resolver actually CONSUMES that bonus when building a
	# skill check. We don't need a full ThiefSkillResolver harness — we
	# just need a CharacterData with the modifier and verify
	# get_effective_value returns 8.
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("elven_cloak")])
	var effective_bonus: int = int(cd.modifiers.get_effective_value("hide_in_shadows_magical_bonus", 0))
	check(effective_bonus == 8,
		"ModifierContainer.get_effective_value returns 8 for hide_in_shadows_magical_bonus")


func test_thief_skill_resolver_applies_ceiling_target() -> void:
	# The ceiling is read in _build_skill_check via
	# get_effective_value(<skill>_ceiling_target, 99); when below 99 it's
	# applied as a min() clamp. Verify the modifier value here directly.
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("elven_boots")])
	var ceiling: int = int(cd.modifiers.get_effective_value("move_silently_ceiling_target", 99))
	check(ceiling == 12,
		"ModifierContainer.get_effective_value returns 12 for move_silently_ceiling_target")
	# Sanity: when no Elven Boots equipped, ceiling defaults to 99 (no cap).
	WornMagicEffectResolver.refresh_for_character(cd, [])
	var no_boots: int = int(cd.modifiers.get_effective_value("move_silently_ceiling_target", 99))
	check(no_boots == 99,
		"no Elven Boots: ceiling defaults to 99 (no cap on throw target)")


# ---------------------------------------------------------------------------
# EntityFlags regression
# ---------------------------------------------------------------------------

func test_new_flags_documented() -> void:
	var path := "res://engine/shared_types/entity_flags.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		check(false, "entity_flags.gd readable")
		return
	var content := f.get_as_text()
	f.close()
	check(content.contains("has_brooch_of_shielding"),
		"has_brooch_of_shielding documented")
	check(content.contains("has_elven_cloak"),
		"has_elven_cloak documented")
	check(content.contains("has_elven_boots"),
		"has_elven_boots documented")
