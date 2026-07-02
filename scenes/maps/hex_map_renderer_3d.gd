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
const HEIGHT_GAIN := 2.0          # field surface [0,1] -> world Y. ~2.5x vertical
								  # exaggeration vs real (1 hex=6mi=1 unit; 0.45 surface
								  # span=3500m=0.9 units). Was 3.0 (~3.7x, read as cliffs).
const WATER_LEVEL_RAW := 0.30     # below this the field is ocean; water mesh Y
## Mountain ruggedness (gdd-wilderness-hex-3d.md §17.3): a ridged-noise height bump added to
## mountain hexes in _hex_height. The corner-averaging in _corner_component_avg propagates a
## tapered, watertight version to the shared corners for free — peaks rise, the saddles
## between hexes stay lower — so the rounded bumps gain varied relief. Render-only; the hex
## grid (shader, world-XZ) and edge/tag data are untouched.
const RUGGED_AMP := 0.56          # world-unit height the ridged noise adds at a mountain peak
const RUGGED_FREQ := 0.63         # noise frequency (per world unit); adjacent hexes differ
## Sub-hex crags (§17.3): mountain hexes SUBDIVIDE each fan wedge and displace the INTERIOR
## sub-vertices by a finer, zero-mean ridged noise. The perimeter stays flat between the
## pinned corners (disp tapers to 0 as the centre-weight a → 0), so it's watertight with ANY
## neighbour — mountain edges tessellate to identical points, plains edges share the straight
## corner line. Peaks come from the coarse per-hex noise; crags from this.
const MOUNTAIN_SUBDIV := 4        # barycentric subdivisions per fan wedge on mountain hexes
const RUGGED_FINE_AMP := 0.3      # crag amplitude (world units), zero-mean ± around the surface
const RUGGED_FINE_FREQ := 2.4     # crag frequency (per world unit) — finer than the peak noise
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
# from res://assets/wilderness_textures/<name>.png in this order. Toon floor set
# (2026-06-29, gdd-wilderness-hex-3d.md §17.2): no separate clear/forest tile — both
# reuse the grassland floor (forests are scatter on top); swamp is now its own toon
# tile rather than darkened jungle.
const _LAYER_FILES := [
	"grassland", "grassland", "savanna", "tundra", "grassland", "jungle",
	"desert", "badlands", "mountain", "volcanic", "snow", "swamp",
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

## #1 Riverbed: lower the SHARED corner height for any corner a river touches, so the channel
## recesses between banks. Applied in the one corner-height function the terrain + cliff walls
## share (_corner_component_avg) → watertight, and canyons (river+cliff corners) stay seam-free.
## #1 Riverbed depth, SCALED BY RIVER SIZE (navigability). A fixed deep carve made every river
## a steep valley — too extreme for the many small streams. Now a small stream barely sinks
## (just enough that the water isn't floating) and only a big river cuts a real valley. The
## depth lowers the SHARED river corners in _corner_component_avg (watertight). Keep modest so
## the hex tilts gently.
const RIVER_CARVE_BY_NAV := {
	"none": 0.045, "small_craft": 0.07, "river_craft": 0.11, "large_craft": 0.16,
}
const RIVER_CARVE_DEFAULT := 0.045

## #2 Smooth meander: the channel is one Catmull-Rom curve through the river's (jittered) corner
## nodes, so bends ROUND across hex corners instead of kinking into rectangles. The DATA stays
## edge-canonical (movement still answers "on the edge"). A SHARED per-corner jitter keeps
## adjacent edges joined; the spline does the rest.
const RIVER_CORNER_JITTER := 0.08   # shared per-corner XZ wobble (frac of edge length)
const RIVER_SAMPLES := 9            # centreline samples per edge (curve smoothness)

## #3 Water shader: a seamless river-water PNG dropped here turns the flat-blue ribbon into an
## animated flowing channel (river_water.gdshader). Missing → graceful flat-blue fallback.
## (Ocean gets its own texture later — hence river-specific, not a generic "water".)
const RIVER_TEX_PATH := "res://assets/wilderness_textures/river.png"
const RIVER_WATER_SHADER := "res://engine/shaders/river_water.gdshader"

# --- Region labels + colour overlay (Jedidiah 2026-06-28) ------------------------
## Named-region labels on the 6-mile play map, ported from the 2D region_label_renderer
## (which the 3D renderer replaced). CONTINENTS are intentionally omitted here — they
## span far beyond the window so their label read as a tiny sliver; they're shown only
## on the 24-mile notebook map (political_map_view._draw_region_labels). Oceans/seas are
## dropped for the same reason. Regions are static geography, so labels+overlay are
## rebuilt only on map load / frontier growth, NOT on every fog tick.
const REGION_LABEL_LAYERS := {"coastal_landform": true, "terrain_cluster": true, "hydronym": true}
const REGION_BIG_SUBTYPES := {"ocean": true, "sea": true}   # too large for the 6-mile window
const REGION_SIG_MIN := 0.30
const REGION_SUB := 4                       # 24-mile parent -> 6-mile children (offset *4)
const REGION_LABEL_FONT_SIZE := 64          # texture resolution; world size is via pixel_size
const REGION_LABEL_MIN_WORLD := 0.5         # cull floor for the title's world-height
const REGION_LABEL_MAX_WORLD := 1.1         # hard cap so a big region can't splash a giant name
const REGION_LABEL_SHRINK := 0.82           # per-step shrink while dodging an overlap
const REGION_LABEL_ADVANCE := 0.55          # glyph advance as a fraction of text height
const REGION_LABEL_LIFT := 0.15            # sits just above the terrain it's painted onto
const REGION_LABEL_FILL := Color(0.0, 0.0, 0.0, 1.0)
const REGION_LABEL_OUTLINE := Color(0.97, 0.96, 0.90, 0.9)   # cream halo, legible over any biome
## Translucent per-region colour wash (the status-bar "Regions" toggle). Hugs the terrain
## just above the surface; floats UNDER labels + the party token.
const REGION_OVERLAY_LIFT := 0.04
const REGION_OVERLAY_ALPHA := 0.34

## City name labels over each settlement, gated by the SAME zoom LOD as the baron
## strongholds (STRONGHOLD_LOD_ZOOM) — they appear only when zoomed in. Black fill,
## white halo, hovering right over the settlement cube.
const CITY_LABEL_FONT_SIZE := 64
const CITY_LABEL_WORLD := 0.28              # world-height of the city name text (small; zoom-gated)
const CITY_LABEL_LIFT := 0.28              # above the settlement cube top
const CITY_LABEL_FILL := Color(0.0, 0.0, 0.0, 1.0)
const CITY_LABEL_OUTLINE := Color(1.0, 1.0, 1.0, 1.0)

var _controller: HexMapController = null
var _map_data: HexMapData = null
var _field = null                 # GeoField (reconstructed; cached)
var _field_ready := false
var _campaign_seed := 0
var _rugged_noise: FastNoiseLite = null   # coarse per-hex peak noise (§17.3)
var _rugged_fine_noise: FastNoiseLite = null   # fine sub-hex crag noise for subdivision (§17.3)

var _camera: Camera3D = null
var _terrain_root: Node3D = null
var _scatter_root: Node3D = null
var _scatter_mesh_cache := {}     # variant name -> Mesh
## Farmland tiles on cultivated (clear/grassland, in-domain, settlement-free) hexes.
var _farmland_root: Node3D = null
## path -> PackedScene cache for the full-scene models (settlement buildings + farmland);
## kept so repeated placements don't reload the glTF.
var _model_scene_cache := {}
## culture_id set whose culture is civ_or_clan == "clan" (beastmen + nomad/tribe humans) —
## their settlements get the clanhold building (Jedidiah: clanhold realms only). Built once.
var _clan_cultures := {}
var _clan_cultures_ready := false
## Baron-tier stronghold seat hexes (no watchtower) — handed to _build_farmland so they
## render as worked land instead. Populated in _build_landmarks before the deferred farmland.
var _barony_seat_hexes := {}
var _river_root: Node3D = null
var _river_material_cache: StandardMaterial3D = null
var _river_water_cache: ShaderMaterial = null   # #3 animated water (when the PNG is present)
## Vector2i hex -> Array[6] of per-corner carve DEPTHS (0 = no river there), scaled by river
## size. Set on ALL hexes sharing each river corner (max if several rivers meet) so the carve
## in _corner_component_avg is identical across the trio (watertight). A cheap dict lookup +
## index keeps the terrain hot path fast; rebuilt only on map/edge change (fog-independent).
var _river_corner_carve := {}
## Cliff/canyon walls (gdd-cliffs-canyons.md §7). _cliff_by_pair maps an unordered
## hex-pair key -> HexCliffEdgeData so the terrain mesh can keep cliff edges as a
## height DISCONTINUITY (stop averaging corners across them) and a vertical wall
## fills the gap. Empty when the map has no cliffs -> the terrain is unchanged.
var _cliff_root: Node3D = null
var _cliff_mat: StandardMaterial3D = null
var _mountain_tex: Texture2D = null
var _cliff_by_pair := {}
var _landmark_root: Node3D = null
var _landmark_mat: StandardMaterial3D = null
var _dungeon_mat: StandardMaterial3D = null
## Strongholds live in their own root so they can be hidden as a group when zoomed
## out (there can be hundreds from the feudal fill — they bury the map otherwise).
var _stronghold_root: Node3D = null
var _stronghold_mat: StandardMaterial3D = null
## Region overlay (translucent colour wash), region name labels, and city name labels —
## each in its own root so it can be layered + toggled independently. The overlay floats
## just over the terrain; the label roots float above the markers, under the party token.
var _region_overlay_root: Node3D = null
var _region_overlay_mat: StandardMaterial3D = null
var _region_overlay_enabled := false   # driven by EventBus.region_overlay_toggled
var _region_label_root: Node3D = null
var _city_label_root: Node3D = null
var _token_root: Node3D = null
## "Enter Settlement" / "Enter Dungeon" HUD buttons — shown when the party stands on a
## settlement/dungeon entrance hex; emit the entry signals the session state consumes.
## (Ported from the 2D hex_map_renderer, which the 3D swap left behind.)
var _entry_hud: CanvasLayer = null
var _enter_dungeon_btn: Button = null
var _enter_settlement_btn: Button = null
var _splat_material: ShaderMaterial = null
var _albedo_array: Texture2DArray = null
var _chunks: Array = []           # MeshInstance3D list (for rebuild)
var _hex_height_cache := {}       # Vector2i -> float (world Y at hex center)
var _party_tokens := {}           # party_id -> Node3D
## Dev: reveal the whole map (no fog) for renderer work — project setting
## acks/rendering/reveal_all_fog (default false). Refreshed on every map load, so
## flipping the setting + reloading the campaign reveals everything. OFF in normal play.
var _reveal_all_fog := false

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
	_farmland_root = Node3D.new()
	_farmland_root.name = "Farmland"
	add_child(_farmland_root)
	_river_root = Node3D.new()
	_river_root.name = "Rivers"
	add_child(_river_root)
	_cliff_root = Node3D.new()
	_cliff_root.name = "Cliffs"
	add_child(_cliff_root)
	# Region colour wash sits OVER the terrain layers (terrain/scatter/rivers/cliffs)
	# but UNDER the markers, labels, and party token.
	_region_overlay_root = Node3D.new()
	_region_overlay_root.name = "RegionOverlay"
	_region_overlay_root.visible = false
	add_child(_region_overlay_root)
	_landmark_root = Node3D.new()
	_landmark_root.name = "Landmarks"
	add_child(_landmark_root)
	_stronghold_root = Node3D.new()
	_stronghold_root.name = "Strongholds"
	add_child(_stronghold_root)
	# Labels float above the markers (region names + zoom-gated city names), under the token.
	_region_label_root = Node3D.new()
	_region_label_root.name = "RegionLabels"
	add_child(_region_label_root)
	_city_label_root = Node3D.new()
	_city_label_root.name = "CityLabels"
	add_child(_city_label_root)
	_token_root = Node3D.new()
	_token_root.name = "Tokens"
	add_child(_token_root)
	_build_environment()
	_build_camera()
	_build_splat_material()
	_build_entry_hud()
	EventBus.region_overlay_toggled.connect(_on_region_overlay_toggled)


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
	controller.frontier_grown.connect(_on_frontier_grown)
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
	_reveal_all_fog = bool(ProjectSettings.get_setting("acks/rendering/reveal_all_fog", false))
	_ensure_field()
	_rebuild_river_lookup()   # before terrain: corners a river runs through carve a riverbed
	_rebuild_cliff_lookup()   # before terrain: corners become cliff-aware
	_build_terrain()
	_build_rivers()
	_build_cliffs()           # vertical walls filling the cliff-edge discontinuities
	_build_landmarks()
	_build_regions()          # named-region colour overlay + region name labels (static geography)
	_rebuild_tokens()
	_update_enter_dungeon_button()
	_update_enter_settlement_button()
	_fit_camera()
	# Scatter is deferred so it never blocks the session-load flow (this runs inside
	# controller.load_map()); it also refreshes with fog via _on_visibility_updated.
	call_deferred("_build_scatter")
	call_deferred("_build_farmland")


func _on_visibility_updated() -> void:
	# Fog rides in per-vertex UV2; cheapest correct path is a terrain rebuild.
	# Scatter + rivers are gated on non-hidden hexes, so they refresh with the fog.
	if _map_data != null:
		_build_terrain()
		_build_rivers()
		_build_landmarks()
		call_deferred("_build_scatter")
	call_deferred("_build_farmland")


func _on_party_moved(_from_hex: Vector2i, _to_hex: Vector2i) -> void:
	_rebuild_tokens()
	_update_enter_dungeon_button()
	_update_enter_settlement_button()


func _on_frontier_grown(_map_id: String) -> void:
	# Rolling frontier (gdd-region-zoom-in.md §6): hexes + reseamed river/cliff edges were
	# appended to the live map. Rebuild the surface + edge geometry, but DO NOT _fit_camera —
	# the player keeps their current view (the growth is meant to be out of sight at the edge).
	_map_data = _controller.get_map()
	if _map_data == null:
		return
	_ensure_field()
	_rebuild_river_lookup()   # new hexes may add river corners to carve
	_rebuild_cliff_lookup()   # new hexes may add cliff edges; refresh corner-awareness first
	_build_terrain()
	_build_rivers()
	_build_cliffs()
	_build_landmarks()
	_build_regions()          # reproject region overlay/labels over the enlarged window
	_rebuild_tokens()
	call_deferred("_build_scatter")
	call_deferred("_build_farmland")


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
	var t := _terrain(coord)
	if _field != null:
		var cell := HexMapController.axial_to_godot_map(coord)
		var fx: int = clampi(cell.x, 0, _field.width - 1)
		var fy: int = clampi(cell.y, 0, _field.height - 1)
		var fi: int = _field.idx(fx, fy)
		raw = _field.surface[fi]
		if t != null and t.water == "lake":
			# A lake sits at its basin POUR level — the Priority-Flood "filled" DEM is
			# exactly the brim it fills to before spilling into its outlet river. Render
			# the surface there, not at the global sea plane, or a high-altitude lake
			# carves down to sea level and reads as a deep pit. (Clamp >= sea level so a
			# near-coast lake never dips below the ocean.) Truly steep rims become a real
			# shore now and a cliff face once that feature exists.
			raw = maxf(_field.filled[fi], WATER_LEVEL_RAW)
		elif t != null and t.water != "":
			raw = WATER_LEVEL_RAW  # ocean sits at the global sea plane
	else:
		raw = _tag_height(coord)
		if t != null and t.water != "":
			raw = WATER_LEVEL_RAW
	var y := raw * HEIGHT_GAIN
	# Mountain ruggedness (§17.3): a ridged bump per mountain hex centre. _corner_component_avg
	# averages this over the sharing hexes, so corners get a tapered, watertight share — no
	# seam, and markers/scatter/cliffs all ride the same rugged surface.
	if t != null and t.elevation == "mountains" and t.water == "":
		var mxz := WildernessHexMath.axial_to_world(coord)
		# ZERO-MEAN displacement (± around the field height): the hex's rendered surface
		# averages back to the RAW elevation, so ruggedizing never systematically inflates
		# a mountain away from what elevation_raw wants — only the texture roughens.
		y += _rugged_noise_value(mxz) * RUGGED_AMP
	_hex_height_cache[coord] = y
	return y


## Ridged height noise centred on ~0 at a world-XZ point (peaks along ridgelines, dips in the
## troughs), so the mountain bump raises AND lowers around the field height — mean stays at
## RAW. Lazily built from the seed.
func _rugged_noise_value(xz: Vector2) -> float:
	if _rugged_noise == null:
		_rugged_noise = FastNoiseLite.new()
		_rugged_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_rugged_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		_rugged_noise.fractal_octaves = 4
		_rugged_noise.frequency = RUGGED_FREQ
		_rugged_noise.seed = _campaign_seed
	return _rugged_noise.get_noise_2d(xz.x, xz.y)


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
		var is_rugged := t.elevation == "mountains" and t.water == ""   # subdivide + crag (§17.3)

		# Precompute the 6 corner positions + fog/water (height = mean of sharing hexes).
		var corner_pos := []
		var corner_uv2 := []
		for i in range(6):
			# Height = the cliff-aware component average (keeps a vertical discontinuity at
			# cliff edges that the wall fills); the biome texture blend keeps the full
			# sharing set for smooth coloring across the corner.
			corner_pos.append(Vector3(center_xz.x + corner_off[i].x,
					_corner_component_avg(coord, i),
					center_xz.y + corner_off[i].y))
			corner_uv2.append(_vertex_uv2(_corner_sharing(coord, i)))

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
			if is_rugged:
				# Subdivided, crag-displaced wedge (interior only; perimeter stays watertight).
				_emit_rugged_wedge(st, center, center_uv2, corner_pos[i], corner_pos[i1],
					corner_uv2[i], corner_uv2[i1], layers)
			else:
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


## Subdivided + crag-displaced fan wedge for a mountain hex (§17.3). Barycentrically tessellate
## the wedge (apex = hex centre `c`, base edge = the two pinned corners `ki`/`ki1`) into
## MOUNTAIN_SUBDIV rows and displace each sub-vertex's Y by the fine ridged noise, TAPERED by
## the centre-weight `a` so the base edge (a=0, the shared hex perimeter) stays flat between the
## pinned corners → watertight. Weights + fog uv2 barycentrically match the un-subdivided wedge,
## and layers are constant per wedge (no biome-index interpolation).
func _emit_rugged_wedge(st: SurfaceTool, c: Vector3, c_uv2: Vector2, ki: Vector3, ki1: Vector3,
		ki_uv2: Vector2, ki1_uv2: Vector2, layers: Color) -> void:
	var n := MOUNTAIN_SUBDIV
	var nf := float(n)
	var verts := {}   # Vector2i(p, q) -> {pos, w, uv2}; p = row (0 apex … n base), q = 0..p
	for p in range(n + 1):
		for q in range(p + 1):
			var a := float(n - p) / nf     # centre weight: 1 at apex, 0 on the perimeter edge
			var b := float(p - q) / nf
			var cc := float(q) / nf
			var base := c * a + ki * b + ki1 * cc
			var disp := _rugged_fine_value(Vector2(base.x, base.z)) * RUGGED_FINE_AMP * smoothstep(0.0, 0.25, a)
			verts[Vector2i(p, q)] = {
				"pos": Vector3(base.x, base.y + disp, base.z),
				"w": Color(0.5 + 0.5 * a, 0.5 - 0.5 * a, 0.0, 0.0),
				"uv2": c_uv2 * a + ki_uv2 * b + ki1_uv2 * cc,
			}
	for p in range(n):
		for q in range(p + 1):   # "up" triangles — same winding as the un-subdivided wedge
			_emit_sub(st, verts[Vector2i(p, q)], layers)
			_emit_sub(st, verts[Vector2i(p + 1, q)], layers)
			_emit_sub(st, verts[Vector2i(p + 1, q + 1)], layers)
		for q in range(p):       # "down" triangles fill the gaps
			_emit_sub(st, verts[Vector2i(p, q)], layers)
			_emit_sub(st, verts[Vector2i(p + 1, q + 1)], layers)
			_emit_sub(st, verts[Vector2i(p, q + 1)], layers)


func _emit_sub(st: SurfaceTool, v: Dictionary, layers: Color) -> void:
	st.set_color(v["w"])
	st.set_custom(0, layers)
	var pos: Vector3 = v["pos"]
	st.set_uv(Vector2(pos.x, pos.z))
	st.set_uv2(v["uv2"])
	st.add_vertex(pos)


## Fine sub-hex crag noise, zero-mean ~[-1,1] at a world-XZ point. Higher frequency than the
## per-hex peak noise so adjacent sub-vertices differ. Lazily built from the seed (+offset so
## it decorrelates from the coarse noise).
func _rugged_fine_value(xz: Vector2) -> float:
	if _rugged_fine_noise == null:
		_rugged_fine_noise = FastNoiseLite.new()
		_rugged_fine_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_rugged_fine_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		_rugged_fine_noise.fractal_octaves = 5
		_rugged_fine_noise.frequency = RUGGED_FINE_FREQ
		_rugged_fine_noise.seed = _campaign_seed + 101
	return _rugged_fine_noise.get_noise_2d(xz.x, xz.y)


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


# ---------------------------------------------------------------------------
# Cliff/canyon edges (gdd-cliffs-canyons.md §7)
# ---------------------------------------------------------------------------

## Build the set of SHARED corner-keys any river edge touches, so _corner_component_avg can
## carve a riverbed there (#1). Call before _build_terrain. Rivers are fog-independent, so
## this is rebuilt only when the map/edges change (like the cliff lookup), not per fog update.
func _rebuild_river_lookup() -> void:
	_river_corner_carve = {}
	if _map_data == null:
		return
	var corner_off := WildernessHexMath.corner_offsets()
	for edge_data in _map_data.river_edges:
		if not (edge_data is HexRiverEdgeData):
			continue
		var owner := Vector2i(edge_data.hex_q, edge_data.hex_r)
		var e: int = edge_data.edge
		var depth: float = float(RIVER_CARVE_BY_NAV.get(edge_data.navigability, RIVER_CARVE_DEFAULT))
		_mark_river_corner(owner, (e + 4) % 6, depth, corner_off)
		_mark_river_corner(owner, (e + 5) % 6, depth, corner_off)


## Record the carve [param depth] on EVERY hex sharing the physical corner (owner, i) — each at
## its OWN local corner index (matched by world position), taking the MAX where rivers meet —
## so the carve in _corner_component_avg is identical across the trio and the mesh stays
## watertight. Cold path (lookup build).
func _mark_river_corner(owner: Vector2i, i: int, depth: float, corner_off: Array) -> void:
	var world_p: Vector2 = WildernessHexMath.axial_to_world(owner) + corner_off[i]
	var trio: Array[Vector2i] = [owner, owner + _CORNER_NEIGHBORS[i][0], owner + _CORNER_NEIGHBORS[i][1]]
	for h in trio:
		if not _map_data.is_valid_coord(h):
			continue
		var li := _corner_index_at(WildernessHexMath.axial_to_world(h), world_p, corner_off)
		var arr = _river_corner_carve.get(h, null)   # untyped: get() returns null when absent
		if arr == null:
			arr = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
			_river_corner_carve[h] = arr
		arr[li] = maxf(float(arr[li]), depth)


## Canonical key for the PHYSICAL corner at index [param i] of [param coord] — the sorted trio
## of hexes meeting there — so every hex referencing the same corner yields one key. Used (off
## the hot path) to seed the SHARED meander corner jitter, keeping adjacent river edges joined.
func _corner_key(coord: Vector2i, i: int) -> String:
	var offs: Array = _CORNER_NEIGHBORS[i]
	var trio: Array[Vector2i] = [coord, coord + offs[0], coord + offs[1]]
	trio.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	return "%d,%d|%d,%d|%d,%d" % [trio[0].x, trio[0].y, trio[1].x, trio[1].y, trio[2].x, trio[2].y]


## Rebuild the unordered-pair -> cliff lookup from _map_data.cliff_edges. Call before
## _build_terrain so the corner heights are cliff-aware. No cliffs -> empty -> no-op.
func _rebuild_cliff_lookup() -> void:
	_cliff_by_pair = {}
	if _map_data == null:
		return
	for c in _map_data.cliff_edges:
		if not (c is HexCliffEdgeData):
			continue
		var owner := Vector2i(c.hex_q, c.hex_r)
		var nb: Vector2i = owner + HexCliffEdgeData.neighbor_offset(c.edge)
		_cliff_by_pair[_cliff_pair_key(owner, nb)] = c


func _cliff_pair_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]


