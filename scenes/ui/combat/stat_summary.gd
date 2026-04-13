class_name StatSummary
extends PanelContainer

## Stat summary panel for the active combatant.
##
## Shows name, class/HD, HP, AC, conditions, and remaining movement.
## Updated each time the active combatant changes via show_combatant().


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const COLOR_HP_GOOD := Color(0.2, 0.8, 0.2)
const COLOR_HP_HURT := Color(0.8, 0.7, 0.1)
const COLOR_HP_LOW  := Color(0.8, 0.2, 0.2)


# ---------------------------------------------------------------------------
# Scene references (built in _ready)
# ---------------------------------------------------------------------------

var _name_label: Label = null
var _class_label: Label = null
var _hp_label: Label = null
var _hp_bar: ProgressBar = null
var _ac_label: Label = null
var _movement_label: Label = null
var _conditions_label: Label = null
var _weapon_label: Label = null
var _attack_label: Label = null
var _damage_label: Label = null
var _ammo_label: Label = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(200, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Name row
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox.add_child(_name_label)

	# Class / HD row
	_class_label = Label.new()
	_class_label.add_theme_font_size_override("font_size", 11)
	_class_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_class_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# HP bar + label row
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6)
	vbox.add_child(hp_row)

	var hp_title := Label.new()
	hp_title.text = "HP:"
	hp_title.add_theme_font_size_override("font_size", 11)
	hp_row.add_child(hp_title)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 11)
	_hp_label.custom_minimum_size.x = 50.0
	hp_row.add_child(_hp_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(80, 12)
	_hp_bar.show_percentage = false
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_hp_bar)

	# AC + Movement row
	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 12)
	vbox.add_child(stat_row)

	_ac_label = Label.new()
	_ac_label.add_theme_font_size_override("font_size", 11)
	stat_row.add_child(_ac_label)

	_movement_label = Label.new()
	_movement_label.add_theme_font_size_override("font_size", 11)
	stat_row.add_child(_movement_label)

	# Weapon row
	_weapon_label = Label.new()
	_weapon_label.add_theme_font_size_override("font_size", 11)
	_weapon_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	vbox.add_child(_weapon_label)

	# Attack + Damage row
	var combat_row := HBoxContainer.new()
	combat_row.add_theme_constant_override("separation", 12)
	vbox.add_child(combat_row)

	_attack_label = Label.new()
	_attack_label.add_theme_font_size_override("font_size", 11)
	combat_row.add_child(_attack_label)

	_damage_label = Label.new()
	_damage_label.add_theme_font_size_override("font_size", 11)
	combat_row.add_child(_damage_label)

	_ammo_label = Label.new()
	_ammo_label.add_theme_font_size_override("font_size", 11)
	_ammo_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5))
	combat_row.add_child(_ammo_label)

	# Conditions row
	_conditions_label = Label.new()
	_conditions_label.add_theme_font_size_override("font_size", 10)
	_conditions_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
	_conditions_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_conditions_label)

	_clear()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Display stats for the given Combatant (engine/subsystems/combat/combatant.gd).
