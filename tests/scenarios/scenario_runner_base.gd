extends "res://tests/test_suite_base.gd"

## Phase 11E — Multi-month integration test scaffolding per
## `docs/phase-11-plan.md` §11E.
##
## Scenarios extend this base class and:
##   1. Override `_setup_world()` to seed a campaign + character(s) + domain(s).
##   2. Call `tick_monthly(N)` to run N months of monthly resolution.
##   3. Assert on the final state.
##
## The scenario runner mirrors `DomainHandlers._handle_monthly_tick` in spirit
## but operates on a white-box stack of direct resolver calls. This makes the
## scenarios deterministic + signal-plumbing-free; they exercise the resolver
## composition without depending on the SessionRunner state machine.
##
## Each scenario is responsible for its own cleanup (`_cleanup()` override or
## an explicit teardown in `run_all_tests`). The base class provides generic
## DELETE helpers keyed on common test ids.

const SCENARIO_DEFAULT_DICE_ROLLER := preload(
	"res://tests/scenarios/scenario_runner_base.gd")


# ---------------------------------------------------------------------------
# Test fixture state — scenarios override / extend as needed
# ---------------------------------------------------------------------------

var _campaign_id: String = ""
var _domain_ids: Array = []
var _character_ids: Array = []
var _stronghold_ids: Array = []
var _current_calendar_day: int = 1


# ---------------------------------------------------------------------------
# World seeding helpers
# ---------------------------------------------------------------------------

func seed_campaign(id: String = "scenario_campaign") -> String:
	_campaign_id = id
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[id, "Scenario " + id])
	return id


## Inserts a PC character row with sensible defaults. Caller can override any
## field via the [param overrides] dict.
func seed_character(id: String, overrides: Dictionary = {}) -> String:
	var name: String = String(overrides.get("name", "Test Char " + id))
	var alignment: String = String(overrides.get("alignment", "lawful"))
	var race: String = String(overrides.get("race", "human"))
	var character_class: String = String(overrides.get("character_class", "fighter"))
	var level: int = int(overrides.get("level", 9))
	var character_type: String = String(overrides.get("character_type", "pc"))
	var charisma: int = int(overrides.get("charisma", 10))
	var combat_progression: String = String(overrides.get("combat_progression", "fighter"))
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 alignment, is_active)
		VALUES (?, ?, ?, ?, 'full', ?, ?, ?, 0, ?,
		        10, 10, 10, 10, 10, ?, ?, 1)
	""", [id, _campaign_id, name, character_type, race, character_class,
		  level, combat_progression, charisma, alignment])
	_character_ids.append(id)
	return id


## Inserts a domain row with sensible defaults. Caller can override any field.
func seed_domain(id: String, owner_character_id: String, overrides: Dictionary = {}) -> String:
	var name: String = String(overrides.get("name", "Test Domain " + id))
	var territory_type: String = String(overrides.get("territory_type", "borderlands"))
	var peasant_families: int = int(overrides.get("peasant_families", 500))
	var alignment: String = String(overrides.get("alignment", "lawful"))
	var religion: String = String(overrides.get("religion", "sun-cult"))
	var effective_religion: String = String(overrides.get("effective_religion", religion))
	var domain_style: String = String(overrides.get("domain_style", "civilized"))
	var establishment_method: String = String(overrides.get("establishment_method", "grant"))
	var calendar_day: int = int(overrides.get("established_calendar_day", _current_calendar_day))
	var liege_domain_id: Variant = overrides.get("liege_domain_id", null)
	var available_tw: int = int(overrides.get("available_tribal_warriors",
		peasant_families if domain_style == "clanhold" else 0))
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, alignment, religion, effective_religion,
			 domain_style, establishment_method, established_calendar_day,
			 liege_domain_id, available_tribal_warriors, lifecycle_state)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active')
	""", [id, _campaign_id, name, owner_character_id, territory_type,
		  peasant_families, alignment, religion, effective_religion,
		  domain_style, establishment_method, calendar_day,
		  liege_domain_id, available_tw])
	_domain_ids.append(id)
	return id


