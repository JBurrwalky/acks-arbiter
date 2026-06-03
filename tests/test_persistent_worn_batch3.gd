extends "res://tests/test_suite_base.gd"

## 2026-06-03 — Persistent-worn cluster: Scarab of Protection + Cube of
## Frost Resistance + Eyes of the Eagle + Necklace of Adaptation.
##
## All 4 items have full RAW from ACKS Core p.215+ supplied by Jedidiah.
## V1 ships all 4 as worn-passive flag-only adds with full RAW metadata;
## consumer integrations (cold-damage absorption, finger-of-death
## negation + charge decrement, missile-range modifier in attack
## resolver, gas immunity + breath-holding in exploration) are
## documented follow-ups.
##
## Coverage:
##   - Catalog: 4 items removed from EXPECTED_DEFER_KEYS; Scarab has
##     default_charges="2d6" stamped for materializer dice roll.
##   - WornMagicEffectResolver: each item sets its flag with full RAW
##     metadata when equipped; cleared on unequip via worn_magic:
##     source-prefix sweep.
##   - Scarab charge reading from inventory row's uses_remaining.


func run_all_tests() -> void:
	# Catalog
	test_catalog_scarab_has_dice_default_charges()
	test_catalog_cube_no_defer_reason()
	test_catalog_eyes_no_defer_reason()
	test_catalog_necklace_no_defer_reason()
	test_catalog_items_removed_from_expected_defer()
	# WornMagicEffectResolver
	test_cube_of_frost_resistance_sets_flag_with_full_raw_metadata()
	test_cube_clears_on_unequip()
	test_scarab_sets_flag_with_full_raw_metadata()
	test_scarab_reads_charges_from_inventory_row()
	test_scarab_clears_on_unequip()
	test_eyes_of_the_eagle_sets_flag_with_full_raw_metadata()
	test_eyes_clears_on_unequip()
	test_necklace_of_adaptation_sets_flag_with_full_raw_metadata()
	test_necklace_clears_on_unequip()
	# EntityFlags regression
	test_new_flags_documented()
	if not has_failures():
		print("PersistentWornBatch3: all tests passed.")


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


func test_catalog_scarab_has_dice_default_charges() -> void:
	var it: Dictionary = _find(_read_items(), "scarab_of_protection")
	check(not it.is_empty(), "scarab_of_protection present")
	check(String(it.get("default_charges", "")) == "2d6",
		"scarab default_charges='2d6' per RAW (rolled at materialization)")


func test_catalog_cube_no_defer_reason() -> void:
	var it: Dictionary = _find(_read_items(), "cube_of_frost_resistance")
	check(String(it.get("defer_reason", "")) == "",
		"cube_of_frost_resistance defer_reason cleared")


func test_catalog_eyes_no_defer_reason() -> void:
	var it: Dictionary = _find(_read_items(), "eyes_of_the_eagle")
	check(String(it.get("defer_reason", "")) == "",
		"eyes_of_the_eagle defer_reason cleared")


func test_catalog_necklace_no_defer_reason() -> void:
	var it: Dictionary = _find(_read_items(), "necklace_of_adaptation")
	check(String(it.get("defer_reason", "")) == "",
		"necklace_of_adaptation defer_reason cleared")


func test_catalog_items_removed_from_expected_defer() -> void:
	var path := "res://tests/test_magic_item_catalog.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		check(false, "test_magic_item_catalog.gd readable")
		return
	var content := f.get_as_text()
	f.close()
	for k in ["scarab_of_protection", "cube_of_frost_resistance",
			"eyes_of_the_eagle", "necklace_of_adaptation"]:
		var bare: String = '"' + String(k) + '",'
		check(not content.contains(bare),
			"%s should NOT appear as bare array member in EXPECTED_DEFER_KEYS" % k)


# ---------------------------------------------------------------------------
# WornMagicEffectResolver tests
# ---------------------------------------------------------------------------

func _make_character() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "pwb3_wearer"
	cd.name = "PWB3 Wearer"
	cd.character_class = "fighter"
	cd.combat_progression = "fighter"
	cd.level = 5
	cd.hp_max = 30; cd.hp_current = 30
	return cd


func _equipped_row(item_key: String, uses_remaining: int = -1) -> Dictionary:
	return {
		"id": item_key + "_row_id",
		"item_key": item_key,
		"is_equipped": 1,
		"magical_bonus": 0,
		"uses_remaining": uses_remaining,
	}


# --- Cube of Frost Resistance ---

