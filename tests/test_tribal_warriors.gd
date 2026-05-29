extends "res://tests/test_suite_base.gd"

## Phase 11D.5 — Tribal Warriors subsystem.
##
## Covers the v1 backbone:
##   * Migration 129: troop_units source_type extended; domains gains
##     available_tribal_warriors; departure_log gains the 6 tribal event types.
##   * TribalWarriorRegistry.pool_for_domain derivation (clanhold + civilized).
##   * LevyTribalWarriorsHandler: decrements available, creates troop_unit,
##     writes departure log entry, emits signal.
##   * StandDownTribalWarriorsHandler: full + partial paths; increments
##     available back; marks unit departed on full.
##   * Validation: non-clanhold domain rejects levy; non-ruler rejects levy;
##     levy capped at available.
##   * Pool invariant: available + levied ≤ peasant_families; slack tracks
##     dead-not-yet-replaced (this is checked indirectly via the pool helper).

const TEST_CAMPAIGN := "test_tw_campaign"
const TEST_RULER := "test_tw_ruler"
const TEST_OTHER := "test_tw_other"
const TEST_CLANHOLD := "test_tw_clanhold"
const TEST_CIVILIZED := "test_tw_civilized"


func run_all_tests() -> void:
	_cleanup()
	# Pool derivation
	test_pool_for_civilized_domain_returns_zeros()
	test_pool_for_clanhold_returns_seeded_state()
	test_pool_for_unknown_domain_returns_empty()
	# Levy mechanics
	test_levy_decrements_available_and_creates_unit()
	test_levy_caps_at_available()
	test_levy_rejects_civilized_domain()
	test_levy_rejects_non_ruler()
	test_levy_rejects_zero_available()
	# Stand-down mechanics
	test_full_stand_down_marks_unit_departed_and_refills_pool()
	test_partial_stand_down_keeps_unit_active()
	test_stand_down_rejects_non_tribal_unit()
	# Migration 129 schema invariants
	test_event_type_check_accepts_tribal_warrior_events()
	test_troop_units_source_type_accepts_tribal_warrior()
	# Phase 11D.5 polish — new hooks
	test_spoils_distribute_to_units_per_warrior_split()
	test_spoils_resets_qualifying_units()
	test_spoils_skips_non_qualifying_units()
	# Phase 11D.5 per-race import — composition + inference
	test_composition_for_orc_120_warriors_matches_raw_table()
	test_composition_for_kobold_levy_is_all_light_infantry()
	test_composition_for_unknown_race_returns_empty()
	test_inferred_race_for_beastman_clanhold_is_orc()
	test_inferred_race_for_kin_clanhold_is_jutland()
	test_morale_modifier_for_steadfast_is_plus_one()
	test_morale_modifier_for_demoralized_is_minus_one()
	_cleanup()
	if not has_failures():
		print("TribalWarriors: all tests passed.")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup_basic() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "Tribal Warriors Test"])
	for c in [TEST_RULER, TEST_OTHER]:
		CampaignRepository.db.query_with_bindings("""
			INSERT OR IGNORE INTO characters
				(id, campaign_id, name, character_type, persistence_tier,
				 race, character_class, level, xp, combat_progression,
				 strength, intelligence, wisdom, dexterity, constitution, charisma,
				 alignment, is_active)
			VALUES (?, ?, 'TW Char', 'pc', 'full', 'human', 'fighter', 9, 0, 'fighter',
			        10, 10, 10, 10, 10, 10, 'chaotic', 1)
		""", [c, TEST_CAMPAIGN])


