extends "res://tests/test_suite_base.gd"

## Tests for party membership invariant enforcement.
## Verifies: mutual exclusivity (one party per character), no orphans,
## UNIQUE constraint, add_party_member move semantics, list_unpartied filtering,
## and creature party_id requirement.

const TEST_CAMPAIGN := "test_pmi_campaign"
const TEST_PARTY_A := "test_pmi_party_a"
const TEST_PARTY_B := "test_pmi_party_b"
const TEST_MAP := "test_pmi_map"
const PC_A := "test_pmi_pc_a"
const PC_B := "test_pmi_pc_b"
const PC_C := "test_pmi_pc_c"


func run_all_tests() -> void:
	test_add_to_second_party_moves_not_copies()
	test_unique_constraint_prevents_raw_duplicate()
	test_list_unpartied_excludes_partied()
	test_remove_leaves_character_unpartied()
	test_creature_requires_party_id()
	test_split_preserves_invariant()

	if not has_failures():
		print("PartyMembershipInvariants: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup_two_parties() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "PMI Test"])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, ?)",
		[TEST_MAP, TEST_CAMPAIGN, "Test Map", "regional_6mi"])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name, current_map_id, current_hex_q, current_hex_r) VALUES (?, ?, ?, ?, ?, ?)",
		[TEST_PARTY_A, TEST_CAMPAIGN, "Party A", TEST_MAP, 3, 5])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name, current_map_id, current_hex_q, current_hex_r) VALUES (?, ?, ?, ?, ?, ?)",
		[TEST_PARTY_B, TEST_CAMPAIGN, "Party B", TEST_MAP, 3, 5])
	for id in [PC_A, PC_B, PC_C]:
		_create_character(id)
	CampaignRepository.add_party_member(TEST_PARTY_A, PC_A)
	CampaignRepository.add_party_member(TEST_PARTY_A, PC_B)
	Timekeeping.register_party(TEST_PARTY_A)
	Timekeeping.register_party(TEST_PARTY_B)


func _create_character(id: String) -> void:
	CampaignRepository.create_character({
		"id": id,
		"campaign_id": TEST_CAMPAIGN,
		"name": "Char_%s" % id.substr(id.length() - 1),
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
	Timekeeping.unregister_party(TEST_PARTY_A)
	Timekeeping.unregister_party(TEST_PARTY_B)
	for char_id in [PC_A, PC_B, PC_C]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM party_members WHERE character_id = ?", [char_id])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [char_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM trained_creatures WHERE campaign_id = ?", [TEST_CAMPAIGN])
	for pid in [TEST_PARTY_A, TEST_PARTY_B]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM party_state WHERE party_id = ?", [pid])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM parties WHERE id = ?", [pid])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [TEST_MAP])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _count_memberships(character_id: String) -> int:
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS cnt FROM party_members WHERE character_id = ?",
		[character_id])
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return CampaignRepository.db.query_result[0].cnt


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## add_party_member with a character already in party A should MOVE to party B,
## not create a duplicate row.
func test_add_to_second_party_moves_not_copies() -> void:
	_setup_two_parties()

	# PC_A is in PARTY_A. Move to PARTY_B.
	var ok := CampaignRepository.add_party_member(TEST_PARTY_B, PC_A)
	check(ok, "add_party_member to second party should succeed")

	var current := CampaignRepository.get_party_for_character(PC_A)
	check(current == TEST_PARTY_B,
		"PC_A should be in PARTY_B after move, got '%s'" % current)

	var count := _count_memberships(PC_A)
	check(count == 1,
		"PC_A should have exactly 1 membership row, got %d" % count)

	# Verify PC_A is NOT in PARTY_A's member list.
	var a_members := CampaignRepository.list_party_characters(TEST_PARTY_A)
	var a_ids: Array = []
	for m in a_members:
		a_ids.append(m.id)
	check(PC_A not in a_ids, "PC_A should no longer be in PARTY_A")

	_cleanup()


