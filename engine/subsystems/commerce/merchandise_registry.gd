# MerchandiseRegistry — RAW Common + Precious merchandise tables for mercantile play
#
# Loads three JSON data files at init:
#   - data/commerce/common_merchandise.json  (20 entries; RAW acore-campaign-hijinks.xml:915-947)
#   - data/commerce/precious_merchandise.json (11 entries; RAW :949-974)
#   - data/commerce/animals_subtable.json    (7 entries; RAW :976-995 — dispatcher target for
#                                             common rows 'animals' and 'mounts')
#
# Public API per generation/gdd-settlement-economy.md §2.7:
#   - all_common(), all_precious(), all_merchandise()
#   - get_by_type(key), is_precious(key)
#   - base_price_gp(key), load_weight_stone(key)
#   - random_common(rng), random_precious(rng) — RAW d100 rolls; resolve dispatchers transparently
#   - monster_parts_count(monster_xp) — RAW L971-972 helper

extends Node


# ---------------------------------------------------------------------------
# Data paths
# ---------------------------------------------------------------------------

const COMMON_PATH := "res://data/commerce/common_merchandise.json"
const PRECIOUS_PATH := "res://data/commerce/precious_merchandise.json"
const ANIMALS_PATH := "res://data/commerce/animals_subtable.json"


# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _common_entries: Array = []          # Array[Dictionary] in d100-roll order
var _precious_entries: Array = []        # Array[Dictionary] in d100-roll order
var _animals_entries: Array = []         # Array[Dictionary] in d8-roll order
var _by_type: Dictionary = {}            # merchandise_type -> entry dict (covers common + precious)
var _precious_dispatch_range: Array = [86, 100]  # from common json


# ---------------------------------------------------------------------------
# Init
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load_common()
	_load_precious()
	_load_animals()
	print("MerchandiseRegistry: %d common + %d precious + %d animal subtable entries loaded" % [
		_common_entries.size(), _precious_entries.size(), _animals_entries.size()
	])


func _load_common() -> void:
	var data: Dictionary = _load_json(COMMON_PATH)
	if data.is_empty():
		return
	_common_entries = data.get("entries", [])
	_precious_dispatch_range = data.get("precious_dispatch_range", [86, 100])
	for entry in _common_entries:
		var key: String = entry.get("merchandise_type", "")
		if not key.is_empty():
			_by_type[key] = entry


func _load_precious() -> void:
	var data: Dictionary = _load_json(PRECIOUS_PATH)
	if data.is_empty():
		return
	_precious_entries = data.get("entries", [])
	for entry in _precious_entries:
		var key: String = entry.get("merchandise_type", "")
		if not key.is_empty():
			_by_type[key] = entry


