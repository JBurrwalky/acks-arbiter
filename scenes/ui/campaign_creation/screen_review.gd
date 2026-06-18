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
var _polities: Array = []           # full setting_polities rows (for the Vassalage tab)
var _domains: Array = []            # setting_domains rows — the Phase 5 intra-realm vassal tree
var _present_ids: Dictionary = {}   # polity_id -> true for realms still holding territory
var _map: Control
var _current_mode: int = 0    # mirrors the map view's mode (0 = Political)
var _legend: VBoxContainer
var _brief_label: RichTextLabel
var _realms_box: VBoxContainer
var _vassalage_tree: Tree          # collapsible per-liege tree (war-vassals + domain decomposition)
var _peoples_box: VBoxContainer
var _history_log: RichTextLabel       # the structured event-log body (History tab)
var _history_filter: OptionButton     # "All realms" + one entry per present-day sovereign
var _history_filter_ids: Array = []   # parallel to the filter items; "" = master log
var _history_export_btn: Button
var _liege_by_id: Dictionary = {}     # polity_id -> liege_id (present-day, for sovereign-of)
var _issues_label: RichTextLabel
var _seed_label: Label
var _validation_label: Label
var _copy_btn: Button
var _share_token: String = ""

# Event log (History tab). Loaded via set_event_log(); rendered per-sovereign or as a
# master log. Dead-realm names come from setting_fallen_polities (toponym roots).
var _events: Array = []
var _fallen_names: Dictionary = {}    # polity_id -> "the Old <root>"


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

	# Left column: view-mode toggle + the map. (The legend moved to its own vertical
	# column; the data panel now expands into the space the map drawing leaves.)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
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
	# Vassal ⇄ Sovereign view toggle (affects the Political map: off = every domain
	# its own colour; on = colour by the top realm of each vassalage chain).
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(14, 0)
	modes.add_child(spacer)
	var sov := CheckButton.new()
	sov.text = "Sovereigns"
	sov.tooltip_text = "Political map: off shows every domain's own colour & borders (vassal view); on colours each hex by the top realm of its vassalage chain, so a realm and its vassals read as one power."
	sov.toggled.connect(_on_sovereign_toggled)
	modes.add_child(sov)

	var map_panel := PanelContainer.new()
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(map_panel)
	_map = preload("res://scenes/ui/campaign_creation/political_map_view.gd").new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_child(_map)

	# Legend column: the map key, VERTICAL alongside the map (was a horizontal strip
	# under it). Fixed width; scrolls vertically when a world has many realms.
	var legend_col := VBoxContainer.new()
	legend_col.custom_minimum_size = Vector2(330, 0)
	legend_col.add_theme_constant_override("separation", 6)
	body.add_child(legend_col)
	var legend_title := Label.new()
	legend_title.text = "Map Key"
	legend_title.add_theme_color_override("font_color", Color(0.74, 0.69, 0.6))
	legend_col.add_child(legend_title)
	var legend_scroll := ScrollContainer.new()
	legend_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	legend_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	legend_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	legend_col.add_child(legend_scroll)
	_legend = VBoxContainer.new()
	_legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_legend.add_theme_constant_override("separation", 8)
	legend_scroll.add_child(_legend)

	# Right column: the data tabs + watch-again — now EXPANDS to fill the space the
	# square-ish map drawing leaves, so the brief/realms/peoples text isn't cramped.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.6
	right.custom_minimum_size = Vector2(360, 0)
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	var side := TabContainer.new()
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(side)
	_brief_label = _rich_tab(side, "Brief")
	_realms_box = _list_tab(side, "Realms")
	_vassalage_tree = _tree_tab(side, "Vassalage")
	_peoples_box = _list_tab(side, "Peoples")
	_build_history_tab(side)
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
func bind_map(ordered_hexes: Array, palette: Array, settlements: Array, polities: Array = [], rivers: Array = []) -> void:
	if _map == null:
		return
	_polities = polities
	# Present-day realms = those still holding at least one hex at game-start (fallen
	# realms own none). Scopes the Vassalage tab to the living political map.
	_present_ids = {}
	for h in ordered_hexes:
		var o := str(h.get("owner_polity_id", ""))
		if o != "":
			_present_ids[o] = true
	var names := {}
	var lieges := {}
	var tiers := {}
	_liege_by_id = {}
	for p in polities:
		var pid := str(p.get("id", ""))
		names[pid] = str(p.get("name", pid)) if str(p.get("name", "")) != "" else pid
		lieges[pid] = str(p.get("liege_id", ""))
		tiers[pid] = int(p.get("tier_index", 0))
		_liege_by_id[pid] = str(p.get("liege_id", ""))
	if not names.is_empty():
		_polity_names = names   # fuller than the top-realms map from populate()
		_map.set_polity_meta(names, lieges, tiers)
	_map.bind(ordered_hexes, palette)
	_map.set_settlements(settlements)
	_map.set_rivers(rivers)
	_refresh_legend()
	_refresh_realms()    # liege map now known → drop vassals from the Realms tab
	_refresh_vassalage()
	_refresh_history()   # sovereigns now known → rebuild the History filter + log


