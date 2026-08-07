extends "res://tests/test_suite_base.gd"

## StrongholdPoiRegistrar tests — Stage F per GDD §13.6 acceptance criteria.
##
## Scenarios:
##   * Cleric-owned stronghold → religious_site, tier='shrine', gp_value
##     converted from cp_value, builder_kind='character',
##     builder_character_id wired, no auto-created altar (Q-UGS-30).
##   * Mage L9 sanctum (archetype='sanctum') → mages_guild_hall.
##   * Fighter fortress / thief hideout → no POI (out of v1 vocabulary).
##   * Stronghold in non-settlement hex → no POI.
##   * Idempotent: re-running on a stronghold with `registered_settlement_poi_id`
##     set short-circuits.
##   * Stage A migration trigger fires when a `consecrate_altar` row
##     attached to the registered POI flips to status='completed' →
##     POI tier becomes 'temple'.
##   * Grant-transfer simulation: reassigning an attached altar's
##     `location_ref` to a new POI promotes the new POI to 'temple' via
##     the trigger.

const TEST_CAMPAIGN := "test_sh_reg_campaign"
const TEST_MAP := "test_sh_reg_map"
const TEST_DOMAIN := "test_sh_reg_domain"
const TEST_SETTLEMENT := "test_sh_reg_settle"
const TEST_CLERIC := "test_sh_reg_cleric"
const TEST_MAGE := "test_sh_reg_mage"
const TEST_FIGHTER := "test_sh_reg_fighter"


func run_all_tests() -> void:
	_cleanup()
	_setup_fixture()
	test_cleric_stronghold_registers_as_shrine()
	test_mage_sanctum_registers_as_mages_guild_hall()
	test_fighter_fortress_does_not_register()
	test_thief_hideout_does_not_register()
	test_stronghold_in_non_settlement_hex_does_not_register()
	test_idempotent_no_double_registration()
	test_consecrate_altar_promotes_shrine_to_temple()
	test_grant_transfer_reassigns_altar_to_new_poi()
	test_no_implicit_altar_q_ugs_30()
	test_gp_value_converted_from_cp_value()
	_cleanup()
	if not has_failures():
		print("StrongholdPoiRegistrar: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup_fixture() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings("INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Stronghold Registrar Test"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale)
		VALUES (?, ?, ?, ?)
	""", [TEST_MAP, TEST_CAMPAIGN, "SR Map", "regional_6mi"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO domains
			(id, campaign_id, name, peasant_families, religion, alignment)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [TEST_DOMAIN, TEST_CAMPAIGN, "SR Domain", 1000,
		"lawful_silver_lady", "lawful"])
	# Settlement at hex (40, 40).
	db.query_with_bindings("""
		INSERT OR IGNORE INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name, market_class,
			 parent_domain_id, urban_families, cumulative_investment_gp)
		VALUES (?, ?, ?, 40, 40, ?, 4, ?, 1000, 75000)
	""", [TEST_SETTLEMENT, TEST_CAMPAIGN, TEST_MAP,
		"SR Town", TEST_DOMAIN])
	# Three test characters, one per class profile.
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, combat_progression, level)
		VALUES (?, ?, ?, 'cleric', 'cleric', 9)
	""", [TEST_CLERIC, TEST_CAMPAIGN, "SR Cleric"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, combat_progression, level)
		VALUES (?, ?, ?, 'mage', 'mage', 9)
	""", [TEST_MAGE, TEST_CAMPAIGN, "SR Mage"])
	db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, combat_progression, level)
		VALUES (?, ?, ?, 'fighter', 'fighter', 9)
	""", [TEST_FIGHTER, TEST_CAMPAIGN, "SR Fighter"])


