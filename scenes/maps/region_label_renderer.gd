class_name RegionLabelRenderer
extends Node2D

## Region name labels on the 6-mile play map (Jedidiah 2026-06-24). For each named
## setting_region overlapping the play window, draws a bold BLACK auto-sized label —
## region-size-aware AND text-length-aware — STRAIGHT where the text fits along the region's
## long axis, CURVED where it must bend to stay within the region's hex footprint.
##
## World-space: a child of HexMapRenderer, so labels pan/zoom WITH the map (sized in world
## units → they scale with camera zoom, like a printed atlas). Recomputed on map load only
## (regions are static). Reads setting_regions (24-mile) and projects each region's hexes to
## the in-window 6-mile children. Pure math — deterministic, no RNG.

# --- tunables -------------------------------------------------------------------
## Layers to label. Default = geographic place-names; 'road' (line feature) and
## 'historical_cultural' (cultural overlay) are off by default — flip to label them.
const LABEL_LAYERS := {
	"continent": true, "coastal_landform": true, "terrain_cluster": true, "hydronym": true,
}
const SIG_MIN := 0.30          # significance gate (0 = everything; ~0.65 = only the big features)
const MIN_FONT := 11           # world-px font clamp (small fully zoomed out)
const MAX_FONT := 64           # world-px font clamp (big on large regions)
const ADVANCE_RATIO := 0.62    # mean glyph advance ÷ font_size for the embolden sans
const EMBOLDEN := 0.55         # FontVariation synthetic-bold strength ("bold black text")
const USE_OUTLINE := true      # thin light halo so black stays legible on dark terrain
const SUB := 4                 # 16 six-mile children per 24-mile parent

const _FILL := Color(0.0, 0.0, 0.0, 1.0)
const _OUTLINE := Color(0.97, 0.96, 0.90, 0.85)

var _placements: Array = []    # precomputed draw data, replayed in _draw()
var _bold: FontVariation = null


func _ensure_font() -> void:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = EMBOLDEN


# --- public API -----------------------------------------------------------------

## Recompute every region-label placement and redraw. [param campaign_id] for list_regions;
## [param map_id] = the regional_6mi play map; [param hex_to_pixel](coord) -> world px (the
## Callable HexMapRenderer already builds for landmark icons).
func refresh(campaign_id: String, map_id: String, hex_to_pixel: Callable) -> void:
	_ensure_font()
	_placements.clear()
	if campaign_id.is_empty() or map_id.is_empty():
		queue_redraw()
		return
	# In-window 6-mile children (one query, reused for every region).
	var window := {}
	CampaignRepository.db.query_with_bindings("SELECT q, r FROM hex_cells WHERE map_id = ?", [map_id])
	for c in CampaignRepository.db.query_result:
		window[Vector2i(int(c["q"]), int(c["r"]))] = true
	if window.is_empty():
		queue_redraw()
		return
	var regions: Array = SettingRepository.list_regions(campaign_id)
	# Significance DESC → bigger features draw last (on top) and a future cull keeps them.
	regions.sort_custom(func(a, b): return float(a.get("significance", 0.0)) > float(b.get("significance", 0.0)))
	for reg in regions:
		if not LABEL_LAYERS.has(str(reg.get("layer", ""))):
			continue
		if float(reg.get("significance", 0.0)) < SIG_MIN:
			continue
		var label := str(reg.get("name_primary", "")).strip_edges()
		if label.is_empty():
			continue
		var members := _project_members(str(reg.get("hexes", "[]")), window)
		if members.is_empty():
			continue
		var pts := PackedVector2Array()
		for m in members:
			pts.append(hex_to_pixel.call(m))
		var placement := _layout(label, pts)
		if not placement.is_empty():
			_placements.append(placement)
	queue_redraw()


# --- projection -----------------------------------------------------------------

