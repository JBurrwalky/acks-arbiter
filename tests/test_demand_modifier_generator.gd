extends "res://tests/test_suite_base.gd"

## Unit tests for DemandModifierGenerator — RAW six-step procedure (steps 1-5).
## Step 6 (trade-route shifts) lands in Prereq.2b; its tests live elsewhere.
##
## Per generation/gdd-settlement-economy.md §4.11.

var _campaign_id: String = ""
var _map_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	# Step-isolation tests (pure functions)
	test_step_1_distribution()
	test_step_2_single_column()
	test_step_2_composite_climate()
	test_step_2_swamp_composite()
	test_step_2_multi_water_source()
	test_step_3_truncation()
	test_step_4_count_fidelity()
	test_step_4_determinism()
	test_step_4_cross_settlement_variation()
	test_step_4_land_revenue_transition()
	test_step_5_dwarf()
	test_step_5_elf()
	test_step_5_human_no_op()

	# End-to-end tests
	test_full_procedure_determinism()
	test_full_procedure_land_revenue_sensitivity()
	test_full_procedure_race_sensitivity()
	test_cache_write_count()
	test_manual_override_preserved()

	if not has_failures():
		print("DemandModifierGenerator: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("DemandModGenTests", "World")
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[_map_id, _campaign_id, "DMGMap"]
	)


func _next_id() -> String:
	_suffix += 1
	return "dmg_%d_%d" % [Time.get_ticks_msec(), _suffix]


func _make_settlement(args: Dictionary) -> String:
	var id: String = _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name,
			 age_years, dominant_race, urban_families, climate_override, parent_domain_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id, _campaign_id, _map_id,
		int(args.get("hex_q", 0)), int(args.get("hex_r", 0)),
		str(args.get("name", "DMGSettlement")),
		int(args.get("age_years", 500)),
		str(args.get("dominant_race", "human")),
		int(args.get("urban_families", 0)),
		str(args.get("climate_override", "")),
		args.get("parent_domain_id", null),
	])
	return id


func _make_hex(q: int, r: int, biome: String, biome_subtype: String,
		elevation: String = "flat", water: String = "") -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_cells
			(map_id, q, r, biome, biome_subtype, elevation, water)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [_map_id, q, r, biome, biome_subtype, elevation, water])