## The cliff edge between adjacent hexes a,b, or null if none.
func _cliff_between(a: Vector2i, b: Vector2i):
	return _cliff_by_pair.get(_cliff_pair_key(a, b))


## CANONICAL per-corner height (gdd-cliffs-canyons.md §7): the mean _hex_height over the
## connected COMPONENT of [param coord] among the three hexes meeting at corner [param i],
## using only NON-cliff edges as connections. Cliffs separate height groups, so adjacent
## hexes agree across non-cliff edges (no crack) but step across cliffs (gap → wall), and a
## cliff that ends is "shorted out" through the bridging hex → the gap tapers to zero. The
## TERRAIN mesh AND the cliff walls both call THIS (bit-identical heights, no FP seams — F3).
## No cliffs → the whole trio connects → identical to _avg_height(_corner_sharing).
func _corner_component_avg(coord: Vector2i, i: int) -> float:
	var offs: Array = _CORNER_NEIGHBORS[i]
	var trio := [coord, coord + offs[0], coord + offs[1]]   # coord is index 0
	# BFS coord's component over non-cliff edges (the trio is pairwise adjacent).
	var comp := [0]
	var added := {0: true}
	var head := 0
	while head < comp.size():
		var a: int = comp[head]
		head += 1
		for b in range(3):
			if added.has(b) or not _map_data.is_valid_coord(trio[b]):
				continue
			if _cliff_between(trio[a], trio[b]) == null:
				added[b] = true
				comp.append(b)
	var sum := 0.0
	for k in comp:
		sum += _hex_height(trio[k])
	var h := sum / float(comp.size())
	# #1 Riverbed carve: a corner a river runs through drops by its size-scaled depth. Applied
	# HERE so the terrain mesh AND the cliff walls (both call this) carve identically — no crack,
	# and a canyon (river on a cliff's low side) just deepens. Cheap dict lookup; no-op w/o rivers.
	if not _river_corner_carve.is_empty():
		var arr = _river_corner_carve.get(coord, null)   # untyped: get() returns null when absent
		if arr != null:
			h -= float(arr[i])
	return h


