extends "res://tests/test_suite_base.gd"

## Tests for FoundGuildhouseFlow (Venturer→Guildhouse refactor). Covers the
## validation matrix, the founding happy path (incl. apprentices spawned as
## individual `followers` rows), and the L12 monopoly-seize gates.


var _campaign_id: String = ""
var _map_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_validate_below_level_9()
	test_validate_not_venturer_class()
	test_validate_missing_settlement()
	test_found_happy_path()
	test_found_spawns_apprentice_followers()
	test_found_insufficient_funds()
	test_found_already_has_guildhouse()
	test_validate_guildhouse_too_far()
	test_seize_monopoly_gates_and_success()
	if not has_failures():
		print("FoundGuildhouseFlow: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test FoundGuildhouse", "TestWorld")
	check(not _campaign_id.is_empty(), "campaign created")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "FGFMap"])


func _make_settlement(market_class: int, hex_q: int, hex_r: int) -> String:
	var sid: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [sid, _campaign_id, _map_id, hex_q, hex_r, "Host_" + sid, market_class])
	return sid


func _make_venturer(level: int, coins_cp: int) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_type, persistence_tier, race,
			 character_class, level, strength, intelligence, wisdom,
			 dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'venturer', ?,
			10, 11, 10, 12, 10, 13, 24, 24)
	""", [id, _campaign_id, "Venturer_" + id, level])
	if coins_cp > 0:
		CampaignRepository.add_coins_cp(id, coins_cp)
	return id


func _apprentice_count(owner_id: String) -> int:
	var n := 0
	for f: Dictionary in CampaignRepository.list_followers_for_owner(owner_id, ""):
		if String(f.get("source_kind", "")) == "venturer_apprentice":
			n += 1
	return n


# ----- Validation -----

func test_validate_below_level_9() -> void:
	var settlement := _make_settlement(6, 0, 0)
	var v := _make_venturer(8, 0)
	var errors := FoundGuildhouseFlow.validate_founding({
		"campaign_id": _campaign_id, "owner_character_id": v,
		"host_settlement_entrance_id": settlement})
	check(errors.has(FoundGuildhouseFlow.ERR_BELOW_LEVEL_9),
		"level-8 venturer blocked from founding, errors=%s" % str(errors))


func test_validate_not_venturer_class() -> void:
	var settlement := _make_settlement(6, 0, 0)
	# A thief is a syndicate class, not a venturer.
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom, dexterity,
			constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'thief', 9, 10,10,10,13,10,10,20,20)
	""", [id, _campaign_id, "NotV_" + id])
	var errors := FoundGuildhouseFlow.validate_founding({
		"campaign_id": _campaign_id, "owner_character_id": id,
		"host_settlement_entrance_id": settlement})
	check(errors.has(FoundGuildhouseFlow.ERR_NOT_VENTURER_CLASS),
		"non-venturer cannot found a guildhouse, errors=%s" % str(errors))


func test_validate_missing_settlement() -> void:
	var v := _make_venturer(9, 0)
	var errors := FoundGuildhouseFlow.validate_founding({
		"campaign_id": _campaign_id, "owner_character_id": v,
		"host_settlement_entrance_id": ""})
	check(errors.has(FoundGuildhouseFlow.ERR_SETTLEMENT_REQUIRED),
		"missing host settlement flagged, errors=%s" % str(errors))


# ----- Founding -----

func test_found_happy_path() -> void:
	var settlement := _make_settlement(6, 5, 5)  # Class VI → 500,000 cp minimum
	var v := _make_venturer(9, 1_000_000)
	var result := FoundGuildhouseFlow.found_guildhouse({
		"campaign_id": _campaign_id, "owner_character_id": v,
		"host_settlement_entrance_id": settlement})
	check(result["errors"].is_empty(), "founding succeeded, errors=%s" % str(result["errors"]))
	check(not String(result["guildhouse_id"]).is_empty(), "guildhouse created")
	var gh: Dictionary = GuildhouseRepository.get_guildhouse(String(result["guildhouse_id"]))
	check(int(gh.get("cp_value", 0)) == 500000,
		"guildhouse cp_value = 500,000 (Class VI min), got %d" % int(gh.get("cp_value", 0)))
	check(int(gh.get("monopoly_seized", 0)) == 0, "monopoly not seized at founding")


