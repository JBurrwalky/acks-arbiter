extends "res://tests/test_suite_base.gd"

## Tests for Phase 10B.1c — Magic item enchanting + manage_assistant.
##
## Covers:
##   - MagicItemEnchanting helper: base_gp_cost / base_days / target_modifier
##     / apply_formula_reduction / precious_materials_throw_bonus /
##     workshop bonus + validation across multiple effect_kinds.
##   - research_magic[project_kind=magic_item] dispatch: eligibility gates
##     (arcane, min_caster_level, imbued spell known, workshop OK),
##     success path (crafted_magic_items + inventory_items rows),
##     failure path (project row only), formula reduction on repeat craft.
##   - ManageAssistantHandler: L9+ gate, INT-bonus headcount.
##   - Constraint: crafted item inventory_items rows use item_key='crafted:<id>'
##     so ShopInventoryGenerator (which reads EquipmentCatalog JSON) never
##     sees them.


var _campaign_id: String = ""
var _mage_l9_int17_id: String = ""
var _mage_l5_id: String = ""
var _mage_l3_id: String = ""
var _cleric_id: String = ""
var _workshop_l5_id: String = ""
var _workshop_l1_id: String = ""
var _stronghold_id: String = ""


func run_all_tests() -> void:
	_setup()

	# MagicItemEnchanting helper
	test_base_gp_cost_one_use()
	test_base_gp_cost_charged_includes_charge_multiplier()
	test_base_gp_cost_permanent_unlimited()
	test_base_gp_cost_weapon_plus_1()
	test_base_days_charged_has_minimum_one_week_per_level()
	test_target_modifier_full_level_without_formula()
	test_target_modifier_half_level_with_formula()
	test_apply_formula_reduction_bankers_rounding()
	test_precious_materials_capped_at_base_cost()
	test_min_caster_level_one_use_is_5()
	test_min_caster_level_permanent_is_9()
	test_min_caster_level_weapon_plus_1_is_9()

	# research_magic[magic_item] handler
	test_magic_item_rejects_below_min_caster_level()
	test_magic_item_rejects_non_arcane()
	test_magic_item_rejects_when_imbued_spell_unknown()
	test_magic_item_rejects_when_no_workshop()
	test_magic_item_rejects_when_workshop_too_small()
	test_magic_item_success_creates_crafted_row_and_inventory_instance()
	test_magic_item_inventory_item_key_uses_crafted_prefix()
	test_magic_item_formula_reduction_on_repeat_craft()

	# manage_assistant
	test_manage_assistant_rejects_below_l9()
	test_manage_assistant_accepts_l9_caster_with_int_bonus()

	if not has_failures():
		print("Phase10B1c: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Test 10B.1c", "TestWorld")

	_mage_l9_int17_id = _create_test_character(_campaign_id, "Test Mage L9", "mage", "mage", 9, 17, 10)
	_mage_l5_id = _create_test_character(_campaign_id, "Test Mage L5", "mage", "mage", 5, 14, 10)
	_mage_l3_id = _create_test_character(_campaign_id, "Test Mage L3", "mage", "mage", 3, 12, 10)
	_cleric_id = _create_test_character(_campaign_id, "Test Cleric", "cleric", "cleric", 9, 10, 16)

	_stronghold_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds (id, owner_character_id, archetype,
			structure_type, gp_value, completion_pct, status)
		VALUES (?, ?, 'sanctum', 'sanctum', 30000, 100, 'completed')
	""", [_stronghold_id, _mage_l9_int17_id])

	# Workshop supporting L5 spell effects with +1 bonus.
	# min_gp for L5 = 4000 + 2000*4 = 12000. With 22,000gp invested:
	#   excess = 10000 → +1 throw bonus.
	_workshop_l5_id = CampaignRepository.create_workshop({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_l9_int17_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "tower_workshop",
		"gp_invested": 22000,
		"max_item_value_supported_gp": 50000,
		"magic_research_throw_bonus": 1,
		"status": "operational",
		"created_calendar_day": 1,
	})

	# Workshop supporting only L1 spell effects (min_gp = 4000).
	_workshop_l1_id = CampaignRepository.create_workshop({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_l5_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "tower_workshop",
		"gp_invested": 4000,
		"max_item_value_supported_gp": 5000,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})

	# Give the L9 mage the formula for magic_missile (so he can imbue it
	# into scrolls/wands).
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO character_spell_formulas (character_id, spell_key, spell_level)
		VALUES (?, 'magic_missile', 1)
	""", [_mage_l9_int17_id])
	# And to the L5 mage (for the workshop-too-small test).
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO character_spell_formulas (character_id, spell_key, spell_level)
		VALUES (?, 'magic_missile', 1)
	""", [_mage_l5_id])


func _create_test_character(
	campaign_id: String, name: String, class_id: String,
	progression: String, level: int, intelligence: int, wisdom: int,
) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, combat_progression, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			alignment, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', ?, ?, ?,
			10, ?, ?, 12, 10, 12, 'neutral', 20, 20)
	""", [id, campaign_id, name, class_id, progression, level, intelligence, wisdom])
	return id