func _cleanup() -> void:
	for d in [TEST_CLANHOLD, TEST_CIVILIZED]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM troop_units WHERE assigned_domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domain_departure_log WHERE domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domains WHERE id = ?", [d])
	for c in [TEST_RULER, TEST_OTHER]:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM troop_units WHERE owner_character_id = ?", [c])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [c])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _insert_clanhold(peasants: int = 500, available: int = -1) -> void:
	# If available is -1, seed to peasants (the canonical clanhold initial state).
	var seeded_available: int = peasants if available < 0 else available
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, alignment, religion, effective_religion,
			 domain_style, establishment_method, established_calendar_day,
			 available_tribal_warriors)
		VALUES (?, ?, 'Test Clanhold', ?, 'wilderness', ?, 'chaotic',
		        'chaos-cult', 'chaos-cult', 'clanhold', 'clanhold_annex', 1, ?)
	""", [TEST_CLANHOLD, TEST_CAMPAIGN, TEST_RULER, peasants, seeded_available])


func _insert_civilized(peasants: int = 500) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, alignment, religion, effective_religion,
			 domain_style, establishment_method, established_calendar_day)
		VALUES (?, ?, 'Test Civilized', ?, 'civilized', ?, 'lawful',
		        'sun-cult', 'sun-cult', 'civilized', 'grant', 1)
	""", [TEST_CIVILIZED, TEST_CAMPAIGN, TEST_RULER, peasants])


func _state(character_id: String, params: Dictionary) -> Dictionary:
	return {
		"character_id": character_id,
		"params_json": JSON.stringify(params),
	}


# ---------------------------------------------------------------------------
# Pool derivation
# ---------------------------------------------------------------------------

func test_pool_for_civilized_domain_returns_zeros() -> void:
	_setup_basic()
	_insert_civilized(500)
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CIVILIZED)
	check(int(pool.get("peasant_families", -1)) == 500,
		"peasant_families surfaced even for civilized; got %d" % int(pool.get("peasant_families", -1)))
	check(int(pool.get("available", -1)) == 0,
		"civilized: available = 0; got %d" % int(pool.get("available", -1)))
	check(int(pool.get("levied", -1)) == 0,
		"civilized: levied = 0; got %d" % int(pool.get("levied", -1)))
	check(not bool(pool.get("is_clanhold", true)),
		"civilized: is_clanhold = false")


func test_pool_for_clanhold_returns_seeded_state() -> void:
	_setup_basic()
	_insert_clanhold(500, 500)
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(int(pool.get("peasant_families", 0)) == 500,
		"clanhold pool peasant_families=500")
	check(int(pool.get("available", 0)) == 500,
		"clanhold pool available=500 (seeded)")
	check(int(pool.get("levied", -1)) == 0,
		"clanhold pool levied=0 initially")
	check(int(pool.get("slack", -1)) == 0,
		"clanhold pool slack=0 initially")
	check(bool(pool.get("pool_invariant_ok", false)),
		"pool_invariant_ok=true on initial state")
	check(bool(pool.get("is_clanhold", false)),
		"is_clanhold=true for clanhold style")


func test_pool_for_unknown_domain_returns_empty() -> void:
	_setup_basic()
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain("nonexistent_domain_id")
	check(int(pool.get("peasant_families", -1)) == 0,
		"unknown domain: peasant_families=0")
	check(int(pool.get("available", -1)) == 0,
		"unknown domain: available=0")


# ---------------------------------------------------------------------------
# Levy mechanics
# ---------------------------------------------------------------------------

func test_levy_decrements_available_and_creates_unit() -> void:
	_setup_basic()
	_insert_clanhold(500, 500)
	var result: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 100, "domain_id": TEST_CLANHOLD}), null)
	check(int(result.get("count", 0)) == 100,
		"levied 100; got count=%d" % int(result.get("count", 0)))
	var ids: Array = result.get("unit_ids", [])
	# Phase 11D.5 per-race import: levy now spawns multiple unit rows per
	# the RAW composition table. clanhold_annex → orc → 5 troop types
	# (light_infantry, heavy_infantry, bowmen, crossbowmen, beast_riders).
	check(ids.size() >= 2,
		"per-race composition: multiple unit rows; got %d rows" % ids.size())
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(int(pool.get("available", -1)) == 400,
		"available decremented to 400; got %d" % int(pool.get("available", -1)))
	check(int(pool.get("levied", -1)) == 100,
		"levied = 100 across all unit rows; got %d" % int(pool.get("levied", -1)))
	# Verify the troop_units rows have the right source_type + race.
	var first_unit: Dictionary = TroopUnitRepository.get_unit(String(ids[0]))
	check(String(first_unit.get("source_type", "")) == "tribal_warrior",
		"unit row has source_type='tribal_warrior'; got %s" % str(first_unit.get("source_type", "?")))
	check(String(first_unit.get("race", "")) == "orc",
		"unit row has race='orc' (clanhold_annex → orc default); got %s" % str(first_unit.get("race", "?")))
	# Sum counts across all created rows should equal 100.
	var total_levied: int = 0
	for uid_v in ids:
		var u: Dictionary = TroopUnitRepository.get_unit(String(uid_v))
		total_levied += int(u.get("count", 0))
	check(total_levied == 100,
		"sum of unit counts == 100; got %d" % total_levied)


