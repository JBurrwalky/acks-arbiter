extends SceneTree

## Dev visualizer for the continuous-geography field (gdd-continuous-geography.md).
## Generates GeoFields and dumps full-resolution PNGs at 6-mile cell resolution
## (NO hex quantization) so the field's real coasts / relief / watershed / climate
## are visible. Run headless:
##   godot --headless --path . --script res://tools/render_geo_field.gd
##
## Outputs three PNGs to user://:
##   geo_latitude_sheet.png  biome contact sheet — rows = latitude band, cols = seed
##   geo_terrain_sheet.png   terrain (relief + rivers) row, one panel per seed
##   geo_terrain.png         a single large terrain render (seed SEEDS[0], large map)

const SCALE := 4            # px per cell in the single large render
const PANEL_SCALE := 2      # px per cell in the contact sheets
const MAP_SIZE := "medium"  # contact-sheet map size (small | medium | large | huge)
const SEEDS := [101, 202, 303]
const BANDS := ["tropical", "subtropical", "temperate", "polar"]
const GAP := 8
const BG := Color(0.06, 0.06, 0.09)


func _initialize() -> void:
	_build_latitude_sheet()
	_build_terrain_sheet()
	_build_single_large()
	_build_terrain_diagnostics()
	_build_style_sheet()
	quit()


# --- Landmass-style comparison (continental / archipelago / pangaea) ---

func _build_style_sheet() -> void:
	var styles := ["continental", "archipelago", "pangaea"]
	var style_size := "large"  # bigger map so fragmentation differences are legible
	var fields: Array = []
	var fw := 0
	var fh := 0
	for style in styles:
		var p := SettingParameters.new()
		p.map_size = style_size
		p.land_mass_style = style
		var f := GeoFieldGenerator.generate(SEEDS[0], p)
		GeoClimateGenerator.apply(f, SEEDS[0], p)
		fw = f.width
		fh = f.height
		fields.append(f)
	var pw := fw * PANEL_SCALE
	var ph := fh * PANEL_SCALE
	var ncol := styles.size()
	var sheet := Image.create(ncol * pw + (ncol + 1) * GAP, ph + 2 * GAP, false, Image.FORMAT_RGB8)
	sheet.fill(BG)
	for c in range(ncol):
		var ox := GAP + c * (pw + GAP)
		var f: GeoField = fields[c]
		for row in range(f.height):
			for col in range(f.width):
				var i := f.idx(col, row)
				_fill_block(sheet, col, row, PANEL_SCALE, ox, GAP, _band_color(f, i,
						f.water[i] != GeoField.WATER_NONE))
	sheet.save_png("user://geo_style_sheet.png")
	print("GEO_STYLE_SHEET=", ProjectSettings.globalize_path("user://geo_style_sheet.png"))
	print("GEO_STYLE_COLS(left->right)=", styles)
	print("GEO_STYLE_SCALE: each panel = %dx%d cells = %d x %d miles (%s map)" % [
			fw, fh, int(fw * GeoField.CELL_MILES), int(fh * GeoField.CELL_MILES), style_size])


# --- Terrain diagnostics (honest, non-interpretive views of the raw field) ---

func _build_terrain_diagnostics() -> void:
	var p := SettingParameters.new()
	p.map_size = "large"
	var f := GeoFieldGenerator.generate(SEEDS[0], p)
	var sea: float = p.sea_level

	# 1. Pure grayscale heightmap: surface 0..1 → black..white; ocean faint blue.
	var gray := Image.create(f.width * SCALE, f.height * SCALE, false, Image.FORMAT_RGB8)
	# 2. Elevation-band quantization: ocean / flat / hills / mountains as flat colors.
	var bands := Image.create(f.width * SCALE, f.height * SCALE, false, Image.FORMAT_RGB8)
	# 3. Hillshade-only relief (no hypsometric tint): pure shape.
	var relief := Image.create(f.width * SCALE, f.height * SCALE, false, Image.FORMAT_RGB8)
	for row in range(f.height):
		for col in range(f.width):
			var i := f.idx(col, row)
			var s := f.surface[i]
			var is_water := f.water[i] != GeoField.WATER_NONE
			_fill_block(gray, col, row, SCALE, 0, 0,
					Color(0.06, 0.10, 0.22) if is_water else Color(s, s, s))
			_fill_block(bands, col, row, SCALE, 0, 0, _band_color(f, i, is_water))
			var sh := _hillshade(f, col, row)
			var rc := Color(0.10, 0.16, 0.30) if is_water else Color(sh * 0.7, sh * 0.7, sh * 0.72)
			_fill_block(relief, col, row, SCALE, 0, 0, rc)
	gray.save_png("user://geo_height_gray.png")
	bands.save_png("user://geo_elev_bands.png")
	relief.save_png("user://geo_relief.png")
	print("GEO_HEIGHT_GRAY=", ProjectSettings.globalize_path("user://geo_height_gray.png"))
	print("GEO_ELEV_BANDS=", ProjectSettings.globalize_path("user://geo_elev_bands.png"))
	print("GEO_RELIEF=", ProjectSettings.globalize_path("user://geo_relief.png"))
	# Surface histogram so the band split is legible as numbers, not just pixels.
	var below := 0
	var flat := 0
	var hills := 0
	var mtn := 0
	for i in range(f.size_cells()):
		if f.water[i] != GeoField.WATER_NONE:
			below += 1
			continue
		var tag := str(HeightmapGenerator._elevation_tag(f.surface[i]))
		if tag == "mountains":
			mtn += 1
		elif tag == "hills":
			hills += 1
		else:
			flat += 1
	var landn: int = maxi(flat + hills + mtn, 1)
	print("GEO_BANDS ocean=%d  land: flat=%.1f%% hills=%.1f%% mountains=%.1f%%" % [
			below, 100.0 * flat / landn, 100.0 * hills / landn, 100.0 * mtn / landn])


