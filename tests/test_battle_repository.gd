extends "res://tests/test_suite_base.gd"

## Tests for BattleRepository (Phase 6B migrations 075-077).
##
## Covers CRUD round-trips for field_battles / battle_unit_states / battle_log
## plus the auto-incrementing sequence_number on battle_log appends.


var _campaign_id: String = ""
var _ruler_a: String = ""
var _ruler_b: String = ""
var _army_a_id: String = ""
var _army_b_id: String = ""
var _troop_unit_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_create_and_get_battle()
	test_update_battle_field_whitelist()
	test_unit_state_round_trip()
	test_unit_state_filtering_by_zone()
	test_battle_log_sequence_numbers()
	if not has_failures():
		print("BattleRepository: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Battle Repo Test", "World")
	_ruler_a = _make_character("Lord A")
	_ruler_b = _make_character("Lord B")
	_army_a_id = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Alpha Force",
		"political_owner_id": _ruler_a, "command_character_id": _ruler_a,
		"state": "marching",
	})
	_army_b_id = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Bravo Force",
		"political_owner_id": _ruler_b, "command_character_id": _ruler_b,
		"state": "encamped",
	})
	_troop_unit_id = TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": _ruler_a,
		"source_type": "mercenary", "troop_type": "Heavy Inf",
		"count": 60, "starting_count": 60, "battle_rating": 2.0,
	})


func _make_character(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, name])
	return id


func _create_battle() -> String:
	return BattleRepository.create_battle({
		"campaign_id": _campaign_id,
		"hex_q": 4, "hex_r": 5,
		"attacker_army_id": _army_a_id,
		"defender_army_id": _army_b_id,
		"terrain_type": "hills",
		"starting_bpc": 1, "current_bpc": 1,
		"current_phase": "missile",
		"started_calendar_day": 100,
	})


func test_create_and_get_battle() -> void:
	var id := _create_battle()
	check(not id.is_empty(), "create_battle returned id")
	var row := BattleRepository.get_battle(id)
	check(String(row.get("terrain_type", "")) == "hills", "terrain stored")
	check(int(row.get("starting_bpc", 0)) == 1, "starting_bpc stored")
	check(String(row.get("current_phase", "")) == "missile", "current_phase stored")
	check(String(row.get("outcome", "")) == "", "outcome empty for active battle")


func test_update_battle_field_whitelist() -> void:
	var id := _create_battle()
	check(BattleRepository.update_battle(id, {
		"current_phase": "skirmish",
		"current_bpc": 0,
		"battle_turn_number": 4,
	}), "valid update succeeds")
	var row := BattleRepository.get_battle(id)
	check(String(row.get("current_phase", "")) == "skirmish", "phase mutated")
	check(int(row.get("current_bpc", 99)) == 0, "bpc mutated")
	check(int(row.get("battle_turn_number", 0)) == 4, "turn mutated")
	# Bad-field rejection.
	var ok := BattleRepository.update_battle(id, {"campaign_id": "evil"})
	check(not ok, "rejects non-whitelisted field")


func test_unit_state_round_trip() -> void:
	var battle_id := _create_battle()
	var state_id := BattleRepository.create_unit_state({
		"battle_id": battle_id,
		"troop_unit_id": _troop_unit_id,
		"side": "attacker",
		"zone": "missile",
		"status": "engaged",
		"br_at_battle_start": 2.0,
		"br_current": 2.0,
	})
	check(not state_id.is_empty(), "create_unit_state returned id")
	var states := BattleRepository.list_unit_states_for_battle(battle_id)
	check(states.size() == 1, "1 state row")
	check(BattleRepository.update_unit_state(state_id, {
		"zone": "skirmish",
		"status": "wavering",
		"br_current": 1.0,
	}), "update succeeded")
	var by_side := BattleRepository.list_unit_states_for_side(battle_id, "attacker")
	check(by_side.size() == 1, "list by side returns the row")
	check(String(by_side[0].get("status", "")) == "wavering", "status mutated")


func test_unit_state_filtering_by_zone() -> void:
	var battle_id := _create_battle()
	for zone in ["missile", "skirmish", "melee", "reserve"]:
		var unit_id: String = TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": _ruler_a,
			"source_type": "mercenary", "troop_type": "Inf",
			"count": 30, "starting_count": 30, "battle_rating": 1.0,
		})
		BattleRepository.create_unit_state({
			"battle_id": battle_id, "troop_unit_id": unit_id,
			"side": "attacker", "zone": zone,
			"br_at_battle_start": 1.0, "br_current": 1.0,
		})
	for zone in ["missile", "skirmish", "melee", "reserve"]:
		var rows := BattleRepository.list_unit_states_for_zone(battle_id, "attacker", zone)
		check(rows.size() == 1, "1 row in zone %s, got %d" % [zone, rows.size()])


func test_battle_log_sequence_numbers() -> void:
	var battle_id := _create_battle()
	var first := BattleRepository.append_log(battle_id, "battle_started", 1, "missile", 1, "", {"foo": 1}, 100)
	var second := BattleRepository.append_log(battle_id, "phase_started", 1, "missile", 1, "", {"bar": 2}, 100)
	var third := BattleRepository.append_log(battle_id, "phase_ended", 1, "missile", 1, "", {"baz": 3}, 100)
	check(not first.is_empty() and not second.is_empty() and not third.is_empty(), "all appends succeeded")
	var entries := BattleRepository.list_log_for_battle(battle_id)
	check(entries.size() == 3, "3 log entries, got %d" % entries.size())
	check(int(entries[0].get("sequence_number", 0)) == 1, "first seq = 1")
	check(int(entries[1].get("sequence_number", 0)) == 2, "second seq = 2")
	check(int(entries[2].get("sequence_number", 0)) == 3, "third seq = 3")
	# Payload round-trips as JSON.
	var parsed_first: Variant = JSON.parse_string(String(entries[0].get("payload_json", "{}")))
	check(parsed_first is Dictionary and int(parsed_first.get("foo", 0)) == 1, "payload round-trips")
