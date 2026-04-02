extends Node

## Unit tests for XPAwardCalculator.
## Source rules: acore_adventures_and_encounters.xml, acore-campaign-hijinks.xml.


func run_all_tests() -> void:
	test_monster_xp_basic()
	test_monster_xp_with_abilities()
	test_monster_xp_high_hd()
	test_party_shares_even()
	test_party_shares_with_henchmen()
	test_prime_req_adjustment_positive()
	test_prime_req_adjustment_negative()
	test_prime_req_adjustment_bankers_round()
	test_clamp_to_one_level()
	test_domain_xp_above_threshold()
	test_domain_xp_below_threshold()
	test_domain_xp_henchman()
	test_bankers_round_half_even()
	test_bankers_round_half_odd()
	print("XPAwardCalculator: all tests passed.")


func test_monster_xp_basic() -> void:
	## HD 1, 0 special abilities = base 10 + 0 = 10.
	var xp := XPAwardCalculator.calculate_monster_xp("1", 0)
	assert(xp == 10, "HD1 no abilities: expected 10, got %d" % xp)
	print("  monster_xp_basic: OK")


func test_monster_xp_with_abilities() -> void:
	## HD 5, 2 special abilities = 200 + (150 * 2) = 500.
	var xp := XPAwardCalculator.calculate_monster_xp("5", 2)
	assert(xp == 500, "HD5 2 abilities: expected 500, got %d" % xp)
	print("  monster_xp_with_abilities: OK")


func test_monster_xp_high_hd() -> void:
	## HD 22 = HD 21 + 1 step.
	## Base = 3000 + 250 = 3250. Bonus/ability = 2000 + 250 = 2250.
	## With 0 abilities: 3250.
	var xp_0 := XPAwardCalculator.calculate_monster_xp("22", 0)
	assert(xp_0 == 3250, "HD22 0 abilities: expected 3250, got %d" % xp_0)
	## With 1 ability: 3250 + 2250 = 5500.
	var xp_1 := XPAwardCalculator.calculate_monster_xp("22", 1)
	assert(xp_1 == 5500, "HD22 1 ability: expected 5500, got %d" % xp_1)
	print("  monster_xp_high_hd: OK")


func test_party_shares_even() -> void:
	## 3 PCs, 900 XP total → 300 each.
	var members := [
		{"character_id": "a", "is_henchman": false},
		{"character_id": "b", "is_henchman": false},
		{"character_id": "c", "is_henchman": false},
	]
	var shares := XPAwardCalculator.calculate_party_shares(900, members)
	assert(shares["a"] == 300, "PC a: expected 300, got %d" % shares["a"])
	assert(shares["b"] == 300, "PC b: expected 300, got %d" % shares["b"])
	assert(shares["c"] == 300, "PC c: expected 300, got %d" % shares["c"])
	print("  party_shares_even: OK")


func test_party_shares_with_henchmen() -> void:
	## 2 PCs + 1 henchman = 2.5 shares.
	## 500 XP / 2.5 = 200 per share.
	## PC = 200, henchman = 100.
	var members := [
		{"character_id": "pc1", "is_henchman": false},
		{"character_id": "pc2", "is_henchman": false},
		{"character_id": "hm1", "is_henchman": true},
	]
	var shares := XPAwardCalculator.calculate_party_shares(500, members)
	assert(shares["pc1"] == 200, "PC1: expected 200, got %d" % shares["pc1"])
	assert(shares["pc2"] == 200, "PC2: expected 200, got %d" % shares["pc2"])
	assert(shares["hm1"] == 100, "Henchman: expected 100, got %d" % shares["hm1"])
	print("  party_shares_with_henchmen: OK")


func test_prime_req_adjustment_positive() -> void:
	## +10% on 200 XP = 220.
	var result := XPAwardCalculator.apply_prime_req_adjustment(200, 10)
	assert(result == 220, "+10%% on 200: expected 220, got %d" % result)
	print("  prime_req_adjustment_positive: OK")


func test_prime_req_adjustment_negative() -> void:
	## -5% on 200 XP = 190.
	var result := XPAwardCalculator.apply_prime_req_adjustment(200, -5)
	assert(result == 190, "-5%% on 200: expected 190, got %d" % result)
	print("  prime_req_adjustment_negative: OK")


