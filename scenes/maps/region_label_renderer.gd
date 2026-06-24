class_name RegionLabelRenderer
extends Node2D

## Region name labels on the 6-mile play map (Jedidiah 2026-06-24). For each named
## setting_region overlapping the play window, draws a bold BLACK auto-sized title — STRAIGHT
## where it fits along the region's long axis, CURVED where it must bend to stay within the
## region — plus a smaller "(forest)" / "(continent)" / "(river)" type subtitle underneath.
##
## Overlap handling: labels are placed in significance order (bigger features first); a label
## that would collide with an already-placed one is SHRUNK to fit, and culled only if it can't
## fit above the minimum size. Oriented-bounding-box (SAT) collision.
##
## World-space: a child of HexMapRenderer, so labels pan/zoom WITH the map (sized in world
## units → scale with camera zoom). Recomputed on map load only (regions are static).

# --- tunables -------------------------------------------------------------------
const LABEL_LAYERS := {
	"continent": true, "coastal_landform": true, "terrain_cluster": true, "hydronym": true,
}
const SIG_MIN := 0.30
const MIN_FONT := 11           # world-px title clamp + the cull floor when overlapping
const MAX_FONT := 64
const ADVANCE_RATIO := 0.62
const EMBOLDEN := 0.55
const USE_OUTLINE := true
const SUB := 4
const SUB_RATIO := 0.52        # subtitle font = title font × this
const MIN_SUB_FONT := 8
const SHRINK_STEP := 0.82      # font shrink factor per overlap iteration

const _FILL := Color(0.0, 0.0, 0.0, 1.0)
const _OUTLINE := Color(0.97, 0.96, 0.90, 0.85)

var _placements: Array = []
var _bold: FontVariation = null


func _ensure_font() -> void:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = EMBOLDEN


# --- public API -----------------------------------------------------------------

func refresh(campaign_id: String, map_id: String, hex_to_pixel: Callable) -> void:
	_ensure_font()
	_placements.clear()
	if campaign_id.is_empty() or map_id.is_empty():
		queue_redraw()
		return
	var window := {}
	CampaignRepository.db.query_with_bindings("SELECT q, r FROM hex_cells WHERE map_id = ?", [map_id])
	for c in CampaignRepository.db.query_result:
		window[Vector2i(int(c["q"]), int(c["r"]))] = true
	if window.is_empty():
		queue_redraw()
		return
	var regions: Array = SettingRepository.list_regions(campaign_id)
	# Significance DESC → bigger features get placement priority + keep their size.
	regions.sort_custom(func(a, b): return float(a.get("significance", 0.0)) > float(b.get("significance", 0.0)))

	# 1. Build a candidate (geometry + mode + flexible size) per labelable region.
	var cands: Array = []
	for reg in regions:
		if not LABEL_LAYERS.has(str(reg.get("layer", ""))):
			continue
		if float(reg.get("significance", 0.0)) < SIG_MIN:
			continue
		var title := str(reg.get("name_primary", "")).strip_edges()
		if title.is_empty():
			continue
		var members := _project_members(str(reg.get("hexes", "[]")), window)
		if members.is_empty():
			continue
		var pts := PackedVector2Array()
		for m in members:
			pts.append(hex_to_pixel.call(m))
		# Type subtitle = the region's subtype (else its layer), prettified: a leaf sub-split
		# "basin_part" reads "basin", "river_system" reads "river system".
		var subtype := str(reg.get("subtype", ""))
		if subtype.is_empty():
			subtype = str(reg.get("layer", ""))
		subtype = subtype.trim_suffix("_part").replace("_", " ")
		var type_text := "(%s)" % subtype
		var cand := _build_candidate(title, type_text, pts)
		if not cand.is_empty():
			cands.append(cand)

	# 2. Greedy overlap resolution: place in significance order; shrink to avoid a collision;
	#    cull if it can't fit above MIN_FONT. SAT on oriented bounding boxes.
	var placed_obbs: Array = []
	for cand in cands:
		var fs := int(cand["base_fs"])
		while fs >= MIN_FONT:
			var obb := _label_obb(cand, fs)
			var hit := false
			for po in placed_obbs:
				if _obb_overlap(obb, po):
					hit = true
					break
			if not hit:
				placed_obbs.append(obb)
				cand["fs"] = fs
				_placements.append(_finalize(cand))
				break
			fs = int(float(fs) * SHRINK_STEP)
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


# --- candidate build (PCA → size → straight/curved decision) --------------------