func test_levy_caps_at_available() -> void:
	_setup_basic()
	_insert_clanhold(500, 50)  # only 50 dormant warriors
	var result: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 200, "domain_id": TEST_CLANHOLD}), null)
	check(int(result.get("count", 0)) == 50,
		"levy capped at available (50); got %d" % int(result.get("count", 0)))
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(int(pool.get("available", -1)) == 0,
		"available drained to 0; got %d" % int(pool.get("available", -1)))


func test_levy_rejects_civilized_domain() -> void:
	_setup_basic()
	_insert_civilized(500)
	var result: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 100, "domain_id": TEST_CIVILIZED}), null)
	check(String(result.get("blocked_reason", "")) == "domain_not_clanhold_style",
		"civilized domain rejects levy; got blocked_reason=%s"
		% str(result.get("blocked_reason", "")))


func test_levy_rejects_non_ruler() -> void:
	_setup_basic()
	_insert_clanhold(500, 500)
	var result: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_OTHER, {"count": 100, "domain_id": TEST_CLANHOLD}), null)
	check(String(result.get("blocked_reason", "")) == "not_domain_ruler",
		"non-ruler levy rejected; got blocked_reason=%s"
		% str(result.get("blocked_reason", "")))


func test_levy_rejects_zero_available() -> void:
	_setup_basic()
	_insert_clanhold(500, 0)
	var result: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 100, "domain_id": TEST_CLANHOLD}), null)
	check(String(result.get("blocked_reason", "")) == "pool_empty",
		"empty pool rejects levy; got blocked_reason=%s"
		% str(result.get("blocked_reason", "")))


# ---------------------------------------------------------------------------
# Stand-down mechanics
# ---------------------------------------------------------------------------

func test_full_stand_down_marks_unit_departed_and_refills_pool() -> void:
	_setup_basic()
	_insert_clanhold(500, 500)
	# Levy 100 (across multiple per-race units), then stand down each.
	var levy_result: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 100, "domain_id": TEST_CLANHOLD}), null)
	var ids: Array = levy_result.get("unit_ids", [])
	for uid_v in ids:
		var u: Dictionary = TroopUnitRepository.get_unit(String(uid_v))
		var c: int = int(u.get("count", 0))
		StandDownTribalWarriorsHandler.on_complete(
			_state(TEST_RULER, {"troop_unit_id": String(uid_v), "count": c}), null)
	# Verify each unit is now departed.
	for uid_v in ids:
		var u: Dictionary = TroopUnitRepository.get_unit(String(uid_v))
		check(String(u.get("status", "")) == "departed",
			"unit %s departed after full stand-down" % str(uid_v))
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(int(pool.get("available", -1)) == 500,
		"available refilled to 500; got %d" % int(pool.get("available", -1)))
	check(int(pool.get("levied", -1)) == 0,
		"levied = 0 after stand-down; got %d" % int(pool.get("levied", -1)))


