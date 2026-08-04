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
	test_levy_caps_at_available_plus_the_excess_allowance()
	test_levy_rejects_civilized_domain()
	test_levy_rejects_non_ruler()
	test_levy_rejects_when_both_the_pool_and_the_excess_allowance_are_empty()
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
	# Per-race stat table (2026-08-01)
	test_stats_for_matches_raw_per_race()
	test_every_composition_pair_resolves_to_a_raw_row()
	test_beast_riders_are_race_specific_and_carnivorous()
	test_ogre_units_are_sixty_strong()
	test_composition_rows_carry_per_race_stats()
	test_levied_units_keep_their_troop_type_base_morale()
	test_levy_chunks_at_the_raw_unit_size()
	# Unit Loyalty rolls (migration 212 + UnitLoyaltyResolver)
	test_unit_loyalty_bands_match_the_raw_table()
	test_loyalty_modifier_is_morale_plus_calamity_penalty_only()
	test_situational_modifier_is_additive_and_not_a_calamity()
	test_loyalty_duplicate_calamities_collapse()
	test_loyalty_fanatic_never_results_from_going_without_pay()
	test_fanatic_grants_plus_one_not_plus_two_on_later_rolls()
	test_two_consecutive_grudging_results_end_service()
	test_grudging_run_resets_on_a_loyal_result()
	test_departure_returns_warriors_to_the_clanhold_and_chronicles_it()
	test_departure_does_not_overfill_the_pool_past_peasant_families()
	test_departing_warriors_are_lost_when_the_clanhold_is_gone()
	test_a_succession_pending_clanhold_still_takes_its_warriors_back()
	test_loyalty_roll_rejects_a_departed_unit_and_an_empty_calamity_list()
	# 3-month-spoils trigger → loyalty roll (Jedidiah errata 2026-08-01)
	test_three_month_spoils_tick_fires_a_loyalty_roll()
	test_two_month_spoils_tick_does_not_roll()
	# "Without pay for a month" calamity (TroopPayShortfallResolver, 2026-08-02)
	test_pay_shortfall_is_zero_when_funds_cover_the_wage_bill()
	test_pay_shortfall_designates_cheapest_units_first()
	test_pay_shortfall_designates_everyone_when_the_domain_can_pay_nothing()
	test_pay_shortfall_ignores_by_value_only_units()
	test_pay_shortfall_spans_every_assignment_kind_and_source_type()
	test_pay_shortfall_custom_designator_replaces_cheapest_first()
	test_pay_shortfall_tops_up_a_designator_that_under_covers()
	test_unpaid_designation_alone_fires_a_loyalty_roll()
	test_unpaid_and_spoils_calamities_make_one_combined_roll()
	# Excess levy + standing levy penalties (Jedidiah 2026-08-03)
	test_levy_cap_is_two_per_ten_families()
	test_levy_morale_penalty_bands_match_raw()
	test_levy_revenue_reduction_is_one_family_per_levied_peasant()
	test_excess_levy_reduces_revenue_by_the_levied_family_count()
	test_excess_levy_spawns_flagged_units_and_leaves_the_free_pool_alone()
	test_excess_levy_is_capped_and_does_not_stack_across_levies()
	test_free_levy_is_taken_before_excess()
	test_population_loss_releases_excess_over_the_shrunken_cap()
	test_militia_now_carry_the_standing_levy_penalties()
	test_levy_morale_penalty_reaches_base_morale()
	# Population-loss release (RAW ax_domains_of_chaos.xml:402, GDD §3.2)
	test_standing_down_excess_warriors_does_not_resurrect_dead_slots()
	test_excess_warriors_departing_on_loyalty_do_not_refill_the_pool()
	test_population_loss_releases_dormant_warriors_first()
	test_population_loss_force_stands_down_levied_lowest_tier_first()
	test_population_loss_restores_the_pool_invariant_and_chronicles_it()
	test_population_loss_is_a_no_op_when_the_pool_already_fits()
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


func test_levy_caps_at_available_plus_the_excess_allowance() -> void:
	# REWRITTEN 2026-08-03. This test used to assert the levy was capped at the
	# dormant pool and the remainder simply refused. Per Jedidiah's ruling that
	# is no longer the behaviour: RAW ax_domains_of_chaos.xml:399 lets a
	# chieftain levy past the free 1-per-family allotment, capped at the militia
	# allowance of 2 per 10 families (daw_armies_recruitment.xml:428) and paid
	# for in domain revenue and morale. The ceiling still exists — it just moved.
	_setup_basic()
	_insert_clanhold(500, 50)  # 50 dormant warriors, 500 families
	var result: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 200, "domain_id": TEST_CLANHOLD}), null)
	# 50 free + (500/10)*2 = 100 excess = 150. The 200 requested is still capped.
	check(int(result.get("count", 0)) == 150,
		"levy capped at free 50 + excess 100 = 150; got %d" % int(result.get("count", 0)))
	check(int(result.get("free_count", -1)) == 50, "the 50 dormant went first")
	check(int(result.get("excess_count", -1)) == 100, "the excess allowance supplied 100")
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(int(pool.get("available", -1)) == 0,
		"available drained to 0; got %d" % int(pool.get("available", -1)))
	check(bool(pool.get("pool_invariant_ok", false)),
		"the free-allotment invariant survives an excess levy")


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


func test_levy_rejects_when_both_the_pool_and_the_excess_allowance_are_empty() -> void:
	# REWRITTEN 2026-08-03 alongside the test above. An empty dormant pool alone
	# is no longer a refusal — the chieftain can reach into the excess allowance.
	# A refusal now requires BOTH to be exhausted, which a sub-10-family clanhold
	# achieves naturally: (9/10)*2 == 0 excess room.
	_setup_basic()
	_insert_clanhold(9, 0)
	var result: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 100, "domain_id": TEST_CLANHOLD}), null)
	check(String(result.get("blocked_reason", "")) == "pool_empty",
		"no pool and no excess allowance rejects the levy; got blocked_reason=%s"
		% str(result.get("blocked_reason", "")))
	_cleanup()

	# Control: the SAME empty pool on a domain large enough to have an excess
	# allowance now SUCCEEDS. Without this the test above would pass just as
	# happily if the excess path had never been wired at all.
	_setup_basic()
	_insert_clanhold(500, 0)
	var with_room: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 100, "domain_id": TEST_CLANHOLD}), null)
	check(String(with_room.get("blocked_reason", "")) == "",
		"an empty pool with excess room is NOT a refusal; got blocked_reason=%s"
		% str(with_room.get("blocked_reason", "")))
	check(int(with_room.get("excess_count", 0)) == 100,
		"all 100 came from the excess allowance, got %d"
		% int(with_room.get("excess_count", 0)))


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


# ---------------------------------------------------------------------------
# Per-race stat table (2026-08-01)
# ---------------------------------------------------------------------------

## RAW per-creature wage + battle rating for every (race, troop_type) pair the
## composition table can levy, re-transcribed here from
## `rules/daw_campaigns_troop_tables_summary.xml` §troop_tables so the test
## fails loudly if the production table drifts. Human rows L101-186, beastman
## rows L187-262; L9 states these ratings are per creature.
##
## Format: {race: {troop_type: [wage_cp, br_per_warrior, supply_cp, unit_size]}}
const _RAW_STATS := {
	# --- human cultures (jutland / iv_kingdom / skysos share the human table) ---
	"jutland": {
		"light_infantry":   [600,  0.008, 200, 120],
		"heavy_infantry":   [1200, 0.017, 200, 120],
		"bowmen":           [900,  0.013, 200, 120],
	},
	"iv_kingdom": {
		"light_infantry":   [600,  0.008, 200, 120],
		"hunters":          [400,  0.006, 200, 120],  # LI F/G/H "Hunters" @4gp
		"bowmen":           [900,  0.013, 200, 120],
	},
	"skysos": {
		"light_infantry":   [600,  0.008, 200, 120],
		"composite_bowmen": [1800, 0.025, 200, 120],  # Longbowmen B, composite bow
		"light_cavalry":    [3000, 0.061, 1600, 60],
		"horse_archers":    [4500, 0.082, 1600, 60],
		"medium_cavalry":   [4500, 0.082, 1600, 60],
	},
	# --- beastmen ---
	"kobold": {
		"light_infantry":   [200,  0.003, 200, 120],
	},
	"goblin": {
		"light_infantry":   [300,  0.004, 200, 120],
		"slingers":         [300,  0.004, 200, 120],
		"bowmen":           [300,  0.004, 200, 120],
		"beast_riders":     [1500, 0.107, 6400, 60],  # Wolf Riders, carnivorous mounts
	},
	"orc": {
		"light_infantry":   [600,  0.008, 200, 120],
		"heavy_infantry":   [900,  0.013, 200, 120],
		"bowmen":           [600,  0.008, 200, 120],
		"crossbowmen":      [1200, 0.017, 200, 120],
		"beast_riders":     [3300, 0.131, 6400, 60],  # Boar Riders
	},
	"hobgoblin": {
		"light_infantry":   [1200, 0.017, 200, 120],
		"heavy_infantry":   [1500, 0.021, 200, 120],
		"longbowmen":       [2500, 0.035, 200, 120],
		"light_cavalry":    [4500, 0.082, 1600, 60],
		"medium_cavalry":   [5500, 0.095, 1600, 60],
		"horse_archers":    [7500, 0.124, 1600, 60],
	},
	"gnoll": {
		"light_infantry":   [1800, 0.025, 200, 120],
		"heavy_infantry":   [2400, 0.033, 200, 120],
		"longbowmen":       [4000, 0.055, 200, 120],
	},
	"lizardman": {
		"light_infantry":   [2700, 0.036, 200, 120],
		"heavy_infantry":   [4500, 0.061, 200, 120],
	},
	"bugbear": {
		"light_infantry":   [3600, 0.050, 200, 120],
		"heavy_infantry":   [5000, 0.069, 200, 120],
	},
	"ogre": {
		# Large creatures — 60-strong units at the 60-unit supply rate.
		"light_infantry":   [4000, 0.077, 1600, 60],
		"heavy_infantry":   [8000, 0.131, 1600, 60],
	},
}


