class_name DungeonGeneratorRepository
extends RefCounted

## Persistence for V1-generated dungeons (DG-V1.C of the build plan).
##
## A regular RefCounted with all-static methods (NOT an autoload — the build
## plan is explicit that this stays a plain class so `class_name` cannot
## collide with an autoload singleton). All DB access goes through the shared
## `CampaignRepository.db` handle, matching the standalone-repository pattern
## used by ArmyRepository / BattleRepository / VassalRepository / etc.
##
## ## What persists
##
## A dungeon is a multi-floor structure: an `Array[DungeonLayout]`, one per
## floor (per V1 GDD §4.2 — the layout generator emits one DungeonLayout per
## floor). The repository persists each floor across the six DG-V1.C tables:
##
##   dungeon_floors   — floor metadata + the rasterized cell grid (cells_json)
##                      + stairs (stairs_json) + stocking summary fields.
##   dungeon_rooms    — one row per room (bounds, purposes, contents_kind,
##                      stocking FKs). Room CELLS are recomputed from bounds on
##                      load (V1 rooms are rectangles) — not stored per-cell.
##   dungeon_doors    — one row per door.
##   monster_groups / treasure_hoards / key_items — DG-V1.D stocking output;
##      the tables exist now and their CHECK constraints are tested, but the
##      layout-level CRUD here only reads/writes them once DG-V1.D adds the
##      stocking fields to the in-memory DungeonLayout. For DG-V1.B layouts
##      these tables stay empty.
##
## ## ID strategy
##
## Every PK is an app-generated TEXT id via `CampaignRepository.generate_id()`
## (the project pattern — avoids AUTOINCREMENT + last_insert_rowid round-trips).
## `dungeon_id` is the external linkage supplied by the caller (POI generator /
## region zoom-in pipeline). Intra-dungeon links use the TEXT floor / room ids.
##
## ## Serialization
##
## `cells_json` is a positional 2D array (see _CELL_FIELD_ORDER) for compact
## exact round-trip. `stairs_json` is an array of stair dicts. JSON because the
## cell grid is large and unstructured relative to the relational tables, and
## the V1 GDD §12.3 "self-contained snapshot" philosophy wants the exact grid
## stored, not re-derived.


# Positional field order for each cell in cells_json. Internal to this file
# (serialize + deserialize both reference it); never exposed.
# [terrain_feature, passable, blocks_los, door_state, door_detected, room_id, is_corridor, elevation]
const _CELL_FIELDS := ["tf", "p", "los", "ds", "dd", "rid", "corr", "elev"]


# ---------------------------------------------------------------------------
# Insert
# ---------------------------------------------------------------------------

## Persist an entire multi-floor dungeon under [param dungeon_id]. Wraps all
## floors in a single transaction. Returns true on success; rolls back + logs
## on any failure. Replaces any existing rows for the dungeon_id (idempotent
## re-save) by deleting first.
##
## [param key_items] is the optional array of KeyItemData for the dungeon
## (cross-floor key placements — DG-V1.D). Defaults to [] so existing callers
## (DG-V1.B tests, layout-only inserts) need no change.
static func insert_dungeon_layout(dungeon_id: String, floors: Array, key_items: Array = []) -> bool:
	if dungeon_id.is_empty():
		push_error("DungeonGeneratorRepository.insert_dungeon_layout: empty dungeon_id.")
		return false
	var db = CampaignRepository.db
	db.query("BEGIN TRANSACTION")
	# Idempotent re-save: clear any prior rows for this dungeon first.
	if not _delete_dungeon_rows(dungeon_id):
		db.query("ROLLBACK")
		return false
	# Build floor_index -> floor_id mapping as we insert each floor.
	# floor_index == layout.level_number (1-based, set by generator/orchestrator).
	var index_to_floor_id: Dictionary = {}
	for layout in floors:
		var floor_id: String = _insert_floor_rows(dungeon_id, layout)
		if floor_id.is_empty():
			db.query("ROLLBACK")
			push_error("DungeonGeneratorRepository.insert_dungeon_layout: floor insert failed for dungeon %s." % dungeon_id)
			return false
		index_to_floor_id[layout.level_number] = floor_id
		# Insert this floor's monster groups and treasure hoards.
		if not _insert_monster_groups(dungeon_id, floor_id, layout.monster_groups):
			db.query("ROLLBACK")
			return false
		if not _insert_treasure_hoards(dungeon_id, floor_id, layout.treasure_hoards):
			db.query("ROLLBACK")
			return false
	# Insert key items after all floors (cross-floor references resolved).
	if not _insert_key_items(dungeon_id, key_items, index_to_floor_id):
		db.query("ROLLBACK")
		return false
	db.query("COMMIT")
	return true