func test_partial_stand_down_keeps_unit_active() -> void:
	_setup_basic()
	_insert_clanhold(500, 500)
	var levy_result: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 100, "domain_id": TEST_CLANHOLD}), null)
	# Pick the largest single unit to do a partial stand-down on.
	var largest_id: String = ""
	var largest_count: int = 0
	for uid_v in (levy_result.get("unit_ids", []) as Array):
		var u: Dictionary = TroopUnitRepository.get_unit(String(uid_v))
		var c: int = int(u.get("count", 0))
		if c > largest_count:
			largest_count = c
			largest_id = String(uid_v)
	check(not largest_id.is_empty() and largest_count >= 2,
		"selected a unit with count >= 2 for partial stand-down (count=%d)" % largest_count)
	var partial: int = mini(largest_count - 1, 10)
	var prior_pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	var prior_avail: int = int(prior_pool.get("available", 0))
	var stand_result: Dictionary = StandDownTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"troop_unit_id": largest_id, "count": partial}), null)
	check(int(stand_result.get("count", 0)) == partial,
		"stood down %d; got %d" % [partial, int(stand_result.get("count", 0))])
	check(not bool(stand_result.get("unit_disbanded", true)),
		"unit_disbanded=false on partial stand-down")
	var unit: Dictionary = TroopUnitRepository.get_unit(largest_id)
	check(String(unit.get("status", "")) == "active",
		"unit still active after partial stand-down")
	check(int(unit.get("count", -1)) == largest_count - partial,
		"unit count decremented by %d; got %d" % [partial, int(unit.get("count", -1))])
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(int(pool.get("available", -1)) == prior_avail + partial,
		"available += %d; got %d" % [partial, int(pool.get("available", -1))])


func test_stand_down_rejects_non_tribal_unit() -> void:
	_setup_basic()
	_insert_clanhold(500, 500)
	# Create a non-tribal-warrior unit (e.g., mercenary).
	var merc_id: String = TroopUnitRepository.create_unit({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_RULER,
		"assigned_domain_id": TEST_CLANHOLD,
		"source_type": "mercenary",
		"troop_type": "light_infantry",
		"race": "human",
		"starting_count": 50, "count": 50,
		"monthly_wage_cp": 30000,
	})
	var result: Dictionary = StandDownTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"troop_unit_id": merc_id, "count": 25}), null)
	check(String(result.get("blocked_reason", "")) == "wrong_source_type",
		"non-tribal unit rejected; got blocked_reason=%s"
		% str(result.get("blocked_reason", "")))


# ---------------------------------------------------------------------------
# Migration 129 schema invariants
# ---------------------------------------------------------------------------

func test_event_type_check_accepts_tribal_warrior_events() -> void:
	_setup_basic()
	_insert_clanhold(100, 100)
	var ok := CampaignRepository.db.query_with_bindings("""
		INSERT INTO domain_departure_log (id, campaign_id, domain_id, calendar_day, event_type, summary)
		VALUES (?, ?, ?, 1, 'tribal_warriors_levied', 'Test')
	""", [CampaignRepository.generate_id(), TEST_CAMPAIGN, TEST_CLANHOLD])
	check(ok, "event_type='tribal_warriors_levied' accepted after migration 129")


func test_troop_units_source_type_accepts_tribal_warrior() -> void:
	_setup_basic()
	_insert_clanhold(100, 100)
	var unit_id: String = TroopUnitRepository.create_unit({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_RULER,
		"assigned_domain_id": TEST_CLANHOLD,
		"source_type": "tribal_warrior",
		"troop_type": "tribal_infantry",
		"race": "human",
		"starting_count": 30, "count": 30,
	})
	check(not unit_id.is_empty(),
		"troop_units.source_type='tribal_warrior' accepted after migration 129")


# ---------------------------------------------------------------------------
# Phase 11D.5 polish tests
# ---------------------------------------------------------------------------

