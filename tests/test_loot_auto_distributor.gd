extends "res://tests/test_suite_base.gd"

## Unit tests for LootAutoDistributor — item distribution algorithm.
## Uses a mock EquipmentCatalog to avoid real catalog dependency.

var _mock_catalog: MockCatalog


func run_all_tests() -> void:
	_mock_catalog = MockCatalog.new()

	test_empty_items_empty_moves()
	test_coin_items_excluded()
	test_preference_tag_match()
	test_multiple_taggers_round_robin()
	test_heavy_item_highest_str()
	test_ammunition_weapon_match()
	test_band_worsening_skipped()
	test_no_valid_target_unassigned()
	test_rations_creatures_first()
	test_magic_items_pcs_round_robin()

	if not has_failures():
		print("LootAutoDistributor: all tests passed.")


# ---------------------------------------------------------------------------
# Mock catalog
# ---------------------------------------------------------------------------

class MockCatalog extends RefCounted:
	var _items: Dictionary = {
		"torch": {"item_category": "gear", "encumbrance_units": 100, "is_heavy": false, "is_magical": false},
		"rations_standard": {"item_category": "foodstuff", "encumbrance_units": 100, "is_heavy": false, "is_magical": false},
		"arrow_quiver": {"item_category": "ammunition", "encumbrance_units": 100, "is_heavy": false, "is_magical": false},
		"longsword": {"item_category": "weapon", "encumbrance_units": 100, "is_heavy": false, "is_magical": false},
		"plate_armor": {"item_category": "armor", "encumbrance_units": 6000, "is_heavy": true, "is_magical": false},
		"scroll_fireball": {"item_category": "gear", "encumbrance_units": 10, "is_heavy": false, "is_magical": true},
		"potion_healing": {"item_category": "gear", "encumbrance_units": 50, "is_heavy": false, "is_magical": true},
		"coins_gp": {"item_category": "treasure", "encumbrance_units": 1, "is_heavy": false, "is_magical": false},
		"rope_50ft": {"item_category": "gear", "encumbrance_units": 500, "is_heavy": false, "is_magical": false},
		"heavy_chest": {"item_category": "gear", "encumbrance_units": 2000, "is_heavy": true, "is_magical": false},
	}

	func get_item(item_key: String) -> Dictionary:
		return _items.get(item_key, {})


# ---------------------------------------------------------------------------
# Helper to build test carriers
# ---------------------------------------------------------------------------

func _make_carrier(id: String, type: String = "pc", enc: int = 0,
		max_enc: int = 20000, prefs: Array = [], weapons: Array = [],
		strength: int = 10) -> Dictionary:
	return {
		"carrier_id": id,
		"carrier_type": type,
		"current_enc_units": enc,
		"max_enc_units": max_enc,
		"preferences": prefs,
		"equipped_weapons": weapons,
		"strength": strength,
	}


func _make_item(key: String, qty: int = 1) -> Dictionary:
	return {"item_key": key, "quantity": qty}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_empty_items_empty_moves() -> void:
	var dist := LootAutoDistributor.new(_mock_catalog)
	var result := dist.distribute([], [_make_carrier("pc1")])
	check(result.moves.is_empty(), "empty items should have no moves")
	check(result.unassigned.is_empty(), "empty items should have no unassigned")
	check(result.summary.total_items == 0, "summary total should be 0")


func test_coin_items_excluded() -> void:
	var dist := LootAutoDistributor.new(_mock_catalog)
	var items := [_make_item("coins_gp", 100)]
	var result := dist.distribute(items, [_make_carrier("pc1")])
	check(result.moves.is_empty(), "coins should not be moved")
	check(result.unassigned.size() == 1, "coins should go to unassigned")


func test_preference_tag_match() -> void:
	var dist := LootAutoDistributor.new(_mock_catalog)
	var carriers := [
		_make_carrier("pc1", "pc", 0, 20000, ["torch_bearer"]),
		_make_carrier("pc2"),
	]
	var items := [_make_item("torch", 1)]
	var result := dist.distribute(items, carriers)
	check(result.moves.size() == 1, "torch should be assigned to torch_bearer")
	check(result.moves[0].to_carrier == "pc1",
		"torch should go to pc1 (torch_bearer), got %s" % str(result.moves[0].to_carrier))
	check(result.moves[0].reason == "preference_tag",
		"reason should be preference_tag")


func test_multiple_taggers_round_robin() -> void:
	var dist := LootAutoDistributor.new(_mock_catalog)
	var carriers := [
		_make_carrier("pc1", "pc", 0, 20000, ["torch_bearer"]),
		_make_carrier("pc2", "pc", 0, 20000, ["torch_bearer"]),
	]
	var items := [
		_make_item("torch", 1),
		_make_item("torch", 1),
		_make_item("torch", 1),
	]
	var result := dist.distribute(items, carriers)
	check(result.moves.size() == 3, "all 3 torches should be assigned")
	# Round-robin: pc1, pc2, pc1
	check(result.moves[0].to_carrier == "pc1", "first torch to pc1")
	check(result.moves[1].to_carrier == "pc2", "second torch to pc2")
	check(result.moves[2].to_carrier == "pc1", "third torch to pc1")


