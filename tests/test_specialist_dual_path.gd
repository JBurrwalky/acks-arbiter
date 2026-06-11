extends "res://tests/test_suite_base.gd"

## Tests for the dual-path specialist system (gdd-specialists.md v2.0,
## 2026-06-11): catalog path flags + services + deterministic availability,
## the SpecialistCommissionManager lifecycle (commission → lazy-ready →
## settlement-gated collect → deliverable grant), and the monthly-engagement
## availability subtraction.
##
## RAW anchors: flat monthly fee acore_equipment.xml:663-668; sage 500gp/mo
## :960-966; alchemist 250gp/mo :877-884; availability rows :709-728.


const CAMPAIGN_ID := "test_specdual_campaign"
const PARTY_ID := "test_specdual_party"
const PC_ID := "test_specdual_pc"
const SETTLEMENT_ID := "test_specdual_town"


## PartyWallet stand-in. `allow` controls affordability; `paid_cp` records.
class _FakeWallet:
	extends RefCounted
	var allow: bool = true
	var paid_cp: Array = []
	func pay(cost_cp: int, _party_id: String, _character_id: String) -> Dictionary:
		if not allow:
			return {"ok": false, "message": "Insufficient party funds."}
		paid_cp.append(cost_cp)
		return {"ok": true, "message": "", "total_paid_cp": cost_cp}


var _commissioned_events: Array = []
var _collected_events: Array = []