## The UNIQUE constraint on character_id should prevent raw SQL from inserting
## the same character into two parties.
func test_unique_constraint_prevents_raw_duplicate() -> void:
	_setup_two_parties()

	# PC_A is already in PARTY_A via _setup_two_parties().
	# Try raw INSERT into PARTY_B (bypassing add_party_member).
	var ok := CampaignRepository.db.query_with_bindings(
		"INSERT INTO party_members (party_id, character_id) VALUES (?, ?)",
		[TEST_PARTY_B, PC_A])
	check(not ok,
		"Raw INSERT of PC_A into second party should fail (UNIQUE violation)")

	var count := _count_memberships(PC_A)
	check(count == 1,
		"PC_A should still have exactly 1 membership row, got %d" % count)

	_cleanup()


## list_unpartied_characters should exclude characters in any party and include
## characters with no party membership.
func test_list_unpartied_excludes_partied() -> void:
	_setup_two_parties()

	# PC_A and PC_B are in PARTY_A. PC_C was created but not added to any party.
	var unpartied := CampaignRepository.list_unpartied_characters(TEST_CAMPAIGN)
	var unpartied_ids: Array = []
	for row in unpartied:
		unpartied_ids.append(row.id)

	check(PC_C in unpartied_ids,
		"PC_C (no party) should appear in unpartied list")
	check(PC_A not in unpartied_ids,
		"PC_A (in PARTY_A) should NOT appear in unpartied list")
	check(PC_B not in unpartied_ids,
		"PC_B (in PARTY_A) should NOT appear in unpartied list")

	_cleanup()


## After removing a character from their party, get_party_for_character should
## return empty string.
func test_remove_leaves_character_unpartied() -> void:
	_setup_two_parties()

	CampaignRepository.remove_party_member(TEST_PARTY_A, PC_A)
	var party := CampaignRepository.get_party_for_character(PC_A)
	check(party == "",
		"PC_A should have no party after removal, got '%s'" % party)

	# Verify they now appear in unpartied list.
	var unpartied := CampaignRepository.list_unpartied_characters(TEST_CAMPAIGN)
	var unpartied_ids: Array = []
	for row in unpartied:
		unpartied_ids.append(row.id)
	check(PC_A in unpartied_ids,
		"PC_A should appear in unpartied list after removal")

	_cleanup()


## create_trained_creature with empty party_id should fail.
func test_creature_requires_party_id() -> void:
	_setup_two_parties()

	var result := CampaignRepository.create_trained_creature({
		"campaign_id": TEST_CAMPAIGN,
		"party_id": "",
		"species_id": "horse_riding",
		"name": "Test Horse",
	})
	check(result == "",
		"create_trained_creature with empty party_id should return empty string")

	_cleanup()


## After a split, every character should be in exactly one party.
func test_split_preserves_invariant() -> void:
	_setup_two_parties()

	# Add PC_C to PARTY_A so we have 3 members to split.
	CampaignRepository.add_party_member(TEST_PARTY_A, PC_C)

	# Split PC_A out into a new party.
	var new_pid := CampaignRepository.split_party(TEST_PARTY_A, "Scouts", [PC_A])
	check(not new_pid.is_empty(), "split_party should succeed")

	# Every character should be in exactly one party.
	for cid in [PC_A, PC_B, PC_C]:
		var count := _count_memberships(cid)
		check(count == 1,
			"%s should be in exactly 1 party after split, got %d" % [cid, count])

	# PC_A in new party, PC_B and PC_C still in PARTY_A.
	check(CampaignRepository.get_party_for_character(PC_A) == new_pid,
		"PC_A should be in the new party")
	check(CampaignRepository.get_party_for_character(PC_B) == TEST_PARTY_A,
		"PC_B should still be in PARTY_A")
	check(CampaignRepository.get_party_for_character(PC_C) == TEST_PARTY_A,
		"PC_C should still be in PARTY_A")

	# Clean up the dynamically-created party.
	Timekeeping.unregister_party(new_pid)
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_members WHERE party_id = ?", [new_pid])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [new_pid])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [new_pid])

	_cleanup()
