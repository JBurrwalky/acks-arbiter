shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

// Wilderness terrain splat (gdd-wilderness-hex-3d.md §7, §10).
// The continuous height mesh is textured by per-vertex biome WEIGHTS (COLOR.rgba)
// against up to four biome LAYERS (CUSTOM0.rgba) of a Texture2DArray, so biome
// transitions blend smoothly across hex boundaries instead of reading as tiles.
// The hex grid is drawn ON TOP in this same fragment (single pass) as a thin
// line — a non-destructive data overlay that never re-renders the geography.

uniform sampler2DArray biome_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 6.0;            // world units per albedo tile
uniform vec3 water_color : source_color = vec3(0.16, 0.34, 0.52);
uniform bool show_grid = true;
uniform vec3 grid_color : source_color = vec3(0.04, 0.04, 0.05);
uniform float grid_line = 0.022;          // line half-width in WORLD units
uniform float grid_strength = 0.55;
uniform float hex_radius = 0.5773503;
uniform vec3 fog_hidden_color : source_color = vec3(0.015, 0.015, 0.02);
uniform vec3 fog_explored_color : source_color = vec3(0.34, 0.34, 0.38);

varying vec3 v_world;
varying vec4 v_weights;
varying vec4 v_layers;
varying float v_water;
varying float v_fog;      // 0 hidden, 0.5 explored, 1 visible

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_weights = COLOR;
	v_layers = CUSTOM0;
	v_water = UV2.x;
	v_fog = UV2.y;
}

vec3 sample_terrain(vec2 uv) {
	float wsum = v_weights.x + v_weights.y + v_weights.z + v_weights.w;
	if (wsum < 0.0001) {
		return texture(biome_albedo, vec3(uv, v_layers.x)).rgb;
	}
	vec3 c = vec3(0.0);
	c += texture(biome_albedo, vec3(uv, v_layers.x)).rgb * v_weights.x;
	c += texture(biome_albedo, vec3(uv, v_layers.y)).rgb * v_weights.y;
	c += texture(biome_albedo, vec3(uv, v_layers.z)).rgb * v_weights.z;
	c += texture(biome_albedo, vec3(uv, v_layers.w)).rgb * v_weights.w;
	return c / wsum;
}

// world XZ -> nearest axial hex (q,r). FLAT-TOP, cube-rounded — the exact inverse
// of axial_to_world below and of WildernessHexMath / HexMapController.axial_to_godot_map
// (the shared even-q transform the 2D renderer + every data model are built on).
vec2 world_to_axial(vec2 xz) {
	float q = (2.0 / 3.0 * xz.x) / hex_radius;
	float r = (-1.0 / 3.0 * xz.x + (1.7320508 / 3.0) * xz.y) / hex_radius;
	float x = q;
	float z = r;
	float y = -x - z;
	float rx = floor(x + 0.5);
	float ry = floor(y + 0.5);
	float rz = floor(z + 0.5);
	float dx = abs(rx - x);
	float dy = abs(ry - y);
	float dz = abs(rz - z);
	if (dx > dy && dx > dz) {
		rx = -ry - rz;
	} else if (dy > dz) {
		ry = -rx - rz;
	} else {
		rz = -rx - ry;
	}
	return vec2(rx, rz);
}

vec2 axial_to_world(vec2 qr) {
	return vec2(hex_radius * 1.5 * qr.x, hex_radius * 1.7320508 * (qr.y + qr.x * 0.5));
}

// Signed distance to a FLAT-TOP hexagon (flat N/S edges, E/W vertices — the
// orientation the mesh corners + the 2D renderer use), apothem r = centre->edge.
// True Euclidean SDF, so the grid line is a uniform width all the way round.
float sd_hex_flat(vec2 p, float r) {
	const vec3 k = vec3(-0.8660254, 0.5, 0.5773503);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

void fragment() {
	vec2 uv = v_world.xz / tex_scale;
	vec3 terrain = sample_terrain(uv);
	vec3 albedo = mix(terrain, water_color, clamp(v_water, 0.0, 1.0));

	if (show_grid) {
		// Distance to the boundary of the flat-top hex this fragment falls in. The
		// nearest hex centre's edge IS the shared edge, so the line is continuous
		// across boundaries and uniform-width (a true SDF, not the rotated cube metric).
		vec2 center = axial_to_world(world_to_axial(v_world.xz));
		float d = abs(sd_hex_flat(v_world.xz - center, hex_radius * 0.8660254));
		float aa = fwidth(d) + 0.0015;
		float line = 1.0 - smoothstep(grid_line, grid_line + aa, d);
		albedo = mix(albedo, grid_color, line * grid_strength);
	}

	// fog of war (HIDDEN darkens, EXPLORED desaturates toward grey)
	if (v_fog < 0.25) {
		albedo = mix(albedo, fog_hidden_color, 0.82);
	} else if (v_fog < 0.75) {
		albedo = mix(albedo, fog_explored_color, 0.45);
	}

	ALBEDO = albedo;
	ROUGHNESS = mix(0.92, 0.35, clamp(v_water, 0.0, 1.0));
	METALLIC = 0.0;
}
