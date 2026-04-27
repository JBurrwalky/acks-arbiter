extends "res://tests/test_suite_base.gd"

## Unit tests for TrainedCreatureData.
##
## Tests serialization, AC calculation, load capacity, barding/saddle
## validation, combat role detection, and movement.


func run_all_tests() -> void:
	test_from_db_round_trip()
	test_combat_role_detection()
	test_can_enter_dungeon()
	test_base_armor_class()
	test_barding_ac_bonus()
	test_barding_size_validation()
	test_saddle_role_validation()
	test_load_multiplier_with_draft_saddle()
	test_load_multiplier_with_pack_saddle()
	test_load_multiplier_with_rope()
	test_load_multiplier_without_rigging()
	test_overload_detection()
	test_movement_halved_when_overloaded()
	test_bankers_rounding()

	if not has_failures():
		print("TrainedCreatureData: all tests passed.")


# --- Helpers ---

func _make_creature(species: String = "horse_medium_war", role_code: String = "WM") -> TrainedCreatureData:
	var c := TrainedCreatureData.new()
	c.id = "test_creature_1"
	c.campaign_id = "test_campaign"
	c.party_id = "test_party"
	c.species_id = species
	c.name = "Thunder"
	c.role = role_code
	c.tricks_known = ["attack", "come", "defend", "heel", "stay"]
	c.trick_limit = 6
	c.morale = 1
	c.handler_id = "test_char_1"
	c.introduced_handlers = ["test_char_2"]
	c.hp_current = 12
	c.hp_max = 14
	c.training_complete = true
	c.is_alive = true
	c.monster_data = {
		"armor_class": 2,
		"size_category": "large",
		"movement": {"land": {"exploration": 180, "combat": 60}},
		"special_abilities": [
			{
				"ability_id": "carrying_capacity",
				"effect": {"load_stone_normal": 30, "load_stone_max": 60}
			}
		],
	}
	return c


func _make_barding_item(ac_bonus: int, equipped: bool = true) -> Dictionary:
	return {
		"item_key": "barding_chain",
		"item_category": "barding",
		"is_equipped": 1 if equipped else 0,
		"armor_ac_bonus": ac_bonus,
		"encumbrance_units": 3000,
		"quantity": 1,
	}


func _make_saddle_item(key: String, equipped: bool = true) -> Dictionary:
	return {
		"item_key": key,
		"item_category": "tack",
		"is_equipped": 1 if equipped else 0,
		"armor_ac_bonus": 0,
		"encumbrance_units": 1000,
		"quantity": 1,
	}


func _make_cargo_item(enc_units: int, qty: int = 1) -> Dictionary:
	return {
		"item_key": "generic_cargo",
		"item_category": "gear",
		"is_equipped": 0,
		"armor_ac_bonus": 0,
		"encumbrance_units": enc_units,
		"quantity": qty,
	}


# --- Serialization ---

func test_from_db_round_trip() -> void:
	var c := _make_creature()
	var d := c.to_dict()
	var c2 := TrainedCreatureData.from_db(d)
	check(c2.id == c.id, "id should survive round-trip")
	check(c2.species_id == c.species_id, "species_id should survive round-trip")
	check(c2.role == c.role, "role should survive round-trip")
	check(c2.hp_current == c.hp_current, "hp_current should survive round-trip")
	check(c2.training_complete == c.training_complete, "training_complete should survive round-trip")
	check(c2.tricks_known.size() == 5, "tricks_known should have 5 items after round-trip, got %d" % c2.tricks_known.size())
	check(c2.introduced_handlers.size() == 1, "introduced_handlers should have 1 item, got %d" % c2.introduced_handlers.size())
	print("  from_db_round_trip: OK")


# --- Combat role ---

func test_combat_role_detection() -> void:
	var wm := _make_creature("horse_medium_war", "WM")
	check(wm.has_combat_role(), "WM should have combat role")
	var guard := _make_creature("dog_war", "G")
	check(guard.has_combat_role(), "G should have combat role")
	var hunter := _make_creature("dog_hunting", "H")
	check(hunter.has_combat_role(), "H should have combat role")
	var mount := _make_creature("horse_light", "M")
	check(not mount.has_combat_role(), "M should NOT have combat role")
	var livestock := _make_creature("cow", "L")
	check(not livestock.has_combat_role(), "L should NOT have combat role")
	print("  combat_role_detection: OK")


# --- Dungeon eligibility ---

func test_can_enter_dungeon() -> void:
	# Allowed species: dogs, hawks, donkeys, mules.
	check(_make_creature("dog_war", "G").can_enter_dungeon(), "war dog should enter dungeon")
	check(_make_creature("dog_hunting", "H").can_enter_dungeon(), "hunting dog should enter dungeon")
	check(_make_creature("hawk_ordinary", "H").can_enter_dungeon(), "hawk should enter dungeon")
	check(_make_creature("donkey", "WB").can_enter_dungeon(), "donkey should enter dungeon")
	check(_make_creature("mule", "WB").can_enter_dungeon(), "mule should enter dungeon")
	# Excluded species: horses (any kind), oxen, cows, pigs, goats.
	check(not _make_creature("horse_medium", "M").can_enter_dungeon(), "medium horse should NOT enter dungeon")
	check(not _make_creature("horse_heavy_war", "WM").can_enter_dungeon(), "heavy warhorse should NOT enter dungeon")
	check(not _make_creature("horse_light", "M").can_enter_dungeon(), "light horse should NOT enter dungeon")
	check(not _make_creature("ox", "WB").can_enter_dungeon(), "ox should NOT enter dungeon")
	check(not _make_creature("cow", "L").can_enter_dungeon(), "cow should NOT enter dungeon")
	check(not _make_creature("pig", "L").can_enter_dungeon(), "pig should NOT enter dungeon")
	check(not _make_creature("goat", "L").can_enter_dungeon(), "goat should NOT enter dungeon")
	check(not _make_creature("sheep", "L").can_enter_dungeon(), "sheep should NOT enter dungeon")
	print("  can_enter_dungeon: OK")


