class_name PortraitPickerPanel
extends VBoxContainer

## Step 8 — Portrait Selection.
##
## Sources:
##   Shipped:   data/portrait_manifest.json → res://assets/portraits/*.png
##   User-added: user://portraits/*.png (DirAccess scan; works in all builds)
##
## Shipped portraits use the naming convention ethnicity_class_gender_number
## (ethnicity may be the two-token "greco_roman"); the manifest carries the
## parsed class/sex/number alongside each entry.
##
## Only portraits whose class matches the selected class are loaded into the grid
## (the full set is 400+ images — building a thumbnail for every one lags the
## step). User-added portraits are always shown so custom art is never hidden.
## The default selection is the lowest-numbered portrait of the selected class,
## preferring the current sex.
## Selected portrait highlighted; preview shown at 256×256.
## No class restrictions on manual choice — any shown portrait may be chosen.


const MANIFEST_PATH  := "res://data/portrait_manifest.json"
const USER_DIR       := "user://portraits"
const THUMB_SIZE     := Vector2i(96, 96)
const PREVIEW_SIZE   := Vector2i(256, 256)

var _state: Dictionary = {}

var _portraits: Array = []           # Array of {id, class, sex, number, path, is_user}
var _thumb_cache: Dictionary = {}    # portrait_id -> ImageTexture

var _grid: GridContainer
var _preview_rect: TextureRect
var _preview_name_label: Label
var _selected_id: String = ""


func setup(state: Dictionary) -> void:
	_state = state
	if get_child_count() == 0:
		_build_ui()
	_load_portrait_list()
	_populate_grid()
	# Auto-select class default or restore prior selection
	var prior_id: String = _state.get("portrait_id", "")
	if not prior_id.is_empty() and _portrait_exists(prior_id):
		_select_portrait(prior_id)
	else:
		_auto_select_class_default()


func is_complete() -> bool:
	return not (_state.get("portrait_id", "") as String).is_empty()


# ---------------------------------------------------------------------------
# Portrait list loading
# ---------------------------------------------------------------------------

func _load_portrait_list() -> void:
	_portraits.clear()
	_thumb_cache.clear()

	# Load shipped portraits from manifest
	var shipped := _load_manifest()
	_portraits.append_array(shipped)

	# Scan user://portraits/ for additional PNGs
	_ensure_user_dir()
	var user_portraits := _scan_user_portraits()
	for up in user_portraits:
		# Avoid duplicates (user portrait overrides shipped if same id)
		var found := false
		for i in range(_portraits.size()):
			if _portraits[i].get("id", "") == up.get("id", ""):
				_portraits[i] = up   # user version takes precedence
				found = true
				break
		if not found:
			_portraits.append(up)


func _load_manifest() -> Array:
	var result: Array = []
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_error("PortraitPickerPanel: manifest not found at %s" % MANIFEST_PATH)
		return result
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return result
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return result
	var data: Dictionary = json.data
	for entry in data.get("portraits", []):
		result.append({
			"id":      entry.get("id", ""),
			"class":   entry.get("class", ""),
			"sex":     entry.get("sex", ""),
			"number":  int(entry.get("number", 0)),
			"path":    entry.get("path", ""),
			"is_user": false,
		})
	return result


func _ensure_user_dir() -> void:
	if not DirAccess.dir_exists_absolute(USER_DIR):
		DirAccess.make_dir_absolute(USER_DIR)


