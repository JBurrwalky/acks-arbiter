extends VBoxContainer

## Guildhouse block UI (Venturer→Guildhouse refactor) — minimal overview surface
## for a Venturer: the guildhouse, its apprentice roster (from the unified
## `followers` table), monopoly status + monthly-revenue preview, and a "Seize
## monopoly" button at level 12+.
##
## The full mercantile activity launchers (buy/sell/persuade/trade routes) are
## the DEFERRED Phase 10B.2 Trade Block; this block is the attach seam. Recreated
## fresh per render by domain_tab_page (not pooled), so it subscribes in _ready
## and unsubscribes in _exit_tree (coding_conventions §76).


var _character_id: String = ""
var _party_id: String = ""
var _body: VBoxContainer = null

const _ROMAN := {6: "VI", 5: "V", 4: "IV", 3: "III", 2: "II", 1: "I"}


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body)
	EventBus.guildhouse_founded.connect(_on_signal)
	EventBus.venturer_monopoly_seized.connect(_on_signal)


func _exit_tree() -> void:
	if EventBus.guildhouse_founded.is_connected(_on_signal):
		EventBus.guildhouse_founded.disconnect(_on_signal)
	if EventBus.venturer_monopoly_seized.is_connected(_on_signal):
		EventBus.venturer_monopoly_seized.disconnect(_on_signal)


func bind(character_id: String, _domain_id: String, party_id: String = "") -> void:
	_character_id = character_id
	_party_id = party_id
	_refresh()


func _on_signal(_a = null, _b = null) -> void:
	_refresh()


func _refresh() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var gh := GuildhouseRepository.get_guildhouse_for_owner(_character_id)
	if gh.is_empty():
		_body.add_child(_label("No guildhouse yet."))
		return

	# Overview.
	var mc := int(gh.get("market_class", 6))
	_body.add_child(_header("Guildhouse"))
	_body.add_child(_label("Settlement: %s (Class %s)" % [
		_settlement_name(String(gh.get("host_settlement_entrance_id", ""))),
		String(_ROMAN.get(mc, str(mc)))]))
	_body.add_child(_label("Value: %s" % Currency.format_cost(int(gh.get("cp_value", 0)))))

	# Apprentices.
	_body.add_child(_header("Apprentices"))
	_body.add_child(_label("%d venturer apprentices" % _apprentice_count()))
	_body.add_child(_dim("They level up, can be recruited as henchmen, and become full NPCs."))

	# Monopoly.
	_body.add_child(_header("Monopoly"))
	if int(gh.get("monopoly_seized", 0)) == 1:
		var fams := _settlement_urban_families(String(gh.get("host_settlement_entrance_id", "")))
		_body.add_child(_label("Seized — %s / month (%d urban families)" % [
			Currency.format_cost(fams * 100), fams]))
	else:
		var level := int(CampaignRepository.get_character(_character_id).get("level", 1))
		if level >= 12:
			var btn := Button.new()
			btn.text = "Seize monopoly"
			btn.pressed.connect(_on_seize_pressed)
			_body.add_child(btn)
		else:
			_body.add_child(_dim("Seizing settlement monopoly requires level 12."))


func _on_seize_pressed() -> void:
	var result := FoundGuildhouseFlow.seize_monopoly({"owner_character_id": _character_id})
	if not bool(result.get("ok", false)):
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "system",
			"title": "Could not seize monopoly",
			"body": str(result.get("errors", [])),
		})
		return
	_refresh()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _apprentice_count() -> int:
	var n := 0
	for f: Dictionary in CampaignRepository.list_followers_for_owner(_character_id, ""):
		if String(f.get("source_kind", "")) == "venturer_apprentice" \
				and String(f.get("status", "")) == "present":
			n += 1
	return n


func _settlement_name(id: String) -> String:
	if id.is_empty():
		return "(unknown)"
	if CampaignRepository.db.query_with_bindings(
			"SELECT name FROM settlement_entrances WHERE id = ? LIMIT 1", [id]) \
			and not CampaignRepository.db.query_result.is_empty():
		return String(CampaignRepository.db.query_result[0].get("name", "(unknown)"))
	return "(unknown)"


func _settlement_urban_families(id: String) -> int:
	if id.is_empty():
		return 0
	if CampaignRepository.db.query_with_bindings(
			"SELECT urban_families FROM settlement_entrances WHERE id = ? LIMIT 1", [id]) \
			and not CampaignRepository.db.query_result.is_empty():
		return int(CampaignRepository.db.query_result[0].get("urban_families", 0))
	return 0


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	return l


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _dim(text: String) -> Label:
	var l := _label(text)
	l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	return l
