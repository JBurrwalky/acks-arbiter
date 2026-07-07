extends Control

## Reusable hex-map view (gdd-campaign-creation-ui.md §5/§6) — shared by Screen C
## (replay, repainted per epoch) and Screen D (static present-day, multi-mode).
##
## Hexes are a RECTANGULAR offset grid: (q, r) = (column, row), flat-top hexes,
## odd columns stepped down half a hex so the map reads as a rectangle (NOT the
## sheared diamond an axial layout produces). View modes recolour the same grid:
##   political  — owner polity colour (replay palette), slate = unowned
##   biome      — terrain/biome colour (forest / dense forest / jungle / swamp / …)
##   elevation  — flat / hills / mountains
##   territory  — civilized / borderlands / wilderness
##   culture    — dominant culture per hex, regardless of realm borders
## Each hex gets a thin outline, and political mode draws a brighter border on
## realm boundaries so adjacent realms of similar hue stay distinct. Hovering a
## hex reveals that layer's data (political & culture also list realm, culture,
## populations and any settlement on the hex).

enum Mode { POLITICAL, BIOME, ELEVATION, TERRITORY, CULTURE }

const _UNOWNED := Color(0.17, 0.16, 0.15)
const _WATER := Color(0.20, 0.34, 0.52)
const _RIVER := Color(0.40, 0.66, 0.95)
const _OUTLINE := Color(0.0, 0.0, 0.0, 0.28)

# Biome palette — distinct hues per Jedidiah's brief: a lincoln-green forest, a
# darker dense forest, a deep lush jungle, and a muddy blue-green swamp (not teal).
const _BIOME := {
	"clear": Color(0.74, 0.69, 0.42),
	"woods": Color(0.30, 0.49, 0.18),    # forest — lincoln green
	"jungle": Color(0.07, 0.42, 0.23),   # deep lush green
	"swamp": Color(0.28, 0.40, 0.36),    # muddy blue-green
	"desert": Color(0.84, 0.73, 0.46),
}
const _BIOME_DENSE_FOREST := Color(0.17, 0.31, 0.11)   # woods + biome_subtype forest_dense
const _BIOME_TAIGA := Color(0.36, 0.47, 0.42)          # woods + forest_taiga — cold blue-green
const _BIOME_TUNDRA := Color(0.78, 0.80, 0.82)         # clear + clear_tundra — pale grey-blue
const _BIOME_SAVANNA := Color(0.80, 0.72, 0.34)        # clear + clear_savanna — dry gold
const _BIOME_GLACIAL := Color(0.88, 0.92, 0.96)        # desert + mountains_glacial — ice
const _BIOME_VOLCANIC := Color(0.34, 0.16, 0.15)       # mountains_volcanic — dark basalt/ember

# Pointillist dapple: a per-forest-type speckle drawn over the base fill so the
# green family (forest / taiga / jungle / dense forest) reads apart at a glance.
const _DAPPLE := {
	"forest": Color(0.47, 0.63, 0.27),   # woods (plain) — lighter leaf-green
	"taiga": Color(0.66, 0.74, 0.70),    # forest_taiga — frost
	"jungle": Color(0.18, 0.62, 0.31),   # jungle — bright lime
	"dense": Color(0.09, 0.19, 0.06),    # forest_dense — deep shadow
}

const _ELEV := {
	"flat": Color(0.56, 0.62, 0.40), "hills": Color(0.55, 0.45, 0.30),
	"mountains": Color(0.52, 0.50, 0.47),
}
# Territory — borderlands darkened so it reads clearly between civilized & wilderness.
const _TERR := {
	"civilized": Color(0.86, 0.78, 0.54),
	"borderlands": Color(0.52, 0.42, 0.24),
	"wilderness": Color(0.34, 0.40, 0.30),
}

# Region labels (Jedidiah 2026-06-24) — bold names for the big strategic features:
# continents over land, oceans & seas over water. Straight, centred on the region,
# sized to its extent; placed biggest-first and shrunk/skipped on overlap (OBB-SAT).
# Only these three subtypes from setting_regions are labelled here.
const _LABEL_SUBTYPES := {"continent": true, "ocean": true, "sea": true}
const _LABEL_FILL := Color(0.0, 0.0, 0.0, 1.0)
const _LABEL_OUTLINE := Color(0.97, 0.96, 0.90, 0.85)
const _LABEL_MIN_FONT := 10
const _LABEL_MAX_FONT := 40
const _LABEL_ADVANCE_RATIO := 0.62
const _LABEL_EMBOLDEN := 0.55
const _LABEL_TILT_ASPECT := 1.5    # only tilt regions longer than this; blobs stay horizontal
const _LABEL_SHRINK_STEP := 0.82

