extends "res://tests/test_suite_base.gd"

## DG-C3D.F.2c cutover gate (a) — single-band byte-identity.
##
## A fixed-seed single-FLOOR dungeon must generate IDENTICAL content before
## and after the composed-pipeline cutover: same layout cells, rooms, doors,
## stairs, stocking rolls, monster groups, treasure hoards (including cell
## placement), and key items. The voxel GEOMETRY changes (one contiguous
## volume instead of stitched floors); the CONTENT must not.
##
## The golden fixture (tests/fixtures/dungeon_cutover_golden_4242.txt) was
## captured from the PRE-flip legacy pipeline via
## res://tests/tools/dungeon_golden_capture.tscn on this exact seed. The
## fingerprint canonicalizer excludes every randomly-generated TEXT id
## (dungeon/group/hoard/key ids come from CampaignRepository.generate_id(),
## which is intentionally non-seeded) and compares pure content.
##
## The comparison uses the kl-NORMALIZED fingerprint (include_kl = false):
## key/lever PLACEMENT re-derives under the composed 3D walker — RULED FINE
## by Jedidiah 2026-07-13 (identical placements were never the intent, so
## long as keys/levers stay reachable; reachability is what
## validate_composed_solvability gates). Everything else — layout cells,
## rooms, doors, stocking rolls, monster groups, treasure contents + cell
## placement, the SET of keyed doors — was verified byte-identical on 29/30
## sweep seeds at the cutover (the 30th differed in one door's §10.4
## downgrade outcome; seed 1515).


## Fixed request the golden was captured against (single floor, tier 2, small).
const GOLDEN_SEED: int = 4242
const GOLDEN_FIXTURE: String = "res://tests/fixtures/dungeon_cutover_golden_4242.txt"


func run_all_tests() -> void:
	test_single_band_content_identity()
	test_single_band_regeneration_is_self_identical()
	test_single_band_composed_output_contract()
	test_multi_band_no_atrium_full_identity()
	test_atrium_balcony_zones_stocked()
	if not has_failures():
		print("DungeonCutoverIdentity: all tests passed.")


## DG-C3D.F.2d gate: a multi-band dungeon WITHOUT atrium balcony zones must
## generate FULL-fingerprint-identical (key/lever placements included) across
## the balcony-stocking version bump — the balcony stream draws zero values
## for it. Golden captured on the v1 (pre-F.2d) engine; verified byte-equal
## on 9/9 no-atrium sweep seeds at the bump.
func test_multi_band_no_atrium_full_identity() -> void:
	var golden_file := FileAccess.open("res://tests/fixtures/dungeon_cutover_golden_3floor_11.txt", FileAccess.READ)
	check(golden_file != null, "3-floor golden fixture opens")
	if golden_file == null:
		return
	var golden: String = golden_file.get_as_text().replace("\r", "").strip_edges()
	golden_file.close()

	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = 1
	req.floor_count = 3
	req.entrance_floor_index = 1
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "small"
	req.seed = 11
	req.persist = false
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	check(result.success, "seed-11 3-floor generates (errors: %s)" % str(result.errors))
	for z in result.zones:
		check((z as RoomZone).zone_index == 0, "seed 11 has no balcony zones (fixture premise)")
	var text: String = content_fingerprint(result, true).strip_edges()
	var ok: bool = text == golden
	check(ok, "no-atrium 3-floor FULL fingerprint matches the pre-F.2d golden (md5 %s vs %s)"
		% [text.md5_text(), golden.md5_text()])
	if not ok:
		_print_first_divergence(golden, text)


