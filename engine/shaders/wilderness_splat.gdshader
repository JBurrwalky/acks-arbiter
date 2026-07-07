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
uniform float blend_jitter = 0.4;         // edge-dither strength (feathered transition)
uniform float dither_freq = 2.6;          // dither feature frequency (per world unit)
// Desert (6) / badlands (7) / mountain (8) / volcanic (9) / snow-glacial (10) are
// high-contrast and feather harshly (sharp, deep intrusions into neighbours). Damp the edge
// jitter for those pairs so the transition stays smooth + shallow, while gentle grass/forest
// edges keep their feathering. jitter_hi_scale=0 → clean geometric hex edge (no feather).
uniform float jitter_hi_scale : hint_range(0.0, 1.0) = 0.15;
// Relief readability: the geometry is kept gently exaggerated (HEIGHT_GAIN ~2x) so
// slopes don't read as cliffs, but that leaves gentle HILLS hard to see. Instead of
// adding height back, exaggerate the slope of the NORMAL the engine LIGHTS with, so a
// gentle hill shades as if steeper. Purely a lighting effect — geometry is untouched.
uniform float relief_gain = 5.0;          // 1 = real normals; higher = hills read more
uniform float relief_cavity = 0.18;       // extra ambient darkening on any slope (AO feel)
// Cel hillshade (gdd-wilderness-hex-3d.md §17.1.1): a SOFT 2-band slope shade reads as the
// §9.1 cartographic hatching. cel_hillshade=false falls back to a smooth narrow Lambert
// wash (the art §7.2 environment default) — the A/B toggle the GDD asks for.
uniform bool cel_hillshade = true;
uniform float shade_threshold : hint_range(0.0, 1.0) = 0.45;   // dot(N,L) split between the 2 bands
uniform float shade_softness : hint_range(0.001, 0.5) = 0.09;  // transition width (lower = crisper cel)
uniform float shade_lit : hint_range(0.0, 1.5) = 1.0;          // lit-band multiplier
uniform float shade_dark : hint_range(0.0, 1.0) = 0.42;        // shadow-band multiplier (lower = stronger)
uniform float wash_min : hint_range(0.0, 1.0) = 0.65;          // smooth-mode floor
uniform float wash_max : hint_range(0.0, 1.5) = 1.0;           // smooth-mode ceiling
// Atmospheric wash (art §7.5): a small mood tint multiplied over the surface. Daylight
// cool-blue by default; the renderer can drive it per time-of-day later.
uniform vec3 atmospheric_tint : source_color = vec3(0.82, 0.88, 1.0);
uniform float atmospheric_blend : hint_range(0.0, 1.0) = 0.08;
// Toon posterize: quantise the albedo into flat colour bands so even FLAT terrain reads cel
// (the slope hillshade only acts where there's relief). Fewer steps = stronger banding;
// raise toward 32 to effectively disable.
uniform float posterize_steps : hint_range(2.0, 32.0) = 8.0;

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

// Cheap hash value-noise for organic edge dithering.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Two-layer biome blend: slot0 = own hex, slot1 = the edge neighbour. The layer pair
// is CONSTANT per triangle (no layer-index interpolation -> no concentric rings).
// v_weights.y runs 0 at the hex centre -> 0.5 at the shared edge; noise jitters the
// transition (ramped up away from the centre) so the boundary feathers, not bands.
vec3 sample_terrain(vec2 uv, vec2 world_xz) {
	float blend = v_weights.y;
	float dw = smoothstep(0.04, 0.25, blend);
	float n = vnoise(world_xz * dither_freq) - 0.5;
	// Damp the jitter when either side is a high-contrast arid/rocky/icy layer (6 desert …
	// 10 snow) — those feather too sharply and too deep otherwise.
	float jitter = blend_jitter;
	if ((v_layers.x >= 6.0 && v_layers.x <= 10.0) || (v_layers.y >= 6.0 && v_layers.y <= 10.0)) {
		jitter *= jitter_hi_scale;
	}
	blend = clamp(blend + n * jitter * dw, 0.0, 0.5);
	vec3 a = texture(biome_albedo, vec3(uv, v_layers.x)).rgb;
	vec3 b = texture(biome_albedo, vec3(uv, v_layers.y)).rgb;
	return mix(a, b, blend);
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
	vec3 terrain = sample_terrain(uv, v_world.xz);
	vec3 albedo = mix(terrain, water_color, clamp(v_water, 0.0, 1.0));

	// Atmospheric mood wash (art §7.5) — small tint over the whole surface.
	albedo = mix(albedo, albedo * atmospheric_tint, atmospheric_blend);
	// Toon posterize: snap to flat colour bands (cel read on flat ground too).
	albedo = floor(albedo * posterize_steps + 0.5) / posterize_steps;

	// Relief readability (land only): tilt the lit NORMAL toward its slope so the
	// directional light shades gentle hills as if they were steeper. NORMAL is
	// view-space, so go to world, exaggerate the horizontal components, come back.
	float relief_slope = 0.0;
	if (v_water < 0.5) {
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 wn_ex = normalize(vec3(wn.x * relief_gain, wn.y, wn.z * relief_gain));
		relief_slope = clamp(1.0 - wn_ex.y, 0.0, 1.0);
		NORMAL = normalize((VIEW_MATRIX * vec4(wn_ex, 0.0)).xyz);
	}

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

	// Slope cavity: a touch of slope-proportional ambient darkening so ridges/valleys
	// read even where they face away from the sun.
	albedo *= 1.0 - relief_slope * relief_cavity;

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

// Cel hillshade: a SOFT 2-band slope shade over the (relief-exaggerated) NORMAL set in
// fragment() — reads as cartographic hatching (§17.1.1) rather than smooth engine light.
// cel_hillshade=false → a smooth narrow Lambert wash (art §7.2). Ambient still fills the
// shadow band, so the dark side reads as drawn shading, not black.
void light() {
	float ndl = max(0.0, dot(NORMAL, LIGHT));
	float shade;
	if (cel_hillshade) {
		float t = smoothstep(shade_threshold - shade_softness, shade_threshold + shade_softness, ndl);
		shade = mix(shade_dark, shade_lit, t);
	} else {
		shade = mix(wash_min, wash_max, ndl);
	}
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * shade;
}