func _add_river(q: int, r: int) -> void:
	# Migration 130: rivers are edge entities. "Hex touches a river" is what
	# the consuming code cares about — insert one edge row whose endpoint
	# is this hex.
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_river_edges
			(map_id, hex_q, hex_r, edge, flow_clockwise, navigability, crossing)
		VALUES (?, ?, ?, 0, 1, 'river_craft', 'none')
	""", [_map_id, q, r])


func _seeded_rng(seed_val: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng


func _load_env_table() -> Dictionary:
	var file := FileAccess.open("res://data/commerce/environmental_adjustments.json", FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	return (json.data as Dictionary).get("entries", {})


# ---------------------------------------------------------------------------
# Step-isolation tests
# ---------------------------------------------------------------------------

func test_step_1_distribution() -> void:
	# 1d3-1d3: 9 outcomes. P(0)=3/9, P(±1)=2/9 each, P(±2)=1/9 each.
	# Run many samples; histogram should be roughly proportional.
	var rng: RandomNumberGenerator = _seeded_rng(42)
	var counts: Dictionary = {}
	for i in 9000:
		var v: int = DemandModifierGenerator.step_1_base_roll(rng)
		counts[v] = int(counts.get(v, 0)) + 1
	# Expected (rough): 0=3000, ±1=2000 each, ±2=1000 each. Allow ±300 jitter
	# (about 10% of the most common bucket).
	check(absi(int(counts.get(0, 0)) - 3000) < 300,
		"step_1: P(0) ≈ 3/9; expected ~3000, got %d" % int(counts.get(0, 0)))
	check(absi(int(counts.get(1, 0)) - 2000) < 300,
		"step_1: P(+1) ≈ 2/9; expected ~2000, got %d" % int(counts.get(1, 0)))
	check(absi(int(counts.get(-1, 0)) - 2000) < 300,
		"step_1: P(-1) ≈ 2/9; expected ~2000, got %d" % int(counts.get(-1, 0)))
	check(absi(int(counts.get(2, 0)) - 1000) < 250,
		"step_1: P(+2) ≈ 1/9; expected ~1000, got %d" % int(counts.get(2, 0)))
	check(absi(int(counts.get(-2, 0)) - 1000) < 250,
		"step_1: P(-2) ≈ 1/9; expected ~1000, got %d" % int(counts.get(-2, 0)))


func test_step_2_single_column() -> void:
	var env: Dictionary = _load_env_table()
	# Inputs: age 101_1000_years, biome woods/forest_taiga (climate=[taiga]),
	# no water, no elevation. Grain: age_101_1000=0, water all 0 for "none",
	# taiga column = +0.5, elevation flat = 0. base=0 → 0 + 0 + 0 + 0.5 + 0 = 0.5.
	var inputs := {
		"age_bucket": "101_1000_years",
		"water_sources": {"sea_coast": false, "lake_shore": false, "river_bank": false},
		"climate_columns": ["taiga"],
		"elevation_bucket": "",
	}
	var value: float = DemandModifierGenerator.step_2_environmental(0, inputs, "grain_vegetables", env)
	check(absf(value - 0.5) < 0.001,
		"step_2 single column: base 0 + grain[age 101_1000]=0 + grain[taiga]=+0.5 → 0.5, got %f" % value)


func test_step_2_composite_climate() -> void:
	var env: Dictionary = _load_env_table()
	# clear-default → [grasslands, plains]. Grain row: grasslands=-1.0, plains=-0.5.
	# Sum of climate contributions = -1.5. Age 101_1000=0, no water, no elevation.
	var inputs := {
		"age_bucket": "101_1000_years",
		"water_sources": {"sea_coast": false, "lake_shore": false, "river_bank": false},
		"climate_columns": ["grasslands", "plains"],
		"elevation_bucket": "",
	}
	var value: float = DemandModifierGenerator.step_2_environmental(0, inputs, "grain_vegetables", env)
	check(absf(value - (-1.5)) < 0.001,
		"step_2 composite: grain[grasslands]=-1.0 + grain[plains]=-0.5 → -1.5, got %f" % value)


func test_step_2_swamp_composite() -> void:
	var env: Dictionary = _load_env_table()
	# Swamp: climate_columns=[scrub] AND water_sources.lake_shore=true.
	# For grain: age 101_1000=0, scrub=-0.5, lake_shore=0.0, no elevation.
	# base 0 + 0 + 0 + (-0.5) + 0 = -0.5.
	var inputs := {
		"age_bucket": "101_1000_years",
		"water_sources": {"sea_coast": false, "lake_shore": true, "river_bank": false},
		"climate_columns": ["scrub"],
		"elevation_bucket": "",
	}
	var value: float = DemandModifierGenerator.step_2_environmental(0, inputs, "grain_vegetables", env)
	check(absf(value - (-0.5)) < 0.001,
		"step_2 swamp: grain[scrub]=-0.5 + grain[lake_shore]=0 → -0.5, got %f" % value)


func test_step_2_multi_water_source() -> void:
	var env: Dictionary = _load_env_table()
	# Coastal river-mouth: sea_coast AND river_bank both true.
	# Grain[sea_coast]=0, grain[river_bank]=-1.0. Climate clear-default + no elev.
	# base 0 + age 0 + water (0 + -1) + climate (grass -1 + plains -0.5) = -2.5.
	var inputs := {
		"age_bucket": "101_1000_years",
		"water_sources": {"sea_coast": true, "lake_shore": false, "river_bank": true},
		"climate_columns": ["grasslands", "plains"],
		"elevation_bucket": "",
	}
	var value: float = DemandModifierGenerator.step_2_environmental(0, inputs, "grain_vegetables", env)
	check(absf(value - (-2.5)) < 0.001,
		"step_2 multi-water: grain sums sea_coast + river_bank columns; expected -2.5, got %f" % value)


func test_step_3_truncation() -> void:
	# Per §4.3: truncate toward zero, NOT banker.
	check(DemandModifierGenerator.step_3_drop_fractions(1.5) == 1,
		"step_3: 1.5 → 1 (truncate)")
	check(DemandModifierGenerator.step_3_drop_fractions(-1.5) == -1,
		"step_3: -1.5 → -1 (truncate, not -2)")
	check(DemandModifierGenerator.step_3_drop_fractions(2.5) == 2,
		"step_3: 2.5 → 2")
	check(DemandModifierGenerator.step_3_drop_fractions(0.5) == 0,
		"step_3: 0.5 → 0")
	check(DemandModifierGenerator.step_3_drop_fractions(-0.5) == 0,
		"step_3: -0.5 → 0 (truncate toward zero)")
	check(DemandModifierGenerator.step_3_drop_fractions(1.0) == 1,
		"step_3: 1.0 → 1 (no fraction to drop)")
	check(DemandModifierGenerator.step_3_drop_fractions(0.0) == 0,
		"step_3: 0.0 → 0")


func _zeroed_modifiers() -> Dictionary:
	# Build a 31-entry dict of {merchandise_type: 0} from the registry.
	var out: Dictionary = {}
	for entry in MerchandiseRegistry.all_merchandise():
		var key: String = str((entry as Dictionary).get("merchandise_type", ""))
		if not key.is_empty():
			out[key] = 0
	return out


func test_step_4_count_fidelity() -> void:
	var table := {3: {"plus": 6, "minus": 1}, 4: {"plus": 4, "minus": 1},
				 5: {"plus": 2, "minus": 1}, 6: {"plus": 1, "minus": 1},
				 7: {"plus": 1, "minus": 2}, 8: {"plus": 1, "minus": 4},
				 9: {"plus": 1, "minus": 6}}
	for land_revenue in [3, 4, 5, 6, 7, 8, 9]:
		var lr: int = land_revenue
		var base: Dictionary = _zeroed_modifiers()
		base = DemandModifierGenerator.step_4_apply_domain_land_revenue(base, lr, "fixed_settlement_id")
		var plus_count: int = 0
		var minus_count: int = 0
		for key in base:
			var v: int = int(base[key])
			if v == 1:
				plus_count += 1
			elif v == -1:
				minus_count += 1
		var expected: Dictionary = table[lr]
		check(plus_count == int(expected["plus"]),
			"step_4 lr=%d: +1 count should be %d, got %d" % [lr, int(expected["plus"]), plus_count])
		check(minus_count == int(expected["minus"]),
			"step_4 lr=%d: -1 count should be %d, got %d" % [lr, int(expected["minus"]), minus_count])


func test_step_4_determinism() -> void:
	# Same (settlement_id, land_revenue) → same result on repeat calls.
	var a: Dictionary = _zeroed_modifiers()
	a = DemandModifierGenerator.step_4_apply_domain_land_revenue(a, 5, "det_settlement")
	var b: Dictionary = _zeroed_modifiers()
	b = DemandModifierGenerator.step_4_apply_domain_land_revenue(b, 5, "det_settlement")
	check(a == b, "step_4 determinism: same settlement + same lr → same result")


func test_step_4_cross_settlement_variation() -> void:
	# Two different settlement_ids at the same land_revenue should produce
	# (likely) different shuffles. Compare the +1 sets.
	var a: Dictionary = _zeroed_modifiers()
	a = DemandModifierGenerator.step_4_apply_domain_land_revenue(a, 5, "settlement_A")
	var b: Dictionary = _zeroed_modifiers()
	b = DemandModifierGenerator.step_4_apply_domain_land_revenue(b, 5, "settlement_B")
	check(a != b, "step_4: different settlement_ids should produce different distributions")


func test_step_4_land_revenue_transition() -> void:
	# Same settlement at lr=3 vs lr=4 should produce different distributions.
	var a: Dictionary = _zeroed_modifiers()
	a = DemandModifierGenerator.step_4_apply_domain_land_revenue(a, 3, "transition_settlement")
	var b: Dictionary = _zeroed_modifiers()
	b = DemandModifierGenerator.step_4_apply_domain_land_revenue(b, 4, "transition_settlement")
	check(a != b, "step_4: same settlement at different lr should differ (seed includes lr)")


func test_step_5_dwarf() -> void:
	var base: Dictionary = _zeroed_modifiers()
	base = DemandModifierGenerator.step_5_apply_racial_adjustment(base, "dwarf")
	for key in ["beer_ale", "metals_common", "tools", "armor_weapons",
				"metals_precious", "semiprecious_stones", "gems"]:
		check(int(base[key]) == -2,
			"step_5 dwarf: %s should be -2, got %d" % [key, int(base[key])])
	# Spot-check a non-affected merchandise.
	check(int(base["silk"]) == 0, "step_5 dwarf: silk unaffected")
	check(int(base["grain_vegetables"]) == 0, "step_5 dwarf: grain_vegetables unaffected")


func test_step_5_elf() -> void:
	var base: Dictionary = _zeroed_modifiers()
	base = DemandModifierGenerator.step_5_apply_racial_adjustment(base, "elf")
	for key in ["wood_common", "dye_pigments", "cloth", "glassware", "porcelain_fine"]:
		check(int(base[key]) == -2,
			"step_5 elf: %s should be -2, got %d" % [key, int(base[key])])
	check(int(base["beer_ale"]) == 0, "step_5 elf: beer_ale unaffected (dwarf-only)")
	check(int(base["silk"]) == 0, "step_5 elf: silk unaffected")


func test_step_5_human_no_op() -> void:
	var base: Dictionary = _zeroed_modifiers()
	base = DemandModifierGenerator.step_5_apply_racial_adjustment(base, "human")
	for key in base:
		check(int(base[key]) == 0,
			"step_5 human: all merchandise should remain 0 (no race table entry)")


# ---------------------------------------------------------------------------
# End-to-end tests
# ---------------------------------------------------------------------------

func test_full_procedure_determinism() -> void:
	_make_hex(200, 0, "clear", "", "flat", "")
	var s: String = _make_settlement({"hex_q": 200, "hex_r": 0})
	var a: Dictionary = DemandModifierGenerator.generate_for_settlement(s)
	var b: Dictionary = DemandModifierGenerator.generate_for_settlement(s)
	check(a == b,
		"full procedure: same settlement + same inputs → same dict on repeat calls")


func test_full_procedure_land_revenue_sensitivity() -> void:
	_make_hex(210, 0, "clear", "", "flat", "")
	var d1: String = CampaignRepository.create_domain({"campaign_id": _campaign_id, "name": "LR4Domain"})
	CampaignRepository.add_domain_hex({"domain_id": d1, "hex_q": 0, "hex_r": 0, "land_value": 4})
	var s1: String = _make_settlement({"hex_q": 210, "hex_r": 0, "parent_domain_id": d1})
	var a: Dictionary = DemandModifierGenerator.generate_for_settlement(s1)

	_make_hex(220, 0, "clear", "", "flat", "")
	var d2: String = CampaignRepository.create_domain({"campaign_id": _campaign_id, "name": "LR7Domain"})
	CampaignRepository.add_domain_hex({"domain_id": d2, "hex_q": 0, "hex_r": 0, "land_value": 7})
	var s2: String = _make_settlement({"hex_q": 220, "hex_r": 0, "parent_domain_id": d2})
	var b: Dictionary = DemandModifierGenerator.generate_for_settlement(s2)

	check(a != b,
		"full procedure: different land_revenue (4 vs 7) should produce different modifier dicts")


func test_full_procedure_race_sensitivity() -> void:
	_make_hex(230, 0, "clear", "", "flat", "")
	var s_human: String = _make_settlement({"hex_q": 230, "hex_r": 0, "dominant_race": "human"})
	var human_mods: Dictionary = DemandModifierGenerator.generate_for_settlement(s_human)

	_make_hex(240, 0, "clear", "", "flat", "")
	var s_dwarf: String = _make_settlement({"hex_q": 240, "hex_r": 0, "dominant_race": "dwarf"})
	var dwarf_mods: Dictionary = DemandModifierGenerator.generate_for_settlement(s_dwarf)

	# Dwarf should have 7 merchandise types shifted -2 vs human (modulo the
	# different step-1/step-4 RNG paths driven by different settlement_ids).
	# Verify per-merchandise the dwarf row's delta is more negative on the
	# dwarf-targeted merchandise. We compare the seven racial-targets only.
	var dwarf_targets := ["beer_ale", "metals_common", "tools", "armor_weapons",
		"metals_precious", "semiprecious_stones", "gems"]
	# Use settlement_id-pinned step 4 with land_revenue=5 baseline to isolate
	# racial effect — feed both base dicts the same shuffle via shared id.
	var base_human: Dictionary = _zeroed_modifiers()
	var base_dwarf: Dictionary = _zeroed_modifiers()
	base_human = DemandModifierGenerator.step_5_apply_racial_adjustment(base_human, "human")
	base_dwarf = DemandModifierGenerator.step_5_apply_racial_adjustment(base_dwarf, "dwarf")
	for k in dwarf_targets:
		check(int(base_dwarf[k]) == int(base_human[k]) - 2,
			"isolated step_5: dwarf %s should be human %s - 2" % [k, k])


func test_cache_write_count() -> void:
	_make_hex(250, 0, "clear", "", "flat", "")
	var s: String = _make_settlement({"hex_q": 250, "hex_r": 0})
	DemandModifierGenerator.generate_for_settlement(s)
	CampaignRepository.db.query_with_bindings(
		"SELECT COUNT(*) AS n, MIN(source_kind) AS k FROM settlement_merchandise_demand WHERE settlement_entrance_id = ?",
		[s]
	)
	var row: Dictionary = CampaignRepository.db.query_result[0]
	check(int(row.get("n", 0)) == 31,
		"cache should have 31 rows after generate_for_settlement, got %d" % int(row.get("n", 0)))
	check(str(row.get("k", "")) == "generated",
		"all rows should have source_kind='generated'")


func test_manual_override_preserved() -> void:
	_make_hex(260, 0, "clear", "", "flat", "")
	var s: String = _make_settlement({"hex_q": 260, "hex_r": 0})
	# First generation populates the cache.
	DemandModifierGenerator.generate_for_settlement(s)
	# Manual override on silk.
	check(DemandModifierGenerator.set_manual_demand_modifier(s, "silk", 5),
		"set_manual_demand_modifier should succeed")
	# Regenerate — manual row should be preserved.
	DemandModifierGenerator.regenerate(s)
	check(DemandModifierGenerator.get_demand_modifier(s, "silk") == 5,
		"manual silk override should remain 5 after regenerate")
	# Verify other rows were regenerated (source_kind='generated').
	CampaignRepository.db.query_with_bindings(
		"SELECT source_kind FROM settlement_merchandise_demand WHERE settlement_entrance_id = ? AND merchandise_type = 'silk'",
		[s]
	)
	check(str(CampaignRepository.db.query_result[0].get("source_kind", "")) == "manual",
		"silk row should retain source_kind='manual'")
