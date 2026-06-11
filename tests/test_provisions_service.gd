extends "res://tests/test_suite_base.gd"

## Unit tests for ProvisionsService — the Option-B derive → resolve → writeback
## orchestration of the food consumption system (gdd-rations-foodstuffs.md
## Phase 1). Uses a fake in-memory repository + a real EquipmentCatalog so the
## inventory write-back (foraged-first, perishable → standard → iron, row
## deletion + quantity/encumbrance sync) is verified without a live DB. The
## SACRED SustenanceResolver runs UNCHANGED inside the loop.


# ---------------------------------------------------------------------------
# Fake repository — minimal in-memory inventory store.
# ---------------------------------------------------------------------------

class _FakeRepo:
	extends RefCounted
	var rows: Array = []  # Array[Dictionary]

	func add_row(row: Dictionary) -> void:
		rows.append(row)

	func get_inventory_items(character_id: String) -> Array:
		var out: Array = []
		for r in rows:
			if str(r.get("character_id", "")) == character_id:
				out.append(r)
		return out

	func get_party_inventory(party_id: String) -> Array:
		var out: Array = []
		for r in rows:
			if str(r.get("party_id", "")) == party_id and str(r.get("character_id", "")) == "":
				out.append(r)
		return out

	func get_trained_creatures_for_party(_party_id: String) -> Array:
		return []

	func get_creature_inventory(_creature_id: String) -> Array:
		return []

	func get_draft_vehicles_for_party(_party_id: String) -> Array:
		return []

	func get_items_in_vehicle(_vehicle_id: String) -> Array:
		return []

	func remove_inventory_item(item_id: String) -> bool:
		for i in range(rows.size()):
			if str(rows[i].get("id", "")) == item_id:
				rows.remove_at(i)
				return true
		return false

	func update_inventory_item_quantity(item_id: String, new_quantity: int) -> bool:
		if new_quantity <= 0:
			return remove_inventory_item(item_id)
		for r in rows:
			if str(r.get("id", "")) == item_id:
				r["quantity"] = new_quantity
				return true
		return false

	func update_inventory_item_consumable_remaining(item_id: String, remaining: int) -> bool:
		for r in rows:
			if str(r.get("id", "")) == item_id:
				r["consumable_units_remaining"] = remaining
				return true
		return false

	func get_items_in_container(container_item_id: String) -> Array:
		var out: Array = []
		for r in rows:
			if str(r.get("container_id", "")) == container_item_id:
				out.append(r)
		return out

	func find(item_id: String) -> Dictionary:
		for r in rows:
			if str(r.get("id", "")) == item_id:
				return r
		return {}


# ---------------------------------------------------------------------------
# Fake dice — fixed value for the resolver's 1d4 dehydration rolls.
# ---------------------------------------------------------------------------