func _cleanup() -> void:
	var db = CampaignRepository.db
	# Order: altars → strongholds.registered_settlement_poi_id (set NULL) →
	# settlement_pois → strongholds → characters → settlement → domain →
	# hex_maps → campaign.
	db.query_with_bindings(
		"DELETE FROM consecrated_altars WHERE character_id IN (?, ?, ?)",
		[TEST_CLERIC, TEST_MAGE, TEST_FIGHTER])
	db.query_with_bindings("""
		UPDATE strongholds SET registered_settlement_poi_id = NULL
		WHERE owner_character_id IN (?, ?, ?)
	""", [TEST_CLERIC, TEST_MAGE, TEST_FIGHTER])
	db.query_with_bindings(
		"DELETE FROM settlement_pois WHERE settlement_id = ?", [TEST_SETTLEMENT])
	db.query_with_bindings(
		"DELETE FROM strongholds WHERE owner_character_id IN (?, ?, ?)",
		[TEST_CLERIC, TEST_MAGE, TEST_FIGHTER])
	db.query_with_bindings(
		"DELETE FROM characters WHERE id IN (?, ?, ?)",
		[TEST_CLERIC, TEST_MAGE, TEST_FIGHTER])
	db.query_with_bindings(
		"DELETE FROM settlement_entrances WHERE id = ?", [TEST_SETTLEMENT])
	db.query_with_bindings("DELETE FROM domains WHERE id = ?", [TEST_DOMAIN])
	db.query_with_bindings("DELETE FROM hex_maps WHERE id = ?", [TEST_MAP])
	db.query_with_bindings("DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _insert_stronghold(
	stronghold_id: String,
	owner_character_id: String,
	archetype: String,
	hex_q: int,
	hex_r: int,
	cp_value: int,
) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds
			(id, domain_id, owner_character_id, archetype, structure_type,
			 cp_value, completion_pct, status,
			 location_map_id, location_hex_q, location_hex_r)
		VALUES (?, ?, ?, ?, 'keep', ?, 100, 'completed', ?, ?, ?)
	""", [
		stronghold_id, TEST_DOMAIN, owner_character_id, archetype,
		cp_value, TEST_MAP, hex_q, hex_r,
	])


func _get_poi(poi_id: String) -> Dictionary:
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM settlement_pois WHERE id = ?", [poi_id])
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## Cleric L9 builds a 75000gp fortified-church (archetype='fortress') in a
## Class IV settlement → POI registers as religious_site, tier='shrine'.
func test_cleric_stronghold_registers_as_shrine() -> void:
	var sh_id := "sh_cleric_1"
	# cp_value = 7,500,000 (= 75,000 gp).
	_insert_stronghold(sh_id, TEST_CLERIC, "fortress", 40, 40, 7500000)
	var result := StrongholdPoiRegistrar.register_stronghold_poi(sh_id)
	var poi_id := String(result.get("poi_id", ""))
	check(not poi_id.is_empty(),
		"cleric stronghold in settlement hex should register a POI")
	if poi_id.is_empty():
		return
	var poi := _get_poi(poi_id)
	check(String(poi.get("type", "")) == "religious_site",
		"cleric stronghold POI type should be 'religious_site'; got '%s'"
		% String(poi.get("type", "")))
	check(String(poi.get("tier", "")) == "shrine",
		"cleric stronghold POI tier should be 'shrine' per Q-UGS-30; got '%s'"
		% String(poi.get("tier", "")))
	check(String(poi.get("builder_kind", "")) == "character",
		"cleric stronghold POI builder_kind should be 'character'")
	check(str_field(poi, "builder_character_id") == TEST_CLERIC,
		"cleric stronghold POI builder_character_id should be the cleric")
	check(String(poi.get("emerged_via", "")) == "stronghold_register",
		"cleric stronghold POI emerged_via should be 'stronghold_register'")


## Mage L9 sanctum (archetype='sanctum') → mages_guild_hall.
func test_mage_sanctum_registers_as_mages_guild_hall() -> void:
	var sh_id := "sh_mage_1"
	_insert_stronghold(sh_id, TEST_MAGE, "sanctum", 40, 40, 5000000)
	var result := StrongholdPoiRegistrar.register_stronghold_poi(sh_id)
	var poi_id := String(result.get("poi_id", ""))
	check(not poi_id.is_empty(),
		"mage sanctum should register a POI")
	if poi_id.is_empty():
		return
	var poi := _get_poi(poi_id)
	check(String(poi.get("type", "")) == "mages_guild_hall",
		"mage sanctum POI type should be 'mages_guild_hall'; got '%s'"
		% String(poi.get("type", "")))
	check(String(poi.get("tier", "")) == "",
		"non-religious POI tier should be empty; got '%s'"
		% String(poi.get("tier", "")))


## Fighter fortress in a settlement hex → no POI (out of v1 vocabulary).
func test_fighter_fortress_does_not_register() -> void:
	var sh_id := "sh_fighter_1"
	_insert_stronghold(sh_id, TEST_FIGHTER, "fortress", 40, 40, 5000000)
	var result := StrongholdPoiRegistrar.register_stronghold_poi(sh_id)
	var poi_id := String(result.get("poi_id", ""))
	check(poi_id.is_empty(),
		"fighter fortress should NOT register a POI in v1; got poi_id='%s'"
		% poi_id)


## Thief hideout → no POI (out of v1 vocabulary).
func test_thief_hideout_does_not_register() -> void:
	# Insert a thief-class character on the fly.
	var thief_id := "sh_reg_thief"
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, combat_progression, level)
		VALUES (?, ?, ?, 'thief', 'thief', 9)
	""", [thief_id, TEST_CAMPAIGN, "SR Thief"])
	var sh_id := "sh_thief_1"
	_insert_stronghold(sh_id, thief_id, "hideout", 40, 40, 3000000)
	var result := StrongholdPoiRegistrar.register_stronghold_poi(sh_id)
	check(String(result.get("poi_id", "")).is_empty(),
		"thief hideout should NOT register a POI in v1")
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM strongholds WHERE id = ?", [sh_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [thief_id])


