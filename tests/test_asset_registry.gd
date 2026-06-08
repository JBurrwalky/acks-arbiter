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
	test_all_portrait_classes_present_in_manifests()
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


func test_all_portrait_classes_present_in_manifests() -> void:
	# Portraits use the ethnicity_class_gender_number convention (data/portrait_manifest.json
	# carries the parsed class). Verify each expected class has at least one portrait and
	# that its path is registered in the asset_manifest (the two manifests stay in sync).
	var classes := [
		"fighter", "assassin", "bard", "thief", "dwarven_vaultguard",
		"explorer", "dwarven_fury", "venturer",
		"bladedancer", "mage", "elven_enchanter", "elven_nightblade",
		"cleric", "dwarven_craftpriest", "elven_spellsword", "barbarian", "shaman",
		"witch", "priestess", "paladin",
		"darkblood_ruinguard", "lightblessed_wonderworker"
	]
	var by_class := {}            # class -> Array of entries
	var file := FileAccess.open("res://data/portrait_manifest.json", FileAccess.READ)
	check(file != null, "portrait_manifest.json should be readable")
	if file == null:
		return
	var json := JSON.new()
	check(json.parse(file.get_as_text()) == OK, "portrait_manifest.json should parse")
	file.close()
	for entry in (json.data as Dictionary).get("portraits", []):
		var cls: String = entry.get("class", "")
		if not by_class.has(cls):
			by_class[cls] = []
		by_class[cls].append(entry)

	for cls in classes:
		check(by_class.has(cls) and not (by_class[cls] as Array).is_empty(),
			"class '%s' should have at least one portrait in the manifest" % cls)
		if by_class.has(cls):
			var first: Dictionary = (by_class[cls] as Array)[0]
			var id := "portrait.%s" % first.get("id", "")
			check(AssetRegistry.has_asset(id),
				"portrait id '%s' should be registered in asset_manifest" % id)


func test_terrain_atlas_registered() -> void:
	check(AssetRegistry.has_asset("terrain.atlas"),
		"terrain.atlas should be registered in the manifest")


func test_ui_bg_registered() -> void:
	check(AssetRegistry.has_asset("ui.bg.vellum_base"),
		"ui.bg.vellum_base should be registered")
	check(AssetRegistry.has_asset("ui.bg.vellum_subtle"),
		"ui.bg.vellum_subtle should be registered")


func test_portrait_paths_are_res_scheme() -> void:
	var path := AssetRegistry.get_asset_path("portrait.asian_fighter_male_01")
	check(path.begins_with("res://"),
		"portrait path should start with res://, got '%s'" % path)


func test_get_all_ids_includes_registered() -> void:
	AssetRegistry.register("test.get_all_ids.unique", "res://dummy.png")
	var ids := AssetRegistry.get_all_ids()
	check(ids.has("test.get_all_ids.unique"),
		"get_all_ids() should include newly registered id")