func test_stats_for_matches_raw_per_race() -> void:
	for race in _RAW_STATS.keys():
		var by_type: Dictionary = _RAW_STATS[race]
		for troop_type in by_type.keys():
			var expected: Array = by_type[troop_type]
			var stats: Dictionary = TribalWarriorRegistry.stats_for(String(race), String(troop_type))
			check(not stats.is_empty(),
				"%s/%s: stats_for returned empty" % [race, troop_type])
			if stats.is_empty():
				continue
			check(int(stats.get("wage_cp", -1)) == int(expected[0]),
				"%s/%s: wage_cp expected %d; got %d" % [
					race, troop_type, int(expected[0]), int(stats.get("wage_cp", -1))])
			check(is_equal_approx(float(stats.get("br_per_warrior", -1.0)), float(expected[1])),
				"%s/%s: br_per_warrior expected %f; got %f" % [
					race, troop_type, float(expected[1]), float(stats.get("br_per_warrior", -1.0))])
			check(int(stats.get("supply_cp", -1)) == int(expected[2]),
				"%s/%s: supply_cp expected %d; got %d" % [
					race, troop_type, int(expected[2]), int(stats.get("supply_cp", -1))])
			check(int(stats.get("unit_size", -1)) == int(expected[3]),
				"%s/%s: unit_size expected %d; got %d" % [
					race, troop_type, int(expected[3]), int(stats.get("unit_size", -1))])
	print("  stats_for_matches_raw_per_race: OK")


## The load-bearing invariant: every (race, troop_type) the composition table
## can produce must resolve to a real RAW row, so no levy ever silently falls
## back to the DEFAULT_* constants (which are human light infantry).
func test_every_composition_pair_resolves_to_a_raw_row() -> void:
	for race in TribalWarriorRegistry.VALID_TRIBAL_RACES:
		var comp: Array = TribalWarriorRegistry.composition_for_race(String(race), 120)
		check(not comp.is_empty(), "%s: composition_for_race(120) should be non-empty" % race)
		for row_v in comp:
			var row: Dictionary = row_v
			var troop_type: String = String(row.get("troop_type", ""))
			var stats: Dictionary = TribalWarriorRegistry.stats_for(String(race), troop_type)
			check(not stats.is_empty(),
				"%s/%s is levied by the composition table but has no RAW stat row" % [
					race, troop_type])
	print("  every_composition_pair_resolves_to_a_raw_row: OK")


## Beast riders are the sharpest per-race divergence and were the entry that
## surfaced this bug: one race-agnostic 0.025 stood in for goblin Wolf Riders
## (0.107 @15gp) and orc Boar Riders (0.131 @33gp) alike — 4-5× too low. Their
## supply is 4× a normal squadron's because the mounts are carnivores (RAW
## L274: 960gp/week per 60 riders).
func test_beast_riders_are_race_specific_and_carnivorous() -> void:
	var goblin: Dictionary = TribalWarriorRegistry.stats_for("goblin", "beast_riders")
	var orc: Dictionary = TribalWarriorRegistry.stats_for("orc", "beast_riders")
	check(is_equal_approx(float(goblin.get("br_per_warrior", 0.0)), 0.107),
		"goblin Wolf Riders BR should be RAW 0.107; got %f" % float(goblin.get("br_per_warrior", 0.0)))
	check(is_equal_approx(float(orc.get("br_per_warrior", 0.0)), 0.131),
		"orc Boar Riders BR should be RAW 0.131; got %f" % float(orc.get("br_per_warrior", 0.0)))
	check(not is_equal_approx(float(goblin.get("br_per_warrior", 0.0)),
			float(orc.get("br_per_warrior", 0.0))),
		"goblin and orc beast riders must NOT share one rating")
	# Explicit guard against the race-agnostic regression.
	for race in ["goblin", "orc"]:
		var stats: Dictionary = TribalWarriorRegistry.stats_for(String(race), "beast_riders")
		check(not is_equal_approx(float(stats.get("br_per_warrior", 0.0)), 0.025),
			"%s beast_riders is back to the old race-agnostic 0.025" % race)
		check(int(stats.get("supply_cp", 0)) == 6400,
			"%s beast riders pay the carnivore supply rate 6400cp; got %d" % [
				race, int(stats.get("supply_cp", 0))])
	print("  beast_riders_are_race_specific_and_carnivorous: OK")


## RAW L273 sizes a unit at 60 for cavalry OR LARGE CREATURES. Ogres are large,
## so ogre infantry — which is not cavalry — still forms 60-strong units and
## pays the 60-unit supply rate.
func test_ogre_units_are_sixty_strong() -> void:
	for troop_type in ["light_infantry", "heavy_infantry"]:
		var stats: Dictionary = TribalWarriorRegistry.stats_for("ogre", String(troop_type))
		check(int(stats.get("unit_size", 0)) == 60,
			"ogre %s unit_size should be 60 (large creature); got %d" % [
				troop_type, int(stats.get("unit_size", 0))])
		check(not bool(stats.get("is_cavalry", true)),
			"ogre %s is infantry, not cavalry" % troop_type)
		check(int(stats.get("supply_cp", 0)) == 1600,
			"ogre %s pays the 60-unit supply rate; got %d" % [
				troop_type, int(stats.get("supply_cp", 0))])
	# And an ogre is ~10× a kobold — the spread the race-agnostic table erased.
	var ogre_li: float = float(TribalWarriorRegistry.stats_for("ogre", "light_infantry").get("br_per_warrior", 0.0))
	var kobold_li: float = float(TribalWarriorRegistry.stats_for("kobold", "light_infantry").get("br_per_warrior", 0.0))
	check(ogre_li > kobold_li * 20.0,
		"ogre light infantry (%f) should dwarf kobold (%f) per RAW" % [ogre_li, kobold_li])
	print("  ogre_units_are_sixty_strong: OK")


## composition_for_race must carry the per-race stats through into its rows —
## that Array is what LevyTribalWarriorsHandler turns into troop_units.
func test_composition_rows_carry_per_race_stats() -> void:
	var goblin: Array = TribalWarriorRegistry.composition_for_race("goblin", 120)
	var ogre: Array = TribalWarriorRegistry.composition_for_race("ogre", 120)
	var goblin_li: Dictionary = _row_for_type(goblin, "light_infantry")
	var ogre_li: Dictionary = _row_for_type(ogre, "light_infantry")
	check(not goblin_li.is_empty() and not ogre_li.is_empty(),
		"both races should levy light_infantry")
	if goblin_li.is_empty() or ogre_li.is_empty():
		return
	check(is_equal_approx(float(goblin_li.get("br_per_warrior", 0.0)), 0.004),
		"goblin LI row BR should be 0.004; got %f" % float(goblin_li.get("br_per_warrior", 0.0)))
	check(is_equal_approx(float(ogre_li.get("br_per_warrior", 0.0)), 0.077),
		"ogre LI row BR should be 0.077; got %f" % float(ogre_li.get("br_per_warrior", 0.0)))
	check(int(goblin_li.get("wage_cp", 0)) == 300 and int(ogre_li.get("wage_cp", 0)) == 4000,
		"wages must be per-race too (goblin 300cp, ogre 4000cp); got %d / %d" % [
			int(goblin_li.get("wage_cp", 0)), int(ogre_li.get("wage_cp", 0))])
	print("  composition_rows_carry_per_race_stats: OK")


## RAW `ax_domains_of_chaos.xml` §tribal_warrior_morale: "Tribal warriors use
## the base morale of their troop type", plus a ONE-TIME ±1 from the domain's
## own morale. The levy handler previously stored the domain modifier alone,
## dropping the troop type's morale entirely — so a kobold levy (RAW -2) and an
## ogre levy (RAW +2) came out identical. [Jedidiah ruling 2026-08-01: base
## morale is the troop's; leader effects are modifiers, not baked-in values.]
func test_levied_units_keep_their_troop_type_base_morale() -> void:
	# Per-race base morale is carried on every composition row.
	var expected_base := {
		"kobold": -2, "goblin": -1, "orc": 0,
		"hobgoblin": 0, "gnoll": 0, "lizardman": 2, "bugbear": 2, "ogre": 2,
	}
	for race in expected_base.keys():
		var comp: Array = TribalWarriorRegistry.composition_for_race(String(race), 120)
		var li: Dictionary = _row_for_type(comp, "light_infantry")
		check(not li.is_empty(), "%s should levy light_infantry" % race)
		if li.is_empty():
			continue
		check(int(li.get("base_morale", 99)) == int(expected_base[race]),
			"%s light_infantry base_morale expected %d; got %d" % [
				race, int(expected_base[race]), int(li.get("base_morale", 99))])
	# Beast riders are the brave ones: RAW gives wolf/boar riders +2.
	for race in ["goblin", "orc"]:
		var riders: Dictionary = TribalWarriorRegistry.stats_for(String(race), "beast_riders")
		check(int(riders.get("base_morale", 99)) == 2,
			"%s beast_riders base_morale should be +2; got %d" % [
				race, int(riders.get("base_morale", 99))])

	# End-to-end: a levied unit's stored morale is base + the domain modifier,
	# not the modifier alone. The fixture clanhold infers race 'orc' (base 0),
	# so assert against the registry rather than a bare literal.
	_setup_basic()
	_insert_clanhold(500, 500)
	var result: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 120, "domain_id": TEST_CLANHOLD}), null)
	var ids: Array = result.get("unit_ids", [])
	check(not ids.is_empty(), "levy should create unit rows")
	var domain: Dictionary = CampaignRepository.get_domain(TEST_CLANHOLD)
	var modifier: int = TribalWarriorRegistry.base_morale_modifier_for_domain_morale(
		int(domain.get("morale", 0)))
	var saw_nonzero: bool = false
	for uid_v in ids:
		var unit: Dictionary = TroopUnitRepository.get_unit(String(uid_v))
		var race: String = String(unit.get("race", ""))
		var troop_type: String = String(unit.get("troop_type", ""))
		var stats: Dictionary = TribalWarriorRegistry.stats_for(race, troop_type)
		var expected: int = int(stats.get("base_morale", 0)) + modifier
		check(int(unit.get("morale", 99)) == expected,
			"%s/%s morale should be base %d + domain modifier %d = %d; got %d" % [
				race, troop_type, int(stats.get("base_morale", 0)), modifier,
				expected, int(unit.get("morale", 99))])
		if int(unit.get("morale", 0)) != 0:
			saw_nonzero = true
	# The fixture clanhold is orc at neutral domain morale, so most rows are
	# legitimately 0 either way — the orc beast_riders row (RAW +2) is what
	# actually discriminates against the old "store the modifier alone"
	# behaviour. Assert we saw it, so this test cannot silently go vacuous.
	check(saw_nonzero,
		"orc levy should include a non-zero-morale row (beast_riders, RAW +2)")
	print("  levied_units_keep_their_troop_type_base_morale: OK")


