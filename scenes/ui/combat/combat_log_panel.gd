class_name CombatLogPanel
extends PanelContainer

## Scrolling combat log display.
##
## Formats CombatLog entries into readable coloured text using RichTextLabel.
## Toggle visibility with the show/hide button.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const COLOR_ROUND   := Color(0.9, 0.9, 0.5)
const COLOR_ATTACK  := Color(0.8, 0.8, 0.8)
const COLOR_DAMAGE  := Color(0.9, 0.3, 0.3)
const COLOR_HEAL    := Color(0.3, 0.9, 0.3)
const COLOR_SPELL   := Color(0.6, 0.5, 0.9)
const COLOR_MORALE  := Color(0.9, 0.7, 0.2)
const COLOR_DOWNED  := Color(0.7, 0.2, 0.2)
const COLOR_DEATH   := Color(0.5, 0.1, 0.1)
const COLOR_FLEE    := Color(0.8, 0.6, 0.2)
const COLOR_MOVE    := Color(0.5, 0.7, 0.9)
const COLOR_CLEAVE  := Color(0.9, 0.5, 0.2)
const COLOR_END     := Color(0.9, 0.9, 0.3)

## Map CombatLog.EntryType enum values to colour.
## Must match the enum order in combat_log.gd.
const COLOR_INIT    := Color(0.5, 0.8, 0.9)
const COLOR_DECL    := Color(0.7, 0.7, 0.5)

const ENTRY_TYPE_COLORS := {
	0:  COLOR_ROUND,   # ROUND_START
	1:  COLOR_ATTACK,  # ATTACK
	2:  COLOR_DAMAGE,  # DAMAGE
	3:  COLOR_SPELL,   # SPELL
	4:  COLOR_MOVE,    # MOVEMENT
	5:  COLOR_MORALE,  # MORALE
	6:  COLOR_DOWNED,  # COMBATANT_DOWNED
	7:  COLOR_DOWNED,  # MORTAL_WOUND
	8:  COLOR_DEATH,   # DEATH
	9:  COLOR_FLEE,    # FLEE
	10: COLOR_CLEAVE,  # CLEAVE
	11: COLOR_END,     # COMBAT_END
	12: COLOR_INIT,    # INITIATIVE (UI-only type)
	13: COLOR_DECL,    # DECLARATION (UI-only type)
}


# ---------------------------------------------------------------------------
# Scene references
# ---------------------------------------------------------------------------

var _log_text: RichTextLabel = null
var _toggle_btn: Button = null
var _export_btn: Button = null
var _scroll: ScrollContainer = null

## Raw log entries for export. Each entry is the original dict passed to append_event().
var _entries: Array = []

## Name lookup: combatant_id -> display_name. Set via set_name_lookup().
var _name_lookup: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(260, 140)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	add_child(vbox)

	# Header row with title + toggle button
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Combat Log"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	header.add_child(title)

	_export_btn = Button.new()
	_export_btn.text = "Export"
	_export_btn.custom_minimum_size = Vector2(55, 0)
	_export_btn.pressed.connect(_on_export_pressed)
	header.add_child(_export_btn)

	_toggle_btn = Button.new()
	_toggle_btn.text = "Hide"
	_toggle_btn.custom_minimum_size = Vector2(50, 0)
	_toggle_btn.pressed.connect(_on_toggle_pressed)
	header.add_child(_toggle_btn)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Scrolling log area
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_log_text = RichTextLabel.new()
	_log_text.bbcode_enabled = true
	_log_text.fit_content = true
	_log_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_text.add_theme_font_size_override("normal_font_size", 10)
	_scroll.add_child(_log_text)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Append a formatted log entry from CombatLog.
## Entry dict: {type, round, actor_id, target_id, data, timestamp}
func append_event(log_entry: Dictionary) -> void:
	_entries.append(log_entry.duplicate(true))

	var entry_type: int = log_entry.get("type", -1)
	var color: Color = ENTRY_TYPE_COLORS.get(entry_type, COLOR_ATTACK)
	var text := _format_entry(log_entry)
	if text.is_empty():
		return

	var hex_color := "#%s" % color.to_html(false)
	_log_text.append_text("[color=%s]%s[/color]\n" % [hex_color, text])

	# Auto-scroll to bottom
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


