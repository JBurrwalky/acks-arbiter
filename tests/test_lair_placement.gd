extends "res://tests/test_suite_base.gd"

## Handler-level tests for lazy lair placement (gdd-lair-discovery.md §3.2,
## §4.3, §5) — the WildernessHandlers wiring over the resolvers/services
## unit-tested in test_lair_discovery.gd.
##
## Covers:
##   * Wandering substitution — % In Lair success places via the Lair
##     Generator, decrements budget room, pops the unrevealed queue, and
##     enriches encounter_data; at budget cap it resolves as a "creature
##     group at home" with no record; a % In Lair miss is a no-op.
##   * Search hour (§5.3) — success pops the pre-rolled queue (post-Survey)
##     or lazy-rolls a type (Search-first); at cap surfaces the soft "no
##     further lairs" result; failure places nothing; every success bumps
##     the cumulative survey_progress counter (RAW L167).
##   * Survey (§4.3/§4.4) — success rolls the budget, eagerly fills the
##     hidden queue, reveals the total; an unmodified-1 false reading
##     affects only the displayed total, never the internal state.
##   * mark_lair_cleared — stamps cleared_at_round and fires lair_cleared.
##
## Dice control via GameState.dice_overrides (forced modified_total,
## consumed once per roll_type). Roll types used here: "lair_budget",
## "lair_substitution_check", "lair_population", "lair_layout_seed",
## "lair_search", "land_surveying", "land_surveying_false",
## "land_surveying_false_sign".


const PARTY_ID := "test_lairplace_party"
const CAMPAIGN_ID := "test_lairplace_campaign"
const MAP_ID := "test_lairplace_map"
const HEX_Q := 3
const HEX_R := 5


# ---------------------------------------------------------------------------
# Fake runner — minimal SessionRunner stand-in. Real HexMapController (the
# handlers type their locals as HexMapController) wrapping a 2-hex map.
# do_encounter_check is stubbed quiet so search-hour tests stay deterministic.
# ---------------------------------------------------------------------------

class _FakeRunner:
	var party_id: String = ""
	var party_data: PartyData = null
	var campaign_id: String = ""
	var controller: HexMapController = null

	func get_party_id() -> String:
		return party_id

	func get_party_data() -> PartyData:
		return party_data

	func get_campaign_id() -> String:
		return campaign_id

	func get_hex_map_controller() -> HexMapController:
		return controller

	func get_scheduler() -> EventScheduler:
		return null

	func do_encounter_check(_terrain: HexTerrainData,
			_dungeon_wandering_table: Array = []) -> Dictionary:
		return {"triggered": false, "encounter_data": {}}


var _runner: _FakeRunner = null
var _handlers: WildernessHandlers = null
var _terrain: HexTerrainData = null
var _placed_signals: Array = []
var _cleared_signals: Array = []