func _load_animals() -> void:
	var data: Dictionary = _load_json(ANIMALS_PATH)
	if data.is_empty():
		return
	_animals_entries = data.get("entries", [])


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MerchandiseRegistry: cannot open %s" % path)
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("MerchandiseRegistry: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}
	if not (json.data is Dictionary):
		push_error("MerchandiseRegistry: %s did not parse to a Dictionary" % path)
		return {}
	return json.data as Dictionary


# ---------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------

## Returns the array of 20 common-merchandise entry dicts in d100-roll order.
func all_common() -> Array:
	return _common_entries.duplicate()


## Returns the array of 11 precious-merchandise entry dicts in d100-roll order.
func all_precious() -> Array:
	return _precious_entries.duplicate()


## Returns all 31 entries (common first, then precious) in roll order.
func all_merchandise() -> Array:
	var out: Array = []
	for e in _common_entries:
		out.append(e)
	for e in _precious_entries:
		out.append(e)
	return out


## Returns the entry dict for a merchandise_type key, or {} if not found.
func get_by_type(merchandise_type: String) -> Dictionary:
	return _by_type.get(merchandise_type, {}).duplicate()


## Returns true if the type is a precious-merchandise entry.
func is_precious(merchandise_type: String) -> bool:
	var entry: Dictionary = _by_type.get(merchandise_type, {})
	return entry.get("precious", false)


# ---------------------------------------------------------------------------
# Price / weight
# ---------------------------------------------------------------------------

## Returns the base price in gp. Returns 0 for dispatcher rows (animals/mounts)
## per §2.5.1 — caller should resolve the dispatcher via random_common/_precious
## first, then ask for the concrete row's price.
func base_price_gp(merchandise_type: String) -> int:
	var entry: Dictionary = _by_type.get(merchandise_type, {})
	var v: Variant = entry.get("base_price_gp", null)
	if v == null:
		return 0
	return int(v)


## Returns the load weight in stone. Returns 0 for dispatcher rows.
func load_weight_stone(merchandise_type: String) -> int:
	var entry: Dictionary = _by_type.get(merchandise_type, {})
	var v: Variant = entry.get("load_weight_stone", null)
	if v == null:
		return 0
	return int(v)


# ---------------------------------------------------------------------------
# Random roll — RAW d100 tables
# ---------------------------------------------------------------------------

## Rolls d100 on the Common Merchandise table. If the roll falls in
## precious_dispatch_range (86-100), recurses into the precious table.
## If the resolved row is an 'animals' or 'mounts' dispatcher, resolves via
## the animals sub-table. Returns a fully-resolved merchandise dict with
## concrete load_weight_stone and base_price_gp (the dispatcher row's null
## values are replaced by the animal sub-table's stone_per_load and
## price_per_load_gp).
func random_common(rng: RandomNumberGenerator) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var roll: int = rng.randi_range(1, 100)
	if roll >= _precious_dispatch_range[0] and roll <= _precious_dispatch_range[1]:
		return random_precious(rng)
	for entry in _common_entries:
		var rr: Array = entry.get("roll_range", [0, 0])
		if roll >= int(rr[0]) and roll <= int(rr[1]):
			return _resolve_dispatcher(entry, rng)
	push_error("MerchandiseRegistry.random_common: no common entry matched d100=%d" % roll)
	return {}


## Rolls d100 on the Precious Merchandise table. Returns a concrete entry dict.
func random_precious(rng: RandomNumberGenerator) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var roll: int = rng.randi_range(1, 100)
	for entry in _precious_entries:
		var rr: Array = entry.get("roll_range", [0, 0])
		if roll >= int(rr[0]) and roll <= int(rr[1]):
			return entry.duplicate()
	push_error("MerchandiseRegistry.random_precious: no precious entry matched d100=%d" % roll)
	return {}


## Resolves dispatcher rows (animals/mounts) by rolling on the animals sub-table
## per the dispatcher's subroll formula. Non-dispatcher rows are returned as-is.
func _resolve_dispatcher(entry: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var dispatcher: Variant = entry.get("dispatcher", null)
	if dispatcher == null:
		return entry.duplicate()
	if String(dispatcher) != "animals_subtable":
		push_error("MerchandiseRegistry: unknown dispatcher %s for type %s" % [
			str(dispatcher), entry.get("merchandise_type", "")
		])
		return entry.duplicate()
	var subroll: String = String(entry.get("subroll", ""))
	var animal_roll: int = _roll_subroll(subroll, rng)
	for animal in _animals_entries:
		var rr: Array = animal.get("roll_range", [0, 0])
		if animal_roll >= int(rr[0]) and animal_roll <= int(rr[1]):
			# Return a resolved dict combining the merchandise-row identity
			# with the concrete animal's load weight and price.
			var resolved: Dictionary = entry.duplicate()
			resolved["resolved_animal_type"] = animal.get("animal_type", "")
			resolved["resolved_animal_display"] = animal.get("display_name", "")
			resolved["load_weight_stone"] = int(animal.get("stone_per_load", 0))
			resolved["base_price_gp"] = int(animal.get("price_per_load_gp", 0))
			resolved["fodder_gp_per_week"] = int(animal.get("fodder_gp_per_week", 0))
			return resolved
	push_error("MerchandiseRegistry: animals subroll %d (%s) matched no animal row" % [animal_roll, subroll])
	return entry.duplicate()


## Parses simple dice specs '1d6' or '1d4+4'. Returns the rolled value.
func _roll_subroll(spec: String, rng: RandomNumberGenerator) -> int:
	# Supports formats: NdM, NdM+K, NdM-K
	var add_idx: int = spec.find("+")
	var sub_idx: int = spec.find("-")
	var modifier: int = 0
	var dice_part: String = spec
	if add_idx > -1:
		dice_part = spec.substr(0, add_idx)
		modifier = int(spec.substr(add_idx + 1))
	elif sub_idx > -1:
		dice_part = spec.substr(0, sub_idx)
		modifier = -int(spec.substr(sub_idx + 1))
	var d_idx: int = dice_part.find("d")
	if d_idx < 0:
		push_error("MerchandiseRegistry._roll_subroll: malformed spec '%s'" % spec)
		return 0
	var n: int = int(dice_part.substr(0, d_idx))
	var sides: int = int(dice_part.substr(d_idx + 1))
	if n <= 0 or sides <= 0:
		push_error("MerchandiseRegistry._roll_subroll: invalid dice in '%s'" % spec)
		return 0
	var total: int = 0
	for _i in n:
		total += rng.randi_range(1, sides)
	return total + modifier


# ---------------------------------------------------------------------------
# Monster parts helper (RAW acore-campaign-hijinks.xml:971-972)
# ---------------------------------------------------------------------------

## Returns the number of monster parts per load given the monster's XP value.
## Per RAW: each part is worth 1 gp value equal to the monster's XP, and the
## load's gp base price is 300, so parts_per_load = floor(300 / monster_xp).
## Returns 0 if monster_xp <= 0 (safety).
func monster_parts_count(monster_xp_value: int) -> int:
	if monster_xp_value <= 0:
		return 0
	return int(floor(300.0 / float(monster_xp_value)))