## The corner index (0..5) of the hex centred at [param center] nearest world-XZ
## [param p] — matches a shared corner across two hexes by position, no index arithmetic.
func _corner_index_at(center: Vector2, p: Vector2, corner_off: Array) -> int:
	var best := 0
	var best_d := INF
	for j in range(6):
		var d: float = (center + corner_off[j]).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = j
	return best


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
	if _reveal_all_fog:
		return 1.0
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
		var path := "res://assets/wilderness_textures/%s.png" % name
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
		if not _reveal_all_fog and _map_data.get_fog_state(coord) == HexMapData.FogState.HIDDEN:
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
		var density := rng.randi_range(int(pool["density_min"]), int(pool["density_max"]))
		for _i in range(density):
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


## Scatter pool for a hex: {variants: Array, density_min: int, density_max: int}.
## Per-hex tree count is randi_range(min, max). Sparse on purpose — a hex is a 6-mile
## SYMBOL, not a literal forest: regular woods 1-2 trees, dense woods/jungle 3-4.
## Empty = no scatter.
func _scatter_pool(t: HexTerrainData) -> Dictionary:
	if t.water != "" or t.elevation == "mountains":
		return {}
	match t.biome:
		"woods":
			if t.biome_subtype == "forest_dense":
				return {"variants": _BROADLEAF, "density_min": 3, "density_max": 4}
			if t.biome_subtype == "forest_taiga":
				return {"variants": _PINE, "density_min": 1, "density_max": 2}
			return {"variants": _BROADLEAF, "density_min": 1, "density_max": 2}
		"jungle":
			return {"variants": _PALM, "density_min": 3, "density_max": 4}
		"swamp":
			return {"variants": _WILLOW, "density_min": 1, "density_max": 2}
		"desert":
			return {"variants": _CACTUS, "density_min": 1, "density_max": 1}
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


## Place farmland tiles on cultivated hexes: clear/grassland biome, civilized or borderlands
## territory (= inside a domain), and no settlement on the hex. Tile style follows the hex's
## territory; two variants seeded per hex. Fog-gated + rebuilt with the scatter.
func _build_farmland() -> void:
	for child in _farmland_root.get_children():
		child.queue_free()
	if _map_data == null:
		return
	var settlement_hexes := {}
	for s in _query_settlement_entrances():
		settlement_hexes[Vector2i(int(s.get("hex_q", 0)), int(s.get("hex_r", 0)))] = true
	# Eligible = clear/grassland in a civilized/borderlands domain, OR a Baron stronghold
	# seat (its watchtower was dropped). Never on a settlement hex. style picks the tile set.
	var farm_style := {}   # Vector2i -> "civilized" | "borderlands"
	for coord in _map_data.hexes.keys():
		if not _reveal_all_fog and _map_data.get_fog_state(coord) == HexMapData.FogState.HIDDEN:
			continue
		if settlement_hexes.has(coord):
			continue
		var t := _terrain(coord)
		if t == null or t.water != "":
			continue
		var is_barony: bool = _barony_seat_hexes.has(coord)
		var clear_ground := t.biome == "clear" and (
			t.biome_subtype == HexTerrainData.SUBTYPE_NONE
			or t.biome_subtype == HexTerrainData.SUBTYPE_CLEAR_GRASSLAND)
		var in_domain := (t.civilization == HexTerrainData.TERRITORY_CIVILIZED
			or t.civilization == HexTerrainData.TERRITORY_BORDERLANDS)
		if not (is_barony or (clear_ground and in_domain)):
			continue
		farm_style[coord] = "borderlands" if t.civilization == HexTerrainData.TERRITORY_BORDERLANDS else "civilized"
	for coord in farm_style:
		var style: String = farm_style[coord]
		var rng := WorldGenRng.stream(_campaign_seed, "farmland", 0, "%d,%d" % [coord.x, coord.y])
		var count := FARM_PER_HEX_MIN + (rng.randi() % (FARM_PER_HEX_MAX - FARM_PER_HEX_MIN + 1))
		for _i in range(count):
			var variant := 1 + (rng.randi() % 2)
			var path := "%s/%s-farmland-%d.gltf" % [BUILDING_DIR, style, variant]
			var ang := rng.randf() * TAU
			var rad := sqrt(rng.randf()) * FARM_JITTER * WildernessHexMath.HEX_RADIUS
			var off := Vector2(cos(ang) * rad, sin(ang) * rad)
			_place_fitted_scene(_farmland_root, coord, path, FARMLAND_FOOTPRINT,
				float(rng.randi() % 4) * (PI * 0.5), off)


