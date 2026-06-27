class_name RegionZoomIn
extends RefCounted

## M2: the 6-mile regional play map (the surface play actually happens on).
##
## Expands the player's starting region from the 24-mile world map into a
## regional_6mi child map: each 24-mile parent hex → 16 six-mile children, with
## terrain INHERITED from the parent and then naturally VARIED (not 16 identical
## tiles). See generation/gdd-region-zoom-in.md (§4 variation, §6 frontier) and
## gdd-hex-subdivision.md §6 (the inheritance contract).
##
## M2a SCOPE (this file): the child map + per-child TERRAIN — base inheritance +
## coherent-noise patches (incl. dense/light forest via biome_subtype) + intra-
## parent orographic foothills. DEFERRED to later M2 increments: cross-parent
## ecotone gradients (Pass A), river oases (need 6-mile rivers), polity/culture
## dithering, content placement (settlements/dungeons/POIs/forts), located domains
## + domain_hexes, roads/rivers, and party placement (M3).
##
## Deterministic: every per-child roll is keyed on
## (campaign_seed, parent_q, parent_r, child_local) via WorldGenRng.

const SUB := 4                  # 16:1 sub-hex ratio → a 4×4 child block per parent
const WINDOW_W_PARENTS := 10    # ≈40 six-mile hexes wide  (wider-than-tall play window,
const WINDOW_H_PARENTS := 8     # ≈32 six-mile hexes tall   ~5:4, snapped to whole parents)

const _VALID_SUBTYPES := [
	"", "forest_dense", "forest_taiga", "mountains_volcanic", "mountains_glacial",
	"clear_tundra", "clear_savanna", "clear_grassland", "clear_steppe",
	"clear_scrub", "desert_badlands",
]

const SUBTYPE_VOLCANIC := "mountains_volcanic"
# When the 24-mile parent is a volcanic range/peak (VolcanismPainter stamp), this
# fraction of its mountain CHILDREN become active vents (also mountains_volcanic);
# the rest read as ordinary mountains. A lone volcanic peak (no volcanic neighbor on
# the world map) vents far more freely so the solitary cone actually shows up.
const VENT_RATE_RANGE := 0.25
const VENT_RATE_LONE := 0.70
# Pointy-top hex neighbor offsets (axial) — for the lone-vs-range neighbor test.
const _OFF := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]


