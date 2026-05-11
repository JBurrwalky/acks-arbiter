class_name BpcTable
extends RefCounted

## Battle Phase Countdown starting count by terrain × 1d8 roll, per
## daw_axioms_pitching_battle.xml §battle_preparation.set_battle_phase_countdown
## L24-101. Heavy rain or snow increases the terrain minimum by 1.
##
## RAW table (terrain → roll buckets):
##                    1     2-4    5-7    8
##   clear_or_grass   1     1      1      2
##   barren           1     1      2      2
##   desert           1     1      2      2
##   hills            1     1      1      2
##   scrub            1     1      1      2
##   woods            1     1      1      2
##   mountains        1     2      2      3
##   jungle           1     1      2      3
##   swamp            1     2      2      3
##
## Public API:
##   roll_starting_bpc(terrain, weather, dice_roller=Callable()) -> int

const TABLE := {
	# terrain : [roll_1, roll_2_to_4, roll_5_to_7, roll_8]
	"clear_or_grass": [1, 1, 1, 2],
	"plain":          [1, 1, 1, 2],
	"plains":         [1, 1, 1, 2],
	"clear":          [1, 1, 1, 2],
	"grass":          [1, 1, 1, 2],
	"barren":         [1, 1, 2, 2],
	"desert":         [1, 1, 2, 2],
	"hills":          [1, 1, 1, 2],
	"scrub":          [1, 1, 1, 2],
	"woods":          [1, 1, 1, 2],
	"forest":         [1, 1, 1, 2],
	"mountains":      [1, 2, 2, 3],
	"mountain":       [1, 2, 2, 3],
	"jungle":         [1, 1, 2, 3],
	"swamp":          [1, 2, 2, 3],
}

const HEAVY_WEATHERS := ["heavy_rain", "rainy_heavy", "snowy_heavy", "snow_heavy", "snowy"]


static func lookup_bpc(terrain: String, roll_1d8: int, weather: String = "calm") -> int:
	var key: String = terrain.to_lower()
	var row: Array = TABLE.get(key, TABLE["clear_or_grass"])
	var bucket: int = _bucket_for_roll(roll_1d8)
	var bpc: int = int(row[bucket])
	# Heavy rain or snow increases terrain minimum by 1.
	if HEAVY_WEATHERS.has(weather.to_lower()):
		bpc += 1
	return bpc


static func roll_starting_bpc(terrain: String, weather: String = "calm", dice_roller: Callable = Callable()) -> Dictionary:
	var roll: int = _roll(dice_roller, 1, 8)
	var bpc: int = lookup_bpc(terrain, roll, weather)
	return {"roll": roll, "bpc": bpc, "terrain": terrain, "weather": weather}


static func _bucket_for_roll(roll: int) -> int:
	if roll <= 1:
		return 0
	if roll <= 4:
		return 1
	if roll <= 7:
		return 2
	return 3


static func _roll(dice_roller: Callable, count: int, sides: int) -> int:
	if dice_roller.is_valid():
		return int(dice_roller.call(count, sides))
	var total: int = 0
	for i in range(count):
		total += randi_range(1, sides)
	return total