var _hexes: Array = []          # full setting_hexes rows (SELECT *)
var _rivers: Array = []         # setting_river_edges rows (drawn as edge segments)
var _colors: Dictionary = {}    # polity_id -> Color (replay palette)
var _owner_override: Dictionary = {}   # Vector2i -> polity_id (replay frame); empty = use hex.owner
var _culture_override: Dictionary = {} # Vector2i -> culture_id (replay frame); empty = present-day
var _territory_override: Dictionary = {} # Vector2i -> territory_class (replay frame); empty = present-day
var _settlements: Array = []
var _settle_by_hex: Dictionary = {}    # Vector2i -> settlement row (tooltip)
var _polity_names: Dictionary = {}     # polity_id -> realm name (tooltip + legend)
var _polity_lieges: Dictionary = {}    # polity_id -> liege_id (sovereign resolution)
var _polity_tiers: Dictionary = {}     # polity_id -> tier_index (border weight by rank)
var _polity_seed_labels: Dictionary = {}  # polity_id -> culture-seed label ("Vallican_01"), replay
var _culture_colors: Dictionary = {}   # culture_id -> Color (lazy, deterministic)
var _mode: int = Mode.POLITICAL
var _sovereign_view: bool = false      # political mode: colour by top-of-liege-chain
var _replay_mode: bool = false         # replay: per-frame ownership only; no present-day data
var _regions: Array = []               # named continent/ocean/sea regions (24-mi hexes JSON)
var _label_font: FontVariation = null  # lazy bold font for the region labels

# Layout cached from the last _draw, so the tooltip hit-test maps a pixel→hex.
var _R := 0.0
var _margin := 8.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_settlements(s: Array) -> void:
	_settlements = s
	_settle_by_hex = {}
	for row in s:
		_settle_by_hex[Vector2i(int(row.get("hex_q", 0)), int(row.get("hex_r", 0)))] = row
	queue_redraw()


## River edges (SettingRepository.list_river_edges) — drawn as line segments along the
## owning hex's edge, matching the gametime map (HexMapRenderer._draw_river_edge).
func set_rivers(edges: Array) -> void:
	_rivers = edges
	queue_redraw()


## Continent / sea / ocean regions (SettingRepository.list_regions) → bold names on the
## strategic map. Only the three big-feature subtypes, and only if named, are kept; the
## rest of the region corpus (terrain clusters, hydronyms, coastal landforms) is ignored
## here — those clutter a strategic overview.
func set_regions(regions: Array) -> void:
	_regions = []
	for reg in regions:
		if not _LABEL_SUBTYPES.has(str(reg.get("subtype", ""))):
			continue
		if str(reg.get("name_primary", "")).strip_edges().is_empty():
			continue
		_regions.append(reg)
	queue_redraw()


## Full realm name + liege + tier maps (from SettingRepository.list_polities) for
## the hover tooltip's "highest realm" (sovereign) resolution, the legend, and the
## tier-graded political borders (higher-rank realms outlined thicker; County and
## below dotted). [param tiers] is optional for back-compat (empty ⇒ all dotted).
func set_polity_meta(names: Dictionary, lieges: Dictionary, tiers: Dictionary = {}) -> void:
	_polity_names = names
	_polity_lieges = lieges
	_polity_tiers = tiers


## Replay shows per-frame OWNERSHIP only; the stored culture/territory/peasants are
## present-day, so the hover suppresses them and reads the frame-aware owner instead.
func set_replay_mode(on: bool) -> void:
	_replay_mode = on


func bind(hexes: Array, palette: Array) -> void:
	_hexes = hexes
	_colors = {}
	for row in palette:
		_colors[str(row.get("polity_id", ""))] = Color.html(str(row.get("color", "#888888")))
	_culture_colors = {}
	_owner_override = {}
	_culture_override = {}
	_territory_override = {}
	queue_redraw()


## Replay drives per-frame ownership; clear to fall back to each hex's owner.
func show_owners(owner_map: Dictionary) -> void:
	_owner_override = owner_map
	queue_redraw()


## Replay drives per-frame dominant-culture per hex (Vector2i -> culture_id, '' = none).
## When non-empty the Culture layer reads THIS frame instead of the present-day map, so
## cultures are watched spreading over the ages. Cleared by bind().
func show_cultures(culture_map: Dictionary) -> void:
	_culture_override = culture_map
	queue_redraw()


## Replay drives per-frame territory class per hex (Vector2i -> civ/borderlands/wilderness).
## When non-empty the Territory layer animates the civilization frontier over the ages.
func show_territories(territory_map: Dictionary) -> void:
	_territory_override = territory_map
	queue_redraw()


## Replay: per-polity culture-seed labels ("Vallican_01") for the frame-aware tooltip,
## so a realm that never earned a proper name reads as its seed culture, not a bare id.
func set_seed_labels(labels: Dictionary) -> void:
	_polity_seed_labels = labels


