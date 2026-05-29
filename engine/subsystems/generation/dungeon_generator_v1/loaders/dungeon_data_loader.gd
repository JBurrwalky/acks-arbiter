class_name DungeonDataLoader
extends RefCounted

## Loads data/dungeon_generator/*.json (the DG-V1.A build-time extraction) into
## memory. NOT an autoload — the V1 generator instantiates it explicitly so its
## data dependencies are visible at the call site (build plan DG-V1.D note).
##
## Per coding_conventions §7.4: no runtime XML reads. All RAW data comes from
## these pre-extracted JSON files. Each file is an object {_source, columns, rows};
## consumers use rows(table_name) plus the static parse helpers below.

const DATA_DIR := "res://data/dungeon_generator/"

const TABLE_NAMES: Array[String] = [
	"dungeon_stocking",
	"unprotected_treasure",
	"dungeon_wandering_monster_level",
	"wandering_monster_table_guidelines",
	"random_monsters_by_level",
	"npc_alignment",
	"npc_class",
	"npc_level",
	"npc_treasure_type_by_level",
	"treasure_type_table",
	"gem_values",
	"jewelry_values",
]

var _tables: Dictionary = {}   ## table_name -> parsed root object {_source, columns, rows}
var _loaded: bool = false


## Load every table. Returns false (and logs the offending file) if any file is
## missing or malformed.
func load_all() -> bool:
	_tables.clear()
	_loaded = false
	for table_name in TABLE_NAMES:
		var path: String = DATA_DIR + table_name + ".json"
		if not FileAccess.file_exists(path):
			push_error("DungeonDataLoader: missing data file: %s" % path)
			return false
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_error("DungeonDataLoader: cannot open %s (err %d)" % [path, FileAccess.get_open_error()])
			return false
		var text: String = f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("rows"):
			push_error("DungeonDataLoader: malformed table '%s' (expected object with 'rows')" % table_name)
			return false
		_tables[table_name] = parsed
	_loaded = true
	return true


func is_loaded() -> bool:
	return _loaded


## The raw rows array for a table (e.g. rows("treasure_type_table")). Logs + []
## if the table is unknown or unloaded.
func rows(table_name: String) -> Array:
	if not _tables.has(table_name):
		push_error("DungeonDataLoader: unknown/unloaded table '%s'" % table_name)
		return []
	return (_tables[table_name] as Dictionary).get("rows", [])


# ---------------------------------------------------------------------------
# Shared parse helpers (static) — used by encounter_roller, treasure_resolver,
# and stocker so the d100-range parsing lives in exactly one place.
# ---------------------------------------------------------------------------

## Parse a roll-range cell like "01-30", "1-9", "12", "76-00" -> Vector2i(min, max).
## "00" is treated as 100 (d100 convention). A bare number "12" -> (12, 12).
## A blank / "-" cell -> Vector2i(-1, -1) (no range).
static func parse_range(s: String) -> Vector2i:
	var t: String = s.strip_edges()
	if t == "" or t == "-":
		return Vector2i(-1, -1)
	if "-" in t:
		var parts: PackedStringArray = t.split("-")
		return Vector2i(_cell_num(parts[0]), _cell_num(parts[1]))
	var n: int = _cell_num(t)
	return Vector2i(n, n)


static func _cell_num(s: String) -> int:
	var t: String = s.strip_edges()
	if t == "00":
		return 100
	return int(t)


## True if roll falls within the inclusive range encoded by range_str.
static func range_contains(range_str: String, roll: int) -> bool:
	var r: Vector2i = parse_range(range_str)
	if r.x < 0:
		return false
	return roll >= r.x and roll <= r.y