func test_heavy_item_highest_str() -> void:
	var dist := LootAutoDistributor.new(_mock_catalog)
	var carriers := [
		_make_carrier("pc1", "pc", 0, 20000, [], [], 10),
		_make_carrier("pc2", "pc", 0, 20000, [], [], 16),
	]
	var items := [_make_item("plate_armor", 1)]
	var result := dist.distribute(items, carriers)
	check(result.moves.size() == 1, "plate armor should be assigned")
	check(result.moves[0].to_carrier == "pc2",
		"heavy item should go to highest STR (pc2=16), got %s" % str(result.moves[0].to_carrier))


func test_ammunition_weapon_match() -> void:
	var dist := LootAutoDistributor.new(_mock_catalog)
	var carriers := [
		_make_carrier("pc1", "pc", 0, 20000, [], ["shortbow"]),
		_make_carrier("pc2", "pc", 0, 20000, [], ["longsword"]),
	]
	var items := [_make_item("arrow_quiver", 1)]
	var result := dist.distribute(items, carriers)
	check(result.moves.size() == 1, "arrows should be assigned")
	check(result.moves[0].to_carrier == "pc1",
		"arrows should go to bow user (pc1), got %s" % str(result.moves[0].to_carrier))


func test_band_worsening_skipped() -> void:
	var dist := LootAutoDistributor.new(_mock_catalog)
	# pc1 is at 4900 enc — adding 200 would push to 5100 (band 0→1, worsened).
	# pc2 is at 0 enc — plenty of room.
	var carriers := [
		_make_carrier("pc1", "pc", 4900, 20000, ["torch_bearer"]),
		_make_carrier("pc2", "pc", 0, 20000, ["torch_bearer"]),
	]
	var items := [_make_item("torch", 2)]  # 100 enc each, qty 2 = 200 total
	var result := dist.distribute(items, carriers)
	check(result.moves.size() == 2, "both torches should be assigned")
	# pc1 would go from 4900→5100 (band 0→1), so first torch skips to pc2.
	# Actually: item total enc = 100 * 2 = 200 per item entry. Wait, each item is qty=2?
	# No — each item in the array is a separate entry with qty=2. So one item = 200 enc.
	# pc1 at 4900 + 200 = 5100 → band 0 to 1 → worsened → skip.
	check(result.moves[0].to_carrier == "pc2",
		"first torch should skip pc1 (band worsening) and go to pc2, got %s" %
		str(result.moves[0].to_carrier))


func test_no_valid_target_unassigned() -> void:
	var dist := LootAutoDistributor.new(_mock_catalog)
	# Both carriers nearly full — heavy_chest (2000 enc) would worsen both.
	var carriers := [
		_make_carrier("pc1", "pc", 4500, 20000),
		_make_carrier("pc2", "pc", 4500, 20000),
	]
	var items := [_make_item("heavy_chest", 1)]
	var result := dist.distribute(items, carriers)
	check(result.unassigned.size() == 1,
		"heavy chest should be unassigned when all carriers would worsen band")


func test_rations_creatures_first() -> void:
	var dist := LootAutoDistributor.new(_mock_catalog)
	var carriers := [
		_make_carrier("pc1", "pc", 0, 20000),
		_make_carrier("mule1", "creature", 0, 30000),
	]
	var items := [_make_item("rations_standard", 1)]
	var result := dist.distribute(items, carriers)
	check(result.moves.size() == 1, "rations should be assigned")
	check(result.moves[0].to_carrier == "mule1",
		"rations should go to creature first, got %s" % str(result.moves[0].to_carrier))


func test_magic_items_pcs_round_robin() -> void:
	var dist := LootAutoDistributor.new(_mock_catalog)
	var carriers := [
		_make_carrier("pc1"),
		_make_carrier("pc2"),
		_make_carrier("mule1", "creature", 0, 30000),
	]
	var items := [
		_make_item("scroll_fireball", 1),
		_make_item("potion_healing", 1),
	]
	var result := dist.distribute(items, carriers)
	check(result.moves.size() == 2, "both magic items should be assigned")
	# Magic items → PCs round-robin, not creatures.
	check(result.moves[0].to_carrier == "pc1",
		"first magic item to pc1, got %s" % str(result.moves[0].to_carrier))
	check(result.moves[1].to_carrier == "pc2",
		"second magic item to pc2, got %s" % str(result.moves[1].to_carrier))
