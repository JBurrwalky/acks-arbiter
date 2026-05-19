extends "res://tests/test_suite_base.gd"

## Phase 4 of the henchman closure plan: tests for
## HenchmanLifecycleManager.dismiss_henchman.
## Exercises:
##   - Default options route through process_departure with reason="dismissed"
##   - Equipment retention: keep_all (no transfers, no removals)
##   - Equipment retention: take_party_gear (items reassigned to employer)
##   - Equipment retention: take_everything (items deleted)
##   - parting_bonus_gp > 0 stamps +1 morale on departed-record
##   - final_wages_gp + parting_bonus_gp deducted from PartyWallet
##   - Returns false on empty character_id


# ---------------------------------------------------------------------------
# FakeRepo + FakeWallet — captures all DB-side mutations without real SQLite
# ---------------------------------------------------------------------------

class FakeRepo:
	extends RefCounted

	var characters: Dictionary = {}     # id -> row dict
	var states: Dictionary = {}         # character_id -> state dict
	var inventory: Dictionary = {}      # character_id -> Array of items
	var party_members: Dictionary = {}  # party_id -> Array of character_ids
	var coin_added_cp: Dictionary = {}  # character_id -> total cp added
	var rep_changes: Array = []         # captured rep-system calls (always [])

	# Captures for the SQL queries we don't fully simulate.
	var update_character_called_with: Array = []

	var db: FakeDB = FakeDB.new()

	class FakeDB:
		extends RefCounted
		var query_result: Array = []
		var captured_sql: Array = []
		var captured_bindings: Array = []
		func query_with_bindings(sql: String, bindings: Array) -> bool:
			captured_sql.append(sql)
			captured_bindings.append(bindings)
			query_result = []
			return true

	func get_character(id: String) -> Dictionary:
		return characters.get(id, {})

	func get_henchman_state(character_id: String) -> Dictionary:
		return states.get(character_id, {})

	func upsert_henchman_state(character_id: String, state: Dictionary) -> bool:
		states[character_id] = state.duplicate()
		return true

	func get_inventory_items(character_id: String) -> Array:
		return inventory.get(character_id, [])

	func remove_inventory_item(item_id: String) -> bool:
		for cid in inventory:
			var arr: Array = inventory[cid]
			for i in range(arr.size()):
				if String(arr[i].get("id", "")) == item_id:
					arr.remove_at(i)
					return true
		return false

	func add_coins_cp(character_id: String, amount: int) -> void:
		coin_added_cp[character_id] = int(coin_added_cp.get(character_id, 0)) + amount

	func remove_party_member(party_id: String, character_id: String) -> bool:
		if party_members.has(party_id):
			party_members[party_id].erase(character_id)
		return true


class FakeWallet:
	extends RefCounted
	var paid_cp: int = 0
	var allow_pay: bool = true
	func pay(cost_cp: int, _party_id: String, _employer_id: String) -> Dictionary:
		if not allow_pay:
			return {"ok": false, "message": "insufficient funds"}
		paid_cp += cost_cp
		return {"ok": true}


# Re-bind the lifecycle manager's wallet getter to use FakeWallet for tests.
class FakeLifecycle:
	extends HenchmanLifecycleManager
	var fake_wallet: FakeWallet
	func _get_party_wallet():
		return fake_wallet


