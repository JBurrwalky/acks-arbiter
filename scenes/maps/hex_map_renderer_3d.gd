extends Node3D

## 3D heightmap renderer for the 6-mile wilderness play map
## (gdd-wilderness-hex-3d.md). The continuous-geography GeoField is the VISIBLE
## play surface — a smooth height mesh textured by biome — and the hex grid is
## drawn ON TOP in the splat shader as a non-destructive data overlay. Behind the
## acks/rendering/wilderness_hex_mode flag; preserves the exact signal + method
## contract of the 2D hex_map_renderer.gd so the session state machine is untouched.
##
## Height source: RAW_FIELD — the GeoField is regenerated deterministically from
## the campaign seed + SettingParameters (same seed -> byte-identical surface),
## then each hex samples its field cell (axial_to_godot_map(q,r)); corners average
## the sharing hexes for a C0-continuous rolling surface.

# --- Contract: the five signals the 2D renderer emits (hex_map_renderer.gd:153-157) ---
signal hex_clicked(coord: Vector2i)
signal party_token_clicked(party_id: String, coord: Vector2i)
signal hex_context_menu_requested(coord: Vector2i, screen_pos: Vector2)
signal dungeon_entry_requested(entrance: Dictionary, spawn_cell: Vector2i)
signal settlement_entry_requested(entrance: Dictionary, entry_poi_id: String)

# WildernessHexMath is a global class_name (axial<->world helpers).

# --- Tunables ---
const HEIGHT_GAIN := 3.0          # field surface [0,1] -> world Y (vertical exaggeration)
const WATER_LEVEL_RAW := 0.30     # below this the field is ocean; water mesh Y
const CHUNK_HEXES := 8            # ~8x8 hexes per mesh chunk (offset-space)
const TEX_SIZE := 512            # common albedo size for the Texture2DArray

# Camera (lifted from the dungeon iso camera, tactical_grid_3d).
const CAM_PITCH_DEG := -35.264
const CAM_YAW_DEG := 0.0
const ZOOM_MIN_FLOOR := 3.0      # most zoomed-IN ortho size (smaller = closer)
const ZOOM_MAX := 120.0          # most zoomed-OUT ortho size
const ZOOM_FACTOR := 1.12        # multiplicative size change per wheel tick
const EDGE_MARGIN := 24.0        # px from a viewport edge that triggers edge-pan
const EDGE_PAN_RATE := 0.85      # fraction of the view height panned per second

# Terrain-class -> Texture2DArray layer index. Order fixed; the array is built
# from res://assets/wilderness_textures/<name>.jpg in this order.
const _LAYER_FILES := [
	"clear", "grassland", "savanna", "tundra", "forest_floor", "jungle",
	"desert", "badlands", "mountain", "volcanic", "snow", "jungle",  # 11 = swamp (darkened jungle)
]
const LAYER_CLEAR := 0
const LAYER_GRASSLAND := 1
const LAYER_SAVANNA := 2
const LAYER_TUNDRA := 3
const LAYER_FOREST := 4
const LAYER_JUNGLE := 5
const LAYER_DESERT := 6
const LAYER_BADLANDS := 7
const LAYER_MOUNTAIN := 8
const LAYER_VOLCANIC := 9
const LAYER_SNOW := 10
const LAYER_SWAMP := 11

# --- Vegetation scatter (GDD §9) — small-but-visible trees on forest/jungle ---
## Native Quaternius trees are ~2-4 units; in a 1-unit-hex world scale them down
## hard so they read as small trees dotting a hex, not towers.
const TREE_SCALE := 0.12
const SCATTER_JITTER := 0.62        # fraction of HEX_RADIUS trees scatter within
const _BROADLEAF := ["common_tree_1", "common_tree_2", "common_tree_3", "common_tree_4",
	"common_tree_5", "birch_tree_1", "birch_tree_2", "birch_tree_3", "birch_tree_4", "birch_tree_5"]
const _PINE := ["pine_tree_1", "pine_tree_2", "pine_tree_3", "pine_tree_4", "pine_tree_5"]
const _PALM := ["palm_tree_1", "palm_tree_2", "palm_tree_3", "palm_tree_4"]
const _WILLOW := ["willow_1", "willow_2", "willow_3", "willow_4", "willow_5"]
const _CACTUS := ["cactus_1", "cactus_2", "cactus_3", "cactus_4", "cactus_5"]

# --- Edge rivers (GDD §8.3/§8.4) — water ribbons along the HexRiverEdgeData edges ---
## Ribbon width (world units) by navigability. Rivers run ALONG hex edges
## (corner->corner); width scales with navigable craft size.
const _RIVER_WIDTH := {
	"none": 0.09, "small_craft": 0.12, "river_craft": 0.17, "large_craft": 0.26,
}
## Raise the water just above the terrain so it doesn't z-fight the surface.
const RIVER_LIFT := 0.035

