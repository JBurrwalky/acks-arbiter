extends "res://tests/test_suite_base.gd"

## Mercantile category catalog parse test — Phase 10B.2 Wave 2.
##
## Verifies data/activities/mercantile_category.json loads via
## ActivityCatalog._load_all and all 6 activity rows are present with the
## expected param_schemas + frequency / activity_level / prerequisites per
## gdd-phase-10b-2-trade-block.md §1.3.


var _catalog: ActivityCatalog = null


func run_all_tests() -> void:
	_catalog = ActivityCatalog.new()
	test_category_loads()
	test_six_activities_present()
	test_buy_merchandise_metadata()
	test_sell_merchandise_metadata()
	test_persuade_merchants_metadata()
	test_solicit_merchants_ongoing_metadata()
	test_locate_merchandise_metadata()
	test_accept_shipping_contract_metadata()
	test_prerequisite_tags_present()

	if not has_failures():
		print("MercantileCategoryParse: all %d tests passed." % test_count())


func test_category_loads() -> void:
	var ids: Array = _catalog.list_by_category("mercantile")
	check(ids.size() > 0, "mercantile category loads at least one activity, got %d" % ids.size())


func test_six_activities_present() -> void:
	for activity_id in [
			"buy_merchandise", "sell_merchandise",
			"persuade_merchants", "solicit_merchants",
			"locate_merchandise", "accept_shipping_contract"]:
		check(_catalog.has_definition(activity_id),
			"catalog has '%s'" % activity_id)


func test_buy_merchandise_metadata() -> void:
	var d: Dictionary = _catalog.get_definition("buy_merchandise")
	check(String(d.get("category", "")) == "mercantile", "buy_merchandise category = mercantile")
	check(String(d.get("frequency", "")) == "singular", "buy_merchandise singular")
	check(String(d.get("activity_level", "")) == "minor", "buy_merchandise minor")
	check(not bool(d.get("strenuous", true)), "buy_merchandise not strenuous")
	var prereqs: Array = d.get("prerequisites", [])
	check("at_market_poi" in prereqs and "visible_merchant_present" in prereqs and "carrier_present" in prereqs,
		"buy_merchandise prerequisites include at_market_poi + visible_merchant_present + carrier_present")
	var schema: Dictionary = d.get("param_schema", {})
	for key in ["merchant_id", "merchandise_type", "loads_count", "carrier_id", "carrier_kind"]:
		check(schema.has(key), "buy_merchandise param_schema has '%s'" % key)


func test_sell_merchandise_metadata() -> void:
	var d: Dictionary = _catalog.get_definition("sell_merchandise")
	check(String(d.get("frequency", "")) == "singular", "sell_merchandise singular")
	var prereqs: Array = d.get("prerequisites", [])
	check("carrier_has_cargo" in prereqs, "sell_merchandise prerequisites include carrier_has_cargo")
	var schema: Dictionary = d.get("param_schema", {})
	for key in ["merchant_id", "cargo_hold_id", "loads_to_sell"]:
		check(schema.has(key), "sell_merchandise param_schema has '%s'" % key)


func test_persuade_merchants_metadata() -> void:
	var d: Dictionary = _catalog.get_definition("persuade_merchants")
	check(String(d.get("frequency", "")) == "singular", "persuade_merchants singular")
	var schema: Dictionary = d.get("param_schema", {})
	for key in ["merchant_id", "target_merchandise_type", "direction"]:
		check(schema.has(key), "persuade_merchants param_schema has '%s'" % key)


func test_solicit_merchants_ongoing_metadata() -> void:
	var d: Dictionary = _catalog.get_definition("solicit_merchants")
	check(String(d.get("frequency", "")) == "ongoing", "solicit_merchants ongoing")
	check(String(d.get("duration_formula", "")) == "21",
		"solicit_merchants duration_formula = '21' (3 weeks)")
	check(int(d.get("default_ticks_required", 0)) == 21,
		"solicit_merchants default_ticks_required = 21")


func test_locate_merchandise_metadata() -> void:
	var d: Dictionary = _catalog.get_definition("locate_merchandise")
	check(String(d.get("frequency", "")) == "singular", "locate_merchandise singular")
	var schema: Dictionary = d.get("param_schema", {})
	check(schema.has("merchandise_type"),
		"locate_merchandise param_schema has 'merchandise_type'")


func test_accept_shipping_contract_metadata() -> void:
	var d: Dictionary = _catalog.get_definition("accept_shipping_contract")
	check(String(d.get("frequency", "")) == "singular", "accept_shipping_contract singular")
	var prereqs: Array = d.get("prerequisites", [])
	check("shipping_offer_present" in prereqs,
		"accept_shipping_contract requires shipping_offer_present")
	var schema: Dictionary = d.get("param_schema", {})
	for key in ["offer_id", "carrier_id", "carrier_kind"]:
		check(schema.has(key), "accept_shipping_contract param_schema has '%s'" % key)


func test_prerequisite_tags_present() -> void:
	# at_market_poi must appear on every mercantile activity.
	for activity_id in [
			"buy_merchandise", "sell_merchandise",
			"persuade_merchants", "solicit_merchants",
			"locate_merchandise", "accept_shipping_contract"]:
		var d: Dictionary = _catalog.get_definition(activity_id)
		var prereqs: Array = d.get("prerequisites", [])
		check("at_market_poi" in prereqs,
			"%s prerequisites include at_market_poi" % activity_id)
