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
	_build_actions_card()


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
	_render_actions()


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
		# Migration 127 (Phase 11D.1): "Chaotic" badge → alignment column;
		# "Clanhold" badge → orthogonal domain_style column. See
		# gdd-domain-style-and-alignment.md §4-§6.
		if String(_domain_data.get("alignment", "neutral")) == "chaotic":
			territory += " · Chaotic"
		if String(_domain_data.get("domain_style", "civilized")) == "clanhold":
			territory += " · Clanhold"
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
		var improvement: int = int(hex.get("land_improvement_level", 0))
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
	# Sufficiency uses effective hex count (owned + intervening for noncontiguous
	# domains) per RAW §noncontiguous_domains; identical to owned count when
	# the domain is contiguous.
	var sufficiency_hex_count: int = StrongholdRepository.get_effective_hex_count_for_domain(_domain_id)
	# Both values are cp post-Migration 116.
	var stronghold_value_cp := StrongholdRepository.get_stronghold_value_for_domain(_domain_id)
	var minimum_cp := StrongholdRepository.classification_minimum_gp(territory, sufficiency_hex_count)
	var sufficiency_text: String
	if minimum_cp <= 0:
		sufficiency_text = "—"
	elif stronghold_value_cp >= minimum_cp:
		sufficiency_text = "Sufficient ✓"
	elif stronghold_value_cp * 2 >= minimum_cp:
		sufficiency_text = "Insufficient (≥½ minimum, −1 morale)"
	elif stronghold_value_cp * 4 >= minimum_cp:
		sufficiency_text = "Insufficient (≥¼ minimum, −2 morale)"
	else:
		sufficiency_text = "Insufficient (<¼ minimum, −3 morale + income gate)"
	info.text = "Current: %s     Stronghold value: %s / %s     Status: %s" % [
		territory.capitalize(),
		Currency.format_cost(stronghold_value_cp),
		Currency.format_cost(minimum_cp),
		sufficiency_text,
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
	# Spinboxes display gp/family; the backing columns are cp/family — convert
	# on the way in (and back out in _on_decree_issue_pressed).
	_tax_spin.value = float(int(_domain_data.get("tax_rate_cp_per_family", 200)) / 100)
	_liturgy_spin.value = float(int(_domain_data.get("liturgy_rate_cp_per_family", 100)) / 100)
	_tithe_spin.value = float(int(_domain_data.get("tithe_rate_cp_per_family", 100)) / 100)


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
		"tax_rate_cp_per_family": int(_tax_spin.value) * 100,
		"liturgy_rate_cp_per_family": int(_liturgy_spin.value) * 100,
		"tithe_rate_cp_per_family": int(_tithe_spin.value) * 100,
	}
	if CampaignRepository.update_domain_settings(_domain_id, fields):
		EventBus.domain_decree_issued.emit(_domain_id, "tax_rate", {"new": fields["tax_rate_cp_per_family"]})
		EventBus.domain_decree_issued.emit(_domain_id, "liturgy_rate", {"new": fields["liturgy_rate_cp_per_family"]})
		EventBus.domain_decree_issued.emit(_domain_id, "tithe_rate", {"new": fields["tithe_rate_cp_per_family"]})


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


# ---------------------------------------------------------------------------
# Section: Actions card (Phase 11B — voluntary abandonment)
# ---------------------------------------------------------------------------

var _actions_card: VBoxContainer = null
var _abandon_button: Button = null
var _abandon_dialog: AcceptDialog = null
var _abandon_dialog_label: RichTextLabel = null
var _abandon_confirm_edit: LineEdit = null
var _abandon_confirm_button: Button = null


func _build_actions_card() -> void:
	_actions_card = _make_card("Domain Management")
	add_child(_actions_card)
	# Row 1: voluntary abandon.
	_abandon_button = Button.new()
	_abandon_button.text = "Abandon Domain…"
	_abandon_button.pressed.connect(_on_abandon_pressed)
	_actions_card.add_child(_abandon_button)
	_build_abandon_dialog()
	# Row 2: succession actions (only visible during succession_pending).
	_succession_row = HBoxContainer.new()
	_succession_row.add_theme_constant_override("separation", 8)
	_succession_row.visible = false
	_actions_card.add_child(_succession_row)
	_designate_heir_button = Button.new()
	_designate_heir_button.text = "Designate Heir…"
	_designate_heir_button.pressed.connect(_on_designate_heir_pressed)
	_succession_row.add_child(_designate_heir_button)
	_confirm_succession_button = Button.new()
	_confirm_succession_button.text = "Confirm Succession Now"
	_confirm_succession_button.pressed.connect(_on_confirm_succession_pressed)
	_succession_row.add_child(_confirm_succession_button)
	_build_heir_dialog()