func _build_candidate(text: String, type_text: String, pts: PackedVector2Array) -> Dictionary:
	var n := pts.size()
	if n == 0:
		return {}
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(n)
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
		amin = -ln * 0.5
		amax = ln * 0.5
	if axis.x < 0.0:
		axis = -axis
	var base_fs := clampi(int(min(ln / (ADVANCE_RATIO * maxf(1.0, float(text.length()))), 2.0 * wabs)), MIN_FONT, MAX_FONT)
	var total := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, base_fs).x
	var base := {"text": text, "type_text": type_text, "c": c, "axis": axis}
	if _straight_fits(text, base_fs, c, axis, total, pts, spacing):
		base["mode"] = "straight"
		base["angle"] = atan2(axis.y, axis.x)
		base["base_fs"] = base_fs
		return base
	# Curved: medial-spline baseline, base_fs shrunk to fit the curve length.
	var curve := _build_curve(text, pts, c, axis, amin, amax)
	if curve == null:
		base["mode"] = "straight"
		base["angle"] = atan2(axis.y, axis.x)
		base["base_fs"] = base_fs
		return base
	var s_len := curve.get_baked_length()
	if total > s_len and total > 0.0:
		base_fs = maxi(MIN_FONT, int(float(base_fs) * s_len / total))
	var baked := curve.get_baked_points()
	var aabb := Rect2(baked[0], Vector2.ZERO)
	for p in baked:
		aabb = aabb.expand(p)
	base["mode"] = "curved"
	base["curve"] = curve
	base["s_len"] = s_len
	base["aabb"] = aabb
	base["base_fs"] = base_fs
	return base


## Smooth Catmull-Rom curve through the region's medial points (centerline). null if the
## centerline degenerates to a point.
func _build_curve(text: String, pts: PackedVector2Array, c: Vector2, axis: Vector2, amin: float, amax: float) -> Curve2D:
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
		var idx := clampi(int((d.dot(axis) - amin) / span * k), 0, k - 1)
		sum_a[idx] = float(sum_a[idx]) + d.dot(axis)
		sum_w[idx] = float(sum_w[idx]) + d.dot(perp)
		cnt[idx] = int(cnt[idx]) + 1
	var medial: Array = []
	for i in range(k):
		if int(cnt[i]) == 0:
			continue
		medial.append(c + axis * (float(sum_a[i]) / float(cnt[i])) + perp * (float(sum_w[i]) / float(cnt[i])))
	if medial.size() < 2:
		return null
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
	if curve.get_baked_length() < 1.0:
		return null
	return curve


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


# --- overlap (oriented-bounding-box SAT) ----------------------------------------

