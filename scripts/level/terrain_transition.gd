@tool
class_name TerrainTransition
extends RefCounted

const MASK_PATH := "res://assets/generated/terrain/default_edge_mask.png"
const MASK_SIZE := 128

static func ensure_default_mask() -> Texture2D:
	if not ResourceLoader.exists(MASK_PATH):
		_generate_default_mask()
	return load(MASK_PATH) as Texture2D

static func mask_for(tile: TileDefinition) -> Texture2D:
	if tile != null and not tile.transition_mask_path.is_empty() and ResourceLoader.exists(tile.transition_mask_path):
		return load(tile.transition_mask_path) as Texture2D
	return ensure_default_mask()

static func dominant(a: TileDefinition, b: TileDefinition) -> bool:
	if a == null:
		return false
	if b == null:
		return true
	if a.transition_priority != b.transition_priority:
		return a.transition_priority > b.transition_priority
	return a.tile_id > b.tile_id

static func edge_material(upper: TileDefinition, lower: TileDefinition) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D upper_art : source_color;
uniform sampler2D lower_art : source_color;
uniform sampler2D edge_mask : source_color;
uniform vec4 upper_color : source_color;
uniform vec4 lower_color : source_color;
uniform bool upper_has_art;
uniform bool lower_has_art;
void fragment() {
	vec4 up = upper_has_art ? texture(upper_art, UV) : upper_color;
	vec4 low = lower_has_art ? texture(lower_art, UV) : lower_color;
	up.rgb = mix(upper_color.rgb, up.rgb, up.a);
	low.rgb = mix(lower_color.rgb, low.rgb, low.a);
	float edge = texture(edge_mask, UV).r;
	ALBEDO = mix(low.rgb, up.rgb, edge);
	ALPHA = 1.0;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	var upper_texture := load(upper.texture_path) as Texture2D if ResourceLoader.exists(upper.texture_path) else null
	var lower_texture := load(lower.texture_path) as Texture2D if ResourceLoader.exists(lower.texture_path) else null
	material.set_shader_parameter("upper_art", upper_texture)
	material.set_shader_parameter("lower_art", lower_texture)
	material.set_shader_parameter("edge_mask", mask_for(upper))
	material.set_shader_parameter("upper_color", upper.base_color)
	material.set_shader_parameter("lower_color", lower.base_color)
	material.set_shader_parameter("upper_has_art", upper_texture != null)
	material.set_shader_parameter("lower_has_art", lower_texture != null)
	return material

static func _generate_default_mask() -> void:
	var image := Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBA8)
	for y in MASK_SIZE:
		for x in MASK_SIZE:
			var along := float(y) / (MASK_SIZE - 1)
			var edge := 0.54
			edge += sin(along * 17.0 + 0.3) * 0.055
			edge += sin(along * 41.0 + 1.1) * 0.025
			edge += sin(along * 91.0 + 2.6) * 0.012
			var value := smoothstep(edge - 0.055, edge + 0.055, float(x) / (MASK_SIZE - 1))
			image.set_pixel(x, y, Color(value, value, value, 1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MASK_PATH.get_base_dir()))
	image.save_png(MASK_PATH)
