extends "res://tests/test_suite_base.gd"

## Cross-file consistency tests for the monster_catalog refactor (Phase 9A
## polish 2026-05-XX). Verifies:
##   - Every catalog entry has the required schema fields.
##   - Every id in wilderness_creature_table.json:category_membership exists
##     in monster_catalog.json AND has a non-empty domain_encounter block.
##   - Every entry's domain_encounter.category matches the bucket it appears in.
##   - Spot-check 5 high-profile creatures (goblin, wolf, wyvern, ogre,
##     dragon_adult) for completeness.
##   - DomainEncounterResolver.validate_consistency() returns ok=true.

const REQUIRED_FIELDS: Array[String] = [
	"id", "name", "monster_types", "hit_dice", "armor_class",
	"attack_routines", "save_as", "morale", "xp", "movement",
	"terrain_affinity", "special_abilities", "immunities",
	"resistances", "vulnerabilities", "combat_behavior"
]

const HIGH_PROFILE_IDS: Array[String] = [
	"goblin", "wolf", "wyvern", "ogre", "dragon_adult"
]

var _catalog: Array = []
var _by_id: Dictionary = {}
var _membership: Dictionary = {}
var _categories: Dictionary = {}


func run_all_tests() -> void:
	_load_data()
	test_catalog_loads_with_min_entry_count()
	test_every_entry_has_required_fields()
	test_every_membership_id_is_in_catalog()
	test_every_membership_id_has_domain_encounter_block()
	test_membership_id_category_matches_bucket()
	test_categories_cover_all_d8_columns()
	test_high_profile_spot_check()
	test_resolver_validate_consistency_returns_ok()
	test_resolver_generates_encounter_against_unified_catalog()
	if not has_failures():
		print("MonsterCatalogConsistency: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _load_data() -> void:
	var f := FileAccess.open("res://data/monsters/monster_catalog.json", FileAccess.READ)
	if f == null:
		push_error("test_monster_catalog_consistency: cannot open monster_catalog.json")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		_catalog = parsed
	for entry in _catalog:
		if entry is Dictionary:
			_by_id[str(entry.get("id", ""))] = entry
	var f2 := FileAccess.open("res://data/domain_events/wilderness_creature_table.json", FileAccess.READ)
	if f2 == null:
		push_error("test_monster_catalog_consistency: cannot open wilderness_creature_table.json")
		return
	var parsed2: Variant = JSON.parse_string(f2.get_as_text())
	f2.close()
	if parsed2 is Dictionary:
		_membership = (parsed2 as Dictionary).get("category_membership", {})
		_categories = (parsed2 as Dictionary).get("categories", {})


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_catalog_loads_with_min_entry_count() -> void:
	check(_catalog.size() >= 100,
		"catalog should have at least 100 entries; actual = %d" % _catalog.size())


func test_every_entry_has_required_fields() -> void:
	var missing_count: int = 0
	var first_missing: String = ""
	for entry in _catalog:
		if not (entry is Dictionary):
			missing_count += 1
			continue
		var d: Dictionary = entry
		var eid: String = str(d.get("id", "?"))
		for field in REQUIRED_FIELDS:
			if not d.has(field):
				missing_count += 1
				if first_missing.is_empty():
					first_missing = "%s missing '%s'" % [eid, field]
				break
	check(missing_count == 0,
		"every catalog entry has required fields; %d missing; first: %s" % [missing_count, first_missing])


func test_every_membership_id_is_in_catalog() -> void:
	var missing: Array = []
	for cat in _membership.keys():
		var ids: Array = _membership[cat]
		for id_v in ids:
			var creature_id: String = String(id_v)
			if not _by_id.has(creature_id):
				missing.append("%s.%s" % [cat, creature_id])
	check(missing.is_empty(),
		"every category_membership id resolves to a catalog entry; %d missing: %s" % [missing.size(), str(missing)])


func test_every_membership_id_has_domain_encounter_block() -> void:
	var missing: Array = []
	for cat in _membership.keys():
		var ids: Array = _membership[cat]
		for id_v in ids:
			var creature_id: String = String(id_v)
			var entry: Variant = _by_id.get(creature_id)
			if not (entry is Dictionary):
				continue
			var de: Variant = (entry as Dictionary).get("domain_encounter")
			if de == null or not (de is Dictionary) or (de as Dictionary).is_empty():
				missing.append("%s.%s" % [cat, creature_id])
	check(missing.is_empty(),
		"every category_membership id has a non-empty domain_encounter block; %d ids without block: %s" % [missing.size(), str(missing)])


func test_membership_id_category_matches_bucket() -> void:
	var mismatched: Array = []
	for cat in _membership.keys():
		var ids: Array = _membership[cat]
		for id_v in ids:
			var creature_id: String = String(id_v)
			var entry: Variant = _by_id.get(creature_id)
			if not (entry is Dictionary):
				continue
			var de: Variant = (entry as Dictionary).get("domain_encounter")
			if not (de is Dictionary):
				continue
			var de_cat: String = String((de as Dictionary).get("category", ""))
			if de_cat != String(cat):
				mismatched.append("%s in membership.%s but de.category=%s" % [creature_id, cat, de_cat])
	check(mismatched.is_empty(),
		"each id's domain_encounter.category matches its membership bucket; %d mismatches: %s" % [mismatched.size(), str(mismatched)])


func test_categories_cover_all_d8_columns() -> void:
	## Per RAW: 1d8 wilderness encounter throw maps to a category. Every
	## column 1..8 must be reachable via at least one category whose
	## membership is non-empty (otherwise that 1d8 roll is dead weight).
	var d8_seen: Dictionary = {}
	for cat_name in _categories.keys():
		var cat_def: Dictionary = _categories[cat_name]
		var cols: Array = cat_def.get("d8_columns", [])
		var ids: Array = _membership.get(cat_name, [])
		if ids.is_empty():
			continue
		for c in cols:
			d8_seen[int(c)] = true
	for n in [1, 2, 3, 4, 5, 6, 7, 8]:
		check(d8_seen.has(n),
			"d8 column %d is covered by a non-empty category" % n)


func test_high_profile_spot_check() -> void:
	for creature_id in HIGH_PROFILE_IDS:
		check(_by_id.has(creature_id),
			"high-profile id '%s' exists in catalog" % creature_id)
		if not _by_id.has(creature_id):
			continue
		var entry: Dictionary = _by_id[creature_id]
		var hd: Dictionary = entry.get("hit_dice", {})
		check(float(hd.get("base", 0)) > 0.0,
			"'%s' has hit_dice.base > 0; got %s" % [creature_id, str(hd.get("base"))])
		var de: Variant = entry.get("domain_encounter")
		var has_de: bool = de != null and de is Dictionary and not (de as Dictionary).is_empty()
		check(has_de,
			"'%s' has non-empty domain_encounter block" % creature_id)
		if has_de:
			var de_d: Dictionary = de
			check(float(de_d.get("individual_br", 0.0)) > 0.0,
				"'%s' individual_br > 0; got %s" % [creature_id, str(de_d.get("individual_br"))])
			check(int(de_d.get("platoon_size", 0)) >= 1,
				"'%s' platoon_size >= 1; got %s" % [creature_id, str(de_d.get("platoon_size"))])


func test_resolver_validate_consistency_returns_ok() -> void:
	var report: Dictionary = DomainEncounterResolver.validate_consistency()
	var ok: bool = bool(report.get("ok", false))
	var errors: Array = report.get("errors", [])
	check(ok,
		"DomainEncounterResolver.validate_consistency reports ok=true; errors: %s" % str(errors))
	check(int(report.get("total_ids", 0)) >= 50,
		"DomainEncounterResolver.validate_consistency saw at least 50 ids; total_ids = %d" % int(report.get("total_ids", 0)))


func test_resolver_generates_encounter_against_unified_catalog() -> void:
	## Smoke test: the resolver's _generate_encounter must produce a
	## non-empty encounter dict for at least one of 16 d8 attempts.
	var got: int = 0
	for i in range(16):
		var encounter: Dictionary = _invoke_generate_encounter()
		if encounter.is_empty():
			continue
		got += 1
		check(encounter.has("key"),
			"generated encounter has 'key' field; got %s" % str(encounter))
		check(int(encounter.get("count", -1)) >= 0,
			"generated encounter has count >= 0; got %s" % str(encounter.get("count")))
		break
	check(got >= 1,
		"resolver generated at least one encounter in 16 attempts (membership likely broken if 0)")


func _invoke_generate_encounter() -> Dictionary:
	## _generate_encounter is a private static; invoke it via the script reference.
	var script := load("res://engine/subsystems/domains/domain_encounter_resolver.gd")
	if script == null:
		return {}
	var fn := Callable(script, "_generate_encounter")
	if not fn.is_valid():
		return {}
	return fn.call(null)
