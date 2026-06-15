extends Control

## Screen D: Review & Approval (gdd-campaign-creation-ui.md §6, setting-gen §11.3).
## The political/terrain map (with a view-mode toggle + legend + city markers) plus
## the side tabs (Brief / Realms / Peoples / History / Issues), the seed footer, and
## Accept / Regenerate / Watch-again. Binds CampaignReviewAssembler's payload.

signal approved
signal regenerate_requested
signal watch_again

const _MODES := [[0, "Political"], [1, "Biome"], [2, "Elevation"], [3, "Territory"], [4, "Culture"]]
const _MODE_TOOLTIPS := {
	0: "Realm ownership — each polity in its own colour; slate = unclaimed. Gold dots mark cities. Hover a hex for realm, culture, populations & settlement.",
	1: "Terrain & vegetation — plains, forest, dense forest, jungle, swamp, desert, water.",
	2: "Relief — flat, hills, mountains, water. Hover for the raw elevation value.",
	3: "Settlement tier — civilized, borderlands, wilderness.",
	4: "Cultural spread — dominant culture per hex, regardless of realm borders. Shares the political hover tooltip.",
}

var _payload: Dictionary = {}
var _polity_names: Dictionary = {}
var _map: Control
var _legend: HBoxContainer
var _brief_label: RichTextLabel
var _realms_box: VBoxContainer
var _peoples_box: VBoxContainer
var _history_label: RichTextLabel
var _issues_label: RichTextLabel
var _seed_label: Label
var _validation_label: Label
var _copy_btn: Button
var _share_token: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.10, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 22
	root.offset_top = 14
	root.offset_right = -22
	root.offset_bottom = -14
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "Your World Awaits"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.93, 0.86, 0.7))
	root.add_child(title)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	# Left column: view-mode toggle, the map, then the legend.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.5
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 6)
	left.add_child(modes)
	for entry in _MODES:
		var b := Button.new()
		b.text = str(entry[1])
		b.toggle_mode = true
		b.button_group = _shared_group()
		b.button_pressed = (int(entry[0]) == 0)
		b.tooltip_text = str(_MODE_TOOLTIPS.get(int(entry[0]), ""))
		b.pressed.connect(_on_mode.bind(int(entry[0])))
		modes.add_child(b)

	var map_panel := PanelContainer.new()
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(map_panel)
	_map = preload("res://scenes/ui/campaign_creation/political_map_view.gd").new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_child(_map)

	var legend_scroll := ScrollContainer.new()
	legend_scroll.custom_minimum_size = Vector2(0, 30)
	legend_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	legend_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(legend_scroll)
	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override("separation", 12)
	legend_scroll.add_child(_legend)

	# Right column: the data tabs + watch-again.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(330, 0)
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	var side := TabContainer.new()
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(side)
	_brief_label = _rich_tab(side, "Brief")
	_realms_box = _list_tab(side, "Realms")
	_peoples_box = _list_tab(side, "Peoples")
	_history_label = _rich_tab(side, "History")
	_issues_label = _rich_tab(side, "Issues")
	var watch := Button.new()
	watch.text = "⟲ Watch the history again"
	watch.custom_minimum_size = Vector2(0, 40)
	watch.pressed.connect(func(): watch_again.emit())
	right.add_child(watch)

	# Footer.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	root.add_child(footer)
	_seed_label = Label.new()
	_seed_label.add_theme_color_override("font_color", Color(0.82, 0.77, 0.66))
	footer.add_child(_seed_label)
	_copy_btn = Button.new()
	_copy_btn.text = "⧉ Copy"
	_copy_btn.tooltip_text = "Copy the full share code to the clipboard — paste it as a seed to reproduce this exact world."
	_copy_btn.pressed.connect(_on_copy_seed)
	footer.add_child(_copy_btn)
	_validation_label = Label.new()
	footer.add_child(_validation_label)
	footer.add_child(_h_expand())
	var regen := Button.new()
	regen.text = "↻ Regenerate world"
	regen.custom_minimum_size = Vector2(170, 44)
	regen.pressed.connect(func(): regenerate_requested.emit())
	footer.add_child(regen)
	var begin := Button.new()
	begin.text = "Begin Campaign  ▸"
	begin.custom_minimum_size = Vector2(180, 44)
	begin.add_theme_font_size_override("font_size", 18)
	begin.pressed.connect(func(): approved.emit())
	footer.add_child(begin)


func populate(payload: Dictionary) -> void:
	_payload = payload
	_polity_names = {}
	for r in payload.get("realms", []):
		_polity_names[str(r.get("id", ""))] = str(r.get("name", ""))
	_refresh()


