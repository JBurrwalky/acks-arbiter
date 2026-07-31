class_name BattleMapGenerator
extends RefCounted

## Terrain-driven wilderness battle map generator
## (gdd-combat-map-generation.md §5, §7). Produces a 70×70 (default) voxel
## battle map from a hex terrain context: seeded heightfield with natural
## slopes, terrain-keyed obstacles from BattleMapObstacleCatalog, watercourses
## with depth-gated wading, surface painting, and a validated spawn-reachability
## guarantee (BattleMapValidator): every spawn-eligible cell is ground-walkable
## from the party anchor without climbing throws, damaging falls, or deep
## water — except across the divider of a deliberate split map (§7.4).
##
## Entry point: BattleMapGenerator.generate(context) -> Dictionary
##   context: seed:int, terrain_category:String (fallback), and optionally
##            biome / elevation / biome_subtype / water / has_river /
##            civilization / territory / width / height.
##   result:  { map: VoxelMapData, party_zone: Array[Vector3i], is_split: bool,
##              divider: String, template_key: String, components: int }
##
## All randomness flows through one seeded RNG + seeded FastNoiseLite —
## same context ⇒ byte-identical map (to_dict()).

const DEFAULT_SIZE := 70          ## 350' per side — the 30%-shrunk battlemap
const MAIN_COMPONENT_FRACTION := 0.85
const SPLIT_SIDE_FRACTION := 0.25
const STRAGGLER_FRACTION := 0.05  ## comps above this get carved into the main
const MAX_REPAIR_ITERATIONS := 12
const MAX_COLUMN_LEVELS := 16     ## restamp clears columns up to this level

# Water-plan kinds (per-column).
const W_NONE := 0
const W_SHALLOW := 1
const W_DEEP := 2
const W_LAVA := 3

var _w: int = DEFAULT_SIZE
var _h: int = DEFAULT_SIZE
var _rng := RandomNumberGenerator.new()
var _t: Dictionary = {}
var _heights: PackedInt32Array
var _water_kind: PackedInt32Array
var _water_depth: PackedInt32Array
var _bridge_level: PackedInt32Array   # -1 = no deck
var _floor: PackedStringArray
var _protected: Dictionary = {}       # column idx -> true (crossings, spawn pocket)
var _map: VoxelMapData = null
var _divider: String = ""
var _split_intended: bool = false
var _party_anchor := Vector3i(-1, -1, -1)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

static func generate(context: Dictionary) -> Dictionary:
	var g := BattleMapGenerator.new()
	return g._run(context)


func _run(context: Dictionary) -> Dictionary:
	_w = maxi(8, int(context.get("width", DEFAULT_SIZE)))
	_h = maxi(8, int(context.get("height", DEFAULT_SIZE)))
	_rng.seed = int(context.get("seed", 0))
	_t = BattleMapTemplates.select(context)

	var n := _w * _h
	_heights = PackedInt32Array()
	_heights.resize(n)
	_water_kind = PackedInt32Array()
	_water_kind.resize(n)
	_water_depth = PackedInt32Array()
	_water_depth.resize(n)
	_bridge_level = PackedInt32Array()
	_bridge_level.resize(n)
	_bridge_level.fill(-1)
	_floor = PackedStringArray()
	_floor.resize(n)

	_build_heights()
	_apply_mountain_features()
	_plan_water(context)
	_paint_floors()
	_reserve_party_pocket()

	_map = VoxelMapData.new()
	_map.id = "battlefield_%d" % _rng.seed
	_map.name = "Battlefield (%s)" % str(_t["key"])
	_map.theme = "wilderness"
	_map.generation_seed = int(context.get("seed", 0))
	_map.natural_slopes = true
	for col in range(_w):
		for row in range(_h):
			_stamp_column(col, row)

	_place_obstacles()
	var analysis := _validate_and_repair()
	BattleMapValidator.stamp_zone_indices(_map, analysis)
	var party_zone := _finalize_spawn(analysis)

	return {
		"map": _map,
		"party_zone": party_zone,
		"is_split": _split_intended,
		"divider": _divider,
		"template_key": str(_t["key"]),
		"components": (analysis["components"] as Array).size(),
	}


# ---------------------------------------------------------------------------
# Heightfield
# ---------------------------------------------------------------------------

func _idx(col: int, row: int) -> int:
	return row * _w + col


func _in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < _w and row >= 0 and row < _h


