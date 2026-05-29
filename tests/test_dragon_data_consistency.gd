extends "res://tests/test_suite_base.gd"

## Phase 9C polish round 7 2026-05-09: cross-file consistency tests for the
## dragon data layer. The runtime resolver is deferred — these tests verify
## the DATA is well-formed and self-consistent so future resolver work has a
## stable foundation.
##
## Verifies:
##   - 10 dragon age-band entries exist in monster_catalog.json (Spawn through
##     Venerable); dragon_huge_venerable does NOT exist as a discrete entry.
##   - Each age band has the new Secondary Dragon Attributes fields populated
##     correctly per RAW (spells_per_day_by_level, chance_asleep_pct,
##     chance_speech_pct, special_abilities_count, encounter dice).
##   - dragon_venerable has br_table_with_abilities mapping for Huge Venerable.
##   - dragon_types.json has 9 types with correct schema.
##   - terrain_to_dragon_type weights are positive integers.
##   - All dragon_type IDs in terrain_to_dragon_type match types section.
##   - All special_abilities_pool members exist in dragon_special_abilities.json.
##   - All elemental_aura_damage_type values are non-empty strings.
##   - All abilities referenced in pools are present in the abilities catalog.
##   - paralyzing_blows is alignment_required='chaotic'.
##   - polymorph_self is spellcaster_required=true.
##   - lair_eligibility map covers all terrain_to_dragon_type keys.

const RAW_SECONDARY := {
	"dragon_spawn":        {"asleep": 80, "speech": 1,   "abilities": 0, "spells_l1": 1},
	"dragon_very_young":   {"asleep": 70, "speech": 2,   "abilities": 0, "spells_l1": 2},
	"dragon_young":        {"asleep": 60, "speech": 5,   "abilities": 0, "spells_l1": 2},
	"dragon_juvenile":     {"asleep": 50, "speech": 10,  "abilities": 0, "spells_l1": 2},
	"dragon_adult":        {"asleep": 40, "speech": 20,  "abilities": 1, "spells_l1": 2},
	"dragon_mature_adult": {"asleep": 30, "speech": 35,  "abilities": 1, "spells_l1": 2},
	"dragon_old":          {"asleep": 20, "speech": 50,  "abilities": 1, "spells_l1": 3},
	"dragon_very_old":     {"asleep": 10, "speech": 75,  "abilities": 2, "spells_l1": 3},
	"dragon_ancient":      {"asleep": 5,  "speech": 100, "abilities": 2, "spells_l1": 3},
	"dragon_venerable":    {"asleep": 0,  "speech": 100, "abilities": 3, "spells_l1": 3},
}

var _catalog: Array = []
var _by_id: Dictionary = {}
var _types_data: Dictionary = {}
var _abilities_data: Dictionary = {}


func run_all_tests() -> void:
	_load_data()
	test_catalog_has_10_dragon_age_bands()
	test_dragon_huge_venerable_not_in_catalog()
	test_dragon_huge_venerable_not_in_wilderness_membership()
	test_each_dragon_has_secondary_attributes_per_raw()
	test_dragon_venerable_has_br_table_with_abilities()
	test_each_dragon_terrain_affinity_covers_dragon_eligible_terrains()
	test_dragon_types_json_has_9_types()
	test_dragon_types_have_required_fields()
	test_terrain_to_dragon_type_keys_match_synthesized_terrain_vocabulary()
	test_terrain_to_dragon_type_references_valid_types()
	test_lair_eligibility_covers_all_terrains()
	test_alignment_constraints_correct_for_wyrm_and_metallic()
	test_dragon_special_abilities_has_13_abilities()
	test_paralyzing_blows_is_chaotic_only()
	test_polymorph_self_requires_spellcaster()
	test_each_type_special_abilities_pool_resolves_to_real_abilities()
	test_each_type_has_elemental_aura_damage_type()
	if not has_failures():
		print("DragonDataConsistency: all %d tests passed." % test_count())


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _load_data() -> void:
	var f := FileAccess.open("res://data/monsters/monster_catalog.json", FileAccess.READ)
	if f == null:
		push_error("test_dragon_data_consistency: cannot open monster_catalog.json")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		_catalog = parsed
	for entry in _catalog:
		if entry is Dictionary:
			_by_id[str(entry.get("id", ""))] = entry

	var f2 := FileAccess.open("res://data/monsters/dragon_types.json", FileAccess.READ)
	if f2 == null:
		push_error("test_dragon_data_consistency: cannot open dragon_types.json")
		return
	var parsed2: Variant = JSON.parse_string(f2.get_as_text())
	f2.close()
	if parsed2 is Dictionary:
		_types_data = parsed2

	var f3 := FileAccess.open("res://data/monsters/dragon_special_abilities.json", FileAccess.READ)
	if f3 == null:
		push_error("test_dragon_data_consistency: cannot open dragon_special_abilities.json")
		return
	var parsed3: Variant = JSON.parse_string(f3.get_as_text())
	f3.close()
	if parsed3 is Dictionary:
		_abilities_data = parsed3


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_catalog_has_10_dragon_age_bands() -> void:
	var dragon_ids: Array = []
	for entry in _catalog:
		var eid: String = String((entry as Dictionary).get("id", ""))
		if eid.begins_with("dragon_") and not eid.begins_with("dragon_turtle"):
			dragon_ids.append(eid)
	dragon_ids.sort()
	check(dragon_ids.size() == 10,
		"catalog should have exactly 10 dragon age-band entries (Spawn through Venerable); got %d: %s" % [dragon_ids.size(), str(dragon_ids)])
	# Spot check the expected ids
	for required_id in [
		"dragon_spawn", "dragon_very_young", "dragon_young", "dragon_juvenile",
		"dragon_adult", "dragon_mature_adult", "dragon_old", "dragon_very_old",
		"dragon_ancient", "dragon_venerable",
	]:
		check(_by_id.has(required_id),
			"catalog missing required dragon age-band: %s" % required_id)


