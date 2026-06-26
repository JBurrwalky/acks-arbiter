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
const HEIGHT_GAIN := 8.0          # field surface [0,1] -> world Y
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

var _controller: HexMapController = null
var _map_data: HexMapData = null
var _field = null                 # GeoField (reconstructed; cached)
var _field_ready := false

var _camera: Camera3D = null
var _terrain_root: Node3D = null
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
	_rebuild_tokens()
	_fit_camera()


func _on_visibility_updated() -> void:
	# Fog rides in per-vertex UV2; cheapest correct path is a terrain rebuild.
	if _map_data != null:
		_build_terrain()


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
	var campaign_seed := int(params.get("campaign_seed", 0))
	var sp := SettingParameters.from_dict(params)
	_field = GeoFieldGenerator.generate(campaign_seed, sp)
	GeoClimateGenerator.apply(_field, campaign_seed, sp)
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
		var center_blend := _vertex_blend([coord])
		var center_uv2 := _vertex_uv2([coord])

		# Precompute the 6 corners (height + biome blend from sharing hexes).
		var corners := []
		for i in range(6):
			var sharing := _corner_sharing(coord, i)
			var cpos := Vector3(center_xz.x + corner_off[i].x, _avg_height(sharing),
					center_xz.y + corner_off[i].y)
			corners.append({
				"pos": cpos,
				"blend": _vertex_blend(sharing),
				"uv2": _vertex_uv2(sharing),
			})

		# Fan: 6 triangles (center, corner i, corner i+1), wound so the top face
		# is front-facing (CCW) under cull_back viewed from +Y.
		for i in range(6):
			var c0: Dictionary = corners[i]
			var c1: Dictionary = corners[(i + 1) % 6]
			_emit_vertex(st, center, center_blend, center_uv2)
			_emit_vertex(st, c0["pos"], c0["blend"], c0["uv2"])
			_emit_vertex(st, c1["pos"], c1["blend"], c1["uv2"])

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


func _emit_vertex(st: SurfaceTool, pos: Vector3, blend: Dictionary, uv2: Vector2) -> void:
	st.set_color(blend["weights"])
	st.set_custom(0, blend["layers"])
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


## Combine the biome layers of the sharing hexes into <=4 (layer, weight) pairs.
## Returns {weights: Color, layers: Color}.
func _vertex_blend(coords: Array) -> Dictionary:
	var acc := {}   # layer -> weight
	for c in coords:
		var t := _terrain(c)
		if t == null:
			continue
		var lyr := _biome_layer(t)
		acc[lyr] = float(acc.get(lyr, 0.0)) + 1.0
	if acc.is_empty():
		return {"weights": Color(1, 0, 0, 0), "layers": Color(0, 0, 0, 0)}
	var layers := [0, 0, 0, 0]
	var weights := [0.0, 0.0, 0.0, 0.0]
	var keys: Array = acc.keys()
	keys.sort()
	var total := 0.0
	for w in acc.values():
		total += w
	var slot := 0
	for k in keys:
		if slot >= 4:
			break
		layers[slot] = k
		weights[slot] = float(acc[k]) / total
		slot += 1
	return {
		"weights": Color(weights[0], weights[1], weights[2], weights[3]),
		"layers": Color(float(layers[0]), float(layers[1]), float(layers[2]), float(layers[3])),
	}


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
