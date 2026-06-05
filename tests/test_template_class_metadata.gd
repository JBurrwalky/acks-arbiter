extends "res://tests/test_suite_base.gd"

## Tests for TemplateClassMetadata — the class-specific selections a template locks
## onto the character record at selection (gdd-class-templates.md §4.4, §9.1; §10
## step 9). Verifies: every witch template derives witch_tradition (lowercased,
## all 4 traditions covered); every barbarian template derives the correct
## regional_origin via the natural-prof reverse map; every shaman template derives
## the totem species + placeholder flag; classes that lock nothing derive {}; and
## the locked metadata actually lands on (and round-trips through) the CharacterData
## the NPC builder produces, plus is surfaced by the PC creation flow.

var _repo: ClassTemplateRepository
var _class_registry: ClassRegistry
var _builder: ClassedNpcBuilder
var _pc_flow: PcTemplateCreationFlow


func run_all_tests() -> void:
	_repo = ClassTemplateRepository.new()
	_class_registry = ClassRegistry.new()
	_builder = ClassedNpcBuilder.new()
	_pc_flow = PcTemplateCreationFlow.new()
	test_witch_tradition_locked()
	test_barbarian_region_reverse_map()
	test_barbarian_region_locked()
	test_shaman_totem_locked()
	test_neutral_classes_lock_nothing()
	test_builder_stamps_and_round_trips()
	test_pc_flow_surfaces_locked_metadata()
	if not has_failures():
		print("TemplateClassMetadata: all tests passed.")


func test_witch_tradition_locked() -> void:
	# All 8 witch templates carry a tradition; it must lock as a lowercased
	# witch_tradition. The 4 distinct traditions must all appear.
	var seen := {}
	for t: ClassTemplate in _repo.get_templates_for_class("witch"):
		var added := TemplateClassMetadata.derive(t, _class_registry)
		check(added.has("witch_tradition"),
			"%s should lock a witch_tradition" % t.template_id)
		var trad := String(added.get("witch_tradition", ""))
		check(trad == trad.to_lower() and trad != "",
			"%s witch_tradition '%s' must be non-empty lowercase" % [t.template_id, trad])
		check(trad == t.tradition.to_lower(),
			"%s witch_tradition '%s' must match template.tradition '%s' lowered" % [
				t.template_id, trad, t.tradition])
		seen[trad] = true
	for expected in ["antiquarian", "chthonic", "voudon", "sylvan"]:
		check(seen.has(expected), "witch traditions should include '%s'" % expected)


func test_barbarian_region_reverse_map() -> void:
	# The reverse map reads barbarian.json regional_origins (data-driven, no IP
	# hard-coding): climbing -> jutland, precise_shooting -> skysostan,
	# running -> ivory_kingdoms.
	var cases := {
		"climbing": "jutland",
		"precise_shooting": "skysostan",
		"running": "ivory_kingdoms",
	}
	for prof in cases:
		check(TemplateClassMetadata.barbarian_region_for_natural_prof(prof, _class_registry)
				== cases[prof],
			"barbarian natural '%s' should map to region '%s'" % [prof, cases[prof]])
	check(TemplateClassMetadata.barbarian_region_for_natural_prof("", _class_registry) == "",
		"empty prof maps to no region")
	check(TemplateClassMetadata.barbarian_region_for_natural_prof("swimming", _class_registry) == "",
		"a non-regional prof maps to no region")


func test_barbarian_region_locked() -> void:
	# Every barbarian template's natural prof must resolve to a valid region key.
	var valid := ["jutland", "skysostan", "ivory_kingdoms"]
	for t: ClassTemplate in _repo.get_templates_for_class("barbarian"):
		var added := TemplateClassMetadata.derive(t, _class_registry)
		check(added.has("regional_origin"),
			"%s should lock a regional_origin" % t.template_id)
		check(String(added.get("regional_origin", "")) in valid,
			"%s regional_origin '%s' not a valid region" % [
				t.template_id, String(added.get("regional_origin", ""))])