## Replay: pre-seed the culture→colour map from the FULL set of cultures seen across the
## whole history (not just present-day), so a culture that spreads and then dies out still
## draws in its own colour while scrubbing. Deterministic over sorted culture ids; a no-op
## if colours were already assigned. `ids` should be the union of every frame's cultures.
func seed_culture_colors(ids: Array) -> void:
	if not _culture_colors.is_empty():
		return
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	var i := 0
	for c in sorted_ids:
		if str(c) == "":
			continue
		_culture_colors[str(c)] = WorldPalette.color_at(i)
		i += 1


func set_mode(mode: int) -> void:
	_mode = mode
	queue_redraw()


## Political mode: false = vassal view (every domain its own colour); true =
## sovereign view (each hex takes the colour of the top of its liege chain, so a
## realm and all its vassals read as one power).
func set_sovereign_view(on: bool) -> void:
	_sovereign_view = on
	queue_redraw()


## The polity whose colour/border a hex shows: its direct owner, or — in sovereign
## view — the sovereign at the top of that owner's liege chain.
func _display_owner(h: Dictionary) -> String:
	var o := _hex_owner(h)
	if _sovereign_view and o != "":
		return _sovereign_of(o)
	return o


## Present-day legend entries [{label, color}] for the current mode.
func legend_entries(polity_names: Dictionary = {}) -> Array:
	match _mode:
		Mode.POLITICAL:
			return _ranked_owner_legend(polity_names)
		Mode.CULTURE:
			return _culture_legend()
		Mode.BIOME:
			return [
				{"label": "Plains", "color": _BIOME["clear"]},
				{"label": "Savanna", "color": _BIOME_SAVANNA},
				{"label": "Forest", "color": _BIOME["woods"]},
				{"label": "Dense forest", "color": _BIOME_DENSE_FOREST},
				{"label": "Taiga", "color": _BIOME_TAIGA},
				{"label": "Jungle", "color": _BIOME["jungle"]},
				{"label": "Swamp", "color": _BIOME["swamp"]},
				{"label": "Desert", "color": _BIOME["desert"]},
				{"label": "Tundra", "color": _BIOME_TUNDRA},
				{"label": "Glacier", "color": _BIOME_GLACIAL},
				{"label": "Volcanic", "color": _BIOME_VOLCANIC},
				{"label": "Water", "color": _WATER},
			]
		Mode.ELEVATION:
			return [
				{"label": "Flat", "color": _ELEV["flat"]},
				{"label": "Hills", "color": _ELEV["hills"]},
				{"label": "Mountains", "color": _ELEV["mountains"]},
				{"label": "Water", "color": _WATER},
			]
		Mode.TERRITORY:
			return [
				{"label": "Civilized", "color": _TERR["civilized"]},
				{"label": "Borderlands", "color": _TERR["borderlands"]},
				{"label": "Wilderness", "color": _TERR["wilderness"]},
				{"label": "Water", "color": _WATER},
			]
	return []


func _ranked_owner_legend(polity_names: Dictionary) -> Array:
	var names: Dictionary = polity_names if not polity_names.is_empty() else _polity_names
	var count := {}
	for h in _hexes:
		var o := _display_owner(h)
		if o != "":
			count[o] = int(count.get(o, 0)) + 1
	var ids: Array = count.keys()
	ids.sort_custom(func(a, b): return int(count[a]) > int(count[b]))
	var out: Array = []
	for pid in ids:
		out.append({"label": str(names.get(pid, pid)), "color": _colors.get(pid, _UNOWNED)})
	return out


func _culture_legend() -> Array:
	_ensure_culture_colors()
	var count := {}
	for h in _hexes:
		if str(h.get("water", "")) != "":
			continue
		var c := _dominant_culture(h)
		if c != "":
			count[c] = int(count.get(c, 0)) + 1
	var ids: Array = count.keys()
	ids.sort_custom(func(a, b): return int(count[a]) > int(count[b]))
	var out: Array = []
	for cid in ids:
		out.append({"label": str(cid).capitalize(), "color": _culture_colors.get(cid, _UNOWNED)})
	return out


# --- culture colouring -------------------------------------------------------

func _dominant_culture(h: Dictionary) -> String:
	var raw = h.get("culture_weights", "{}")
	var d = raw
	if raw is String:
		d = JSON.parse_string(raw)
	if typeof(d) != TYPE_DICTIONARY or d.is_empty():
		return ""
	var best := ""
	var bestw := -1.0
	for k in d:
		var w := float(d[k])
		if w > bestw:
			bestw = w
			best = str(k)
	return best