func _render_actions() -> void:
	if _abandon_button == null:
		return
	# Abandon button: hide when already terminal.
	var state: String = String(_domain_data.get(
		"lifecycle_state", LifecycleHandler.STATE_ACTIVE))
	var is_terminal: bool = state == LifecycleHandler.STATE_ABANDONED \
		or state == LifecycleHandler.STATE_SALTED_TO_RUIN
	_abandon_button.disabled = is_terminal or _domain_id.is_empty()
	_abandon_button.tooltip_text = "Already abandoned." if is_terminal else \
		"Voluntarily abandon this domain. Liquidates treasury to the ruler's coin."
	# Succession row: visible during succession_pending only.
	var is_pending: bool = state == LifecycleHandler.STATE_SUCCESSION_PENDING
	_succession_row.visible = is_pending
	if is_pending:
		var heir_id: String = String(_domain_data.get("designated_heir_character_id", ""))
		_confirm_succession_button.disabled = heir_id.is_empty()
		_confirm_succession_button.tooltip_text = (
			"Resolve succession with the designated heir."
			if not heir_id.is_empty()
			else "Designate an heir before you can confirm.")


func _build_abandon_dialog() -> void:
	_abandon_dialog = AcceptDialog.new()
	_abandon_dialog.title = "Abandon Domain"
	_abandon_dialog.min_size = Vector2(520, 280)
	_abandon_dialog.dialog_hide_on_ok = false  # we override with custom Confirm
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	_abandon_dialog.add_child(vb)
	_abandon_dialog_label = RichTextLabel.new()
	_abandon_dialog_label.bbcode_enabled = true
	_abandon_dialog_label.fit_content = true
	_abandon_dialog_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_abandon_dialog_label.custom_minimum_size = Vector2(480, 160)
	vb.add_child(_abandon_dialog_label)
	var prompt := Label.new()
	prompt.text = "Type the domain's name to confirm:"
	vb.add_child(prompt)
	_abandon_confirm_edit = LineEdit.new()
	_abandon_confirm_edit.placeholder_text = "(domain name)"
	_abandon_confirm_edit.text_changed.connect(_on_abandon_confirm_text_changed)
	vb.add_child(_abandon_confirm_edit)
	_abandon_confirm_button = _abandon_dialog.add_button("Abandon", true, "abandon_confirm")
	_abandon_confirm_button.disabled = true
	_abandon_dialog.custom_action.connect(_on_abandon_custom_action)
	add_child(_abandon_dialog)


func _on_abandon_pressed() -> void:
	if _domain_id.is_empty():
		return
	var name: String = String(_domain_data.get("name", "this domain"))
	var treasury_cp: int = int(_domain_data.get("treasury_cp", 0))
	var peasants: int = int(_domain_data.get("peasant_families", 0))
	var owner_id: String = String(_domain_data.get("owner_character_id", ""))
	var vassal_count: int = 0
	if not owner_id.is_empty():
		vassal_count = VassalRepository.list_active_for_liege(owner_id).size()
	var treasury_gp: int = treasury_cp / 100
	var remainder_cp: int = treasury_cp - (treasury_gp * 100)
	var text: String = (
		"[b]%s[/b]\n\n"
		+ "This action [b]cannot be undone[/b].\n\n"
		+ "• Treasury [b]%d gp %d cp[/b] will transfer to the ruler's coin.\n"
		+ "• [b]%d[/b] peasant families will disperse.\n"
		+ "• [b]%d[/b] vassal henchman(en) will become independent.\n"
		+ "• Stronghold (if any) reverts to ruined / available for other rulers.\n"
		+ "• Domain hexes are released back to the unowned pool.\n\n"
		+ "A Departure Log entry will record the event."
	) % [name, treasury_gp, remainder_cp, peasants, vassal_count]
	_abandon_dialog_label.text = text
	_abandon_confirm_edit.text = ""
	_abandon_confirm_button.disabled = true
	_abandon_dialog.popup_centered()


func _on_abandon_confirm_text_changed(new_text: String) -> void:
	var expected: String = String(_domain_data.get("name", "")).strip_edges()
	_abandon_confirm_button.disabled = new_text.strip_edges() != expected or expected.is_empty()