func _make_noise(freq: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = freq
	return noise


func _build_heights() -> void:
	var amp: int = int(_t["amp"])
	# Mountains get a rolling walkable base; the drama comes from the
	# escarpment/chasm pass in _apply_mountain_features().
	var base_amp: int = mini(amp, 4) if str(_t["elevation"]) == "mountains" else amp
	var noise := _make_noise(float(_t["freq"]))
	var plateau: bool = bool(_t.get("plateau", false))

	for row in range(_h):
		for col in range(_w):
			var v: float = (noise.get_noise_2d(float(col), float(row)) + 1.0) * 0.5
			var hgt: int
			if plateau:
				# Badlands mesas: flat floor with sharp two-level tables.
				if v > 0.80:
					hgt = mini(4, amp)
				elif v > 0.62:
					hgt = mini(2, amp)
				else:
					hgt = 0
			else:
				hgt = clampi(int(floor(v * float(base_amp + 1))), 0, base_amp)
			_heights[_idx(col, row)] = hgt

	if not plateau:
		_clamp_slopes(1)  # base terrain is fully walkable; cliffs are added deliberately


## Slope-limit pass: no column may exceed its lowest neighbor by more than
## [param max_step]. Repeats until stable.
func _clamp_slopes(max_step: int) -> void:
	for _pass in range(12):
		var changed := false
		for row in range(_h):
			for col in range(_w):
				var i := _idx(col, row)
				var lowest := _heights[i]
				for offset: Vector2i in VoxelGrid.DIRECTION_OFFSETS:
					var nc := col + offset.x
					var nr := row + offset.y
					if _in_bounds(nc, nr):
						lowest = mini(lowest, _heights[_idx(nc, nr)])
				if _heights[i] > lowest + max_step:
					_heights[i] = lowest + max_step
					changed = true
		if not changed:
			return


# ---------------------------------------------------------------------------
# Mountain features — escarpment / chasm / divider
# ---------------------------------------------------------------------------

func _apply_mountain_features() -> void:
	var is_mountains: bool = str(_t["elevation"]) == "mountains"
	var is_plateau: bool = bool(_t.get("plateau", false))
	if not is_mountains and not is_plateau:
		return

	var lava_pending: bool = _rng.randf() < float(_t.get("lava_chance", 0.0))
	_t["lava_rolled"] = lava_pending
	var divider_rolled: bool = _rng.randf() < float(_t.get("divider_chance", 0.0))

	if not is_mountains:
		# Badlands: mesas came from the plateau heightfield; a rolled divider
		# is an uncrossed escarpment cliff line across the flats.
		if divider_rolled:
			_divider = "cliff"
			_split_intended = true
			_build_escarpment(3, false)
		return

	# Divider roll (§7.4). A rolled divider stays uncrossed (split map);
	# otherwise walkable switchback ramps are carved through the face.
	var raise_levels: int = _rng.randi_range(2, 3)
	if divider_rolled:
		if lava_pending and _rng.randf() < 0.5:
			# The lava flow (planned later) is the divider; the cliff gets ramps.
			_divider = "lava"
			_split_intended = true
			_build_escarpment(raise_levels, true)
		elif _rng.randf() < 0.5:
			_divider = "cliff"
			_split_intended = true
			_build_escarpment(raise_levels, false)
		else:
			_divider = "chasm"
			_split_intended = true
			var center := _build_escarpment(raise_levels, false)
			# Carve the gorge floor along the boundary. The raised far wall is
			# what keeps the sides apart; the low side may slope into the gorge.
			for col in range(_w):
				for row in range(maxi(0, center[col] - 1), mini(_h, center[col] + 2)):
					var i := _idx(col, row)
					_heights[i] = maxi(0, _heights[i] - (raise_levels + 3))
	else:
		_build_escarpment(raise_levels, true)


## Raises everything past a meandering midline by [param raise_levels],
## creating a cliff face along the line. When [param with_ramps], grades two
## stepped switchback notches through the face so ground walkers can cross
## without climbing (§7.5 walkable-route guarantee). Returns the midline.
func _build_escarpment(raise_levels: int, with_ramps: bool) -> PackedInt32Array:
	var base_row: int = _rng.randi_range(int(_h * 0.35), int(_h * 0.65))
	var phase: float = _rng.randf() * TAU
	var meander_amp: float = float(_h) * 0.08
	var center := PackedInt32Array()
	center.resize(_w)
	for col in range(_w):
		center[col] = clampi(
			base_row + int(round(sin(float(col) * 0.09 + phase) * meander_amp)),
			2, _h - 3)

	for col in range(_w):
		for row in range(_h):
			if row > center[col]:
				var i := _idx(col, row)
				_heights[i] = _heights[i] + raise_levels

	if with_ramps:
		for _ramp in range(2):
			var col: int = _rng.randi_range(4, _w - 5)
			var c: int = center[col]
			var low_h: int = _heights[_idx(col, maxi(0, c - 1))]
			for k in range(raise_levels):
				var row: int = c + k
				if not _in_bounds(col, row):
					break
				var i := _idx(col, row)
				_heights[i] = low_h + k + 1
				_protected[i] = true
	return center


# ---------------------------------------------------------------------------
# Water plan
# ---------------------------------------------------------------------------

func _plan_water(context: Dictionary) -> void:
	var water_tag: String = str(context.get("water", ""))
	var has_river: bool = bool(context.get("has_river", false))

	if has_river:
		_plan_river()
	elif _rng.randf() < float(_t.get("stream_chance", 0.0)):
		_plan_stream()

	if water_tag == "ocean":
		_plan_ocean()
	elif water_tag == "lake":
		_plan_lake()

	if bool(_t.get("swamp_water", false)):
		_plan_swamp_pools()

	if bool(_t.get("lava_rolled", false)):
		_plan_lava()

	# Re-smooth fully-walkable templates after water carving so channel banks
	# never leave accidental 2+ level steps (canyon walls belong to mountains
	# and badlands only; those rely on the §7.5 repair pass instead).
	if int(_t.get("max_step", 1)) == 1 and not bool(_t.get("plateau", false)):
		_clamp_slopes(1)


## Returns the meandering row midline for a west→east path.
func _meander_line(amp_frac: float) -> PackedInt32Array:
	var base_row: int = _rng.randi_range(int(_h * 0.3), int(_h * 0.7))
	var phase: float = _rng.randf() * TAU
	var freq: float = _rng.randf_range(0.06, 0.12)
	var amp: float = float(_h) * amp_frac
	var line := PackedInt32Array()
	line.resize(_w)
	for col in range(_w):
		line[col] = clampi(
			base_row + int(round(sin(float(col) * freq + phase) * amp)),
			1, _h - 2)
	return line


## Large watercourse for river-adjacent hexes (§5.6): 3–5 cells wide, deep
## center, shallow edges, banks carved one level down. Crossing roll:
## ford 45% / bridge 20% / none 35% (divider → split map).
func _plan_river() -> void:
	var width: int = _rng.randi_range(3, 5)
	var line := _meander_line(0.10)
	var half: int = width / 2

	# Bed level: one below the lowest terrain the channel crosses.
	var bed: int = 99
	for col in range(_w):
		for row in range(maxi(0, line[col] - half), mini(_h, line[col] + half + 1)):
			bed = mini(bed, _heights[_idx(col, row)])
	bed = maxi(0, bed - 1)

	for col in range(_w):
		for dr in range(-half - 2, half + 3):
			var row: int = line[col] + dr
			if not _in_bounds(col, row):
				continue
			var i := _idx(col, row)
			if abs(dr) <= half:
				_heights[i] = bed
				var is_edge: bool = abs(dr) == half or width <= 2
				_water_kind[i] = W_SHALLOW if is_edge else W_DEEP
				_water_depth[i] = 0 if is_edge else (2 if width >= 4 and dr == 0 else 1)
			else:
				# Banks slope down toward the channel.
				_heights[i] = mini(_heights[i], bed + 1)

	var crossing_roll: float = _rng.randf()
	if crossing_roll < 0.45:
		# Ford: a short stretch where the whole channel is wadeable.
		var ford_col: int = _rng.randi_range(int(_w * 0.2), int(_w * 0.8))
		var ford_w: int = _rng.randi_range(2, 3)
		for col in range(ford_col, mini(_w, ford_col + ford_w)):
			for dr in range(-half, half + 1):
				var row: int = line[col] + dr
				if not _in_bounds(col, row):
					continue
				var i := _idx(col, row)
				if _water_kind[i] == W_DEEP:
					_water_kind[i] = W_SHALLOW
					_water_depth[i] = 0
				_protected[i] = true
	elif crossing_roll < 0.65:
		# Bridge: a deck at bank level spanning the channel.
		var bridge_col: int = _rng.randi_range(int(_w * 0.2), int(_w * 0.8))
		for col in range(bridge_col, mini(_w, bridge_col + 2)):
			for dr in range(-half, half + 1):
				var row: int = line[col] + dr
				if not _in_bounds(col, row):
					continue
				var i := _idx(col, row)
				if _water_kind[i] != W_NONE:
					_bridge_level[i] = bed + 1
				_protected[i] = true
	else:
		# No crossing — the river divides the map (§7.4).
		_divider = "river"
		_split_intended = true


## Small watercourse (§5.6): 1–2 cells wide, all wadeable, never splits.
func _plan_stream() -> void:
	var width: int = _rng.randi_range(1, 2)
	var line := _meander_line(0.14)
	for col in range(_w):
		for dr in range(0, width):
			var row: int = line[col] + dr
			if not _in_bounds(col, row):
				continue
			var i := _idx(col, row)
			if _water_kind[i] != W_NONE:
				continue
			_heights[i] = maxi(0, _heights[i] - 1)
			_water_kind[i] = W_SHALLOW
			_water_depth[i] = 0


## Coastline along one map edge: deep open water with a wadeable rim.
func _plan_ocean() -> void:
	var side: int = _rng.randi_range(0, 3)
	for col in range(_w):
		for row in range(_h):
			var dist: int
			match side:
				0: dist = col
				1: dist = _w - 1 - col
				2: dist = row
				_: dist = _h - 1 - row
			if dist >= 10:
				continue
			var i := _idx(col, row)
			if dist < 8:
				_heights[i] = 0
				if _water_kind[i] == W_NONE or dist < 5:
					_water_kind[i] = W_DEEP if dist < 5 else W_SHALLOW
					_water_depth[i] = 2 if dist < 5 else 0
			else:
				_heights[i] = mini(_heights[i], 1)
				_floor[i] = "sand"


## Pond/lake blob: deep core, wadeable rim, shore flattened to the pour level.
func _plan_lake() -> void:
	var cx: int = _rng.randi_range(int(_w * 0.25), int(_w * 0.75))
	var cy: int = _rng.randi_range(int(_h * 0.25), int(_h * 0.75))
	var radius: int = _rng.randi_range(7, 11)
	var lake_level: int = 99
	for col in range(maxi(0, cx - radius), mini(_w, cx + radius + 1)):
		for row in range(maxi(0, cy - radius), mini(_h, cy + radius + 1)):
			if Vector2(col - cx, row - cy).length() < float(radius):
				lake_level = mini(lake_level, _heights[_idx(col, row)])
	if lake_level == 99:
		return
	for col in range(maxi(0, cx - radius - 2), mini(_w, cx + radius + 3)):
		for row in range(maxi(0, cy - radius - 2), mini(_h, cy + radius + 3)):
			var d: float = Vector2(col - cx, row - cy).length()
			var i := _idx(col, row)
			if d < float(radius - 3):
				_heights[i] = lake_level
				_water_kind[i] = W_DEEP
				_water_depth[i] = 1
			elif d < float(radius):
				_heights[i] = lake_level
				_water_kind[i] = W_SHALLOW
				_water_depth[i] = 0
			elif d < float(radius + 2):
				_heights[i] = mini(_heights[i], lake_level + 1)


## Swamp pool blobs (§5.3): connected shallow zones with a few deep centers.
func _plan_swamp_pools() -> void:
	var pool_noise := _make_noise(0.09)
	for col in range(_w):
		for row in range(_h):
			var i := _idx(col, row)
			if _water_kind[i] != W_NONE:
				continue
			var v: float = (pool_noise.get_noise_2d(float(col), float(row)) + 1.0) * 0.5
			if v > 0.85:
				_water_kind[i] = W_DEEP
				_water_depth[i] = 1
			elif v > 0.60:
				_water_kind[i] = W_SHALLOW
				_water_depth[i] = 0


## Volcanic lava flow (§5.3): meandering 1–3 wide band. A crossing gap is
## guaranteed unless the flow is the map's rolled divider.
func _plan_lava() -> void:
	var width: int = _rng.randi_range(1, 3)
	var line := _meander_line(0.12)
	var gap_col: int = _rng.randi_range(int(_w * 0.25), int(_w * 0.75))
	var gap_w: int = _rng.randi_range(2, 3)
	for col in range(_w):
		var in_gap: bool = _divider != "lava" and col >= gap_col and col < gap_col + gap_w
		for dr in range(0, width):
			var row: int = line[col] + dr
			if not _in_bounds(col, row):
				continue
			var i := _idx(col, row)
			if _water_kind[i] != W_NONE:
				continue
			if in_gap:
				_floor[i] = "lava_rock"
				_protected[i] = true
			else:
				_water_kind[i] = W_LAVA
				_water_depth[i] = 0


# ---------------------------------------------------------------------------
# Surface painting
# ---------------------------------------------------------------------------

func _paint_floors() -> void:
	var paint_noise := _make_noise(0.08)
	var amp: int = int(_t["amp"])
	var is_mountains: bool = str(_t["elevation"]) == "mountains"
	for col in range(_w):
		for row in range(_h):
			var i := _idx(col, row)
			if not _floor[i].is_empty():
				continue  # pre-painted (beach sand, lava gap crust)
			var floor_type: String = str(_t["surface"])
			var v: float = (paint_noise.get_noise_2d(float(col), float(row)) + 1.0) * 0.5
			if v > 0.62:
				floor_type = str(_t["surface_alt"])
			# Scree/rock beside cliff faces.
			for offset: Vector2i in VoxelGrid.DIRECTION_OFFSETS:
				var nc := col + offset.x
				var nr := row + offset.y
				if _in_bounds(nc, nr) \
						and abs(_heights[_idx(nc, nr)] - _heights[i]) >= 2:
					floor_type = str(_t["steep_floor"])
					break
			if is_mountains and _heights[i] >= amp - 1:
				floor_type = str(_t["high_floor"])
			_floor[i] = floor_type


# ---------------------------------------------------------------------------
# Voxelization
# ---------------------------------------------------------------------------

## Stamps (or restamps) one column from the plan arrays into the map: solid
## earth stack, surface cell (dry / shallow / deep / lava), optional bridge
## deck. Restamping clears any obstacle previously placed on the column.
func _stamp_column(col: int, row: int) -> void:
	var i := _idx(col, row)
	for z in range(0, MAX_COLUMN_LEVELS):
		_map.remove_cell(Vector3i(col, row, z))

	var hgt: int = _heights[i]
	for z in range(0, hgt):
		var solid := VoxelCell.new()
		solid.solidity = "solid"
		solid.feature = "earth"
		solid.floor_type = "none"
		solid.fog_state = "visible"
		_map.set_cell(Vector3i(col, row, z), solid)

	var surface := VoxelCell.new()
	surface.fog_state = "visible"
	match _water_kind[i]:
		W_SHALLOW:
			surface.solidity = "air"
			surface.feature = "water_shallow"
			surface.floor_type = "water"
			surface.water_depth = 0
		W_DEEP:
			surface.solidity = "liquid"
			surface.feature = "water_deep"
			surface.floor_type = "water"
			surface.water_depth = maxi(1, _water_depth[i])
		W_LAVA:
			surface.solidity = "liquid"
			surface.feature = "lava"
			surface.floor_type = "lava_rock"
			surface.water_depth = 0
		_:
			surface.solidity = "air"
			surface.feature = "open"
			surface.floor_type = _floor[i] if not _floor[i].is_empty() else "grass"
	_map.set_cell(Vector3i(col, row, hgt), surface)

	if _bridge_level[i] >= 0 and _bridge_level[i] > hgt:
		var deck := VoxelCell.new()
		deck.solidity = "air"
		deck.feature = "open"
		deck.floor_type = "wood"
		deck.fog_state = "visible"
		_map.set_cell(Vector3i(col, row, _bridge_level[i]), deck)


# ---------------------------------------------------------------------------
# Party pocket
# ---------------------------------------------------------------------------

## Reserves a cleared spawn pocket near the west side of the map before
## obstacle scatter (§7.6). The final anchor is confirmed post-validation.
func _reserve_party_pocket() -> void:
	var target := Vector2i(6, _h / 2)
	var pocket := Vector2i(-1, -1)
	for radius in range(0, maxi(_w, _h)):
		if pocket.x >= 0:
			break
		for col in range(maxi(0, target.x - radius), mini(_w, target.x + radius + 1)):
			for row in range(maxi(0, target.y - radius), mini(_h, target.y + radius + 1)):
				if maxi(abs(col - target.x), abs(row - target.y)) != radius:
					continue
				if _water_kind[_idx(col, row)] == W_NONE:
					pocket = Vector2i(col, row)
					break
			if pocket.x >= 0:
				break
	if pocket.x < 0:
		pocket = target
	for dc in range(-2, 3):
		for dr in range(-2, 3):
			if _in_bounds(pocket.x + dc, pocket.y + dr):
				_protected[_idx(pocket.x + dc, pocket.y + dr)] = true
	_party_anchor = Vector3i(pocket.x, pocket.y, _heights[_idx(pocket.x, pocket.y)])


# ---------------------------------------------------------------------------
# Obstacles
# ---------------------------------------------------------------------------

## True when the column's surface cell can take an obstacle: dry open ground,
## not a reserved crossing / spawn pocket / bridge deck.
func _obstacle_eligible(col: int, row: int) -> bool:
	if not _in_bounds(col, row):
		return false
	var i := _idx(col, row)
	if _protected.has(i) or _water_kind[i] != W_NONE or _bridge_level[i] >= 0:
		return false
	var pos := Vector3i(col, row, _heights[i])
	var cell := _map.get_cell(pos)
	return cell.solidity == "air" and cell.feature == "open"


func _stamp_obstacle(col: int, row: int, feature: String) -> void:
	var pos := Vector3i(col, row, _heights[_idx(col, row)])
	BattleMapObstacleCatalog.apply_to_cell(_map.get_cell(pos), feature)


func _place_obstacles() -> void:
	# Jungle clearing first — protect it from the coverage fill (§5.3).
	if bool(_t.get("clearing", false)):
		var cx: int = _rng.randi_range(int(_w * 0.3), int(_w * 0.7))
		var cy: int = _rng.randi_range(int(_h * 0.3), int(_h * 0.7))
		var cr: int = _rng.randi_range(2, 3)
		for col in range(cx - cr, cx + cr + 1):
			for row in range(cy - cr, cy + cr + 1):
				if _in_bounds(col, row):
					var i := _idx(col, row)
					_protected[i] = true
					if _water_kind[i] == W_NONE:
						_map.get_cell(Vector3i(col, row, _heights[i])).floor_type = \
							str(_t["surface_alt"])

	# Coverage fill (forest/jungle trees + undergrowth). The per-cell stamp
	# probability is the target fraction scaled by a low-frequency noise clump
	# factor (mean ~1.0) — organic clusters with natural clearings, while the
	# overall coverage tracks the template fraction.
	var coverage: Array = _t.get("coverage", [])
	for entry: Dictionary in coverage:
		var fraction: float = _rng.randf_range(
			float(entry["fmin"]), float(entry["fmax"]))
		var clump := _make_noise(0.15)
		for row in range(_h):
			for col in range(_w):
				if not _obstacle_eligible(col, row):
					continue
				var v: float = (clump.get_noise_2d(float(col), float(row)) + 1.0) * 0.5
				var clump_factor: float = clampf(v * 2.0, 0.15, 2.0)
				if _rng.randf() < fraction * clump_factor:
					_stamp_obstacle(col, row, str(entry["feature"]))

	# Lone features.
	for entry: Dictionary in _t.get("scatter", []):
		var count: int = _rng.randi_range(int(entry["min"]), int(entry["max"]))
		for _n in range(count):
			for _attempt in range(30):
				var col: int = _rng.randi_range(0, _w - 1)
				var row: int = _rng.randi_range(0, _h - 1)
				if _obstacle_eligible(col, row):
					_stamp_obstacle(col, row, str(entry["feature"]))
					break

	# Clusters (brush patches, reed beds, outcrops).
	for entry: Dictionary in _t.get("clusters", []):
		var count: int = _rng.randi_range(int(entry["min"]), int(entry["max"]))
		for _n in range(count):
			var seed_cell := Vector2i(-1, -1)
			for _attempt in range(30):
				var col: int = _rng.randi_range(0, _w - 1)
				var row: int = _rng.randi_range(0, _h - 1)
				if _obstacle_eligible(col, row):
					seed_cell = Vector2i(col, row)
					break
			if seed_cell.x < 0:
				continue
			var size: int = _rng.randi_range(int(entry["size_min"]), int(entry["size_max"]))
			var frontier: Array[Vector2i] = [seed_cell]
			var placed := 0
			while placed < size and not frontier.is_empty():
				var pick: int = _rng.randi_range(0, frontier.size() - 1)
				var cell: Vector2i = frontier[pick]
				if _obstacle_eligible(cell.x, cell.y):
					_stamp_obstacle(cell.x, cell.y, str(entry["feature"]))
					placed += 1
					for offset: Vector2i in VoxelGrid.DIRECTION_OFFSETS:
						frontier.append(cell + offset)
				frontier.remove_at(pick)

	# Lines (hedgerows, fences, low walls, fallen logs).
	for entry: Dictionary in _t.get("lines", []):
		var count: int = _rng.randi_range(int(entry["min"]), int(entry["max"]))
		for _n in range(count):
			_walk_line(str(entry["feature"]),
				_rng.randi_range(int(entry["len_min"]), int(entry["len_max"])))

	# Ruined walls — any locale (§5.3).
	if _rng.randf() < float(_t.get("ruin_chance", 0.15)):
		var ruins: int = _rng.randi_range(1, 2)
		for _n in range(ruins):
			_walk_line("wall_ruined", _rng.randi_range(3, 7))

	# Farmstead (civilized clear).
	if _rng.randf() < float(_t.get("farmstead_chance", 0.0)):
		_place_farmstead()


func _walk_line(feature: String, length: int) -> void:
	var col: int = _rng.randi_range(2, _w - 3)
	var row: int = _rng.randi_range(2, _h - 3)
	var dir_idx: int = _rng.randi_range(0, 7)
	for _step in range(length):
		if _obstacle_eligible(col, row):
			_stamp_obstacle(col, row, feature)
		if _rng.randf() < 0.25:
			dir_idx = wrapi(dir_idx + (1 if _rng.randf() < 0.5 else -1), 0, 8)
		var offset: Vector2i = VoxelGrid.DIRECTION_OFFSETS[dir_idx]
		col += offset.x
		row += offset.y
		if not _in_bounds(col, row):
			return


## A small solid farm building on flat ground plus a broken fence ring
## (gdd-combat-map-generation.md §5.3, civilized clear).
func _place_farmstead() -> void:
	for _attempt in range(12):
		var bw: int = _rng.randi_range(3, 5)
		var bh: int = _rng.randi_range(4, 6)
		var col0: int = _rng.randi_range(3, _w - bw - 4)
		var row0: int = _rng.randi_range(3, _h - bh - 4)
		var level: int = _heights[_idx(col0, row0)]
		var ok := true
		for col in range(col0, col0 + bw):
			for row in range(row0, row0 + bh):
				if not _obstacle_eligible(col, row) \
						or _heights[_idx(col, row)] != level:
					ok = false
					break
			if not ok:
				break
		if not ok:
			continue
		for col in range(col0, col0 + bw):
			for row in range(row0, row0 + bh):
				var cell := _map.get_cell(Vector3i(col, row, level))
				cell.solidity = "solid"
				cell.feature = "wall_wood"
		# Broken fence ring with an entry gap on one side.
		var gap_side: int = _rng.randi_range(0, 3)
		var fence_rows: Array[int] = [row0 - 2, row0 + bh + 1]
		for col in range(col0 - 2, col0 + bw + 2):
			for r_i in range(fence_rows.size()):
				if r_i == gap_side:
					continue
				var row: int = fence_rows[r_i]
				if _obstacle_eligible(col, row) and _rng.randf() < 0.85:
					_stamp_obstacle(col, row, "fence")
		var fence_cols: Array[int] = [col0 - 2, col0 + bw + 1]
		for row in range(row0 - 2, row0 + bh + 2):
			for c_i in range(fence_cols.size()):
				if c_i + 2 == gap_side:
					continue
				var col: int = fence_cols[c_i]
				if _obstacle_eligible(col, row) and _rng.randf() < 0.85:
					_stamp_obstacle(col, row, "fence")
		return


# ---------------------------------------------------------------------------
# Validation + repair (§7.5)
# ---------------------------------------------------------------------------

func _validate_and_repair() -> Dictionary:
	var analysis: Dictionary = BattleMapValidator.analyze(_map)
	for _iteration in range(MAX_REPAIR_ITERATIONS):
		var comps: Array = analysis["components"]
		if comps.is_empty():
			break
		var total: int = (analysis["surfaces"] as Array).size()
		if _split_intended:
			if comps.size() < 2 \
					or (comps[1] as Array).size() < int(SPLIT_SIDE_FRACTION * total):
				# The divider failed to produce two viable sides — downgrade:
				# carve a crossing (ford / ramp) and continue as a normal map.
				_split_intended = false
				_divider = ""
				if comps.size() >= 2:
					_carve_corridor(analysis, 0, [1])
					analysis = BattleMapValidator.analyze(_map)
				continue
			if comps.size() > 2 \
					and (comps[2] as Array).size() > int(STRAGGLER_FRACTION * total):
				# Stray fragment: attach it to whichever major side is nearest
				# (never force it across the divider).
				_carve_corridor(analysis, 2, [0, 1])
				analysis = BattleMapValidator.analyze(_map)
				continue
			break
		else:
			var main_ok: bool = (comps[0] as Array).size() >= int(MAIN_COMPONENT_FRACTION * total)
			var straggler: bool = comps.size() > 1 \
				and (comps[1] as Array).size() > int(STRAGGLER_FRACTION * total)
			if main_ok and not straggler:
				break
			if comps.size() < 2:
				break
			_carve_corridor(analysis, 1, [0])
			analysis = BattleMapValidator.analyze(_map)
	return analysis


## Carves a walkable corridor from component [param from_comp] to the nearest
## cell of any component in [param to_comps]: deep water fords to shallow,
## lava crusts over, obstacles clear, and heights re-grade to 1-level steps.
func _carve_corridor(analysis: Dictionary, from_comp: int, to_comps: Array) -> void:
	var comps: Array = analysis["components"]
	var cell_component: Dictionary = analysis["cell_component"]
	if from_comp >= comps.size():
		return
	var targets: Dictionary = {}
	for tc in to_comps:
		if tc < comps.size():
			for pos: Vector3i in comps[tc]:
				targets[Vector2i(pos.x, pos.y)] = true
	if targets.is_empty():
		return

	# Multi-source BFS over columns from every from_comp cell.
	var queue: Array[Vector2i] = []
	var parent: Dictionary = {}
	for pos: Vector3i in comps[from_comp]:
		var c2 := Vector2i(pos.x, pos.y)
		parent[c2] = c2
		queue.append(c2)
	var goal := Vector2i(-1, -1)
	while not queue.is_empty() and goal.x < 0:
		var current: Vector2i = queue.pop_front()
		for offset: Vector2i in VoxelGrid.DIRECTION_OFFSETS:
			var next: Vector2i = current + offset
			if not _in_bounds(next.x, next.y) or parent.has(next):
				continue
			parent[next] = current
			if targets.has(next):
				goal = next
				break
			queue.append(next)
	if goal.x < 0:
		return

	# Reconstruct the column path back to the from_comp border.
	var path: Array[Vector2i] = []
	var walk := goal
	while parent[walk] != walk:
		path.push_front(walk)
		walk = parent[walk]
	path.push_front(walk)

	# Force each column walkable, grading heights in 1-level steps.
	var prev_z: int = _heights[_idx(path[0].x, path[0].y)]
	var start_pos := Vector3i(path[0].x, path[0].y, _map.surface_level_at(path[0].x, path[0].y))
	if cell_component.has(start_pos):
		prev_z = start_pos.z
	for step in path:
		prev_z = _force_walkable_column(step.x, step.y, prev_z)


## Makes one column standable next to a neighbor surface at [param near_z]:
## returns the column's new surface level.
func _force_walkable_column(col: int, row: int, near_z: int) -> int:
	var i := _idx(col, row)
	if _water_kind[i] == W_DEEP:
		_water_kind[i] = W_SHALLOW
		_water_depth[i] = 0
	elif _water_kind[i] == W_LAVA:
		_water_kind[i] = W_NONE
		_floor[i] = "lava_rock"
	_heights[i] = clampi(_heights[i], near_z - 1, near_z + 1)
	_stamp_column(col, row)
	return _heights[i]


# ---------------------------------------------------------------------------
# Spawn zones (§7.6)
# ---------------------------------------------------------------------------

## Confirms the party anchor sits in the main component (re-picking the
## west-most suitable cell if a repair moved things) and returns the party
## spawn zone: anchor first, then nearby same-component standable cells.
func _finalize_spawn(analysis: Dictionary) -> Array[Vector3i]:
	var comps: Array = analysis["components"]
	var zone: Array[Vector3i] = []
	if comps.is_empty():
		return zone
	var main: Array = comps[0]

	var anchor_surface := Vector3i(
		_party_anchor.x, _party_anchor.y,
		_map.surface_level_at(_party_anchor.x, _party_anchor.y))
	var cell_component: Dictionary = analysis["cell_component"]
	if cell_component.get(anchor_surface, -1) != 0:
		# Pick the west-most main-component cell nearest the map's mid row.
		var best := Vector3i(-1, -1, -1)
		var best_score := 1 << 30
		for pos: Vector3i in main:
			var score: int = pos.x * 3 + abs(pos.y - _h / 2)
			if score < best_score:
				best_score = score
				best = pos
		anchor_surface = best
	if anchor_surface.x < 0:
		return zone
	_party_anchor = anchor_surface
	_map.entry_pos = anchor_surface

	# BFS outward from the anchor over legal ground steps for the zone list.
	var visited: Dictionary = {anchor_surface: true}
	var queue: Array[Vector3i] = [anchor_surface]
	while not queue.is_empty() and zone.size() < 40:
		var current: Vector3i = queue.pop_front()
		zone.append(current)
		for offset: Vector2i in VoxelGrid.DIRECTION_OFFSETS:
			var nz: int = _map.surface_level_at(current.x + offset.x, current.y + offset.y)
			if nz < 0:
				continue
			var npos := Vector3i(current.x + offset.x, current.y + offset.y, nz)
			if visited.has(npos):
				continue
			if cell_component.get(npos, -1) != 0:
				continue
			if not MovementRules.is_ground_step_open(_map, current, npos):
				continue
			visited[npos] = true
			queue.append(npos)
	return zone


# ---------------------------------------------------------------------------
# Placement helpers for CombatState
# ---------------------------------------------------------------------------

## Picks the enemy anchor for a rolled encounter distance of
## [param desired_cells] from [param party_anchor] (gdd §7.6). On a split map
## the anchor comes from the OTHER major component (across the divider);
## otherwise from the party's own component. Ring-searches outward from the
## ideal spot (party anchor + desired cells along +col) for the nearest
## standable surface cell that satisfies the component rule.
static func pick_enemy_anchor(
		map: VoxelMapData, party_anchor: Vector3i,
		desired_cells: int, is_split: bool) -> Vector3i:
	var party_zone: int = map.get_cell(party_anchor).zone_index
	var target := Vector2i(party_anchor.x + desired_cells, party_anchor.y)
	for radius in range(0, 160):
		for dc in range(-radius, radius + 1):
			for dr in range(-radius, radius + 1):
				if maxi(abs(dc), abs(dr)) != radius:
					continue
				var col: int = target.x + dc
				var row: int = target.y + dr
				var z: int = map.surface_level_at(col, row)
				if z < 0:
					continue
				var pos := Vector3i(col, row, z)
				if not BattleMapValidator.is_standable_surface(map, pos):
					continue
				var zone: int = map.get_cell(pos).zone_index
				if zone < 0:
					continue
				if is_split:
					if zone == party_zone or zone > 1:
						continue
				elif zone != party_zone:
					continue
				return pos
	return Vector3i(-1, -1, -1)


## Collects up to [param count] standable spawn cells around [param anchor] in
## the anchor's own walkable component, nearest first (anchor included).
static func spawn_cells_near(
		map: VoxelMapData, anchor: Vector3i, count: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if anchor.x < 0:
		return result
	var anchor_zone: int = map.get_cell(anchor).zone_index
	for radius in range(0, 40):
		if result.size() >= count:
			break
		for dc in range(-radius, radius + 1):
			for dr in range(-radius, radius + 1):
				if maxi(abs(dc), abs(dr)) != radius:
					continue
				var col: int = anchor.x + dc
				var row: int = anchor.y + dr
				var z: int = map.surface_level_at(col, row)
				if z < 0:
					continue
				var pos := Vector3i(col, row, z)
				if not BattleMapValidator.is_standable_surface(map, pos):
					continue
				if map.get_cell(pos).zone_index != anchor_zone:
					continue
				result.append(pos)
				if result.size() >= count:
					break
			if result.size() >= count:
				break
	return result