var _controller: HexMapController = null
var _map_data: HexMapData = null
var _field = null                 # GeoField (reconstructed; cached)
var _field_ready := false
var _campaign_seed := 0

var _camera: Camera3D = null
var _terrain_root: Node3D = null
var _scatter_root: Node3D = null
var _scatter_mesh_cache := {}     # variant name -> Mesh
var _river_root: Node3D = null
var _river_material_cache: StandardMaterial3D = null
var _landmark_root: Node3D = null
var _landmark_mat: StandardMaterial3D = null
var _dungeon_mat: StandardMaterial3D = null
var _token_root: Node3D = null
var _splat_material: ShaderMaterial = null
var _albedo_array: Texture2DArray = null
var _chunks: Array = []           # MeshInstance3D list (for rebuild)
var _hex_height_cache := {}       # Vector2i -> float (world Y at hex center)
var _party_tokens := {}           # party_id -> Node3D

var _zoom := 24.0
var _zoom_min := 8.0
var _cam_target := Vector3.ZERO


func _ready() -> void:
	_terrain_root = Node3D.new()
	_terrain_root.name = "TerrainChunks"
	add_child(_terrain_root)
	_scatter_root = Node3D.new()
	_scatter_root.name = "Scatter"
	add_child(_scatter_root)
	_river_root = Node3D.new()
	_river_root.name = "Rivers"
	add_child(_river_root)
	_landmark_root = Node3D.new()
	_landmark_root.name = "Landmarks"
	add_child(_landmark_root)
	_token_root = Node3D.new()
	_token_root.name = "Tokens"
	add_child(_token_root)
	_build_environment()
	_build_camera()
	_build_splat_material()


# ---------------------------------------------------------------------------
# Contract methods (mirror hex_map_renderer.gd:272, :282)
# ---------------------------------------------------------------------------

func setup(controller: HexMapController) -> void:
	_controller = controller
	controller.map_loaded.connect(_on_map_loaded)
	controller.visibility_updated.connect(_on_visibility_updated)
	controller.party_moved.connect(_on_party_moved)
	controller.hex_terrain_updated.connect(_on_hex_terrain_updated)
	controller.hex_overlay_updated.connect(_on_overlay_updated)
	var existing := controller.get_map()
	if existing != null:
		_on_map_loaded(existing.id)


func center_on_hex(coord: Vector2i) -> void:
	var xz := WildernessHexMath.axial_to_world(coord)
	_cam_target = Vector3(xz.x, _hex_height_cache.get(coord, 0.0), xz.y)
	_apply_camera()


# ---------------------------------------------------------------------------
# Controller signal handlers
# ---------------------------------------------------------------------------

func _on_map_loaded(_map_id: String) -> void:
	_map_data = _controller.get_map()
	if _map_data == null:
		return
	_ensure_field()
	_build_terrain()
	_build_rivers()
	_build_landmarks()
	_rebuild_tokens()
	_fit_camera()
	# Scatter is deferred so it never blocks the session-load flow (this runs inside
	# controller.load_map()); it also refreshes with fog via _on_visibility_updated.
	call_deferred("_build_scatter")


func _on_visibility_updated() -> void:
	# Fog rides in per-vertex UV2; cheapest correct path is a terrain rebuild.
	# Scatter + rivers are gated on non-hidden hexes, so they refresh with the fog.
	if _map_data != null:
		_build_terrain()
		_build_rivers()
		_build_landmarks()
		call_deferred("_build_scatter")


func _on_party_moved(_from_hex: Vector2i, _to_hex: Vector2i) -> void:
	_rebuild_tokens()


func _on_hex_terrain_updated(_coord: Vector2i) -> void:
	# Field-sourced height does not change on a tag edit, but biome/water can —
	# rebuild the whole surface for now (chunk-local rebuild is a later refinement).
	if _map_data != null:
		_build_terrain()


func _on_overlay_updated(_coord: Vector2i) -> void:
	pass  # roads/rivers overlay is a later phase


# ---------------------------------------------------------------------------
# Field reconstruction (RAW_FIELD) — deterministic from the campaign seed
# ---------------------------------------------------------------------------

func _ensure_field() -> void:
	if _field_ready:
		return
	var campaign_id := GameState.campaign_id
	var params: Dictionary = {} if campaign_id.is_empty() else SettingRepository.get_parameters(campaign_id)
	if params.is_empty():
		_field = null
		_field_ready = true
		return
	_campaign_seed = int(params.get("campaign_seed", 0))
	var sp := SettingParameters.from_dict(params)
	_field = GeoFieldGenerator.generate(_campaign_seed, sp)
	GeoClimateGenerator.apply(_field, _campaign_seed, sp)
	_field_ready = true


