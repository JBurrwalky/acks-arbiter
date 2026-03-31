class_name PortraitPickerPanel
extends VBoxContainer

## Step 8 — Portrait Selection.
##
## Sources:
##   Shipped:   data/portrait_manifest.json → res://assets/portraits/*.png
##   User-added: user://portraits/*.png (DirAccess scan; works in all builds)
##
## Class-matching portraits shown first, then all others.
## Selected portrait highlighted; preview shown at 256×256.
## No class restrictions — any portrait may be chosen for any class.


const MANIFEST_PATH  := "res://data/portrait_manifest.json"
const USER_DIR       := "user://portraits"
const THUMB_SIZE     := Vector2i(96, 96)
const PREVIEW_SIZE   := Vector2i(256, 256)

var _state: Dictionary = {}

var _portraits: Array = []           # Array of {id, class, path, is_user}
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
			# Parse class from naming convention portrait_{class}_{nn}
			var parts := portrait_id.split("_")
			var cls_str := ""
			if parts.size() >= 2:
				# Everything between "portrait_" prefix and final number segment
				var class_parts: Array = []
				for i in range(1, parts.size() - 1):
					class_parts.append(parts[i])
				cls_str = "_".join(class_parts)
			result.append({
				"id":      portrait_id,
				"class":   cls_str,
				"path":    "%s/%s" % [USER_DIR, filename],
				"is_user": true,
			})
		filename = dir.get_next()
	dir.list_dir_end()
	return result


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
	# Sort: class-matching portraits first, then all others, alphabetically within each group
	var matching: Array = []
	var others: Array = []
	for p in _portraits:
		if p.get("class", "") == class_id:
			matching.append(p)
		else:
			others.append(p)

	var ordered: Array = []
	ordered.append_array(matching)
	ordered.append_array(others)

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
	var default_id := "portrait_%s_01" % class_id
	if _portrait_exists(default_id):
		_select_portrait(default_id)
	elif not _portraits.is_empty():
		_select_portrait(_portraits[0].get("id", ""))


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
	note.modulate = Color(0.7, 0.7, 0.7, 1.0)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_vbox.add_child(note)
