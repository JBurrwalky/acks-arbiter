class_name AssetRegistry
extends RefCounted

## Central semantic-ID-to-path registry for all project assets.
##
## IDs use dot-notation: "portrait.fighter_01", "terrain.atlas", "ui.bg.vellum_base".
## Loaded lazily from res://data/asset_manifest.json on first access.
## Static state persists for the session; no autoload required.
##
## Usage:
##   var path := AssetRegistry.get_path("portrait.fighter_01")
##   if AssetRegistry.has_asset("terrain.atlas"):
##       source.texture = load(AssetRegistry.get_path("terrain.atlas"))


# ---------------------------------------------------------------------------
# Static state
# ---------------------------------------------------------------------------

static var _manifest: Dictionary = {}
static var _loaded: bool = false


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns the res:// path for [param id], or "" if not registered.
static func get_asset_path(id: String) -> String:
	_ensure_loaded()
	return _manifest.get(id, "")


## Returns true if [param id] is registered with a non-empty path.
static func has_asset(id: String) -> bool:
	return get_asset_path(id) != ""


## Registers [param id] → [param path], overwriting any existing entry.
## Useful for runtime overrides and testing.
static func register(id: String, path: String) -> void:
	_ensure_loaded()
	_manifest[id] = path


## Returns all registered IDs. Primarily for testing and debug tooling.
static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for k in _manifest.keys():
		ids.append(k)
	return ids


# ---------------------------------------------------------------------------
# Internal — manifest loading
# ---------------------------------------------------------------------------

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_manifest()


static func _load_manifest() -> void:
	const MANIFEST_PATH := "res://data/asset_manifest.json"
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_error("AssetRegistry: manifest not found at %s" % MANIFEST_PATH)
		return
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("AssetRegistry: could not open manifest at %s" % MANIFEST_PATH)
		return
	var text := file.get_as_text()
	file.close()
	var result: Variant = JSON.parse_string(text)
	if result == null or not result is Dictionary:
		push_error("AssetRegistry: manifest JSON parse failed")
		return
	_flatten("", result as Dictionary)


## Recursively flattens a nested Dictionary into [_manifest] using dot-notation keys.
## A top-level key "portrait" with child "fighter_01" becomes "portrait.fighter_01".
static func _flatten(prefix: String, obj: Dictionary) -> void:
	for key in obj.keys():
		var key_str: String = str(key)
		var full_key: String = (prefix + "." + key_str) if prefix != "" else key_str
		var value: Variant = obj[key]
		if value is Dictionary:
			_flatten(full_key, value)
		elif value is String:
			_manifest[full_key] = value
		else:
			push_warning("AssetRegistry: unexpected value type for key '%s' — skipping" % full_key)
