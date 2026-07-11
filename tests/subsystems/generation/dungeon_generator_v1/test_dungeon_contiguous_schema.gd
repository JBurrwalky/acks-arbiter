extends "res://tests/test_suite_base.gd"

## DG-C3D.A unit tests — dormant contiguous-3D types + schema (migration 210).
##
## Covers:
##   1. RoomZone / StairwellData dict serialization round-trips (through
##      JSON.stringify/parse_string to prove JSON-safety of the cell arrays).
##   2. SQLite round-trips via the DungeonGeneratorRepository helpers
##      (insert_room_zones/get_room_zones, insert_stairwells/get_stairwells),
##      including "" <-> NULL conversion on the stocking FK columns.
##   3. Migration 210 applied + recorded exactly once; new columns exist on
##      voxel_map_cells / dungeon_rooms / dungeon_floors.
##   4. CHECK constraints: every allowed vocabulary value inserts (conventions
##      §6.5 round-trip-each-value discipline); bad values are rejected.
##   5. Cascade delete (delete_dungeon_layout) covers the two new tables.
##   6. dungeon_rooms new-column defaults hold for rows inserted without them
##      (the dormancy guarantee for the legacy insert path).


func run_all_tests() -> void:
	test_room_zone_dict_round_trip()
	test_stairwell_dict_round_trip()
	test_room_zone_sqlite_round_trip()
	test_stairwell_sqlite_round_trip()
	test_migration_recorded_once()
	test_new_columns_exist()
	test_check_constraints_accept_all_vocab_values()
	test_check_constraints_reject_bad_values()
	test_cascade_delete_covers_new_tables()
	test_dungeon_rooms_new_column_defaults()
	if not has_failures():
		print("DungeonContiguousSchema: all tests passed.")


# ---------------------------------------------------------------------------
# 1. Dict round-trips
# ---------------------------------------------------------------------------

func test_room_zone_dict_round_trip() -> void:
	var zone := RoomZone.new()
	zone.room_id = 7
	zone.zone_index = 2
	zone.band = 3
	zone.zone_type = RoomZone.ZONE_TYPE_BALCONY
	zone.cells = [Vector2i(4, 5), Vector2i(4, 6), Vector2i(5, 5)]
	zone.level_offset = 0
	zone.contents_kind = "monster"
	zone.monster_group_id = "mg_abc"
	zone.treasure_hoard_id = ""
	zone.current_purpose = "overlook gallery"

	# Round-trip through actual JSON text — proves the [col,row] cell encoding
	# survives stringify/parse (Vector2i itself would not).
	var json_text := JSON.stringify(zone.to_dict())
	var parsed: Variant = JSON.parse_string(json_text)
	check(parsed is Dictionary, "RoomZone dict survives JSON stringify/parse")
	if not (parsed is Dictionary):
		return
	var back := RoomZone.from_dict(parsed)
	check(back.room_id == 7, "RoomZone round-trip room_id")
	check(back.zone_index == 2, "RoomZone round-trip zone_index")
	check(back.band == 3, "RoomZone round-trip band")
	check(back.zone_type == RoomZone.ZONE_TYPE_BALCONY, "RoomZone round-trip zone_type")
	check(back.cells == zone.cells, "RoomZone round-trip cells, got %s" % str(back.cells))
	check(back.level_offset == 0, "RoomZone round-trip level_offset")
	check(back.contents_kind == "monster", "RoomZone round-trip contents_kind")
	check(back.monster_group_id == "mg_abc", "RoomZone round-trip monster_group_id")
	check(back.treasure_hoard_id == "", "RoomZone round-trip empty treasure_hoard_id")
	check(back.current_purpose == "overlook gallery", "RoomZone round-trip current_purpose")

	var defaults := RoomZone.from_dict({})
	check(defaults.room_id == -1 and defaults.zone_index == 0
		and defaults.zone_type == RoomZone.ZONE_TYPE_MAIN and defaults.cells.is_empty(),
		"RoomZone.from_dict({}) yields defaults")