func test_found_spawns_apprentice_followers() -> void:
	var settlement := _make_settlement(6, 6, 6)
	var v := _make_venturer(9, 1_000_000)
	var result := FoundGuildhouseFlow.found_guildhouse({
		"campaign_id": _campaign_id, "owner_character_id": v,
		"host_settlement_entrance_id": settlement})
	var fc: int = int(result["apprentice_count"])
	check(fc >= 2 and fc <= 12, "2d6 founding apprentices, got %d" % fc)
	# Apprentices are individual followers rows (source_kind='venturer_apprentice').
	check(_apprentice_count(v) == fc,
		"spawned %d apprentice followers, found %d" % [fc, _apprentice_count(v)])


func test_found_insufficient_funds() -> void:
	var settlement := _make_settlement(6, 0, 0)
	var v := _make_venturer(9, 0)
	var result := FoundGuildhouseFlow.found_guildhouse({
		"campaign_id": _campaign_id, "owner_character_id": v,
		"host_settlement_entrance_id": settlement})
	check(result["errors"].has(FoundGuildhouseFlow.ERR_INSUFFICIENT_FUNDS),
		"insufficient funds blocks founding, errors=%s" % str(result["errors"]))
	check(GuildhouseRepository.list_guildhouses_for_owner(v).is_empty(),
		"no guildhouse row left behind")


func test_found_already_has_guildhouse() -> void:
	var settlement := _make_settlement(6, 1, 1)
	var v := _make_venturer(9, 2_000_000)
	var first := FoundGuildhouseFlow.found_guildhouse({
		"campaign_id": _campaign_id, "owner_character_id": v,
		"host_settlement_entrance_id": settlement})
	check(first["errors"].is_empty(), "first founding ok, errors=%s" % str(first["errors"]))
	var second := FoundGuildhouseFlow.found_guildhouse({
		"campaign_id": _campaign_id, "owner_character_id": v,
		"host_settlement_entrance_id": settlement})
	check(second["errors"].has(FoundGuildhouseFlow.ERR_ALREADY_HAS_GUILDHOUSE),
		"second founding blocked (one guildhouse per venturer in v1), errors=%s" % str(second["errors"]))


func test_validate_guildhouse_too_far() -> void:
	# Settlement at (5,5); requested guildhouse at (5,8) is 3 hexes away (> 1).
	var settlement := _make_settlement(4, 5, 5)
	var v := _make_venturer(9, 5_000_000)
	var errors := FoundGuildhouseFlow.validate_founding({
		"campaign_id": _campaign_id, "owner_character_id": v,
		"host_settlement_entrance_id": settlement,
		"guildhouse_map_id": _map_id, "guildhouse_hex_q": 5, "guildhouse_hex_r": 8})
	check(errors.has(FoundGuildhouseFlow.ERR_GUILDHOUSE_TOO_FAR),
		"guildhouse >1 hex from settlement is rejected, errors=%s" % str(errors))


func test_seize_monopoly_gates_and_success() -> void:
	# An L11 venturer with a guildhouse cannot yet seize monopoly.
	var settlement := _make_settlement(6, 7, 7)
	var v11 := _make_venturer(11, 2_000_000)
	FoundGuildhouseFlow.found_guildhouse({
		"campaign_id": _campaign_id, "owner_character_id": v11,
		"host_settlement_entrance_id": settlement})
	var r11 := FoundGuildhouseFlow.seize_monopoly({"owner_character_id": v11})
	check(r11["errors"].has(FoundGuildhouseFlow.ERR_BELOW_LEVEL_12),
		"L11 venturer cannot seize monopoly, errors=%s" % str(r11["errors"]))

	# An L12 venturer with a guildhouse can seize.
	var settlement2 := _make_settlement(6, 9, 9)
	var v12 := _make_venturer(12, 2_000_000)
	FoundGuildhouseFlow.found_guildhouse({
		"campaign_id": _campaign_id, "owner_character_id": v12,
		"host_settlement_entrance_id": settlement2})
	var r12 := FoundGuildhouseFlow.seize_monopoly({"owner_character_id": v12})
	check(bool(r12["ok"]), "L12 venturer seizes monopoly, errors=%s" % str(r12["errors"]))
	var gh := GuildhouseRepository.get_guildhouse_for_owner(v12)
	check(int(gh.get("monopoly_seized", 0)) == 1, "monopoly_seized set on the guildhouse")