# ---------------------------------------------------------------------------
# Edge rivers (GDD §8.3/§8.4) — water ribbons ALONG hex edges (corner->corner)
# ---------------------------------------------------------------------------

func _build_rivers() -> void:
	for c in _river_root.get_children():
		c.queue_free()
	if _map_data == null or _map_data.river_edges.is_empty():
		return
	var corner_off := WildernessHexMath.corner_offsets()
	var edge_len: float = (corner_off[0] - corner_off[1]).length()

	# Pass 1: build the DIRECTED river graph from the edge-canonical data. Each visible river
	# edge contributes its two carved, jittered corner nodes; the flow direction comes from the
	# stored flow_clockwise (the downstream "clockwise" vertex of edge e is the corner shared
	# with edge (e+1)%6 — mesh corner (e+5)%6 here), NOT from re-reading terrain heights.
	# Edges are a flat list; out_edges holds the indices leaving each corner, so a corner with
	# several out-edges (a hand-authored distributary; steepest-descent drainage never makes
	# one) branches into separate chains instead of silently dropping all but one.
	var nodes := {}            # corner_key -> {pos: Vector2 (jittered XZ), y: float}
	var edges: Array = []      # {up: String, to: String, navig: String}, data order
	var out_edges := {}        # up_key -> Array[int] (indices into `edges`)
	var in_deg := {}           # corner_key -> int (upstream edge count)
	var out_deg := {}          # corner_key -> int (downstream edge count)
	for edge_data in _map_data.river_edges:
		if not (edge_data is HexRiverEdgeData):
			continue
		var owner := Vector2i(edge_data.hex_q, edge_data.hex_r)
		var e: int = edge_data.edge
		var nb: Vector2i = owner + HexRiverEdgeData.neighbor_offset(e)
		# Fog: skip if BOTH endpoint hexes are still hidden (don't reveal unseen rivers).
		if _fog_value(owner) < 0.25 and _fog_value(nb) < 0.25:
			continue
		# Edge e (0=N..5=NW) is bounded by mesh corners (e+4)%6 and (e+5)%6.
		var i1 := (e + 4) % 6
		var i2 := (e + 5) % 6
		var ka := _corner_key(owner, i1)
		var kb := _corner_key(owner, i2)
		var center := WildernessHexMath.axial_to_world(owner)
		if not nodes.has(ka):
			nodes[ka] = {
				"pos": Vector2(center.x + corner_off[i1].x, center.y + corner_off[i1].y) + _corner_jitter(ka, edge_len),
				"y": _corner_component_avg(owner, i1) + RIVER_LIFT,
			}
		if not nodes.has(kb):
			nodes[kb] = {
				"pos": Vector2(center.x + corner_off[i2].x, center.y + corner_off[i2].y) + _corner_jitter(kb, edge_len),
				"y": _corner_component_avg(owner, i2) + RIVER_LIFT,
			}
		# flow_clockwise → downstream is the clockwise vertex (mesh corner i2 = kb).
		var up_key: String = ka if edge_data.flow_clockwise else kb
		var down_key: String = kb if edge_data.flow_clockwise else ka
		var ei := edges.size()
		edges.append({"up": up_key, "to": down_key, "navig": edge_data.navigability})
		if not out_edges.has(up_key):
			out_edges[up_key] = []
		(out_edges[up_key] as Array).append(ei)
		out_deg[up_key] = int(out_deg.get(up_key, 0)) + 1
		in_deg[down_key] = int(in_deg.get(down_key, 0)) + 1
		if not in_deg.has(up_key):
			in_deg[up_key] = 0      # ensure a source reads as in-degree 0
		if not out_deg.has(down_key):
			out_deg[down_key] = 0   # ensure a sink reads as out-degree 0

	# Pass 2: decompose the directed graph into maximal CHAINS. A chain breaks at any node
	# that is NOT a simple pass-through (in-degree 1 AND out-degree 1) — i.e. at sources,
	# sinks, confluences (in-degree > 1), and distributaries (out-degree > 1). Each chain
	# renders as ONE continuous Catmull-Rom ribbon welded across its corners, flowing
	# downstream. Every edge is consumed exactly once (the fallback catches any cycle).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var visited := {}          # edge index -> true once consumed
	var emitted := 0
	for ei2 in range(edges.size()):
		var up: String = edges[ei2]["up"]
		if int(in_deg.get(up, 0)) == 1 and int(out_deg.get(up, 0)) == 1:
			continue           # interior node — reached by an upstream chain
		if visited.has(ei2):
			continue
		if _emit_river_chain(st, nodes, edges, out_edges, in_deg, out_deg, visited, ei2):
			emitted += 1
	# Fallback: any edge not consumed (a pure cycle — impossible in a drainage DAG) becomes
	# its own ribbon, so no river is ever silently dropped.
	for ei3 in range(edges.size()):
		if visited.has(ei3):
			continue
		if _emit_river_chain(st, nodes, edges, out_edges, in_deg, out_deg, visited, ei3):
			emitted += 1
	if emitted == 0:
		return
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _river_water_material()
	_river_root.add_child(mi)


## Walk the directed river graph downstream from edge [param start_ei] (which leaves a source /
## confluence / distributary), following the single out-edge while interior nodes stay
## degree-(1 in, 1 out), collecting corner positions/heights + per-segment width, then emit ONE
## continuous welded ribbon for the chain. Stops at any non-pass-through node so junctions stay
## crisp. Marks each consumed edge visited. Returns true if a ribbon was emitted.
func _emit_river_chain(st: SurfaceTool, nodes: Dictionary, edges: Array, out_edges: Dictionary,
		in_deg: Dictionary, out_deg: Dictionary, visited: Dictionary, start_ei: int) -> bool:
	var keys: Array[String] = [str(edges[start_ei]["up"])]
	var navigs: Array = []     # navigability of the edge keys[i] -> keys[i+1]
	var ei := start_ei
	while ei >= 0 and not visited.has(ei):
		visited[ei] = true
		var ed: Dictionary = edges[ei]
		var nxt: String = ed["to"]
		keys.append(nxt)
		navigs.append(ed["navig"])
		# Continue only through a pass-through node (1 in, 1 out); stop at a confluence
		# (in-degree > 1), distributary (out-degree > 1), or sink (no out-edge).
		ei = -1
		if int(in_deg.get(nxt, 0)) == 1 and int(out_deg.get(nxt, 0)) == 1:
			var outs: Array = out_edges.get(nxt, [])
			if not outs.is_empty() and not visited.has(int(outs[0])):
				ei = int(outs[0])
	var m := keys.size()
	if m < 2:
		return false
	var cpos: Array[Vector2] = []
	var cy: Array[float] = []
	for k in keys:
		cpos.append(nodes[k]["pos"] as Vector2)
		cy.append(float(nodes[k]["y"]))
	# Sample each segment with Catmull-Rom through the chain's OWN corners (continuous across
	# corners → welded). Phantom endpoints reflect so the spline runs straight out of the
	# source / mouth. Non-final segments stop one sample short to avoid duplicating the shared
	# corner; the final segment includes its endpoint.
	var pts: Array[Vector3] = []
	var flows: Array = []
	var widths: Array = []
	for seg in range(m - 1):
		var p0: Vector2 = cpos[seg - 1] if seg > 0 else (cpos[0] * 2.0 - cpos[1])
		var p1: Vector2 = cpos[seg]
		var p2: Vector2 = cpos[seg + 1]
		var p3: Vector2 = cpos[seg + 2] if seg + 2 < m else (cpos[m - 1] * 2.0 - cpos[m - 2])
		var w: float = _RIVER_WIDTH.get(navigs[seg], 0.075)
		var n_samp: int = RIVER_SAMPLES + 1 if seg == m - 2 else RIVER_SAMPLES
		for s in range(n_samp):
			var t := float(s) / float(RIVER_SAMPLES)
			var p := _catmull(p0, p1, p2, p3, t)
			pts.append(Vector3(p.x, lerpf(cy[seg], cy[seg + 1], t), p.y))
			var tang := _catmull_tangent(p0, p1, p2, p3, t)
			if tang.length() < 1.0e-5:
				tang = p2 - p1
			flows.append(tang.normalized())   # chain is ordered upstream→downstream
			widths.append(w)
	_emit_river_ribbon(st, pts, widths, flows)
	return true