func run_all_tests() -> void:
	test_catalog_dual_path_flags_and_services()
	test_catalog_availability_deterministic_and_none()
	test_commission_creates_row_and_debits_wallet()
	test_commission_requires_subject_when_flagged()
	test_commission_fails_on_wallet_refusal()
	test_collect_gates_on_ready_and_settlement()
	test_collect_report_marks_collected_once()
	test_alchemist_brew_prices_from_catalog_and_grants_item()
	test_engagements_subtract_from_monthly_availability()
	if not has_failures():
		print("SpecialistDualPath: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _setup() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM specialist_commissions WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM specialists WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [PC_ID])
	db.query_with_bindings(
		"DELETE FROM party_members WHERE party_id = ?", [PARTY_ID])
	db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [PC_ID])
	db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [PARTY_ID])
	db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [PARTY_ID])
	db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)",
		[CAMPAIGN_ID, "test specialist dual path"])
	db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[PARTY_ID, CAMPAIGN_ID, "Dual Path Party"])
	db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'Payer', 'pc')
	""", [PC_ID, CAMPAIGN_ID])
	_commissioned_events.clear()
	_collected_events.clear()
	EventBus.specialist_commissioned.connect(_on_commissioned)
	EventBus.specialist_commission_collected.connect(_on_collected)


func _teardown() -> void:
	EventBus.specialist_commissioned.disconnect(_on_commissioned)
	EventBus.specialist_commission_collected.disconnect(_on_collected)
	var db = CampaignRepository.db
	db.query_with_bindings(
		"DELETE FROM specialist_commissions WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM specialists WHERE campaign_id = ?", [CAMPAIGN_ID])
	db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [PC_ID])
	db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [PC_ID])
	db.query_with_bindings(
		"DELETE FROM party_state WHERE party_id = ?", [PARTY_ID])
	db.query_with_bindings(
		"DELETE FROM parties WHERE id = ?", [PARTY_ID])


func _on_commissioned(party_id: String, data: Dictionary) -> void:
	if party_id == PARTY_ID:
		_commissioned_events.append(data)


func _on_collected(party_id: String, data: Dictionary) -> void:
	if party_id == PARTY_ID:
		_collected_events.append(data)


func _manager(wallet) -> SpecialistCommissionManager:
	return SpecialistCommissionManager.new(CampaignRepository, EventBus, wallet)


# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------

func test_catalog_dual_path_flags_and_services() -> void:
	check(SpecialistCatalog.can_retain("pathfinder"), "pathfinder retains")
	check(not SpecialistCatalog.can_commission("pathfinder"), "pathfinder has no services")
	check(SpecialistCatalog.can_retain("sage"), "sage retains (travels to investigate)")
	check(SpecialistCatalog.can_commission("sage"), "sage commissions")
	check(not SpecialistCatalog.can_retain("alchemist"), "alchemist is commission-only in v2")
	check(SpecialistCatalog.can_commission("alchemist"), "alchemist commissions")

	check(SpecialistCatalog.services("sage").size() == 2, "sage offers 2 services")
	var research := SpecialistCatalog.get_service("sage", "sage_research_topic")
	check(int(research.get("cost_cp", 0)) == 50000,
		"research topic = 500gp (one month of the RAW retainer)")
	check(int(research.get("duration_days", 0)) == 30, "research takes 30 days")
	check(str(research.get("result_kind", "")) == "report", "research delivers a report")
	check(bool(research.get("needs_subject", false)), "research needs a subject")

	check(int(SpecialistCatalog.monthly_wage_cp("sage")) == 50000,
		"sage wage 500gp/month per acore_equipment.xml:960")
	check(int(SpecialistCatalog.monthly_wage_cp("alchemist")) == 25000,
		"alchemist wage 250gp/month per acore_equipment.xml:877")


func test_catalog_availability_deterministic_and_none() -> void:
	# Same seed inputs → same roll (the panel never rerolls on reopen).
	var a := SpecialistCatalog.monthly_availability("sage", 1, "c1", "s1", 7)
	var b := SpecialistCatalog.monthly_availability("sage", 1, "c1", "s1", 7)
	check(a == b, "availability is deterministic per (campaign, settlement, kind, month)")
	check(a >= 1 and a <= 6, "sage class I rolls 1d6; got %d" % a)

	# Sage at market class VI is RAW 'None' (acore_equipment.xml:726).
	check(SpecialistCatalog.monthly_availability("sage", 6, "c1", "s1", 7) == 0,
		"sage unavailable at class VI")

	# Alchemist class III is a flat '1'.
	check(SpecialistCatalog.monthly_availability("alchemist", 3, "c1", "s1", 7) == 1,
		"alchemist class III = flat 1")


# ---------------------------------------------------------------------------
# Commission lifecycle
# ---------------------------------------------------------------------------

func test_commission_creates_row_and_debits_wallet() -> void:
	_setup()
	var wallet := _FakeWallet.new()
	var now := 1000
	var result := _manager(wallet).commission(
		CAMPAIGN_ID, PARTY_ID, SETTLEMENT_ID, "sage", "sage_research_topic",
		"the fall of the Zaharan empire", PC_ID, now)
	check(bool(result.get("ok", false)), "commission succeeds: %s" % str(result.get("message", "")))
	check(wallet.paid_cp == [50000], "wallet debited 500gp up front")

	var rows := CampaignRepository.list_specialist_commissions(CAMPAIGN_ID, PARTY_ID)
	check(rows.size() == 1, "one commission row")
	if rows.size() == 1:
		check(int(rows[0].get("completes_at_round", 0)) ==
			now + 30 * Timekeeping.ROUNDS_PER_DAY,
			"completes 30 days out")
		check(str(rows[0].get("subject", "")) == "the fall of the Zaharan empire",
			"subject stored")
		check(int(rows[0].get("collected", 1)) == 0, "starts uncollected")
	check(_commissioned_events.size() == 1, "specialist_commissioned fired")
	_teardown()


func test_commission_requires_subject_when_flagged() -> void:
	_setup()
	var wallet := _FakeWallet.new()
	var result := _manager(wallet).commission(
		CAMPAIGN_ID, PARTY_ID, SETTLEMENT_ID, "sage", "sage_consult_question",
		"   ", PC_ID, 1000)
	check(not bool(result.get("ok", true)), "blank subject rejected")
	check(wallet.paid_cp.is_empty(), "no charge on rejection")
	check(CampaignRepository.list_specialist_commissions(CAMPAIGN_ID, PARTY_ID).is_empty(),
		"no row on rejection")
	_teardown()


func test_commission_fails_on_wallet_refusal() -> void:
	_setup()
	var wallet := _FakeWallet.new()
	wallet.allow = false
	var result := _manager(wallet).commission(
		CAMPAIGN_ID, PARTY_ID, SETTLEMENT_ID, "sage", "sage_consult_question",
		"dragons", PC_ID, 1000)
	check(not bool(result.get("ok", true)), "unaffordable commission fails")
	check(CampaignRepository.list_specialist_commissions(CAMPAIGN_ID, PARTY_ID).is_empty(),
		"no row when payment fails")
	check(_commissioned_events.is_empty(), "no signal when payment fails")
	_teardown()


func test_collect_gates_on_ready_and_settlement() -> void:
	_setup()
	var wallet := _FakeWallet.new()
	var manager := _manager(wallet)
	var now := 2000
	var made := manager.commission(
		CAMPAIGN_ID, PARTY_ID, SETTLEMENT_ID, "sage", "sage_consult_question",
		"owlbears", PC_ID, now)
	var cid: String = str(made.get("commission_id", ""))
	var done_at: int = now + 7 * Timekeeping.ROUNDS_PER_DAY

	var early := manager.collect(cid, PC_ID, SETTLEMENT_ID, now + 10)
	check(not bool(early.get("ok", true)), "cannot collect before completion")

	var wrong_town := manager.collect(cid, PC_ID, "elsewhere", done_at + 1)
	check(not bool(wrong_town.get("ok", true)), "cannot collect outside the origin settlement")

	var row := CampaignRepository.get_specialist_commission(cid)
	check(not SpecialistCommissionManager.is_ready(row, now + 10), "not ready early")
	check(SpecialistCommissionManager.is_ready(row, done_at), "ready at completes_at_round")
	_teardown()


func test_collect_report_marks_collected_once() -> void:
	_setup()
	var wallet := _FakeWallet.new()
	var manager := _manager(wallet)
	var now := 3000
	var made := manager.commission(
		CAMPAIGN_ID, PARTY_ID, SETTLEMENT_ID, "sage", "sage_consult_question",
		"the Iron Pass", PC_ID, now)
	var cid: String = str(made.get("commission_id", ""))
	var done_at: int = now + 7 * Timekeeping.ROUNDS_PER_DAY

	var result := manager.collect(cid, PC_ID, SETTLEMENT_ID, done_at)
	check(bool(result.get("ok", false)), "ready + right settlement collects")
	check(str(result.get("result_kind", "")) == "report", "report deliverable")
	check(str(result.get("result_payload", "")).contains("the Iron Pass"),
		"report references the subject")
	check(int(CampaignRepository.get_specialist_commission(cid).get("collected", 0)) == 1,
		"collected stamped")
	check(_collected_events.size() == 1, "specialist_commission_collected fired")

	var again := manager.collect(cid, PC_ID, SETTLEMENT_ID, done_at + 5)
	check(not bool(again.get("ok", true)), "re-collection refused")
	check(_collected_events.size() == 1, "no second signal")
	_teardown()


func test_alchemist_brew_prices_from_catalog_and_grants_item() -> void:
	_setup()
	var wallet := _FakeWallet.new()
	var manager := _manager(wallet)
	var now := 4000

	# Potion of Healing carries value_gp 500 in the magic item catalog.
	check(manager.service_cost_cp("alchemist", "alchemist_brew_healing") == 50000,
		"brew priced from the magic item catalog (500gp)")

	var made := manager.commission(
		CAMPAIGN_ID, PARTY_ID, SETTLEMENT_ID, "alchemist", "alchemist_brew_healing",
		"", PC_ID, now)
	check(bool(made.get("ok", false)), "brew commission succeeds")
	check(wallet.paid_cp == [50000], "brew charged at catalog value")

	var cid: String = str(made.get("commission_id", ""))
	var done_at: int = now + 7 * Timekeeping.ROUNDS_PER_DAY
	var result := manager.collect(cid, PC_ID, SETTLEMENT_ID, done_at)
	check(bool(result.get("ok", false)), "brew collected")
	check(str(result.get("result_kind", "")) == "item", "item deliverable")

	CampaignRepository.db.query_with_bindings("""
		SELECT item_key, name, is_magical, value_cp, item_category
		FROM inventory_items WHERE character_id = ?
	""", [PC_ID])
	var items: Array = CampaignRepository.db.query_result.duplicate()
	check(items.size() == 1, "one inventory item granted")
	if items.size() == 1:
		check(str(items[0].get("item_key", "")) == "potion_of_healing", "potion granted")
		check(int(items[0].get("is_magical", 0)) == 1, "potion is magical")
		check(int(items[0].get("value_cp", 0)) == 50000, "potion carries its sale value")
	_teardown()


# ---------------------------------------------------------------------------
# Availability subtraction
# ---------------------------------------------------------------------------

func test_engagements_subtract_from_monthly_availability() -> void:
	_setup()
	const MONTH_ROUNDS := Timekeeping.DAYS_PER_MONTH * Timekeeping.ROUNDS_PER_DAY
	var month_start := 2 * MONTH_ROUNDS
	var in_month := month_start + 100
	var out_of_month := month_start - 100

	# One retain + one commission inside the month; one commission before it.
	CampaignRepository.open_specialist({
		"campaign_id": CAMPAIGN_ID, "party_id": PARTY_ID, "kind": "sage",
		"name": "Sage A", "settlement_id": SETTLEMENT_ID,
		"hired_at_round": in_month, "monthly_wage_cp": 50000,
	})
	var wallet := _FakeWallet.new()
	var manager := _manager(wallet)
	manager.commission(CAMPAIGN_ID, PARTY_ID, SETTLEMENT_ID,
		"sage", "sage_consult_question", "q1", PC_ID, in_month)
	manager.commission(CAMPAIGN_ID, PARTY_ID, SETTLEMENT_ID,
		"sage", "sage_consult_question", "q0", PC_ID, out_of_month)

	check(CampaignRepository.count_specialist_engagements_this_month(
		CAMPAIGN_ID, SETTLEMENT_ID, "sage",
		month_start, month_start + MONTH_ROUNDS) == 2,
		"in-month retain + commission counted; prior-month commission excluded")
	_teardown()
