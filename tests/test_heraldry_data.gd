extends "res://tests/test_suite_base.gd"

## Unit tests for Session 1 of the heraldry builder:
##   - HeraldryDescriptor (shared type)
##   - ShieldShapeRegistry, ChargeRegistry, FieldDivisionRegistry,
##     OrdinaryRegistry, TincturePalette, PresetLibrary
##   - CampaignRepository heraldry CRUD round-trip
##
## Run via test_runner.tscn.


var _campaign_id: String = ""
var _party_id: String = ""


func run_all_tests() -> void:
	# ---- HeraldryDescriptor ----
	test_descriptor_defaults()
	test_descriptor_round_trip()
	test_descriptor_color_hex_lowercase()
	test_descriptor_color_hex_uppercase()
	test_descriptor_color_hex_without_hash()
	test_descriptor_color_hex_empty()
	test_descriptor_visual_hash_changes()
	test_descriptor_duplicate_descriptor()

	# ---- ShieldShapeRegistry ----
	test_shape_registry_loads()
	test_shape_registry_lookup_hit()
	test_shape_registry_lookup_miss()

	# ---- ChargeRegistry ----
	test_charge_registry_loads()
	test_charge_registry_lookup_hit()
	test_charge_registry_lookup_miss()
	test_charge_registry_search_by_name()
	test_charge_registry_tags_empty_v1()

	# ---- FieldDivisionRegistry ----
	test_division_registry_has_all_six()
	test_division_registry_plain_empty_polygons()
	test_division_registry_quarterly_two_polygons()

	# ---- OrdinaryRegistry ----
	test_ordinary_registry_has_all_four()
	test_ordinary_registry_bordure_is_border_type()
	test_ordinary_registry_cross_is_filled_type()

	# ---- TincturePalette ----
	test_tincture_palette_has_seven_named()
	test_tincture_palette_is_metal_id()
	test_tincture_palette_luminance_classification()
	test_tincture_palette_is_low_contrast()

	# ---- PresetLibrary ----
	test_preset_library_loads()
	test_preset_library_random_returns_valid()

	# ---- CampaignRepository heraldry CRUD ----
	_setup_campaign()
	test_repo_save_and_get()
	test_repo_assign_to_party()
	test_repo_get_for_party_nonexistent()
	test_repo_create_default_for_party()

	if not has_failures():
		print("HeraldryData: all tests passed.")


# ---------------------------------------------------------------------------
# HeraldryDescriptor
# ---------------------------------------------------------------------------

func test_descriptor_defaults() -> void:
	var d := HeraldryDescriptor.new()
	check(d.heraldry_id == "", "default heraldry_id is empty")
	check(d.shape_id == "english", "default shape is english")
	check(d.division_id == "plain", "default division is plain")
	check(d.ordinary_id == "", "default ordinary is empty")
	check(d.charge_id == "", "default charge is empty")


func test_descriptor_round_trip() -> void:
	var original := HeraldryDescriptor.new()
	original.heraldry_id = "h_abc123"
	original.shape_id = "italian"
	original.division_id = "quarterly"
	original.tincture_primary = Color("#d4af37")
	original.tincture_secondary = Color("#1f3a8a")
	original.ordinary_id = "cross"
	original.tincture_ordinary = Color("#a02020")
	original.charge_id = "eagle_01"
	original.tincture_charge = Color("#1a1a1a")

	var dict := original.to_dict()
	var restored := HeraldryDescriptor.from_dict(dict)

	check(restored.heraldry_id == original.heraldry_id, "heraldry_id round-trip")
	check(restored.shape_id == original.shape_id, "shape_id round-trip")
	check(restored.division_id == original.division_id, "division_id round-trip")
	check(restored.tincture_primary == original.tincture_primary, "tincture_primary round-trip")
	check(restored.tincture_secondary == original.tincture_secondary, "tincture_secondary round-trip")
	check(restored.ordinary_id == original.ordinary_id, "ordinary_id round-trip")
	check(restored.tincture_ordinary == original.tincture_ordinary, "tincture_ordinary round-trip")
	check(restored.charge_id == original.charge_id, "charge_id round-trip")
	check(restored.tincture_charge == original.tincture_charge, "tincture_charge round-trip")


func test_descriptor_color_hex_lowercase() -> void:
	var c := HeraldryDescriptor.color_from_hex("#a1b2c3")
	check(c == Color("#a1b2c3"), "parses lowercase hex")


