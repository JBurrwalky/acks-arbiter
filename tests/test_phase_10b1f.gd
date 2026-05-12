extends "res://tests/test_suite_base.gd"

## Tests for Phase 10B.1f — Cross-breeding (project_kind='monster',
## monster_action='crossbreed').
##
## Covers:
##   - MagicalResearchCrossbreed helper: cost / time / target modifier /
##     progenitor HD limit / crossbreed HD range / ability-soft-cap /
##     alignment derivation / type compute / laboratory bonus.
##   - research_magic[monster] dispatch:
##     - eligibility (arcane L11+; Dwarven Craftpriest NOT eligible per RAW)
##     - rejects monster_action='scratch' (deferred per Q19)
##     - progenitor HD > caster level rejected
##     - crossbreed HD outside progenitor range rejected
##     - ability soft cap rejected at >2× per-progenitor max
##     - laboratory required + worth >= cost
##     - success creates species + instance rows
##     - alignment derived correctly (chaotic wins; both-lawful → lawful)
##     - dedupe: re-crafting same signature reuses species row


var _campaign_id: String = ""
var _mage_l11_id: String = ""
var _mage_l10_id: String = ""
var _craftpriest_l11_id: String = ""
var _laboratory_big_id: String = ""
var _laboratory_small_id: String = ""
var _stronghold_id: String = ""


func run_all_tests() -> void:
	_setup()

	# MagicalResearchCrossbreed helper
	test_base_gp_cost_matches_construct_formula()
	test_base_days_formula()
	test_target_modifier_per_5000gp()
	test_validate_progenitor_hd_over_caster_level()
	test_validate_crossbreed_hd_in_range()
	test_crossbreed_hd_outside_range_rejected()
	test_max_special_abilities_per_progenitor()
	test_validate_ability_count_soft_cap()
	test_derive_alignment_chaotic_wins()
	test_derive_alignment_both_lawful()
	test_derive_alignment_otherwise_neutral()
	test_compute_types_always_includes_fantastic()
	test_compute_types_filters_unknown()
	test_movement_kind_both_costs_ability()

	# research_magic[monster] dispatch
	test_crossbreed_rejects_below_l11()
	test_crossbreed_rejects_craftpriest()
	test_crossbreed_rejects_scratch_action()
	test_crossbreed_rejects_progenitor_hd_over_caster_level()
	test_crossbreed_rejects_hd_outside_progenitor_range()
	test_crossbreed_rejects_no_laboratory()
	test_crossbreed_rejects_lab_too_small()
	test_crossbreed_success_creates_species_and_instance()
	test_crossbreed_dedupe_on_repeat_craft()

	if not has_failures():
		print("Phase10B1f: all tests passed.")


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Test 10B.1f", "TestWorld")

	_mage_l11_id = _create_test_character(_campaign_id, "Test Mage L11", "mage", "mage", 11, 17, 10)
	_mage_l10_id = _create_test_character(_campaign_id, "Test Mage L10", "mage", "mage", 10, 14, 10)
	_craftpriest_l11_id = _create_test_character(_campaign_id, "Test Craftpriest L11",
		"dwarven_craftpriest", "cleric", 11, 12, 16)

	_stronghold_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds (id, owner_character_id, archetype,
			structure_type, gp_value, completion_pct, status)
		VALUES (?, ?, 'sanctum', 'sanctum', 60000, 100, 'completed')
	""", [_stronghold_id, _mage_l11_id])

	# Big laboratory (50,000gp invested) — supports up to a 50,000gp
	# crossbreed; for smaller crossbreeds excess gives throw bonus.
	_laboratory_big_id = CampaignRepository.create_laboratory({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_l11_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "crossbreeding_laboratory",
		"gp_invested": 50000,
		"max_crossbreed_cost_gp": 100000,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})

	# Small laboratory (2,000gp) — too small for typical crossbreeds.
	_laboratory_small_id = CampaignRepository.create_laboratory({
		"campaign_id": _campaign_id,
		"owner_character_id": _mage_l11_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "crossbreeding_laboratory",
		"gp_invested": 2000,
		"max_crossbreed_cost_gp": 3000,
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
			10, ?, ?, 12, 10, 12, 'neutral', 30, 30)
	""", [id, campaign_id, name, class_id, progression, level, intelligence, wisdom])
	return id


# ---------------------------------------------------------------------------
# Helper tests
# ---------------------------------------------------------------------------

func test_base_gp_cost_matches_construct_formula() -> void:
	# Same formula as constructs: 2000*HD + 5000*abilities.
	check(MagicalResearchCrossbreed.base_gp_cost(3, 1) == 11000,
		"3 HD + 1 ability should cost 11,000 gp; got %d" % MagicalResearchCrossbreed.base_gp_cost(3, 1))


