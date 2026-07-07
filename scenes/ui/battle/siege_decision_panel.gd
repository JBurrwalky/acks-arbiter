extends CanvasLayer

## Post-victory siege-decision modal (gdd-army-warfare.md §4.10.3). Opens when a PLAYER army wins
## a field battle whose loser retreated into a friendly stronghold in the battle hex. RAW
## (daw_axioms_pitching_battle.xml:563-575): "the victorious army may then begin a siege." The
## player chooses Besiege / Encamp / March on.
##
## Pure UI. It emits ONE `decided(choice)` signal and closes; it performs NO DB writes and NO
## scheduler manipulation. The SessionRunner-owned listener owns the scheduler pause and routes the
## choice to BattleRetreatSiegeRouter.resolve_player_decision (which holds the live scheduler). This
## follows the player-decision-modal split in coding_conventions.md §27.
##
## Public API:
##   open_for_decision(victor_army_id, stronghold_id, defeated_army_id)
##   close()
##
## Signals:
##   decided(choice: String)   # choice ∈ {besiege, encamp, march_on}


signal decided(choice: String)

## Choice table (choice id + button label + description). Static + literal so tests can assert the
## option set without a SceneTree, mirroring EncounterDecisionPrompt.buttons_for_disposition (§27).
const CHOICES := [
	{
		"choice": "besiege",
		"label": "Besiege the stronghold",
		"desc": "Invest the stronghold and begin a siege under the normal rules. The garrison is trapped inside.",
	},
	{
		"choice": "encamp",
		"label": "Encamp here",
		"desc": "Hold the field. Your army stays encamped on this hex — rest, resupply, or wait before deciding.",
	},
	{
		"choice": "march_on",
		"label": "March on",
		"desc": "Break off and leave the garrison be. Your army stays encamped, ready for new orders from the map.",
	},
]

var _victor_army_id: String = ""
var _stronghold_id: String = ""
var _defeated_army_id: String = ""

var _root: Panel = null
var _header_label: Label = null
var _body_label: Label = null


static func choices() -> Array:
	return CHOICES.duplicate(true)


func _ready() -> void:
	layer = 95  # above the field-battle panel (layer 90); this opens as that one closes.
	visible = false
	_build_layout()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open_for_decision(victor_army_id: String, stronghold_id: String, defeated_army_id: String) -> void:
	_victor_army_id = victor_army_id
	_stronghold_id = stronghold_id
	_defeated_army_id = defeated_army_id
	_render()
	visible = true


func close() -> void:
	visible = false
	_victor_army_id = ""
	_stronghold_id = ""
	_defeated_army_id = ""


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_layout() -> void:
	# Dimmed full-screen backdrop.
	_root = Panel.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.modulate = Color(1, 1, 1, 0.96)
	add_child(_root)

	# Centered dialog.
	var dialog := PanelContainer.new()
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.custom_minimum_size = Vector2(560, 0)
	dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(dialog)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	# Header.
	_header_label = Label.new()
	_header_label.text = "Victory — the enemy holes up"
	_header_label.add_theme_font_size_override("font_size", 22)
	outer.add_child(_header_label)

	# Body (situation description; filled per-open in _render).
	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(512, 0)
	_body_label.modulate = Color(0.85, 0.85, 0.85)
	outer.add_child(_body_label)

	var sep := HSeparator.new()
	outer.add_child(sep)

	# One button (+ description) per choice.
	for entry in CHOICES:
		var choice: String = String(entry.get("choice", ""))
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var btn := Button.new()
		btn.text = String(entry.get("label", choice))
		btn.pressed.connect(_on_choice.bind(choice))
		row.add_child(btn)
		var desc := Label.new()
		desc.text = String(entry.get("desc", ""))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(512, 0)
		desc.add_theme_font_size_override("font_size", 12)
		desc.modulate = Color(0.65, 0.65, 0.65)
		row.add_child(desc)
		outer.add_child(row)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _render() -> void:
	if _body_label == null:
		return
	var victor_name := _army_name(_victor_army_id)
	var stronghold_label := _stronghold_label(_stronghold_id)
	var defeated_name := _army_name(_defeated_army_id)
	_body_label.text = "%s won the field. %s retreated into %s and the garrison holds it. What are your orders?" % [
		victor_name, defeated_name, stronghold_label,
	]


# ---------------------------------------------------------------------------
# Action handlers
# ---------------------------------------------------------------------------

func _on_choice(choice: String) -> void:
	emit_signal("decided", choice)
	close()


# ---------------------------------------------------------------------------
# Read-only display helpers (name lookups only — no writes, per §27)
# ---------------------------------------------------------------------------

func _army_name(army_id: String) -> String:
	if army_id.is_empty():
		return "The army"
	if not CampaignRepository.db.query_with_bindings(
			"SELECT name FROM armies WHERE id = ?", [army_id]) \
			or CampaignRepository.db.query_result.is_empty():
		return "The army"
	var v: Variant = CampaignRepository.db.query_result[0].get("name")
	return "The army" if v == null else String(v)


func _stronghold_label(stronghold_id: String) -> String:
	if stronghold_id.is_empty():
		return "the stronghold"
	if not CampaignRepository.db.query_with_bindings(
			"SELECT structure_type, domain_id FROM strongholds WHERE id = ?", [stronghold_id]) \
			or CampaignRepository.db.query_result.is_empty():
		return "the stronghold"
	var row: Dictionary = CampaignRepository.db.query_result[0]
	var structure: Variant = row.get("structure_type")
	var domain_name := _domain_name(row.get("domain_id"))
	var kind := "stronghold" if structure == null else String(structure).replace("_", " ")
	if domain_name.is_empty():
		return "the %s" % kind
	return "the %s of %s" % [kind, domain_name]


func _domain_name(domain_id_v: Variant) -> String:
	if domain_id_v == null:
		return ""
	var domain_id := String(domain_id_v)
	if domain_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
			"SELECT name FROM domains WHERE id = ?", [domain_id]) \
			or CampaignRepository.db.query_result.is_empty():
		return ""
	var v: Variant = CampaignRepository.db.query_result[0].get("name")
	return "" if v == null else String(v)