## Append a raw text line (for custom messages).
func append_text(text: String, color: Color = Color.WHITE) -> void:
	var hex_color := "#%s" % color.to_html(false)
	_log_text.append_text("[color=%s]%s[/color]\n" % [hex_color, text])


## Set the name lookup dictionary: {combatant_id: display_name}.
## Used to resolve raw IDs in attack result sub-dicts.
func set_name_lookup(lookup: Dictionary) -> void:
	_name_lookup = lookup


## Clear all log content.
func clear_log() -> void:
	_log_text.clear()
	_entries.clear()


## Export all log entries to a JSON file in user:// and copy the formatted text
## to clipboard. Returns the file path, or "" on failure.
func export_log() -> String:
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var json_path := "user://combat_log_%s.json" % timestamp
	var txt_path := "user://combat_log_%s.txt" % timestamp

	# Write structured JSON
	var json_file := FileAccess.open(json_path, FileAccess.WRITE)
	if json_file == null:
		push_error("CombatLogPanel.export_log: could not open '%s'" % json_path)
		return ""
	json_file.store_string(JSON.stringify(_entries, "\t"))
	json_file.close()

	# Write human-readable text
	var txt_file := FileAccess.open(txt_path, FileAccess.WRITE)
	if txt_file != null:
		for entry in _entries:
			var line := _format_entry(entry)
			if not line.is_empty():
				txt_file.store_line(line)
		txt_file.close()

	# Also copy text to clipboard for quick paste
	var clip_text := ""
	for entry in _entries:
		var line := _format_entry(entry)
		if not line.is_empty():
			clip_text += line + "\n"
	DisplayServer.clipboard_set(clip_text)

	var real_path := ProjectSettings.globalize_path(json_path)
	print("Combat log exported: %s (also copied to clipboard)" % real_path)
	return json_path


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _format_entry(entry: Dictionary) -> String:
	var entry_type: int = entry.get("type", -1)
	var data: Dictionary = entry.get("data", {})
	# Prefer display names over raw IDs
	var actor: String = entry.get("actor_name", entry.get("actor_id", ""))
	var target: String = entry.get("target_name", entry.get("target_id", ""))
	var round_num: int = entry.get("round", 0)

	match entry_type:
		0:  # ROUND_START
			return "--- Round %d ---" % round_num
		1:  # ATTACK
			return _format_attack(data, actor, target)
		2:  # DAMAGE
			var amount: int = data.get("damage_total", data.get("amount", 0))
			var dmg_expr: String = data.get("damage_expression", "")
			if not dmg_expr.is_empty():
				return "  Damage: %s = %d hp" % [dmg_expr, amount]
			return "  Damage: %d hp" % amount
		3:  # SPELL
			var spell_name: String = data.get("spell_name", "a spell")
			return "%s casts %s" % [actor, spell_name]
		4:  # MOVEMENT
			return _format_movement(data, actor)
		5:  # MORALE
			return _format_morale(data, actor)
		6:  # COMBATANT_DOWNED
			return "%s is downed!" % target
		7:  # MORTAL_WOUND
			var wound_desc: String = data.get("wound_description", "mortal wound")
			return "%s: %s" % [target, wound_desc]
		8:  # DEATH
			return "%s is slain!" % target
		9:  # FLEE
			return "%s flees!" % actor
		10: # CLEAVE
			if target.is_empty():
				return "%s may cleave!" % actor
			return "%s may cleave into %s!" % [actor, target]
		11: # COMBAT_END
			var result: String = data.get("result", "unknown")
			return "=== Combat Over: %s ===" % result.to_upper()
		12: # INITIATIVE (custom type for UI log)
			return _format_initiative(data)
		13: # DECLARATION (custom type for UI log)
			return _format_declaration(data, actor)
		_:
			# Fallback: check if data has an "action" wrapper from CombatUIController
			if data.has("action"):
				return _format_action_wrapper(data, actor)
			return str(data)


