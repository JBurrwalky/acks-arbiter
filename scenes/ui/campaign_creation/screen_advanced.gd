extends Control

## Screen B: Advanced Parameters (gdd-campaign-creation-ui.md §4). Tabbed controls
## (Physical / Cultures / History / Content), each bound to a SettingParameters
## field. The UI never invents parameter semantics — every control maps to a field
## (see SettingParameters for the vector + enum→value tables). Controls write into
## the shared _params on change; _refresh_from_params re-displays on (re-)entry.

signal generate_requested
signal back_requested

var _params: SettingParameters
var _refreshers: Array = []   # Callables that re-read _params into each control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func bind_params(p: SettingParameters) -> void:
	_params = p
	_refresh_from_params()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.11, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	root.offset_left = 40
	root.offset_top = 28
	root.offset_right = -40
	root.offset_bottom = -28
	add_child(root)

	var title := Label.new()
	title.text = "Advanced Parameters"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.93, 0.86, 0.7))
	root.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	_build_physical(_tab(tabs, "Physical"))
	_build_cultures(_tab(tabs, "Cultures"))
	_build_history(_tab(tabs, "History"))
	_build_content(_tab(tabs, "Content"))

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 16)
	root.add_child(footer)
	var back := Button.new()
	back.text = "◂ Back"
	back.custom_minimum_size = Vector2(120, 44)
	back.pressed.connect(func(): back_requested.emit())
	footer.add_child(back)
	var gen := Button.new()
	gen.text = "Generate World  ▸"
	gen.custom_minimum_size = Vector2(190, 44)
	gen.pressed.connect(func(): generate_requested.emit())
	footer.add_child(gen)


# --- tabs --------------------------------------------------------------------

func _build_physical(p: VBoxContainer) -> void:
	_enum_row(p, "Map size", [["small", "Small"], ["medium", "Medium"], ["large", "Large"], ["huge", "Huge"]],
		func(): return _params.map_size, func(v): _params.map_size = v,
		"World dimensions in 24-mile hexes (bigger = slower to generate).\n" +
		"Small  15×12  = 180 hexes  (~360 mi across)\n" +
		"Medium 25×20 = 500 hexes  (~600 mi across)\n" +
		"Large  40×30 = 1,200 hexes (~960 mi across)\n" +
		"Huge   60×45 = 2,700 hexes (~1,440 mi across)")
	_enum_row(p, "Land mass", [["continental", "Continental"], ["archipelago", "Archipelago"], ["pangaea", "Pangaea"]],
		func(): return _params.land_mass_style, func(v): _params.land_mass_style = v,
		"Shape of the continents.\n" +
		"Continental — a few large landmasses (default)\n" +
		"Archipelago — more, smaller landmasses & island chains\n" +
		"Pangaea — land concentrated into one dominant supercontinent")
	_enum_row(p, "Mountains", [["low", "Low"], ["medium", "Medium"], ["high", "High"]],
		func(): return _params.mountain_frequency, func(v): _params.mountain_frequency = v,
		"Ruggedness of the land — share of land that is mountains / hills.\n" +
		"Low  ≈ 4% mountains / 17% hills\n" +
		"Medium ≈ 5% / 20%\n" +
		"High ≈ 8% / 31%\n" +
		"Higher settings also push more terrain above sea level.")
	_enum_row(p, "Rivers", [["low", "Low"], ["medium", "Medium"], ["high", "High"]],
		func(): return _params.river_density, func(v): _params.river_density = v,
		"How many river systems form.\n" +
		"Low — only the highest peaks feed rivers\n" +
		"High — many more sources, a denser river network")
	_enum_row(p, "Latitude", [["tropical", "Tropical"], ["subtropical", "Subtropical"], ["temperate", "Temperate"], ["continental", "Continental"], ["polar", "Polar"]],
		func(): return _params.latitude_range, func(v): _params.latitude_range = v,
		"Climate band the map sits in.\n" +
		"Tropical 5–20°N — hot; jungles & deserts\n" +
		"Subtropical 20–38°N — warm, dry summers\n" +
		"Temperate 35–55°N — mild; forests & plains (default)\n" +
		"Continental 45–65°N — cold winters\n" +
		"Polar 60–75°N — cold; tundra & taiga")
	_slider_row(p, "Sea level", 0.1, 0.6, 0.05,
		func(): return _params.sea_level, func(v): _params.sea_level = v,
		"Ocean coverage — higher means more sea, less land.\n" +
		"0.1 ≈ 87% land · 0.3 ≈ 51% land (default) · 0.6 ≈ 11% land")


func _build_cultures(p: VBoxContainer) -> void:
	_slider_row(p, "Human cultures", 3, 16, 1,
		func(): return float(_params.human_seed_points), func(v): _params.human_seed_points = int(v),
		"Number of distinct human cultures seeded across the map (default 10).\n" +
		"More = a busier patchwork of peoples and borders.")
	_check_row(p, "Demihuman peoples (elves, dwarves)",
		func(): return _params.demihuman_presence, func(v): _params.demihuman_presence = v,
		"Seed elf and dwarf homelands alongside the humans. Off = a humans-only world.")
	_slider_row(p, "Beastman frontier density", 0.0, 2.0, 0.1,
		func(): return _params.wilderness_beastman_density, func(v): _params.wilderness_beastman_density = v,
		"How thickly beastman clanholds (goblins, orcs, gnolls…) fill the wilderness.\n" +
		"0 = none · 1 = baseline · 2 = a teeming chaotic frontier (default 0.5)")


