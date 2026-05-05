extends "res://tests/test_suite_base.gd"

## End-to-end test for the lair-discovery flow (Wilderness closure Phase 4).
##
## Verifies the CampaignRepository helpers + LairSearchResolver round-trip:
##   * Place 3 lair rows on a fixture hex.
##   * Repeatedly call search_hour with a forced-success dice; reveal one
##     lair per success via reveal_one_lair until none remain.
##   * Per le_wilderness_lair_rules.xml §searching_for_lairs:
##       "If more than one lair is present, choose one or determine it
##        randomly." We verify that *some* lair is revealed each time —
##        the ordering policy is implementation-defined (current impl: by
##        lair_id ascending for stable tiebreak).
##
## Also verifies survey_progress upsert round-trip and reveal_one_lair
## edge cases (returns "" when no undiscovered lairs remain).


const PARTY_PREFIX := "test_phase4_ld_"
const CAMPAIGN_ID := "test_phase4_ld_campaign"
const MAP_ID := "test_phase4_ld_map"


# ---------------------------------------------------------------------------
# Fake DiceSystem — fixed return value
# ---------------------------------------------------------------------------

class _FixedDice:
	extends RefCounted
	var _value: int = 20
	func _init(v: int = 20) -> void:
		_value = v
	func roll_digital(sides: int, count: int = 1, modifier: int = 0,
			_roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		r.individual_results = []
		var total := 0
		for _i in range(count):
			r.individual_results.append(_value)
			total += _value
		r.raw_total = total
		r.modified_total = total + modifier
		r.natural_one = (_value == 1 and sides == 20 and count == 1)
		r.natural_max = (_value == sides and count == 1)
		return r


func run_all_tests() -> void:
	test_place_three_lairs_search_until_all_revealed()
	test_reveal_one_lair_returns_empty_when_none_undiscovered()
	test_count_helpers_match_actual_state()
	test_survey_progress_upsert_round_trip()
	if not has_failures():
		print("LairDiscovery: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_party_id(suffix: String) -> String:
	return PARTY_PREFIX + suffix


func _setup_fixture(party_id: String) -> void:
	# Seed required FK rows (campaign, hex_map, party) and clear any leftover
	# lairs/pois/survey_progress from prior runs of this fixture.
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM survey_progress WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM lairs WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM pois WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [MAP_ID])
	db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[CAMPAIGN_ID, "test phase4 ld"])
	db.query_with_bindings(
		"INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale) " +
		"VALUES (?, ?, ?, ?)",
		[MAP_ID, CAMPAIGN_ID, "test_map", "regional_6mi"])
	db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[party_id, CAMPAIGN_ID, "Test Phase 4 Party"])


func _cleanup_fixture(party_id: String) -> void:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM survey_progress WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM lairs WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM pois WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [MAP_ID])


func _place_lair(suffix: String, q: int, r: int, monster: String) -> void:
	CampaignRepository.create_lair({
		"lair_id": "test_phase4_lair_" + suffix,
		"campaign_id": CAMPAIGN_ID,
		"map_id": MAP_ID,
		"hex_q": q,
		"hex_r": r,
		"monster_group": monster,
		"monster_count": 5,
	})


func _make_party(party_id: String, with_tracking: bool = true) -> PartyData:
	var pd := PartyData.new()
	pd.id = party_id
	pd.campaign_id = CAMPAIGN_ID
	pd.character_data = []
	for i in range(2):
		var cd := CharacterData.new()
		cd.id = "%s_pc_%d" % [party_id, i]
		cd.name = "PC %d" % i
		cd.hp_max = 10
		cd.hp_current = 10
		if with_tracking and i == 0:
			cd.proficiencies = [{"proficiency_key": "tracking", "rank": 1}]
		pd.character_data.append(cd)
	return pd


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_place_three_lairs_search_until_all_revealed() -> void:
	var pid := _make_party_id("place3")
	_setup_fixture(pid)
	_place_lair("place3_a", 3, 5, "orcs")
	_place_lair("place3_b", 3, 5, "goblins")
	_place_lair("place3_c", 3, 5, "kobolds")

	var party := _make_party(pid)
	var dice := _FixedDice.new(20)

	var revealed_ids: Array = []
	for _attempt in range(5):
		var undiscovered: int = CampaignRepository.count_undiscovered_lairs(
			CAMPAIGN_ID, MAP_ID, 3, 5)
		if undiscovered <= 0:
			break
		var r: Dictionary = LairSearchResolver.search_hour(
			party, 0, undiscovered, dice)
		check(bool(r["succeeded"]), "rolled 20 + 4 tracking → success")
		check(bool(r["lair_found"]), "lair_found when undiscovered > 0")
		var rid: String = CampaignRepository.reveal_one_lair(
			CAMPAIGN_ID, MAP_ID, 3, 5, 100, "search")
		check(not rid.is_empty(), "reveal returns a lair id")
		revealed_ids.append(rid)

	check(revealed_ids.size() == 3, "all 3 lairs revealed after 3 search hours")
	check(CampaignRepository.count_undiscovered_lairs(
		CAMPAIGN_ID, MAP_ID, 3, 5) == 0, "no undiscovered lairs remain")
	check(CampaignRepository.list_discovered_lairs(
		CAMPAIGN_ID, MAP_ID).size() == 3, "list_discovered_lairs returns all 3")

	_cleanup_fixture(pid)