func test_descriptor_color_hex_uppercase() -> void:
	var c := HeraldryDescriptor.color_from_hex("#A1B2C3")
	check(c == Color("#a1b2c3"), "parses uppercase hex (case-insensitive)")


func test_descriptor_color_hex_without_hash() -> void:
	var c := HeraldryDescriptor.color_from_hex("a1b2c3")
	check(c == Color("#a1b2c3"), "parses hex string without leading '#'")


func test_descriptor_color_hex_empty() -> void:
	var c := HeraldryDescriptor.color_from_hex("")
	check(c == Color.WHITE, "empty string falls back to WHITE")


func test_descriptor_visual_hash_changes() -> void:
	var a := HeraldryDescriptor.new()
	var b := HeraldryDescriptor.new()
	check(a.visual_hash() == b.visual_hash(), "identical descriptors have identical visual_hash")
	b.shape_id = "italian"
	check(a.visual_hash() != b.visual_hash(), "shape_id change flips visual_hash")
	b.shape_id = a.shape_id
	b.tincture_primary = Color("#ffffff")
	# a's default primary is #dcdcdc, so these must differ
	check(a.visual_hash() != b.visual_hash(), "tincture change flips visual_hash")


func test_descriptor_duplicate_descriptor() -> void:
	var a := HeraldryDescriptor.new()
	a.heraldry_id = "h_x"
	a.shape_id = "swiss"
	var b := a.duplicate_descriptor()
	check(b != a, "duplicate is a different instance")
	check(b.shape_id == a.shape_id, "duplicate preserves shape_id")
	b.shape_id = "italian"
	check(a.shape_id == "swiss", "mutating duplicate does not affect original")


# ---------------------------------------------------------------------------
# ShieldShapeRegistry
# ---------------------------------------------------------------------------

func test_shape_registry_loads() -> void:
	var reg := ShieldShapeRegistry.new()
	check(reg.get_shape_count() >= 6, "at least 6 shield shapes (got %d)" % reg.get_shape_count())


func test_shape_registry_lookup_hit() -> void:
	var reg := ShieldShapeRegistry.new()
	var s := reg.get_shape("english")
	check(not s.is_empty(), "english shape exists")
	check(s.get("mask_path", "").begins_with("res://assets/heraldry/escutcheons/"), "english mask_path points to assets")
	check(reg.has_shape("english"), "has_shape returns true")


func test_shape_registry_lookup_miss() -> void:
	var reg := ShieldShapeRegistry.new()
	check(reg.get_shape("no_such_shape").is_empty(), "miss returns empty dict")
	check(not reg.has_shape("no_such_shape"), "has_shape returns false on miss")


# ---------------------------------------------------------------------------
# ChargeRegistry
# ---------------------------------------------------------------------------

func test_charge_registry_loads() -> void:
	var reg := ChargeRegistry.new()
	check(reg.get_charge_count() >= 700, "at least 700 charges loaded (got %d)" % reg.get_charge_count())


func test_charge_registry_lookup_hit() -> void:
	var reg := ChargeRegistry.new()
	var c := reg.get_charge("eagle_01")
	check(not c.is_empty(), "eagle_01 is present in the catalog")
	check(c.get("image_path", "").begins_with("res://assets/heraldry/charges/"), "image_path points to charges folder")


func test_charge_registry_lookup_miss() -> void:
	var reg := ChargeRegistry.new()
	check(reg.get_charge("no_such_charge").is_empty(), "miss returns empty dict")


func test_charge_registry_search_by_name() -> void:
	var reg := ChargeRegistry.new()
	var results := reg.search_by_name("eagle")
	check(results.size() > 0, "search by 'eagle' returns results")
	var empty_search := reg.search_by_name("")
	check(empty_search.size() == reg.get_charge_count(), "empty search returns all charges")


func test_charge_registry_tags_empty_v1() -> void:
	var reg := ChargeRegistry.new()
	# v1 ships with empty tag arrays; tags content pass is deferred.
	check(reg.get_all_tags().size() == 0, "tags empty in v1 (content pass deferred)")
	check(reg.get_charges_by_tag("mammal").size() == 0, "tag filter returns empty when no tags defined")


# ---------------------------------------------------------------------------
# FieldDivisionRegistry
# ---------------------------------------------------------------------------

func test_division_registry_has_all_six() -> void:
	var ids := FieldDivisionRegistry.get_all_division_ids()
	for expected in ["plain", "per_pale", "per_fess", "per_bend", "quarterly", "per_saltire"]:
		check(ids.has(expected), "division '%s' present" % expected)


