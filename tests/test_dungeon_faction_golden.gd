extends "res://tests/test_suite_base.gd"

## Golden test for the §12 worked example of gdd-dungeon-factions.md — the
## Abandoned Dwarven Mine, Level 1 (15 rooms). Verifies faction identification,
## territory assignment, relationships, and byte-identical determinism. NOT run
## by this build session (registered for the central suite).
##
## Deviation note (documented): the GDD's printed territory MAP marks rooms 6 and
## 12 "unclaimed", but its per-faction SUMMARY lists room 6 as the goblin frontier
## and room 12 as the orc-adjacent buffer. Those two statements are internally
## inconsistent. The flood-fill (TerritoryAssigner) is Voronoi-consistent with the
## SUMMARY: room 6 → goblin frontier (claimed via the open 5-6 corridor, bounded
## by the locked 6-7 door), room 12 → unclaimed (across a single-corridor
## chokepoint from every faction). 14/15 rooms match the printed map exactly.

const SEED := 12345
const DUNGEON_ID := "dfx_mine"


func run_all_tests() -> void:
	test_identifies_three_factions()
	test_goblin_faction()
	test_necromancer_cult()
	test_orc_warband()
	test_spider_is_not_a_faction_or_threat()
	test_territory_map()
	test_relationships()
	test_determinism_byte_identical()
	test_names_follow_template()
	if not has_failures():
		print("DungeonFactionGolden: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture — the §12 mine
# ---------------------------------------------------------------------------

func _build_mine() -> DungeonFactionInput:
	var input := DungeonFactionInput.new()
	input.dungeon_id = DUNGEON_ID
	input.default_level = 1
	for i in range(1, 16):
		input.add_room(i, 1)

	# Goblins (rooms 2,4,5) + trained giant rats (room 5).
	input.place(2, "goblin", 4, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "patrol_dice": "1d4"})
	input.place(4, "goblin", 6, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_lair": true, "is_leader": true,
		"leader_hd": 2.0, "leader_title": "Chieftain", "patrol_dice": "1d4"})
	input.place(5, "goblin", 3, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "patrol_dice": "1d4"})
	input.place(5, "giant_rat", 2, {"monster_types": ["vermin"], "intelligence": "animal",
		"alignment": "neutral", "hd": 0.5, "controlled_by_species": "goblin"})

	# Necromancer (room 9) + controlled skeletons (rooms 7,8,9).
	input.place(7, "skeleton", 8, {"monster_types": ["undead"], "intelligence": "non",
		"alignment": "chaotic", "hd": 1.0, "controlled_by_species": "necromancer"})
	input.place(8, "skeleton", 4, {"monster_types": ["undead"], "intelligence": "non",
		"alignment": "chaotic", "hd": 1.0, "controlled_by_species": "necromancer"})
	input.place(9, "necromancer", 1, {"monster_types": ["human"], "intelligence": "high",
		"alignment": "chaotic", "hd": 3.0, "is_lair": true, "is_leader": true,
		"leader_hd": 3.0, "leader_title": "Necromancer", "patrol_dice": "1d4",
		"has_special_abilities": true})
	input.place(9, "skeleton", 2, {"monster_types": ["undead"], "intelligence": "non",
		"alignment": "chaotic", "hd": 1.0, "controlled_by_species": "necromancer"})

	# Giant spider (room 11): animal intelligence, 2 HD, no controller.
	input.place(11, "giant_spider", 1, {"monster_types": ["vermin"], "intelligence": "animal",
		"alignment": "neutral", "hd": 2.0})

	# Orcs (rooms 13,14,15) + sub-chieftain (room 14).
	input.place(13, "orc", 5, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "patrol_dice": "1d6"})
	input.place(14, "orc", 8, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_lair": true, "patrol_dice": "1d6"})
	input.place(14, "orc", 1, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_leader": true, "leader_hd": 2.0,
		"leader_title": "Sub-chieftain", "patrol_dice": "1d6"})
	input.place(15, "orc", 3, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "patrol_dice": "1d6"})

	# Edges. Goblin corridor is open; the 6-7 door is locked (strong boundary);
	# the middle links via single-corridor (narrow) chokepoints.
	input.connect_rooms(1, 2)
	input.connect_rooms(2, 3)
	input.connect_rooms(3, 4)
	input.connect_rooms(4, 5)
	input.connect_rooms(5, 6)
	input.connect_rooms(6, 7, DungeonFactionEdge.KIND_LOCKED)
	input.connect_rooms(7, 8)
	input.connect_rooms(8, 9)
	input.connect_rooms(1, 12, DungeonFactionEdge.KIND_NARROW, 5)
	input.connect_rooms(10, 12, DungeonFactionEdge.KIND_NARROW, 5)
	input.connect_rooms(10, 11, DungeonFactionEdge.KIND_NARROW, 5)
	input.connect_rooms(10, 13)
	input.connect_rooms(13, 14)
	input.connect_rooms(14, 15)
	return input


func _generate() -> DungeonFactionGenerationResult:
	return DungeonFactionGenerator.generate(_build_mine(), SEED)


