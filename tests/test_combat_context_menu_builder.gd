extends "res://tests/test_suite_base.gd"

## Unit tests for CombatContextMenuBuilder — verifies correct menu options
## appear for various combat situations: empty cells, enemies, allies,
## downed entities, self-clicks, engagement restrictions, and proficiencies.

const Builder := preload("res://engine/subsystems/combat/combat_context_menu_builder.gd")


func run_all_tests() -> void:
	test_universal_options_always_present()
	test_empty_cell_movement_options()
	test_enemy_cell_attack_options()
	test_self_click_self_options()
	test_ally_click_ally_options()
	test_downed_click_downed_options()
	test_engaged_no_movement()
	test_engaged_with_skirmishing()
	test_charge_option_when_valid()
	test_backstab_thief_conditions()
	test_maneuver_submenu_present()
	test_maneuver_combat_trickery_penalty()
	test_ranged_attack_not_engaged()
	test_prone_stand_up_option()
	if not has_failures():
		print("CombatContextMenuBuilder: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a minimal mock controller with the fields the builder needs.
func _make_controller(
	combatants: Array[Combatant],
	map: TacticalMapData = null,
) -> Dictionary:
	## Returns a mock controller as a Dictionary, duck-typed for the builder.
	## We build a real CombatRoster and MovementResolver for accurate tests.
	var roster := CombatRoster.new()
	for c in combatants:
		roster.add(c)

	var mr: MovementResolver = null
	if map != null:
		mr = MovementResolver.new(map, roster)

	return {
		"roster": roster,
		"movement_resolver": mr,
		"tactical_map": map,
		"condition_manager": null,
	}


func _make_pc(id: String, name: String, progression: String = "fighter",
		level: int = 1, hp: int = 10) -> Combatant:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = name
	cd.combat_progression = progression
	cd.level = level
	cd.hp_max = hp
	cd.hp_current = hp
	cd.base_movement = 120
	var c := Combatant.from_character(cd, id)
	return c


func _make_enemy(id: String, name: String, hp: int = 5) -> Combatant:
	var monster_data := {
		"name": name,
		"hit_dice": {"base": 1},
		"armor_class": 3,
		"morale": 0,
		"movement": {"land": {"exploration": 120, "combat": 40}},
		"attack_routines": [{"attacks": [{"attack_type": "natural", "damage": "1d6"}]}],
	}
	var c := Combatant.from_monster(monster_data, hp, id)
	return c


func _make_map_with_cells(cell_positions: Array[Vector2i]) -> TacticalMapData:
	var cells := []
	for pos in cell_positions:
		cells.append({"col": pos.x, "row": pos.y, "terrain_feature": "open"})
	var data := {
		"grid_width": 20,
		"grid_height": 20,
		"entry_col": 0,
		"entry_row": 0,
		"cells": cells,
		"transition_cells": [],
	}
	return TacticalMapData.from_dict(data)


func _find_option(options: Array, id: String) -> Dictionary:
	for opt in options:
		if opt.get("id") == id:
			return opt
	return {}


func _has_option(options: Array, id: String) -> bool:
	return not _find_option(options, id).is_empty()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_universal_options_always_present() -> void:
	var pc := _make_pc("pc1", "Bran")
	pc.grid_position = Vector2i(5, 5)
	var map := _make_map_with_cells([Vector2i(5, 5), Vector2i(6, 5)])
	map.set_entity_pos("pc1", Vector2i(5, 5))
	var ctrl := _make_controller([pc], map)
	var result := Builder.build_menu("pc1", Vector2i(6, 5), ctrl, null)
	check(_has_option(result, "pass"), "Pass should be present")
	check(_has_option(result, "delay"), "Delay should be present")
	check(_has_option(result, "cancel"), "Cancel should be present")
	print("  universal_options_always_present: OK")


func test_empty_cell_movement_options() -> void:
	var pc := _make_pc("pc1", "Bran")
	pc.grid_position = Vector2i(5, 5)
	var map := _make_map_with_cells([Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)])
	map.set_entity_pos("pc1", Vector2i(5, 5))
	var ctrl := _make_controller([pc], map)
	var result := Builder.build_menu("pc1", Vector2i(6, 5), ctrl, null)
	check(_has_option(result, "move_here"), "Move Here should be present for empty cell")
	var move_opt := _find_option(result, "move_here")
	check(move_opt.get("enabled", false), "Move Here should be enabled for reachable cell")
	print("  empty_cell_movement_options: OK")


