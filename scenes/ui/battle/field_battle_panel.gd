extends CanvasLayer

## Interactive field-battle panel per gdd-army-warfare.md §7.4.
##
## Auto-opens on EventBus.battle_pause_for_player; closes on
## EventBus.battle_concluded. Player makes one bundled phase decision per
## iteration: foray declarations + advance/hold/withdraw choice. Confirm
## fires FieldBattleResolver.continue_battle and waits for the next
## battle_pause_for_player.
##
## Save/load: the panel rebuilds entirely from FieldBattleResolver
## .get_battle_state(battle_id) on reopen — no volatile scene state.
##
## Public API:
##   open_for_battle(battle_id: String)
##   close()
##
## Signals:
##   battle_panel_closed(battle_id: String, outcome: String)


signal battle_panel_closed(battle_id: String, outcome: String)

const _ZONE_LABELS := ["missile", "skirmish", "melee", "reserve"]

var _battle_id: String = ""

var _root: Panel = null
var _header_label: Label = null
var _bpc_label: Label = null
var _terrain_label: Label = null
var _attacker_zones: Dictionary = {}    # zone -> VBoxContainer
var _defender_zones: Dictionary = {}    # zone -> VBoxContainer
var _foray_box: VBoxContainer = null
var _attacker_choice_btns: Dictionary = {}
var _defender_label: Label = null
var _battle_log_box: VBoxContainer = null
var _battle_log_scroll: ScrollContainer = null

var _selected_attacker_choice: String = "hold"
var _attacker_foray_inputs: Array = []  # [{hero_id_option, br_stake_option}]


func _ready() -> void:
	visible = false
	_build_layout()
	if EventBus.battle_pause_for_player.is_connected(_on_pause):
		EventBus.battle_pause_for_player.disconnect(_on_pause)
	EventBus.battle_pause_for_player.connect(_on_pause)
	if EventBus.battle_concluded.is_connected(_on_concluded):
		EventBus.battle_concluded.disconnect(_on_concluded)
	EventBus.battle_concluded.connect(_on_concluded)


func _exit_tree() -> void:
	if EventBus.battle_pause_for_player.is_connected(_on_pause):
		EventBus.battle_pause_for_player.disconnect(_on_pause)
	if EventBus.battle_concluded.is_connected(_on_concluded):
		EventBus.battle_concluded.disconnect(_on_concluded)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open_for_battle(battle_id: String) -> void:
	_battle_id = battle_id
	visible = true
	_render()


func close() -> void:
	visible = false
	_battle_id = ""


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_layout() -> void:
	_root = Panel.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 8)
	_root.add_child(outer)

	# Header.
	_header_label = Label.new()
	_header_label.text = "Battle"
	_header_label.add_theme_font_size_override("font_size", 22)
	outer.add_child(_header_label)

	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 16)
	_bpc_label = Label.new()
	_bpc_label.text = "Phase: — | BPC: —"
	info_row.add_child(_bpc_label)
	_terrain_label = Label.new()
	_terrain_label.text = "Terrain: —"
	info_row.add_child(_terrain_label)
	outer.add_child(info_row)

	# Two-column zone display.
	var two_col := HBoxContainer.new()
	two_col.add_theme_constant_override("separation", 16)
	two_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(two_col)

	var att_col := _make_side_column("Attacker", _attacker_zones)
	att_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two_col.add_child(att_col)
	var def_col := _make_side_column("Defender", _defender_zones)
	def_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two_col.add_child(def_col)

	# Foray declaration.
	_foray_box = VBoxContainer.new()
	_foray_box.add_theme_constant_override("separation", 4)
	var foray_header := Label.new()
	foray_header.text = "Heroic Forays (your side)"
	foray_header.add_theme_font_size_override("font_size", 14)
	_foray_box.add_child(foray_header)
	outer.add_child(_foray_box)

	# Advance / Hold / Withdraw.
	var ahw_row := HBoxContainer.new()
	ahw_row.add_theme_constant_override("separation", 8)
	for choice in ["advance", "hold", "withdraw"]:
		var btn := Button.new()
		btn.text = choice.capitalize()
		btn.toggle_mode = true
		btn.button_pressed = (choice == "hold")
		btn.pressed.connect(_on_choice_button.bind(choice))
		_attacker_choice_btns[choice] = btn
		ahw_row.add_child(btn)
	_defender_label = Label.new()
	_defender_label.text = "(opponent: NPC)"
	_defender_label.modulate = Color(0.7, 0.7, 0.7)
	ahw_row.add_child(_defender_label)
	outer.add_child(ahw_row)

	# Confirm button.
	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm Phase"
	confirm_btn.pressed.connect(_on_confirm)
	outer.add_child(confirm_btn)

	# Battle log scroll.
	var log_header := Label.new()
	log_header.text = "Battle Log"
	log_header.add_theme_font_size_override("font_size", 14)
	outer.add_child(log_header)
	_battle_log_scroll = ScrollContainer.new()
	_battle_log_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_battle_log_scroll.custom_minimum_size = Vector2(0, 200)
	_battle_log_box = VBoxContainer.new()
	_battle_log_scroll.add_child(_battle_log_box)
	outer.add_child(_battle_log_scroll)


