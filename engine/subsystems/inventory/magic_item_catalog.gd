class_name MagicItemCatalog
extends RefCounted

## Loads the found-magic-item catalog (`data/treasure/magic_item_catalog.json`,
## extracted from `rules/acore_treasure_and_magic_items_rules.xml:197-216` by
## `tools/extract_magic_item_catalog.py`). Provides category-by-d100 lookup and
## within-category item selection that MATERIALIZES sub-roll / generator items.
##
## Scope: names + categories + magical_bonus + 167-unit encumbrance + sale price
## (value_gp) and creation time (creation_time_days). Selection within a category
## is uniform, EXCEPT items carrying a `sub_roll` table (Ring of Protection — a
## d100 picks one of 5 priced variants) or a `generator` (Spell Scroll — the
## scroll_of_spells generator rolls class/count/levels and prices it). Per-item
## EFFECTS / charges / identification + binding specific named spells remain
## deferred to the magic-item usage session (gdd-treasure-item-backing.md §9).
## NOT an autoload — instantiate as needed (callers cache it).

const CATALOG_PATH := "res://data/treasure/magic_item_catalog.json"

var _items: Dictionary = {}        ## item_key -> item dict
var _by_category: Dictionary = {}  ## category -> Array[item dict]
var _type_table: Array = []        ## [{roll_min, roll_max, category}]
var _generators: Dictionary = {}   ## generator name -> generator spec
var _loaded: bool = false
var _load_error: String = ""


func _init() -> void:
	_load()


func is_loaded() -> bool:
	return _loaded


func get_load_error() -> String:
	return _load_error


func get_item(item_key: String) -> Dictionary:
	return _items.get(item_key, {})


func item_count() -> int:
	return _items.size()


## All top-level catalog items (un-materialized). For tests / tooling.
func get_all_items() -> Array:
	return _items.values()


## Category for a d100 roll (1-100) via the random_magic_type_table.
func category_for_roll(roll: int) -> String:
	for row in _type_table:
		if roll >= int(row.get("roll_min", 0)) and roll <= int(row.get("roll_max", 0)):
			return str(row.get("category", ""))
	if not _type_table.is_empty():
		return str(_type_table[-1].get("category", ""))  # clamp to last band
	return ""