## A 24-mile region's hexes JSON → the in-window 6-mile child hexes it covers (offset space,
## SUB=4 — the inverse of HexInfoAssembler._parent_axial).
func _project_members(hexes_json: String, window: Dictionary) -> Array:
	var out: Array = []
	var parsed = JSON.parse_string(hexes_json)
	if not (parsed is Array):
		return out
	for pair in parsed:
		if not (pair is Array and (pair as Array).size() == 2):
			continue
		var poff := WorldGrid.axial_to_offset(Vector2i(int(pair[0]), int(pair[1])))
		for lx in range(SUB):
			for ly in range(SUB):
				var child := WorldGrid.offset_to_axial(poff.x * SUB + lx, poff.y * SUB + ly)
				if window.has(child):
					out.append(child)
	return out


# --- layout (PCA → size → straight/curved) --------------------------------------

func _layout(text: String, pts: PackedVector2Array) -> Dictionary:
	var n := pts.size()
	if n == 0:
		return {}
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(n)
	# PCA principal axis.
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	for p in pts:
		var d := p - c
		sxx += d.x * d.x
		syy += d.y * d.y
		sxy += d.x * d.y
	var theta := 0.5 * atan2(2.0 * sxy, sxx - syy)
	var axis := Vector2(cos(theta), sin(theta))
	# Axis extent + perpendicular half-width.
	var amin := INF
	var amax := -INF
	var wabs := 0.0
	for p in pts:
		var d := p - c
		var a := d.dot(axis)
		amin = minf(amin, a)
		amax = maxf(amax, a)
		wabs = maxf(wabs, absf(d.dot(Vector2(-axis.y, axis.x))))
	var ln := amax - amin
	var spacing := _hex_spacing(pts)
	if n <= 2 or ln < 1.0:
		ln = spacing * 0.9
		axis = Vector2.RIGHT
		wabs = spacing * 0.5
	# Read left→right (never upside-down).
	if axis.x < 0.0:
		axis = -axis
	# Region-size + text-length aware font size (world units).
	var size_len := ln / (ADVANCE_RATIO * maxf(1.0, float(text.length())))
	var size_w := 2.0 * wabs
	var fs := clampi(int(min(size_len, size_w)), MIN_FONT, MAX_FONT)
	var total := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# STRAIGHT iff every glyph centre lands on a member hex (within ~1 hex). A thin/bent
	# region (river, crescent) fails this — the straight axis crosses off its hexes.
	if _straight_fits(text, fs, c, axis, total, pts, spacing):
		return {
			"mode": "straight", "text": text, "fs": fs,
			"origin": c - axis * (total * 0.5) + Vector2(-axis.y, axis.x) * (fs * 0.30),
			"angle": atan2(axis.y, axis.x),
		}
	return _curved_layout(text, fs, pts, c, axis, amin, amax, spacing)


## Min adjacent-hex distance (world px) from a sample of the points = the hex spacing.
func _hex_spacing(pts: PackedVector2Array) -> float:
	var n := mini(pts.size(), 24)
	if n < 2:
		return 75.0
	var best := INF
	for i in range(n):
		for j in range(i + 1, n):
			var d := pts[i].distance_to(pts[j])
			if d > 0.1:
				best = minf(best, d)
	return best if best < INF else 75.0


## True iff a straight label centred on `c` along `axis` keeps every glyph centre within
## ~one hex of a member point (i.e. the label stays ON the region).
func _straight_fits(text: String, fs: int, c: Vector2, axis: Vector2, total: float, pts: PackedVector2Array, spacing: float) -> bool:
	var r2 := (spacing * 0.95) * (spacing * 0.95)
	var t := -total * 0.5
	for i in range(text.length()):
		var adv := _bold.get_char_size(text.unicode_at(i), fs).x
		var gc := c + axis * (t + adv * 0.5)
		var on := false
		for p in pts:
			if gc.distance_squared_to(p) <= r2:
				on = true
				break
		if not on:
			return false
		t += adv
	return true