## Inserts a stronghold row + links it to a domain via the stronghold's
## location_map_id (Phase 11B's collapse hook reads this). v1 minimal:
## creates a stronghold with the given shp_value and links the domain to it.
func seed_stronghold(id: String, domain_id: String, shp_value_cp: int = 1_500_000) -> String:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO strongholds
			(id, campaign_id, name, owner_character_id, current_shp_value_cp,
			 invested_shp_value_cp, location_map_id, location_hex_q, location_hex_r,
			 status)
		VALUES (?, ?, ?, ?, ?, ?, '', 0, 0, 'active')
	""", [id, _campaign_id, "Test Stronghold " + id,
		  _domain_owner(domain_id), shp_value_cp, shp_value_cp])
	# Link the domain's location_hex_* to the stronghold (Phase 11B's collapse
	# hook locates strongholds by location_hex). Simplest: leave the stronghold
	# unlinked for v1; sufficient for scenarios that don't trigger collapse.
	_stronghold_ids.append(id)
	return id


## Seeds N hexes for a domain at sequential coords. Each hex has the given
## land_value (default 5gp/family) + land_improvement_level (default 0).
func seed_hexes(domain_id: String, count: int, land_value: int = 5,
		land_improvement_level: int = 0) -> Array:
	var ids: Array = []
	for i in range(count):
		var hex_id: String = "%s_hex_%d" % [domain_id, i]
		CampaignRepository.db.query_with_bindings("""
			INSERT OR REPLACE INTO domain_hexes
				(id, domain_id, hex_q, hex_r, land_value, land_improvement_level)
			VALUES (?, ?, ?, 0, ?, ?)
		""", [hex_id, domain_id, i, land_value, land_improvement_level])
		ids.append(hex_id)
	return ids


# ---------------------------------------------------------------------------
# Monthly tick — composes resolver calls per DomainHandlers pattern
# ---------------------------------------------------------------------------

## Runs N months of monthly resolution against every seeded domain.
## Mirrors `DomainHandlers._handle_monthly_tick` in white-box form:
##   revenue → expenses → base morale → current morale → growth → classification
## Returns an Array of per-month per-domain result dicts for assertion.
func tick_monthly(months: int = 1) -> Array:
	var results: Array = []
	for m in range(months):
		_current_calendar_day += 30
		for domain_id in _domain_ids:
			var domain: Dictionary = CampaignRepository.get_domain(domain_id)
			if domain.is_empty():
				continue
			if String(domain.get("lifecycle_state", "active")) != "active":
				continue
			results.append(_resolve_one_domain_one_month(domain))
	return results


func _resolve_one_domain_one_month(domain: Dictionary) -> Dictionary:
	var domain_id: String = String(domain.get("id", ""))
	var owner_id: String = String(domain.get("owner_character_id", ""))
	var ruler: Dictionary = CampaignRepository.get_character(owner_id)
	# Domain-level support data.
	var hexes: Array = _list_hexes_for_domain(domain_id)
	# Stronghold sufficiency (v1: classification minimum table per RAW).
	var classification: String = String(domain.get("territory_type", "wilderness"))
	var stronghold_value_cp: int = int(domain.get("_stronghold_value_cp_override", 1_500_000))
	var stronghold_minimum_cp: int = _classification_minimum_cp(classification)
	# Revenue.
	var revenue: Dictionary = DomainRevenueCalculator.calculate_monthly_revenue(
		domain, hexes, stronghold_value_cp, stronghold_minimum_cp, 0)
	# Garrison (for the minimum + morale-incentive bonus).
	var garrison: Dictionary = GarrisonExpenditureCalculator.compute_from_domain(domain)
	var actual_paid_cp: int = int(garrison.get("total_paid_cp", 0))
	var morale_incentive: int = int(garrison.get("morale_incentive_bonus", 0))
	# Expenses.
	var expenses: Dictionary = DomainExpenseCalculator.calculate_monthly_expenses(
		domain, actual_paid_cp, bool(revenue.get("income_gate_active", false)))
	# Morale.
	var ruler_block: Dictionary = {
		"cha_modifier": _cha_mod(int(ruler.get("charisma", 10))),
		"level": int(ruler.get("level", 1)),
		"alignment": String(ruler.get("alignment", "neutral")),
		"race": String(ruler.get("race", "human")),
		"has_leadership_proficiency": false,
	}
	var base_morale: int = DomainMoraleResolver.resolve_base_morale(
		domain, ruler_block, int(revenue.get("total", 0)),
		stronghold_value_cp, stronghold_minimum_cp, morale_incentive)
	var morale_state: Dictionary = DomainMoraleResolver.resolve_current_morale(
		domain, base_morale, 0,
		int(domain.get("repression_cp_per_family_this_month", 0)),
		bool(domain.get("is_repressed_this_month", 0)),
		7)  # mid-band 2d6 roll for determinism (7 = drift toward base)
	var current_morale: int = int(morale_state.get("current_morale", 0))
	var morale_tier: String = DomainMoraleResolver.morale_tier(current_morale)
	# Growth (deterministic roller for scenario determinism).
	var growth: Dictionary = DomainGrowthResolver.resolve_growth(
		domain, int(revenue.get("total", 0)), 0,
		morale_tier, false, bool(revenue.get("income_gate_active", false)),
		_deterministic_roller())
	# Persist updated state.
	var new_peasants: int = maxi(0,
		int(domain.get("peasant_families", 0)) + int(growth.get("net_change", 0)))
	CampaignRepository.db.query_with_bindings("""
		UPDATE domains SET morale = ?, peasant_families = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [current_morale, new_peasants, domain_id])
	# Classification advancement (informational; doesn't auto-flip).
	var class_change: Dictionary = ClassificationAdvancement.check_classification_change(
		domain, hexes.size(),
		false, 0,  # has_urban, urban_pct stub
		0,  # distance_to_friendly_city — placeholder
		false,  # contiguous_blocked
		true)  # same-realm: scenario default
	return {
		"domain_id": domain_id,
		"calendar_day": _current_calendar_day,
		"revenue": revenue,
		"expenses": expenses,
		"base_morale": base_morale,
		"current_morale": current_morale,
		"morale_tier": morale_tier,
		"growth": growth,
		"new_peasants": new_peasants,
		"class_change": class_change,
	}


