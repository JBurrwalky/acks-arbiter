extends "res://tests/test_suite_base.gd"

## Tests for BattleXPDistributor per daw_axioms_pitching_battle.xml
## §experience_points L630-645.


var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_mutual_withdrawal_returns_zero()
	test_distribute_credits_leader_50_percent()
	test_distribute_credits_dcs_proportionally()
	test_distribute_increments_unit_xp_for_troops()
	if not has_failures():
		print("BattleXPDistributor: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("XP Dist Test", "World")


func _make_npc(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current, xp)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 12, 60, 60, 0)
	""", [id, _campaign_id, name])
	return id


func _build_army(name: String, owner_id: String) -> String:
	return ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": name,
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": "battling",
	})


func _make_unit(owner_id: String, br: float, wage: int) -> String:
	return TroopUnitRepository.create_unit({
		"campaign_id": _campaign_id, "owner_character_id": owner_id,
		"source_type": "mercenary", "troop_type": "Inf",
		"count": 60, "starting_count": 60, "battle_rating": br,
		"monthly_wage_cp": wage,
	})


func _get_xp(character_id: String) -> int:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT xp FROM characters WHERE id = ?", [character_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("xp", 0))


func test_mutual_withdrawal_returns_zero() -> void:
	var atk_owner := _make_npc("AtkLord")
	var def_owner := _make_npc("DefLord")
	var attacker := _build_army("Atk", atk_owner)
	var defender := _build_army("Def", def_owner)
	var battle_id := BattleRepository.create_battle({
		"campaign_id": _campaign_id,
		"attacker_army_id": attacker, "defender_army_id": defender,
		"outcome": "mutual_withdrawal_draw",
	})
	var result := BattleXPDistributor.distribute(battle_id, 100000, 100)  # 1000 gp = 100,000 cp
	check(bool(result.get("success", false)), "mutual withdrawal still returns success")
	check(int(result.get("total_distributed_xp", -1)) == 0, "no XP distributed in mutual draw")


func test_distribute_credits_leader_50_percent() -> void:
	var atk_owner := _make_npc("Leader1")
	var def_owner := _make_npc("EnemyLord")
	var attacker := _build_army("Atk2", atk_owner)
	var defender := _build_army("Def2", def_owner)
	# Attacker leader is the only officer; no DCs. So leader gets all officer XP.
	ArmyRepository.create_officer({
		"army_id": attacker, "character_id": atk_owner, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	var battle_id := BattleRepository.create_battle({
		"campaign_id": _campaign_id,
		"attacker_army_id": attacker, "defender_army_id": defender,
		"outcome": "attacker_victory",
	})
	# Add an attacker unit so the troops_pool has a recipient (otherwise it
	# falls into "equal distribution if no wage data" path on empty list).
	# Per the 2026-05-16 army wage cp pass, _make_unit's wage arg is cp; 100 × 100 = 10000 cp.
	var atk_unit: String = _make_unit(atk_owner, 1.0, 10000)
	ArmyRepository.create_assignment({
		"army_id": attacker, "troop_unit_id": atk_unit,
		"parent_officer_id": ArmyRepository.list_officers_for_army(attacker)[0]["id"],
		"role": "line", "assigned_calendar_day": 100,
	})
	# distribute() takes spoils in cp; 1000 gp = 100,000 cp.
	var spoils_cp := 100000
	var result := BattleXPDistributor.distribute(battle_id, spoils_cp, 100)
	check(bool(result.get("success", false)), "distribute ok")
	# 100,000 cp / 100 = 1000 gp for XP allocation. With no DCs, commanders_pool
	# collapses back to leader → leader_xp = officer_total = 500 (officers' half
	# of 1000 gp spoils) + combat_xp (spoils_gp - lost_value, here 1000 - 0 = 1000).
	# leader_xp ≥ 50% × (500 + 1000) = 750.
	var leader_xp_actual: int = _get_xp(atk_owner)
	check(leader_xp_actual >= 750, "leader xp ≥ 750; got %d" % leader_xp_actual)


func test_distribute_credits_dcs_proportionally() -> void:
	var leader_id := _make_npc("Leader3")
	var dc1 := _make_npc("DC1")
	var dc2 := _make_npc("DC2")
	var def_owner := _make_npc("EnemyLord3")
	var attacker := _build_army("Atk3", leader_id)
	var defender := _build_army("Def3", def_owner)
	var leader_oid := ArmyRepository.create_officer({
		"army_id": attacker, "character_id": leader_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	var dc1_oid := ArmyRepository.create_officer({
		"army_id": attacker, "character_id": dc1, "rank": "division_commander",
		"parent_officer_id": leader_oid, "appointed_calendar_day": 100,
	})
	var dc2_oid := ArmyRepository.create_officer({
		"army_id": attacker, "character_id": dc2, "rank": "division_commander",
		"parent_officer_id": leader_oid, "appointed_calendar_day": 100,
	})
	# DC1 leads 3 units; DC2 leads 1 unit.
	for i in range(3):
		var u: String = _make_unit(leader_id, 1.0, 10000)
		ArmyRepository.create_assignment({
			"army_id": attacker, "troop_unit_id": u,
			"parent_officer_id": dc1_oid, "role": "line", "assigned_calendar_day": 100,
		})
	var u4: String = _make_unit(leader_id, 1.0, 10000)
	ArmyRepository.create_assignment({
		"army_id": attacker, "troop_unit_id": u4,
		"parent_officer_id": dc2_oid, "role": "line", "assigned_calendar_day": 100,
	})
	var battle_id := BattleRepository.create_battle({
		"campaign_id": _campaign_id,
		"attacker_army_id": attacker, "defender_army_id": defender,
		"outcome": "attacker_victory",
	})
	BattleXPDistributor.distribute(battle_id, 100000, 100)  # 1000 gp = 100,000 cp
	var dc1_xp := _get_xp(dc1)
	var dc2_xp := _get_xp(dc2)
	# DC1 should have ~3× DC2's XP (proportional to units led: 3:1).
	check(dc1_xp > dc2_xp, "DC1 (3 units) > DC2 (1 unit); got %d vs %d" % [dc1_xp, dc2_xp])
	check(dc1_xp >= 2 * dc2_xp, "DC1 ≥ 2× DC2 (expecting 3× ratio); got %d vs %d" % [dc1_xp, dc2_xp])


func test_distribute_increments_unit_xp_for_troops() -> void:
	var leader_id := _make_npc("Leader4")
	var def_owner := _make_npc("EnemyLord4")
	var attacker := _build_army("Atk4", leader_id)
	var defender := _build_army("Def4", def_owner)
	var leader_oid := ArmyRepository.create_officer({
		"army_id": attacker, "character_id": leader_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	var unit_id: String = _make_unit(leader_id, 1.0, 10000)
	ArmyRepository.create_assignment({
		"army_id": attacker, "troop_unit_id": unit_id,
		"parent_officer_id": leader_oid, "role": "line", "assigned_calendar_day": 100,
	})
	var battle_id := BattleRepository.create_battle({
		"campaign_id": _campaign_id,
		"attacker_army_id": attacker, "defender_army_id": defender,
		"outcome": "attacker_victory",
	})
	BattleXPDistributor.distribute(battle_id, 100000, 100)  # 1000 gp = 100,000 cp
	var unit := TroopUnitRepository.get_unit(unit_id)
	check(int(unit.get("unit_xp", 0)) > 0, "unit_xp incremented from troops_pool")