## Deterministic culture→colour, assigned in sorted culture order over the map.
func _ensure_culture_colors() -> void:
	if not _culture_colors.is_empty():
		return
	var seen: Array = []
	for h in _hexes:
		if str(h.get("water", "")) != "":
			continue
		var c := _dominant_culture(h)
		if c != "" and not seen.has(c):
			seen.append(c)
	seen.sort()
	var i := 0
	for c in seen:
		_culture_colors[c] = WorldPalette.color_at(i)
		i += 1


# --- drawing -----------------------------------------------------------------

func _draw() -> void:
	if _hexes.is_empty():
		return
	if _mode == Mode.CULTURE:
		_ensure_culture_colors()
	# Extent in EVEN-Q OFFSET space (axial row r maps to row + (q-(q&1))/2), so the
	# parallelogram of axial hexes fits the rect without clipping.
	var max_col := 0
	var max_row := 0
	for h in _hexes:
		var hq := int(h["q"])
		max_col = maxi(max_col, hq)
		max_row = maxi(max_row, int(h["r"]) + (hq - (hq & 1)) / 2)
	_margin = 8.0
	var rx := (size.x - 2.0 * _margin) / (1.5 * float(max_col + 1) + 0.5)
	var ry := (size.y - 2.0 * _margin) / ((float(max_row) + 2.0) * sqrt(3.0))
	_R = minf(rx, ry)
	var owner_by := {}
	for h in _hexes:
		owner_by[Vector2i(int(h["q"]), int(h["r"]))] = _display_owner(h)
	for h in _hexes:
		var q := int(h["q"])
		var r := int(h["r"])
		var center := _center_of(q, r)
		_draw_hex(center, _R, _hex_color(h))
		if _mode == Mode.BIOME and _is_forest_family(h):
			_draw_dapple(center, _R, _dapple_accent(h), q, r)
		if _mode == Mode.POLITICAL:
			var owner := str(owner_by.get(Vector2i(q, r), ""))
			if owner != "":
				var b := _realm_border(owner_by, q, r, owner)
				_draw_hex_outline(center, _R, b[0], b[1], b[2])
	_draw_rivers()
	# City markers (Class I-III larger). Drawn on top of the hexes.
	for s in _settlements:
		var sc := _center_of(int(s.get("hex_q", 0)), int(s.get("hex_r", 0)))
		var mrad: float = _R * (0.5 if int(s.get("market_class", 6)) <= 3 else 0.32)
		draw_circle(sc, mrad, Color(0.99, 0.96, 0.84))
		draw_circle(sc, mrad, Color(0.18, 0.10, 0.04), false, 1.0)
	# Continent / sea / ocean names, on top of everything else.
	_draw_region_labels()


## Draw river edges as line segments along the owning hex's edge, matching the gametime
## map (HexMapRenderer._draw_river_edge): edge e spans hex vertices (e+4)%6 and (e+5)%6
## (flat-top, vertex n at 60°·n). Width encodes the river class. Drawn over the fills.
func _draw_rivers() -> void:
	if _rivers.is_empty() or _R <= 0.0:
		return
	for row in _rivers:
		var center := _center_of(int(row.get("hex_q", 0)), int(row.get("hex_r", 0)))
		var verts := _edge_vertex_offsets(int(row.get("edge", 0)))
		var wcat := str(row.get("width_category", "stream"))
		var w := 3.0 if wcat == "major_river" else (2.2 if wcat == "river" else 1.4)
		draw_line(center + verts[0], center + verts[1], _RIVER, w)


## Pixel offsets of edge e's two endpoints from the hex centre (flat-top circumradius _R).
## Edge e spans vertices (e+4)%6 and (e+5)%6 — ported from HexMapRenderer so the segment
## lies on the same edge the gametime map draws. Edge numbering 0=N, 1=NE … 5=NW.
func _edge_vertex_offsets(e: int) -> Array:
	var a := deg_to_rad(60.0 * float((e + 4) % 6))
	var b := deg_to_rad(60.0 * float((e + 5) % 6))
	return [Vector2(cos(a), sin(a)) * _R, Vector2(cos(b), sin(b)) * _R]


## Pixel centre of AXIAL hex (q, r), matching the gametime map: axial → even-q offset
## (HexMapController.axial_to_godot_map) then a flat-top hex layout. The axial→offset
## conversion is exactly what the review view was missing — without it, axial-adjacent
## hexes (a realm's own land) landed non-adjacent on screen, so contiguous realms rendered
## with phantom gaps ("orphans"). Columns are spaced 1.5R; rows √3·R; ODD columns drop a
## half-row — matching Godot's TileMapLayer (TILE_OFFSET_AXIS_VERTICAL), which staggers
## odd columns down, so the review map is PIXEL-IDENTICAL to the gametime map (the old
## even-column shift drew even columns a full row low vs gametime). Uses the cached
## `_max_row` extent so the layout fills the rect.
func _center_of(q: int, r: int) -> Vector2:
	var col := q
	var row := r + (q - (q & 1)) / 2     # axial → even-q offset (matches gametime)
	var col_shift := 0.5 if (col & 1) == 1 else 0.0
	return Vector2(
		_margin + _R + 1.5 * _R * float(col),
		_margin + sqrt(3.0) * _R * (float(row) + col_shift + 0.5))