func test_cube_of_frost_resistance_sets_flag_with_full_raw_metadata() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("cube_of_frost_resistance")])
	check(cd.flags.has_flag("has_cube_of_frost_resistance_field"),
		"wearer carries has_cube_of_frost_resistance_field flag")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_cube_of_frost_resistance_field")
	check(bool(meta.get("absorbs_cold_attacks", false)) == true,
		"absorbs_cold_attacks=true per RAW")
	check(int(meta.get("min_temperature_f", 0)) == 65,
		"min_temperature_f=65 per RAW")
	check(int(meta.get("area_cube_side_feet", 0)) == 10,
		"area_cube_side_feet=10 per RAW")
	check(int(meta.get("collapse_threshold_cold_damage_per_turn", 0)) == 50,
		"collapse_threshold=50 per RAW")
	check(int(meta.get("collapse_cooldown_hours", 0)) == 1,
		"collapse_cooldown=1 hour per RAW")
	check(int(meta.get("destroy_threshold_cold_damage_per_turn", 0)) == 100,
		"destroy_threshold=100 per RAW")


func test_cube_clears_on_unequip() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("cube_of_frost_resistance")])
	check(cd.flags.has_flag("has_cube_of_frost_resistance_field"), "setup")
	WornMagicEffectResolver.refresh_for_character(cd, [])
	check(not cd.flags.has_flag("has_cube_of_frost_resistance_field"),
		"flag cleared after unequip via source-prefix sweep")


# --- Scarab of Protection ---

func test_scarab_sets_flag_with_full_raw_metadata() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("scarab_of_protection", 7)])
	check(cd.flags.has_flag("has_scarab_of_protection"),
		"wearer carries has_scarab_of_protection flag")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_scarab_of_protection")
	var immune_to: Array = meta.get("immune_to", [])
	check("curse" in immune_to, "immune_to includes curse")
	check("finger_of_death" in immune_to, "immune_to includes finger_of_death")


func test_scarab_reads_charges_from_inventory_row() -> void:
	var cd := _make_character()
	# Row with uses_remaining=9 (a sample 2d6 roll result).
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("scarab_of_protection", 9)])
	var meta: Dictionary = cd.flags.get_flag_metadata("has_scarab_of_protection")
	check(int(meta.get("charges_remaining", 0)) == 9,
		"charges_remaining=9 read from inventory row uses_remaining")


func test_scarab_clears_on_unequip() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("scarab_of_protection", 7)])
	check(cd.flags.has_flag("has_scarab_of_protection"), "setup")
	WornMagicEffectResolver.refresh_for_character(cd, [])
	check(not cd.flags.has_flag("has_scarab_of_protection"),
		"flag cleared after unequip")


# --- Eyes of the Eagle ---

func test_eyes_of_the_eagle_sets_flag_with_full_raw_metadata() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("eyes_of_the_eagle")])
	check(cd.flags.has_flag("has_eyes_of_the_eagle"),
		"wearer carries has_eyes_of_the_eagle flag")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_eyes_of_the_eagle")
	check(int(meta.get("vision_range_multiplier", 0)) == 100,
		"vision_range_multiplier=100 per RAW")
	check(int(meta.get("missile_medium_range_modifier", 0)) == -1,
		"missile_medium_range_modifier=-1 per RAW")
	check(int(meta.get("missile_long_range_modifier", 0)) == -2,
		"missile_long_range_modifier=-2 per RAW")


func test_eyes_clears_on_unequip() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("eyes_of_the_eagle")])
	check(cd.flags.has_flag("has_eyes_of_the_eagle"), "setup")
	WornMagicEffectResolver.refresh_for_character(cd, [])
	check(not cd.flags.has_flag("has_eyes_of_the_eagle"),
		"flag cleared after unequip")


# --- Necklace of Adaptation ---

func test_necklace_of_adaptation_sets_flag_with_full_raw_metadata() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("necklace_of_adaptation")])
	check(cd.flags.has_flag("has_necklace_of_adaptation"),
		"wearer carries has_necklace_of_adaptation flag")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_necklace_of_adaptation")
	check(bool(meta.get("immune_to_harmful_vapors_and_gases", false)) == true,
		"immune_to_harmful_vapors_and_gases=true per RAW")
	check(int(meta.get("survive_without_air_days", 0)) == 7,
		"survive_without_air_days=7 per RAW (1 week)")


func test_necklace_clears_on_unequip() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("necklace_of_adaptation")])
	check(cd.flags.has_flag("has_necklace_of_adaptation"), "setup")
	WornMagicEffectResolver.refresh_for_character(cd, [])
	check(not cd.flags.has_flag("has_necklace_of_adaptation"),
		"flag cleared after unequip")


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
	check(content.contains("has_cube_of_frost_resistance_field"),
		"has_cube_of_frost_resistance_field documented")
	check(content.contains("has_scarab_of_protection"),
		"has_scarab_of_protection documented")
	check(content.contains("has_eyes_of_the_eagle"),
		"has_eyes_of_the_eagle documented")
	check(content.contains("has_necklace_of_adaptation"),
		"has_necklace_of_adaptation documented")