func run_all_tests() -> void:
	test_substitution_places_lair_and_pops_queue()
	test_substitution_at_budget_cap_places_no_record()
	test_substitution_skips_when_not_in_lair()
	test_search_hour_pops_queue_and_places()
	test_search_hour_at_cap_soft_notification()
	test_search_hour_failure_places_nothing()
	test_search_first_lazy_rolls_type()
	test_survey_success_fills_queue_and_reveals()
	test_survey_natural_one_false_reading_display_only()
	test_survey_via_hired_land_surveyor()
	test_survey_inconclusive_reveals_nothing()
	test_mark_lair_cleared_emits_and_stamps()
	if not has_failures():
		print("LairPlacement: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _setup() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM specialists WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM survey_progress WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM hex_lair_state WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM lairs WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [PARTY_ID])
	db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [PARTY_ID])
	db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [MAP_ID])
	db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[CAMPAIGN_ID, "test lair placement"])
	db.query_with_bindings(
		"INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale) " +
		"VALUES (?, ?, ?, ?)",
		[MAP_ID, CAMPAIGN_ID, "test_map", "regional_6mi"])
	db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[PARTY_ID, CAMPAIGN_ID, "Test Lair Placement Party"])
	Timekeeping.register_party(PARTY_ID)

	_terrain = HexTerrainData.new()
	_terrain.biome = HexTerrainData.BIOME_WOODS
	_terrain.elevation = HexTerrainData.ELEVATION_FLAT
	_terrain.civilization = HexTerrainData.TERRITORY_WILDERNESS

	var map := HexMapData.new()
	map.id = MAP_ID
	map.party_hex = Vector2i(0, 0)
	map.hexes[Vector2i(0, 0)] = HexTerrainData.new()
	map.hexes[Vector2i(HEX_Q, HEX_R)] = _terrain

	_runner = _FakeRunner.new()
	_runner.party_id = PARTY_ID
	_runner.campaign_id = CAMPAIGN_ID
	_runner.controller = HexMapController.new()
	_runner.controller.load_map(map)
	_runner.party_data = _make_party()
	_handlers = WildernessHandlers.new(_runner)

	_placed_signals.clear()
	_cleared_signals.clear()
	EventBus.lair_placed.connect(_on_lair_placed)
	EventBus.lair_cleared.connect(_on_lair_cleared)
	DiceTestHarness.clear_all()


func _teardown() -> void:
	EventBus.lair_placed.disconnect(_on_lair_placed)
	EventBus.lair_cleared.disconnect(_on_lair_cleared)
	DiceTestHarness.clear_all()
	if _runner != null and _runner.controller != null:
		_runner.controller.free()
	_runner = null
	_handlers = null
	Timekeeping.unregister_party(PARTY_ID)
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM specialists WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM survey_progress WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM hex_lair_state WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM lairs WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [PARTY_ID])
	db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [PARTY_ID])
	db.query_with_bindings(
		"DELETE FROM hex_maps WHERE id = ?", [MAP_ID])


func _on_lair_placed(party_id: String, result: Dictionary) -> void:
	if party_id == PARTY_ID:
		_placed_signals.append(result)


func _on_lair_cleared(party_id: String, result: Dictionary) -> void:
	if party_id == PARTY_ID:
		_cleared_signals.append(result)


## Party with a Land Surveying member. Non-empty proficiencies on every
## member so _load_member_proficiencies skips its DB reads.
func _make_party() -> PartyData:
	var pd := PartyData.new()
	pd.id = PARTY_ID
	pd.campaign_id = CAMPAIGN_ID
	pd.name = "Test Lair Placement Party"
	pd.current_hex_q = HEX_Q
	pd.current_hex_r = HEX_R
	pd.character_data = []
	var surveyor := CharacterData.new()
	surveyor.id = PARTY_ID + "_surveyor"
	surveyor.name = "Surveyor"
	surveyor.hp_max = 10
	surveyor.hp_current = 10
	surveyor.proficiencies = [{"proficiency_key": "land_surveying", "rank": 1}]
	pd.character_data.append(surveyor)
	var grunt := CharacterData.new()
	grunt.id = PARTY_ID + "_grunt"
	grunt.name = "Grunt"
	grunt.hp_max = 10
	grunt.hp_current = 10
	grunt.proficiencies = [{"proficiency_key": "alertness", "rank": 1}]
	pd.character_data.append(grunt)
	return pd


## Seeds a pre-rolled hex_lair_state row so tests can pin the budget without
## consuming the "lair_budget" override.
func _seed_state(budget: int, placed: int = 0, queue: Array = []) -> void:
	CampaignRepository.upsert_hex_lair_state({
		"campaign_id": CAMPAIGN_ID,
		"map_id": MAP_ID,
		"hex_q": HEX_Q,
		"hex_r": HEX_R,
		"lair_budget": budget,
		"lair_budget_rolled_at_round": 0,
		"lairs_placed_count": placed,
		"unrevealed_lair_types": JSON.stringify(queue),
		"surveyed_total": null,
	})