func test_stairwell_dict_round_trip() -> void:
	var stairwell := StairwellData.new()
	stairwell.stairwell_id = "sw_test_1"
	stairwell.type = StairwellData.TYPE_SWITCHBACK
	stairwell.lower_band = 2
	stairwell.upper_band = 1
	stairwell.bottom_cell = Vector3i(10, 12, -4)
	stairwell.top_cell = Vector3i(11, 12, -2)
	stairwell.run_cells = [Vector3i(10, 12, -4), Vector3i(10, 12, -3), Vector3i(11, 12, -3)]
	stairwell.width = 2
	stairwell.room_id = 9
	stairwell.is_entrance = false

	var json_text := JSON.stringify(stairwell.to_dict())
	var parsed: Variant = JSON.parse_string(json_text)
	check(parsed is Dictionary, "StairwellData dict survives JSON stringify/parse")
	if not (parsed is Dictionary):
		return
	var back := StairwellData.from_dict(parsed)
	check(back.stairwell_id == "sw_test_1", "StairwellData round-trip stairwell_id")
	check(back.type == StairwellData.TYPE_SWITCHBACK, "StairwellData round-trip type")
	check(back.lower_band == 2 and back.upper_band == 1, "StairwellData round-trip bands")
	check(back.bottom_cell == Vector3i(10, 12, -4), "StairwellData round-trip bottom_cell")
	check(back.top_cell == Vector3i(11, 12, -2), "StairwellData round-trip top_cell")
	check(back.run_cells == stairwell.run_cells,
		"StairwellData round-trip run_cells, got %s" % str(back.run_cells))
	check(back.width == 2, "StairwellData round-trip width")
	check(back.room_id == 9, "StairwellData round-trip room_id")
	check(back.is_entrance == false, "StairwellData round-trip is_entrance")

	var defaults := StairwellData.from_dict({})
	check(defaults.stairwell_id == "" and defaults.type == StairwellData.TYPE_STRAIGHT
		and defaults.bottom_cell == StairwellData.UNSET_CELL and defaults.run_cells.is_empty(),
		"StairwellData.from_dict({}) yields defaults")


# ---------------------------------------------------------------------------
# 2. SQLite round-trips (repository helpers)
# ---------------------------------------------------------------------------

func test_room_zone_sqlite_round_trip() -> void:
	var did := _unique_id("zones")
	var main_zone := RoomZone.new()
	main_zone.room_id = 0
	main_zone.zone_index = 0
	main_zone.band = 1
	main_zone.zone_type = RoomZone.ZONE_TYPE_MAIN
	main_zone.cells = [Vector2i(2, 2), Vector2i(2, 3)]
	main_zone.contents_kind = "monster_lair"
	main_zone.monster_group_id = "mg_1"
	main_zone.treasure_hoard_id = "th_1"
	main_zone.current_purpose = "worship hall"

	var balcony := RoomZone.new()
	balcony.room_id = 0
	balcony.zone_index = 1
	balcony.band = 2
	balcony.zone_type = RoomZone.ZONE_TYPE_BALCONY
	balcony.cells = [Vector2i(1, 1)]
	# contents_kind stays "empty"; both FK ids stay "" — must store as NULL.

	check(DungeonGeneratorRepository.insert_room_zones(did, [main_zone, balcony]),
		"insert_room_zones succeeds")

	var loaded := DungeonGeneratorRepository.get_room_zones(did)
	check(loaded.size() == 2, "two zones load back, got %d" % loaded.size())
	if loaded.size() != 2:
		DungeonGeneratorRepository.delete_dungeon_layout(did)
		return
	# Ordered by (room_id, zone_index): main first.
	check(loaded[0].zone_index == 0 and loaded[1].zone_index == 1,
		"zones ordered by zone_index")
	check(loaded[0].band == 1 and loaded[0].zone_type == RoomZone.ZONE_TYPE_MAIN
		and loaded[0].cells == main_zone.cells
		and loaded[0].contents_kind == "monster_lair"
		and loaded[0].monster_group_id == "mg_1"
		and loaded[0].treasure_hoard_id == "th_1"
		and loaded[0].current_purpose == "worship hall",
		"main zone fields round-trip through room_zones")
	check(loaded[1].zone_type == RoomZone.ZONE_TYPE_BALCONY
		and loaded[1].cells == balcony.cells
		and loaded[1].monster_group_id == "" and loaded[1].treasure_hoard_id == "",
		"balcony zone round-trips; NULL FK columns read back as \"\"")

	# NULL actually stored (not empty string) for unset FK ids.
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM room_zones WHERE dungeon_id = ? AND zone_index = 1 AND monster_group_id IS NULL",
		[did])
	check(int(CampaignRepository.db.query_result[0]["n"]) == 1,
		"empty monster_group_id stored as SQL NULL")

	DungeonGeneratorRepository.delete_dungeon_layout(did)


