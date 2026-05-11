extends "res://tests/test_suite_base.gd"

## Tests for ArmyMoraleResolver per daw_axioms_pitching_battle.xml
## §ending_battles.morale_collapse + §morale_rolls.


func run_all_tests() -> void:
	test_break_point_one_third_rounded_up()
	test_should_check_morale_requires_destroyed_this_phase()
	test_result_table_boundaries()
	test_modifiers_loss_fraction_two_thirds()
	test_modifiers_loss_fraction_half()
	test_modifiers_cannot_retreat_plus_2()
	test_modifiers_unit_wavering_minus_2()
	test_modifiers_unit_fleeing_minus_5()
	if not has_failures():
		print("ArmyMoraleResolver: all tests passed.")


func test_break_point_one_third_rounded_up() -> void:
	check(ArmyMoraleResolver.compute_break_point(1) == 1, "1/3 of 1 ceil = 1")
	check(ArmyMoraleResolver.compute_break_point(3) == 1, "1/3 of 3 = 1")
	check(ArmyMoraleResolver.compute_break_point(4) == 2, "1/3 of 4 ceil = 2")
	check(ArmyMoraleResolver.compute_break_point(9) == 3, "1/3 of 9 = 3")
	check(ArmyMoraleResolver.compute_break_point(10) == 4, "1/3 of 10 ceil = 4")


func test_should_check_morale_requires_destroyed_this_phase() -> void:
	# Even if destroyed-so-far ≥ break point, no check unless a unit was destroyed this phase.
	check(not ArmyMoraleResolver.should_check_morale(9, 5, false), "no check when no unit destroyed this phase")
	check(ArmyMoraleResolver.should_check_morale(9, 3, true), "check fires at break-point with destroyed-this-phase=true")
	check(not ArmyMoraleResolver.should_check_morale(9, 2, true), "below break-point → no check")


func test_result_table_boundaries() -> void:
	# Use a fixed roller that returns specific values to map adjusted_roll → result.
	var unit_state := {"id": "u1", "troop_unit_id": "tu1", "status": "engaged"}
	var ctx := {
		"army_leader_present": false, "army_morale_modifier": 0,
		"starting_br_total": 10.0, "current_br_total": 10.0,
		"opposing_br_destroyed": 0.0, "opposing_br_lost": 0.0,
	}
	# Inject a mock for _get_unit_morale by writing directly through the test:
	# v1 reads from troop_units; create a unit row to back this.
	var campaign_id: String = CampaignRepository.create_campaign("Morale Test", "World")
	var owner_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Owner', 'pc', 'full', 'human', 'fighter', 5,
			12, 12, 12, 12, 12, 12, 30, 30)
	""", [owner_id, campaign_id])
	var tu_id: String = TroopUnitRepository.create_unit({
		"campaign_id": campaign_id, "owner_character_id": owner_id,
		"source_type": "mercenary", "troop_type": "test",
		"count": 60, "starting_count": 60, "battle_rating": 1.0,
		"morale": 0,  # neutral morale so adjusted = roll
	})
	unit_state["troop_unit_id"] = tu_id

	# Test rollers return the TOTAL of count d sides (the resolver passes count
	# and sides to the roller; if roller returns a single int it's used as the
	# total directly).
	# Adjusted = roll_total + unit_morale (0) + modifiers (0).
	var r2 := ArmyMoraleResolver.resolve_unit_morale(unit_state, ctx, func(_c, _s): return 2)
	check(String(r2.get("result", "")) == "rout", "adjusted 2 = rout; got %s" % r2.get("result", "?"))

	var r4 := ArmyMoraleResolver.resolve_unit_morale(unit_state, ctx, func(_c, _s): return 4)
	check(String(r4.get("result", "")) == "flee", "adjusted 4 = flee")

	var r6 := ArmyMoraleResolver.resolve_unit_morale(unit_state, ctx, func(_c, _s): return 6)
	check(String(r6.get("result", "")) == "waver", "adjusted 6 = waver")

	var r10 := ArmyMoraleResolver.resolve_unit_morale(unit_state, ctx, func(_c, _s): return 10)
	check(String(r10.get("result", "")) == "stand_firm", "adjusted 10 = stand_firm")

	var r12 := ArmyMoraleResolver.resolve_unit_morale(unit_state, ctx, func(_c, _s): return 12)
	check(String(r12.get("result", "")) == "rally", "adjusted 12 = rally")


func test_modifiers_loss_fraction_two_thirds() -> void:
	var unit_state := {"id": "u1", "troop_unit_id": "tu_morale_modtest", "status": "engaged"}
	var ctx := {
		"army_leader_present": false, "army_morale_modifier": 0,
		"starting_br_total": 12.0, "current_br_total": 4.0,  # lost 8/12 = 2/3
		"opposing_br_destroyed": 0.0,
	}
	var mods := ArmyMoraleResolver.compute_modifiers(unit_state, ctx)
	check(mods.has("lost_two_thirds_or_more"), "lost ≥ 2/3 modifier present")
	check(int(mods.get("lost_two_thirds_or_more", 0)) == -5, "modifier -5")


func test_modifiers_loss_fraction_half() -> void:
	var unit_state := {"id": "u1", "status": "engaged"}
	var ctx := {
		"starting_br_total": 12.0, "current_br_total": 6.0,  # lost 6/12 = 1/2
		"opposing_br_destroyed": 0.0,
	}
	var mods := ArmyMoraleResolver.compute_modifiers(unit_state, ctx)
	check(mods.has("lost_half_to_two_thirds"), "lost ≥ 1/2 < 2/3 modifier present")
	check(int(mods.get("lost_half_to_two_thirds", 0)) == -2, "modifier -2")


func test_modifiers_cannot_retreat_plus_2() -> void:
	var unit_state := {"id": "u1", "status": "engaged"}
	var ctx := {
		"starting_br_total": 10.0, "current_br_total": 10.0,
		"opposing_br_destroyed": 0.0,
		"cannot_retreat": true,
	}
	var mods := ArmyMoraleResolver.compute_modifiers(unit_state, ctx)
	check(int(mods.get("cannot_retreat", 0)) == 2, "cannot_retreat = +2")


func test_modifiers_unit_wavering_minus_2() -> void:
	var unit_state := {"id": "u1", "status": "wavering"}
	var ctx := {"starting_br_total": 10.0, "current_br_total": 10.0}
	var mods := ArmyMoraleResolver.compute_modifiers(unit_state, ctx)
	check(int(mods.get("unit_wavering", 0)) == -2, "wavering = -2")


func test_modifiers_unit_fleeing_minus_5() -> void:
	var unit_state := {"id": "u1", "status": "fleeing"}
	var ctx := {"starting_br_total": 10.0, "current_br_total": 10.0}
	var mods := ArmyMoraleResolver.compute_modifiers(unit_state, ctx)
	check(int(mods.get("unit_fleeing", 0)) == -5, "fleeing = -5")