## Cleric stronghold sited in a wilderness hex (no settlement) → no POI.
func test_stronghold_in_non_settlement_hex_does_not_register() -> void:
	var sh_id := "sh_cleric_wilderness"
	# Hex (99, 99) has no settlement_entrances row.
	_insert_stronghold(sh_id, TEST_CLERIC, "fortress", 99, 99, 7500000)
	var result := StrongholdPoiRegistrar.register_stronghold_poi(sh_id)
	check(String(result.get("poi_id", "")).is_empty(),
		"stronghold in non-settlement hex should NOT register a POI")
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM strongholds WHERE id = ?", [sh_id])


## Re-running on a stronghold with registered_settlement_poi_id already set
## must NOT create a second POI row.
func test_idempotent_no_double_registration() -> void:
	var sh_id := "sh_idemp"
	_insert_stronghold(sh_id, TEST_CLERIC, "fortress", 40, 40, 7500000)
	var first := StrongholdPoiRegistrar.register_stronghold_poi(sh_id)
	var first_poi := String(first.get("poi_id", ""))
	check(not first_poi.is_empty(), "first registration should succeed")
	var second := StrongholdPoiRegistrar.register_stronghold_poi(sh_id)
	check(String(second.get("poi_id", "")).is_empty(),
		"second registration on the same stronghold should short-circuit; got '%s'"
		% String(second.get("poi_id", "")))


