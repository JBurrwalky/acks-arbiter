# GoldShareModal — weighted gold-share editor for loot distribution.
#
# Dependencies:
#   - CampaignRepository (autoload): list_xp_eligible_entities, get_character_coins
#   - GameState (autoload): active_party_id / party_id
#   - Currency (preloaded): coins_to_cp, format_cost
#
# No class_name — lazily instantiated by LootDistributionModal.
#
# Design note:
#   PCs default to share weight 1.0, henchmen to 0.5 (ACKS half-share).
#   The modal only edits *weights*. Actual GP amounts are previewed live but
#   deposits are performed by the parent modal on shares_confirmed.

extends CanvasLayer

signal shares_confirmed(shares: Dictionary)
signal cancelled()

const Currency := preload("res://engine/subsystems/commerce/currency.gd")

var _panel: PanelContainer
var _share_rows: Dictionary = {}  # character_id -> {spinbox: SpinBox, name: String, type: String}
var _preview_label: Label
var _total_cp: int = 0
var _is_built: bool = false


func _ready() -> void:
	layer = 54
	visible = false


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Opens the modal for editing gold shares.
## total_cp: the total copper value to distribute.
## party_id: which party to list recipients from.
func open(total_cp: int, party_id: String = "") -> void:
	_total_cp = total_cp
	if not _is_built:
		_build_ui()

	_populate_recipients(party_id)
	_update_preview()
	visible = true


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_is_built = true

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.25
	_panel.anchor_right = 0.75
	_panel.anchor_top = 0.15
	_panel.anchor_bottom = 0.85
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	UiSurfaceStyles.apply_framed_window_chrome(_panel)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Edit Gold Shares"
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Instructions
	var hint := Label.new()
	hint.text = "Set share weights. PCs default to 1.0, henchmen to 0.5 (half-share)."
	hint.add_theme_font_size_override("font_size", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint)

	vbox.add_child(HSeparator.new())

	# Scroll container for recipient rows
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 200
	vbox.add_child(scroll)

	var _rows_container := VBoxContainer.new()
	_rows_container.name = "RowsContainer"
	_rows_container.add_theme_constant_override("separation", 4)
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)

	vbox.add_child(HSeparator.new())

	# Preview
	_preview_label = Label.new()
	_preview_label.text = ""
	_preview_label.add_theme_font_size_override("font_size", 11)
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_preview_label)

	vbox.add_child(HSeparator.new())

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.add_theme_font_size_override("font_size", 12)
	reset_btn.pressed.connect(_on_reset)
	btn_row.add_child(reset_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 12)
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)

	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.add_theme_font_size_override("font_size", 12)
	apply_btn.pressed.connect(_on_apply)
	btn_row.add_child(apply_btn)


# ---------------------------------------------------------------------------
# Recipient list
# ---------------------------------------------------------------------------

func _populate_recipients(party_id: String) -> void:
	_share_rows.clear()

	var rows_container: VBoxContainer = _panel.find_child("RowsContainer", true, false)
	if rows_container == null:
		return

	# Clear old rows.
	for child in rows_container.get_children():
		child.queue_free()

	if party_id.is_empty():
		party_id = GameState.active_party_id
		if party_id.is_empty():
			party_id = GameState.party_id

	var entities: Array = CampaignRepository.list_xp_eligible_entities(party_id)

	for entity in entities:
		var char_id: String = str(entity.get("id", ""))
		var char_name: String = str(entity.get("name", "Unknown"))
		var char_type: String = str(entity.get("character_type", "pc"))
		var default_weight: float = 1.0 if char_type == "pc" else 0.5

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		rows_container.add_child(row)

		# Name label
		var name_label := Label.new()
		var type_suffix := " (H)" if char_type == "henchman" else ""
		name_label.text = char_name + type_suffix
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.custom_minimum_size.x = 150
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		# Share weight label
		var weight_label := Label.new()
		weight_label.text = "Share:"
		weight_label.add_theme_font_size_override("font_size", 12)
		row.add_child(weight_label)

		# SpinBox for share weight
		var spinbox := SpinBox.new()
		spinbox.min_value = 0.0
		spinbox.max_value = 10.0
		spinbox.step = 0.5
		spinbox.value = default_weight
		spinbox.custom_minimum_size.x = 80
		spinbox.add_theme_font_size_override("font_size", 12)
		spinbox.value_changed.connect(func(_v): _update_preview())
		row.add_child(spinbox)

		# Per-character preview amount
		var amount_label := Label.new()
		amount_label.name = "AmountLabel"
		amount_label.text = ""
		amount_label.add_theme_font_size_override("font_size", 11)
		amount_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
		amount_label.custom_minimum_size.x = 100
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(amount_label)

		_share_rows[char_id] = {
			"spinbox": spinbox,
			"name": char_name,
			"type": char_type,
			"amount_label": amount_label,
			"row": row,
		}


