extends "res://tests/test_suite_base.gd"

## Monster-catalog footprint data integrity (creature-size build session).
##
## Pins the invariants for the size/footprint data written from
## docs/monster_size_audit.xlsx: every wired footprint is one of the six legal
## ACKS shapes, agrees with its size_category (+ orientation), and the entries the
## session deliberately FLAGGED (elementals, swarms, un-audited herd animals,
## dragon_turtle) were left un-wired. Mirrors the §42 catalog-consistency pattern.

const CATALOG_PATH := "res://data/monsters/monster_catalog.json"

var _catalog: Array = []


func run_all_tests() -> void:
	_load_catalog()
	if _catalog.is_empty():
		check(false, "monster_catalog.json failed to load or is empty")
		return
	test_footprints_are_legal_shapes()
	test_footprint_matches_size_category()
	test_footprinted_size_is_valid_acks_category()
	test_enough_entries_wired()
	test_flagged_families_have_no_footprint()
	test_combatant_reads_footprint()
	test_elemental_sizes_from_raw()
	test_herd_species_footprints_and_stats()
	test_domestic_livestock_footprints()
	test_no_dangling_herd_placeholders()
	test_terrain_columns_resolve_to_real_ids()
	test_named_herd_species_reachable_per_terrain()
	if not has_failures():
		print("MonsterFootprintData: all tests passed.")


func _load_catalog() -> void:
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		_catalog = parsed


func _footprinted() -> Array:
	var out: Array = []
	for m in _catalog:
		if m is Dictionary and m.has("footprint"):
			out.append(m)
	return out


const LEGAL := [
	Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2),
	Vector2i(2, 2), Vector2i(3, 4), Vector2i(6, 9),
	# Radial elemental footprints — decoupled from the size-category scale
	# (Jedidiah 2026-07-20; a whirlwind's / water-wave's floor print ≠ its size tier).
	Vector2i(3, 3), Vector2i(5, 5), Vector2i(7, 7),
	# Gigantic "long" orientation — 4x3 (hydra, remorhaz; Jedidiah 2026-07-22).
	Vector2i(4, 3),
	# Elongated thin-body footprints — decoupled, unique per creature
	# (Jedidiah 2026-07-24): caecilian 6x1 (30' worm), purple worm 11x5.
	Vector2i(6, 1), Vector2i(11, 5),
]


func test_footprints_are_legal_shapes() -> void:
	for m in _footprinted():
		var fp: Dictionary = m["footprint"]
		var cl: Array = fp.get("cells_local", [])
		check(cl.size() == 2, "%s: cells_local has two entries" % m["id"])
		if cl.size() == 2:
			var v := Vector2i(int(cl[0]), int(cl[1]))
			check(v in LEGAL, "%s: footprint %s is a legal ACKS shape" % [m["id"], str(v)])


func test_footprint_matches_size_category() -> void:
	for m in _footprinted():
		var fp: Dictionary = m["footprint"]
		var size: String = str(fp.get("size_category", ""))
		# The footprint block's size_category mirrors the entry's.
		check(size == str(m.get("size_category", "")),
			"%s: footprint.size_category matches entry size_category" % m["id"])
		# Decoupled footprints (elementals: radial / tall-thin bodies whose floor
		# print intentionally differs from the size-category scale) are exempt from
		# the shape-match check — their cells_local is authored, not derived.
		if bool(fp.get("size_decoupled", false)):
			continue
		# And the cells match CreatureSize's table for that category/orientation.
		var orientation: String = str(fp.get("orientation", ""))
		var expected := CreatureSize.footprint_local(size, orientation)
		var cl: Array = fp.get("cells_local", [])
		if cl.size() == 2:
			var v := Vector2i(int(cl[0]), int(cl[1]))
			check(v == expected,
				"%s: cells_local %s == CreatureSize table %s (%s/%s)"
					% [m["id"], str(v), str(expected), size, orientation])


func test_footprinted_size_is_valid_acks_category() -> void:
	for m in _footprinted():
		var size: String = str(m.get("size_category", ""))
		check(CreatureSize.is_valid_category(size),
			"%s: size_category '%s' is one of the six ACKS categories" % [m["id"], size])


func test_enough_entries_wired() -> void:
	# The confident data pass wired ~155 entries; guard against a silent data loss.
	check(_footprinted().size() >= 150,
		"at least 150 catalog entries carry a footprint (got %d)" % _footprinted().size())