## A random item dict from a category, or {} if the category is empty. Selection
## is uniform; the chosen item is then materialized (sub_roll / generator items
## resolve to a concrete, priced item — see _materialize).
func random_item_in_category(category: String, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = _by_category.get(category, [])
	if pool.is_empty():
		return {}
	var picked: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	return _materialize(picked, rng)


## Generator spec by name (e.g. "scroll_of_spells"), or {} if absent.
func get_generator(name: String) -> Dictionary:
	return _generators.get(name, {})


# ---------------------------------------------------------------------------
# Materialization: resolve sub_roll / generator items into a concrete, priced
# item. Normal items are returned unchanged. Deterministic given `rng`.
# ---------------------------------------------------------------------------

func _materialize(item: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if item.is_empty():
		return item
	if item.has("sub_roll"):
		return _resolve_sub_roll(item, rng)
	if str(item.get("generator", "")) == "scroll_of_spells":
		return _generate_spell_scroll(item, rng)
	return item


## Roll a d100 on the item's sub_roll table and return the matching variant,
## inheriting category / encumbrance / cursed-ness from the parent.
func _resolve_sub_roll(item: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var sub: Dictionary = item.get("sub_roll", {})
	var table: Array = sub.get("table", [])
	if table.is_empty():
		return item
	var roll: int = rng.randi_range(1, 100)
	var chosen: Dictionary = {}
	for v: Dictionary in table:
		if roll >= int(v.get("roll_min", 0)) and roll <= int(v.get("roll_max", 0)):
			chosen = v
			break
	if chosen.is_empty():
		chosen = table[table.size() - 1]
	var out: Dictionary = {
		"item_key": str(chosen.get("item_key", item.get("item_key", ""))),
		"name": str(chosen.get("name", item.get("name", ""))),
		"category": str(item.get("category", "")),
		"magical_bonus": int(chosen.get("magical_bonus", 0)),
		"is_cursed": bool(item.get("is_cursed", false)),
		"encumbrance_units": int(item.get("encumbrance_units", 167)),
		"value_gp": int(chosen.get("value_gp", -1)),
		"creation_time_days": int(chosen.get("creation_time_days", -1)),
	}
	if chosen.has("radius_ft"):
		out["radius_ft"] = int(chosen.get("radius_ft", 0))
	return out


## Build a Scroll of Spells: roll class (d4), spell count, and each spell's level
## (d100 per the class table). Price = price_per_spell_gp x sum(levels); time =
## days_per_spell_level x sum(levels). Records scroll_class + spell_levels for the
## later usage session (specific named spells are NOT bound here).
func _generate_spell_scroll(item: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var gen: Dictionary = _generators.get("scroll_of_spells", {})
	if gen.is_empty():
		return item
	# Class (d4: 1-3 arcane, 4 divine, per acore_treasure_and_magic_items_rules.xml:227).
	var c4: int = rng.randi_range(1, 4)
	var cls: String = "arcane"
	for r: Dictionary in gen.get("class_table", []):
		if c4 >= int(r.get("roll_min", 0)) and c4 <= int(r.get("roll_max", 0)):
			cls = str(r.get("class", "arcane"))
			break
	# Spell count: roll within the RAW "Spells (N)" sub-band (rows 41-76) of the
	# scrolls d100 table — reproduces the RAW conditional count distribution.
	var count_roll: Dictionary = gen.get("count_roll", {})
	var count_table: Array = count_roll.get("table", [])
	var count: int = 1
	if not count_table.is_empty():
		var croll: int = rng.randi_range(int(count_roll.get("roll_min", 1)), int(count_roll.get("roll_max", 1)))
		count = _lookup_band(count_table, croll, "count", 1)
	# Per-spell levels.
	var level_table: Array = (gen.get("level_tables", {}) as Dictionary).get(cls, [])
	var levels: Array = []
	var total_levels: int = 0
	for _i in range(count):
		var lvl: int = _lookup_band(level_table, rng.randi_range(1, 100), "level", 1)
		levels.append(lvl)
		total_levels += lvl
	var value_gp: int = int(gen.get("price_per_spell_gp", 500)) * total_levels
	var days: int = int(gen.get("days_per_spell_level", 7)) * total_levels
	var plural: String = "" if count == 1 else "s"
	return {
		"item_key": "spell_scroll",
		"name": "%s Scroll of Spells (%d spell%s)" % [cls.capitalize(), count, plural],
		"category": "scroll",
		"magical_bonus": 0,
		"is_cursed": false,
		"encumbrance_units": int(item.get("encumbrance_units", 167)),
		"value_gp": value_gp,
		"creation_time_days": days,
		"scroll_class": cls,
		"spell_levels": levels,
	}


## Generic d-roll band lookup: returns `field` from the first row whose
## [roll_min, roll_max] contains `roll` (used for both spell-level and spell-count
## tables). Falls back to the last row, then `fallback`.
func _lookup_band(table: Array, roll: int, field: String, fallback: int) -> int:
	for r: Dictionary in table:
		if roll >= int(r.get("roll_min", 0)) and roll <= int(r.get("roll_max", 0)):
			return int(r.get(field, fallback))
	if not table.is_empty():
		return int((table[table.size() - 1] as Dictionary).get(field, fallback))
	return fallback


## Resolve a treasure-table category token (e.g. "any", "potion",
## "sword, weapon or armor") to a specific catalog item. Unrecognised / "any"
## tokens roll on the d100 type table. Returns {} if nothing resolves.
func pick_for_token(token: String, rng: RandomNumberGenerator) -> Dictionary:
	var t: String = token.to_lower()
	var cats: Array[String] = []
	if "potion" in t:
		cats.append("potion")
	if "scroll" in t:
		cats.append("scroll")
	if "ring" in t:
		cats.append("ring")
	if "wand" in t or "staff" in t or "rod" in t:
		cats.append("rod_staff_wand")
	if "sword" in t:
		cats.append("sword")
	if "armor" in t or "armour" in t or "shield" in t:
		cats.append("armor")
	if "weapon" in t:
		cats.append("misc_weapon")
	if "miscellaneous item" in t or "miscellaneous magic" in t or "misc magic" in t:
		cats.append("misc_magic")
	if cats.is_empty():
		# "any" / unrecognised -> roll on the d100 type table.
		var c: String = category_for_roll(rng.randi_range(1, 100))
		if not c.is_empty():
			cats.append(c)
	if cats.is_empty():
		return {}
	var chosen: String = cats[rng.randi_range(0, cats.size() - 1)]
	return random_item_in_category(chosen, rng)


func _load() -> void:
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		_load_error = "cannot open %s" % CATALOG_PATH
		push_error("MagicItemCatalog: " + _load_error)
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_load_error = "malformed catalog JSON"
		push_error("MagicItemCatalog: " + _load_error)
		return
	var data: Dictionary = parsed
	_type_table = data.get("type_table", [])
	_generators = data.get("generators", {})
	for it in data.get("items", []):
		var key: String = str((it as Dictionary).get("item_key", ""))
		if key.is_empty():
			continue
		_items[key] = it
		var cat: String = str((it as Dictionary).get("category", ""))
		if not _by_category.has(cat):
			_by_category[cat] = []
		_by_category[cat].append(it)
	_loaded = not _items.is_empty() and not _type_table.is_empty()