# --- Armor class ---

func test_base_armor_class() -> void:
	var c := _make_creature()
	check(c.get_base_armor_class() == 2, "base AC should be 2, got %d" % c.get_base_armor_class())
	check(c.get_armor_class() == 2, "total AC without barding should be 2")
	print("  base_armor_class: OK")


func test_barding_ac_bonus() -> void:
	var c := _make_creature()
	c.inventory = [_make_barding_item(3)]
	check(c.get_equipped_barding_ac() == 3, "equipped barding AC should be 3")
	check(c.get_armor_class() == 5, "total AC with chain barding should be 5, got %d" % c.get_armor_class())
	print("  barding_ac_bonus: OK")


# --- Equipment validation ---

func test_barding_size_validation() -> void:
	var large := _make_creature()
	large.monster_data["size_category"] = "large"
	check(large.can_equip_barding(), "large creature should accept barding")
	var man_sized := _make_creature()
	man_sized.monster_data["size_category"] = "man_sized"
	check(not man_sized.can_equip_barding(), "man_sized creature should reject barding")
	var small := _make_creature()
	small.monster_data["size_category"] = "small"
	check(not small.can_equip_barding(), "small creature should reject barding")
	print("  barding_size_validation: OK")


func test_saddle_role_validation() -> void:
	var mount := _make_creature("horse_light", "M")
	check(mount.can_equip_saddle(), "mount (M) should accept saddle")
	var war_mount := _make_creature("horse_medium_war", "WM")
	check(war_mount.can_equip_saddle(), "war mount (WM) should accept saddle")
	var workbeast := _make_creature("ox", "WB")
	check(workbeast.can_equip_saddle(), "workbeast (WB) should accept saddle")
	var guard := _make_creature("dog_war", "G")
	check(not guard.can_equip_saddle(), "guard (G) should reject saddle")
	print("  saddle_role_validation: OK")


# --- Load capacity ---

func test_load_multiplier_with_draft_saddle() -> void:
	var c := _make_creature()
	c.inventory = [_make_saddle_item("saddle_draft")]
	check(is_equal_approx(c.get_load_multiplier(), 1.0), "draft saddle should give 1.0 multiplier")
	check(c.get_effective_capacity_normal() == 30, "capacity should be full 30 stone")
	print("  load_multiplier_draft: OK")


func test_load_multiplier_with_pack_saddle() -> void:
	var c := _make_creature()
	c.inventory = [_make_saddle_item("saddle_pack")]
	check(is_equal_approx(c.get_load_multiplier(), 1.0), "pack saddle should give 1.0 multiplier")
	check(c.get_effective_capacity_normal() == 30, "capacity with pack saddle should be full 30 stone")
	print("  load_multiplier_pack: OK")


func test_load_multiplier_with_rope() -> void:
	var c := _make_creature()
	c.inventory = [{"item_key": "rope_50ft", "encumbrance_units": 1000, "quantity": 1}]
	check(is_equal_approx(c.get_load_multiplier(), 0.5), "rope should give 0.5 multiplier")
	check(c.get_effective_capacity_normal() == 15, "capacity with rope should be 15 stone, got %d" % c.get_effective_capacity_normal())
	print("  load_multiplier_rope: OK")


func test_load_multiplier_without_rigging() -> void:
	var c := _make_creature()
	c.inventory = []
	check(is_equal_approx(c.get_load_multiplier(), 0.0), "no rigging should give 0.0 multiplier")
	check(c.get_effective_capacity_normal() == 0, "capacity without rigging should be 0")
	print("  load_multiplier_none: OK")


# --- Overload ---

func test_overload_detection() -> void:
	var c := _make_creature()
	c.inventory = [
		_make_saddle_item("saddle_draft"),
		_make_cargo_item(1000, 20),  # 20 stone of cargo
	]
	check(not c.is_overloaded(), "20 stone on 30-capacity creature should not be overloaded")
	c.inventory.append(_make_cargo_item(1000, 15))  # +15 = 35 total
	check(c.is_overloaded(), "35 stone on 30-capacity creature should be overloaded")
	print("  overload_detection: OK")


# --- Movement ---

func test_movement_halved_when_overloaded() -> void:
	var c := _make_creature()
	check(c.get_effective_movement() == 180, "normal movement should be 180")
	c.inventory = [
		_make_saddle_item("saddle_draft"),
		_make_cargo_item(1000, 35),  # 35 stone > 30 capacity
	]
	check(c.get_effective_movement() == 90, "overloaded movement should be 90, got %d" % c.get_effective_movement())
	print("  movement_overloaded: OK")


# --- Banker's rounding ---

func test_bankers_rounding() -> void:
	check(TrainedCreatureData._bankers_round(2.5) == 2, "2.5 rounds to 2 (even)")
	check(TrainedCreatureData._bankers_round(3.5) == 4, "3.5 rounds to 4 (even)")
	check(TrainedCreatureData._bankers_round(4.5) == 4, "4.5 rounds to 4 (even)")
	check(TrainedCreatureData._bankers_round(5.5) == 6, "5.5 rounds to 6 (even)")
	check(TrainedCreatureData._bankers_round(2.3) == 2, "2.3 rounds to 2")
	check(TrainedCreatureData._bankers_round(2.7) == 3, "2.7 rounds to 3")
	print("  bankers_rounding: OK")
