extends "res://tests/test_suite_base.gd"

## Phase S-2 — per-campaign whole-DB save slots (gdd-savegame-system.md §6).
##
## Save = VACUUM INTO a slot file (complete capture). Restore = ATTACH + copy
## back ONLY the slot's campaign rows, scoped per-table by `_campaign_scope_entries`
## so loading one adventure never touches another. Coverage:
##   - test_scope_map_covers_all_tables: the completeness GUARANTEE — every table
##     is either in the scope map or the excluded list (a new table fails here).
##   - test_round_trip_restores_registry_hard_tables: save → lose → restore brings
##     back the tables a registry would miss (voxel_map_cells via dungeon-id list;
##     dungeon_entity_positions via party-FK).
##   - test_restore_is_campaign_isolated: restoring campaign A leaves campaign B's
##     data exactly as it was.
##   - test_snapshot_file_captures_full_table_set: the slot file is a whole-DB copy.
##   - test_delete_campaign_purges_all_scoped_tables: delete_campaign derives its
##     DELETEs from the same scope map, so it removes EVERY in-scope row of every
##     scoped table (and nothing else) — the delete path inherits the map's
##     completeness guarantee and can never silently orphan again.


const C_A := "test_savegame_snap_campaign_a"
const C_B := "test_savegame_snap_campaign_b"
const MAP_A := "test_snap_map_a"
const MAP_B := "test_snap_map_b"
const DUN_A := "test_snap_dungeon_a"  # dungeon id == voxel_map_cells.map_id
const DUN_B := "test_snap_dungeon_b"


func run_all_tests() -> void:
	# Clean slate before each test — seeds reuse the same campaign/dungeon ids.
	_cleanup()
	test_scope_map_covers_all_tables()
	_cleanup()
	test_snapshot_file_captures_full_table_set()
	_cleanup()
	test_round_trip_restores_registry_hard_tables()
	_cleanup()
	test_restore_is_campaign_isolated()
	_cleanup()
	test_delete_campaign_purges_all_scoped_tables()
	_cleanup()
	if not has_failures():
		print("SavegameSnapshot: all tests passed.")


## The completeness guarantee: every DB table must be classified — either scoped
## by _campaign_scope_entries or in SNAPSHOT_EXCLUDED_TABLES. A new table that is
## neither fails here, so the save system can never silently forget one.
func test_scope_map_covers_all_tables() -> void:
	var mapped: Dictionary = {}
	for entry in CampaignRepository._campaign_scope_entries():
		mapped[String(entry.get("table", ""))] = true
	var excluded: Dictionary = {}
	for t in CampaignRepository.SNAPSHOT_EXCLUDED_TABLES:
		excluded[t] = true
	CampaignRepository.db.query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
	var unclassified: Array = []
	for r: Dictionary in CampaignRepository.db.query_result:
		var t := String(r.get("name", ""))
		if not mapped.has(t) and not excluded.has(t):
			unclassified.append(t)
	check(unclassified.is_empty(),
		"every table must be scoped or excluded; unclassified: %s" % str(unclassified))
	print("  scope_map_covers_all_tables: OK")


func test_snapshot_file_captures_full_table_set() -> void:
	_seed(C_A, MAP_A, DUN_A, Vector3i(2, 3, 1))
	var sid := CampaignRepository.save_snapshot(C_A, "Capture Test", "manual", "Test Loc")
	check(not sid.is_empty(), "save_snapshot returned an id")
	var abs := CampaignRepository._slot_abs_path(sid)
	check(FileAccess.file_exists(abs), "slot .db file was created")
	var main_count := _live_table_count()
	var slot_count := _slot_table_count(abs)
	check(slot_count == main_count and main_count > 100,
		"slot captured the full table set (slot=%d, main=%d)" % [slot_count, main_count])
	var slots := CampaignRepository.list_snapshots(C_A)
	check(slots.size() == 1, "one slot listed for the campaign")
	if slots.size() == 1:
		check(String(slots[0].get("label", "")) == "Capture Test", "slot label stored")
		check(String(slots[0].get("location_label", "")) == "Test Loc", "slot location_label stored")
		check(int(slots[0].get("schema_version", 0)) > 0, "slot schema_version stamped")
	CampaignRepository.delete_snapshot(sid)
	check(not FileAccess.file_exists(abs), "delete_snapshot removed the slot file")
	print("  snapshot_file_captures_full_table_set: OK")


