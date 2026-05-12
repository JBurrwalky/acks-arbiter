extends "res://tests/test_suite_base.gd"

## Tests for Phase 10B.1e — Construct creation.
##
## Covers:
##   - MagicalResearchConstruct helper: cost / time / target modifier /
##     HD cap / default AC / damage-per-round cap / banker's-rounded
##     default HP.
##   - research_magic[project_kind=construct] dispatch:
##     - eligibility (L11+ arcane/divine; L9+ Dwarven Craftpriest;
##       below-min-level rejected)
##     - HD cap (>2×level rejected)
##     - attack/damage limits (>4 attacks rejected; max_damage > 3×HD rejected)
##     - workshop required + worth >= construct cost
##     - success path creates construct_designs + construct_instances rows
##     - design dedupe: re-crafting the same signature reuses the design


var _campaign_id: String = ""
var _mage_l11_id: String = ""
var _mage_l5_id: String = ""
var _craftpriest_l9_id: String = ""
var _fighter_l11_id: String = ""
var _workshop_big_id: String = ""
var _workshop_small_id: String = ""
var _stronghold_id: String = ""


func run_all_tests() -> void:
	_setup()

	# MagicalResearchConstruct helper
	test_base_gp_cost_1_hd_no_abilities()
	test_base_gp_cost_includes_special_abilities()
	test_base_days_formula()
	test_target_modifier_per_5000_gp()
	test_max_hd_for_caster_level()
	test_validate_hd_rejects_over_cap()
	test_default_armor_class_is_half_hd()
	test_max_damage_per_round_cap()
	test_default_hp_max_bankers_rounded()

	# research_magic[construct] dispatch
	test_construct_rejects_l10_arcane()
	test_construct_rejects_l8_craftpriest()
	test_construct_accepts_l9_craftpriest()
	test_construct_rejects_fighter()
	test_construct_rejects_hd_over_2x_caster_level()
	test_construct_rejects_too_many_attacks()
	test_construct_rejects_damage_over_3x_hd()
	test_construct_rejects_no_workshop()
	test_construct_rejects_workshop_too_small()
	test_construct_success_creates_design_and_instance()
	test_construct_repeat_dedupes_design()

	if not has_failures():
		print("Phase10B1e: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Test 10B.1e", "TestWorld")

	_mage_l11_id = _create_test_character(_campaign_id, "Test Mage L11", "mage", "mage", 11, 17, 10)
	_mage_l5_id = _create_test_character(_campaign_id, "Test Mage L5", "mage", "mage", 5, 14, 10)
	_craftpriest_l9_id = _create_test_character(_campaign_id, "Test Craftpriest L9",
		"dwarven_craftpriest", "cleric", 9, 12, 16)
	_fighter_l11_id = _create_test_character(_campaign_id, "Test Fighter L11", "fighter", "fighter", 11, 10, 10)

	_stronghold_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds (id, owner_character_id, archetype,
			structure_type, gp_value, completion_pct, status)
		VALUES (?, ?, 'sanctum', 'sanctum', 50000, 100, 'completed')
	""", [_stronghold_id, _mage_l11_id])

	# Large workshop (50,000 gp invested) — supports up to a 50,000gp
	# construct. With 50,000gp construct cost: excess = 0, bonus = 0.
	# With smaller constructs: excess up to (50,000 - cost) bonus up to +3.
	_workshop_big_id = CampaignRepository.create_workshop({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_l11_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "tower_workshop",
		"gp_invested": 50000,
		"max_item_value_supported_gp": 100000,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})

	# Small workshop (2,000 gp) — won't support a typical construct cost.
	_workshop_small_id = CampaignRepository.create_workshop({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_l11_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "tower_workshop",
		"gp_invested": 2000,
		"max_item_value_supported_gp": 3000,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})


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
			10, ?, ?, 12, 10, 12, 'neutral', 24, 24)
	""", [id, campaign_id, name, class_id, progression, level, intelligence, wisdom])
	return id


# ---------------------------------------------------------------------------
# MagicalResearchConstruct helper tests
# ---------------------------------------------------------------------------

func test_base_gp_cost_1_hd_no_abilities() -> void:
	# RAW: 2,000gp/HD + 5,000gp/ability. 1 HD, 0 abilities = 2,000gp.
	check(MagicalResearchConstruct.base_gp_cost(1, 0) == 2000,
		"1 HD construct should cost 2,000 gp")


