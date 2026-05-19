// cel_figure.gdshader
// Figure cel shader per gdd-art-direction.md §6 (early-1990s American action animation register).
//
// Component stack:
//   1. Albedo sample with painted shading baked in
//   2. Three-step toon ramp on diffuse (hard transitions, no smoothstep)
//   3. Rim light pass (warm cream tint)
//   4. Hard-cutoff specular (threshold 0.92, "snap-on metal pop")
//   5. Inverted-hull outline pass — runs as a SEPARATE material on a sibling mesh; see cel_outline.gdshader
//   6. Painted-in interior linework — baked into albedo, no shader cost
//
// Body-specific features per gdd-character-creation-pipeline.md §8.3:
//   - hide_mask uniform (uint, bit 0..9): vertices in hidden regions collapse to origin
//   - Region ID encoded in vertex color channel R (values 0..9, or 255 for "always visible")
//   - skin_color / hair_color / eye_color uniforms: per-region tinting via vertex color channel G
//
// Performance: targets gdd-art-direction.md §6.7 (50+ figures @ 60fps on GTX 1060 / RTX 3050 Ti).
// The fragment shader is intentionally simple. Three-band ramp = 2 branches; rim + spec = a few muls.
// Skinning cost is the dominant per-vertex term at scale; the shader itself is cheap.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

// --- Albedo ---
// hint_default_white: when no texture is bound, the sampler returns (1,1,1,1) instead of black.
// This means albedo_tint alone controls the base color in the unbound case — no need to set
// a 1×1 white texture per material.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// --- Per-region runtime tinting (body shader only — armor/clothing shaders may omit) ---
// Region IDs encoded in vertex color channel G at bake time per gdd-character-creation-pipeline.md §3.4:
//   0 = skin, 1 = hair, 2 = eyes, 3 = lips/mouth, 4 = clothing-painted-in
uniform vec4 skin_color : source_color = vec4(0.85, 0.72, 0.6, 1.0);
uniform vec4 hair_color : source_color = vec4(0.35, 0.22, 0.12, 1.0);
uniform vec4 eye_color : source_color = vec4(0.25, 0.55, 0.75, 1.0);
uniform bool use_region_tinting = false;  // body sets true; armor/clothing sets false

// --- Hide regions (body shader only) ---
// Bit field: bit N set means region N is hidden by equipped armor.
// Region IDs in vertex color channel R per gdd-character-creation-pipeline.md §3.4:
//   0=head, 1=neck, 2=chest, 3=waist, 4=upper_arms, 5=forearms,
//   6=hands, 7=thighs, 8=calves, 9=feet, 255=always visible
// Declared `int` (not `uint`) because GDScript's set_shader_parameter has unreliable
// int→uint conversion in some Godot 4 versions. GLSL `int` supports bitwise ops identically.
uniform int hide_mask = 0;
uniform bool use_hide_mask = false;  // body sets true; armor/clothing sets false

// Diagnostic: forces hiding of a single region regardless of hide_mask. Set to -1 to disable,
// 0..9 to force-hide that region. Useful for verifying the vertex color → region encoding
// pipeline independently of the mask uniform.
uniform int debug_hide_region = -1;

// Diagnostic: when true, output the per-vertex region as a flat color (instead of cel shading).
// Region colors: 0=red(head), 1=orange(neck), 2=yellow(chest), 3=green(waist),
//   4=cyan(upper_arms), 5=blue(forearms), 6=magenta(hands), 7=dark red(thighs),
//   8=dark green(calves), 9=dark blue(feet), 255=white(always visible), other=black(error).
// If the body shows up entirely black or all-white, the vertex color attribute didn't survive
// glTF import or is being sRGB-converted.
uniform bool debug_visualize_regions = false;

// --- Three-step toon ramp (§6.2) ---
// dot(N,L) thresholds. Defaults match the GDD's placeholder values; tune in Phase 1.
uniform float shadow_threshold_1 : hint_range(-1.0, 1.0) = 0.5;
uniform float shadow_threshold_2 : hint_range(-1.0, 1.0) = 0.0;

// Per-band color shifts. The mid color is the lit color shifted toward shadow_color by ~50% in HSL.
// The shadow color is the lit color shifted toward navy (cool) and darkened (§5.2).
// These are MULTIPLIERS on the albedo, so 1.0 = lit, ~0.7 = mid, ~0.4 = shadow.
uniform vec3 lit_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 mid_tint : source_color = vec3(0.7, 0.65, 0.75);
uniform vec3 shadow_tint : source_color = vec3(0.35, 0.30, 0.55);

// --- Rim light (§6.3) ---
uniform vec3 rim_color : source_color = vec3(0.96, 0.92, 0.84);  // warm cream
uniform float rim_power : hint_range(0.0, 16.0) = 4.0;
uniform float rim_intensity : hint_range(0.0, 2.0) = 0.6;

// --- Hard-cutoff specular (§6.4) ---
// Per-light specular computed in light(); output snapped via threshold.
uniform vec3 spec_color : source_color = vec3(0.96, 0.92, 0.84);
uniform float spec_threshold : hint_range(0.5, 1.0) = 0.92;
uniform float spec_intensity : hint_range(0.0, 4.0) = 1.5;