## World Y at a hex center. From the field cell (= axial_to_godot_map(q,r)); falls
## back to the categorical elevation band when no field is available.
func _hex_height(coord: Vector2i) -> float:
	if _hex_height_cache.has(coord):
		return _hex_height_cache[coord]
	var raw := 0.0
	if _field != null:
		var cell := HexMapController.axial_to_godot_map(coord)
		var fx: int = clampi(cell.x, 0, _field.width - 1)
		var fy: int = clampi(cell.y, 0, _field.height - 1)
		raw = _field.surface[_field.idx(fx, fy)]
	else:
		raw = _tag_height(coord)
	var t := _terrain(coord)
	if t != null and t.water != "":
		raw = WATER_LEVEL_RAW  # water hexes sit at the water plane
	var y := raw * HEIGHT_GAIN
	_hex_height_cache[coord] = y
	return y


func _tag_height(coord: Vector2i) -> float:
	var t := _terrain(coord)
	if t == null:
		return 0.35
	match t.elevation:
		"mountains": return 0.85
		"hills": return 0.6
		_: return 0.38


func _terrain(coord: Vector2i) -> HexTerrainData:
	if _map_data == null:
		return null
	return _map_data.get_hex(coord)


# ---------------------------------------------------------------------------
# Terrain mesh (chunked ArrayMesh via SurfaceTool) + collision
# ---------------------------------------------------------------------------

func _build_terrain() -> void:
	for c in _chunks:
		c.queue_free()
	_chunks.clear()
	_hex_height_cache.clear()
	if _map_data == null:
		return

	# Bucket hexes into chunks by their offset col/row (clean rectangle).
	var buckets := {}
	for coord in _map_data.hexes.keys():
		var off := HexMapController.axial_to_godot_map(coord)
		@warning_ignore("integer_division")
		var key := Vector2i(off.x / CHUNK_HEXES, off.y / CHUNK_HEXES)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(coord)

	for key in buckets:
		_build_chunk(buckets[key])


func _build_chunk(coords: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)

	var corner_off := WildernessHexMath.corner_offsets()
	for coord in coords:
		var t := _terrain(coord)
		if t == null:
			continue
		var center_xz := WildernessHexMath.axial_to_world(coord)
		var ch := _hex_height(coord)
		var center := Vector3(center_xz.x, ch, center_xz.y)
		var own_layer := float(_biome_layer(t))
		var center_uv2 := _vertex_uv2([coord])

		# Precompute the 6 corner positions + fog/water (height = mean of sharing hexes).
		var corner_pos := []
		var corner_uv2 := []
		for i in range(6):
			var sharing := _corner_sharing(coord, i)
			corner_pos.append(Vector3(center_xz.x + corner_off[i].x, _avg_height(sharing),
					center_xz.y + corner_off[i].y))
			corner_uv2.append(_vertex_uv2(sharing))

		# Fan: 6 triangles. Each covers the wedge near ONE hex edge, so it blends just
		# TWO layers — this hex (slot 0) and the neighbour across that edge (slot 1) —
		# with the SAME layer pair on all 3 of its vertices. (Interpolating per-vertex
		# layer INDICES through the Texture2DArray is what drew the concentric biome
		# rings; constant-per-triangle layers + only the WEIGHTS interpolating fixes it.)
		for i in range(6):
			var e := (i + 2) % 6   # hex edge between corners i and i+1 (HexRiverEdgeData order)
			var nb_layer := own_layer
			var nb: Vector2i = coord + HexRiverEdgeData.EDGE_NEIGHBOR_OFFSETS[e]
			if _map_data.is_valid_coord(nb):
				var nt := _terrain(nb)
				if nt != null:
					nb_layer = float(_biome_layer(nt))
			var layers := Color(own_layer, nb_layer, 0.0, 0.0)
			var i1 := (i + 1) % 6
			# Centre is pure own; both edge corners blend own<->neighbour 50/50.
			_emit_vertex(st, center, Color(1.0, 0.0, 0.0, 0.0), layers, center_uv2)
			_emit_vertex(st, corner_pos[i], Color(0.5, 0.5, 0.0, 0.0), layers, corner_uv2[i])
			_emit_vertex(st, corner_pos[i1], Color(0.5, 0.5, 0.0, 0.0), layers, corner_uv2[i1])

	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _splat_material
	_terrain_root.add_child(mi)
	_chunks.append(mi)

	# Collision from the same triangle soup (for surface-raycast picking).
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(mesh.get_faces())
	shape.shape = concave
	body.add_child(shape)
	mi.add_child(body)


func _emit_vertex(st: SurfaceTool, pos: Vector3, weights: Color, layers: Color, uv2: Vector2) -> void:
	st.set_color(weights)        # per-vertex blend weights (slot0=own, slot1=neighbour)
	st.set_custom(0, layers)     # constant per triangle -> never interpolates an index
	st.set_uv(Vector2(pos.x, pos.z))   # world XZ; shader rescales by tex_scale
	st.set_uv2(uv2)
	st.add_vertex(pos)