## A CONTINUOUS welded water ribbon through centreline points [param pts], with a per-sample
## width [param widths] and per-sample downstream flow [param flows]. Each sample's
## perpendicular comes from its own averaged tangent, so consecutive quads SHARE their seam
## vertices — no tearing, no per-quad tilt. XZ-perp only; each sample keeps its own height.
func _emit_river_ribbon(st: SurfaceTool, pts: Array, widths: Array, flows: Array) -> void:
	var n := pts.size()
	if n < 2:
		return
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for s in range(n):
		var pc: Vector3 = pts[s]
		var pa: Vector3 = pts[maxi(s - 1, 0)]
		var pb: Vector3 = pts[mini(s + 1, n - 1)]
		var tang := Vector2(pb.x - pa.x, pb.z - pa.z)
		if tang.length() < 1.0e-5:
			tang = Vector2(1.0, 0.0)
		tang = tang.normalized()
		var hw: float = float(widths[s]) * 0.5
		var perp := Vector2(-tang.y, tang.x) * hw
		left.append(Vector3(pc.x - perp.x, pc.y, pc.z - perp.y))
		right.append(Vector3(pc.x + perp.x, pc.y, pc.z + perp.y))
	for s in range(1, n):
		var c0 := _flow_color(flows[s - 1])
		var c1 := _flow_color(flows[s])
		var l0: Vector3 = left[s - 1]
		var r0: Vector3 = right[s - 1]
		var l1: Vector3 = left[s]
		var r1: Vector3 = right[s]
		# World-XZ UVs (tile/scroll the texture); per-vertex COLOR.rg carries the local DOWNHILL
		# flow direction so the shader scrolls each channel along its OWN course (not universal).
		st.set_color(c0); st.set_uv(Vector2(l0.x, l0.z)); st.add_vertex(l0)
		st.set_color(c0); st.set_uv(Vector2(r0.x, r0.z)); st.add_vertex(r0)
		st.set_color(c1); st.set_uv(Vector2(r1.x, r1.z)); st.add_vertex(r1)
		st.set_color(c0); st.set_uv(Vector2(l0.x, l0.z)); st.add_vertex(l0)
		st.set_color(c1); st.set_uv(Vector2(r1.x, r1.z)); st.add_vertex(r1)
		st.set_color(c1); st.set_uv(Vector2(l1.x, l1.z)); st.add_vertex(l1)


## Encode a flow direction (unit XZ) into vertex COLOR.rg (0..1); the shader unmaps it.
func _flow_color(flow: Vector2) -> Color:
	return Color(flow.x * 0.5 + 0.5, flow.y * 0.5 + 0.5, 0.0, 1.0)