## The label's oriented bounding box at font size `fs` (covers title + subtitle).
func _label_obb(cand: Dictionary, fs: int) -> Dictionary:
	var sub_fs := maxi(MIN_SUB_FONT, int(float(fs) * SUB_RATIO))
	var tw := _bold.get_string_size(str(cand["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var sw := _bold.get_string_size(str(cand["type_text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fs).x
	var w := maxf(tw, sw)
	var h := float(fs) * 0.85 + float(sub_fs) * 0.85 + float(fs) * 0.20
	if str(cand["mode"]) == "straight":
		return {"c": cand["c"], "half": Vector2(w * 0.5, h * 0.5), "angle": float(cand["angle"])}
	# Curved: inflate the curve's AABB by the line block (axis-aligned, conservative).
	var aabb: Rect2 = (cand["aabb"] as Rect2).grow(h * 0.5)
	return {"c": aabb.get_center(), "half": aabb.size * 0.5, "angle": 0.0}


func _obb_corners(o: Dictionary) -> PackedVector2Array:
	var a := float(o["angle"])
	var half: Vector2 = o["half"]
	var c: Vector2 = o["c"]
	var ux := Vector2(cos(a), sin(a)) * half.x
	var uy := Vector2(-sin(a), cos(a)) * half.y
	return PackedVector2Array([c - ux - uy, c + ux - uy, c + ux + uy, c - ux + uy])


func _obb_overlap(a: Dictionary, b: Dictionary) -> bool:
	var pa := _obb_corners(a)
	var pb := _obb_corners(b)
	var aa := float(a["angle"])
	var ab := float(b["angle"])
	var axes := [
		Vector2(cos(aa), sin(aa)), Vector2(-sin(aa), cos(aa)),
		Vector2(cos(ab), sin(ab)), Vector2(-sin(ab), cos(ab)),
	]
	for ax in axes:
		var amin := INF
		var amax := -INF
		var bmin := INF
		var bmax := -INF
		for p in pa:
			var d: float = p.dot(ax)
			amin = minf(amin, d)
			amax = maxf(amax, d)
		for p in pb:
			var d: float = p.dot(ax)
			bmin = minf(bmin, d)
			bmax = maxf(bmax, d)
		if amax < bmin or bmax < amin:
			return false   # separating axis → no overlap
	return true


# --- finalize (title + subtitle glyph placement at the resolved fs) -------------

func _finalize(cand: Dictionary) -> Dictionary:
	var fs := int(cand["fs"])
	var text := str(cand["text"])
	var type_text := str(cand["type_text"])
	var sub_fs := maxi(MIN_SUB_FONT, int(float(fs) * SUB_RATIO))
	var sw := _bold.get_string_size(type_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fs).x
	if str(cand["mode"]) == "straight":
		var c: Vector2 = cand["c"]
		var axis: Vector2 = cand["axis"]
		var perp := Vector2(-axis.y, axis.x)
		var angle := float(cand["angle"])
		var tw := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		return {
			"mode": "straight", "text": text, "fs": fs,
			"origin": c - axis * (tw * 0.5) + perp * (fs * 0.30 - sub_fs * 0.55), "angle": angle,
			"sub_text": type_text, "sub_fs": sub_fs,
			"sub_origin": c - axis * (sw * 0.5) + perp * (fs * 0.30 + fs * 0.62), "sub_angle": angle,
		}
	# Curved title + a small straight subtitle below the curve midpoint.
	var curve: Curve2D = cand["curve"]
	var s_len := float(cand["s_len"])
	var axis2: Vector2 = cand["axis"]
	var total := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if total > s_len:
		fs = maxi(MIN_FONT, int(float(fs) * s_len / total))
		total = _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		sub_fs = maxi(MIN_SUB_FONT, int(float(fs) * SUB_RATIO))
		sw = _bold.get_string_size(type_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fs).x
	var glyphs: Array = []
	var arc := maxf(0.0, (s_len - total) * 0.5)
	for i in range(text.length()):
		var cp := text.unicode_at(i)
		var adv := _bold.get_char_size(cp, fs).x
		var mid := clampf(arc + adv * 0.5, 0.0, s_len)
		var pos := curve.sample_baked(mid)
		var tang := curve.sample_baked(clampf(mid + 2.0, 0.0, s_len)) - curve.sample_baked(clampf(mid - 2.0, 0.0, s_len))
		if tang.length() < 0.001:
			tang = axis2
		tang = tang.normalized()
		var gperp := Vector2(-tang.y, tang.x)
		glyphs.append({
			"ch": String.chr(cp), "origin": pos - tang * (adv * 0.5) + gperp * (fs * 0.30),
			"angle": atan2(tang.y, tang.x),
		})
		arc += adv
	var mpos := curve.sample_baked(s_len * 0.5)
	var mtan := curve.sample_baked(clampf(s_len * 0.5 + 2.0, 0.0, s_len)) - curve.sample_baked(clampf(s_len * 0.5 - 2.0, 0.0, s_len))
	if mtan.length() < 0.001:
		mtan = axis2
	mtan = mtan.normalized()
	var mperp := Vector2(-mtan.y, mtan.x)
	return {
		"mode": "curved", "fs": fs, "glyphs": glyphs,
		"sub_text": type_text, "sub_fs": sub_fs,
		"sub_origin": mpos - mtan * (sw * 0.5) + mperp * (fs * 0.92), "sub_angle": atan2(mtan.y, mtan.x),
	}


# --- draw -----------------------------------------------------------------------

func _draw() -> void:
	_ensure_font()
	for pl in _placements:
		var fs := int(pl["fs"])
		if str(pl["mode"]) == "straight":
			_draw_text(str(pl["text"]), pl["origin"], float(pl["angle"]), fs)
		else:
			for g in pl["glyphs"]:
				_draw_glyph(str(g["ch"]), g["origin"], float(g["angle"]), fs)
		if not str(pl.get("sub_text", "")).is_empty():
			_draw_text(str(pl["sub_text"]), pl["sub_origin"], float(pl["sub_angle"]), int(pl["sub_fs"]))


func _draw_text(text: String, origin: Vector2, angle: float, fs: int) -> void:
	draw_set_transform(origin, angle, Vector2.ONE)
	if USE_OUTLINE:
		draw_string_outline(_bold, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(float(fs) * 0.12)), _OUTLINE)
	draw_string(_bold, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _FILL)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_glyph(ch: String, origin: Vector2, angle: float, fs: int) -> void:
	draw_set_transform(origin, angle, Vector2.ONE)
	if USE_OUTLINE:
		draw_char_outline(_bold, Vector2.ZERO, ch, fs, maxi(2, int(float(fs) * 0.12)), _OUTLINE)
	draw_char(_bold, Vector2.ZERO, ch, fs, _FILL)
	draw_set_transform_matrix(Transform2D.IDENTITY)