func _format_attack(data: Dictionary, actor: String, target: String) -> String:
	## Full attack roll breakdown.
	# data may be:
	#   - raw attack_result dict (hit, attack_roll, etc.)
	#   - multi-attack wrapper: {"attacks": [attack_result, ...]}
	#   - action wrapper: {"action":..., "result":...}

	# Multi-attack: format each sub-attack on its own line
	if data.has("attacks") and data["attacks"] is Array:
		var lines: Array = []
		for i in range(data["attacks"].size()):
			var sub: Dictionary = data["attacks"][i]
			var sub_target: String = _lookup_name(sub.get("target_id", target))
			lines.append(_format_single_attack(sub, actor, sub_target))
		return "\n".join(lines)

	# Action wrapper from combat_log.add_entry
	if data.has("result") and data["result"] is Dictionary:
		var inner: Dictionary = data["result"]
		if inner.has("attacks") and inner["attacks"] is Array:
			var lines: Array = []
			for sub in inner["attacks"]:
				var sub_target: String = _lookup_name(sub.get("target_id", target))
				lines.append(_format_single_attack(sub, actor, sub_target))
			return "\n".join(lines)
		if inner.has("hit"):
			return _format_single_attack(inner, actor, inner.get("target_id", target))
		if inner.has("note"):
			return "%s: %s" % [actor, inner["note"]]

	# Direct single attack
	return _format_single_attack(data, actor, target)


func _format_single_attack(atk: Dictionary, actor: String, target: String) -> String:
	var hit: bool = atk.get("hit", false)
	var roll: int = atk.get("attack_roll", 0)
	var bonus: int = atk.get("to_hit_bonus", 0)
	var total: int = atk.get("total_attack", 0)
	var needed: int = atk.get("target_number", 0)
	var nat20: bool = atk.get("natural_twenty", false)
	var nat1: bool = atk.get("natural_one", false)

	# Use the resolved target name passed in; fall back to raw ID from attack result
	var atk_target: String = target if not target.is_empty() else atk.get("target_id", "")

	# --- Special cases: no d20 was rolled (attack_roll == 0) ---

	# Ranged: target beyond weapon range
	if atk.get("out_of_range", false):
		return "%s -> %s: Out of range" % [actor, atk_target]

	# Ranged: blocked by melee engagement
	if atk.get("into_melee_blocked", false):
		var reason: String = atk.get("blocked_reason", "firing into melee")
		if reason == "no_precise_shooting":
			return "%s -> %s: Blocked — cannot fire into melee without Precise Shooting" % [actor, atk_target]
		return "%s -> %s: Blocked — %s" % [actor, atk_target, reason]

	# Auto-hit (spell effect) — no d20 rolled, skip to damage
	if hit and roll == 0:
		var line := "%s -> %s: Auto-hit" % [actor, atk_target]
		line += _format_damage_suffix(atk, atk_target)
		return line

	# Attack prevented (spell hook cancellation etc.) — no d20 rolled
	if not hit and roll == 0:
		return "%s -> %s: Attack prevented" % [actor, atk_target]

	# --- Normal attack: d20 was rolled ---
	var bonus_str := "+%d" % bonus if bonus >= 0 else str(bonus)

	var line := "%s -> %s: d20(%d)%s = %d vs AC target %d" % [
		actor, atk_target, roll, bonus_str, total, needed]

	if nat20:
		line += " — NATURAL 20, HIT!"
	elif nat1:
		line += " — NATURAL 1, miss!"
	elif hit:
		line += " — HIT"
	else:
		line += " — miss"

	if hit:
		line += _format_damage_suffix(atk, atk_target)

	return line


func _format_damage_suffix(atk: Dictionary, atk_target: String) -> String:
	## Formats the damage portion of an attack log entry.
	var dmg_expr: String = atk.get("damage_expression", "")
	var dmg_total: int = atk.get("damage_total", 0)
	var dmg_result: Dictionary = atk.get("damage_result", {})
	var hp_dmg: int = dmg_result.get("hp_damage", dmg_total)
	var resisted: int = dmg_result.get("resisted", 0)
	var new_hp: int = dmg_result.get("new_hp", -1)
	var downed: bool = atk.get("target_downed", false)

	var suffix := ""
	suffix += "\n  Damage: %s = %d" % [dmg_expr, dmg_total] if not dmg_expr.is_empty() \
		else "\n  Damage: %d" % dmg_total
	if resisted > 0:
		suffix += " (%d resisted, %d applied)" % [resisted, hp_dmg]
	if new_hp >= 0:
		suffix += " [%s HP: %d]" % [atk_target, new_hp]
	if downed:
		suffix += " — DOWNED!"
	return suffix