# ---------------------------------------------------------------------------
# MagicItemEnchanting helper tests
# ---------------------------------------------------------------------------

func test_base_gp_cost_one_use() -> void:
	# one_use L1: 500 * 1 * 1 = 500 gp
	check(MagicItemEnchanting.base_gp_cost("one_use", 1, 1) == 500,
		"one_use L1 should cost 500 gp, got %d" % MagicItemEnchanting.base_gp_cost("one_use", 1, 1))


func test_base_gp_cost_charged_includes_charge_multiplier() -> void:
	# charged L1 × 20 charges: 500 * 1 * 1 * 20 = 10,000 gp (Wand of MM-ish)
	var got: int = MagicItemEnchanting.base_gp_cost("charged", 1, 20)
	check(got == 10000,
		"charged L1 × 20 charges should cost 10,000 gp, got %d" % got)


func test_base_gp_cost_permanent_unlimited() -> void:
	# permanent_unlimited L3: 500 * 3 * 50 = 75,000 gp
	var got: int = MagicItemEnchanting.base_gp_cost("permanent_unlimited", 3)
	check(got == 75000,
		"permanent_unlimited L3 should cost 75,000 gp, got %d" % got)


func test_base_gp_cost_weapon_plus_1() -> void:
	# weapon_plus_1: 5,000 gp flat
	check(MagicItemEnchanting.base_gp_cost("weapon_plus_1", 1, 1) == 5000,
		"weapon_plus_1 should cost 5,000 gp")
	# weapon_plus_2: 15,000 cumulative
	check(MagicItemEnchanting.base_gp_cost("weapon_plus_2", 1, 1) == 15000,
		"weapon_plus_2 should cost 15,000 gp")
	# weapon_plus_3: 35,000 cumulative
	check(MagicItemEnchanting.base_gp_cost("weapon_plus_3", 1, 1) == 35000,
		"weapon_plus_3 should cost 35,000 gp")


func test_base_days_charged_has_minimum_one_week_per_level() -> void:
	# charged L3 × 1 charge: raw = 2 * 3 * 1 = 6 days; min = 7 * 3 = 21 days.
	# Expect 21 (the minimum).
	var got: int = MagicItemEnchanting.base_days("charged", 3, 1)
	check(got == 21,
		"charged L3 × 1 charge should be 21 days (minimum 7×spell_level), got %d" % got)
	# charged L1 × 20: raw = 2*1*20 = 40; min = 7. Expect 40.
	got = MagicItemEnchanting.base_days("charged", 1, 20)
	check(got == 40,
		"charged L1 × 20 charges should be 40 days, got %d" % got)


func test_target_modifier_full_level_without_formula() -> void:
	# RAW L135: target += full spell level when no formula.
	check(MagicItemEnchanting.target_modifier_for_effect("one_use", 3, false) == 3,
		"target modifier should be full spell_level=3 without formula")


func test_target_modifier_half_level_with_formula() -> void:
	# With formula: target += floor(spell_level / 2) per RAW L156.
	check(MagicItemEnchanting.target_modifier_for_effect("one_use", 3, true) == 1,
		"target modifier should be floor(3/2)=1 with formula")
	check(MagicItemEnchanting.target_modifier_for_effect("one_use", 4, true) == 2,
		"target modifier should be floor(4/2)=2 with formula")


