// cel_environment.gdshader
// Environment flat-painted shader per gdd-art-direction.md §7.
//
// Applied to walls, floors, ceilings, vegetation, and non-interactable props.
// Significantly cheaper than the figure shader: no toon ramp, no rim light, no specular,
// no outline (or thin outline for mid-ground props — handled by a separate material variant).
//
// Component stack (§7.1):
//   1. Albedo sample with heavily painted shading (form definition baked in)
//   2. Subtle ambient occlusion in albedo (baked at authoring time, not runtime)
//   3. Optional very subtle distance fog (a global shader parameter, not in this material)
//   4. Atmospheric color wash (§7.5): a small multiplier toward the scene mood color
//
// The lighting contribution is either FLAT (single-color multiplier) or a smooth Lambertian wash
// clamped to a narrow range. The actual shadows on the surface come from the painted texture,
// not from real-time lighting — this is the matte-painting treatment that lets KayKit/Quaternius
// environment packs coexist with the figure shader without visual conflict.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_disabled;

// --- Albedo ---
// hint_default_white: unbound samplers return (1,1,1,1) so albedo_tint alone controls the
// base color in the no-texture case.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 uv_tile = vec2(1.0, 1.0);

// --- Lambertian wash range (§7.2) ---
// 0.0 = full flat shading (no engine lighting contribution at all)
// 0.7-1.0 = narrow Lambertian range (subtle directional shading on top of painted detail)
uniform float wash_min : hint_range(0.0, 1.0) = 0.7;
uniform float wash_max : hint_range(0.0, 1.0) = 1.0;

// --- Atmospheric color wash (§7.5) ---
// Multiplied against environment albedos. Warm orange for torch-lit dungeons,
// cool sky-blue for daylight exteriors, purple for twilight wilderness, etc.
// Magnitude is small (5-15% blend) — see blend_strength.
uniform vec3 atmospheric_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float atmospheric_blend : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec4 sample = texture(albedo_texture, UV * uv_tile);
    vec3 base_color = sample.rgb * albedo_tint.rgb;

    // Atmospheric wash
    base_color = mix(base_color, base_color * atmospheric_tint, atmospheric_blend);

    ALBEDO = base_color;
}

void light() {
    // Narrow-range Lambertian wash: clamp the lighting contribution to [wash_min, wash_max].
    // This compresses the engine's directional lighting into a subtle modulation rather than
    // a full shading pass, so the painted shading in the albedo dominates.
    float n_dot_l = max(0.0, dot(NORMAL, LIGHT));
    float wash = mix(wash_min, wash_max, n_dot_l);
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * wash;
}
