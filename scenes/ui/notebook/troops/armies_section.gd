extends VBoxContainer

## Armies sub-section embedded in the Troops tab per gdd-army-warfare.md §7.1.
##
## Vertical card list of armies owned (or commanded) by the active entity,
## with a "Form Army" button. Each card shows: name, command line
## (rank + officer name + Leadership/Strategic/Morale Mod), composition
## summary (unit count · BR · troop count), color-coded state badge, current
## location, and a horizontal supply gauge (current_stockpile / weekly_cost
## weeks remaining). Click a card → expand into an army_detail_panel inline
## below the card.
##
## Subscribes to:
##   EventBus.army_formed
##   EventBus.army_disbanded
##   EventBus.army_arrived_at_hex
##   EventBus.army_supply_consumed
##   EventBus.army_supply_cut
##
## Public API:
##   set_active_entity(entity_id: String, entity_kind: String)  # 'pc' | 'henchman'
##   refresh()  # rebuild card list from DB

const _CARD_SEPARATION := 8

const STATE_COLOR := {
	"assembling":      Color(0.65, 0.65, 0.65),
	"encamped":        Color(0.30, 0.55, 0.85),
	"marching":        Color(0.95, 0.65, 0.20),
	"requisitioning":  Color(0.30, 0.75, 0.40),
	"looting":         Color(0.65, 0.20, 0.20),
	"besieging":       Color(0.55, 0.20, 0.65),
	"battling":        Color(0.85, 0.20, 0.20),
	"withdrawing":     Color(0.85, 0.45, 0.20),
	"disbanded":       Color(0.40, 0.40, 0.40),
}

const PreloadFormDialog := preload("res://scenes/ui/troops/army_form_dialog.gd")
const PreloadDetailPanel := preload("res://scenes/ui/notebook/troops/army_detail_panel.gd")

var _active_entity_id: String = ""
var _active_entity_kind: String = "pc"

var _header_label: Label = null
var _form_button: Button = null
var _list_vbox: VBoxContainer = null
var _expanded_army_id: String = ""


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", _CARD_SEPARATION)

	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header_row)

	_header_label = Label.new()
	_header_label.text = "Armies (0)"
	_header_label.add_theme_font_size_override("font_size", 18)
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_header_label)

	_form_button = Button.new()
	_form_button.text = "Form Army"
	_form_button.pressed.connect(_on_form_army_pressed)
	header_row.add_child(_form_button)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", _CARD_SEPARATION)
	add_child(_list_vbox)

	_subscribe_signals()


func _exit_tree() -> void:
	_unsubscribe_signals()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_active_entity(entity_id: String, entity_kind: String = "pc") -> void:
	_active_entity_id = entity_id
	_active_entity_kind = entity_kind
	refresh()


func refresh() -> void:
	for child in _list_vbox.get_children():
		_list_vbox.remove_child(child)
		child.queue_free()

	var armies: Array = _list_armies_for_active()
	_header_label.text = "Armies (%d)" % armies.size()

	# Form Army button is disabled until the player has ≥3 unaligned-and-
	# ungarrisoned troop_units (per gdd-army-warfare.md §3.1 minimum).
	_form_button.disabled = _count_eligible_units() < 3
	_form_button.tooltip_text = "" if not _form_button.disabled else \
		"Need ≥3 unaligned troop_units to form an army (RAW: daw_armies_recruitment.xml §divisions L737)."

	if armies.is_empty():
		var hint := Label.new()
		hint.text = (
			"No armies. Hire mercenaries / conscript troops / call vassals " +
			"to arms via the Domain tab's Decrees & Remote Orders sub-tab, " +
			"then press Form Army to assemble them under a command hierarchy."
		)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.modulate = Color(0.78, 0.78, 0.78)
		_list_vbox.add_child(hint)
		return

	for army in armies:
		_list_vbox.add_child(_build_card(army))


# ---------------------------------------------------------------------------
# Card construction
# ---------------------------------------------------------------------------

