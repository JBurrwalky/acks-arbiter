extends "res://tests/test_suite_base.gd"

## Unit tests for the lazy lair-placement model (gdd-lair-discovery.md,
## 2026-05-27 redesign — supersedes the v1 eager-placement/lazy-discovery
## suite that lived in this file).
##
## Covers the repository + service + resolver layer:
##   * lairs CRUD (migration 152 shape) — create/get round-trip, creation
##     order, cleared counts, mark_lair_cleared idempotency.
##   * LairBudgetResolver — terrain-row mapping, RAW lairs_per_hex dice per
##     classification, "-" cells, <0 clamp
##     (le_wilderness_lair_rules.xml §securing_land L34-87).
##   * HexLairState — lazy budget roll-and-cache, unrevealed-types FIFO,
##     placed-count bookkeeping, §6.1 "Lairs: X/Y" display rules, §7
##     Build Stronghold gate.
##   * LairGenerator stub — in-lair population parsing + LairRecord shape.
##   * LairTypeResolver — `% In Lair > 0` re-roll guarantee.
##   * survey_progress upsert round-trip (table unchanged by the redesign).


const PARTY_PREFIX := "test_lairlazy_"
const CAMPAIGN_ID := "test_lairlazy_campaign"
const MAP_ID := "test_lairlazy_map"


# ---------------------------------------------------------------------------
# Fake DiceSystem — fixed return value, with call counting
# ---------------------------------------------------------------------------

class _FixedDice:
	extends RefCounted
	var _value: int = 20
	var calls: int = 0
	func _init(v: int = 20) -> void:
		_value = v
	func roll_digital(sides: int, count: int = 1, modifier: int = 0,
			_roll_type: String = "") -> RollResult:
		calls += 1
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		r.individual_results = []
		var total := 0
		for _i in range(count):
			r.individual_results.append(_value)
			total += _value
		r.raw_total = total
		r.modified_total = total + modifier
		r.natural_one = (_value == 1 and sides == 20 and count == 1)
		r.natural_max = (_value == sides and count == 1)
		return r


func run_all_tests() -> void:
	test_create_lair_round_trip_and_creation_order()
	test_cleared_counts_and_mark_cleared_idempotent()
	test_budget_resolver_terrain_rows()
	test_budget_resolver_dice_and_clamps()
	test_hex_lair_state_lazy_roll_caches()
	test_unrevealed_queue_fifo_and_placed_count()
	test_display_rules_and_stronghold_gate()
	test_lair_generator_population_parsing()
	test_lair_generator_record_shape()
	test_type_resolver_returns_lairing_creature()
	test_survey_progress_upsert_round_trip()
	if not has_failures():
		print("LairDiscovery: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_party_id(suffix: String) -> String:
	return PARTY_PREFIX + suffix


func _setup_fixture(party_id: String) -> void:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM survey_progress WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM hex_lair_state WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM lairs WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [MAP_ID])
	db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[CAMPAIGN_ID, "test lair lazy"])
	db.query_with_bindings(
		"INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale) " +
		"VALUES (?, ?, ?, ?)",
		[MAP_ID, CAMPAIGN_ID, "test_map", "regional_6mi"])
	db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[party_id, CAMPAIGN_ID, "Test Lazy Lair Party"])


func _cleanup_fixture(party_id: String) -> void:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM survey_progress WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM hex_lair_state WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM lairs WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [party_id])
	db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [MAP_ID])


func _place_lair(suffix: String, q: int, r: int, monster: String,
		created_at: int = 0) -> String:
	return CampaignRepository.create_lair({
		"lair_id": "test_lairlazy_lair_" + suffix,
		"campaign_id": CAMPAIGN_ID,
		"map_id": MAP_ID,
		"hex_q": q,
		"hex_r": r,
		"monster_group": monster,
		"monster_count": 5,
		"placed_via": "search",
		"created_at_round": created_at,
		"treasure_type": "E",
		"lair_layout_seed": 42,
	})


func _make_terrain(biome: String, elevation: String = "flat",
		civ: String = "wilderness", subtype: String = "") -> HexTerrainData:
	var t := HexTerrainData.new()
	t.biome = biome
	t.elevation = elevation
	t.civilization = civ
	t.biome_subtype = subtype
	return t


# ---------------------------------------------------------------------------
# lairs CRUD (migration 152)
# ---------------------------------------------------------------------------