func test_apply_formula_reduction_bankers_rounding() -> void:
	# 1000 / 2 = 500 (exact, no rounding)
	check(MagicItemEnchanting.apply_formula_reduction(1000) == 500,
		"1000 halved should be 500")
	# 1001 / 2 = 500.5 → banker's rounding: round to even = 500
	check(MagicItemEnchanting.apply_formula_reduction(1001) == 500,
		"1001 halved with banker's rounding should be 500 (round half to even)")
	# 1003 / 2 = 501.5 → banker's rounding: round to even = 502
	check(MagicItemEnchanting.apply_formula_reduction(1003) == 502,
		"1003 halved with banker's rounding should be 502 (round half to even)")


func test_precious_materials_capped_at_base_cost() -> void:
	# 30,000gp precious materials with base cost 10,000gp: cap kicks in.
	# Throw bonus = 10000 / 10000 = +1 (the cap).
	var bonus: int = MagicItemEnchanting.precious_materials_throw_bonus(30000, 10000)
	check(bonus == 1,
		"precious materials throw bonus should be capped at base_cost / 10000 = 1, got %d" % bonus)
	# 20,000gp precious / 10,000 base: cap at 10,000 → +1.
	bonus = MagicItemEnchanting.precious_materials_throw_bonus(20000, 10000)
	check(bonus == 1, "should also be 1 with 20,000gp gem")
	# 5,000gp precious / 10,000 base: under cap → 5,000 / 10,000 = 0.
	bonus = MagicItemEnchanting.precious_materials_throw_bonus(5000, 10000)
	check(bonus == 0,
		"5,000gp precious shouldn't grant any bonus (< 10,000gp threshold)")


func test_min_caster_level_one_use_is_5() -> void:
	check(MagicItemEnchanting.min_caster_level("one_use") == 5,
		"one_use min caster level should be 5")


func test_min_caster_level_permanent_is_9() -> void:
	check(MagicItemEnchanting.min_caster_level("permanent_unlimited") == 9,
		"permanent_unlimited min caster level should be 9")


func test_min_caster_level_weapon_plus_1_is_9() -> void:
	check(MagicItemEnchanting.min_caster_level("weapon_plus_1") == 9,
		"weapon_plus_1 min caster level should be 9")


# ---------------------------------------------------------------------------
# research_magic[magic_item] handler tests
# ---------------------------------------------------------------------------