func test_division_registry_plain_empty_polygons() -> void:
	var d := FieldDivisionRegistry.get_division("plain")
	check(not d.is_empty(), "plain division exists")
	check(d.get("secondary_polygons", []).size() == 0, "plain has no secondary polygons")


func test_division_registry_quarterly_two_polygons() -> void:
	var d := FieldDivisionRegistry.get_division("quarterly")
	check(d.get("secondary_polygons", []).size() == 2, "quarterly has exactly 2 secondary polygons")


# ---------------------------------------------------------------------------
# OrdinaryRegistry
# ---------------------------------------------------------------------------

func test_ordinary_registry_has_all_four() -> void:
	var ids := OrdinaryRegistry.get_all_ordinary_ids()
	for expected in ["cross", "chevron", "chief", "bordure"]:
		check(ids.has(expected), "ordinary '%s' present" % expected)


func test_ordinary_registry_bordure_is_border_type() -> void:
	var d := OrdinaryRegistry.get_ordinary("bordure")
	check(d.get("render_type", "") == "border", "bordure renders as border")
	check(d.get("border_inset_ratio", 0.0) > 0.0, "bordure has positive border_inset_ratio")


func test_ordinary_registry_cross_is_filled_type() -> void:
	var d := OrdinaryRegistry.get_ordinary("cross")
	check(d.get("render_type", "") == "filled", "cross renders as filled polygons")
	check(d.get("polygons", []).size() == 2, "cross has vertical and horizontal bars")


# ---------------------------------------------------------------------------
# TincturePalette
# ---------------------------------------------------------------------------

func test_tincture_palette_has_seven_named() -> void:
	var ids := TincturePalette.get_all_tincture_ids()
	check(ids.size() == 7, "exactly 7 named tinctures")
	for expected in ["or", "argent", "gules", "azure", "sable", "vert", "purpure"]:
		check(ids.has(expected), "tincture '%s' present" % expected)


func test_tincture_palette_is_metal_id() -> void:
	check(TincturePalette.is_metal_id("or"), "or is a metal")
	check(TincturePalette.is_metal_id("argent"), "argent is a metal")
	check(not TincturePalette.is_metal_id("gules"), "gules is not a metal")
	check(not TincturePalette.is_metal_id("azure"), "azure is not a metal")


func test_tincture_palette_luminance_classification() -> void:
	var or_color := TincturePalette.get_tincture_color("or")
	var sable_color := TincturePalette.get_tincture_color("sable")
	check(TincturePalette.classify_color(or_color) == "metal", "Or classifies as metal by luminance")
	check(TincturePalette.classify_color(sable_color) == "color", "Sable classifies as color by luminance")
	var argent_color := TincturePalette.get_tincture_color("argent")
	check(TincturePalette.classify_color(argent_color) == "metal", "Argent classifies as metal by luminance")


func test_tincture_palette_is_low_contrast() -> void:
	var or_c := TincturePalette.get_tincture_color("or")
	var argent_c := TincturePalette.get_tincture_color("argent")
	var gules_c := TincturePalette.get_tincture_color("gules")
	var azure_c := TincturePalette.get_tincture_color("azure")
	check(TincturePalette.is_low_contrast(or_c, argent_c), "metal-on-metal is low contrast")
	check(TincturePalette.is_low_contrast(gules_c, azure_c), "color-on-color is low contrast")
	check(not TincturePalette.is_low_contrast(or_c, gules_c), "metal-on-color is OK contrast")


# ---------------------------------------------------------------------------
# PresetLibrary
# ---------------------------------------------------------------------------

func test_preset_library_loads() -> void:
	var lib := PresetLibrary.new()
	check(lib.preset_count() >= 8, "at least 8 starter presets (got %d)" % lib.preset_count())


func test_preset_library_random_returns_valid() -> void:
	var lib := PresetLibrary.new()
	var shapes := ShieldShapeRegistry.new()
	# Exercise randomness a handful of times.
	for _i in range(20):
		var d := lib.get_random_preset_descriptor()
		check(shapes.has_shape(d.shape_id), "preset shape_id '%s' resolves in ShieldShapeRegistry" % d.shape_id)
		check(FieldDivisionRegistry.has_division(d.division_id), "preset division_id '%s' resolves" % d.division_id)
		if not d.ordinary_id.is_empty():
			check(OrdinaryRegistry.has_ordinary(d.ordinary_id), "preset ordinary_id '%s' resolves" % d.ordinary_id)