## Insert a single floor's rows (floor + rooms + doors). Returns the new
## floor's TEXT id, or "" on failure. Caller is responsible for the enclosing
## transaction. Used internally by insert_dungeon_layout.
static func _insert_floor_rows(dungeon_id: String, layout: DungeonLayout) -> String:
	var db = CampaignRepository.db
	var floor_id: String = CampaignRepository.generate_id()
	var ok: bool = db.query_with_bindings(
		"""INSERT INTO dungeon_floors
			(id, dungeon_id, floor_index, floor_tier, is_entrance_floor,
			 dungeon_type, dungeon_size, structure_type, grid_width, grid_height,
			 entrance_x, entrance_y, generation_seed, cells_json, stairs_json)
		   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
		[
			floor_id, dungeon_id, layout.level_number, layout.floor_tier,
			1 if layout.is_entrance_floor else 0,
			layout.dungeon_type, layout.dungeon_size, layout.structure_type,
			layout.grid_width, layout.grid_height,
			layout.entrance.x, layout.entrance.y, layout.generation_seed,
			_serialize_cells(layout.cells), _serialize_stairs(layout.stairs),
		])
	if not ok:
		push_error("DungeonGeneratorRepository: dungeon_floors insert failed (dungeon %s, floor %d)." % [dungeon_id, layout.level_number])
		return ""
	# Rooms.
	for r in layout.rooms:
		var room: DungeonRoomData = r
		var room_pk: String = CampaignRepository.generate_id()
		var room_ok: bool = db.query_with_bindings(
			"""INSERT INTO dungeon_rooms
				(id, dungeon_id, floor_id, room_id_in_floor,
				 bounds_x, bounds_y, bounds_w, bounds_h, area_sqft,
				 center_x, center_y, original_purpose, current_purpose, contents_kind)
			   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
			[
				room_pk, dungeon_id, floor_id, room.id,
				room.bounds.position.x, room.bounds.position.y,
				room.bounds.size.x, room.bounds.size.y, room.area_sqft,
				room.center.x, room.center.y,
				room.original_purpose, room.current_purpose,
				room.contents_kind,
			])
		if not room_ok:
			push_error("DungeonGeneratorRepository: dungeon_rooms insert failed (floor %s, room %d)." % [floor_id, room.id])
			return ""
	# Doors.
	for d in layout.doors:
		var door: DungeonDoorData = d
		var door_pk: String = CampaignRepository.generate_id()
		var door_ok: bool = db.query_with_bindings(
			"""INSERT INTO dungeon_doors
				(id, dungeon_id, floor_id, position_x, position_y, type,
				 is_secret, door_state, door_material, is_evil, connects_room_ids)
			   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
			[
				door_pk, dungeon_id, floor_id, door.position.x, door.position.y,
				door.type, 1 if door.is_secret else 0,
				_door_state_of(door), door.door_material,
				1 if door.is_evil else 0,
				JSON.stringify(door.connects),
			])
		if not door_ok:
			push_error("DungeonGeneratorRepository: dungeon_doors insert failed (floor %s, pos %s)." % [floor_id, door.position])
			return ""
	return floor_id


# ---------------------------------------------------------------------------
# Read
# ---------------------------------------------------------------------------

## Lightweight floor metadata (no cell grid) for listing — ordered by
## floor_index. Each entry is a Dictionary mirroring the dungeon_floors row.
static func list_floors(dungeon_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var db = CampaignRepository.db
	if not db.query_with_bindings(
			"SELECT id, dungeon_id, floor_index, floor_tier, is_entrance_floor, grid_width, grid_height FROM dungeon_floors WHERE dungeon_id = ? ORDER BY floor_index ASC",
			[dungeon_id]):
		return out
	for row in db.query_result:
		out.append((row as Dictionary).duplicate())
	return out


## Reconstruct every floor of a dungeon as Array[DungeonLayout], ordered by
## floor_index. Empty array if the dungeon has no stored floors.
##
## NOTE: returns an Array (a dungeon is multi-floor) rather than the build
## plan's singular `DungeonLayout` return — the singular type was illustrative.
static func get_dungeon_layout(dungeon_id: String) -> Array[DungeonLayout]:
	var out: Array[DungeonLayout] = []
	var db = CampaignRepository.db
	if not db.query_with_bindings(
			"SELECT id FROM dungeon_floors WHERE dungeon_id = ? ORDER BY floor_index ASC",
			[dungeon_id]):
		return out
	var floor_ids: Array[String] = []
	for row in db.query_result:
		floor_ids.append(str(row["id"]))
	for fid in floor_ids:
		var layout: DungeonLayout = get_floor(fid)
		if layout != null:
			out.append(layout)
	return out


## Reconstruct one floor (by its TEXT floor PK) into a DungeonLayout. Returns
## null if the floor id is unknown. Also loads monster_groups and
## treasure_hoards for this floor (DG-V1.D).
static func get_floor(floor_id: String) -> DungeonLayout:
	var db = CampaignRepository.db
	if not db.query_with_bindings("SELECT * FROM dungeon_floors WHERE id = ?", [floor_id]):
		return null
	if db.query_result.is_empty():
		return null
	var row: Dictionary = db.query_result[0]

	var layout := DungeonLayout.new()
	layout.dungeon_id = str(row["dungeon_id"])
	layout.dungeon_type = str(row["dungeon_type"])
	layout.dungeon_size = str(row["dungeon_size"])
	layout.structure_type = str(row["structure_type"])
	layout.level_number = int(row["floor_index"])
	layout.floor_tier = int(row["floor_tier"])
	layout.is_entrance_floor = int(row["is_entrance_floor"]) == 1
	layout.grid_width = int(row["grid_width"])
	layout.grid_height = int(row["grid_height"])
	layout.entrance = Vector2i(int(row["entrance_x"]), int(row["entrance_y"]))
	layout.generation_seed = int(row["generation_seed"])
	layout.cells = _deserialize_cells(str(row["cells_json"]), layout.grid_width, layout.grid_height)
	layout.stairs = _deserialize_stairs(str(row["stairs_json"]))
	# Theme is not persisted (it lives in the catalog); recover by type.
	layout.theme = DungeonThemeCatalog.get_theme(layout.dungeon_type)

	# Rooms.
	layout.rooms = []
	if db.query_with_bindings(
			"SELECT * FROM dungeon_rooms WHERE floor_id = ? ORDER BY room_id_in_floor ASC",
			[floor_id]):
		for rrow in db.query_result:
			layout.rooms.append(_row_to_room(rrow))

	# Doors.
	layout.doors = []
	if db.query_with_bindings(
			"SELECT * FROM dungeon_doors WHERE floor_id = ?",
			[floor_id]):
		for drow in db.query_result:
			layout.doors.append(_row_to_door(drow))

	_attach_doors_to_rooms(layout.rooms, layout.doors)

	# Monster groups (DG-V1.D). floor_index == level_number (already set above).
	layout.monster_groups = _load_monster_groups(floor_id, layout.level_number)

	# Treasure hoards (DG-V1.D).
	layout.treasure_hoards = _load_treasure_hoards(floor_id, layout.level_number)

	return layout


## Reconstruct all KeyItemData for a dungeon. Resolves floor_id -> level_number
## via a lookup query so KeyItemData.opens_door_floor_index and
## placed_on_floor_index are correctly re-populated as ints.
static func get_key_items(dungeon_id: String) -> Array[KeyItemData]:
	var out: Array[KeyItemData] = []
	var db = CampaignRepository.db

	# Build floor_id -> level_number lookup for this dungeon.
	var floor_level: Dictionary = {}
	if db.query_with_bindings(
			"SELECT id, floor_index FROM dungeon_floors WHERE dungeon_id = ?",
			[dungeon_id]):
		for frow in db.query_result:
			floor_level[str(frow["id"])] = int(frow["floor_index"])

	if not db.query_with_bindings(
			"SELECT * FROM key_items WHERE dungeon_id = ?",
			[dungeon_id]):
		return out
	for row in db.query_result:
		out.append(_row_to_key_item(row, floor_level))
	return out


# ---------------------------------------------------------------------------
# Delete (cascade)
# ---------------------------------------------------------------------------

## Cascading delete across all six tables for [param dungeon_id]. Transactional.
static func delete_dungeon_layout(dungeon_id: String) -> bool:
	var db = CampaignRepository.db
	db.query("BEGIN TRANSACTION")
	if not _delete_dungeon_rows(dungeon_id):
		db.query("ROLLBACK")
		return false
	db.query("COMMIT")
	return true


## Delete every row for a dungeon across all six tables. Caller manages the
## transaction. Returns false on the first failed statement.
static func _delete_dungeon_rows(dungeon_id: String) -> bool:
	var db = CampaignRepository.db
	for table in ["dungeon_rooms", "dungeon_doors", "monster_groups",
			"treasure_hoards", "key_items", "dungeon_floors"]:
		if not db.query_with_bindings("DELETE FROM %s WHERE dungeon_id = ?" % table, [dungeon_id]):
			push_error("DungeonGeneratorRepository: cascade delete failed on %s for dungeon %s." % [table, dungeon_id])
			return false
	return true


# ---------------------------------------------------------------------------
# DG-V1.D insert helpers
# ---------------------------------------------------------------------------

## Insert all monster groups for a single floor. Caller holds the transaction.
static func _insert_monster_groups(dungeon_id: String, floor_id: String, groups: Array) -> bool:
	var db = CampaignRepository.db
	for g in groups:
		var group: MonsterGroupData = g
		var pk: String = CampaignRepository.generate_id()
		var ttl: Variant = null if group.treasure_type_letter.is_empty() else group.treasure_type_letter
		var ok: bool = db.query_with_bindings(
			"""INSERT INTO monster_groups
				(id, dungeon_id, floor_id, room_id, monster_name, monster_xp_each,
				 number_appearing, hd, associated_creatures, is_lair, morale,
				 alignment, treasure_type_letter, initial_inventory)
			   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
			[
				pk, dungeon_id, floor_id, str(group.room_id),
				group.monster_name, group.monster_xp_each, group.number_appearing,
				group.hd, JSON.stringify(group.associated_creatures),
				1 if group.is_lair else 0,
				group.morale, group.alignment,
				ttl,
				JSON.stringify(group.initial_inventory),
			])
		if not ok:
			push_error("DungeonGeneratorRepository: monster_groups insert failed (floor %s, room %d)." % [floor_id, group.room_id])
			return false
	return true


