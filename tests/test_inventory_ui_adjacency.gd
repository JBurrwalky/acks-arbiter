extends "res://tests/test_suite_base.gd"

## Session 9 adjacency-aware inventory tests.
##
## Covers the pieces the overlay wires together but doesn't need a live scene:
##   - PartyInventoryTransferValidator.collect_adjacent_carrier_ids (pure)
##   - LootAutoDistributor.redistribute_among_adjacent (pure)
##   - LocationCacheManager voxel key round-trip (DB-backed)
## The overlay/modal UI flows are covered by the existing integration suites
## and the visual smoke test in the session plan.

const ValidatorScript := preload("res://engine/subsystems/inventory/party_inventory_transfer_validator.gd")

const TEST_CAMPAIGN := "test_iua_campaign"
const DUNGEON_ID := "test_iua_dungeon"


func run_all_tests() -> void:
	test_collect_adjacent_ids_same_cell()
	test_collect_adjacent_ids_2d_adjacent()
	test_collect_adjacent_ids_2d_far()
	test_collect_adjacent_ids_cross_level_diagonal()
	test_collect_adjacent_ids_cross_level_far()
	test_collect_adjacent_ids_missing_anchor()
	test_rebalance_equalizes_encumbrance()
	test_rebalance_preserves_equipped()
	test_rebalance_ignores_non_adjacent_carrier()
	test_rebalance_empty_cluster()
	test_cache_voxel_location_key_roundtrip()
	test_cache_voxel_key_parse_accepts_legacy_2d()

	if not has_failures():
		print("InventoryUIAdjacency: all tests passed.")


# ---------------------------------------------------------------------------
# collect_adjacent_carrier_ids — pure helper tests
# ---------------------------------------------------------------------------

func test_collect_adjacent_ids_same_cell() -> void:
	# ACKS movement forbids two entities sharing a cell; the anchor's own id
	# stays included (as the anchor), but any *other* carrier at the same
	# position is excluded — strict adjacency means Chebyshev == 1.
	var positions := {
		"A": Vector3i(5, 5, 0),
		"B": Vector3i(5, 5, 0),
	}
	var result := ValidatorScript.collect_adjacent_carrier_ids("A", positions)
	check(result.has("A"), "anchor always included")
	check(not result.has("B"), "other carrier at same cell is not adjacent")


func test_collect_adjacent_ids_2d_adjacent() -> void:
	var positions := {
		"A": Vector3i(5, 5, 0),
		"B": Vector3i(6, 6, 0),  # diagonal, Chebyshev = 1
	}
	var result := ValidatorScript.collect_adjacent_carrier_ids("A", positions)
	check(result.has("B"), "diagonal 2D neighbor should be adjacent")


func test_collect_adjacent_ids_2d_far() -> void:
	var positions := {
		"A": Vector3i(5, 5, 0),
		"B": Vector3i(7, 5, 0),  # Chebyshev = 2
	}
	var result := ValidatorScript.collect_adjacent_carrier_ids("A", positions)
	check(not result.has("B"), "2-cell-far carrier should be excluded")
	check(result.size() == 1, "only anchor remains; got %d" % result.size())


func test_collect_adjacent_ids_cross_level_diagonal() -> void:
	var positions := {
		"A": Vector3i(5, 5, 0),
		"B": Vector3i(6, 6, 1),  # 3D Chebyshev = 1
	}
	var result := ValidatorScript.collect_adjacent_carrier_ids("A", positions)
	check(result.has("B"), "cross-level diagonal should be adjacent")


func test_collect_adjacent_ids_cross_level_far() -> void:
	var positions := {
		"A": Vector3i(5, 5, 0),
		"B": Vector3i(5, 5, 2),  # z diff = 2
	}
	var result := ValidatorScript.collect_adjacent_carrier_ids("A", positions)
	check(not result.has("B"), "2-level-far carrier should be excluded")


func test_collect_adjacent_ids_missing_anchor() -> void:
	var positions := {"B": Vector3i(5, 5, 0)}
	var result := ValidatorScript.collect_adjacent_carrier_ids("A", positions)
	check(result.is_empty(), "missing anchor yields empty result")


# ---------------------------------------------------------------------------
# LootAutoDistributor.redistribute_among_adjacent — pure helper tests
# ---------------------------------------------------------------------------

func _make_carrier(id: String, current: int, carrier_type: String = "pc") -> Dictionary:
	return {
		"carrier_id": id,
		"carrier_type": carrier_type,
		"current_enc_units": current,
		"max_enc_units": 20000,
		"preferences": [],
		"equipped_weapons": [],
		"strength": 10,
	}


func _make_item(id: String, enc: int, source: String, is_eq: bool = false) -> Dictionary:
	return {
		"item_id": id,
		"item_key": "item_%s" % id,
		"quantity": 1,
		"encumbrance_units": enc,
		"item_category": "gear",
		"is_equipped": is_eq,
		"source_carrier_id": source,
	}


