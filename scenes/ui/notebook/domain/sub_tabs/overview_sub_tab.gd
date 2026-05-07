extends VBoxContainer

## Overview sub-tab — default landing page on session-first activation. Per
## `gdd-domain-tab.md` §6 the overview consolidates identity, demographics,
## growth, land value, classification, alignment/religion, and recent events
## into one scannable view.
##
## Phase 2 implementation: the four headline sections are rendered (identity
## card, demographics summary, classification status, and editable rate
## steppers). The growth-roll history detail section and the per-event-row
## "open in Encounters/Treasury" cross-activation links land in Phase 3+.


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _domain_id: String = ""
var _domain_data: Dictionary = {}

var _identity_card: VBoxContainer = null
var _demographics_card: VBoxContainer = null
var _land_value_card: VBoxContainer = null
var _classification_card: VBoxContainer = null
var _alignment_card: VBoxContainer = null
var _decree_card: VBoxContainer = null

# Form controls cached so display() can update them in place.
var _name_edit: LineEdit = null
var _tax_spin: SpinBox = null
var _liturgy_spin: SpinBox = null
var _tithe_spin: SpinBox = null
var _religion_edit: LineEdit = null
var _alignment_option: OptionButton = null

const ALIGNMENTS := ["lawful", "neutral", "chaotic"]


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	_build_identity_card()
	_build_demographics_card()
	_build_land_value_card()
	_build_classification_card()
	_build_alignment_card()
	_build_decree_card()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Render Overview content for [param domain_data] (a domain row dict).
func display(domain_data: Dictionary) -> void:
	_domain_data = domain_data
	_domain_id = String(domain_data.get("id", ""))
	_render_identity()
	_render_demographics()
	_render_land_value()
	_render_classification()
	_render_alignment()
	_render_decree()


# ---------------------------------------------------------------------------
# Section: identity card
# ---------------------------------------------------------------------------

func _build_identity_card() -> void:
	_identity_card = _make_card("Identity")
	add_child(_identity_card)
	# Name row.
	var name_row := HBoxContainer.new()
	_identity_card.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Name:"
	name_label.custom_minimum_size = Vector2(120, 0)
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.placeholder_text = "Untitled Domain"
	name_row.add_child(_name_edit)
	var rename_btn := Button.new()
	rename_btn.text = "Rename"
	rename_btn.pressed.connect(_on_rename_pressed)
	name_row.add_child(rename_btn)
	# Established / classification row.
	_identity_card.add_child(Label.new())  # spacer for dynamic content


func _render_identity() -> void:
	if _domain_data.is_empty():
		_name_edit.text = ""
		return
	_name_edit.text = String(_domain_data.get("name", ""))
	# Strip the spacer label and rebuild.
	var children := _identity_card.get_children()
	# Index 0 = "Identity" header, 1 = name HBox, 2 = spacer Label.
	if children.size() >= 3 and children[2] is Label:
		var info: Label = children[2]
		var territory: String = String(_domain_data.get("territory_type", "")).capitalize()
		if int(_domain_data.get("is_chaotic_domain", 0)) == 1:
			territory += " · Chaotic"
		info.text = "Classification: %s     Established day %d via %s" % [
			territory,
			int(_domain_data.get("established_calendar_day", 0)),
			_humanize_method(String(_domain_data.get("establishment_method", ""))),
		]


# ---------------------------------------------------------------------------
# Section: demographics summary
# ---------------------------------------------------------------------------

func _build_demographics_card() -> void:
	_demographics_card = _make_card("Demographics")
	add_child(_demographics_card)
	_demographics_card.add_child(Label.new())


func _render_demographics() -> void:
	var children := _demographics_card.get_children()
	if children.size() < 2 or not (children[1] is Label):
		return
	var info: Label = children[1]
	if _domain_data.is_empty():
		info.text = "—"
		return
	var peasants: int = int(_domain_data.get("peasant_families", 0))
	var urban: int = int(_domain_data.get("urban_families", 0))
	var morale: int = int(_domain_data.get("morale", 0))
	var morale_tier: String = DomainMoraleResolver.morale_tier(morale)
	var hex_count: int = CampaignRepository.get_domain_hexes(_domain_id).size()
	info.text = "Peasant families: %d (%d hex%s)\nUrban families: %d\nMorale: %s (%+d)" % [
		peasants, hex_count, "" if hex_count == 1 else "es",
		urban, morale_tier, morale,
	]