func test_spoils_distribute_to_units_per_warrior_split() -> void:
	_setup_basic()
	_insert_clanhold(500, 500)
	# Create two tribal-warrior units with different counts.
	var unit_a := TroopUnitRepository.create_unit({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_RULER,
		"assigned_domain_id": TEST_CLANHOLD,
		"source_type": "tribal_warrior",
		"troop_type": "tribal_infantry",
		"race": "human",
		"starting_count": 60, "count": 60,
		"monthly_wage_cp": 600,
	})
	var unit_b := TroopUnitRepository.create_unit({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_RULER,
		"assigned_domain_id": TEST_CLANHOLD,
		"source_type": "tribal_warrior",
		"troop_type": "tribal_infantry",
		"race": "human",
		"starting_count": 40, "count": 40,
		"monthly_wage_cp": 600,
	})
	# Distribute 100,000 cp across 100 total warriors → 60% to A, 40% to B.
	var dist := SiegeSpoilsResolver.distribute_to_units(
		{"total_spoils_cp": 100_000},
		[unit_a, unit_b])
	check(int(dist.get(unit_a, -1)) == 60_000,
		"unit A (60 warriors of 100) gets 60,000 cp; got %d" % int(dist.get(unit_a, -1)))
	check(int(dist.get(unit_b, -1)) == 40_000,
		"unit B (40 warriors of 100) gets 40,000 cp; got %d" % int(dist.get(unit_b, -1)))


func test_spoils_resets_qualifying_units() -> void:
	_setup_basic()
	_insert_clanhold(500, 500)
	# Unit with wage 600 cp/warrior, count 50 → required share = 30,000 cp.
	var unit_id := TroopUnitRepository.create_unit({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_RULER,
		"assigned_domain_id": TEST_CLANHOLD,
		"source_type": "tribal_warrior",
		"troop_type": "tribal_infantry",
		"race": "human",
		"starting_count": 50, "count": 50,
		"monthly_wage_cp": 600,
	})
	# Pre-set the counter to 2 to verify reset.
	TroopUnitRepository.update_unit(unit_id, {"months_without_qualifying_spoils": 2})
	# Apply distribution with 35,000 cp share → exceeds 30,000 threshold.
	var reset_ids := SiegeSpoilsResolver.apply_spoils_to_tribal_warriors(
		{unit_id: 35_000}, 1)
	check(unit_id in reset_ids,
		"unit with qualifying share is reset; reset_ids=%s" % str(reset_ids))
	var unit_after := TroopUnitRepository.get_unit(unit_id)
	check(int(unit_after.get("months_without_qualifying_spoils", -1)) == 0,
		"counter reset to 0; got %d" % int(unit_after.get("months_without_qualifying_spoils", -1)))


func test_spoils_skips_non_qualifying_units() -> void:
	_setup_basic()
	_insert_clanhold(500, 500)
	var unit_id := TroopUnitRepository.create_unit({
		"campaign_id": TEST_CAMPAIGN,
		"owner_character_id": TEST_RULER,
		"assigned_domain_id": TEST_CLANHOLD,
		"source_type": "tribal_warrior",
		"troop_type": "tribal_infantry",
		"race": "human",
		"starting_count": 50, "count": 50,
		"monthly_wage_cp": 600,
	})
	TroopUnitRepository.update_unit(unit_id, {"months_without_qualifying_spoils": 2})
	# Share below 30,000 threshold (50 × 600 = 30,000).
	var reset_ids := SiegeSpoilsResolver.apply_spoils_to_tribal_warriors(
		{unit_id: 15_000}, 1)
	check(not (unit_id in reset_ids),
		"non-qualifying unit NOT reset; got reset_ids=%s" % str(reset_ids))
	var unit_after := TroopUnitRepository.get_unit(unit_id)
	check(int(unit_after.get("months_without_qualifying_spoils", -1)) == 2,
		"counter unchanged at 2 for non-qualifying unit; got %d"
		% int(unit_after.get("months_without_qualifying_spoils", -1)))


# ---------------------------------------------------------------------------
# Phase 11D.5 per-race import tests
# ---------------------------------------------------------------------------