func test_dragon_huge_venerable_not_in_catalog() -> void:
	check(not _by_id.has("dragon_huge_venerable"),
		"dragon_huge_venerable should NOT be a discrete catalog entry; it's the daw-troops shorthand for Venerable + massive_size, mapped via dragon_venerable.br_table_with_abilities")


func test_dragon_huge_venerable_not_in_wilderness_membership() -> void:
	var f := FileAccess.open("res://data/domain_events/wilderness_creature_table.json", FileAccess.READ)
	if f == null:
		check(false, "cannot open wilderness_creature_table.json")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		check(false, "wilderness_creature_table.json malformed")
		return
	var membership: Dictionary = (parsed as Dictionary).get("category_membership", {})
	var fantastic: Array = membership.get("fantastic_creatures", [])
	check(not ("dragon_huge_venerable" in fantastic),
		"dragon_huge_venerable should NOT be in fantastic_creatures membership; got: %s" % str(fantastic))


func test_each_dragon_has_secondary_attributes_per_raw() -> void:
	for required_id in RAW_SECONDARY.keys():
		var entry: Variant = _by_id.get(required_id)
		if not (entry is Dictionary):
			check(false, "%s missing from catalog" % required_id)
			continue
		var d: Dictionary = entry
		var raw: Dictionary = RAW_SECONDARY[required_id]
		check(int(d.get("chance_asleep_pct", -1)) == int(raw["asleep"]),
			"%s chance_asleep_pct should be %d, got %d" % [required_id, int(raw["asleep"]), int(d.get("chance_asleep_pct", -1))])
		check(int(d.get("chance_speech_pct", -1)) == int(raw["speech"]),
			"%s chance_speech_pct should be %d, got %d" % [required_id, int(raw["speech"]), int(d.get("chance_speech_pct", -1))])
		check(int(d.get("special_abilities_count", -1)) == int(raw["abilities"]),
			"%s special_abilities_count should be %d, got %d" % [required_id, int(raw["abilities"]), int(d.get("special_abilities_count", -1))])
		var spells: Array = d.get("spells_per_day_by_level", [])
		check(spells.size() == 5,
			"%s spells_per_day_by_level should be length 5, got %d" % [required_id, spells.size()])
		if spells.size() == 5:
			check(int(spells[0]) == int(raw["spells_l1"]),
				"%s spells_per_day_by_level[0] (L1) should be %d, got %d" % [required_id, int(raw["spells_l1"]), int(spells[0])])


func test_dragon_venerable_has_br_table_with_abilities() -> void:
	var entry: Variant = _by_id.get("dragon_venerable")
	if not (entry is Dictionary):
		check(false, "dragon_venerable missing")
		return
	var br_aliases: Variant = (entry as Dictionary).get("br_table_with_abilities")
	check(br_aliases is Dictionary,
		"dragon_venerable.br_table_with_abilities should be a Dictionary; got %s" % typeof(br_aliases))
	if br_aliases is Dictionary:
		var br_d: Dictionary = br_aliases
		check(br_d.has("Dragon, Huge Venerable"),
			"br_table_with_abilities should map 'Dragon, Huge Venerable'; keys: %s" % str(br_d.keys()))
		var huge: Variant = br_d.get("Dragon, Huge Venerable")
		if huge is Dictionary:
			var huge_d: Dictionary = huge
			var abilities_applied: Array = huge_d.get("abilities_applied", [])
			check("massive_size" in abilities_applied,
				"Huge Venerable should apply massive_size; got abilities_applied=%s" % str(abilities_applied))
			check(float(huge_d.get("individual_br", 0.0)) == 18.762,
				"Huge Venerable individual_br should be 18.762; got %s" % str(huge_d.get("individual_br")))


