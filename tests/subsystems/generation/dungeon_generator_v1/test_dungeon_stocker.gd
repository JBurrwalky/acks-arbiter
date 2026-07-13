extends "res://tests/test_suite_base.gd"

## Tests for DungeonStocker.stock_floor() (gdd-dungeon-generator-v1.md §11).
##
## Strategy: generate a real DungeonLayout via DungeonLayoutGenerator, load a
## DungeonDataLoader (res://data/dungeon_generator/), and construct a minimal
## MonsterRegistry. Then call DungeonStocker.stock_floor() with a seeded RNG and
## assert structural post-conditions.
##
## NOTE: DungeonEncounterRoller, DungeonTreasureResolver, and MonsterRegistry are
## sibling DG-V1.D components built in parallel — this test file codes against their
## declared signatures; all tests require those siblings to be present at runtime.


var _loader: DungeonDataLoader
var _registry: MonsterRegistry
var _layout: DungeonLayout
var _rng: RandomNumberGenerator


func run_all_tests() -> void:
	# Setup shared state — bail early if data load fails.
	_loader = DungeonDataLoader.new()
	if not _loader.load_all():
		push_error("DungeonStocker tests: DungeonDataLoader.load_all() failed — skipping suite.")
		return

	_registry = MonsterRegistry.new()

	var req := DungeonLayoutRequest.new()
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "small"
	req.level_number = 1
	req.floor_tier = 2
	req.seed = 42
	req.stairs_up = 1
	req.stairs_down = 1
	req.is_entrance_floor = true
	_layout = DungeonLayoutGenerator.generate(req)

	if _layout == null or _layout.rooms.is_empty():
		push_error("DungeonStocker tests: DungeonLayoutGenerator.generate() returned null or 0 rooms — skipping suite.")
		return

	_rng = RandomNumberGenerator.new()
	_rng.seed = 12345

	# Run stock_floor once; all subsequent tests inspect the same stocked layout.
	DungeonStocker.stock_floor(_layout, _loader, _registry, _rng)

	test_all_rooms_have_contents_kind()
	test_monster_rooms_have_group_id()
	test_trap_placeholder_rooms_have_secret_door()
	test_unique_placeholder_rooms_have_monster_group_id()
	test_treasure_hoard_ids_match_layout_array()
	test_monster_group_ids_match_layout_array()
	test_all_rooms_have_current_purpose()
	test_special_value_roll_ranges()
	test_special_treasure_creates_lair_hoard_when_none()
	test_special_treasure_folds_into_existing_lair_hoard()
	test_special_treasure_noop_when_empty_or_zero_chance()
	test_ant_giant_catalog_treasure_corrected()
	test_animal_treasure_corrections()
	# Cell-based treasure placement (Pass D) — gdd-treasure-item-backing.md §15.
	test_all_placed_hoards_have_valid_cell()
	test_all_placed_hoards_have_valid_container_type()
	test_placed_hoards_cell_is_inside_room()
	test_trap_room_hoards_are_locked_chests()
	test_pile_hoards_are_never_locked_or_trapped()
	test_traps_unavailable_no_hoard_is_trapped()
	# DG-C3D.F.2a — project per-band stocking onto composed zones.
	test_map_band_stocking_to_zones()
	test_stock_floor_skips_circulation_rooms()
	# DG-C3D.F.2d — balcony/gallery zone stocking.
	test_balcony_stream_zero_draw_without_zones()
	test_balcony_zone_stocks_on_zone_band_layout()
	test_balcony_doorless_trap_demotes_to_empty()
	test_balcony_doorless_trap_swaps_to_doored_zone()

	if not has_failures():
		print("DungeonStocker: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## Every room must have a non-empty contents_kind after stocking.
func test_all_rooms_have_contents_kind() -> void:
	var valid_kinds: Array[String] = [
		"empty", "monster", "monster_lair", "trap_placeholder", "unique_placeholder",
	]
	for room in _layout.rooms:
		check(room.contents_kind in valid_kinds,
			"room %d contents_kind '%s' is not a valid kind" % [room.id, room.contents_kind])


## Rooms classified as "monster" or "monster_lair" must have a non-empty monster_group_id.
func test_monster_rooms_have_group_id() -> void:
	for room in _layout.rooms:
		if room.contents_kind in ["monster", "monster_lair"]:
			check(room.monster_group_id != "",
				"room %d (%s) should have monster_group_id set" % [room.id, room.contents_kind])


## trap_placeholder rooms must be gated by AT LEAST ONE bordering door with
## is_secret == true AND type in [LOCKED, TRAPPED] (§11.4 fallback / §14.1.6).
## Exactly-one is the stocker's per-room target, but the layout generator can
## independently place extra secret+locked doors, so >= 1 is the real invariant.
func test_trap_placeholder_rooms_have_secret_door() -> void:
	for room in _layout.rooms:
		if room.contents_kind != "trap_placeholder":
			continue
		if room.doors.is_empty():
			# Edge case: a doorless room cannot be gated (the stocker demotes it to
			# empty); navigability prevents doorless reachable rooms anyway.
			continue
		var qualifying: int = 0
		for door in room.doors:
			if door.is_secret and (
				door.type == DungeonDoorData.TYPE_LOCKED
				or door.type == DungeonDoorData.TYPE_TRAPPED
			):
				qualifying += 1
		check(qualifying >= 1,
			"trap_placeholder room %d should have at least 1 secret+locked/trapped bordering door, got %d"
				% [room.id, qualifying])


## unique_placeholder rooms must have a non-empty monster_group_id per acceptance test 7.
func test_unique_placeholder_rooms_have_monster_group_id() -> void:
	for room in _layout.rooms:
		if room.contents_kind == "unique_placeholder":
			check(room.monster_group_id != "",
				"unique_placeholder room %d must have monster_group_id set" % room.id)


## Every treasure_hoard_id on a room must reference a hoard in layout.treasure_hoards.
func test_treasure_hoard_ids_match_layout_array() -> void:
	var hoard_ids: Dictionary = {}
	for hoard in _layout.treasure_hoards:
		hoard_ids[hoard.id] = true
	for room in _layout.rooms:
		if room.treasure_hoard_id == "":
			continue
		check(hoard_ids.has(room.treasure_hoard_id),
			"room %d treasure_hoard_id '%s' not found in layout.treasure_hoards"
				% [room.id, room.treasure_hoard_id])


## Every monster_group_id on a room must reference a group in layout.monster_groups.
func test_monster_group_ids_match_layout_array() -> void:
	var group_ids: Dictionary = {}
	for grp in _layout.monster_groups:
		group_ids[grp.id] = true
	for room in _layout.rooms:
		if room.monster_group_id == "":
			continue
		check(group_ids.has(room.monster_group_id),
			"room %d monster_group_id '%s' not found in layout.monster_groups"
				% [room.id, room.monster_group_id])


## Every room must have a non-empty current_purpose string after stocking (§11.6).
func test_all_rooms_have_current_purpose() -> void:
	for room in _layout.rooms:
		check(room.current_purpose != "",
			"room %d should have a non-empty current_purpose after stocking" % room.id)


# ---------------------------------------------------------------------------
# Per-monster special lair treasure (e.g. Giant Ant gold nuggets).
# ---------------------------------------------------------------------------

func test_special_value_roll_ranges() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 24680
	# "1d10x1000" -> 1000..10000 in multiples of 1000.
	for _i in 30:
		var v: int = DungeonStocker._roll_special_value("1d10x1000", rng)
		check(v >= 1000 and v <= 10000 and v % 1000 == 0,
			"1d10x1000 must be 1000..10000 in 1000s, got %d" % v)
	# "2d4x100" -> 200..800.
	for _j in 20:
		var v2: int = DungeonStocker._roll_special_value("2d4x100", rng)
		check(v2 >= 200 and v2 <= 800, "2d4x100 must be 200..800, got %d" % v2)
	# Plain int, unicode '×' multiplier, empty, and unparseable.
	check(DungeonStocker._roll_special_value("5", rng) == 5, "'5' -> 5")
	var vx: int = DungeonStocker._roll_special_value("1d6×100", rng)
	check(vx >= 100 and vx <= 600, "1d6×100 (unicode ×) must be 100..600, got %d" % vx)
	check(DungeonStocker._roll_special_value("", rng) == 0, "'' -> 0")
	check(DungeonStocker._roll_special_value("garbage", rng) == 0, "unparseable -> 0")


func _make_special_group(chance: int, dice: String) -> MonsterGroupData:
	var g := MonsterGroupData.new()
	g.is_lair = true
	g.special_treasure = {"chance_pct": chance, "value_dice": dice, "denomination": "gp"}
	return g


func test_special_treasure_creates_lair_hoard_when_none() -> void:
	# Monster has a special but no lettered type: the special must CREATE a lair hoard.
	var layout := DungeonLayout.new()
	var room := DungeonRoomData.new()
	room.id = 1
	layout.rooms.append(room)
	var grp := _make_special_group(100, "1d10x1000")  # 100% -> always fires
	var rng := RandomNumberGenerator.new()
	rng.seed = 111
	DungeonStocker._apply_special_treasure(grp, room, layout, 1, rng)
	check(layout.treasure_hoards.size() == 1,
		"special-only lair must create exactly 1 hoard, got %d" % layout.treasure_hoards.size())
	if layout.treasure_hoards.size() == 1:
		var h: TreasureHoardData = layout.treasure_hoards[0]
		check(h.room_id == 1, "special hoard room_id should be 1, got %d" % h.room_id)
		check(h.gold >= 1000 and h.gold <= 10000, "special gold must be 1000..10000, got %d" % h.gold)
		check(h.total_gp_value == h.gold,
			"total_gp_value should equal the added gold (%d), got %d" % [h.gold, h.total_gp_value])
		check(room.treasure_hoard_id == h.id, "room should back-link the created hoard")


func test_special_treasure_folds_into_existing_lair_hoard() -> void:
	# A base type hoard already exists in the room: the special ADDS to it (no new hoard).
	var layout := DungeonLayout.new()
	var room := DungeonRoomData.new()
	room.id = 7
	layout.rooms.append(room)
	var base := TreasureHoardData.new()
	base.id = "base-hoard"
	base.room_id = 7
	base.source = TreasureHoardData.SOURCE_LAIR
	base.gold = 50
	base.total_gp_value = 50
	layout.treasure_hoards.append(base)
	room.treasure_hoard_id = base.id
	var grp := _make_special_group(100, "1d10x1000")
	var rng := RandomNumberGenerator.new()
	rng.seed = 222
	DungeonStocker._apply_special_treasure(grp, room, layout, 1, rng)
	check(layout.treasure_hoards.size() == 1,
		"special must fold into the existing hoard, not add one (got %d)" % layout.treasure_hoards.size())
	check(base.gold > 50, "special must add gold to the existing hoard (was 50, now %d)" % base.gold)
	check(base.total_gp_value == base.gold, "total_gp_value must track the new gold")


func test_special_treasure_noop_when_empty_or_zero_chance() -> void:
	var layout := DungeonLayout.new()
	var room := DungeonRoomData.new()
	room.id = 3
	layout.rooms.append(room)
	var rng := RandomNumberGenerator.new()
	rng.seed = 333
	# Empty spec -> no hoard.
	var g_empty := MonsterGroupData.new()
	g_empty.is_lair = true
	DungeonStocker._apply_special_treasure(g_empty, room, layout, 1, rng)
	check(layout.treasure_hoards.is_empty(), "empty special_treasure must add no hoard")
	# chance_pct 0 -> no hoard.
	var g0 := _make_special_group(0, "1d10x1000")
	DungeonStocker._apply_special_treasure(g0, room, layout, 1, rng)
	check(layout.treasure_hoards.is_empty(), "chance_pct 0 must add no hoard")


func test_ant_giant_catalog_treasure_corrected() -> void:
	# Giant Ant: treasure_type "I" (not the erroneous "U") plus the gold-nugget special.
	check(_registry.has_monster("ant_giant"), "ant_giant must exist in catalog")
	if _registry.has_monster("ant_giant"):
		var m: Dictionary = _registry.get_monster("ant_giant")
		check(str(m.get("treasure_type", "")) == "I",
			"ant_giant treasure_type should be 'I', got '%s'" % str(m.get("treasure_type")))
		var st: Dictionary = m.get("special_treasure", {})
		check(int(st.get("chance_pct", 0)) == 30,
			"ant special chance should be 30, got %s" % str(st.get("chance_pct")))
		check(str(st.get("value_dice", "")) == "1d10x1000",
			"ant special value_dice should be '1d10x1000', got '%s'" % str(st.get("value_dice")))


func test_animal_treasure_corrections() -> void:
	# Jedidiah's clarifications for the entries that carried the bogus "U" (there is no
	# treasure type U; types end at R) plus the two "Special (...)" entries.
	# expected treasure_type per id:
	var expected_type := {
		"bear_black": "None", "bear_grizzly": "None", "bear_cave": "None",
		"lion": "None", "cat_tiger": "None",
		"beetle_giant_bombardier": "None", "beetle_giant_fire": "None", "beetle_giant_tiger": "None",
		"snake_giant_python": "None", "hawk_giant": "None", "pegasus": "None",
		"spider_giant_crab": "C", "spider_giant_tarantula": "F",
		"fly_giant_carnivorous": "C", "rhagodessa_giant": "I", "hippogriff": "F",
		"caecilian": "K", "sea_serpent": "M, I", "whale_narwhal": "None",
	}
	for cid in expected_type:
		check(_registry.has_monster(cid), "catalog must have '%s'" % cid)
		if _registry.has_monster(cid):
			var got: String = str(_registry.get_monster(cid).get("treasure_type", ""))
			check(got == expected_type[cid],
				"%s treasure_type should be '%s', got '%s'" % [cid, expected_type[cid], got])
	# Loot-drop creatures carry a forward-looking delivery marker.
	for cid in ["caecilian", "sea_serpent", "whale_narwhal"]:
		if _registry.has_monster(cid):
			check(str(_registry.get_monster(cid).get("treasure_delivery", "")) == "loot_drop",
				"%s should be marked treasure_delivery=loot_drop" % cid)
	# Narwhal ivory horn modeled as a monster-part special worth 1d6x1000 gp.
	if _registry.has_monster("whale_narwhal"):
		var nst: Dictionary = _registry.get_monster("whale_narwhal").get("special_treasure", {})
		check(str(nst.get("value_dice", "")) == "1d6x1000",
			"narwhal horn value_dice should be '1d6x1000', got '%s'" % str(nst.get("value_dice")))
		check(bool(nst.get("is_monster_part", false)), "narwhal horn should be is_monster_part")
	# Regression guard: the bogus type "U" must be fully purged from the catalog.
	for mid in _registry.get_all_monster_ids():
		check(str(_registry.get_monster(mid).get("treasure_type", "")) != "U",
			"no catalog entry may carry the bogus treasure type 'U' (found on '%s')" % mid)


# ---------------------------------------------------------------------------
# Cell-based treasure placement (Pass D) — gdd-treasure-item-backing.md §15.
#
# stock_floor runs Pass D after Pass C, so by the time the shared _layout in
# run_all_tests is inspected every hoard should carry a cell + container_type
# stamp from TreasurePlacementService.
# ---------------------------------------------------------------------------

## Every persisted hoard must have a real cell (x >= 0); the placement service
## only skips placement when room_cells is empty (defensive path that should
## not fire on a real generator output where every room has cells).
func test_all_placed_hoards_have_valid_cell() -> void:
	for hoard in _layout.treasure_hoards:
		check(hoard.cell_x >= 0 and hoard.cell_y >= 0,
			"hoard in room %d expected placed cell, got (%d, %d)"
				% [hoard.room_id, hoard.cell_x, hoard.cell_y])


## Every persisted hoard must have a non-empty container_type drawn from the
## V1 catalog (see TreasureContainerTypes.VALID).
func test_all_placed_hoards_have_valid_container_type() -> void:
	for hoard in _layout.treasure_hoards:
		check(hoard.container_type in TreasureContainerTypes.VALID,
			"hoard in room %d has invalid container_type '%s'"
				% [hoard.room_id, hoard.container_type])


## The placed cell must be one of the hoard's room's interior cells.
func test_placed_hoards_cell_is_inside_room() -> void:
	for hoard in _layout.treasure_hoards:
		var room: DungeonRoomData = _layout.find_room(hoard.room_id)
		check(room != null, "hoard's room %d must exist in layout.rooms" % hoard.room_id)
		if room == null:
			continue
		var placed_cell := Vector2i(hoard.cell_x, hoard.cell_y)
		check(placed_cell in room.cells,
			"hoard in room %d placed at %s should be one of the room's cells"
				% [hoard.room_id, placed_cell])


## Trap-room hoards must be locked chests — the chest IS the trap
## (gdd-treasure-item-backing.md §15.5).
func test_trap_room_hoards_are_locked_chests() -> void:
	for hoard in _layout.treasure_hoards:
		if hoard.source != TreasureHoardData.SOURCE_UNPROTECTED_TRAP:
			continue
		check(hoard.container_type == TreasureContainerTypes.CHEST,
			"trap-room hoard in room %d should be a chest, got '%s'"
				% [hoard.room_id, hoard.container_type])
		check(hoard.is_locked == true,
			"trap-room hoard in room %d should be locked" % hoard.room_id)


## Pile types (coin_pile / gear_pile) are too loose to lock or trap; the
## placement service guards on capability flags before setting either bit.
func test_pile_hoards_are_never_locked_or_trapped() -> void:
	for hoard in _layout.treasure_hoards:
		if hoard.container_type != TreasureContainerTypes.COIN_PILE \
				and hoard.container_type != TreasureContainerTypes.GEAR_PILE:
			continue
		check(hoard.is_locked == false,
			"%s in room %d must not be locked" % [hoard.container_type, hoard.room_id])
		check(hoard.is_trapped == false,
			"%s in room %d must not be trapped" % [hoard.container_type, hoard.room_id])


## Trap-fallback guardrail: stock_floor passes traps_available = false to the
## placement service in V1, so no hoard should ever land with is_trapped = true.
## When the traps subsystem ships, this assertion needs to relax; until then it
## guards the "would-be-trapped becomes locked" invariant.
func test_traps_unavailable_no_hoard_is_trapped() -> void:
	for hoard in _layout.treasure_hoards:
		check(hoard.is_trapped == false,
			"with traps_available=false (V1), no hoard should emit is_trapped=true (room %d, container '%s')"
				% [hoard.room_id, hoard.container_type])


# ---------------------------------------------------------------------------
# DG-C3D.F.2a — per-zone stocking projection + circulation exclusion
# ---------------------------------------------------------------------------

## map_band_stocking_to_zones copies each stocked band-layout chamber room onto
## its composed zone-0 RoomZone, stamps MonsterGroupData.zone_index 0 while
## KEEPING per-band-LOCAL room ids on groups/hoards (F.2c id model: the
## relational store scopes them by floor_id; zones link by string id), skips
## circulation rooms, and rolls the composed room's purpose up from its main zone.
func test_map_band_stocking_to_zones() -> void:
	# Band 1 (composer slot 0): a stocked chamber (local 0) + a circulation room.
	var b1 := DungeonLayout.new()
	b1.level_number = 1
	var b1_chamber := DungeonRoomData.new()
	b1_chamber.id = 0
	b1_chamber.kind = DungeonRoomData.KIND_CHAMBER
	b1_chamber.contents_kind = "monster_lair"
	b1_chamber.monster_group_id = "mg_b1"
	b1_chamber.current_purpose = "goblin lair"
	var b1_circ := DungeonRoomData.new()
	b1_circ.id = 1
	b1_circ.kind = DungeonRoomData.KIND_CIRCULATION
	b1_circ.contents_kind = "empty"
	b1.rooms = [b1_chamber, b1_circ]
	var mg1 := MonsterGroupData.new()
	mg1.id = "mg_b1"
	mg1.room_id = 0
	b1.monster_groups = [mg1]

	# Band 2 (composer slot 1): a stocked chamber (local 0 -> global 1000).
	var b2 := DungeonLayout.new()
	b2.level_number = 2
	var b2_chamber := DungeonRoomData.new()
	b2_chamber.id = 0
	b2_chamber.kind = DungeonRoomData.KIND_CHAMBER
	b2_chamber.contents_kind = "empty"
	b2_chamber.current_purpose = "empty vault"
	b2.rooms = [b2_chamber]
	var h2 := TreasureHoardData.new()
	h2.id = "h_b2"
	h2.room_id = 0
	b2.treasure_hoards = [h2]

	# Compose result: global rooms + zone-0 per chamber (slot 0 -> id 0; slot 1 -> id 1000).
	var cr := DungeonVolumeComposer.ComposeResult.new()
	var cr1 := DungeonRoomData.new()
	cr1.id = 0
	cr1.band = 1
	var cr2 := DungeonRoomData.new()
	cr2.id = 1000
	cr2.band = 2
	cr.rooms = [cr1, cr2]
	var z1 := RoomZone.new()
	z1.room_id = 0
	z1.zone_index = 0
	z1.band = 1
	var z2 := RoomZone.new()
	z2.room_id = 1000
	z2.zone_index = 0
	z2.band = 2
	cr.zones = [z1, z2]

	var out: Dictionary = DungeonStocker.map_band_stocking_to_zones([b1, b2], cr)

	# Zone-0 carries the band-layout room's stocking.
	check(z1.contents_kind == "monster_lair", "band-1 chamber content maps to its zone 0")
	check(z1.monster_group_id == "mg_b1", "band-1 monster group id maps to zone 0")
	check(z1.current_purpose == "goblin lair", "band-1 purpose maps to zone 0")
	check(z2.contents_kind == "empty", "band-2 chamber maps as empty")
	# Monster group / hoard room ids stay LOCAL (F.2c id model); zone_index 0.
	check(mg1.room_id == 0, "band-1 group keeps its local room id 0")
	check(mg1.zone_index == 0, "band-1 group zone_index stamped 0")
	check(h2.room_id == 0, "band-2 hoard keeps its local room id 0 (floor_id scopes it), got %d" % h2.room_id)
	check((out["monster_groups"] as Array).size() == 1, "collected 1 monster group")
	check((out["treasure_hoards"] as Array).size() == 1, "collected 1 treasure hoard")
	# Composed RoomData rollup from the main zone.
	check(cr1.current_purpose == "goblin lair", "composed room 0 purpose rolls up from zone 0")
	check(cr1.monster_group_id == "mg_b1", "composed room 0 monster id rolls up")
	# Circulation room contributed nothing (no zone, no remapped group).
	check(z1.contents_kind != "" and z2.contents_kind != "", "both chamber zones stocked")


## stock_floor never stocks a circulation room (§11.1): it is skipped from the
## d100 loop, so it keeps its default empty contents and gets no purpose.
func test_stock_floor_skips_circulation_rooms() -> void:
	var layout := DungeonLayout.new()
	layout.level_number = 1
	layout.floor_tier = 1
	layout.grid_width = 6
	layout.grid_height = 6
	var cells: Array[Array] = []
	for x in range(6):
		var col: Array[DungeonCellData] = []
		for y in range(6):
			var c := DungeonCellData.new()
			c.terrain_feature = DungeonCellData.FEATURE_ROCK
			col.append(c)
		cells.append(col)
	layout.cells = cells
	var circ := DungeonRoomData.new()
	circ.id = 0
	circ.kind = DungeonRoomData.KIND_CIRCULATION
	circ.cells = [Vector2i(1, 1), Vector2i(2, 1)]
	layout.rooms = [circ]

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	DungeonStocker.stock_floor(layout, _loader, _registry, rng)

	check(circ.current_purpose == "", "circulation room never gets a stocked purpose")
	check(circ.contents_kind == "empty", "circulation room keeps default empty contents")
	check(circ.monster_group_id == "", "circulation room gets no monster group")
	check(layout.monster_groups.is_empty(), "no monster groups stocked for a circulation-only floor")
	check(layout.treasure_hoards.is_empty(), "no treasure hoards stocked for a circulation-only floor")


# ---------------------------------------------------------------------------
# DG-C3D.F.2d — balcony/gallery zone stocking
# ---------------------------------------------------------------------------

## Build a minimal composed fixture: one home-band chamber (global 1000, home
## band 2) with a balcony zone on band 1, plus band layouts for floors 1-2.
## door_specs: array of {cell: Vector3i, connects: Array} access-door records.
func _balcony_fixture(zone_cells: Array, door_specs: Array = [], second_zone_cells: Array = []) -> Dictionary:
	var cr := DungeonVolumeComposer.ComposeResult.new()
	var room := DungeonRoomData.new()
	room.id = 1000
	room.band = 2
	room.kind = DungeonRoomData.KIND_CHAMBER
	cr.rooms = [room]
	var zone := RoomZone.new()
	zone.room_id = 1000
	zone.zone_index = 1
	zone.band = 1
	zone.zone_type = RoomZone.ZONE_TYPE_BALCONY
	for c in zone_cells:
		zone.cells.append(c)
	cr.zones = [zone]
	var zone2: RoomZone = null
	if not second_zone_cells.is_empty():
		var room2 := DungeonRoomData.new()
		room2.id = 1001
		room2.band = 2
		room2.kind = DungeonRoomData.KIND_CHAMBER
		cr.rooms.append(room2)
		zone2 = RoomZone.new()
		zone2.room_id = 1001
		zone2.zone_index = 1
		zone2.band = 1
		zone2.zone_type = RoomZone.ZONE_TYPE_BALCONY
		for c in second_zone_cells:
			zone2.cells.append(c)
		cr.zones.append(zone2)
	cr.volume = VoxelMapData.new()
	for spec in door_specs:
		var cell: Vector3i = spec["cell"]
		var vc := VoxelCell.new()
		vc.col = cell.x
		vc.row = cell.y
		vc.level = cell.z
		vc.solidity = "air"
		vc.feature = "open"
		vc.floor_type = "stone"
		vc.door_state = "closed"
		vc.door_type = "unlocked"
		cr.volume.set_cell(cell, vc)
		var connects: Array[int] = []
		for cid in spec["connects"]:
			connects.append(int(cid))
		cr.doors.append({
			"cell": cell,
			"type": DungeonDoorData.TYPE_UNLOCKED,
			"is_secret": false,
			"material": DungeonDoorData.MATERIAL_WOOD_STANDARD,
			"band": 1,
			"connects": connects,
		})
	var floors: Array[DungeonLayout] = []
	for fi in [1, 2]:
		var fl := DungeonLayout.new()
		fl.level_number = fi
		fl.floor_tier = fi  # discriminating: band 1 tier 1, band 2 tier 2
		floors.append(fl)
	return {"cr": cr, "floors": floors, "zone": zone, "zone2": zone2,
		"band_walk": {1: 0, 2: -2}}


## Probe for a balcony-stream seed whose FIRST d100 lands in the wanted
## category (and optionally whose SECOND avoids a category) — against the
## real dungeon_stocking table, so range edits cannot silently break the test.
func _probe_balcony_seed(first_category: String, second_must_not_be: String = "") -> int:
	var rows: Array = _loader.rows("dungeon_stocking")
	for s in range(1, 5000):
		var rng := DungeonStocker.derive_balcony_rng(s)
		if DungeonStocker._match_stocking_category(rows, rng.randi_range(1, 100)) != first_category:
			continue
		if second_must_not_be != "":
			if DungeonStocker._match_stocking_category(rows, rng.randi_range(1, 100)) == second_must_not_be:
				continue
		return s
	return -1


## Conventions §118 zero-draw guard: a compose result with NO zone_index >= 1
## zones must consume nothing from the balcony stream.
func test_balcony_stream_zero_draw_without_zones() -> void:
	var cr := DungeonVolumeComposer.ComposeResult.new()
	var room := DungeonRoomData.new()
	room.id = 0
	room.band = 1
	room.kind = DungeonRoomData.KIND_CHAMBER
	cr.rooms = [room]
	var z0 := RoomZone.new()
	z0.room_id = 0
	z0.zone_index = 0
	z0.band = 1
	z0.cells.append(Vector2i(1, 1))
	cr.zones = [z0]
	var fl := DungeonLayout.new()
	fl.level_number = 1
	fl.floor_tier = 1
	var floors: Array[DungeonLayout] = [fl]
	var rng := DungeonStocker.derive_balcony_rng(777)
	var before: int = rng.state
	DungeonStocker.stock_balcony_zones(floors, cr, {1: 0}, _loader, _registry, rng)
	check(rng.state == before, "no eligible zones -> zero draws from the balcony stream")
	check(z0.contents_kind == "empty", "zone 0 untouched by the balcony pass")


## A Monster-category balcony zone stocks onto the ZONE band layout with the
## GLOBAL room id, the zone index, and hoards (if any) at the band walk z.
func test_balcony_zone_stocks_on_zone_band_layout() -> void:
	var s: int = _probe_balcony_seed("Monster")
	check(s > 0, "found a balcony seed whose first d100 is Monster")
	if s <= 0:
		return
	var fx := _balcony_fixture([Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5)])
	var floors: Array[DungeonLayout] = fx["floors"]
	DungeonStocker.stock_balcony_zones(
		floors, fx["cr"], fx["band_walk"], _loader, _registry, DungeonStocker.derive_balcony_rng(s))
	var zone: RoomZone = fx["zone"]
	check(zone.contents_kind == "monster" or zone.contents_kind == "monster_lair",
		"Monster category stocks the zone (got '%s')" % zone.contents_kind)
	check(zone.monster_group_id != "", "zone links its monster group")
	var band1: DungeonLayout = floors[0]
	check(band1.monster_groups.size() == 1, "group attached to the ZONE band layout (band 1)")
	if band1.monster_groups.size() == 1:
		var grp: MonsterGroupData = band1.monster_groups[0]
		check(grp.room_id == 1000, "group carries the GLOBAL room id")
		check(grp.zone_index == 1, "group carries the zone index")
		check(grp.floor_index == 1, "group floor_index = the zone band")
	for h in band1.treasure_hoards:
		var hoard: TreasureHoardData = h
		if hoard.cell_x >= 0:
			check(hoard.cell_z == 0, "balcony hoard placed at band 1 walk level 0 (got %d)" % hoard.cell_z)
	check((floors[1] as DungeonLayout).monster_groups.is_empty(),
		"nothing attached to the home band layout")