## Insert all treasure hoards for a single floor. Caller holds the transaction.
##
## Migration 137 added cell_x/y/z + container_type + is_locked + is_trapped for
## the cell-based treasure container model (gdd-treasure-item-backing.md §15).
## Unplaced hoards (the placement service skipped them — empty room_cells) keep
## the sentinel cell -1/-1/0 and NULL container_type.
static func _insert_treasure_hoards(dungeon_id: String, floor_id: String, hoards: Array) -> bool:
	var db = CampaignRepository.db
	for h in hoards:
		var hoard: TreasureHoardData = h
		var pk: String = CampaignRepository.generate_id()
		var ttl: Variant = null if hoard.treasure_type_letter.is_empty() else hoard.treasure_type_letter
		# container_type "" → NULL (matches the schema's nullable column / CHECK
		# enum semantics: an unplaced hoard has no container yet).
		var ct: Variant = null if hoard.container_type.is_empty() else hoard.container_type
		var ok: bool = db.query_with_bindings(
			"""INSERT INTO treasure_hoards
				(id, dungeon_id, floor_id, room_id, source, treasure_type_letter,
				 copper, silver, electrum, gold, platinum,
				 gems, jewelry, magic_items, total_gp_value, is_hidden,
				 cell_x, cell_y, cell_z, container_type, is_locked, is_trapped)
			   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
			[
				pk, dungeon_id, floor_id, str(hoard.room_id),
				hoard.source, ttl,
				hoard.copper, hoard.silver, hoard.electrum, hoard.gold, hoard.platinum,
				JSON.stringify(hoard.gems), JSON.stringify(hoard.jewelry),
				JSON.stringify(hoard.magic_items), hoard.total_gp_value,
				1 if hoard.is_hidden else 0,
				hoard.cell_x, hoard.cell_y, hoard.cell_z, ct,
				1 if hoard.is_locked else 0,
				1 if hoard.is_trapped else 0,
			])
		if not ok:
			push_error("DungeonGeneratorRepository: treasure_hoards insert failed (floor %s, room %d)." % [floor_id, hoard.room_id])
			return false
	return true


## Insert all key items for the dungeon. Caller holds the transaction.
## [param index_to_floor_id] maps floor level_number (int) -> floor_id (String).
static func _insert_key_items(dungeon_id: String, keys: Array, index_to_floor_id: Dictionary) -> bool:
	var db = CampaignRepository.db
	for k in keys:
		var key: KeyItemData = k
		var pk: String = CampaignRepository.generate_id()

		# Resolve floor indices to TEXT floor ids.
		var opens_floor_id: String = str(index_to_floor_id.get(key.opens_door_floor_index, ""))
		if opens_floor_id.is_empty():
			push_error("DungeonGeneratorRepository: key_items insert — opens_door_floor_index %d not in index_to_floor_id." % key.opens_door_floor_index)
			return false
		var placed_floor_id: Variant = null
		if key.placed_on_floor_index >= 0:
			var pf_str: String = str(index_to_floor_id.get(key.placed_on_floor_index, ""))
			if pf_str.is_empty():
				push_error("DungeonGeneratorRepository: key_items insert — placed_on_floor_index %d not in index_to_floor_id." % key.placed_on_floor_index)
				return false
			placed_floor_id = pf_str

		# placed_in_room_id: NULL when < 0 (loose / unplaced).
		var room_id_val: Variant = null if key.placed_in_room_id < 0 else str(key.placed_in_room_id)

		var ok: bool = db.query_with_bindings(
			"""INSERT INTO key_items
				(id, dungeon_id, opens_door_floor_id, opens_door_position_x,
				 opens_door_position_y, placed_in, placed_in_room_id, placed_on_floor_id)
			   VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
			[
				pk, dungeon_id, opens_floor_id,
				key.opens_door_position.x, key.opens_door_position.y,
				key.placed_in, room_id_val, placed_floor_id,
			])
		if not ok:
			push_error("DungeonGeneratorRepository: key_items insert failed (dungeon %s)." % dungeon_id)
			return false
	return true