# ---------------------------------------------------------------------------
# Preview computation
# ---------------------------------------------------------------------------

func _update_preview() -> void:
	var shares := _collect_weights()
	if shares.is_empty():
		_preview_label.text = "No recipients."
		return

	var computed := compute_shares(_total_cp, shares)
	if computed.is_empty():
		_preview_label.text = "All weights are zero."
		return

	# Update per-row amount labels.
	for char_id in _share_rows:
		var row_data: Dictionary = _share_rows[char_id]
		var amount_label: Label = row_data["amount_label"]
		var char_cp: int = computed.get(char_id, 0)
		amount_label.text = Currency.format_cost(char_cp)

	# Summary line — Currency.format_cost already denominates gp/sp/cp,
	# so the redundant decimal-gp form was dropped (Tier 3 sweep 2026-05-19).
	_preview_label.text = "Total: %s split among %d recipients." % [
		Currency.format_cost(_total_cp), computed.size()]


func _collect_weights() -> Dictionary:
	var weights := {}
	for char_id in _share_rows:
		var row_data: Dictionary = _share_rows[char_id]
		var w: float = row_data["spinbox"].value
		if w > 0.0:
			weights[char_id] = w
	return weights


# ---------------------------------------------------------------------------
# Share computation — static so parent modal can reuse
# ---------------------------------------------------------------------------

## Computes per-character CP amounts from total_cp and weight dict.
## Banker's rounding on each share, residual CP to the character with smallest share.
static func compute_shares(total_cp: int, shares: Dictionary) -> Dictionary:
	if shares.is_empty() or total_cp <= 0:
		return {}

	var total_weight := 0.0
	for w in shares.values():
		total_weight += float(w)
	if total_weight <= 0.0:
		return {}

	var per_char := {}
	var allocated := 0
	var char_ids: Array = shares.keys()

	for char_id in char_ids:
		var share_cp: int = roundi(total_cp * (float(shares[char_id]) / total_weight))
		per_char[char_id] = share_cp
		allocated += share_cp

	# Assign residual to the recipient with the smallest allocated amount.
	var residual: int = total_cp - allocated
	if residual != 0 and not char_ids.is_empty():
		var poorest_id: String = char_ids[0]
		var poorest_amount: int = per_char.get(poorest_id, 0)
		for char_id in char_ids:
			var amt: int = per_char.get(char_id, 0)
			if amt < poorest_amount:
				poorest_amount = amt
				poorest_id = char_id
		per_char[poorest_id] += residual

	return per_char


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

func _on_reset() -> void:
	for char_id in _share_rows:
		var row_data: Dictionary = _share_rows[char_id]
		var default_w: float = 1.0 if row_data["type"] == "pc" else 0.5
		row_data["spinbox"].value = default_w
	_update_preview()


func _on_cancel() -> void:
	visible = false
	cancelled.emit()


func _on_apply() -> void:
	var weights := _collect_weights()
	if weights.is_empty():
		return
	visible = false
	shares_confirmed.emit(weights)
