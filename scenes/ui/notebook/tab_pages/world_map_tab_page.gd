extends "res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd"

## World Map tab (M3-c; gdd-setting-runtime-materialization §15.4). The 24-mile strategic
## map of the generated world, read from the frozen `setting_*` tables — the world AS
## GENERATED (a live realm sim would refresh it at M5). Reuses the campaign-creation review
## screen's PoliticalMapView widget with the SAME layer toggle (Political / Biome / Elevation
## / Territory / Culture) + Sovereigns view, and a ranked legend that refreshes per layer.
##
## Only meaningful for `campaign_origin='generated'`; a fixture campaign has no `setting_hexes`,
## so it shows an empty state instead.

const PoliticalMapViewScript := preload("res://scenes/ui/campaign_creation/political_map_view.gd")

## Layer toggle (matches ScreenReview): [mode_int, label]. Ints map to PoliticalMapView.Mode.
const _MODES := [[0, "Political"], [1, "Biome"], [2, "Elevation"], [3, "Territory"], [4, "Culture"]]
const _MODE_TOOLTIPS := {
	0: "Realm ownership — each polity its own colour; slate = unclaimed. Gold dots mark cities. Hover a hex for realm, culture, populations & settlement.",
	1: "Terrain & vegetation — plains, forest, dense forest, jungle, swamp, desert, water.",
	2: "Relief — flat, hills, mountains, water.",
	3: "Settlement tier — civilized, borderlands, wilderness.",
	4: "Cultural spread — dominant culture per hex, regardless of realm borders.",
}
const _LEGEND_CAP_POLITICAL := 14   # Political can list many realms; Biome/Elev/Terr/Culture are short.

var _map = null                       # the PoliticalMapView instance (dynamic calls)
var _legend: VBoxContainer = null
var _polity_names: Dictionary = {}
var _current_mode: int = 0
var _mode_group: ButtonGroup = null


func _build_content() -> void:
	var cid := String(GameState.campaign_id)
	if cid.is_empty() or String(CampaignRepository.get_campaign(cid).get("campaign_origin", "")) != "generated":
		_add_empty_state(
			"World Map",
			"The strategic world map is available for worlds you generate. Start a new campaign "
			+ "with “Generate World” to chart its realms, rivers, and cities.")
		return

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# Polity metadata (names / liege chain / tier) — drives tooltips, border weight, legend.
	var polities: Array = SettingRepository.list_polities(cid)
	var lieges := {}
	var tiers := {}
	_polity_names = {}
	for p in polities:
		var pid := str(p.get("id", ""))
		_polity_names[pid] = str(p.get("name", pid)) if str(p.get("name", "")) != "" else pid
		lieges[pid] = str(p.get("liege_id", ""))
		tiers[pid] = int(p.get("tier_index", 0))

	# Header.
	var title := Label.new()
	var world := String(CampaignRepository.get_campaign(cid).get("world_name", ""))
	title.text = world if not world.is_empty() else "The Known World"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.12, 0.09, 0.05))
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "24-mile strategic map · %d realms" % _polity_names.size()
	subtitle.add_theme_color_override("font_color", Color(0.30, 0.24, 0.16))
	root.add_child(subtitle)

	# Body: left column (layer toggle + map) | legend column.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)

	# Layer toggle: mutually-exclusive mode buttons + the Sovereigns checkbox.
	_mode_group = ButtonGroup.new()
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 6)
	left.add_child(modes)
	for entry in _MODES:
		var b := Button.new()
		b.text = str(entry[1])
		b.toggle_mode = true
		b.button_group = _mode_group
		b.button_pressed = (int(entry[0]) == 0)
		b.tooltip_text = str(_MODE_TOOLTIPS.get(int(entry[0]), ""))
		b.pressed.connect(_on_mode.bind(int(entry[0])))
		modes.add_child(b)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(14, 0)
	modes.add_child(spacer)
	var sov := CheckButton.new()
	sov.text = "Sovereigns"
	sov.tooltip_text = "Political map: off shows every domain's own colour & borders; on colours each hex by the top realm of its vassalage chain, so a realm and its vassals read as one power."
	sov.toggled.connect(_on_sovereign_toggled)
	modes.add_child(sov)

	# Map (expands).
	var map_panel := PanelContainer.new()
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(map_panel)
	_map = PoliticalMapViewScript.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_child(_map)
	# Same bind order as ScreenReview.bind_map (set_polity_meta before bind).
	_map.set_polity_meta(_polity_names, lieges, tiers)
	_map.bind(SettingRepository.list_hexes(cid), SettingRepository.list_replay_palette(cid))
	_map.set_settlements(SettingRepository.list_settlements(cid))
	_map.set_rivers(SettingRepository.list_river_edges(cid))

	# Legend column (refreshes per layer; scrolls when a layer has many entries).
	var legend_col := VBoxContainer.new()
	legend_col.custom_minimum_size = Vector2(200, 0)
	legend_col.add_theme_constant_override("separation", 6)
	body.add_child(legend_col)
	var legend_title := Label.new()
	legend_title.text = "Map Key"
	legend_title.add_theme_font_size_override("font_size", 16)
	legend_title.add_theme_color_override("font_color", Color(0.12, 0.09, 0.05))
	legend_col.add_child(legend_title)
	var legend_scroll := ScrollContainer.new()
	legend_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	legend_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	legend_col.add_child(legend_scroll)
	_legend = VBoxContainer.new()
	_legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_legend.add_theme_constant_override("separation", 6)
	legend_scroll.add_child(_legend)
	_refresh_legend()


func _on_mode(mode: int) -> void:
	_current_mode = mode
	if _map != null:
		_map.set_mode(mode)
	_refresh_legend()


func _on_sovereign_toggled(on: bool) -> void:
	if _map != null:
		_map.set_sovereign_view(on)
	_refresh_legend()


## Rebuild the legend from the map's current layer. Political is capped (+N more); the short
## layers (biome/elevation/territory/culture) show every entry so a low-coverage key isn't
## silently dropped.
func _refresh_legend() -> void:
	if _legend == null or _map == null:
		return
	for c in _legend.get_children():
		c.queue_free()
	var entries: Array = _map.legend_entries(_polity_names)
	var cap: int = _LEGEND_CAP_POLITICAL if _current_mode == 0 else entries.size()
	for i in entries.size():
		if i >= cap:
			var more := Label.new()
			more.text = "+%d more…" % (entries.size() - cap)
			more.add_theme_color_override("font_color", Color(0.40, 0.34, 0.24))
			_legend.add_child(more)
			break
		var e = entries[i]
		var item := HBoxContainer.new()
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.add_theme_constant_override("separation", 6)
		var sw := ColorRect.new()
		sw.color = e["color"]
		sw.custom_minimum_size = Vector2(15, 15)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(sw)
		var lab := Label.new()
		lab.text = str(e["label"])
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.clip_text = true
		lab.tooltip_text = str(e["label"])
		lab.add_theme_color_override("font_color", Color(0.20, 0.16, 0.10))
		item.add_child(lab)
		_legend.add_child(item)
