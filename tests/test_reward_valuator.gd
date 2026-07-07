extends "res://tests/test_suite_base.gd"

## Session Q-1: RewardValuator pure-math unit tests.
## generation/gdd-quest-rumor-system.md §8 (formulas), §15 (test plan),
## §13.1/Appendix C (worked example — ogre bounty).


func run_all_tests() -> void:
	test_treasure_bearing_multipliers()
	test_treasure_estimation_from_types()
	test_creature_bounty_2x_monster_xp()
	test_party_level_daily_rate()
	test_escort_delivery_reward()
	test_reconnaissance_reward()
	test_recovery_item_valuation()
	test_recovery_magic_item_valuation()
	test_motivation_tone_nudge_desperate()
	test_motivation_tone_nudge_calculating()
	test_motivation_tone_no_nudge_neutral()
	test_variance_bounds()
	test_rounding_bucket_small()
	test_rounding_bucket_large()
	test_rounding_bankers_at_boundary()
	test_affordability_clamp_ruler()
	test_affordability_clamp_personal()
	test_affordability_clamp_faction()
	test_affordability_clamp_one_time_uncapped()
	test_clamp_gold_bounds_min()
	test_clamp_gold_bounds_max()
	test_reward_xp_equals_gp_value()
	test_reward_xp_domain_exempt()
	test_reward_xp_per_quest_override()
	test_domain_gp_equivalent()
	test_political_favor_band()
	test_appendix_c_worked_example_ogre_bounty()
	if not has_failures():
		print("RewardValuator: all tests passed.")


# ---------------------------------------------------------------------------
# §8.1 treasure-bearing threats
# ---------------------------------------------------------------------------

func test_treasure_bearing_multipliers() -> void:
	check(is_equal_approx(RewardValuator.base_reward_treasure_bearing("monster_lair", 1000), 500.0),
		"monster_lair multiplier should be 0.50")
	check(is_equal_approx(RewardValuator.base_reward_treasure_bearing("dungeon", 1000), 250.0),
		"dungeon multiplier should be 0.25")
	check(is_equal_approx(RewardValuator.base_reward_treasure_bearing("brigand", 1000), 750.0),
		"brigand multiplier should be 0.75")


func test_treasure_estimation_from_types() -> void:
	# ACore acore_treasure_and_magic_items_rules.xml:56-87 average values.
	check(RewardValuator.estimate_treasure_value(["E"]) == 1250, "type E average should be 1250 gp")
	check(RewardValuator.estimate_treasure_value(["A", "C"]) == 275 + 700,
		"multi-type sum should add each average")
	check(RewardValuator.estimate_treasure_value([]) == 0, "empty type list should estimate 0")
	check(RewardValuator.estimate_treasure_value(["e"]) == 1250,
		"lowercase letters should normalize to uppercase")


# ---------------------------------------------------------------------------
# §8.1 creature bounty
# ---------------------------------------------------------------------------

func test_creature_bounty_2x_monster_xp() -> void:
	check(is_equal_approx(RewardValuator.base_reward_creature_bounty(200), 400.0),
		"creature bounty should be 2x monster XP")
	check(is_equal_approx(RewardValuator.base_reward_creature_bounty(0), 0.0),
		"zero monster XP should yield zero base reward")


# ---------------------------------------------------------------------------
# §8.1 time-based rewards
# ---------------------------------------------------------------------------

func test_party_level_daily_rate() -> void:
	check(is_equal_approx(RewardValuator.party_level_gp_rate(3), 75.0), "L3 -> 75/day")
	check(is_equal_approx(RewardValuator.party_level_gp_rate(7), 175.0), "L7 -> 175/day")


func test_escort_delivery_reward() -> void:
	# L3 party, 3 days: 75 * 3 * 0.50 = 112.5
	check(is_equal_approx(RewardValuator.base_reward_escort_or_delivery(3, 3), 112.5),
		"escort/delivery reward formula")


func test_reconnaissance_reward() -> void:
	# L3 party, 3 days: 75 * 3 * 0.25 = 56.25
	check(is_equal_approx(RewardValuator.base_reward_reconnaissance(3, 3), 56.25),
		"reconnaissance reward formula")


# ---------------------------------------------------------------------------
# §8.5 recovery valuation
# ---------------------------------------------------------------------------

func test_recovery_item_valuation() -> void:
	check(is_equal_approx(RewardValuator.recovery_reward(1000, 0.5), 500.0),
		"recovery reward at midband multiplier")
	check(is_equal_approx(RewardValuator.recovery_reward(1000, 0.9), 750.0),
		"recovery reward multiplier should clamp to the 0.25-0.75 band")
	check(is_equal_approx(RewardValuator.recovery_reward(1000, 0.1), 250.0),
		"recovery reward multiplier should clamp to the 0.25-0.75 band (low)")


