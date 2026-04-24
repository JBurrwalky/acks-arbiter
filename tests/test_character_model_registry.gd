extends "res://tests/test_suite_base.gd"

## Unit tests for CharacterModelRegistry — path resolution, scale lookup,
## default/available-variant resolution, and fallback behavior for classes
## with no registered GLB.

const CharacterModelRegistryScript := preload("res://scenes/ui/components/character_model_registry.gd")


func run_all_tests() -> void:
	test_has_model_hits()
	test_has_model_misses()
	test_get_model_path_resolves_under_assets()
	test_get_model_path_empty_on_miss()
	test_scale_generic_male_and_female()
	test_scale_short_classes()
	test_scale_medium_classes()
	test_short_overrides_sex_default()
	test_default_variant_prefers_def()
	test_default_variant_falls_back_to_alt()
	test_default_variant_empty_for_unknown_class()
	test_available_variants_orders_def_first()
	test_available_variants_empty_for_unknown_triple()
	test_available_sexes_reports_both_when_present()
	test_available_sexes_single_sex_class()
	test_has_any_model_true_for_registered_class()
	test_has_any_model_false_for_unregistered()
	test_elf_aliases_resolve_to_base_class()
	test_dwarf_aliases_resolve_to_base_class()
	test_alias_preserves_scale_overrides()


func test_has_model_hits() -> void:
	check(CharacterModelRegistryScript.has_model("fighter", "def", "male"),
		"fighter/def/male should be registered")
	check(CharacterModelRegistryScript.has_model("fighter", "def", "female"),
		"fighter/def/female should be registered")
	check(CharacterModelRegistryScript.has_model("assassin", "alt1", "male"),
		"assassin/alt1/male should be registered")
	check(CharacterModelRegistryScript.has_model("bladedancer", "alt1", "female"),
		"bladedancer/alt1/female (renamed from hyphenated form) should be registered")


func test_has_model_misses() -> void:
	check(not CharacterModelRegistryScript.has_model("paladin", "def", "female"),
		"paladin/def/female should NOT be registered (only male paladin GLBs exist)")
	check(not CharacterModelRegistryScript.has_model("fighter", "alt9", "male"),
		"fighter/alt9/male should NOT be registered (no such variant)")
	check(not CharacterModelRegistryScript.has_model("nonexistent_class", "def", "male"),
		"unknown class should not resolve")


func test_get_model_path_resolves_under_assets() -> void:
	var path: String = CharacterModelRegistryScript.get_model_path("fighter", "def", "male")
	check(path == "res://assets/tokens/characters/fighter_def_male.glb",
		"fighter/def/male path should resolve to the expected asset. Got: %s" % path)


func test_get_model_path_empty_on_miss() -> void:
	var path: String = CharacterModelRegistryScript.get_model_path("paladin", "def", "female")
	check(path == "", "missing model should return empty path")


func test_scale_generic_male_and_female() -> void:
	var g: float = CharacterModelRegistryScript.GLOBAL_SCALE
	var fighter_male: float = CharacterModelRegistryScript.get_scale("fighter", "male")
	check(is_equal_approx(fighter_male, 1.85 * g),
		"fighter male scale should be 1.85 * GLOBAL_SCALE, got %s" % fighter_male)
	var fighter_female: float = CharacterModelRegistryScript.get_scale("fighter", "female")
	check(is_equal_approx(fighter_female, 1.75 * g),
		"fighter female scale should be 1.75 * GLOBAL_SCALE, got %s" % fighter_female)


func test_scale_short_classes() -> void:
	var g: float = CharacterModelRegistryScript.GLOBAL_SCALE
	var vg: float = CharacterModelRegistryScript.get_scale("vaultguard", "male")
	check(is_equal_approx(vg, 1.25 * g),
		"vaultguard scale should be 1.25 * GLOBAL_SCALE, got %s" % vg)
	var cp: float = CharacterModelRegistryScript.get_scale("craftpriest", "male")
	check(is_equal_approx(cp, 1.25 * g),
		"craftpriest scale should be 1.25 * GLOBAL_SCALE, got %s" % cp)


func test_scale_medium_classes() -> void:
	var g: float = CharacterModelRegistryScript.GLOBAL_SCALE
	var spellsword: float = CharacterModelRegistryScript.get_scale("spellsword", "male")
	check(is_equal_approx(spellsword, 1.70 * g),
		"spellsword should override male default, got %s" % spellsword)
	var enchanter_female: float = CharacterModelRegistryScript.get_scale("enchanter", "female")
	check(is_equal_approx(enchanter_female, 1.70 * g),
		"enchanter female should override female default, got %s" % enchanter_female)
	var nightblade: float = CharacterModelRegistryScript.get_scale("nightblade", "male")
	check(is_equal_approx(nightblade, 1.70 * g),
		"nightblade should override male default, got %s" % nightblade)


func test_short_overrides_sex_default() -> void:
	# The short-class override applies regardless of sex (there are no
	# female vaultguard/craftpriest models shipped, but the rule still holds
	# for any hypothetical future additions).
	var g: float = CharacterModelRegistryScript.GLOBAL_SCALE
	var vg_female: float = CharacterModelRegistryScript.get_scale("vaultguard", "female")
	check(is_equal_approx(vg_female, 1.25 * g),
		"vaultguard female should also be 1.25 * GLOBAL_SCALE, got %s" % vg_female)


func test_default_variant_prefers_def() -> void:
	var v: String = CharacterModelRegistryScript.get_default_variant("fighter", "male")
	check(v == "def", "expected 'def' for fighter male, got '%s'" % v)