func _lair_rows() -> Array:
	return CampaignRepository.get_lairs_in_hex(CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R)


# ---------------------------------------------------------------------------
# Wandering substitution (§3.2)
# ---------------------------------------------------------------------------

func test_substitution_places_lair_and_pops_queue() -> void:
	_setup()
	HexLairState.append_unrevealed_types(
		CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R, ["orc"])
	# Goblin % In Lair = 40 → forced d100 of 1 is "in its lair".
	GameState.dice_overrides["lair_substitution_check"] = 1
	GameState.dice_overrides["lair_budget"] = 2
	GameState.dice_overrides["lair_population"] = 4
	GameState.dice_overrides["lair_layout_seed"] = 123

	var enc := {"monster_group": "goblin", "number": 2}
	_handlers._apply_lair_substitution(
		_runner.party_data, enc, Vector2i(HEX_Q, HEX_R), _terrain)

	check(bool(enc.get("is_lair", false)), "encounter marked in-lair")
	check(not String(enc.get("lair_id", "")).is_empty(), "encounter carries the lair_id")
	check(int(enc.get("number", 0)) == 4, "encounter uses lair-population numbers")

	var rows := _lair_rows()
	check(rows.size() == 1, "one lair record placed")
	if rows.size() == 1:
		check(String(rows[0].get("monster_group", "")) == "goblin",
			"placed lair uses the WANDERED creature's type")
		check(String(rows[0].get("placed_via", "")) == "wandering_substitution",
			"placed_via = wandering_substitution")

	var state: Dictionary = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R)
	check(bool(state["budget_rolled"]) and int(state["lair_budget"]) == 2,
		"budget lazily rolled on first need")
	check(int(state["lairs_placed_count"]) == 1, "placed count incremented")
	check((state["unrevealed_lair_types"] as Array).is_empty(),
		"substitution consumed one unrevealed slot (RAW L150)")

	check(_placed_signals.size() == 1, "lair_placed fired once")
	if _placed_signals.size() == 1:
		check(String(_placed_signals[0].get("via", "")) == "wandering_substitution",
			"signal via discriminator = wandering_substitution")
	_teardown()


func test_substitution_at_budget_cap_places_no_record() -> void:
	_setup()
	_seed_state(0)  # budget rolled at 0 — hex has no lair slots
	GameState.dice_overrides["lair_substitution_check"] = 1
	GameState.dice_overrides["lair_population"] = 3

	var enc := {"monster_group": "goblin", "number": 2}
	_handlers._apply_lair_substitution(
		_runner.party_data, enc, Vector2i(HEX_Q, HEX_R), _terrain)

	check(bool(enc.get("is_lair", false)), "still resolves as a group at home")
	check(bool(enc.get("at_budget_cap", false)), "flagged at_budget_cap")
	check(int(enc.get("number", 0)) == 3, "lair-population numbers used at cap")
	check(_lair_rows().is_empty(), "no persistent record at budget cap")
	check(_placed_signals.is_empty(), "no lair_placed signal at cap")
	var state: Dictionary = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R)
	check(int(state["lairs_placed_count"]) == 0, "placed count unchanged at cap")
	_teardown()


func test_substitution_skips_when_not_in_lair() -> void:
	_setup()
	# Goblin % In Lair = 40 → forced d100 of 100 misses.
	GameState.dice_overrides["lair_substitution_check"] = 100

	var enc := {"monster_group": "goblin", "number": 2}
	_handlers._apply_lair_substitution(
		_runner.party_data, enc, Vector2i(HEX_Q, HEX_R), _terrain)

	check(not enc.has("is_lair"), "encounter untouched on a %% In Lair miss")
	check(int(enc.get("number", 0)) == 2, "wandering numbers retained")
	check(_lair_rows().is_empty(), "no record placed")
	var state: Dictionary = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R)
	check(not bool(state["budget_rolled"]), "budget stays unrolled on a miss")
	_teardown()