## Catmull-Rom point at [param t] on the segment p1->p2 (p0,p3 are the neighbouring control
## points) — smooths the channel ACROSS hex corners so it reads as a flowing curve, not rectangles.
static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t \
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 \
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Catmull-Rom tangent (unnormalised) at [param t] — the local downstream axis for the flow.
static func _catmull_tangent(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	return 0.5 * ((-p0 + p2) \
		+ 2.0 * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t \
		+ 3.0 * (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t2)


## Stable 0..1 hash of a string — cosmetic determinism, no global RNG. The meander is render-
## only (never feeds game logic), but must look identical on every rebuild.
static func _hash01(s: String) -> float:
	return float(hash(s) & 0xFFFFFF) / float(0x1000000)


## SHARED XZ jitter for a physical corner (keyed on its canonical corner key) so adjacent
## river edges meet at the same nudged point → a continuous channel. Bounded to a fraction of
## the hex edge length.
func _corner_jitter(key: String, edge_len: float) -> Vector2:
	var ang := _hash01(key + "#a") * TAU
	var mag := _hash01(key + "#m") * RIVER_CORNER_JITTER * edge_len
	return Vector2(cos(ang), sin(ang)) * mag


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


## The river surface material: an ANIMATED water shader when the seamless water PNG is present
## (#3), else the flat-blue StandardMaterial fallback — so rivers render either way and "just
## work" the moment the texture is dropped at WATER_TEX_PATH and reimported. The ribbon's UVs
## are world XZ, so the shader tiles + scrolls the texture consistently across the channel.
func _river_water_material() -> Material:
	if _river_water_cache != null:
		return _river_water_cache
	if not ResourceLoader.exists(RIVER_TEX_PATH) or not ResourceLoader.exists(RIVER_WATER_SHADER):
		return _river_material()
	var tex := load(RIVER_TEX_PATH) as Texture2D
	var shader := load(RIVER_WATER_SHADER) as Shader
	if tex == null or shader == null:
		return _river_material()
	var sm := ShaderMaterial.new()
	sm.shader = shader
	sm.set_shader_parameter("water_tex", tex)
	# Align the water's hex-grid overlay with the terrain's (same hex_radius) so the grid lines
	# read continuous across land and river → the river looks set INTO the ground.
	sm.set_shader_parameter("hex_radius", WildernessHexMath.HEX_RADIUS)
	_river_water_cache = sm
	return sm


# ---------------------------------------------------------------------------
# Cliff/canyon walls — a vertical quad along each cliff edge filling the corner
# discontinuity the cliff-aware terrain leaves (gdd-cliffs-canyons.md §7). Mountain
# texture for now; double-sided so it reads from inside a canyon.
# ---------------------------------------------------------------------------

func _build_cliffs() -> void:
	for ch in _cliff_root.get_children():
		ch.queue_free()
	if _map_data == null or _map_data.cliff_edges.is_empty():
		return
	var corner_off := WildernessHexMath.corner_offsets()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := 0
	for c in _map_data.cliff_edges:
		if not (c is HexCliffEdgeData):
			continue
		var owner := Vector2i(c.hex_q, c.hex_r)
		var nb: Vector2i = owner + HexCliffEdgeData.neighbor_offset(c.edge)
		if not (_map_data.is_valid_coord(owner) and _map_data.is_valid_coord(nb)):
			continue
		# Edge e is bounded by owner corners (e+4)%6 and (e+5)%6 (matches _build_chunk).
		var k1: int = (c.edge + 4) % 6
		var k2: int = (c.edge + 5) % 6
		var oc := WildernessHexMath.axial_to_world(owner)
		var p1: Vector2 = oc + corner_off[k1]
		var p2: Vector2 = oc + corner_off[k2]
		# Owner + neighbour heights at the two shared corners — the SAME canonical
		# component average the terrain fan uses (F3: bit-identical, no seams). The
		# neighbour's corner indices are matched by world position.
		var oh1 := _corner_component_avg(owner, k1)
		var oh2 := _corner_component_avg(owner, k2)
		var nc := WildernessHexMath.axial_to_world(nb)
		var nh1 := _corner_component_avg(nb, _corner_index_at(nc, p1, corner_off))
		var nh2 := _corner_component_avg(nb, _corner_index_at(nc, p2, corner_off))
		# Wall span = [min, max] of the two component averages (F1: never an inverted,
		# backfacing quad — independent of which raw hex is "higher").
		var top1: float = maxf(oh1, nh1)
		var top2: float = maxf(oh2, nh2)
		var bot1: float = minf(oh1, nh1)
		var bot2: float = minf(oh2, nh2)
		if absf(top1 - bot1) < 1.0e-4 and absf(top2 - bot2) < 1.0e-4:
			continue   # degenerate at BOTH corners (cliff tapered to zero here) — F2
		var vb1 := Vector3(p1.x, bot1, p1.y)
		var vt1 := Vector3(p1.x, top1, p1.y)
		var vt2 := Vector3(p2.x, top2, p2.y)
		var vb2 := Vector3(p2.x, bot2, p2.y)
		st.add_vertex(vb1); st.add_vertex(vt1); st.add_vertex(vt2)
		st.add_vertex(vb1); st.add_vertex(vt2); st.add_vertex(vb2)
		emitted += 1
	if emitted == 0:
		return
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _cliff_wall_material()
	_cliff_root.add_child(mi)


func _cliff_wall_material() -> StandardMaterial3D:
	if _cliff_mat != null:
		return _cliff_mat
	var m := StandardMaterial3D.new()
	var tex := _mountain_texture()
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / 6.0
	# Darken the rock to a shadowed exposed-cliff face so it READS against the lighter
	# mountain terrain it sits in (the un-modulated mountain texture blends in).
	m.albedo_color = Color(0.52, 0.47, 0.42) if tex != null else Color(0.30, 0.26, 0.22)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.96
	m.metallic = 0.0
	_cliff_mat = m
	return m


## The mountain biome layer pulled out of the splat Texture2DArray as a standalone
## Texture2D for the wall material (cached). Null if the array isn't ready.
func _mountain_texture() -> Texture2D:
	if _mountain_tex != null:
		return _mountain_tex
	if _albedo_array != null and _albedo_array.get_layers() > LAYER_MOUNTAIN:
		var img := _albedo_array.get_layer_data(LAYER_MOUNTAIN)
		if img != null:
			_mountain_tex = ImageTexture.create_from_image(img)
	return _mountain_tex


# ---------------------------------------------------------------------------
# Settlement / stronghold landmarks — PLACEHOLDER red cube + market-class label
# (I-VI for settlements by market_class, O for sub-market strongholds = Outpost).
# Quaternius glTF replacements come later; this just makes them visible/locatable.
# ---------------------------------------------------------------------------

const _ROMAN := ["", "I", "II", "III", "IV", "V", "VI"]


func _build_landmarks() -> void:
	for c in _landmark_root.get_children():
		c.queue_free()
	for c in _stronghold_root.get_children():
		c.queue_free()
	for c in _city_label_root.get_children():
		c.queue_free()
	if _map_data == null:
		return
	# Settlements: a Quaternius building model sized by market class (a settlement and a
	# stronghold on the same hex are the same place — the settlement wins). Each discovered
	# settlement also gets a zoom-gated name label (see _place_city_label).
	_ensure_clan_cultures()
	var settlement_classes := {}   # Vector2i -> int market_class (1..6)
	var settlement_names := {}     # Vector2i -> settlement name String
	var settlement_clan := {}      # Vector2i -> bool (owning culture is a clan culture)
	for s in _query_settlement_entrances():
		var coord := Vector2i(int(s.get("hex_q", 0)), int(s.get("hex_r", 0)))
		settlement_classes[coord] = clampi(int(s.get("market_class", 6)), 1, 6)
		settlement_names[coord] = str(s.get("name", ""))
		settlement_clan[coord] = _clan_cultures.has(str(s.get("culture_id", "")))
	for coord in settlement_classes:
		if _fog_value(coord) < 0.25:
			continue
		_place_settlement_building(coord, int(settlement_classes[coord]), bool(settlement_clan.get(coord, false)))
		_place_city_label(coord, str(settlement_names.get(coord, "")))

	# Strongholds: only Marquis-tier (and higher) seats render as watchtowers; the numerous
	# Baron-tier feudal-fill leaves drop to farmland instead (handed to _build_farmland via
	# _barony_seat_hexes). Deduped against settlements (a settlement on the seat wins). A hex
	# with both a March seat + its seat Barony takes the higher tier.
	_barony_seat_hexes = {}
	var stronghold_tier := {}   # Vector2i -> max realm-title rank
	for h in _query_strongholds():
		var coord := Vector2i(int(h.get("location_hex_q", 0)), int(h.get("location_hex_r", 0)))
		if settlement_classes.has(coord):
			continue
		var rank := int(_TITLE_RANK.get(str(h.get("realm_title", "Baron")), 0))
		stronghold_tier[coord] = maxi(int(stronghold_tier.get(coord, -1)), rank)
	for coord in stronghold_tier:
		if _fog_value(coord) < 0.25:
			continue
		if int(stronghold_tier[coord]) >= _MARQUIS_RANK:
			_place_stronghold_marker(coord)
		else:
			_barony_seat_hexes[coord] = true
	_update_stronghold_lod()

	# Dungeons: a purple pyramid at each entrance. Shown regardless of fog for now —
	# placeholder location markers so dungeons are visible before entry/discovery is
	# wired. A dungeon can share a hex with a settlement (undercity), so this pass is
	# independent of the settlement/stronghold markers above.
	for d in _query_dungeon_entrances():
		_place_dungeon_marker(Vector2i(int(d.get("hex_q", 0)), int(d.get("hex_r", 0))))


const LANDMARK_SIZE := 0.36
## Stronghold cubes are smaller + dimmer than settlements, and the whole group hides
## when the camera's ortho size exceeds this (zoomed out) — see _update_stronghold_lod.
const STRONGHOLD_SIZE := 0.18
const STRONGHOLD_LOD_ZOOM := 18.0
## Non-market-class strongholds (baron/marquis seats) render as a small watchtower model
## instead of the dim cube (Jedidiah 2026-06-29). Auto-fitted; sits in _stronghold_root so
## it keeps the zoomed-in LOD gate. Falls back to the cube if the model can't load.
const STRONGHOLD_MODEL := "res://assets/wilderness_kit/building/WatchTower_SecondAge_Level1.gltf"
const STRONGHOLD_FOOTPRINT := 0.175
## Only Marquis-tier (and higher) stronghold seats render as watchtowers; the numerous
## Baron-tier feudal-fill leaves drop to farmland instead (Jedidiah 2026-06-29). Title
## ladder: Baron < Marquis < Count < Duke < Prince < King < Emperor (realm_title_resolver.gd).
const _TITLE_RANK := {"Baron": 0, "Marquis": 1, "Count": 2, "Duke": 3, "Prince": 4, "King": 5, "Emperor": 6}
const _MARQUIS_RANK := 1

# --- Settlement building + farmland models (Jedidiah 2026-06-29) ------------------
## Settlement buildings by market class: civ-MC-I … civ-MC-VI for civilized realms,
## clanhold-MC-III … VI for clan-culture realms (see _place_settlement_building). The model
## is auto-fitted by its AABB to a per-class footprint so a Class-I metropolis reads bigger
## than a Class-VI hamlet regardless of the source model's native scale. (Mountains were
## tried + cut — too exaggerated; their assets were removed.)
const BUILDING_DIR := "res://assets/wilderness_kit/building"
const SETTLEMENT_FOOTPRINT_MIN := 0.75    # MC VI (hamlet) footprint, world units
const SETTLEMENT_FOOTPRINT_STEP := 0.16   # added per class below VI (MC I = +5 steps -> ~1.55)
## Farmland tiles fill cultivated hexes (clear/grassland in a civilized/borderlands domain,
## no settlement) AND the Baron-tier stronghold seats (whose watchtowers are dropped). 1-3
## jittered tiles per hex; civilized-farmland-* vs borderlands-farmland-* by territory.
const FARMLAND_FOOTPRINT := 0.17    # a small cultivated patch
const FARM_PER_HEX_MIN := 1
const FARM_PER_HEX_MAX := 3
const FARM_JITTER := 0.55           # fraction of HEX_RADIUS the farm tiles scatter within


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


## Place a settlement building sized to its market class. Clan-culture settlements get the
## clanhold model (which only spans Class III-VI — clamped — since clanholds never reach a
## metropolis); everyone else gets the civilized building. Falls back to the old red cube +
## roman letter if the model can't be loaded (so a settlement is never invisible).
func _place_settlement_building(coord: Vector2i, market_class: int, is_clan: bool) -> void:
	var mc := clampi(market_class, 1, 6)
	var path: String
	if is_clan:
		path = "%s/clanhold-MC-%s.glb" % [BUILDING_DIR, _ROMAN[clampi(mc, 3, 6)]]
	else:
		path = "%s/civ-MC-%s.glb" % [BUILDING_DIR, _ROMAN[mc]]
	var footprint := SETTLEMENT_FOOTPRINT_MIN + float(6 - mc) * SETTLEMENT_FOOTPRINT_STEP
	if not _place_fitted_scene(_landmark_root, coord, path, footprint, 0.0):
		_place_landmark(coord, _ROMAN[mc])


## Build the clan-culture set once: a culture is "clan" (clanhold-style) when its catalog
## identity has civ_or_clan == "clan" (beastmen + nomad/tribe humans) — same signal as
## tools/check_clanholds.gd. Static catalog, so campaign-independent + cached.
func _ensure_clan_cultures() -> void:
	if _clan_cultures_ready:
		return
	_clan_cultures_ready = true
	var all_cultures: Dictionary = CultureCatalogLoader.load_all()
	for cid in all_cultures:
		var coc := str(CultureCatalogLoader.identity(all_cultures[cid]).get("civ_or_clan", "civ"))
		if coc == "clan":
			_clan_cultures[str(cid)] = true


## Instance a full glTF/glb scene at [param coord], auto-fitted: uniformly scaled so its
## widest XZ extent == [param footprint], centred on the hex, and seated so its base rests
## on the terrain. [param yaw] spins it about its centre. Returns false if the model is
## missing/empty (caller can fall back). Scale-agnostic — works whatever the source units.
func _place_fitted_scene(parent: Node3D, coord: Vector2i, path: String, footprint: float, yaw: float,
		xz_offset: Vector2 = Vector2.ZERO) -> bool:
	var packed := _load_packed(path)
	if packed == null:
		return false
	var inst := packed.instantiate()
	var aabb := _combined_aabb(inst)
	var fp := maxf(aabb.size.x, aabb.size.z)
	if fp < 0.0001:
		inst.free()
		return false
	var s := footprint / fp
	var xz := WildernessHexMath.axial_to_world(coord) + xz_offset
	var holder := Node3D.new()
	holder.position = Vector3(xz.x, _hex_height(coord), xz.y)
	holder.rotation = Vector3(0.0, yaw, 0.0)
	var center := aabb.position + aabb.size * 0.5
	inst.scale = Vector3(s, s, s)
	# Centre the model's XZ on the hex and seat its base (min-Y) at the holder origin.
	inst.position = Vector3(-center.x * s, -aabb.position.y * s, -center.z * s)
	holder.add_child(inst)
	parent.add_child(holder)
	return true


## Cached PackedScene load for the model kits (settlements + mountains).
func _load_packed(path: String) -> PackedScene:
	if _model_scene_cache.has(path):
		return _model_scene_cache[path]
	var p := load(path) as PackedScene
	if p == null:
		push_warning("wilderness model: cannot load %s" % path)
	_model_scene_cache[path] = p
	return p


## The combined local-space AABB of every MeshInstance3D under [param root] (transforms
## accumulated down the tree), so a multi-part model fits as a whole.
func _combined_aabb(root: Node) -> AABB:
	var boxes: Array = []
	_collect_mesh_aabbs(root, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB()
	var acc: AABB = boxes[0]
	for i in range(1, boxes.size()):
		acc = acc.merge(boxes[i])
	return acc


func _collect_mesh_aabbs(node: Node, xform: Transform3D, out: Array) -> void:
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(t * (node as MeshInstance3D).mesh.get_aabb())
	for c in node.get_children():
		_collect_mesh_aabbs(c, t, out)


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


## A small, dim red cube for a stronghold (no letter). Sits in _stronghold_root so the
## whole layer can be hidden when zoomed out; recessive vs the brighter settlement cube.
func _place_stronghold_marker(coord: Vector2i) -> void:
	if _place_fitted_scene(_stronghold_root, coord, STRONGHOLD_MODEL, STRONGHOLD_FOOTPRINT, 0.0):
		return
	# Fallback: the original dim cube if the watchtower model can't be loaded.
	var xz := WildernessHexMath.axial_to_world(coord)
	var base_y := _hex_height(coord)
	var cube := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(STRONGHOLD_SIZE, STRONGHOLD_SIZE, STRONGHOLD_SIZE)
	cube.mesh = box
	cube.material_override = _stronghold_marker_material()
	cube.position = Vector3(xz.x, base_y + STRONGHOLD_SIZE * 0.5, xz.y)
	_stronghold_root.add_child(cube)


func _stronghold_marker_material() -> StandardMaterial3D:
	if _stronghold_mat != null:
		return _stronghold_mat
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.16, 0.16)   # muted brick — quieter than settlements
	m.emission_enabled = true
	m.emission = Color(0.22, 0.05, 0.05)
	m.emission_energy_multiplier = 0.4
	_stronghold_mat = m
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
			"SELECT hex_q, hex_r, market_class, name, culture_id FROM settlement_entrances WHERE map_id = ?",
			[_map_data.id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


func _query_strongholds() -> Array:
	if _map_data == null:
		return []
	if not CampaignRepository.db.query_with_bindings("""
			SELECT s.location_hex_q, s.location_hex_r, d.realm_title
			FROM strongholds s LEFT JOIN domains d ON s.domain_id = d.id
			WHERE s.location_map_id = ? AND s.status IN ('completed', 'claimed')
			      AND s.location_hex_q IS NOT NULL AND s.location_hex_r IS NOT NULL
		""", [_map_data.id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Enter Settlement / Enter Dungeon HUD buttons (ported from the 2D renderer). Appear when
# the party stands on a settlement/dungeon entrance hex; emit the entry signals the
# session state (wilderness_explore_state) consumes to run the transition.
# ---------------------------------------------------------------------------

func _build_entry_hud() -> void:
	_entry_hud = CanvasLayer.new()
	_entry_hud.layer = 10   # above the world, below the status bar (80) and dice prompts
	add_child(_entry_hud)
	var vbox := VBoxContainer.new()
	vbox.anchor_left = 1.0
	vbox.anchor_right = 1.0
	vbox.anchor_top = 0.0
	vbox.anchor_bottom = 0.0
	vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # size to content, hug the right edge
	vbox.grow_vertical = Control.GROW_DIRECTION_END
	vbox.offset_right = -240.0   # clear the ~220px EntityOutliner "Orders" sidebar on the right
	vbox.offset_top = 24.0
	vbox.add_theme_constant_override("separation", 8)
	_entry_hud.add_child(vbox)

	_enter_dungeon_btn = Button.new()
	_enter_dungeon_btn.text = "Enter Dungeon"
	_enter_dungeon_btn.visible = false
	_enter_dungeon_btn.pressed.connect(_on_enter_dungeon_pressed)
	_style_overlay_button(_enter_dungeon_btn)
	vbox.add_child(_enter_dungeon_btn)

	_enter_settlement_btn = Button.new()
	_enter_settlement_btn.text = "Enter Settlement"
	_enter_settlement_btn.visible = false
	_enter_settlement_btn.pressed.connect(_on_enter_settlement_pressed)
	_style_overlay_button(_enter_settlement_btn)
	vbox.add_child(_enter_settlement_btn)


## Show the "Enter <name>" dungeon button when the party's hex holds a dungeon entrance.
func _update_enter_dungeon_button() -> void:
	if _enter_dungeon_btn == null or _map_data == null:
		return
	var party_hex := _map_data.party_hex
	for entrance in CampaignRepository.get_dungeon_entrances_for_map(_map_data.id):
		if int(entrance.get("hex_q", 999)) == party_hex.x and int(entrance.get("hex_r", 999)) == party_hex.y:
			_enter_dungeon_btn.text = "Enter %s" % str(entrance.get("name", "Dungeon"))
			_enter_dungeon_btn.set_meta("entrance_data", entrance)
			_enter_dungeon_btn.visible = true
			return
	_enter_dungeon_btn.visible = false


## Show the "Enter <name>" settlement button when the party's hex holds a settlement entrance.
func _update_enter_settlement_button() -> void:
	if _enter_settlement_btn == null or _map_data == null:
		return
	var party_hex := _map_data.party_hex
	for entrance in CampaignRepository.get_settlement_entrances_for_map(_map_data.id):
		if int(entrance.get("hex_q", 999)) == party_hex.x and int(entrance.get("hex_r", 999)) == party_hex.y:
			_enter_settlement_btn.text = "Enter %s" % str(entrance.get("name", "Settlement"))
			_enter_settlement_btn.set_meta("entrance_data", entrance)
			_enter_settlement_btn.visible = true
			return
	_enter_settlement_btn.visible = false


## Enter the dungeon on the party's hex. Lazily generates the voxel layout on first entry,
## then emits dungeon_entry_requested at the default entry cell. (The 2D renderer offers a
## transition-cell picker when a dungeon has several; that modal is a follow-up — this enters
## at the primary entry.)
func _on_enter_dungeon_pressed() -> void:
	var entrance: Dictionary = _enter_dungeon_btn.get_meta("entrance_data", {})
	if entrance.is_empty():
		return
	var pre = JSON.parse_string(str(entrance.get("dungeon_data", "")))
	var is_generated: bool = pre is Dictionary and (pre.has("cells") or pre.has("levels"))
	if not is_generated:
		var generated: String = DungeonFixtureService.get_or_generate_voxel(entrance)
		if generated.is_empty():
			push_error("wilderness 3D: dungeon generation failed for '%s'" % str(entrance.get("id", "?")))
			return
	var dungeon_dict = JSON.parse_string(str(entrance.get("dungeon_data", "")))
	if not (dungeon_dict is Dictionary):
		return
	var entry_pos: Vector2i
	if dungeon_dict.has("cells"):
		var entry_dict: Dictionary = dungeon_dict.get("entry", {})
		entry_pos = Vector2i(int(entry_dict.get("col", 0)), int(entry_dict.get("row", 0)))
	else:
		var levels: Array = dungeon_dict.get("levels", [])
		if levels.is_empty():
			return
		var level1: Dictionary = levels[0]
		entry_pos = Vector2i(int(level1.get("entry_col", 0)), int(level1.get("entry_row", 0)))
	dungeon_entry_requested.emit(entrance, entry_pos)


## Enter the settlement on the party's hex. Lazily stocks a baseline interior on first entry,
## then emits settlement_entry_requested at the first entry PoI. (The 2D renderer offers a
## gate picker when several exist; that modal is a follow-up — this enters at the first gate.)
func _on_enter_settlement_pressed() -> void:
	var entrance: Dictionary = _enter_settlement_btn.get_meta("entrance_data", {})
	if entrance.is_empty():
		return
	var entrance_id := str(entrance.get("id", ""))
	if not SettlementDictBuilder.has_relational_pois(entrance_id) \
			and str(entrance.get("settlement_data", "")).is_empty():
		SettlementLayoutGenerator.new().seed_pois(
			entrance_id, int(entrance.get("market_class", 6)), str(entrance.get("name", "Settlement")))
	var settlement_dict = null
	if SettlementDictBuilder.has_relational_pois(entrance_id):
		settlement_dict = SettlementDictBuilder.build_from_pois(entrance_id, entrance)
	else:
		settlement_dict = JSON.parse_string(str(entrance.get("settlement_data", "")))
	if not (settlement_dict is Dictionary):
		return
	var entry_pois: Array = []
	for district in settlement_dict.get("districts", []):
		for poi in district.get("pois", []):
			if poi.get("is_entry_exit", false):
				entry_pois.append(poi)
	if not entry_pois.is_empty():
		settlement_entry_requested.emit(entrance, str(entry_pois[0].get("id", "")))
		return
	# Fallback: the first PoI of the first district so the player can still enter.
	var districts: Array = settlement_dict.get("districts", [])
	if districts.is_empty():
		return
	var pois: Array = districts[0].get("pois", [])
	if not pois.is_empty():
		settlement_entry_requested.emit(entrance, str(pois[0].get("id", "")))


## Parchment-on-dark styling so the button reads over the map (mirrors the 2D renderer).
func _style_overlay_button(btn: Button) -> void:
	var bg_normal := StyleBoxFlat.new()
	bg_normal.bg_color = Color(0.90, 0.84, 0.74, 0.96)
	bg_normal.border_color = Color(0.46, 0.33, 0.19, 1.0)
	bg_normal.set_border_width_all(1)
	bg_normal.set_corner_radius_all(5)
	bg_normal.content_margin_left = 12.0
	bg_normal.content_margin_right = 12.0
	bg_normal.content_margin_top = 6.0
	bg_normal.content_margin_bottom = 6.0
	var bg_hover := bg_normal.duplicate() as StyleBoxFlat
	bg_hover.bg_color = Color(0.82, 0.76, 0.65, 0.98)
	var bg_pressed := bg_normal.duplicate() as StyleBoxFlat
	bg_pressed.bg_color = Color(0.70, 0.64, 0.54, 1.0)
	btn.add_theme_stylebox_override("normal", bg_normal)
	btn.add_theme_stylebox_override("hover", bg_hover)
	btn.add_theme_stylebox_override("pressed", bg_pressed)
	btn.add_theme_color_override("font_color", Color(0.09, 0.06, 0.03, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.09, 0.06, 0.03, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.09, 0.06, 0.03, 1.0))


# ---------------------------------------------------------------------------
# Named regions — translucent colour overlay + region name labels
# (Jedidiah 2026-06-28; ports the 2D region_label_renderer onto the 3D surface).
# Static geography → built on map load / frontier growth, fog-independent.
# ---------------------------------------------------------------------------

func _build_regions() -> void:
	var regions := _collect_label_regions()
	_build_region_overlay(regions)
	_build_region_labels(regions)


## The labelable regions overlapping the play window, as
##   {id, name, subtype, layer, members: Array[Vector2i]} — members are the in-window
## 6-mile child hexes. Continents + oceans/seas are excluded (too big for this scale);
## the notebook 24-mile map carries those. Empty for a non-generated campaign.
func _collect_label_regions() -> Array:
	var out: Array = []
	if _map_data == null:
		return out
	var cid := GameState.campaign_id
	if cid.is_empty():
		return out
	for reg in SettingRepository.list_regions(cid):
		if not REGION_LABEL_LAYERS.has(str(reg.get("layer", ""))):
			continue
		if REGION_BIG_SUBTYPES.has(str(reg.get("subtype", ""))):
			continue
		if float(reg.get("significance", 0.0)) < REGION_SIG_MIN:
			continue
		var name := str(reg.get("name_primary", "")).strip_edges()
		if name.is_empty():
			continue
		var members := _project_region_members(str(reg.get("hexes", "[]")))
		if members.is_empty():
			continue
		out.append({
			"id": str(reg.get("id", "")), "name": name,
			"subtype": str(reg.get("subtype", "")), "layer": str(reg.get("layer", "")),
			"members": members,
		})
	return out


## A region's 24-mile parent hexes (JSON [[q,r],…]) → the in-window 6-mile child hexes it
## covers (offset space, SUB=4 — mirrors the 2D region_label_renderer._project_members).
func _project_region_members(hexes_json: String) -> Array:
	var out: Array = []
	var parsed = JSON.parse_string(hexes_json)
	if not (parsed is Array):
		return out
	for pair in parsed:
		if not (pair is Array and (pair as Array).size() == 2):
			continue
		var poff := WorldGrid.axial_to_offset(Vector2i(int(pair[0]), int(pair[1])))
		for lx in range(REGION_SUB):
			for ly in range(REGION_SUB):
				var child := WorldGrid.offset_to_axial(poff.x * REGION_SUB + lx, poff.y * REGION_SUB + ly)
				if _map_data.hexes.has(child):
					out.append(child)
	return out


## One translucent mesh washing each named region's hexes with a stable per-region colour.
## A hex in several regions takes the SMALLEST region's colour (paint biggest-first; the
## later, smaller region overwrites), so local features (a forest, a range) read distinctly
## rather than drowning under a broad parent. Hugs the terrain a hair above the surface.
func _build_region_overlay(regions: Array) -> void:
	for c in _region_overlay_root.get_children():
		c.queue_free()
	if _map_data == null or regions.is_empty():
		return
	var ordered := regions.duplicate()
	ordered.sort_custom(func(a, b): return (a["members"] as Array).size() > (b["members"] as Array).size())
	var hex_color := {}   # Vector2i -> Color
	for reg in ordered:
		var col := _region_color(str(reg["id"]))
		for h in reg["members"]:
			hex_color[h] = col
	if hex_color.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corner_off := WildernessHexMath.corner_offsets()
	for coord in hex_color:
		_emit_overlay_hex(st, coord, corner_off, hex_color[coord])
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _region_overlay_material()
	_region_overlay_root.add_child(mi)
	_region_overlay_root.visible = _region_overlay_enabled


## A single hex's flat fan (centre + 6 corners), lifted just above the terrain it hugs,
## every vertex tinted [param col]. Winding is irrelevant (unshaded, cull-disabled).
func _emit_overlay_hex(st: SurfaceTool, coord: Vector2i, corner_off: Array, col: Color) -> void:
	var center_xz := WildernessHexMath.axial_to_world(coord)
	var center := Vector3(center_xz.x, _hex_height(coord) + REGION_OVERLAY_LIFT, center_xz.y)
	var cpos: Array = []
	for i in range(6):
		cpos.append(Vector3(center_xz.x + corner_off[i].x,
				_corner_component_avg(coord, i) + REGION_OVERLAY_LIFT,
				center_xz.y + corner_off[i].y))
	for i in range(6):
		var i1 := (i + 1) % 6
		st.set_color(col)
		st.add_vertex(center)
		st.set_color(col)
		st.add_vertex(cpos[i])
		st.set_color(col)
		st.add_vertex(cpos[i1])


func _region_overlay_material() -> StandardMaterial3D:
	if _region_overlay_mat != null:
		return _region_overlay_mat
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED   # don't occlude markers/labels
	_region_overlay_mat = m
	return m


## Stable, deterministic colour for a region id (hash → hue), with the overlay alpha baked
## in (the material reads vertex-colour alpha). Adjacent regions have unrelated ids, so
## their hues land far apart — distinct patches without storing a palette.
func _region_color(region_id: String) -> Color:
	var h := 0
	for i in range(region_id.length()):
		h = (h * 31 + region_id.unicode_at(i)) & 0x7fffffff
	var hue := float(h % 360) / 360.0
	return Color.from_hsv(hue, 0.55, 0.95, REGION_OVERLAY_ALPHA)


## Billboarded region name labels (+ a small subtype subtitle) at each region's in-window
## centroid. Placed BIGGEST-REGION-FIRST with greedy overlap resolution in world-XZ
## (zoom-invariant, like the 2D region_label_renderer): a label that would collide is
## shrunk to dodge, and culled if it can't stay above the minimum — so the major features
## keep their names and minor ones yield instead of piling into an illegible jumble.
## The whole layer is gated to the ZOOMED-OUT view (see _update_stronghold_lod) so it
## reads as a map overview and never fights the zoomed-in city labels.
func _build_region_labels(regions: Array) -> void:
	for c in _region_label_root.get_children():
		c.queue_free()
	# Candidate per region: centroid + base world-height, ordered biggest-region-first.
	var cands: Array = []
	for reg in regions:
		var members: Array = reg["members"]
		var n := float(members.size())
		var cx := 0.0
		var cy := 0.0
		var cz := 0.0
		for h in members:
			var xz := WildernessHexMath.axial_to_world(h)
			cx += xz.x
			cz += xz.y
			cy += _hex_height(h)
		cx /= n
		cy /= n
		cz /= n
		var name := str(reg["name"])
		cands.append({
			"name": name,
			"cx": cx, "cy": cy, "cz": cz, "len": maxi(name.length(), 1),
			"count": members.size(),
			"base_h": _region_label_world_h(_members_extent(members, Vector2(cx, cz)), name.length()),
		})
	cands.sort_custom(func(a, b): return int(a["count"]) > int(b["count"]))
	# Greedy de-clutter: shrink-to-fit, cull below the floor. Boxes are world-XZ AABBs.
	var placed: Array = []
	for cd in cands:
		var world_h := float(cd["base_h"])
		var fitted := false
		while world_h >= REGION_LABEL_MIN_WORLD:
			var box := _region_label_box(cd, world_h)
			if not _xz_box_hits(box, placed):
				placed.append(box)
				fitted = true
				break
			world_h *= REGION_LABEL_SHRINK
		if not fitted:
			continue
		var px := world_h / float(REGION_LABEL_FONT_SIZE)
		var title := _make_map_label(str(cd["name"]), REGION_LABEL_FILL, REGION_LABEL_OUTLINE,
				REGION_LABEL_FONT_SIZE, px)
		# Lie FLAT on the ground (parallel to the geography, like a name printed on a map)
		# rather than standing up as a billboard — and draw on top so terrain never clips it.
		title.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		title.no_depth_test = true
		title.position = Vector3(cd["cx"], float(cd["cy"]) + REGION_LABEL_LIFT, cd["cz"])
		_region_label_root.add_child(title)
	_region_label_root.visible = _zoom > STRONGHOLD_LOD_ZOOM


## Diameter (≈) of the member cloud about its centroid, in world units.
func _members_extent(members: Array, c: Vector2) -> float:
	var maxd := 0.0
	for h in members:
		var xz := WildernessHexMath.axial_to_world(h)
		maxd = maxf(maxd, Vector2(xz.x, xz.y).distance_to(c))
	return maxd * 2.0


## World text-height that makes the title span ~70% of the region, clamped so neither a
## sprawling region splashes a giant name nor a sliver shrinks below the floor.
func _region_label_world_h(extent: float, name_len: int) -> float:
	var target_w := extent * 0.7
	var world_h := target_w / (REGION_LABEL_ADVANCE * float(maxi(name_len, 1)))
	return clampf(world_h, REGION_LABEL_MIN_WORLD, REGION_LABEL_MAX_WORLD)


## The label's world-XZ footprint box (centred at the centroid). The title lies flat on the
## ground, so its text width is the X extent and its single-line height the Z extent — a
## faithful ground footprint for de-cluttering. {x, z, hw, hh}.
func _region_label_box(cd: Dictionary, world_h: float) -> Dictionary:
	var w := REGION_LABEL_ADVANCE * float(int(cd["len"])) * world_h
	return {"x": float(cd["cx"]), "z": float(cd["cz"]), "hw": w * 0.5, "hh": world_h * 0.6}


func _xz_box_hits(box: Dictionary, placed: Array) -> bool:
	for p in placed:
		if absf(float(box["x"]) - float(p["x"])) < float(box["hw"]) + float(p["hw"]) \
				and absf(float(box["z"]) - float(p["z"])) < float(box["hh"]) + float(p["hh"]):
			return true
	return false


## A world-sized map label (black fill + halo outline), faces the camera and
## zooms with the map. Shared by region names and city names.
func _make_map_label(text: String, fill: Color, outline: Color, font_size: int,
		pixel_size: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel_size
	l.modulate = fill
	l.outline_modulate = outline
	l.outline_size = maxi(2, int(float(font_size) * 0.12))
	l.double_sided = true
	l.fixed_size = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Orientation is the caller's call: city names billboard (face camera); region names
	# lie flat on the ground (see _build_region_labels / _place_city_label).
	return l


## A settlement's name label, hovering over its cube. Added to _city_label_root, whose
## visibility is gated by the stronghold zoom LOD (_update_stronghold_lod).
func _place_city_label(coord: Vector2i, name: String) -> void:
	if name.strip_edges().is_empty():
		return
	var xz := WildernessHexMath.axial_to_world(coord)
	var base_y := _hex_height(coord)
	var px := CITY_LABEL_WORLD / float(CITY_LABEL_FONT_SIZE)
	var l := _make_map_label(name, CITY_LABEL_FILL, CITY_LABEL_OUTLINE, CITY_LABEL_FONT_SIZE, px)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # face the camera, hovering over the town
	l.position = Vector3(xz.x, base_y + LANDMARK_SIZE + CITY_LABEL_LIFT, xz.y)
	_city_label_root.add_child(l)


func _on_region_overlay_toggled(enabled: bool) -> void:
	_region_overlay_enabled = enabled
	if _region_overlay_root != null:
		_region_overlay_root.visible = enabled


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
	_update_stronghold_lod()


## Strongholds are a strategic-clutter layer: hide the whole group when zoomed out
## (ortho size large), reveal it only when zoomed in past STRONGHOLD_LOD_ZOOM, where
## the smaller dim cubes recede behind the terrain. Settlements + dungeons ignore this.
## City NAME labels share the same gate (Jedidiah: appear "on zoom in") — quiet when
## zoomed out, legible once the player zooms into a locale. REGION names are the inverse:
## an overview layer that shows when zoomed OUT and yields to the city names up close, so
## the two label tiers never fight for the same screen space.
func _update_stronghold_lod() -> void:
	var zoomed_in := _zoom <= STRONGHOLD_LOD_ZOOM
	if _stronghold_root != null:
		_stronghold_root.visible = zoomed_in
	if _city_label_root != null:
		_city_label_root.visible = zoomed_in
	if _region_label_root != null:
		_region_label_root.visible = not zoomed_in


func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -50, 0)
	light.light_energy = 0.85
	light.shadow_enabled = true
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.70, 0.88)   # sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.62)
	# Low ambient: high ambient washed the toon colours past 1.0 AND filled the shadow side so
	# the hillshade couldn't darken slopes. 0.30 keeps lit ≈ 1.0 and lets the shadow band read.
	e.ambient_light_energy = 0.30
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