func _on_abandon_custom_action(action: String) -> void:
	if action != "abandon_confirm":
		return
	if _domain_id.is_empty():
		_abandon_dialog.hide()
		return
	var owner_id: String = String(_domain_data.get("owner_character_id", ""))
	var calendar_day: int = _abandon_calendar_day()
	LifecycleHandler.abandon_domain(
		_domain_id, calendar_day,
		LifecycleHandler.REASON_VOLUNTARY,
		owner_id)
	_abandon_dialog.hide()


static func _abandon_calendar_day() -> int:
	return Timekeeping.get_calendar_day()


# ---------------------------------------------------------------------------
# Section: Succession picker (Phase 11C)
# ---------------------------------------------------------------------------

var _succession_row: HBoxContainer = null
var _designate_heir_button: Button = null
var _confirm_succession_button: Button = null
var _heir_dialog: AcceptDialog = null
var _heir_list: VBoxContainer = null
var _heir_button_group: ButtonGroup = null
var _heir_confirm_button: Button = null
var _selected_heir_id: String = ""
var _selected_heir_kind: String = ""


func _build_heir_dialog() -> void:
	_heir_dialog = AcceptDialog.new()
	_heir_dialog.title = "Designate Heir"
	_heir_dialog.min_size = Vector2(520, 360)
	_heir_dialog.dialog_hide_on_ok = false
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	_heir_dialog.add_child(vb)
	var prompt := Label.new()
	prompt.text = "Choose an heir for this domain. Non-henchman heirs inherit at base loyalty −2."
	vb.add_child(prompt)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(480, 220)
	vb.add_child(scroll)
	_heir_list = VBoxContainer.new()
	_heir_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_heir_list)
	_heir_button_group = ButtonGroup.new()
	_heir_confirm_button = _heir_dialog.add_button("Designate", true, "heir_designate")
	_heir_confirm_button.disabled = true
	_heir_dialog.custom_action.connect(_on_heir_dialog_action)
	add_child(_heir_dialog)


func _on_designate_heir_pressed() -> void:
	if _domain_id.is_empty():
		return
	# Populate the candidate list freshly.
	for child in _heir_list.get_children():
		_heir_list.remove_child(child)
		child.queue_free()
	_selected_heir_id = ""
	_selected_heir_kind = ""
	_heir_confirm_button.disabled = true
	var candidates: Array = RulerDeathHandler.eligible_heirs_for(_domain_id)
	if candidates.is_empty():
		var none_label := Label.new()
		none_label.text = "(no eligible heirs found in this campaign)"
		none_label.modulate = Color(0.7, 0.7, 0.7)
		_heir_list.add_child(none_label)
	for c: Dictionary in candidates:
		_heir_list.add_child(_build_heir_row(c))
	_heir_dialog.popup_centered()


func _build_heir_row(candidate: Dictionary) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var radio := CheckBox.new()
	radio.button_group = _heir_button_group
	var heir_id: String = String(candidate.get("character_id", ""))
	var heir_kind: String = String(candidate.get("kind", ""))
	radio.pressed.connect(_on_heir_selected.bind(heir_id, heir_kind))
	hb.add_child(radio)
	var kind_chip := Label.new()
	kind_chip.text = "[%s]" % heir_kind
	kind_chip.modulate = (
		Color(0.7, 0.85, 1.0) if heir_kind == "pc"
		else Color(0.85, 0.85, 0.7) if heir_kind == "henchman"
		else Color(0.95, 0.75, 0.55))
	kind_chip.custom_minimum_size = Vector2(110, 0)
	hb.add_child(kind_chip)
	var name_label := Label.new()
	name_label.text = String(candidate.get("name", ""))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(name_label)
	var detail_label := Label.new()
	detail_label.text = "%s L%d" % [
		String(candidate.get("character_class", "")),
		int(candidate.get("level", 0)),
	]
	detail_label.modulate = Color(0.7, 0.7, 0.7)
	hb.add_child(detail_label)
	return hb


func _on_heir_selected(heir_id: String, heir_kind: String) -> void:
	_selected_heir_id = heir_id
	_selected_heir_kind = heir_kind
	_heir_confirm_button.disabled = false


func _on_heir_dialog_action(action: String) -> void:
	if action != "heir_designate":
		return
	if _domain_id.is_empty() or _selected_heir_id.is_empty():
		_heir_dialog.hide()
		return
	RulerDeathHandler.designate_heir(_domain_id, _selected_heir_id, _selected_heir_kind)
	_heir_dialog.hide()


func _on_confirm_succession_pressed() -> void:
	if _domain_id.is_empty():
		return
	var calendar_day: int = _abandon_calendar_day()
	RulerDeathHandler.resolve_succession(_domain_id, calendar_day)
