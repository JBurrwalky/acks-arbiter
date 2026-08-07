extends "res://tests/test_suite_base.gd"

## BaselineNpcStocker tests — Stage D per GDD §13.4 acceptance criteria.
##
## Each test seeds a fresh campaign + map + settlement + domain + POI,
## invokes BaselineNpcStocker.stock_poi directly with a seeded RNG, and
## queries the characters / settlement_pois tables to verify the resulting
## NPC rows + POI head pointer.

const TEST_CAMPAIGN := "test_stocker_campaign"
const TEST_MAP := "test_stocker_map"
const TEST_DOMAIN := "test_stocker_domain"
const TEST_SETTLEMENT := "test_stocker_settle"


func run_all_tests() -> void:
	_cleanup()
	_setup_fixture()
	test_k_local_one_stocks_head_only()
	test_k_local_three_stocks_head_plus_two_adherents()
	test_shrine_baseline_stocks_l1_or_l2_cleric()
	test_mages_guild_hall_stocks_mage()
	test_mercenary_guild_hall_stocks_fighter()
	test_workshop_specialist_kind_set()
	test_named_tavern_stocks_normal_man()
	test_baseline_head_pointer_set_on_poi()
	test_idempotent_does_not_double_stock()
	test_alignment_inherits_from_domain()
	_cleanup()
	if not has_failures():
		print("BaselineNpcStocker: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup_fixture() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings("INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Stocker Test"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, ?, ?)
	""", [TEST_MAP, TEST_CAMPAIGN, "Stocker Map", "regional_6mi"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_cells (map_id, q, r, water)
		VALUES (?, ?, ?, ?)
	""", [TEST_MAP, 20, 20, ""])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO domains
			(id, campaign_id, name, peasant_families, religion, alignment)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [TEST_DOMAIN, TEST_CAMPAIGN, "Stocker Domain", 1000,
		"lawful_silver_lady", "lawful"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 parent_domain_id, urban_families, cumulative_investment_gp)
		VALUES (?, ?, ?, 20, 20, ?, 4, ?, 800, 75000)
	""", [TEST_SETTLEMENT, TEST_CAMPAIGN, TEST_MAP,
		"Stocker Town", TEST_DOMAIN])


func _cleanup() -> void:
	var db = CampaignRepository.db
	# Order matters: delete characters that reference settlement_pois first,
	# then settlement_pois, then dependent rows.
	db.query_with_bindings("""
		DELETE FROM characters
		WHERE home_poi_id IN (
			SELECT id FROM settlement_pois WHERE settlement_id = ?
		)
	""", [TEST_SETTLEMENT])
	db.query_with_bindings(
		"DELETE FROM settlement_pois WHERE settlement_id = ?",
		[TEST_SETTLEMENT])
	db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE id = ?", [TEST_SETTLEMENT])
	db.query_with_bindings("DELETE FROM domains WHERE id = ?", [TEST_DOMAIN])
	db.query_with_bindings("DELETE FROM hex_cells WHERE map_id = ?", [TEST_MAP])
	db.query_with_bindings("DELETE FROM hex_maps WHERE id = ?", [TEST_MAP])
	db.query_with_bindings("DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _insert_poi(
	poi_id: String,
	poi_type: String,
	k_local: int,
	tier: String = "",
	attached_specialist_kind: String = "",
	attached_religion: String = "",
) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_pois
			(id, settlement_id, type, tier, status, builder_kind,
			 emerged_via, established_at_calendar_day, gp_value,
			 l3_plus_npc_count, l1_l2_adherent_count,
			 attached_religion, attached_specialist_kind)
		VALUES (?, ?, ?, ?, 'active', 'emergent',
				'class_advancement', 100, 1000, ?, 0, ?, ?)
	""", [
		poi_id, TEST_SETTLEMENT, poi_type,
		tier if poi_type == "religious_site" else "",
		k_local,
		attached_religion,
		attached_specialist_kind,
	])


func _get_character(character_id: String) -> Dictionary:
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM characters WHERE id = ?", [character_id])
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


