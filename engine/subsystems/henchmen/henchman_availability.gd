class_name HenchmanAvailability
extends RefCounted

## Phase G-2: Generates the monthly henchman pool for a settlement based on
## market class, using the sacred tables from acore_equipment.xml and
## ax_henchmen_recruitment_expanded.xml.
##
## Produces an Array of {class_id, level} specs ready for
## CharacterGenerator.generate_henchman(). Also assigns weekly allotment.

## Returns an Array of {class_id: String, level: int, allotment_week: int}.
## Rolls availability for each class rarity that the market supports, then
## determines level for each available henchman. Assigns weekly allotment per
## sacred rules (½ week 1, ¼ week 2, remainder week 3).
static func generate_pool(market_class: int, dice = null) -> Array:
	var candidates: Array = []

	var available_classes: Array = _roll_available_classes(market_class, dice)

	for class_id in available_classes:
		var level := _determine_level(market_class, dice)
		candidates.append({"class_id": class_id, "level": level})

	var allotment := HenchmanTables.weekly_allotment(candidates.size())
	var idx := 0
	for week in range(3):
		var count: int = allotment[week]
		for _i in range(count):
			if idx < candidates.size():
				candidates[idx]["allotment_week"] = week + 1
				idx += 1

	return candidates


## Rolls the search cost for one week of searching in the given market class.
static func roll_search_cost(market_class: int, dice = null) -> int:
	var spec := HenchmanTables.search_cost_spec(market_class)
	var roll := _roll(spec["dice_count"], spec["dice_sides"], dice)
	return roll + spec["modifier"]


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## For each class known to the rarity table, check if the market supports that
## rarity, then roll the percentage chance. Returns Array of class_id strings.
static func _roll_available_classes(market_class: int, dice) -> Array:
	var result: Array = []
	var seen_classes: Dictionary = {}

	for class_id in HenchmanTables.CLASS_RARITY:
		if seen_classes.has(class_id):
			continue
		var rarity: String = HenchmanTables.CLASS_RARITY[class_id]
		var avail: Dictionary = HenchmanTables.rarity_availability(rarity, market_class)
		if avail["count"] < 0:
			continue
		if avail["percent"] < 100:
			var pct_roll := _roll(1, 100, dice)
			if pct_roll > avail["percent"]:
				continue
		var count: int = avail["count"]
		for _i in range(count):
			result.append(class_id)
			seen_classes[class_id] = true

	return result


## Determines a henchman's level via the 1d20 table.
static func _determine_level(market_class: int, dice) -> int:
	var roll := _roll(1, 20, dice)
	return HenchmanTables.level_from_roll(roll, market_class)


static func _roll(count: int, sides: int, dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(count, sides))
	var total := 0
	for _i in range(count):
		total += (randi() % sides) + 1
	return total