func run_all_tests() -> void:
	test_empty_character_id_returns_false()
	test_dismiss_routes_through_process_departure()
	test_default_final_wages_unpaid_months_times_wage()
	test_parting_bonus_stamps_plus_one_morale()
	test_retention_keep_all_no_inventory_changes()
	test_retention_take_party_gear_reassigns_to_employer()
	test_retention_take_everything_deletes_inventory()
	test_pay_failure_returns_false()
	if not has_failures():
		print("DismissHenchman: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## 2026-05-16 cp pass: monthly_wage_cp is cp; fixture default is 25 gp = 2500 cp.
func _make_lifecycle(unpaid_months: int = 0,
		monthly_wage_cp: int = 2500,
		inventory_count: int = 0,
		allow_pay: bool = true) -> FakeLifecycle:
	var repo := FakeRepo.new()
	repo.characters["henchman1"] = {
		"id": "henchman1",
		"name": "Test Henchman",
		"character_type": "henchman",
		"employer_id": "patron1",
		"wage_cp_per_month": monthly_wage_cp,
	}
	repo.characters["patron1"] = {
		"id": "patron1",
		"name": "Test Patron",
		"character_type": "pc",
	}
	repo.states["henchman1"] = {
		"morale_score": 0,
		"unpaid_months": unpaid_months,
		"is_grudging": 0,
		"is_fanatic": 0,
	}
	if inventory_count > 0:
		var items: Array = []
		for i in range(inventory_count):
			items.append({
				"id": "item_%d" % i,
				"item_key": "item_%d" % i,
				"slot": "body" if i == 0 else "pack",
				"is_equipped": (i == 0),
			})
		repo.inventory["henchman1"] = items
	repo.party_members["party1"] = ["henchman1", "patron1"]

	var lifecycle := FakeLifecycle.new(repo, null, null)
	var wallet := FakeWallet.new()
	wallet.allow_pay = allow_pay
	lifecycle.fake_wallet = wallet
	return lifecycle


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_empty_character_id_returns_false() -> void:
	var lifecycle := _make_lifecycle()
	check(not lifecycle.dismiss_henchman(""),
		"empty character_id must return false")


func test_dismiss_routes_through_process_departure() -> void:
	var lifecycle := _make_lifecycle()
	var ok := lifecycle.dismiss_henchman("henchman1", {
		"settlement_id": "settle1",
		"party_id": "party1",
	})
	check(ok, "dismiss should succeed")
	# State after process_departure should carry reason="dismissed".
	var state: Dictionary = lifecycle._repo.get_henchman_state("henchman1")
	check(String(state.get("departure_reason", "")) == "dismissed",
		"departure_reason should be 'dismissed', got %s" % str(state.get("departure_reason", "")))
	check(String(state.get("departure_settlement_id", "")) == "settle1",
		"departure_settlement_id should propagate")


func test_default_final_wages_unpaid_months_times_wage() -> void:
	# 2 months unpaid × 25 gp/mo = 50 gp owed → 5000 cp.
	var lifecycle := _make_lifecycle(2, 2500)
	lifecycle.dismiss_henchman("henchman1", {
		"party_id": "party1",
	})
	check(lifecycle.fake_wallet.paid_cp == 5000,
		"default final wages should = unpaid_months * wage * 100; got %d cp" % lifecycle.fake_wallet.paid_cp)
	# The henchman should also receive that 5000 cp into their purse.
	check(int(lifecycle._repo.coin_added_cp.get("henchman1", 0)) == 5000,
		"henchman should receive their final wages")


func test_parting_bonus_stamps_plus_one_morale() -> void:
	var lifecycle := _make_lifecycle(0, 2500)
	# Pre-condition: morale_score = 0
	check(int(lifecycle._repo.states["henchman1"]["morale_score"]) == 0,
		"baseline morale should be 0")
	lifecycle.dismiss_henchman("henchman1", {
		"final_wages_cp": 0,
		"parting_bonus_cp": 1000,
		"party_id": "party1",
	})
	# After dismiss: morale_score should be +1 (the parting bonus stamp).
	# Note: process_departure doesn't touch morale, so this is purely the
	# dismiss_henchman parting-bonus stamp.
	check(int(lifecycle._repo.states["henchman1"]["morale_score"]) == 1,
		"parting bonus should stamp +1 morale; got %d" % int(lifecycle._repo.states["henchman1"]["morale_score"]))
	# Wallet was charged for the bonus.
	check(lifecycle.fake_wallet.paid_cp == 1000,
		"wallet should be charged 10 gp = 1000 cp; got %d" % lifecycle.fake_wallet.paid_cp)


func test_retention_keep_all_no_inventory_changes() -> void:
	var lifecycle := _make_lifecycle(0, 2500, 3)
	lifecycle.dismiss_henchman("henchman1", {
		"equipment_retention": "keep_all",
		"party_id": "party1",
	})
	# Henchman keeps all 3 items.
	var inv: Array = lifecycle._repo.inventory.get("henchman1", [])
	check(inv.size() == 3, "keep_all should leave all items; got %d" % inv.size())


func test_retention_take_party_gear_reassigns_to_employer() -> void:
	var lifecycle := _make_lifecycle(0, 2500, 3)
	lifecycle.dismiss_henchman("henchman1", {
		"equipment_retention": "take_party_gear",
		"party_id": "party1",
	})
	# Inventory items should still exist (not deleted) but the FakeRepo
	# captures the UPDATE statements that reassign character_id. Verify the
	# UPDATE was issued for each item.
	var update_count := 0
	for sql: String in lifecycle._repo.db.captured_sql:
		if sql.contains("UPDATE inventory_items") and sql.contains("character_id = ?"):
			update_count += 1
	check(update_count == 3,
		"take_party_gear should issue UPDATE for each item (3); got %d" % update_count)


func test_retention_take_everything_deletes_inventory() -> void:
	var lifecycle := _make_lifecycle(0, 2500, 3)
	lifecycle.dismiss_henchman("henchman1", {
		"equipment_retention": "take_everything",
		"party_id": "party1",
	})
	# All items should be removed.
	var inv: Array = lifecycle._repo.inventory.get("henchman1", [])
	check(inv.size() == 0, "take_everything should delete all items; got %d" % inv.size())


func test_pay_failure_returns_false() -> void:
	# Insufficient funds — should return false WITHOUT advancing the dismissal.
	var lifecycle := _make_lifecycle(2, 2500, 0, false)
	var ok := lifecycle.dismiss_henchman("henchman1", {
		"party_id": "party1",
	})
	check(not ok, "insufficient funds should yield false")
	# departure_reason should NOT have been stamped.
	var state: Dictionary = lifecycle._repo.get_henchman_state("henchman1")
	check(String(state.get("departure_reason", "")) == "",
		"failed dismissal must not stamp departure_reason")