## Door-less nuance, no eligible swap target: the Trap assignment falls to
## Empty (d100 never re-rolled) and the zone still stocks deterministically.
func test_balcony_doorless_trap_demotes_to_empty() -> void:
	var s: int = _probe_balcony_seed("Trap")
	check(s > 0, "found a balcony seed whose first d100 is Trap")
	if s <= 0:
		return
	var fx := _balcony_fixture([Vector2i(4, 4), Vector2i(5, 4)])  # no access doors
	var floors: Array[DungeonLayout] = fx["floors"]
	DungeonStocker.stock_balcony_zones(
		floors, fx["cr"], fx["band_walk"], _loader, _registry, DungeonStocker.derive_balcony_rng(s))
	var zone: RoomZone = fx["zone"]
	check(zone.contents_kind == "empty",
		"door-less Trap with no swap target is assigned Empty (got '%s')" % zone.contents_kind)


## Door-less nuance, swap: the door-less zone gives its Trap to a same-band
## zone WITH an access door; that door record is gated (secret + locked) and
## its volume cell restamped.
func test_balcony_doorless_trap_swaps_to_doored_zone() -> void:
	var s: int = _probe_balcony_seed("Trap", "Trap")
	check(s > 0, "found a balcony seed with first Trap, second non-Trap")
	if s <= 0:
		return
	var door_cell := Vector3i(9, 9, 0)
	var fx := _balcony_fixture(
		[Vector2i(4, 4), Vector2i(5, 4)],                       # zone A: door-less
		[{"cell": door_cell, "connects": [1001]}],              # access door for zone B
		[Vector2i(9, 8), Vector2i(9, 7)])                       # zone B: has the door
	var floors: Array[DungeonLayout] = fx["floors"]
	DungeonStocker.stock_balcony_zones(
		floors, fx["cr"], fx["band_walk"], _loader, _registry, DungeonStocker.derive_balcony_rng(s))
	var zone_b: RoomZone = fx["zone2"]
	check(zone_b.contents_kind == "trap_placeholder",
		"the doored zone took the swapped Trap (got '%s')" % zone_b.contents_kind)
	var cr: DungeonVolumeComposer.ComposeResult = fx["cr"]
	var rec: Dictionary = cr.doors[0]
	check(bool(rec["is_secret"]) and str(rec["type"]) == DungeonDoorData.TYPE_LOCKED,
		"the access door record is gated secret+locked")
	var vc: VoxelCell = cr.volume.get_cell(door_cell)
	check(vc.door_type == "secret" and vc.door_state == "closed" and not vc.door_detected,
		"the volume door cell is restamped secret")
	check((fx["zone"] as RoomZone).contents_kind != "trap_placeholder",
		"the door-less zone no longer holds the Trap")
