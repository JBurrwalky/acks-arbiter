extends "res://tests/test_suite_base.gd"

## Tests for BattleDispatcher routing logic.


var _campaign_id: String = ""


func _max_roller(_count: int, sides: int) -> int:
	return sides


func run_all_tests() -> void:
	_setup()
	test_npc_vs_npc_resolves_silently()
	test_pc_owned_routes_interactive()
	test_dispatch_returns_battle_id()
	if not has_failures():
		print("BattleDispatcher: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Dispatcher Test", "World")


func _make_character(name: String, character_type: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, ?, 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 12, 60, 60)
	""", [id, _campaign_id, name, character_type])
	return id


func _build_army(name: String, owner_id: String, state: String, br_per_unit: float, count: int) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": name,
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": state, "unit_scale": "company",
	})
	var leader_id: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": owner_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	for i in range(count):
		var unit_id: String = TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": owner_id,
			"source_type": "mercenary", "troop_type": "Inf",
			"count": 30, "starting_count": 30, "battle_rating": br_per_unit,
		})
		ArmyRepository.create_assignment({
			"army_id": army_id, "troop_unit_id": unit_id,
			"parent_officer_id": leader_id, "role": "line",
			"assigned_calendar_day": 100,
		})
	return army_id


func test_npc_vs_npc_resolves_silently() -> void:
	var npc_a := _make_character("NPC A", "npc")
	var npc_b := _make_character("NPC B", "npc")
	var army_a := _build_army("AlphaA", npc_a, "marching", 2.0, 3)
	var army_b := _build_army("BravoB", npc_b, "encamped", 1.0, 3)
	var roller := func(_c, sides): return sides
	var result := BattleDispatcher.dispatch_collision(army_a, army_b, 1, 1, 100, roller)
	check(String(result.get("mode", "")) == BattleDispatcher.MODE_SILENT, "NPC-vs-NPC = silent")
	check(not String(result.get("battle_id", "")).is_empty(), "battle_id returned")
	check(not String(result.get("outcome", "")).is_empty(), "outcome returned")


func test_pc_owned_routes_interactive() -> void:
	var pc := _make_character("Hero", "pc")
	var npc := _make_character("Bandit Chief", "npc")
	var pc_army := _build_army("Hero Host", pc, "marching", 2.0, 3)
	var bandit_army := _build_army("Bandit Host", npc, "encamped", 1.0, 3)
	var pause_received := [false]
	EventBus.battle_pause_for_player.connect(func(_bid, _decision_point):
		pause_received[0] = true
	)
	var result := BattleDispatcher.dispatch_collision(pc_army, bandit_army, 2, 2, 100, Callable())
	check(String(result.get("mode", "")) == BattleDispatcher.MODE_INTERACTIVE, "PC-owned = interactive")
	check(pause_received[0], "battle_pause_for_player signal fired")
	check(String(result.get("outcome", "")) == "", "outcome empty for interactive (UI-driven)")


func test_dispatch_returns_battle_id() -> void:
	var npc_a := _make_character("Disp NPC A", "npc")
	var npc_b := _make_character("Disp NPC B", "npc")
	var army_a := _build_army("Disp Alpha", npc_a, "marching", 1.5, 3)
	var army_b := _build_army("Disp Bravo", npc_b, "encamped", 1.5, 3)
	var roller := func(_c, sides): return sides
	var result := BattleDispatcher.dispatch_collision(army_a, army_b, 3, 3, 100, roller)
	var battle_id: String = String(result.get("battle_id", ""))
	check(not battle_id.is_empty(), "battle_id returned")
	# The battle row should exist with this id and a non-empty outcome.
	var battle := BattleRepository.get_battle(battle_id)
	check(not battle.is_empty(), "battle row exists")
	check(String(battle.get("outcome", "")) != "", "battle has outcome")