func _faction_by_species(result: DungeonFactionGenerationResult, species: String) -> DungeonFaction:
	for f in result.factions:
		if f.species == species:
			return f
	return null


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_identifies_three_factions() -> void:
	var result := _generate()
	check(result.factions.size() == 3, "3 factions identified (got %d)" % result.factions.size())
	check(_faction_by_species(result, "goblin") != null, "goblin faction present")
	check(_faction_by_species(result, "necromancer") != null, "necromancer faction present")
	check(_faction_by_species(result, "orc") != null, "orc faction present")


func test_goblin_faction() -> void:
	var f := _faction_by_species(_generate(), "goblin")
	check(f != null, "goblin faction exists")
	if f == null:
		return
	check(f.faction_type == DungeonFaction.TYPE_TRIBAL, "goblins are tribal (got %s)" % f.faction_type)
	check(f.alignment == "chaotic", "goblins chaotic")
	check(f.lair_room_ids == [4], "goblin lair is room 4 (got %s)" % str(f.lair_room_ids))
	check(_same_set(f.core_room_ids, [2, 4, 5]), "goblin core {2,4,5} (got %s)" % str(f.core_room_ids))
	check(_same_set(f.patrol_room_ids, [1, 3]), "goblin patrol {1,3} (got %s)" % str(f.patrol_room_ids))
	check(_same_set(f.frontier_room_ids, [6]), "goblin frontier {6} (got %s)" % str(f.frontier_room_ids))
	check(f.leader_room_id == 4, "goblin leader in room 4")
	check(is_equal_approx(f.leader_hd, 2.0), "goblin chieftain 2 HD")
	check(f.starting_population == 15, "goblin population 15 (13 goblins + 2 rats), got %d" % f.starting_population)
	check(f.current_population == 15, "goblin current pop 15")
	check(f.patrol_size == "1d4", "goblin patrol size 1d4")
	check(f.secondary_species.has("giant_rat"), "goblins keep trained giant rats as secondary species")


func test_necromancer_cult() -> void:
	var f := _faction_by_species(_generate(), "necromancer")
	check(f != null, "necromancer faction exists")
	if f == null:
		return
	check(f.faction_type == DungeonFaction.TYPE_CULT, "necromancer+undead is a cult (got %s)" % f.faction_type)
	check(f.secondary_species.has("skeleton"), "skeletons are a secondary species of the cult")
	check(f.lair_room_ids == [9], "cult lair is room 9")
	check(_same_set(f.core_room_ids, [7, 8, 9]), "cult core {7,8,9} (got %s)" % str(f.core_room_ids))
	check(f.leader_room_id == 9, "necromancer in room 9")
	check(is_equal_approx(f.leader_hd, 3.0), "necromancer 3 HD leader")
	check(f.starting_population == 15, "cult population 15 (1 necromancer + 14 skeletons), got %d" % f.starting_population)
	check(f.alert_state == DungeonFaction.ALERT_UNAWARE, "faction starts unaware")


func test_orc_warband() -> void:
	var f := _faction_by_species(_generate(), "orc")
	check(f != null, "orc faction exists")
	if f == null:
		return
	check(f.faction_type == DungeonFaction.TYPE_MILITARY, "orcs are a military warband (got %s)" % f.faction_type)
	check(f.lair_room_ids == [14], "orc lair room 14")
	check(_same_set(f.core_room_ids, [13, 14, 15]), "orc core {13,14,15} (got %s)" % str(f.core_room_ids))
	check(_same_set(f.patrol_room_ids, [10]), "orc patrol {10} (got %s)" % str(f.patrol_room_ids))
	check(f.leader_room_id == 14, "orc sub-chieftain in room 14")
	check(is_equal_approx(f.leader_hd, 2.0), "orc sub-chieftain 2 HD")
	check(f.starting_population == 17, "orc population 17 (got %d)" % f.starting_population)
	check(f.patrol_size == "1d6", "orc patrol size 1d6")


func test_spider_is_not_a_faction_or_threat() -> void:
	var result := _generate()
	check(_faction_by_species(result, "giant_spider") == null, "spider forms no faction (animal intelligence)")
	check(result.solitary_threats.is_empty(), "spider is not a solitary threat (<4 HD, no special abilities)")
	check(result.territory_map.status_of(11) == DungeonTerritoryEntry.STATUS_UNCLAIMED,
		"room 11 (spider) is unclaimed")


