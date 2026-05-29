extends "res://tests/test_suite_base.gd"

## Tests for DungeonHandlers._resolve_loot — the cell-based loot interaction
## handler (Commit 4 of the cell-based-treasure-containers arc).
##
## Wires materialize_hoard_cell into the dungeon runtime so first interaction
## with a placed-hoard cell promotes the hoard into a runtime cache and opens
## the loot modal. Locked containers surface as "open_loot_modal_locked"
## presentations; hidden hoards return "Nothing visible here." until a Search
## reveals them.

const _DB_CAMPAIGN := "test_resolve_loot_campaign"
const _DUNGEON_ID := "test_resolve_loot_dungeon"
const _FLOOR_ID := "test_resolve_loot_floor"
const _ROOM_ID := 11


var _handlers: DungeonHandlers


func run_all_tests() -> void:
	# `DungeonHandlers._init(runner)` accepts a runner. `_resolve_loot` does not
	# read `_runner` (verified via inspection), so null is safe in this test.
	_handlers = DungeonHandlers.new(null)

	test_no_floor_no_cache_returns_nothing_to_loot()
	test_no_hoard_at_cell_returns_nothing_to_loot()
	test_unlocked_pile_opens_loot_modal()
	test_locked_chest_returns_locked_presentation()
	test_hidden_hoard_returns_nothing_visible()
	test_repeated_loot_on_same_cell_is_idempotent_modal()

	if not has_failures():
		print("DungeonHandlersResolveLoot: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_no_floor_no_cache_returns_nothing_to_loot() -> void:
	# An unknown dungeon (no dungeon_floors row) AND no pre-existing cache:
	# the cache-only fallback returns "Nothing to loot here."
	_loot_setup()
	var res: Dictionary = _handlers._resolve_loot("entity_x", Vector3i(7, 7, 0), _DUNGEON_ID)
	check(str(res.get("pause_reason", "")) == "Nothing to loot here.",
		"unknown floor + no cache → 'Nothing to loot here.', got '%s'" % str(res.get("pause_reason", "")))
	check(not res.has("presentation"), "no presentation when nothing's there")
	_loot_teardown()
	print("  no_floor_no_cache_returns_nothing_to_loot: OK")


func test_no_hoard_at_cell_returns_nothing_to_loot() -> void:
	# A real floor exists but no hoard at the queried cell: "Nothing to loot here."
	_loot_setup()
	_insert_floor()
	var res: Dictionary = _handlers._resolve_loot("entity_x", Vector3i(99, 99, 0), _DUNGEON_ID)
	check(str(res.get("pause_reason", "")) == "Nothing to loot here.",
		"floor exists but no hoard at cell → 'Nothing to loot here.', got '%s'"
			% str(res.get("pause_reason", "")))
	_loot_teardown()
	print("  no_hoard_at_cell_returns_nothing_to_loot: OK")


func test_unlocked_pile_opens_loot_modal() -> void:
	# A visible unlocked coin_pile at a cell: opens the standard loot modal.
	_loot_setup()
	_insert_floor()
	_insert_hoard("loot_pile", _ROOM_ID, Vector3i(3, 4, 0), {
		"gold": 25,
		"total_gp_value": 25,
		"container_type": TreasureContainerTypes.COIN_PILE,
		"is_locked": false, "is_trapped": false, "is_hidden": false,
	})

	var res: Dictionary = _handlers._resolve_loot("entity_x", Vector3i(3, 4, 0), _DUNGEON_ID)
	check(str(res.get("pause_reason", "")) == "Looting",
		"unlocked pile → 'Looting' pause_reason, got '%s'" % str(res.get("pause_reason", "")))
	var pres: Dictionary = res.get("presentation", {})
	check(str(pres.get("type", "")) == "open_loot_modal",
		"unlocked pile presentation type 'open_loot_modal', got '%s'" % str(pres.get("type", "")))
	check(not str(pres.get("cache_id", "")).is_empty(),
		"presentation must carry a cache_id")
	check(int(pres.get("cell_z", -1)) == 0,
		"presentation carries cell_z, got %d" % int(pres.get("cell_z", -1)))

	_loot_teardown()
	print("  unlocked_pile_opens_loot_modal: OK")


func test_locked_chest_returns_locked_presentation() -> void:
	# A locked chest: returns a distinct "open_loot_modal_locked" presentation
	# carrying the container_item_id, container_type, and trap-stub flag.
	_loot_setup()
	_insert_floor()
	_insert_hoard("loot_chest", _ROOM_ID, Vector3i(5, 6, 0), {
		"gold": 500,
		"total_gp_value": 500,
		"container_type": TreasureContainerTypes.CHEST,
		"is_locked": true, "is_trapped": false, "is_hidden": false,
	})

	var res: Dictionary = _handlers._resolve_loot("entity_x", Vector3i(5, 6, 0), _DUNGEON_ID)
	check(str(res.get("pause_reason", "")) == "Locked",
		"locked chest → 'Locked' pause_reason, got '%s'" % str(res.get("pause_reason", "")))
	var pres: Dictionary = res.get("presentation", {})
	check(str(pres.get("type", "")) == "open_loot_modal_locked",
		"locked chest presentation type 'open_loot_modal_locked', got '%s'" % str(pres.get("type", "")))
	check(not str(pres.get("container_item_id", "")).is_empty(),
		"locked presentation must carry a container_item_id")
	check(str(pres.get("container_type", "")) == TreasureContainerTypes.CHEST,
		"locked presentation carries container_type")
	check(bool(pres.get("is_trapped", true)) == false,
		"non-trapped chest → is_trapped=false in presentation")

	_loot_teardown()
	print("  locked_chest_returns_locked_presentation: OK")


func test_hidden_hoard_returns_nothing_visible() -> void:
	# A hidden hoard at a cell: the handler returns "Nothing visible here." and
	# does NOT materialize (the hoard stays is_looted=0 for a later Search +
	# materialize flow).
	_loot_setup()
	_insert_floor()
	_insert_hoard("loot_hidden", _ROOM_ID, Vector3i(2, 2, 0), {
		"gold": 100,
		"total_gp_value": 100,
		"container_type": TreasureContainerTypes.CHEST,
		"is_locked": false, "is_trapped": false, "is_hidden": true,
	})

	var res: Dictionary = _handlers._resolve_loot("entity_x", Vector3i(2, 2, 0), _DUNGEON_ID)
	check(str(res.get("pause_reason", "")) == "Nothing visible here.",
		"hidden hoard → 'Nothing visible here.', got '%s'" % str(res.get("pause_reason", "")))
	check(not res.has("presentation"), "hidden hoard yields no presentation")

	# The hoard must NOT be looted — a future Search + un-hide + re-loot path
	# should still find it.
	var hoard_after: TreasureHoardData = (
		DungeonGeneratorRepository.get_unlooted_treasure_hoard_at_cell(
			_FLOOR_ID, Vector3i(2, 2, 0)))
	check(hoard_after != null, "hidden hoard must remain unlooted after a hidden-gate loot attempt")

	_loot_teardown()
	print("  hidden_hoard_returns_nothing_visible: OK")


func test_repeated_loot_on_same_cell_is_idempotent_modal() -> void:
	# Calling _resolve_loot twice on the same unlocked pile cell should return
	# the SAME cache_id both times (the first call materializes; the second
	# finds the existing cache via the idempotency path).
	_loot_setup()
	_insert_floor()
	_insert_hoard("loot_idem", _ROOM_ID, Vector3i(8, 8, 0), {
		"gold": 10,
		"total_gp_value": 10,
		"container_type": TreasureContainerTypes.COIN_PILE,
	})

	var first: Dictionary = _handlers._resolve_loot("entity_x", Vector3i(8, 8, 0), _DUNGEON_ID)
	var second: Dictionary = _handlers._resolve_loot("entity_x", Vector3i(8, 8, 0), _DUNGEON_ID)
	var first_id: String = str(first.get("presentation", {}).get("cache_id", ""))
	var second_id: String = str(second.get("presentation", {}).get("cache_id", ""))
	check(not first_id.is_empty(), "first loot creates a cache")
	check(first_id == second_id,
		"second loot returns the same cache id (idempotent), got '%s' vs '%s'" % [first_id, second_id])

	_loot_teardown()
	print("  repeated_loot_on_same_cell_is_idempotent_modal: OK")


# ---------------------------------------------------------------------------
# Setup / teardown helpers
# ---------------------------------------------------------------------------

func _loot_setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_DB_CAMPAIGN, "Resolve Loot Test", "Test World"])
	GameState.campaign_id = _DB_CAMPAIGN
	# Clear prior state for the dungeon (each test runs the full set).
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM treasure_hoards WHERE dungeon_id = ?", [_DUNGEON_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM dungeon_floors WHERE dungeon_id = ?", [_DUNGEON_ID])


