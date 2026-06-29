class_name GeoFieldToGrid
extends RefCounted

## INTEGRATION of the field-first engine (gdd-continuous-geography.md §13). The
## SOLE Layers-1-2 world-gen path since the 2026-06-25 cutover (the legacy
## hex-native HeightmapGenerator/ClimateGenerator generation was retired): generate
## the continuous GeoField, then normalize it into the per-24-mile-hex grid via
## GeoFieldSampler.tag_24mile + block-mean climate, and map corner-graph rivers
## (GeoRiverMapper). Produces ctx.hex_grid / river_edges / width / height in the
## shape every downstream layer (region painting, history sim, …) consumes.


## Fill ctx.hex_grid / river_edges / width / height with the field-first Layers
## 1-2 output. Returns true on success.
static func run(ctx: Dictionary) -> bool:
	var params = ctx["params"]
	var seed: int = int(ctx["campaign_seed"])
	var dims: Vector2i = params.map_dimensions()
	ctx["width"] = dims.x
	ctx["height"] = dims.y

	var field := GeoFieldGenerator.generate(seed, params)
	GeoClimateGenerator.apply(field, seed, params)

	var grid := {}
	var lat_south: float = params.latitude_south()
	var lat_span: float = params.latitude_north() - lat_south
	for row in range(dims.y):
		var lat := lat_south + lat_span * (float(dims.y - 1 - row) / maxf(float(dims.y - 1), 1.0))
		for col in range(dims.x):
			var key := WorldGrid.offset_to_axial(col, row)
			grid[key] = _hex_from_field(field, col, row, lat)
	ctx["hex_grid"] = grid

	# Rivers: drainage on the hex-corner graph (GeoRiverMapper), aggregating the
	# field's terrain into along-edge trunk rivers with discharge-ranked width.
	ctx["river_edges"] = GeoRiverMapper.map_rivers(params, dims, grid)
	var river_hexes := ClimateGenerator._river_adjacent_set(ctx["river_edges"])
	ClimateGenerator._apply_swamp_pass(seed, grid, dims.x, dims.y, river_hexes)
	ClimateGenerator._assign_land_values(grid, dims.x, dims.y, river_hexes)
	return true


## One working-hex dict matching HeightmapGenerator + ClimateGenerator output,
## sourced from the field (climate block-aggregated over the 4×4 base cells).
static func _hex_from_field(field: GeoField, col: int, row: int, lat: float) -> Dictionary:
	var tag := GeoFieldSampler.tag_24mile(field, col, row)
	var water := str(tag["water"])
	var s := GeoField.SUBDIV_PER_24MI
	var t_sum := 0.0
	var p_sum := 0.0
	var cnt := 0
	for cy in range(row * s, row * s + s):
		for cx in range(col * s, col * s + s):
			var ci := field.idx(cx, cy)
			t_sum += field.temperature[ci]
			p_sum += field.precipitation[ci]
			cnt += 1
	var temp := t_sum / float(maxi(cnt, 1))
	var precip := p_sum / float(maxi(cnt, 1))
	var koppen := "" if water != "" else ClimateGenerator._classify_koppen(temp, precip, 0.5)
	return {
		"elevation_raw": float(tag["elevation_raw"]),
		"elevation": str(tag["elevation"]),
		"water": water,
		"temperature": temp,
		"precipitation": precip,
		"effective_latitude": lat,
		"koppen": koppen,
		"biome": str(tag["biome"]),
		"biome_subtype": str(tag["biome_subtype"]),
		"original_biome": "",
		"culture_weights": "{}",
		"alignment_weights": "{}",
		"population_band": 0,
		"territory_class": "wilderness",
		"owner_polity_id": "",
		"land_value": 0,
		"clearing_progress": 0,   # §5.4 deforestation timed-cost counter (Phase 2b)
	}
