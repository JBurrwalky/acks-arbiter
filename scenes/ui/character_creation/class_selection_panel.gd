class_name ClassSelectionPanel
extends VBoxContainer

## Step 2 — Class Selection.
##
## Shows all 25 ACKS 1e classes grouped by race (human first, then dwarf, then elf).
## Eligible classes are highlighted; ineligible ones are grayed with a reason tooltip.
## Right panel shows full class details for the selected class.


const RACES_IN_ORDER: Array[String] = ["human", "dwarf", "elf"]
const RACE_LABELS: Dictionary = {"human": "Human Classes", "dwarf": "Dwarven Classes", "elf": "Elven Classes"}
const SELECTED_CLASS_TEXT_COLOR := Color(1.0, 0.85, 0.3, 1.0)
const INELIGIBLE_CLASS_TEXT_COLOR := Color(0.35, 0.35, 0.35, 1.0)

var _state: Dictionary = {}
var _class_registry: ClassRegistry

var _class_buttons: Dictionary = {}   # class_id -> Button
var _detail_area: VBoxContainer
var _selected_class_id: String = ""

# Ineligibility reasons — computed on setup, class_id -> String
var _ineligible_reasons: Dictionary = {}


func setup(state: Dictionary, class_registry: ClassRegistry) -> void:
	_state = state
	_class_registry = class_registry
	if get_child_count() == 0:
		_build_ui()
	_refresh_eligibility()
	# Restore selection if returning to this step
	if not _state.get("class_id", "").is_empty():
		_select_class(_state["class_id"] as String, false)


func is_complete() -> bool:
	return not (_state.get("class_id", "") as String).is_empty()


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	add_child(hbox)

	# --- Left: scrollable class list (~40% width) ---
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.4
	UiSurfaceStyles.apply_textured_panel(left_panel)
	hbox.add_child(left_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	for race in RACES_IN_ORDER:
		var race_lbl := Label.new()
		race_lbl.text = RACE_LABELS[race]
		race_lbl.add_theme_font_size_override("font_size", 13)
		list_vbox.add_child(race_lbl)

		var sep := HSeparator.new()
		list_vbox.add_child(sep)

		var all_ids := _class_registry.get_all_class_ids()
		for class_id in all_ids:
			var cls := _class_registry.get_class_def(class_id)
			if cls.get("race", "human") != race:
				continue
			var btn := Button.new()
			btn.text = cls.get("class_name", class_id)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.toggle_mode = false
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_on_class_button_pressed.bind(class_id))
			list_vbox.add_child(btn)
			_class_buttons[class_id] = btn

		# Spacing between race groups
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 8)
		list_vbox.add_child(spacer)

	# --- Right: class detail display (~60% width) ---
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.6
	UiSurfaceStyles.apply_textured_panel(right_panel)
	hbox.add_child(right_panel)

	_detail_area = VBoxContainer.new()
	_detail_area.add_theme_constant_override("separation", 8)
	right_panel.add_child(_detail_area)

	var placeholder := Label.new()
	placeholder.text = "Select a class to see details."
	placeholder.name = "Placeholder"
	_detail_area.add_child(placeholder)


# ---------------------------------------------------------------------------
# Eligibility
# ---------------------------------------------------------------------------

func _refresh_eligibility() -> void:
	var scores: Dictionary = _state.get("scores", {})
	_ineligible_reasons.clear()

	for class_id in _class_buttons.keys():
		var btn: Button = _class_buttons[class_id]
		var cls := _class_registry.get_class_def(class_id)
		var reason := _get_ineligible_reason(cls, scores)
		if reason.is_empty():
			btn.disabled = false
			btn.modulate = Color.WHITE
			btn.remove_theme_color_override("font_disabled_color")
			btn.tooltip_text = ""
		else:
			btn.disabled = true
			btn.modulate = Color(0.6, 0.6, 0.6, 1.0)
			btn.add_theme_color_override("font_disabled_color", INELIGIBLE_CLASS_TEXT_COLOR)
			btn.tooltip_text = reason
			_ineligible_reasons[class_id] = reason


func _get_ineligible_reason(cls: Dictionary, scores: Dictionary) -> String:
	if scores.is_empty():
		return "Roll ability scores first."

	# Prime requisite minimum 9
	var primes: Array = cls.get("prime_requisites", [])
	for pr in primes:
		var score: int = int(scores.get(pr, 0))
		if score < 9:
			return "%s requires %s 9+ (you have %d)." % [cls.get("class_name", ""), pr, score]

	# Minimum abilities
	var mins: Dictionary = cls.get("minimum_abilities", {})
	for ability in mins.keys():
		var required: int = int(mins[ability])
		var score: int = int(scores.get(ability, 0))
		if score < required:
			return "%s requires %s %d+ (you have %d)." % [
				cls.get("class_name", ""), ability, required, score]

	return ""


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func _on_class_button_pressed(class_id: String) -> void:
	_select_class(class_id, true)


