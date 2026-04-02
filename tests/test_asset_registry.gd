extends "res://tests/test_suite_base.gd"

## Unit tests for AssetRegistry.
##
## Tests verify manifest loading, ID lookup, registration, and that all
## expected portrait/terrain/UI entries are present.


func run_all_tests() -> void:
	test_get_path_unknown_id_returns_empty()
	test_has_asset_false_for_unknown()
	test_register_and_retrieve()
	test_has_asset_true_after_register()
	test_register_overwrites()
	test_all_25_portrait_classes_have_variant_01()
	test_terrain_atlas_registered()
	test_ui_bg_registered()
	test_portrait_paths_are_res_scheme()
	test_get_all_ids_includes_registered()
	if not has_failures():
		print("AssetRegistry: all tests passed.")


func test_get_path_unknown_id_returns_empty() -> void:
	var result := AssetRegistry.get_asset_path("no.such.asset.id.xyz")
	check(result == "", "unknown id should return empty string, got '%s'" % result)


func test_has_asset_false_for_unknown() -> void:
	check(
		not AssetRegistry.has_asset("no.such.asset.id.xyz"),
		"has_asset should be false for unknown id"
	)


func test_register_and_retrieve() -> void:
	AssetRegistry.register("test.register.retrieve", "res://test_placeholder.png")
	var result := AssetRegistry.get_asset_path("test.register.retrieve")
	check(result == "res://test_placeholder.png",
		"registered path should be retrievable, got '%s'" % result)


func test_has_asset_true_after_register() -> void:
	AssetRegistry.register("test.has_asset.check", "res://dummy.png")
	check(AssetRegistry.has_asset("test.has_asset.check"),
		"has_asset should be true after register()")


func test_register_overwrites() -> void:
	AssetRegistry.register("test.overwrite", "res://first.png")
	AssetRegistry.register("test.overwrite", "res://second.png")
	var result := AssetRegistry.get_asset_path("test.overwrite")
	check(result == "res://second.png",
		"second register() should overwrite first, got '%s'" % result)


func test_all_25_portrait_classes_have_variant_01() -> void:
	var classes := [
		"fighter", "assassin", "bard", "thief", "dwarf_vaultguard",
		"dwarven_delver", "explorer", "dwarven_fury", "venturer", "elven_ranger",
		"bladedancer", "mage", "elven_enchanter", "elf_nightblade", "elven_courtier",
		"cleric", "dwarf_craftpriest", "elf_spellsword", "barbarian", "shaman",
		"witch", "anti_paladin", "priestess", "paladin", "warlock"
	]
	for cls in classes:
		var id := "portrait.%s_01" % cls
		check(AssetRegistry.has_asset(id),
			"portrait id '%s' should be registered" % id)


func test_terrain_atlas_registered() -> void:
	check(AssetRegistry.has_asset("terrain.atlas"),
		"terrain.atlas should be registered in the manifest")


func test_ui_bg_registered() -> void:
	check(AssetRegistry.has_asset("ui.bg.vellum_base"),
		"ui.bg.vellum_base should be registered")
	check(AssetRegistry.has_asset("ui.bg.vellum_subtle"),
		"ui.bg.vellum_subtle should be registered")


func test_portrait_paths_are_res_scheme() -> void:
	var path := AssetRegistry.get_asset_path("portrait.fighter_01")
	check(path.begins_with("res://"),
		"portrait path should start with res://, got '%s'" % path)


func test_get_all_ids_includes_registered() -> void:
	AssetRegistry.register("test.get_all_ids.unique", "res://dummy.png")
	var ids := AssetRegistry.get_all_ids()
	check(ids.has("test.get_all_ids.unique"),
		"get_all_ids() should include newly registered id")
