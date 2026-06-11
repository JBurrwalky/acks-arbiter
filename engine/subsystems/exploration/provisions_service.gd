class_name ProvisionsService
extends RefCounted

## DB-aware orchestration for the rations / water / fodder consumption system
## (gdd-rations-foodstuffs.md, Option B). Inventory is the source of truth; the
## PartyData ration_units / water_units counters are per-tick DERIVED scratch
## values. Each day-tick:
##
##   1. derive_*  — sum carried provisions out of real inventory INTO the counter,
##   2. SustenanceResolver.apply_daily(...)  — the SACRED, unit-tested penalty math
##      runs UNCHANGED, decrementing the counter by party_size and rolling HP loss,
##   3. writeback_* — split the consumed amount back onto real inventory rows,
##      decrementing the items actually eaten / drunk.
##
## Foraged food (the persisted ration_units surplus) is always consumed BEFORE any
## carried item, so foraging keeps working exactly as before. Among carried items,
## food is eaten perishable-first (ProvisionsLedger.food_priority).
##
## Pure provisions math lives in ProvisionsLedger; this class only adds the I/O
## (gather rows, decrement / delete rows, reset the counter). `repo` is duck-typed
## (CampaignRepository in production, a fake in unit tests) and must expose:
## get_inventory_items, get_party_inventory, get_trained_creatures_for_party,
## get_creature_inventory, get_draft_vehicles_for_party, get_items_in_vehicle,
## remove_inventory_item, update_inventory_item_quantity,
## update_inventory_item_consumable_remaining.

var _repo
var _catalog: EquipmentCatalog


func _init(repo, catalog: EquipmentCatalog) -> void:
	_repo = repo
	_catalog = catalog


# ---------------------------------------------------------------------------
# Gathering
# ---------------------------------------------------------------------------

## Every inventory row carried by the whole party: each member's pack (including
## items nested in containers — the query is by character_id), the party-shared
## pool, trained-creature packs (mules carry supplies), and draft vehicles
## (supply wagons). No overlap: party / creature / vehicle items have an empty
## character_id, so member-pack queries never return them twice.
func gather_all_rows(party_data: PartyData) -> Array:
	var rows: Array = []
	if party_data == null or _repo == null:
		return rows
	for cd in party_data.character_data:
		if cd == null or cd.id.is_empty():
			continue
		rows.append_array(_repo.get_inventory_items(cd.id))
	if party_data.id.is_empty():
		return rows
	rows.append_array(_repo.get_party_inventory(party_data.id))
	for creature_row in _repo.get_trained_creatures_for_party(party_data.id):
		var cid := str(creature_row.get("id", ""))
		if not cid.is_empty():
			rows.append_array(_repo.get_creature_inventory(cid))
	for veh_row in _repo.get_draft_vehicles_for_party(party_data.id):
		var vid := str(veh_row.get("id", ""))
		if not vid.is_empty():
			rows.append_array(_repo.get_items_in_vehicle(vid))
	return rows


## Carried food in person-days (excludes the foraged ration_units surplus).
func carried_food_days(party_data: PartyData) -> int:
	return ProvisionsLedger.sum_food_days(gather_all_rows(party_data), _catalog)


# ---------------------------------------------------------------------------
# Food (Phase 1)
# ---------------------------------------------------------------------------

## Step 1: fold carried food INTO party_data.ration_units so the unchanged
## SustenanceResolver sees the full available pool (foraged surplus + carried).
## Returns a context Dictionary for writeback_food to undo the conflation.
func derive_food_into_counter(party_data: PartyData) -> Dictionary:
	var foraged_before: int = party_data.ration_units
	var rows := gather_all_rows(party_data)
	var food_rows := ProvisionsLedger.food_rows_in_priority(rows, _catalog)
	var carried: int = ProvisionsLedger.sum_food_days(rows, _catalog)
	party_data.ration_units = foraged_before + carried
	return {"foraged_before": foraged_before, "food_rows": food_rows}


## Step 3: after the resolver consumed `food_consumed` person-days from the
## combined counter, split it foraged-first and decrement the carried rows for
## the remainder. Resets ration_units to the FORAGED surplus that survives (so
## the persisted counter never double-counts carried inventory).
func writeback_food(party_data: PartyData, food_consumed: int, ctx: Dictionary) -> void:
	var foraged_before: int = int(ctx.get("foraged_before", 0))
	var consumed: int = maxi(0, food_consumed)
	var foraged_consumed: int = mini(foraged_before, consumed)
	var carried_consumed: int = consumed - foraged_consumed
	party_data.ration_units = foraged_before - foraged_consumed
	if carried_consumed > 0:
		_consume_rows(ctx.get("food_rows", []), carried_consumed, true)


# ---------------------------------------------------------------------------
# Fodder (Phase 3) — animal feed, consumed by the AnimalSustenanceResolver
# ---------------------------------------------------------------------------

## Carried fodder in fodder-days, pooled across the whole party's inventory.
func carried_fodder_days(party_data: PartyData) -> int:
	return ProvisionsLedger.sum_fodder_days(gather_all_rows(party_data), _catalog)


func gather_fodder_rows(party_data: PartyData) -> Array:
	var out: Array = []
	for row in gather_all_rows(party_data):
		if ProvisionsLedger.row_kind(row, _catalog) == ProvisionsLedger.KIND_FODDER:
			out.append(row)
	return out


