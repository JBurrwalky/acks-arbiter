class_name ClaimStrongholdModal
extends CanvasLayer

## Confirm-claim modal for adopting an existing structure (ruin / dungeon /
## conquest / inheritance / purchase / grant) as a stronghold.
##
## Mirrors the danger-mode pattern of `ConfirmationPrompt`: the confirm button
## is greyed for 2 seconds before becoming clickable, since claiming is
## effectively irreversible (the stronghold is inserted with status='completed').
##
## Usage:
##   var modal := ClaimStrongholdModal.new()
##   add_child(modal)
##   modal.show_claim(
##       domain_id, owner_character_id,
##       "fortress", "stronghold_castle",
##       25000, "ruin", 0, 0, "")
##   modal.claimed.connect(_on_claimed)
##   modal.cancelled.connect(modal.queue_free)
##
## Phase 1 ships a minimal procedural UI; Phase 4 (Stronghold sub-tab) styles
## it via the shared vellum chrome and binds it to the sub-tab's "Claim
## existing structure" button.

signal claimed(stronghold_id: String)
signal cancelled

const PANEL_WIDTH := 440
const BUTTON_DELAY := 2.0
const HEADING_COLOR := Color(0.95, 0.90, 0.78, 1.0)
const BODY_COLOR := Color(0.85, 0.80, 0.70, 1.0)
const DANGER_COLOR := Color(0.75, 0.22, 0.18, 1.0)

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _body_label: Label = null
var _confirm_btn: Button = null
var _cancel_btn: Button = null

# Captured claim parameters.
var _domain_id: String = ""
var _owner_character_id: String = ""
var _archetype: String = ""
var _archetype_power_id: String = ""
var _appraised_gp_value: int = 0
var _source: String = ""
var _location_hex_q: int = 0
var _location_hex_r: int = 0
var _location_map_id: String = ""
var _ruler_class_id: String = ""


func _ready() -> void:
	layer = 180
	_build_ui()
	_hide_all()


func show_claim(
	domain_id: String,
	owner_character_id: String,
	archetype: String,
	archetype_power_id: String,
	appraised_gp_value: int,
	source: String,
	location_hex_q: int,
	location_hex_r: int,
	location_map_id: String,
	ruler_class_id: String = ""
) -> void:
	_domain_id = domain_id
	_owner_character_id = owner_character_id
	_archetype = archetype
	_archetype_power_id = archetype_power_id
	_appraised_gp_value = appraised_gp_value
	_source = source
	_location_hex_q = location_hex_q
	_location_hex_r = location_hex_r
	_location_map_id = location_map_id
	_ruler_class_id = ruler_class_id

	_title_label.text = "Claim Existing %s" % archetype.capitalize()
	_body_label.text = (
		"Source: %s\n"
		+ "Appraised value: %d gp\n"
		+ "\n"
		+ "Claiming this structure will permanently make it your stronghold. "
		+ "This action cannot be reversed."
	) % [source, appraised_gp_value]

	_confirm_btn.add_theme_color_override("font_color", DANGER_COLOR)
	_confirm_btn.disabled = true
	_confirm_btn.text = "Claim (2s)"
	_show_all()

	var timer := get_tree().create_timer(BUTTON_DELAY)
	await timer.timeout
	_confirm_btn.disabled = false
	_confirm_btn.text = "Claim"


func _on_confirm_pressed() -> void:
	var result := ClaimingResolver.claim_existing(
		_domain_id, _owner_character_id,
		_archetype, _archetype_power_id,
		_appraised_gp_value, _source,
		_location_hex_q, _location_hex_r, _location_map_id,
		_ruler_class_id)
	if result["errors"].is_empty():
		claimed.emit(String(result["stronghold_id"]))
	else:
		push_error("ClaimStrongholdModal: claim failed: %s" % str(result["errors"]))
		cancelled.emit()
	queue_free()


func _on_cancel_pressed() -> void:
	cancelled.emit()
	queue_free()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.55)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 220)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_color_override("font_color", HEADING_COLOR)
	_title_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.add_theme_color_override("font_color", BODY_COLOR)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(PANEL_WIDTH - 32, 0)
	vbox.add_child(_body_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(_cancel_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Claim"
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	btn_row.add_child(_confirm_btn)


func _hide_all() -> void:
	visible = false


func _show_all() -> void:
	visible = true
