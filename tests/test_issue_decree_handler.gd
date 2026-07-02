extends "res://tests/test_suite_base.gd"

## Tests for the issue_decree activity handler (Domain Phase 3).
##
## Regression coverage for the gp/cp units bug: decree "value" for
## decree_kind in {tax, liturgy, tithe} is CP/family — matching
## domains.{tax,liturgy,tithe}_rate_cp_per_family and the
## RulerActionCatalog "VALUE IS CP" contract. UI callers presenting a
## gp/family control convert gp -> cp (x100) before dispatching; this
## suite locks the handler's cp-in / cp-out contract so a UI regression
## can't silently reintroduce the 100x revenue bug.


var _campaign_id: String = ""
var _ruler_id: String = ""
var _domain_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_tax_decree_of_200_cp_yields_200_cp_column()
	test_liturgy_decree_writes_liturgy_column()
	test_tithe_decree_writes_tithe_column()
	test_null_value_falls_back_to_raw_defaults()
	test_summary_string_reports_gp_not_cp()
	if not has_failures():
		print("IssueDecreeHandler: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test Decree", "TestWorld")
	_ruler_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Test Ruler', 'pc', 'full', 'human', 'fighter', 9,
			14, 10, 10, 10, 10, 14, 60, 60)
	""", [_ruler_id, _campaign_id])
	_domain_id = CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Decree Test Domain",
		"territory_type": "borderlands",
		"owner_character_id": _ruler_id,
		"peasant_families": 100,
	})


func _make_state(decree_kind: String, value: Variant) -> Dictionary:
	var params := {"domain_id": _domain_id, "decree_kind": decree_kind}
	if value != null:
		params["value"] = value
	return {
		"id": "test_state_id",
		"character_id": _ruler_id,
		"activity_def_id": "issue_decree",
		"params_json": JSON.stringify(params),
	}


func _read_domain() -> Dictionary:
	CampaignRepository.db.query_with_bindings(
		"SELECT tax_rate_cp_per_family, liturgy_rate_cp_per_family, tithe_rate_cp_per_family "
		+ "FROM domains WHERE id = ?", [_domain_id])
	return CampaignRepository.db.query_result[0] if not CampaignRepository.db.query_result.is_empty() else {}


## A UI dispatching a "2 gp/family" tax decree sends value=200 (cp) per the
## handler's cp-in contract — the actual regression this suite guards.
func test_tax_decree_of_200_cp_yields_200_cp_column() -> void:
	var state := _make_state("tax", 200)
	IssueDecreeHandler.on_complete(state, null)
	var row := _read_domain()
	check(int(row.get("tax_rate_cp_per_family", -1)) == 200,
		"a 2gp/family tax decree should set tax_rate_cp_per_family=200, got %s"
			% str(row.get("tax_rate_cp_per_family", "?")))


func test_liturgy_decree_writes_liturgy_column() -> void:
	var state := _make_state("liturgy", 300)
	IssueDecreeHandler.on_complete(state, null)
	var row := _read_domain()
	check(int(row.get("liturgy_rate_cp_per_family", -1)) == 300,
		"a 3gp/family liturgy decree should set liturgy_rate_cp_per_family=300, got %s"
			% str(row.get("liturgy_rate_cp_per_family", "?")))


func test_tithe_decree_writes_tithe_column() -> void:
	var state := _make_state("tithe", 400)
	IssueDecreeHandler.on_complete(state, null)
	var row := _read_domain()
	check(int(row.get("tithe_rate_cp_per_family", -1)) == 400,
		"a 4gp/family tithe decree should set tithe_rate_cp_per_family=400, got %s"
			% str(row.get("tithe_rate_cp_per_family", "?")))


## Null-value fallbacks must match the schema's cp defaults (200/100/100),
## not the pre-fix gp-scale fallbacks (2/1/1).
func test_null_value_falls_back_to_raw_defaults() -> void:
	var tax_state := _make_state("tax", null)
	IssueDecreeHandler.on_complete(tax_state, null)
	check(int(_read_domain().get("tax_rate_cp_per_family", -1)) == 200,
		"null-value tax decree should fall back to 200 cp/family (RAW standard)")
	var liturgy_state := _make_state("liturgy", null)
	IssueDecreeHandler.on_complete(liturgy_state, null)
	check(int(_read_domain().get("liturgy_rate_cp_per_family", -1)) == 100,
		"null-value liturgy decree should fall back to 100 cp/family (RAW standard)")
	var tithe_state := _make_state("tithe", null)
	IssueDecreeHandler.on_complete(tithe_state, null)
	check(int(_read_domain().get("tithe_rate_cp_per_family", -1)) == 100,
		"null-value tithe decree should fall back to 100 cp/family (RAW standard)")


func test_summary_string_reports_gp_not_cp() -> void:
	var state := _make_state("tax", 200)
	var result: Dictionary = IssueDecreeHandler.on_complete(state, null)
	var summary := String(result.get("summary", ""))
	check(summary.contains("2 gp/family"),
		"summary for a 200cp tax decree should read '2 gp/family', got '%s'" % summary)