func test_create_lair_round_trip_and_creation_order() -> void:
	var pid := _make_party_id("crud")
	_setup_fixture(pid)

	var id_b := _place_lair("crud_b", 3, 5, "orc", 20)
	var id_a := _place_lair("crud_a", 3, 5, "goblin", 10)
	check(not id_a.is_empty() and not id_b.is_empty(), "create_lair returns ids")

	var row: Dictionary = CampaignRepository.get_lair(id_a)
	check(String(row.get("monster_group", "")) == "goblin", "monster_group round-trips")
	check(String(row.get("placed_via", "")) == "search", "placed_via round-trips")
	check(int(row.get("created_at_round", -1)) == 10, "created_at_round round-trips")
	check(row.get("cleared_at_round") == null, "cleared_at_round starts null")
	check(String(row.get("treasure_type", "")) == "E", "treasure_type round-trips")

	var rows: Array = CampaignRepository.get_lairs_in_hex(CAMPAIGN_ID, MAP_ID, 3, 5)
	check(rows.size() == 2, "both lairs returned")
	check(String(rows[0].get("monster_group", "")) == "goblin",
		"creation order: earlier created_at_round first")

	_cleanup_fixture(pid)


func test_cleared_counts_and_mark_cleared_idempotent() -> void:
	var pid := _make_party_id("clear")
	_setup_fixture(pid)
	var id_a := _place_lair("clear_a", 7, 7, "ogre")
	_place_lair("clear_b", 7, 7, "troll")

	check(CampaignRepository.count_lairs_in_hex(CAMPAIGN_ID, MAP_ID, 7, 7) == 2,
		"total = 2")
	check(CampaignRepository.count_cleared_lairs_in_hex(CAMPAIGN_ID, MAP_ID, 7, 7) == 0,
		"cleared starts 0")
	check(CampaignRepository.count_uncleared_lairs_in_hex(CAMPAIGN_ID, MAP_ID, 7, 7) == 2,
		"uncleared starts 2")

	check(CampaignRepository.mark_lair_cleared(id_a, 500), "mark_lair_cleared succeeds")
	check(CampaignRepository.count_cleared_lairs_in_hex(CAMPAIGN_ID, MAP_ID, 7, 7) == 1,
		"cleared = 1 after marking")
	check(CampaignRepository.count_uncleared_lairs_in_hex(CAMPAIGN_ID, MAP_ID, 7, 7) == 1,
		"uncleared drops to 1")

	# Idempotent: a second clear keeps the original round.
	check(CampaignRepository.mark_lair_cleared(id_a, 999), "re-clear returns true")
	check(int(CampaignRepository.get_lair(id_a).get("cleared_at_round", -1)) == 500,
		"original cleared_at_round retained")

	_cleanup_fixture(pid)


# ---------------------------------------------------------------------------
# LairBudgetResolver (RAW lairs_per_hex)
# ---------------------------------------------------------------------------

func test_budget_resolver_terrain_rows() -> void:
	check(LairBudgetResolver.terrain_row_key(_make_terrain("clear")) == "clear_grass",
		"flat clear → clear_grass")
	check(LairBudgetResolver.terrain_row_key(_make_terrain("clear", "hills")) == "scrub_hills",
		"clear hills → scrub_hills")
	check(LairBudgetResolver.terrain_row_key(
		_make_terrain("clear", "flat", "wilderness", "clear_scrub")) == "scrub_hills",
		"scrub subtype → scrub_hills")
	check(LairBudgetResolver.terrain_row_key(_make_terrain("desert")) == "barren_desert",
		"desert → barren_desert")
	check(LairBudgetResolver.terrain_row_key(_make_terrain("woods")) == "mountains_woods",
		"woods → mountains_woods")
	check(LairBudgetResolver.terrain_row_key(
		_make_terrain("clear", "mountains")) == "mountains_woods",
		"mountains → mountains_woods")
	check(LairBudgetResolver.terrain_row_key(_make_terrain("swamp")) == "swamp",
		"swamp → swamp")
	check(LairBudgetResolver.terrain_row_key(_make_terrain("jungle")) == "jungle",
		"jungle → jungle")
	var ocean := _make_terrain("clear")
	ocean.water = HexTerrainData.WATER_OCEAN
	check(LairBudgetResolver.terrain_row_key(ocean) == "",
		"ocean → no lair row")


