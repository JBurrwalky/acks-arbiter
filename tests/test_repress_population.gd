extends "res://tests/test_suite_base.gd"

## Tests for the repress_population activity handler [RAW PATCH] (Domain Phase 3).
##
## Verifies the handler sets domains.is_repressed_this_month=1 and
## repression_gp_per_family_this_month=N per acore_axioms §repression L510-516.
## The morale-cap-at-0 invariant is exercised by tests/test_repression.gd
## (Phase 0); this suite covers the handler's responsibility for SETTING the
## inputs to that resolver.


var _campaign_id: String = ""
var _ruler_id: String = ""
var _domain_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_handler_sets_columns_when_gp_per_family_positive()
	test_handler_no_op_when_gp_per_family_zero()
	test_handler_writes_ledger_entry()
	if not has_failures():
		print("RepressPopulationHandler: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test Repress", "TestWorld")
	_ruler_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Test Tyrant', 'pc', 'full', 'human', 'fighter', 9,
			14, 10, 10, 10, 10, 14, 60, 60)
	""", [_ruler_id, _campaign_id])
	_domain_id = CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Repress Test Domain",
		"territory_type": "borderlands",
		"owner_character_id": _ruler_id,
		"peasant_families": 200,
	})


func _make_state(gp_per_family: int) -> Dictionary:
	return {
		"id": "test_state_id",
		"character_id": _ruler_id,
		"activity_def_id": "repress_population",
		"params_json": JSON.stringify({"repressing_troops_gp_per_family": gp_per_family}),
	}


func test_handler_sets_columns_when_gp_per_family_positive() -> void:
	# Reset state.
	CampaignRepository.update_domain_monthly_state(_domain_id, {
		"is_repressed_this_month": 0,
		"repression_gp_per_family_this_month": 0,
	})
	var state := _make_state(4)
	var result: Dictionary = RepressPopulationHandler.on_complete(state, null)
	check(not String(result.get("summary", "")).is_empty(),
		"handler should return a summary")
	# Verify columns set.
	CampaignRepository.db.query_with_bindings(
		"SELECT is_repressed_this_month, repression_gp_per_family_this_month FROM domains WHERE id = ?",
		[_domain_id])
	check(not CampaignRepository.db.query_result.is_empty(), "domain row should be readable")
	var row: Dictionary = CampaignRepository.db.query_result[0]
	check(int(row.get("is_repressed_this_month", 0)) == 1,
		"is_repressed_this_month should be 1, got %s" % str(row.get("is_repressed_this_month", 0)))
	check(int(row.get("repression_gp_per_family_this_month", 0)) == 4,
		"repression_gp_per_family should be 4, got %s" % str(row.get("repression_gp_per_family_this_month", 0)))


func test_handler_no_op_when_gp_per_family_zero() -> void:
	CampaignRepository.update_domain_monthly_state(_domain_id, {
		"is_repressed_this_month": 0,
		"repression_gp_per_family_this_month": 0,
	})
	var state := _make_state(0)
	var result: Dictionary = RepressPopulationHandler.on_complete(state, null)
	# Verify columns unchanged.
	CampaignRepository.db.query_with_bindings(
		"SELECT is_repressed_this_month, repression_gp_per_family_this_month FROM domains WHERE id = ?",
		[_domain_id])
	var row: Dictionary = CampaignRepository.db.query_result[0]
	check(int(row.get("is_repressed_this_month", 0)) == 0,
		"is_repressed_this_month should remain 0 with 0 gp/family")
	check(String(result.get("summary", "")).contains("0 gp"),
		"summary should mention 0 gp/family no-effect")


func test_handler_writes_ledger_entry() -> void:
	CampaignRepository.update_domain_monthly_state(_domain_id, {
		"is_repressed_this_month": 0,
		"repression_gp_per_family_this_month": 0,
	})
	var prior_count := CampaignRepository.list_ledger_entries(_domain_id).size()
	var state := _make_state(2)
	RepressPopulationHandler.on_complete(state, null)
	var entries := CampaignRepository.list_ledger_entries(_domain_id)
	check(entries.size() > prior_count,
		"handler should add a ledger entry, prior=%d new=%d" % [prior_count, entries.size()])
	var found_repression := false
	for e in entries:
		if String(e.get("subcategory", "")) == "repression_active":
			found_repression = true
			break
	check(found_repression, "ledger should contain a repression_active subcategory entry")