func _insert_floor() -> void:
	# Minimum row to make get_floor_id_for_voxel_level(_DUNGEON_ID, 0) resolve
	# to _FLOOR_ID. The remaining columns get sensible defaults / nullable
	# values so the CHECK constraints don't fire.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO dungeon_floors
			(id, dungeon_id, floor_index, floor_tier, is_entrance_floor,
			 dungeon_type, dungeon_size, structure_type, grid_width, grid_height,
			 entrance_x, entrance_y, generation_seed, cells_json, stairs_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		_FLOOR_ID, _DUNGEON_ID, 1, 1, 1,
		"wizards_dungeon", "small", "subterranean", 21, 21,
		0, 0, 0, "[]", "[]",
	])


func _insert_hoard(hoard_pk: String, room_id: int, cell: Vector3i, fields: Dictionary) -> void:
	# container_type "" persists as SQL NULL (matches the migration-137 CHECK
	# enum semantics).
	var container_type: Variant = null
	if not str(fields.get("container_type", "")).is_empty():
		container_type = fields["container_type"]
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO treasure_hoards
			(id, dungeon_id, floor_id, room_id, source, treasure_type_letter,
			 copper, silver, electrum, gold, platinum, gems, jewelry, magic_items,
			 total_gp_value, is_hidden,
			 cell_x, cell_y, cell_z, container_type, is_locked, is_trapped)
		VALUES (?, ?, ?, ?, 'lair', NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
			?, ?, ?, ?, ?, ?)
	""", [
		hoard_pk, _DUNGEON_ID, _FLOOR_ID, str(room_id),
		int(fields.get("copper", 0)), int(fields.get("silver", 0)),
		int(fields.get("electrum", 0)), int(fields.get("gold", 0)),
		int(fields.get("platinum", 0)),
		JSON.stringify(fields.get("gems", [])),
		JSON.stringify(fields.get("jewelry", [])),
		JSON.stringify(fields.get("magic_items", [])),
		int(fields.get("total_gp_value", 0)),
		1 if bool(fields.get("is_hidden", false)) else 0,
		cell.x, cell.y, cell.z, container_type,
		1 if bool(fields.get("is_locked", false)) else 0,
		1 if bool(fields.get("is_trapped", false)) else 0,
	])


func _loot_teardown() -> void:
	# Delete cache items + caches created during the test for this campaign,
	# then the floor + hoards + campaign row.
	for c in LocationCacheManager.list_caches_for_campaign():
		var cid: String = str(c.get("id", ""))
		for it in CampaignRepository.list_items_in_cache(cid):
			CampaignRepository.remove_inventory_item(str(it.get("id", "")))
		CampaignRepository.delete_location_cache(cid)
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM treasure_hoards WHERE dungeon_id = ?", [_DUNGEON_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM dungeon_floors WHERE dungeon_id = ?", [_DUNGEON_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_DB_CAMPAIGN])