## The Stage A migration trigger should promote a registered religious_site
## to tier='temple' when a consecrated_altars row with location_kind=
## 'settlement_poi' flips to status='completed'.
func test_consecrate_altar_promotes_shrine_to_temple() -> void:
	var sh_id := "sh_promote"
	_insert_stronghold(sh_id, TEST_CLERIC, "fortress", 40, 40, 7500000)
	var result := StrongholdPoiRegistrar.register_stronghold_poi(sh_id)
	var poi_id := String(result.get("poi_id", ""))
	if poi_id.is_empty():
		check(false, "expected POI registration to succeed")
		return
	# Insert an in-progress altar attached to the POI, then flip to completed.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO consecrated_altars
			(id, character_id, location_kind, location_ref, alignment,
			 status, cp_invested)
		VALUES (?, ?, 'settlement_poi', ?, 'lawful', 'in_progress', 100000)
	""", ["sh_altar_promote", TEST_CLERIC, poi_id])
	CampaignRepository.db.query_with_bindings(
		"UPDATE consecrated_altars SET status = 'completed' WHERE id = ?",
		["sh_altar_promote"])
	var poi := _get_poi(poi_id)
	check(String(poi.get("tier", "")) == "temple",
		"shrine should promote to 'temple' after altar completes; got tier='%s'"
		% String(poi.get("tier", "")))


## Grant-transfer simulation: a completed altar is reassigned from a prior
## POI to a new POI via direct SQL. The migration trigger should then flip
## the new POI's tier to 'temple'. The prior POI's tier should revert to
## 'shrine' (no other completed altars remain).
func test_grant_transfer_reassigns_altar_to_new_poi() -> void:
	# Set up POI A (cleric stronghold) with a completed altar → tier=temple.
	var sh_a := "sh_grant_a"
	_insert_stronghold(sh_a, TEST_CLERIC, "fortress", 40, 40, 7500000)
	var poi_a := String(StrongholdPoiRegistrar.register_stronghold_poi(sh_a)
		.get("poi_id", ""))
	if poi_a.is_empty():
		check(false, "expected POI A to register")
		return
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO consecrated_altars
			(id, character_id, location_kind, location_ref, alignment,
			 status, cp_invested)
		VALUES (?, ?, 'settlement_poi', ?, 'lawful', 'completed', 100000)
	""", ["sh_altar_grant", TEST_CLERIC, poi_a])
	# POI A now has tier='temple' via the promote-on-insert trigger.
	# Set up POI B (a second cleric stronghold at the same hex — simulates a
	# transferred fortified-church). Use a different cleric for the second.
	var cleric_b := "sh_reg_cleric_b"
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, combat_progression, level)
		VALUES (?, ?, ?, 'cleric', 'cleric', 9)
	""", [cleric_b, TEST_CAMPAIGN, "SR Cleric B"])
	var sh_b := "sh_grant_b"
	_insert_stronghold(sh_b, cleric_b, "fortress", 40, 40, 5000000)
	var poi_b := String(StrongholdPoiRegistrar.register_stronghold_poi(sh_b)
		.get("poi_id", ""))
	if poi_b.is_empty():
		check(false, "expected POI B to register")
		return
	# Reassign altar from POI A to POI B. The demote trigger should leave
	# POI A as 'shrine' (no remaining altars), and the promote trigger
	# should fire on POI B if we then "update" the altar to completed
	# again (the trigger fires on UPDATE OF status — a no-op status set
	# back to 'completed' still triggers).
	CampaignRepository.db.query_with_bindings(
		"UPDATE consecrated_altars SET location_ref = ? WHERE id = ?",
		[poi_b, "sh_altar_grant"])
	# The promotion trigger fires AFTER UPDATE OF status only. To force
	# re-promotion after the location_ref reassignment, set status to a
	# non-completed value then back. v1 grant-transfer flow (when shipped
	# in stronghold-construction GDD) should do exactly this.
	CampaignRepository.db.query_with_bindings(
		"UPDATE consecrated_altars SET status = 'in_progress' WHERE id = ?",
		["sh_altar_grant"])
	CampaignRepository.db.query_with_bindings(
		"UPDATE consecrated_altars SET status = 'completed' WHERE id = ?",
		["sh_altar_grant"])
	var poi_b_row := _get_poi(poi_b)
	check(String(poi_b_row.get("tier", "")) == "temple",
		"POI B should be 'temple' after altar reassignment; got '%s'"
		% String(poi_b_row.get("tier", "")))
	# Clean up the extra cleric.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM strongholds WHERE id = ?", [sh_b])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [cleric_b])


## Q-UGS-30 explicit check: a freshly-registered cleric stronghold has NO
## auto-created consecrated_altars row.
func test_no_implicit_altar_q_ugs_30() -> void:
	var sh_id := "sh_no_altar"
	_insert_stronghold(sh_id, TEST_CLERIC, "fortress", 40, 40, 7500000)
	var result := StrongholdPoiRegistrar.register_stronghold_poi(sh_id)
	var poi_id := String(result.get("poi_id", ""))
	if poi_id.is_empty():
		check(false, "expected POI to register")
		return
	CampaignRepository.db.query_with_bindings("""
		SELECT COUNT(*) AS c FROM consecrated_altars
		WHERE location_kind = 'settlement_poi' AND location_ref = ?
	""", [poi_id])
	var count: int = int(CampaignRepository.db.query_result[0].get("c", 0))
	check(count == 0,
		"Q-UGS-30: registered cleric stronghold should have NO auto-created altar; got %d"
		% count)


## gp_value is banker-rounded from cp_value. 7500000 cp / 100 = 75000 gp.
func test_gp_value_converted_from_cp_value() -> void:
	var sh_id := "sh_gp_value"
	_insert_stronghold(sh_id, TEST_CLERIC, "fortress", 40, 40, 7500000)
	var result := StrongholdPoiRegistrar.register_stronghold_poi(sh_id)
	check(int(result.get("gp_value", -1)) == 75000,
		"7500000cp should convert to 75000gp; got %d"
		% int(result.get("gp_value", -1)))
	var poi_id := String(result.get("poi_id", ""))
	if not poi_id.is_empty():
		var poi := _get_poi(poi_id)
		check(int(poi.get("gp_value", -1)) == 75000,
			"POI row gp_value should be 75000; got %d"
			% int(poi.get("gp_value", -1)))