func test_budget_resolver_dice_and_clamps() -> void:
	# Wilderness mountains/woods = 2d4 → FixedDice(3) rolls 3+3 = 6.
	var dice := _FixedDice.new(3)
	var result: Dictionary = LairBudgetResolver.roll_budget(
		_make_terrain("woods"), dice)
	check(int(result["budget"]) == 6, "wilderness woods 2d4 @3 → 6")
	check(bool(result["rolled"]), "dice consumed for a live cell")

	# Borderlands scrub/hills = 1d3-2 → FixedDice(1) rolls 1-2 = -1 → clamp 0.
	var low := _FixedDice.new(1)
	var clamped: Dictionary = LairBudgetResolver.roll_budget(
		_make_terrain("clear", "hills", "borderlands"), low)
	check(int(clamped["budget"]) == 0, "RAW step 2: result < 0 treated as 0")

	# Civilized clear/grass = "-" → 0 without consuming a roll (RAW step 3).
	var unused := _FixedDice.new(4)
	var dash: Dictionary = LairBudgetResolver.roll_budget(
		_make_terrain("clear", "flat", "civilized"), unused)
	check(int(dash["budget"]) == 0, "civilized clear '-' → 0")
	check(not bool(dash["rolled"]), "'-' cell consumes no dice")
	check(unused.calls == 0, "no roll_digital call for '-' cell")

	# Civilized mountains/woods = 1d6-5 → FixedDice(6) → 1.
	var civ := _FixedDice.new(6)
	var civ_result: Dictionary = LairBudgetResolver.roll_budget(
		_make_terrain("woods", "flat", "civilized"), civ)
	check(int(civ_result["budget"]) == 1, "civilized woods 1d6-5 @6 → 1")


# ---------------------------------------------------------------------------
# HexLairState
# ---------------------------------------------------------------------------

func test_hex_lair_state_lazy_roll_caches() -> void:
	var pid := _make_party_id("lazy")
	_setup_fixture(pid)

	var fresh: Dictionary = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, 4, 4)
	check(not bool(fresh["budget_rolled"]), "fresh hex has no rolled budget")

	var dice := _FixedDice.new(3)
	var budget: int = HexLairState.get_or_roll_budget(
		CAMPAIGN_ID, MAP_ID, 4, 4, _make_terrain("woods"), dice, 777)
	check(budget == 6, "first call rolls 2d4 @3 → 6")
	var first_calls: int = dice.calls

	var cached: int = HexLairState.get_or_roll_budget(
		CAMPAIGN_ID, MAP_ID, 4, 4, _make_terrain("woods"), dice, 888)
	check(cached == 6, "second call returns cached budget")
	check(dice.calls == first_calls, "cached call consumes no dice")

	var state: Dictionary = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, 4, 4)
	check(bool(state["budget_rolled"]), "budget_rolled true after roll")
	check(int(state["budget_rolled_at"]) == 777, "rolled_at stamps the FIRST roll round")

	_cleanup_fixture(pid)


func test_unrevealed_queue_fifo_and_placed_count() -> void:
	var pid := _make_party_id("queue")
	_setup_fixture(pid)

	HexLairState.append_unrevealed_types(CAMPAIGN_ID, MAP_ID, 5, 5, ["goblin", "orc"])
	var state: Dictionary = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, 5, 5)
	check((state["unrevealed_lair_types"] as Array).size() == 2, "queue holds 2 types")

	check(HexLairState.pop_unrevealed_type(CAMPAIGN_ID, MAP_ID, 5, 5) == "goblin",
		"FIFO: first appended pops first")
	state = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, 5, 5)
	check((state["unrevealed_lair_types"] as Array) == ["orc"], "queue keeps the tail")

	check(HexLairState.pop_unrevealed_type(CAMPAIGN_ID, MAP_ID, 5, 5) == "orc",
		"second pop returns the tail")
	check(HexLairState.pop_unrevealed_type(CAMPAIGN_ID, MAP_ID, 5, 5) == "",
		"empty queue pops empty string")

	check(HexLairState.increment_placed_count(CAMPAIGN_ID, MAP_ID, 5, 5) == 1,
		"first increment → 1")
	check(HexLairState.increment_placed_count(CAMPAIGN_ID, MAP_ID, 5, 5) == 2,
		"second increment → 2")

	# Budget stays unrolled through queue/count writes.
	state = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, 5, 5)
	check(not bool(state["budget_rolled"]), "queue writes don't fabricate a budget")

	_cleanup_fixture(pid)