## RAW `daw_campaigns_troop_tables_summary.xml:273` sizes a unit at 120 for
## infantry but 60 for cavalry OR LARGE CREATURES. The levy handler used a flat
## 120-warrior cap, so beast riders and every ogre troop type were chunked into
## 120-strong rows RAW does not permit.
func test_levy_chunks_at_the_raw_unit_size() -> void:
	# No row from a levy may exceed its own RAW unit size.
	for race in TribalWarriorRegistry.VALID_TRIBAL_RACES:
		# 600 warriors forces chunking for every troop type in every race.
		var comp: Array = TribalWarriorRegistry.composition_for_race(String(race), 600)
		for row_v in comp:
			var row: Dictionary = row_v
			var troop_type: String = String(row.get("troop_type", ""))
			var expected_size: int = TribalWarriorRegistry.unit_size_for(
				String(race), troop_type)
			check(expected_size == 60 or expected_size == 120,
				"%s/%s: unit_size should be 60 or 120; got %d" % [
					race, troop_type, expected_size])
			check(int(row.get("unit_size", 0)) == expected_size,
				"%s/%s: composition row unit_size %d != %d" % [
					race, troop_type, int(row.get("unit_size", 0)), expected_size])

	# End-to-end: levy 600 ogres and confirm every spawned row is <= 60.
	# Ogres are large creatures, so even their INFANTRY forms 60-strong units.
	_setup_basic()
	_insert_clanhold(600, 600)
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET establishment_method = 'clanhold_annex' WHERE id = ?",
		[TEST_CLANHOLD])
	var comp_ogre: Array = TribalWarriorRegistry.composition_for_race("ogre", 600)
	check(not comp_ogre.is_empty(), "ogre composition should be non-empty")
	for row_v in comp_ogre:
		var row: Dictionary = row_v
		check(int(row.get("unit_size", 0)) == 60,
			"ogre %s should be a 60-strong unit; got %d" % [
				String(row.get("troop_type", "")), int(row.get("unit_size", 0))])

	# And the handler honours it: levy from the fixture (orc) and assert no
	# spawned row exceeds its troop type's RAW unit size. Orc beast_riders are
	# 60-cap; the infantry types are 120-cap.
	var result: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 600, "domain_id": TEST_CLANHOLD}), null)
	var ids: Array = result.get("unit_ids", [])
	check(not ids.is_empty(), "levy of 600 should create rows")
	var checked_a_60: bool = false
	for uid_v in ids:
		var unit: Dictionary = TroopUnitRepository.get_unit(String(uid_v))
		var cap: int = TribalWarriorRegistry.unit_size_for(
			String(unit.get("race", "")), String(unit.get("troop_type", "")))
		check(int(unit.get("count", 0)) <= cap,
			"%s row has %d warriors, over its RAW unit size %d" % [
				String(unit.get("troop_type", "")), int(unit.get("count", 0)), cap])
		if cap == 60:
			checked_a_60 = true
	check(checked_a_60,
		"orc levy should include a 60-cap troop type (beast_riders) so this test is not vacuous")
	print("  levy_chunks_at_the_raw_unit_size: OK")


func _row_for_type(composition: Array, troop_type: String) -> Dictionary:
	for row_v in composition:
		var row: Dictionary = row_v
		if String(row.get("troop_type", "")) == troop_type:
			return row
	return {}


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


# ---------------------------------------------------------------------------
# Unit Loyalty (migration 212 + UnitLoyaltyResolver)
#
# RAW: rules/daw_armies_recruitment.xml:93-109 (mechanic) + :265-275 (table),
# triggered per rules/ax_domains_of_chaos.xml:454-456.
# ---------------------------------------------------------------------------

## Deterministic 2d6 seam. Returns each queued total in order; the last value
## repeats once the queue drains, so a test that rolls more often than it
## queued still fails on its assertion rather than on a null.
class _FakeDice:
	var _queue: Array[int] = []
	var _last: int = 7
	var rolls_made: int = 0

	func _init(totals: Array) -> void:
		for t in totals:
			_queue.append(int(t))

	func roll(_count: int, _sides: int) -> int:
		rolls_made += 1
		if _queue.is_empty():
			return _last
		_last = _queue.pop_front()
		return _last


