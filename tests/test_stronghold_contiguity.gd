extends "res://tests/test_suite_base.gd"

## Unit tests for StrongholdRepository.get_effective_hex_count_for_domain
## per RAW `acore_axioms` §noncontiguous_domains L95-98:
##
##   "For noncontiguous territory, the stronghold or combined strongholds
##    must be large enough to secure all noncontiguous hexes and the
##    intervening hexes between them."
##
## The function returns `|owned hexes ∪ minimal connecting set|`. For
## contiguous domains (one connected component) it returns the owned count
## unchanged — the bit-for-bit pre-2026-05-19 behavior. For noncontiguous
## domains it adds the minimal greedy-MST connecting set.
##
## Sufficiency consequence: noncontiguous domains require MORE stronghold
## value than the same hex count would in a contiguous arrangement, per RAW.


var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()
	test_empty_domain_zero()
	test_single_hex_returns_one()
	test_two_adjacent_hexes_returns_two()
	test_two_hexes_distance_two_adds_one_intervening()
	test_two_hexes_distance_three_adds_two_intervening()
	test_line_of_three_with_middle_missing_adds_one()
	test_three_components_in_triangle()
	test_l_shape_all_adjacent_returns_owned_count()
	test_contiguous_domain_sufficiency_unchanged()
	test_noncontiguous_domain_minimum_scales_up()
	if not has_failures():
		print("StrongholdContiguity: all tests passed.")


# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

func _setup_campaign() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign(
		"Test Stronghold Contiguity", "TestWorld")
	check(not _campaign_id.is_empty(), "campaign created")
	StrongholdRepository._clear_sufficiency_cache_for_test()


func _make_domain(territory: String) -> String:
	return CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "TestDomain_%s" % territory,
		"territory_type": territory,
	})


func _add_hex(domain_id: String, q: int, r: int) -> void:
	CampaignRepository.add_domain_hex({
		"domain_id": domain_id,
		"hex_q": q,
		"hex_r": r,
		"land_value": 5,
	})


# -----------------------------------------------------------------------------
# Trivial cases — confirm contiguous behavior is preserved
# -----------------------------------------------------------------------------

func test_empty_domain_zero() -> void:
	var d := _make_domain("wilderness")
	check(StrongholdRepository.get_effective_hex_count_for_domain(d) == 0,
		"empty domain → 0")


func test_single_hex_returns_one() -> void:
	var d := _make_domain("wilderness")
	_add_hex(d, 0, 0)
	check(StrongholdRepository.get_effective_hex_count_for_domain(d) == 1,
		"single hex → 1")


func test_two_adjacent_hexes_returns_two() -> void:
	var d := _make_domain("wilderness")
	# (0,0) and (1,0) are axial neighbors (distance 1) — contiguous.
	_add_hex(d, 0, 0)
	_add_hex(d, 1, 0)
	var n := StrongholdRepository.get_effective_hex_count_for_domain(d)
	check(n == 2, "two adjacent hexes → 2 (got %d)" % n)


func test_l_shape_all_adjacent_returns_owned_count() -> void:
	# 5-hex L: (0,0), (1,0), (2,0), (2,-1), (2,-2). All form one connected
	# component via the axial 6-neighbor rule.
	var d := _make_domain("borderlands")
	_add_hex(d, 0, 0)
	_add_hex(d, 1, 0)
	_add_hex(d, 2, 0)
	_add_hex(d, 2, -1)
	_add_hex(d, 2, -2)
	var n := StrongholdRepository.get_effective_hex_count_for_domain(d)
	check(n == 5, "contiguous L-shape → owned count (5), got %d" % n)


# -----------------------------------------------------------------------------
# Noncontiguous cases — intervening hexes must be added
# -----------------------------------------------------------------------------

func test_two_hexes_distance_two_adds_one_intervening() -> void:
	# (0,0) and (2,0) — axial distance 2, no shared neighbor in the owned set.
	# A single intervening hex (1,0) connects them.
	var d := _make_domain("wilderness")
	_add_hex(d, 0, 0)
	_add_hex(d, 2, 0)
	var n := StrongholdRepository.get_effective_hex_count_for_domain(d)
	check(n == 3, "distance-2 pair → 2 owned + 1 intervening = 3, got %d" % n)


