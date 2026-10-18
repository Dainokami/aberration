shader_type canvas_item;

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	float least_channel = min(pixel.r, min(pixel.g, pixel.b));
	float ink_alpha = 1.0 - smoothstep(0.955, 0.995, least_channel);
	vec3 clean_ink = clamp((pixel.rgb - vec3(1.0 - ink_alpha)) / max(ink_alpha, 0.001), vec3(0.0), vec3(1.0));
	COLOR = vec4(clean_ink, pixel.a * ink_alpha);
}