func test_base_days_formula() -> void:
	check(MagicalResearchCrossbreed.base_days(11000) == 18,
		"11,000gp should take 18 days (7 + 11), got %d" % MagicalResearchCrossbreed.base_days(11000))


func test_target_modifier_per_5000gp() -> void:
	check(MagicalResearchCrossbreed.target_modifier_for_cost(11000) == 2,
		"11,000gp → +2 target modifier")
	check(MagicalResearchCrossbreed.target_modifier_for_cost(4999) == 0,
		"4,999gp → +0 target modifier")


func test_validate_progenitor_hd_over_caster_level() -> void:
	# L11 caster: progenitor HD must be <= 11.
	var err: String = MagicalResearchCrossbreed.validate_progenitor_hd(12, 5, 11)
	check(err.contains("exceeds caster level"),
		"progenitor A HD 12 for L11 caster should be rejected; got '%s'" % err)
	err = MagicalResearchCrossbreed.validate_progenitor_hd(8, 11, 11)
	check(err.is_empty(), "progenitor HD exactly at cap should pass")


func test_validate_crossbreed_hd_in_range() -> void:
	# Crossbreed HD must be in [min, max] of progenitor HD.
	# Progenitors 4 and 8 → crossbreed in [4, 8].
	check(MagicalResearchCrossbreed.validate_crossbreed_hd(6, 4, 8).is_empty(),
		"6 HD should pass when progenitors are 4 and 8")
	check(MagicalResearchCrossbreed.validate_crossbreed_hd(4, 4, 8).is_empty(),
		"4 HD (min boundary) should pass")
	check(MagicalResearchCrossbreed.validate_crossbreed_hd(8, 4, 8).is_empty(),
		"8 HD (max boundary) should pass")


func test_crossbreed_hd_outside_range_rejected() -> void:
	# Progenitors 4 and 8 → crossbreed must be in [4, 8].
	check(MagicalResearchCrossbreed.validate_crossbreed_hd(3, 4, 8).contains("outside"),
		"3 HD below progenitor min should be rejected")
	check(MagicalResearchCrossbreed.validate_crossbreed_hd(9, 4, 8).contains("outside"),
		"9 HD above progenitor max should be rejected")


func test_max_special_abilities_per_progenitor() -> void:
	# RAW L424: 1 + INT bonus per progenitor.
	check(MagicalResearchCrossbreed.max_special_abilities_per_progenitor(0) == 1,
		"INT mod +0 → 1 ability per progenitor")
	check(MagicalResearchCrossbreed.max_special_abilities_per_progenitor(2) == 3,
		"INT mod +2 → 3 abilities per progenitor")


func test_validate_ability_count_soft_cap() -> void:
	# INT mod +2 → per-progenitor cap 3 → soft cap 6 total.
	check(MagicalResearchCrossbreed.validate_crossbreed_ability_count(6, 2).is_empty(),
		"6 abilities at INT mod +2 (cap 6) should pass")
	check(MagicalResearchCrossbreed.validate_crossbreed_ability_count(7, 2).contains("soft cap"),
		"7 abilities at INT mod +2 should be rejected")


func test_derive_alignment_chaotic_wins() -> void:
	check(MagicalResearchCrossbreed.derive_alignment("chaotic", "lawful") == "chaotic",
		"chaotic + lawful → chaotic (RAW L430)")
	check(MagicalResearchCrossbreed.derive_alignment("neutral", "chaotic") == "chaotic",
		"either chaotic → chaotic")


func test_derive_alignment_both_lawful() -> void:
	check(MagicalResearchCrossbreed.derive_alignment("lawful", "lawful") == "lawful",
		"both lawful → lawful (RAW L431)")


func test_derive_alignment_otherwise_neutral() -> void:
	check(MagicalResearchCrossbreed.derive_alignment("lawful", "neutral") == "neutral",
		"lawful + neutral → neutral (RAW L432)")
	check(MagicalResearchCrossbreed.derive_alignment("neutral", "neutral") == "neutral",
		"both neutral → neutral")


func test_compute_types_always_includes_fantastic() -> void:
	var types := MagicalResearchCrossbreed.compute_types([])
	check(types == ["fantastic"], "empty optional_types should yield ['fantastic']")
	types = MagicalResearchCrossbreed.compute_types(["beastman"])
	check(types.size() == 2 and types[0] == "fantastic" and types[1] == "beastman",
		"['beastman'] should yield ['fantastic', 'beastman']")