func test_display_rules_and_stronghold_gate() -> void:
	var pid := _make_party_id("display")
	_setup_fixture(pid)

	# §6.1: hidden before any placement or Survey. §7 (ruling 2026-06-10):
	# un-surveyed land is never buildable, even with no lairs known.
	check(HexLairState.format_lairs_line(CAMPAIGN_ID, MAP_ID, 6, 6) == "",
		"line hidden pre-placement, pre-Survey")
	check(not HexLairState.has_uncleared_placed_lair(CAMPAIGN_ID, MAP_ID, 6, 6),
		"no placed lairs → none uncleared")
	check(not HexLairState.is_stronghold_buildable(CAMPAIGN_ID, MAP_ID, 6, 6),
		"un-surveyed land blocks Build Stronghold")

	# Post-substitution, pre-Survey: denominator = placed count.
	var lid := _place_lair("display_a", 6, 6, "goblin")
	HexLairState.increment_placed_count(CAMPAIGN_ID, MAP_ID, 6, 6)
	check(HexLairState.format_lairs_line(CAMPAIGN_ID, MAP_ID, 6, 6) == "0 / 1",
		"pre-Survey denominator = placed count")
	check(HexLairState.has_uncleared_placed_lair(CAMPAIGN_ID, MAP_ID, 6, 6),
		"uncleared placed lair gates stronghold")

	# Post-Survey: denominator switches to the surveyed total.
	HexLairState.set_surveyed_total(CAMPAIGN_ID, MAP_ID, 6, 6, 4)
	check(HexLairState.format_lairs_line(CAMPAIGN_ID, MAP_ID, 6, 6) == "0 / 4",
		"post-Survey denominator = surveyed total")
	check(not HexLairState.is_stronghold_buildable(CAMPAIGN_ID, MAP_ID, 6, 6),
		"surveyed but uncleared lair → not buildable")

	# Clearing increments the numerator; the surveyed total still outstrips
	# the cleared count, so the hex remains unbuildable (known lairs remain).
	CampaignRepository.mark_lair_cleared(lid, 900)
	check(HexLairState.format_lairs_line(CAMPAIGN_ID, MAP_ID, 6, 6) == "1 / 4",
		"cleared lair increments the numerator")
	check(not HexLairState.has_uncleared_placed_lair(CAMPAIGN_ID, MAP_ID, 6, 6),
		"no placed lair remains uncleared")
	check(not HexLairState.is_stronghold_buildable(CAMPAIGN_ID, MAP_ID, 6, 6),
		"cleared 1 of surveyed 4 → still not buildable")

	# A corrective re-survey (e.g. the 4 was a false-high reading) lowers the
	# displayed total to the cleared count → buildable.
	HexLairState.set_surveyed_total(CAMPAIGN_ID, MAP_ID, 6, 6, 1)
	check(HexLairState.is_stronghold_buildable(CAMPAIGN_ID, MAP_ID, 6, 6),
		"surveyed + all surveyed lairs cleared → buildable")

	# Permissive fallback without campaign/map context (no-DB fixtures).
	check(HexLairState.is_stronghold_buildable("", "", 6, 6),
		"empty context stays permissive for unit-test fixtures")

	_cleanup_fixture(pid)


# ---------------------------------------------------------------------------
# LairGenerator stub
# ---------------------------------------------------------------------------

func test_lair_generator_population_parsing() -> void:
	var dice := _FixedDice.new(4)

	# Compound unit listing: roll the leading dice, surface the unit word.
	var compound: Dictionary = LairGenerator.roll_lair_population({
		"wilderness_encounter": {"in_lair": {"number": "1d10 warbands"}},
	}, dice)
	check(int(compound["count"]) == 4, "1d10 @4 → 4 units")
	check(String(compound["unit"]) == "warbands", "unit word surfaced")

	# Plain dice listing: individuals, no unit.
	var plain: Dictionary = LairGenerator.roll_lair_population({
		"wilderness_encounter": {"in_lair": {"number": "2d6"}},
	}, dice)
	check(int(plain["count"]) == 8, "2d6 @4 → 8")
	check(String(plain["unit"]) == "", "no unit word on plain dice")

	# Flat count: no dice consumed.
	var before: int = dice.calls
	var flat: Dictionary = LairGenerator.roll_lair_population({
		"dungeon_encounter": {"in_lair": {"number": "1 warband"}},
	}, dice)
	check(int(flat["count"]) == 1, "flat count parses")
	check(String(flat["unit"]) == "warband", "flat unit word surfaced")
	check(dice.calls == before, "flat count consumes no dice")

	# Missing listing falls back to 1.
	var missing: Dictionary = LairGenerator.roll_lair_population({}, dice)
	check(int(missing["count"]) == 1, "missing listing → count 1")