# ---------------------------------------------------------------------------
# DG-V1.D load helpers
# ---------------------------------------------------------------------------

## Load all monster groups for [param floor_id] into an Array[MonsterGroupData].
## [param floor_index] is set on each returned object (= level_number of the floor).
static func _load_monster_groups(floor_id: String, floor_index: int) -> Array[MonsterGroupData]:
	var out: Array[MonsterGroupData] = []
	var db = CampaignRepository.db
	if not db.query_with_bindings(
			"SELECT * FROM monster_groups WHERE floor_id = ?", [floor_id]):
		return out
	for row in db.query_result:
		out.append(_row_to_monster_group(row, floor_index))
	return out


## Load all treasure hoards for [param floor_id] into an Array[TreasureHoardData].
static func _load_treasure_hoards(floor_id: String, floor_index: int) -> Array[TreasureHoardData]:
	var out: Array[TreasureHoardData] = []
	var db = CampaignRepository.db
	if not db.query_with_bindings(
			"SELECT * FROM treasure_hoards WHERE floor_id = ?", [floor_id]):
		return out
	for row in db.query_result:
		out.append(_row_to_treasure_hoard(row, floor_index))
	return out


## Load a room's UNLOOTED treasure hoards for runtime loot consumption. Scoped by
## floor_id + room_id (room_id is unique within a floor, not across a dungeon).
## Sets the hoard primary key (`id`) on each returned object so the caller can
## pass it to mark_hoard_looted(). Migration 135 adds the is_looted column.
static func get_unlooted_treasure_hoards_for_room(floor_id: String, room_id: int) -> Array[TreasureHoardData]:
	var out: Array[TreasureHoardData] = []
	var db = CampaignRepository.db
	if not db.query_with_bindings(
			"SELECT * FROM treasure_hoards WHERE floor_id = ? AND room_id = ? AND is_looted = 0",
			[floor_id, str(room_id)]):
		return out
	for row in db.query_result:
		var h := _row_to_treasure_hoard(row, -1)
		h.id = str(row.get("id", ""))
		out.append(h)
	return out