func test_round_trip_restores_registry_hard_tables() -> void:
	var pid := _seed(C_A, MAP_A, DUN_A, Vector3i(2, 3, 1))
	var sid := CampaignRepository.save_snapshot(C_A, "Round Trip", "manual", "")
	check(not sid.is_empty(), "save_snapshot returned an id")

	# Simulate post-save loss in campaign A.
	CampaignRepository.db.query_with_bindings("DELETE FROM voxel_map_cells WHERE map_id = ?", [DUN_A])
	CampaignRepository.clear_dungeon_entity_positions(pid)
	check(_count("voxel_map_cells", "map_id", DUN_A) == 0, "voxel cell gone pre-restore")
	check(CampaignRepository.load_dungeon_entity_positions(pid).is_empty(), "positions gone pre-restore")

	check(CampaignRepository.restore_snapshot(sid), "restore_snapshot succeeded")

	check(_count("voxel_map_cells", "map_id", DUN_A) == 1,
		"voxel_map_cells restored (dungeon-id-list scoped — registry-hard)")
	var pos := CampaignRepository.load_dungeon_entity_positions(pid)
	check(pos.get("snap_char", Vector3i.ZERO) == Vector3i(2, 3, 1),
		"dungeon_entity_positions restored (party-FK scoped)")
	check(CampaignRepository.list_snapshots(C_A).size() >= 1, "slot list survived restore")
	CampaignRepository.delete_snapshot(sid)
	print("  round_trip_restores_registry_hard_tables: OK")


## The headline guarantee for the user: restoring campaign A must NOT touch B.
func test_restore_is_campaign_isolated() -> void:
	_seed(C_A, MAP_A, DUN_A, Vector3i(2, 3, 1))
	_seed(C_B, MAP_B, DUN_B, Vector3i(5, 5, 0))
	var sid := CampaignRepository.save_snapshot(C_A, "Isolation Test", "manual", "")
	check(not sid.is_empty(), "save_snapshot(A) returned an id")

	# After saving A: lose A's voxel cell, and make NEW progress in B.
	CampaignRepository.db.query_with_bindings("DELETE FROM voxel_map_cells WHERE map_id = ?", [DUN_A])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO voxel_map_cells (map_id, col, row, level, fog_state) VALUES (?, ?, ?, ?, ?)",
		[DUN_B, 9, 9, 0, "explored"])
	check(_count("voxel_map_cells", "map_id", DUN_B) == 2, "B has 2 voxel cells pre-restore")

	check(CampaignRepository.restore_snapshot(sid), "restore_snapshot(A) succeeded")

	# A is restored…
	check(_count("voxel_map_cells", "map_id", DUN_A) == 1, "A's voxel cell restored")
	# …and B is UNTOUCHED (its new cell survives — A's restore didn't revert B).
	check(_count("voxel_map_cells", "map_id", DUN_B) == 2,
		"B untouched by A's restore (isolation holds)")
	CampaignRepository.delete_snapshot(sid)
	print("  restore_is_campaign_isolated: OK")