// =============================================================
// VERTEX
// =============================================================
// Region ID encoded in UV2.x per gdd-character-creation-pipeline.md §3.4 (revised after the
// vertex-color path proved unreliable through Blender's gltf round-trip). Uses `flat varying`
// so the region is constant across each triangle — the fragment shader discards atomically,
// so we don't get long stretched triangles when only some verts of a triangle are hidden.
varying flat int v_region_id;
varying float v_outline_thickness;

void vertex() {
    v_region_id = int(UV2.x * 255.0 + 0.5);
    v_outline_thickness = UV2.y;
}

// =============================================================
// FRAGMENT
// =============================================================
varying vec3 v_world_normal;
varying vec3 v_view_dir;

void fragment() {
    // Hide-region check (per-triangle via flat varying — discards the whole triangle atomically,
    // avoiding the long-stretched-triangle artifact that vertex-collapse produces when only some
    // verts of a triangle are hidden).
    int region = v_region_id;
    if (debug_hide_region >= 0 && region == debug_hide_region) {
        discard;
    }
    if (use_hide_mask && region < 10 && (hide_mask & (1 << region)) != 0) {
        discard;
    }

    vec3 base_color;

    if (debug_visualize_regions) {
        // Diagnostic mode: visualize per-vertex region as flat color
        if (region == 0) base_color = vec3(1.0, 0.0, 0.0);
        else if (region == 1) base_color = vec3(1.0, 0.5, 0.0);
        else if (region == 2) base_color = vec3(1.0, 1.0, 0.0);
        else if (region == 3) base_color = vec3(0.0, 1.0, 0.0);
        else if (region == 4) base_color = vec3(0.0, 1.0, 1.0);
        else if (region == 5) base_color = vec3(0.0, 0.0, 1.0);
        else if (region == 6) base_color = vec3(1.0, 0.0, 1.0);
        else if (region == 7) base_color = vec3(0.5, 0.0, 0.0);
        else if (region == 8) base_color = vec3(0.0, 0.5, 0.0);
        else if (region == 9) base_color = vec3(0.0, 0.0, 0.5);
        else if (region == 255) base_color = vec3(1.0, 1.0, 1.0);
        else base_color = vec3(0.0, 0.0, 0.0);  // unexpected value
        ALBEDO = base_color;
        EMISSION = vec3(0.0);
    } else {
        // Sample albedo
        vec4 albedo_sample = texture(albedo_texture, UV);
        base_color = albedo_sample.rgb * albedo_tint.rgb;

        // Per-region tinting (body shader): swap base color for skin/hair/eye uniforms based on
        // region semantic encoded in COLOR.g (channel name retained for legacy; future revisions
        // may move this to UV3 or similar for consistency with the region-ID move to UV2).
        if (use_region_tinting) {
            float semantic = COLOR.g;
            if (semantic < 0.125) {
                base_color *= skin_color.rgb;
            } else if (semantic < 0.375) {
                base_color *= hair_color.rgb;
            } else if (semantic < 0.625) {
                base_color *= eye_color.rgb;
            }
        }
        ALBEDO = base_color;

        // Pass world-space normal to light() via varying (light() doesn't have UV but has NORMAL)
        v_world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
        v_view_dir = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;

        // Rim light is independent of light sources (treated as ambient global rim per §6.3)
        float rim_dot = 1.0 - max(0.0, dot(NORMAL, VIEW));
        float rim = pow(rim_dot, rim_power) * rim_intensity;
        EMISSION = rim_color * rim;
    }
}

// =============================================================
// LIGHT
// =============================================================
// Per-light contribution. Godot 4 calls this once per light affecting the fragment.
// We compute the three-step toon ramp and snap-on specular here, accumulating into
// DIFFUSE_LIGHT and SPECULAR_LIGHT respectively.
void light() {
    float n_dot_l = dot(NORMAL, LIGHT);

    // Three-band ramp (§6.2, hard transitions, no smoothstep)
    vec3 band_color;
    if (n_dot_l > shadow_threshold_1) {
        band_color = lit_tint;
    } else if (n_dot_l > shadow_threshold_2) {
        band_color = mid_tint;
    } else {
        band_color = shadow_tint;
    }

    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * band_color;

    // Hard-cutoff specular (§6.4): Blinn-Phong half-vector, snap threshold.
    // shininess 128 produces a tight pre-snap cone — only highly aligned half-vectors pass
    // the threshold, which is the "snap-on metal pop" the GDD describes. Lower values produce
    // a wider, washed-out highlight.
    vec3 half_vec = normalize(LIGHT + VIEW);
    float spec_term = max(0.0, dot(NORMAL, half_vec));
    spec_term = pow(spec_term, 128.0);
    if (spec_term > spec_threshold) {
        SPECULAR_LIGHT += spec_color * LIGHT_COLOR * ATTENUATION * spec_intensity;
    }
}
