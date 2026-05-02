extends "res://tests/test_suite_base.gd"

## Tests for FamiliarFormRegistry — loading the catalog, canon-form resolution
## via MonsterRegistry, project-authored inline stat blocks, and the small
## convenience accessors (display_name, summary, AC, movement, etc.) the
## picker UI relies on.


func run_all_tests() -> void:
	test_loads_seven_forms()
	test_canon_form_resolves_via_monster_registry()
	test_project_authored_form_has_inline_stat_block()
	test_cosmetic_variants_returned()
	test_unknown_form_lookup_is_safe()
	test_display_name_falls_back_to_form_key()
	test_armor_class_caps_at_3_for_project_authored()
	test_form_keys_in_catalog_order()
	test_is_project_authored_distinguishes_canon_vs_inline()
	test_attack_routines_for_canon_bat()
	test_special_abilities_for_project_cat()

	if not has_failures():
		print("FamiliarFormRegistry: all tests passed.")


# --- Helpers ---

func _make_registry() -> FamiliarFormRegistry:
	# MonsterRegistry instantiated fresh per test so canon resolution is real,
	# not stubbed — we want to confirm the bat / hawk references actually wire
	# through to the live monster catalog.
	return FamiliarFormRegistry.new(MonsterRegistry.new())


# --- Tests ---

func test_loads_seven_forms() -> void:
	var reg := _make_registry()
	check(reg.get_form_count() == 7,
		"Expected 7 forms in catalog (bat, hawk, cat, rat, snake_small, toad, weasel), got %d" % reg.get_form_count())


func test_canon_form_resolves_via_monster_registry() -> void:
	var reg := _make_registry()
	# Bat is a canon form pointing to bat_ordinary in monster_catalog.
	var bat_stats := reg.get_form_stats("bat")
	check(not bat_stats.is_empty(), "bat stat block should resolve via MonsterRegistry")
	check(int(bat_stats.get("armor_class", -1)) == 3, "bat AC = 3 (canon)")
	# Echolocation should be in special_abilities
	var has_echolocation := false
	for ability in bat_stats.get("special_abilities", []):
		if String(ability.get("ability_id", "")) == "echolocation":
			has_echolocation = true
			break
	check(has_echolocation, "bat resolved stat block should carry echolocation special ability")


func test_project_authored_form_has_inline_stat_block() -> void:
	var reg := _make_registry()
	# Cat is project-authored — inline stat_block in the catalog.
	var cat_stats := reg.get_form_stats("cat")
	check(not cat_stats.is_empty(), "cat inline stat block should be returned")
	check(int(cat_stats.get("armor_class", -1)) == 3, "cat AC must be 3 (capped per directive)")
	# Cat has 2 claws + 1 bite per the catalog.
	var routines: Array = cat_stats.get("attack_routines", [])
	check(routines.size() >= 1, "cat has at least one attack routine")


func test_cosmetic_variants_returned() -> void:
	var reg := _make_registry()
	check(reg.get_cosmetic_variants("hawk") == ["Hawk", "Raven", "Eagle", "Falcon", "Owl"],
		"hawk cosmetic variants = Hawk/Raven/Eagle/Falcon/Owl")
	check(reg.get_cosmetic_variants("bat") == ["Bat"],
		"bat has a single cosmetic variant")
	check(reg.get_cosmetic_variants("snake_small") == ["Garter Snake", "Adder", "Viperling"],
		"snake_small cosmetic variants = Garter/Adder/Viperling")


func test_unknown_form_lookup_is_safe() -> void:
	var reg := _make_registry()
	check(reg.has_form("nonexistent") == false, "unknown form returns false")
	# get_form returns empty dict + push_error rather than crashing
	check(reg.get_form("nonexistent").is_empty(), "unknown form returns empty Dictionary")


func test_display_name_falls_back_to_form_key() -> void:
	var reg := _make_registry()
	check(reg.get_display_name("bat") == "Bat", "bat display_name from catalog")
	check(reg.get_display_name("snake_small") == "Snake (Small)", "snake_small uses catalog display_name")


func test_armor_class_caps_at_3_for_project_authored() -> void:
	var reg := _make_registry()
	for form_key in ["cat", "rat", "snake_small", "toad", "weasel"]:
		var ac := reg.get_armor_class(form_key)
		check(ac <= 3, "%s AC must be ≤ 3 per project-authoring rule, got %d" % [form_key, ac])


func test_form_keys_in_catalog_order() -> void:
	var reg := _make_registry()
	var keys := reg.get_all_form_keys()
	# Catalog order: bat, hawk, cat, rat, snake_small, toad, weasel
	check(keys[0] == "bat", "first form key is bat")
	check(keys[1] == "hawk", "second form key is hawk")
	check(keys[6] == "weasel", "last form key is weasel")


func test_is_project_authored_distinguishes_canon_vs_inline() -> void:
	var reg := _make_registry()
	check(reg.is_project_authored("bat") == false, "bat is canon, not project-authored")
	check(reg.is_project_authored("hawk") == false, "hawk is canon, not project-authored")
	check(reg.is_project_authored("cat") == true, "cat is project-authored")
	check(reg.is_project_authored("weasel") == true, "weasel is project-authored")


func test_attack_routines_for_canon_bat() -> void:
	var reg := _make_registry()
	var routines := reg.get_attack_routines("bat")
	check(routines.size() == 1, "bat has 1 attack routine")
	var attacks: Array = routines[0].get("attacks", [])
	check(attacks.size() == 1, "bat routine has 1 attack")
	check(String(attacks[0].get("attack_type", "")) == "bite", "bat attack type is bite")


func test_special_abilities_for_project_cat() -> void:
	var reg := _make_registry()
	var abilities := reg.get_special_abilities("cat")
	var ids: Array[String] = []
	for ab in abilities:
		ids.append(String(ab.get("ability_id", "")))
	check("silent_move" in ids, "cat has silent_move ability")
	check("low_light_vision" in ids, "cat has low_light_vision ability")
