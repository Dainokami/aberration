shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D source_texture : source_color, filter_linear;

void fragment() {
	vec4 pixel = texture(source_texture, UV);
	float least_channel = min(pixel.r, min(pixel.g, pixel.b));
	float ink_alpha = 1.0 - smoothstep(0.86, 0.995, least_channel);
	// JPEG edge pixels were blended against white. Remove that white matte as
	// their alpha fades, so neighboring body and limb layers meet cleanly.
	ALBEDO = clamp((pixel.rgb - vec3(1.0 - ink_alpha)) / max(ink_alpha, 0.001), vec3(0.0), vec3(1.0));
	ALPHA = pixel.a * ink_alpha;
}