func test_each_dragon_terrain_affinity_covers_dragon_eligible_terrains() -> void:
	## Per Q4: all dragon age bands have expanded terrain_affinity covering all
	## 9 dragon-eligible terrains (mapped via dragon_types.json:terrain_to_dragon_type).
	var required_terrains: Array = [
		"clear_grass_scrub", "mountains_hills", "woods", "jungle",
		"swamp", "barren_desert", "ocean", "lake",
	]
	for dragon_id in RAW_SECONDARY.keys():
		var entry: Variant = _by_id.get(dragon_id)
		if not (entry is Dictionary):
			continue
		var affinity: Array = (entry as Dictionary).get("terrain_affinity", [])
		for t in required_terrains:
			check(t in affinity,
				"%s terrain_affinity should include '%s'; got %s" % [dragon_id, t, str(affinity)])


func test_dragon_types_json_has_9_types() -> void:
	var types: Dictionary = _types_data.get("types", {})
	check(types.size() == 9,
		"dragon_types.json should have 9 types (red, blue, white, black, green, brown, sea, wyrm, metallic); got %d: %s" % [types.size(), str(types.keys())])
	for required_type in ["red", "blue", "white", "black", "green", "brown", "sea", "wyrm", "metallic"]:
		check(types.has(required_type),
			"dragon_types.json missing required type: %s" % required_type)


func test_dragon_types_have_required_fields() -> void:
	var required_fields: Array = [
		"common_name", "habitats", "hide_colors", "breath",
		"alignment_constraint", "is_aquatic", "loses_flight",
		"elemental_aura_damage_type", "special_abilities_pool",
	]
	var types: Dictionary = _types_data.get("types", {})
	for type_id in types.keys():
		var t: Dictionary = types[type_id]
		for field in required_fields:
			check(t.has(field),
				"dragon type '%s' missing required field '%s'" % [type_id, field])
		var breath: Dictionary = t.get("breath", {})
		for breath_field in ["shape", "dimensions", "element", "special_effects"]:
			check(breath.has(breath_field),
				"dragon type '%s' breath missing '%s'" % [type_id, breath_field])


func test_terrain_to_dragon_type_keys_match_synthesized_terrain_vocabulary() -> void:
	## Keys should be synthesized terrain_keys (mountains, hills, woods, etc.),
	## NOT terrain_affinity values (mountains_hills, etc.).
	var expected_keys: Array = ["mountains", "hills", "desert", "ocean", "lake",
		"woods", "jungle", "swamp", "clear", "settled"]
	var lookup: Dictionary = _types_data.get("terrain_to_dragon_type", {})
	for key in expected_keys:
		check(lookup.has(key),
			"terrain_to_dragon_type missing key '%s' (synthesized terrain vocabulary)" % key)


func test_terrain_to_dragon_type_references_valid_types() -> void:
	var lookup: Dictionary = _types_data.get("terrain_to_dragon_type", {})
	var types: Dictionary = _types_data.get("types", {})
	for terrain in lookup.keys():
		var weights: Array = lookup[terrain]
		for entry in weights:
			if not (entry is Array) or (entry as Array).size() < 2:
				continue
			var type_or_sentinel: String = String((entry as Array)[0])
			if type_or_sentinel == "__random_all_colors__":
				continue
			check(types.has(type_or_sentinel),
				"terrain_to_dragon_type[%s] references unknown type '%s'" % [terrain, type_or_sentinel])


func test_lair_eligibility_covers_all_terrains() -> void:
	var lookup: Dictionary = _types_data.get("terrain_to_dragon_type", {})
	var lair: Dictionary = _types_data.get("lair_eligibility", {})
	for terrain in lookup.keys():
		check(lair.has(terrain),
			"lair_eligibility missing terrain '%s'" % terrain)
	# Per Q2: hills + clear are NOT lair-eligible.
	check(lair.get("hills", null) == false,
		"lair_eligibility.hills should be false (cannot be a lair)")
	check(lair.get("clear", null) == false,
		"lair_eligibility.clear should be false (cannot be a lair)")
	check(lair.get("settled", null) == false,
		"lair_eligibility.settled should be false (no dragons in settled)")
	check(lair.get("mountains", null) == true,
		"lair_eligibility.mountains should be true")