# ---------------------------------------------------------------------------
# Search hour (§5)
# ---------------------------------------------------------------------------

func test_search_hour_pops_queue_and_places() -> void:
	_setup()
	_seed_state(2, 0, ["orc"])
	GameState.dice_overrides["lair_search"] = 20
	GameState.dice_overrides["lair_population"] = 5
	GameState.dice_overrides["lair_layout_seed"] = 9

	var result: Dictionary = _handlers._resolve_lair_search_hour(PARTY_ID, HEX_Q, HEX_R)
	var presentation: Dictionary = result.get("presentation", {})
	check(String(presentation.get("type", "")) == "lair_search_complete",
		"search-complete presentation returned")
	check(not String(presentation.get("lair_found_id", "")).is_empty(),
		"search success places a lair")

	var rows := _lair_rows()
	check(rows.size() == 1, "one lair record placed")
	if rows.size() == 1:
		check(String(rows[0].get("monster_group", "")) == "orc",
			"post-Survey search pops the queue front")
		check(String(rows[0].get("placed_via", "")) == "search", "placed_via = search")

	var state: Dictionary = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R)
	check(int(state["lairs_placed_count"]) == 1, "placed count incremented")
	check((state["unrevealed_lair_types"] as Array).is_empty(), "queue front consumed")

	var progress: Dictionary = CampaignRepository.get_survey_progress(
		CAMPAIGN_ID, MAP_ID, PARTY_ID, HEX_Q, HEX_R)
	check(int(progress.get("successful_searches", 0)) == 1,
		"successful search bumps the cumulative +4 counter (RAW L167)")

	check(_placed_signals.size() == 1
		and String(_placed_signals[0].get("via", "")) == "search",
		"lair_placed fired with via=search")
	_teardown()


func test_search_hour_at_cap_soft_notification() -> void:
	_setup()
	_seed_state(0)
	GameState.dice_overrides["lair_search"] = 20

	var result: Dictionary = _handlers._resolve_lair_search_hour(PARTY_ID, HEX_Q, HEX_R)
	var presentation: Dictionary = result.get("presentation", {})
	check(bool(presentation.get("budget_exhausted", false)),
		"budget cap surfaces the no-further-lairs result")
	check(String(presentation.get("lair_found_id", "")).is_empty(), "no lair placed")
	check(_lair_rows().is_empty(), "no record at cap")
	var progress: Dictionary = CampaignRepository.get_survey_progress(
		CAMPAIGN_ID, MAP_ID, PARTY_ID, HEX_Q, HEX_R)
	check(int(progress.get("successful_searches", 0)) == 1,
		"successful throw still counts toward the survey bonus at cap")
	_teardown()


func test_search_hour_failure_places_nothing() -> void:
	_setup()
	_seed_state(2, 0, ["orc"])
	GameState.dice_overrides["lair_search"] = 1  # 1 < 18 target → failure

	var result: Dictionary = _handlers._resolve_lair_search_hour(PARTY_ID, HEX_Q, HEX_R)
	var presentation: Dictionary = result.get("presentation", {})
	check(String(presentation.get("lair_found_id", "")).is_empty(),
		"failed throw places nothing")
	check(_lair_rows().is_empty(), "no record on failure")
	var state: Dictionary = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R)
	check((state["unrevealed_lair_types"] as Array).size() == 1,
		"queue untouched on failure")
	var progress: Dictionary = CampaignRepository.get_survey_progress(
		CAMPAIGN_ID, MAP_ID, PARTY_ID, HEX_Q, HEX_R)
	check(progress.is_empty() or int(progress.get("successful_searches", 0)) == 0,
		"no bonus counter bump on failure")
	_teardown()


