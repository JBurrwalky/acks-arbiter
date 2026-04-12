class_name TokenAtlasRegistry
extends RefCounted

## Central lookup for class-specific token sprite atlases.
##
## Maps "<class_id>/<variant>" → 3x3 sprite atlas texture (8-facing layout).
## The variant component lets each class have multiple visual options
## (e.g., "default", "scarred", "fur") that the player picks during character
## creation. The variant string is persisted in CharacterData.token_variant
## via the characters.token_variant column (added in migration 026).
##
## Returns null for class/variant combinations without a registered atlas —
## CombatantToken falls back to the placeholder circle in that case.
##
## Adding new variants requires NO database migration. Just:
##   1. Drop a PNG into assets/tokens/ matching the format in ATLAS_SPEC.md
##   2. Add an entry to _ATLAS_PATHS below
##   3. Done — character creation UI auto-discovers it via get_available_variants()


## "<class_id>/<variant>" → atlas resource path
const _ATLAS_PATHS := {
	"barbarian/default": "res://assets/tokens/barbarian_1_atlas.png",
}

## Cache loaded textures so we don't re-read from disk each token creation.
static var _cache: Dictionary = {}


## Build the registry lookup key from class_id + variant.
## Empty variant becomes "default".
static func _make_key(class_id: String, variant: String) -> String:
	if variant.is_empty():
		variant = "default"
	return "%s/%s" % [class_id, variant]


## Return the atlas Texture2D for a (class_id, variant) pair, or null if none
## is registered. Falls back from the specific variant to "<class_id>/default"
## if the requested variant is not found.
static func get_atlas_for_class(class_id: String, variant: String = "") -> Texture2D:
	if class_id.is_empty():
		return null

	var key: String = _make_key(class_id, variant)

	# Cache hit
	if _cache.has(key):
		return _cache[key]

	# Try the requested variant first
	if _ATLAS_PATHS.has(key):
		var tex: Texture2D = _load_texture(_ATLAS_PATHS[key])
		_cache[key] = tex
		return tex

	# Fall back to default variant for this class
	var default_key: String = _make_key(class_id, "default")
	if default_key != key and _ATLAS_PATHS.has(default_key):
		var fallback_tex: Texture2D = _load_texture(_ATLAS_PATHS[default_key])
		_cache[key] = fallback_tex
		return fallback_tex

	_cache[key] = null
	return null


## Returns the list of available variant names for a class, e.g.
## ["default", "scarred", "fur"]. Empty array if the class has no atlases.
## Used by the character creation UI to populate the variant picker.
static func get_available_variants(class_id: String) -> Array[String]:
	var result: Array[String] = []
	if class_id.is_empty():
		return result
	var prefix: String = class_id + "/"
	for key: String in _ATLAS_PATHS.keys():
		if key.begins_with(prefix):
			var variant: String = key.substr(prefix.length())
			if not variant.is_empty():
				result.append(variant)
	# Sort with "default" first for consistent UI ordering
	result.sort()
	if "default" in result:
		result.erase("default")
		result.insert(0, "default")
	return result


## Returns true if the given class has at least one registered atlas variant.
static func has_atlases_for_class(class_id: String) -> bool:
	return not get_available_variants(class_id).is_empty()


## Load and validate a texture resource. Returns null on failure.
static func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("TokenAtlasRegistry: atlas not found at %s" % path)
		return null
	return load(path)
