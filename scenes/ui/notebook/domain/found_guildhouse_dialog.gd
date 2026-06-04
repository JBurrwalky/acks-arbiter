extends AcceptDialog

## FoundGuildhouseDialog — the Venturer analogue of FoundSyndicateDialog
## (Venturer→Guildhouse refactor). Lets a level-9+ Venturer found a GUILDHOUSE
## (their mercantile base) in a chosen urban settlement. Calls
## FoundGuildhouseFlow.found_guildhouse on confirm and emits
## `guildhouse_founded_requested(guildhouse_id)` so the Domain tab can refresh.
##
## v1 simplification (mirrors the syndicate dialog): the dropdown lists ALL
## campaign settlements; the guildhouse is placed at the chosen settlement's hex.


signal guildhouse_founded_requested(guildhouse_id: String)


var _character: Dictionary = {}
var _campaign_id: String = ""

var _settlement_option: OptionButton = null
var _preview_label: Label = null
var _error_label: Label = null

const _ROMAN := {6: "VI", 5: "V", 4: "IV", 3: "III", 2: "II", 1: "I"}


func _ready() -> void:
	title = "Found a Guildhouse"
	dialog_hide_on_ok = false
	confirmed.connect(_on_confirmed)
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = ("Found a guildhouse in an urban settlement — your mercantile base. It "
		+ "follows hideout rules and secures no domain. You gain 2d6 1st-level apprentices. "
		+ "At level 12 you may seize settlement monopoly power for monthly revenue.")
	vbox.add_child(intro)

	var row := HBoxContainer.new()
	vbox.add_child(row)
	var lbl := Label.new()
	lbl.text = "Host settlement:"
	lbl.custom_minimum_size = Vector2(160, 0)
	row.add_child(lbl)
	_settlement_option = OptionButton.new()
	_settlement_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settlement_option.item_selected.connect(_on_settlement_changed)
	row.add_child(_settlement_option)

	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_preview_label)

	_error_label = Label.new()
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_error_label)


func setup(campaign_id: String, character: Dictionary) -> void:
	_campaign_id = campaign_id
	_character = character
	_error_label.text = ""
	_refresh_settlements()
	_refresh_preview()


func _refresh_settlements() -> void:
	_settlement_option.clear()
	for s: Dictionary in _list_campaign_settlements():
		var mc := int(s.get("market_class", 6))
		var label := "%s  (Class %s)" % [
			String(s.get("name", "Settlement")), String(_ROMAN.get(mc, str(mc)))]
		_settlement_option.add_item(label)
		var idx := _settlement_option.item_count - 1
		_settlement_option.set_item_metadata(idx,
			{"id": String(s.get("id", "")), "market_class": mc})
	if _settlement_option.item_count > 0:
		_settlement_option.selected = 0


func _refresh_preview() -> void:
	var meta := _selected_settlement_meta()
	if meta.is_empty():
		_preview_label.text = "No urban settlements available in this campaign."
		return
	var mc := int(meta.get("market_class", 6))
	var min_gp := HideoutCostTable.minimum_cost_gp_for_market_class(mc)
	_preview_label.text = "Guildhouse minimum cost: %d gp   •   2d6 apprentices" % min_gp


func _on_settlement_changed(_idx: int) -> void:
	_refresh_preview()


func _on_confirmed() -> void:
	_error_label.text = ""
	var meta := _selected_settlement_meta()
	if meta.is_empty():
		_error_label.text = "Select a host settlement."
		return
	var result := FoundGuildhouseFlow.found_guildhouse({
		"campaign_id": _campaign_id,
		"owner_character_id": String(_character.get("id", "")),
		"host_settlement_entrance_id": String(meta.get("id", "")),
	})
	if not result["errors"].is_empty():
		_error_label.text = "Could not found guildhouse: %s" % str(result["errors"])
		return
	guildhouse_founded_requested.emit(String(result["guildhouse_id"]))
	hide()


func _selected_settlement_meta() -> Dictionary:
	var idx := _settlement_option.selected
	if idx < 0:
		return {}
	var meta: Variant = _settlement_option.get_item_metadata(idx)
	return meta if meta is Dictionary else {}


func _list_campaign_settlements() -> Array:
	if _campaign_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id, name, market_class FROM settlement_entrances WHERE campaign_id = ? ORDER BY name ASC",
		[_campaign_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()