## Load the single UNLOOTED hoard placed at [param cell] on [param floor_id], or
## null when there's nothing to materialize there. Used by the cell-based loot
## flow (`TreasureLootService.materialize_hoard_cell` — see
## gdd-treasure-item-backing.md §15). The placement service guarantees at most
## one hoard per (floor_id, cell_x, cell_y, cell_z); if the DB has multiple
## (would indicate a generation bug), the first row is returned and the rest
## are warned about.
##
## Sets `id` on the returned hoard so the caller can hand it to
## `mark_hoard_looted()` after materialization.
static func get_unlooted_treasure_hoard_at_cell(
		floor_id: String, cell: Vector3i) -> TreasureHoardData:
	var db = CampaignRepository.db
	if not db.query_with_bindings(
			"SELECT * FROM treasure_hoards WHERE floor_id = ? AND cell_x = ? AND cell_y = ? AND cell_z = ? AND is_looted = 0",
			[floor_id, cell.x, cell.y, cell.z]):
		return null
	if db.query_result.is_empty():
		return null
	if db.query_result.size() > 1:
		push_warning("DungeonGeneratorRepository.get_unlooted_treasure_hoard_at_cell: %d hoards at floor %s cell %s (expected <=1)"
			% [db.query_result.size(), floor_id, str(cell)])
	var row: Dictionary = db.query_result[0]
	var h := _row_to_treasure_hoard(row, -1)
	h.id = str(row.get("id", ""))
	return h


