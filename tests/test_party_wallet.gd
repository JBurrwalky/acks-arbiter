extends "res://tests/test_suite_base.gd"

## Unit tests for PartyWallet — gold aggregation, payment, and distribution.
## Seeds test characters with known coin inventories into the DB, exercises
## PartyWallet methods, and verifies outcomes. Cleans up after itself.

const TEST_CAMPAIGN := "test_pw_campaign"
const TEST_PARTY := "test_pw_party"
const PC_A := "test_pw_pc_a"
const PC_B := "test_pw_pc_b"
const PC_C := "test_pw_pc_c"
const HENCH_D := "test_pw_hench_d"


func run_all_tests() -> void:
	# Eligibility
	test_contributors_excludes_henchmen()
	test_contributors_active_first()
	test_contributors_single_pc()
	test_contributors_empty_party()

	# Aggregation
	test_party_total_cp_sums_pcs()
	test_party_breakdown_aggregates()
	test_party_total_gp_float()

	# Affordability
	test_can_afford_true()
	test_can_afford_false_with_shortfall()
	test_can_afford_pooled()

	# Payment
	test_pay_single_pc_sufficient()
	test_pay_spans_multiple_pcs()
	test_pay_insufficient_fails()
	test_pay_deduction_order()
	test_pay_from_character_success()
	test_pay_from_character_failure()

	# Distribution
	test_deposit_to_character()
	test_deposit_even_split_exact()
	test_deposit_even_split_remainder_to_poorest()
	test_deposit_by_shares()

	if not has_failures():
		print("PartyWallet: all tests passed.")


# ---------------------------------------------------------------------------
# Test data setup / teardown
# ---------------------------------------------------------------------------

func _setup_party(pc_a_gp: int, pc_b_gp: int, pc_c_gp: int = 0, include_henchman: bool = false) -> void:
	_cleanup()

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "PW Test"])

	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[TEST_PARTY, TEST_CAMPAIGN, "Test Party"])

	# Create PCs.
	_create_character(PC_A, "Alice", "pc", pc_a_gp)
	_add_to_party(PC_A, 0)
	_create_character(PC_B, "Bob", "pc", pc_b_gp)
	_add_to_party(PC_B, 1)
	if pc_c_gp > 0:
		_create_character(PC_C, "Carol", "pc", pc_c_gp)
		_add_to_party(PC_C, 2)

	if include_henchman:
		_create_character(HENCH_D, "Dirk", "henchman", 50)
		_add_to_party(HENCH_D, 3)


func _create_character(id: String, char_name: String, char_type: String, gold_gp: int) -> void:
	CampaignRepository.create_character({
		"id": id,
		"campaign_id": TEST_CAMPAIGN,
		"name": char_name,
		"character_type": char_type,
		"persistence_tier": "full",
		"race": "human",
		"character_class": "fighter",
		"level": 1,
		"xp": 0,
		"combat_progression": "fighter",
		"strength": 10,
		"intelligence": 10,
		"wisdom": 10,
		"dexterity": 10,
		"constitution": 10,
		"charisma": 10,
	})
	# Give gold (in GP → convert to CP for add_coins_cp).
	if gold_gp > 0:
		CampaignRepository.add_coins_cp(id, gold_gp * 100)


func _add_to_party(character_id: String, slot: int) -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO party_members (party_id, character_id, formation_slot) VALUES (?, ?, ?)",
		[TEST_PARTY, character_id, "middle"])


func _cleanup() -> void:
	for char_id in [PC_A, PC_B, PC_C, HENCH_D]:
		# Remove coins (inventory items).
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM inventory_items WHERE character_id = ?", [char_id])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM party_members WHERE character_id = ?", [char_id])
		CampaignRepository.db.query_with_bindings(
			"DELETE FROM characters WHERE id = ?", [char_id])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [TEST_PARTY])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [TEST_CAMPAIGN])


func _get_wealth(character_id: String) -> int:
	return CampaignRepository.get_character_wealth_cp(character_id)


# ---------------------------------------------------------------------------
# Eligibility tests
# ---------------------------------------------------------------------------

func test_contributors_excludes_henchmen() -> void:
	_setup_party(100, 50, 0, true)
	var contributors := PartyWallet.get_contributors(TEST_PARTY, PC_A)
	check(PC_A in contributors, "PC_A should be a contributor")
	check(PC_B in contributors, "PC_B should be a contributor")
	check(HENCH_D not in contributors, "Henchman should NOT be a contributor")
	_cleanup()
	print("  contributors_excludes_henchmen: OK")


func test_contributors_active_first() -> void:
	_setup_party(100, 50)
	var contributors := PartyWallet.get_contributors(TEST_PARTY, PC_B)
	check(contributors[0] == PC_B, "Active character (PC_B) should be first, got %s" % contributors[0])
	_cleanup()
	print("  contributors_active_first: OK")