func _hex_owner(h: Dictionary) -> String:
	var key := Vector2i(int(h["q"]), int(h["r"]))
	if not _owner_override.is_empty():
		return str(_owner_override.get(key, ""))
	return str(h.get("owner_polity_id", ""))


func _hex_color(h: Dictionary) -> Color:
	if str(h.get("water", "")) != "":
		return _WATER
	match _mode:
		Mode.POLITICAL:
			var o := _display_owner(h)
			return _colors.get(o, _UNOWNED) if o != "" else _UNOWNED
		Mode.BIOME:
			return _biome_color(h)
		Mode.ELEVATION:
			return _ELEV.get(str(h.get("elevation", "")), _ELEV["flat"])
		Mode.TERRITORY:
			return _TERR.get(_territory_of(h), _UNOWNED)
		Mode.CULTURE:
			var c := _culture_of(h)
			return _culture_colors.get(c, _UNOWNED) if c != "" else _UNOWNED
	return _UNOWNED


## Dominant culture for the current view: the replay frame's value when a per-frame
## override is loaded (Culture layer animates), else the present-day hex substrate.
func _culture_of(h: Dictionary) -> String:
	if not _culture_override.is_empty():
		return str(_culture_override.get(Vector2i(int(h["q"]), int(h["r"])), ""))
	return _dominant_culture(h)


## Territory class for the current view: the replay frame's value when a per-frame
## override is loaded (Territory layer animates), else the present-day hex class.
func _territory_of(h: Dictionary) -> String:
	if not _territory_override.is_empty():
		var tc := str(_territory_override.get(Vector2i(int(h["q"]), int(h["r"])), ""))
		if tc != "":
			return tc
	return str(h.get("territory_class", ""))


## Biome fill colour, resolving the meaningful subtypes (tundra/taiga/savanna/
## glacial/dense forest) before falling back to the base biome.
func _biome_color(h: Dictionary) -> Color:
	match str(h.get("biome_subtype", "")):
		"forest_dense": return _BIOME_DENSE_FOREST
		"forest_taiga": return _BIOME_TAIGA
		"clear_tundra": return _BIOME_TUNDRA
		"clear_savanna": return _BIOME_SAVANNA
		"mountains_glacial": return _BIOME_GLACIAL
		"mountains_volcanic": return _BIOME_VOLCANIC
	return _BIOME.get(str(h.get("biome", "")), _UNOWNED)


## Forest-family hexes (the greens) get the pointillist dapple.
func _is_forest_family(h: Dictionary) -> bool:
	var b := str(h.get("biome", ""))
	return b == "woods" or b == "jungle"


## Speckle accent encoding which green this hex is.
func _dapple_accent(h: Dictionary) -> Color:
	if str(h.get("biome", "")) == "jungle":
		return _DAPPLE["jungle"]
	match str(h.get("biome_subtype", "")):
		"forest_taiga": return _DAPPLE["taiga"]
		"forest_dense": return _DAPPLE["dense"]
	return _DAPPLE["forest"]


## Draw ~6 small accent dots inside a hex at positions derived from (q, r), so the
## speckle pattern is stable across redraws (no flicker) yet varies hex to hex.
func _draw_dapple(center: Vector2, radius: float, accent: Color, q: int, r: int) -> void:
	var dot := maxf(radius * 0.13, 1.0)
	var hsh := ((q * 374761393) ^ (r * 668265263)) & 0x7fffffff
	for _i in 6:
		hsh = (hsh * 1103515245 + 12345) & 0x7fffffff
		var ang := TAU * float(hsh % 997) / 997.0
		hsh = (hsh * 1103515245 + 12345) & 0x7fffffff
		var dist := radius * 0.55 * sqrt(float(hsh % 997) / 997.0)
		draw_circle(center + Vector2(cos(ang), sin(ang)) * dist, dot, accent)


## Political-mode hex outline as [colour, width, dashed]. A realm boundary (the hex
## has a neighbour of a different owner, or borders unclaimed land) is drawn at a
## weight set by the owner's RANK: Empire/Kingdom thickest, Duchy/Principality medium,
## County-and-below a thin DOTTED line — so the many small low-tier realms stop
## drowning out the big ones. Interior hexes (all neighbours same owner) keep the
## faint per-hex grid. In sovereign view the owner already IS its sovereign, so the
## weight tracks the whole realm's rank.
func _realm_border(owner_by: Dictionary, q: int, r: int, owner: String) -> Array:
	for n in _neighbors(q, r):
		if owner_by.has(n) and str(owner_by[n]) != owner:
			return _border_style(int(_polity_tiers.get(owner, 0)))
	return [_OUTLINE, 1.0, false]