## The Phase 5 vassal tree (setting_domains). Call after bind_map so _present_ids
## and _polities are populated; rebuilds the Vassalage tab with the domain layer.
func set_domains(domains: Array) -> void:
	_domains = domains
	_refresh_vassalage()


func _on_mode(mode: int) -> void:
	_current_mode = mode
	if _map != null:
		_map.set_mode(mode)
	_refresh_legend()


func _on_sovereign_toggled(on: bool) -> void:
	if _map != null:
		_map.set_sovereign_view(on)
	_refresh_legend()


func _refresh_legend() -> void:
	if _legend == null or _map == null:
		return
	for c in _legend.get_children():
		c.queue_free()
	var entries: Array = _map.legend_entries(_polity_names)
	# Political can list hundreds of realms, so cap it (the scroll container handles
	# the rest) with a "+N more" note. Biome/elevation/territory/culture are short —
	# show every entry so a low-coverage culture isn't silently dropped from the key.
	var cap: int = 12 if _current_mode == 0 else entries.size()
	for i in entries.size():
		if i >= cap:
			var more := Label.new()
			more.text = "+%d more…" % (entries.size() - cap)
			more.add_theme_color_override("font_color", Color(0.62, 0.58, 0.5))
			_legend.add_child(more)
			break
		var e = entries[i]
		var item := HBoxContainer.new()
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.add_theme_constant_override("separation", 6)
		var sw := ColorRect.new()
		sw.color = e["color"]
		sw.custom_minimum_size = Vector2(16, 16)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(sw)
		var lab := Label.new()
		lab.text = str(e["label"])
		# Long realm names clip in the narrow vertical key; full name on hover.
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.clip_text = true
		lab.tooltip_text = str(e["label"])
		lab.add_theme_color_override("font_color", Color(0.84, 0.79, 0.69))
		item.add_child(lab)
		_legend.add_child(item)