func _list_characters_at_poi(poi_id: String) -> Array:
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM characters WHERE home_poi_id = ?", [poi_id])
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## K_local=1 should stock exactly 1 head NPC, no adherents.
func test_k_local_one_stocks_head_only() -> void:
	var poi_id := "stk_poi_k1"
	_insert_poi(poi_id, "mages_guild_hall", 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 100
	var result := BaselineNpcStocker.stock_poi(poi_id, rng)
	check(int(result.get("adherent_count", -1)) == 0,
		"K_local=1 should produce 0 adherents; got %d"
		% int(result.get("adherent_count", -1)))
	var characters := _list_characters_at_poi(poi_id)
	check(characters.size() == 1,
		"K_local=1 should produce 1 character row total; got %d" % characters.size())


## K_local=3 should stock 1 head + 2 adherents, all at home_poi_id=this POI.
func test_k_local_three_stocks_head_plus_two_adherents() -> void:
	var poi_id := "stk_poi_k3"
	_insert_poi(poi_id, "religious_site", 3, "shrine")
	var rng := RandomNumberGenerator.new()
	rng.seed = 200
	var result := BaselineNpcStocker.stock_poi(poi_id, rng)
	check(int(result.get("adherent_count", -1)) == 2,
		"K_local=3 should produce 2 adherents; got %d"
		% int(result.get("adherent_count", -1)))
	var characters := _list_characters_at_poi(poi_id)
	check(characters.size() == 3,
		"K_local=3 should produce 3 character rows; got %d" % characters.size())
	# All adherents should be at level >= 3 (per §7.3 floor).
	for c in characters:
		check(int(c.get("level", 0)) >= 3,
			"all K_local>0 stocked NPCs should be L3+; got level=%d for %s"
			% [int(c.get("level", 0)), String(c.get("name", "?"))])


## Shrine baseline (K_local=0) stocks an L1-L2 cleric.
func test_shrine_baseline_stocks_l1_or_l2_cleric() -> void:
	var poi_id := "stk_poi_shrine"
	_insert_poi(poi_id, "religious_site", 0, "shrine")
	var rng := RandomNumberGenerator.new()
	rng.seed = 300
	var result := BaselineNpcStocker.stock_poi(poi_id, rng)
	var head_id := str_field(result, "head_character_id")
	check(not head_id.is_empty(), "shrine should stock a head NPC")
	if head_id.is_empty():
		return
	var head := _get_character(head_id)
	check(String(head.get("character_class", "")) == "cleric",
		"shrine head should be a cleric; got '%s'"
		% String(head.get("character_class", "")))
	var head_level: int = int(head.get("level", -1))
	check(head_level >= 1 and head_level <= 2,
		"shrine head should be L1-L2; got %d" % head_level)


## Mages Guild Hall stocks a Mage as the head.
func test_mages_guild_hall_stocks_mage() -> void:
	var poi_id := "stk_poi_mage"
	_insert_poi(poi_id, "mages_guild_hall", 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 400
	var result := BaselineNpcStocker.stock_poi(poi_id, rng)
	var head_id := str_field(result, "head_character_id")
	check(not head_id.is_empty(), "mages_guild_hall should stock a head NPC")
	if head_id.is_empty():
		return
	var head := _get_character(head_id)
	check(String(head.get("character_class", "")) == "mage",
		"mages_guild_hall head should be a mage; got '%s'"
		% String(head.get("character_class", "")))
	check(String(head.get("combat_progression", "")) == "mage",
		"mages_guild_hall head combat_progression should be 'mage'")


## Mercenary Guild Hall stocks a Fighter as the head.
func test_mercenary_guild_hall_stocks_fighter() -> void:
	var poi_id := "stk_poi_mercs"
	_insert_poi(poi_id, "mercenary_guild_hall", 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 500
	var result := BaselineNpcStocker.stock_poi(poi_id, rng)
	var head_id := str_field(result, "head_character_id")
	if head_id.is_empty():
		check(false, "mercenary_guild_hall should stock a head NPC")
		return
	var head := _get_character(head_id)
	check(String(head.get("character_class", "")) == "fighter",
		"mercenary_guild_hall head should be a fighter; got '%s'"
		% String(head.get("character_class", "")))


## Workshop with attached_specialist_kind='alchemist' stocks an Alchemist
## specialist NPC.
func test_workshop_specialist_kind_set() -> void:
	var poi_id := "stk_poi_workshop"
	_insert_poi(poi_id, "workshop", 0, "", "alchemist")
	var rng := RandomNumberGenerator.new()
	rng.seed = 600
	var result := BaselineNpcStocker.stock_poi(poi_id, rng)
	var head_id := str_field(result, "head_character_id")
	if head_id.is_empty():
		check(false, "workshop should stock a head specialist")
		return
	var head := _get_character(head_id)
	check(String(head.get("character_class", "")) == "alchemist",
		"workshop head character_class should match attached_specialist_kind; got '%s'"
		% String(head.get("character_class", "")))


## Named tavern stocks a 0-level normal man (innkeeper).
func test_named_tavern_stocks_normal_man() -> void:
	var poi_id := "stk_poi_tavern"
	_insert_poi(poi_id, "named_tavern", 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 700
	var result := BaselineNpcStocker.stock_poi(poi_id, rng)
	var head_id := str_field(result, "head_character_id")
	if head_id.is_empty():
		check(false, "named_tavern should stock a head NPC")
		return
	var head := _get_character(head_id)
	check(String(head.get("character_class", "")) == "normal_man",
		"named_tavern head should be a normal_man; got '%s'"
		% String(head.get("character_class", "")))


## After stocking, the POI's baseline_head_npc_character_id should point
## at the new head NPC, and the npc_role + home_poi_id columns must be
## populated correctly.
func test_baseline_head_pointer_set_on_poi() -> void:
	var poi_id := "stk_poi_head_ptr"
	_insert_poi(poi_id, "mages_guild_hall", 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 800
	var result := BaselineNpcStocker.stock_poi(poi_id, rng)
	var head_id := str_field(result, "head_character_id")
	if head_id.is_empty():
		check(false, "expected head NPC id")
		return
	CampaignRepository.db.query_with_bindings(
		"SELECT baseline_head_npc_character_id FROM settlement_pois WHERE id = ?",
		[poi_id])
	if CampaignRepository.db.query_result.is_empty():
		check(false, "POI row should exist")
		return
	var stored_head: String = str_field(
		CampaignRepository.db.query_result[0], "baseline_head_npc_character_id")
	check(stored_head == head_id,
		"POI baseline_head_npc_character_id should point at the new head NPC; got '%s' expected '%s'"
		% [stored_head, head_id])
	# Verify all stocked characters have npc_role='baseline_placeholder' and
	# home_poi_id pointing at this POI.
	var characters := _list_characters_at_poi(poi_id)
	for c in characters:
		check(String(c.get("npc_role", "")) == "baseline_placeholder",
			"stocked NPC should have npc_role='baseline_placeholder'; got '%s'"
			% String(c.get("npc_role", "")))
		check(str_field(c, "home_poi_id") == poi_id,
			"stocked NPC home_poi_id should match POI; got '%s'"
			% str_field(c, "home_poi_id"))


## Calling stock_poi twice on the same POI should NOT double-stock —
## the second call detects the existing head_npc_character_id and skips.
func test_idempotent_does_not_double_stock() -> void:
	var poi_id := "stk_poi_idemp"
	_insert_poi(poi_id, "mages_guild_hall", 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900
	BaselineNpcStocker.stock_poi(poi_id, rng)
	BaselineNpcStocker.stock_poi(poi_id, rng)
	var characters := _list_characters_at_poi(poi_id)
	check(characters.size() == 1,
		"idempotent re-stock should leave 1 character row, not duplicate; got %d"
		% characters.size())


## Stocked NPCs at a religious_site should inherit alignment from the
## parent domain (v1 fallback when no religion roster exists).
func test_alignment_inherits_from_domain() -> void:
	var poi_id := "stk_poi_alignment"
	_insert_poi(poi_id, "religious_site", 1, "shrine", "", "lawful_silver_lady")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000
	var result := BaselineNpcStocker.stock_poi(poi_id, rng)
	var head_id := str_field(result, "head_character_id")
	if head_id.is_empty():
		check(false, "expected head NPC id")
		return
	var head := _get_character(head_id)
	# Domain alignment was 'lawful' in the fixture.
	check(str_field(head, "alignment") == "lawful",
		"stocked cleric alignment should match domain alignment 'lawful'; got '%s'"
		% str_field(head, "alignment"))
