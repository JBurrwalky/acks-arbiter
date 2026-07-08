extends "res://tests/test_suite_base.gd"

## Faction FF-2.0/§6.1 (gdd-faction-framework.md) — org-type catalog + seeding
## determinism: the wage table + RAW level-mix, presence gating, syndicate-seed
## promotion (idempotent), and seed_for_settlement determinism incl. dominant
## temple PoI ownership and tithe-default sum-100. NOT executed by this build
## session — registered for the central suite.

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_catalog_wage_table_and_mix()
	test_catalog_ranks_and_services()
	test_catalog_presence_and_passthrough()
	test_promote_syndicate_seeds_idempotent()
	test_seed_for_settlement_determinism_and_poi_ownership()
	if not has_failures():
		print("FactionFF2Seeding: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FF2 Seeding Test", "World")


# ---------------------------------------------------------------------------

func test_catalog_wage_table_and_mix() -> void:
	check(OrgTypeCatalog.wage_gp_for_level(0) == 12, "L0 wage = 12 gp")
	check(OrgTypeCatalog.wage_gp_for_level(8) == 3000, "L8 wage = 3000 gp")
	check(OrgTypeCatalog.wage_gp_for_level(14) == 350000, "L14 wage = 350000 gp")
	# Pyramid mix: 0.45*12 + 0.35*25 + 0.125*50 + 0.075*100 = 27.9
	check(is_equal_approx(OrgTypeCatalog.avg_abstract_wage_gp(), 27.9),
		"avg abstract wage = 27.9 gp (RAW pyramid mix)")
	check(is_equal_approx(OrgTypeCatalog.abstract_wage_sum_gp(10), 279.0),
		"10 abstract members -> 279 gp wage sum")


func test_catalog_ranks_and_services() -> void:
	check(OrgTypeCatalog.rank_title("syndicate", 0) == "Associate", "syndicate rank 0")
	check(OrgTypeCatalog.rank_title("syndicate", 3) == "Boss", "syndicate rank 3")
	check(OrgTypeCatalog.rank_title("syndicate", 99) == "Boss", "rank index clamps to ladder end")
	check(OrgTypeCatalog.service_min_rank("temple", "consecration") == 3,
		"temple consecration requires rank 3")
	check(OrgTypeCatalog.service_min_rank("temple", "healing") == 0,
		"temple healing requires rank 0")
	check(OrgTypeCatalog.service_min_rank("temple", "nonexistent") == -1,
		"unknown service -> -1")


func test_catalog_presence_and_passthrough() -> void:
	check(OrgTypeCatalog.is_passthrough_income("syndicate"), "syndicate income is passthrough")
	check(OrgTypeCatalog.is_passthrough_income("merchant_guild"), "merchant_guild passthrough (Venturer)")
	check(not OrgTypeCatalog.is_passthrough_income("temple"), "temple uses ¼-wages")
	check(OrgTypeCatalog.presence_class_threshold("mage_guild") == 2, "mage_guild present at MC II+")


func test_promote_syndicate_seeds_idempotent() -> void:
	var sid := SyndicateRepository.create_syndicate({
		"campaign_id": _campaign_id, "boss_character_id": "",
		"syndicate_size_max": 8, "current_size": 3, "status": "active"})
	check(sid != "", "syndicate fixture created")
	var first: Array = OrgSeeder.promote_syndicate_seeds(_campaign_id)
	check("org_synd_%s" % sid in first, "syndicate seed promoted to org faction")
	var org: Dictionary = CampaignRepository.get_faction("org_synd_%s" % sid)
	check(not org.is_empty(), "org faction row exists")
	check(String(org.get("faction_type", "")) == "syndicate", "promoted org is a syndicate")
	check(String(org.get("scope", "")) == "organization", "promoted org is organization-scope")
	# Idempotent: re-running does not duplicate.
	var second: Array = OrgSeeder.promote_syndicate_seeds(_campaign_id)
	check(second.size() == first.size(), "promotion is idempotent (no duplicate rows)")


func test_seed_for_settlement_determinism_and_poi_ownership() -> void:
	# A domain + a settlement in it, with a temple PoI and a declared religion.
	var did := CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "Seed Domain"})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET peasant_families = ?, religion = ? WHERE id = ?",
		[800, "tulras", did])
	var settlement_id := CampaignRepository.create_settlement_entrance({
		"campaign_id": _campaign_id, "map_id": "map_seed", "hex_q": 1, "hex_r": 1,
		"name": "Seedborough", "market_class": 2})
	CampaignRepository.set_settlement_parent_domain(settlement_id, did)
	var poi_id := "poi_temple_seed"
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO settlement_pois (id, settlement_id, type, tier) VALUES (?, ?, 'religious_site', 'temple')",
		[poi_id, settlement_id])

	var seed := 4242
	var first: Array = OrgSeeder.seed_for_settlement(_campaign_id, settlement_id, seed, 0, false)
	var second: Array = OrgSeeder.seed_for_settlement(_campaign_id, settlement_id, seed, 0, false)
	first.sort()
	second.sort()
	check(first == second, "same seed -> identical org roster (determinism)")
	check(first.size() >= 1, "at least the dominant temple is seeded")

	# The dominant temple owns the settlement's temple PoI.
	var temple_id := "org_temple_%s_tulras" % settlement_id
	check(temple_id in first, "dominant temple seeded with deterministic id")
	CampaignRepository.db.query_with_bindings(
		"SELECT owner_faction_id FROM settlement_pois WHERE id = ?", [poi_id])
	var owner := ""
	if not CampaignRepository.db.query_result.is_empty():
		var v = CampaignRepository.db.query_result[0].get("owner_faction_id", null)
		owner = "" if v == null else String(v)
	check(owner == temple_id, "dominant temple owns the temple PoI (§4.7 reuse)")

	# Tithe defaults for the domain sum to 100.
	var total := 0
	for row in CampaignRepository.ff_list_tithe_shares(did):
		total += int((row as Dictionary).get("share_pct", 0))
	check(total == 100, "seeded tithe defaults sum to 100, got %d" % total)
