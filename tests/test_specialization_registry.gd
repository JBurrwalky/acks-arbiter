extends Node

## Unit tests for SpecializationRegistry.
## Verifies JSON loading, per-proficiency entry counts, lookup by key and ID,
## display name resolution, and prerequisite population.


func run_all_tests() -> void:
	test_catalog_loads()
	test_has_specializations_riding()
	test_has_specializations_non_spec()
	test_get_specializations_riding_count()
	test_get_specializations_craft_count()
	test_get_specialization_by_id()
	test_get_specialization_ids()
	test_unknown_proficiency_returns_empty()
	test_display_name_lookup()
	test_display_name_unknown_returns_empty()
	test_weapon_focus_six_entries()
	test_elementalism_four_entries()
	test_knowledge_fourteen_entries()
	test_prerequisite_ids_fantastic_mounts()
	test_naturalism_eleven_entries()
	print("SpecializationRegistry: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_catalog_loads() -> void:
	var reg := SpecializationRegistry.new()
	# Registry should have entries for all 14 specialization proficiencies.
	# animal_training: 27 entries (26 from GDD table + giant_crabs)
	for key in ["weapon_focus", "riding", "animal_training", "knowledge", "craft",
			"art", "performance", "profession", "language", "naturalism",
			"collegiate_wizardry", "signaling", "labor", "elementalism"]:
		assert(reg.has_specializations(key),
			"SpecializationRegistry: should have specializations for '%s'" % key)


func test_has_specializations_riding() -> void:
	var reg := SpecializationRegistry.new()
	assert(reg.has_specializations("riding"),
		"SpecializationRegistry: riding should have specializations")


func test_has_specializations_non_spec() -> void:
	var reg := SpecializationRegistry.new()
	assert(not reg.has_specializations("divine_blessing"),
		"SpecializationRegistry: divine_blessing should not have specializations (not in registry)")
	assert(not reg.has_specializations("nonexistent_key"),
		"SpecializationRegistry: nonexistent key should return false")


func test_get_specializations_riding_count() -> void:
	var reg := SpecializationRegistry.new()
	var specs := reg.get_specializations("riding")
	assert(specs.size() == 15,
		"SpecializationRegistry: riding should have 15 specializations, got %d" % specs.size())
	# Each entry should have required fields
	for entry in specs:
		assert(entry.has("id"), "SpecializationRegistry: riding entry missing 'id'")
		assert(entry.has("display_name"), "SpecializationRegistry: riding entry missing 'display_name'")
		assert(entry.has("layer"), "SpecializationRegistry: riding entry missing 'layer'")
		assert(entry.has("prerequisite_ids"), "SpecializationRegistry: riding entry missing 'prerequisite_ids'")


func test_get_specializations_craft_count() -> void:
	var reg := SpecializationRegistry.new()
	var specs := reg.get_specializations("craft")
	assert(specs.size() == 32,
		"SpecializationRegistry: craft should have 32 specializations, got %d" % specs.size())


func test_get_specialization_by_id() -> void:
	var reg := SpecializationRegistry.new()
	var entry := reg.get_specialization("riding", "horses")
	assert(not entry.is_empty(),
		"SpecializationRegistry: get_specialization('riding', 'horses') should return a dict")
	assert(entry.get("id", "") == "horses",
		"SpecializationRegistry: horses entry id should be 'horses'")
	assert(entry.get("display_name", "") == "Horses",
		"SpecializationRegistry: horses display_name should be 'Horses'")
	assert(entry.get("layer", "") == "base",
		"SpecializationRegistry: horses layer should be 'base'")


func test_get_specialization_ids() -> void:
	var reg := SpecializationRegistry.new()
	var ids := reg.get_specialization_ids("knowledge")
	assert(ids.size() == 14,
		"SpecializationRegistry: knowledge should have 14 IDs, got %d" % ids.size())
	assert("history" in ids,
		"SpecializationRegistry: 'history' should be in knowledge IDs")
	assert("occult" in ids,
		"SpecializationRegistry: 'occult' should be in knowledge IDs")
	# All entries should be strings
	for id in ids:
		assert(id is String,
			"SpecializationRegistry: knowledge ID should be a String, got %s" % str(id))


func test_unknown_proficiency_returns_empty() -> void:
	var reg := SpecializationRegistry.new()
	assert(reg.get_specializations("not_real").is_empty(),
		"SpecializationRegistry: unknown proficiency should return empty array")
	assert(reg.get_specialization_ids("not_real").is_empty(),
		"SpecializationRegistry: unknown proficiency IDs should return empty array")
	assert(reg.get_specialization("not_real", "horses").is_empty(),
		"SpecializationRegistry: unknown proficiency get_specialization should return empty dict")


func test_display_name_lookup() -> void:
	var reg := SpecializationRegistry.new()
	assert(reg.get_specialization_display_name("knowledge", "history") == "History",
		"SpecializationRegistry: knowledge/history display name should be 'History'")
	assert(reg.get_specialization_display_name("performance", "playing_instruments") == "Playing instruments",
		"SpecializationRegistry: performance/playing_instruments display name should be correct")


func test_display_name_unknown_returns_empty() -> void:
	var reg := SpecializationRegistry.new()
	assert(reg.get_specialization_display_name("knowledge", "nonexistent_id") == "",
		"SpecializationRegistry: unknown spec ID should return empty string")
	assert(reg.get_specialization_display_name("not_real", "anything") == "",
		"SpecializationRegistry: unknown proficiency should return empty string")


func test_weapon_focus_six_entries() -> void:
	var reg := SpecializationRegistry.new()
	var ids := reg.get_specialization_ids("weapon_focus")
	assert(ids.size() == 6,
		"SpecializationRegistry: weapon_focus should have 6 entries, got %d" % ids.size())
	for expected in ["axes", "maces_flails_hammers", "swords_daggers", "bows_crossbows",
			"slings_thrown", "spears_polearms"]:
		assert(expected in ids,
			"SpecializationRegistry: weapon_focus should include '%s'" % expected)


func test_elementalism_four_entries() -> void:
	var reg := SpecializationRegistry.new()
	var ids := reg.get_specialization_ids("elementalism")
	assert(ids.size() == 4,
		"SpecializationRegistry: elementalism should have 4 entries, got %d" % ids.size())
	for expected in ["air", "earth", "fire", "water"]:
		assert(expected in ids,
			"SpecializationRegistry: elementalism should include '%s'" % expected)


func test_knowledge_fourteen_entries() -> void:
	var reg := SpecializationRegistry.new()
	var ids := reg.get_specialization_ids("knowledge")
	assert(ids.size() == 14,
		"SpecializationRegistry: knowledge should have 14 entries, got %d" % ids.size())


func test_prerequisite_ids_fantastic_mounts() -> void:
	var reg := SpecializationRegistry.new()
	# Griffons require hawks_falcons as prerequisite
	var griffon := reg.get_specialization("riding", "griffons")
	assert(not griffon.is_empty(),
		"SpecializationRegistry: griffons entry should exist in riding")
	var prereqs: Array = griffon.get("prerequisite_ids", [])
	assert(not prereqs.is_empty(),
		"SpecializationRegistry: griffons should have prerequisite_ids (not empty)")
	assert("hawks_falcons" in prereqs,
		"SpecializationRegistry: griffons prerequisite should include hawks_falcons")
	# Horses have no prerequisites
	var horses := reg.get_specialization("riding", "horses")
	var horse_prereqs: Array = horses.get("prerequisite_ids", [])
	assert(horse_prereqs.is_empty(),
		"SpecializationRegistry: horses should have no prerequisite_ids")


func test_naturalism_eleven_entries() -> void:
	var reg := SpecializationRegistry.new()
	var ids := reg.get_specialization_ids("naturalism")
	assert(ids.size() == 11,
		"SpecializationRegistry: naturalism should have 11 entries, got %d" % ids.size())
	assert("forest" in ids,
		"SpecializationRegistry: naturalism should include 'forest'")
	assert("underground" in ids,
		"SpecializationRegistry: naturalism should include 'underground'")
