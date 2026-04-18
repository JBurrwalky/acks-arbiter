extends "res://tests/test_suite_base.gd"

## Unit tests for party split and merge — CampaignRepository.split_party()
## and CampaignRepository.merge_parties(). Seeds test data into the DB, exercises
## the methods, and verifies outcomes. Cleans up after itself.

const TEST_CAMPAIGN := "test_psm_campaign"
const TEST_PARTY := "test_psm_party"
const PC_A := "test_psm_pc_a"
const PC_B := "test_psm_pc_b"
const PC_C := "test_psm_pc_c"
const PC_D := "test_psm_pc_d"
const TEST_MAP := "test_psm_map"

var _created_party_ids: Array = []


func run_all_tests() -> void:
	# Split tests
	test_split_one_character()
	test_split_n_minus_one_characters()
	test_split_all_rejected()
	test_split_empty_list_rejected()
	test_split_wrong_character_rejected()
	test_split_copies_position()
	test_split_emits_signal()

	# Merge tests
	test_merge_same_hex()
	test_merge_different_hex_rejected()
	test_merge_self_rejected()
	test_merge_transfers_fks()
	test_merge_emits_signal()

	if not has_failures():
		print("PartySplitMerge: all tests passed.")


# ---------------------------------------------------------------------------
# Test data setup / teardown
# ---------------------------------------------------------------------------

func _setup_party_4() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "PSM Test"])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, ?)",
		[TEST_MAP, TEST_CAMPAIGN, "Test Map", "regional_6mi"])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name, current_map_id, current_hex_q, current_hex_r) VALUES (?, ?, ?, ?, ?, ?)",
		[TEST_PARTY, TEST_CAMPAIGN, "Main Party", TEST_MAP, 3, 5])
	for id in [PC_A, PC_B, PC_C, PC_D]:
		_create_character(id)
		CampaignRepository.add_party_member(TEST_PARTY, id)
	Timekeeping.register_party(TEST_PARTY)


func _create_character(id: String) -> void:
	CampaignRepository.create_character({
		"id": id,
		"campaign_id": TEST_CAMPAIGN,
		"name": "Char_%s" % id.right(1),
		"character_type": "pc",
		"persistence_tier": "full",
		"race": "human",
		"character_class": "fighter",
		"level": 1,
		"xp": 0,
		"combat_progression": "fighter",
		"strength": 10,
		"intelligence": 10,
		"wisdom": 10,
		"dexterity": 10,
		"constitution": 10,
		"charisma": 10,
	})