## hexes + replay palette + city markers + the full realm name/liege maps (from
## list_polities) for the hover tooltip's sovereign resolution and the legend.
func bind_map(ordered_hexes: Array, palette: Array, settlements: Array, polities: Array = []) -> void:
	if _map == null:
		return
	var names := {}
	var lieges := {}
	for p in polities:
		var pid := str(p.get("id", ""))
		names[pid] = str(p.get("name", pid)) if str(p.get("name", "")) != "" else pid
		lieges[pid] = str(p.get("liege_id", ""))
	if not names.is_empty():
		_polity_names = names   # fuller than the top-realms map from populate()
		_map.set_polity_meta(names, lieges)
	_map.bind(ordered_hexes, palette)
	_map.set_settlements(settlements)
	_refresh_legend()


func _on_mode(mode: int) -> void:
	if _map != null:
		_map.set_mode(mode)
	_refresh_legend()


func _refresh_legend() -> void:
	if _legend == null or _map == null:
		return
	for c in _legend.get_children():
		c.queue_free()
	var entries: Array = _map.legend_entries(_polity_names)
	var shown := 0
	for e in entries:
		if shown >= 10:
			break
		shown += 1
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 4)
		var sw := ColorRect.new()
		sw.color = e["color"]
		sw.custom_minimum_size = Vector2(16, 16)
		item.add_child(sw)
		var lab := Label.new()
		lab.text = str(e["label"])
		lab.add_theme_color_override("font_color", Color(0.84, 0.79, 0.69))
		item.add_child(lab)
		_legend.add_child(item)


func _refresh() -> void:
	if _brief_label == null:
		return
	_brief_label.text = str(_payload.get("brief", "—"))
	_history_label.text = str(_payload.get("timeline", "—"))
	# A custom-parameter world's share token is a long base64 string; show a
	# truncated form (full code in the tooltip) and clip it, so it can't inflate
	# the footer and shove the whole right column off-screen.
	var token := str(_payload.get("share_token", _payload.get("seed", "?")))
	_share_token = token
	var shown := token if token.length() <= 30 else token.substr(0, 28) + "…"
	_seed_label.text = "Seed: %s" % shown
	_seed_label.clip_text = true
	_seed_label.tooltip_text = "Full share code (reproduces this exact world):\n%s" % token
	var v: Dictionary = _payload.get("validation", {})
	var verr := int(v.get("errors", 0))
	_validation_label.text = "  ✓ valid" if verr == 0 else "  ⚠ %d issue(s)" % verr
	_validation_label.add_theme_color_override("font_color",
		Color(0.5, 0.8, 0.5) if verr == 0 else Color(0.9, 0.7, 0.3))
	_issues_label.text = str(v.get("report", "No validation report.")) if verr > 0 \
		else "✓ No mechanical issues — the world is internally consistent."

	for c in _realms_box.get_children():
		c.queue_free()
	for r in _payload.get("realms", []):
		var line := Label.new()
		line.text = "%s — %s, %s (%s L%d)" % [str(r.get("name", "?")), str(r.get("title", "")),
			str(r.get("alignment", "")), str(r.get("ruler_class", "")).replace("_", " "),
			int(r.get("ruler_level", 0))]
		line.add_theme_color_override("font_color", Color(0.86, 0.81, 0.71))
		_realms_box.add_child(line)

	for c in _peoples_box.get_children():
		c.queue_free()
	for p in _payload.get("peoples", []):
		var line := Label.new()
		line.text = "• %s" % str(p.get("label", "?"))
		line.add_theme_color_override("font_color", Color(0.86, 0.81, 0.71))
		_peoples_box.add_child(line)

	_refresh_legend()


# --- helpers -----------------------------------------------------------------

var _mode_group: ButtonGroup

func _shared_group() -> ButtonGroup:
	if _mode_group == null:
		_mode_group = ButtonGroup.new()
	return _mode_group


func _rich_tab(tabs: TabContainer, title: String) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.name = title
	# fit_content=false so the label stays the size of the tab area (a long
	# timeline would otherwise inflate its minimum size and blow the panel up);
	# scroll_active then renders an internal scrollbar when the content overflows.
	rt.fit_content = false
	rt.scroll_active = true
	rt.add_theme_color_override("default_color", Color(0.84, 0.79, 0.69))
	tabs.add_child(rt)
	return rt


func _list_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	tabs.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	vb.offset_left = 8
	vb.offset_top = 8
	scroll.add_child(vb)
	return vb


func _h_expand() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func share_token() -> String:
	return str(_payload.get("share_token", ""))


## Copy the full share code to the clipboard, with brief in-button feedback.
func _on_copy_seed() -> void:
	if _share_token == "":
		return
	DisplayServer.clipboard_set(_share_token)
	if _copy_btn != null:
		_copy_btn.text = "✓ Copied"
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(_copy_btn):
			_copy_btn.text = "⧉ Copy"
