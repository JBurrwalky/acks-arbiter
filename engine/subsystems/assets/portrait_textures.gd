extends RefCounted

## Referenced via preload (not class_name) so consumers don't depend on the
## global class registry being refreshed — see the `const PortraitTextures :=
## preload(...)` in entity_strip / session_status_bar / cs_tab_equipment.
##
## Shared portrait-texture loader for the game's portrait surfaces (the Character
## tab entity strip, the session status bar, and the Equipment paper-doll — the
## only portrait consumers as of 2026-06-11).
##
## Portraits are large painted busts (~512-1024px) shown small (≈56-150px). Handing
## the full-res image to a small TextureRect makes the GPU minify it with no mip
## chain → hard aliasing. This helper builds a downscaled + MIPMAPPED copy so the
## GPU samples the right mip level at any display size. Consumers must also set
## their TextureRect's `texture_filter` to a mipmap mode (TEXTURE_FILTER_LINEAR_
## WITH_MIPMAPS) for the chain to be used. Done in code (not via import settings)
## so it needs no re-import of the shared portrait assets.
##
## portrait_id is a filename STEM (no extension): "user://portraits/<id>.png"
## override first, then the bundled "res://assets/portraits/<id>.png".

const DEFAULT_MAX_EDGE := 256

## Process-lifetime cache keyed by "<id>|<max_edge>". Textures are immutable +
## shared. (Mid-session portrait changes need a reload to reflect — same as the
## per-surface caches this replaces.)
static var _cache: Dictionary = {}


## Resolve a mipmapped, downscaled portrait texture for [param portrait_id].
## [param max_edge] caps the longest side of the backing image (px). Returns null
## if no portrait file is found.
static func resolve(portrait_id: String, max_edge: int = DEFAULT_MAX_EDGE) -> Texture2D:
	if portrait_id.is_empty():
		return null
	var key := "%s|%d" % [portrait_id, max_edge]
	if _cache.has(key):
		return _cache[key]

	var img: Image = null
	var fallback: Texture2D = null
	var user_path := "user://portraits/%s.png" % portrait_id
	if FileAccess.file_exists(user_path):
		img = Image.load_from_file(user_path)
	else:
		var res_path := "res://assets/portraits/%s.png" % portrait_id
		if ResourceLoader.exists(res_path):
			var tex := load(res_path) as Texture2D
			if tex != null:
				fallback = tex
				img = tex.get_image()

	var result: Texture2D = fallback  # null, or the raw texture if get_image() failed
	if img != null:
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		var longest := maxi(w, h)
		if longest > max_edge:
			var s := float(max_edge) / float(longest)
			img.resize(int(round(w * s)), int(round(h * s)), Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
		result = ImageTexture.create_from_image(img)

	_cache[key] = result
	return result


## Drop the cache (e.g. after a portrait is changed in character creation) so the
## next resolve() reloads from disk.
static func clear_cache() -> void:
	_cache.clear()