func _cleanup() -> void:
	# Remove any dynamically-created parties
	for pid in _created_party_ids:
		Timekeeping.unregister_party(pid)
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM party_state WHERE party_id = ?", [pid])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM party_members WHERE party_id = ?", [pid])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM trained_creatures WHERE party_id = ?", [pid])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM draft_vehicles WHERE party_id = ?", [pid])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM inventory_items WHERE party_id = ?", [pid])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM parties WHERE id = ?", [pid])
	_created_party_ids.clear()

	Timekeeping.unregister_party(TEST_PARTY)
	for char_id in [PC_A, PC_B, PC_C, PC_D]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM inventory_items WHERE character_id = ?", [char_id])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM party_members WHERE character_id = ?", [char_id])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [char_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [TEST_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [TEST_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [TEST_MAP])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _get_member_ids(party_id: String) -> Array:
	var members := CampaignRepository.list_party_characters(party_id)
	var ids: Array = []
	for m in members:
		ids.append(m.id)
	return ids


# ---------------------------------------------------------------------------
# Split tests
# ---------------------------------------------------------------------------

func test_split_one_character() -> void:
	_setup_party_4()
	var new_id := CampaignRepository.split_party(TEST_PARTY, "Scouts", [PC_A])
	check(not new_id.is_empty(), "split_one: should return new party id")
	_created_party_ids.append(new_id)

	var source_ids := _get_member_ids(TEST_PARTY)
	var new_ids := _get_member_ids(new_id)
	check(source_ids.size() == 3, "split_one: source should have 3 members, got %d" % source_ids.size())
	check(new_ids.size() == 1, "split_one: new party should have 1 member, got %d" % new_ids.size())
	check(PC_A in new_ids, "split_one: PC_A should be in new party")
	check(PC_A not in source_ids, "split_one: PC_A should not be in source")
	_cleanup()
	print("  split_one_character: OK")


func test_split_n_minus_one_characters() -> void:
	_setup_party_4()
	var new_id := CampaignRepository.split_party(TEST_PARTY, "Away Team", [PC_A, PC_B, PC_C])
	check(not new_id.is_empty(), "split_n-1: should return new party id")
	_created_party_ids.append(new_id)

	var source_ids := _get_member_ids(TEST_PARTY)
	var new_ids := _get_member_ids(new_id)
	check(source_ids.size() == 1, "split_n-1: source should have 1 member, got %d" % source_ids.size())
	check(new_ids.size() == 3, "split_n-1: new party should have 3 members, got %d" % new_ids.size())
	check(PC_D in source_ids, "split_n-1: PC_D should remain in source")
	_cleanup()
	print("  split_n_minus_one_characters: OK")


func test_split_all_rejected() -> void:
	_setup_party_4()
	var new_id := CampaignRepository.split_party(TEST_PARTY, "Bad", [PC_A, PC_B, PC_C, PC_D])
	check(new_id.is_empty(), "split_all: should reject (would empty source)")
	# Verify nobody moved
	var source_ids := _get_member_ids(TEST_PARTY)
	check(source_ids.size() == 4, "split_all: source should still have 4 members")
	_cleanup()
	print("  split_all_rejected: OK")


func test_split_empty_list_rejected() -> void:
	_setup_party_4()
	var new_id := CampaignRepository.split_party(TEST_PARTY, "Empty", [])
	check(new_id.is_empty(), "split_empty: should reject empty character list")
	_cleanup()
	print("  split_empty_list_rejected: OK")


func test_split_wrong_character_rejected() -> void:
	_setup_party_4()
	var new_id := CampaignRepository.split_party(TEST_PARTY, "Bad", ["nonexistent_char"])
	check(new_id.is_empty(), "split_wrong: should reject character not in party")
	_cleanup()
	print("  split_wrong_character_rejected: OK")


func test_split_copies_position() -> void:
	_setup_party_4()
	var new_id := CampaignRepository.split_party(TEST_PARTY, "Scouts", [PC_A])
	check(not new_id.is_empty(), "split_pos: should succeed")
	_created_party_ids.append(new_id)

	var new_party := CampaignRepository.get_party(new_id)
	check(new_party.current_map_id == TEST_MAP, "split_pos: new party should have same map_id")
	check(new_party.current_hex_q == 3, "split_pos: new party hex_q should be 3, got %d" % new_party.current_hex_q)
	check(new_party.current_hex_r == 5, "split_pos: new party hex_r should be 5, got %d" % new_party.current_hex_r)
	_cleanup()
	print("  split_copies_position: OK")


func test_split_emits_signal() -> void:
	_setup_party_4()
	var emitted_source := ""
	var emitted_new := ""
	var handler := func(src: String, nw: String) -> void:
		emitted_source = src
		emitted_new = nw
	EventBus.party_split.connect(handler)

	var new_id := CampaignRepository.split_party(TEST_PARTY, "Scouts", [PC_A])
	_created_party_ids.append(new_id)

	check(emitted_source == TEST_PARTY, "split_signal: source id should match")
	check(emitted_new == new_id, "split_signal: new id should match")
	EventBus.party_split.disconnect(handler)
	_cleanup()
	print("  split_emits_signal: OK")


# ---------------------------------------------------------------------------
# Merge tests
# ---------------------------------------------------------------------------

func test_merge_same_hex() -> void:
	_setup_party_4()
	var new_id := CampaignRepository.split_party(TEST_PARTY, "Scouts", [PC_A, PC_B])
	check(not new_id.is_empty(), "merge_same: split should succeed")
	_created_party_ids.append(new_id)

	var ok := CampaignRepository.merge_parties(TEST_PARTY, new_id)
	check(ok, "merge_same: merge should succeed")

	var source_ids := _get_member_ids(TEST_PARTY)
	check(source_ids.size() == 4, "merge_same: target should have all 4 members, got %d" % source_ids.size())

	# Source party should be deleted
	var dissolved := CampaignRepository.get_party(new_id)
	check(dissolved.is_empty(), "merge_same: dissolved party should not exist")
	_cleanup()
	print("  merge_same_hex: OK")


func test_merge_different_hex_rejected() -> void:
	_setup_party_4()
	var new_id := CampaignRepository.split_party(TEST_PARTY, "Scouts", [PC_A])
	check(not new_id.is_empty(), "merge_diff: split should succeed")
	_created_party_ids.append(new_id)

	# Move new party to different hex
	CampaignRepository.update_party_position(new_id, TEST_MAP, 10, 10)

	var ok := CampaignRepository.merge_parties(TEST_PARTY, new_id)
	check(not ok, "merge_diff: merge should fail (different hex)")
	_cleanup()
	print("  merge_different_hex_rejected: OK")


func test_merge_self_rejected() -> void:
	_setup_party_4()
	var ok := CampaignRepository.merge_parties(TEST_PARTY, TEST_PARTY)
	check(not ok, "merge_self: should reject merging with self")
	_cleanup()
	print("  merge_self_rejected: OK")


func test_merge_transfers_fks() -> void:
	_setup_party_4()
	var new_id := CampaignRepository.split_party(TEST_PARTY, "Scouts", [PC_A])
	check(not new_id.is_empty(), "merge_fks: split should succeed")
	_created_party_ids.append(new_id)

	# Add a party-level inventory item to the source (scout) party
	CampaignRepository.add_party_inventory_item(new_id, {
		"item_key": "test_ration",
		"name": "Test Ration",
		"quantity": 5,
	})

	var ok := CampaignRepository.merge_parties(TEST_PARTY, new_id)
	check(ok, "merge_fks: merge should succeed")

	# The inventory item should now belong to the target party
	var target_inv := CampaignRepository.get_party_inventory(TEST_PARTY)
	var found := false
	for item in target_inv:
		if item.item_key == "test_ration":
			found = true
			break
	check(found, "merge_fks: party inventory should transfer to target")

	# Clean up the test inventory item
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE item_key = 'test_ration' AND party_id = ?",
		[TEST_PARTY])
	_cleanup()
	print("  merge_transfers_fks: OK")


func test_merge_emits_signal() -> void:
	_setup_party_4()
	var new_id := CampaignRepository.split_party(TEST_PARTY, "Scouts", [PC_A])
	check(not new_id.is_empty(), "merge_signal: split should succeed")
	_created_party_ids.append(new_id)

	var emitted_target := ""
	var emitted_dissolved := ""
	var handler := func(tgt: String, src: String) -> void:
		emitted_target = tgt
		emitted_dissolved = src
	EventBus.party_merged.connect(handler)

	var ok := CampaignRepository.merge_parties(TEST_PARTY, new_id)
	check(ok, "merge_signal: merge should succeed")
	check(emitted_target == TEST_PARTY, "merge_signal: target should match")
	check(emitted_dissolved == new_id, "merge_signal: dissolved should match")

	EventBus.party_merged.disconnect(handler)
	_cleanup()
	print("  merge_emits_signal: OK")
