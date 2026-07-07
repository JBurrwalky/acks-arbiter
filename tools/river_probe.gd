extends Node

## Width-calibration + visual probe for GeoRiverMapper. Runs as a real SCENE (so
## autoloads load and WorldGrid/HexMapController resolve, unlike the --script
## visualizer). Prints the river width distribution + max corner discharge, and
## renders a river overlay over the terrain so the network can be judged visually.
##   godot --headless --path . res://tools/river_probe.tscn   (use an isolated %APPDATA%)

const SCALE := 5          # px per 6-mile field cell
const SUB := 4            # field cells per 24-mile hex (GeoField.SUBDIV_PER_24MI)
const RENDER_SEED := 101  # seed 101 has a major-river trunk


func _ready() -> void:
	print("=== River probe (GeoRiverMapper, continental large) ===")
	for seed_val in [42, 101, 202]:
		var p := SettingParameters.new()
		p.map_size = "large"
		var ctx := {"params": p, "campaign_seed": seed_val}
		GeoFieldToGrid.run(ctx)
		var edges: Array = ctx["river_edges"]
		var counts := {"stream": 0, "creek": 0, "river": 0, "major_river": 0}
		for e in edges:
			var wc := str(e["width_category"])
			counts[wc] = int(counts.get(wc, 0)) + 1
		print("PROBE seed %d: %d edges  max_accum=%.0f  stream=%d creek=%d river=%d major=%d" % [
				seed_val, edges.size(), GeoRiverMapper.debug_max_accum,
				counts["stream"], counts["creek"], counts["river"], counts["major_river"]])

	_render_rivers(RENDER_SEED)
	get_tree().quit()


func _render_rivers(seed_val: int) -> void:
	var p := SettingParameters.new()
	p.map_size = "large"
	# Field for the terrain background (same seed → same world the grid samples).
	var field := GeoFieldGenerator.generate(seed_val, p)
	GeoClimateGenerator.apply(field, seed_val, p)
	var ctx := {"params": p, "campaign_seed": seed_val}
	GeoFieldToGrid.run(ctx)
	var dims: Vector2i = p.map_dimensions()
	var edges: Array = ctx["river_edges"]

	var img := Image.create(field.width * SCALE, field.height * SCALE, false, Image.FORMAT_RGB8)
	for row in range(field.height):
		for col in range(field.width):
			_fill_cell(img, col, row, _terrain_color(field, col, row))

	# axial → offset (col,row), so a river edge's axial owner places into field space.
	var axial_to_off := {}
	for r in range(dims.y):
		for c in range(dims.x):
			axial_to_off[WorldGrid.offset_to_axial(c, r)] = Vector2i(c, r)

	var off6 := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
			Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
	var width_px := {"stream": 1, "creek": 2, "river": 3, "major_river": 5}
	var width_col := {
		"stream": Color(0.45, 0.66, 0.85), "creek": Color(0.28, 0.55, 0.85),
		"river": Color(0.15, 0.42, 0.85), "major_river": Color(0.05, 0.28, 0.78),
	}
	for e in edges:
		var owner := Vector2i(int(e["hex_q"]), int(e["hex_r"]))
		if not axial_to_off.has(owner):
			continue
		var oo: Vector2i = axial_to_off[owner]
		var nbr_ax: Vector2i = owner + off6[int(e["edge"])]
		var no: Vector2i = axial_to_off.get(nbr_ax, oo)
		# Owner + neighbour hex centres in field-cell space (4×4 block centres).
		var p0 := Vector2((oo.x * SUB + SUB * 0.5) * SCALE, (oo.y * SUB + SUB * 0.5) * SCALE)
		var p1 := Vector2((no.x * SUB + SUB * 0.5) * SCALE, (no.y * SUB + SUB * 0.5) * SCALE)
		var wc := str(e["width_category"])
		_draw_line(img, p0, (p0 + p1) * 0.5, int(width_px[wc]), width_col[wc])

	var path := "user://river_overlay.png"
	img.save_png(path)
	print("RIVER_OVERLAY=", ProjectSettings.globalize_path(path), " seed=", seed_val,
			" dims=", field.width, "x", field.height)


func _terrain_color(f: GeoField, col: int, row: int) -> Color:
	var i := f.idx(col, row)
	var s: float = f.surface[i]
	if f.water[i] == GeoField.WATER_OCEAN:
		return Color(0.10, 0.20, 0.40)
	if f.water[i] == GeoField.WATER_LAKE:
		return Color(0.24, 0.46, 0.66)
	var base: Color
	if s < 0.55:
		base = Color(0.48, 0.60, 0.40)
	elif s < 0.75:
		base = Color(0.60, 0.56, 0.40)
	else:
		base = Color(0.72, 0.70, 0.66)
	# faint hillshade
	var xl: float = f.surface[f.idx(maxi(col - 1, 0), row)]
	var xr: float = f.surface[f.idx(mini(col + 1, f.width - 1), row)]
	var sh: float = clampf(0.85 + 2.0 * (xl - xr), 0.55, 1.25)
	return Color(clampf(base.r * sh, 0, 1), clampf(base.g * sh, 0, 1), clampf(base.b * sh, 0, 1))


func _fill_cell(img: Image, col: int, row: int, c: Color) -> void:
	for dy in range(SCALE):
		for dx in range(SCALE):
			img.set_pixel(col * SCALE + dx, row * SCALE + dy, c)


func _draw_line(img: Image, a: Vector2, b: Vector2, radius: int, c: Color) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for s in range(steps + 1):
		var t := float(s) / float(steps)
		var px := int(round(a.x + (b.x - a.x) * t))
		var py := int(round(a.y + (b.y - a.y) * t))
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var x := px + dx
				var y := py + dy
				if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
					img.set_pixel(x, y, c)
