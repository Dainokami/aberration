@tool
class_name TerrainMaterials
extends RefCounted

static var _top_shader: Shader
static var _blended_top_shader: Shader
static var _cliff_shader: Shader
static var _rim_shader: Shader
static var _foam_shader: Shader

static func top_material(tile: TileDefinition, lower: TileDefinition,
		transition_mask: Texture2D, transition_turns: int,
		shape_mask: Texture2D, tint: Color, lower_tint: Color,
		rotation_turns: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _get_top_shader()
	var upper_texture := _texture(tile.texture_path)
	var lower_texture := _texture(lower.texture_path) if lower != null else null
	material.set_shader_parameter("upper_art", upper_texture)
	material.set_shader_parameter("lower_art", lower_texture)
	material.set_shader_parameter("edge_mask", transition_mask)
	material.set_shader_parameter("shape_mask", shape_mask)
	material.set_shader_parameter("upper_color", tile.base_color)
	material.set_shader_parameter("lower_color", lower.base_color if lower != null else tile.base_color)
	material.set_shader_parameter("upper_tint", tint)
	material.set_shader_parameter("lower_tint", lower_tint)
	material.set_shader_parameter("upper_span", tile.top_texture_span_m)
	material.set_shader_parameter("lower_span",
		lower.top_texture_span_m if lower != null else tile.top_texture_span_m)
	material.set_shader_parameter("upper_has_art", upper_texture != null)
	material.set_shader_parameter("lower_has_art", lower_texture != null)
	material.set_shader_parameter("upper_world_space", tile.world_space_top)
	material.set_shader_parameter("lower_world_space",
		lower.world_space_top if lower != null else tile.world_space_top)
	material.set_shader_parameter("use_transition", lower != null and transition_mask != null)
	material.set_shader_parameter("mask_turns", posmod(transition_turns, 4))
	material.set_shader_parameter("art_turns", posmod(rotation_turns, 4))
	return material

static func blended_top_material(blend: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _get_blended_top_shader()
	material.set_shader_parameter("blend_indices", blend["index_texture"])
	material.set_shader_parameter("blend_weights", blend["weight_texture"])
	material.set_shader_parameter("blend_rotations", blend["rotation_texture"])
	material.set_shader_parameter("blend_origin", blend["origin"])
	material.set_shader_parameter("blend_size", blend["world_size"])
	material.set_shader_parameter("terrain_art", blend["terrain_art"])
	material.set_shader_parameter("terrain_colors", blend["terrain_colors"])
	material.set_shader_parameter("terrain_tints", blend["terrain_tints"])
	material.set_shader_parameter("terrain_settings", blend["terrain_settings"])
	return material

static func cliff_material(tile: TileDefinition, tint: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _get_cliff_shader()
	var texture := _texture(tile.cliff_texture_path)
	material.set_shader_parameter("cliff_art", texture)
	material.set_shader_parameter("base_color", tile.base_color.darkened(0.18))
	material.set_shader_parameter("terrain_tint", tint)
	material.set_shader_parameter("has_art", texture != null)
	return material

static func rim_material(tile: TileDefinition, tint: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _get_rim_shader()
	var rim := _texture(tile.rim_texture_path)
	var top := _texture(tile.texture_path)
	var cliff := _texture(tile.cliff_texture_path)
	material.set_shader_parameter("rim_art", rim)
	material.set_shader_parameter("top_art", top)
	material.set_shader_parameter("cliff_art", cliff)
	material.set_shader_parameter("base_color", tile.base_color)
	material.set_shader_parameter("terrain_tint", tint)
	material.set_shader_parameter("top_span", tile.top_texture_span_m)
	material.set_shader_parameter("cliff_span", tile.cliff_texture_span_m)
	material.set_shader_parameter("rim_span", tile.rim_u_span_m)
	material.set_shader_parameter("has_rim", rim != null)
	material.set_shader_parameter("has_top", top != null)
	material.set_shader_parameter("has_cliff", cliff != null)
	return material

static func foam_material(water: TileDefinition) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _get_foam_shader()
	var foam := _texture(water.foam_texture_path)
	material.set_shader_parameter("foam_art", foam)
	material.set_shader_parameter("has_art", foam != null)
	return material

static func _texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

static func _get_top_shader() -> Shader:
	if _top_shader != null:
		return _top_shader
	_top_shader = Shader.new()
	_top_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D upper_art : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D lower_art : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D edge_mask : filter_linear, repeat_disable;
uniform sampler2D shape_mask : filter_linear, repeat_disable;
uniform vec4 upper_color : source_color;
uniform vec4 lower_color : source_color;
uniform vec4 upper_tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 lower_tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec2 upper_span = vec2(2.0);
uniform vec2 lower_span = vec2(2.0);
uniform bool upper_has_art = false;
uniform bool lower_has_art = false;
uniform bool upper_world_space = false;
uniform bool lower_world_space = false;
uniform bool use_transition = false;
uniform int mask_turns = 0;
uniform int art_turns = 0;
varying vec3 world_pos;

vec2 mirror_uv(vec2 value) {
	return vec2(1.0) - abs(mod(value, vec2(2.0)) - vec2(1.0));
}

vec2 turn_uv(vec2 value, int turns) {
	if (turns == 1) { return vec2(value.y, 1.0 - value.x); }
	if (turns == 2) { return vec2(1.0) - value; }
	if (turns == 3) { return vec2(1.0 - value.y, value.x); }
	return value;
}

vec3 tint_preserve_value(vec3 color, vec4 tint) {
	float tint_luma = max(dot(tint.rgb, vec3(0.299, 0.587, 0.114)), 0.05);
	vec3 shifted = clamp(color * tint.rgb / tint_luma, vec3(0.0), vec3(1.0));
	return mix(color, shifted, clamp(tint.a, 0.0, 1.0));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 local_uv = turn_uv(UV, art_turns);
	vec2 upper_uv = upper_world_space ? mirror_uv(world_pos.xz / max(upper_span, vec2(0.001))) : local_uv;
	vec2 lower_uv = lower_world_space ? mirror_uv(world_pos.xz / max(lower_span, vec2(0.001))) : local_uv;
	vec4 upper_pixel = upper_has_art ? texture(upper_art, upper_uv) : upper_color;
	vec4 lower_pixel = lower_has_art ? texture(lower_art, lower_uv) : lower_color;
	vec3 upper_rgb = mix(upper_color.rgb, upper_pixel.rgb, upper_pixel.a);
	vec3 lower_rgb = mix(lower_color.rgb, lower_pixel.rgb, lower_pixel.a);
	upper_rgb = tint_preserve_value(upper_rgb, upper_tint);
	lower_rgb = tint_preserve_value(lower_rgb, lower_tint);
	float blend_value = use_transition ? texture(edge_mask, turn_uv(UV, mask_turns)).r : 1.0;
	ALBEDO = mix(lower_rgb, upper_rgb, blend_value);
	ROUGHNESS = 1.0;
}
"""
	return _top_shader

static func _get_blended_top_shader() -> Shader:
	if _blended_top_shader != null:
		return _blended_top_shader
	_blended_top_shader = Shader.new()
	_blended_top_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D blend_indices : filter_nearest, repeat_disable;
uniform sampler2D blend_weights : filter_nearest, repeat_disable;
uniform sampler2D blend_rotations : filter_nearest, repeat_disable;
uniform vec2 blend_origin;
uniform vec2 blend_size = vec2(1.0);
uniform sampler2DArray terrain_art : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D terrain_colors : source_color, filter_nearest, repeat_disable;
uniform sampler2D terrain_tints : source_color, filter_nearest, repeat_disable;
uniform sampler2D terrain_settings : filter_nearest, repeat_disable;
varying vec3 world_pos;

vec2 mirror_uv(vec2 value) {
	return vec2(1.0) - abs(mod(value, vec2(2.0)) - vec2(1.0));
}

vec2 turn_uv(vec2 value, int turns) {
	if (turns == 1) { return vec2(value.y, 1.0 - value.x); }
	if (turns == 2) { return vec2(1.0) - value; }
	if (turns == 3) { return vec2(1.0 - value.y, value.x); }
	return value;
}

vec3 tint_preserve_value(vec3 color, vec4 tint) {
	float tint_luma = max(dot(tint.rgb, vec3(0.299, 0.587, 0.114)), 0.05);
	vec3 shifted = clamp(color * tint.rgb / tint_luma, vec3(0.0), vec3(1.0));
	return mix(color, shifted, clamp(tint.a, 0.0, 1.0));
}

vec3 terrain_color(int page, vec2 local_uv) {
	vec4 base = texelFetch(terrain_colors, ivec2(page, 0), 0);
	vec4 tint = texelFetch(terrain_tints, ivec2(page, 0), 0);
	vec4 settings = texelFetch(terrain_settings, ivec2(page, 0), 0);
	vec2 span = max(settings.xy, vec2(0.001));
	vec2 art_uv = settings.z > 0.5 ? mirror_uv(world_pos.xz / span) : local_uv;
	vec4 pixel = texture(terrain_art, vec3(art_uv, float(page)));
	return tint_preserve_value(mix(base.rgb, pixel.rgb, pixel.a), tint);
}

vec3 splat_texel(ivec2 coordinate, vec2 local_uv) {
	ivec4 pages = ivec4(round(
		texelFetch(blend_indices, coordinate, 0) * 255.0));
	vec4 weights = max(texelFetch(blend_weights, coordinate, 0), vec4(0.0));
	weights /= max(dot(weights, vec4(1.0)), 0.0001);
	return terrain_color(pages.x, local_uv) * weights.r
		+ terrain_color(pages.y, local_uv) * weights.g
		+ terrain_color(pages.z, local_uv) * weights.b
		+ terrain_color(pages.w, local_uv) * weights.a;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 blend_uv = clamp((world_pos.xz - blend_origin) / max(blend_size, vec2(0.001)), vec2(0.0), vec2(1.0));
	int turns = int(round(texture(blend_rotations, blend_uv).r * 3.0));
	vec2 local_uv = turn_uv(UV, turns);
	ivec2 map_size = textureSize(blend_weights, 0);
	vec2 pixel = clamp(
		blend_uv * vec2(map_size) - vec2(0.5),
		vec2(0.0), vec2(map_size - ivec2(1)));
	ivec2 first = ivec2(floor(pixel));
	ivec2 second = min(first + ivec2(1), map_size - ivec2(1));
	vec2 blend = fract(pixel);
	vec3 top = mix(
		splat_texel(ivec2(first.x, first.y), local_uv),
		splat_texel(ivec2(second.x, first.y), local_uv),
		blend.x);
	vec3 bottom = mix(
		splat_texel(ivec2(first.x, second.y), local_uv),
		splat_texel(ivec2(second.x, second.y), local_uv),
		blend.x);
	ALBEDO = mix(top, bottom, blend.y);
	ROUGHNESS = 1.0;
}
"""
	return _blended_top_shader

static func _get_cliff_shader() -> Shader:
	if _cliff_shader != null:
		return _cliff_shader
	_cliff_shader = Shader.new()
	_cliff_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D cliff_art : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 base_color : source_color;
uniform vec4 terrain_tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform bool has_art = false;
vec2 mirror_uv(vec2 value) {
	return vec2(1.0) - abs(mod(value, vec2(2.0)) - vec2(1.0));
}
vec3 tint_preserve_value(vec3 color, vec4 tint) {
	float tint_luma = max(dot(tint.rgb, vec3(0.299, 0.587, 0.114)), 0.05);
	return mix(color, clamp(color * tint.rgb / tint_luma, vec3(0.0), vec3(1.0)), tint.a);
}
void fragment() {
	vec4 pixel = has_art ? texture(cliff_art, mirror_uv(UV)) : base_color;
	vec3 color = mix(base_color.rgb, pixel.rgb, pixel.a);
	ALBEDO = tint_preserve_value(color, terrain_tint);
	ROUGHNESS = 1.0;
}
"""
	return _cliff_shader

static func _get_rim_shader() -> Shader:
	if _rim_shader != null:
		return _rim_shader
	_rim_shader = Shader.new()
	_rim_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D rim_art : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D top_art : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D cliff_art : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 base_color : source_color;
uniform vec4 terrain_tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec2 top_span = vec2(8.0);
uniform vec2 cliff_span = vec2(4.0);
uniform float rim_span = 8.0;
uniform bool has_rim = false;
uniform bool has_top = false;
uniform bool has_cliff = false;
varying vec3 world_pos;
vec2 mirror_uv(vec2 value) {
	return vec2(1.0) - abs(mod(value, vec2(2.0)) - vec2(1.0));
}
vec3 tint_preserve_value(vec3 color, vec4 tint) {
	float tint_luma = max(dot(tint.rgb, vec3(0.299, 0.587, 0.114)), 0.05);
	return mix(color, clamp(color * tint.rgb / tint_luma, vec3(0.0), vec3(1.0)), tint.a);
}
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec4 top_pixel = has_top ? texture(top_art, mirror_uv(world_pos.xz / max(top_span, vec2(0.001)))) : base_color;
	vec4 cliff_pixel = has_cliff ? texture(cliff_art, mirror_uv(vec2(
		UV.x * rim_span / max(cliff_span.x, 0.001),
		-world_pos.y / max(cliff_span.y, 0.001)))) : base_color;
	vec3 top_color = mix(base_color.rgb, top_pixel.rgb, top_pixel.a);
	vec3 cliff_color = mix(base_color.rgb * 0.82, cliff_pixel.rgb, cliff_pixel.a);
	vec3 under = mix(top_color, cliff_color, smoothstep(0.18, 0.92, UV2.x));
	vec4 rim = has_rim ? texture(rim_art, vec2(1.0 - abs(mod(UV.x, 2.0) - 1.0), UV.y)) : vec4(under, 0.0);
	ALBEDO = tint_preserve_value(mix(under, rim.rgb, rim.a), terrain_tint);
	ROUGHNESS = 1.0;
}
"""
	return _rim_shader

static func _get_foam_shader() -> Shader:
	if _foam_shader != null:
		return _foam_shader
	_foam_shader = Shader.new()
	_foam_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;
uniform sampler2D foam_art : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_art = false;
void fragment() {
	vec4 foam = has_art ? texture(foam_art, vec2(1.0 - abs(mod(UV.x, 2.0) - 1.0), UV.y)) : vec4(1.0);
	ALBEDO = foam.rgb;
	ALPHA = foam.a;
	ROUGHNESS = 1.0;
}
"""
	return _foam_shader