func test_stairwell_sqlite_round_trip() -> void:
	var did := _unique_id("stairs")
	var spiral := StairwellData.new()
	spiral.stairwell_id = ""  # empty — insert must generate and write back
	spiral.type = StairwellData.TYPE_SPIRAL
	spiral.lower_band = 3
	spiral.upper_band = 2
	spiral.bottom_cell = Vector3i(6, 7, -6)
	spiral.top_cell = Vector3i(6, 7, -4)
	spiral.run_cells = [Vector3i(6, 7, -6), Vector3i(6, 7, -5), Vector3i(6, 7, -4)]
	spiral.width = 1
	spiral.room_id = 4
	spiral.is_entrance = false

	var entrance_stair := StairwellData.new()
	entrance_stair.stairwell_id = "sw_entrance_fixed"
	entrance_stair.type = StairwellData.TYPE_STRAIGHT
	entrance_stair.lower_band = 1
	entrance_stair.upper_band = 0
	entrance_stair.is_entrance = true

	check(DungeonGeneratorRepository.insert_stairwells(did, [spiral, entrance_stair]),
		"insert_stairwells succeeds")
	check(not spiral.stairwell_id.is_empty(),
		"insert generates a stairwell_id for records that lack one")

	var loaded := DungeonGeneratorRepository.get_stairwells(did)
	check(loaded.size() == 2, "two stairwells load back, got %d" % loaded.size())
	if loaded.size() != 2:
		DungeonGeneratorRepository.delete_dungeon_layout(did)
		return
	# Ordered by lower_band ASC: the entrance stair (lower_band 1) first.
	check(loaded[0].stairwell_id == "sw_entrance_fixed" and loaded[0].is_entrance,
		"entrance stairwell round-trips with fixed id + flag")
	check(loaded[0].bottom_cell == StairwellData.UNSET_CELL
		and loaded[0].run_cells.is_empty(),
		"unset cells round-trip as sentinels / empty run")
	var back := loaded[1]
	check(back.stairwell_id == spiral.stairwell_id, "generated id round-trips")
	check(back.type == StairwellData.TYPE_SPIRAL, "type round-trips")
	check(back.lower_band == 3 and back.upper_band == 2, "bands round-trip")
	check(back.bottom_cell == spiral.bottom_cell and back.top_cell == spiral.top_cell,
		"landing cells round-trip")
	check(back.run_cells == spiral.run_cells, "run_cells round-trip")
	check(back.width == 1 and back.room_id == 4 and back.is_entrance == false,
		"width/room_id/is_entrance round-trip")

	DungeonGeneratorRepository.delete_dungeon_layout(did)


# ---------------------------------------------------------------------------
# 3. Migration applied + columns exist
# ---------------------------------------------------------------------------

func test_migration_recorded_once() -> void:
	# Idempotent-re-run proof: the double-run harness (tools/run_tests.ps1,
	# stable per-worktree DB) boots run 2 against an ALREADY-migrated DB, so
	# this assertion executing in run 2 proves the runner skipped 210 rather
	# than re-applying it (re-application would fail on the ALTERs and/or
	# double-record the version).
	CampaignRepository.db.query(
		"SELECT COUNT(*) AS n FROM schema_migrations WHERE version = 210")
	check(int(CampaignRepository.db.query_result[0]["n"]) == 1,
		"migration 210 recorded exactly once in schema_migrations")