## Build the starting region's 6-mile play map. Returns
## {ok, errors[], region_map_id, parent_count, child_count, center}.
func build_start_region(campaign_id: String, world_map_id: String, start_settlement_id: String = "") -> Dictionary:
	var result := {
		"ok": false, "errors": [], "region_map_id": "",
		"parent_count": 0, "child_count": 0, "river_count": 0, "center": Vector2i.ZERO,
	}
	var db = CampaignRepository.db

	# World-map parent extent (the set of 24-mile hexes we may subdivide).
	var parents := {}   # "q,r" -> parent hex_cells row
	db.query_with_bindings(
		"SELECT q, r, elevation, biome, biome_subtype, water, civilization, original_biome, elevation_raw FROM hex_cells WHERE map_id = ?",
		[world_map_id])
	for row in db.query_result:
		parents["%d,%d" % [int(row["q"]), int(row["r"])]] = row
	if parents.is_empty():
		result["errors"].append("no world-map hexes to subdivide")
		return result

	# Volcanic parents (VolcanismPainter stamp) — the lone-vs-range vent rate is
	# derived from the FULL world map here, not just the play window, so a volcano
	# at the window edge still vents at the right rate.
	var volcanic_parents := {}
	for pkey in parents:
		if str(parents[pkey].get("biome_subtype", "")) == SUBTYPE_VOLCANIC:
			volcanic_parents[pkey] = true

	var center := _pick_center(campaign_id, parents, start_settlement_id)
	result["center"] = center

	var params := SettingRepository.get_parameters(campaign_id)
	var campaign_seed := int(params.get("campaign_seed", 0))

	# Continuous-geography (the only world-gen path since the 2026-06-25 cutover):
	# regenerate the deterministic field and SAMPLE it per 6-mile child cell (each
	# child = one base cell → real sub-hex terrain), instead of flat-copying the
	# 24-mile parent into 16 near-identical tiles (gdd-continuous-geography.md §5.6 /
	# hex-normalization §8). Field-mode requires the campaign's setting parameters.
	if params.is_empty():
		result["errors"].append("no setting parameters for campaign %s" % campaign_id)
		return result
	var sp := SettingParameters.from_dict(params)
	var field := GeoFieldGenerator.generate(campaign_seed, sp)
	GeoClimateGenerator.apply(field, campaign_seed, sp)

	# Window: WINDOW_W×H parents centered on `center`, keeping only parents that
	# actually exist on the world map.
	var window: Array = []          # Array[Vector2i] of parent coords
	var footprint: Array = []       # same, for the hex_maps footprint
	# The window is an OFFSET-rectangle box (so the 6-mile play map renders as a clean
	# rectangle, matching the world map). center is axial; box it in offset space and
	# convert each cell back to axial. A fixed axial box would render a parallelogram.
	# World offset-bounds, so the window SHIFTS to stay inside the world near an edge
	# instead of TRUNCATING — that keeps the play map a full landscape rectangle (the
	# 10×8 request) even when the start city sits near a world border (otherwise a
	# near-edge city yields a clipped, portrait-ish window). Only clamps when the world
	# is larger than the window in that axis; else the window spans the whole dimension.
	var w_min_col := 1 << 30
	var w_max_col := -(1 << 30)
	var w_min_row := 1 << 30
	var w_max_row := -(1 << 30)
	for key in parents:
		var pp: Dictionary = parents[key]
		var po := WorldGrid.axial_to_offset(Vector2i(int(pp["q"]), int(pp["r"])))
		w_min_col = mini(w_min_col, po.x)
		w_max_col = maxi(w_max_col, po.x)
		w_min_row = mini(w_min_row, po.y)
		w_max_row = maxi(w_max_row, po.y)

	var center_off := WorldGrid.axial_to_offset(center)
	var min_col := center_off.x - WINDOW_W_PARENTS / 2
	var min_row := center_off.y - WINDOW_H_PARENTS / 2
	if w_max_col - w_min_col + 1 >= WINDOW_W_PARENTS:
		min_col = clampi(min_col, w_min_col, w_max_col - WINDOW_W_PARENTS + 1)
	else:
		min_col = w_min_col
	if w_max_row - w_min_row + 1 >= WINDOW_H_PARENTS:
		min_row = clampi(min_row, w_min_row, w_max_row - WINDOW_H_PARENTS + 1)
	else:
		min_row = w_min_row
	for dcol in WINDOW_W_PARENTS:
		for drow in WINDOW_H_PARENTS:
			var pkey := WorldGrid.offset_to_axial(min_col + dcol, min_row + drow)
			if parents.has("%d,%d" % [pkey.x, pkey.y]):
				window.append(pkey)
				footprint.append(pkey)
	if window.is_empty():
		result["errors"].append("starting window covers no real parents")
		return result

	var region_id := _create_region_map(campaign_id, world_map_id, footprint)
	result["region_map_id"] = region_id

	db.query("BEGIN TRANSACTION")
	var region_grid := {}   # child axial → child dict, for the 6-mile edge passes
	var child_count := _materialize_children(
		region_id, field, window, parents, campaign_seed, volcanic_parents, region_grid)
	if child_count < 0:
		db.query("ROLLBACK")
		result["errors"].append("child hex insert failed")
		return result

	# 6-mile rivers + cliffs over the window grid (window-edge corners drain off as
	# outlets). The adaptive cliff threshold is PINNED on the map row here so frontier
	# growth reuses it and cliffs stay stable as the map grows (gdd-region-zoom-in.md §6).
	var r_origin := Vector2i(min_col * SUB, min_row * SUB)
	var r_dims := Vector2i(WINDOW_W_PARENTS * SUB, WINDOW_H_PARENTS * SUB)
	var edges := _rebuild_edges(region_id, sp, region_grid, r_origin, r_dims, -1.0)
	db.query_with_bindings(
		"UPDATE hex_maps SET cliff_threshold = ? WHERE id = ?", [edges["threshold"], region_id])

	db.query("COMMIT")

	result["parent_count"] = window.size()
	result["child_count"] = child_count
	result["river_count"] = edges["river_count"]
	result["cliff_count"] = edges["cliff_count"]
	result["ok"] = true
	return result