# ---------------------------------------------------------------------------
# Section: land value
# ---------------------------------------------------------------------------

func _build_land_value_card() -> void:
	_land_value_card = _make_card("Land Value")
	add_child(_land_value_card)


func _render_land_value() -> void:
	# Clear and rebuild.
	for child in _land_value_card.get_children():
		if child.get_index() == 0:
			continue  # keep the header
		_land_value_card.remove_child(child)
		child.queue_free()
	if _domain_data.is_empty():
		var none := Label.new()
		none.text = "—"
		_land_value_card.add_child(none)
		return
	var hexes := CampaignRepository.get_domain_hexes(_domain_id)
	if hexes.is_empty():
		var none := Label.new()
		none.text = "No hexes assigned to this domain. Surveying activities (Phase 3) will reveal land values."
		_land_value_card.add_child(none)
		return
	for hex in hexes:
		var lbl := Label.new()
		var land_value: int = int(hex.get("land_value", 5))
		var improvement: int = int(hex.get("land_improvement_gp", 0))
		var improved_text := ""
		if improvement > 0:
			improved_text = " (+%d improvement, base %d)" % [improvement, land_value - improvement]
		lbl.text = "Hex (%d, %d): %d gp/family%s" % [
			int(hex.get("hex_q", 0)), int(hex.get("hex_r", 0)),
			land_value, improved_text,
		]
		_land_value_card.add_child(lbl)


# ---------------------------------------------------------------------------
# Section: classification
# ---------------------------------------------------------------------------

func _build_classification_card() -> void:
	_classification_card = _make_card("Classification")
	add_child(_classification_card)
	_classification_card.add_child(Label.new())


func _render_classification() -> void:
	var children := _classification_card.get_children()
	if children.size() < 2 or not (children[1] is Label):
		return
	var info: Label = children[1]
	if _domain_data.is_empty():
		info.text = "—"
		return
	var territory := String(_domain_data.get("territory_type", "wilderness"))
	var hex_count: int = CampaignRepository.get_domain_hexes(_domain_id).size()
	var stronghold_value := StrongholdRepository.get_stronghold_value_for_domain(_domain_id)
	var minimum := StrongholdRepository.classification_minimum_gp(territory, hex_count)
	var sufficiency_text: String
	if minimum <= 0:
		sufficiency_text = "—"
	elif stronghold_value >= minimum:
		sufficiency_text = "Sufficient ✓"
	elif stronghold_value * 2 >= minimum:
		sufficiency_text = "Insufficient (≥½ minimum, −1 morale)"
	elif stronghold_value * 4 >= minimum:
		sufficiency_text = "Insufficient (≥¼ minimum, −2 morale)"
	else:
		sufficiency_text = "Insufficient (<¼ minimum, −3 morale + income gate)"
	info.text = "Current: %s     Stronghold value: %d / %d gp     Status: %s" % [
		territory.capitalize(), stronghold_value, minimum, sufficiency_text,
	]


# ---------------------------------------------------------------------------
# Section: alignment & religion
# ---------------------------------------------------------------------------

func _build_alignment_card() -> void:
	_alignment_card = _make_card("Alignment & Religion")
	add_child(_alignment_card)
	# Religion row.
	var rel_row := HBoxContainer.new()
	_alignment_card.add_child(rel_row)
	var rel_label := Label.new()
	rel_label.text = "Religion:"
	rel_label.custom_minimum_size = Vector2(120, 0)
	rel_row.add_child(rel_label)
	_religion_edit = LineEdit.new()
	_religion_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_religion_edit.placeholder_text = "(none)"
	rel_row.add_child(_religion_edit)
	# Alignment row.
	var align_row := HBoxContainer.new()
	_alignment_card.add_child(align_row)
	var align_label := Label.new()
	align_label.text = "Alignment:"
	align_label.custom_minimum_size = Vector2(120, 0)
	align_row.add_child(align_label)
	_alignment_option = OptionButton.new()
	for a in ALIGNMENTS:
		_alignment_option.add_item(a.capitalize())
	align_row.add_child(_alignment_option)
	# Apply button.
	var apply_btn := Button.new()
	apply_btn.text = "Save"
	apply_btn.pressed.connect(_on_alignment_save_pressed)
	_alignment_card.add_child(apply_btn)