func test_new_columns_exist() -> void:
	check(_has_column("voxel_map_cells", "zone_index"), "voxel_map_cells.zone_index exists")
	check(_has_column("dungeon_rooms", "band"), "dungeon_rooms.band exists")
	check(_has_column("dungeon_rooms", "kind"), "dungeon_rooms.kind exists")
	check(_has_column("dungeon_rooms", "height_levels"), "dungeon_rooms.height_levels exists")
	check(_has_column("dungeon_rooms", "level_offset"), "dungeon_rooms.level_offset exists")
	check(_has_column("dungeon_floors", "generator_version"), "dungeon_floors.generator_version exists")
	check(_table_exists("room_zones"), "room_zones table exists")
	check(_table_exists("stairwells"), "stairwells table exists")


# ---------------------------------------------------------------------------
# 4. CHECK constraints (conventions §6.5 — every allowed value inserts;
#    uncovered values are rejected)
# ---------------------------------------------------------------------------

func test_check_constraints_accept_all_vocab_values() -> void:
	var did := _unique_id("vocab")
	for zt in RoomZone.VALID_ZONE_TYPES:
		var ok: bool = CampaignRepository.db.query_with_bindings(
			"INSERT INTO room_zones (id, dungeon_id, zone_type) VALUES (?, ?, ?)",
			["%s_zt_%s" % [did, zt], did, zt])
		check(ok, "room_zones.zone_type accepts '%s'" % zt)
	for ck in ["empty", "monster", "monster_lair", "trap_placeholder", "unique_placeholder"]:
		var ok2: bool = CampaignRepository.db.query_with_bindings(
			"INSERT INTO room_zones (id, dungeon_id, contents_kind) VALUES (?, ?, ?)",
			["%s_ck_%s" % [did, ck], did, ck])
		check(ok2, "room_zones.contents_kind accepts '%s'" % ck)
	for st in StairwellData.VALID_TYPES:
		var ok3: bool = CampaignRepository.db.query_with_bindings(
			"INSERT INTO stairwells (id, dungeon_id, type) VALUES (?, ?, ?)",
			["%s_st_%s" % [did, st], did, st])
		check(ok3, "stairwells.type accepts '%s'" % st)
	for kind in DungeonRoomData.VALID_KINDS:
		var ok4: bool = CampaignRepository.db.query_with_bindings(
			"""INSERT INTO dungeon_rooms
				(id, dungeon_id, floor_id, room_id_in_floor,
				 bounds_x, bounds_y, bounds_w, bounds_h, kind)
			   VALUES (?, ?, ?, 0, 0, 0, 1, 1, ?)""",
			["%s_kind_%s" % [did, kind], did, "%s_floor" % did, kind])
		check(ok4, "dungeon_rooms.kind accepts '%s'" % kind)
	_purge_dungeon_rows(did)


func test_check_constraints_reject_bad_values() -> void:
	var did := _unique_id("badvocab")
	check(not CampaignRepository.db.query_with_bindings(
		"INSERT INTO room_zones (id, dungeon_id, zone_type) VALUES (?, ?, ?)",
		[did + "_bad1", did, "mezzanine"]),
		"room_zones.zone_type rejects 'mezzanine'")
	check(not CampaignRepository.db.query_with_bindings(
		"INSERT INTO room_zones (id, dungeon_id, contents_kind) VALUES (?, ?, ?)",
		[did + "_bad2", did, "stocked"]),
		"room_zones.contents_kind rejects 'stocked'")
	check(not CampaignRepository.db.query_with_bindings(
		"INSERT INTO stairwells (id, dungeon_id, type) VALUES (?, ?, ?)",
		[did + "_bad3", did, "elevator"]),
		"stairwells.type rejects 'elevator'")
	check(not CampaignRepository.db.query_with_bindings(
		"INSERT INTO stairwells (id, dungeon_id, is_entrance) VALUES (?, ?, ?)",
		[did + "_bad4", did, 2]),
		"stairwells.is_entrance rejects 2")
	check(not CampaignRepository.db.query_with_bindings(
		"""INSERT INTO dungeon_rooms
			(id, dungeon_id, floor_id, room_id_in_floor,
			 bounds_x, bounds_y, bounds_w, bounds_h, kind)
		   VALUES (?, ?, ?, 0, 0, 0, 1, 1, ?)""",
		[did + "_bad5", did, did + "_floor", "corridor"]),
		"dungeon_rooms.kind rejects 'corridor'")
	_purge_dungeon_rows(did)


