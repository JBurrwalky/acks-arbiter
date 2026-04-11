extends "res://tests/test_suite_base.gd"

## Unit tests for CreatureEquipmentService.


var _catalog: EquipmentCatalog


func run_all_tests() -> void:
	_catalog = EquipmentCatalog.new()

	test_barding_on_large_creature()
	test_barding_rejected_on_small_creature()
	test_barding_conflict()
	test_saddle_on_mount()
	test_saddle_rejected_on_guard()
	test_saddle_conflict()
	test_saddlebags_require_saddle()
	test_saddlebags_with_saddle()
	test_caparison_requires_saddle()
	test_cargo_requires_rigging()
	test_cargo_with_draft_saddle()
	test_cargo_exceeds_max()
	test_saddlebag_capacity()
	test_determine_creature_slot()
	test_saddlebag_contents_excluded_from_load()

	_catalog = null
	if not has_failures():
		print("CreatureEquipmentService: all tests passed.")


# --- Helpers ---

func _make_creature(role_code: String = "WM", size: String = "large") -> TrainedCreatureData:
	var c := TrainedCreatureData.new()
	c.id = "test_creature"
	c.species_id = "horse_medium_war"
	c.role = role_code
	c.monster_data = {
		"armor_class": 2,
		"size_category": size,
		"movement": {"land": {"exploration": 180, "combat": 60}},
		"special_abilities": [
			{"ability_id": "carrying_capacity", "effect": {"load_stone_normal": 30, "load_stone_max": 60}}
		],
	}
	c.inventory = []
	return c


func _barding_item() -> Dictionary:
	return {"item_key": "barding_chain", "item_category": "barding", "armor_ac_bonus": 3, "encumbrance_units": 3000}


func _saddle_item(key: String = "saddle_draft") -> Dictionary:
	return {"item_key": key, "item_category": "tack", "encumbrance_units": 1000}


func _saddlebags_item() -> Dictionary:
	return {"item_key": "saddlebags", "item_category": "tack", "encumbrance_units": 167}


func _caparison_item() -> Dictionary:
	return {"item_key": "caparison", "item_category": "tack", "encumbrance_units": 1000}


func _cargo_item(enc: int = 1000, qty: int = 1) -> Dictionary:
	return {"item_key": "generic_cargo", "item_category": "gear", "encumbrance_units": enc, "quantity": qty}


func _equipped(item: Dictionary, slot: String = "pack") -> Dictionary:
	var e := item.duplicate()
	e["is_equipped"] = 1
	e["slot"] = slot
	e["id"] = "inv_%d" % randi()
	return e


# --- Barding ---

func test_barding_on_large_creature() -> void:
	var c := _make_creature("WM", "large")
	var result := CreatureEquipmentService.validate_equip_on_creature(c, _barding_item(), _catalog)
	check(result == "", "barding on large creature should succeed, got: %s" % result)
	print("  barding_on_large: OK")


func test_barding_rejected_on_small_creature() -> void:
	var c := _make_creature("G", "man_sized")
	var result := CreatureEquipmentService.validate_equip_on_creature(c, _barding_item(), _catalog)
	check(result != "", "barding on man_sized creature should fail")
	print("  barding_rejected_small: OK")


func test_barding_conflict() -> void:
	var c := _make_creature()
	c.inventory = [_equipped(_barding_item(), "body")]
	var result := CreatureEquipmentService.validate_equip_on_creature(c, _barding_item(), _catalog)
	check(result != "", "second barding should fail")
	print("  barding_conflict: OK")


# --- Saddle ---

func test_saddle_on_mount() -> void:
	var c := _make_creature("M")
	var result := CreatureEquipmentService.validate_equip_on_creature(c, _saddle_item(), _catalog)
	check(result == "", "saddle on mount should succeed, got: %s" % result)
	print("  saddle_on_mount: OK")


func test_saddle_rejected_on_guard() -> void:
	var c := _make_creature("G")
	var result := CreatureEquipmentService.validate_equip_on_creature(c, _saddle_item(), _catalog)
	check(result != "", "saddle on guard should fail")
	print("  saddle_rejected_guard: OK")


func test_saddle_conflict() -> void:
	var c := _make_creature("M")
	c.inventory = [_equipped(_saddle_item(), "mount")]
	var result := CreatureEquipmentService.validate_equip_on_creature(c, _saddle_item("saddle_riding"), _catalog)
	check(result != "", "second saddle should fail")
	print("  saddle_conflict: OK")


# --- Saddlebags ---

func test_saddlebags_require_saddle() -> void:
	var c := _make_creature("M")
	var result := CreatureEquipmentService.validate_equip_on_creature(c, _saddlebags_item(), _catalog)
	check(result != "", "saddlebags without saddle should fail")
	print("  saddlebags_require_saddle: OK")


