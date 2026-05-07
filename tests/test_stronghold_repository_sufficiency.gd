extends "res://tests/test_suite_base.gd"

## Unit tests for StrongholdRepository sufficiency math (Domain Phase 1).
##
## Verifies:
##   * Empty domain → 0 / not-sufficient
##   * One completed stronghold below per-hex × hex_count → not-sufficient
##   * At minimum → sufficient
##   * Multiple completed strongholds sum correctly
##   * In-progress strongholds don't count
##   * recompute_sufficiency_after_change emits signal exactly on flip


var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()
	test_empty_domain_zero_value()
	test_empty_domain_not_sufficient()
	test_classification_minimum_civilized()
	test_classification_minimum_borderlands()
	test_classification_minimum_wilderness()
	test_one_completed_below_minimum()
	test_one_completed_at_minimum_sufficient()
	test_in_progress_does_not_count()
	test_multiple_completed_sum()
	test_recompute_emits_on_flip_to_sufficient()
	test_recompute_no_signal_on_no_change()
	if not has_failures():
		print("StrongholdRepositorySufficiency: all tests passed.")


# ----- Setup -----

func _setup_campaign() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign(
		"Test Stronghold Sufficiency", "TestWorld")
	check(not _campaign_id.is_empty(), "campaign created")
	StrongholdRepository._clear_sufficiency_cache_for_test()


func _make_test_domain(territory_type: String) -> String:
	return CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "TestDomain_%s" % territory_type,
		"territory_type": territory_type,
	})


# ----- Empty domain -----

func test_empty_domain_zero_value() -> void:
	var domain_id := _make_test_domain("wilderness")
	var v := StrongholdRepository.get_stronghold_value_for_domain(domain_id)
	check(v == 0, "empty domain → 0 stronghold value, got %d" % v)


func test_empty_domain_not_sufficient() -> void:
	var domain_id := _make_test_domain("wilderness")
	check(StrongholdRepository.is_sufficient_for_domain(domain_id) == false,
		"empty domain not sufficient")


# ----- Classification minimums -----

func test_classification_minimum_civilized() -> void:
	check(StrongholdRepository.per_hex_minimum_for("civilized") == 15000,
		"civilized = 15,000 gp/hex")


func test_classification_minimum_borderlands() -> void:
	check(StrongholdRepository.per_hex_minimum_for("borderlands") == 22500,
		"borderlands = 22,500 gp/hex")


func test_classification_minimum_wilderness() -> void:
	check(StrongholdRepository.per_hex_minimum_for("wilderness") == 32000,
		"wilderness = 32,000 gp/hex")


# ----- One stronghold -----

func test_one_completed_below_minimum() -> void:
	var domain_id := _make_test_domain("wilderness")
	# Wilderness minimum is 32,000 gp × 1 hex (no hexes added yet, so default 1)
	# = 32,000. We commit a 16,000 gp completed stronghold → below minimum.
	CampaignRepository.create_stronghold({
		"domain_id": domain_id,
		"archetype": "fortress",
		"archetype_power_id": "stronghold_castle",
		"gp_value": 16000,
		"completion_pct": 100,
		"status": "completed",
	})
	var v := StrongholdRepository.get_stronghold_value_for_domain(domain_id)
	check(v == 16000, "value sum = 16,000, got %d" % v)
	check(StrongholdRepository.is_sufficient_for_domain(domain_id) == false,
		"16,000 < 32,000 wilderness minimum → not sufficient")


func test_one_completed_at_minimum_sufficient() -> void:
	var domain_id := _make_test_domain("borderlands")
	# Borderlands min = 22,500 × 1 hex.
	CampaignRepository.create_stronghold({
		"domain_id": domain_id,
		"archetype": "fortress",
		"archetype_power_id": "stronghold_castle",
		"gp_value": 22500,
		"completion_pct": 100,
		"status": "completed",
	})
	check(StrongholdRepository.is_sufficient_for_domain(domain_id) == true,
		"22,500 = borderlands minimum → sufficient")


# ----- In-progress doesn't count -----

func test_in_progress_does_not_count() -> void:
	var domain_id := _make_test_domain("civilized")
	# Civilized min = 15,000 × 1 hex.
	CampaignRepository.create_stronghold({
		"domain_id": domain_id,
		"archetype": "fortress",
		"archetype_power_id": "stronghold_castle",
		"gp_value": 15000,
		"completion_pct": 75,
		"status": "in_progress",
	})
	var v := StrongholdRepository.get_stronghold_value_for_domain(domain_id)
	check(v == 0, "in-progress strongholds contribute 0, got %d" % v)
	check(StrongholdRepository.is_sufficient_for_domain(domain_id) == false,
		"in-progress not sufficient")


# ----- Multiple completed -----

func test_multiple_completed_sum() -> void:
	var domain_id := _make_test_domain("wilderness")
	CampaignRepository.create_stronghold({
		"domain_id": domain_id, "archetype": "fortress",
		"archetype_power_id": "stronghold_castle",
		"gp_value": 12000, "completion_pct": 100, "status": "completed",
	})
	CampaignRepository.create_stronghold({
		"domain_id": domain_id, "archetype": "fortress",
		"archetype_power_id": "stronghold_castle",
		"gp_value": 22000, "completion_pct": 100, "status": "completed",
	})
	var v := StrongholdRepository.get_stronghold_value_for_domain(domain_id)
	check(v == 34000, "12k + 22k = 34k, got %d" % v)
	check(StrongholdRepository.is_sufficient_for_domain(domain_id) == true,
		"34k > 32k wilderness min → sufficient")


# ----- recompute_sufficiency_after_change -----

func test_recompute_emits_on_flip_to_sufficient() -> void:
	var domain_id := _make_test_domain("borderlands")
	StrongholdRepository._set_sufficiency_cache_for_test(domain_id, false)

	# Insert a stronghold that flips sufficiency to true.
	CampaignRepository.create_stronghold({
		"domain_id": domain_id, "archetype": "fortress",
		"archetype_power_id": "stronghold_castle",
		"gp_value": 25000, "completion_pct": 100, "status": "completed",
	})

	var fired: Array[Array] = []
	var conn := func(d_id: String, is_sufficient: bool, value_gp: int, minimum_gp: int):
		fired.append([d_id, is_sufficient, value_gp, minimum_gp])
	EventBus.stronghold_sufficiency_changed.connect(conn)

	StrongholdRepository.recompute_sufficiency_after_change(domain_id)
	check(fired.size() == 1, "signal fired exactly once on flip")
	if fired.size() > 0:
		check(fired[0][1] == true, "is_sufficient = true on flip")
		check(fired[0][2] == 25000, "value_gp = 25000")

	EventBus.stronghold_sufficiency_changed.disconnect(conn)


func test_recompute_no_signal_on_no_change() -> void:
	var domain_id := _make_test_domain("wilderness")
	# Cache already shows insufficient (no strongholds yet).
	StrongholdRepository._set_sufficiency_cache_for_test(domain_id, false)

	var fired: Array[Array] = []
	var conn := func(d_id: String, is_sufficient: bool, value_gp: int, minimum_gp: int):
		fired.append([d_id, is_sufficient, value_gp, minimum_gp])
	EventBus.stronghold_sufficiency_changed.connect(conn)

	# No change to underlying state — recompute should not flip.
	StrongholdRepository.recompute_sufficiency_after_change(domain_id)
	check(fired.size() == 0, "no signal when sufficiency unchanged")

	EventBus.stronghold_sufficiency_changed.disconnect(conn)