func test_composition_for_orc_120_warriors_matches_raw_table() -> void:
	var comp: Array = TribalWarriorRegistry.composition_for_race("orc", 120)
	# Per RAW ax_domains_of_chaos.xml:417-444 orc row:
	# light_infantry=44, heavy_infantry=30, bowmen=20, crossbowmen=20, beast_riders=6.
	check(comp.size() == 5, "orc composition has 5 troop_types; got %d" % comp.size())
	var by_type: Dictionary = {}
	for row_v in comp:
		var row: Dictionary = row_v
		by_type[str(row.get("troop_type", ""))] = int(row.get("count", 0))
	check(int(by_type.get("light_infantry", 0)) == 44,
		"orc 120: 44 light_infantry; got %d" % int(by_type.get("light_infantry", 0)))
	check(int(by_type.get("heavy_infantry", 0)) == 30,
		"orc 120: 30 heavy_infantry; got %d" % int(by_type.get("heavy_infantry", 0)))
	check(int(by_type.get("bowmen", 0)) == 20,
		"orc 120: 20 bowmen; got %d" % int(by_type.get("bowmen", 0)))
	check(int(by_type.get("crossbowmen", 0)) == 20,
		"orc 120: 20 crossbowmen; got %d" % int(by_type.get("crossbowmen", 0)))
	check(int(by_type.get("beast_riders", 0)) == 6,
		"orc 120: 6 beast_riders; got %d" % int(by_type.get("beast_riders", 0)))


func test_composition_for_kobold_levy_is_all_light_infantry() -> void:
	# Kobolds: 120 light_infantry per RAW (single troop-type race).
	var comp: Array = TribalWarriorRegistry.composition_for_race("kobold", 120)
	check(comp.size() == 1, "kobold composition has 1 row; got %d" % comp.size())
	check(String(comp[0].get("troop_type", "")) == "light_infantry",
		"kobold is all light_infantry")
	check(int(comp[0].get("count", 0)) == 120,
		"kobold 120 = 120 light_infantry; got %d" % int(comp[0].get("count", 0)))


func test_composition_for_unknown_race_returns_empty() -> void:
	var comp: Array = TribalWarriorRegistry.composition_for_race("not_a_real_race", 120)
	check(comp.is_empty(), "unknown race returns empty composition")


func test_inferred_race_for_beastman_clanhold_is_orc() -> void:
	_setup_basic()
	_insert_clanhold(500, 500)  # establishment_method='clanhold_annex' → beastman → orc default
	var race: String = TribalWarriorRegistry.inferred_tribal_race_for_domain(TEST_CLANHOLD)
	check(race == "orc",
		"beastman clanhold inference → orc; got %s" % race)


func test_inferred_race_for_kin_clanhold_is_jutland() -> void:
	_setup_basic()
	# Insert a kin clanhold (METHOD_CLEAR).
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, alignment, religion, effective_religion,
			 domain_style, establishment_method, established_calendar_day,
			 available_tribal_warriors)
		VALUES (?, ?, 'Kin Clanhold', ?, 'wilderness', 500, 'lawful',
		        'sun-cult', 'sun-cult', 'clanhold', 'clear', 1, 500)
	""", [TEST_CLANHOLD, TEST_CAMPAIGN, TEST_RULER])
	var race: String = TribalWarriorRegistry.inferred_tribal_race_for_domain(TEST_CLANHOLD)
	check(race == "jutland",
		"kin clanhold (METHOD_CLEAR) inference → jutland; got %s" % race)


func test_morale_modifier_for_steadfast_is_plus_one() -> void:
	check(TribalWarriorRegistry.base_morale_modifier_for_domain_morale(3) == 1,
		"morale +3 (Steadfast) → +1 modifier")
	check(TribalWarriorRegistry.base_morale_modifier_for_domain_morale(4) == 1,
		"morale +4 (Stalwart) → +1 modifier")


func test_morale_modifier_for_demoralized_is_minus_one() -> void:
	check(TribalWarriorRegistry.base_morale_modifier_for_domain_morale(-1) == -1,
		"morale -1 (Demoralized) → -1 modifier")
	check(TribalWarriorRegistry.base_morale_modifier_for_domain_morale(-3) == -1,
		"morale -3 (Defiant) → -1 modifier")
	check(TribalWarriorRegistry.base_morale_modifier_for_domain_morale(0) == 0,
		"morale 0 (Apathetic) → 0 modifier (no penalty)")
	check(TribalWarriorRegistry.base_morale_modifier_for_domain_morale(2) == 0,
		"morale +2 (Dedicated) → 0 modifier")
