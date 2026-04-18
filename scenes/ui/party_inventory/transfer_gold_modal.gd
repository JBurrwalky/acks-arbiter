# TransferGoldModal — moves coins between PCs via PartyWallet.
#
# Dependencies:
#   - PartyWallet (autoload): get_contributors, pay_from_character, deposit_to_character
#   - CampaignRepository (autoload): get_character for names, list_party_characters for henchmen
#   - GameState (autoload): party_id, active_character_id
#   - EventBus (autoload): notification_requested for errors
#
# No class_name — lazily instantiated by PartyInventoryOverlay.

extends PanelContainer

signal gold_transferred(source_id: String, target_id: String, amount_gp: float)

const Currency := preload("res://engine/subsystems/commerce/currency.gd")

var _source_dropdown: OptionButton
var _target_dropdown: OptionButton
var _amount_field: LineEdit
var _preview_label: Label
var _confirm_btn: Button
var _source_ids: Array = []
var _target_ids: Array = []
var _is_built: bool = false


func _ready() -> void:
	visible = false
	_build_ui()


func open_for_character(character_id: String) -> void:
	if not _is_built:
		_build_ui()

	_populate_dropdowns()

	# Pre-select the clicked character as source
	for i in range(_source_ids.size()):
		if _source_ids[i] == character_id:
			_source_dropdown.selected = i
			break

	_amount_field.text = ""
	_update_preview()
	visible = true


func _build_ui() -> void:
	_is_built = true

	anchor_left = 0.3
	anchor_right = 0.7
	anchor_top = 0.2
	anchor_bottom = 0.7

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.08, 0.95)
	style.border_color = Color(0.46, 0.33, 0.19, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Transfer Gold"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# From
	var from_row := HBoxContainer.new()
	from_row.add_theme_constant_override("separation", 8)
	vbox.add_child(from_row)
	var from_label := Label.new()
	from_label.text = "From:"
	from_label.add_theme_font_size_override("font_size", 13)
	from_label.custom_minimum_size.x = 50
	from_row.add_child(from_label)
	_source_dropdown = OptionButton.new()
	_source_dropdown.add_theme_font_size_override("font_size", 12)
	_source_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_dropdown.item_selected.connect(func(_idx): _update_preview())
	from_row.add_child(_source_dropdown)

	# To
	var to_row := HBoxContainer.new()
	to_row.add_theme_constant_override("separation", 8)
	vbox.add_child(to_row)
	var to_label := Label.new()
	to_label.text = "To:"
	to_label.add_theme_font_size_override("font_size", 13)
	to_label.custom_minimum_size.x = 50
	to_row.add_child(to_label)
	_target_dropdown = OptionButton.new()
	_target_dropdown.add_theme_font_size_override("font_size", 12)
	_target_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_dropdown.item_selected.connect(func(_idx): _update_preview())
	to_row.add_child(_target_dropdown)

	# Amount
	var amt_row := HBoxContainer.new()
	amt_row.add_theme_constant_override("separation", 8)
	vbox.add_child(amt_row)
	var amt_label := Label.new()
	amt_label.text = "Amount:"
	amt_label.add_theme_font_size_override("font_size", 13)
	amt_label.custom_minimum_size.x = 50
	amt_row.add_child(amt_label)
	_amount_field = LineEdit.new()
	_amount_field.placeholder_text = "GP amount"
	_amount_field.add_theme_font_size_override("font_size", 12)
	_amount_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount_field.text_changed.connect(func(_t): _update_preview())
	amt_row.add_child(_amount_field)
	var gp_suffix := Label.new()
	gp_suffix.text = "GP"
	gp_suffix.add_theme_font_size_override("font_size", 13)
	amt_row.add_child(gp_suffix)

	vbox.add_child(HSeparator.new())

	# Preview
	_preview_label = Label.new()
	_preview_label.text = ""
	_preview_label.add_theme_font_size_override("font_size", 11)
	_preview_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_preview_label)

	vbox.add_child(HSeparator.new())

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 12)
	cancel_btn.pressed.connect(func(): visible = false)
	btn_row.add_child(cancel_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Transfer"
	_confirm_btn.add_theme_font_size_override("font_size", 12)
	_confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_btn)