# ---------------------------------------------------------------------------
# 5. Cascade delete
# ---------------------------------------------------------------------------

func test_cascade_delete_covers_new_tables() -> void:
	var did := _unique_id("cascade")
	var zone := RoomZone.new()
	zone.room_id = 0
	var stairwell := StairwellData.new()
	check(DungeonGeneratorRepository.insert_room_zones(did, [zone]), "cascade: zone inserted")
	check(DungeonGeneratorRepository.insert_stairwells(did, [stairwell]), "cascade: stairwell inserted")
	check(DungeonGeneratorRepository.delete_dungeon_layout(did), "cascade: delete_dungeon_layout succeeds")
	check(DungeonGeneratorRepository.get_room_zones(did).is_empty(),
		"cascade delete purges room_zones")
	check(DungeonGeneratorRepository.get_stairwells(did).is_empty(),
		"cascade delete purges stairwells")


# ---------------------------------------------------------------------------
# 6. Legacy-path dormancy: defaults hold when the new columns are not written
# ---------------------------------------------------------------------------

func test_dungeon_rooms_new_column_defaults() -> void:
	var did := _unique_id("defaults")
	var ok: bool = CampaignRepository.db.query_with_bindings(
		"""INSERT INTO dungeon_rooms
			(id, dungeon_id, floor_id, room_id_in_floor,
			 bounds_x, bounds_y, bounds_w, bounds_h)
		   VALUES (?, ?, ?, 0, 0, 0, 2, 2)""",
		[did + "_room", did, did + "_floor"])
	check(ok, "legacy-shape dungeon_rooms insert (no new columns) still succeeds")
	CampaignRepository.db.query_with_bindings(
		"SELECT band, kind, height_levels, level_offset FROM dungeon_rooms WHERE id = ?",
		[did + "_room"])
	if CampaignRepository.db.query_result.is_empty():
		check(false, "defaults test: inserted room row not found")
		_purge_dungeon_rows(did)
		return
	var row: Dictionary = CampaignRepository.db.query_result[0]
	check(int(row["band"]) == 0, "dungeon_rooms.band defaults to 0")
	check(str(row["kind"]) == "chamber", "dungeon_rooms.kind defaults to 'chamber'")
	check(int(row["height_levels"]) == 2, "dungeon_rooms.height_levels defaults to 2")
	check(int(row["level_offset"]) == 0, "dungeon_rooms.level_offset defaults to 0")
	_purge_dungeon_rows(did)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _unique_id(prefix: String) -> String:
	return "test_c3d_%s_%d" % [prefix, randi()]


func _has_column(table: String, column: String) -> bool:
	CampaignRepository.db.query("PRAGMA table_info(%s)" % table)
	for row in CampaignRepository.db.query_result:
		if str(row["name"]) == column:
			return true
	return false


func _table_exists(table: String) -> bool:
	CampaignRepository.db.query_with_bindings(
		"SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [table])
	return not CampaignRepository.db.query_result.is_empty()


func _purge_dungeon_rows(dungeon_id: String) -> void:
	for table in ["room_zones", "stairwells", "dungeon_rooms"]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM %s WHERE dungeon_id = ?" % table, [dungeon_id])