# ---------------------------------------------------------------------------
# Common assertions
# ---------------------------------------------------------------------------

func assert_domain_state(domain_id: String, expected: Dictionary) -> void:
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	for key in expected:
		var actual: Variant = domain.get(key, null)
		var want: Variant = expected[key]
		check(str(actual) == str(want),
			"%s.%s: expected %s, got %s" % [domain_id, key, str(want), str(actual)])


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

func cleanup_scenario() -> void:
	for d in _domain_ids:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM troop_units WHERE assigned_domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domain_departure_log WHERE domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domain_hexes WHERE domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domain_religion_conversion WHERE domain_id = ?", [d])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM domains WHERE id = ?", [d])
	for s in _stronghold_ids:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM strongholds WHERE id = ?", [s])
	for c in _character_ids:
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM congregants WHERE character_id = ?", [c])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [c])
	if not _campaign_id.is_empty():
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM campaigns WHERE id = ?", [_campaign_id])
	_domain_ids.clear()
	_character_ids.clear()
	_stronghold_ids.clear()
	_campaign_id = ""
	_current_calendar_day = 1


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _list_hexes_for_domain(domain_id: String) -> Array:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domain_hexes WHERE domain_id = ?", [domain_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


func _domain_owner(domain_id: String) -> String:
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	return String(domain.get("owner_character_id", ""))


## Returns the classification's stronghold sufficiency minimum in cp.
## Per acore_axioms_strongholds_and_domains.xml §peasants_and_followers L108-109
## via the stronghold value table. v1 uses RAW magnitudes (15,000gp wilderness;
## 75,000gp borderlands; 375,000gp civilized).
func _classification_minimum_cp(classification: String) -> int:
	match classification:
		"civilized":    return 37_500_000  # 375,000 gp
		"borderlands":  return 7_500_000   # 75,000 gp
		"wilderness":   return 1_500_000   # 15,000 gp
		_:              return 1_500_000


func _cha_mod(score: int) -> int:
	if score <= 3:    return -3
	elif score <= 5:  return -2
	elif score <= 8:  return -1
	elif score <= 12: return 0
	elif score <= 15: return 1
	elif score <= 17: return 2
	return 3


## Deterministic roller — returns count × 5 for any (faces, count) call.
## Used to make scenarios reproducible. Scenarios that need specific dice
## outcomes override via a per-test roller.
func _deterministic_roller() -> Callable:
	return func(_faces: int, count: int, _exploding: bool) -> int:
		return count * 5