func test_search_first_lazy_rolls_type() -> void:
	_setup()
	_seed_state(1)  # budget room, EMPTY queue — Search-first per §5.3
	GameState.dice_overrides["lair_search"] = 20

	_handlers._resolve_lair_search_hour(PARTY_ID, HEX_Q, HEX_R)

	var rows := _lair_rows()
	check(rows.size() == 1, "Search-first lazy-rolls one type and places")
	if rows.size() == 1:
		var creature_id: String = String(rows[0].get("monster_group", ""))
		check(not creature_id.is_empty(), "placed lair carries a rolled type")
		var registry := MonsterRegistry.new()
		var entry: Dictionary = registry.get_monster(creature_id)
		var pct_raw: Variant = entry.get("percent_in_lair", 0)
		var pct: int = int(pct_raw) if pct_raw != null else 0
		check(pct > 0, "lazy-rolled type can lair: %s" % creature_id)
	_teardown()


# ---------------------------------------------------------------------------
# Survey (§4.3 / §4.4)
# ---------------------------------------------------------------------------

func test_survey_success_fills_queue_and_reveals() -> void:
	_setup()
	GameState.dice_overrides["land_surveying"] = 20
	GameState.dice_overrides["lair_budget"] = 3

	var result: Dictionary = _handlers._resolve_survey_activity(PARTY_ID, HEX_Q, HEX_R)
	var presentation: Dictionary = result.get("presentation", {})
	var survey: Dictionary = presentation.get("result", {})
	check(bool(survey.get("succeeded", false)), "forced 20 vs 18 succeeds")
	check(int(survey.get("displayed_total", -1)) == 3, "true budget revealed")
	check(not bool(survey.get("was_false_reading", true)), "not a false reading")

	var state: Dictionary = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R)
	check(bool(state["budget_rolled"]) and int(state["lair_budget"]) == 3,
		"budget rolled on first need")
	check(bool(state["surveyed"]) and int(state["surveyed_total"]) == 3,
		"surveyed_total = true budget")
	check((state["unrevealed_lair_types"] as Array).size() == 3,
		"queue eagerly filled to the full budget (types hidden)")
	check(HexLairState.format_lairs_line(CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R) == "0 / 3",
		"display shows 0 / 3 post-Survey")
	_teardown()


func test_survey_natural_one_false_reading_display_only() -> void:
	_setup()
	GameState.dice_overrides["land_surveying"] = 1
	GameState.dice_overrides["lair_budget"] = 3
	GameState.dice_overrides["land_surveying_false"] = 2       # step magnitude
	GameState.dice_overrides["land_surveying_false_sign"] = 2  # 2 = positive step

	var result: Dictionary = _handlers._resolve_survey_activity(PARTY_ID, HEX_Q, HEX_R)
	var survey: Dictionary = result.get("presentation", {}).get("result", {})
	check(bool(survey.get("natural_one", false)), "unmodified 1 triggers false reading")
	check(int(survey.get("displayed_total", -1)) == 5,
		"player sees the false value (3 + 2)")
	check(bool(survey.get("was_false_reading", false)), "flagged for debug overlays")

	var state: Dictionary = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R)
	check(int(state["lair_budget"]) == 3, "internal budget stays the truth")
	check(int(state["surveyed_total"]) == 5, "displayed total is the false value")
	check((state["unrevealed_lair_types"] as Array).size() == 3,
		"queue fills against the REAL budget, not the false value (§4.4)")
	check(HexLairState.format_lairs_line(CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R) == "0 / 5",
		"display uses the false denominator until corrected")
	_teardown()


