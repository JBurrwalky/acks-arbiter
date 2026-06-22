extends "res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd"

## World Map tab (M3-c; gdd-setting-runtime-materialization §15.4). The 24-mile strategic
## POLITICAL map of the generated world, read from the frozen `setting_*` tables — the world
## AS GENERATED (a live realm sim would refresh it at M5). Reuses the campaign-creation
## review screen's PoliticalMapView widget (same bind sequence), plus a ranked-realm legend.
##
## Only meaningful for `campaign_origin='generated'`; a fixture campaign has no `setting_hexes`,
## so it shows an empty state instead.

const PoliticalMapViewScript := preload("res://scenes/ui/campaign_creation/political_map_view.gd")

const _LEGEND_MAX := 14   # cap the realm legend; overflow folds into a "+N more" line.


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
	var names := {}
	var lieges := {}
	var tiers := {}
	for p in polities:
		var pid := str(p.get("id", ""))
		names[pid] = str(p.get("name", pid)) if str(p.get("name", "")) != "" else pid
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
	subtitle.text = "24-mile strategic map · %d realms" % names.size()
	subtitle.add_theme_color_override("font_color", Color(0.30, 0.24, 0.16))
	root.add_child(subtitle)

	# Map (expands) + realm legend (fixed column).
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	var map = PoliticalMapViewScript.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(map)
	# Same bind order as ScreenReview.bind_map (set_polity_meta before bind).
	map.set_polity_meta(names, lieges, tiers)
	map.bind(SettingRepository.list_hexes(cid), SettingRepository.list_replay_palette(cid))
	map.set_settlements(SettingRepository.list_settlements(cid))
	map.set_rivers(SettingRepository.list_river_edges(cid))

	_build_legend(body, map.legend_entries(names))


## Ranked-realm legend (color swatch + name), capped at _LEGEND_MAX with a "+N more" line.
func _build_legend(parent: HBoxContainer, entries: Array) -> void:
	var legend := VBoxContainer.new()
	legend.custom_minimum_size = Vector2(190, 0)
	legend.add_theme_constant_override("separation", 4)
	parent.add_child(legend)
	var heading := Label.new()
	heading.text = "Realms"
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color(0.12, 0.09, 0.05))
	legend.add_child(heading)
	var shown := mini(entries.size(), _LEGEND_MAX)
	for i in range(shown):
		var e: Dictionary = entries[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var swatch := ColorRect.new()
		swatch.color = e.get("color", Color.WHITE)
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var lbl := Label.new()
		lbl.text = str(e.get("label", ""))
		lbl.add_theme_color_override("font_color", Color(0.20, 0.16, 0.10))
		row.add_child(lbl)
		legend.add_child(row)
	if entries.size() > shown:
		var more := Label.new()
		more.text = "+%d more" % (entries.size() - shown)
		more.add_theme_color_override("font_color", Color(0.40, 0.34, 0.24))
		legend.add_child(more)