## Mark a treasure hoard as claimed so it is not handed out again (Migration 135).
static func mark_hoard_looted(hoard_id: String) -> bool:
	if hoard_id.is_empty():
		return false
	return CampaignRepository.db.query_with_bindings(
		"UPDATE treasure_hoards SET is_looted = 1 WHERE id = ?", [hoard_id])


# ---------------------------------------------------------------------------
# Row → object (DG-V1.D types)
# ---------------------------------------------------------------------------

static func _row_to_monster_group(row: Dictionary, floor_index: int) -> MonsterGroupData:
	var g := MonsterGroupData.new()
	g.floor_index = floor_index
	g.room_id = int(str(row["room_id"]))
	g.monster_name = str(row["monster_name"])
	g.monster_xp_each = int(row["monster_xp_each"])
	g.number_appearing = int(row["number_appearing"])
	g.hd = str(row["hd"])
	var ac_parsed: Variant = JSON.parse_string(str(row["associated_creatures"]))
	g.associated_creatures = ac_parsed if ac_parsed is Array else []
	g.is_lair = int(row["is_lair"]) == 1
	g.morale = int(row["morale"])
	g.alignment = str(row["alignment"])
	# treasure_type_letter: NULL stored as null; convert back to "" for the type.
	var ttl_raw = row["treasure_type_letter"]
	g.treasure_type_letter = "" if ttl_raw == null else str(ttl_raw)
	var inv_parsed: Variant = JSON.parse_string(str(row["initial_inventory"]))
	g.initial_inventory = inv_parsed if inv_parsed is Array else []
	return g