func _build_history(p: VBoxContainer) -> void:
	_enum_row(p, "Temperament", [["stable", "Stable"], ["moderate", "Moderate"], ["turbulent", "Turbulent"]],
		func(): return _params.collapse_temperament, func(v): _params.collapse_temperament = v,
		"How often realms rise and fall across the simulated history.\n" +
		"Stable — empires endure; fewer ruins\n" +
		"Moderate — balanced (default)\n" +
		"Turbulent — frequent collapses; more fallen realms & ruins")
	_enum_row(p, "History length", [["short", "Short"], ["standard", "Standard"], ["deep", "Deep"]],
		func(): return _params.history_length, func(v): _params.history_length = v,
		"Years of history simulated before play begins (each tick = 25 years).\n" +
		"Short ≈ 2,000 yr · Standard ≈ 4,000 yr · Deep ≈ 6,000 yr (slower, richer past)")
	_enum_row(p, "Migrations", [["off", "Off"], ["low", "Low"], ["moderate", "Moderate"], ["high", "High"]],
		func(): return _params.migration_rate, func(v): _params.migration_rate = v,
		"How readily whole peoples uproot and resettle under pressure.\n" +
		"Off — none · Low · Moderate (default) · High — frequent folk-migrations reshuffle the map")
	_slider_row(p, "Non-human ratio", 0.0, 0.5, 0.05,
		func(): return _params.non_human_ratio, func(v): _params.non_human_ratio = v,
		"Target share of the population that is non-human (demihuman + beastman).\n" +
		"0.2 ≈ one in five (default).")


func _build_content(p: VBoxContainer) -> void:
	_slider_row(p, "Dungeons", 0.5, 2.0, 0.1, func(): return _params.dungeon_density, func(v): _params.dungeon_density = v,
		"Multiplier on how many dungeons are placed. 0.5 = half · 1.0 = default · 2.0 = double.")
	_slider_row(p, "Roads", 0.5, 2.0, 0.1, func(): return _params.road_density, func(v): _params.road_density = v,
		"Multiplier on road-network density. 0.5 = sparse · 1.0 = default · 2.0 = dense.")
	_slider_row(p, "Fortifications", 0.5, 2.0, 0.1, func(): return _params.fortification_density, func(v): _params.fortification_density = v,
		"Multiplier on forts, watchtowers & strongholds. 0.5 = few · 1.0 = default · 2.0 = many.")
	_slider_row(p, "Points of interest", 0.5, 2.0, 0.1, func(): return _params.poi_density, func(v): _params.poi_density = v,
		"Multiplier on points of interest (shrines, ruins, landmarks…). 0.5 = few · 1.0 = default · 2.0 = many.")
	_enum_row(p, "POI danger", [["low", "Low"], ["medium", "Medium"], ["high", "High"]],
		func(): return _params.poi_danger, func(v): _params.poi_danger = v,
		"How dangerous points of interest skew.\n" +
		"Low — milder · Medium (default) · High — more lairs, hazards & tougher guardians")


# --- control helpers ---------------------------------------------------------

func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	tabs.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 14)
	vb.offset_left = 16
	vb.offset_top = 16
	scroll.add_child(vb)
	return vb


func _label(text: String, tooltip: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(230, 0)
	l.add_theme_color_override("font_color", Color(0.86, 0.81, 0.71))
	if tooltip != "":
		# A trailing "ⓘ" cues that hovering the row reveals an explanation.
		l.text = "%s  ⓘ" % text
		l.tooltip_text = tooltip
		l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


func _enum_row(parent: VBoxContainer, label: String, options: Array, getter: Callable, setter: Callable, tooltip: String = "") -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	parent.add_child(hb)
	hb.add_child(_label(label, tooltip))
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(200, 0)
	if tooltip != "":
		ob.tooltip_text = tooltip
	for entry in options:
		ob.add_item(str(entry[1]))
	ob.item_selected.connect(func(idx):
		if _params != null:
			setter.call(str(options[idx][0])))
	hb.add_child(ob)
	_refreshers.append(func():
		var cur = getter.call()
		for i in options.size():
			if str(options[i][0]) == str(cur):
				ob.select(i))


func _slider_row(parent: VBoxContainer, label: String, lo: float, hi: float, step: float, getter: Callable, setter: Callable, tooltip: String = "") -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	parent.add_child(hb)
	hb.add_child(_label(label, tooltip))
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.custom_minimum_size = Vector2(220, 0)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if tooltip != "":
		sl.tooltip_text = tooltip
	hb.add_child(sl)
	var val := Label.new()
	val.custom_minimum_size = Vector2(54, 0)
	val.add_theme_color_override("font_color", Color(0.82, 0.77, 0.66))
	hb.add_child(val)
	sl.value_changed.connect(func(v):
		val.text = "%.2f" % v
		if _params != null:
			setter.call(v))
	_refreshers.append(func():
		var cur := float(getter.call())
		sl.set_value_no_signal(cur)
		val.text = "%.2f" % cur)


func _check_row(parent: VBoxContainer, label: String, getter: Callable, setter: Callable, tooltip: String = "") -> void:
	var cb := CheckBox.new()
	cb.text = label
	cb.add_theme_color_override("font_color", Color(0.86, 0.81, 0.71))
	if tooltip != "":
		cb.tooltip_text = tooltip
	parent.add_child(cb)
	cb.toggled.connect(func(on):
		if _params != null:
			setter.call(on))
	_refreshers.append(func(): cb.set_pressed_no_signal(bool(getter.call())))


func _refresh_from_params() -> void:
	if _params == null:
		return
	for r in _refreshers:
		r.call()