func _select_class(class_id: String, update_state: bool) -> void:
	_selected_class_id = class_id
	if update_state:
		var cls := _class_registry.get_class_def(class_id)
		_state["class_id"] = class_id
		_state["race"] = cls.get("race", "human")

	# Highlight selected button
	for cid in _class_buttons.keys():
		var btn: Button = _class_buttons[cid]
		if cid == class_id:
			btn.add_theme_color_override("font_color", SELECTED_CLASS_TEXT_COLOR)
		else:
			btn.remove_theme_color_override("font_color")

	_show_class_detail(class_id)


func _show_class_detail(class_id: String) -> void:
	# Clear existing detail children
	for child in _detail_area.get_children():
		child.queue_free()

	var cls := _class_registry.get_class_def(class_id)
	if cls.is_empty():
		return

	var scores: Dictionary = _state.get("scores", {})

	# Class name + race
	var name_lbl := Label.new()
	name_lbl.text = "%s  (%s)" % [cls.get("class_name", class_id),
		(cls.get("race", "human") as String).capitalize()]
	name_lbl.add_theme_font_size_override("font_size", 16)
	_detail_area.add_child(name_lbl)

	_detail_area.add_child(HSeparator.new())

	# Prime requisites + XP adjustment
	var primes: Array = cls.get("prime_requisites", [])
	var prime_str := ", ".join(primes) if not primes.is_empty() else "None"
	var prime_scores: Array = []
	for pr in primes:
		prime_scores.append(int(scores.get(pr, 10)))
	var xp_adj := AbilityUtils.get_xp_adjustment(prime_scores)
	var xp_adj_str := ("+%d%%" % xp_adj) if xp_adj >= 0 else ("%d%%" % xp_adj)
	_add_detail_row("Prime Requisite:", "%s → XP %s" % [prime_str, xp_adj_str])

	# Minimum abilities (if any)
	var mins: Dictionary = cls.get("minimum_abilities", {})
	if not mins.is_empty():
		var min_parts: Array = []
		for ability in mins.keys():
			min_parts.append("%s %d+" % [ability, int(mins[ability])])
		_add_detail_row("Minimums:", ", ".join(min_parts))

	# Hit die
	_add_detail_row("Hit Die:", cls.get("hit_die", "1d8"))

	# Max level
	_add_detail_row("Max Level:", str(cls.get("max_level", 14)))

	# Combat progression
	_add_detail_row("Combat:", (cls.get("combat_progression", "fighter") as String).capitalize())

	# XP for level 2
	var xp_l2 := _class_registry.get_xp_for_level(class_id, 2)
	_add_detail_row("XP for Level 2:", "%d" % xp_l2)

	# Weapon permissions
	var wpn: Array = cls.get("weapon_permissions", [])
	var wpn_str := "All weapons" if wpn == ["all"] else (", ".join(wpn) if not wpn.is_empty() else "None")
	if wpn_str.length() > 50:
		wpn_str = "Restricted (see class)"
	_add_detail_row("Weapons:", wpn_str)

	# Armor permissions
	var arm: Array = cls.get("armor_permissions", [])
	var arm_str := "All armor" if arm == ["all"] else (", ".join(arm) if not arm.is_empty() else "None")
	if arm_str.length() > 50:
		arm_str = "Restricted (see class)"
	var shield_ok: bool = cls.get("shield_permitted", true)
	arm_str += (" + Shield" if shield_ok else ", No Shield")
	_add_detail_row("Armor:", arm_str)

	# Casting
	var casting := _class_registry.get_casting_power(class_id)
	if not casting.is_empty():
		var power_id: String = casting.get("power_id", "")
		var tradition := "Arcane" if "arcane" in power_id else "Divine"
		_add_detail_row("Spellcasting:", tradition)
	else:
		_add_detail_row("Spellcasting:", "None")

	# Alignment restriction
	var align_restrict: String = cls.get("alignment_restriction", "")
	if not align_restrict.is_empty():
		_add_detail_row("Alignment:", align_restrict.capitalize())

	# Level 1 title
	var title := _class_registry.get_level_title(class_id, 1)
	if not title.is_empty():
		_add_detail_row("Level 1 Title:", title)

	# Ineligibility warning (if applicable)
	if _ineligible_reasons.has(class_id):
		var warn := Label.new()
		warn.text = "⚠ " + _ineligible_reasons[class_id]
		warn.add_theme_color_override("font_color", UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail_area.add_child(warn)


func _add_detail_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_detail_area.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(130, 0)
	row.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)