func test_contributors_single_pc() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "PW Test"])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[TEST_PARTY, TEST_CAMPAIGN, "Test Party"])
	_create_character(PC_A, "Alice", "pc", 100)
	_add_to_party(PC_A, 0)
	var contributors := PartyWallet.get_contributors(TEST_PARTY, PC_A)
	check(contributors.size() == 1, "Single-PC party should have 1 contributor, got %d" % contributors.size())
	check(contributors[0] == PC_A, "Should be PC_A")
	_cleanup()
	print("  contributors_single_pc: OK")


func test_contributors_empty_party() -> void:
	_cleanup()
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[TEST_CAMPAIGN, "PW Test"])
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[TEST_PARTY, TEST_CAMPAIGN, "Test Party"])
	var contributors := PartyWallet.get_contributors(TEST_PARTY, "nonexistent")
	check(contributors.is_empty(), "Empty party should have 0 contributors")
	_cleanup()
	print("  contributors_empty_party: OK")


# ---------------------------------------------------------------------------
# Aggregation tests
# ---------------------------------------------------------------------------

func test_party_total_cp_sums_pcs() -> void:
	_setup_party(100, 50, 25, true)
	var total := PartyWallet.get_party_total_cp(TEST_PARTY)
	# 100gp + 50gp + 25gp = 175gp = 17500cp. Henchman's 50gp excluded.
	check(total == 17500, "Party total should be 17500cp, got %d" % total)
	_cleanup()
	print("  party_total_cp_sums_pcs: OK")


func test_party_breakdown_aggregates() -> void:
	_setup_party(100, 50)
	var bd := PartyWallet.get_party_breakdown(TEST_PARTY)
	# 100gp + 50gp = 150gp = 15000cp.
	check(bd["total_cp"] == 15000, "Breakdown total_cp should be 15000, got %d" % bd["total_cp"])
	# add_coins_cp distributes to largest denominations:
	# 100gp = 10000cp → cp_to_coins → coins_pp: 20 (20*500=10000)
	# 50gp  = 5000cp  → cp_to_coins → coins_pp: 10 (10*500=5000)
	# So total coins_pp should be 30
	check(bd["coins_pp"] == 30, "Breakdown coins_pp should be 30, got %d" % bd["coins_pp"])
	_cleanup()
	print("  party_breakdown_aggregates: OK")


func test_party_total_gp_float() -> void:
	_setup_party(100, 50)
	var gp_float := PartyWallet.get_party_total_gp_float(TEST_PARTY)
	check(is_equal_approx(gp_float, 150.0), "GP float should be 150.0, got %.2f" % gp_float)
	_cleanup()
	print("  party_total_gp_float: OK")


# ---------------------------------------------------------------------------
# Affordability tests
# ---------------------------------------------------------------------------

func test_can_afford_true() -> void:
	_setup_party(100, 50)
	var result := PartyWallet.can_afford(10000, TEST_PARTY, PC_A)  # 100gp
	check(result["ok"], "Party with 150gp should afford 100gp")
	check(result["shortfall_cp"] == 0, "No shortfall expected")
	_cleanup()
	print("  can_afford_true: OK")


func test_can_afford_false_with_shortfall() -> void:
	_setup_party(100, 50)
	var result := PartyWallet.can_afford(20000, TEST_PARTY, PC_A)  # 200gp
	check(not result["ok"], "Party with 150gp should NOT afford 200gp")
	check(result["shortfall_cp"] == 5000, "Shortfall should be 5000cp (50gp), got %d" % result["shortfall_cp"])
	_cleanup()
	print("  can_afford_false_with_shortfall: OK")


func test_can_afford_pooled() -> void:
	_setup_party(80, 80)
	# Each has 80gp alone, but together 160gp. Test 120gp (needs pooling).
	var result := PartyWallet.can_afford(12000, TEST_PARTY, PC_A)
	check(result["ok"], "Pooled 160gp should afford 120gp")
	_cleanup()
	print("  can_afford_pooled: OK")


# ---------------------------------------------------------------------------
# Payment tests
# ---------------------------------------------------------------------------

func test_pay_single_pc_sufficient() -> void:
	_setup_party(100, 50)
	var before_a := _get_wealth(PC_A)
	var result := PartyWallet.pay(5000, TEST_PARTY, PC_A)  # 50gp
	check(result["ok"], "Payment should succeed")
	check(result["total_paid_cp"] == 5000, "total_paid_cp should be 5000")
	var after_a := _get_wealth(PC_A)
	check(after_a == before_a - 5000, "PC_A should have lost 5000cp, lost %d" % (before_a - after_a))
	# PC_B unchanged.
	check(_get_wealth(PC_B) == 5000, "PC_B should be unchanged at 5000cp")
	_cleanup()
	print("  pay_single_pc_sufficient: OK")


func test_pay_spans_multiple_pcs() -> void:
	_setup_party(100, 50)
	# PC_A has 10000cp (100gp), PC_B has 5000cp (50gp). Pay 12000cp (120gp).
	var result := PartyWallet.pay(12000, TEST_PARTY, PC_A)
	check(result["ok"], "Payment should succeed with pooling")
	# PC_A should be drained (10000cp → 0), PC_B covers remaining 2000cp.
	check(_get_wealth(PC_A) == 0, "PC_A should be 0, got %d" % _get_wealth(PC_A))
	check(_get_wealth(PC_B) == 3000, "PC_B should be 3000cp (5000-2000), got %d" % _get_wealth(PC_B))
	_cleanup()
	print("  pay_spans_multiple_pcs: OK")


