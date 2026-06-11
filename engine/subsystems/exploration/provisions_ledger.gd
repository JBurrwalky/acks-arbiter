class_name ProvisionsLedger
extends RefCounted

## Pure provisions accounting — the single source of truth for converting carried
## INVENTORY into person-day totals for the rations / water / fodder consumption
## system (gdd-rations-foodstuffs.md, Option B). No DB access, no signals: every
## function operates on already-loaded inventory rows + an EquipmentCatalog so it
## is fully unit-testable in isolation. The DB-aware orchestration (gathering rows,
## deriving into the per-tick counters, writing consumption back) lives in
## `ProvisionsService`; the SACRED penalty math lives in `SustenanceResolver`.
##
## A "row" is either an InventoryItem or a raw DB Dictionary (snake_case keys);
## both shapes are accepted everywhere so callers can pass loaded objects or
## query results interchangeably.
##
## Person-day cadence: 1 person-day = one humanoid's food OR water for one day OR
## one standard animal's fodder for one day. A "week" ration = 7 person-days.
## RAW: acore_adventures_and_encounters.xml:322 (1 stone/character/day).

const KIND_FOOD := "food"
const KIND_WATER := "water"
const KIND_FODDER := "fodder"

## Carried-food consumption order (perishable-first per gdd §5.1). Foraged food
## (the ration_units counter) is consumed BEFORE any carried item — handled by
## ProvisionsService, not here. Among carried items: fresh perishables (bread,
## cheese, meat) are eaten first, then Standard rations (1-week shelf life), then
## shelf-stable Iron rations last. Lower number = consumed earlier.
const FOOD_PRIORITY_PERISHABLE := 0
const FOOD_PRIORITY_STANDARD := 1
const FOOD_PRIORITY_IRON := 2


# ---------------------------------------------------------------------------
# Per-row queries (accept InventoryItem or Dictionary)
# ---------------------------------------------------------------------------

static func row_item_key(row) -> String:
	if row is InventoryItem:
		return row.item_key
	if row is Dictionary:
		return str(row.get("item_key", ""))
	return ""


static func row_quantity(row) -> int:
	if row is InventoryItem:
		return row.quantity
	if row is Dictionary:
		return int(row.get("quantity", 1))
	return 1


static func row_remaining_field(row) -> int:
	## The raw consumable_units_remaining value (-1 = uninitialized).
	if row is InventoryItem:
		return row.consumable_units_remaining
	if row is Dictionary:
		return int(row.get("consumable_units_remaining", -1))
	return -1


## The catalog's consumable kind for this row ("food"/"water"/"fodder"/"").
static func row_kind(row, catalog) -> String:
	if catalog == null:
		return ""
	var entry: Dictionary = catalog.get_item(row_item_key(row))
	return str(entry.get("consumable_kind", ""))


## True if this row is a water-bearing container (waterskin / barrel) per the
## catalog `holds_water` flag — the only items that count toward field water.
static func row_holds_water(row, catalog) -> bool:
	if catalog == null:
		return false
	var entry: Dictionary = catalog.get_item(row_item_key(row))
	return bool(entry.get("holds_water", false))


## Whole person-days a SINGLE unit of this item provides (catalog
## consumable_person_days, floored — fractional tavern drinks like ale/wine
## contribute 0 to the field-consumption mechanic).
static func row_per_unit_days(row, catalog) -> int:
	if catalog == null:
		return 0
	var entry: Dictionary = catalog.get_item(row_item_key(row))
	return int(floor(float(entry.get("consumable_person_days", 0))))


## Full capacity of this row in person-days = quantity x per-unit-days.
static func row_capacity_days(row, catalog) -> int:
	return row_quantity(row) * row_per_unit_days(row, catalog)


## Effective person-days currently in this row: the explicit
## consumable_units_remaining when set (>= 0), else the full capacity
## (-1 uninitialized = "full", per migration 149 semantics).
static func row_effective_days(row, catalog) -> int:
	var remaining: int = row_remaining_field(row)
	if remaining >= 0:
		return remaining
	return row_capacity_days(row, catalog)


## Perishable-first sort key for carried food (see FOOD_PRIORITY_* constants).
static func food_priority(item_key: String) -> int:
	var k := item_key.to_lower()
	if k.contains("iron"):
		return FOOD_PRIORITY_IRON
	if k.begins_with("rations_standard") or k == "standard_rations":
		return FOOD_PRIORITY_STANDARD
	return FOOD_PRIORITY_PERISHABLE


# ---------------------------------------------------------------------------
# Aggregates over a list of rows
# ---------------------------------------------------------------------------

static func sum_kind_days(rows: Array, catalog, kind: String) -> int:
	var total := 0
	for row in rows:
		if row_kind(row, catalog) == kind:
			total += row_effective_days(row, catalog)
	return total


static func sum_food_days(rows: Array, catalog) -> int:
	return sum_kind_days(rows, catalog, KIND_FOOD)


static func sum_fodder_days(rows: Array, catalog) -> int:
	return sum_kind_days(rows, catalog, KIND_FODDER)


## Water currently held across all water-bearing containers (person-days).
static func sum_water_days(rows: Array, catalog) -> int:
	var total := 0
	for row in rows:
		if row_holds_water(row, catalog):
			total += row_effective_days(row, catalog)
	return total


## Maximum water the party could carry if every container were topped off
## (Σ container capacities, person-days) — used by fill-at-source.
static func sum_water_capacity_days(rows: Array, catalog) -> int:
	var total := 0
	for row in rows:
		if row_holds_water(row, catalog):
			total += row_capacity_days(row, catalog)
	return total


## Returns the food rows from [param rows] sorted in consumption order
## (perishable → standard → iron). Stable within a priority band.
static func food_rows_in_priority(rows: Array, catalog) -> Array:
	var food: Array = []
	for row in rows:
		if row_kind(row, catalog) == KIND_FOOD:
			food.append(row)
	food.sort_custom(func(a, b) -> bool:
		return ProvisionsLedger.food_priority(ProvisionsLedger.row_item_key(a)) \
			< ProvisionsLedger.food_priority(ProvisionsLedger.row_item_key(b)))
	return food


# ---------------------------------------------------------------------------
# Daily need
# ---------------------------------------------------------------------------

## Humanoids that eat/drink each day: PCs + humanoid henchmen. Mercenaries are
## independent contractors (they feed themselves) and are excluded, matching
## SustenanceResolver's party_size and the Party tab's §6.3.1 rule.
static func humanoid_count(party_data: PartyData) -> int:
	if party_data == null:
		return 0
	var count := 0
	for cd in party_data.character_data:
		if cd == null:
			continue
		if cd.character_type == "pc" or cd.character_type == "henchman":
			count += 1
	return count