## Insert a tribal-warrior troop unit and return its id.
func _insert_tw_unit(count: int, morale: int, tier: String = "average",
		troop_type: String = "light_infantry") -> String:
	var unit_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO troop_units
			(id, campaign_id, owner_character_id, assigned_domain_id,
			 source_type, troop_type, race, tier, starting_count, count,
			 battle_rating, monthly_wage_cp, monthly_supply_cp, monthly_cost_cp,
			 morale, assignment_kind, status)
		VALUES (?, ?, ?, ?, 'tribal_warrior', ?, 'orc', ?, ?, ?,
		        1.0, 60000, 20000, 80000, ?, 'garrison', 'active')
	""", [unit_id, TEST_CAMPAIGN, TEST_RULER, TEST_CLANHOLD,
		troop_type, tier, count, count, morale])
	return unit_id


func test_unit_loyalty_bands_match_the_raw_table() -> void:
	# RAW rules/daw_armies_recruitment.xml:270-274.
	check(UnitLoyaltyResolver.outcome_for_total(-3)
		== UnitLoyaltyResolver.OUTCOME_ENMITY, "total -3 → Enmity (2- band)")
	check(UnitLoyaltyResolver.outcome_for_total(2)
		== UnitLoyaltyResolver.OUTCOME_ENMITY, "total 2 → Enmity")
	check(UnitLoyaltyResolver.outcome_for_total(3)
		== UnitLoyaltyResolver.OUTCOME_RESIGNATION, "total 3 → Resignation")
	check(UnitLoyaltyResolver.outcome_for_total(5)
		== UnitLoyaltyResolver.OUTCOME_RESIGNATION, "total 5 → Resignation")
	check(UnitLoyaltyResolver.outcome_for_total(6)
		== UnitLoyaltyResolver.OUTCOME_GRUDGING, "total 6 → Grudging Loyalty")
	check(UnitLoyaltyResolver.outcome_for_total(8)
		== UnitLoyaltyResolver.OUTCOME_GRUDGING, "total 8 → Grudging Loyalty")
	check(UnitLoyaltyResolver.outcome_for_total(9)
		== UnitLoyaltyResolver.OUTCOME_LOYALTY, "total 9 → Loyalty")
	check(UnitLoyaltyResolver.outcome_for_total(11)
		== UnitLoyaltyResolver.OUTCOME_LOYALTY, "total 11 → Loyalty")
	check(UnitLoyaltyResolver.outcome_for_total(12)
		== UnitLoyaltyResolver.OUTCOME_FANATIC, "total 12 → Fanatic loyalty")
	check(UnitLoyaltyResolver.outcome_for_total(20)
		== UnitLoyaltyResolver.OUTCOME_FANATIC, "total 20+ → Fanatic loyalty")


func test_loyalty_modifier_is_morale_plus_calamity_penalty_only() -> void:
	# RAW :99 "2d6 plus morale and adjustments" + :100 "-2 per calamity after
	# the first". RAW :775 explicitly excludes the officer morale modifier from
	# Unit Loyalty rolls, so nothing else may enter this stack.
	_setup_basic()
	_insert_clanhold(500, 500)
	var unit_id: String = _insert_tw_unit(100, 2)

	var one: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_OUT_OF_SUPPLY], 30, _FakeDice.new([7]))
	check(bool(one.get("ok", false)), "single-calamity roll resolved")
	check(int(one.get("calamity_penalty", -99)) == 0,
		"one calamity → no extra-calamity penalty, got %d" % int(one.get("calamity_penalty", -99)))
	check(int(one.get("modifier", -99)) == 2,
		"modifier == unit morale (2) alone, got %d" % int(one.get("modifier", -99)))
	check(int(one.get("total", 0)) == 9, "2d6 7 + 2 = 9, got %d" % int(one.get("total", 0)))

	var three: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_OUT_OF_SUPPLY,
		 UnitLoyaltyResolver.CALAMITY_ROUT,
		 UnitLoyaltyResolver.CALAMITY_CASUALTIES],
		31, _FakeDice.new([7]))
	check(int(three.get("calamity_penalty", 0)) == -4,
		"three calamities → -2 × 2 = -4, got %d" % int(three.get("calamity_penalty", 0)))
	check(int(three.get("modifier", 0)) == -2,
		"morale 2 + (-4) = -2, got %d" % int(three.get("modifier", 0)))
	_cleanup()


func test_situational_modifier_is_additive_and_not_a_calamity() -> void:
	# RAW :99's "adjustments" term, added for RAW
	# daw_campaigning_armies.xml:367 — "Unsupplied units suffer an ADDITIONAL -1
	# penalty on their loyalty rolls." Additional to the out-of-supply calamity,
	# and -1 rather than the -2 a second calamity would cost, so it must sit
	# outside the extra-calamity stack.
	_setup_basic()
	_insert_clanhold(500, 500)
	var unit_id: String = _insert_tw_unit(100, 2)

	var starving: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_OUT_OF_SUPPLY], 30,
		_FakeDice.new([7]), -1)
	check(int(starving.get("situational_modifier", 0)) == -1,
		"the adjustment is reported, got %d" % int(starving.get("situational_modifier", 0)))
	check(int(starving.get("calamity_penalty", -99)) == 0,
		"one calamity still means no extra-calamity penalty, got %d"
			% int(starving.get("calamity_penalty", -99)))
	check(int(starving.get("modifier", -99)) == 1,
		"morale 2 plus the -1 adjustment = 1, got %d" % int(starving.get("modifier", -99)))
	check(int(starving.get("total", 0)) == 8, "2d6 7 + 1 = 8, got %d" % int(starving.get("total", 0)))

	# Default of 0 keeps every pre-existing caller's arithmetic identical.
	var unchanged: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_OUT_OF_SUPPLY], 31, _FakeDice.new([7]))
	check(int(unchanged.get("situational_modifier", -99)) == 0,
		"omitted adjustment defaults to 0, got %d" % int(unchanged.get("situational_modifier", -99)))
	check(int(unchanged.get("modifier", -99)) == 2,
		"morale 2 alone when no adjustment is passed, got %d" % int(unchanged.get("modifier", -99)))
	_cleanup()


func test_loyalty_duplicate_calamities_collapse() -> void:
	# Two reports of the same calamity are one calamity, not grounds for -2.
	_setup_basic()
	_insert_clanhold(500, 500)
	var unit_id: String = _insert_tw_unit(100, 0)
	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT,
		 UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([7]))
	check(int(res.get("calamity_penalty", -99)) == 0,
		"duplicate calamity collapses → no penalty, got %d" % int(res.get("calamity_penalty", -99)))
	check((res.get("calamities", []) as Array).size() == 1,
		"duplicate collapsed to a single calamity entry")
	_cleanup()


func test_loyalty_fanatic_never_results_from_going_without_pay() -> void:
	# RAW :107 — "fanatic loyalty can never result from going without pay and
	# becomes ordinary loyalty in that case."
	_setup_basic()
	_insert_clanhold(500, 500)

	var unpaid_unit: String = _insert_tw_unit(100, 4)
	var unpaid: Dictionary = UnitLoyaltyResolver.roll_loyalty(unpaid_unit,
		[UnitLoyaltyResolver.CALAMITY_UNPAID], 30, _FakeDice.new([12]))
	check(String(unpaid.get("outcome", "")) == UnitLoyaltyResolver.OUTCOME_LOYALTY,
		"12+ while unpaid → downgraded to Loyalty, got %s" % String(unpaid.get("outcome", "")))
	check(bool(unpaid.get("fanatic_suppressed_by_unpaid", false)),
		"suppression is reported so the log can explain the downgrade")
	check(not bool(unpaid.get("loyalty_is_fanatic", true)),
		"suppressed result does not set the sticky fanatic flag")

	# Control: the SAME roll on a different calamity DOES produce Fanatic, so
	# this cannot pass merely because 16 missed the band.
	var supplied_unit: String = _insert_tw_unit(100, 4)
	var supplied: Dictionary = UnitLoyaltyResolver.roll_loyalty(supplied_unit,
		[UnitLoyaltyResolver.CALAMITY_OUT_OF_SUPPLY], 30, _FakeDice.new([12]))
	check(String(supplied.get("outcome", "")) == UnitLoyaltyResolver.OUTCOME_FANATIC,
		"same 12 + morale 4 on a non-pay calamity → Fanatic, got %s"
			% String(supplied.get("outcome", "")))
	check(bool(supplied.get("loyalty_is_fanatic", false)), "fanatic flag persisted")
	_cleanup()


func test_fanatic_grants_plus_one_not_plus_two_on_later_rolls() -> void:
	# RAW :107 — "all future loyalty rolls are at +1". The henchman ladder uses
	# +2; this pins that unit loyalty did not inherit that number.
	_setup_basic()
	_insert_clanhold(500, 500)
	var unit_id: String = _insert_tw_unit(100, 4)

	UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_OUT_OF_SUPPLY], 30, _FakeDice.new([12]))
	var row: Dictionary = TroopUnitRepository.get_unit(unit_id)
	check(int(row.get("loyalty_is_fanatic", 0)) == 1, "unit is fanatic after a 12+")

	var later: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 60, _FakeDice.new([7]))
	check(int(later.get("fanatic_bonus_applied", 0)) == 1,
		"fanatic bonus is +1 (NOT the henchman ladder's +2), got %d"
			% int(later.get("fanatic_bonus_applied", 0)))
	check(int(later.get("modifier", 0)) == 5,
		"morale 4 + fanatic 1 = 5, got %d" % int(later.get("modifier", 0)))
	_cleanup()


func test_two_consecutive_grudging_results_end_service() -> void:
	# RAW :105 — "if rolled on two consecutive morale rolls they leave service."
	_setup_basic()
	_insert_clanhold(500, 400)
	var unit_id: String = _insert_tw_unit(100, 0)

	var first: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([7]))
	check(String(first.get("outcome", "")) == UnitLoyaltyResolver.OUTCOME_GRUDGING,
		"first roll is Grudging")
	check(not bool(first.get("departs", true)), "one Grudging result does NOT end service")
	check(int(first.get("consecutive_grudging", 0)) == 1,
		"grudging run == 1 after the first, got %d" % int(first.get("consecutive_grudging", 0)))

	var second: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 60, _FakeDice.new([7]))
	check(String(second.get("outcome", "")) == UnitLoyaltyResolver.OUTCOME_GRUDGING,
		"second roll is Grudging")
	check(bool(second.get("departs", false)), "two CONSECUTIVE Grudging results end service")
	check(String(second.get("departure_kind", "")) == UnitLoyaltyResolver.DEPARTURE_GRUDGING,
		"departure_kind records the grudging-twice cause")
	var row: Dictionary = TroopUnitRepository.get_unit(unit_id)
	check(String(row.get("status", "")) == "departed", "unit row marked departed")
	_cleanup()


func test_grudging_run_resets_on_a_loyal_result() -> void:
	# The run must be CONSECUTIVE — a Loyalty result in between clears it, so a
	# unit cannot accumulate two grudging results a year apart and vanish.
	_setup_basic()
	_insert_clanhold(500, 400)
	var unit_id: String = _insert_tw_unit(100, 0)

	UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([7]))
	var loyal: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 60, _FakeDice.new([10]))
	check(String(loyal.get("outcome", "")) == UnitLoyaltyResolver.OUTCOME_LOYALTY,
		"middle roll is Loyalty")
	check(int(loyal.get("consecutive_grudging", -1)) == 0, "Loyalty resets the grudging run")

	var third: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 90, _FakeDice.new([7]))
	check(String(third.get("outcome", "")) == UnitLoyaltyResolver.OUTCOME_GRUDGING,
		"third roll is Grudging")
	check(not bool(third.get("departs", true)),
		"a non-consecutive second Grudging does NOT end service")
	_cleanup()


func test_departure_returns_warriors_to_the_clanhold_and_chronicles_it() -> void:
	# RAW rules/ax_domains_of_chaos.xml:461 — departing warriors "return to
	# their villages if possible"; per Jedidiah (2026-08-01) that means the
	# clanhold's dormant pool, and they may be levied again later.
	_setup_basic()
	_insert_clanhold(500, 300)
	var unit_id: String = _insert_tw_unit(150, 0)

	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([2]))
	check(String(res.get("outcome", "")) == UnitLoyaltyResolver.OUTCOME_ENMITY,
		"2- → Enmity")
	check(bool(res.get("departs", false)), "Enmity ends service immediately")
	check(int(res.get("returned_to_pool", 0)) == 150,
		"all 150 survivors returned to the dormant pool, got %d"
			% int(res.get("returned_to_pool", 0)))

	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(int(pool.get("available", 0)) == 450,
		"available 300 + 150 returned = 450, got %d" % int(pool.get("available", 0)))
	check(int(pool.get("levied", -1)) == 0, "departed unit no longer counts as levied")
	check(bool(pool.get("pool_invariant_ok", false)),
		"available + levied <= peasant_families still holds after the return")

	var entries: Array = DepartureLogRecorder.list_for_domain(TEST_CLANHOLD, 20)
	var found: bool = false
	for e in entries:
		if String((e as Dictionary).get("event_type", "")) == "tribal_warriors_loyalty_failed":
			found = true
	check(found, "a tribal_warriors_loyalty_failed departure-log line was written")
	_cleanup()


func test_departure_does_not_overfill_the_pool_past_peasant_families() -> void:
	# The §3 invariant binds the return too: a clanhold cannot absorb more
	# warriors than it has households to put them in.
	_setup_basic()
	_insert_clanhold(100, 90)
	var unit_id: String = _insert_tw_unit(50, 0)

	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([2]))
	check(int(res.get("returned_to_pool", -1)) == 10,
		"only 10 of 50 fit under the 100-family ceiling, got %d"
			% int(res.get("returned_to_pool", -1)))
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(int(pool.get("available", 0)) == 100, "available capped at peasant_families")
	check(bool(pool.get("pool_invariant_ok", false)), "invariant holds")
	_cleanup()


func test_departing_warriors_are_lost_when_the_clanhold_is_gone() -> void:
	# RAW rules/ax_domains_of_chaos.xml:461-462 — warriors return to their
	# villages "if possible"; if return is not possible they become brigands or
	# mercenaries. Per Jedidiah (2026-08-01) the clanhold must "still exist",
	# and per GDD §7.4 + Q-TW-8 v1 does NOT materialise a brigand force — the
	# warriors simply leave the pool accounting.
	_setup_basic()
	_insert_clanhold(500, 100)
	var unit_id: String = _insert_tw_unit(150, 0)
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET lifecycle_state = 'abandoned' WHERE id = ?", [TEST_CLANHOLD])

	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([2]))
	check(bool(res.get("departs", false)), "Enmity still ends service")
	check(int(res.get("returned_to_pool", -1)) == 0,
		"an abandoned clanhold takes nobody back, got %d" % int(res.get("returned_to_pool", -1)))
	var domain: Dictionary = CampaignRepository.get_domain(TEST_CLANHOLD)
	check(int(domain.get("available_tribal_warriors", -1)) == 100,
		"dormant pool untouched, got %d" % int(domain.get("available_tribal_warriors", -1)))
	_cleanup()


func test_a_succession_pending_clanhold_still_takes_its_warriors_back() -> void:
	# ruined_stronghold / succession_pending domains keep ticking (migration
	# 122) — a clanhold whose chieftain just died is exactly the sort of place
	# warriors go home to. Only abandoned / salted_to_ruin close the door.
	_setup_basic()
	_insert_clanhold(500, 100)
	var unit_id: String = _insert_tw_unit(150, 0)
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET lifecycle_state = 'succession_pending' WHERE id = ?",
		[TEST_CLANHOLD])

	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([2]))
	check(int(res.get("returned_to_pool", -1)) == 150,
		"succession-pending clanhold still receives its warriors, got %d"
			% int(res.get("returned_to_pool", -1)))
	_cleanup()


func test_loyalty_roll_rejects_a_departed_unit_and_an_empty_calamity_list() -> void:
	_setup_basic()
	_insert_clanhold(500, 500)
	var unit_id: String = _insert_tw_unit(100, 0)

	var none: Dictionary = UnitLoyaltyResolver.roll_loyalty(
		unit_id, [], 30, _FakeDice.new([7]))
	check(not bool(none.get("ok", true)), "no calamity → no roll")
	check(String(none.get("error", "")) == "no_calamity", "reports why")

	TroopUnitRepository.update_unit(unit_id, {"status": "departed"})
	var gone: Dictionary = UnitLoyaltyResolver.roll_loyalty(unit_id,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([7]))
	check(not bool(gone.get("ok", true)), "a departed unit does not roll loyalty")
	_cleanup()


# ---------------------------------------------------------------------------
# Population-loss release (RAW ax_domains_of_chaos.xml:402, GDD §3.2)
# ---------------------------------------------------------------------------

class _StubRunner:
	var _cid: String = ""
	func _init(cid: String) -> void:
		_cid = cid
	func get_campaign_id() -> String:
		return _cid


func test_three_month_spoils_tick_fires_a_loyalty_roll() -> void:
	# Per Jedidiah (2026-08-01) the RAW "morale roll" at
	# ax_domains_of_chaos.xml:456 is errata'd to a straight LOYALTY roll. Before
	# this build the tick emitted a signal and stopped — the counter stuck at 3
	# and nothing rolled. The roll outcome itself is random here (the tick owns
	# its own dice), so assert the two things that are deterministic either way:
	# the chronicle line exists, and the counter was consumed.
	_setup_basic()
	_insert_clanhold(500, 400)
	var unit_id: String = _insert_tw_unit(100, 0)
	CampaignRepository.db.query_with_bindings(
		"UPDATE troop_units SET months_without_qualifying_spoils = 2 WHERE id = ?",
		[unit_id])

	var handlers := DomainHandlers.new(_StubRunner.new(TEST_CAMPAIGN))
	handlers._tick_unit_loyalty(TEST_CLANHOLD, 84)

	var row: Dictionary = TroopUnitRepository.get_unit(unit_id)
	check(int(row.get("months_without_qualifying_spoils", -1)) == 0,
		"the roll consumed the 3-month counter (was 3 and stuck before), got %d"
			% int(row.get("months_without_qualifying_spoils", -1)))

	var entries: Array = DepartureLogRecorder.list_for_domain(TEST_CLANHOLD, 20)
	var saw_trigger: bool = false
	for e in entries:
		var et: String = String((e as Dictionary).get("event_type", ""))
		if et == "tribal_warriors_morale_check_triggered":
			saw_trigger = true
	check(saw_trigger,
		"the 3-month trigger now writes its departure-log line (it never did before)")
	_cleanup()


func test_two_month_spoils_tick_does_not_roll() -> void:
	# The counter must reach 3. At 2 the tick only increments.
	_setup_basic()
	_insert_clanhold(500, 400)
	var unit_id: String = _insert_tw_unit(100, 0)

	var handlers := DomainHandlers.new(_StubRunner.new(TEST_CAMPAIGN))
	handlers._tick_unit_loyalty(TEST_CLANHOLD, 28)

	var row: Dictionary = TroopUnitRepository.get_unit(unit_id)
	check(int(row.get("months_without_qualifying_spoils", -1)) == 1,
		"counter incremented to 1, got %d"
			% int(row.get("months_without_qualifying_spoils", -1)))
	check(String(row.get("status", "")) == "active", "no departure at 1 month")
	var entries: Array = DepartureLogRecorder.list_for_domain(TEST_CLANHOLD, 20)
	for e in entries:
		var et: String = String((e as Dictionary).get("event_type", ""))
		check(et != "tribal_warriors_morale_check_triggered",
			"no trigger line before the counter reaches 3")
	_cleanup()


# ---------------------------------------------------------------------------
# "Going without pay for a month" — RAW ax_domains_of_chaos.xml:455 +
# daw_armies_recruitment.xml:98. Pay is aggregate, so the unpaid units are
# designated ex post facto from the shortfall (TroopPayShortfallResolver).
# ---------------------------------------------------------------------------

## Insert an arbitrary payroll unit on the test clanhold and return its id.
## Unlike _insert_tw_unit this exposes wage / cost / assignment_kind, which are
## exactly what the shortfall designation reads.
func _insert_payroll_unit(wage_cp: int, cost_cp: int,
		source_type: String = "tribal_warrior",
		assignment_kind: String = "garrison",
		morale: int = 0, count: int = 100) -> String:
	var unit_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO troop_units
			(id, campaign_id, owner_character_id, assigned_domain_id,
			 source_type, troop_type, race, tier, starting_count, count,
			 battle_rating, monthly_wage_cp, monthly_supply_cp, monthly_cost_cp,
			 morale, assignment_kind, status)
		VALUES (?, ?, ?, ?, ?, 'light_infantry', 'orc', 'average', ?, ?,
		        1.0, ?, 0, ?, ?, ?, 'active')
	""", [unit_id, TEST_CAMPAIGN, TEST_RULER, TEST_CLANHOLD,
		source_type, count, count, wage_cp, cost_cp, morale, assignment_kind])
	return unit_id


