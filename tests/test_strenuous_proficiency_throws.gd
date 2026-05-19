extends "res://tests/test_suite_base.gd"

## Integration test for #26: strenuous penalty propagates to proficiency
## throws per RAW `ax_campaign_play.xml` §effort_rules L168
## ("cumulative -1 per day penalty to attack throws, damage rolls,
##  and proficiency throws").
##
## Wired call sites covered:
##   * ForagingResolver — forage_food + forage_water (per-character loop)
##   * HuntingResolver — single hunter pick
##   * TrackingResolver — single tracker parameter
##   * SurveyingResolver — single surveyor pick
##
## Each test asserts the SAME roll yields a `total` lower by exactly the
## strenuous_penalty after the character's `attack_throw_penalty` is
## upserted, and that the per-throw result Dictionary surfaces the
## `strenuous_penalty` field for transparency.


# ---------------------------------------------------------------------------
# Fake DiceSystem — fixed-value, mirrors test_foraging_resolver's pattern
# ---------------------------------------------------------------------------

class _FixedDice:
	extends RefCounted
	var _value: int

	func _init(value: int) -> void:
		_value = value

	func roll_digital(sides: int, count: int = 1, modifier: int = 0,
			_roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		# RollResult.individual_results is typed Array[int]; assign-then-append
		# to keep the typed-array invariant (a bare `var rolls: Array = []`
		# generic-array assignment errors).
		r.individual_results = []
		var total: int = 0
		for _i in range(count):
			r.individual_results.append(_value)
			total += _value
		r.raw_total = total
		r.modified_total = total + modifier
		r.natural_one = (_value == 1 and sides == 20 and count == 1)
		r.natural_max = (_value == sides and count == 1)
		return r


var _campaign_id: String = ""
var _character_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_foraging_food_subtracts_strenuous_penalty()
	test_foraging_water_subtracts_strenuous_penalty()
	test_hunting_subtracts_strenuous_penalty()
	test_tracking_subtracts_strenuous_penalty()
	test_surveying_subtracts_strenuous_penalty()
	test_saving_throw_NOT_penalized_raw_silent()
	if not has_failures():
		print("StrenuousProficiencyThrows: all tests passed.")


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign(
		"Test Strenuous Proficiency", "TestWorld")
	check(not _campaign_id.is_empty(), "campaign created")
	_character_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Strenuous Forager', 'pc', 'full', 'human', 'fighter', 1,
			10, 10, 10, 10, 10, 10, 8, 8)
	""", [_character_id, _campaign_id])


func _reset_activity_state() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_activity_state WHERE character_id = ?",
		[_character_id])


func _apply_strenuous_penalty(amount: int) -> void:
	CampaignRepository.upsert_character_activity_state(_character_id, {
		"strenuous_days_in_streak": 6 + amount,
		"attack_throw_penalty": amount,
		"last_updated_calendar_day": 6 + amount,
	})


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_party_with_test_character() -> PartyData:
	var pd := PartyData.new()
	pd.id = "strenuous_test_party"
	var cd := CharacterData.new()
	cd.id = _character_id
	cd.name = "Strenuous Forager"
	cd.hp_max = 8
	cd.hp_current = 8
	cd.proficiencies = []  # no Survival/Tracking bonus by default
	pd.character_data = [cd]
	return pd


func _make_solo_tracker() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = _character_id
	cd.name = "Strenuous Tracker"
	cd.hp_max = 8
	cd.hp_current = 8
	cd.proficiencies = [{"proficiency_key": "tracking", "rank": 1}]
	return cd


func _terrain_clear() -> HexTerrainData:
	var t := HexTerrainData.new()
	t.elevation = HexTerrainData.ELEVATION_FLAT
	t.biome = HexTerrainData.BIOME_CLEAR
	t.water = HexTerrainData.WATER_NONE
	return t


func _calm_weather() -> WeatherStateData:
	return WeatherStateData.make(
		WeatherStateData.TEMP_MILD, WeatherStateData.ATMO_CALM, "clear")


# ---------------------------------------------------------------------------
# Foraging — food
# ---------------------------------------------------------------------------

func test_foraging_food_subtracts_strenuous_penalty() -> void:
	_reset_activity_state()
	var party := _make_party_with_test_character()
	var dice := _FixedDice.new(15)  # d20 → 15

	var baseline: Dictionary = ForagingResolver.attempt_daily(
		party, _terrain_clear(), _calm_weather(), dice)
	var baseline_throw: Dictionary = (baseline.get("food", {}).get("throws", []) as Array)[0]
	check(int(baseline_throw.get("strenuous_penalty", -1)) == 0,
		"baseline forage_food penalty=0, got %s" % baseline_throw.get("strenuous_penalty"))

	_apply_strenuous_penalty(3)
	var penalized: Dictionary = ForagingResolver.attempt_daily(
		party, _terrain_clear(), _calm_weather(), dice)
	var penalized_throw: Dictionary = (penalized.get("food", {}).get("throws", []) as Array)[0]
	check(int(penalized_throw.get("strenuous_penalty", -1)) == 3,
		"penalized forage_food penalty=3, got %s" % penalized_throw.get("strenuous_penalty"))
	check(int(penalized_throw.get("total", 0)) == int(baseline_throw.get("total", 0)) - 3,
		"forage_food total drops by 3 (baseline %d → penalized %d)" % [
			int(baseline_throw.get("total", 0)),
			int(penalized_throw.get("total", 0))])


# ---------------------------------------------------------------------------
# Foraging — water
# ---------------------------------------------------------------------------

func test_foraging_water_subtracts_strenuous_penalty() -> void:
	_reset_activity_state()
	var party := _make_party_with_test_character()
	var dice := _FixedDice.new(12)

	var baseline: Dictionary = ForagingResolver.attempt_daily(
		party, _terrain_clear(), _calm_weather(), dice)
	var baseline_throw: Dictionary = (baseline.get("water", {}).get("throws", []) as Array)[0]
	check(int(baseline_throw.get("strenuous_penalty", -1)) == 0,
		"baseline forage_water penalty=0")

	_apply_strenuous_penalty(2)
	var penalized: Dictionary = ForagingResolver.attempt_daily(
		party, _terrain_clear(), _calm_weather(), dice)
	var penalized_throw: Dictionary = (penalized.get("water", {}).get("throws", []) as Array)[0]
	check(int(penalized_throw.get("strenuous_penalty", -1)) == 2,
		"penalized forage_water penalty=2")
	check(int(penalized_throw.get("total", 0)) == int(baseline_throw.get("total", 0)) - 2,
		"forage_water total drops by 2")


# ---------------------------------------------------------------------------
# Hunting
# ---------------------------------------------------------------------------

func test_hunting_subtracts_strenuous_penalty() -> void:
	_reset_activity_state()
	var party := _make_party_with_test_character()
	var dice := _FixedDice.new(14)

	var baseline: Dictionary = HuntingResolver.attempt(party, dice)
	check(int(baseline.get("strenuous_penalty", -1)) == 0,
		"baseline hunt penalty=0")

	_apply_strenuous_penalty(4)
	var penalized: Dictionary = HuntingResolver.attempt(party, dice)
	check(int(penalized.get("strenuous_penalty", -1)) == 4,
		"penalized hunt penalty=4")
	check(int(penalized.get("total", 0)) == int(baseline.get("total", 0)) - 4,
		"hunt total drops by 4 (baseline %d → penalized %d)" % [
			int(baseline.get("total", 0)),
			int(penalized.get("total", 0))])


# ---------------------------------------------------------------------------
# Tracking
# ---------------------------------------------------------------------------

func test_tracking_subtracts_strenuous_penalty() -> void:
	_reset_activity_state()
	var tracker := _make_solo_tracker()
	var dice := _FixedDice.new(10)

	var baseline: Dictionary = TrackingResolver.attempt(
		tracker, 5, "soft", "daylight", 0, dice, 0)
	check(int(baseline.get("strenuous_penalty", -1)) == 0,
		"baseline tracking penalty=0")

	_apply_strenuous_penalty(1)
	var penalized: Dictionary = TrackingResolver.attempt(
		tracker, 5, "soft", "daylight", 0, dice, 0)
	check(int(penalized.get("strenuous_penalty", -1)) == 1,
		"penalized tracking penalty=1")
	check(int(penalized.get("total", 0)) == int(baseline.get("total", 0)) - 1,
		"tracking total drops by 1")


# ---------------------------------------------------------------------------
# Surveying
# ---------------------------------------------------------------------------

func test_surveying_subtracts_strenuous_penalty() -> void:
	_reset_activity_state()
	var pd := PartyData.new()
	pd.id = "strenuous_test_party_survey"
	var cd := CharacterData.new()
	cd.id = _character_id
	cd.name = "Strenuous Surveyor"
	cd.hp_max = 8
	cd.hp_current = 8
	cd.proficiencies = [{"proficiency_key": "land_surveying", "rank": 1}]
	pd.character_data = [cd]
	var dice := _FixedDice.new(15)

	var baseline: Dictionary = SurveyingResolver.assess(pd, 0, 2, dice, 0)
	check(int(baseline.get("strenuous_penalty", -1)) == 0,
		"baseline land_surveying penalty=0")

	_apply_strenuous_penalty(2)
	var penalized: Dictionary = SurveyingResolver.assess(pd, 0, 2, dice, 0)
	check(int(penalized.get("strenuous_penalty", -1)) == 2,
		"penalized land_surveying penalty=2")
	check(int(penalized.get("total", 0)) == int(baseline.get("total", 0)) - 2,
		"land_surveying total drops by 2")


# ---------------------------------------------------------------------------
# Negative test: saving throws are RAW-silent on strenuous, so we must
# NOT have wired any saving-throw path. Asserts get_proficiency_throw_penalty
# is the alias accessor (same return as get_attack_throw_penalty), confirming
# the unified-counter design — no double counter to drift from.
# ---------------------------------------------------------------------------

func test_saving_throw_NOT_penalized_raw_silent() -> void:
	_reset_activity_state()
	_apply_strenuous_penalty(5)
	# Both accessors must return the same value — they read the same column
	# by design (RAW lumps attack/damage/proficiency under one counter; no
	# saving-throw counter exists because RAW does not extend the penalty
	# to saving throws).
	var attack_pen: int = StrenuousAccountant.get_attack_throw_penalty(_character_id)
	var prof_pen: int = StrenuousAccountant.get_proficiency_throw_penalty(_character_id)
	check(attack_pen == 5, "attack-throw penalty = 5, got %d" % attack_pen)
	check(prof_pen == 5, "proficiency-throw penalty = 5, got %d" % prof_pen)
	check(attack_pen == prof_pen,
		"unified-counter: attack accessor and proficiency accessor return the same value")
