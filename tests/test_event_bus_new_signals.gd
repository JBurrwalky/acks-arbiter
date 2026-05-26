extends "res://tests/test_suite_base.gd"

## Stage A signal-declaration sanity tests for the Urban Growth Stocking
## substrate per `generation/gdd-urban-growth-stocking.md` §13.1 + §11.5.
##
## Each test connects a local handler to the signal, emits the signal with
## representative argument values, and verifies the handler received the
## expected payload. Confirms (a) the signal exists, (b) the parameter
## arity matches, and (c) emit-and-receive plumbing works end-to-end.
##
## Per project convention, settlement / POI / character identifiers are
## String (matching existing settlement_market_class_changed,
## settlement_created, etc.); the GDD's `int` notation is design-doc
## shorthand, not the binding type.

var _captured: Dictionary = {}


func run_all_tests() -> void:
	test_market_class_advanced_signal()
	test_market_class_regressed_signal()
	test_settlement_dissolved_signal()
	test_poi_emerged_signal()
	test_poi_stocked_signal()
	test_poi_unstocked_signal()
	test_poi_status_changed_signal()
	test_spellcasting_service_purchased_signal()
	if not has_failures():
		print("EventBusNewSignals: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_market_class_advanced_signal() -> void:
	check(EventBus.has_signal("market_class_advanced"),
		"EventBus.market_class_advanced should exist")
	_captured.clear()
	var cb := func(sid: String, oc: int, nc: int) -> void:
		_captured["sid"] = sid; _captured["oc"] = oc; _captured["nc"] = nc
	EventBus.market_class_advanced.connect(cb)
	EventBus.market_class_advanced.emit("settle_1", 6, 5)
	EventBus.market_class_advanced.disconnect(cb)
	check(String(_captured.get("sid", "")) == "settle_1", "settlement_id captured")
	check(int(_captured.get("oc", -1)) == 6, "old_class captured")
	check(int(_captured.get("nc", -1)) == 5, "new_class captured")


func test_market_class_regressed_signal() -> void:
	check(EventBus.has_signal("market_class_regressed"),
		"EventBus.market_class_regressed should exist")
	_captured.clear()
	var cb := func(sid: String, oc: int, nc: int) -> void:
		_captured["sid"] = sid; _captured["oc"] = oc; _captured["nc"] = nc
	EventBus.market_class_regressed.connect(cb)
	EventBus.market_class_regressed.emit("settle_2", 4, 5)
	EventBus.market_class_regressed.disconnect(cb)
	check(String(_captured.get("sid", "")) == "settle_2",
		"market_class_regressed payload preserved")
	check(int(_captured.get("oc", -1)) == 4 and int(_captured.get("nc", -1)) == 5,
		"market_class_regressed class numbers preserved")


func test_settlement_dissolved_signal() -> void:
	check(EventBus.has_signal("settlement_dissolved"),
		"EventBus.settlement_dissolved should exist")
	_captured.clear()
	var cb := func(sid: String) -> void:
		_captured["sid"] = sid
	EventBus.settlement_dissolved.connect(cb)
	EventBus.settlement_dissolved.emit("settle_3")
	EventBus.settlement_dissolved.disconnect(cb)
	check(String(_captured.get("sid", "")) == "settle_3",
		"settlement_dissolved payload preserved")


func test_poi_emerged_signal() -> void:
	check(EventBus.has_signal("poi_emerged"),
		"EventBus.poi_emerged should exist")
	_captured.clear()
	var cb := func(poi_id: String, t: String, sid: String) -> void:
		_captured["poi"] = poi_id; _captured["type"] = t; _captured["sid"] = sid
	EventBus.poi_emerged.connect(cb)
	EventBus.poi_emerged.emit("poi_1", "religious_site", "settle_1")
	EventBus.poi_emerged.disconnect(cb)
	check(String(_captured.get("poi", "")) == "poi_1", "poi_id captured")
	check(String(_captured.get("type", "")) == "religious_site", "type captured")
	check(String(_captured.get("sid", "")) == "settle_1", "settlement_id captured")


func test_poi_stocked_signal() -> void:
	check(EventBus.has_signal("poi_stocked"),
		"EventBus.poi_stocked should exist")
	_captured.clear()
	var cb := func(poi_id: String, cid: String) -> void:
		_captured["poi"] = poi_id; _captured["cid"] = cid
	EventBus.poi_stocked.connect(cb)
	EventBus.poi_stocked.emit("poi_2", "char_1")
	EventBus.poi_stocked.disconnect(cb)
	check(String(_captured.get("poi", "")) == "poi_2" \
		and String(_captured.get("cid", "")) == "char_1",
		"poi_stocked payload preserved")


func test_poi_unstocked_signal() -> void:
	check(EventBus.has_signal("poi_unstocked"),
		"EventBus.poi_unstocked should exist")
	_captured.clear()
	var cb := func(poi_id: String, prior: String) -> void:
		_captured["poi"] = poi_id; _captured["prior"] = prior
	EventBus.poi_unstocked.connect(cb)
	EventBus.poi_unstocked.emit("poi_3", "char_2")
	EventBus.poi_unstocked.disconnect(cb)
	check(String(_captured.get("poi", "")) == "poi_3" \
		and String(_captured.get("prior", "")) == "char_2",
		"poi_unstocked payload preserved")


func test_poi_status_changed_signal() -> void:
	check(EventBus.has_signal("poi_status_changed"),
		"EventBus.poi_status_changed should exist")
	_captured.clear()
	var cb := func(poi_id: String, old_status: String, new_status: String) -> void:
		_captured["poi"] = poi_id
		_captured["old"] = old_status
		_captured["new"] = new_status
	EventBus.poi_status_changed.connect(cb)
	EventBus.poi_status_changed.emit("poi_4", "active", "dormant")
	EventBus.poi_status_changed.disconnect(cb)
	check(String(_captured.get("poi", "")) == "poi_4" \
		and String(_captured.get("old", "")) == "active" \
		and String(_captured.get("new", "")) == "dormant",
		"poi_status_changed payload preserved")


func test_spellcasting_service_purchased_signal() -> void:
	check(EventBus.has_signal("spellcasting_service_purchased"),
		"EventBus.spellcasting_service_purchased should exist")
	_captured.clear()
	var cb := func(poi_id: String, tradition: String, level: int, spell_name: String,
				payer: String, cost: int) -> void:
		_captured["poi"] = poi_id
		_captured["trad"] = tradition
		_captured["lvl"] = level
		_captured["name"] = spell_name
		_captured["payer"] = payer
		_captured["cost"] = cost
	EventBus.spellcasting_service_purchased.connect(cb)
	EventBus.spellcasting_service_purchased.emit(
		"poi_5", "divine", 1, "cure_light_wounds", "char_3", 10)
	EventBus.spellcasting_service_purchased.disconnect(cb)
	check(String(_captured.get("poi", "")) == "poi_5", "poi_id captured")
	check(String(_captured.get("trad", "")) == "divine", "tradition captured")
	check(int(_captured.get("lvl", -1)) == 1, "spell_level captured")
	check(String(_captured.get("name", "")) == "cure_light_wounds", "spell_name captured")
	check(String(_captured.get("payer", "")) == "char_3", "payer captured")
	check(int(_captured.get("cost", -1)) == 10, "unit_cost_gp captured")