func test_pay_insufficient_fails() -> void:
	_setup_party(100, 50)
	var before_a := _get_wealth(PC_A)
	var before_b := _get_wealth(PC_B)
	var result := PartyWallet.pay(20000, TEST_PARTY, PC_A)  # 200gp, party only has 150gp
	check(not result["ok"], "Payment should fail")
	check(result["total_paid_cp"] == 0, "Nothing should be paid")
	# No coins should have been deducted.
	check(_get_wealth(PC_A) == before_a, "PC_A should be unchanged")
	check(_get_wealth(PC_B) == before_b, "PC_B should be unchanged")
	_cleanup()
	print("  pay_insufficient_fails: OK")


func test_pay_deduction_order() -> void:
	_setup_party(30, 30)
	# PC_A=3000cp, PC_B=3000cp. Pay 4000cp. Active=PC_A should pay first.
	var result := PartyWallet.pay(4000, TEST_PARTY, PC_A)
	check(result["ok"], "Payment should succeed")
	# PC_A drained (3000cp → 0), PC_B covers 1000cp (3000 → 2000).
	check(_get_wealth(PC_A) == 0, "Active PC_A should be drained first, got %d" % _get_wealth(PC_A))
	check(_get_wealth(PC_B) == 2000, "PC_B should have 2000cp remaining, got %d" % _get_wealth(PC_B))
	_cleanup()
	print("  pay_deduction_order: OK")


func test_pay_from_character_success() -> void:
	_setup_party(100, 50)
	var result := PartyWallet.pay_from_character(PC_B, 3000)  # 30gp from PC_B only
	check(result["ok"], "pay_from_character should succeed")
	check(_get_wealth(PC_B) == 2000, "PC_B should be 2000cp, got %d" % _get_wealth(PC_B))
	check(_get_wealth(PC_A) == 10000, "PC_A should be untouched at 10000cp")
	_cleanup()
	print("  pay_from_character_success: OK")


func test_pay_from_character_failure() -> void:
	_setup_party(100, 50)
	var result := PartyWallet.pay_from_character(PC_B, 6000)  # 60gp, PC_B only has 50gp
	check(not result["ok"], "pay_from_character should fail")
	check(_get_wealth(PC_B) == 5000, "PC_B should be unchanged at 5000cp")
	_cleanup()
	print("  pay_from_character_failure: OK")


# ---------------------------------------------------------------------------
# Distribution tests
# ---------------------------------------------------------------------------

func test_deposit_to_character() -> void:
	_setup_party(100, 50)
	PartyWallet.deposit_to_character(PC_B, 2500)  # +25gp
	check(_get_wealth(PC_B) == 7500, "PC_B should be 7500cp (5000+2500), got %d" % _get_wealth(PC_B))
	_cleanup()
	print("  deposit_to_character: OK")


func test_deposit_even_split_exact() -> void:
	_setup_party(0, 0)
	var result := PartyWallet.deposit_to_party_even_split(TEST_PARTY, 1000, PC_A)
	check(result["ok"], "Even split should succeed")
	# 1000cp / 2 = 500cp each.
	check(_get_wealth(PC_A) == 500, "PC_A should get 500cp, got %d" % _get_wealth(PC_A))
	check(_get_wealth(PC_B) == 500, "PC_B should get 500cp, got %d" % _get_wealth(PC_B))
	_cleanup()
	print("  deposit_even_split_exact: OK")


func test_deposit_even_split_remainder_to_poorest() -> void:
	_setup_party(100, 0)
	# PC_A has 10000cp, PC_B has 0cp. Split 1001cp between them.
	# base = 500 each, remainder = 1. Poorest = PC_B (0cp). PC_B gets 501, PC_A gets 500.
	var result := PartyWallet.deposit_to_party_even_split(TEST_PARTY, 1001, PC_A)
	check(result["ok"], "Even split should succeed")
	check(_get_wealth(PC_A) == 10500, "PC_A should be 10000+500=10500, got %d" % _get_wealth(PC_A))
	check(_get_wealth(PC_B) == 501, "PC_B (poorest) should be 0+501=501, got %d" % _get_wealth(PC_B))
	_cleanup()
	print("  deposit_even_split_remainder_to_poorest: OK")


func test_deposit_by_shares() -> void:
	_setup_party(0, 0, 0, false)
	# PC_A gets 60% of 1000cp = 600, PC_B gets 40% = 400.
	var shares := {PC_A: 3.0, PC_B: 2.0}  # 3:2 ratio
	var result := PartyWallet.deposit_to_party_by_shares(TEST_PARTY, 1000, shares)
	check(result["ok"], "By-shares split should succeed")
	check(_get_wealth(PC_A) == 600, "PC_A should get 600cp (60%%), got %d" % _get_wealth(PC_A))
	check(_get_wealth(PC_B) == 400, "PC_B should get 400cp (40%%), got %d" % _get_wealth(PC_B))
	_cleanup()
	print("  deposit_by_shares: OK")