## Average world-Y over the given coords (skips off-map).
func _avg_height(coords: Array) -> float:
	var sum := 0.0
	var n := 0
	for c in coords:
		if _map_data.is_valid_coord(c):
			sum += _hex_height(c)
			n += 1
	return sum / float(maxi(n, 1))


## World Y on the RENDERED surface at a point [param local] (XZ offset from the hex
## centre), interpolated over the same 6-triangle fan the terrain mesh draws:
## center at [param center_y], corner i at [param corner_y][i] (positions in
## [param corner_off]). Barycentric over whichever wedge (centre, corner i, corner
## i+1) contains the point; falls back to centre height if none (point at/near
## centre or just outside). Keeps scattered trees ON the tilted surface.
func _fan_y(local: Vector2, center_y: float, corner_off: Array, corner_y: Array) -> float:
	for i in range(6):
		var i1 := (i + 1) % 6
		var b: Vector2 = corner_off[i]
		var c: Vector2 = corner_off[i1]
		var det := b.x * c.y - c.x * b.y
		if absf(det) < 1.0e-9:
			continue
		var wb := (local.x * c.y - c.x * local.y) / det
		var wc := (b.x * local.y - local.x * b.y) / det
		var wa := 1.0 - wb - wc
		if wa >= -0.01 and wb >= -0.01 and wc >= -0.01:
			return wa * center_y + wb * float(corner_y[i]) + wc * float(corner_y[i1])
	return center_y


## The hexes sharing corner [param i] of [param coord] (self + up to 2 neighbours).
func _corner_sharing(coord: Vector2i, i: int) -> Array:
	var pairs: Array = _CORNER_NEIGHBORS[i]
	var out := [coord]
	for off in pairs:
		var n: Vector2i = coord + off
		if _map_data.is_valid_coord(n):
			out.append(n)
	return out


# corner i (angles 0,60,..300) -> the two neighbour axial offsets sharing it.
const _CORNER_NEIGHBORS := [
	[Vector2i(1, -1), Vector2i(1, 0)],
	[Vector2i(1, 0), Vector2i(0, 1)],
	[Vector2i(0, 1), Vector2i(-1, 1)],
	[Vector2i(-1, 1), Vector2i(-1, 0)],
	[Vector2i(-1, 0), Vector2i(0, -1)],
	[Vector2i(0, -1), Vector2i(1, -1)],
]


## UV2 = (water_flag, fog_value), averaged over the sharing hexes.
func _vertex_uv2(coords: Array) -> Vector2:
	var water := 0.0
	var fog := 0.0
	var n := 0
	for c in coords:
		var t := _terrain(c)
		if t == null:
			continue
		water += (1.0 if t.water != "" else 0.0)
		fog += _fog_value(c)
		n += 1
	n = maxi(n, 1)
	return Vector2(water / float(n), fog / float(n))


func _fog_value(coord: Vector2i) -> float:
	if _map_data == null:
		return 1.0
	match _map_data.get_fog_state(coord):
		HexMapData.FogState.VISIBLE: return 1.0
		HexMapData.FogState.EXPLORED: return 0.5
		_: return 0.0


## Map a hex's terrain tags to a Texture2DArray layer (mountains dominate; then
## subtype; then base biome). Hills reuse the base biome texture.
func _biome_layer(t: HexTerrainData) -> int:
	if t.water != "":
		return LAYER_CLEAR  # water fragments are overwritten by water_color anyway
	if t.elevation == "mountains":
		match t.biome_subtype:
			"mountains_volcanic": return LAYER_VOLCANIC
			"mountains_glacial": return LAYER_SNOW
		return LAYER_MOUNTAIN
	match t.biome_subtype:
		"clear_grassland": return LAYER_GRASSLAND
		"clear_savanna": return LAYER_SAVANNA
		"clear_tundra": return LAYER_TUNDRA
		"desert_badlands": return LAYER_BADLANDS
	match t.biome:
		"woods": return LAYER_FOREST
		"jungle": return LAYER_JUNGLE
		"swamp": return LAYER_SWAMP
		"desert": return LAYER_DESERT
	return LAYER_CLEAR


# ---------------------------------------------------------------------------
# Material + Texture2DArray
# ---------------------------------------------------------------------------

func _build_splat_material() -> void:
	_splat_material = ShaderMaterial.new()
	_splat_material.shader = load("res://engine/shaders/wilderness_splat.gdshader")
	_albedo_array = _build_albedo_array()
	if _albedo_array != null:
		_splat_material.set_shader_parameter("biome_albedo", _albedo_array)
	_splat_material.set_shader_parameter("hex_radius", WildernessHexMath.HEX_RADIUS)
	_splat_material.set_shader_parameter("tex_scale", 1.2)