func _make_side_column(side_name: String, zones_dict: Dictionary) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var header := Label.new()
	header.text = side_name
	header.add_theme_font_size_override("font_size", 18)
	col.add_child(header)
	for zone in _ZONE_LABELS:
		var zone_header := Label.new()
		zone_header.text = "  %s" % zone.capitalize()
		zone_header.modulate = Color(0.75, 0.75, 0.75)
		col.add_child(zone_header)
		var zone_box := VBoxContainer.new()
		zone_box.add_theme_constant_override("separation", 2)
		col.add_child(zone_box)
		zones_dict[zone] = zone_box
	return col


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _render() -> void:
	if _battle_id.is_empty():
		return
	var state: Dictionary = FieldBattleResolver.get_battle_state(_battle_id)
	if state.is_empty():
		return
	var battle: Dictionary = state.get("battle", {})
	var unit_states: Array = state.get("unit_states", [])
	var log_entries: Array = state.get("log", [])

	# Header.
	_header_label.text = "Battle of (%d, %d)" % [int(battle.get("hex_q", 0)), int(battle.get("hex_r", 0))]
	_bpc_label.text = "Turn %d · Phase: %s · BPC: %d / %d" % [
		int(battle.get("battle_turn_number", 1)),
		String(battle.get("current_phase", "—")),
		int(battle.get("current_bpc", 0)),
		int(battle.get("starting_bpc", 0)),
	]
	_terrain_label.text = "Terrain: %s · Atk advantage: %s · Def advantage: %s" % [
		String(battle.get("terrain_type", "—")),
		String(battle.get("attacker_terrain_advantage", "regular")),
		String(battle.get("defender_terrain_advantage", "regular")),
	]

	# Zone displays.
	for zone in _ZONE_LABELS:
		_clear_box(_attacker_zones[zone])
		_clear_box(_defender_zones[zone])
	for u in unit_states:
		var side: String = String(u.get("side", "attacker"))
		var zone: String = String(u.get("zone", "melee"))
		var box: VBoxContainer
		if side == "attacker":
			box = _attacker_zones[zone]
		else:
			box = _defender_zones[zone]
		var line := Label.new()
		var unit_name: String = _troop_type_for_unit(String(u.get("troop_unit_id", "")))
		line.text = "    %s — BR %.1f / %.1f [%s]" % [
			unit_name,
			float(u.get("br_current", 0.0)),
			float(u.get("br_at_battle_start", 0.0)),
			String(u.get("status", "engaged")),
		]
		if String(u.get("status", "")) == "destroyed":
			line.modulate = Color(0.5, 0.3, 0.3)
		box.add_child(line)

	# Foray inputs (one per qualifying hero on attacker side).
	_render_foray_inputs(battle)

	# Battle log.
	_clear_box(_battle_log_box)
	for entry in log_entries:
		var label := Label.new()
		label.text = "[%d turn %d %s] %s" % [
			int(entry.get("sequence_number", 0)),
			int(entry.get("turn_number", 0)),
			String(entry.get("phase", "")),
			String(entry.get("event_type", "")),
		]
		label.tooltip_text = String(entry.get("payload_json", "{}"))
		_battle_log_box.add_child(label)


