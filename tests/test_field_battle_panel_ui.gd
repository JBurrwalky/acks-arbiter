extends "res://tests/test_suite_base.gd"

## UI tests for field_battle_panel + battle_log_viewer + commander_departure_modal.

const FieldBattlePanelScript := preload("res://scenes/ui/battle/field_battle_panel.gd")
const BattleLogViewerScript := preload("res://scenes/ui/battle/battle_log_viewer.gd")
const CommanderDepartureModalScript := preload("res://scenes/ui/troops/commander_departure_modal.gd")

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_field_battle_panel_opens_for_battle()
	test_field_battle_panel_renders_zone_units()
	test_battle_log_viewer_displays_entries()
	test_commander_departure_modal_lists_successor_candidates()
	test_commander_departure_modal_disband_action()
	if not has_failures():
		print("FieldBattlePanelUI: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("PanelUI Test", "World")


func _make_npc(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 12, 60, 60)
	""", [id, _campaign_id, name])
	return id


func _build_army(name: String, owner_id: String, br: float = 1.0, count: int = 3) -> String:
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": name,
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": "marching", "unit_scale": "company",
		"map_id": CampaignRepository.generate_id(), "hex_q": 0, "hex_r": 0,
	})
	var leader: String = ArmyRepository.create_officer({
		"army_id": army_id, "character_id": owner_id, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	for i in range(count):
		var unit_id: String = TroopUnitRepository.create_unit({
			"campaign_id": _campaign_id, "owner_character_id": owner_id,
			"source_type": "mercenary", "troop_type": "Heavy Infantry",
			"count": 60, "starting_count": 60, "battle_rating": br,
		})
		ArmyRepository.create_assignment({
			"army_id": army_id, "troop_unit_id": unit_id,
			"parent_officer_id": leader, "role": "line",
			"assigned_calendar_day": 100,
		})
	return army_id


func test_field_battle_panel_opens_for_battle() -> void:
	var atk := _build_army("AtkUI", _make_npc("Atk"))
	var def := _build_army("DefUI", _make_npc("Def"))
	var battle_id := FieldBattleResolver.start_battle(
		atk, def, "clear_or_grass", "calm", 100, true,
		func(_c, sides): return sides
	)
	var panel = FieldBattlePanelScript.new()
	add_child(panel)
	panel.open_for_battle(battle_id)
	check(panel.visible, "panel becomes visible on open")
	check(panel._battle_id == battle_id, "battle_id captured")
	# Header should reflect the battle hex.
	check(panel._header_label.text.contains("Battle of"), "header text set")
	panel.queue_free()


func test_field_battle_panel_renders_zone_units() -> void:
	var atk := _build_army("AtkUI2", _make_npc("Atk2"))
	var def := _build_army("DefUI2", _make_npc("Def2"))
	var battle_id := FieldBattleResolver.start_battle(
		atk, def, "clear_or_grass", "calm", 100, true,
		func(_c, sides): return sides
	)
	var panel = FieldBattlePanelScript.new()
	add_child(panel)
	panel.open_for_battle(battle_id)
	# Each zone box should have something (units) in attacker side melee.
	# All units default to melee zone for non-missile-eligible types.
	var melee_box: VBoxContainer = panel._attacker_zones["melee"]
	check(melee_box.get_child_count() >= 1, "attacker melee zone has units; got %d" % melee_box.get_child_count())
	panel.queue_free()


func test_battle_log_viewer_displays_entries() -> void:
	var atk := _build_army("LogAtk", _make_npc("LogAtk"))
	var def := _build_army("LogDef", _make_npc("LogDef"))
	var battle_id := FieldBattleResolver.start_battle(
		atk, def, "hills", "calm", 100, false,
		func(_c, sides): return sides
	)
	var viewer = BattleLogViewerScript.new()
	add_child(viewer)
	viewer.display(battle_id)
	# Each setup event (battle_started, surprise_resolved, etc.) gets one row.
	check(viewer._list.get_child_count() >= 4, "viewer has ≥ 4 setup events; got %d" % viewer._list.get_child_count())
	check(viewer._header_label.text.contains("Battle Log"), "header includes 'Battle Log'")
	viewer.queue_free()


func test_commander_departure_modal_lists_successor_candidates() -> void:
	var pc := _make_npc("DepartingPC")
	var hench := _make_npc("Successor")
	# Override character_type to henchman for hench.
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET character_type = 'henchman' WHERE id = ?", [hench])
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Departure Host",
		"political_owner_id": pc, "command_character_id": pc, "state": "encamped",
	})
	var leader_oid := ArmyRepository.create_officer({
		"army_id": army_id, "character_id": pc, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	ArmyRepository.create_officer({
		"army_id": army_id, "character_id": hench, "rank": "division_commander",
		"parent_officer_id": leader_oid, "appointed_calendar_day": 100,
	})
	var modal = CommanderDepartureModalScript.new()
	add_child(modal)
	modal.set_army(army_id, pc)
	check(modal._successor_candidates.size() == 1, "1 successor candidate (hench, excludes departing PC)")
	check(not modal._appoint_btn.disabled, "appoint button enabled with valid candidate")
	modal.queue_free()


func test_commander_departure_modal_disband_action() -> void:
	var pc := _make_npc("DisbanderPC")
	var army_id: String = ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "Disband Host",
		"political_owner_id": pc, "command_character_id": pc, "state": "encamped",
	})
	ArmyRepository.create_officer({
		"army_id": army_id, "character_id": pc, "rank": "army_leader",
		"appointed_calendar_day": 100,
	})
	var modal = CommanderDepartureModalScript.new()
	add_child(modal)
	modal.set_army(army_id, pc)
	# Pressing the disband button should disband.
	var disband_signal_received := [false]
	modal.army_disbanded_emitted.connect(func(_aid):
		disband_signal_received[0] = true
	)
	modal._on_disband_pressed()
	check(disband_signal_received[0], "army_disbanded_emitted fired")
	var army := ArmyRepository.get_army(army_id)
	check(String(army.get("state", "")) == "disbanded", "state=disbanded")
	modal.queue_free()