func _build_albedo_array() -> Texture2DArray:
	var images: Array[Image] = []
	for name in _LAYER_FILES:
		var path := "res://assets/wilderness_textures/%s.jpg" % name
		var tex := load(path) as Texture2D
		if tex == null:
			push_warning("wilderness renderer: missing albedo %s" % path)
			var blank := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
			blank.fill(Color(0.5, 0.5, 0.5))
			images.append(blank)
			continue
		var img := tex.get_image()
		img.decompress()
		img.convert(Image.FORMAT_RGB8)
		if img.get_width() != TEX_SIZE or img.get_height() != TEX_SIZE:
			img.resize(TEX_SIZE, TEX_SIZE)
		img.generate_mipmaps()
		images.append(img)
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	return arr


# ---------------------------------------------------------------------------
# Vegetation scatter (GDD §9) — seeded MultiMesh trees on forest/jungle hexes
# ---------------------------------------------------------------------------

func _build_scatter() -> void:
	for child in _scatter_root.get_children():
		child.queue_free()
	if _map_data == null:
		return
	var per_variant := {}   # variant name -> Array[Transform3D]
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for coord in _map_data.hexes.keys():
		# Don't reveal unexplored ground (fog leak): scatter only non-hidden hexes.
		if _map_data.get_fog_state(coord) == HexMapData.FogState.HIDDEN:
			continue
		var t := _terrain(coord)
		if t == null:
			continue
		var pool := _scatter_pool(t)
		if pool.is_empty():
			continue
		var variants: Array = pool["variants"]
		var center := WildernessHexMath.axial_to_world(coord)
		# Precompute the same fan the terrain mesh draws (center height + 6 corner
		# heights), so a scattered tree follows the tilted surface instead of the flat
		# hex-centre height — which is what sank/floated them off-centre.
		var center_y := _hex_height(coord)
		var corner_off := WildernessHexMath.corner_offsets()
		var corner_y := []
		for ci in range(6):
			corner_y.append(_avg_height(_corner_sharing(coord, ci)))
		var rng := WorldGenRng.stream(_campaign_seed, "tree_scatter", 0, "%d,%d" % [coord.x, coord.y])
		for _i in range(int(pool["density"])):
			var variant_name: String = variants[rng.randi() % variants.size()]
			var ang := rng.randf() * TAU
			var rad := sqrt(rng.randf()) * SCATTER_JITTER * WildernessHexMath.HEX_RADIUS
			var local := Vector2(cos(ang) * rad, sin(ang) * rad)
			var px := center.x + local.x
			var pz := center.y + local.y
			var py := _fan_y(local, center_y, corner_off, corner_y)
			var yaw := rng.randf() * TAU
			var s := TREE_SCALE * (0.8 + rng.randf() * 0.5)
			var xform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)),
					Vector3(px, py, pz))
			if not per_variant.has(variant_name):
				per_variant[variant_name] = []
			per_variant[variant_name].append(xform)
			min_x = minf(min_x, px)
			max_x = maxf(max_x, px)
			min_z = minf(min_z, pz)
			max_z = maxf(max_z, pz)
	if per_variant.is_empty():
		return
	var aabb := AABB(Vector3(min_x, -2.0, min_z),
			Vector3(max_x - min_x + 1.0, HEIGHT_GAIN + 6.0, max_z - min_z + 1.0))
	for variant_name in per_variant:
		var mesh := _load_scatter_mesh(variant_name)
		if mesh == null:
			continue
		var xforms: Array = per_variant[variant_name]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.custom_aabb = aabb   # GDD §9.1: auto-AABB only covers origin -> wrong culling
		_scatter_root.add_child(mmi)


## Scatter pool for a hex: {variants: Array, density: int}. Empty = no scatter.
func _scatter_pool(t: HexTerrainData) -> Dictionary:
	if t.water != "" or t.elevation == "mountains":
		return {}
	match t.biome:
		"woods":
			if t.biome_subtype == "forest_taiga":
				return {"variants": _PINE, "density": 5}
			return {"variants": _BROADLEAF, "density": 6}
		"jungle":
			return {"variants": _PALM, "density": 6}
		"swamp":
			return {"variants": _WILLOW, "density": 3}
		"desert":
			return {"variants": _CACTUS, "density": 1}
	return {}


## Load a scatter variant's mesh from its single-mesh .glb (cached). The Mesh
## resource is ref-counted, so it survives freeing the throwaway instance.
func _load_scatter_mesh(variant_name: String) -> Mesh:
	if _scatter_mesh_cache.has(variant_name):
		return _scatter_mesh_cache[variant_name]
	var cat := "cactus" if variant_name.begins_with("cactus") else "tree"
	var path := "res://assets/wilderness_kit/%s/%s.glb" % [cat, variant_name]
	var mesh: Mesh = null
	var packed := load(path) as PackedScene
	if packed != null:
		var inst := packed.instantiate()
		var mi := _first_mesh_instance(inst)
		if mi != null:
			mesh = mi.mesh
		inst.free()
	if mesh == null:
		push_warning("wilderness scatter: no mesh in %s" % path)
	_scatter_mesh_cache[variant_name] = mesh
	return mesh