func _band_color(f: GeoField, i: int, is_water: bool) -> Color:
	if is_water:
		return Color(0.10, 0.20, 0.46)
	match str(HeightmapGenerator._elevation_tag(f.surface[i])):
		"mountains":
			return Color(0.55, 0.40, 0.34)
		"hills":
			return Color(0.62, 0.58, 0.38)
		_:
			return Color(0.50, 0.62, 0.40)  # flat


# --- Contact sheets ---------------------------------------------------------

func _build_latitude_sheet() -> void:
	var rows: Array = []
	var fw := 0
	var fh := 0
	for band in BANDS:
		var row_fields: Array = []
		for seed_val in SEEDS:
			var p := SettingParameters.new()
			p.map_size = MAP_SIZE
			p.latitude_range = band
			var f := GeoFieldGenerator.generate(seed_val, p)
			GeoClimateGenerator.apply(f, seed_val, p)
			fw = f.width
			fh = f.height
			row_fields.append(f)
		rows.append(row_fields)

	var pw := fw * PANEL_SCALE
	var ph := fh * PANEL_SCALE
	var ncol := SEEDS.size()
	var nrow := BANDS.size()
	var sheet := Image.create(ncol * pw + (ncol + 1) * GAP, nrow * ph + (nrow + 1) * GAP,
			false, Image.FORMAT_RGB8)
	sheet.fill(BG)
	for r in range(nrow):
		for c in range(ncol):
			var ox := GAP + c * (pw + GAP)
			var oy := GAP + r * (ph + GAP)
			_blit_biome(sheet, rows[r][c], ox, oy)
	sheet.save_png("user://geo_latitude_sheet.png")
	print("GEO_LAT_SHEET=", ProjectSettings.globalize_path("user://geo_latitude_sheet.png"))
	print("GEO_LAT_ROWS(top->bottom)=", BANDS)
	print("GEO_LAT_COLS(left->right seeds)=", SEEDS)


func _build_terrain_sheet() -> void:
	var fields: Array = []
	var fw := 0
	var fh := 0
	var p := SettingParameters.new()
	p.map_size = MAP_SIZE
	var fat := GeoFieldGenerator._fat(p)
	for seed_val in SEEDS:
		var f := GeoFieldGenerator.generate(seed_val, p)
		GeoClimateGenerator.apply(f, seed_val, p)
		fw = f.width
		fh = f.height
		fields.append(f)
	var pw := fw * PANEL_SCALE
	var ph := fh * PANEL_SCALE
	var ncol := SEEDS.size()
	var sheet := Image.create(ncol * pw + (ncol + 1) * GAP, ph + 2 * GAP, false, Image.FORMAT_RGB8)
	sheet.fill(BG)
	for c in range(ncol):
		var ox := GAP + c * (pw + GAP)
		_blit_terrain(sheet, fields[c], p.sea_level, fat, ox, GAP)
	sheet.save_png("user://geo_terrain_sheet.png")
	print("GEO_TERRAIN_SHEET=", ProjectSettings.globalize_path("user://geo_terrain_sheet.png"))
	print("GEO_TERRAIN_COLS(left->right seeds)=", SEEDS)


func _build_single_large() -> void:
	var p := SettingParameters.new()
	p.map_size = "large"
	var f := GeoFieldGenerator.generate(SEEDS[0], p)
	GeoClimateGenerator.apply(f, SEEDS[0], p)
	var fat := GeoFieldGenerator._fat(p)
	var img := Image.create(f.width * SCALE, f.height * SCALE, false, Image.FORMAT_RGB8)
	for row in range(f.height):
		for col in range(f.width):
			_fill_block(img, col, row, SCALE, 0, 0, _terrain_color(f, col, row, p.sea_level, fat))
	img.save_png("user://geo_terrain.png")
	print("GEO_TERRAIN_PATH=", ProjectSettings.globalize_path("user://geo_terrain.png"),
			" seed=", SEEDS[0], " dims=", f.width, "x", f.height)


