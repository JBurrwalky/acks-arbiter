extends "res://tests/test_suite_base.gd"

## Unit tests for the slim SettlementMapController (V2 — settlement context;
## tracks current_poi_id / current_district_id without spatial state).
## See gdd-settlement-exploration-ui.md v2 §2-3.


var _controller: SettlementMapController = null


func _make_settlement_dict() -> Dictionary:
	return {
		"id": "ctx_test",
		"name": "Context Test",
		"market_class": 5,
		"districts": [
			{
				"id": "d1",
				"name": "District One",
				"type": "village_center",
				"encounter_modifier": "default",
				"pois": [
					{"id": "p1", "name": "First PoI", "type": "tavern",
						"is_entry_exit": false, "importance": "major"},
					{"id": "gate1", "name": "First Gate", "type": "gate",
						"is_entry_exit": true, "importance": "major"},
				],
			},
			{
				"id": "d2",
				"name": "District Two",
				"type": "market",
				"encounter_modifier": "default",
				"pois": [
					{"id": "p2", "name": "Second PoI", "type": "shop",
						"is_entry_exit": false, "importance": "minor"},
				],
			},
		],
	}


func run_all_tests() -> void:
	test_load_with_explicit_entry_poi()
	test_load_falls_back_to_first_entry_exit()
	test_load_falls_back_to_first_poi_when_no_entry_exit()
	test_set_current_poi_changes_state_and_emits_signal()
	test_set_current_poi_rejects_unknown_id()
	test_is_at_entry_exit()
	test_same_district_as_current()
	if not has_failures():
		print("SettlementContext: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_controller() -> SettlementMapController:
	return SettlementMapController.new()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_load_with_explicit_entry_poi() -> void:
	var c := _make_controller()
	c.load_settlement(_make_settlement_dict(), "p1")
	check(c.get_current_poi_id() == "p1",
		"explicit entry PoI honored, got %s" % c.get_current_poi_id())
	check(c.get_current_district_id() == "d1",
		"district resolved from PoI, got %s" % c.get_current_district_id())
	check(c.get_settlement_id() == "ctx_test", "settlement_id roundtrip")
	print("  load_with_explicit_entry_poi: OK")


func test_load_falls_back_to_first_entry_exit() -> void:
	var c := _make_controller()
	c.load_settlement(_make_settlement_dict(), "")
	check(c.get_current_poi_id() == "gate1",
		"empty entry id falls back to first entry/exit PoI, got %s" % c.get_current_poi_id())
	print("  load_falls_back_to_first_entry_exit: OK")


func test_load_falls_back_to_first_poi_when_no_entry_exit() -> void:
	var dict := _make_settlement_dict()
	# Strip is_entry_exit flags
	for d in dict.get("districts", []):
		for p in d.get("pois", []):
			p["is_entry_exit"] = false

	var c := _make_controller()
	c.load_settlement(dict, "")
	check(c.get_current_poi_id() == "p1",
		"no entry/exit PoIs falls back to first PoI overall, got %s" % c.get_current_poi_id())
	print("  load_falls_back_to_first_poi_when_no_entry_exit: OK")


func test_set_current_poi_changes_state_and_emits_signal() -> void:
	var c := _make_controller()
	c.load_settlement(_make_settlement_dict(), "p1")
	# Box the captured value in an Array so the lambda assignment propagates
	# (GDScript lambdas don't write through to plain local vars).
	var emitted: Array = [""]
	c.current_poi_changed.connect(func(poi_id: String): emitted[0] = poi_id)
	c.set_current_poi("p2")
	check(c.get_current_poi_id() == "p2", "current PoI updated")
	check(c.get_current_district_id() == "d2", "district updates with PoI")
	check(emitted[0] == "p2", "current_poi_changed emitted with new id, got '%s'" % emitted[0])

	# Setting same PoI again is a no-op (no signal re-emit).
	emitted[0] = ""
	c.set_current_poi("p2")
	check(emitted[0] == "", "no signal emitted when PoI doesn't change")
	print("  set_current_poi_changes_state_and_emits_signal: OK")


func test_set_current_poi_rejects_unknown_id() -> void:
	var c := _make_controller()
	c.load_settlement(_make_settlement_dict(), "p1")
	var emitted: Array = [false]
	c.current_poi_changed.connect(func(_id: String): emitted[0] = true)
	c.set_current_poi("does_not_exist")
	check(c.get_current_poi_id() == "p1", "unknown PoI id leaves state unchanged")
	check(not emitted[0], "no signal emitted on rejection")
	print("  set_current_poi_rejects_unknown_id: OK")


func test_is_at_entry_exit() -> void:
	var c := _make_controller()
	c.load_settlement(_make_settlement_dict(), "p1")
	check(not c.is_at_entry_exit(), "p1 is not entry/exit")
	c.set_current_poi("gate1")
	check(c.is_at_entry_exit(), "gate1 is entry/exit")
	print("  is_at_entry_exit: OK")


func test_same_district_as_current() -> void:
	var c := _make_controller()
	c.load_settlement(_make_settlement_dict(), "p1")
	check(c.same_district_as_current("gate1"), "p1 and gate1 are both in d1")
	check(not c.same_district_as_current("p2"), "p1 (d1) and p2 (d2) differ")
	check(not c.same_district_as_current("nonexistent"), "unknown id returns false")
	print("  same_district_as_current: OK")