func test_pay_shortfall_is_zero_when_funds_cover_the_wage_bill() -> void:
	_setup_basic()
	_insert_clanhold(500, 400)
	_insert_payroll_unit(10_000, 12_000)
	_insert_payroll_unit(30_000, 32_000)

	var res: Dictionary = TroopPayShortfallResolver.resolve_for_domain(
		TEST_CLANHOLD, 40_000)
	check(int(res.get("wage_bill_cp", -1)) == 40_000,
		"wage bill sums monthly_wage_cp, got %d" % int(res.get("wage_bill_cp", -1)))
	check(int(res.get("shortfall_cp", -1)) == 0,
		"exactly covering the bill is not a shortfall, got %d" % int(res.get("shortfall_cp", -1)))
	check((res.get("unpaid_unit_ids", []) as Array).is_empty(),
		"nobody is designated unpaid when payroll clears")
	_cleanup()


func test_pay_shortfall_designates_cheapest_units_first() -> void:
	# Jedidiah 2026-08-01: cheapest-first (lowest monthly_wage_cp) until the
	# designated wages cover the shortfall. Bill 60,000 with 25,000 on hand
	# leaves a 35,000 shortfall; the 10k and 20k units total 30,000, so the
	# 30k unit is pulled in as well and the 40k unit stays paid.
	_setup_basic()
	_insert_clanhold(500, 400)
	var cheap: String = _insert_payroll_unit(10_000, 11_000)
	var mid: String = _insert_payroll_unit(20_000, 21_000)
	var dear: String = _insert_payroll_unit(30_000, 31_000)

	var res: Dictionary = TroopPayShortfallResolver.resolve_for_domain(
		TEST_CLANHOLD, 25_000)
	var unpaid: Array = res.get("unpaid_unit_ids", [])
	check(int(res.get("shortfall_cp", 0)) == 35_000,
		"60,000 bill - 25,000 on hand = 35,000 short, got %d" % int(res.get("shortfall_cp", 0)))
	check(unpaid.size() == 3,
		"10k + 20k = 30k does not cover 35k, so the 30k unit joins them; got %d units" % unpaid.size())
	check(unpaid.has(cheap) and unpaid.has(mid) and unpaid.has(dear),
		"all three cheapest units are designated")
	check(int(res.get("unpaid_wage_cp", 0)) == 60_000,
		"designated wages are reported, got %d" % int(res.get("unpaid_wage_cp", 0)))
	check(String(res.get("designator", "")) == TroopPayShortfallResolver.DESIGNATOR_CHEAPEST_FIRST,
		"NPC domains get cheapest-first with no player input")

	# Control: a smaller shortfall stops at the cheapest unit alone. Without
	# the accumulate-until-covered loop this would designate the same set.
	var small: Dictionary = TroopPayShortfallResolver.resolve_for_domain(
		TEST_CLANHOLD, 55_000)
	var few: Array = small.get("unpaid_unit_ids", [])
	check(few.size() == 1 and few.has(cheap),
		"a 5,000 shortfall is covered by the cheapest unit alone, got %d units" % few.size())
	_cleanup()


func test_pay_shortfall_designates_everyone_when_the_domain_can_pay_nothing() -> void:
	# treasury_cp is unclamped and carries deficits forward, so the funds figure
	# can arrive negative. It must floor at 0, not inflate the shortfall past
	# the bill (which would still designate everyone, but would report a
	# shortfall larger than any amount of unpaid wages could account for).
	_setup_basic()
	_insert_clanhold(500, 400)
	_insert_payroll_unit(10_000, 11_000)
	_insert_payroll_unit(20_000, 21_000)

	var res: Dictionary = TroopPayShortfallResolver.resolve_for_domain(
		TEST_CLANHOLD, -500_000)
	check(int(res.get("funds_available_cp", -1)) == 0,
		"negative funds floor at 0, got %d" % int(res.get("funds_available_cp", -1)))
	check(int(res.get("shortfall_cp", 0)) == 30_000,
		"shortfall never exceeds the wage bill, got %d" % int(res.get("shortfall_cp", 0)))
	check((res.get("unpaid_unit_ids", []) as Array).size() == 2,
		"a domain that can pay nobody designates everybody")
	_cleanup()


