class_name WeaponSwitchPopup
extends PanelContainer

## Modal popup for selecting a weapon to equip during combat.
##
## Shown when the player clicks "Sheathe & Draw" in the action panel.
## Lists all weapons in the character's inventory (excluding the currently
## equipped main-hand weapon) plus an "Unarmed (stow weapon)" option.
##
## Emits weapon_selected when a weapon is picked, or cancelled if the
## player closes the popup without choosing.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the player selects a weapon. The Dictionary is the inventory
## row for the chosen weapon, or {"stow_only": true} for going unarmed.
signal weapon_selected(item: Dictionary)

## Emitted when the player clicks Cancel.
signal cancelled()


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _list_container: VBoxContainer = null
var _cancel_btn: Button = null
var _subtitle_label: Label = null
var _has_shield: bool = false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(340, 180)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.4, 0.5)
	add_theme_stylebox_override("panel", style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	# Title
	var title := Label.new()
	title.text = "Sheathe & Draw"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	outer.add_child(title)

	# Subtitle (shows cost)
	_subtitle_label = Label.new()
	_subtitle_label.text = ""
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 11)
	_subtitle_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	outer.add_child(_subtitle_label)

	var sep := HSeparator.new()
	outer.add_child(sep)

	# Scroll container for weapon list
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 120.0
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.add_theme_constant_override("separation", 4)
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_container)

	var sep2 := HSeparator.new()
	outer.add_child(sep2)

	# Cancel button
	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.custom_minimum_size.y = 32.0
	_cancel_btn.pressed.connect(func(): cancelled.emit())
	outer.add_child(_cancel_btn)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Populate the weapon list.
## [param weapons]: Array of inventory row Dictionaries for available weapons.
## [param has_moved]: Whether the PC has already moved (determines cost label).
## [param is_armed]: Whether the PC currently has a weapon equipped.
## [param has_shield]: Whether the PC has a shield equipped in off-hand.
func set_weapons(weapons: Array, has_moved: bool, is_armed: bool, has_shield: bool) -> void:
	_has_shield = has_shield

	# Update subtitle with cost
	if has_moved:
		_subtitle_label.text = "(forfeits your attack action)"
	else:
		_subtitle_label.text = "(forfeits your movement)"

	# Clear existing children
	for child in _list_container.get_children():
		child.queue_free()

	# Load equipment catalog for weapon tag lookups
	var catalog_script = load("res://engine/subsystems/characters/equipment_catalog.gd")
	var catalog = catalog_script.new() if catalog_script != null else null

	# Add weapon buttons
	for weapon in weapons:
		var btn := Button.new()
		var display_name: String = weapon.get("name", "Unknown")
		var dmg: String = weapon.get("weapon_damage", "")
		var magic: int = int(weapon.get("magical_bonus", 0))

		# Build label
		var parts: Array = [display_name]
		if magic > 0:
			parts.append("+%d" % magic)
		if not dmg.is_empty():
			parts.append("(%s)" % dmg)

		# Check if two-handed (needs shield stow note)
		var item_key: String = weapon.get("item_key", "")
		if catalog != null and catalog.has_method("get_item") and has_shield:
			var cat_entry: Dictionary = catalog.get_item(item_key)
			var tags: Array = cat_entry.get("weapon_tags", [])
			if "two_handed" in tags:
				parts.append("[stows shield]")

		btn.text = " ".join(parts)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size.y = 30.0
		btn.add_theme_font_size_override("font_size", 12)
		var w: Dictionary = weapon
		btn.pressed.connect(func(): weapon_selected.emit(w))
		_list_container.add_child(btn)

	# Add "Stow Weapon (go unarmed)" option if currently armed
	if is_armed:
		var stow_btn := Button.new()
		stow_btn.text = "Stow Weapon (go unarmed)"
		stow_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		stow_btn.custom_minimum_size.y = 30.0
		stow_btn.add_theme_font_size_override("font_size", 12)
		stow_btn.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
		stow_btn.pressed.connect(func(): weapon_selected.emit({"stow_only": true}))
		_list_container.add_child(stow_btn)

	# Show message if nothing available at all
	if weapons.is_empty() and not is_armed:
		var lbl := Label.new()
		lbl.text = "No weapons available."
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_list_container.add_child(lbl)