func test_enemy_cell_attack_options() -> void:
	var pc := _make_pc("pc1", "Bran")
	pc.grid_position = Vector2i(5, 5)
	pc.set_equipped_weapon({"name": "Sword", "weapon_damage": "1d8", "weapon_tags": ["melee"]})
	var enemy := _make_enemy("gob1", "Goblin")
	enemy.grid_position = Vector2i(6, 5)
	var map := _make_map_with_cells([Vector2i(5, 5), Vector2i(6, 5)])
	map.set_entity_pos("pc1", Vector2i(5, 5))
	map.set_entity_pos("gob1", Vector2i(6, 5))
	var ctrl := _make_controller([pc, enemy], map)
	var result := Builder.build_menu("pc1", Vector2i(6, 5), ctrl, null)
	check(_has_option(result, "attack_melee"), "Melee Attack should be present for adjacent enemy")
	check(_has_option(result, "combat_maneuver"), "Combat Maneuver submenu should be present")
	print("  enemy_cell_attack_options: OK")


func test_self_click_self_options() -> void:
	var pc := _make_pc("pc1", "Bran")
	pc.grid_position = Vector2i(5, 5)
	var map := _make_map_with_cells([Vector2i(5, 5)])
	map.set_entity_pos("pc1", Vector2i(5, 5))
	var ctrl := _make_controller([pc], map)
	var result := Builder.build_menu("pc1", Vector2i(5, 5), ctrl, null)
	check(_has_option(result, "use_item"), "Use Item should be present for self-click")
	check(_has_option(result, "drop_item"), "Drop Item should be present for self-click")
	check(_has_option(result, "switch_weapon"), "Sheathe & Draw should be present")
	check(not _has_option(result, "move_here"), "Move Here should NOT be present for self-click")
	print("  self_click_self_options: OK")


func test_ally_click_ally_options() -> void:
	var pc := _make_pc("pc1", "Bran")
	pc.grid_position = Vector2i(5, 5)
	var ally := _make_pc("pc2", "Yara")
	ally.grid_position = Vector2i(6, 5)
	var map := _make_map_with_cells([Vector2i(5, 5), Vector2i(6, 5)])
	map.set_entity_pos("pc1", Vector2i(5, 5))
	map.set_entity_pos("pc2", Vector2i(6, 5))
	var ctrl := _make_controller([pc, ally], map)
	var result := Builder.build_menu("pc1", Vector2i(6, 5), ctrl, null)
	check(_has_option(result, "trade"), "Trade should be present for adjacent ally")
	check(_has_option(result, "heal_ally"), "Heal should be present for ally")
	print("  ally_click_ally_options: OK")


func test_downed_click_downed_options() -> void:
	var pc := _make_pc("pc1", "Bran")
	pc.grid_position = Vector2i(5, 5)
	var downed_enemy := _make_enemy("gob1", "Goblin", 0)
	downed_enemy.grid_position = Vector2i(6, 5)
	downed_enemy.set_hp_current(0)
	var map := _make_map_with_cells([Vector2i(5, 5), Vector2i(6, 5)])
	map.set_entity_pos("pc1", Vector2i(5, 5))
	map.set_entity_pos("gob1", Vector2i(6, 5))
	var ctrl := _make_controller([pc, downed_enemy], map)
	var result := Builder.build_menu("pc1", Vector2i(6, 5), ctrl, null)
	check(_has_option(result, "check_status"), "Check Status should be present for downed entity")
	check(_has_option(result, "carry"), "Carry should be present for downed entity")
	check(_has_option(result, "coup_de_grace"), "Coup de Grace should be present for downed enemy")
	print("  downed_click_downed_options: OK")


func test_engaged_no_movement() -> void:
	var pc := _make_pc("pc1", "Bran")
	pc.grid_position = Vector2i(5, 5)
	var enemy := _make_enemy("gob1", "Goblin")
	enemy.grid_position = Vector2i(6, 5)
	var map := _make_map_with_cells([
		Vector2i(5, 5), Vector2i(6, 5), Vector2i(4, 5), Vector2i(3, 5)])
	map.set_entity_pos("pc1", Vector2i(5, 5))
	map.set_entity_pos("gob1", Vector2i(6, 5))
	var ctrl := _make_controller([pc, enemy], map)

	# Right-click an empty cell while engaged — movement should be disabled
	var result := Builder.build_menu("pc1", Vector2i(4, 5), ctrl, null)
	var move_opt := _find_option(result, "move_here")
	check(not move_opt.is_empty(), "Move Here should be present (but disabled)")
	check(not move_opt.get("enabled", true), "Move Here should be disabled when engaged without declaration")
	check("defensive movement" in move_opt.get("tooltip", "").to_lower(),
		"Tooltip should mention defensive movement")
	print("  engaged_no_movement: OK")