func test_pay_shortfall_ignores_by_value_only_units() -> void:
	# RAW acore_axioms §garrison L229-230 — faithful followers and trained
	# militia count toward garrison expense by value without money changing
	# hands, and daw_armies_recruitment.xml:481 bars religious fanatics from
	# calamity loyalty rolls outright. monthly_cost_cp == 0 is how this project
	# already marks them (GarrisonExpenditureCalculator), and there is no pay
	# for them to go without.
	_setup_basic()
	_insert_clanhold(500, 400)
	var paid: String = _insert_payroll_unit(10_000, 11_000)
	var by_value: String = _insert_payroll_unit(40_000, 0, "follower")

	var res: Dictionary = TroopPayShortfallResolver.resolve_for_domain(
		TEST_CLANHOLD, 0)
	check(int(res.get("wage_bill_cp", -1)) == 10_000,
		"the cost-0 unit is off the payroll, got a bill of %d" % int(res.get("wage_bill_cp", -1)))
	var unpaid: Array = res.get("unpaid_unit_ids", [])
	check(unpaid.has(paid) and not unpaid.has(by_value),
		"only the genuinely-waged unit can go unpaid")
	_cleanup()


func test_pay_shortfall_spans_every_assignment_kind_and_source_type() -> void:
	# Levied tribal warriors are minted assignment_kind='available' and
	# ExtractionResistanceRouter flips garrison units to 'on_campaign' for the
	# length of a muster, so filtering on assignment_kind the way
	# GarrisonExpenditureCalculator does would make this rule a no-op for the
	# only source type that rolls. The bill also spans source types: the ruler
	# weighs the whole roster when deciding who to stiff.
	_setup_basic()
	_insert_clanhold(500, 400)
	var available: String = _insert_payroll_unit(10_000, 11_000, "tribal_warrior", "available")
	var campaigning: String = _insert_payroll_unit(20_000, 21_000, "tribal_warrior", "on_campaign")
	var merc: String = _insert_payroll_unit(30_000, 31_000, "mercenary", "garrison")

	var res: Dictionary = TroopPayShortfallResolver.resolve_for_domain(
		TEST_CLANHOLD, 0)
	check(int(res.get("wage_bill_cp", -1)) == 60_000,
		"every active waged unit is on the bill, got %d" % int(res.get("wage_bill_cp", -1)))
	var unpaid: Array = res.get("unpaid_unit_ids", [])
	check(unpaid.has(available) and unpaid.has(campaigning) and unpaid.has(merc),
		"assignment_kind and source_type do not gate the DESIGNATION (only the roll)")
	_cleanup()


func test_pay_shortfall_custom_designator_replaces_cheapest_first() -> void:
	# The seam a future player-facing "choose who goes unpaid" option plugs
	# into: a Callable(shortfall_cp, units) -> Array of unit ids. Here it picks
	# the single most expensive unit, which cheapest-first would never choose.
	_setup_basic()
	_insert_clanhold(500, 400)
	var cheap: String = _insert_payroll_unit(10_000, 11_000)
	var dear: String = _insert_payroll_unit(50_000, 51_000)

	var pick_dearest: Callable = func(_shortfall_cp: int, units: Array) -> Array:
		var best_id: String = ""
		var best_wage: int = -1
		for u in units:
			var wage: int = int((u as Dictionary).get("monthly_wage_cp", 0))
			if wage > best_wage:
				best_wage = wage
				best_id = String((u as Dictionary).get("id", ""))
		return [best_id]

	var res: Dictionary = TroopPayShortfallResolver.resolve_for_domain(
		TEST_CLANHOLD, 20_000, pick_dearest)
	var unpaid: Array = res.get("unpaid_unit_ids", [])
	check(int(res.get("shortfall_cp", 0)) == 40_000,
		"60,000 bill - 20,000 on hand = 40,000 short, got %d" % int(res.get("shortfall_cp", 0)))
	check(unpaid.size() == 1 and unpaid.has(dear),
		"the override's pick stands; it covers 40,000 on its own")
	check(not unpaid.has(cheap), "cheapest-first did not run")
	check(String(res.get("designator", "")) == TroopPayShortfallResolver.DESIGNATOR_CUSTOM,
		"the result reports which designation rule produced it")
	_cleanup()


func test_pay_shortfall_tops_up_a_designator_that_under_covers() -> void:
	# A designation that leaves part of the shortfall unaccounted for is not a
	# preference — that money is gone regardless. Keep the caller's picks and
	# make up the difference cheapest-first rather than silently pretending the
	# remainder was paid.
	_setup_basic()
	_insert_clanhold(500, 400)
	var cheap: String = _insert_payroll_unit(10_000, 11_000)
	var mid: String = _insert_payroll_unit(20_000, 21_000)
	var dear: String = _insert_payroll_unit(30_000, 31_000)

	var pick_only_mid: Callable = func(_shortfall_cp: int, _units: Array) -> Array:
		return [mid]

	# Bill 60,000, nothing on hand → 60,000 short; the single pick covers
	# 20,000, so both remaining units are pulled in.
	var res: Dictionary = TroopPayShortfallResolver.resolve_for_domain(
		TEST_CLANHOLD, 0, pick_only_mid)
	var unpaid: Array = res.get("unpaid_unit_ids", [])
	check(unpaid.size() == 3, "the shortfall is fully accounted for, got %d units" % unpaid.size())
	check(unpaid.has(mid) and unpaid.has(cheap) and unpaid.has(dear),
		"the caller's pick is kept and the rest topped up")
	check(String(res.get("designator", "")) == TroopPayShortfallResolver.DESIGNATOR_CUSTOM_TOPPED_UP,
		"the top-up is reported, not hidden")
	_cleanup()


func test_unpaid_designation_alone_fires_a_loyalty_roll() -> void:
	# The end-to-end wiring. Morale -20 puts every possible 2d6 result in the
	# 2- Enmity band, so the roll's outcome is deterministic even though the
	# tick owns its own dice: a unit that rolls departs, a unit that does not
	# roll stays active. The un-designated control unit is what makes this a
	# test of the unpaid trigger rather than of the tick running at all.
	_setup_basic()
	_insert_clanhold(500, 400)
	var unpaid_unit: String = _insert_payroll_unit(10_000, 11_000, "tribal_warrior", "garrison", -20)
	var control: String = _insert_payroll_unit(20_000, 21_000, "tribal_warrior", "garrison", -20)

	var handlers := DomainHandlers.new(_StubRunner.new(TEST_CAMPAIGN))
	handlers._tick_unit_loyalty(TEST_CLANHOLD, 56, [unpaid_unit])

	check(String(TroopUnitRepository.get_unit(unpaid_unit).get("status", "")) == "departed",
		"the designated-unpaid unit rolled and left service")
	check(String(TroopUnitRepository.get_unit(control).get("status", "")) == "active",
		"the unit that was still paid never rolled")

	# The spoils clock is a different calamity with its own counter; an unpaid
	# roll must not consume it (roll_loyalty resets it only for NO_SPOILS).
	check(int(TroopUnitRepository.get_unit(unpaid_unit).get(
			"months_without_qualifying_spoils", -1)) == 1,
		"the unpaid roll left the spoils counter alone, got %d"
			% int(TroopUnitRepository.get_unit(unpaid_unit).get(
				"months_without_qualifying_spoils", -1)))

	var calamities: Array = _departure_calamities_for(unpaid_unit)
	check(calamities.size() == 1 and calamities.has(
			UnitLoyaltyResolver.CALAMITY_UNPAID),
		"the departure was chronicled as the unpaid calamity alone, got %s" % str(calamities))
	_cleanup()


func test_unpaid_and_spoils_calamities_make_one_combined_roll() -> void:
	# RAW daw_armies_recruitment.xml:100 — "If troops are suffering more than
	# one calamity at once, apply -2 to the loyalty roll per calamity after the
	# first." A unit three months without spoils that ALSO went unpaid is
	# suffering both at once, so the monthly tick owes it one roll at -2, not
	# two independent rolls at full strength. Morale -20 forces the departure
	# so the chronicle line is guaranteed to exist.
	_setup_basic()
	_insert_clanhold(500, 400)
	var unit_id: String = _insert_payroll_unit(10_000, 11_000, "tribal_warrior", "garrison", -20)
	CampaignRepository.db.query_with_bindings(
		"UPDATE troop_units SET months_without_qualifying_spoils = 2 WHERE id = ?",
		[unit_id])

	var handlers := DomainHandlers.new(_StubRunner.new(TEST_CAMPAIGN))
	handlers._tick_unit_loyalty(TEST_CLANHOLD, 84, [unit_id])

	var failures: int = 0
	for e in DepartureLogRecorder.list_for_domain(TEST_CLANHOLD, 20):
		if String((e as Dictionary).get("event_type", "")) == "tribal_warriors_loyalty_failed":
			failures += 1
	check(failures == 1, "exactly one loyalty roll, not one per calamity; got %d" % failures)

	var calamities: Array = _departure_calamities_for(unit_id)
	check(calamities.size() == 2,
		"both calamities entered the same roll (worth -2), got %s" % str(calamities))
	check(calamities.has(UnitLoyaltyResolver.CALAMITY_NO_SPOILS)
			and calamities.has(UnitLoyaltyResolver.CALAMITY_UNPAID),
		"the roll carried the spoils stretch AND the unpaid month, got %s" % str(calamities))
	_cleanup()


## Pull the `calamities` metadata off the tribal_warriors_loyalty_failed line
## written for [param unit_id], or [] if the unit never departed.
func _departure_calamities_for(unit_id: String) -> Array:
	for e in DepartureLogRecorder.list_for_domain(TEST_CLANHOLD, 20):
		var entry: Dictionary = e
		if String(entry.get("event_type", "")) != "tribal_warriors_loyalty_failed":
			continue
		var details: Dictionary = entry.get("full_details", {})
		if String(details.get("troop_unit_id", "")) == unit_id:
			return details.get("calamities", [])
	return []


# ---------------------------------------------------------------------------
# Excess levy past the free 1-per-family allotment
# (RAW ax_domains_of_chaos.xml:398-399 + daw_armies_recruitment.xml:428-432;
#  Jedidiah 2026-08-03)
# ---------------------------------------------------------------------------