class _FixedDice:
	extends RefCounted
	var _v: int = 2
	func _init(v: int = 2) -> void:
		_v = v
	func roll_digital(sides: int, count: int = 1, modifier: int = 0,
			_roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		r.individual_results = []
		var total := 0
		for _i in range(count):
			r.individual_results.append(_v)
			total += _v
		r.raw_total = total
		r.modified_total = total + modifier
		return r


var _catalog: EquipmentCatalog = null


func run_all_tests() -> void:
	_catalog = EquipmentCatalog.new()
	test_derive_folds_carried_into_counter()
	test_writeback_consumes_foraged_before_carried()
	test_writeback_standard_before_iron()
	test_fed_party_does_not_starve()
	test_empty_pack_still_starves()
	test_row_deleted_when_depleted()
	test_quantity_syncs_with_remaining()
	test_fill_water_containers_to_capacity()
	test_barrel_with_items_excluded_from_water()
	test_container_less_party_water_is_noop()
	test_water_drawn_from_containers_persists_empty()
	test_dehydrate_only_when_containers_empty()
	test_carried_fodder_and_consume()
	if not has_failures():
		print("ProvisionsService: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _make_party(humanoids: int) -> PartyData:
	var pd := PartyData.new()
	pd.id = "test_provisions_party"
	pd.character_data = []
	for i in range(humanoids):
		var cd := CharacterData.new()
		cd.id = "pc_%d" % i
		cd.name = "PC %d" % i
		cd.character_type = "pc"
		cd.hp_max = 10
		cd.hp_current = 10
		pd.character_data.append(cd)
	return pd


func _food_row(repo: _FakeRepo, id: String, item_key: String,
		quantity: int = 1, remaining: int = -1) -> void:
	repo.add_row({
		"id": id,
		"character_id": "pc_0",
		"item_key": item_key,
		"quantity": quantity,
		"consumable_units_remaining": remaining,
	})


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_derive_folds_carried_into_counter() -> void:
	var repo := _FakeRepo.new()
	_food_row(repo, "f1", "rations_standard_week", 2, -1)  # 14 days carried
	var party := _make_party(4)
	party.ration_units = 3  # foraged surplus
	var service := ProvisionsService.new(repo, _catalog)
	var ctx := service.derive_food_into_counter(party)
	check(party.ration_units == 17, "counter = 3 foraged + 14 carried = 17; got %d" % party.ration_units)
	check(int(ctx.get("foraged_before", -1)) == 3, "ctx remembers the foraged surplus")
	check(ctx.get("food_rows", []).size() == 1, "one carried food row captured")


func test_writeback_consumes_foraged_before_carried() -> void:
	var repo := _FakeRepo.new()
	_food_row(repo, "f1", "rations_standard_week", 1, -1)  # 7 carried
	var party := _make_party(2)
	party.ration_units = 1  # 1 foraged day
	var service := ProvisionsService.new(repo, _catalog)
	var ctx := service.derive_food_into_counter(party)  # counter -> 8
	# Resolver would consume party_size = 2 person-days from the pool of 8.
	service.writeback_food(party, 2, ctx)
	check(party.ration_units == 0, "foraged drained first (1 of 2 from forage)")
	check(int(repo.find("f1").get("consumable_units_remaining", -99)) == 6,
		"1 carried day consumed: 7 -> 6; got %d"
		% int(repo.find("f1").get("consumable_units_remaining", -99)))


func test_writeback_standard_before_iron() -> void:
	var repo := _FakeRepo.new()
	_food_row(repo, "iron", "rations_iron_week", 1, -1)
	_food_row(repo, "std", "rations_standard_week", 1, -1)
	var party := _make_party(1)
	party.ration_units = 0
	var service := ProvisionsService.new(repo, _catalog)
	var ctx := service.derive_food_into_counter(party)  # counter -> 14
	service.writeback_food(party, 1, ctx)  # eat 1 day
	check(int(repo.find("std").get("consumable_units_remaining", -99)) == 6,
		"standard rations eaten first: 7 -> 6")
	check(int(repo.find("iron").get("consumable_units_remaining", -99)) == -1,
		"iron rations untouched (still uninitialized)")


func test_fed_party_does_not_starve() -> void:
	# THE Phase 1 acceptance test: a party with a week of rations in the pack
	# loses no HP over the first 3 days, and the ration row depletes 2/day.
	var repo := _FakeRepo.new()
	_food_row(repo, "f1", "rations_standard_week", 1, -1)  # 7 person-days
	var party := _make_party(2)
	var dice := _FixedDice.new(2)
	var expected_remaining := [5, 3, 1]
	for day in range(3):
		party.water_units = 10  # refill water — Phase 1 isolates food
		var ctx := service_for(repo).derive_food_into_counter(party)
		var summary := SustenanceResolver.apply_daily(party, dice)
		service_for(repo).writeback_food(party, int(summary.get("food_consumed", 0)), ctx)
		check(int(summary.get("total_hp_lost", -1)) == 0,
			"day %d: fed party loses no HP" % (day + 1))
		check(party.starvation_days == 0, "day %d: no starvation accrued" % (day + 1))
		check(int(repo.find("f1").get("consumable_units_remaining", -99)) == expected_remaining[day],
			"day %d: ration row remaining = %d" % [day + 1, expected_remaining[day]])


func test_empty_pack_still_starves() -> void:
	# No carried food, no foraged surplus → the RAW starvation curve must still
	# fire exactly as SustenanceResolver dictates (the safety net).
	var repo := _FakeRepo.new()
	var party := _make_party(2)
	var dice := _FixedDice.new(2)
	for _day in range(3):
		party.water_units = 10
		var ctx := service_for(repo).derive_food_into_counter(party)
		var summary := SustenanceResolver.apply_daily(party, dice)
		service_for(repo).writeback_food(party, int(summary.get("food_consumed", 0)), ctx)
	check(party.starvation_days == 3, "3 days no food → starvation_days=3")
	check(party.ration_units == 0, "counter stays at 0 (no carried, no foraged)")
	check(SustenanceResolver.is_natural_healing_blocked(party),
		"natural healing blocked after grace")


func test_row_deleted_when_depleted() -> void:
	var repo := _FakeRepo.new()
	_food_row(repo, "f1", "rations_standard_week", 1, 1)  # only 1 day left
	var party := _make_party(2)
	party.ration_units = 0
	var service := ProvisionsService.new(repo, _catalog)
	var ctx := service.derive_food_into_counter(party)  # counter -> 1
	service.writeback_food(party, 1, ctx)  # eat the last day
	check(repo.find("f1").is_empty(), "depleted food row removed from inventory")


func test_quantity_syncs_with_remaining() -> void:
	# A 2-week stack (14 days) eaten down to 6 days should drop to quantity 1 so
	# encumbrance (units x quantity) tracks the surviving food.
	var repo := _FakeRepo.new()
	_food_row(repo, "f1", "rations_standard_week", 2, -1)  # 14 days, qty 2
	var party := _make_party(8)
	party.ration_units = 0
	var service := ProvisionsService.new(repo, _catalog)
	var ctx := service.derive_food_into_counter(party)  # counter -> 14
	service.writeback_food(party, 8, ctx)  # eat 8 days
	var row := repo.find("f1")
	check(int(row.get("consumable_units_remaining", -99)) == 6, "14 - 8 = 6 days left")
	check(int(row.get("quantity", -99)) == 1, "quantity drops 2 -> 1 (ceil(6/7))")


# ---------------------------------------------------------------------------
# Water (Phase 2)
# ---------------------------------------------------------------------------

func _water_row(repo: _FakeRepo, id: String, item_key: String,
		quantity: int = 1, remaining: int = -1, container_id: String = "") -> void:
	repo.add_row({
		"id": id,
		"character_id": "pc_0",
		"item_key": item_key,
		"quantity": quantity,
		"consumable_units_remaining": remaining,
		"container_id": container_id,
	})


func test_fill_water_containers_to_capacity() -> void:
	var repo := _FakeRepo.new()
	_water_row(repo, "skin", "waterskin", 2, 0)   # 2 skins, empty (cap 2)
	_water_row(repo, "barrel", "barrel", 1, 5)    # 1 barrel, 5 of 20 left
	var party := _make_party(2)
	var service := ProvisionsService.new(repo, _catalog)
	check(service.water_capacity_days(party) == 22, "capacity = 2 + 20 = 22")
	check(service.carried_water_days(party) == 5, "current fill = 0 + 5 = 5")
	var filled := service.fill_water_containers(party)
	check(filled == 17, "filled 2 + 15 = 17 person-days; got %d" % filled)
	check(service.carried_water_days(party) == 22, "containers now full = 22")


func test_barrel_with_items_excluded_from_water() -> void:
	var repo := _FakeRepo.new()
	_water_row(repo, "barrel", "barrel", 1, -1)  # a barrel...
	# ...currently holding a general item (container_id points at the barrel).
	repo.add_row({
		"id": "loot", "character_id": "pc_0", "item_key": "torch",
		"quantity": 1, "consumable_units_remaining": -1, "container_id": "barrel",
	})
	var party := _make_party(2)
	var service := ProvisionsService.new(repo, _catalog)
	check(not service.has_water_containers(party),
		"a barrel holding items is not a water vessel (items XOR water)")
	check(service.carried_water_days(party) == 0, "no usable water in an item-barrel")


func test_container_less_party_water_is_noop() -> void:
	var repo := _FakeRepo.new()  # no water containers at all
	var party := _make_party(2)
	party.water_units = 5  # legacy abstract counter
	var service := ProvisionsService.new(repo, _catalog)
	var ctx := service.derive_water_into_counter(party)
	check(not bool(ctx.get("has_containers", true)), "no containers reported")
	check(party.water_units == 5, "legacy water_units left untouched by derive")
	service.writeback_water(party, 2, ctx)  # must be a no-op
	check(party.water_units == 5, "writeback is a no-op for container-less party")


func test_water_drawn_from_containers_persists_empty() -> void:
	var repo := _FakeRepo.new()
	_water_row(repo, "skin", "waterskin", 1, -1)  # full (cap 1)
	_water_row(repo, "barrel", "barrel", 1, -1)   # full (cap 20)
	var party := _make_party(2)
	var service := ProvisionsService.new(repo, _catalog)
	var ctx := service.derive_water_into_counter(party)
	check(party.water_units == 21, "derived water_units = 1 + 20 = 21")
	service.writeback_water(party, 2, ctx)  # drink 2 person-days
	check(int(repo.find("skin").get("consumable_units_remaining", -99)) == 0,
		"waterskin drained first to 0 (and PERSISTS — not deleted)")
	check(not repo.find("skin").is_empty(), "empty waterskin still in inventory")
	check(int(repo.find("barrel").get("consumable_units_remaining", -99)) == 19,
		"barrel supplies the 2nd day: 20 -> 19")


func test_dehydrate_only_when_containers_empty() -> void:
	# A 1-day waterskin + well-fed party: day 1 watered (no HP loss), day 2 the
	# skin is empty so dehydration fires exactly per the RAW curve.
	var repo := _FakeRepo.new()
	_water_row(repo, "skin", "waterskin", 1, -1)  # 1 person-day of water
	var party := _make_party(1)
	party.ration_units = 100  # well-fed — isolate water
	var dice := _FixedDice.new(2)
	var service := ProvisionsService.new(repo, _catalog)

	var ctx1 := service.derive_water_into_counter(party)
	var r1 := SustenanceResolver.apply_daily(party, dice)
	service.writeback_water(party, int(r1.get("water_consumed", 0)), ctx1)
	check(int(r1.get("total_hp_lost", -1)) == 0, "day 1: watered, no HP loss")
	check(party.dehydration_days == 0, "day 1: no dehydration")
	check(int(repo.find("skin").get("consumable_units_remaining", -99)) == 0,
		"day 1: skin emptied")

	var ctx2 := service.derive_water_into_counter(party)
	var r2 := SustenanceResolver.apply_daily(party, dice)
	service.writeback_water(party, int(r2.get("water_consumed", 0)), ctx2)
	check(party.dehydration_days == 1, "day 2: empty skin → dehydration begins")
	check(int(r2.get("total_hp_lost", -1)) > 0, "day 2: HP lost to dehydration")


# ---------------------------------------------------------------------------
# Fodder (Phase 3)
# ---------------------------------------------------------------------------

func test_carried_fodder_and_consume() -> void:
	var repo := _FakeRepo.new()
	repo.add_row({
		"id": "fod", "character_id": "pc_0", "item_key": "fodder",
		"quantity": 2, "consumable_units_remaining": -1,  # 2 loads = 14 fodder-days
	})
	var party := _make_party(1)
	var service := ProvisionsService.new(repo, _catalog)
	check(service.carried_fodder_days(party) == 14, "2 fodder loads = 14 fodder-days")
	var eaten := service.consume_fodder(party, 5)
	check(eaten == 5, "consumed 5 fodder-days; got %d" % eaten)
	check(int(repo.find("fod").get("consumable_units_remaining", -99)) == 9,
		"14 - 5 = 9 fodder-days left")
	check(int(repo.find("fod").get("quantity", -99)) == 2,
		"quantity still 2 (ceil(9/7) = 2 loads)")


# A fresh service each call so the catalog is reused but no state leaks.
func service_for(repo: _FakeRepo) -> ProvisionsService:
	return ProvisionsService.new(repo, _catalog)
