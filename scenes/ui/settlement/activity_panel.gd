class_name SettlementActivityPanel
extends VBoxContainer

## Dynamic activity panel shown when the party is at a PoI.
##
## Populates available activities based on PoI type per
## gdd-settlement-exploration-ui.md §4.1. Minor activities resolve immediately;
## major activities schedule completion events via the settlement handlers.

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal activity_requested(activity_type: String, poi: Dictionary)
signal exit_settlement_requested()
signal shop_requested(poi: Dictionary)
signal hiring_requested(poi: Dictionary)
## Routes the guild "Hire Specialists" activity to the specialist hire panel
## (gdd-specialists.md §6.2 — dual-path retain / commission flows).
signal specialist_hiring_requested(poi: Dictionary)
# Phase 10B.2 Wave 2: routes mercantile activity launchers (the six market /
# town_square trade activities) to SettlementExploreState's mercantile_panel.
signal mercantile_requested(activity_id: String, poi: Dictionary)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _poi: Dictionary = {}
var _is_open: bool = false  ## true = within business hours


# ---------------------------------------------------------------------------
# Activity definitions by PoI type
# ---------------------------------------------------------------------------

## Maps PoI type → Array of activity definitions.
## Each activity: {id, label, major: bool, requires_open: bool}
const ACTIVITIES := {
	"tavern": [
		{"id": "rest_short", "label": "Rest (Short)", "major": false, "requires_open": false},
		{"id": "rest_long", "label": "Rest (Long, 8 hours)", "major": true, "requires_open": false},
		{"id": "gather_info", "label": "Gather Information (4 hours)", "major": true, "requires_open": false},
		{"id": "carouse", "label": "Carouse (1 day)", "major": true, "requires_open": false},
		{"id": "hire_henchmen", "label": "Hire Henchmen", "major": false, "requires_open": false},
	],
	"inn": [
		{"id": "rest_short", "label": "Rest (Short)", "major": false, "requires_open": false},
		{"id": "rest_long", "label": "Rest (Long, 8 hours)", "major": true, "requires_open": false},
		{"id": "gather_info", "label": "Gather Information (4 hours)", "major": true, "requires_open": false},
		{"id": "hire_henchmen", "label": "Hire Henchmen", "major": false, "requires_open": false},
	],
	"temple": [
		{"id": "healing", "label": "Healing Services", "major": false, "requires_open": false},
		{"id": "tithe", "label": "Tithe", "major": false, "requires_open": true},
		{"id": "commune", "label": "Commune (Divine Services)", "major": true, "requires_open": true},
	],
	"shop": [
		{"id": "buy_equipment", "label": "Buy Equipment", "major": false, "requires_open": true},
		{"id": "sell_equipment", "label": "Sell Equipment", "major": false, "requires_open": true},
		{"id": "commission", "label": "Commission Equipment", "major": false, "requires_open": true},
	],
	"shophouse": [
		{"id": "buy_equipment", "label": "Buy Equipment", "major": false, "requires_open": true},
		{"id": "sell_equipment", "label": "Sell Equipment", "major": false, "requires_open": true},
		{"id": "commission", "label": "Commission Equipment", "major": false, "requires_open": true},
	],
	"emporium": [
		{"id": "buy_equipment", "label": "Buy Equipment", "major": false, "requires_open": true},
		{"id": "sell_equipment", "label": "Sell Equipment", "major": false, "requires_open": true},
		{"id": "commission", "label": "Commission Equipment", "major": false, "requires_open": true},
	],
	"guild": [
		{"id": "hire_specialists", "label": "Hire Specialists", "major": false, "requires_open": true},
		{"id": "guild_services", "label": "Guild Services", "major": false, "requires_open": true},
	],
	"market": [
		{"id": "buy_equipment", "label": "Buy Equipment", "major": false, "requires_open": true},
		{"id": "sell_equipment", "label": "Sell Equipment", "major": false, "requires_open": true},
		{"id": "hire_hirelings", "label": "Hire Hirelings", "major": false, "requires_open": true},
		{"id": "gather_info", "label": "Gather Information (4 hours)", "major": true, "requires_open": true},
		# Phase 10B.2 Wave 2 — Trade block mercantile activities.
		{"id": "buy_merchandise", "label": "Buy Merchandise", "major": false, "requires_open": true},
		{"id": "sell_merchandise", "label": "Sell Merchandise", "major": false, "requires_open": true},
		{"id": "persuade_merchants", "label": "Persuade Merchants", "major": false, "requires_open": true},
		{"id": "solicit_merchants", "label": "Solicit Merchants (1-3 weeks)", "major": true, "requires_open": true},
		{"id": "locate_merchandise", "label": "Locate Merchandise (1 hour)", "major": false, "requires_open": true},
		{"id": "accept_shipping_contract", "label": "Accept Shipping Contract", "major": false, "requires_open": true},
	],
	# Phase 10B.2 Wave 2 — town_square is the Class V/VI alias for market per §2.3.
	# Hosts the same mercantile activities; the eligibility tag `at_market_poi`
	# matches both POI types.
	"town_square": [
		{"id": "buy_merchandise", "label": "Buy Merchandise", "major": false, "requires_open": true},
		{"id": "sell_merchandise", "label": "Sell Merchandise", "major": false, "requires_open": true},
		{"id": "persuade_merchants", "label": "Persuade Merchants", "major": false, "requires_open": true},
		{"id": "solicit_merchants", "label": "Solicit Merchants (1-3 weeks)", "major": true, "requires_open": true},
		{"id": "locate_merchandise", "label": "Locate Merchandise (1 hour)", "major": false, "requires_open": true},
		{"id": "accept_shipping_contract", "label": "Accept Shipping Contract", "major": false, "requires_open": true},
	],
}