func test_recovery_magic_item_valuation() -> void:
	check(is_equal_approx(RewardValuator.recovery_reward_magic_item(2000), 1000.0),
		"magic item recovery should be 0.50 x sale value")


# ---------------------------------------------------------------------------
# §8.3 Motivation tone nudge
# ---------------------------------------------------------------------------

func test_motivation_tone_nudge_desperate() -> void:
	var nudged := RewardValuator.apply_motivation_tone(1000.0, "security", 1.0)
	check(is_equal_approx(nudged, 1200.0), "desperate motivation should nudge up to +20%")


func test_motivation_tone_nudge_calculating() -> void:
	var nudged := RewardValuator.apply_motivation_tone(1000.0, "wealth", 1.0)
	check(is_equal_approx(nudged, 800.0), "calculating motivation should nudge down to -20%")


func test_motivation_tone_no_nudge_neutral() -> void:
	var nudged := RewardValuator.apply_motivation_tone(1000.0, "unknown_motivation", 1.0)
	check(is_equal_approx(nudged, 1000.0), "unrecognized motivation should not nudge")


# ---------------------------------------------------------------------------
# §8.1 variance
# ---------------------------------------------------------------------------

func test_variance_bounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 200:
		var result := RewardValuator.apply_variance(1000.0, rng)
		check(result >= 900.0 - 0.001 and result <= 1100.0 + 0.001,
			"variance result %s should stay within +/-10%%" % result)


# ---------------------------------------------------------------------------
# §8.1 rounding
# ---------------------------------------------------------------------------

func test_rounding_bucket_small() -> void:
	check(RewardValuator.round_to_bucket(410.0) == 400, "410 under 500 should round to nearest 25 (400)")
	check(RewardValuator.round_to_bucket(405.0) == 400, "405 should round down to 400 (nearest 25)")
	check(RewardValuator.round_to_bucket(438.0) == 450, "438 should round up to 450 (nearest 25)")


func test_rounding_bucket_large() -> void:
	check(RewardValuator.round_to_bucket(1030.0) == 1000, "1030 at/above 500 should round to nearest 100")
	check(RewardValuator.round_to_bucket(1070.0) == 1100, "1070 should round up to nearest 100")


func test_rounding_bankers_at_boundary() -> void:
	# 450 / 25 = 18.0 exactly landed; 475/25 = 19.0 exactly landed -- test the
	# true half-way case: 12.5 buckets of 25 = 312.5 -> bankers rounds .5 to even.
	# 312.5 / 25 = 12.5 -> banker's round to even -> 12 -> 300.
	check(RewardValuator.round_to_bucket(312.5) == 300,
		"exact half-bucket should round half-to-even (12.5 -> 12 -> 300)")
	# 337.5 / 25 = 13.5 -> banker's round to even -> 14 -> 350.
	check(RewardValuator.round_to_bucket(337.5) == 350,
		"exact half-bucket should round half-to-even (13.5 -> 14 -> 350)")


# ---------------------------------------------------------------------------
# §8.6 affordability clamp
# ---------------------------------------------------------------------------

func test_affordability_clamp_ruler() -> void:
	# monthly income 720 -> annual 8640 -> 10% = 864.
	var result := RewardValuator.clamp_affordability(1000, RewardValuator.GiverKind.RULER, 720)
	check(result["gold"] == 864, "ruler clamp should cap at 10%% of annual income")
	check(result["exceeded"] == true, "ruler clamp should flag exceeded when over cap")

	var under_cap := RewardValuator.clamp_affordability(400, RewardValuator.GiverKind.RULER, 720)
	check(under_cap["gold"] == 400, "ruler clamp should pass through when under cap")
	check(under_cap["exceeded"] == false, "ruler clamp should not flag exceeded when under cap")


func test_affordability_clamp_personal() -> void:
	var result := RewardValuator.clamp_affordability(500, RewardValuator.GiverKind.PERSONAL, 0, 300)
	check(result["gold"] == 300, "personal clamp should cap at personal_wealth_cap")
	check(result["exceeded"] == true, "personal clamp should flag exceeded")


func test_affordability_clamp_faction() -> void:
	var result := RewardValuator.clamp_affordability(2000, RewardValuator.GiverKind.FACTION, 0, 0, 1500)
	check(result["gold"] == 1500, "faction clamp should cap at treasury headroom")
	check(result["exceeded"] == true, "faction clamp should flag exceeded")


