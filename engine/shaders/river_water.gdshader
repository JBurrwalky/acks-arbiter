shader_type spatial;
// Stylised flowing river water for the 3D wilderness renderer (gdd-wilderness-hex-3d.md).
// Two scrolling layers of a seamless water texture, blended, so the surface flows and the
// tiling is hidden. Translucent so the carved pebble bed reads through it. Double-sided
// (the ribbon is thin and viewed from above). The texture supplies the cel/painted look; the
// animation is purely shader-driven (UV scroll over TIME), so a still PNG is all that's needed.
//
// The hex GRID is also drawn here (same SDF + params as wilderness_splat.gdshader) so the grid
// reads as CONTINUOUS across terrain and river — the river then looks set INTO the ground
// rather than floating on top of it. UV is world XZ (set on the ribbon), so the lines align.

render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D water_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.65;            // world-XZ units -> UV tiling (lower = bigger waves)
uniform vec2 flow_dir = vec2(1.0, 0.2);    // global flow direction in world XZ
uniform float flow_speed = 0.025;          // downstream scroll speed
uniform float layer2_scale = 1.43;         // second layer tiling (break the repeat)
uniform float layer2_speed = 0.6;          // second layer relative speed (opposing)
uniform float water_alpha = 0.86;          // translucency (bed shows through)
uniform float emission_boost = 0.04;       // small lift for readability (was glowing too cyan)
uniform float tint = 0.88;                 // darken toward the texture's deeper blue

// Hex grid overlay (match wilderness_splat.gdshader). hex_radius is set by the renderer.
uniform bool show_grid = true;
uniform float hex_radius = 0.5773503;
uniform float grid_line = 0.022;           // line half-width in world units
uniform vec3 grid_color : source_color = vec3(0.04, 0.04, 0.05);
uniform float grid_strength = 0.75;        // a touch stronger than land so it reads over water

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

float sd_hex_flat(vec2 p, float r) {
	const vec3 k = vec3(-0.8660254, 0.5, 0.5773503);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

void fragment() {
	vec2 base = UV * tex_scale;
	vec2 f = normalize(flow_dir) * (TIME * flow_speed);
	vec3 a = texture(water_tex, base + f).rgb;
	vec3 b = texture(water_tex, base * layer2_scale - f * layer2_speed).rgb;
	vec3 col = mix(a, b, 0.5) * tint;
	if (show_grid) {
		vec2 center = axial_to_world(world_to_axial(UV));
		float d = abs(sd_hex_flat(UV - center, hex_radius * 0.8660254));
		float aa = fwidth(d) + 0.0015;
		float line = 1.0 - smoothstep(grid_line, grid_line + aa, d);
		col = mix(col, grid_color, line * grid_strength);
	}
	ALBEDO = col;
	ALPHA = water_alpha;
	EMISSION = col * emission_boost;
	ROUGHNESS = 0.15;
	METALLIC = 0.0;
}