static func _row_to_treasure_hoard(row: Dictionary, floor_index: int) -> TreasureHoardData:
	var h := TreasureHoardData.new()
	h.floor_index = floor_index
	h.room_id = int(str(row["room_id"]))
	h.source = str(row["source"])
	var ttl_raw = row["treasure_type_letter"]
	h.treasure_type_letter = "" if ttl_raw == null else str(ttl_raw)
	h.copper = int(row["copper"])
	h.silver = int(row["silver"])
	h.electrum = int(row["electrum"])
	h.gold = int(row["gold"])
	h.platinum = int(row["platinum"])
	var gems_parsed: Variant = JSON.parse_string(str(row["gems"]))
	h.gems = gems_parsed if gems_parsed is Array else []
	var jew_parsed: Variant = JSON.parse_string(str(row["jewelry"]))
	h.jewelry = jew_parsed if jew_parsed is Array else []
	var mi_parsed: Variant = JSON.parse_string(str(row["magic_items"]))
	h.magic_items = mi_parsed if mi_parsed is Array else []
	h.total_gp_value = int(row["total_gp_value"])
	h.is_hidden = int(row["is_hidden"]) == 1
	# Migration 137 — cell + container placement.
	# Defensive .get() so a load from a pre-137 row (impossible in normal flow
	# since migrations run before app code, but cheap safety) defaults to the
	# in-memory "not placed" sentinels and falls through unchanged.
	h.cell_x = int(row.get("cell_x", -1))
	h.cell_y = int(row.get("cell_y", -1))
	h.cell_z = int(row.get("cell_z", 0))
	var ct_raw = row.get("container_type", null)
	h.container_type = "" if ct_raw == null else str(ct_raw)
	h.is_locked = int(row.get("is_locked", 0)) == 1
	h.is_trapped = int(row.get("is_trapped", 0)) == 1
	return h


## Reconstruct a KeyItemData from a key_items row.
## [param floor_level] maps floor_id (String) -> level_number (int).
static func _row_to_key_item(row: Dictionary, floor_level: Dictionary) -> KeyItemData:
	var k := KeyItemData.new()

	var opens_fid: String = str(row["opens_door_floor_id"])
	k.opens_door_floor_index = floor_level.get(opens_fid, -1)
	k.opens_door_position = Vector2i(
		int(row["opens_door_position_x"]),
		int(row["opens_door_position_y"]))
	k.placed_in = str(row["placed_in"])

	var room_id_raw = row["placed_in_room_id"]
	k.placed_in_room_id = -1 if room_id_raw == null else int(str(room_id_raw))

	var placed_fid_raw = row["placed_on_floor_id"]
	if placed_fid_raw == null:
		k.placed_on_floor_index = -1
	else:
		k.placed_on_floor_index = floor_level.get(str(placed_fid_raw), -1)

	return k


# ---------------------------------------------------------------------------
# Row → object
# ---------------------------------------------------------------------------

static func _row_to_room(row: Dictionary) -> DungeonRoomData:
	var room := DungeonRoomData.new()
	room.id = int(row["room_id_in_floor"])
	room.bounds = Rect2i(
		int(row["bounds_x"]), int(row["bounds_y"]),
		int(row["bounds_w"]), int(row["bounds_h"]))
	room.area_sqft = int(row["area_sqft"])
	room.center = Vector2i(int(row["center_x"]), int(row["center_y"]))
	room.original_purpose = str(row["original_purpose"])
	room.current_purpose = str(row["current_purpose"])
	# Recompute cells from bounds (V1 rooms are rectangles). V2 irregular rooms
	# would need explicit cell storage or a grid scan; flagged for then.
	var b: Rect2i = room.bounds
	for x in range(b.position.x, b.position.x + b.size.x):
		for y in range(b.position.y, b.position.y + b.size.y):
			room.cells.append(Vector2i(x, y))
	return room


