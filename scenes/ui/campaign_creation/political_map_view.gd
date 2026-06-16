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

var _hexes: Array = []          # full setting_hexes rows (SELECT *)
var _colors: Dictionary = {}    # polity_id -> Color (replay palette)
var _owner_override: Dictionary = {}   # Vector2i -> polity_id (replay frame); empty = use hex.owner
var _settlements: Array = []
var _settle_by_hex: Dictionary = {}    # Vector2i -> settlement row (tooltip)
var _polity_names: Dictionary = {}     # polity_id -> realm name (tooltip + legend)
var _polity_lieges: Dictionary = {}    # polity_id -> liege_id (sovereign resolution)
var _culture_colors: Dictionary = {}   # culture_id -> Color (lazy, deterministic)
var _mode: int = Mode.POLITICAL
var _sovereign_view: bool = false      # political mode: colour by top-of-liege-chain

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


## Full realm name + liege maps (from SettingRepository.list_polities) for the
## hover tooltip's "highest realm" (sovereign) resolution and the legend.
func set_polity_meta(names: Dictionary, lieges: Dictionary) -> void:
	_polity_names = names
	_polity_lieges = lieges


func bind(hexes: Array, palette: Array) -> void:
	_hexes = hexes
	_colors = {}
	for row in palette:
		_colors[str(row.get("polity_id", ""))] = Color.html(str(row.get("color", "#888888")))
	_culture_colors = {}
	queue_redraw()


## Replay drives per-frame ownership; clear to fall back to each hex's owner.
func show_owners(owner_map: Dictionary) -> void:
	_owner_override = owner_map
	queue_redraw()


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
				{"label": "Forest", "color": _BIOME["woods"]},
				{"label": "Dense forest", "color": _BIOME_DENSE_FOREST},
				{"label": "Jungle", "color": _BIOME["jungle"]},
				{"label": "Swamp", "color": _BIOME["swamp"]},
				{"label": "Desert", "color": _BIOME["desert"]},
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
	var maxq := 0
	var maxr := 0
	for h in _hexes:
		maxq = maxi(maxq, int(h["q"]))
		maxr = maxi(maxr, int(h["r"]))
	var cols := maxq + 1
	var rows := maxr + 1
	_margin = 8.0
	var rx := (size.x - 2.0 * _margin) / (1.5 * float(cols) + 0.5)
	var ry := (size.y - 2.0 * _margin) / ((float(rows) + 0.5) * sqrt(3.0))
	_R = minf(rx, ry)
	var owner_by := {}
	for h in _hexes:
		owner_by[Vector2i(int(h["q"]), int(h["r"]))] = _display_owner(h)
	for h in _hexes:
		var q := int(h["q"])
		var r := int(h["r"])
		var center := _center_of(q, r)
		_draw_hex(center, _R, _hex_color(h))
		if _mode == Mode.POLITICAL:
			var owner := str(owner_by.get(Vector2i(q, r), ""))
			if owner != "":
				_draw_hex_outline(center, _R, _border_for(owner_by, q, r, owner))
	# City markers (Class I-III larger). Drawn on top of the hexes.
	for s in _settlements:
		var sc := _center_of(int(s.get("hex_q", 0)), int(s.get("hex_r", 0)))
		var mrad: float = _R * (0.5 if int(s.get("market_class", 6)) <= 3 else 0.32)
		draw_circle(sc, mrad, Color(0.99, 0.96, 0.84))
		draw_circle(sc, mrad, Color(0.18, 0.10, 0.04), false, 1.0)


## Pixel centre of hex (q, r) in the rectangular offset layout (odd-q stepped).
func _center_of(q: int, r: int) -> Vector2:
	return Vector2(
		_margin + _R + 1.5 * _R * float(q),
		_margin + sqrt(3.0) * _R * (float(r) + 0.5 * float(q & 1)) + sqrt(3.0) * _R * 0.5)


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
			if str(h.get("biome_subtype", "")) == "forest_dense":
				return _BIOME_DENSE_FOREST
			return _BIOME.get(str(h.get("biome", "")), _UNOWNED)
		Mode.ELEVATION:
			return _ELEV.get(str(h.get("elevation", "")), _ELEV["flat"])
		Mode.TERRITORY:
			return _TERR.get(str(h.get("territory_class", "")), _UNOWNED)
		Mode.CULTURE:
			var c := _dominant_culture(h)
			return _culture_colors.get(c, _UNOWNED) if c != "" else _UNOWNED
	return _UNOWNED


## A realm-boundary outline is brighter than the per-hex outline so similar
## adjacent realm colours separate; interior hexes get the faint default.
func _border_for(owner_by: Dictionary, q: int, r: int, owner: String) -> Color:
	for n in _neighbors(q, r):
		if str(owner_by.get(n, owner)) != owner:
			return Color(0.95, 0.92, 0.8, 0.5)
	return _OUTLINE


func _neighbors(q: int, r: int) -> Array:
	# Flat-top offset neighbours (odd-q vertical layout).
	if q & 1:
		return [Vector2i(q + 1, r), Vector2i(q + 1, r + 1), Vector2i(q, r + 1),
			Vector2i(q - 1, r + 1), Vector2i(q - 1, r), Vector2i(q, r - 1)]
	return [Vector2i(q + 1, r - 1), Vector2i(q + 1, r), Vector2i(q, r + 1),
		Vector2i(q - 1, r), Vector2i(q - 1, r - 1), Vector2i(q, r - 1)]


func _draw_hex(center: Vector2, radius: float, col: Color) -> void:
	draw_colored_polygon(_hex_poly(center, radius), col)


func _draw_hex_outline(center: Vector2, radius: float, col: Color) -> void:
	var poly := _hex_poly(center, radius)
	poly.append(poly[0])
	draw_polyline(poly, col, 1.0)


func _hex_poly(center: Vector2, radius: float) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for k in 6:
		var a := deg_to_rad(60.0 * float(k))
		poly.append(center + Vector2(cos(a), sin(a)) * radius)
	return poly


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


func _biome_label(h: Dictionary) -> String:
	if str(h.get("biome_subtype", "")) == "forest_dense":
		return "Dense forest"
	match str(h.get("biome", "clear")):
		"woods": return "Forest"
		"jungle": return "Jungle"
		"swamp": return "Swamp"
		"desert": return "Desert"
	return "Plains"


func _realm_tooltip(h: Dictionary, head: String) -> String:
	var lines: Array = [head]
	var owner := str(h.get("owner_polity_id", ""))
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
