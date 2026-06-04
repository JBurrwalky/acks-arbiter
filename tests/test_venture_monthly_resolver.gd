extends "res://tests/test_suite_base.gd"

## Tests for VentureMonthlyResolver (Venturer→Guildhouse refactor): monopoly
## revenue + apprentice wage upkeep, pure functions, and an E2E found→seize→process.


var _campaign_id: String = ""
var _map_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_compute_revenue_pure()
	test_compute_upkeep_pure()
	test_e2e_found_seize_process()
	test_no_monopoly_no_revenue()
	if not has_failures():
		print("VentureMonthlyResolver: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Test VentureMonthly", "TestWorld")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "VMRMap"])


func _make_settlement(market_class: int, urban_families: int, hex_q: int, hex_r: int) -> String:
	var sid: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class, urban_families)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [sid, _campaign_id, _map_id, hex_q, hex_r, "Host_" + sid, market_class, urban_families])
	return sid


func _make_venturer(level: int, coins_cp: int) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_type, persistence_tier, race,
			 character_class, level, strength, intelligence, wisdom,
			 dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'venturer', ?, 10,11,10,12,10,13,24,24)
	""", [id, _campaign_id, "V_" + id, level])
	if coins_cp > 0:
		CampaignRepository.add_coins_cp(id, coins_cp)
	return id


# ----- Pure functions -----

func test_compute_revenue_pure() -> void:
	check(VentureMonthlyResolver.compute_monthly_revenue_cp(500, true) == 50000,
		"500 urban families × monopoly = 50,000cp")
	check(VentureMonthlyResolver.compute_monthly_revenue_cp(500, false) == 0,
		"no monopoly → no revenue")


func test_compute_upkeep_pure() -> void:
	# 5 L1 apprentices × 25gp × 100 = 12,500cp.
	check(VentureMonthlyResolver.compute_monthly_upkeep_cp([1, 1, 1, 1, 1]) == 12500,
		"5 L1 apprentices = 12,500cp upkeep")
	check(VentureMonthlyResolver.compute_monthly_upkeep_cp([]) == 0,
		"no apprentices = no upkeep")


# ----- Integration -----

func test_e2e_found_seize_process() -> void:
	# L12 venturer founds a guildhouse in a Class III settlement (1000 urban
	# families), seizes monopoly, then the monthly resolver pays revenue + wages.
	var settlement := _make_settlement(3, 1000, 5, 5)  # Class III → 75,000gp minimum
	var v := _make_venturer(12, 20_000_000)  # 200,000gp on hand
	var founded := FoundGuildhouseFlow.found_guildhouse({
		"campaign_id": _campaign_id, "owner_character_id": v,
		"host_settlement_entrance_id": settlement})
	check(founded["errors"].is_empty(), "E2E founding ok, errors=%s" % str(founded["errors"]))
	var fc: int = int(founded["apprentice_count"])
	var seize := FoundGuildhouseFlow.seize_monopoly({"owner_character_id": v})
	check(bool(seize["ok"]), "monopoly seized, errors=%s" % str(seize["errors"]))

	var gh := GuildhouseRepository.get_guildhouse_for_owner(v)
	var month := VentureMonthlyResolver.process_guildhouse_month(String(gh.get("id", "")))
	check(int(month.get("revenue_cp", 0)) == 100000,
		"monopoly revenue = 1000 families × 100 = 100,000cp; got %d" % int(month.get("revenue_cp", 0)))
	check(int(month.get("upkeep_cp", 0)) == fc * 2500,
		"upkeep = %d apprentices × 2,500cp = %d; got %d" % [fc, fc * 2500, int(month.get("upkeep_cp", 0))])
	check(bool(month.get("monopoly_active", false)), "monopoly active in the summary")


func test_no_monopoly_no_revenue() -> void:
	# A guildhouse without seized monopoly earns no revenue (income is the L12
	# monopoly; pre-L12 the guildhouse only incurs apprentice wages).
	var settlement := _make_settlement(6, 25, 6, 6)
	var v := _make_venturer(9, 1_000_000)
	FoundGuildhouseFlow.found_guildhouse({
		"campaign_id": _campaign_id, "owner_character_id": v,
		"host_settlement_entrance_id": settlement})
	var gh := GuildhouseRepository.get_guildhouse_for_owner(v)
	var month := VentureMonthlyResolver.process_guildhouse_month(String(gh.get("id", "")))
	check(int(month.get("revenue_cp", 0)) == 0, "no monopoly → 0 revenue")
	check(not bool(month.get("monopoly_active", true)), "monopoly inactive")