func test_engaged_with_skirmishing() -> void:
	var cd := CharacterData.new()
	cd.id = "pc1"
	cd.name = "Scout"
	cd.combat_progression = "thief"
	cd.level = 3
	cd.hp_max = 10
	cd.hp_current = 10
	cd.base_movement = 120
	# Add Skirmishing proficiency
	cd.proficiencies = [{"proficiency_key": "skirmishing", "rank": 1}]
	var pc := Combatant.from_character(cd, "pc1")
	pc.grid_position = Vector2i(5, 5)

	var enemy := _make_enemy("gob1", "Goblin")
	enemy.grid_position = Vector2i(6, 5)
	var map := _make_map_with_cells([
		Vector2i(5, 5), Vector2i(6, 5), Vector2i(4, 5)])
	map.set_entity_pos("pc1", Vector2i(5, 5))
	map.set_entity_pos("gob1", Vector2i(6, 5))
	var ctrl := _make_controller([pc, enemy], map)

	# Right-click an empty cell while engaged but with Skirmishing
	var result := Builder.build_menu("pc1", Vector2i(4, 5), ctrl, null)
	check(_has_option(result, "fighting_withdrawal"),
		"Fighting Withdrawal should be available with Skirmishing")
	check(_has_option(result, "full_retreat"),
		"Full Retreat should be available with Skirmishing")
	print("  engaged_with_skirmishing: OK")


func test_charge_option_when_valid() -> void:
	# Place PC at (2,5), enemy at (7,5) — 5 cells apart, straight line
	var pc := _make_pc("pc1", "Bran")
	pc.grid_position = Vector2i(2, 5)
	pc.set_equipped_weapon({"name": "Sword", "weapon_damage": "1d8", "weapon_tags": ["melee"]})
	var enemy := _make_enemy("gob1", "Goblin")
	enemy.grid_position = Vector2i(7, 5)

	# Build a map with cells along the line
	var cells: Array[Vector2i] = []
	for x in range(0, 10):
		cells.append(Vector2i(x, 5))
	# Add rows above/below for adjacency
	for x in range(0, 10):
		cells.append(Vector2i(x, 4))
		cells.append(Vector2i(x, 6))
	var map := _make_map_with_cells(cells)
	map.set_entity_pos("pc1", Vector2i(2, 5))
	map.set_entity_pos("gob1", Vector2i(7, 5))
	var ctrl := _make_controller([pc, enemy], map)

	# Right-click on the enemy — charge should be available (>= 4 cells = 20ft)
	var result := Builder.build_menu("pc1", Vector2i(7, 5), ctrl, null)
	check(_has_option(result, "charge"), "Charge should be available for distant enemy")
	print("  charge_option_when_valid: OK")


func test_backstab_thief_conditions() -> void:
	var pc := _make_pc("pc1", "Rogue", "thief", 5, 10)
	pc.grid_position = Vector2i(5, 5)
	pc.set_equipped_weapon({"name": "Dagger", "weapon_damage": "1d4", "weapon_tags": ["melee"]})
	var enemy := _make_enemy("gob1", "Goblin")
	enemy.grid_position = Vector2i(6, 5)
	enemy.add_condition("held")  # Held = backstab eligible
	var map := _make_map_with_cells([Vector2i(5, 5), Vector2i(6, 5)])
	map.set_entity_pos("pc1", Vector2i(5, 5))
	map.set_entity_pos("gob1", Vector2i(6, 5))
	var ctrl := _make_controller([pc, enemy], map)
	var result := Builder.build_menu("pc1", Vector2i(6, 5), ctrl, null)
	check(_has_option(result, "backstab"), "Backstab should be available for thief vs held enemy")
	# Check multiplier in label (level 5 = x3)
	var bs_opt := _find_option(result, "backstab")
	check("x3" in bs_opt.get("label", ""), "Backstab label should show x3 for level 5 thief")
	print("  backstab_thief_conditions: OK")