## Vassalage tab: an indented liege→vassal forest of the present-day realms. Roots are
## sovereigns (no present liege); each realm's vassals nest beneath it, deepest tier
## first. Built from list_polities' liege_id, scoped to realms that still hold territory.
## A unified collapsible feudal tree (req D), default ALL collapsed: roots are
## sovereigns, each expanding to its war-vassal/protectorate polities AND its own
## crownland's domain decomposition (setting_domains, Phase 5). Domain nodes expand
## to their sub-domains. War-vassalage lives in setting_polities (liege_id); the
## intra-realm Duchy→County tree lives in setting_domains — this view fuses both.
func _refresh_vassalage() -> void:
	if _vassalage_tree == null:
		return
	_vassalage_tree.clear()
	var root := _vassalage_tree.create_item()   # hidden root (hide_root)
	# --- polity (war-vassalage) maps ---
	var by_id := {}
	for p in _polities:
		by_id[str(p.get("id", ""))] = p
	var pol_kids := {}    # liege polity_id -> [vassal polity_id, …]
	var roots: Array = []
	for p in _polities:
		var pid := str(p.get("id", ""))
		if pid == "" or not bool(_present_ids.get(pid, false)):
			continue
		var liege := str(p.get("liege_id", ""))
		if liege != "" and bool(_present_ids.get(liege, false)) and by_id.has(liege):
			if not pol_kids.has(liege):
				pol_kids[liege] = []
			pol_kids[liege].append(pid)
		else:
			roots.append(pid)   # sovereign, or liege fell / isn't a present realm
	# --- domain (intra-realm decomposition) maps ---
	var dom_top := {}        # polity_id -> [domain rows with no liege domain]
	var dom_kids := {}       # liege_domain_id -> [domain rows]
	for d in _domains:
		var dp := str(d.get("polity_id", ""))
		if not bool(_present_ids.get(dp, false)):
			continue
		var dl := str(d.get("liege_domain_id", ""))
		if dl == "":
			if not dom_top.has(dp):
				dom_top[dp] = []
			dom_top[dp].append(d)
		else:
			if not dom_kids.has(dl):
				dom_kids[dl] = []
			dom_kids[dl].append(d)
	if roots.is_empty():
		var none := _vassalage_tree.create_item(root)
		none.set_text(0, "No present-day realms.")
		none.set_custom_color(0, Color(0.7, 0.66, 0.58))
		return
	roots.sort_custom(func(a, b): return int(by_id.get(a, {}).get("tier_index", 0)) > int(by_id.get(b, {}).get("tier_index", 0)))
	var seen := {}
	for rid in roots:
		_add_polity_item(root, rid, by_id, pol_kids, seen, dom_top, dom_kids)


func _add_polity_item(parent: TreeItem, pid: String, by_id: Dictionary,
		pol_kids: Dictionary, seen: Dictionary, dom_top: Dictionary, dom_kids: Dictionary) -> void:
	if seen.has(pid):     # cycle guard — a liege loop would otherwise recurse forever
		return
	seen[pid] = true
	var item := _vassalage_tree.create_item(parent)
	item.set_text(0, _vassal_label(by_id.get(pid, {}), pid))
	item.set_custom_color(0, Color(0.90, 0.85, 0.74))
	item.collapsed = true
	# This polity's own crownland, decomposed into its vassal domains (Phase 5).
	for d in _sorted_domains(dom_top.get(pid, [])):
		_add_domain_item(item, d, dom_kids)
	# Its war-vassal / protectorate polities (each its own realm).
	var ck: Array = pol_kids.get(pid, [])
	ck.sort_custom(func(a, b): return int(by_id.get(a, {}).get("tier_index", 0)) > int(by_id.get(b, {}).get("tier_index", 0)))
	for cid in ck:
		_add_polity_item(item, cid, by_id, pol_kids, seen, dom_top, dom_kids)


func _add_domain_item(parent: TreeItem, dom: Dictionary, dom_kids: Dictionary) -> void:
	var item := _vassalage_tree.create_item(parent)
	item.set_text(0, _domain_label(dom))
	item.set_custom_color(0, Color(0.78, 0.74, 0.66))
	item.collapsed = true
	for c in _sorted_domains(dom_kids.get(str(dom.get("id", "")), [])):
		_add_domain_item(item, c, dom_kids)


## Highest tier first, then id — a stable, readable order within a liege.
func _sorted_domains(rows: Array) -> Array:
	var out: Array = rows.duplicate()
	out.sort_custom(func(a, b):
		var ta := int(a.get("tier_index", 0))
		var tb := int(b.get("tier_index", 0))
		if ta != tb:
			return ta > tb
		return str(a.get("id", "")) < str(b.get("id", "")))
	return out