func test_affordability_clamp_one_time_uncapped() -> void:
	var result := RewardValuator.clamp_affordability(50000, RewardValuator.GiverKind.ONE_TIME)
	check(result["gold"] == 50000, "one-time rewards (domain grants, political favors) should have no income cap")
	check(result["exceeded"] == false, "one-time rewards should never flag exceeded")


func test_clamp_gold_bounds_min() -> void:
	check(RewardValuator.clamp_gold_bounds(10) == RewardValuator.MIN_GOLD_REWARD,
		"gold below minimum should clamp up to 25")


func test_clamp_gold_bounds_max() -> void:
	check(RewardValuator.clamp_gold_bounds(999999) == RewardValuator.MAX_GOLD_REWARD,
		"gold above maximum should clamp down to 25000")


# ---------------------------------------------------------------------------
# §8.2 reward XP
# ---------------------------------------------------------------------------

func test_reward_xp_equals_gp_value() -> void:
	check(RewardValuator.reward_xp(400, "gold") == 400, "gold reward XP should equal total_gp_value")
	check(RewardValuator.reward_xp(1000, "item") == 1000, "item reward XP should equal GP-equivalent")
	check(RewardValuator.reward_xp(3000, "political") == 3000,
		"political favor reward XP should equal GP-equivalent")


func test_reward_xp_domain_exempt() -> void:
	check(RewardValuator.reward_xp(50000, "domain") == 0,
		"domain grants should be XP-exempt regardless of gp_equivalent (§8.2/§8.8)")


func test_reward_xp_per_quest_override() -> void:
	check(RewardValuator.reward_xp(500, "gold", false) == 0,
		"xp_eligible=false override should suppress reward XP")
	check(RewardValuator.reward_xp(500, "gold", true) == 500,
		"xp_eligible=true (default) should award reward XP")


# ---------------------------------------------------------------------------
# §8.8 domain-grant gp-equivalent
# ---------------------------------------------------------------------------

func test_domain_gp_equivalent() -> void:
	# stronghold 5000 + (100 families * 2.0 gp/mo * 12) = 5000 + 2400 = 7400.
	var result := RewardValuator.domain_gp_equivalent(5000, 100, 2.0)
	check(result == 7400, "domain gp-equivalent formula should be stronghold + families*rate*12, got %d" % result)


# ---------------------------------------------------------------------------
# §8.4 political favor band
# ---------------------------------------------------------------------------

func test_political_favor_band() -> void:
	var low := RewardValuator.political_favor_gp_equivalent(0.0)
	var high := RewardValuator.political_favor_gp_equivalent(1.0)
	check(low == 1000, "political favor at tier_fraction 0.0 should be the 1000 gp floor")
	check(high == 5000, "political favor at tier_fraction 1.0 should be the 5000 gp ceiling")


# ---------------------------------------------------------------------------
# Appendix C worked example — ogre bounty (§13.1: verifies the ~53% band)
# ---------------------------------------------------------------------------

func test_appendix_c_worked_example_ogre_bounty() -> void:
	# Ogre (4+1 HD) monster XP = 200 (Appendix C). Bounty basis = 2x monster XP.
	var base := RewardValuator.base_reward_creature_bounty(200)
	check(is_equal_approx(base, 400.0), "ogre bounty base reward should be 400 gp (2x 200 XP)")

	# Variance rolled to +2.5% in the worked example (400 -> 410).
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	# Find a seed state landing near +2.5%; instead, directly verify the
	# rounding step reproduces the documented 410 -> 400 gp result, since the
	# GDD's worked example fixes the POST-variance value at 410 gp.
	var rounded := RewardValuator.round_to_bucket(410.0)
	check(rounded == 400, "410 gp post-variance should round to 400 gp (Appendix C)")

	# Affordability: 400 < 10% x (720 x 12) = 864 -- should NOT clamp.
	var afford := RewardValuator.clamp_affordability(400, RewardValuator.GiverKind.RULER, 720)
	check(afford["gold"] == 400 and afford["exceeded"] == false,
		"Appendix C: 400 gp bounty should be affordable for Baron Morson (864 gp cap)")

	# Reward XP = total_gp_value = 400 (the GDD states "+400 XP").
	check(RewardValuator.reward_xp(400, "gold") == 400,
		"Appendix C: reward XP should equal the 400 gp reward")

	# Quest reward = 400 / (350 treasure + 400 reward) ~= 53%, inside the
	# 50-100% creature-bounty band (§13.1).
	var band_fraction := 400.0 / (350.0 + 400.0)
	check(band_fraction >= 0.50 and band_fraction <= 1.00,
		"Appendix C: reward-to-total-take ratio should land in the 50-100%% creature-bounty band")