func _render_foray_inputs(battle: Dictionary) -> void:
	# Clear existing inputs (keep header at index 0).
	while _foray_box.get_child_count() > 1:
		var child = _foray_box.get_child(_foray_box.get_child_count() - 1)
		_foray_box.remove_child(child)
		child.queue_free()
	_attacker_foray_inputs.clear()

	var attacker_army_id: String = String(battle.get("attacker_army_id", ""))
	var unit_scale: String = "company"  # v1 default; ArmyRepository.get_army has unit_scale but plumbing through is fine
	var attacker_army: Dictionary = ArmyRepository.get_army(attacker_army_id)
	if not attacker_army.is_empty():
		unit_scale = String(attacker_army.get("unit_scale", "company"))
	var qualifying: Array = HeroicForayResolver.list_qualifying_heroes_for_army(attacker_army_id, unit_scale)
	if qualifying.is_empty():
		var hint := Label.new()
		hint.text = "(no qualifying heroes)"
		hint.modulate = Color(0.65, 0.65, 0.65)
		_foray_box.add_child(hint)
		return

	for hero in qualifying:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		var hero_id: String = String(hero.get("character_id", ""))
		name_label.text = "%s (%s level %d)" % [
			_character_name(hero_id),
			String(hero.get("character_type", "")),
			int(hero.get("level", 0)),
		]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var stake_option := OptionButton.new()
		stake_option.add_item("0 (no foray)")
		for s in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
			stake_option.add_item("%.1f BR" % s)
		row.add_child(stake_option)
		_foray_box.add_child(row)
		_attacker_foray_inputs.append({"hero_id": hero_id, "stake_option": stake_option})


# ---------------------------------------------------------------------------
# Action handlers
# ---------------------------------------------------------------------------

func _on_choice_button(choice: String) -> void:
	_selected_attacker_choice = choice
	# Toggle the buttons (radio-style).
	for c in _attacker_choice_btns:
		var btn: Button = _attacker_choice_btns[c]
		btn.button_pressed = (c == choice)


func _on_confirm() -> void:
	if _battle_id.is_empty():
		return
	var forays: Array = []
	var stake_values := [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
	for input in _attacker_foray_inputs:
		var stake_idx: int = (input["stake_option"] as OptionButton).selected
		if stake_idx <= 0:
			continue
		forays.append({
			"hero_id": String(input["hero_id"]),
			"br_staked": stake_values[stake_idx],
		})
	var decision: Dictionary = {
		"attacker_choice": _selected_attacker_choice,
		# defender_choice falls back to NPC heuristic.
		"attacker_forays": forays,
	}
	var result: Dictionary = FieldBattleResolver.continue_battle(_battle_id, decision)
	if bool(result.get("battle_concluded", false)):
		_on_concluded(_battle_id, String(result.get("outcome", "")))
		return
	_render()


func _on_pause(battle_id: String, _decision_point: String) -> void:
	if not visible:
		open_for_battle(battle_id)
	elif _battle_id == battle_id:
		_render()


func _on_concluded(battle_id: String, outcome: String) -> void:
	if _battle_id != battle_id:
		return
	# Show aftermath summary briefly, then close.
	var summary := Label.new()
	summary.text = "Battle concluded: %s" % outcome
	summary.add_theme_font_size_override("font_size", 18)
	summary.modulate = Color(1.0, 0.85, 0.2)
	if _battle_log_box != null:
		_battle_log_box.add_child(summary)
	emit_signal("battle_panel_closed", battle_id, outcome)
	# Caller is responsible for actually freeing / hiding the panel after
	# acknowledging. We hide on a delay so the player can read the result.
	await get_tree().create_timer(2.0).timeout
	close()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _clear_box(box: VBoxContainer) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _character_name(character_id: String) -> String:
	if character_id.is_empty():
		return "?"
	if not CampaignRepository.db.query_with_bindings(
		"SELECT name FROM characters WHERE id = ?", [character_id]):
		return "?"
	if CampaignRepository.db.query_result.is_empty():
		return "?"
	return String(CampaignRepository.db.query_result[0].get("name", "?"))


func _troop_type_for_unit(troop_unit_id: String) -> String:
	if troop_unit_id.is_empty():
		return "?"
	if not CampaignRepository.db.query_with_bindings(
		"SELECT troop_type FROM troop_units WHERE id = ?", [troop_unit_id]):
		return "?"
	if CampaignRepository.db.query_result.is_empty():
		return "?"
	return String(CampaignRepository.db.query_result[0].get("troop_type", "?"))
