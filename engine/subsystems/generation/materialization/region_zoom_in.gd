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

# Cross-parent ecotone (Pass A, gdd-region-zoom-in §4.1) feathering strength: an edge
# child bordering ONE different-biome neighbour parent feathers toward it with this
# probability; a corner child (two such neighbours) feathers at 2×. The primary
# anti-uniformity mechanism — softens the 24-mile biome step into a natural transition.
# Tunable uniformity↔noise dial.
const ECOTONE_STRENGTH := 0.25

# Coastal jitter (gdd-region-zoom-in §4.2 "coastal fringe"): a boundary child between a
# land and a water parent can flip — a water child near land juts out as a peninsula,
# a land child near water floods to a cove. Coherent (driven by the smoothed noise, so
# it clusters into capes/inlets, not speckle). Higher = more ragged coast.
const COAST_STRENGTH := 0.30

# The 6 axial hex-neighbour deltas (matches HexRiverEdgeData.EDGE_NEIGHBOR_OFFSETS /
# HexMapController), for locating which neighbour PARENT an edge child borders.
const _AXIAL_NEIGHBORS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]


## Build the starting region's 6-mile play map. Returns
## {ok, errors[], region_map_id, parent_count, child_count, center}.
func build_start_region(campaign_id: String, world_map_id: String, start_settlement_id: String = "") -> Dictionary:
	var result := {
		"ok": false, "errors": [], "region_map_id": "",
		"parent_count": 0, "child_count": 0, "center": Vector2i.ZERO,
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

	var center := _pick_center(campaign_id, parents, start_settlement_id)
	result["center"] = center

	var params := SettingRepository.get_parameters(campaign_id)
	var campaign_seed := int(params.get("campaign_seed", 0))

	# Continuous-geography: regenerate the deterministic field and SAMPLE it per
	# 6-mile child cell (each child = one base cell → real sub-hex terrain), instead
	# of flat-copying the 24-mile parent into 16 near-identical tiles. Gated on the
	# same flag as world generation — only consistent when the world was generated
	# field-first (gdd-continuous-geography.md §5.6 / hex-normalization §8).
	var field: GeoField = null
	if GeoFieldToGrid.is_enabled() and not params.is_empty():
		var sp := SettingParameters.from_dict(params)
		field = GeoFieldGenerator.generate(campaign_seed, sp)
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
	var child_count := 0
	for pv in window:
		var parent: Dictionary = parents["%d,%d" % [pv.x, pv.y]]
		var kids: Array = _children_from_field(field, pv.x, pv.y, parent) if field != null \
				else _children_for_parent(campaign_seed, pv.x, pv.y, parent, parents)
		for ch in kids:
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
				db.query("ROLLBACK")
				result["errors"].append("child hex insert failed at parent (%d,%d)" % [pv.x, pv.y])
				return result
			child_count += 1
	db.query("COMMIT")

	result["parent_count"] = window.size()
	result["child_count"] = child_count
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


## 16 children for one parent: inherit + vary (patches, dense/light forest, intra-parent
## foothills, cross-parent ecotones, coastal jitter). `parents` is the full covered-parent
## map, for the neighbour-parent (ecotone + coast) lookup.
func _children_for_parent(seed: int, pq: int, pr: int, parent: Dictionary, parents: Dictionary) -> Array:
	var p_elev := str(parent.get("elevation", "flat"))
	var p_biome := str(parent.get("biome", "clear"))
	var p_sub := str(parent.get("biome_subtype", ""))
	var p_water := str(parent.get("water", ""))
	var p_civ := str(parent.get("civilization", "wilderness"))
	var p_orig := str(parent.get("original_biome", ""))
	var p_eraw := float(parent.get("elevation_raw", 0.0))
	# Children laid in OFFSET space (parent_col*SUB+local) so the 4x4 block tiles a clean
	# rectangle (parent_col == pq under even-q).
	var prow := WorldGrid.axial_to_offset(Vector2i(pq, pr)).y

	# Coherent smoothed noise (§6.5) — drives foothills, forest patches, AND the coastal
	# jitter (so capes/inlets cluster into shapes instead of speckling).
	var sm := _smooth(_noise_grid(seed, pq, pr))

	var out: Array = []

	# Water parent → water children, EXCEPT a child bordering a LAND neighbour parent can
	# jut out as a coherent peninsula/spit (coastal jitter — softens the square coast).
	if p_water != "":
		for cqi in SUB:
			for cri in SUB:
				var ckw := WorldGrid.offset_to_axial(pq * SUB + cqi, prow * SUB + cri)
				var land_nb := _coastal_neighbor(ckw, pq, pr, parents, false)
				if not land_nb.is_empty() and sm[cqi][cri] >= 1.0 - COAST_STRENGTH:
					out.append({
						"q": ckw.x, "r": ckw.y,
						"elevation": str(land_nb.get("elevation", "flat")),
						"biome": str(land_nb.get("biome", "clear")), "biome_subtype": "",
						"water": "", "civilization": str(land_nb.get("civilization", "wilderness")),
						"original_biome": str(land_nb.get("original_biome", "")),
						"elevation_raw": float(land_nb.get("elevation_raw", 0.0)),
					})
				else:
					out.append({
						"q": ckw.x, "r": ckw.y,
						"elevation": p_elev, "biome": p_biome, "biome_subtype": _clamp_sub(p_sub),
						"water": p_water, "civilization": p_civ, "original_biome": p_orig,
						"elevation_raw": p_eraw,
					})
		return out

	for cqi in SUB:
		for cri in SUB:
			var s: float = sm[cqi][cri]
			var ck := WorldGrid.offset_to_axial(pq * SUB + cqi, prow * SUB + cri)

			# A land child bordering a WATER neighbour parent can flood to a coherent cove
			# (coastal jitter) — overrides the land variation below.
			var water_nb := _coastal_neighbor(ck, pq, pr, parents, true)
			if not water_nb.is_empty() and s <= COAST_STRENGTH:
				out.append({
					"q": ck.x, "r": ck.y,
					"elevation": str(water_nb.get("elevation", "flat")),
					"biome": str(water_nb.get("biome", "clear")), "biome_subtype": "",
					"water": str(water_nb.get("water", "ocean")),
					"civilization": str(water_nb.get("civilization", "wilderness")),
					"original_biome": str(water_nb.get("original_biome", "")),
					"elevation_raw": float(water_nb.get("elevation_raw", 0.0)),
				})
				continue

			# Elevation: intra-parent orographic foothills (coherent → contiguous).
			var elev := p_elev
			if p_elev == "mountains":
				elev = "mountains" if s >= 0.35 else ("hills" if s >= 0.15 else "flat")
			elif p_elev == "hills":
				elev = "hills" if s >= 0.20 else "flat"
			else:
				elev = "hills" if s >= 0.90 else "flat"  # occasional knolls

			# Biome: copses/clearings (deviate one step) + dense/light forest patches.
			var biome := p_biome
			var sub := p_sub
			var bn: float = _roll(seed, "zoom_biome", pq, pr, cqi, cri)
			if bn >= 0.78:
				biome = _deviate_biome(p_biome, seed, pq, pr, cqi, cri)
				sub = ""  # a deviated biome drops the parent's subtype
			elif p_biome == "woods" or p_biome == "jungle":
				if s >= 0.66:
					sub = "forest_dense"
				elif s <= 0.20:
					sub = ""  # a light/thinned patch

			# Cross-parent ecotone (Pass A): an edge child bordering a different-biome
			# neighbour PARENT feathers toward it — a natural transition, not a hard step.
			var eco := _ecotone_biome(ck, pq, pr, p_biome, parents, seed, cqi, cri)
			if not eco.is_empty():
				biome = eco
				sub = ""

			# Civilization: rare one-step deviation at the margins.
			var civ := p_civ
			if _roll(seed, "zoom_civ", pq, pr, cqi, cri) >= 0.95:
				civ = _deviate_civ(p_civ)

			out.append({
				"q": ck.x, "r": ck.y,
				"elevation": elev, "biome": biome,
				"biome_subtype": _clamp_sub(sub if biome == p_biome else ""),
				"water": "", "civilization": civ, "original_biome": p_orig,
				"elevation_raw": p_eraw,
			})
	return out


## Continuous-geography child generation: each 6-mile child reads ONE base cell of
## the field (child offset (pq·SUB+cqi, prow·SUB+cri) == that field cell, 1:1), so
## terrain is the field's real sub-hex variation — coastline, ridge/valley, biome
## transitions are READ, not invented. The heuristic deviation/ecotone/coastal-jitter
## machinery of the legacy path is unnecessary here (the field already has it).
## Politics (civilization / original_biome) have no field representation, so they're
## inherited from the 24-mile parent.
func _children_from_field(field: GeoField, pq: int, pr: int, parent: Dictionary) -> Array:
	var prow := WorldGrid.axial_to_offset(Vector2i(pq, pr)).y
	var p_civ := str(parent.get("civilization", "wilderness"))
	var p_orig := str(parent.get("original_biome", ""))
	var out: Array = []
	for cqi in SUB:
		for cri in SUB:
			var fc := pq * SUB + cqi    # parent_col == pq under even-q (see legacy note)
			var fr := prow * SUB + cri
			var ck := WorldGrid.offset_to_axial(fc, fr)
			var tag := GeoFieldSampler.tag_6mile(field, fc, fr)
			out.append({
				"q": ck.x, "r": ck.y,
				"elevation": str(tag["elevation"]),
				"biome": str(tag["biome"]),
				"biome_subtype": _clamp_sub(str(tag["biome_subtype"])),
				"water": str(tag["water"]),
				"civilization": p_civ,
				"original_biome": p_orig,
				"elevation_raw": float(tag["elevation_raw"]),
			})
	return out


## A bordering neighbour PARENT (not the current one) that is water (want_water=true) or
## land (false). Returns the parent dict, or {} if `ck` borders no such neighbour — for
## the coastal jitter (land child near water → cove; water child near land → peninsula).
func _coastal_neighbor(ck: Vector2i, pq: int, pr: int, parents: Dictionary, want_water: bool) -> Dictionary:
	for d in _AXIAL_NEIGHBORS:
		var nb: Vector2i = ck + d
		var nboff := WorldGrid.axial_to_offset(nb)
		var np := WorldGrid.offset_to_axial(floori(nboff.x / 4.0), floori(nboff.y / 4.0))
		if np.x == pq and np.y == pr:
			continue
		var npar = parents.get("%d,%d" % [np.x, np.y], null)
		if npar == null:
			continue
		if (str((npar as Dictionary).get("water", "")) != "") == want_water:
			return npar as Dictionary
	return {}


## Cross-parent ecotone (§4.1): if child `ck` borders a neighbour PARENT (not the
## current one) whose biome differs and isn't water, feather toward it with
## probability ECOTONE_STRENGTH × (number of such neighbours) — so corner children
## feather more. Returns the chosen neighbour biome, or "" for no deviation (always
## "" for interior children, which border no neighbour parent). Deterministic.
func _ecotone_biome(ck: Vector2i, pq: int, pr: int, p_biome: String, parents: Dictionary, seed: int, cqi: int, cri: int) -> String:
	var cands: Array = []
	for d in _AXIAL_NEIGHBORS:
		var nb: Vector2i = ck + d
		var nboff := WorldGrid.axial_to_offset(nb)
		var np := WorldGrid.offset_to_axial(floori(nboff.x / 4.0), floori(nboff.y / 4.0))
		if np.x == pq and np.y == pr:
			continue  # neighbour child is in the same parent (interior edge)
		var npar = parents.get("%d,%d" % [np.x, np.y], null)
		if npar == null:
			continue
		if str((npar as Dictionary).get("water", "")) != "":
			continue  # never feather toward water
		var nbiome := str((npar as Dictionary).get("biome", "clear"))
		if nbiome != p_biome and not cands.has(nbiome):
			cands.append(nbiome)
	if cands.is_empty():
		return ""
	if _roll(seed, "zoom_ecotone", pq, pr, cqi, cri) >= ECOTONE_STRENGTH * float(cands.size()):
		return ""
	cands.sort()
	var idx := clampi(int(_roll(seed, "zoom_ecotone_pick", pq, pr, cqi, cri) * float(cands.size())), 0, cands.size() - 1)
	return str(cands[idx])


func _noise_grid(seed: int, pq: int, pr: int) -> Array:
	var g: Array = []
	for cqi in SUB:
		var row: Array = []
		for cri in SUB:
			row.append(_roll(seed, "zoom_noise", pq, pr, cqi, cri))
		g.append(row)
	return g


## §6.5: smoothed = 0.5·self + 0.5·mean(in-parent orthogonal neighbours).
func _smooth(n: Array) -> Array:
	var out: Array = []
	for x in SUB:
		var row: Array = []
		for y in SUB:
			var nsum := 0.0
			var ncnt := 0.0
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx: int = x + d[0]
				var ny: int = y + d[1]
				if nx >= 0 and nx < SUB and ny >= 0 and ny < SUB:
					nsum += float(n[nx][ny])
					ncnt += 1.0
			var navg: float = (nsum / ncnt) if ncnt > 0.0 else float(n[x][y])
			row.append(0.5 * float(n[x][y]) + 0.5 * navg)
		out.append(row)
	return out


func _deviate_biome(base: String, seed: int, pq: int, pr: int, cqi: int, cri: int) -> String:
	var r: float = _roll(seed, "zoom_biome_dev", pq, pr, cqi, cri)
	match base:
		"clear":
			return "woods" if r < 0.7 else "desert"
		"woods":
			return "clear" if r < 0.7 else "jungle"
		"jungle":
			return "woods" if r < 0.8 else "swamp"
		"swamp":
			return "jungle" if r < 0.8 else "woods"
		"desert":
			return "clear"
	return base


func _deviate_civ(base: String) -> String:
	match base:
		"civilized":
			return "borderlands"
		"borderlands":
			return "wilderness"
		"wilderness":
			return "borderlands"
	return base


func _clamp_sub(sub: String) -> String:
	return sub if _VALID_SUBTYPES.has(sub) else ""


func _roll(seed: int, stream_name: String, pq: int, pr: int, cqi: int, cri: int) -> float:
	return WorldGenRng.stream(seed, stream_name, 0, "%d,%d,%d,%d" % [pq, pr, cqi, cri]).randf()
