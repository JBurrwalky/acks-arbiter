class_name TokenPickerPanel
extends VBoxContainer

## Step 9 — Combat Token Selection.
##
## Presents the placeholder 3D character models (GLB) for the chosen class
## and sex. Left pane: male/female toggle + variant list. Right pane: a
## SubViewport that renders ONLY the currently-selected model. Selecting a
## variant frees the prior preview CharacterToken3D and instantiates a new
## one — never loads all variants at once.
##
## Persists to creation_state:
##   token_variant: String     (selected variant key, e.g. "def", "alt1")
##   sex:           String     ("male" | "female" — also honored by Finalize)
##
## When the class has no models at all (e.g., witch), the panel shows a
## placeholder notice and is_complete() returns true so the player can skip.


const CharacterModelRegistryScript := preload("res://scenes/ui/components/character_model_registry.gd")
const CharacterTokenSceneRef := preload("res://scenes/ui/components/character_token_3d.tscn")

const PREVIEW_SIZE := Vector2i(320, 420)


var _state: Dictionary = {}
var _class_registry: ClassRegistry = null

var _sex_male_btn: Button = null
var _sex_female_btn: Button = null
var _variant_list: VBoxContainer = null
var _variant_buttons: Dictionary = {}   # variant key -> Button
var _empty_notice: Label = null

var _preview_viewport: SubViewport = null
var _preview_token: Node3D = null
var _preview_name_label: Label = null

var _selected_variant: String = ""


func setup(state: Dictionary, class_registry: ClassRegistry) -> void:
	_state = state
	_class_registry = class_registry
	if get_child_count() == 0:
		_build_ui()
	_apply_sex_restrictions()
	_populate_variant_list()