## Center the window on the player's chosen start settlement (its 24-mile hex), or
## auto-pick the largest civilized settlement (lowest market_class), or the extent
## midpoint as a last resort.
func _pick_center(campaign_id: String, parents: Dictionary, start_settlement_id: String) -> Vector2i:
	var db = CampaignRepository.db
	if not start_settlement_id.is_empty():
		db.query_with_bindings(
			"SELECT hex_q, hex_r FROM setting_settlements WHERE campaign_id = ? AND id = ?",
			[campaign_id, start_settlement_id])
		if not db.query_result.is_empty():
			var r: Dictionary = db.query_result[0]
			return Vector2i(int(r["hex_q"]), int(r["hex_r"]))
	# Auto-pick the biggest settlement (Class I = market_class 1).
	db.query_with_bindings(
		"SELECT hex_q, hex_r FROM setting_settlements WHERE campaign_id = ? ORDER BY market_class ASC, hex_r ASC, hex_q ASC LIMIT 1",
		[campaign_id])
	if not db.query_result.is_empty():
		var r2: Dictionary = db.query_result[0]
		return Vector2i(int(r2["hex_q"]), int(r2["hex_r"]))
	# Fallback: extent midpoint.
	var minq := 1 << 30
	var minr := 1 << 30
	var maxq := -(1 << 30)
	var maxr := -(1 << 30)
	for key in parents:
		var p: Dictionary = parents[key]
		minq = mini(minq, int(p["q"]))
		minr = mini(minr, int(p["r"]))
		maxq = maxi(maxq, int(p["q"]))
		maxr = maxi(maxr, int(p["r"]))
	return Vector2i((minq + maxq) / 2, (minr + maxr) / 2)