## Decrement [param days] fodder-days from carried fodder (depleted rows are
## removed). Returns the amount actually consumed.
func consume_fodder(party_data: PartyData, days: int) -> int:
	if days <= 0:
		return 0
	return _consume_rows(gather_fodder_rows(party_data), days, true)


# ---------------------------------------------------------------------------
# Water (Phase 2) — held in waterskins (liquid only) + barrels (items XOR water)
# ---------------------------------------------------------------------------
#
# Water containers are the source of truth; water_units is derived scratch. A
# party with NO water containers keeps the legacy abstract water_units counter
# untouched (back-compat for container-less parties + the existing Decanter /
# refill tests) — derive/writeback are no-ops in that case.

## Water-bearing containers (catalog holds_water) currently usable for water.
## A barrel holding general items is NOT a water vessel (items XOR water) and is
## excluded until emptied; waterskins are liquid-only and always eligible.
func gather_water_containers(party_data: PartyData) -> Array:
	var out: Array = []
	for row in gather_all_rows(party_data):
		if ProvisionsLedger.row_holds_water(row, _catalog) and not _has_child_items(row):
			out.append(row)
	return out


func has_water_containers(party_data: PartyData) -> bool:
	return not gather_water_containers(party_data).is_empty()


## Water currently held across all eligible containers (person-days).
func carried_water_days(party_data: PartyData) -> int:
	return ProvisionsLedger.sum_water_days(gather_water_containers(party_data), _catalog)


## Maximum water the party could carry with every container topped off.
func water_capacity_days(party_data: PartyData) -> int:
	return ProvisionsLedger.sum_water_capacity_days(gather_water_containers(party_data), _catalog)


## Fill every eligible container to its capacity (fill-at-source). Returns the
## total person-days added. Item-bearing barrels are skipped.
func fill_water_containers(party_data: PartyData) -> int:
	var filled := 0
	for row in gather_water_containers(party_data):
		var cap: int = ProvisionsLedger.row_capacity_days(row, _catalog)
		var cur: int = ProvisionsLedger.row_effective_days(row, _catalog)
		if cur < cap:
			filled += (cap - cur)
			_repo.update_inventory_item_consumable_remaining(_row_id(row), cap)
	return filled


## Step 1 (water): fold current container water INTO party_data.water_units. A
## NO-OP when the party has no water containers — the legacy abstract counter is
## then left alone. Returns a context for writeback_water.
func derive_water_into_counter(party_data: PartyData) -> Dictionary:
	var rows := gather_water_containers(party_data)
	if rows.is_empty():
		return {"water_rows": [], "has_containers": false}
	party_data.water_units = ProvisionsLedger.sum_water_days(rows, _catalog)
	return {"water_rows": rows, "has_containers": true}


## Step 3 (water): decrement the drunk water from containers (they persist empty
## at 0 — refilled at a source). No-op for container-less parties.
func writeback_water(party_data: PartyData, water_consumed: int, ctx: Dictionary) -> void:
	if not bool(ctx.get("has_containers", false)):
		return
	var consumed: int = maxi(0, water_consumed)
	if consumed > 0:
		_consume_rows(ctx.get("water_rows", []), consumed, false)


## True if [param row] is a container currently holding general items (so a
## barrel of gear is excluded from water duty per the items-XOR-water rule).
func _has_child_items(row) -> bool:
	var item_id := _row_id(row)
	if item_id.is_empty() or _repo == null:
		return false
	if not _repo.has_method("get_items_in_container"):
		return false
	return not _repo.get_items_in_container(item_id).is_empty()


# ---------------------------------------------------------------------------
# Row decrement (shared by food / fodder / water)
# ---------------------------------------------------------------------------

## Draw [param total_days] person-days from [param rows] in order, returning the
## amount actually drawn. [param delete_at_zero] true for eaten provisions
## (food / fodder — depleted rows are removed); false for water containers
## (they persist empty and are refilled at a source).
func _consume_rows(rows: Array, total_days: int, delete_at_zero: bool) -> int:
	var to_consume: int = total_days
	for row in rows:
		if to_consume <= 0:
			break
		var eff: int = ProvisionsLedger.row_effective_days(row, _catalog)
		if eff <= 0:
			continue
		var take: int = mini(eff, to_consume)
		to_consume -= take
		_apply_row_remaining(row, eff - take, delete_at_zero)
	return total_days - to_consume


func _apply_row_remaining(row, new_remaining: int, delete_at_zero: bool) -> void:
	var item_id := _row_id(row)
	if item_id.is_empty():
		return
	if delete_at_zero:
		if new_remaining <= 0:
			_repo.remove_inventory_item(item_id)
			return
		# Keep quantity (=> encumbrance) in step with the surviving whole units:
		# the row holds ceil(remaining / per-unit-days) blocks. Weight drops one
		# block at a time as each is fully consumed; the partial block's precise
		# remaining is preserved in consumable_units_remaining.
		var per_unit: int = ProvisionsLedger.row_per_unit_days(row, _catalog)
		if per_unit > 0:
			var new_qty: int = maxi(1, int(ceil(float(new_remaining) / float(per_unit))))
			if new_qty != ProvisionsLedger.row_quantity(row):
				_repo.update_inventory_item_quantity(item_id, new_qty)
	# Water containers keep their fixed quantity; only the fill level changes.
	_repo.update_inventory_item_consumable_remaining(item_id, maxi(0, new_remaining))


func _row_id(row) -> String:
	if row is InventoryItem:
		return row.id
	if row is Dictionary:
		return str(row.get("id", ""))
	return ""