func test_two_hexes_distance_three_adds_two_intervening() -> void:
	# (0,0) and (3,0) — axial distance 3 → 2 intervening hexes.
	var d := _make_domain("wilderness")
	_add_hex(d, 0, 0)
	_add_hex(d, 3, 0)
	var n := StrongholdRepository.get_effective_hex_count_for_domain(d)
	check(n == 4, "distance-3 pair → 2 owned + 2 intervening = 4, got %d" % n)


func test_line_of_three_with_middle_missing_adds_one() -> void:
	# Owned: (0,0), (2,0), (4,0). Three components.
	# (1,0) connects (0,0)-(2,0); (3,0) connects (2,0)-(4,0). 2 intervening.
	var d := _make_domain("borderlands")
	_add_hex(d, 0, 0)
	_add_hex(d, 2, 0)
	_add_hex(d, 4, 0)
	var n := StrongholdRepository.get_effective_hex_count_for_domain(d)
	check(n == 5, "3 components in line → 3 owned + 2 intervening = 5, got %d" % n)


func test_three_components_in_triangle() -> void:
	# (0,0), (3,0), (0,3) — three points each distance 3 from one another.
	# Greedy MST: connect two of them (cost 2 intervening hexes), then connect
	# the third to the merged set. The shortest path from the third to the
	# merged set is at least 2 intervening (distance 3 from any of the
	# nodes, but the path can reuse the existing connecting hex). With this
	# layout the minimum spanning structure adds ~4 intervening hexes.
	var d := _make_domain("civilized")
	_add_hex(d, 0, 0)
	_add_hex(d, 3, 0)
	_add_hex(d, 0, 3)
	var n := StrongholdRepository.get_effective_hex_count_for_domain(d)
	# Strict lower bound: 3 owned + 4 intervening (two distance-3 spans share
	# at most one waypoint). Strict upper bound: 3 + (2+2) = 7 in the worst
	# greedy choice. Accept either as RAW-safe (over-count is allowed).
	check(n >= 7 and n <= 7,
		"3 components in equilateral triangle → 3 owned + 4 intervening = 7, got %d" % n)


# -----------------------------------------------------------------------------
# Sufficiency integration — confirms the new count flows into is_sufficient
# -----------------------------------------------------------------------------

func test_contiguous_domain_sufficiency_unchanged() -> void:
	# 2 adjacent civilized hexes → minimum = 2 × 15,000 gp = 1,500,000 cp × 2
	#   = 3,000,000 cp.  Build a 3,000,000-cp stronghold → exactly sufficient.
	# This case is identical to pre-change behavior.
	var d := _make_domain("civilized")
	_add_hex(d, 0, 0)
	_add_hex(d, 1, 0)
	CampaignRepository.create_stronghold({
		"domain_id": d, "archetype": "fortress",
		"archetype_power_id": "stronghold_castle",
		"cp_value": 3000000, "completion_pct": 100, "status": "completed",
	})
	check(StrongholdRepository.is_sufficient_for_domain(d) == true,
		"contiguous 2-hex civilized at exact minimum (3M cp) → sufficient")


func test_noncontiguous_domain_minimum_scales_up() -> void:
	# Same 2 civilized hexes but at distance 2 (1 intervening). Effective
	# hex count = 3; minimum = 3 × 1,500,000 = 4,500,000 cp. A 3,000,000-cp
	# stronghold that was sufficient in the contiguous case is now NOT
	# sufficient — RAW §noncontiguous_domains in effect.
	var d := _make_domain("civilized")
	_add_hex(d, 0, 0)
	_add_hex(d, 2, 0)  # 1 intervening
	CampaignRepository.create_stronghold({
		"domain_id": d, "archetype": "fortress",
		"archetype_power_id": "stronghold_castle",
		"cp_value": 3000000, "completion_pct": 100, "status": "completed",
	})
	check(StrongholdRepository.is_sufficient_for_domain(d) == false,
		"noncontiguous 2-hex civilized at 3M cp (matches owned count only) → insufficient")
	# At 4,500,000 cp it becomes sufficient.
	CampaignRepository.create_stronghold({
		"domain_id": d, "archetype": "fortress",
		"archetype_power_id": "stronghold_castle",
		"cp_value": 1500000, "completion_pct": 100, "status": "completed",
	})
	check(StrongholdRepository.is_sufficient_for_domain(d) == true,
		"noncontiguous 2-hex civilized at 4.5M cp (3M + 1.5M) → sufficient")