func _first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _first_mesh_instance(child)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# Edge rivers (GDD §8.3/§8.4) — water ribbons ALONG hex edges (corner->corner)
# ---------------------------------------------------------------------------

func _build_rivers() -> void:
	for c in _river_root.get_children():
		c.queue_free()
	if _map_data == null or _map_data.river_edges.is_empty():
		return
	var corner_off := WildernessHexMath.corner_offsets()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := 0
	for edge_data in _map_data.river_edges:
		if not (edge_data is HexRiverEdgeData):
			continue
		var owner := Vector2i(edge_data.hex_q, edge_data.hex_r)
		# Fog: skip if BOTH endpoint hexes are still hidden (don't reveal unseen rivers).
		var nb: Vector2i = owner + HexRiverEdgeData.neighbor_offset(edge_data.edge)
		if _fog_value(owner) < 0.25 and _fog_value(nb) < 0.25:
			continue
		# Edge e (0=N..5=NW) is bounded by mesh corners (e+4)%6 and (e+5)%6.
		var e: int = edge_data.edge
		var i1 := (e + 4) % 6
		var i2 := (e + 5) % 6
		var center := WildernessHexMath.axial_to_world(owner)
		var p1 := Vector3(center.x + corner_off[i1].x,
				_avg_height(_corner_sharing(owner, i1)) + RIVER_LIFT, center.y + corner_off[i1].y)
		var p2 := Vector3(center.x + corner_off[i2].x,
				_avg_height(_corner_sharing(owner, i2)) + RIVER_LIFT, center.y + corner_off[i2].y)
		var w: float = _RIVER_WIDTH.get(edge_data.navigability, 0.075)
		_emit_river_quad(st, p1, p2, w)
		emitted += 1
	if emitted == 0:
		return
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _river_material()
	_river_root.add_child(mi)


## A flat water quad of width [param w] from p1 to p2, perpendicular in XZ.
func _emit_river_quad(st: SurfaceTool, p1: Vector3, p2: Vector3, w: float) -> void:
	var dir := p2 - p1
	dir.y = 0.0
	if dir.length() < 1.0e-5:
		return
	dir = dir.normalized()
	var perp := Vector3(-dir.z, 0.0, dir.x) * (w * 0.5)
	var a := p1 - perp
	var b := p1 + perp
	var c := p2 + perp
	var d := p2 - perp
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 1)); st.add_vertex(d)


func _river_material() -> StandardMaterial3D:
	if _river_material_cache != null:
		return _river_material_cache
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.20, 0.48, 0.74, 0.95)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # thin ribbon, view from above only
	m.roughness = 0.1
	m.metallic = 0.0
	m.metallic_specular = 0.8
	# A touch of emission so rivers stay readable against shadowed terrain.
	m.emission_enabled = true
	m.emission = Color(0.05, 0.16, 0.26)
	m.emission_energy_multiplier = 0.5
	_river_material_cache = m
	return m


# ---------------------------------------------------------------------------
# Settlement / stronghold landmarks — PLACEHOLDER red cube + market-class label
# (I-VI for settlements by market_class, O for sub-market strongholds = Outpost).
# Quaternius glTF replacements come later; this just makes them visible/locatable.
# ---------------------------------------------------------------------------

const _ROMAN := ["", "I", "II", "III", "IV", "V", "VI"]


func _build_landmarks() -> void:
	for c in _landmark_root.get_children():
		c.queue_free()
	if _map_data == null:
		return
	# One marker per hex. A settlement and a stronghold on the same hex are generally
	# the same place (the stronghold became a settlement POI), so the settlement wins —
	# show its market class, not the stronghold's "O".
	var by_hex := {}   # Vector2i -> label String
	for s in _query_settlement_entrances():
		var coord := Vector2i(int(s.get("hex_q", 0)), int(s.get("hex_r", 0)))
		by_hex[coord] = _ROMAN[clampi(int(s.get("market_class", 6)), 1, 6)]
	for h in _query_strongholds():
		var coord := Vector2i(int(h.get("location_hex_q", 0)), int(h.get("location_hex_r", 0)))
		if not by_hex.has(coord):
			by_hex[coord] = "O"
	for coord in by_hex:
		if _fog_value(coord) < 0.25:
			continue
		_place_landmark(coord, by_hex[coord])

	# Dungeons: a purple pyramid at each entrance. Shown regardless of fog for now —
	# placeholder location markers so dungeons are visible before entry/discovery is
	# wired. A dungeon can share a hex with a settlement (undercity), so this pass is
	# independent of the settlement/stronghold markers above.
	for d in _query_dungeon_entrances():
		_place_dungeon_marker(Vector2i(int(d.get("hex_q", 0)), int(d.get("hex_r", 0))))


const LANDMARK_SIZE := 0.36


