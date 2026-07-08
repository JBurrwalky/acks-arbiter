extends "res://tests/test_suite_base.gd"

## Faction FF-2.3 (gdd-faction-framework.md §6.4/§4.9) — the tithe apportionment
## engine: sum-to-100 apportionment, +10 ruler-deity seeding bias, monthly gp
## distribution (banker's rounding), the shared apply() validator, ledger writes
## (patronage/grievance), the issue_decree(tithe_apportionment) shared path, and
## the panel data contract. NOT executed by this build session — registered for
## the central suite.

var _campaign_id: String = ""
var _domain_id: String = ""
var _realm_id: String = "realm_tithe_test"
var _mirror_id: String = ""
var _temple_a: String = ""   # ruler's deity (biased)
var _temple_b: String = ""
var _temple_c: String = ""


func run_all_tests() -> void:
	_setup()
	test_apportion_points_sums_to_100()
	test_apportion_equal_when_zero_basis()
	test_seed_defaults_ruler_deity_bias_and_sum100()
	test_distribute_month_bankers()
	test_apply_rejects_bad_sum()
	test_apply_rejects_absent_faction()
	test_apply_rejects_partial_coverage()
	test_apply_writes_patronage_and_grievance_ledger()
	test_issue_decree_tithe_apportionment_shared_path()
	test_panel_model_shape()
	if not has_failures():
		print("FactionFF2Tithe: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FF2 Tithe Test", "World")
	# A realm mirror so apply() can attribute ruler-side patronage/grievance.
	var mirror := FactionData.new()
	mirror.id = "mirror_%s" % _realm_id
	mirror.campaign_id = _campaign_id
	mirror.name = "Realm Mirror"
	mirror.faction_type = "realm"
	mirror.scope = "realm"
	mirror.realm_id = _realm_id
	CampaignRepository.create_faction(mirror)
	_mirror_id = mirror.id
	# A domain with 1000 families (tithe pool = 1000 gp), in the realm.
	_domain_id = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "Tithe Domain"})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET peasant_families = ?, realm_id = ?, religion = ? WHERE id = ?",
		[1000, _realm_id, "tulras", _domain_id])
	# Three temples with congregant proxies 500 / 300 / 200.
	_temple_a = _mk_temple("Temple of Tulras", "tulras", 500)
	_temple_b = _mk_temple("Temple of Realta", "realta", 300)
	_temple_c = _mk_temple("Temple of Ammon", "ammon", 200)


func _mk_temple(nm: String, religion: String, congregants: int) -> String:
	var f := FactionData.new()
	f.campaign_id = _campaign_id
	f.name = nm
	f.faction_type = "temple"
	f.scope = "organization"
	f.religion_id = religion
	f.home_domain_id = _domain_id
	f.member_count_abstract = congregants
	f.status = "active"
	return CampaignRepository.create_faction(f)


# ---------------------------------------------------------------------------

func test_apportion_points_sums_to_100() -> void:
	var pts: Dictionary = TitheApportionment.apportion_points(
		{"a": 500.0, "b": 300.0, "c": 200.0})
	var total: int = 0
	for k in pts:
		total += int(pts[k])
	check(total == 100, "apportion_points must sum to 100, got %d" % total)
	check(int(pts["a"]) > int(pts["c"]), "larger congregation -> larger share")


func test_apportion_equal_when_zero_basis() -> void:
	var pts: Dictionary = TitheApportionment.apportion_points({"x": 0.0, "y": 0.0})
	var total: int = int(pts.get("x", 0)) + int(pts.get("y", 0))
	check(total == 100, "zero-basis apportion still sums to 100")


func test_seed_defaults_ruler_deity_bias_and_sum100() -> void:
	var shares: Dictionary = TitheApportionment.seed_defaults(
		_campaign_id, _domain_id, "tulras", 10)
	var total: int = 0
	for k in shares:
		total += int(shares[k])
	check(total == 100, "seeded tithe shares sum to 100, got %d" % total)
	# Temple A (tulras, congregants 500 = 50%) should get MORE than 50 due to +10 bias.
	check(int(shares.get(_temple_a, 0)) > 50,
		"ruler-deity temple biased above its 50%% congregant share: %d" % int(shares.get(_temple_a, 0)))


