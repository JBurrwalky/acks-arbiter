shader_type spatial;
// Stylised flowing river water for the 3D wilderness renderer (gdd-wilderness-hex-3d.md).
// Two scrolling layers of a seamless water texture, blended, so the surface flows and the
// tiling is hidden. Translucent so the carved pebble bed reads through it. Double-sided
// (the ribbon is thin and viewed from above). The texture supplies the cel/painted look; the
// animation is purely shader-driven (UV scroll over TIME), so a still PNG is all that's needed.

render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D water_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.45;            // world-XZ units -> UV tiling (lower = bigger waves)
uniform vec2 flow_dir = vec2(1.0, 0.2);    // global flow direction in world XZ
uniform float flow_speed = 0.025;          // downstream scroll speed
uniform float layer2_scale = 1.43;         // second layer tiling (break the repeat)
uniform float layer2_speed = 0.6;          // second layer relative speed (opposing)
uniform float water_alpha = 0.86;          // translucency (bed shows through)
uniform float emission_boost = 0.10;       // keep readable against shadowed terrain

void fragment() {
	vec2 base = UV * tex_scale;
	vec2 f = normalize(flow_dir) * (TIME * flow_speed);
	vec3 a = texture(water_tex, base + f).rgb;
	vec3 b = texture(water_tex, base * layer2_scale - f * layer2_speed).rgb;
	vec3 col = mix(a, b, 0.5);
	ALBEDO = col;
	ALPHA = water_alpha;
	EMISSION = col * emission_boost;
	ROUGHNESS = 0.15;
	METALLIC = 0.0;
}