## DG-C3D.F.2d: an atrium dungeon's balcony zones are stocked — the zone
## carries contents, any group it owns sits on the ZONE's band layout with
## the room's GLOBAL id + the zone's index, and any placed hoard sits at the
## zone band's WALK level (seed 88 rolls a balcony Morlock lair + sack hoard
## at z=-2; the atrium rollup composes the room purpose).
func test_atrium_balcony_zones_stocked() -> void:
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = 1
	req.floor_count = 3
	req.entrance_floor_index = 1
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "small"
	req.seed = 88
	req.persist = false
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	check(result.success, "seed-88 atrium dungeon generates (errors: %s)" % str(result.errors))

	var balcony: RoomZone = null
	for z in result.zones:
		if (z as RoomZone).zone_index >= 1:
			balcony = z
			break
	check(balcony != null, "seed 88 has a balcony zone (fixture premise)")
	if balcony == null:
		return
	check(balcony.contents_kind != "", "balcony zone is stocked (contents_kind set)")

	if balcony.monster_group_id != "":
		var band_layout: DungeonLayout = result.floors[balcony.band - 1]
		var found: MonsterGroupData = null
		for g in band_layout.monster_groups:
			if (g as MonsterGroupData).id == balcony.monster_group_id:
				found = g
				break
		check(found != null, "balcony group lives on the ZONE's band layout (band %d)" % balcony.band)
		if found != null:
			check(found.room_id == balcony.room_id,
				"balcony group carries the GLOBAL room id (%d)" % balcony.room_id)
			check(found.zone_index == balcony.zone_index,
				"balcony group carries the zone index (%d)" % balcony.zone_index)

	if balcony.treasure_hoard_id != "":
		var band_layout2: DungeonLayout = result.floors[balcony.band - 1]
		for h in band_layout2.treasure_hoards:
			var hoard: TreasureHoardData = h
			if hoard.room_id != balcony.room_id or hoard.cell_x < 0:
				continue
			var expected_walk: int = 2 * (req.entrance_floor_index - balcony.band)
			check(hoard.cell_z == expected_walk,
				"balcony hoard placed at the zone band's walk level (%d, got %d)" % [expected_walk, hoard.cell_z])

	# The atrium room's LLM-facing purpose composes the balcony clause.
	var home_slot: int = int(balcony.room_id / DungeonVolumeComposer.ROOM_ID_STRIDE)
	for r in result.floors[home_slot].rooms:
		var room: DungeonRoomData = r
		if room.id == balcony.room_id % DungeonVolumeComposer.ROOM_ID_STRIDE:
			check(room.current_purpose.contains(";"),
				"atrium room purpose composes the balcony clause (got '%s')" % room.current_purpose)
			break


## The gate: post-flip normalized content fingerprint == the pre-flip golden.
func test_single_band_content_identity() -> void:
	var golden_file := FileAccess.open(GOLDEN_FIXTURE, FileAccess.READ)
	check(golden_file != null, "golden fixture %s opens" % GOLDEN_FIXTURE)
	if golden_file == null:
		return
	var golden: String = golden_file.get_as_text().replace("\r", "").strip_edges()
	golden_file.close()

	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(_golden_request())
	check(result.success, "golden-seed dungeon generates (errors: %s)" % str(result.errors))
	var text: String = content_fingerprint(result, false).strip_edges()
	var ok: bool = text == golden
	check(ok, "single-band normalized content fingerprint matches the pre-flip golden (md5 %s vs %s)"
		% [text.md5_text(), golden.md5_text()])
	if not ok:
		_print_first_divergence(golden, text)


## Same seed twice through the CURRENT pipeline → identical content INCLUDING
## key/lever placements (the V1 determinism guarantee carried through the
## composed path — the kl residual re-derives, but deterministically).
func test_single_band_regeneration_is_self_identical() -> void:
	var r1: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(_golden_request())
	var r2: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(_golden_request())
	check(content_fingerprint(r1) == content_fingerprint(r2),
		"same seed generates identical content twice")


## The composed result contract the fixture service persists: one contiguous
## volume, an entry at the entrance band's walk level 0, one main zone per
## chamber room, no stairwells for a single band.
func test_single_band_composed_output_contract() -> void:
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(_golden_request())
	check(result.composed_volume != null, "composed_volume is set on the result")
	if result.composed_volume == null:
		return
	check(result.composed_volume.entry_pos.z == 0,
		"single-band entry sits at walk level 0 (got z=%d)" % result.composed_volume.entry_pos.z)
	check(result.stairwells.is_empty(), "single-band dungeon has no stairwells")
	var chamber_count: int = 0
	for room in result.floors[0].rooms:
		if (room as DungeonRoomData).kind != DungeonRoomData.KIND_CIRCULATION:
			chamber_count += 1
	check(result.zones.size() == chamber_count,
		"one zone per chamber room (%d zones vs %d chambers)" % [result.zones.size(), chamber_count])
	for z in result.zones:
		check((z as RoomZone).zone_index == 0, "single-band zones are all main (zone 0)")
	var entry_cell: VoxelCell = result.composed_volume.get_cell(result.composed_volume.entry_pos)
	check(entry_cell.solidity == "air" and entry_cell.floor_type != "none",
		"entry cell is standable in the composed volume")


func _golden_request() -> DungeonGeneratorRequestV1:
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = 2
	req.floor_count = 1
	req.entrance_floor_index = 1
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "small"
	req.seed = GOLDEN_SEED
	req.persist = false
	return req


func _print_first_divergence(golden: String, actual: String) -> void:
	var g_lines: PackedStringArray = golden.split("\n")
	var a_lines: PackedStringArray = actual.split("\n")
	for i in range(mini(g_lines.size(), a_lines.size())):
		if g_lines[i] != a_lines[i]:
			print("FINGERPRINT DIVERGES at line %d:\n  golden: %s\n  actual: %s" % [i, g_lines[i], a_lines[i]])
			return
	print("FINGERPRINT DIVERGES in line count: golden %d vs actual %d" % [g_lines.size(), a_lines.size()])