## Ruling 2026-06-10: a hired Land Surveyor (specialists table, attached to
## the party) makes the Survey throw when no party member has the
## proficiency — the §7 stronghold gate is reachable for surveyor-less
## parties via hiring.
func test_survey_via_hired_land_surveyor() -> void:
	_setup()
	# Strip the fixture party's Land Surveying proficiency.
	for cd: CharacterData in _runner.party_data.character_data:
		cd.proficiencies = [{"proficiency_key": "alertness", "rank": 1}]
	var sid: String = CampaignRepository.open_specialist({
		"campaign_id": CAMPAIGN_ID,
		"party_id": PARTY_ID,
		"kind": "land_surveyor",
		"name": "Hired Surveyor",
		"settlement_id": "test_town",
		"hired_at_round": 0,
		"monthly_wage_cp": 2500,
	})
	check(not sid.is_empty(), "specialist row opened")
	GameState.dice_overrides["land_surveying"] = 18
	GameState.dice_overrides["lair_budget"] = 2

	var result: Dictionary = _handlers._resolve_survey_activity(PARTY_ID, HEX_Q, HEX_R)
	var survey: Dictionary = result.get("presentation", {}).get("result", {})
	check(bool(survey.get("eligible", false)), "hired surveyor satisfies eligibility")
	check(bool(survey.get("surveyor_is_specialist", false)), "specialist made the throw")
	check(bool(survey.get("succeeded", false)),
		"18 vs 18 succeeds at base — thrower's own +4 excluded from assist")
	check(int(survey.get("specialist_bonus", -1)) == 0,
		"sole hired surveyor contributes no self-assist bonus")
	check(int(survey.get("displayed_total", -1)) == 2, "budget revealed")

	var state: Dictionary = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R)
	check(bool(state["surveyed"]) and int(state["surveyed_total"]) == 2,
		"surveyed_total persisted from a specialist-thrown survey")
	check((state["unrevealed_lair_types"] as Array).size() == 2,
		"queue eagerly filled")
	_teardown()


func test_survey_inconclusive_reveals_nothing() -> void:
	_setup()
	GameState.dice_overrides["land_surveying"] = 10  # fail, not a natural 1
	GameState.dice_overrides["lair_budget"] = 2

	var result: Dictionary = _handlers._resolve_survey_activity(PARTY_ID, HEX_Q, HEX_R)
	var survey: Dictionary = result.get("presentation", {}).get("result", {})
	check(not bool(survey.get("succeeded", true)), "10 vs 18 fails")
	check(int(survey.get("displayed_total", 0)) == -1, "nothing revealed")

	var state: Dictionary = HexLairState.get_state(CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R)
	check(not bool(state["surveyed"]), "surveyed_total stays unset")
	check((state["unrevealed_lair_types"] as Array).is_empty(),
		"queue not filled on an inconclusive failure")
	check(HexLairState.format_lairs_line(CAMPAIGN_ID, MAP_ID, HEX_Q, HEX_R) == "",
		"Lairs line stays hidden")
	_teardown()


# ---------------------------------------------------------------------------
# Clearing
# ---------------------------------------------------------------------------

func test_mark_lair_cleared_emits_and_stamps() -> void:
	_setup()
	var lid := CampaignRepository.create_lair({
		"campaign_id": CAMPAIGN_ID,
		"map_id": MAP_ID,
		"hex_q": HEX_Q,
		"hex_r": HEX_R,
		"monster_group": "goblin",
		"monster_count": 4,
		"placed_via": "search",
		"created_at_round": 100,
	})

	check(_handlers.mark_lair_cleared(PARTY_ID, lid), "mark_lair_cleared succeeds")
	check(CampaignRepository.get_lair(lid).get("cleared_at_round") != null,
		"cleared_at_round stamped")
	check(_cleared_signals.size() == 1, "lair_cleared fired once")
	if _cleared_signals.size() == 1:
		check(String(_cleared_signals[0].get("lair_id", "")) == lid,
			"signal carries the lair_id")

	check(_handlers.mark_lair_cleared(PARTY_ID, lid), "re-clear is idempotent")
	check(not _handlers.mark_lair_cleared(PARTY_ID, "nonexistent_lair"),
		"unknown lair returns false")
	_teardown()