func _build_card(army: Dictionary) -> Control:
	var army_id: String = String(army.get("id", ""))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_inner := VBoxContainer.new()
	card_inner.add_theme_constant_override("separation", 4)
	card.add_child(card_inner)

	# Header row: name + state badge.
	var header_row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = String(army.get("name", "Unnamed Army"))
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(name_label)
	var state_chip := Label.new()
	var state: String = String(army.get("state", "assembling"))
	state_chip.text = "  %s  " % state.replace("_", " ")
	state_chip.modulate = STATE_COLOR.get(state, Color(0.7, 0.7, 0.7))
	header_row.add_child(state_chip)
	card_inner.add_child(header_row)

	# Command line.
	var leader: Dictionary = ArmyRepository.get_army_leader(army_id)
	var leader_name := _character_name(String(leader.get("character_id", "")))
	var cmd_line := Label.new()
	cmd_line.text = "%s %s · Leadership %d · Strategic %+d · Morale Mod %+d" % [
		String(leader.get("rank", "—")).replace("_", " "),
		leader_name,
		int(leader.get("leadership_ability", 4)),
		int(leader.get("strategic_ability", 0)),
		int(leader.get("morale_modifier", 0)),
	]
	cmd_line.modulate = Color(0.85, 0.85, 0.85)
	card_inner.add_child(cmd_line)

	# Composition + location.
	var assignments: Array = ArmyRepository.list_active_assignments_for_army(army_id)
	var total_br: float = 0.0
	var total_troops: int = 0
	for assn in assignments:
		var unit: Dictionary = _troop_unit(String(assn.get("troop_unit_id", "")))
		total_br += float(unit.get("battle_rating", 0.0)) * float(unit.get("count", 0))
		total_troops += int(unit.get("count", 0))
	var loc_text: String = ""
	if army.get("hex_q") != null and army.get("hex_r") != null:
		loc_text = "(%d, %d)" % [int(army.get("hex_q", 0)), int(army.get("hex_r", 0))]
	var meta_line := Label.new()
	meta_line.text = "%d units · BR %.1f · %d troops · %s" % [
		assignments.size(), total_br, total_troops, loc_text,
	]
	meta_line.modulate = Color(0.75, 0.75, 0.75)
	card_inner.add_child(meta_line)

	# Supply gauge.
	var supply: Dictionary = ArmyRepository.get_supply_state(army_id)
	if not supply.is_empty():
		var weekly_cost_cp: int = int(supply.get("weekly_supply_cost_cp", 0))
		var stockpile_cp: int = int(supply.get("current_stockpile_cp", 0))
		var weeks_remaining: float = 0.0
		if weekly_cost_cp > 0:
			weeks_remaining = float(stockpile_cp) / float(weekly_cost_cp)
		var supply_line := Label.new()
		# stockpile + weekly_cost are cp; format_cost denominates.
		supply_line.text = "Supply: %s / %s/wk = %.1f weeks" % [
			Currency.format_cost(stockpile_cp),
			Currency.format_cost(weekly_cost_cp),
			weeks_remaining,
		]
		var status: String = String(supply.get("supply_line_status", "out_of_supply_no_base"))
		if status != "in_supply":
			supply_line.modulate = Color(0.85, 0.55, 0.20)
		card_inner.add_child(supply_line)

	# Click-to-expand: when card is clicked, replace it with a detail panel.
	var btn := Button.new()
	btn.text = "Inspect"
	btn.pressed.connect(_on_inspect_pressed.bind(army_id))
	card_inner.add_child(btn)

	# Inline expanded detail panel when this army is the expanded one.
	if _expanded_army_id == army_id:
		var detail := PreloadDetailPanel.new()
		detail.display(army_id)
		card_inner.add_child(detail)

	return card


# ---------------------------------------------------------------------------
# Action handlers
# ---------------------------------------------------------------------------

func _on_form_army_pressed() -> void:
	var dialog := PreloadFormDialog.new()
	dialog.set_owner_character(_active_entity_id)
	add_child(dialog)
	dialog.popup_centered()
	dialog.army_formed.connect(func(_army_id):
		dialog.queue_free()
		refresh()
	)
	dialog.cancelled.connect(func():
		dialog.queue_free()
	)