static func _row_to_door(row: Dictionary) -> DungeonDoorData:
	var door := DungeonDoorData.new()
	door.position = Vector2i(int(row["position_x"]), int(row["position_y"]))
	door.type = str(row["type"])
	door.is_secret = int(row["is_secret"]) == 1
	door.door_material = str(row["door_material"])
	door.is_evil = int(row["is_evil"]) == 1
	var connects_parsed: Variant = JSON.parse_string(str(row["connects_room_ids"]))
	var connects: Array[int] = []
	if connects_parsed is Array:
		for v in connects_parsed:
			connects.append(int(v))
	door.connects = connects
	return door


static func _attach_doors_to_rooms(rooms: Array[DungeonRoomData], doors: Array[DungeonDoorData]) -> void:
	for d in doors:
		for room_id in d.connects:
			if room_id < 0:
				continue
			for r in rooms:
				if r.id == room_id:
					r.doors.append(d)
					break


# ---------------------------------------------------------------------------
# Cell + stair serialization
# ---------------------------------------------------------------------------

static func _serialize_cells(cells: Array) -> String:
	# Positional 2D array: cells[x][y] → [tf, p, los, ds, dd, rid, corr, elev].
	var grid: Array = []
	for col in cells:
		var ser_col: Array = []
		for cell in col:
			var c: DungeonCellData = cell
			ser_col.append([
				c.terrain_feature, c.passable, c.blocks_los, c.door_state,
				c.door_detected, c.room_id, c.is_corridor, c.elevation,
			])
		grid.append(ser_col)
	return JSON.stringify(grid)


static func _deserialize_cells(json_text: String, grid_width: int, grid_height: int) -> Array[Array]:
	var out: Array[Array] = []
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Array):
		return out
	var grid: Array = parsed
	for x in grid.size():
		var col_in: Array = grid[x]
		var col_out: Array[DungeonCellData] = []
		for y in col_in.size():
			var arr: Array = col_in[y]
			var c := DungeonCellData.new()
			c.terrain_feature = str(arr[0])
			c.passable = bool(arr[1])
			c.blocks_los = bool(arr[2])
			c.door_state = str(arr[3])
			c.door_detected = bool(arr[4])
			c.room_id = int(arr[5])
			c.is_corridor = bool(arr[6])
			c.elevation = int(arr[7])
			col_out.append(c)
		out.append(col_out)
	return out


static func _serialize_stairs(stairs: Array) -> String:
	var arr: Array = []
	for s in stairs:
		var stair: DungeonStairData = s
		arr.append({
			"x": stair.position.x,
			"y": stair.position.y,
			"dir": stair.direction,
			"level": stair.connects_to_level,
			"entrance": stair.is_entrance_stair,
		})
	return JSON.stringify(arr)


static func _deserialize_stairs(json_text: String) -> Array[DungeonStairData]:
	var out: Array[DungeonStairData] = []
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Array):
		return out
	for entry in parsed:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		var s := DungeonStairData.new()
		s.position = Vector2i(int(d.get("x", -1)), int(d.get("y", -1)))
		s.direction = str(d.get("dir", DungeonStairData.DIRECTION_DOWN))
		s.connects_to_level = int(d.get("level", -1))
		s.is_entrance_stair = bool(d.get("entrance", false))
		out.append(s)
	return out


# ---------------------------------------------------------------------------
# Field helpers
# ---------------------------------------------------------------------------

static func _door_state_of(door: DungeonDoorData) -> String:
	# DungeonDoorData has no door_state field; the runtime state is derived
	# from type at rasterization. Store the post-generation initial state so a
	# round-trip preserves it: locked/trapped → "locked", portcullis/unlocked
	# → "closed", arch → "open".
	match door.type:
		DungeonDoorData.TYPE_ARCH:
			return "open"
		DungeonDoorData.TYPE_LOCKED, DungeonDoorData.TYPE_TRAPPED:
			return "locked"
		_:
			return "closed"