# ---------------------------------------------------------------------------
# CampaignRepository heraldry CRUD
# ---------------------------------------------------------------------------

func _setup_campaign() -> void:
	_campaign_id = CampaignRepository.create_campaign(
		"Test Heraldry", "TestWorld"
	)
	check(not _campaign_id.is_empty(), "campaign created for heraldry CRUD tests")
	_party_id = CampaignRepository.create_party(_campaign_id, "Heraldry Test Party")
	check(not _party_id.is_empty(), "party created for heraldry CRUD tests")


func test_repo_save_and_get() -> void:
	var d := HeraldryDescriptor.new()
	d.heraldry_id = CampaignRepository.generate_id()
	d.shape_id = "italian"
	d.division_id = "per_fess"
	d.tincture_primary = Color("#a02020")
	d.tincture_secondary = Color("#d4af37")
	d.ordinary_id = "chief"
	d.tincture_ordinary = Color("#1a1a1a")
	d.charge_id = "eagle_01"
	d.tincture_charge = Color("#dcdcdc")

	check(CampaignRepository.save_heraldry(d), "save_heraldry succeeds")

	var loaded := CampaignRepository.get_heraldry(d.heraldry_id)
	check(loaded != null, "get_heraldry returns a descriptor")
	check(loaded.heraldry_id == d.heraldry_id, "heraldry_id round-trips through DB")
	check(loaded.shape_id == d.shape_id, "shape_id round-trips")
	check(loaded.division_id == d.division_id, "division_id round-trips")
	check(loaded.tincture_primary == d.tincture_primary, "tincture_primary round-trips")
	check(loaded.tincture_secondary == d.tincture_secondary, "tincture_secondary round-trips")
	check(loaded.ordinary_id == d.ordinary_id, "ordinary_id round-trips")
	check(loaded.tincture_ordinary == d.tincture_ordinary, "tincture_ordinary round-trips")
	check(loaded.charge_id == d.charge_id, "charge_id round-trips")
	check(loaded.tincture_charge == d.tincture_charge, "tincture_charge round-trips")

	# Upsert path: mutate and save again, verify the row was updated not duplicated.
	d.shape_id = "swiss"
	check(CampaignRepository.save_heraldry(d), "upsert save succeeds")
	var reloaded := CampaignRepository.get_heraldry(d.heraldry_id)
	check(reloaded.shape_id == "swiss", "upsert updates shape_id")


func test_repo_assign_to_party() -> void:
	var d := HeraldryDescriptor.new()
	d.heraldry_id = CampaignRepository.generate_id()
	d.shape_id = "english"
	check(CampaignRepository.save_heraldry(d), "save for assignment test")
	check(CampaignRepository.assign_heraldry_to_party(_party_id, d.heraldry_id),
		"assign_heraldry_to_party succeeds")

	var via_party := CampaignRepository.get_heraldry_for_party(_party_id)
	check(via_party != null, "get_heraldry_for_party resolves")
	check(via_party.heraldry_id == d.heraldry_id, "correct heraldry linked to party")


func test_repo_get_for_party_nonexistent() -> void:
	var nothing := CampaignRepository.get_heraldry_for_party("party_that_doesnt_exist")
	check(nothing == null, "missing party returns null")


func test_repo_create_default_for_party() -> void:
	# Fresh party with no heraldry yet.
	var blank_party_id := CampaignRepository.create_party(_campaign_id, "Blank Party")
	check(not blank_party_id.is_empty(), "blank party created")

	var pre_check := CampaignRepository.get_heraldry_for_party(blank_party_id)
	check(pre_check == null, "blank party has no heraldry initially")

	var new_id := CampaignRepository.create_default_heraldry_for_party(blank_party_id)
	check(not new_id.is_empty(), "create_default_heraldry_for_party returns non-empty id")

	var loaded := CampaignRepository.get_heraldry(new_id)
	check(loaded != null, "the new heraldry row exists")

	var via_party := CampaignRepository.get_heraldry_for_party(blank_party_id)
	check(via_party != null, "the new heraldry is now linked to the party")
	check(via_party.heraldry_id == new_id, "link points at the newly-created heraldry")

	# The descriptor should be sourced from a preset — all registry IDs valid.
	var shapes := ShieldShapeRegistry.new()
	check(shapes.has_shape(via_party.shape_id),
		"backfilled shape_id '%s' resolves" % via_party.shape_id)
	check(FieldDivisionRegistry.has_division(via_party.division_id),
		"backfilled division_id resolves")