func test_rebalance_equalizes_encumbrance() -> void:
	# A has all the weight. Rebalance should move items to B and C.
	var distributor := LootAutoDistributor.new(null)
	var items := [
		_make_item("i1", 3000, "A"),
		_make_item("i2", 2500, "A"),
		_make_item("i3", 2000, "A"),
		_make_item("i4", 1500, "A"),
	]
	var carriers := [
		_make_carrier("A", 9000),  # loaded
		_make_carrier("B", 0),
		_make_carrier("C", 0),
	]
	var plan := distributor.redistribute_among_adjacent(items, carriers, "A")
	check(plan.moves.size() >= 2, "at least two items should move to other carriers; got %d" % plan.moves.size())

	# Reconstruct post-plan totals.
	var totals := {"A": 0, "B": 0, "C": 0}
	var consumed := {}
	for m in plan.moves:
		var to_cid: String = m["to_carrier"]
		var itm: Dictionary = m["item"]
		totals[to_cid] += int(itm["encumbrance_units"]) * int(itm["quantity"])
		consumed[itm["item_id"]] = true
	for it in items:
		if not consumed.has(it["item_id"]):
			totals[it["source_carrier_id"]] += int(it["encumbrance_units"]) * int(it["quantity"])

	var max_total: int = max(totals["A"], max(totals["B"], totals["C"]))
	var min_total: int = min(totals["A"], min(totals["B"], totals["C"]))
	# Delta should be less than the heaviest item once balance happens — the
	# greedy can't split units smaller than the largest chunk.
	check(max_total - min_total <= 3000,
		"post-rebalance delta should be <= heaviest item (3000); got max=%d min=%d" % [max_total, min_total])


func test_rebalance_preserves_equipped() -> void:
	var distributor := LootAutoDistributor.new(null)
	# Equipped items should be skipped even if their source is overloaded.
	var items := [
		_make_item("eq1", 3000, "A", true),  # equipped
		_make_item("free1", 3000, "A", false),
	]
	var carriers := [
		_make_carrier("A", 6000),
		_make_carrier("B", 0),
	]
	var plan := distributor.redistribute_among_adjacent(items, carriers, "A")
	for m in plan.moves:
		check(m["item"]["item_id"] != "eq1", "equipped item must not move")


func test_rebalance_ignores_non_adjacent_carrier() -> void:
	# C is NOT in the carriers array (not in the cluster). Only A+B items are
	# passed in, and only A+B are candidates. Verifies the helper doesn't
	# invent destinations or pull from outside.
	var distributor := LootAutoDistributor.new(null)
	var items := [_make_item("i1", 2000, "A")]
	var carriers := [
		_make_carrier("A", 2000),
		_make_carrier("B", 0),
	]
	var plan := distributor.redistribute_among_adjacent(items, carriers, "A")
	for m in plan.moves:
		check(m["to_carrier"] in ["A", "B"], "destination must be in cluster; got %s" % m["to_carrier"])


func test_rebalance_empty_cluster() -> void:
	var distributor := LootAutoDistributor.new(null)
	var plan := distributor.redistribute_among_adjacent([], [], "A")
	check(plan.moves.is_empty(), "empty cluster yields no moves")


# ---------------------------------------------------------------------------
# LocationCacheManager voxel key round-trip — DB-backed
# ---------------------------------------------------------------------------

func _cache_setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "IUA Test"])
	GameState.campaign_id = TEST_CAMPAIGN


func _cache_cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM location_caches WHERE campaign_id = ?", [TEST_CAMPAIGN])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])
	GameState.campaign_id = ""


func test_cache_voxel_location_key_roundtrip() -> void:
	_cache_setup()
	GameState.dice_overrides["cache_decay_timer"] = 3

	var cell := Vector3i(5, 7, 2)
	var cache_id := LocationCacheManager.create_dungeon_loose_cache(DUNGEON_ID, cell)
	check(not cache_id.is_empty(), "cache creation should succeed")

	var cache := CampaignRepository.get_location_cache(cache_id)
	var expected := "dungeon:%s:cell:5,7,2" % DUNGEON_ID
	check(cache.get("location_key") == expected,
		"location_key should be '%s'; got '%s'" % [expected, cache.get("location_key")])

	var parsed := LocationCacheManager.parse_dungeon_cell_key(cache.get("location_key"))
	check(not parsed.is_empty(), "parse_dungeon_cell_key should succeed on generated key")
	check(parsed["dungeon_id"] == DUNGEON_ID, "parsed dungeon_id should match")
	check(parsed["cell"] == cell, "parsed cell should equal original %s; got %s" % [cell, parsed["cell"]])

	GameState.dice_overrides.clear()
	_cache_cleanup()


func test_cache_voxel_key_parse_accepts_legacy_2d() -> void:
	# Pre-migration-037 keys ('dungeon:id:cell:col,row') resolve as level 0
	# when the migration hasn't run yet on a given DB. Guard: the helper
	# tolerates the legacy shape so cache lookups don't silently fail during
	# the rollout window.
	var parsed := LocationCacheManager.parse_dungeon_cell_key("dungeon:d1:cell:3,4")
	check(not parsed.is_empty(), "legacy 2D key should parse")
	check(parsed["cell"] == Vector3i(3, 4, 0),
		"legacy key should resolve to level 0; got %s" % parsed["cell"])