func test_base_gp_cost_includes_special_abilities() -> void:
	# 4 HD + 2 abilities: 2000*4 + 5000*2 = 18,000.
	check(MagicalResearchConstruct.base_gp_cost(4, 2) == 18000,
		"4 HD + 2 abilities should cost 18,000 gp, got %d" % MagicalResearchConstruct.base_gp_cost(4, 2))


func test_base_days_formula() -> void:
	# 8,000gp cost: 7 days + ceil(8000/1000) = 7 + 8 = 15 days.
	var got: int = MagicalResearchConstruct.base_days(8000)
	check(got == 15, "8,000gp construct should take 15 days, got %d" % got)
	# 500gp cost: 7 + ceil(500/1000)=1 = 8 days.
	got = MagicalResearchConstruct.base_days(500)
	check(got == 8, "500gp should take 8 days (7 + ceil(500/1000))")


func test_target_modifier_per_5000_gp() -> void:
	check(MagicalResearchConstruct.target_modifier_for_cost(5000) == 1,
		"5,000gp construct should have +1 target modifier")
	check(MagicalResearchConstruct.target_modifier_for_cost(14999) == 2,
		"14,999gp construct should have +2 target modifier")
	check(MagicalResearchConstruct.target_modifier_for_cost(15000) == 3,
		"15,000gp construct should have +3 target modifier")


func test_max_hd_for_caster_level() -> void:
	check(MagicalResearchConstruct.max_hd_for_caster_level(11) == 22,
		"L11 caster max HD should be 22 (2×11)")
	check(MagicalResearchConstruct.max_hd_for_caster_level(9) == 18,
		"L9 caster max HD should be 18 (2×9)")


func test_validate_hd_rejects_over_cap() -> void:
	var err: String = MagicalResearchConstruct.validate_hd(25, 11)
	check(not err.is_empty() and err.contains("exceeds"),
		"HD 25 for L11 caster (cap 22) should be rejected; got '%s'" % err)
	err = MagicalResearchConstruct.validate_hd(22, 11)
	check(err.is_empty(),
		"HD 22 exactly at cap should pass; got '%s'" % err)
	err = MagicalResearchConstruct.validate_hd(0, 11)
	check(err.contains("at least 1 HD"),
		"HD 0 should be rejected as below minimum")


func test_default_armor_class_is_half_hd() -> void:
	check(MagicalResearchConstruct.default_armor_class(6) == 3,
		"6 HD default AC should be 3 (floor(HD/2))")
	check(MagicalResearchConstruct.default_armor_class(7) == 3,
		"7 HD default AC should be 3 (floor(7/2))")
	check(MagicalResearchConstruct.default_armor_class(1) == 0,
		"1 HD default AC should be 0 (floor(1/2))")


func test_max_damage_per_round_cap() -> void:
	check(MagicalResearchConstruct.max_damage_per_round_cap(4) == 12,
		"max damage cap for 4 HD = 3×4 = 12")
	var err: String = MagicalResearchConstruct.validate_attacks_and_damage(2, 15, 4)
	check(err.contains("exceeds 3"),
		"max damage 15 for 4 HD (cap 12) should be rejected")
	err = MagicalResearchConstruct.validate_attacks_and_damage(5, 6, 4)
	check(err.contains("1-4 attacks"),
		"5 attacks per round should be rejected (RAW: 1-4)")


func test_default_hp_max_bankers_rounded() -> void:
	# HD 1: 4.5 → 4 (round half to even)
	check(MagicalResearchConstruct.default_hp_max(1) == 4,
		"1 HD default HP should be 4 (banker's-rounded 4.5)")
	# HD 2: 9 (exact)
	check(MagicalResearchConstruct.default_hp_max(2) == 9,
		"2 HD default HP should be 9 (exact 9.0)")
	# HD 3: 13.5 → 14 (round to even)
	check(MagicalResearchConstruct.default_hp_max(3) == 14,
		"3 HD default HP should be 14 (banker's 13.5 → 14)")
	# HD 4: 18 (exact)
	check(MagicalResearchConstruct.default_hp_max(4) == 18,
		"4 HD default HP should be 18")


# ---------------------------------------------------------------------------
# research_magic[construct] dispatch tests
# ---------------------------------------------------------------------------

