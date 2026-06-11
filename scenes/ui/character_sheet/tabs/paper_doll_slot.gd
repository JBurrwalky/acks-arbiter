class_name PaperDollSlot
extends PanelContainer

## A single equipment slot tile in the Equipment tab's paper-doll
## (gdd-character-tab.md §3.4.3). Renders as a ~76×76 square showing the
## equipped item's icon (or its name as text fallback — the catalog has no
## per-item icons yet) with the slot label, an empty-state when nothing is
## worn, and a greyed disabled state (e.g. the off-hand while a two-handed
## weapon is equipped, §3.4.5).
##
## Interactions (§3.4.4):
##   - Drop an inventory/slot item here   -> _equip_action.call(item_id, slot_id)
##   - Click an occupied slot             -> _unequip_action.call(item_id)
##   - Drag an occupied slot elsewhere    -> drag payload carries from_slot so
##                                           a drop on the inventory zone or
##                                           another slot can move/unequip it.
##
## Drag payload shape (shared with EquipmentItemRow):
##   { "type": "inventory_item", "item_id": String, "item": Dictionary,
##     "from_slot": String }   # from_slot empty when dragged out of inventory

const SLOT_SIZE := Vector2(76, 76)

## Border tints — clothing/ornamentation slots read warmer (parchment) than the
## armor/weapon slots (steel), per §3.4.3's "visually distinct borders" note.
const _BORDER_GEAR := Color(0.46, 0.46, 0.52, 1.0)
const _BORDER_CLOTH := Color(0.52, 0.42, 0.26, 1.0)
const _BG_EMPTY := Color(0.12, 0.11, 0.10, 0.45)
const _BG_FILLED := Color(0.18, 0.17, 0.15, 0.85)
const _BG_DROP_OK := Color(0.20, 0.34, 0.20, 0.9)
const _BG_DROP_BAD := Color(0.36, 0.16, 0.14, 0.9)

## Slots that use the clothing/ornament border tint.
const _CLOTH_SLOTS := [
	"head", "neck", "cloak", "torso_clothing", "legs_clothing",
	"belt", "ring_l", "ring_r",
]

var _slot_id: String = ""
var _item: Dictionary = {}
var _disabled: bool = false
var _accept_check: Callable = Callable()
var _equip_action: Callable = Callable()
var _unequip_action: Callable = Callable()

var _style: StyleBoxFlat = null


func setup(slot_id: String, label: String, item: Dictionary, icon: Texture2D,
		disabled: bool, disabled_reason: String,
		accept_check: Callable, equip_action: Callable,
		unequip_action: Callable) -> void:
	_slot_id = slot_id
	_item = item if item != null else {}
	_disabled = disabled
	_accept_check = accept_check
	_equip_action = equip_action
	_unequip_action = unequip_action

	custom_minimum_size = SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP

	_style = StyleBoxFlat.new()
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(3)
	_style.content_margin_left = 3
	_style.content_margin_right = 3
	_style.content_margin_top = 2
	_style.content_margin_bottom = 2
	_apply_idle_style()
	add_theme_stylebox_override("panel", _style)

	_build(label, icon)

	# Tooltip: full item name (or slot purpose / disabled reason).
	if _disabled and not disabled_reason.is_empty():
		tooltip_text = disabled_reason
	elif not _item.is_empty():
		tooltip_text = _full_item_name()
	else:
		tooltip_text = label

	if _disabled:
		modulate = Color(0.55, 0.55, 0.55, 1.0)

	gui_input.connect(_on_gui_input)