func test_flagged_families_have_no_footprint() -> void:
	# Entries the session deliberately deferred must NOT have been given a footprint.
	# (Elementals were flagged initially but are now fully wired — 2026-07-20 —
	# so they are no longer in this list.)
	# All swarm flavours use a `swarm_area` block (diffuse enveloping area), NOT
	# a solid `footprint` — they move as a 1x1 anchor (coding_conventions §126).
	var flagged_prefixes := ["insect_swarm", "bat_swarm", "rat_swarm"]
	# (dragon_turtle wired 2026-07-22; purple_worm wired 2026-07-24;
	#  herd/domestic group wired 2026-07-24 — herd_animal_* species + cow/ox/
	#  sheep/goat/donkey now carry footprints, so they are no longer here.)
	var flagged_ids := []
	for m in _catalog:
		if not (m is Dictionary):
			continue
		var mid: String = str(m.get("id", ""))
		var is_flagged := mid in flagged_ids
		for pre in flagged_prefixes:
			if mid.begins_with(pre):
				is_flagged = true
		if is_flagged:
			check(not m.has("footprint"),
				"flagged entry '%s' was correctly left without a footprint" % mid)


func test_elemental_sizes_from_raw() -> void:
	# Elemental size_category derived from le_monster_catalog_6.xml *_form_dimensions
	# (dimension per Hit Die) → le_monster_creation.xml size brackets (boundary
	# convention 12'→huge, 32'→colossal). Footprints are AUTHORED per Jedidiah
	# (2026-07-20), decoupled from the size category (radial / tall-thin bodies).
	var expected_size := {
		"elemental_air_8hd": "huge", "elemental_air_12hd": "gigantic", "elemental_air_16hd": "colossal",
		"elemental_earth_8hd": "large", "elemental_earth_12hd": "huge", "elemental_earth_16hd": "huge",
		"elemental_fire_8hd": "large", "elemental_fire_12hd": "huge", "elemental_fire_16hd": "huge",
		"elemental_water_8hd": "huge", "elemental_water_12hd": "gigantic", "elemental_water_16hd": "colossal",
	}
	var expected_fp := {
		"elemental_air_8hd": Vector2i(1, 1), "elemental_air_12hd": Vector2i(1, 1), "elemental_air_16hd": Vector2i(2, 2),
		"elemental_earth_8hd": Vector2i(1, 1), "elemental_earth_12hd": Vector2i(1, 2), "elemental_earth_16hd": Vector2i(2, 2),
		"elemental_fire_8hd": Vector2i(2, 2), "elemental_fire_12hd": Vector2i(3, 3), "elemental_fire_16hd": Vector2i(3, 3),
		"elemental_water_8hd": Vector2i(3, 3), "elemental_water_12hd": Vector2i(5, 5), "elemental_water_16hd": Vector2i(7, 7),
	}
	var by_id: Dictionary = {}
	for m in _catalog:
		if m is Dictionary:
			by_id[str(m.get("id", ""))] = m
	for eid in expected_size:
		var m = by_id.get(eid)
		check(m != null, "elemental %s present in catalog" % eid)
		if m == null:
			continue
		check(str(m.get("size_category", "")) == expected_size[eid],
			"%s size_category == %s (got %s)" % [eid, expected_size[eid], str(m.get("size_category", ""))])
		check(m.has("footprint"), "%s has a wired footprint" % eid)
		var fp: Dictionary = m.get("footprint", {})
		var cl: Array = fp.get("cells_local", [])
		var got := Vector2i(int(cl[0]), int(cl[1])) if cl.size() == 2 else Vector2i(-1, -1)
		check(got == expected_fp[eid],
			"%s footprint %s == expected %s" % [eid, str(got), str(expected_fp[eid])])
		check(bool(fp.get("size_decoupled", false)),
			"%s footprint flagged size_decoupled (floor print != size tier)" % eid)


func test_combatant_reads_footprint() -> void:
	# End-to-end: a spawned monster surfaces its footprint through Combatant.
	var registry := MonsterRegistry.new()
	if registry.has_monster("ogre"):
		var ogre := Combatant.from_monster(registry.get_monster("ogre"), 12, "o1", "ogre")
		check(ogre.get_size_category() == "large", "ogre is large")
		check(ogre.get_footprint_local() == Vector2i(1, 2), "ogre footprint is 1x2 (wide)")
		check(ogre.is_multi_cell(), "ogre is multi-cell")
	if registry.has_monster("goblin"):
		var gob := Combatant.from_monster(registry.get_monster("goblin"), 4, "g1", "goblin")
		check(not gob.is_multi_cell(), "goblin is single-cell")
		check(gob.get_footprint_local() == Vector2i(1, 1), "goblin footprint is 1x1")


# The nine real terrain-specific herd-animal species that replaced the four
# `herd_animal_<hd>` placeholders (2026-07-24). RAW: acore_monster_catalog
# `typical_species` table + acore-monster-stocking-rules encounter tables.
# Every species is Man-sized (1 HD) or Large (2-4 HD) — RAW caps all herd
# animals at Large (heaviest tier 1,400 lb < 2,000 lb Large ceiling in
# le_monster_creation.xml size_category_table), so none reach Huge.
const HERD_SPECIES := [
	"herd_animal_antelope", "herd_animal_deer", "herd_animal_wild_goat",
	"herd_animal_wild_sheep", "herd_animal_caribou", "herd_animal_aurochs",
	"herd_animal_bison", "herd_animal_elk", "herd_animal_moose",
]
const HERD_PLACEHOLDERS := [
	"herd_animal_1hd", "herd_animal_2hd", "herd_animal_3hd", "herd_animal_4hd",
]