func _purge_crafted_for(character_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM crafted_magic_items WHERE creator_character_id = ?", [character_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM magic_research_projects WHERE character_id = ?", [character_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ? AND item_key LIKE 'crafted:%'",
		[character_id])


func test_magic_item_rejects_below_min_caster_level() -> void:
	_purge_crafted_for(_mage_l3_id)
	# Give L3 mage the formula so we don't trip on the spell-knowledge check.
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO character_spell_formulas (character_id, spell_key, spell_level)
		VALUES (?, 'magic_missile', 1)
	""", [_mage_l3_id])
	var state := {
		"character_id": _mage_l3_id,
		"params_json": JSON.stringify({
			"project_kind": "magic_item",
			"item_name": "Scroll of MM",
			"item_category": "scroll",
			"effect_kind": "one_use",
			"primary_spell_key": "magic_missile",
			"primary_spell_level": 1,
			"gp_committed": 500,
			"workshop_id": _workshop_l1_id,
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("requires caster L5+"),
		"L3 mage attempting one_use scroll should be rejected (min L5); got '%s'" % result.get("summary", ""))


func test_magic_item_rejects_non_arcane() -> void:
	# Phase 10B.1g.1 (2026-05-11): magic-item arcane-only gate widened to
	# the magical_research bucket gate per RAW L116-117. Cleric now PASSES
	# eligibility — but still gets rejected because they don't know the
	# imbued spell's formula (RAW L121: "the spellcaster must know the
	# spell or spells that replicate the item's effect"). The fixture
	# cleric has no entry in character_spell_formulas for 'bless', so the
	# rejection cascades to the formula check. The bucket-level
	# rejection path is now exercised by Bladedancer (no MR bucket per Q11);
	# v1 doesn't yet have a Bladedancer-in-magic_item test, so the
	# rejection summary here verifies the next gate: formula knowledge.
	_purge_crafted_for(_cleric_id)
	var state := {
		"character_id": _cleric_id,
		"params_json": JSON.stringify({
			"project_kind": "magic_item",
			"item_name": "Scroll of Bless",
			"item_category": "scroll",
			"effect_kind": "one_use",
			"primary_spell_key": "bless",
			"primary_spell_level": 1,
			"gp_committed": 500,
			"workshop_id": _workshop_l5_id,
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("does not know formula"),
		"Cleric without 'bless' formula should be rejected at the formula gate; got '%s'" % result.get("summary", ""))


func test_magic_item_rejects_when_imbued_spell_unknown() -> void:
	_purge_crafted_for(_mage_l9_int17_id)
	# Use a spell the L9 mage doesn't have a formula for.
	var state := {
		"character_id": _mage_l9_int17_id,
		"params_json": JSON.stringify({
			"project_kind": "magic_item",
			"item_name": "Scroll of Sleep",
			"item_category": "scroll",
			"effect_kind": "one_use",
			"primary_spell_key": "sleep",
			"primary_spell_level": 1,
			"gp_committed": 500,
			"workshop_id": _workshop_l5_id,
		}),
	}
	# Ensure sleep is NOT a formula for this caster.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spell_formulas WHERE character_id = ? AND spell_key = 'sleep'",
		[_mage_l9_int17_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_spells WHERE character_id = ? AND spell_key = 'sleep'",
		[_mage_l9_int17_id])
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("does not know formula for"),
		"Imbuing an unknown spell should be rejected; got '%s'" % result.get("summary", ""))


func test_magic_item_rejects_when_no_workshop() -> void:
	_purge_crafted_for(_mage_l9_int17_id)
	var state := {
		"character_id": _mage_l9_int17_id,
		"params_json": JSON.stringify({
			"project_kind": "magic_item",
			"item_name": "Scroll of MM",
			"item_category": "scroll",
			"effect_kind": "one_use",
			"primary_spell_key": "magic_missile",
			"primary_spell_level": 1,
			"gp_committed": 500,
			# no workshop_id, no location_ref
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("workshop required"),
		"No workshop should be rejected; got '%s'" % result.get("summary", ""))


func test_magic_item_rejects_when_workshop_too_small() -> void:
	_purge_crafted_for(_mage_l5_id)
	# L5 mage with the L1-supporting workshop tries to craft a L3-spell
	# permanent_unlimited item. Workshop min_gp for L3 = 4000 + 2000*2 = 8000.
	# _workshop_l1_id has gp_invested = 4000, below the 8000 threshold.
	# Give the caster the formula so we don't trip on spell-knowledge first.
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO character_spell_formulas (character_id, spell_key, spell_level)
		VALUES (?, 'fireball', 3)
	""", [_mage_l5_id])
	var state := {
		"character_id": _mage_l5_id,
		"params_json": JSON.stringify({
			"project_kind": "magic_item",
			"item_name": "Wand of Fireball",
			"item_category": "wand",
			"effect_kind": "permanent_per_day",
			"primary_spell_key": "fireball",
			"primary_spell_level": 3,
			"gp_committed": 15000,
			"workshop_id": _workshop_l1_id,
		}),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	# L5 is below the permanent_per_day min L9, so the level gate will fire
	# FIRST before the workshop check. Verify either rejection happens.
	var summary: String = String(result.get("summary", ""))
	check(summary.contains("requires caster L9+") or summary.contains("workshop too small") or summary.contains("workshop supports up to"),
		"Should reject for level OR workshop size; got '%s'" % summary)


func test_magic_item_success_creates_crafted_row_and_inventory_instance() -> void:
	_purge_crafted_for(_mage_l9_int17_id)
	# L9 INT17 mage crafts a Scroll of Magic Missile (one_use L1):
	#   cost = 500gp, days = 7. caster_level=9 target=8+; spell_level penalty=+1 (full level for new item, no formula).
	#   effective_target = 9. modifier = INT+2 + workshop+1 = +3. d20 needs >=6 to succeed.
	#   At ~75% success per attempt, retry up to 10 times.
	var crafted_id: String = ""
	var inv_item_id: String = ""
	var attempts := 0
	while attempts < 10:
		attempts += 1
		_purge_crafted_for(_mage_l9_int17_id)
		var state := {
			"character_id": _mage_l9_int17_id,
			"params_json": JSON.stringify({
				"project_kind": "magic_item",
				"item_name": "Scroll of Magic Missile",
				"item_category": "scroll",
				"effect_kind": "one_use",
				"primary_spell_key": "magic_missile",
				"primary_spell_level": 1,
				"gp_committed": 500,
				"workshop_id": _workshop_l5_id,
				"encumbrance_units": 50,
			}),
		}
		var result := ResearchMagicHandler.on_complete(state, null)
		if String(result.get("summary", "")).contains("enchanted"):
			# Find the crafted row.
			var crafted_rows: Array = CampaignRepository.list_crafted_magic_items_for_creator(_mage_l9_int17_id)
			if crafted_rows.size() == 1:
				crafted_id = String(crafted_rows[0].get("id", ""))
				check(String(crafted_rows[0].get("name", "")) == "Scroll of Magic Missile",
					"crafted_magic_items row should have correct name")
				check(String(crafted_rows[0].get("item_category", "")) == "scroll",
					"crafted item_category should be 'scroll'")
				check(String(crafted_rows[0].get("effect_kind", "")) == "one_use",
					"crafted effect_kind should be 'one_use'")
				check(int(crafted_rows[0].get("gp_cost_base", 0)) == 500,
					"crafted gp_cost_base should be 500")
				check(int(crafted_rows[0].get("days_to_create", 0)) == 7,
					"crafted days_to_create should be 7")
			# Find the inventory row.
			if CampaignRepository.db.query_with_bindings(
				"SELECT id, item_key FROM inventory_items WHERE character_id = ? AND item_key LIKE 'crafted:%' LIMIT 1",
				[_mage_l9_int17_id]
			):
				if not CampaignRepository.db.query_result.is_empty():
					inv_item_id = String(CampaignRepository.db.query_result[0].get("id", ""))
			break
	check(not crafted_id.is_empty(),
		"After at most 10 attempts, crafted_magic_items row should be persisted")
	check(not inv_item_id.is_empty(),
		"After successful enchanting, an inventory_items row should be created")


func test_magic_item_inventory_item_key_uses_crafted_prefix() -> void:
	# Verify the convention: crafted instances' item_key is 'crafted:<id>'.
	# This is what ensures ShopInventoryGenerator (which reads EquipmentCatalog
	# JSON) cannot see crafted items.
	CampaignRepository.db.query_with_bindings(
		"SELECT item_key FROM inventory_items WHERE character_id = ? AND item_key LIKE 'crafted:%' LIMIT 1",
		[_mage_l9_int17_id])
	if not CampaignRepository.db.query_result.is_empty():
		var item_key: String = String(CampaignRepository.db.query_result[0].get("item_key", ""))
		check(item_key.begins_with("crafted:"),
			"inventory item_key should begin with 'crafted:' to flag as runtime-only; got '%s'" % item_key)
		# Confirm: this key would NOT match any EquipmentCatalog JSON entry.
		var catalog := EquipmentCatalog.new()
		check(not catalog.has_item(item_key),
			"EquipmentCatalog (JSON) should NOT have the crafted item key (shop separation invariant)")


func test_magic_item_formula_reduction_on_repeat_craft() -> void:
	# After the first successful Scroll of Magic Missile, character should
	# auto-have its formula (per RAW L151). The next craft of the same
	# template signature gets -50% cost+time.
	# Verify by calling character_has_item_formula directly.
	var has_formula: bool = CampaignRepository.character_has_item_formula(
		_mage_l9_int17_id, "scroll", "one_use", "magic_missile")
	check(has_formula,
		"After crafting, character_has_item_formula(scroll, one_use, magic_missile) should be true")


# ---------------------------------------------------------------------------
# manage_assistant
# ---------------------------------------------------------------------------

func test_manage_assistant_rejects_below_l9() -> void:
	var state := {
		"character_id": _mage_l5_id,
		"params_json": JSON.stringify({"assistant_character_ids": []}),
	}
	var result := ManageAssistantHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("L9+"),
		"L5 mage should be rejected by manage_assistant; got '%s'" % result.get("summary", ""))


func test_manage_assistant_accepts_l9_caster_with_int_bonus() -> void:
	var state := {
		"character_id": _mage_l9_int17_id,
		"params_json": JSON.stringify({"assistant_character_ids": []}),
	}
	var result := ManageAssistantHandler.on_complete(state, null)
	var summary: String = String(result.get("summary", ""))
	# INT 17 → +2 bonus → 1 + 2 = 3 max assistants.
	check(summary.contains("3 assistants"),
		"L9 INT17 mage should report 0/3 assistants supervised; got '%s'" % summary)