## delete_campaign derives its DELETEs from _campaign_scope_entries, so deleting
## campaign A must remove exactly the in-scope rows of EVERY scoped table while
## leaving campaign B untouched. In-scope counts are captured BEFORE the delete
## (via clauses resolve through parent tables, so they are only meaningful while
## the parents still exist); the per-table equality total_after == total_before
## - in_scope catches both leftovers (under-deletion) and lost B rows
## (over-deletion).
func test_delete_campaign_purges_all_scoped_tables() -> void:
	_seed(C_A, MAP_A, DUN_A, Vector3i(2, 3, 1))
	_seed(C_B, MAP_B, DUN_B, Vector3i(5, 5, 0))
	# Rows on the paths where the old hand-rolled delete and the scope map
	# diverged: dungeon voxel cells (old delete scoped map_id via hex_maps — a
	# no-op, map_id is a DUNGEON id), a domain-only pending_divine_effects row,
	# and a henchman pool + member.
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO characters (id, campaign_id, name) VALUES (?, ?, ?)",
		["del_char_a", C_A, "Del Test Char"])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO domains (id, campaign_id, name) VALUES (?, ?, ?)",
		["del_dom_a", C_A, "Del Test Domain"])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO pending_divine_effects (id, domain_id, effect_kind)
		VALUES (?, ?, 'consecrate_fields_land_value')""", ["del_pde_a", "del_dom_a"])
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO henchman_pools (id, campaign_id, settlement_id, generated_month, generated_year)
		VALUES (?, ?, ?, 1, 1)""", ["del_pool_a", C_A, "del_settle_a"])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO henchman_pool_members (pool_id, character_id) VALUES (?, ?)",
		["del_pool_a", "del_char_a"])
	var sid := CampaignRepository.save_snapshot(C_A, "Delete Test", "manual", "")
	check(not sid.is_empty(), "save_snapshot returned an id")
	var slot_abs := CampaignRepository._slot_abs_path(sid)

	var audit: Array = []
	for entry: Dictionary in CampaignRepository._campaign_scope_entries():
		var t: String = entry["table"]
		if not CampaignRepository._table_exists("main", t):
			continue
		var scope: Dictionary = CampaignRepository._scope_where(entry, "main", C_A)
		var where: String = scope["where"]
		var scoped := 0
		if where != "0":
			CampaignRepository.db.query_with_bindings(
				"SELECT COUNT(*) AS c FROM main.\"%s\" WHERE %s" % [t, where], scope["params"])
			scoped = int(CampaignRepository.db.query_result[0].get("c", 0))
		audit.append({"table": t, "total": _table_total(t), "scoped": scoped})

	check(CampaignRepository.delete_campaign(C_A), "delete_campaign returned true")

	var drifted: Array = []
	for a: Dictionary in audit:
		var t: String = a["table"]
		var expected: int = int(a["total"]) - int(a["scoped"])
		var actual := _table_total(t)
		if actual != expected:
			drifted.append("%s (want %d, have %d)" % [t, expected, actual])
	check(drifted.is_empty(),
		"delete_campaign must remove exactly the in-scope rows of every scoped table; drifted: %s" % str(drifted))

	# Targeted spot-checks: the historic divergences + the two tables outside
	# the scope map (campaigns root, game_snapshots slot metadata).
	check(_count("campaigns", "id", C_A) == 0, "campaign root row deleted")
	check(_count("game_snapshots", "campaign_id", C_A) == 0,
		"save-slot metadata deleted (game_snapshots is outside the scope map)")
	check(_count("voxel_map_cells", "map_id", DUN_A) == 0,
		"dungeon voxel cells purged (previously orphaned — scoped via hex_maps)")
	check(_count("pending_divine_effects", "domain_id", "del_dom_a") == 0,
		"domain-only pending_divine_effects purged (dual-parent clause)")
	check(_count("henchman_pool_members", "pool_id", "del_pool_a") == 0,
		"henchman_pool_members purged")
	# Campaign B untouched.
	check(_count("campaigns", "id", C_B) == 1, "campaign B root survives")
	check(_count("voxel_map_cells", "map_id", DUN_B) == 1, "campaign B voxel cell survives")
	check(_count("parties", "campaign_id", C_B) == 1, "campaign B party survives")
	# delete_campaign removes the slot METADATA row; the slot file itself is not
	# its concern — remove it here so test runs don't accumulate orphan files.
	if FileAccess.file_exists(slot_abs):
		DirAccess.remove_absolute(slot_abs)
	print("  delete_campaign_purges_all_scoped_tables: OK")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Seeds a campaign with a hex map, a party, a registered dungeon (entrance +
## voxel cell), and a per-entity dungeon position. Returns the party id.
func _seed(campaign_id: String, map_id: String, dungeon_id: String, cell: Vector3i) -> String:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)", [campaign_id, "Snap Test"])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, ?)",
		[map_id, campaign_id, "Map", "regional_6mi"])
	# Dungeon entrance whose dungeon_data.id == dungeon_id, so the dungeon-content
	# tables (voxel_map_cells) resolve to this campaign.
	var dj := JSON.stringify({"id": dungeon_id, "name": "Snap Dungeon", "cells": []})
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO dungeon_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, dungeon_data)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", ["entr_" + dungeon_id, campaign_id, map_id, 0, 0, "Snap Dungeon", dj])
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO voxel_map_cells (map_id, col, row, level, fog_state) VALUES (?, ?, ?, ?, ?)",
		[dungeon_id, cell.x, cell.y, cell.z, "explored"])
	var pid := CampaignRepository.create_party(campaign_id, "Snap Party")
	CampaignRepository.save_dungeon_entity_positions(pid, dungeon_id, {"snap_char": cell})
	return pid