# ---------------------------------------------------------------------------
# Phase 10B.2 Wave 2 — mercantile activity routing.
# ---------------------------------------------------------------------------

const MERCANTILE_ACTIVITY_IDS: Array = [
	"buy_merchandise",
	"sell_merchandise",
	"persuade_merchants",
	"solicit_merchants",
	"locate_merchandise",
	"accept_shipping_contract",
]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Populates the activity panel for the given PoI.
func show_for_poi(poi: Dictionary, is_open: bool = true) -> void:
	_poi = poi
	_is_open = is_open
	_rebuild()
	visible = true


## Hides the activity panel.
func hide_panel() -> void:
	_poi = {}
	visible = false
	# Clear children.
	for child in get_children():
		child.queue_free()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	# Clear existing entries.
	for child in get_children():
		child.queue_free()

	var poi_type: String = _poi.get("type", "")
	var poi_name: String = _poi.get("name", "Location")

	# Header.
	var header := Label.new()
	header.text = poi_name
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	add_child(header)

	# Status.
	if not _is_open:
		var closed_label := Label.new()
		closed_label.text = "Closed until dawn"
		closed_label.add_theme_font_size_override("font_size", 12)
		closed_label.add_theme_color_override("font_color", Color(0.7, 0.4, 0.3))
		add_child(closed_label)

	# Exit Settlement is offered at any PoI flagged is_entry_exit: true,
	# independent of PoI type (per gdd-settlement-exploration-ui.md v2 §4.1).
	var activities: Array = []
	if _poi.get("is_entry_exit", false):
		activities.append({"id": "exit_settlement", "label": "Exit Settlement",
			"major": false, "requires_open": false})

	# Activity buttons.
	activities.append_array(ACTIVITIES.get(poi_type, []))
	if activities.is_empty():
		var no_act := Label.new()
		no_act.text = "No activities available."
		no_act.add_theme_font_size_override("font_size", 12)
		no_act.add_theme_color_override("font_color", Color(0.6, 0.55, 0.48))
		add_child(no_act)
		return

	for activity in activities:
		var btn := Button.new()
		btn.text = activity["label"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		# Disable if requires open and is closed.
		if activity.get("requires_open", false) and not _is_open:
			btn.disabled = true
			btn.tooltip_text = "This activity requires the establishment to be open."

		# Major activity indicator.
		if activity.get("major", false):
			btn.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))

		btn.pressed.connect(_on_activity_pressed.bind(activity["id"]))
		add_child(btn)

	# Always offer a way back out of the activity panel without committing to
	# an activity. Hides the panel; the settlement menu (with the full PoI
	# list) remains visible behind so the player can pick a new destination.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	add_child(spacer)

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	leave_btn.pressed.connect(hide_panel)
	add_child(leave_btn)


func _on_activity_pressed(activity_id: String) -> void:
	match activity_id:
		"exit_settlement":
			exit_settlement_requested.emit()
		"buy_equipment", "sell_equipment", "commission":
			shop_requested.emit(_poi)
		"hire_henchmen":
			hiring_requested.emit(_poi)
		"hire_specialists":
			specialist_hiring_requested.emit(_poi)
		_:
			# Phase 10B.2 Wave 2: route mercantile launchers to the trade panel.
			if activity_id in MERCANTILE_ACTIVITY_IDS:
				mercantile_requested.emit(activity_id, _poi)
			else:
				activity_requested.emit(activity_id, _poi)
