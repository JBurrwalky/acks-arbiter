extends "res://tests/test_suite_base.gd"

## Unit tests for ClaimingResolver (Domain Phase 1).
##
## Verifies claim_existing inserts a fully-completed stronghold and emits
## stronghold_claimed; verifies the is_archetype_conforming_to_class matrix
## (display-only flag per [RESOLVED 2026-05-06]).


var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()
	test_claim_inserts_completed_stronghold()
	test_claim_emits_signal()
	test_claim_rejects_zero_or_negative_value()
	test_claim_rejects_invalid_source()
	test_claim_rejects_unknown_archetype()
	test_archetype_conforming_fighter_to_castle()
	test_archetype_conforming_fighter_to_sanctum()
	test_archetype_conforming_mage_to_sanctum()
	test_archetype_conforming_thief_to_hideout()
	test_archetype_conforming_dwarven_to_vault()
	test_archetype_empty_class_returns_true()
	if not has_failures():
		print("ClaimingResolver: all tests passed.")


# ----- Setup -----

func _setup_campaign() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign(
		"Test Claiming Resolver", "TestWorld")
	check(not _campaign_id.is_empty(), "campaign created")


func _make_test_domain() -> String:
	return CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "TestDomain",
		"territory_type": "borderlands",
	})


# ----- Claim inserts a completed stronghold -----

func test_claim_inserts_completed_stronghold() -> void:
	var domain_id := _make_test_domain()
	var result := ClaimingResolver.claim_existing(
		domain_id, "char_1", "fortress", "stronghold_castle",
		25000, "ruin", 0, 0, "")
	check(result["errors"].is_empty(),
		"no errors, got %s" % str(result["errors"]))
	check(not result["stronghold_id"].is_empty(), "stronghold inserted")

	var sh: Dictionary = CampaignRepository.get_stronghold(result["stronghold_id"])
	check(int(sh.get("completion_pct", 0)) == 100,
		"completion_pct = 100, got %d" % int(sh.get("completion_pct", 0)))
	check(String(sh.get("status", "")) == "completed",
		"status = completed, got %s" % str(sh.get("status", "")))
	check(int(sh.get("is_claimed", 0)) == 1,
		"is_claimed = 1, got %d" % int(sh.get("is_claimed", 0)))
	check(String(sh.get("claimed_from_source", "")) == "ruin",
		"claimed_from_source = ruin")
	check(int(sh.get("gp_value", 0)) == 25000,
		"gp_value = 25000")


func test_claim_emits_signal() -> void:
	var domain_id := _make_test_domain()
	var fired: Array[Array] = []
	var conn := func(stronghold_id: String, source: String, gp_value: int):
		fired.append([stronghold_id, source, gp_value])
	EventBus.stronghold_claimed.connect(conn)

	var result := ClaimingResolver.claim_existing(
		domain_id, "char_1", "hideout", "stronghold_hideout",
		15000, "dungeon", 0, 0, "")

	check(fired.size() == 1, "stronghold_claimed fired exactly once")
	if fired.size() > 0:
		check(fired[0][1] == "dungeon", "source = dungeon")
		check(fired[0][2] == 15000, "gp_value = 15000")
	EventBus.stronghold_claimed.disconnect(conn)


# ----- Claim rejection cases -----

func test_claim_rejects_zero_or_negative_value() -> void:
	var domain_id := _make_test_domain()
	var result := ClaimingResolver.claim_existing(
		domain_id, "char_1", "fortress", "stronghold_castle",
		0, "ruin", 0, 0, "")
	check(result["errors"].has("appraised_value_must_be_positive"),
		"zero value rejected, got %s" % str(result["errors"]))


func test_claim_rejects_invalid_source() -> void:
	var domain_id := _make_test_domain()
	var result := ClaimingResolver.claim_existing(
		domain_id, "char_1", "fortress", "stronghold_castle",
		25000, "invented_source", 0, 0, "")
	check(result["errors"].has("invalid_source"),
		"invalid source rejected, got %s" % str(result["errors"]))


func test_claim_rejects_unknown_archetype() -> void:
	var domain_id := _make_test_domain()
	var result := ClaimingResolver.claim_existing(
		domain_id, "char_1", "spaceship", "stronghold_orbital_platform",
		25000, "ruin", 0, 0, "")
	check(result["errors"].has("unknown_archetype"),
		"unknown archetype rejected, got %s" % str(result["errors"]))


# ----- is_archetype_conforming_to_class matrix -----

func test_archetype_conforming_fighter_to_castle() -> void:
	var c := ClaimingResolver.is_archetype_conforming_to_class(
		"fortress", "stronghold_castle", "fighter")
	check(c == true, "fighter → castle (fortress) is conforming")


func test_archetype_conforming_fighter_to_sanctum() -> void:
	var c := ClaimingResolver.is_archetype_conforming_to_class(
		"sanctum", "stronghold_sanctum", "fighter")
	check(c == false, "fighter → sanctum is NON-conforming")


func test_archetype_conforming_mage_to_sanctum() -> void:
	var c := ClaimingResolver.is_archetype_conforming_to_class(
		"sanctum", "stronghold_sanctum", "mage")
	check(c == true, "mage → sanctum is conforming")


func test_archetype_conforming_thief_to_hideout() -> void:
	var c := ClaimingResolver.is_archetype_conforming_to_class(
		"hideout", "stronghold_hideout", "thief")
	check(c == true, "thief → hideout is conforming")


func test_archetype_conforming_dwarven_to_vault() -> void:
	var c := ClaimingResolver.is_archetype_conforming_to_class(
		"vault", "stronghold_vault", "dwarven_craftpriest")
	check(c == true, "dwarven craftpriest → vault is conforming")


func test_archetype_empty_class_returns_true() -> void:
	var c := ClaimingResolver.is_archetype_conforming_to_class(
		"fortress", "stronghold_castle", "")
	check(c == true, "empty ruler_class_id → assume conforming (no check)")