func _place_landmark(coord: Vector2i, text: String) -> void:
	var xz := WildernessHexMath.axial_to_world(coord)
	var base_y := _hex_height(coord)
	var holder := Node3D.new()
	# Holder at the cube centre; the cube sits ON the terrain (bottom at base_y).
	holder.position = Vector3(xz.x, base_y + LANDMARK_SIZE * 0.5, xz.y)

	var cube := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(LANDMARK_SIZE, LANDMARK_SIZE, LANDMARK_SIZE)
	cube.mesh = box
	cube.material_override = _landmark_cube_material()
	holder.add_child(cube)

	# Letter on the +Z face (which faces the yaw-0 iso camera) — part of the cube,
	# world-scaled (no billboard, no fixed_size) so it zooms with everything else.
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = LANDMARK_SIZE / 150.0
	label.modulate = Color(1, 1, 1)
	label.outline_size = 16
	label.outline_modulate = Color(0, 0, 0)
	label.double_sided = true
	label.rotation_degrees = Vector3(0.0, 180.0, 0.0)   # face +Z toward the camera
	label.position = Vector3(0.0, 0.0, LANDMARK_SIZE * 0.5 + 0.006)
	holder.add_child(label)

	_landmark_root.add_child(holder)


func _landmark_cube_material() -> StandardMaterial3D:
	if _landmark_mat != null:
		return _landmark_mat
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.12, 0.12)
	m.emission_enabled = true
	m.emission = Color(0.55, 0.06, 0.06)
	m.emission_energy_multiplier = 0.6
	_landmark_mat = m
	return m


## Purple pyramid marking a dungeon entrance (placeholder until proper art / entry).
## A square-based pyramid = CylinderMesh with top_radius 0 and 4 radial segments.
func _place_dungeon_marker(coord: Vector2i) -> void:
	var xz := WildernessHexMath.axial_to_world(coord)
	var base_y := _hex_height(coord)
	var pyramid := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = LANDMARK_SIZE * 0.62
	cyl.height = LANDMARK_SIZE * 1.35
	cyl.radial_segments = 4   # square base -> a 4-sided pyramid
	cyl.rings = 1
	pyramid.mesh = cyl
	pyramid.material_override = _dungeon_marker_material()
	# Origin is the cylinder centre, so lift by half its height to sit on the terrain.
	pyramid.position = Vector3(xz.x, base_y + cyl.height * 0.5, xz.y)
	pyramid.rotation_degrees = Vector3(0.0, 45.0, 0.0)   # a flat face toward the iso camera
	_landmark_root.add_child(pyramid)


func _dungeon_marker_material() -> StandardMaterial3D:
	if _dungeon_mat != null:
		return _dungeon_mat
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.20, 0.85)   # purple
	m.emission_enabled = true
	m.emission = Color(0.40, 0.08, 0.55)
	m.emission_energy_multiplier = 0.7
	_dungeon_mat = m
	return m


