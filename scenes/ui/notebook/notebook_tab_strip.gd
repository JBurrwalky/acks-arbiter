extends HBoxContainer

## NotebookTabStrip — right-edge vertical-label tab strip for the Management
## Notebook. Two-column 5+3 layout per gdd-management-notebook.md §3.3.5:
##   Primary (innermost, closest to page): Character, Inventory, Party,
##     Henchmen, Troops
##   Secondary (outermost, screen edge): Domain, Journal, Quests
##
## Tabs render their labels rotated 90° clockwise so they read top-to-bottom
## from the player's perspective. Active tab uses Theme variant
## NotebookActiveTab (vellum, merges with page); inactive tabs use
## NotebookInactiveTab (leather binding color).


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the player clicks any tab. Notebook root translates this into
## open(tab_id) for a different tab or close() for the active tab (toggle
## semantics per gdd-ui-architecture.md §3.7).
signal tab_clicked(tab_id: String)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Tab id → display label, in primary-column order then secondary-column.
const TAB_ORDER := [
	["character", "Character"],
	["inventory", "Inventory"],
	["party", "Party"],
	["henchmen", "Henchmen"],
	["troops", "Troops"],
	["domain", "Domain"],
	["journal", "Journal"],
	["quests", "Quests"],
]

## Number of tabs that go in the primary (innermost) column.
const PRIMARY_COLUMN_COUNT := 5

const COLUMN_WIDTH := 64
const TAB_HEIGHT := 120
const TAB_LABEL_FONT_SIZE := 14


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _active_tab_id: String = ""

## tab_id -> Button (the tab button in the strip).
var _tab_buttons: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Visually mark [param tab_id] as the active tab. Other tabs revert to
## inactive styling. Empty string clears all active highlights.
func set_active_tab(tab_id: String) -> void:
	if _active_tab_id == tab_id:
		return
	_active_tab_id = tab_id
	for id in _tab_buttons.keys():
		_apply_tab_style(_tab_buttons[id], id == tab_id)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build() -> void:
	# Primary column (closest to page area, leftmost in the strip per
	# gdd-management-notebook.md §3.3.5).
	var primary_col := _make_column()
	add_child(primary_col)
	for i in range(PRIMARY_COLUMN_COUNT):
		if i >= TAB_ORDER.size():
			break
		var entry: Array = TAB_ORDER[i]
		primary_col.add_child(_make_tab_button(entry[0], entry[1]))

	# Secondary column (outermost; further from page).
	var secondary_col := _make_column()
	add_child(secondary_col)
	for i in range(PRIMARY_COLUMN_COUNT, TAB_ORDER.size()):
		var entry: Array = TAB_ORDER[i]
		secondary_col.add_child(_make_tab_button(entry[0], entry[1]))


func _make_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return col


func _make_tab_button(tab_id: String, label_text: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(COLUMN_WIDTH, TAB_HEIGHT)
	btn.size_flags_horizontal = Control.SIZE_FILL
	btn.size_flags_vertical = Control.SIZE_FILL
	# Strip the default Button text — we render the label as a rotated child
	# Label so it reads top-to-bottom.
	btn.text = ""
	btn.tooltip_text = label_text
	btn.flat = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = true

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", TAB_LABEL_FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position = Vector2(COLUMN_WIDTH * 0.5, TAB_HEIGHT * 0.5)
	# 90° clockwise (positive in Godot screen-space rotation) so the text
	# reads top-to-bottom — natural for a right-edge notebook tab.
	label.rotation = PI * 0.5
	label.pivot_offset = Vector2.ZERO
	# Center the rotated label by translating it. After rotating around its
	# own origin, the label's logical width becomes its rendered height; we
	# offset back so the visible glyph cluster sits in the button center.
	# The Label's set_anchors_preset(CENTER) plus position above already
	# anchors it. The pivot at (0,0) and our position (COLUMN_WIDTH/2, ...)
	# place the rotation origin centered; minimal further offset is needed
	# because we autosize the label.
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(label)

	btn.pressed.connect(_on_tab_pressed.bind(tab_id))
	_tab_buttons[tab_id] = btn
	_apply_tab_style(btn, false)
	return btn


func _apply_tab_style(btn: Button, is_active: bool) -> void:
	btn.theme_type_variation = "NotebookActiveTab" if is_active else "NotebookInactiveTab"


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _on_tab_pressed(tab_id: String) -> void:
	tab_clicked.emit(tab_id)