## Curved fallback: a smooth baseline through the region's medial points (centerline),
## arc-length-parameterised, with one glyph placed + rotated to the tangent per character.
func _curved_layout(text: String, fs: int, pts: PackedVector2Array, c: Vector2, axis: Vector2, amin: float, amax: float, spacing: float) -> Dictionary:
	var perp := Vector2(-axis.y, axis.x)
	var k := clampi(int(text.length() / 2), 3, 8)
	var span := maxf(1.0, amax - amin)
	var sum_a: Array = []
	var sum_w: Array = []
	var cnt: Array = []
	for i in range(k):
		sum_a.append(0.0)
		sum_w.append(0.0)
		cnt.append(0)
	for p in pts:
		var d := p - c
		var a := d.dot(axis)
		var idx := clampi(int((a - amin) / span * k), 0, k - 1)
		sum_a[idx] = float(sum_a[idx]) + a
		sum_w[idx] = float(sum_w[idx]) + d.dot(perp)
		cnt[idx] = int(cnt[idx]) + 1
	var medial: Array = []
	for i in range(k):
		if int(cnt[i]) == 0:
			continue
		var ac := float(sum_a[i]) / float(cnt[i])
		var wc := float(sum_w[i]) / float(cnt[i])
		medial.append(c + axis * ac + perp * wc)
	if medial.size() < 2:
		# Not enough centerline to curve — fall back to a straight horizontal label.
		var t0 := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		return {
			"mode": "straight", "text": text, "fs": fs,
			"origin": c - axis * (t0 * 0.5) + perp * (fs * 0.30), "angle": atan2(axis.y, axis.x),
		}
	# Smooth Catmull-Rom curve through the medial points (Curve2D bakes arc length for us).
	var curve := Curve2D.new()
	for i in range(medial.size()):
		var tang := Vector2.ZERO
		if i > 0 and i < medial.size() - 1:
			tang = (medial[i + 1] - medial[i - 1]) * 0.5
		elif i == 0:
			tang = medial[1] - medial[0]
		else:
			tang = medial[i] - medial[i - 1]
		curve.add_point(medial[i], -tang / 3.0, tang / 3.0)
	var s_len := curve.get_baked_length()
	if s_len < 1.0:
		return {}
	var total := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# Shrink-to-fit so the string never overflows the curve.
	if total > s_len:
		fs = maxi(MIN_FONT, int(float(fs) * s_len / total))
		total = _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var glyphs: Array = []
	var arc := maxf(0.0, (s_len - total) * 0.5)
	for i in range(text.length()):
		var cp := text.unicode_at(i)
		var adv := _bold.get_char_size(cp, fs).x
		var mid := clampf(arc + adv * 0.5, 0.0, s_len)
		var pos := curve.sample_baked(mid)
		var tang := curve.sample_baked(clampf(mid + 2.0, 0.0, s_len)) - curve.sample_baked(clampf(mid - 2.0, 0.0, s_len))
		if tang.length() < 0.001:
			tang = axis
		tang = tang.normalized()
		var gperp := Vector2(-tang.y, tang.x)
		glyphs.append({
			"ch": String.chr(cp),
			"origin": pos - tang * (adv * 0.5) + gperp * (fs * 0.30),
			"angle": atan2(tang.y, tang.x),
		})
		arc += adv
	return {"mode": "curved", "text": text, "fs": fs, "glyphs": glyphs}


# --- draw -----------------------------------------------------------------------

func _draw() -> void:
	_ensure_font()
	for pl in _placements:
		var fs := int(pl["fs"])
		var outline_px := maxi(2, int(float(fs) * 0.12))
		if str(pl["mode"]) == "straight":
			var text := str(pl["text"])
			draw_set_transform(pl["origin"], float(pl["angle"]), Vector2.ONE)
			if USE_OUTLINE:
				draw_string_outline(_bold, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline_px, _OUTLINE)
			draw_string(_bold, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _FILL)
			draw_set_transform_matrix(Transform2D.IDENTITY)
		else:
			for g in pl["glyphs"]:
				var ch := str(g["ch"])
				draw_set_transform(g["origin"], float(g["angle"]), Vector2.ONE)
				if USE_OUTLINE:
					draw_char_outline(_bold, Vector2.ZERO, ch, fs, outline_px, _OUTLINE)
				draw_char(_bold, Vector2.ZERO, ch, fs, _FILL)
				draw_set_transform_matrix(Transform2D.IDENTITY)