func _purge_constructs_for(character_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM construct_instances WHERE creator_character_id = ?", [character_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM construct_designs WHERE creator_character_id = ?", [character_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM magic_research_projects WHERE character_id = ?", [character_id])


func _construct_params(hit_dice: int = 2, abilities: Array = []) -> Dictionary:
	var cost: int = MagicalResearchConstruct.base_gp_cost(hit_dice, abilities.size())
	return {
		"project_kind": "construct",
		"name": "Iron Sentinel",
		"hit_dice": hit_dice,
		"attacks_per_round": 1,
		"max_damage_per_round": 6,
		"damage_expression": "1d6",
		"special_abilities": abilities,
		"armor_class": 1,
		"gp_committed": cost,
		"workshop_id": _workshop_big_id,
		"location_kind": "stronghold",
		"location_ref": "stronghold:" + _stronghold_id,
	}


func test_construct_rejects_l10_arcane() -> void:
	# Modify the L11 mage temporarily by creating an L10 mage.
	var mage_l10_id := _create_test_character(_campaign_id, "Test Mage L10", "mage", "mage", 10, 14, 10)
	var state := {
		"character_id": mage_l10_id,
		"params_json": JSON.stringify(_construct_params()),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("must be L11+"),
		"L10 mage should be rejected (arcane needs L11+); got '%s'" % result.get("summary", ""))


func test_construct_rejects_l8_craftpriest() -> void:
	var craftpriest_l8_id := _create_test_character(_campaign_id, "Test Craftpriest L8",
		"dwarven_craftpriest", "cleric", 8, 12, 14)
	var state := {
		"character_id": craftpriest_l8_id,
		"params_json": JSON.stringify(_construct_params()),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("must be L9+"),
		"L8 Dwarven Craftpriest should be rejected (needs L9+); got '%s'" % result.get("summary", ""))


func test_construct_accepts_l9_craftpriest() -> void:
	# L9 craftpriest should pass the eligibility gate (whatever the throw
	# result). Move on past the level gate.
	_purge_constructs_for(_craftpriest_l9_id)
	# Give the craftpriest a workshop.
	var craftpriest_workshop := CampaignRepository.create_workshop({
		"campaign_id": _campaign_id,
		"owner_character_id": _craftpriest_l9_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "tower_workshop",
		"gp_invested": 10000,
		"max_item_value_supported_gp": 20000,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})
	var params := _construct_params(2, [])
	params["workshop_id"] = craftpriest_workshop
	var state := {
		"character_id": _craftpriest_l9_id,
		"params_json": JSON.stringify(params),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	# Whatever the throw outcome, the summary should NOT contain the level
	# rejection. It will say either "built" or "failed" (post-throw).
	var summary: String = String(result.get("summary", ""))
	check(not summary.contains("must be L"),
		"L9 Dwarven Craftpriest should pass eligibility gates; got '%s'" % summary)


func test_construct_rejects_fighter() -> void:
	var state := {
		"character_id": _fighter_l11_id,
		"params_json": JSON.stringify(_construct_params()),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("requires arcane or divine"),
		"Fighter should be rejected (not an arcane/divine caster or craftpriest); got '%s'" % result.get("summary", ""))


func test_construct_rejects_hd_over_2x_caster_level() -> void:
	# L11 mage tries to craft a 23 HD construct (cap = 22).
	var params := _construct_params(23, [])
	params["max_damage_per_round"] = 1  # avoid hitting the 3×HD cap first
	# But the cost will be huge; bump gp_committed and use the big workshop.
	var cost: int = MagicalResearchConstruct.base_gp_cost(23, 0)
	params["gp_committed"] = cost
	# Workshop is 50,000gp; 23-HD cost is 46,000 — workshop is enough.
	var state := {
		"character_id": _mage_l11_id,
		"params_json": JSON.stringify(params),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("HD") and String(result.get("summary", "")).contains("exceeds"),
		"HD 23 for L11 caster should be rejected; got '%s'" % result.get("summary", ""))


func test_construct_rejects_too_many_attacks() -> void:
	var params := _construct_params(4, [])
	params["attacks_per_round"] = 5
	params["max_damage_per_round"] = 4
	var state := {
		"character_id": _mage_l11_id,
		"params_json": JSON.stringify(params),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("1-4 attacks"),
		"5 attacks per round should be rejected; got '%s'" % result.get("summary", ""))


func test_construct_rejects_damage_over_3x_hd() -> void:
	# 2 HD construct → max damage cap = 6. Try 12.
	var params := _construct_params(2, [])
	params["max_damage_per_round"] = 12
	var state := {
		"character_id": _mage_l11_id,
		"params_json": JSON.stringify(params),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("exceeds 3"),
		"max damage 12 for 2 HD (cap 6) should be rejected; got '%s'" % result.get("summary", ""))


func test_construct_rejects_no_workshop() -> void:
	var params := _construct_params(2, [])
	params.erase("workshop_id")
	var state := {
		"character_id": _mage_l11_id,
		"params_json": JSON.stringify(params),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("workshop required"),
		"No workshop should be rejected; got '%s'" % result.get("summary", ""))


func test_construct_rejects_workshop_too_small() -> void:
	# Construct cost 4,000gp; small workshop has only 2,000gp invested.
	var params := _construct_params(2, [])  # cost = 4,000
	params["workshop_id"] = _workshop_small_id
	var state := {
		"character_id": _mage_l11_id,
		"params_json": JSON.stringify(params),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("workshop too small"),
		"2,000gp workshop should be rejected for 4,000gp construct; got '%s'" % result.get("summary", ""))


func test_construct_success_creates_design_and_instance() -> void:
	# L11 INT17 mage crafts a 2-HD construct (cost 4,000gp, +0 target mod,
	# workshop_big has 50,000gp invested → excess 46,000 → +3 throw bonus).
	# Modifier = INT+2 + Mag Eng 0 + Workshop +3 = +5.
	# Target = L11 base 6 + 0 = 6+. Need raw_roll >= 1 to clear with mod 5;
	# but natural 1-3 always fails. Retry up to 10 times.
	_purge_constructs_for(_mage_l11_id)
	var design_id := ""
	var instance_id := ""
	var attempts := 0
	while attempts < 10 and (design_id.is_empty() or instance_id.is_empty()):
		attempts += 1
		_purge_constructs_for(_mage_l11_id)
		var state := {
			"character_id": _mage_l11_id,
			"params_json": JSON.stringify(_construct_params(2, [])),
		}
		var result := ResearchMagicHandler.on_complete(state, null)
		if String(result.get("summary", "")).contains("built"):
			design_id = String(result.get("design_id", ""))
			instance_id = String(result.get("instance_id", ""))
			# Verify rows persisted.
			var design: Dictionary = CampaignRepository.get_construct_design(design_id)
			check(int(design.get("hit_dice", 0)) == 2,
				"design row hit_dice should be 2")
			check(int(design.get("gp_cost_total", 0)) == 4000,
				"design row gp_cost_total should be 4,000")
			check(int(design.get("days_to_design", 0)) == 11,
				"design row days_to_design should be 11 (7 + 4) got %d" % int(design.get("days_to_design", 0)))
			var instance: Dictionary = CampaignRepository.get_construct_instance(instance_id)
			check(String(instance.get("design_id", "")) == design_id,
				"instance.design_id should point at design")
			check(int(instance.get("hp_max", 0)) == 9,
				"2-HD construct default HP should be 9; got %d" % int(instance.get("hp_max", 0)))
			break
	check(not design_id.is_empty(),
		"L11 INT17 mage with +3 workshop bonus should succeed within 10 attempts (cumulative failure < 1 in a million)")
	check(not instance_id.is_empty(), "construct_instances row should exist on success")


func test_construct_repeat_dedupes_design() -> void:
	# Designed in the previous test (Iron Sentinel, 2 HD, 1 attack, 6 dmg, []).
	# Re-running the handler with the same signature should REUSE the design
	# rather than insert a new one.
	var pre_designs: Array = CampaignRepository.list_construct_designs_for_creator(_mage_l11_id)
	var pre_design_count: int = pre_designs.size()
	if pre_design_count == 0:
		# Previous test may not have succeeded if we got REALLY unlucky.
		# Skip cleanly.
		check(true, "skipping dedupe test (no prior design)")
		return

	# Run again with identical params; retry until success.
	var attempts := 0
	while attempts < 10:
		attempts += 1
		var state := {
			"character_id": _mage_l11_id,
			"params_json": JSON.stringify(_construct_params(2, [])),
		}
		var result := ResearchMagicHandler.on_complete(state, null)
		if String(result.get("summary", "")).contains("built"):
			# After success, design count should still equal pre_design_count
			# (dedupe hit), and instance count should have grown.
			var post_designs: Array = CampaignRepository.list_construct_designs_for_creator(_mage_l11_id)
			check(post_designs.size() == pre_design_count,
				"design count should remain %d (dedupe), got %d" % [pre_design_count, post_designs.size()])
			var post_instances: Array = CampaignRepository.list_construct_instances_for_creator(_mage_l11_id)
			check(post_instances.size() >= 2,
				"instance count should now be at least 2 (one per attempt); got %d" % post_instances.size())
			break
