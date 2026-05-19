extends "res://tests/test_suite_base.gd"

## Phase G-2: Integration tests for HenchmanLifecycleManager using FakeRepo.


class FakeDice:
	extends RefCounted
	var fixed_total: int = 7
	func roll(_count: int, _sides: int) -> int:
		return fixed_total


class FakeRepo:
	extends RefCounted

	var db_pools: Dictionary = {}       # pool_id -> row dict
	var db_members: Dictionary = {}     # pool_id -> Array of member dicts
	var db_characters: Dictionary = {}  # character_id -> row dict
	var db_state: Dictionary = {}       # character_id -> state dict
	var db_party_members: Dictionary = {} # party_id -> Array of character_ids
	var db_party_gold: Dictionary = {}    # party_id -> int
	var _next_id := 0

	var db: FakeDB = FakeDB.new()

	class FakeDB:
		extends RefCounted
		var query_result: Array = []
		var _parent: FakeRepo

		func query_with_bindings(_sql: String, _bindings: Array) -> bool:
			query_result = []
			return true

	func _init() -> void:
		db._parent = self

	func generate_id() -> String:
		_next_id += 1
		return "fake_id_%d" % _next_id

	func get_henchman_pool(settlement_id: String, month: int, year: int) -> Dictionary:
		for pool in db_pools.values():
			if pool.get("settlement_id") == settlement_id and \
				int(pool.get("generated_month")) == month and \
				int(pool.get("generated_year")) == year:
				return pool
		return {}

	func create_henchman_pool(campaign_id: String, settlement_id: String,
			month: int, year: int, total: int, cost: int) -> String:
		var id := generate_id()
		db_pools[id] = {
			"id": id, "campaign_id": campaign_id,
			"settlement_id": settlement_id,
			"generated_month": month, "generated_year": year,
			"total_available": total, "search_cost_cp": cost,
		}
		db_members[id] = []
		return id

	func add_pool_member(pool_id: String, character_id: String, week: int) -> bool:
		if not db_members.has(pool_id):
			db_members[pool_id] = []
		db_members[pool_id].append({
			"pool_id": pool_id, "character_id": character_id,
			"allotment_week": week, "is_hired": 0,
			"name": "Henchman", "class_id": "fighter", "level": 1,
			"character_type": "henchman",
		})
		return true

	func get_pool_members(pool_id: String, max_week: int = 3) -> Array:
		if not db_members.has(pool_id):
			return []
		return db_members[pool_id].filter(
			func(m): return int(m["allotment_week"]) <= max_week and int(m["is_hired"]) == 0)

	func mark_pool_member_hired(pool_id: String, character_id: String) -> bool:
		if not db_members.has(pool_id):
			return false
		for m in db_members[pool_id]:
			if m["character_id"] == character_id:
				m["is_hired"] = 1
				return true
		return false

	func save_character(data: Dictionary) -> String:
		db_characters[data.get("id", "")] = data
		return data.get("id", "")

	func upsert_henchman_state(character_id: String, state: Dictionary) -> bool:
		db_state[character_id] = state.duplicate(true)
		return true

	func get_henchman_state(character_id: String) -> Dictionary:
		return db_state.get(character_id, {})

	func list_henchman_states_for_employer(_employer_id: String) -> Array:
		return db_state.values()

	func update_character_field(character_id: String, field: String, value) -> bool:
		if not db_characters.has(character_id):
			db_characters[character_id] = {}
		db_characters[character_id][field] = value
		return true


class FakeCharGen:
	extends RefCounted
	var _next := 0
	func generate_henchman(class_id: String, level: int, campaign_id: String,
			_employer_id: String = "", _morale_base: int = 0):
		_next += 1
		var cd = RefCounted.new()  # Minimal stand-in
		return null  # lifecycle manager handles null


func run_all_tests() -> void:
	test_hiring_reaction_accept()
	test_hiring_reaction_refuse_slander()
	test_loyalty_check_grudging()
	test_loyalty_check_fanatic()
	test_morale_modifiers_level_up_and_calamity()
	if not has_failures():
		print("HenchmanLifecycle: all tests passed.")


func test_hiring_reaction_accept() -> void:
	var dice := FakeDice.new()
	dice.fixed_total = 10
	var repo := FakeRepo.new()
	var mgr := HenchmanLifecycleManager.new(repo, null, null)
	var result := mgr.attempt_hire(1, 0, dice)
	# 10 + 1 = 11 → accept
	check(result["outcome"] == HenchmanTables.HIRE_ACCEPT, "10+1=11 → accept")
	check(result["morale_bonus"] == 0, "accept has no bonus")


func test_hiring_reaction_refuse_slander() -> void:
	var dice := FakeDice.new()
	dice.fixed_total = 3
	var repo := FakeRepo.new()
	var mgr := HenchmanLifecycleManager.new(repo, null, null)
	var result := mgr.attempt_hire(-1, 0, dice)
	# 3 + (-1) = 2 → refuse and slander
	check(result["outcome"] == HenchmanTables.HIRE_REFUSE_SLANDER, "3-1=2 → slander")


func test_loyalty_check_grudging() -> void:
	var dice := FakeDice.new()
	dice.fixed_total = 7
	var repo := FakeRepo.new()
	repo.upsert_henchman_state("h1", {"morale_score": 0})
	var mgr := HenchmanLifecycleManager.new(repo, null, null)
	var result := mgr.trigger_loyalty_check("h1", "calamity", dice)
	# 7 + 0 = 7 → grudging
	check(result["outcome"] == HenchmanTables.LOYALTY_GRUDGING, "7+0=7 → grudging")
	var state := repo.get_henchman_state("h1")
	check(state.get("is_grudging") == true, "grudging flag set on state")


func test_loyalty_check_fanatic() -> void:
	var dice := FakeDice.new()
	dice.fixed_total = 7
	var repo := FakeRepo.new()
	repo.upsert_henchman_state("h2", {"morale_score": 5})
	var mgr := HenchmanLifecycleManager.new(repo, null, null)
	var result := mgr.trigger_loyalty_check("h2", "level_up", dice)
	# 7 + 5 = 12 → fanatic
	check(result["outcome"] == HenchmanTables.LOYALTY_FANATIC, "7+5=12 → fanatic")
	var state := repo.get_henchman_state("h2")
	check(state.get("is_fanatic") == true, "fanatic flag set on state")


func test_morale_modifiers_level_up_and_calamity() -> void:
	var repo := FakeRepo.new()
	repo.upsert_henchman_state("h3", {"morale_score": 2})
	var mgr := HenchmanLifecycleManager.new(repo, null, null)
	mgr.on_henchman_leveled_up("h3")
	check(int(repo.get_henchman_state("h3").get("morale_score", 0)) == 3,
		"level up: morale 2 → 3")
	mgr.on_henchman_calamity("h3")
	check(int(repo.get_henchman_state("h3").get("morale_score", 0)) == 2,
		"calamity: morale 3 → 2")
	mgr.on_henchman_calamity("h3")
	mgr.on_henchman_calamity("h3")
	check(int(repo.get_henchman_state("h3").get("morale_score", 0)) == 0,
		"two calamities: morale 2 → 0")
