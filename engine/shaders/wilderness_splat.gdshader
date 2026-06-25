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
uniform float grid_line = 0.05;           // line half-width (axial-cube units, 0..0.5)
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

// world XZ -> fractional cube coords (matches WildernessHexMath.world_to_axial)
vec3 world_to_cube(vec2 xz) {
	float q = (2.0 / 3.0 * xz.x) / hex_radius;
	float r = (-1.0 / 3.0 * xz.x + (1.7320508 / 3.0) * xz.y) / hex_radius;
	return vec3(q, -q - r, r);
}

void fragment() {
	vec2 uv = v_world.xz / tex_scale;
	vec3 terrain = sample_terrain(uv);
	vec3 albedo = mix(terrain, water_color, clamp(v_water, 0.0, 1.0));

	if (show_grid) {
		vec3 cube = world_to_cube(v_world.xz);
		vec3 diff = abs(cube - round(cube));         // 0 at hex center .. ~0.5 at edge
		float border = max(diff.x, max(diff.y, diff.z));
		float aa = fwidth(border) * 1.5 + 0.0015;
		float line = smoothstep(0.5 - grid_line - aa, 0.5 - grid_line + aa, border);
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
