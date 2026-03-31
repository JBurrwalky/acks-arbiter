class_name FinalizePanel
extends VBoxContainer

## Step 9 — Finalize Character.
##
## Player enters name (required), alignment, and optional description.
## Full character sheet summary is displayed below for review.
##
## Alignment dropdown filtered by class alignment_restriction if present.


const ALIGNMENT_OPTIONS: Array[String] = ["lawful", "neutral", "chaotic"]

var _state: Dictionary = {}
var _class_registry: ClassRegistry

var _name_edit: LineEdit
var _sex_male_btn: Button
var _sex_female_btn: Button
var _alignment_option: OptionButton
var _description_edit: TextEdit
var _sheet_panel: CharacterSheetPanel


func setup(state: Dictionary, class_registry: ClassRegistry) -> void:
	_state = state
	_class_registry = class_registry
	if get_child_count() == 0:
		_build_ui()
	_restore_from_state()
	_refresh_sheet()


func is_complete() -> bool:
	return not (_state.get("name", "") as String).strip_edges().is_empty()


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

func _restore_from_state() -> void:
	if _name_edit == null:
		return
	_name_edit.text = _state.get("name", "")
	var sex: String = _state.get("sex", "male")
	_sex_male_btn.button_pressed = (sex == "male")
	_sex_female_btn.button_pressed = (sex == "female")
	_populate_alignment_options()
	var alignment: String = _state.get("alignment", "neutral")
	for i in range(_alignment_option.item_count):
		if _alignment_option.get_item_metadata(i) == alignment:
			_alignment_option.select(i)
			break
	_description_edit.text = _state.get("description", "")


func _populate_alignment_options() -> void:
	_alignment_option.clear()
	var class_id: String = _state.get("class_id", "")
	var cls := _class_registry.get_class_def(class_id)
	var restriction: String = (cls.get("alignment_restriction", "") as String).to_lower()

	for align in ALIGNMENT_OPTIONS:
		# Filter based on restriction
		if not restriction.is_empty() and restriction != "any":
			if restriction == "lawful" and align != "lawful":
				continue
			if restriction == "chaotic" and align != "chaotic":
				continue
			if restriction == "non-chaotic" and align == "chaotic":
				continue
			if restriction == "non-lawful" and align == "lawful":
				continue
		_alignment_option.add_item(align.capitalize())
		_alignment_option.set_item_metadata(_alignment_option.item_count - 1, align)

	# Default select neutral if present, else first
	var default_align: String = _state.get("alignment", "neutral")
	for i in range(_alignment_option.item_count):
		if _alignment_option.get_item_metadata(i) == default_align:
			_alignment_option.select(i)
			return
	if _alignment_option.item_count > 0:
		_alignment_option.select(0)
		_state["alignment"] = _alignment_option.get_item_metadata(0)


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 8)

	# --- Name field ---
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = "Name:*"
	name_lbl.custom_minimum_size = Vector2(100, 0)
	name_row.add_child(name_lbl)

	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.placeholder_text = "Character name (required)"
	_name_edit.max_length = 64
	_name_edit.text_changed.connect(_on_name_changed)
	name_row.add_child(_name_edit)

	# --- Sex selector ---
	var sex_row := HBoxContainer.new()
	sex_row.add_theme_constant_override("separation", 8)
	add_child(sex_row)

	var sex_lbl := Label.new()
	sex_lbl.text = "Sex:"
	sex_lbl.custom_minimum_size = Vector2(100, 0)
	sex_row.add_child(sex_lbl)

	_sex_male_btn = Button.new()
	_sex_male_btn.text = "Male"
	_sex_male_btn.toggle_mode = true
	_sex_male_btn.button_pressed = true
	_sex_male_btn.pressed.connect(_on_sex_pressed.bind("male"))
	sex_row.add_child(_sex_male_btn)

	_sex_female_btn = Button.new()
	_sex_female_btn.text = "Female"
	_sex_female_btn.toggle_mode = true
	_sex_female_btn.button_pressed = false
	_sex_female_btn.pressed.connect(_on_sex_pressed.bind("female"))
	sex_row.add_child(_sex_female_btn)

	# --- Alignment dropdown ---
	var align_row := HBoxContainer.new()
	align_row.add_theme_constant_override("separation", 8)
	add_child(align_row)

	var align_lbl := Label.new()
	align_lbl.text = "Alignment:"
	align_lbl.custom_minimum_size = Vector2(100, 0)
	align_row.add_child(align_lbl)

	_alignment_option = OptionButton.new()
	_alignment_option.custom_minimum_size = Vector2(120, 0)
	_alignment_option.item_selected.connect(_on_alignment_changed)
	align_row.add_child(_alignment_option)

	# --- Description (optional) ---
	var desc_lbl := Label.new()
	desc_lbl.text = "Notes / Description (optional):"
	add_child(desc_lbl)

	_description_edit = TextEdit.new()
	_description_edit.custom_minimum_size = Vector2(0, 80)
	_description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_description_edit.placeholder_text = "Optional character notes…"
	_description_edit.text_changed.connect(_on_description_changed)
	add_child(_description_edit)

	add_child(HSeparator.new())

	# --- Character sheet summary ---
	# Placed as a direct child of this VBoxContainer (not inside a ScrollContainer)
	# so SIZE_EXPAND_FILL works and the sheet reaches the bottom of the window.
	var summary_lbl := Label.new()
	summary_lbl.text = "Character Summary:"
	summary_lbl.add_theme_font_size_override("font_size", 14)
	add_child(summary_lbl)

	_sheet_panel = CharacterSheetPanel.new()
	_sheet_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_sheet_panel)


func _refresh_sheet() -> void:
	if _sheet_panel == null:
		return
	_sheet_panel.setup_registry(_class_registry)
	# Push name and alignment into the character object for preview
	var character: CharacterData = _state.get("character")
	if character != null:
		character.name = (_state.get("name", "") as String).strip_edges()
		character.alignment = _state.get("alignment", "neutral")
		character.portrait_id = _state.get("portrait_id", "")
	_sheet_panel.display(_state)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_name_changed(new_text: String) -> void:
	_state["name"] = new_text
	# Update character object for live sheet preview
	var character: CharacterData = _state.get("character")
	if character != null:
		character.name = new_text.strip_edges()
	_refresh_sheet()


func _on_alignment_changed(index: int) -> void:
	var align: String = _alignment_option.get_item_metadata(index) as String
	_state["alignment"] = align
	var character: CharacterData = _state.get("character")
	if character != null:
		character.alignment = align
	_refresh_sheet()


func _on_sex_pressed(sex: String) -> void:
	_state["sex"] = sex
	# Keep buttons mutually exclusive without ButtonGroup (toggle_mode handles visual)
	_sex_male_btn.button_pressed = (sex == "male")
	_sex_female_btn.button_pressed = (sex == "female")
	_refresh_sheet()


func _on_description_changed() -> void:
	_state["description"] = _description_edit.text