func show_combatant(combatant) -> void:
	if combatant == null:
		_clear()
		return

	_name_label.text = combatant.display_name

	# Class / HD line
	if combatant.is_character:
		var prog: String = combatant.get_combat_progression()
		var lvl: int = combatant.get_level_or_hd()
		_class_label.text = "%s (Lvl %d)" % [prog.capitalize(), lvl]
	else:
		var hd: int = combatant.get_level_or_hd()
		_class_label.text = "HD %d" % hd

	# HP
	var hp_cur: int = combatant.get_hp_current()
	var hp_max: int = combatant.get_hp_max()
	_hp_label.text = "%d / %d" % [hp_cur, hp_max]
	_hp_bar.max_value = hp_max
	_hp_bar.value = hp_cur
	_style_hp_bar(hp_cur, hp_max)

	# AC
	var ac: int = combatant.get_effective_ac()
	_ac_label.text = "AC %d" % ac

	# Movement
	var move_cells: int = combatant.get_combat_movement_cells()
	var moved: bool = combatant.has_moved_this_round
	if moved:
		_movement_label.text = "Mv: 0/%d" % move_cells
	else:
		_movement_label.text = "Mv: %d" % move_cells

	# Weapon info (PC only)
	if combatant.is_character:
		var wpn: Dictionary = combatant.get_equipped_weapon()
		if not wpn.is_empty():
			var wpn_name: String = wpn.get("name", "Weapon")
			var magic: int = int(wpn.get("magical_bonus", 0))
			_weapon_label.text = "%s%s" % [wpn_name, " +%d" % magic if magic > 0 else ""]

			# Attack throw vs AC 0
			var atk_throw: int = combatant.get_effective_attack_throw()
			var str_mod: int = CharacterData.ability_modifier(
				combatant._character.get_effective_ability_score("strength"))
			var total_bonus: int = str_mod + magic
			var target_ac0: int = atk_throw  # attack_throw is the d20 value needed to hit AC 0
			var bonus_str := "+%d" % total_bonus if total_bonus >= 0 else str(total_bonus)
			_attack_label.text = "Atk: %d+ (%s)" % [target_ac0, bonus_str]

			# Damage
			var dmg_expr: String = combatant.get_weapon_damage()
			var dmg_bonus: int = str_mod + magic
			if dmg_bonus > 0:
				_damage_label.text = "Dmg: %s+%d" % [dmg_expr, dmg_bonus]
			elif dmg_bonus < 0:
				_damage_label.text = "Dmg: %s%d" % [dmg_expr, dmg_bonus]
			else:
				_damage_label.text = "Dmg: %s" % dmg_expr

			# Ammo
			var ammo_count: int = combatant.get_ammo_count()
			if ammo_count >= 0:
				_ammo_label.text = "Ammo: %d" % ammo_count
			else:
				_ammo_label.text = ""
		else:
			_weapon_label.text = "Unarmed"
			var unarmed_str_mod: int = CharacterData.ability_modifier(
				combatant._character.get_effective_ability_score("strength"))
			var unarmed_atk: int = combatant.get_effective_attack_throw()
			var unarmed_bonus_str := "+%d" % unarmed_str_mod if unarmed_str_mod >= 0 else str(unarmed_str_mod)
			_attack_label.text = "Atk: %d+ (%s)" % [unarmed_atk, unarmed_bonus_str]
			if unarmed_str_mod > 0:
				_damage_label.text = "Dmg: 1d3+%d" % unarmed_str_mod
			elif unarmed_str_mod < 0:
				_damage_label.text = "Dmg: 1d3%d" % unarmed_str_mod
			else:
				_damage_label.text = "Dmg: 1d3"
			_ammo_label.text = ""
	else:
		# Monster — show HD-based attack info
		_weapon_label.text = ""
		_attack_label.text = ""
		_damage_label.text = ""
		_ammo_label.text = ""

	# Conditions
	if combatant.conditions.is_empty():
		_conditions_label.text = ""
	else:
		_conditions_label.text = ", ".join(combatant.conditions)


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _clear() -> void:
	_name_label.text = "No combatant"
	_class_label.text = ""
	_hp_label.text = "- / -"
	_hp_bar.max_value = 1
	_hp_bar.value = 0
	_ac_label.text = "AC -"
	_movement_label.text = "Mv: -"
	_weapon_label.text = ""
	_attack_label.text = ""
	_damage_label.text = ""
	_ammo_label.text = ""
	_conditions_label.text = ""


func _style_hp_bar(current: int, max_val: int) -> void:
	var ratio := 0.0 if max_val <= 0 else float(current) / float(max_val)
	var fill := StyleBoxFlat.new()
	if ratio > 0.5:
		fill.bg_color = COLOR_HP_GOOD
	elif ratio > 0.25:
		fill.bg_color = COLOR_HP_HURT
	else:
		fill.bg_color = COLOR_HP_LOW
	fill.corner_radius_top_left = 2
	fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2
	_hp_bar.add_theme_stylebox_override("fill", fill)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.15)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	_hp_bar.add_theme_stylebox_override("background", bg)