func _format_movement(data: Dictionary, actor: String) -> String:
	var action: String = data.get("action", "move")
	match action:
		"fighting_withdrawal":
			return "%s performs a fighting withdrawal" % actor
		"full_retreat":
			return "%s performs a full retreat!" % actor
		_:
			# Weapon switch (Sheathe & Draw)
			if data.has("old_weapon_name") or data.has("new_weapon_name"):
				var old_name: String = data.get("old_weapon_name", "Unarmed")
				var new_name: String = data.get("new_weapon_name", "")
				if new_name.is_empty() or new_name == "Unarmed":
					return "%s stows %s" % [actor, old_name]
				if old_name.is_empty() or old_name == "Unarmed":
					return "%s draws %s" % [actor, new_name]
				return "%s sheathes %s and draws %s" % [actor, old_name, new_name]

			var to_pos = data.get("to_position", data.get("target_cell", null))
			if to_pos != null and to_pos is Vector2i:
				return "%s moves to (%d, %d)" % [actor, to_pos.x, to_pos.y]
			var note: String = data.get("note", "")
			if not note.is_empty():
				return "%s: %s" % [actor, note]
			return "%s moves" % actor


func _format_morale(data: Dictionary, actor: String) -> String:
	var passed: bool = data.get("passed", false)
	var roll_val: int = data.get("roll", 0)
	var morale_mod: int = data.get("morale_modifier", 0)
	var total: int = data.get("total", roll_val)
	var outcome: String = data.get("outcome", "")

	var mod_str := "+%d" % morale_mod if morale_mod >= 0 else str(morale_mod)
	var line := "Morale [%s]: 2d6(%d)%s = %d" % [actor, roll_val, mod_str, total]
	if not outcome.is_empty():
		line += " — %s" % outcome
	elif passed:
		line += " — holds"
	else:
		line += " — BREAKS!"
	return line


func _format_initiative(data: Dictionary) -> String:
	var order: Array = data.get("initiative_order", [])
	if order.is_empty():
		return "Initiative rolled"
	var parts: Array = []
	for entry in order:
		var cid: String = entry.get("display_name", entry.get("combatant_id", "?"))
		var total: int = entry.get("total", 0)
		var roll: int = entry.get("roll", 0)
		var mod: int = entry.get("modifier", 0)
		var mod_str := "+%d" % mod if mod >= 0 else str(mod)
		parts.append("%s: d6(%d)%s=%d" % [cid, roll, mod_str, total])
	return "Initiative: %s" % ", ".join(parts)


func _format_declaration(data: Dictionary, actor: String) -> String:
	var decl_type: String = data.get("declaration_type", "")
	match decl_type:
		"fighting_withdrawal":
			return "%s declares fighting withdrawal" % actor
		"full_retreat":
			return "%s declares full retreat" % actor
		"set_against_charge":
			return "%s sets weapon against charge" % actor
		_:
			return "%s declares: %s" % [actor, decl_type]


func _format_action_wrapper(data: Dictionary, actor: String) -> String:
	## Handle the {action, result} wrapper from CombatUIController._emit_action_log
	var action_str: String = data.get("action", "")
	var result: Dictionary = data.get("result", {})

	match action_str:
		"attack_melee", "attack_ranged":
			return _format_attack(data, actor, result.get("target_id", ""))
		"move":
			return _format_movement(result, actor)
		"fighting_withdrawal", "full_retreat":
			return _format_movement({"action": action_str}, actor)
		"pass":
			return "%s passes" % actor
		_:
			var note: String = result.get("note", "")
			if not note.is_empty():
				return "%s: %s (%s)" % [actor, action_str, note]
			return "%s: %s" % [actor, action_str]


func _on_export_pressed() -> void:
	var path := export_log()
	if not path.is_empty():
		_export_btn.text = "Copied!"
		# Reset button text after 2 seconds
		get_tree().create_timer(2.0).timeout.connect(func(): _export_btn.text = "Export")


func _lookup_name(raw_id: String) -> String:
	## Resolve a combatant ID to display name via _name_lookup.
	if raw_id.is_empty():
		return raw_id
	return _name_lookup.get(raw_id, raw_id)


func _on_toggle_pressed() -> void:
	_scroll.visible = not _scroll.visible
	_toggle_btn.text = "Show" if not _scroll.visible else "Hide"