func test_shaman_totem_locked() -> void:
	# Every shaman template carries a totem companion; it must lock the species and
	# preserve the v1 placeholder flag (gdd §9.1 — totem subsystem deferred).
	var count := 0
	for t: ClassTemplate in _repo.get_templates_for_class("shaman"):
		var added := TemplateClassMetadata.derive(t, _class_registry)
		check(added.has("shaman_totem"), "%s should lock a shaman_totem" % t.template_id)
		check(String(added.get("shaman_totem", "")) != "",
			"%s shaman_totem species must be non-empty" % t.template_id)
		check(String(added.get(TemplateClassMetadata.TOTEM_PLACEHOLDER_FLAG, "")) == "1",
			"%s should preserve the totem placeholder flag" % t.template_id)
		count += 1
	check(count == 8, "expected 8 shaman templates, got %d" % count)


func test_neutral_classes_lock_nothing() -> void:
	# Classes with no class_metadata sub-selection derive an empty dict — including
	# classes that HAVE a natural prof (bard / dwarven_craftpriest) but no region.
	for cid in ["fighter", "cleric", "mage", "thief", "bard", "dwarven_craftpriest"]:
		for t: ClassTemplate in _repo.get_templates_for_class(cid):
			var added := TemplateClassMetadata.derive(t, _class_registry)
			check(added.is_empty(),
				"%s should lock no class_metadata, got %s" % [t.template_id, str(added)])


func test_builder_stamps_and_round_trips() -> void:
	# The NPC builder must stamp the locked selection onto the CharacterData, expose
	# it in the bundle, and it must survive a to_dict() / from_dict() round trip
	# (so it persists to the characters.class_metadata column).
	var b := _builder.build_classed_npc("barbarian", {"forced_roll": 5, "force_int": 12})
	check(bool(b["ok"]), "barbarian@5 build failed: %s" % String(b.get("error", "")))
	var locked: Dictionary = b["class_metadata_locked"]
	check(locked.has("regional_origin"), "bundle should expose the locked regional_origin")
	var character: CharacterData = b["character"]
	var region := character.get_class_metadata_value("regional_origin")
	check(region == String(locked["regional_origin"]),
		"character class_metadata region '%s' should match bundle '%s'" % [
			region, String(locked["regional_origin"])])
	# Round-trip through the DB-shaped dict.
	var restored := CharacterData.from_dict(character.to_dict())
	check(restored.get_class_metadata_value("regional_origin") == region,
		"regional_origin must survive to_dict/from_dict")

	# Witch build stamps witch_tradition.
	var w := _builder.build_classed_npc("witch", {"forced_roll": 9, "force_int": 12})
	check(bool(w["ok"]), "witch@9 build failed")
	var wc: CharacterData = w["character"]
	check(wc.get_class_metadata_value("witch_tradition") == "sylvan",
		"witch@9 (Sylvan) should lock witch_tradition=sylvan, got '%s'" % wc.get_class_metadata_value("witch_tradition"))

	# A neutral class leaves class_metadata empty (still default "{}").
	var f := _builder.build_classed_npc("fighter", {"forced_roll": 10, "force_int": 12})
	check((f["class_metadata_locked"] as Dictionary).is_empty(),
		"fighter should lock nothing")


func test_pc_flow_surfaces_locked_metadata() -> void:
	# Path B selection surfaces class_metadata_locked so the creation wizard can
	# stamp it (witch_9_10 = Sylvan).
	var res := _pc_flow.choose_path_b("witch", "witch_9_10", 12)
	check(bool(res["ok"]), "witch path B failed: %s" % String(res.get("error", "")))
	var locked: Dictionary = res["class_metadata_locked"]
	check(String(locked.get("witch_tradition", "")) == "sylvan",
		"PC flow should surface witch_tradition=sylvan, got '%s'" % String(locked.get("witch_tradition", "")))
