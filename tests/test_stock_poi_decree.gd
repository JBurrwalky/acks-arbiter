extends "res://tests/test_suite_base.gd"

## StockPoiDecreeHandler + UnstockPoiDecreeHandler tests — Stage H per
## GDD §7.2 / §13.8.

const TEST_CAMPAIGN := "test_stk_dec_campaign"
const TEST_MAP := "test_stk_dec_map"
const TEST_DOMAIN := "test_stk_dec_domain"
const TEST_SETTLEMENT := "test_stk_dec_settle"
const TEST_RULER := "test_stk_dec_ruler"
const TEST_CLERIC_HENCH := "test_stk_dec_cleric_h"
const TEST_FIGHTER_HENCH := "test_stk_dec_fighter_h"
const TEST_MAGE_HENCH := "test_stk_dec_mage_h"
const TEST_ALCHEMIST_SPEC := "test_stk_dec_alchemist"
const TEST_ON_DEMAND := "test_stk_dec_on_demand"

var _captured: Dictionary = {}


func run_all_tests() -> void:
	_cleanup()
	_setup_fixture()
	test_stock_cleric_into_temple_succeeds()
	test_stock_fighter_into_temple_rejected()
	test_stock_mage_into_mages_guild_hall_succeeds()
	test_one_character_per_poi_relocation_unassigns_prior()
	test_stock_emits_poi_stocked_signal()
	test_relocation_emits_poi_unstocked_then_poi_stocked()
	test_unstock_returns_to_null()
	test_unstock_emits_poi_unstocked_signal()
	test_unstock_unstocked_poi_rejected()
	test_stock_inactive_poi_rejected()
	test_stock_on_demand_npc_rejected()
	test_stock_specialist_into_workshop_kind_match()
	test_stock_named_tavern_accepts_any_class()
	_cleanup()
	if not has_failures():
		print("StockPoiDecree: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup_fixture() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings("INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "StockDecree Test"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, ?, ?)
	""", [TEST_MAP, TEST_CAMPAIGN, "Map", "regional_6mi"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO domains
			(id, campaign_id, name, peasant_families, religion, alignment)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [TEST_DOMAIN, TEST_CAMPAIGN, "StockDecree Domain", 1000,
		"lawful_silver_lady", "lawful"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 parent_domain_id, urban_families, cumulative_investment_gp)
		VALUES (?, ?, ?, 70, 70, 'StockDecree Town', 4, ?, 800, 75000)
	""", [TEST_SETTLEMENT, TEST_CAMPAIGN, TEST_MAP, TEST_DOMAIN])
	# PC ruler.
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, character_class,
			 combat_progression, level, alignment)
		VALUES (?, ?, ?, 'pc', 'fighter', 'fighter', 9, 'lawful')
	""", [TEST_RULER, TEST_CAMPAIGN, "PC Ruler"])
	# L7 Cleric henchman.
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, character_class,
			 combat_progression, level, alignment, is_active, employer_id)
		VALUES (?, ?, ?, 'henchman', 'cleric', 'cleric', 7, 'lawful', 1, ?)
	""", [TEST_CLERIC_HENCH, TEST_CAMPAIGN, "L7 Cleric Hench", TEST_RULER])
	# L5 Fighter henchman.
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, character_class,
			 combat_progression, level, alignment, is_active, employer_id)
		VALUES (?, ?, ?, 'henchman', 'fighter', 'fighter', 5, 'lawful', 1, ?)
	""", [TEST_FIGHTER_HENCH, TEST_CAMPAIGN, "L5 Fighter Hench", TEST_RULER])
	# L5 Mage henchman.
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, character_class,
			 combat_progression, level, alignment, is_active, employer_id)
		VALUES (?, ?, ?, 'henchman', 'mage', 'mage', 5, 'lawful', 1, ?)
	""", [TEST_MAGE_HENCH, TEST_CAMPAIGN, "L5 Mage Hench", TEST_RULER])
	# Specialist alchemist.
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, character_class,
			 combat_progression, level, alignment, npc_role)
		VALUES (?, ?, ?, 'npc', 'alchemist', 'fighter', 1, 'neutral', 'specialist')
	""", [TEST_ALCHEMIST_SPEC, TEST_CAMPAIGN, "Alchemist Spec"])
	# On-demand NPC — should be rejected.
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, character_class,
			 combat_progression, level, alignment, npc_role)
		VALUES (?, ?, ?, 'npc', 'cleric', 'cleric', 1, 'lawful', 'on_demand')
	""", [TEST_ON_DEMAND, TEST_CAMPAIGN, "On Demand NPC"])