func _domain_label(d: Dictionary) -> String:
	var nm := str(d.get("realm_name", ""))
	if nm == "":
		nm = str(d.get("title", "Domain"))
	var meta: Array = []
	var title := str(d.get("title", ""))
	if title != "":
		meta.append(title)
	var rc := str(d.get("ruler_class", "")).replace("_", " ")
	if rc != "":
		var lvl := int(d.get("ruler_level", 0))
		meta.append("%s L%d" % [rc, lvl] if lvl > 0 else rc)
	var fam := int(d.get("families", 0))
	if fam > 0:
		meta.append("%s families" % _commafy(fam))
	if meta.is_empty():
		return nm
	return "%s — %s" % [nm, ", ".join(meta)]


func _vassal_label(p: Dictionary, pid: String) -> String:
	var nm := str(p.get("name", ""))
	if nm == "":
		nm = str(_polity_names.get(pid, pid))
	var title := str(p.get("title", ""))
	var rc := str(p.get("ruler_class", "")).replace("_", " ")
	var lvl := int(p.get("ruler_level", 0))
	var meta: Array = []
	if title != "":
		meta.append(title)
	if rc != "":
		meta.append("%s L%d" % [rc, lvl] if lvl > 0 else rc)
	if meta.is_empty():
		return nm
	return "%s — %s" % [nm, ", ".join(meta)]


func _refresh() -> void:
	if _brief_label == null:
		return
	_brief_label.text = str(_payload.get("brief", "—"))
	# History tab is the structured event log, populated via set_event_log() (not the
	# pre-baked prose timeline). _refresh_history() re-renders it.
	_refresh_history()
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

	_refresh_realms()

	for c in _peoples_box.get_children():
		c.queue_free()
	for p in _payload.get("peoples", []):
		var line := Label.new()
		line.text = "• %s" % str(p.get("label", "?"))
		line.add_theme_color_override("font_color", Color(0.86, 0.81, 0.71))
		_peoples_box.add_child(line)

	_refresh_legend()


## Realms tab = SOVEREIGNS ONLY (req D): a realm with a present-day liege is a
## vassal and shows in the Vassalage tree, not here. _liege_by_id is populated by
## bind_map (from list_polities); before that (the populate() pass) it is empty and
## every realm shows, so bind_map re-runs this once the liege map is known.
func _refresh_realms() -> void:
	if _realms_box == null:
		return
	for c in _realms_box.get_children():
		c.queue_free()
	for r in _payload.get("realms", []):
		var rid := str(r.get("id", ""))
		if str(_liege_by_id.get(rid, "")) != "":
			continue   # a vassal — lives in the Vassalage tree
		var line := Label.new()
		line.text = "%s — %s, %s (%s L%d)" % [str(r.get("name", "?")), str(r.get("title", "")),
			str(r.get("alignment", "")), str(r.get("ruler_class", "")).replace("_", " "),
			int(r.get("ruler_level", 0))]
		line.add_theme_color_override("font_color", Color(0.86, 0.81, 0.71))
		_realms_box.add_child(line)


# --- History tab: structured, per-sovereign, exportable event log --------------

## The History tab is a custom page (filter row + scrolling log) rather than a plain
## _rich_tab, so it can filter the chronicle by sovereign and export it to Markdown.
func _build_history_tab(tabs: TabContainer) -> void:
	var page := VBoxContainer.new()
	page.name = "History"
	page.add_theme_constant_override("separation", 6)
	tabs.add_child(page)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	page.add_child(bar)
	var flbl := Label.new()
	flbl.text = "Realm"
	flbl.add_theme_color_override("font_color", Color(0.74, 0.69, 0.6))
	bar.add_child(flbl)
	_history_filter = OptionButton.new()
	_history_filter.tooltip_text = "Filter the chronicle to one sovereign realm (its own + its vassals' events), or show every realm."
	_history_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_filter.item_selected.connect(_on_history_filter)
	bar.add_child(_history_filter)
	_history_export_btn = Button.new()
	_history_export_btn.text = "⧉ Export"
	_history_export_btn.tooltip_text = "Copy the currently-shown chronicle to the clipboard as Markdown."
	_history_export_btn.pressed.connect(_on_export_history)
	bar.add_child(_history_export_btn)
	_history_log = RichTextLabel.new()
	_history_log.fit_content = false
	_history_log.scroll_active = true
	_history_log.bbcode_enabled = false
	_history_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_log.add_theme_color_override("default_color", Color(0.84, 0.79, 0.69))
	page.add_child(_history_log)