func _scan_user_portraits() -> Array:
	var result: Array = []
	var dir := DirAccess.open(USER_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var filename := dir.get_next()
	while not filename.is_empty():
		if not dir.current_is_dir() and filename.ends_with(".png"):
			var portrait_id := filename.trim_suffix(".png")
			var meta := _parse_portrait_stem(portrait_id)
			result.append({
				"id":      portrait_id,
				"class":   meta.get("class", ""),
				"sex":     meta.get("sex", ""),
				"number":  int(meta.get("number", 0)),
				"path":    "%s/%s" % [USER_DIR, filename],
				"is_user": true,
			})
		filename = dir.get_next()
	dir.list_dir_end()
	return result


## Single-token ethnicity prefixes (the only two-token prefix, "greco_roman", is
## handled inline). Used to locate the class span in a portrait filename stem.
const _ETH_SINGLE := {
	"asian": true, "chaotic": true, "egyptian": true, "english": true,
	"germanic": true, "lawful": true, "mesopotamian": true, "neutral": true,
	"nubian": true,
}


## Parse a portrait filename stem into {class, sex, number}.
## Primary convention: ethnicity_class_gender_number (ethnicity may be the
## two-token "greco_roman"; class may itself be multi-token). The class token is
## normalized to match class_id (hyphens -> underscores, e.g. anti-paladin ->
## anti_paladin). Falls back to the legacy portrait_{class}_{nn} form for any
## user-supplied portraits still using the old naming. Returns {} on no match.
func _parse_portrait_stem(stem: String) -> Dictionary:
	var parts := stem.split("_")
	if parts.size() >= 4:
		var last: String = parts[parts.size() - 1]
		var sex: String = parts[parts.size() - 2]
		if (sex == "male" or sex == "female") and last.is_valid_int():
			var head: String = parts[0]
			var class_start := -1
			if head == "greco" and parts.size() >= 5 and parts[1] == "roman":
				class_start = 2
			elif _ETH_SINGLE.has(head):
				class_start = 1
			if class_start != -1:
				var class_parts: Array = []
				for i in range(class_start, parts.size() - 2):
					class_parts.append(parts[i])
				if not class_parts.is_empty():
					return {
						"class":  "_".join(class_parts).replace("-", "_"),
						"sex":    sex,
						"number": last.to_int(),
					}
	# Legacy fallback: portrait_{class}_{nn}
	if parts.size() >= 3 and parts[0] == "portrait":
		var legacy_last: String = parts[parts.size() - 1]
		if legacy_last.is_valid_int():
			var legacy_parts: Array = []
			for i in range(1, parts.size() - 1):
				legacy_parts.append(parts[i])
			if not legacy_parts.is_empty():
				return {
					"class":  "_".join(legacy_parts).replace("-", "_"),
					"sex":    "",
					"number": legacy_last.to_int(),
				}
	return {}


func _portrait_exists(portrait_id: String) -> bool:
	for p in _portraits:
		if p.get("id", "") == portrait_id:
			return true
	return false


# ---------------------------------------------------------------------------
# Grid population
# ---------------------------------------------------------------------------

func _populate_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()

	var class_id: String = _state.get("class_id", "")
	# Only load portraits for the selected class — the full set is 400+ images and
	# building a thumbnail for every one lags the step. User portraits are always
	# shown so custom art is never hidden by the class filter.
	var ordered := _portraits_for_class(class_id)

	for p in ordered:
		var portrait_id: String = p.get("id", "")
		if portrait_id.is_empty():
			continue
		var thumb := _get_thumbnail(p)
		if thumb == null:
			continue
		var btn := TextureButton.new()
		btn.texture_normal = thumb
		btn.custom_minimum_size = Vector2(THUMB_SIZE)
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.name = portrait_id
		btn.pressed.connect(_on_portrait_selected.bind(portrait_id))
		_grid.add_child(btn)


## Shipped portraits whose class matches [param class_id] (sorted by number),
## followed by every user portrait. If no shipped portrait matches the class
## (e.g. a class with no art yet), falls back to showing all shipped portraits so
## the player is never left with an empty grid.
func _portraits_for_class(class_id: String) -> Array:
	var shipped_match: Array = []
	var user_all: Array = []
	for p in _portraits:
		if p.get("is_user", false):
			user_all.append(p)
		elif p.get("class", "") == class_id:
			shipped_match.append(p)
	shipped_match.sort_custom(func(a, b): return int(a.get("number", 0)) < int(b.get("number", 0)))

	var ordered: Array = []
	if shipped_match.is_empty():
		# Fallback: no class-specific art — show everything shipped.
		for p in _portraits:
			if not p.get("is_user", false):
				ordered.append(p)
	else:
		ordered.append_array(shipped_match)
	ordered.append_array(user_all)
	return ordered


func _get_thumbnail(portrait_entry: Dictionary) -> ImageTexture:
	var portrait_id: String = portrait_entry.get("id", "")
	if _thumb_cache.has(portrait_id):
		return _thumb_cache[portrait_id]

	var img: Image = null
	var path: String = portrait_entry.get("path", "")
	if portrait_entry.get("is_user", false):
		img = Image.load_from_file(path)
	else:
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				img = tex.get_image()

	if img == null:
		return null

	img.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(img)
	_thumb_cache[portrait_id] = texture
	return texture


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func _auto_select_class_default() -> void:
	var class_id: String = _state.get("class_id", "")
	var sex: String = _state.get("sex", "")
	var candidates := _portraits_for_class(class_id)
	if candidates.is_empty():
		return

	# Prefer the lowest-numbered shipped portrait of this class matching the
	# current sex; fall back to the lowest-numbered of the class regardless of
	# sex; finally fall back to the first candidate (covers the no-art fallback
	# grid and user-only situations).
	var best_sex := {}
	var best_any := {}
	for p in candidates:
		if p.get("is_user", false):
			continue
		if not best_any.has("id") or int(p.get("number", 0)) < int(best_any.get("number", 0)):
			best_any = p
		if not sex.is_empty() and p.get("sex", "") == sex:
			if not best_sex.has("id") or int(p.get("number", 0)) < int(best_sex.get("number", 0)):
				best_sex = p

	if best_sex.has("id"):
		_select_portrait(best_sex.get("id", ""))
	elif best_any.has("id"):
		_select_portrait(best_any.get("id", ""))
	else:
		_select_portrait(candidates[0].get("id", ""))


func _on_portrait_selected(portrait_id: String) -> void:
	_select_portrait(portrait_id)


func _select_portrait(portrait_id: String) -> void:
	_selected_id = portrait_id
	_state["portrait_id"] = portrait_id

	# Highlight selected button; un-highlight others
	for child in _grid.get_children():
		if child is TextureButton:
			child.modulate = Color.WHITE
	var sel_btn := _grid.get_node_or_null(portrait_id)
	if sel_btn is TextureButton:
		(sel_btn as TextureButton).modulate = Color(0.6, 1.0, 0.6, 1.0)  # green tint

	# Load full-size preview
	var full_texture := _load_full_texture(portrait_id)
	_preview_rect.texture = full_texture
	_preview_name_label.text = portrait_id.replace("_", " ").capitalize()


func _load_full_texture(portrait_id: String) -> Texture2D:
	for p in _portraits:
		if p.get("id", "") != portrait_id:
			continue
		if p.get("is_user", false):
			var img := Image.load_from_file(p.get("path", ""))
			if img != null:
				return ImageTexture.create_from_image(img)
		else:
			var path: String = p.get("path", "")
			if ResourceLoader.exists(path):
				return load(path) as Texture2D
	return null


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = "Choose a portrait for your character."
	add_child(header)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	add_child(hbox)

	# Left: portrait grid
	var grid_panel := PanelContainer.new()
	grid_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_panel.size_flags_stretch_ratio = 0.7
	grid_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiSurfaceStyles.apply_textured_panel(grid_panel)
	hbox.add_child(grid_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_panel.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)

	# Right: preview
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_stretch_ratio = 0.3
	right_vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(right_vbox)

	_preview_rect = TextureRect.new()
	_preview_rect.custom_minimum_size = Vector2(PREVIEW_SIZE)
	_preview_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right_vbox.add_child(_preview_rect)

	_preview_name_label = Label.new()
	_preview_name_label.text = ""
	_preview_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(_preview_name_label)

	var note := Label.new()
	note.text = "Add custom portraits to:\nuser://portraits/"
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_TEXT_COLOR)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_vbox.add_child(note)