func test_saddlebags_with_saddle() -> void:
	var c := _make_creature("M")
	c.inventory = [_equipped(_saddle_item("saddle_riding"), "mount")]
	var result := CreatureEquipmentService.validate_equip_on_creature(c, _saddlebags_item(), _catalog)
	check(result == "", "saddlebags with saddle should succeed, got: %s" % result)
	print("  saddlebags_with_saddle: OK")


# --- Caparison ---

func test_caparison_requires_saddle() -> void:
	var c := _make_creature("WM")
	var result := CreatureEquipmentService.validate_equip_on_creature(c, _caparison_item(), _catalog)
	check(result != "", "caparison without saddle should fail")
	c.inventory = [_equipped(_saddle_item("saddle_war"), "mount")]
	result = CreatureEquipmentService.validate_equip_on_creature(c, _caparison_item(), _catalog)
	check(result == "", "caparison with saddle should succeed, got: %s" % result)
	print("  caparison_requires_saddle: OK")


# --- Cargo ---

func test_cargo_requires_rigging() -> void:
	var c := _make_creature("WB")
	var result := CreatureEquipmentService.validate_cargo_on_creature(c, _cargo_item())
	check(result != "", "cargo without rigging should fail")
	print("  cargo_requires_rigging: OK")


func test_cargo_with_draft_saddle() -> void:
	var c := _make_creature("WB")
	c.inventory = [_equipped(_saddle_item("saddle_draft"), "mount")]
	var result := CreatureEquipmentService.validate_cargo_on_creature(c, _cargo_item())
	check(result == "", "cargo with draft saddle should succeed, got: %s" % result)
	print("  cargo_with_draft_saddle: OK")


func test_cargo_exceeds_max() -> void:
	var c := _make_creature("WB")
	c.inventory = [_equipped(_saddle_item("saddle_draft"), "mount")]
	# Max capacity = 60 stone = 60000 units. Try adding 61 stone.
	var result := CreatureEquipmentService.validate_cargo_on_creature(c, _cargo_item(1000, 61))
	check(result != "", "cargo exceeding max should fail")
	print("  cargo_exceeds_max: OK")


# --- Saddlebag container ---

func test_saddlebag_capacity() -> void:
	var c := _make_creature("M")
	var sb := _equipped(_saddlebags_item(), "pack")
	sb["id"] = "saddlebag_1"
	c.inventory = [
		_equipped(_saddle_item("saddle_riding"), "mount"),
		sb,
	]
	# Empty saddlebags — should accept a 2-stone item (2000 units < 3000 capacity).
	var small_item := _cargo_item(2000)
	var result := CreatureEquipmentService.validate_into_saddlebags(c, small_item, "saddlebag_1", _catalog)
	check(result == "", "2-stone item should fit in empty saddlebags, got: %s" % result)

	# Add item that fills saddlebags.
	var filler := _cargo_item(2500)
	filler["container_id"] = "saddlebag_1"
	c.inventory.append(filler)
	result = CreatureEquipmentService.validate_into_saddlebags(c, _cargo_item(600), "saddlebag_1", _catalog)
	check(result != "", "item should not fit in nearly-full saddlebags")
	print("  saddlebag_capacity: OK")


# --- Slot determination ---

func test_determine_creature_slot() -> void:
	check(CreatureEquipmentService.determine_creature_slot(_barding_item()) == "body", "barding -> body")
	check(CreatureEquipmentService.determine_creature_slot(_saddle_item()) == "mount", "saddle -> mount")
	check(CreatureEquipmentService.determine_creature_slot(_saddlebags_item()) == "pack", "saddlebags -> pack")
	check(CreatureEquipmentService.determine_creature_slot(_caparison_item()) == "pack", "caparison -> pack")
	check(CreatureEquipmentService.determine_creature_slot(_cargo_item()) == "", "cargo -> empty")
	print("  determine_creature_slot: OK")


# --- Load calculation with saddlebag exclusion ---

func test_saddlebag_contents_excluded_from_load() -> void:
	var c := _make_creature("M")
	var sb := _equipped(_saddlebags_item(), "pack")
	sb["id"] = "saddlebag_1"
	var in_bag := _cargo_item(1000)
	in_bag["container_id"] = "saddlebag_1"
	var loose := _cargo_item(2000)
	c.inventory = [
		_equipped(_saddle_item("saddle_riding"), "mount"),  # 1000 units
		sb,                                                  # 167 units
		in_bag,                                              # 1000 units (INSIDE saddlebag)
		loose,                                               # 2000 units (loose)
	]
	# Load should be: saddle(1000) + saddlebags(167) + loose(2000) = 3167 units
	# The in_bag item should be excluded.
	var load_units := c.get_current_load_units()
	check(load_units == 3167,
		"load should be 3167 units (excluding saddlebag contents), got %d" % load_units)
	print("  saddlebag_contents_excluded: OK")