func test_distribute_month_bankers() -> void:
	TitheApportionment.seed_defaults(_campaign_id, _domain_id, "tulras", 10)
	var dist: Dictionary = TitheApportionment.distribute_month(_domain_id)
	var total: int = 0
	for k in dist:
		total += int(dist[k])
	# Pool is 1000 gp; distributed gp is within rounding of the pool.
	check(absi(total - 1000) <= 3, "distributed tithe ~= pool (1000), got %d" % total)
	check(int(dist.get(_temple_a, 0)) > int(dist.get(_temple_c, 0)),
		"biased temple receives more gp than the smallest")


func test_apply_rejects_bad_sum() -> void:
	var res: Dictionary = TitheApportionment.apply(
		_campaign_id, _domain_id, {_temple_a: 50, _temple_b: 30, _temple_c: 10}, 20)
	check(not bool(res.get("ok", true)), "apply rejects a non-100 sum")
	check(String(res.get("reason", "")).begins_with("sum_not_100"), "reason names the bad sum")


func test_apply_rejects_absent_faction() -> void:
	var res: Dictionary = TitheApportionment.apply(
		_campaign_id, _domain_id, {"not_a_temple": 100}, 20)
	check(not bool(res.get("ok", true)), "apply rejects a non-present faction")


func test_apply_rejects_partial_coverage() -> void:
	# A map that OMITS a present temple must be rejected: the omitted temple keeps
	# its stale persisted row, so distribute_month would pay it on TOP of the
	# supplied shares — over-distributing the pool past 100%.
	var res: Dictionary = TitheApportionment.apply(
		_campaign_id, _domain_id, {_temple_a: 60, _temple_b: 40}, 20)
	check(not bool(res.get("ok", true)),
		"a partial map (2 of the 3 present temples, summing to 100) is rejected")
	check(String(res.get("reason", "")).begins_with("missing_temple"),
		"the rejection reason names the omitted temple")


func test_apply_writes_patronage_and_grievance_ledger() -> void:
	# Seed A=60 B=25 C=15 baseline, then move 10 points from B to A.
	TitheApportionment.apply(_campaign_id, _domain_id,
		{_temple_a: 60, _temple_b: 25, _temple_c: 15}, 30)
	var res: Dictionary = TitheApportionment.apply(_campaign_id, _domain_id,
		{_temple_a: 70, _temple_b: 15, _temple_c: 15}, 31, "ruler_x")
	check(bool(res.get("ok", false)), "valid re-apportionment applies")
	# Winner A holds patronage from the ruler mirror.
	var patronage: Array = CampaignRepository.ff_list_faction_events(_mirror_id, _temple_a)
	check(_has_kind(patronage, "patronage_granted"),
		"winner temple gets patronage_granted from the ruler mirror")
	# Loser B holds grievance (persecution) vs the winner A.
	var grievance: Array = CampaignRepository.ff_list_faction_events(_temple_a, _temple_b)
	check(_has_kind(grievance, "persecution"),
		"loser temple holds a persecution grievance vs the winner")


func test_issue_decree_tithe_apportionment_shared_path() -> void:
	# The SAME path a player Tithe panel confirm uses: issue_decree with
	# decree_kind='tithe_apportionment' + params.shares.
	var params := {
		"domain_id": _domain_id, "decree_kind": "tithe_apportionment",
		"shares": {_temple_a: 34, _temple_b: 33, _temple_c: 33},
	}
	var outcome: Dictionary = IssueDecreeHandler.on_complete(
		{"character_id": "ruler_x", "params_json": JSON.stringify(params)}, null)
	check(String(outcome.get("decree_kind", "")) == "tithe_apportionment",
		"decree_kind rides the outcome for the narrator cache variant")
	# The shares persisted.
	var shares_now: Dictionary = {}
	for row in CampaignRepository.ff_list_tithe_shares(_domain_id):
		shares_now[String((row as Dictionary).get("faction_id", ""))] = \
			int((row as Dictionary).get("share_pct", 0))
	check(int(shares_now.get(_temple_a, 0)) == 34, "decree persisted the new apportionment")


func test_panel_model_shape() -> void:
	var model: Dictionary = TitheApportionment.panel_model(_domain_id)
	check(bool(model.get("has_temples", false)), "panel model reports temples present")
	check(int(model.get("pool_gp", 0)) == 1000, "panel pool_gp = 1000")
	check((model.get("temples", []) as Array).size() == 3, "panel lists all 3 temples")
	for t in model.get("temples", []):
		check((t as Dictionary).has("congregant_share_pct"), "each temple has the fairness reference")
		check((t as Dictionary).has("gp_preview"), "each temple has a gp preview")


func _has_kind(rows: Array, kind: String) -> bool:
	for r in rows:
		if String((r as Dictionary).get("kind", "")) == kind:
			return true
	return false
