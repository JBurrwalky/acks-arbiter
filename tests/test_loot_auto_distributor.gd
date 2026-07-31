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
	test_band_crossing_placed_via_capacity_fallback()
	test_over_hard_cap_unassigned()
	test_coin_unassigned_reason()
	test_describe_unassigned_reason()
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
	# Both carriers are already in band 3 (severe, >10000) with capacity to spare,
	# so the plate does NOT worsen either band. Among band-free candidates a heavy
	# item routes to the highest-STR carrier (pc2). (When a heavy item WOULD worsen
	# every carrier's band it is NOT dropped: the capacity fallback places it on
	# the strongest carrier that still fits it under raw hard-cap — see
	# test_band_crossing_placed_via_capacity_fallback. It only stays unassigned
	# when it exceeds every carrier's hard cap — see test_over_hard_cap_unassigned.)
	var carriers := [
		_make_carrier("pc1", "pc", 12000, 20000, [], [], 10),
		_make_carrier("pc2", "pc", 12000, 20000, [], [], 16),
	]
	var items := [_make_item("plate_armor", 1)]
	var result := dist.distribute(items, carriers)
	check(result.moves.size() == 1, "plate armor should be assigned (fits both in-band)")
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
	# One stack of 2 torches = one item entry (200 enc total). distribute emits
	# ONE move per item entry, so the whole stack is a single move.
	var items := [_make_item("torch", 2)]
	var result := dist.distribute(items, carriers)
	check(result.moves.size() == 1, "the torch stack should be assigned")
	# pc1 at 4900 + 200 = 5100 crosses band 0→1 (worsened), so the round-robin
	# skips pc1 and assigns the stack to pc2 (which stays in band 0).
	check(result.moves[0].to_carrier == "pc2",
		"stack should skip pc1 (band worsening) and go to pc2, got %s" %
		str(result.moves[0].to_carrier))


func test_band_crossing_placed_via_capacity_fallback() -> void:
	var dist := LootAutoDistributor.new(_mock_catalog)
	# Both carriers nearly full — heavy_chest (2000 enc) would worsen both bands
	# (4500 → 6500 crosses band 0→1). Per the loot policy, crossing a band is a
	# soft-cap penalty, NOT a reason to drop loot: the capacity fallback places
	# it on the strongest carrier that still fits it under raw hard-cap (20000).
	var carriers := [
		_make_carrier("pc1", "pc", 4500, 20000, [], [], 10),
		_make_carrier("pc2", "pc", 4500, 20000, [], [], 16),
	]
	var items := [_make_item("heavy_chest", 1)]
	var result := dist.distribute(items, carriers)
	check(result.unassigned.is_empty(),
		"heavy chest fits under hard cap — should NOT be unassigned")
	check(result.moves.size() == 1, "heavy chest should be placed via fallback")
	check(result.moves[0].reason == "capacity_fallback",
		"placement reason should be capacity_fallback, got %s" % str(result.moves[0].reason))
	check(result.moves[0].to_carrier == "pc2",
		"heavy item fallback should prefer strongest carrier (pc2=16), got %s" %
		str(result.moves[0].to_carrier))


func test_over_hard_cap_unassigned() -> void:
	var dist := LootAutoDistributor.new(_mock_catalog)
	# Both carriers have a tiny hard cap (1000) — heavy_chest (2000 enc) exceeds
	# every carrier's RAW capacity, so it TRULY does not fit anyone. Only now does
	# it stay unassigned, tagged over_capacity for the loot modal to surface.
	var carriers := [
		_make_carrier("pc1", "pc", 0, 1000),
		_make_carrier("pc2", "pc", 500, 1000),
	]
	var items := [_make_item("heavy_chest", 1)]
	var result := dist.distribute(items, carriers)
	check(result.moves.is_empty(), "over-capacity chest should not be placed")
	check(result.unassigned.size() == 1,
		"heavy chest should be unassigned when it exceeds every hard cap")
	check(result.unassigned[0].get("unassigned_reason", "") == "over_capacity",
		"unassigned reason should be over_capacity, got %s" %
		str(result.unassigned[0].get("unassigned_reason", "")))


func test_coin_unassigned_reason() -> void:
	var dist := LootAutoDistributor.new(_mock_catalog)
	var items := [_make_item("coins_gp", 100)]
	var result := dist.distribute(items, [_make_carrier("pc1")])
	check(result.unassigned.size() == 1, "coins should go to unassigned")
	check(result.unassigned[0].get("unassigned_reason", "") == "coin_excluded",
		"coin unassigned reason should be coin_excluded, got %s" %
		str(result.unassigned[0].get("unassigned_reason", "")))


func test_describe_unassigned_reason() -> void:
	# Pure/static helper the loot modal uses to build its alert text.
	check(LootAutoDistributor.describe_unassigned_reason("over_capacity")
		== "no one has enough carrying capacity", "over_capacity phrase")
	check(LootAutoDistributor.describe_unassigned_reason("coin_excluded")
		== "coins are shared separately", "coin_excluded phrase")
	check(not LootAutoDistributor.describe_unassigned_reason("mystery").is_empty(),
		"unknown reason should still produce a non-empty phrase")


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