func _query_dungeon_entrances() -> Array:
	if _map_data == null:
		return []
	if not CampaignRepository.db.query_with_bindings(
			"SELECT hex_q, hex_r, name FROM dungeon_entrances WHERE map_id = ?",
			[_map_data.id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


func _query_settlement_entrances() -> Array:
	if _map_data == null:
		return []
	if not CampaignRepository.db.query_with_bindings(
			"SELECT hex_q, hex_r, market_class, name FROM settlement_entrances WHERE map_id = ?",
			[_map_data.id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


func _query_strongholds() -> Array:
	if _map_data == null:
		return []
	if not CampaignRepository.db.query_with_bindings("""
			SELECT location_hex_q, location_hex_r FROM strongholds
			WHERE location_map_id = ? AND status IN ('completed', 'claimed')
			      AND location_hex_q IS NOT NULL AND location_hex_r IS NOT NULL
		""", [_map_data.id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Camera, lighting, environment
# ---------------------------------------------------------------------------

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _zoom
	_camera.near = 0.1
	_camera.far = 4000.0
	add_child(_camera)
	_apply_camera()


func _apply_camera() -> void:
	if _camera == null:
		return
	_camera.size = _zoom
	var pitch := deg_to_rad(CAM_PITCH_DEG)
	var yaw := deg_to_rad(CAM_YAW_DEG)
	# Place the camera back+up from the target along the view direction.
	var dist := 200.0
	var dir := Vector3(0, sin(-pitch), cos(-pitch)).rotated(Vector3.UP, yaw)
	_camera.position = _cam_target + dir * dist
	_camera.rotation = Vector3(pitch, yaw, 0)


func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -50, 0)
	light.light_energy = 1.15
	light.shadow_enabled = true
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.70, 0.88)   # sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.62)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)


func _fit_camera() -> void:
	if _map_data == null or _map_data.hexes.is_empty():
		return
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var sum := Vector3.ZERO
	var n := 0
	for coord in _map_data.hexes.keys():
		var xz := WildernessHexMath.axial_to_world(coord)
		min_x = minf(min_x, xz.x); max_x = maxf(max_x, xz.x)
		min_z = minf(min_z, xz.y); max_z = maxf(max_z, xz.y)
		sum += Vector3(xz.x, _hex_height(coord), xz.y)
		n += 1
	_cam_target = sum / float(maxi(n, 1))
	var extent := maxf(max_x - min_x, max_z - min_z)
	_zoom_min = ZOOM_MIN_FLOOR
	_zoom = clampf(extent * 1.15, ZOOM_MIN_FLOOR, ZOOM_MAX)
	_apply_camera()


# ---------------------------------------------------------------------------
# Party tokens (simple capsule for the slice; heraldry viewport is polish)
# ---------------------------------------------------------------------------

func _rebuild_tokens() -> void:
	for child in _token_root.get_children():
		child.queue_free()
	_party_tokens.clear()
	if _map_data == null:
		return
	var party_hex := _map_data.party_hex
	var xz := WildernessHexMath.axial_to_world(party_hex)
	var marker := _make_party_marker()
	marker.position = Vector3(xz.x, _hex_height(party_hex) + 0.4, xz.y)
	_token_root.add_child(marker)
	_party_tokens["party"] = marker


func _make_party_marker() -> Node3D:
	var mi := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.18
	capsule.height = 0.7
	mi.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.85, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.5, 0.1)
	mat.emission_energy_multiplier = 0.4
	mi.material_override = mat
	return mi


# ---------------------------------------------------------------------------
# Input: pan / zoom / pick
# ---------------------------------------------------------------------------

## Continuous pan: WASD / arrows, plus mouse-to-edge panning (mirrors the 2D
## renderer's _process). Pans the camera TARGET in world XZ; speed scales with the
## ortho size so it feels consistent at any zoom.
func _process(delta: float) -> void:
	if not visible or _camera == null or _map_data == null:
		return
	var vp_size := get_viewport().get_visible_rect().size
	var mouse_pos := get_viewport().get_mouse_position()
	var pan := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		pan.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		pan.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		pan.y -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		pan.y += 1.0
	if pan == Vector2.ZERO and mouse_pos.x >= 0.0 and mouse_pos.x <= vp_size.x \
			and mouse_pos.y >= 0.0 and mouse_pos.y <= vp_size.y:
		if mouse_pos.x < EDGE_MARGIN:
			pan.x -= 1.0
		elif mouse_pos.x > vp_size.x - EDGE_MARGIN:
			pan.x += 1.0
		if mouse_pos.y < EDGE_MARGIN:
			pan.y -= 1.0
		elif mouse_pos.y > vp_size.y - EDGE_MARGIN:
			pan.y += 1.0
	if pan != Vector2.ZERO:
		var step := _zoom * EDGE_PAN_RATE * delta
		_cam_target += Vector3(pan.x, 0.0, pan.y).normalized() * step
		_apply_camera()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _camera == null:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_pick(false)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				_pick(true)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				_zoom = clampf(_zoom / ZOOM_FACTOR, _zoom_min, ZOOM_MAX)
				_apply_camera()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = clampf(_zoom * ZOOM_FACTOR, _zoom_min, ZOOM_MAX)
				_apply_camera()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
		# Middle-drag pan: 1:1 with the world (world-units-per-pixel = size / vp height).
		var vp_h := maxf(get_viewport().get_visible_rect().size.y, 1.0)
		var k := _zoom / vp_h
		_cam_target += Vector3(-event.relative.x * k, 0.0, -event.relative.y * k)
		_apply_camera()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_HOME:
		_fit_camera()
		get_viewport().set_input_as_handled()


## Surface-raycast pick: ray -> chunk collision -> world XZ -> axial (GDD §11.2).
## Uses the SubViewport-local mouse position (event.position is unreliable inside
## a SubViewport — the 2D renderer reads get_local_mouse_position for the same reason).
func _pick(is_context: bool) -> void:
	if _camera == null or _map_data == null:
		return
	var screen_pos := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 4000.0)
	var hit := space.intersect_ray(query)
	var coord: Vector2i
	if hit.is_empty():
		# Off-map fallback: intersect the water-level plane.
		var plane_y := WATER_LEVEL_RAW * HEIGHT_GAIN
		if absf(dir.y) < 1e-5:
			return
		var ti := (plane_y - from.y) / dir.y
		var p := from + dir * ti
		coord = WildernessHexMath.world_to_axial(Vector2(p.x, p.z))
	else:
		var p: Vector3 = hit["position"]
		coord = WildernessHexMath.world_to_axial(Vector2(p.x, p.z))
	if not _map_data.is_valid_coord(coord):
		return
	if is_context:
		hex_context_menu_requested.emit(coord, screen_pos)
	elif coord == _map_data.party_hex:
		party_token_clicked.emit("party", coord)
	else:
		hex_clicked.emit(coord)