# ---------------------------------------------------------------------------
# Canonical content fingerprint (shared with tests/tools/dungeon_golden_capture.gd)
# ---------------------------------------------------------------------------

## Serialize every piece of CONTENT the cutover must preserve, in a canonical
## order, excluding randomly-generated TEXT ids (linkage is captured as
## presence/embedding instead: room->group/hoard back-links become booleans,
## key embedding shows as inventory item_type counts).
##
## [param include_kl]: when false, key/lever PLACEMENT artifacts are
## normalized out — key placed-rooms/zones, wired-lever cells + their layout
## terrain stamps, finalize-forced hoards (unplaced lair hoards), and "key"
## inventory embeddings. The SET of keyed doors and every door's hardware
## (type / secret / material) stay IN — those are layout+stocking-determined.
## Rationale: the composed key/lever placer walks the real 3D movement graph,
## so its discovery order (and thus which candidate zone each kl-stream draw
## selects) legitimately differs from the legacy 2D BFS; the kl-stream DRAWS
## are preserved, the selections re-derive. See the DG-C3D.F.2c build-log
## entry ([NEEDS-JEDIDIAH] residual).
static func content_fingerprint(result: DungeonGeneratorResultV1, include_kl: bool = true) -> String:
	var lines: Array[String] = []
	lines.append("success=%s floors=%d keys=%d" % [str(result.success), result.floors.size(), result.key_items.size()])

	for fl in result.floors:
		var layout: DungeonLayout = fl
		lines.append("floor=%d tier=%d entrance=%s grid=%dx%d is_entrance=%s type=%s size=%s" % [
			layout.level_number, layout.floor_tier, str(layout.entrance),
			layout.grid_width, layout.grid_height, str(layout.is_entrance_floor),
			layout.dungeon_type, layout.dungeon_size])

		# Cell grid — every field the repository persists (cells_json parity).
		# kl-normalized mode strips lever terrain stamps (wired-lever cells are
		# a kl-placement artifact).
		var cell_buf: String = ""
		for x in range(layout.grid_width):
			for y in range(layout.grid_height):
				var c: DungeonCellData = layout.cells[x][y]
				var tf: String = c.terrain_feature
				if not include_kl and tf.begins_with("lever_portcullis_"):
					tf = DungeonCellData.FEATURE_OPEN
				cell_buf += "%s|%s|%s|%s|%s|%d|%s|%d;" % [
					tf, str(c.passable), str(c.blocks_los),
					c.door_state, str(c.door_detected), c.room_id,
					str(c.is_corridor), c.elevation]
		lines.append("cells_md5=%s" % cell_buf.md5_text())

		# Placed-hoard presence per room (kl-normalized rooms use this instead
		# of the treasure_hoard_id back-link, which finalize-forced hoards flip).
		var room_has_placed_hoard: Dictionary = {}
		for h in layout.treasure_hoards:
			if (h as TreasureHoardData).cell_x >= 0:
				room_has_placed_hoard[(h as TreasureHoardData).room_id] = true

		# Rooms sorted by local id.
		var rooms: Array = layout.rooms.duplicate()
		rooms.sort_custom(func(a, b): return (a as DungeonRoomData).id < (b as DungeonRoomData).id)
		for r in rooms:
			var room: DungeonRoomData = r
			var th_flag: bool = room.treasure_hoard_id != "" if include_kl \
				else room_has_placed_hoard.has(room.id)
			lines.append("room=%d kind=%s bounds=%s contents=%s purpose=%s|%s mg=%s th=%s" % [
				room.id, room.kind, str(room.bounds), room.contents_kind,
				room.original_purpose, room.current_purpose,
				str(room.monster_group_id != ""), str(th_flag)])

		# Monster groups sorted by (room_id, name).
		var groups: Array = layout.monster_groups.duplicate()
		groups.sort_custom(func(a, b):
			var ga: MonsterGroupData = a
			var gb: MonsterGroupData = b
			if ga.room_id != gb.room_id:
				return ga.room_id < gb.room_id
			return ga.monster_name < gb.monster_name)
		for g in groups:
			var grp: MonsterGroupData = g
			var inv_types: Array[String] = []
			for item in grp.initial_inventory:
				var it: String = str((item as Dictionary).get("item_type", "?"))
				if not include_kl and it == "key":
					continue  # key embedding is a kl-placement artifact
				inv_types.append(it)
			inv_types.sort()
			var assoc: Array[String] = []
			for a in grp.associated_creatures:
				var ad: Dictionary = a
				assoc.append("%s x%d" % [str(ad.get("name", "?")), int(ad.get("number_appearing", 0))])
			# zone_index is composed-model metadata (the flip stamps 0 where the
			# legacy pipeline left -1) — new bookkeeping, not content; the
			# normalized variant omits it.
			var zone_part: String = " zone=%d" % grp.zone_index if include_kl else ""
			lines.append("group room=%d%s name=%s n=%d xp=%d hd=%s lair=%s morale=%d align=%s ttl=%s assoc=%s inv=%s" % [
				grp.room_id, zone_part, grp.monster_name, grp.number_appearing,
				grp.monster_xp_each, grp.hd, str(grp.is_lair), grp.morale,
				grp.alignment, grp.treasure_type_letter, str(assoc), str(inv_types)])

		# Treasure hoards sorted by (room_id, source, cell, gp). kl-normalized
		# mode skips UNPLACED hoards (cell_x == -1): the only unplaced hoards in
		# practice are the type-"A" hoards finalize_key_placements forces into
		# empty key rooms — a kl-placement artifact.
		var hoards: Array = []
		for h in layout.treasure_hoards:
			if not include_kl and (h as TreasureHoardData).cell_x < 0:
				continue
			hoards.append(h)
		hoards.sort_custom(func(a, b):
			var ka: String = _hoard_sort_key(a)
			var kb: String = _hoard_sort_key(b)
			return ka < kb)
		for h in hoards:
			var hoard: TreasureHoardData = h
			lines.append("hoard room=%d src=%s ttl=%s coins=%d/%d/%d/%d/%d gems=%d jewelry=%d magic=%d gp=%d hidden=%s locked=%s trapped=%s cell=%d,%d,%d container=%s" % [
				hoard.room_id, hoard.source, hoard.treasure_type_letter,
				hoard.copper, hoard.silver, hoard.electrum, hoard.gold, hoard.platinum,
				hoard.gems.size(), hoard.jewelry.size(), hoard.magic_items.size(),
				hoard.total_gp_value, str(hoard.is_hidden), str(hoard.is_locked),
				str(hoard.is_trapped), hoard.cell_x, hoard.cell_y, hoard.cell_z,
				hoard.container_type])

		# Doors sorted by (x, y).
		var doors: Array = layout.doors.duplicate()
		doors.sort_custom(func(a, b):
			var da: DungeonDoorData = a
			var db: DungeonDoorData = b
			if da.position.x != db.position.x:
				return da.position.x < db.position.x
			return da.position.y < db.position.y)
		for d in doors:
			var door: DungeonDoorData = d
			var connects: Array = door.connects.duplicate()
			connects.sort()
			var lever_part: String = " lever=%s" % str(door.wired_lever_position) if include_kl else ""
			lines.append("door pos=%s type=%s secret=%s material=%s evil=%s connects=%s%s" % [
				str(door.position), door.type, str(door.is_secret), door.door_material,
				str(door.is_evil), str(connects), lever_part])

		# Stairs sorted by (x, y).
		var stairs: Array = layout.stairs.duplicate()
		stairs.sort_custom(func(a, b):
			var sa: DungeonStairData = a
			var sb: DungeonStairData = b
			if sa.position.x != sb.position.x:
				return sa.position.x < sb.position.x
			return sa.position.y < sb.position.y)
		for s in stairs:
			var stair: DungeonStairData = s
			lines.append("stair pos=%s dir=%s connects=%d entrance=%s" % [
				str(stair.position), stair.direction, stair.connects_to_level,
				str(stair.is_entrance_stair)])

	# Key items sorted by (opens floor, opens x, opens y).
	var keys: Array = result.key_items.duplicate()
	keys.sort_custom(func(a, b):
		var ka: KeyItemData = a
		var kb: KeyItemData = b
		if ka.opens_door_floor_index != kb.opens_door_floor_index:
			return ka.opens_door_floor_index < kb.opens_door_floor_index
		if ka.opens_door_position.x != kb.opens_door_position.x:
			return ka.opens_door_position.x < kb.opens_door_position.x
		return ka.opens_door_position.y < kb.opens_door_position.y)
	for k in keys:
		var key: KeyItemData = k
		if include_kl:
			lines.append("key opens=%d:%s placed_floor=%d placed_room=%d placed_in=%s zone=%d" % [
				key.opens_door_floor_index, str(key.opens_door_position),
				key.placed_on_floor_index, key.placed_in_room_id, key.placed_in,
				key.placed_in_zone_index])
		else:
			# The SET of keyed doors is layout+stocking-determined and must be
			# preserved; only the key's placement re-derives.
			lines.append("key opens=%d:%s" % [
				key.opens_door_floor_index, str(key.opens_door_position)])

	return "\n".join(lines)


static func _hoard_sort_key(h) -> String:
	var hoard: TreasureHoardData = h
	return "%06d|%s|%04d,%04d,%04d|%08d" % [
		hoard.room_id + 1000, hoard.source,
		hoard.cell_x + 100, hoard.cell_y + 100, hoard.cell_z + 100,
		hoard.total_gp_value]
