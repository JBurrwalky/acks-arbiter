extends AcceptDialog

## EstablishDomainDialog — modal that branches per classification × class ×
## chaotic-toggle for Phase 2 domain establishment per gdd-domain-tab.md
## §16.1 and `docs/domain-roadmap-corrected.md` Phase 2.
##
## Surfaces the available paths for the active character and the selected
## classification, calls EstablishDomainFlow.establish_domain on confirm,
## and emits `domain_established_requested(domain_id)` so the parent tab can
## refresh.


signal domain_established_requested(domain_id: String)


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _character: Dictionary = {}
var _campaign_id: String = ""

var _name_edit: LineEdit = null
var _classification_option: OptionButton = null
var _method_option: OptionButton = null
var _chaotic_toggle: CheckBox = null
var _religion_edit: LineEdit = null
var _own_race_toggle: CheckBox = null
var _error_label: Label = null

const CLASSIFICATIONS := ["civilized", "borderlands", "wilderness"]


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	title = "Establish a Domain"
	dialog_hide_on_ok = false
	confirmed.connect(_on_confirmed)
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)
	# Name.
	var name_row := HBoxContainer.new()
	vbox.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = "Domain name:"
	name_lbl.custom_minimum_size = Vector2(160, 0)
	name_row.add_child(name_lbl)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.placeholder_text = "Untitled Domain"
	name_row.add_child(_name_edit)
	# Classification.
	var class_row := HBoxContainer.new()
	vbox.add_child(class_row)
	var class_lbl := Label.new()
	class_lbl.text = "Classification:"
	class_lbl.custom_minimum_size = Vector2(160, 0)
	class_row.add_child(class_lbl)
	_classification_option = OptionButton.new()
	for c in CLASSIFICATIONS:
		_classification_option.add_item(c.capitalize())
	_classification_option.item_selected.connect(_on_classification_changed)
	class_row.add_child(_classification_option)
	# Method.
	var method_row := HBoxContainer.new()
	vbox.add_child(method_row)
	var method_lbl := Label.new()
	method_lbl.text = "Acquisition method:"
	method_lbl.custom_minimum_size = Vector2(160, 0)
	method_row.add_child(method_lbl)
	_method_option = OptionButton.new()
	method_row.add_child(_method_option)
	# Chaotic opt-in.
	_chaotic_toggle = CheckBox.new()
	_chaotic_toggle.text = "Establish as chaotic domain (chaotic-aligned PCs only)"
	vbox.add_child(_chaotic_toggle)
	# Own-race flag.
	_own_race_toggle = CheckBox.new()
	_own_race_toggle.text = "Hex is in own-race area (dwarven / elven only — controls civilized/borderlands access)"
	_own_race_toggle.button_pressed = true
	_own_race_toggle.toggled.connect(_on_own_race_toggled)
	vbox.add_child(_own_race_toggle)
	# Religion.
	var rel_row := HBoxContainer.new()
	vbox.add_child(rel_row)
	var rel_lbl := Label.new()
	rel_lbl.text = "Dominant religion:"
	rel_lbl.custom_minimum_size = Vector2(160, 0)
	rel_row.add_child(rel_lbl)
	_religion_edit = LineEdit.new()
	_religion_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_religion_edit.placeholder_text = "(optional)"
	rel_row.add_child(_religion_edit)
	# Error display.
	_error_label = Label.new()
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_error_label)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Configure the dialog before popup. [param character] should be a
## CharacterData-shape dict with `character_class` and `alignment` set.
func setup(campaign_id: String, character: Dictionary) -> void:
	_campaign_id = campaign_id
	_character = character
	_name_edit.text = ""
	_classification_option.selected = 0
	_chaotic_toggle.button_pressed = false
	_chaotic_toggle.disabled = String(character.get("alignment", "")) != "chaotic"
	_own_race_toggle.button_pressed = true
	_religion_edit.text = ""
	_error_label.text = ""
	_refresh_methods()


# ---------------------------------------------------------------------------
# Internal — method dropdown population
# ---------------------------------------------------------------------------

func _refresh_methods() -> void:
	_method_option.clear()
	var classification: String = CLASSIFICATIONS[_classification_option.selected]
	var paths := EstablishDomainFlow.available_paths(
		_character, classification, _own_race_toggle.button_pressed)
	for p in paths:
		var label := String(p["label"])
		if not bool(p["available"]):
			label += "  (unavailable: %s)" % String(p["reason"])
		_method_option.add_item(label)
		var idx := _method_option.item_count - 1
		_method_option.set_item_metadata(idx, String(p["id"]))
		_method_option.set_item_disabled(idx, not bool(p["available"]))
	# Default to the first available item.
	for i in range(_method_option.item_count):
		if not _method_option.is_item_disabled(i):
			_method_option.selected = i
			break


func _on_classification_changed(_idx: int) -> void:
	_refresh_methods()


func _on_own_race_toggled(_pressed: bool) -> void:
	_refresh_methods()


# ---------------------------------------------------------------------------
# Confirm handler
# ---------------------------------------------------------------------------

func _on_confirmed() -> void:
	_error_label.text = ""
	var classification: String = CLASSIFICATIONS[_classification_option.selected]
	var method_idx := _method_option.selected
	if method_idx < 0:
		_error_label.text = "Select a method."
		return
	var method_id: String = String(_method_option.get_item_metadata(method_idx))
	var name := _name_edit.text.strip_edges()
	if name.is_empty():
		_error_label.text = "Enter a domain name."
		return
	var owner_id := String(_character.get("id", ""))
	var calendar_day := _current_calendar_day()
	var params := {
		"campaign_id": _campaign_id,
		"owner_character_id": owner_id,
		"character": _character,
		"name": name,
		"territory_type": classification,
		"establishment_method": method_id,
		"is_chaotic_domain": _chaotic_toggle.button_pressed,
		"in_own_race_area": _own_race_toggle.button_pressed,
		"religion": _religion_edit.text.strip_edges(),
		"calendar_day": calendar_day,
	}
	var result := EstablishDomainFlow.establish_domain(params)
	if not result["errors"].is_empty():
		_error_label.text = "Could not establish domain: %s" % str(result["errors"])
		return
	domain_established_requested.emit(String(result["domain_id"]))
	hide()


func _current_calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