func _create_region_map(campaign_id: String, world_map_id: String, footprint: Array) -> String:
	var region_id := "%s_region6mi" % campaign_id
	var fp: Array = []
	for pv in footprint:
		fp.append([pv.x, pv.y])
	# Child coords are GLOBAL 6-mile (parent_q*4 + local), so the child of parent
	# (0,0) is (0,0) → parent_anchor = (0,0). The footprint lists the covered parents.
	CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_maps
			(id, campaign_id, name, scale, parent_map_id, parent_anchor_q, parent_anchor_r, parent_hex_footprint)
		VALUES (?, ?, ?, 'regional_6mi', ?, 0, 0, ?)
	""", [region_id, campaign_id, "Starting Region", world_map_id, JSON.stringify(fp)])
	return region_id


## Continuous-geography child generation: each 6-mile child reads ONE base cell of
## the field (child offset (pq·SUB+cqi, prow·SUB+cri) == that field cell, 1:1), so
## terrain is the field's real sub-hex variation — coastline, ridge/valley, biome
## transitions are READ, not invented. The heuristic deviation/ecotone/coastal-jitter
## machinery of the legacy path is unnecessary here (the field already has it).
## Politics (civilization / original_biome) have no field representation, so they're
## inherited from the 24-mile parent.
func _children_from_field(field: GeoField, pq: int, pr: int, parent: Dictionary,
		campaign_seed: int = 0, volcanic_parents: Dictionary = {}) -> Array:
	var prow := WorldGrid.axial_to_offset(Vector2i(pq, pr)).y
	var p_civ := str(parent.get("civilization", "wilderness"))
	var p_orig := str(parent.get("original_biome", ""))
	# Volcanic parent → its mountain children may erupt into active vents. A lone
	# volcano (no volcanic neighbor on the world map) vents at the higher rate.
	var p_volcanic := str(parent.get("biome_subtype", "")) == SUBTYPE_VOLCANIC
	var vent_rate := 0.0
	if p_volcanic:
		vent_rate = VENT_RATE_LONE if _is_lone_volcano(pq, pr, volcanic_parents) else VENT_RATE_RANGE
	var out: Array = []
	for cqi in SUB:
		for cri in SUB:
			var fc := pq * SUB + cqi    # parent_col == pq under even-q (see legacy note)
			var fr := prow * SUB + cri
			var ck := WorldGrid.offset_to_axial(fc, fr)
			var tag := GeoFieldSampler.tag_6mile(field, fc, fr)
			var sub := _clamp_sub(str(tag["biome_subtype"]))
			if p_volcanic and str(tag["elevation"]) == "mountains":
				sub = _volcanic_vent_subtype(sub, vent_rate, campaign_seed, ck)
			out.append({
				"q": ck.x, "r": ck.y,
				"elevation": str(tag["elevation"]),
				"biome": str(tag["biome"]),
				"biome_subtype": sub,
				"water": str(tag["water"]),
				"civilization": p_civ,
				"original_biome": p_orig,
				"elevation_raw": float(tag["elevation_raw"]),
			})
	return out


## A volcanic-range parent is part of a connected volcanic mass, so it has at least
## one volcanic neighbor; a lone volcanic peak has none. (A size-1 mountain component
## can have no adjacent mountain — hence no adjacent volcanic — by construction.)
static func _is_lone_volcano(pq: int, pr: int, volcanic_parents: Dictionary) -> bool:
	for off in _OFF:
		var n: Vector2i = Vector2i(pq, pr) + off
		if volcanic_parents.has("%d,%d" % [n.x, n.y]):
			return false
	return true


## Decide whether a mountain child of a volcanic parent is an active vent. A vent
## reads as mountains_volcanic (winning over glacial); otherwise the child keeps its
## field-sampled subtype. Deterministic per child axial (coding_conventions §80).
static func _volcanic_vent_subtype(base_sub: String, vent_rate: float,
		campaign_seed: int, child: Vector2i) -> String:
	var rng := WorldGenRng.stream(campaign_seed, "volcano_vent", 0,
			"%d,%d" % [child.x, child.y])
	if rng.randf() < vent_rate:
		return SUBTYPE_VOLCANIC
	return base_sub


func _clamp_sub(sub: String) -> String:
	return sub if _VALID_SUBTYPES.has(sub) else ""


# ---------------------------------------------------------------------------
# Shared materialization core (build_start_region + grow_frontier)
# ---------------------------------------------------------------------------

## Write the 16 field-sampled children of each parent in [param parents_to_write] into the
## region map's hex_cells, accumulating them into [param region_grid] (child axial → dict).
## Returns the number of children written, or -1 on a DB insert failure (caller ROLLBACKs).
## Caller is responsible for the surrounding transaction.
func _materialize_children(region_id: String, field: GeoField, parents_to_write: Array,
		parents: Dictionary, campaign_seed: int, volcanic_parents: Dictionary,
		region_grid: Dictionary) -> int:
	var db = CampaignRepository.db
	var n := 0
	for pv: Vector2i in parents_to_write:
		var parent: Dictionary = parents["%d,%d" % [pv.x, pv.y]]
		for ch in _children_from_field(field, pv.x, pv.y, parent, campaign_seed, volcanic_parents):
			if not db.query_with_bindings("""
				INSERT OR REPLACE INTO hex_cells
					(map_id, q, r, elevation, biome, biome_subtype, water, civilization,
					 has_city, original_biome, fog_state, elevation_raw)
				VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, 'hidden', ?)
			""", [
				region_id, ch["q"], ch["r"], ch["elevation"], ch["biome"],
				ch["biome_subtype"], ch["water"], ch["civilization"],
				ch["original_biome"], ch["elevation_raw"],
			]):
				return -1
			region_grid[Vector2i(int(ch["q"]), int(ch["r"]))] = ch
			n += 1
	return n


## Recompute the whole river + cliff EDGE layer over [param region_grid] (the FULL current
## play grid) and write it. Terrain hexes are never regenerated; only the edge layer is
## rebuilt so the frontier rivers extend naturally and cliffs stay consistent
## (gdd-region-zoom-in.md §6, Jedidiah ruling 2026-06-26). [param threshold] < 0 → compute
## the adaptive cliff cutoff (first build); ≥ 0 → reuse the pinned value (growth). DELETE +
## reinsert makes it idempotent. Returns {river_count, cliff_count, threshold}. Caller owns
## the transaction.
func _rebuild_edges(region_id: String, sp: SettingParameters, region_grid: Dictionary,
		origin: Vector2i, dims: Vector2i, threshold: float) -> Dictionary:
	var db = CampaignRepository.db
	db.query_with_bindings("DELETE FROM hex_river_edges WHERE map_id = ?", [region_id])
	db.query_with_bindings("DELETE FROM hex_cliff_edges WHERE map_id = ?", [region_id])
	var river_count := 0
	var river_hexes := {}   # Vector2i set: hexes a river touches (for canyon classification)
	for edge_row in GeoRiverMapper.map_rivers(sp, dims, region_grid, origin):
		var redge := HexRiverEdgeData.from_dict(edge_row)
		if CampaignRepository.save_hex_river_edge(region_id, redge):
			river_count += 1
			var ow := Vector2i(redge.hex_q, redge.hex_r)
			river_hexes[ow] = true
			river_hexes[ow + HexRiverEdgeData.neighbor_offset(redge.edge)] = true
	var thr: float = threshold if threshold >= 0.0 else CliffDetector.compute_threshold(region_grid)
	var cliff_count := 0
	for cliff in CliffDetector.detect(region_grid, river_hexes, thr):
		var cd: HexCliffEdgeData = cliff
		if db.query_with_bindings("""
			INSERT OR REPLACE INTO hex_cliff_edges
				(map_id, hex_q, hex_r, edge, cliff_type, height_ft, high_side)
			VALUES (?, ?, ?, ?, ?, ?, ?)
		""", [region_id, cd.hex_q, cd.hex_r, cd.edge, cd.cliff_type, cd.height_ft, cd.high_side]):
			cliff_count += 1
	return {"river_count": river_count, "cliff_count": cliff_count, "threshold": thr}


# ---------------------------------------------------------------------------
# Frontier growth (gdd-region-zoom-in.md §6 / gdd-setting-runtime-materialization §4.3)
# ---------------------------------------------------------------------------

## Append the next ROW or COLUMN of 24-mile parents' 16 children to the SAME regional_6mi
## map, on [param dir] (offset-space unit: (1,0)=E, (-1,0)=W, (0,1)=S, (0,-1)=N), keeping
## the play map a clean growing rectangle. Terrain hexes are pure field samples (generated
## once, never changed); the river/cliff edge layer is recomputed over the enlarged grid
## with the PINNED cliff threshold so it stays seamless + stable. Stops at the world edge.
## Returns {ok, grew, new_parents, new_children, river_count, cliff_count, errors, footprint}.
func grow_frontier(campaign_id: String, region_map_id: String, dir: Vector2i) -> Dictionary:
	var result := {
		"ok": false, "grew": false, "errors": [], "new_parents": 0, "new_children": 0,
		"river_count": 0, "cliff_count": 0, "footprint": [],
	}
	var db = CampaignRepository.db
	db.query_with_bindings(
		"SELECT parent_map_id, parent_hex_footprint, cliff_threshold FROM hex_maps WHERE id = ?",
		[region_map_id])
	if db.query_result.is_empty():
		result["errors"].append("region map %s not found" % region_map_id)
		return result
	var mrow: Dictionary = db.query_result[0]
	var world_map_id := str(mrow.get("parent_map_id", ""))
	var footprint := HexMapData.footprint_from_json_string(str(mrow.get("parent_hex_footprint", "[]")))
	var stored_threshold: float = float(mrow["cliff_threshold"]) if mrow.get("cliff_threshold") != null else -1.0
	if footprint.is_empty():
		result["errors"].append("region map has an empty footprint")
		return result

	# World parents (the set we may subdivide) + volcanic stamps.
	var parents := {}
	db.query_with_bindings(
		"SELECT q, r, elevation, biome, biome_subtype, water, civilization, original_biome, elevation_raw FROM hex_cells WHERE map_id = ?",
		[world_map_id])
	for row in db.query_result:
		parents["%d,%d" % [int(row["q"]), int(row["r"])]] = row
	if parents.is_empty():
		result["errors"].append("world map %s has no hexes" % world_map_id)
		return result
	var volcanic_parents := {}
	for pkey in parents:
		if str(parents[pkey].get("biome_subtype", "")) == SUBTYPE_VOLCANIC:
			volcanic_parents[pkey] = true

	# The next parent strip just beyond the footprint on `dir`, clamped to the world.
	var strip := _frontier_strip(_offset_bounds(footprint), _world_offset_bounds(parents), dir, parents)
	if strip.is_empty():
		result["ok"] = true   # at the world edge (or no real parents that way) — a no-op, not an error
		return result

	var params := SettingRepository.get_parameters(campaign_id)
	if params.is_empty():
		result["errors"].append("no setting parameters for campaign %s" % campaign_id)
		return result
	var sp := SettingParameters.from_dict(params)
	var campaign_seed := int(params.get("campaign_seed", 0))
	var field := GeoFieldGenerator.generate(campaign_seed, sp)
	GeoClimateGenerator.apply(field, campaign_seed, sp)

	# Load the existing region grid (needed for the seamless full-grid edge re-run).
	var region_grid := {}
	db.query_with_bindings(
		"SELECT q, r, elevation, biome, biome_subtype, water, civilization, original_biome, elevation_raw FROM hex_cells WHERE map_id = ?",
		[region_map_id])
	for row in db.query_result:
		region_grid[Vector2i(int(row["q"]), int(row["r"]))] = row

	db.query("BEGIN TRANSACTION")
	var new_children := _materialize_children(
		region_map_id, field, strip, parents, campaign_seed, volcanic_parents, region_grid)
	if new_children < 0:
		db.query("ROLLBACK")
		result["errors"].append("frontier child insert failed")
		return result

	var new_footprint := footprint.duplicate()
	new_footprint.append_array(strip)
	var box := _grid_box(new_footprint)
	var edges := _rebuild_edges(region_map_id, sp, region_grid, box["origin"], box["dims"], stored_threshold)

	var fp_json: Array = []
	for pv: Vector2i in new_footprint:
		fp_json.append([pv.x, pv.y])
	db.query_with_bindings(
		"UPDATE hex_maps SET parent_hex_footprint = ?, cliff_threshold = ? WHERE id = ?",
		[JSON.stringify(fp_json), edges["threshold"], region_map_id])
	db.query("COMMIT")

	result["ok"] = true
	result["grew"] = true
	result["new_parents"] = strip.size()
	result["new_children"] = new_children
	result["river_count"] = edges["river_count"]
	result["cliff_count"] = edges["cliff_count"]
	result["footprint"] = new_footprint
	return result


## Offset-space bounding box {min_col, max_col, min_row, max_row} of a set of axial parent
## coords (Array[Vector2i]).
func _offset_bounds(coords: Array) -> Dictionary:
	var min_col := 1 << 30
	var max_col := -(1 << 30)
	var min_row := 1 << 30
	var max_row := -(1 << 30)
	for c: Vector2i in coords:
		var o := WorldGrid.axial_to_offset(c)
		min_col = mini(min_col, o.x)
		max_col = maxi(max_col, o.x)
		min_row = mini(min_row, o.y)
		max_row = maxi(max_row, o.y)
	return {"min_col": min_col, "max_col": max_col, "min_row": min_row, "max_row": max_row}


## Offset-space bounding box of the world map's parents ("q,r"-keyed dict).
func _world_offset_bounds(parents: Dictionary) -> Dictionary:
	var coords: Array = []
	for row in parents.values():
		coords.append(Vector2i(int(row["q"]), int(row["r"])))
	return _offset_bounds(coords)


## The child-coordinate origin + dims for the river/cliff grid box covering a footprint:
## origin = (min_col·SUB, min_row·SUB); dims = (cols·SUB, rows·SUB).
func _grid_box(footprint: Array) -> Dictionary:
	var b := _offset_bounds(footprint)
	return {
		"origin": Vector2i(b["min_col"] * SUB, b["min_row"] * SUB),
		"dims": Vector2i((b["max_col"] - b["min_col"] + 1) * SUB, (b["max_row"] - b["min_row"] + 1) * SUB),
	}


## The next parent strip (a row or column) just beyond the footprint on [param dir], in
## offset space, keeping only parents that exist on the world map. Empty at the world edge.
func _frontier_strip(fb: Dictionary, wb: Dictionary, dir: Vector2i, parents: Dictionary) -> Array:
	var strip: Array = []
	if dir == Vector2i(1, 0):          # east — new column to the right
		var col: int = int(fb["max_col"]) + 1
		if col > int(wb["max_col"]):
			return strip
		_append_col_parents(strip, col, int(fb["min_row"]), int(fb["max_row"]), parents)
	elif dir == Vector2i(-1, 0):       # west — new column to the left
		var col2: int = int(fb["min_col"]) - 1
		if col2 < int(wb["min_col"]):
			return strip
		_append_col_parents(strip, col2, int(fb["min_row"]), int(fb["max_row"]), parents)
	elif dir == Vector2i(0, 1):        # south — new row below
		var row: int = int(fb["max_row"]) + 1
		if row > int(wb["max_row"]):
			return strip
		_append_row_parents(strip, row, int(fb["min_col"]), int(fb["max_col"]), parents)
	elif dir == Vector2i(0, -1):       # north — new row above
		var row2: int = int(fb["min_row"]) - 1
		if row2 < int(wb["min_row"]):
			return strip
		_append_row_parents(strip, row2, int(fb["min_col"]), int(fb["max_col"]), parents)
	return strip


func _append_col_parents(strip: Array, col: int, min_row: int, max_row: int, parents: Dictionary) -> void:
	for row in range(min_row, max_row + 1):
		var p := WorldGrid.offset_to_axial(col, row)
		if parents.has("%d,%d" % [p.x, p.y]):
			strip.append(p)


func _append_row_parents(strip: Array, row: int, min_col: int, max_col: int, parents: Dictionary) -> void:
	for col in range(min_col, max_col + 1):
		var p := WorldGrid.offset_to_axial(col, row)
		if parents.has("%d,%d" % [p.x, p.y]):
			strip.append(p)