func _on_inspect_pressed(army_id: String) -> void:
	if _expanded_army_id == army_id:
		_expanded_army_id = ""
	else:
		_expanded_army_id = army_id
	refresh()


# ---------------------------------------------------------------------------
# Signal handling
# ---------------------------------------------------------------------------

func _subscribe_signals() -> void:
	if not EventBus.army_formed.is_connected(_on_army_event):
		EventBus.army_formed.connect(_on_army_event)
	if not EventBus.army_disbanded.is_connected(_on_army_disbanded):
		EventBus.army_disbanded.connect(_on_army_disbanded)
	if not EventBus.army_arrived_at_hex.is_connected(_on_army_arrived):
		EventBus.army_arrived_at_hex.connect(_on_army_arrived)
	if not EventBus.army_supply_consumed.is_connected(_on_army_supply_event):
		EventBus.army_supply_consumed.connect(_on_army_supply_event)
	if not EventBus.army_supply_cut.is_connected(_on_army_supply_cut):
		EventBus.army_supply_cut.connect(_on_army_supply_cut)


func _unsubscribe_signals() -> void:
	if EventBus.army_formed.is_connected(_on_army_event):
		EventBus.army_formed.disconnect(_on_army_event)
	if EventBus.army_disbanded.is_connected(_on_army_disbanded):
		EventBus.army_disbanded.disconnect(_on_army_disbanded)
	if EventBus.army_arrived_at_hex.is_connected(_on_army_arrived):
		EventBus.army_arrived_at_hex.disconnect(_on_army_arrived)
	if EventBus.army_supply_consumed.is_connected(_on_army_supply_event):
		EventBus.army_supply_consumed.disconnect(_on_army_supply_event)
	if EventBus.army_supply_cut.is_connected(_on_army_supply_cut):
		EventBus.army_supply_cut.disconnect(_on_army_supply_cut)


func _on_army_event(_army_id: String, _owner_id: String, _command_id: String) -> void:
	refresh()


func _on_army_disbanded(_army_id: String, _reason: String) -> void:
	refresh()


func _on_army_arrived(_army_id: String, _q: int, _r: int, _map_id: String) -> void:
	refresh()


func _on_army_supply_event(_army_id: String, _gp: int, _remaining: int) -> void:
	refresh()


func _on_army_supply_cut(_army_id: String, _cause: String) -> void:
	refresh()


# ---------------------------------------------------------------------------
# Data helpers
# ---------------------------------------------------------------------------

func _list_armies_for_active() -> Array:
	if _active_entity_id.is_empty():
		return []
	# Combine armies-owned + armies-commanded; dedupe by id.
	var owned: Array = ArmyRepository.list_armies_for_owner(_active_entity_id)
	var commanded: Array = ArmyRepository.list_armies_under_command(_active_entity_id)
	var seen: Dictionary = {}
	var combined: Array = []
	for a in owned:
		var aid: String = String(a.get("id", ""))
		if not seen.has(aid):
			seen[aid] = true
			combined.append(a)
	for a in commanded:
		var aid: String = String(a.get("id", ""))
		if not seen.has(aid):
			seen[aid] = true
			combined.append(a)
	return combined


func _count_eligible_units() -> int:
	if _active_entity_id.is_empty():
		return 0
	# Units owned by active entity that are not currently assigned to any army.
	var units: Array = TroopUnitRepository.list_active_for_owner(_active_entity_id)
	var count: int = 0
	for u in units:
		var unit_id: String = String(u.get("id", ""))
		var assn: Dictionary = ArmyRepository.get_active_assignment_for_unit(unit_id)
		if assn.is_empty():
			count += 1
	return count


func _character_name(character_id: String) -> String:
	if character_id.is_empty():
		return "(no commander)"
	if not CampaignRepository.db.query_with_bindings(
		"SELECT name FROM characters WHERE id = ? LIMIT 1", [character_id]):
		return "?"
	if CampaignRepository.db.query_result.is_empty():
		return "?"
	return String(CampaignRepository.db.query_result[0].get("name", "?"))


func _troop_unit(troop_unit_id: String) -> Dictionary:
	if troop_unit_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM troop_units WHERE id = ?", [troop_unit_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]