func test_levy_cap_is_two_per_ten_families() -> void:
	# RAW daw_armies_recruitment.xml:428 — "Up to 2 additional peasants per 10
	# families may be levied." Integer division mirrors LevyMilitiaHandler.
	check(LevyPenaltyCalculator.levy_cap_for_families(100) == 20,
		"100 families → 20 excess, got %d" % LevyPenaltyCalculator.levy_cap_for_families(100))
	check(LevyPenaltyCalculator.levy_cap_for_families(9) == 0,
		"under 10 families → no excess allowance")
	check(LevyPenaltyCalculator.levy_cap_for_families(0) == 0, "0 families → 0")
	check(LevyPenaltyCalculator.levy_cap_for_families(-5) == 0, "negative → 0, not negative")


func test_levy_morale_penalty_bands_match_raw() -> void:
	# RAW :430 — "1 or fewer militia per 10 families reduces domain morale by 1;
	# 2 per 10 families reduces domain morale by 2."
	check(LevyPenaltyCalculator.morale_penalty(0, 100) == 0, "nobody levied → no penalty")
	check(LevyPenaltyCalculator.morale_penalty(10, 100) == -1, "1 per 10 → -1")
	check(LevyPenaltyCalculator.morale_penalty(1, 100) == -1, "well under 1 per 10 → still -1")
	check(LevyPenaltyCalculator.morale_penalty(20, 100) == -2, "2 per 10 → -2")
	check(LevyPenaltyCalculator.morale_penalty(30, 100) == -2, "beyond 2 per 10 → still -2")
	check(LevyPenaltyCalculator.morale_penalty(15, 100) == -1,
		"between the bands stays at -1 until 2 per 10 is reached")


func test_levy_revenue_reduction_is_one_family_per_levied_peasant() -> void:
	# RAW :429 — "For each peasant levied, domain revenue is reduced by one family."
	check(LevyPenaltyCalculator.revenue_family_reduction(20, 100) == 20, "20 levied → 20 families")
	check(LevyPenaltyCalculator.revenue_family_reduction(0, 100) == 0, "none levied → none lost")
	check(LevyPenaltyCalculator.revenue_family_reduction(500, 100) == 100,
		"cannot lose more families than exist")


func test_excess_levy_reduces_revenue_by_the_levied_family_count() -> void:
	# The headline number from the ruling: 2 warriors per 10 families beyond the
	# free allotment = 1.2 warriors/family total and a 20% income cut.
	var domain := {"peasant_families": 100, "tax_rate_cp_per_family": 200,
		"domain_style": "clanhold"}
	var hexes: Array = [{"land_value": 5, "land_improvement_level": 0}]
	var full := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 1000, 0, 0, 0)
	var levied := DomainRevenueCalculator.calculate_monthly_revenue(domain, hexes, 1000, 0, 0, 20)
	check(int(levied.get("revenue_families_lost_to_levy", -1)) == 20,
		"20 families dropped out of the revenue base, got %d"
			% int(levied.get("revenue_families_lost_to_levy", -1)))
	check(int(levied.get("total", 0)) == int(full.get("total", 0)) * 80 / 100,
		"20 levied of 100 families → exactly 80%% of revenue (%d vs %d)"
			% [int(levied.get("total", 0)), int(full.get("total", 0))])
	# peasant_families itself must be untouched — they are under arms, not dead.
	check(int(domain.get("peasant_families", 0)) == 100,
		"the levy does not consume population")


func test_excess_levy_spawns_flagged_units_and_leaves_the_free_pool_alone() -> void:
	_setup_basic()
	# 100 families, pool already drained to 0 — so every warrior levied now is
	# excess. Cap is (100/10)*2 = 20.
	_insert_clanhold(100, 0)
	var res: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 20}), null)
	check(int(res.get("excess_count", 0)) == 20,
		"all 20 levied as excess, got %d" % int(res.get("excess_count", 0)))
	check(int(res.get("free_count", -1)) == 0, "nothing came from the empty free pool")

	var domain: Dictionary = CampaignRepository.get_domain(TEST_CLANHOLD)
	check(int(domain.get("available_tribal_warriors", -1)) == 0,
		"available_tribal_warriors was NOT driven negative, got %d"
			% int(domain.get("available_tribal_warriors", -1)))

	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(int(pool.get("excess_levied", 0)) == 20,
		"pool reports 20 excess under arms, got %d" % int(pool.get("excess_levied", 0)))
	check(int(pool.get("levied", -1)) == 0,
		"excess warriors do NOT count toward the free-allotment levied total")
	check(bool(pool.get("pool_invariant_ok", false)),
		"the free-allotment invariant still holds when the excess is used")
	check(LevyPenaltyCalculator.levied_peasants_for_domain(TEST_CLANHOLD) == 20,
		"the penalty calculator sees all 20 as peasants under arms")
	_cleanup()


func test_excess_levy_is_capped_and_does_not_stack_across_levies() -> void:
	_setup_basic()
	_insert_clanhold(100, 0)
	var first: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 500}), null)
	check(int(first.get("excess_count", 0)) == 20,
		"a 500-warrior request is capped at the 20-warrior excess allowance, got %d"
			% int(first.get("excess_count", 0)))

	# The cap is STANDING, so a second levy gets nothing.
	var second: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 20}), null)
	check(int(second.get("excess_count", 0)) == 0,
		"cap already consumed — second levy raises nobody, got %d"
			% int(second.get("excess_count", 0)))
	check(String(second.get("blocked_reason", "")) == "excess_levy_cap_reached",
		"blocked with the cap reason, got '%s'" % String(second.get("blocked_reason", "")))
	check(TribalWarriorRegistry.excess_levied_count(TEST_CLANHOLD) == 20,
		"still exactly 20 excess under arms")
	_cleanup()


func test_free_levy_is_taken_before_excess() -> void:
	# 100 families with 10 still dormant: a 25-warrior request should draw the
	# 10 free first and only then reach into the penalised allowance.
	_setup_basic()
	_insert_clanhold(100, 10)
	var res: Dictionary = LevyTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"count": 25}), null)
	check(int(res.get("free_count", -1)) == 10,
		"10 free warriors taken first, got %d" % int(res.get("free_count", -1)))
	check(int(res.get("excess_count", -1)) == 15,
		"remaining 15 come from the excess allowance, got %d" % int(res.get("excess_count", -1)))
	var domain: Dictionary = CampaignRepository.get_domain(TEST_CLANHOLD)
	check(int(domain.get("available_tribal_warriors", -1)) == 0,
		"the free pool was decremented by 10 only")
	check(LevyPenaltyCalculator.morale_penalty(15, 100) == -1,
		"15 per 100 families is the -1 band")
	_cleanup()


func test_population_loss_releases_excess_over_the_shrunken_cap() -> void:
	# The excess ceiling derives from peasant_families, so a shrink lowers it —
	# and that must fire even when the FREE side needs no release at all.
	_setup_basic()
	_insert_clanhold(100, 0)
	LevyTribalWarriorsHandler.on_complete(_state(TEST_RULER, {"count": 20}), null)
	check(TribalWarriorRegistry.excess_levied_count(TEST_CLANHOLD) == 20, "20 excess to start")

	var handlers := DomainHandlers.new(_StubRunner.new(TEST_CAMPAIGN))
	# 100 → 50 families. Free side: available 0 + free levied 0 = 0 <= 50, fine.
	# Excess cap falls from 20 to (50/10)*2 = 10, so 10 must go.
	var released: Dictionary = handlers._release_tribal_warriors_for_population_loss(
		TEST_CLANHOLD, 50, 0, 0, 40)
	check(int(released.get("released_excess_over_cap", -1)) == 10,
		"10 excess released down to the new cap of 10, got %d"
			% int(released.get("released_excess_over_cap", -1)))
	check(int(released.get("released_dormant", -1)) == 0, "free side untouched")
	check(int(released.get("released_levied", -1)) == 0, "free side untouched")
	check(TribalWarriorRegistry.excess_levied_count(TEST_CLANHOLD) == 10,
		"exactly the new cap remains under arms, got %d"
			% TribalWarriorRegistry.excess_levied_count(TEST_CLANHOLD))
	_cleanup()


