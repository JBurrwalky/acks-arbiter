class_name HenchmanAvailability
extends RefCounted

## Phase G-2: Generates the monthly henchman pool for a settlement based on
## market class, using the sacred tables from acore_equipment.xml and
## ax_henchmen_recruitment_expanded.xml.
##
## Produces an Array of {class_id, level} specs ready for
## CharacterGenerator.generate_henchman(). Also assigns weekly allotment.

## Returns an Array of
##   {class_id: String, level: int, allotment_week: int,
##    is_normal_man_placeholder: bool}.
## Generates the monthly tavern pool by rolling per-level counts from the
## acore_equipment.xml availability table (4d100 Normal Men in Class I markets,
## 1d2 in Class VI, etc.), then assigning each slot a class via the rarity-
## weighted distribution for that market class.
##
## Normal Men (level 0) are not yet implemented as a class. Per project
## decision (smoke test batch 3): each level-0 slot is filled with a
## Level-1 Fighter placeholder and flagged with is_normal_man_placeholder.
## A future session will replace these stubs with the proper 0th-level
## Normal Man class.
static func generate_pool(market_class: int, dice = null) -> Array:
	var candidates: Array = []

	# acore_equipment.xml:730 — per-level availability by market class.
	# Levels 0..4 are the spec-defined range; higher levels are too rare to
	# show up in standard recruitment.
	for level in range(5):
		var count := _roll_level_count(level, market_class, dice)
		for _i in range(count):
			if level == 0:
				# TODO(normal-men): replace this placeholder with a real
				# 0th-level Normal Man character once the class is built.
				# The is_normal_man_placeholder flag is the swap point.
				candidates.append({
					"class_id": "fighter",
					"level": 1,
					"is_normal_man_placeholder": true,
				})
			else:
				var class_id := _pick_class_for_market(market_class, dice)
				candidates.append({
					"class_id": class_id,
					"level": level,
					"is_normal_man_placeholder": false,
				})

	# Sacred allotment: ½ week 1, ¼ week 2, remainder week 3.
	var allotment := HenchmanTables.weekly_allotment(candidates.size())
	var idx := 0
	for week in range(3):
		var w_count: int = allotment[week]
		for _i in range(w_count):
			if idx < candidates.size():
				candidates[idx]["allotment_week"] = week + 1
				idx += 1

	return candidates


## Rolls the count of henchmen at a given level for a market class. Honours
## both the dice expressions ("5d10") and the percent-chance entries
## ("1 (65%)") in the level_availability table.
static func _roll_level_count(level: int, market_class: int, dice) -> int:
	var spec := HenchmanTables.level_availability(level, market_class)
	var dc: int = int(spec.get("dice_count", 0))
	var ds: int = int(spec.get("dice_sides", 0))
	var pct: int = int(spec.get("percent", 0))
	if dc > 0 and ds > 0:
		return _roll(dc, ds, dice)
	if pct > 0:
		return 1 if _roll(1, 100, dice) <= pct else 0
	return 0


## Picks a class for a leveled henchman slot. Builds a weighted pool from the
## rarity-availability table at the given market class — common classes
## (fighter/thief) dominate small markets, with higher rarities slipping in
## at large markets. Returns "fighter" if the pool somehow comes up empty.
static func _pick_class_for_market(market_class: int, dice) -> String:
	var pool: Array = []
	for class_id in HenchmanTables.CLASS_RARITY:
		var rarity: String = HenchmanTables.CLASS_RARITY[class_id]
		var avail: Dictionary = HenchmanTables.rarity_availability(rarity, market_class)
		var count: int = int(avail.get("count", -1))
		if count < 0:
			continue
		var pct: int = int(avail.get("percent", 0))
		var weight: int = count * maxi(1, pct)
		for _i in range(weight):
			pool.append(class_id)
	if pool.is_empty():
		return "fighter"
	var idx: int = (_roll(1, pool.size(), dice) - 1) % pool.size()
	return pool[idx]


## Rolls the search cost for one week of searching in the given market class.
static func roll_search_cost(market_class: int, dice = null) -> int:
	var spec := HenchmanTables.search_cost_spec(market_class)
	var roll := _roll(spec["dice_count"], spec["dice_sides"], dice)
	return roll + spec["modifier"]


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _roll(count: int, sides: int, dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(count, sides))
	var total := 0
	for _i in range(count):
		total += (randi() % sides) + 1
	return total