func _build(label: String, icon: Texture2D) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	var label_lbl := Label.new()
	label_lbl.text = label
	label_lbl.add_theme_font_size_override("font_size", 9)
	label_lbl.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_SECONDARY_TEXT_COLOR)
	label_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(label_lbl)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(center)

	if not _item.is_empty():
		if icon != null:
			var tex := TextureRect.new()
			tex.texture = icon
			tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.custom_minimum_size = Vector2(48, 48)
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			center.add_child(tex)
		else:
			var name_lbl := Label.new()
			name_lbl.text = _short_item_name()
			name_lbl.add_theme_font_size_override("font_size", 10)
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			# clip_text caps the label's minimum width at 0 so a long name can
			# never force the tile wider than SLOT_SIZE; the text is also
			# truncated in _short_item_name(). Full name lives in the tooltip.
			# (Short-term: name text. End goal per §3.4.3 is a per-item icon.)
			name_lbl.clip_text = true
			name_lbl.custom_minimum_size = Vector2(SLOT_SIZE.x - 8, 0)
			name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			center.add_child(name_lbl)
	else:
		var dash := Label.new()
		dash.text = "—"
		dash.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_SECONDARY_TEXT_COLOR)
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(dash)


# ---------------------------------------------------------------------------
# Styling
# ---------------------------------------------------------------------------

func _apply_idle_style() -> void:
	_style.bg_color = _BG_FILLED if not _item.is_empty() else _BG_EMPTY
	_style.border_color = _BORDER_CLOTH if _slot_id in _CLOTH_SLOTS else _BORDER_GEAR


func _set_drop_style(ok: bool) -> void:
	_style.bg_color = _BG_DROP_OK if ok else _BG_DROP_BAD


# ---------------------------------------------------------------------------
# Click — unequip the occupant
# ---------------------------------------------------------------------------

func _on_gui_input(event: InputEvent) -> void:
	if _disabled or _item.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed:
		if _unequip_action.is_valid():
			_unequip_action.call(str(_item.get("id", "")))


# ---------------------------------------------------------------------------
# Drag and drop
# ---------------------------------------------------------------------------

func _get_drag_data(_at_position: Vector2) -> Variant:
	if _disabled or _item.is_empty():
		return null
	var preview := Label.new()
	preview.text = _full_item_name()
	set_drag_preview(preview)
	return {
		"type": "inventory_item",
		"item_id": str(_item.get("id", "")),
		"item": _item,
		"from_slot": _slot_id,
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if _disabled:
		return false
	if not (data is Dictionary) or data.get("type", "") != "inventory_item":
		return false
	var item: Dictionary = data.get("item", {})
	# Dropping an item back onto the slot it already occupies is a no-op reject.
	if str(item.get("id", "")) == str(_item.get("id", "")) and not _item.is_empty():
		return false
	var ok: bool = _accept_check.is_valid() and bool(_accept_check.call(item))
	_set_drop_style(ok)
	add_theme_stylebox_override("panel", _style)
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_apply_idle_style()
	add_theme_stylebox_override("panel", _style)
	if _equip_action.is_valid():
		_equip_action.call(str(data.get("item_id", "")), _slot_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_apply_idle_style()
		if _style != null:
			add_theme_stylebox_override("panel", _style)


# ---------------------------------------------------------------------------
# Name helpers
# ---------------------------------------------------------------------------

func _full_item_name() -> String:
	var name_str: String = str(_item.get("name", _item.get("item_key", "?")))
	var qty: int = int(_item.get("quantity", 1))
	var mag: int = int(_item.get("magical_bonus", 0))
	var dmg: String = str(_item.get("weapon_damage", ""))
	var result := name_str
	if mag > 0:
		result += " +%d" % mag
	if qty > 1:
		result += " ×%d" % qty
	if not dmg.is_empty():
		result += " (%s)" % dmg
	return result


## Max characters of the item name shown on the tile face before truncating with
## an ellipsis. Short-term measure until per-item icons land (§3.4.3); the full
## name + bonus + damage is always available via the slot tooltip.
const MAX_SLOT_NAME_CHARS := 10

func _short_item_name() -> String:
	## Compact label for the tile face — the full name lives in the tooltip.
	var name_str: String = str(_item.get("name", _item.get("item_key", "?")))
	if name_str.length() > MAX_SLOT_NAME_CHARS:
		name_str = name_str.substr(0, MAX_SLOT_NAME_CHARS - 1).strip_edges() + "…"
	var qty: int = int(_item.get("quantity", 1))
	if qty > 1:
		name_str += " ×%d" % qty
	return name_str