func _by_id() -> Dictionary:
	var out: Dictionary = {}
	for m in _catalog:
		if m is Dictionary:
			out[str(m.get("id", ""))] = m
	return out


func test_herd_species_footprints_and_stats() -> void:
	# Each new herd species carries a legal footprint that agrees with a valid
	# ACKS size category, and its size is one of the two RAW-legal herd tiers.
	var by_id := _by_id()
	for sid in HERD_SPECIES:
		var m = by_id.get(sid)
		check(m != null, "herd species '%s' present in catalog" % sid)
		if m == null:
			continue
		var size: String = str(m.get("size_category", ""))
		check(CreatureSize.is_valid_category(size),
			"%s size_category '%s' is a valid ACKS category" % [sid, size])
		check(size in ["man_sized", "large"],
			"%s size is Man-sized or Large (RAW caps herd animals at Large); got '%s'" % [sid, size])
		check(m.has("footprint"), "%s carries a footprint block" % sid)
		var fp: Dictionary = m.get("footprint", {})
		var cl: Array = fp.get("cells_local", [])
		check(cl.size() == 2, "%s footprint cells_local has two entries" % sid)
		if cl.size() == 2:
			var v := Vector2i(int(cl[0]), int(cl[1]))
			check(v in LEGAL, "%s footprint %s is a legal ACKS shape" % [sid, str(v)])
			var expected := CreatureSize.footprint_local(size, str(fp.get("orientation", "")))
			check(v == expected,
				"%s cells_local %s == CreatureSize table %s" % [sid, str(v), str(expected)])
		# The old placeholder bloc spanned 1-4 HD; the replacements must too, so
		# the wilderness herd is not silently narrowed to one power tier.
		check(m.has("domain_encounter") and m["domain_encounter"] != null,
			"%s has a domain_encounter block (BR-eligible)" % sid)


func test_domestic_livestock_footprints() -> void:
	# The concrete domestic animals in the same flag group now carry footprints.
	var by_id := _by_id()
	var expected := {
		"cow": Vector2i(2, 1), "ox": Vector2i(2, 1),
		"sheep": Vector2i(1, 1), "goat": Vector2i(1, 1), "donkey": Vector2i(1, 1),
	}
	for did in expected:
		var m = by_id.get(did)
		check(m != null, "domestic '%s' present in catalog" % did)
		if m == null:
			continue
		check(m.has("footprint"), "%s carries a footprint block" % did)
		var cl: Array = m.get("footprint", {}).get("cells_local", [])
		if cl.size() == 2:
			check(Vector2i(int(cl[0]), int(cl[1])) == expected[did],
				"%s footprint == %s" % [did, str(expected[did])])


func test_no_dangling_herd_placeholders() -> void:
	# The four `herd_animal_<hd>` placeholders must be fully removed.
	var by_id := _by_id()
	for pid in HERD_PLACEHOLDERS:
		check(not by_id.has(pid),
			"placeholder '%s' was removed from the catalog" % pid)


func test_terrain_columns_resolve_to_real_ids() -> void:
	# Every terrain column the wilderness resolver can roll must resolve, via
	# terrain_affinity, only to ids that exist in the catalog — no dangling
	# `herd_animal_<hd>` (or any other stale) reference survives.
	var registry := MonsterRegistry.new()
	var by_id := _by_id()
	for column in EncounterTerrainResolver.CREATURE_TYPE_TABLE.keys():
		var pool: Array = registry.get_monsters_for_terrain(column)
		for mid in pool:
			check(by_id.has(mid),
				"terrain column '%s' id '%s' resolves to a real catalog entry" % [column, mid])
			check(not (mid in HERD_PLACEHOLDERS),
				"terrain column '%s' has no dangling placeholder '%s'" % [column, mid])


func test_named_herd_species_reachable_per_terrain() -> void:
	# The RAW-named herd species surface in exactly the terrain columns the
	# acore-monster-stocking-rules encounter tables place them in, and each
	# matches the resolver's "Animal" creature-type filter.
	var registry := MonsterRegistry.new()
	var expected := {
		"herd_animal_antelope": ["clear_grass_scrub", "woods", "river", "mountains_hills", "barren_desert", "jungle"],
		"herd_animal_wild_goat": ["mountains_hills", "barren_desert", "inhabited"],
		"herd_animal_wild_sheep": ["mountains_hills", "inhabited"],
	}
	for sid in expected:
		var m: Dictionary = registry.get_monster(sid)
		check(not m.is_empty(), "named herd species '%s' loads from registry" % sid)
		check(EncounterTerrainResolver.monster_matches_creature_type(m, "Animal"),
			"%s matches the resolver's Animal creature-type filter" % sid)
		for column in expected[sid]:
			var pool: Array = registry.get_monsters_for_terrain(column)
			check(sid in pool,
				"%s is reachable in terrain column '%s'" % [sid, column])
