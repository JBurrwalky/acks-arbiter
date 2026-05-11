extends "res://tests/test_suite_base.gd"

## Tests for RetreatResolver per daw_axioms_pitching_battle.xml §retreat L565-571.


var _campaign_id: String = ""
var _ruler_a: String = ""
var _ruler_b: String = ""
var _map_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_rejects_when_not_withdrawing()
	test_default_retreat_direction()
	test_retreat_into_supply_base_direction()
	test_retreat_uses_alternate_when_path_blocked()
	test_retreat_updates_army_state_to_encamped()
	if not has_failures():
		print("RetreatResolver: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Retreat Test", "World")
	_ruler_a = _make_character("Lord A")
	_ruler_b = _make_character("Lord B")
	_map_id = CampaignRepository.generate_id()


func _make_character(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 12, 60, 60)
	""", [id, _campaign_id, name])
	return id


func _make_army(owner_id: String, state: String, hex_q: int, hex_r: int) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Test Army",
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": state,
		"map_id": _map_id, "hex_q": hex_q, "hex_r": hex_r,
	})
	ArmyRepository.create_supply_state({"army_id": army_id})
	return army_id


func test_rejects_when_not_withdrawing() -> void:
	var army_id := _make_army(_ruler_a, "encamped", 5, 5)
	var result := RetreatResolver.resolve_retreat(army_id, 100)
	check(not bool(result.get("success", true)), "rejects encamped army")
	check(String(result.get("reason", "")) == "army_not_withdrawing", "reason cited")


func test_default_retreat_direction() -> void:
	var army_id := _make_army(_ruler_a, "withdrawing", 10, 10)
	var result := RetreatResolver.resolve_retreat(army_id, 100)
	check(bool(result.get("success", false)), "retreat ok")
	# No supply base set; default direction is (-1, 0) → from (10,10) to (9,10).
	check(int(result.get("to_hex_q", 0)) == 9, "default direction reduces q by 1")
	check(int(result.get("to_hex_r", 0)) == 10, "default direction keeps r")


func test_retreat_into_supply_base_direction() -> void:
	# Without a real strongholds table populated for the test harness, this
	# falls back to the default direction. The "find supply base hex" path
	# is best-effort in v1 (Phase 9 will refine). Verify it doesn't crash.
	var army_id := _make_army(_ruler_a, "withdrawing", 5, 5)
	# Set a fake supply_base_stronghold_id; the resolver tries to look up its
	# hex via _stronghold_hex which may return [] for unknown ids — falling
	# back to the default direction.
	ArmyRepository.update_supply_state(army_id, {
		"supply_base_stronghold_id": CampaignRepository.generate_id(),
	})
	var result := RetreatResolver.resolve_retreat(army_id, 100)
	check(bool(result.get("success", false)), "retreat ok with unknown supply base")
	check(int(result.get("from_hex_q", 0)) == 5, "from_hex_q recorded")


func test_retreat_uses_alternate_when_path_blocked() -> void:
	# Place a hostile army on the default-direction hex.
	var retreating_army := _make_army(_ruler_a, "withdrawing", 10, 10)
	var blocker := ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Blocker",
		"political_owner_id": _ruler_b, "command_character_id": _ruler_b,
		"state": "encamped", "map_id": _map_id, "hex_q": 9, "hex_r": 10,
	})
	var _b := blocker
	var result := RetreatResolver.resolve_retreat(retreating_army, 100)
	check(bool(result.get("success", false)), "retreat ok")
	# Default would be (9,10) but that's blocked → use an empty adjacent.
	# The resolver picks the first empty in ADJACENT_DELTAS order.
	check(int(result.get("to_hex_q", 0)) != 9 or int(result.get("to_hex_r", 0)) != 10,
		"did not retreat into blocked hex; got (%d,%d)" % [
			result.get("to_hex_q", 0), result.get("to_hex_r", 0)
		])


func test_retreat_updates_army_state_to_encamped() -> void:
	var army_id := _make_army(_ruler_a, "withdrawing", 7, 7)
	RetreatResolver.resolve_retreat(army_id, 100)
	var army := ArmyRepository.get_army(army_id)
	check(String(army.get("state", "")) == "encamped", "state transitioned to encamped after retreat")