func _count(table: String, col: String, val) -> int:
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS c FROM %s WHERE %s = ?" % [table, col], [val])
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("c", 0))


func _table_total(table: String) -> int:
	CampaignRepository.db.query("SELECT COUNT(*) AS c FROM main.\"%s\"" % table)
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("c", 0))


func _live_table_count() -> int:
	CampaignRepository.db.query("SELECT COUNT(*) AS c FROM main.sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
	return int(CampaignRepository.db.query_result[0].get("c", 0))


func _slot_table_count(slot_abs: String) -> int:
	var escaped := slot_abs.replace("'", "''")
	CampaignRepository.db.query("ATTACH DATABASE '%s' AS verify" % escaped)
	CampaignRepository.db.query("SELECT COUNT(*) AS c FROM verify.sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
	var n := int(CampaignRepository.db.query_result[0].get("c", 0))
	CampaignRepository.db.query("DETACH DATABASE verify")
	return n


func _cleanup() -> void:
	for camp in [C_A, C_B]:
		for s in CampaignRepository.list_snapshots(camp):
			CampaignRepository.delete_snapshot(String(s.get("id", "")))
	for dun in [DUN_A, DUN_B]:
		CampaignRepository.db.query_with_bindings("DELETE FROM voxel_map_cells WHERE map_id = ?", [dun])
		CampaignRepository.db.query_with_bindings("DELETE FROM dungeon_entrances WHERE id = ?", ["entr_" + dun])
	for camp in [C_A, C_B]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM dungeon_entity_positions WHERE party_id IN (SELECT id FROM parties WHERE campaign_id = ?)", [camp])
		CampaignRepository.db.query_with_bindings("DELETE FROM parties WHERE campaign_id = ?", [camp])
		CampaignRepository.db.query_with_bindings("DELETE FROM dungeon_entrances WHERE campaign_id = ?", [camp])
		CampaignRepository.db.query_with_bindings("DELETE FROM hex_maps WHERE campaign_id = ?", [camp])
		CampaignRepository.db.query_with_bindings("DELETE FROM campaigns WHERE id = ?", [camp])
	# Extra rows seeded by test_delete_campaign_purges_all_scoped_tables —
	# normally removed by delete_campaign itself; purge here so a failed run
	# can't leak them into other tests.
	CampaignRepository.db.query("DELETE FROM pending_divine_effects WHERE id = 'del_pde_a'")
	CampaignRepository.db.query("DELETE FROM henchman_pool_members WHERE pool_id = 'del_pool_a'")
	CampaignRepository.db.query("DELETE FROM henchman_pools WHERE id = 'del_pool_a'")
	CampaignRepository.db.query("DELETE FROM characters WHERE id = 'del_char_a'")
	CampaignRepository.db.query("DELETE FROM domains WHERE id = 'del_dom_a'")