func test_default_variant_falls_back_to_alt() -> void:
	# No bladedancer "def" male model exists; there's also no alt male, so
	# the default variant for male should be "". For the female path though,
	# a def does exist — use that as a positive control.
	var f: String = CharacterModelRegistryScript.get_default_variant("bladedancer", "female")
	check(f == "def", "bladedancer female should default to 'def', got '%s'" % f)
	var m: String = CharacterModelRegistryScript.get_default_variant("bladedancer", "male")
	check(m == "", "bladedancer male has no model — expected empty default, got '%s'" % m)


func test_default_variant_empty_for_unknown_class() -> void:
	var v: String = CharacterModelRegistryScript.get_default_variant("mystery_class", "male")
	check(v == "", "unknown class should produce empty default")


func test_available_variants_orders_def_first() -> void:
	var variants: Array[String] = CharacterModelRegistryScript.get_available_variants(
		"fighter", "male")
	check(variants.size() == 4,
		"fighter male should have 4 variants (def + alt1/2/3), got %s" % variants.size())
	check(variants[0] == "def", "def must come first, got '%s'" % variants[0])
	check(variants.has("alt1") and variants.has("alt2") and variants.has("alt3"),
		"fighter male should include alt1/alt2/alt3")


func test_available_variants_empty_for_unknown_triple() -> void:
	var none: Array[String] = CharacterModelRegistryScript.get_available_variants(
		"fighter", "")
	check(none.is_empty(), "empty sex should yield no variants")


func test_available_sexes_reports_both_when_present() -> void:
	var sexes: Array[String] = CharacterModelRegistryScript.get_available_sexes("fighter")
	check("male" in sexes and "female" in sexes,
		"fighter should have both male and female models")


func test_available_sexes_single_sex_class() -> void:
	var sexes: Array[String] = CharacterModelRegistryScript.get_available_sexes("paladin")
	check("male" in sexes and not "female" in sexes,
		"paladin ships male-only placeholders")


func test_has_any_model_true_for_registered_class() -> void:
	check(CharacterModelRegistryScript.has_any_model("fighter", "male"),
		"fighter male should have at least one model")


func test_has_any_model_false_for_unregistered() -> void:
	check(not CharacterModelRegistryScript.has_any_model("ghost_warrior", "male"),
		"unregistered class should have no model")
	check(not CharacterModelRegistryScript.has_any_model("paladin", "female"),
		"paladin female has no models shipped")


## Racial-prefix class IDs (elven_spellsword, elven_nightblade, elven_enchanter)
## must resolve to the bare-stem GLBs in assets/tokens/characters/.
func test_elf_aliases_resolve_to_base_class() -> void:
	check(CharacterModelRegistryScript.has_model("elven_spellsword", "def", "male"),
		"elven_spellsword/def/male should alias to spellsword_def_male")
	check(CharacterModelRegistryScript.has_model("elven_nightblade", "def", "female"),
		"elven_nightblade/def/female should alias to nightblade_def_female")
	check(CharacterModelRegistryScript.has_model("elven_enchanter", "def", "male"),
		"elven_enchanter/def/male should alias to enchanter_def_male")
	var path: String = CharacterModelRegistryScript.get_model_path(
		"elven_spellsword", "def", "male")
	check(path == "res://assets/tokens/characters/spellsword_def_male.glb",
		"elven_spellsword path should resolve to spellsword_def_male.glb, got: %s" % path)
	var variants: Array[String] = CharacterModelRegistryScript.get_available_variants(
		"elven_spellsword", "male")
	check("def" in variants and "alt1" in variants,
		"elven_spellsword should surface all spellsword variants, got %s" % [variants])
	check(CharacterModelRegistryScript.has_any_model("elven_spellsword", "male"),
		"elven_spellsword should pass has_any_model")


## Dwarven-prefix classes alias the same way.
func test_dwarf_aliases_resolve_to_base_class() -> void:
	check(CharacterModelRegistryScript.has_model("dwarven_vaultguard", "def", "male"),
		"dwarven_vaultguard should alias to vaultguard_def_male")
	check(CharacterModelRegistryScript.has_model("dwarven_craftpriest", "def", "male"),
		"dwarven_craftpriest should alias to craftpriest_def_male")
	check(CharacterModelRegistryScript.has_model("dwarven_fury", "def", "male"),
		"dwarven_fury should alias to fury_def_male")
	var sexes: Array[String] = CharacterModelRegistryScript.get_available_sexes("dwarven_vaultguard")
	check("male" in sexes, "dwarven_vaultguard should expose male sex")


## Aliased class_ids must still hit the short / medium scale overrides.
func test_alias_preserves_scale_overrides() -> void:
	var g: float = CharacterModelRegistryScript.GLOBAL_SCALE
	var elf_sw: float = CharacterModelRegistryScript.get_scale("elven_spellsword", "male")
	check(is_equal_approx(elf_sw, 1.70 * g),
		"elven_spellsword should be MEDIUM (1.70 * GLOBAL_SCALE), got %s" % elf_sw)
	var dwarf_vg: float = CharacterModelRegistryScript.get_scale("dwarven_vaultguard", "male")
	check(is_equal_approx(dwarf_vg, 1.25 * g),
		"dwarven_vaultguard should be SHORT (1.25 * GLOBAL_SCALE), got %s" % dwarf_vg)
	var dwarf_cp: float = CharacterModelRegistryScript.get_scale("dwarven_craftpriest", "male")
	check(is_equal_approx(dwarf_cp, 1.25 * g),
		"dwarven_craftpriest should be SHORT, got %s" % dwarf_cp)
	var dwarven_fury: float = CharacterModelRegistryScript.get_scale("dwarven_fury", "male")
	check(is_equal_approx(dwarven_fury, 1.85 * g),
		"dwarven_fury should use the male default (no override), got %s" % dwarven_fury)