func _render_alignment() -> void:
	if _domain_data.is_empty():
		_religion_edit.text = ""
		_alignment_option.selected = 1
		return
	_religion_edit.text = String(_domain_data.get("religion", ""))
	var alignment := String(_domain_data.get("alignment", "neutral"))
	var idx := ALIGNMENTS.find(alignment)
	if idx >= 0:
		_alignment_option.selected = idx


# ---------------------------------------------------------------------------
# Section: decree (tax / liturgy / tithe rate steppers)
# ---------------------------------------------------------------------------

func _build_decree_card() -> void:
	_decree_card = _make_card("Decree (Tax · Liturgy · Tithe)")
	add_child(_decree_card)
	_tax_spin = _make_rate_row(_decree_card, "Tax (gp/family)", 0, 10, 2)
	_liturgy_spin = _make_rate_row(_decree_card, "Liturgy (gp/family)", 0, 10, 1)
	_tithe_spin = _make_rate_row(_decree_card, "Tithe (gp/family)", 0, 10, 1)
	var apply_btn := Button.new()
	apply_btn.text = "Issue Decree"
	apply_btn.pressed.connect(_on_decree_issue_pressed)
	_decree_card.add_child(apply_btn)
	var hint := Label.new()
	hint.text = "Each adjustment is logged immediately and dispatched as an issue_decree activity (Singular Minor) per gdd-realtime-scheduler.md §4.8."
	hint.modulate = Color(0.7, 0.7, 0.7)
	_decree_card.add_child(hint)


func _render_decree() -> void:
	if _domain_data.is_empty():
		_tax_spin.value = 2
		_liturgy_spin.value = 1
		_tithe_spin.value = 1
		return
	_tax_spin.value = float(int(_domain_data.get("tax_rate_gp_per_family", 2)))
	_liturgy_spin.value = float(int(_domain_data.get("liturgy_rate_gp_per_family", 1)))
	_tithe_spin.value = float(int(_domain_data.get("tithe_rate_gp_per_family", 1)))


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_rename_pressed() -> void:
	if _domain_id.is_empty():
		return
	var new_name := _name_edit.text.strip_edges()
	if new_name.is_empty():
		return
	if CampaignRepository.update_domain_settings(_domain_id, {"name": new_name}):
		EventBus.domain_decree_issued.emit(_domain_id, "rename", {"new": new_name})


func _on_alignment_save_pressed() -> void:
	if _domain_id.is_empty():
		return
	var new_religion := _religion_edit.text.strip_edges()
	var idx := _alignment_option.selected
	var new_alignment: String = ALIGNMENTS[idx] if idx >= 0 and idx < ALIGNMENTS.size() else "neutral"
	if CampaignRepository.update_domain_settings(_domain_id, {
		"religion": new_religion,
		"alignment": new_alignment,
	}):
		EventBus.domain_decree_issued.emit(_domain_id, "religion", {"new": new_religion})
		EventBus.domain_decree_issued.emit(_domain_id, "alignment", {"new": new_alignment})


func _on_decree_issue_pressed() -> void:
	if _domain_id.is_empty():
		return
	var fields := {
		"tax_rate_gp_per_family": int(_tax_spin.value),
		"liturgy_rate_gp_per_family": int(_liturgy_spin.value),
		"tithe_rate_gp_per_family": int(_tithe_spin.value),
	}
	if CampaignRepository.update_domain_settings(_domain_id, fields):
		EventBus.domain_decree_issued.emit(_domain_id, "tax_rate", {"new": fields["tax_rate_gp_per_family"]})
		EventBus.domain_decree_issued.emit(_domain_id, "liturgy_rate", {"new": fields["liturgy_rate_gp_per_family"]})
		EventBus.domain_decree_issued.emit(_domain_id, "tithe_rate", {"new": fields["tithe_rate_gp_per_family"]})


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_card(title: String) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 16)
	card.add_child(heading)
	return card


func _make_rate_row(parent: Container, label_text: String, mn: int, mx: int, default_val: int) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(180, 0)
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = mn
	spin.max_value = mx
	spin.step = 1
	spin.value = default_val
	row.add_child(spin)
	return spin


static func _humanize_method(method: String) -> String:
	match method:
		"grant":             return "Land grant"
		"purchase":          return "Purchase"
		"conquest":          return "Conquest"
		"clear":             return "Cleared territory"
		"clanhold_annex":    return "Clanhold annexation"
		"recruit_chieftain": return "Recruited chieftain"
		"":                  return "(unknown)"
		_:                   return method.capitalize()