func test_militia_now_carry_the_standing_levy_penalties() -> void:
	# Conventions §100 flagged these as unimplemented on 2026-07-04: a militia
	# levy was free until someone died. Closed 2026-08-03 (Jedidiah).
	_setup_basic()
	_insert_civilized(100)
	var unit_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO troop_units
			(id, campaign_id, owner_character_id, assigned_domain_id,
			 source_type, troop_type, race, tier, starting_count, count,
			 battle_rating, monthly_wage_cp, monthly_supply_cp, monthly_cost_cp,
			 morale, assignment_kind, status)
		VALUES (?, ?, ?, ?, 'militia', 'light_infantry', 'human', 'untrained',
		        20, 20, 0.16, 300, 0, 300, -2, 'garrison', 'active')
	""", [unit_id, TEST_CAMPAIGN, TEST_RULER, TEST_CIVILIZED])

	var pen: Dictionary = LevyPenaltyCalculator.penalties_for_domain(TEST_CIVILIZED, 100)
	check(int(pen.get("levied", 0)) == 20,
		"20 militia counted as peasants under arms, got %d" % int(pen.get("levied", 0)))
	check(int(pen.get("revenue_family_reduction", 0)) == 20, "20 families off the land")
	check(int(pen.get("morale_penalty", 0)) == -2, "2 per 10 families → -2 morale")

	# :431 — "These penalties remain until the militia is sent home."
	TroopUnitRepository.update_unit(unit_id, {"status": "departed"})
	var after: Dictionary = LevyPenaltyCalculator.penalties_for_domain(TEST_CIVILIZED, 100)
	check(int(after.get("levied", -1)) == 0, "sending them home relieves the penalty")
	check(int(after.get("morale_penalty", -1)) == 0, "morale penalty lifts too")
	_cleanup()


func test_levy_morale_penalty_reaches_base_morale() -> void:
	# The penalty is a STANDING condition (:431), so it belongs in base morale
	# alongside the classification and stronghold penalties, not the monthly
	# event-modifier sum.
	var domain := {"territory_type": "civilized", "peasant_families": 100}
	var ruler := {"cha_modifier": 0, "level": 1}
	var without: int = DomainMoraleResolver.resolve_base_morale(
		domain, ruler, 100000, 1000, 1000, 0, 0)
	var with_levy: int = DomainMoraleResolver.resolve_base_morale(
		domain, ruler, 100000, 1000, 1000, 0, -2)
	check(with_levy == without - 2,
		"a -2 levy penalty lands on base morale (%d vs %d)" % [with_levy, without])


func test_standing_down_excess_warriors_does_not_resurrect_dead_slots() -> void:
	# The bug this pins: excess warriors are ADDITIONAL peasants, not the
	# family's designated 1-per-family warrior, so the levy never decremented
	# `available_tribal_warriors` for them. Returning them must not increment
	# it. On a clanhold carrying SLACK from past casualties the refill cap is
	# not tight enough to save you — the slack is exactly the room it would
	# wrongly fill, resurrecting dead warriors against RAW
	# ax_domains_of_chaos.xml:404.
	_setup_basic()
	# 100 families, all 100 free warriors levied, then 50 of them die:
	# available 0, free levied 50, slack 50.
	_insert_clanhold(100, 0)
	var free_unit: String = _insert_tw_unit(50, 0)
	# 20 excess warriors on top.
	var excess_unit: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO troop_units
			(id, campaign_id, owner_character_id, assigned_domain_id,
			 source_type, troop_type, race, tier, starting_count, count,
			 battle_rating, monthly_wage_cp, monthly_supply_cp, monthly_cost_cp,
			 morale, assignment_kind, status, is_excess_levy)
		VALUES (?, ?, ?, ?, 'tribal_warrior', 'light_infantry', 'orc', 'average',
		        20, 20, 1.0, 60000, 20000, 80000, 0, 'garrison', 'active', 1)
	""", [excess_unit, TEST_CAMPAIGN, TEST_RULER, TEST_CLANHOLD])

	var before: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(int(before.get("slack", 0)) == 50,
		"fixture has 50 slack from casualties, got %d" % int(before.get("slack", 0)))

	StandDownTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"troop_unit_id": excess_unit, "count": 20}), null)

	var after: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(int(after.get("available", -1)) == 0,
		"standing down EXCESS warriors leaves the free pool at 0 — dead warriors stay dead; got %d"
			% int(after.get("available", -1)))
	check(int(after.get("slack", 0)) == 50,
		"the casualty slack is untouched, got %d" % int(after.get("slack", 0)))
	check(int(after.get("excess_levied", -1)) == 0, "the excess unit did stand down")

	# Control: standing down a FREE unit DOES refill, so the guard above is
	# scoped to excess rather than having broken stand-down outright.
	StandDownTribalWarriorsHandler.on_complete(
		_state(TEST_RULER, {"troop_unit_id": free_unit, "count": 50}), null)
	var final_pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(int(final_pool.get("available", 0)) == 50,
		"a FREE unit standing down still refills the pool, got %d"
			% int(final_pool.get("available", 0)))
	_cleanup()


func test_excess_warriors_departing_on_loyalty_do_not_refill_the_pool() -> void:
	# Same invariant on the loyalty-departure path.
	_setup_basic()
	_insert_clanhold(100, 0)
	_insert_tw_unit(50, 0)  # 50 free levied, 50 slack
	var excess_unit: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO troop_units
			(id, campaign_id, owner_character_id, assigned_domain_id,
			 source_type, troop_type, race, tier, starting_count, count,
			 battle_rating, monthly_wage_cp, monthly_supply_cp, monthly_cost_cp,
			 morale, assignment_kind, status, is_excess_levy)
		VALUES (?, ?, ?, ?, 'tribal_warrior', 'light_infantry', 'orc', 'average',
		        20, 20, 1.0, 60000, 20000, 80000, 0, 'garrison', 'active', 1)
	""", [excess_unit, TEST_CAMPAIGN, TEST_RULER, TEST_CLANHOLD])

	var res: Dictionary = UnitLoyaltyResolver.roll_loyalty(excess_unit,
		[UnitLoyaltyResolver.CALAMITY_ROUT], 30, _FakeDice.new([2]))
	check(bool(res.get("departs", false)), "Enmity ends service")
	check(int(res.get("returned_to_pool", -1)) == 0,
		"excess warriors return to the FIELDS, not the warrior pool; got %d"
			% int(res.get("returned_to_pool", -1)))
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(int(pool.get("available", -1)) == 0,
		"free pool untouched by an excess departure, got %d" % int(pool.get("available", -1)))
	_cleanup()


func test_population_loss_releases_dormant_warriors_first() -> void:
	# GDD §3.2 step 3a — dormant warriors go before anyone in service.
	_setup_basic()
	_insert_clanhold(500, 200)
	var unit_id: String = _insert_tw_unit(100, 0)
	var handlers := DomainHandlers.new(_StubRunner.new(TEST_CAMPAIGN))

	# 500 → 250 families. available 200 + levied 100 = 300; excess = 50.
	var released: Dictionary = handlers._release_tribal_warriors_for_population_loss(
		TEST_CLANHOLD, 250, 200, 100, 40)
	check(int(released.get("released_dormant", 0)) == 50,
		"all 50 came out of the dormant pool, got %d" % int(released.get("released_dormant", 0)))
	check(int(released.get("released_levied", -1)) == 0,
		"no unit in service was touched, got %d" % int(released.get("released_levied", -1)))
	check(int(released.get("new_available", -1)) == 150,
		"available 200 - 50 = 150, got %d" % int(released.get("new_available", -1)))
	var row: Dictionary = TroopUnitRepository.get_unit(unit_id)
	check(int(row.get("count", 0)) == 100, "levied unit still at full strength")
	check(String(row.get("status", "")) == "active", "levied unit still active")
	_cleanup()


func test_population_loss_force_stands_down_levied_lowest_tier_first() -> void:
	# GDD §3.2 step 3b — when the dormant pool cannot cover the shortfall, RAW's
	# "must be released" reaches into units already in service. Veterans are the
	# last warriors sent home.
	_setup_basic()
	_insert_clanhold(500, 20)
	var veteran: String = _insert_tw_unit(100, 0, "veteran")
	var untrained: String = _insert_tw_unit(100, 0, "untrained")
	var average: String = _insert_tw_unit(100, 0, "average")
	var handlers := DomainHandlers.new(_StubRunner.new(TEST_CAMPAIGN))

	# 500 → 150 families. available 20 + levied 300 = 320; excess = 170.
	# 20 dormant, then 150 from service: untrained 100 (emptied) then 50 of average.
	var released: Dictionary = handlers._release_tribal_warriors_for_population_loss(
		TEST_CLANHOLD, 150, 20, 300, 40)
	check(int(released.get("released_dormant", -1)) == 20,
		"dormant pool drained first, got %d" % int(released.get("released_dormant", -1)))
	check(int(released.get("released_levied", -1)) == 150,
		"remaining 150 taken from units in service, got %d" % int(released.get("released_levied", -1)))
	check(int(released.get("new_available", -1)) == 0, "dormant pool emptied")

	var u_row: Dictionary = TroopUnitRepository.get_unit(untrained)
	check(int(u_row.get("count", -1)) == 0, "untrained unit emptied first")
	check(String(u_row.get("status", "")) == "departed", "emptied unit marked departed")
	check(String(u_row.get("departure_kind", "")) == "released_for_population_loss",
		"departure_kind records the cause")
	var a_row: Dictionary = TroopUnitRepository.get_unit(average)
	check(int(a_row.get("count", -1)) == 50, "average unit took the remainder, got %d"
		% int(a_row.get("count", -1)))
	check(String(a_row.get("status", "")) == "active", "partially-released unit stays active")
	var v_row: Dictionary = TroopUnitRepository.get_unit(veteran)
	check(int(v_row.get("count", -1)) == 100, "veterans untouched — released LAST, got %d"
		% int(v_row.get("count", -1)))
	_cleanup()


func test_population_loss_restores_the_pool_invariant_and_chronicles_it() -> void:
	_setup_basic()
	_insert_clanhold(500, 100)
	_insert_tw_unit(300, 0)
	var handlers := DomainHandlers.new(_StubRunner.new(TEST_CAMPAIGN))

	# Before: 100 + 300 = 400 > 200 ceiling → invariant WOULD be violated.
	var released: Dictionary = handlers._release_tribal_warriors_for_population_loss(
		TEST_CLANHOLD, 200, 100, 300, 40)
	check(int(released.get("total", 0)) == 200,
		"400 - 200 ceiling = 200 released, got %d" % int(released.get("total", 0)))

	# Persist the new available exactly as _save_domain would, then assert the
	# invariant the registry reports.
	CampaignRepository.update_domain_monthly_state(TEST_CLANHOLD, {
		"peasant_families": 200,
		"available_tribal_warriors": int(released.get("new_available", 0)),
	})
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(TEST_CLANHOLD)
	check(bool(pool.get("pool_invariant_ok", false)),
		"available %d + levied %d <= families %d after release"
			% [int(pool.get("available", 0)), int(pool.get("levied", 0)),
			   int(pool.get("peasant_families", 0))])

	var entries: Array = DepartureLogRecorder.list_for_domain(TEST_CLANHOLD, 20)
	var found: bool = false
	for e in entries:
		var et: String = String((e as Dictionary).get("event_type", ""))
		if et == "tribal_warriors_released_for_population_loss":
			found = true
	check(found, "a tribal_warriors_released_for_population_loss log line was written")
	_cleanup()


func test_population_loss_is_a_no_op_when_the_pool_already_fits() -> void:
	# Shrinking to a ceiling the pool already respects releases nobody, and must
	# NOT write a log line about releasing zero warriors.
	_setup_basic()
	_insert_clanhold(500, 50)
	_insert_tw_unit(50, 0)
	var handlers := DomainHandlers.new(_StubRunner.new(TEST_CAMPAIGN))

	var released: Dictionary = handlers._release_tribal_warriors_for_population_loss(
		TEST_CLANHOLD, 400, 50, 50, 40)
	check(released.is_empty(), "100 warriors under a 400 ceiling → nothing released")
	var entries: Array = DepartureLogRecorder.list_for_domain(TEST_CLANHOLD, 20)
	for e in entries:
		var et: String = String((e as Dictionary).get("event_type", ""))
		check(et != "tribal_warriors_released_for_population_loss",
			"no spurious release log line when nothing was released")
	_cleanup()
