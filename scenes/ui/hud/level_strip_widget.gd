extends PanelContainer

## LevelStripWidget — per-level HUD for multi-level dungeons.
##
## One row per explored level, sorted top-down (highest level at top).
## Each row shows: level label, party count, enemy count, focus marker.
## Clicking a row sets the VisibilityManager's focus level.
##
## Instantiated by DungeonMapRenderer3D and added under its DungeonHUD
## CanvasLayer. Listens to VisibilityManager.focus_level_changed for restyle,
## and to EventBus signals for rebuild triggers (party composition, movement).
##
## See gdd-voxel-tactical-architecture.md §16.4.


signal level_row_clicked(level: int)


const ROW_HEIGHT: int = 28
const WIDGET_WIDTH: int = 180

const FOCUS_BG_COLOR := Color(0.22, 0.48, 0.72, 0.95)
const ROW_BG_COLOR := Color(0.10, 0.10, 0.12, 0.85)
const PANEL_BG_COLOR := Color(0.05, 0.05, 0.07, 0.88)
const PANEL_BORDER_COLOR := Color(0.30, 0.30, 0.35, 1.0)
const ENEMY_HIGHLIGHT_COLOR := Color(1.0, 0.5, 0.4, 1.0)
const ENEMY_ZERO_COLOR := Color(0.5, 0.5, 0.5, 1.0)


var _visibility_manager: VisibilityManager = null
var _renderer: Node = null
var _voxel_map: VoxelMapData = null

var _list: VBoxContainer = null
var _row_buttons: Dictionary = {}


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -float(WIDGET_WIDTH) - 10.0
	offset_right = -10.0
	offset_top = 20.0
	offset_bottom = 20.0

	var bg := StyleBoxFlat.new()
	bg.bg_color = PANEL_BG_COLOR
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.border_color = PANEL_BORDER_COLOR
	bg.content_margin_left = 6
	bg.content_margin_top = 6
	bg.content_margin_right = 6
	bg.content_margin_bottom = 6
	bg.corner_radius_top_left = 4
	bg.corner_radius_top_right = 4
	bg.corner_radius_bottom_left = 4
	bg.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", bg)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	add_child(_list)


func setup(vis: VisibilityManager, renderer: Node, vmap: VoxelMapData) -> void:
	_visibility_manager = vis
	_renderer = renderer
	_voxel_map = vmap
	if _list == null:
		_build_ui()
	if _visibility_manager != null:
		if not _visibility_manager.focus_level_changed.is_connected(_on_focus_level_changed):
			_visibility_manager.focus_level_changed.connect(_on_focus_level_changed)
	if not EventBus.party_member_joined.is_connected(_on_party_changed):
		EventBus.party_member_joined.connect(_on_party_changed)
	if not EventBus.party_member_left.is_connected(_on_party_changed):
		EventBus.party_member_left.connect(_on_party_changed)
	refresh()


func refresh() -> void:
	if _list == null or _visibility_manager == null:
		return

	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_row_buttons.clear()

	var levels: Array = _visibility_manager.explored_levels.duplicate()
	levels.sort()
	levels.reverse()

	var party_counts: Dictionary = _count_party_per_level()
	var enemy_counts: Dictionary = {}
	if _renderer != null and _renderer.has_method("get_enemy_levels_snapshot"):
		enemy_counts = _renderer.get_enemy_levels_snapshot()

	for lvl_variant in levels:
		var lvl: int = int(lvl_variant)
		var p: int = int(party_counts.get(lvl, 0))
		var e: int = int(enemy_counts.get(lvl, 0))
		var row := _create_row(lvl, p, e)
		_list.add_child(row)
		_row_buttons[lvl] = row


func _count_party_per_level() -> Dictionary:
	var counts: Dictionary = {}
	if _visibility_manager == null:
		return counts
	for pos in _visibility_manager.party_positions:
		var lvl: int = pos.z
		counts[lvl] = int(counts.get(lvl, 0)) + 1
	return counts


func _create_row(level: int, party_count: int, enemy_count: int) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(WIDGET_WIDTH - 12, ROW_HEIGHT)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_row_pressed.bind(level))

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)

	var lbl_level := Label.new()
	lbl_level.text = "L%d" % level
	lbl_level.custom_minimum_size = Vector2(28, 0)
	hb.add_child(lbl_level)

	hb.add_child(VSeparator.new())

	var lbl_party := Label.new()
	lbl_party.text = "P:%d" % party_count
	lbl_party.custom_minimum_size = Vector2(32, 0)
	hb.add_child(lbl_party)

	var lbl_enemy := Label.new()
	lbl_enemy.text = "E:%d" % enemy_count
	lbl_enemy.custom_minimum_size = Vector2(32, 0)
	lbl_enemy.modulate = ENEMY_HIGHLIGHT_COLOR if enemy_count > 0 else ENEMY_ZERO_COLOR
	hb.add_child(lbl_enemy)

	var lbl_focus := Label.new()
	lbl_focus.text = "●"
	lbl_focus.custom_minimum_size = Vector2(12, 0)
	lbl_focus.visible = (level == _visibility_manager.focus_level)
	hb.add_child(lbl_focus)

	btn.add_child(hb)
	btn.set_meta("focus_marker", lbl_focus)
	_apply_row_style(btn, level == _visibility_manager.focus_level)
	return btn


func _apply_row_style(btn: Button, focused: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = FOCUS_BG_COLOR if focused else ROW_BG_COLOR
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)


func _restyle_focus() -> void:
	if _visibility_manager == null:
		return
	for lvl_variant in _row_buttons.keys():
		var lvl: int = int(lvl_variant)
		var btn: Button = _row_buttons[lvl]
		var focused := (lvl == _visibility_manager.focus_level)
		_apply_row_style(btn, focused)
		var marker = btn.get_meta("focus_marker", null)
		if marker != null:
			marker.visible = focused


func _on_row_pressed(level: int) -> void:
	level_row_clicked.emit(level)
	if _visibility_manager != null:
		_visibility_manager.set_focus_level(level)


func _on_focus_level_changed(_new_level: int) -> void:
	_restyle_focus()


func _on_party_changed(_party_id: String, _entity_id: String) -> void:
	refresh()


## Hides the widget when the scene is not a dungeon (combat/wilderness).
## Currently all instantiations are dungeon-only, so this is a future-proof stub.
func set_mode(mode: String) -> void:
	visible = (mode == "dungeon")