## Feed the History tab the raw chronicle (setting_events) + fallen-realm names so dead
## realms read as "the Old X" instead of a bare pol_id. Called by the flow on review entry.
func set_event_log(events: Array, fallen: Array = []) -> void:
	_events = events
	_fallen_names = {}
	for f in fallen:
		var pid := str(f.get("polity_id", ""))
		var root := str(f.get("toponym_root", ""))
		if pid != "" and root != "" and root != "<null>":
			_fallen_names[pid] = "the Old %s" % root
	_refresh_history()


## Rebuild the filter dropdown from present-day sovereigns (highest tier first), then
## render. Master log is index 0; each sovereign filters to its own + its vassals' events.
func _refresh_history() -> void:
	if _history_filter == null:
		return
	_history_filter.clear()
	_history_filter_ids = []
	_history_filter.add_item("All realms (master)")
	_history_filter_ids.append("")
	var sovs: Array = []
	for p in _polities:
		if str(p.get("liege_id", "")) == "" and bool(_present_ids.get(str(p.get("id", "")), false)):
			sovs.append(p)
	sovs.sort_custom(func(a, b): return int(a.get("tier_index", 0)) > int(b.get("tier_index", 0)))
	for p in sovs:
		var pid := str(p.get("id", ""))
		_history_filter.add_item(str(_polity_names.get(pid, pid)))
		_history_filter_ids.append(pid)
	_history_filter.select(0)
	_render_history_log()


func _on_history_filter(_idx: int) -> void:
	_render_history_log()


func _render_history_log() -> void:
	if _history_log == null:
		return
	var sov := _current_history_filter()
	var lines: Array = []
	for e in _events:
		if sov != "" and not _event_touches_sovereign(e, sov):
			continue
		var sentence := _event_sentence(e)
		if sentence == "":
			continue
		lines.append("~%s yr ago — %s" % [_commafy(int(e.get("year_before_start", 0))), sentence])
	if lines.is_empty():
		_history_log.text = "No recorded events yet." if sov == "" else "No recorded events for this realm."
	else:
		_history_log.text = "\n".join(lines)


func _current_history_filter() -> String:
	if _history_filter == null:
		return ""
	var idx := _history_filter.selected
	return str(_history_filter_ids[idx]) if idx >= 0 and idx < _history_filter_ids.size() else ""


## True if any polity named in the event resolves (up its present-day liege chain) to
## the given sovereign — so a war involving a vassal shows under that vassal's sovereign.
func _event_touches_sovereign(e: Dictionary, sov: String) -> bool:
	for pid in _parse_ids(e.get("polity_ids", "[]")):
		if _sovereign_of(str(pid)) == sov:
			return true
	return false


func _sovereign_of(pid: String) -> String:
	var cur := pid
	var guard := 0
	while str(_liege_by_id.get(cur, "")) != "" and guard < 32:
		cur = str(_liege_by_id[cur])
		guard += 1
	return cur


func _parse_ids(raw) -> Array:
	var parsed = JSON.parse_string(str(raw))
	return parsed if parsed is Array else []