func test_reveal_one_lair_returns_empty_when_none_undiscovered() -> void:
	var pid := _make_party_id("empty")
	_setup_fixture(pid)
	# No lairs placed at all.
	var rid: String = CampaignRepository.reveal_one_lair(
		CAMPAIGN_ID, MAP_ID, 0, 0, 100, "search")
	check(rid.is_empty(), "no lairs → reveal returns empty string")
	_cleanup_fixture(pid)


func test_count_helpers_match_actual_state() -> void:
	var pid := _make_party_id("count")
	_setup_fixture(pid)
	_place_lair("count_a", 7, 7, "ogres")
	_place_lair("count_b", 7, 7, "trolls")
	check(CampaignRepository.count_lairs_in_hex(
		CAMPAIGN_ID, MAP_ID, 7, 7) == 2, "total = 2")
	check(CampaignRepository.count_undiscovered_lairs(
		CAMPAIGN_ID, MAP_ID, 7, 7) == 2, "undiscovered = 2")
	CampaignRepository.reveal_one_lair(
		CAMPAIGN_ID, MAP_ID, 7, 7, 100, "passive")
	check(CampaignRepository.count_lairs_in_hex(
		CAMPAIGN_ID, MAP_ID, 7, 7) == 2, "total still = 2 after reveal")
	check(CampaignRepository.count_undiscovered_lairs(
		CAMPAIGN_ID, MAP_ID, 7, 7) == 1, "undiscovered drops to 1")
	_cleanup_fixture(pid)


func test_survey_progress_upsert_round_trip() -> void:
	var pid := _make_party_id("sp")
	_setup_fixture(pid)

	# First read on a fresh fixture should be empty.
	var initial: Dictionary = CampaignRepository.get_survey_progress(
		CAMPAIGN_ID, MAP_ID, pid, 2, 2)
	check(initial.is_empty(), "no row before first upsert")

	var ok: bool = CampaignRepository.upsert_survey_progress({
		"campaign_id": CAMPAIGN_ID,
		"map_id": MAP_ID,
		"party_id": pid,
		"hex_q": 2,
		"hex_r": 2,
		"successful_searches": 1,
		"last_search_round": 4321,
		"last_estimate": 5,
		"last_estimate_correct": true,
	})
	check(ok, "first upsert succeeds")

	var row: Dictionary = CampaignRepository.get_survey_progress(
		CAMPAIGN_ID, MAP_ID, pid, 2, 2)
	check(int(row.get("successful_searches", 0)) == 1, "successes round-trip")
	check(int(row.get("last_estimate", -1)) == 5, "estimate round-trip")

	# Replace with new values.
	CampaignRepository.upsert_survey_progress({
		"campaign_id": CAMPAIGN_ID,
		"map_id": MAP_ID,
		"party_id": pid,
		"hex_q": 2,
		"hex_r": 2,
		"successful_searches": 3,
		"last_search_round": 9999,
		"last_estimate": 7,
		"last_estimate_correct": false,
	})
	var row2: Dictionary = CampaignRepository.get_survey_progress(
		CAMPAIGN_ID, MAP_ID, pid, 2, 2)
	check(int(row2.get("successful_searches", 0)) == 3, "successes updated")
	check(int(row2.get("last_estimate", -1)) == 7, "estimate updated")
	check(int(row2.get("last_estimate_correct", 1)) == 0, "false-reading flag stored")

	_cleanup_fixture(pid)