## Border [colour, width, dashed] for a realm of [param tier] (DomainTierTable index
## 0=Barony … 6=Empire). Higher rank → thicker & more opaque; County (2) and below
## switch to a dotted line so they read as subordinate divisions, not hard frontiers.
func _border_style(tier: int) -> Array:
	match tier:
		6: return [Color(1.00, 0.97, 0.86, 0.98), 3.0, false]   # Empire
		5: return [Color(0.99, 0.95, 0.83, 0.95), 2.6, false]   # Kingdom
		4: return [Color(0.97, 0.93, 0.80, 0.90), 2.1, false]   # Principality
		3: return [Color(0.95, 0.91, 0.78, 0.85), 1.6, false]   # Duchy
		2: return [Color(0.93, 0.89, 0.76, 0.80), 1.2, true]    # County (dotted)
	return [Color(0.90, 0.86, 0.73, 0.65), 1.0, true]           # March / Barony (dotted)


func _neighbors(q: int, r: int) -> Array:
	# AXIAL neighbours — the data's true adjacency (matches the sim's _OFF and
	# HexMapController.get_neighbors), so realm-boundary outlines align with the fills.
	return [Vector2i(q + 1, r), Vector2i(q - 1, r), Vector2i(q + 1, r - 1),
		Vector2i(q - 1, r + 1), Vector2i(q, r - 1), Vector2i(q, r + 1)]


func _draw_hex(center: Vector2, radius: float, col: Color) -> void:
	draw_colored_polygon(_hex_poly(center, radius), col)


func _draw_hex_outline(center: Vector2, radius: float, col: Color, width: float = 1.0,
		dashed: bool = false) -> void:
	var poly := _hex_poly(center, radius)
	if dashed:
		var dash := maxf(radius * 0.45, 3.0)
		for i in 6:
			draw_dashed_line(poly[i], poly[(i + 1) % 6], col, width, dash)
		return
	poly.append(poly[0])
	draw_polyline(poly, col, width)


func _hex_poly(center: Vector2, radius: float) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for k in 6:
		var a := deg_to_rad(60.0 * float(k))
		poly.append(center + Vector2(cos(a), sin(a)) * radius)
	return poly


# --- region labels (continent / sea / ocean) --------------------------------

func _ensure_label_font() -> void:
	if _label_font == null:
		_label_font = FontVariation.new()
		_label_font.base_font = ThemeDB.fallback_font
		_label_font.variation_embolden = _LABEL_EMBOLDEN


## Bold continent / sea / ocean names. Biggest regions first (so continents & oceans keep
## their size); each is sized to its own extent, then shrunk to dodge an already-placed
## label, and skipped only if it can't fit above the minimum size. OBB-SAT collision.
func _draw_region_labels() -> void:
	if _regions.is_empty() or _R <= 0.0:
		return
	_ensure_label_font()
	var ordered := _regions.duplicate()
	ordered.sort_custom(func(a, b): return _region_hex_count(a) > _region_hex_count(b))
	var placed: Array = []
	for reg in ordered:
		var lay := _region_layout(reg)
		if lay.is_empty():
			continue
		var fs := int(lay["max_fs"])
		while fs >= _LABEL_MIN_FONT:
			var box := _label_box(lay, fs)
			var hit := false
			for po in placed:
				if _box_overlap(box, po):
					hit = true
					break
			if not hit:
				placed.append(box)
				_draw_region_label(str(lay["text"]), lay["c"], float(lay["angle"]), fs)
				break
			fs = int(float(fs) * _LABEL_SHRINK_STEP)


func _region_hex_count(reg: Dictionary) -> int:
	var parsed = JSON.parse_string(str(reg.get("hexes", "[]")))
	return (parsed as Array).size() if parsed is Array else 0