## One human-readable chronicle line per event. Unknown types return "" (skipped).
func _event_sentence(e: Dictionary) -> String:
	var ids := _parse_ids(e.get("polity_ids", "[]"))
	var cults := _parse_ids(e.get("culture_ids", "[]"))
	var a := _name_for(str(ids[0])) if ids.size() > 0 else "a realm"
	var b := _name_for(str(ids[1])) if ids.size() > 1 else "a neighbour"
	var subject := str(cults[1]).capitalize() if cults.size() > 1 else "a subject people"
	match str(e.get("type", "")):
		"war":
			match str(e.get("summary_key", "")):
				"war.defender_held": return "%s repelled %s's invasion" % [b, a]
				"war.border": return "%s won border clashes with %s" % [a, b]
				"war.crushing": return "%s crushed %s in war" % [a, b]
				_: return "%s won a war against %s" % [a, b]
		"conquest": return "%s annexed %s" % [a, b]
		"vassalage": return "%s vassalized %s" % [a, b]
		"pillage": return "%s pillaged %s" % [a, b]
		"razing": return "%s put %s to the torch" % [a, b]
		"secession": return "%s broke away from %s" % [a, b]
		"protectorate": return "%s signed a treaty of protection with %s, joining their realms" % [a, b]
		"rebellion": return "%s rose in revolt within %s" % [subject, a]
		"rebellion_won": return "%s won their freedom from %s" % [subject, a]
		"rebellion_concession": return "%s won concessions from %s" % [subject, a]
		"rebellion_crushed": return "%s crushed a %s revolt" % [a, subject]
		"rebellion_extinguished": return "%s annihilated the %s" % [a, subject]
		"collapse_rump": return "%s fragmented, shedding its frontier" % a
		"collapse_shatter": return "%s shattered into successor states" % a
		"depopulation": return "%s collapsed into ruin" % a
		"dynasty_change": return "A new dynasty took the throne of %s" % a
		"cultural_shift": return "%s adopted %s ways" % [a, subject]
		"migration": return "A wandering people resettled the frontier"
		"founding": return "%s was founded" % a
		_: return ""


func _name_for(pid: String) -> String:
	# _polity_names stores the pid itself as a fallback for unnamed realms, so a value
	# equal to the id means "no real name" — fall through to the fallen toponym, then a
	# generic descriptor (the history sim only names survivors + fallen-with-heartland).
	var nm := str(_polity_names.get(pid, ""))
	if nm != "" and nm != pid:
		return nm
	if _fallen_names.has(pid):
		return str(_fallen_names[pid])
	return "an unnamed realm"


## Copy the currently-shown (filtered) chronicle to the clipboard as Markdown.
func _on_export_history() -> void:
	var sov := _current_history_filter()
	var title := "All realms"
	if _history_filter != null and _history_filter.selected >= 0:
		title = _history_filter.get_item_text(_history_filter.selected)
	var md: Array = ["# Chronicle — %s" % title, ""]
	for e in _events:
		if sov != "" and not _event_touches_sovereign(e, sov):
			continue
		var sentence := _event_sentence(e)
		if sentence == "":
			continue
		md.append("- **~%s yr ago** — %s" % [_commafy(int(e.get("year_before_start", 0))), sentence])
	DisplayServer.clipboard_set("\n".join(md))
	if _history_export_btn != null:
		_history_export_btn.text = "✓ Copied"
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(_history_export_btn):
			_history_export_btn.text = "⧉ Export"


func _commafy(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out


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


## A collapsible Tree tab (the Vassalage forest). hide_root makes the sovereigns the
## visible top level; every item is created collapsed, so the tab opens as a tidy
## sovereign list the player drills into. A dark panel keeps it on-theme.
func _tree_tab(tabs: TabContainer, title: String) -> Tree:
	var tree := Tree.new()
	tree.name = title
	tree.hide_root = true
	tree.columns = 1
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.add_theme_color_override("font_color", Color(0.86, 0.81, 0.71))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.14, 0.13, 0.10)
	tree.add_theme_stylebox_override("panel", panel)
	tabs.add_child(tree)
	return tree


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