## The panel is always considered complete — either a variant has been
## chosen, or the class has no models and the player is skipping past.
func is_complete() -> bool:
	return true


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = "Choose your combat token."
	add_child(header)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	add_child(hbox)

	# --- Left: controls ---
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.45
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiSurfaceStyles.apply_textured_panel(left_panel)
	hbox.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 10)
	left_panel.add_child(left_vbox)

	var sex_header := Label.new()
	sex_header.text = "Body"
	sex_header.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(sex_header)

	var sex_row := HBoxContainer.new()
	sex_row.add_theme_constant_override("separation", 6)
	left_vbox.add_child(sex_row)

	_sex_male_btn = Button.new()
	_sex_male_btn.text = "Male"
	_sex_male_btn.toggle_mode = true
	_sex_male_btn.pressed.connect(_on_sex_selected.bind("male"))
	sex_row.add_child(_sex_male_btn)

	_sex_female_btn = Button.new()
	_sex_female_btn.text = "Female"
	_sex_female_btn.toggle_mode = true
	_sex_female_btn.pressed.connect(_on_sex_selected.bind("female"))
	sex_row.add_child(_sex_female_btn)

	left_vbox.add_child(HSeparator.new())

	var variant_header := Label.new()
	variant_header.text = "Variant"
	variant_header.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(variant_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(scroll)

	_variant_list = VBoxContainer.new()
	_variant_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_variant_list)

	_empty_notice = Label.new()
	_empty_notice.text = "No placeholder tokens for this class yet.\nA blue cylinder will be used in combat."
	_empty_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_notice.visible = false
	left_vbox.add_child(_empty_notice)

	# --- Right: 3D preview ---
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.55
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiSurfaceStyles.apply_textured_panel(right_panel)
	hbox.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 6)
	right_panel.add_child(right_vbox)

	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(PREVIEW_SIZE)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.stretch = true
	right_vbox.add_child(container)

	_preview_viewport = SubViewport.new()
	_preview_viewport.size = PREVIEW_SIZE
	_preview_viewport.transparent_bg = true
	_preview_viewport.own_world_3d = true
	container.add_child(_preview_viewport)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.0, 3.2)
	camera.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	camera.fov = 45.0
	_preview_viewport.add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	light.light_energy = 1.1
	_preview_viewport.add_child(light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill_light.light_energy = 0.5
	_preview_viewport.add_child(fill_light)

	_preview_name_label = Label.new()
	_preview_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_name_label.text = ""
	right_vbox.add_child(_preview_name_label)


# ---------------------------------------------------------------------------
# Sex toggle
# ---------------------------------------------------------------------------

func _apply_sex_restrictions() -> void:
	var class_id: String = _state.get("class_id", "")
	var restriction := ""
	if _class_registry != null and not class_id.is_empty():
		restriction = _class_registry.get_sex_restriction(class_id)

	var allowed_male := restriction != "female"
	var allowed_female := restriction != "male"
	_sex_male_btn.disabled = not allowed_male
	_sex_female_btn.disabled = not allowed_female

	var current_sex: String = _state.get("sex", "male")
	if current_sex == "male" and not allowed_male:
		current_sex = "female"
	elif current_sex == "female" and not allowed_female:
		current_sex = "male"
	_state["sex"] = current_sex

	# Prefer a sex for which a model actually exists, when free choice is
	# allowed but the default doesn't have one.
	var available_sexes: Array[String] = CharacterModelRegistryScript.get_available_sexes(class_id)
	if allowed_male and allowed_female and not current_sex in available_sexes and not available_sexes.is_empty():
		_state["sex"] = available_sexes[0]

	_sex_male_btn.button_pressed = (_state["sex"] == "male")
	_sex_female_btn.button_pressed = (_state["sex"] == "female")


func _on_sex_selected(sex: String) -> void:
	if _state.get("sex", "male") == sex:
		# Keep the toggle latched visually.
		_sex_male_btn.button_pressed = (sex == "male")
		_sex_female_btn.button_pressed = (sex == "female")
		return
	_state["sex"] = sex
	_sex_male_btn.button_pressed = (sex == "male")
	_sex_female_btn.button_pressed = (sex == "female")
	_populate_variant_list()


# ---------------------------------------------------------------------------
# Variant list + preview
# ---------------------------------------------------------------------------

func _populate_variant_list() -> void:
	for child in _variant_list.get_children():
		child.queue_free()
	_variant_buttons.clear()

	var class_id: String = _state.get("class_id", "")
	var sex: String = _state.get("sex", "male")
	var variants: Array[String] = CharacterModelRegistryScript.get_available_variants(class_id, sex)

	if variants.is_empty():
		_empty_notice.visible = true
		_selected_variant = ""
		_state["token_variant"] = ""
		_clear_preview()
		return

	_empty_notice.visible = false

	for v in variants:
		var btn := Button.new()
		btn.text = _label_for(v)
		btn.toggle_mode = true
		btn.pressed.connect(_on_variant_selected.bind(v))
		_variant_list.add_child(btn)
		_variant_buttons[v] = btn

	# Preserve prior selection if still available for this (class, sex).
	var prior: String = _state.get("token_variant", "")
	var initial: String = prior if prior in variants else \
		CharacterModelRegistryScript.get_default_variant(class_id, sex)
	if initial.is_empty():
		initial = variants[0]
	_select_variant(initial)


func _label_for(variant: String) -> String:
	if variant == "def":
		return "Default"
	return variant.capitalize().replace("Alt", "Alt ")


func _on_variant_selected(variant: String) -> void:
	_select_variant(variant)


func _select_variant(variant: String) -> void:
	_selected_variant = variant
	_state["token_variant"] = variant

	for v in _variant_buttons:
		var btn: Button = _variant_buttons[v]
		btn.button_pressed = (v == variant)
		btn.modulate = Color(0.6, 1.0, 0.6, 1.0) if v == variant else Color.WHITE

	_rebuild_preview()
	_preview_name_label.text = _label_for(variant)


func _rebuild_preview() -> void:
	_clear_preview()
	var class_id: String = _state.get("class_id", "")
	var sex: String = _state.get("sex", "male")
	if _selected_variant.is_empty() or not CharacterModelRegistryScript.has_model(
			class_id, _selected_variant, sex):
		return
	_preview_token = CharacterTokenSceneRef.instantiate()
	_preview_viewport.add_child(_preview_token)
	_preview_token.setup(
		"preview",
		"",
		0,
		class_id.substr(0, 1).to_upper(),
		class_id,
		_selected_variant,
		sex,
	)
	# Rotate slightly so the model is seen at a three-quarter angle.
	_preview_token.set_facing(Vector2i(1, 0))


func _clear_preview() -> void:
	if _preview_token != null and is_instance_valid(_preview_token):
		_preview_token.queue_free()
	_preview_token = null