func test_maneuver_submenu_present() -> void:
	var pc := _make_pc("pc1", "Bran")
	pc.grid_position = Vector2i(5, 5)
	pc.set_equipped_weapon({"name": "Sword", "weapon_damage": "1d8", "weapon_tags": ["melee"]})
	var enemy := _make_enemy("gob1", "Goblin")
	enemy.grid_position = Vector2i(6, 5)
	var map := _make_map_with_cells([Vector2i(5, 5), Vector2i(6, 5)])
	map.set_entity_pos("pc1", Vector2i(5, 5))
	map.set_entity_pos("gob1", Vector2i(6, 5))
	var ctrl := _make_controller([pc, enemy], map)
	var result := Builder.build_menu("pc1", Vector2i(6, 5), ctrl, null)
	var maneuver_opt := _find_option(result, "combat_maneuver")
	check(not maneuver_opt.is_empty(), "Combat Maneuver submenu should be present")
	var sub := maneuver_opt.get("submenu_options", [])
	check(sub.size() >= 9, "Submenu should have at least 9 options (8 maneuvers + back)")
	# Verify disarm is in submenu
	var has_disarm := false
	for opt in sub:
		if opt.get("id") == "maneuver_disarm":
			has_disarm = true
	check(has_disarm, "Disarm should be in maneuver submenu")
	print("  maneuver_submenu_present: OK")


func test_maneuver_combat_trickery_penalty() -> void:
	var cd := CharacterData.new()
	cd.id = "pc1"
	cd.name = "Trickster"
	cd.combat_progression = "fighter"
	cd.level = 3
	cd.hp_max = 10
	cd.hp_current = 10
	cd.base_movement = 120
	cd.proficiencies = [{"proficiency_key": "combat_trickery", "rank": 1}]
	var pc := Combatant.from_character(cd, "pc1")
	pc.grid_position = Vector2i(5, 5)
	pc.set_equipped_weapon({"name": "Sword", "weapon_damage": "1d8", "weapon_tags": ["melee"]})

	var enemy := _make_enemy("gob1", "Goblin")
	enemy.grid_position = Vector2i(6, 5)
	var map := _make_map_with_cells([Vector2i(5, 5), Vector2i(6, 5)])
	map.set_entity_pos("pc1", Vector2i(5, 5))
	map.set_entity_pos("gob1", Vector2i(6, 5))
	var ctrl := _make_controller([pc, enemy], map)
	var result := Builder.build_menu("pc1", Vector2i(6, 5), ctrl, null)
	var maneuver_opt := _find_option(result, "combat_maneuver")
	var sub: Array = maneuver_opt.get("submenu_options", [])
	# Find disarm — should show -2 penalty with Combat Trickery
	var disarm_opt := {}
	for opt in sub:
		if opt.get("id") == "maneuver_disarm":
			disarm_opt = opt
	check(not disarm_opt.is_empty(), "Disarm should be in submenu")
	check("-2" in disarm_opt.get("label", ""), "Disarm should show -2 penalty with Combat Trickery")
	print("  maneuver_combat_trickery_penalty: OK")


func test_ranged_attack_not_engaged() -> void:
	var pc := _make_pc("pc1", "Archer")
	pc.grid_position = Vector2i(2, 5)
	pc.set_equipped_weapon({
		"name": "Shortbow", "weapon_damage": "1d6",
		"weapon_tags": ["ranged"],
		"range_short": 50, "range_medium": 100, "range_long": 150,
	})
	pc.set_equipped_ammo({"item_id": "arrow1", "name": "Arrows", "quantity": 20})
	var enemy := _make_enemy("gob1", "Goblin")
	enemy.grid_position = Vector2i(5, 5)
	var cells: Array[Vector2i] = []
	for x in range(0, 10):
		cells.append(Vector2i(x, 5))
	var map := _make_map_with_cells(cells)
	map.set_entity_pos("pc1", Vector2i(2, 5))
	map.set_entity_pos("gob1", Vector2i(5, 5))
	var ctrl := _make_controller([pc, enemy], map)
	var result := Builder.build_menu("pc1", Vector2i(5, 5), ctrl, null)
	check(_has_option(result, "attack_ranged"), "Ranged Attack should be present for ranged weapon")
	print("  ranged_attack_not_engaged: OK")


func test_prone_stand_up_option() -> void:
	var pc := _make_pc("pc1", "Bran")
	pc.grid_position = Vector2i(5, 5)
	pc.add_condition("prone")
	var map := _make_map_with_cells([Vector2i(5, 5)])
	map.set_entity_pos("pc1", Vector2i(5, 5))
	var ctrl := _make_controller([pc], map)
	# Self-click while prone
	var result := Builder.build_menu("pc1", Vector2i(5, 5), ctrl, null)
	check(_has_option(result, "stand_up"), "Stand Up should be present when prone")
	print("  prone_stand_up_option: OK")