func test_prime_req_adjustment_bankers_round() -> void:
	## +5% on 100 XP = 100 * 1.05 = 105.0 (exact, no rounding needed).
	var r1 := XPAwardCalculator.apply_prime_req_adjustment(100, 5)
	assert(r1 == 105, "+5%% on 100: expected 105, got %d" % r1)

	## +5% on 10 XP = 10 * 1.05 = 10.5 → Banker's: floor=10, half, even → 10.
	var r2 := XPAwardCalculator.apply_prime_req_adjustment(10, 5)
	assert(r2 == 10, "+5%% on 10 (Banker's: 10.5 → 10): expected 10, got %d" % r2)

	## +5% on 30 XP = 30 * 1.05 = 31.5 → Banker's: floor=31, half, odd → 32.
	var r3 := XPAwardCalculator.apply_prime_req_adjustment(30, 5)
	assert(r3 == 32, "+5%% on 30 (Banker's: 31.5 → 32): expected 32, got %d" % r3)
	print("  prime_req_adjustment_bankers_round: OK")


func test_clamp_to_one_level() -> void:
	## Fighter L1 (xp=0, xp_for_next=2000). Awarding 5000 XP would jump to L3.
	## L3 threshold for fighter = 4000. So cap = 4000 - 1 - 0 = 3999.
	var class_reg := ClassRegistry.new()
	var calc := XPAwardCalculator.new(class_reg)

	var fighter := CharacterData.new()
	fighter.character_class = "fighter"
	fighter.level = 1
	fighter.xp = 0
	fighter.xp_for_next_level = 2000
	fighter.max_level = 14

	var clamped := calc.clamp_to_one_level(fighter, 5000)
	# L3 threshold = 4000. cap = 4000 - 1 - 0 = 3999.
	assert(clamped == 3999, "Fighter L1 clamped from 5000 to 3999 (L3-1), got %d" % clamped)

	# Award that wouldn't exceed two levels should not be clamped.
	var not_clamped := calc.clamp_to_one_level(fighter, 1000)
	assert(not_clamped == 1000, "Fighter L1 award of 1000 should not be clamped, got %d" % not_clamped)
	print("  clamp_to_one_level: OK")


func test_domain_xp_above_threshold() -> void:
	## Level 9, threshold=12000, income=15000 → XP = 3000.
	var calc := XPAwardCalculator.new(ClassRegistry.new())
	var xp := calc.calculate_domain_xp(15000, 9, false)
	assert(xp == 3000, "Level 9 domain XP: expected 3000, got %d" % xp)
	print("  domain_xp_above_threshold: OK")


func test_domain_xp_below_threshold() -> void:
	## Level 9, threshold=12000, income=10000 → XP = 0.
	var calc := XPAwardCalculator.new(ClassRegistry.new())
	var xp := calc.calculate_domain_xp(10000, 9, false)
	assert(xp == 0, "Level 9 domain XP below threshold: expected 0, got %d" % xp)
	print("  domain_xp_below_threshold: OK")


func test_domain_xp_henchman() -> void:
	## Henchman earns 50% of domain XP.
	## Level 9, income=15000 → base 3000 → henchman gets 1500.
	var calc := XPAwardCalculator.new(ClassRegistry.new())
	var xp := calc.calculate_domain_xp(15000, 9, true)
	assert(xp == 1500, "Henchman domain XP: expected 1500, got %d" % xp)
	print("  domain_xp_henchman: OK")


func test_bankers_round_half_even() -> void:
	## 2.5 → 2 (floor is 2, even → round down).
	var r := XPAwardCalculator.bankers_round(2.5)
	assert(r == 2, "bankers_round(2.5) should be 2, got %d" % r)
	print("  bankers_round_half_even: OK")


func test_bankers_round_half_odd() -> void:
	## 3.5 → 4 (floor is 3, odd → round up).
	var r := XPAwardCalculator.bankers_round(3.5)
	assert(r == 4, "bankers_round(3.5) should be 4, got %d" % r)
	print("  bankers_round_half_odd: OK")