# --- Panel blitters ---------------------------------------------------------

func _blit_biome(sheet: Image, f: GeoField, ox: int, oy: int) -> void:
	for row in range(f.height):
		for col in range(f.width):
			_fill_block(sheet, col, row, PANEL_SCALE, ox, oy, _biome_color(f, f.idx(col, row)))


func _blit_terrain(sheet: Image, f: GeoField, sea: float, fat: float, ox: int, oy: int) -> void:
	for row in range(f.height):
		for col in range(f.width):
			_fill_block(sheet, col, row, PANEL_SCALE, ox, oy, _terrain_color(f, col, row, sea, fat))


# --- Color ramps ------------------------------------------------------------

func _terrain_color(f: GeoField, col: int, row: int, sea: float, fat: float) -> Color:
	var i := f.idx(col, row)
	var s := f.surface[i]
	if f.water[i] == GeoField.WATER_OCEAN:
		var t := clampf(s / maxf(sea, 0.0001), 0.0, 1.0)  # deep (0) -> shore (1)
		return Color(0.03, 0.09, 0.27).lerp(Color(0.13, 0.40, 0.58), t)
	if f.water[i] == GeoField.WATER_LAKE:
		return Color(0.27, 0.58, 0.72)
	if f.flow_accum[i] >= fat:  # river channel
		var ord := clampf(float(f.strahler[i]) / 6.0, 0.0, 1.0)
		return Color(0.28, 0.5, 0.78).lerp(Color(0.10, 0.28, 0.62), ord)
	var base: Color
	if s < 0.40:
		base = Color(0.47, 0.60, 0.36)
	elif s < 0.55:
		base = Color(0.52, 0.62, 0.33)
	elif s < 0.68:
		base = Color(0.58, 0.56, 0.34)
	elif s < 0.78:
		base = Color(0.52, 0.43, 0.31)
	elif s < 0.90:
		base = Color(0.46, 0.40, 0.35)
	else:
		base = Color(0.88, 0.88, 0.90)
	var shade := _hillshade(f, col, row)
	return Color(clampf(base.r * shade, 0, 1), clampf(base.g * shade, 0, 1), clampf(base.b * shade, 0, 1))


func _hillshade(f: GeoField, col: int, row: int) -> float:
	var xl := f.surface[f.idx(maxi(col - 1, 0), row)]
	var xr := f.surface[f.idx(mini(col + 1, f.width - 1), row)]
	var yt := f.surface[f.idx(col, maxi(row - 1, 0))]
	var yb := f.surface[f.idx(col, mini(row + 1, f.height - 1))]
	var n := Vector3(-(xr - xl), -(yb - yt), 0.06).normalized()
	var light := Vector3(-1.0, -1.0, 1.1).normalized()
	return 0.62 + 0.85 * clampf(n.dot(light), 0.0, 1.0)


func _biome_color(f: GeoField, i: int) -> Color:
	if f.water[i] == GeoField.WATER_OCEAN:
		return Color(0.10, 0.20, 0.46)
	if f.water[i] == GeoField.WATER_LAKE:
		return Color(0.30, 0.60, 0.75)
	match GeoField.SUBTYPE_NAMES[f.biome_subtype[i]]:
		"clear_tundra":
			return Color(0.80, 0.84, 0.84)
		"clear_savanna":
			return Color(0.82, 0.74, 0.36)
		"forest_taiga":
			return Color(0.20, 0.40, 0.34)
		"mountains_glacial":
			return Color(0.90, 0.93, 0.96)
		"mountains_volcanic":
			return Color(0.36, 0.18, 0.16)
		"desert_badlands":
			return Color(0.60, 0.42, 0.30)
	match f.biome[i]:
		GeoField.BIOME_WOODS:
			return Color(0.24, 0.45, 0.22)
		GeoField.BIOME_JUNGLE:
			return Color(0.14, 0.50, 0.20)
		GeoField.BIOME_SWAMP:
			return Color(0.30, 0.40, 0.30)
		GeoField.BIOME_DESERT:
			# Cold-barren (EF/BWk) reads as icy waste, not warm sand. Cosmetic only —
			# the underlying tag is "desert" (barren / low-forage) either way.
			if f.temperature[i] < 0.0:
				return Color(0.74, 0.78, 0.80)
			return Color(0.84, 0.74, 0.46)
		_:
			return Color(0.72, 0.80, 0.45)  # clear


func _fill_block(img: Image, col: int, row: int, scale: int, ox: int, oy: int, c: Color) -> void:
	for dy in range(scale):
		for dx in range(scale):
			img.set_pixel(ox + col * scale + dx, oy + row * scale + dy, c)