func test_compute_types_filters_unknown() -> void:
	var types := MagicalResearchCrossbreed.compute_types(["beastman", "unknown_type", "humanoid"])
	# Per CLAUDE.md anti-pattern: don't use `as Array[String]` after == —
	# GDScript parses it as `(types == [...]) as Array[String]` which is a
	# type error. Plain `==` on typed and untyped arrays works.
	check(types.size() == 3 and types[0] == "fantastic"
			and types[1] == "beastman" and types[2] == "humanoid",
		"unknown types should be filtered; got %s" % str(types))


func test_movement_kind_both_costs_ability() -> void:
	check(MagicalResearchCrossbreed.movement_costs_ability("both"),
		"movement_kind='both' should cost +1 ability per RAW L436")
	check(not MagicalResearchCrossbreed.movement_costs_ability("progenitor_a"),
		"movement_kind='progenitor_a' should NOT cost an ability")


# ---------------------------------------------------------------------------
# Dispatch tests
# ---------------------------------------------------------------------------

func _purge_crossbreeds_for(character_id: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM crossbreed_instances WHERE creator_character_id = ?", [character_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM crossbreed_species WHERE creator_character_id = ?", [character_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM magic_research_projects WHERE character_id = ? AND project_kind = 'monster'",
		[character_id])


## Returns a baseline params dict (5 HD owlbear-style crossbreed from a
## 6 HD owl + 5 HD bear; chooses bear's attacks + flight as a single
## special ability).
func _crossbreed_params(
	hit_dice: int = 5,
	abilities: Array = [],
	movement_kind: String = "progenitor_a",
) -> Dictionary:
	var ability_count: int = abilities.size()
	if movement_kind == "both":
		ability_count += 1
	var cost: int = MagicalResearchCrossbreed.base_gp_cost(hit_dice, ability_count)
	return {
		"project_kind": "monster",
		"monster_action": "crossbreed",
		"name": "Owlbear",
		"progenitor_a_name": "Owl",
		"progenitor_b_name": "Bear",
		"progenitor_a_hd": 6,
		"progenitor_b_hd": 5,
		"progenitor_a_alignment": "neutral",
		"progenitor_b_alignment": "neutral",
		"hit_dice": hit_dice,
		"armor_class": 4,
		"attacks_per_round": 2,
		"max_damage_per_round": 8,
		"damage_expression": "1d6/1d6",
		"morale": 1,
		"movement_kind": movement_kind,
		"special_abilities": abilities,
		"additional_types": [],
		"laboratory_id": _laboratory_big_id,
		"gp_committed": cost,
		"location_kind": "stronghold",
		"location_ref": "stronghold:" + _stronghold_id,
	}


func test_crossbreed_rejects_below_l11() -> void:
	var state := {
		"character_id": _mage_l10_id,
		"params_json": JSON.stringify(_crossbreed_params()),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("L11+"),
		"L10 mage should be rejected (need L11+); got '%s'" % result.get("summary", ""))


func test_crossbreed_rejects_craftpriest() -> void:
	# Give the craftpriest a laboratory so we don't trip on that gate first.
	var lab_id := CampaignRepository.create_laboratory({
		"campaign_id": _campaign_id,
		"owner_character_id": _craftpriest_l11_id,
		"stronghold_id": _stronghold_id,
		"structure_kind": "crossbreeding_laboratory",
		"gp_invested": 50000,
		"max_crossbreed_cost_gp": 100000,
		"magic_research_throw_bonus": 0,
		"status": "operational",
		"created_calendar_day": 1,
	})
	var params := _crossbreed_params()
	params["laboratory_id"] = lab_id
	var state := {
		"character_id": _craftpriest_l11_id,
		"params_json": JSON.stringify(params),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("arcane caster required"),
		"Dwarven Craftpriest should be rejected (RAW grants crossbreeding to arcane only); got '%s'" % result.get("summary", ""))


func test_crossbreed_rejects_scratch_action() -> void:
	var params := _crossbreed_params()
	params["monster_action"] = "scratch"
	var state := {
		"character_id": _mage_l11_id,
		"params_json": JSON.stringify(params),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("not yet supported"),
		"monster_action='scratch' should be rejected per Q19; got '%s'" % result.get("summary", ""))


func test_crossbreed_rejects_progenitor_hd_over_caster_level() -> void:
	var params := _crossbreed_params()
	params["progenitor_a_hd"] = 12  # L11 caster
	var state := {
		"character_id": _mage_l11_id,
		"params_json": JSON.stringify(params),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("exceeds caster level"),
		"progenitor HD 12 for L11 should be rejected; got '%s'" % result.get("summary", ""))


func test_crossbreed_rejects_hd_outside_progenitor_range() -> void:
	# Owl 6 HD + Bear 5 HD → crossbreed must be in [5, 6]. Try 4.
	var params := _crossbreed_params(4, [])
	var state := {
		"character_id": _mage_l11_id,
		"params_json": JSON.stringify(params),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("outside progenitor range"),
		"crossbreed HD 4 outside [5,6] should be rejected; got '%s'" % result.get("summary", ""))


func test_crossbreed_rejects_no_laboratory() -> void:
	var params := _crossbreed_params()
	params.erase("laboratory_id")
	var state := {
		"character_id": _mage_l11_id,
		"params_json": JSON.stringify(params),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("laboratory required"),
		"no laboratory should be rejected; got '%s'" % result.get("summary", ""))


func test_crossbreed_rejects_lab_too_small() -> void:
	# 5 HD crossbreed cost = 10,000gp. Small lab has 2,000gp.
	var params := _crossbreed_params(5, [])
	params["laboratory_id"] = _laboratory_small_id
	var state := {
		"character_id": _mage_l11_id,
		"params_json": JSON.stringify(params),
	}
	var result := ResearchMagicHandler.on_complete(state, null)
	check(String(result.get("summary", "")).contains("laboratory too small"),
		"2,000gp lab should be rejected for 10,000gp crossbreed; got '%s'" % result.get("summary", ""))


func test_crossbreed_success_creates_species_and_instance() -> void:
	# L11 INT17 mage with big lab (+3 throw bonus): target = base 6 + (10000/5000 = 2) = 8.
	# Modifier = INT+2 + Mag Eng 0 + Lab +3 (50,000 - 10,000 = 40,000 excess → +3) = +5.
	# Need raw_roll >= 3 to clear. Natural 1-3 always fails; raw_roll 4-20 succeeds = 17/20 = 85%.
	# Retry up to 10 times (cumulative failure < 1 in a million).
	_purge_crossbreeds_for(_mage_l11_id)
	var species_id := ""
	var instance_id := ""
	var attempts := 0
	while attempts < 10 and (species_id.is_empty() or instance_id.is_empty()):
		attempts += 1
		_purge_crossbreeds_for(_mage_l11_id)
		var state := {
			"character_id": _mage_l11_id,
			"params_json": JSON.stringify(_crossbreed_params(5, [])),
		}
		var result := ResearchMagicHandler.on_complete(state, null)
		if String(result.get("summary", "")).contains("created from"):
			species_id = String(result.get("species_id", ""))
			instance_id = String(result.get("instance_id", ""))
			# Verify rows.
			var species: Dictionary = CampaignRepository.get_crossbreed_species(species_id)
			check(int(species.get("hit_dice", 0)) == 5,
				"species hit_dice should be 5")
			check(int(species.get("gp_cost_total", 0)) == 10000,
				"species gp_cost_total should be 10,000 (2000 × 5 HD + 5000 × 0)")
			check(String(species.get("alignment", "")) == "neutral",
				"species alignment should be neutral (both progenitors neutral)")
			check(String(species.get("types_json", "")).contains("fantastic"),
				"species types should include 'fantastic'")
			var instance: Dictionary = CampaignRepository.get_crossbreed_instance(instance_id)
			check(String(instance.get("species_id", "")) == species_id,
				"instance.species_id should point at species")
			check(String(instance.get("status", "")) == "alive",
				"instance status should be 'alive'")
			check(int(instance.get("hp_max", 0)) > 0,
				"instance hp_max should be > 0")
			break
	check(not species_id.is_empty(),
		"L11 INT17 mage + big lab should succeed within 10 attempts (cumulative failure < 1 in a million)")


func test_crossbreed_dedupe_on_repeat_craft() -> void:
	# Designed once already by test_crossbreed_success_creates_species_and_instance.
	var pre_species: Array = CampaignRepository.list_crossbreed_species_for_creator(_mage_l11_id)
	if pre_species.size() == 0:
		check(true, "skipping dedupe test (no prior species)")
		return
	var pre_count: int = pre_species.size()
	var attempts := 0
	while attempts < 10:
		attempts += 1
		var state := {
			"character_id": _mage_l11_id,
			"params_json": JSON.stringify(_crossbreed_params(5, [])),
		}
		var result := ResearchMagicHandler.on_complete(state, null)
		if String(result.get("summary", "")).contains("created from"):
			var post_species: Array = CampaignRepository.list_crossbreed_species_for_creator(_mage_l11_id)
			check(post_species.size() == pre_count,
				"species count should remain %d (dedupe), got %d" % [pre_count, post_species.size()])
			var post_instances: Array = CampaignRepository.list_crossbreed_instances_for_creator(_mage_l11_id)
			check(post_instances.size() >= 2,
				"instance count should be >= 2 after the second successful craft")
			break