## Pixel centres of a region's member hexes (24-mile axial → map pixel, via _center_of).
func _region_member_px(reg: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var parsed = JSON.parse_string(str(reg.get("hexes", "[]")))
	if not (parsed is Array):
		return out
	for pair in parsed:
		if pair is Array and (pair as Array).size() == 2:
			out.append(_center_of(int(pair[0]), int(pair[1])))
	return out


## Straight-label layout for a region: centroid, axis (the long axis for an elongated
## region, horizontal for a blob), and a font size sized to the region's extent & name
## length. Returns {} for an empty region.
func _region_layout(reg: Dictionary) -> Dictionary:
	var pts := _region_member_px(reg)
	if pts.is_empty():
		return {}
	var text := str(reg.get("name_primary", "")).strip_edges()
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	# PCA principal axis of the member cloud.
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
	var ln_pca := _extent_along(pts, c, axis)
	var w_pca := _extent_along(pts, c, Vector2(-axis.y, axis.x))
	# Tilt only elongated regions; a round ocean/sea reads better horizontal.
	if ln_pca < _LABEL_TILT_ASPECT * maxf(1.0, w_pca):
		axis = Vector2.RIGHT
	# Orient the baseline conventionally: left-to-right, and bottom-to-top for a
	# near-vertical label (so a tall sea/ocean name reads upward, not head-down).
	if absf(axis.x) < 0.2:
		if axis.y > 0.0:
			axis = -axis
	elif axis.x < 0.0:
		axis = -axis
	var ln := _extent_along(pts, c, axis)
	var half_w := _extent_along(pts, c, Vector2(-axis.y, axis.x)) * 0.5 + _R
	var fs := clampi(
		int(min(ln / (_LABEL_ADVANCE_RATIO * maxf(1.0, float(text.length()))), 2.0 * half_w)),
		_LABEL_MIN_FONT, _LABEL_MAX_FONT)
	return {"text": text, "c": c, "axis": axis, "angle": atan2(axis.y, axis.x), "max_fs": fs}


## Peak-to-peak span of the points projected onto `dir`.
func _extent_along(pts: PackedVector2Array, c: Vector2, dir: Vector2) -> float:
	var lo := INF
	var hi := -INF
	for p in pts:
		var a := (p - c).dot(dir)
		lo = minf(lo, a)
		hi = maxf(hi, a)
	return maxf(0.0, hi - lo)


## The label's oriented bounding box at size `fs`: {c, half, angle}.
func _label_box(lay: Dictionary, fs: int) -> Dictionary:
	var w := _label_font.get_string_size(str(lay["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return {"c": lay["c"], "half": Vector2(w * 0.5, float(fs) * 0.6), "angle": float(lay["angle"])}


func _box_corners(o: Dictionary) -> PackedVector2Array:
	var a := float(o["angle"])
	var half: Vector2 = o["half"]
	var c: Vector2 = o["c"]
	var ux := Vector2(cos(a), sin(a)) * half.x
	var uy := Vector2(-sin(a), cos(a)) * half.y
	return PackedVector2Array([c - ux - uy, c + ux - uy, c + ux + uy, c - ux + uy])


## Separating-axis test on two oriented boxes (each {c, half, angle}).
func _box_overlap(a: Dictionary, b: Dictionary) -> bool:
	var ca := _box_corners(a)
	var cb := _box_corners(b)
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
		for p in ca:
			var d: float = p.dot(ax)
			amin = minf(amin, d)
			amax = maxf(amax, d)
		for p in cb:
			var d: float = p.dot(ax)
			bmin = minf(bmin, d)
			bmax = maxf(bmax, d)
		if amax < bmin or bmax < amin:
			return false   # separating axis → no overlap
	return true


## One straight, centred, bold-black region name with a light outline (legible over both
## land and water). `c` is the region centroid; the text is centred on it.
func _draw_region_label(text: String, c: Vector2, angle: float, fs: int) -> void:
	var w := _label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var axis := Vector2(cos(angle), sin(angle))
	var perp := Vector2(-axis.y, axis.x)
	var origin := c - axis * (w * 0.5) + perp * (float(fs) * 0.32)
	draw_set_transform(origin, angle, Vector2.ONE)
	draw_string_outline(_label_font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		maxi(2, int(float(fs) * 0.12)), _LABEL_OUTLINE)
	draw_string(_label_font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _LABEL_FILL)
	draw_set_transform_matrix(Transform2D.IDENTITY)


# --- hover tooltip -----------------------------------------------------------

func _get_tooltip(at_position: Vector2) -> String:
	var h := _hex_at(at_position)
	if h.is_empty():
		return ""
	return _tooltip_for(h)


## The hex whose centre is nearest the position (within one hex radius), or {}.
func _hex_at(pos: Vector2) -> Dictionary:
	if _R <= 0.0:
		return {}
	var best := {}
	var best_d := _R * _R
	for h in _hexes:
		var d := pos.distance_squared_to(_center_of(int(h["q"]), int(h["r"])))
		if d < best_d:
			best_d = d
			best = h
	return best


func _tooltip_for(h: Dictionary) -> String:
	var head := "Hex (%d, %d)" % [int(h["q"]), int(h["r"])]
	if str(h.get("water", "")) != "":
		return "%s\n%s" % [head, "Ocean" if str(h["water"]) == "ocean" else "Lake"]
	if _replay_mode:
		return _replay_tooltip(h, head)
	match _mode:
		Mode.BIOME:
			return "%s\nBiome: %s" % [head, _biome_label(h)]
		Mode.ELEVATION:
			return "%s\nElevation: %s  (raw %.3f)" % [head,
				str(h.get("elevation", "flat")).capitalize(), float(h.get("elevation_raw", 0.0))]
		Mode.TERRITORY:
			return "%s\nTerritory: %s" % [head, str(h.get("territory_class", "wilderness")).capitalize()]
		_:   # POLITICAL & CULTURE share the rich realm tooltip
			return _realm_tooltip(h, head)


## Replay hover: every layer reports THIS epoch's frame data, never the present-day
## substrate. Political leads with the culture-seed label so cultures read at a glance;
## Culture and Territory report the frame's dominant culture / advancing frontier.
func _replay_tooltip(h: Dictionary, head: String) -> String:
	var owner := _hex_owner(h)
	match _mode:
		Mode.TERRITORY:
			var tc := _territory_of(h)
			return "%s\nTerritory: %s" % [head, tc.capitalize() if tc != "" else "—"]
		Mode.CULTURE:
			var c := _culture_of(h)
			var lines: Array = [head]
			lines.append("Culture: %s" % (c.capitalize() if c != "" else "None"))
			if owner != "":
				lines.append("Realm: %s" % _owner_label(owner))
			return "\n".join(lines)
		_:   # POLITICAL — per-frame ownership, seed-labelled
			return "%s\nRealm: %s" % [head, _owner_label(owner)] if owner != "" \
				else "%s\nUnclaimed this epoch" % head


## The replay owner label: the culture-seed identity ("Vallican_01") first, with the
## realm's eventual proper name in parentheses when it earned one — so the seed culture
## is always legible while scrubbing, without falling back to a bare pol id.
func _owner_label(pid: String) -> String:
	var seed := str(_polity_seed_labels.get(pid, ""))
	var nm := str(_polity_names.get(pid, ""))
	if seed == "":
		return nm if nm != "" else pid
	if nm != "" and nm != pid:
		return "%s (%s)" % [seed, nm]
	return seed


func _biome_label(h: Dictionary) -> String:
	match str(h.get("biome_subtype", "")):
		"forest_dense": return "Dense forest"
		"forest_taiga": return "Taiga"
		"clear_tundra": return "Tundra"
		"clear_savanna": return "Savanna"
		"clear_grassland": return "Grassland"
		"mountains_glacial": return "Glacier"
		"mountains_volcanic": return "Volcanic mountains"
	match str(h.get("biome", "clear")):
		"woods": return "Forest"
		"jungle": return "Jungle"
		"swamp": return "Swamp"
		"desert": return "Desert"
	return "Plains"


func _realm_tooltip(h: Dictionary, head: String) -> String:
	var lines: Array = [head]
	# Frame-aware owner: in replay this honours the displayed epoch's ownership.
	var owner := _hex_owner(h)
	if _replay_mode:
		# Only per-frame ownership is known for a past epoch; the stored culture,
		# territory and population are present-day, so don't report them here.
		lines.append("Realm: %s" % str(_polity_names.get(owner, owner)) if owner != ""
			else "Unclaimed this epoch")
		return "\n".join(lines)
	if owner == "":
		lines.append("Unclaimed wilderness")
	else:
		var sovereign := _sovereign_of(owner)
		lines.append(str(_polity_names.get(sovereign, sovereign)))
		if sovereign != owner:
			lines.append("  held by %s" % str(_polity_names.get(owner, owner)))
	var cult := _dominant_culture(h)
	if cult != "":
		lines.append("Culture: %s" % cult.capitalize())
	lines.append("Territory: %s" % str(h.get("territory_class", "wilderness")).capitalize())
	var peasants := int(h.get("population_band", 0))
	if peasants > 0:
		lines.append("Peasants: %s families (~%s people)" % [
			_thousands(peasants), _thousands(peasants * 5)])
	var key := Vector2i(int(h["q"]), int(h["r"]))
	if _settle_by_hex.has(key):
		var s: Dictionary = _settle_by_hex[key]
		var uf := int(s.get("urban_families", 0))
		if uf > 0:
			lines.append("Urban: %s families (~%s people)" % [_thousands(uf), _thousands(uf * 5)])
		var nm := str(s.get("name", ""))
		if nm != "":
			lines.append("⚑ %s — Market Class %s" % [nm, _market_roman(int(s.get("market_class", 6)))])
	return "\n".join(lines)


## Follow the liege chain to the sovereign (the "highest" realm the hex is part of).
func _sovereign_of(pid: String) -> String:
	var cur := pid
	var guard := 0
	while _polity_lieges.has(cur) and str(_polity_lieges[cur]) != "" and guard < 32:
		cur = str(_polity_lieges[cur])
		guard += 1
	return cur


func _market_roman(mc: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI"][clampi(mc, 1, 6)]


func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
