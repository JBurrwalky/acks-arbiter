shader_type canvas_item;

// Multiplies the CanvasGroup's rendered alpha by the mask texture's alpha.
// The shield mask PNGs are solid white on transparent background, so sampling
// the mask's alpha channel gives 1.0 inside the shield silhouette and 0.0
// outside — exactly the clip we want.

uniform sampler2D mask_texture : filter_linear, repeat_disable;

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float m = texture(mask_texture, UV).a;
	COLOR = vec4(src.rgb, src.a * m);
}