func test_territory_map() -> void:
	var result := _generate()
	var tmap := result.territory_map
	var goblin := _faction_by_species(result, "goblin")
	var cult := _faction_by_species(result, "necromancer")
	var orc := _faction_by_species(result, "orc")

	# Room -> [status, controlling faction (or null)].
	_expect_room(tmap, 1, DungeonTerritoryEntry.STATUS_PATROL, goblin)
	_expect_room(tmap, 2, DungeonTerritoryEntry.STATUS_CORE, goblin)
	_expect_room(tmap, 3, DungeonTerritoryEntry.STATUS_PATROL, goblin)
	_expect_room(tmap, 4, DungeonTerritoryEntry.STATUS_CORE, goblin)
	_expect_room(tmap, 5, DungeonTerritoryEntry.STATUS_CORE, goblin)
	_expect_room(tmap, 6, DungeonTerritoryEntry.STATUS_FRONTIER, goblin)
	_expect_room(tmap, 7, DungeonTerritoryEntry.STATUS_CORE, cult)
	_expect_room(tmap, 8, DungeonTerritoryEntry.STATUS_CORE, cult)
	_expect_room(tmap, 9, DungeonTerritoryEntry.STATUS_CORE, cult)
	_expect_room(tmap, 10, DungeonTerritoryEntry.STATUS_PATROL, orc)
	check(tmap.status_of(11) == DungeonTerritoryEntry.STATUS_UNCLAIMED, "room 11 unclaimed")
	check(tmap.status_of(12) == DungeonTerritoryEntry.STATUS_UNCLAIMED, "room 12 unclaimed")
	_expect_room(tmap, 13, DungeonTerritoryEntry.STATUS_CORE, orc)
	_expect_room(tmap, 14, DungeonTerritoryEntry.STATUS_CORE, orc)
	_expect_room(tmap, 15, DungeonTerritoryEntry.STATUS_CORE, orc)


func test_relationships() -> void:
	var result := _generate()
	var goblin := _faction_by_species(result, "goblin")
	var cult := _faction_by_species(result, "necromancer")
	var orc := _faction_by_species(result, "orc")

	var g_c := result.relationship_between(goblin.id, cult.id)
	var c_o := result.relationship_between(cult.id, orc.id)
	var g_o := result.relationship_between(goblin.id, orc.id)
	check(g_c != null and c_o != null and g_o != null, "all three pair records exist")
	if g_c == null or c_o == null or g_o == null:
		return
	check(g_c.relationship == DungeonFactionRelationship.REL_UNAWARE,
		"goblins unaware of the cult (locked door), got %s" % g_c.relationship)
	check(c_o.relationship == DungeonFactionRelationship.REL_UNAWARE,
		"cult unaware of orcs (walled off), got %s" % c_o.relationship)
	check(g_o.relationship != DungeonFactionRelationship.REL_UNAWARE,
		"goblins and orcs are AWARE of each other, got %s" % g_o.relationship)
	check(DungeonFactionRelationship.VALID_RELATIONSHIPS.has(g_o.relationship),
		"goblin-orc relationship is a valid value")


func test_determinism_byte_identical() -> void:
	var a := _digest(DungeonFactionGenerator.generate(_build_mine(), SEED))
	var b := _digest(DungeonFactionGenerator.generate(_build_mine(), SEED))
	check(a == b, "same input + seed → byte-identical generation")
	# A different seed may change rolled names/relationships (not identity).
	var c := _digest(DungeonFactionGenerator.generate(_build_mine(), SEED + 1))
	check(a != "" and c != "", "digests are non-empty")


func test_names_follow_template() -> void:
	var result := _generate()
	for f in result.factions:
		check(f.name != "", "%s faction has a generated name: '%s'" % [f.species, f.name])
		var parts := f.name.split(" ")
		check(parts.size() == 3, "name '%s' is [Adjective Noun Group]" % f.name)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _expect_room(tmap: DungeonTerritoryMap, room_id: int, status: String, faction: DungeonFaction) -> void:
	check(tmap.status_of(room_id) == status,
		"room %d status %s (got %s)" % [room_id, status, tmap.status_of(room_id)])
	if faction != null:
		check(tmap.controller_of(room_id) == faction.id,
			"room %d controlled by %s" % [room_id, faction.species])


func _same_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var sa := a.duplicate()
	var sb := b.duplicate()
	sa.sort()
	sb.sort()
	return sa == sb


## A stable string digest of a result for determinism comparison.
func _digest(result: DungeonFactionGenerationResult) -> String:
	var lines: Array[String] = []
	var fs := result.factions.duplicate()
	fs.sort_custom(func(a, b): return a.id < b.id)
	for f in fs:
		lines.append("F|%s|%s|%s|%s|lair=%s|core=%s|patrol=%s|frontier=%s|pop=%d|lead=%d/%s|name=%s" % [
			f.id, f.species, f.faction_type, f.alignment, str(f.lair_room_ids),
			str(f.core_room_ids), str(f.patrol_room_ids), str(f.frontier_room_ids),
			f.starting_population, f.leader_room_id, str(f.leader_hd), f.name])
	var rs := result.relationships.duplicate()
	rs.sort_custom(func(a, b): return a.id < b.id)
	for r in rs:
		lines.append("R|%s|%s|%s|%s|%s" % [r.id, r.faction_a_id, r.faction_b_id, r.relationship, str(r.contested_room_ids)])
	var rids := result.territory_map.room_assignments.keys()
	rids.sort()
	for rid in rids:
		var e: DungeonTerritoryEntry = result.territory_map.room_assignments[rid]
		lines.append("T|%d|%s|%s" % [rid, e.status, e.controlling_faction_id])
	return "\n".join(lines)
