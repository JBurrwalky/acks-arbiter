extends "res://tests/test_suite_base.gd"

## Tests for FoundSyndicateFlow (Thief→Syndicate refactor).
##
## Covers the validation matrix and the founding happy path: a level-9 thief
## near a market settlement funds a hideout, founds a syndicate, and gains 2d6
## level-1 followers of their class.


var _campaign_id: String = ""
var _map_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_validate_below_level_9()
	test_validate_not_syndicate_class()
	test_validate_missing_settlement()
	test_found_happy_path()
	test_found_insufficient_funds()
	test_found_already_has_syndicate()
	test_validate_hideout_too_far()
	test_found_then_monthly_income_e2e()
	if not has_failures():
		print("FoundSyndicateFlow: all tests passed.")


# ----- Setup / fixtures -----

func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test FoundSyndicate", "TestWorld")
	check(not _campaign_id.is_empty(), "campaign created")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "FSFMap"])


func _make_settlement(market_class: int, hex_q: int, hex_r: int) -> String:
	var sid: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [sid, _campaign_id, _map_id, hex_q, hex_r, "Host_" + sid, market_class])
	return sid


func _make_boss(class_id: String, level: int, coins_cp: int) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_type, persistence_tier, race,
			 character_class, level, strength, intelligence, wisdom,
			 dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', ?, ?,
			10, 10, 10, 13, 10, 12, 24, 24)
	""", [id, _campaign_id, "Boss_" + id, class_id, level])
	if coins_cp > 0:
		CampaignRepository.add_coins_cp(id, coins_cp)
	return id


# ----- Validation -----

func test_validate_below_level_9() -> void:
	var settlement := _make_settlement(6, 0, 0)
	var boss := _make_boss("thief", 8, 0)
	var errors := FoundSyndicateFlow.validate_founding({
		"campaign_id": _campaign_id,
		"owner_character_id": boss,
		"host_settlement_entrance_id": settlement,
	})
	check(errors.has(FoundSyndicateFlow.ERR_BELOW_LEVEL_9),
		"level-8 thief blocked from founding, errors=%s" % str(errors))


func test_validate_not_syndicate_class() -> void:
	var settlement := _make_settlement(6, 0, 0)
	var boss := _make_boss("fighter", 9, 0)
	var errors := FoundSyndicateFlow.validate_founding({
		"campaign_id": _campaign_id,
		"owner_character_id": boss,
		"host_settlement_entrance_id": settlement,
	})
	check(errors.has(FoundSyndicateFlow.ERR_NOT_SYNDICATE_CLASS),
		"fighter cannot found a syndicate, errors=%s" % str(errors))


func test_validate_missing_settlement() -> void:
	var boss := _make_boss("assassin", 9, 0)
	var errors := FoundSyndicateFlow.validate_founding({
		"campaign_id": _campaign_id,
		"owner_character_id": boss,
		"host_settlement_entrance_id": "",
	})
	check(errors.has(FoundSyndicateFlow.ERR_SETTLEMENT_REQUIRED),
		"missing host settlement flagged, errors=%s" % str(errors))


# ----- Founding -----

func test_found_happy_path() -> void:
	# Class VI settlement → 5,000 gp (500,000 cp) minimum hideout, max 25 members.
	var settlement := _make_settlement(6, 5, 5)
	var boss := _make_boss("thief", 9, 1_000_000)  # 10,000 gp on hand
	var result := FoundSyndicateFlow.found_syndicate({
		"campaign_id": _campaign_id,
		"owner_character_id": boss,
		"host_settlement_entrance_id": settlement,
	})
	check(result["errors"].is_empty(), "founding succeeded, errors=%s" % str(result["errors"]))
	check(not String(result["syndicate_id"]).is_empty(), "syndicate created")
	check(not String(result["hideout_id"]).is_empty(), "hideout created")
	# 2d6 followers.
	var fc: int = int(result["follower_count"])
	check(fc >= 2 and fc <= 12, "2d6 founding followers, got %d" % fc)

	# Hideout: funded to the Class VI minimum (500,000 cp) and back-linked.
	var hideout: Dictionary = HideoutRepository.get_hideout(String(result["hideout_id"]))
	check(int(hideout.get("cp_value", 0)) == 500000,
		"hideout cp_value = 500,000 (Class VI min), got %d" % int(hideout.get("cp_value", 0)))
	check(String(hideout.get("syndicate_id", "")) == String(result["syndicate_id"]),
		"hideout back-linked to its syndicate")

	# Syndicate: size cap from market class; current_size == follower count;
	# members reachable.
	var syndicate: Dictionary = SyndicateRepository.get_syndicate(String(result["syndicate_id"]))
	check(int(syndicate.get("syndicate_size_max", 0)) == 25,
		"syndicate_size_max = 25 (Class VI), got %d" % int(syndicate.get("syndicate_size_max", 0)))
	check(int(syndicate.get("current_size", 0)) == fc,
		"current_size matches follower count")
	check(String(syndicate.get("hideout_id", "")) == String(result["hideout_id"]),
		"syndicate.hideout_id points at the hideout")
	var members: Array = SyndicateRepository.list_members(String(result["syndicate_id"]))
	check(members.size() == fc, "spawned %d members, found %d" % [fc, members.size()])
	if members.size() > 0:
		check(String(members[0].get("follower_kind", "")) == "thief",
			"followers are the boss's class (thief)")

	# Boss was charged the hideout minimum.
	check(not SyndicateRepository.list_syndicates_for_boss(boss).is_empty(),
		"syndicate reachable via list_syndicates_for_boss")


func test_found_insufficient_funds() -> void:
	# Class VI minimum is 500,000 cp; this boss has nothing.
	var settlement := _make_settlement(6, 0, 0)
	var boss := _make_boss("thief", 9, 0)
	var result := FoundSyndicateFlow.found_syndicate({
		"campaign_id": _campaign_id,
		"owner_character_id": boss,
		"host_settlement_entrance_id": settlement,
	})
	check(result["errors"].has(FoundSyndicateFlow.ERR_INSUFFICIENT_FUNDS),
		"insufficient funds blocks founding, errors=%s" % str(result["errors"]))
	check(String(result["syndicate_id"]).is_empty(), "no syndicate created when broke")
	check(SyndicateRepository.list_syndicates_for_boss(boss).is_empty(),
		"no syndicate row left behind")


func test_found_already_has_syndicate() -> void:
	var settlement := _make_settlement(6, 1, 1)
	var boss := _make_boss("elven_nightblade", 9, 2_000_000)
	var first := FoundSyndicateFlow.found_syndicate({
		"campaign_id": _campaign_id,
		"owner_character_id": boss,
		"host_settlement_entrance_id": settlement,
	})
	check(first["errors"].is_empty(), "first founding succeeds, errors=%s" % str(first["errors"]))
	var second := FoundSyndicateFlow.found_syndicate({
		"campaign_id": _campaign_id,
		"owner_character_id": boss,
		"host_settlement_entrance_id": settlement,
	})
	check(second["errors"].has(FoundSyndicateFlow.ERR_ALREADY_HAS_SYNDICATE),
		"second founding blocked (one syndicate per boss in v1), errors=%s" % str(second["errors"]))


func test_validate_hideout_too_far() -> void:
	# Settlement at (5,5); requested hideout at (5,8) is 3 hexes away (> 1).
	var settlement := _make_settlement(4, 5, 5)
	var boss := _make_boss("thief", 9, 5_000_000)
	var errors := FoundSyndicateFlow.validate_founding({
		"campaign_id": _campaign_id,
		"owner_character_id": boss,
		"host_settlement_entrance_id": settlement,
		"hideout_map_id": _map_id,
		"hideout_hex_q": 5,
		"hideout_hex_r": 8,
	})
	check(errors.has(FoundSyndicateFlow.ERR_HIDEOUT_TOO_FAR),
		"hideout >1 hex from settlement is rejected, errors=%s" % str(errors))


func test_found_then_monthly_income_e2e() -> void:
	# End-to-end: found a syndicate via the new flow, then run the monthly
	# fast-path over the founded syndicate. The 2d6 founding members are all
	# level 1, so each yields 5gp × 100 = 500cp of net monthly income — proving
	# the founding path produces a syndicate the income system can resolve.
	var settlement := _make_settlement(6, 9, 9)
	var boss := _make_boss("thief", 9, 2_000_000)
	var founded := FoundSyndicateFlow.found_syndicate({
		"campaign_id": _campaign_id,
		"owner_character_id": boss,
		"host_settlement_entrance_id": settlement,
	})
	check(founded["errors"].is_empty(), "E2E founding ok, errors=%s" % str(founded["errors"]))
	var fc: int = int(founded["follower_count"])
	var month := NpcSyndicateMonthlyResolver.process_syndicate_month(String(founded["syndicate_id"]))
	check(int(month.get("total_cp", 0)) == fc * 500,
		"monthly income = %d members × 500cp = %d; got %d" % [fc, fc * 500, int(month.get("total_cp", 0))])
	check(int(month.get("skipped_l9_plus_members", 0)) == 0, "no L9+ founding members")
	check(int(month.get("upkeep_cp", 0)) == 0, "L1 founding members incur no upkeep")