func test_lair_generator_record_shape() -> void:
	var pid := _make_party_id("gen")
	_setup_fixture(pid)
	var registry := MonsterRegistry.new()
	var dice := _FixedDice.new(3)

	var record: Dictionary = LairGenerator.generate(
		CAMPAIGN_ID, MAP_ID, 9, 9, "goblin", registry, dice, 1234)
	check(not String(record.get("lair_id", "")).is_empty(), "record carries an id")
	check(String(record.get("monster_group", "")) == "goblin", "occupant type stamped")
	check(int(record.get("monster_count", 0)) >= 1, "population rolled ≥ 1")
	check(record.get("cleared_at_round") == null, "cleared_at_round null on creation")
	check(bool(record.get("discovered", false)), "placement IS discovery")
	check(int(record.get("created_at_round", -1)) == 1234, "created_at_round stamped")
	check(not String(record.get("treasure_type", "")).is_empty(),
		"goblin treasure_type carried from the catalog")

	# Round-trips through the repository unchanged.
	record["placed_via"] = "search"
	var lid: String = CampaignRepository.create_lair(record)
	check(not lid.is_empty(), "record persists via create_lair")
	var row: Dictionary = CampaignRepository.get_lair(lid)
	check(String(row.get("treasure_type", "")) == String(record["treasure_type"]),
		"treasure_type round-trips")
	check(int(row.get("lair_layout_seed", -1)) == int(record["lair_layout_seed"]),
		"layout seed round-trips")

	_cleanup_fixture(pid)


# ---------------------------------------------------------------------------
# LairTypeResolver
# ---------------------------------------------------------------------------

func test_type_resolver_returns_lairing_creature() -> void:
	var registry := MonsterRegistry.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var creature_id: String = LairTypeResolver.roll_type(
		_make_terrain("woods"), registry, rng)
	check(not creature_id.is_empty(), "type roll returns a creature for woods")
	var entry: Dictionary = registry.get_monster(creature_id)
	var pct_raw: Variant = entry.get("percent_in_lair", 0)
	var pct: int = int(pct_raw) if pct_raw != null else 0
	check(pct > 0, "rolled creature can lair (%% In Lair > 0): %s" % creature_id)

	var slots: Array[String] = LairTypeResolver.roll_types_for_remaining_slots(
		_make_terrain("woods"), registry, 3, rng)
	check(slots.size() == 3, "eager roll fills all requested slots")
	for cid in slots:
		var e: Dictionary = registry.get_monster(cid)
		var p_raw: Variant = e.get("percent_in_lair", 0)
		var p: int = int(p_raw) if p_raw != null else 0
		check(p > 0, "every eager slot can lair: %s" % cid)


# ---------------------------------------------------------------------------
# survey_progress (unchanged table)
# ---------------------------------------------------------------------------

func test_survey_progress_upsert_round_trip() -> void:
	var pid := _make_party_id("sp")
	_setup_fixture(pid)

	var initial: Dictionary = CampaignRepository.get_survey_progress(
		CAMPAIGN_ID, MAP_ID, pid, 2, 2)
	check(initial.is_empty(), "no row before first upsert")

	var ok: bool = CampaignRepository.upsert_survey_progress({
		"campaign_id": CAMPAIGN_ID,
		"map_id": MAP_ID,
		"party_id": pid,
		"hex_q": 2,
		"hex_r": 2,
		"successful_searches": 1,
		"last_search_round": 4321,
		"last_estimate": 5,
		"last_estimate_correct": true,
	})
	check(ok, "first upsert succeeds")

	var row: Dictionary = CampaignRepository.get_survey_progress(
		CAMPAIGN_ID, MAP_ID, pid, 2, 2)
	check(int(row.get("successful_searches", 0)) == 1, "successes round-trip")
	check(int(row.get("last_estimate", -1)) == 5, "estimate round-trip")

	CampaignRepository.upsert_survey_progress({
		"campaign_id": CAMPAIGN_ID,
		"map_id": MAP_ID,
		"party_id": pid,
		"hex_q": 2,
		"hex_r": 2,
		"successful_searches": 3,
		"last_search_round": 9999,
		"last_estimate": 7,
		"last_estimate_correct": false,
	})
	var row2: Dictionary = CampaignRepository.get_survey_progress(
		CAMPAIGN_ID, MAP_ID, pid, 2, 2)
	check(int(row2.get("successful_searches", 0)) == 3, "successes updated")
	check(int(row2.get("last_estimate", -1)) == 7, "estimate updated")
	check(int(row2.get("last_estimate_correct", 1)) == 0, "false-reading flag stored")

	_cleanup_fixture(pid)
