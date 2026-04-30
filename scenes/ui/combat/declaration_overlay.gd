class_name DeclarationOverlay
extends PanelContainer

## Modal overlay at combat round start for PC action declarations.
##
## Lists all alive PCs with per-PC buttons for:
## - Fighting Withdrawal
## - Full Retreat
## - Set Against Charge
## - No Declaration (default)
##
## Spell declaration is disabled (deferred to F-3).
## Emits declarations_complete when the player confirms all declarations.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the player clicks Confirm. Array of {combatant_id, declaration_type}.
## declaration_type is "" for no declaration, or "fighting_withdrawal" / "full_retreat" / "set_against_charge".
signal declarations_complete(declarations: Array)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const DECLARATION_OPTIONS := [
	{"id": "", "label": "None"},
	{"id": "fighting_withdrawal", "label": "Fighting Withdrawal"},
	{"id": "full_retreat", "label": "Full Retreat"},
	{"id": "set_against_charge", "label": "Set vs Charge"},
]


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Array of {combatant_id, display_name} for alive PCs.
var _pc_list: Array = []

## {combatant_id -> selected declaration_type string}
var _declarations: Dictionary = {}

var _confirm_btn: Button = null
var _list_container: VBoxContainer = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(400, 200)

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
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	# Title
	var title := Label.new()
	title.text = "Declaration Phase"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	outer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Declare movement intentions before initiative is rolled."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(subtitle)

	var sep := HSeparator.new()
	outer.add_child(sep)

	# Scrollable PC list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_container)

	# Confirm button
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(btn_row)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm Declarations"
	_confirm_btn.custom_minimum_size = Vector2(180, 36)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	btn_row.add_child(_confirm_btn)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Populate the overlay with alive PCs.
## [param pcs] Array of {combatant_id: String, display_name: String}
func set_pc_list(pcs: Array) -> void:
	_pc_list = pcs
	_declarations.clear()
	for pc in pcs:
		_declarations[pc.get("combatant_id", "")] = ""
	_rebuild()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	for child in _list_container.get_children():
		child.queue_free()

	for pc in _pc_list:
		var cid: String = pc.get("combatant_id", "")
		var dname: String = pc.get("display_name", "???")

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list_container.add_child(row)

		# PC name
		var name_label := Label.new()
		name_label.text = dname
		name_label.custom_minimum_size.x = 120.0
		name_label.add_theme_font_size_override("font_size", 12)
		row.add_child(name_label)

		# Option buttons (OptionButton dropdown)
		var is_berserk: bool = bool(pc.get("is_berserk_raging", false))
		var dropdown := OptionButton.new()
		dropdown.custom_minimum_size.x = 180.0
		for i in range(DECLARATION_OPTIONS.size()):
			var opt: Dictionary = DECLARATION_OPTIONS[i]
			dropdown.add_item(opt["label"])
			# Berserkers cannot declare defensive movement.
			if is_berserk and opt["id"] in ["fighting_withdrawal", "full_retreat"]:
				dropdown.set_item_disabled(i, true)
		dropdown.selected = 0
		dropdown.item_selected.connect(_on_declaration_changed.bind(cid))
		if is_berserk:
			dropdown.tooltip_text = "Berserk rage — defensive declarations unavailable."
		row.add_child(dropdown)


func _on_declaration_changed(index: int, combatant_id: String) -> void:
	if index >= 0 and index < DECLARATION_OPTIONS.size():
		_declarations[combatant_id] = DECLARATION_OPTIONS[index]["id"]


func _on_confirm_pressed() -> void:
	var result: Array = []
	for cid in _declarations:
		var decl_type: String = _declarations[cid]
		if not decl_type.is_empty():
			result.append({"combatant_id": cid, "declaration_type": decl_type})
	declarations_complete.emit(result)