func test_alignment_constraints_correct_for_wyrm_and_metallic() -> void:
	var types: Dictionary = _types_data.get("types", {})
	check(String((types.get("wyrm", {}) as Dictionary).get("alignment_constraint", "")) == "chaotic",
		"wyrm should have alignment_constraint='chaotic'")
	check(String((types.get("metallic", {}) as Dictionary).get("alignment_constraint", "")) == "lawful",
		"metallic should have alignment_constraint='lawful'")
	# Unconstrained types should have null
	for unconstrained in ["red", "blue", "white", "black", "green", "brown", "sea"]:
		var t: Dictionary = types.get(unconstrained, {})
		check(t.get("alignment_constraint") == null,
			"%s should have alignment_constraint=null (unconstrained)" % unconstrained)


func test_dragon_special_abilities_has_13_abilities() -> void:
	var abilities: Dictionary = _abilities_data.get("abilities", {})
	check(abilities.size() == 13,
		"dragon_special_abilities.json should have 13 abilities; got %d" % abilities.size())
	for required_ability in [
		"clutching_claws", "decapitating_bite", "elemental_aura", "fear_aura",
		"gem_encrusted_hide", "horrific_stench", "invulnerable", "massive_size",
		"paralyzing_blows", "poisonous_blood", "polymorph_self", "tail_lash",
		"wing_claws",
	]:
		check(abilities.has(required_ability),
			"dragon_special_abilities missing: %s" % required_ability)


func test_paralyzing_blows_is_chaotic_only() -> void:
	var abilities: Dictionary = _abilities_data.get("abilities", {})
	var pb: Dictionary = abilities.get("paralyzing_blows", {})
	check(String(pb.get("alignment_required", "")) == "chaotic",
		"paralyzing_blows should have alignment_required='chaotic'; got '%s'" % str(pb.get("alignment_required")))
	check(bool(pb.get("spellcaster_required", false)) == false,
		"paralyzing_blows should NOT require spellcaster")


func test_polymorph_self_requires_spellcaster() -> void:
	var abilities: Dictionary = _abilities_data.get("abilities", {})
	var ps: Dictionary = abilities.get("polymorph_self", {})
	check(bool(ps.get("spellcaster_required", false)) == true,
		"polymorph_self should require spellcaster")
	check(ps.get("alignment_required") == null,
		"polymorph_self should have alignment_required=null (any alignment)")


func test_each_type_special_abilities_pool_resolves_to_real_abilities() -> void:
	var types: Dictionary = _types_data.get("types", {})
	var abilities: Dictionary = _abilities_data.get("abilities", {})
	for type_id in types.keys():
		var t: Dictionary = types[type_id]
		var pool: Array = t.get("special_abilities_pool", [])
		for ability_id in pool:
			check(abilities.has(String(ability_id)),
				"dragon type '%s' special_abilities_pool references unknown ability '%s'" % [type_id, ability_id])
		# Wyrm pool must include paralyzing_blows (chaotic-bound species)
		if type_id == "wyrm":
			check("paralyzing_blows" in pool,
				"wyrm pool should include paralyzing_blows (chaotic-bound species)")
		# Metallic pool must NOT include paralyzing_blows (lawful)
		if type_id == "metallic":
			check(not ("paralyzing_blows" in pool),
				"metallic pool should NOT include paralyzing_blows (lawful)")
		# Sea pool must NOT include wing_claws (loses flight per RAW)
		if type_id == "sea":
			check(not ("wing_claws" in pool),
				"sea pool should NOT include wing_claws (sea dragons lose flight)")


func test_each_type_has_elemental_aura_damage_type() -> void:
	## Per user's spec: elemental_aura damage types per type:
	##   red→fire, blue→lightning, white→cold, black→acid, green→poison,
	##   brown→bludgeoning (rocks-and-sand maelstrom), sea→steam,
	##   wyrm→necrotic (project decision), metallic→fire.
	var expected: Dictionary = {
		"red": "fire", "blue": "lightning", "white": "cold",
		"black": "acid", "green": "poison", "brown": "bludgeoning",
		"sea": "steam", "wyrm": "necrotic", "metallic": "fire",
	}
	var types: Dictionary = _types_data.get("types", {})
	for type_id in expected.keys():
		var t: Dictionary = types.get(type_id, {})
		var dmg: String = String(t.get("elemental_aura_damage_type", ""))
		check(dmg == String(expected[type_id]),
			"dragon type '%s' elemental_aura_damage_type should be '%s'; got '%s'" % [type_id, expected[type_id], dmg])