func _populate_dropdowns() -> void:
	_source_dropdown.clear()
	_target_dropdown.clear()
	_source_ids.clear()
	_target_ids.clear()

	var party_id: String = GameState.party_id
	var active_id: String = GameState.active_character_id

	# Source: wallet contributors (PCs only)
	var contributors: Array = PartyWallet.get_contributors(party_id, active_id)
	for char_id in contributors:
		var char_data := CampaignRepository.get_character(char_id)
		var name_str: String = str(char_data.get("name", "Unknown"))
		var coins := CampaignRepository.get_character_coins(char_id)
		var total_gp := Currency.coins_to_cp(coins) / 100.0
		_source_dropdown.add_item("%s (%.2f GP)" % [name_str, total_gp])
		_source_ids.append(char_id)

	# Target: all PCs + henchmen
	var all_chars: Array = CampaignRepository.list_party_characters(party_id)
	for c in all_chars:
		var char_id: String = str(c.get("id", ""))
		var name_str: String = str(c.get("name", "Unknown"))
		var coins := CampaignRepository.get_character_coins(char_id)
		var total_gp := Currency.coins_to_cp(coins) / 100.0
		_target_dropdown.add_item("%s (%.2f GP)" % [name_str, total_gp])
		_target_ids.append(char_id)

	# Default target to someone other than source if possible
	if _target_ids.size() > 1 and _source_ids.size() > 0:
		for i in range(_target_ids.size()):
			if _target_ids[i] != _source_ids[0]:
				_target_dropdown.selected = i
				break


func _update_preview() -> void:
	var amount_text: String = _amount_field.text.strip_edges()
	if amount_text.is_empty() or not amount_text.is_valid_float():
		_preview_label.text = "Enter a GP amount to see preview."
		_confirm_btn.disabled = true
		return

	var amount_gp := float(amount_text)
	var amount_cp := roundi(amount_gp * 100.0)

	if amount_cp <= 0:
		_preview_label.text = "Amount must be positive."
		_confirm_btn.disabled = true
		return

	var src_idx: int = _source_dropdown.selected
	var tgt_idx: int = _target_dropdown.selected
	if src_idx < 0 or src_idx >= _source_ids.size() or tgt_idx < 0 or tgt_idx >= _target_ids.size():
		_preview_label.text = "Select source and target."
		_confirm_btn.disabled = true
		return

	var src_id: String = _source_ids[src_idx]
	var tgt_id: String = _target_ids[tgt_idx]

	if src_id == tgt_id:
		_preview_label.text = "Source and target cannot be the same."
		_confirm_btn.disabled = true
		return

	# Check if source can afford
	var src_coins := CampaignRepository.get_character_coins(src_id)
	var src_total := Currency.coins_to_cp(src_coins)
	if amount_cp > src_total:
		_preview_label.text = "Insufficient funds (has %.2f GP)." % (src_total / 100.0)
		_confirm_btn.disabled = true
		return

	_preview_label.text = "Transfer %.2f GP (%d cp)" % [amount_gp, amount_cp]
	_confirm_btn.disabled = false


func _on_confirm() -> void:
	var amount_text: String = _amount_field.text.strip_edges()
	if not amount_text.is_valid_float():
		return
	var amount_gp := float(amount_text)
	var amount_cp := roundi(amount_gp * 100.0)

	var src_idx: int = _source_dropdown.selected
	var tgt_idx: int = _target_dropdown.selected
	if src_idx < 0 or tgt_idx < 0:
		return

	var src_id: String = _source_ids[src_idx]
	var tgt_id: String = _target_ids[tgt_idx]

	var pay_result: Dictionary = PartyWallet.pay_from_character(src_id, amount_cp)
	if not pay_result.get("ok", false):
		EventBus.notification_requested.emit({
			"message": str(pay_result.get("message", "Payment failed")),
			"type": "warning",
		})
		return

	PartyWallet.deposit_to_character(tgt_id, amount_cp)

	visible = false
	gold_transferred.emit(src_id, tgt_id, amount_gp)