func _cleanup() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM settlement_pois WHERE settlement_id = ?", [TEST_SETTLEMENT])
	db.query_with_bindings(
		"DELETE FROM characters WHERE id IN (?, ?, ?, ?, ?, ?)",
		[TEST_RULER, TEST_CLERIC_HENCH, TEST_FIGHTER_HENCH,
		 TEST_MAGE_HENCH, TEST_ALCHEMIST_SPEC, TEST_ON_DEMAND])
	db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE id = ?", [TEST_SETTLEMENT])
	db.query_with_bindings("DELETE FROM domains WHERE id = ?", [TEST_DOMAIN])
	db.query_with_bindings("DELETE FROM hex_maps WHERE id = ?", [TEST_MAP])
	db.query_with_bindings("DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _insert_poi(
	poi_id: String,
	poi_type: String,
	attached_specialist_kind: String = "",
	status: String = "active",
) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, tier, status, builder_kind,
			 emerged_via, established_at_calendar_day, gp_value,
			 l3_plus_npc_count, l1_l2_adherent_count,
			 attached_religion, attached_specialist_kind)
		VALUES (?, ?, ?, ?, ?, 'emergent',
				'class_advancement', 100, 1000, 0, 0, '', ?)
	""", [
		poi_id, TEST_SETTLEMENT, poi_type,
		"shrine" if poi_type == "religious_site" else "",
		status, attached_specialist_kind,
	])


func _get_poi(poi_id: String) -> Dictionary:
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM settlement_pois WHERE id = ?", [poi_id])
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


# ---------------------------------------------------------------------------
# Tests — stock
# ---------------------------------------------------------------------------

func test_stock_cleric_into_temple_succeeds() -> void:
	_insert_poi("stk_p_temple", "religious_site")
	var result := StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_temple",
		"character_id": TEST_CLERIC_HENCH,
	})
	check(bool(result.get("success", false)),
		"stock L7 cleric into temple should succeed; error='%s'"
		% String(result.get("error_code", "")))
	var poi := _get_poi("stk_p_temple")
	check(str_field(poi, "stocked_character_id") == TEST_CLERIC_HENCH,
		"stocked_character_id should be the cleric")


func test_stock_fighter_into_temple_rejected() -> void:
	_insert_poi("stk_p_temple_no_fighter", "religious_site")
	var result := StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_temple_no_fighter",
		"character_id": TEST_FIGHTER_HENCH,
	})
	check(not bool(result.get("success", false)),
		"fighter into temple should be rejected")
	check(String(result.get("error_code", "")) == "class_mismatch",
		"error_code should be 'class_mismatch'; got '%s'"
		% String(result.get("error_code", "")))


func test_stock_mage_into_mages_guild_hall_succeeds() -> void:
	_insert_poi("stk_p_mage", "mages_guild_hall")
	var result := StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_mage",
		"character_id": TEST_MAGE_HENCH,
	})
	check(bool(result.get("success", false)),
		"stock mage into mages_guild_hall should succeed")


func test_one_character_per_poi_relocation_unassigns_prior() -> void:
	_insert_poi("stk_p_temple_a", "religious_site")
	_insert_poi("stk_p_temple_b", "religious_site")
	# Stock cleric into temple A.
	StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_temple_a",
		"character_id": TEST_CLERIC_HENCH,
	})
	check(str_field(_get_poi("stk_p_temple_a"), "stocked_character_id") == TEST_CLERIC_HENCH,
		"temple A should have the cleric stocked")
	# Now stock the same cleric into temple B.
	var result := StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_temple_b",
		"character_id": TEST_CLERIC_HENCH,
	})
	check(bool(result.get("success", false)),
		"relocation to temple B should succeed")
	check(String(result.get("prior_poi_id", "")) == "stk_p_temple_a",
		"result should report prior_poi_id = temple A; got '%s'"
		% String(result.get("prior_poi_id", "")))
	# Temple A should be unstocked now.
	var poi_a_v: Variant = _get_poi("stk_p_temple_a").get("stocked_character_id", null)
	check(poi_a_v == null or String(poi_a_v).is_empty(),
		"temple A should have stocked_character_id NULL after relocation")
	check(str_field(_get_poi("stk_p_temple_b"), "stocked_character_id") == TEST_CLERIC_HENCH,
		"temple B should now have the cleric")


func test_stock_emits_poi_stocked_signal() -> void:
	_insert_poi("stk_p_signal", "religious_site")
	_captured.clear()
	var cb := func(poi_id: String, character_id: String) -> void:
		_captured["poi_id"] = poi_id
		_captured["character_id"] = character_id
	EventBus.poi_stocked.connect(cb)
	StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_signal",
		"character_id": TEST_CLERIC_HENCH,
	})
	EventBus.poi_stocked.disconnect(cb)
	check(String(_captured.get("poi_id", "")) == "stk_p_signal",
		"poi_stocked signal should fire with poi_id")
	check(str_field(_captured, "character_id") == TEST_CLERIC_HENCH,
		"poi_stocked signal should fire with character_id")


func test_relocation_emits_poi_unstocked_then_poi_stocked() -> void:
	_insert_poi("stk_p_relo_a", "religious_site")
	_insert_poi("stk_p_relo_b", "religious_site")
	StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_relo_a",
		"character_id": TEST_CLERIC_HENCH,
	})
	var unstocked_events: Array = []
	var stocked_events: Array = []
	var unstock_cb := func(poi_id: String, prior: String) -> void:
		unstocked_events.append({"poi": poi_id, "prior": prior})
	var stock_cb := func(poi_id: String, char_id: String) -> void:
		stocked_events.append({"poi": poi_id, "char": char_id})
	EventBus.poi_unstocked.connect(unstock_cb)
	EventBus.poi_stocked.connect(stock_cb)
	StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_relo_b",
		"character_id": TEST_CLERIC_HENCH,
	})
	EventBus.poi_unstocked.disconnect(unstock_cb)
	EventBus.poi_stocked.disconnect(stock_cb)
	check(unstocked_events.size() >= 1,
		"poi_unstocked should fire on relocation; got %d events"
		% unstocked_events.size())
	check(stocked_events.size() >= 1,
		"poi_stocked should fire on relocation; got %d events"
		% stocked_events.size())


func test_unstock_returns_to_null() -> void:
	_insert_poi("stk_p_unstock", "religious_site")
	StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_unstock",
		"character_id": TEST_CLERIC_HENCH,
	})
	var result := UnstockPoiDecreeHandler.try_unstock({
		"poi_id": "stk_p_unstock",
	})
	check(bool(result.get("success", false)),
		"unstock should succeed; error='%s'" % String(result.get("error_code", "")))
	check(String(result.get("prior_character_id", "")) == TEST_CLERIC_HENCH,
		"unstock should return prior character id")
	var poi := _get_poi("stk_p_unstock")
	var stocked_v: Variant = poi.get("stocked_character_id", null)
	check(stocked_v == null or String(stocked_v).is_empty(),
		"stocked_character_id should be NULL after unstock")


func test_unstock_emits_poi_unstocked_signal() -> void:
	_insert_poi("stk_p_unsig", "religious_site")
	StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_unsig",
		"character_id": TEST_CLERIC_HENCH,
	})
	_captured.clear()
	var cb := func(poi_id: String, prior: String) -> void:
		_captured["poi_id"] = poi_id
		_captured["prior"] = prior
	EventBus.poi_unstocked.connect(cb)
	UnstockPoiDecreeHandler.try_unstock({"poi_id": "stk_p_unsig"})
	EventBus.poi_unstocked.disconnect(cb)
	check(String(_captured.get("poi_id", "")) == "stk_p_unsig",
		"poi_unstocked should fire")


func test_unstock_unstocked_poi_rejected() -> void:
	_insert_poi("stk_p_already_unstocked", "religious_site")
	var result := UnstockPoiDecreeHandler.try_unstock({
		"poi_id": "stk_p_already_unstocked",
	})
	check(String(result.get("error_code", "")) == "not_stocked",
		"unstocking an already-empty POI should return 'not_stocked'; got '%s'"
		% String(result.get("error_code", "")))


func test_stock_inactive_poi_rejected() -> void:
	_insert_poi("stk_p_dormant", "religious_site", "", "dormant")
	var result := StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_dormant",
		"character_id": TEST_CLERIC_HENCH,
	})
	check(String(result.get("error_code", "")) == "poi_inactive",
		"dormant POI should reject stock; got '%s'"
		% String(result.get("error_code", "")))


func test_stock_on_demand_npc_rejected() -> void:
	_insert_poi("stk_p_no_od", "religious_site")
	var result := StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_no_od",
		"character_id": TEST_ON_DEMAND,
	})
	check(String(result.get("error_code", "")) == "ineligible_role",
		"on_demand NPC should be rejected; got '%s'"
		% String(result.get("error_code", "")))


## Workshop stocking requires the character_class to match
## attached_specialist_kind.
func test_stock_specialist_into_workshop_kind_match() -> void:
	_insert_poi("stk_p_workshop_alch", "workshop", "alchemist")
	var result := StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_workshop_alch",
		"character_id": TEST_ALCHEMIST_SPEC,
	})
	check(bool(result.get("success", false)),
		"alchemist into alchemist workshop should succeed; error='%s'"
		% String(result.get("error_code", "")))
	# Cross-kind rejection:
	_insert_poi("stk_p_workshop_other", "workshop", "healer_general")
	var bad := StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_workshop_other",
		"character_id": TEST_ALCHEMIST_SPEC,
	})
	check(String(bad.get("error_code", "")) == "class_mismatch",
		"alchemist into healer workshop should be rejected; got '%s'"
		% String(bad.get("error_code", "")))


func test_stock_named_tavern_accepts_any_class() -> void:
	_insert_poi("stk_p_tavern", "named_tavern")
	# Use the fighter henchman — would be rejected at a temple, accepted here.
	var result := StockPoiDecreeHandler.try_stock({
		"poi_id": "stk_p_tavern",
		"character_id": TEST_FIGHTER_HENCH,
	})
	check(bool(result.get("success", false)),
		"named_tavern should accept any class (Q-UGS-3 v1); error='%s'"
		% String(result.get("error_code", "")))
