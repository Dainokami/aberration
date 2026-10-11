@tool
class_name TileDefinition
extends Resource

## Unique identifier. Built-in tiles use short names like "grass", "rock".
## Custom tiles use generated IDs from import.
@export var tile_id := ""
## Display name shown in the palette.
@export var display_name := ""
## Path to the albedo texture for the top face. Empty means use base_color shader.
@export var texture_path := ""
## Path to a 64x64 thumbnail for the palette list. Empty means auto-generate.
@export var thumbnail_path := ""
## Base color used for side walls and as fallback when no texture.
@export var base_color := Color(0.45, 0.53, 0.34)
## Default elevation index (0, 1, or 2) when painting with this tile.
@export var default_height := 0
## Whether this is a built-in tile (not saved to disk).
@export var is_builtin := false
## Higher terrain visually grows over lower terrain on same-height boundaries.
@export_range(-100, 100) var transition_priority := 0
## Optional grayscale image. White is the terrain side of an irregular edge.
## Empty uses the project's generated default transition mask.
@export var transition_mask_path := ""

func top_material() -> Material:
	var texture := load(texture_path) as Texture2D if ResourceLoader.exists(texture_path) else null
	if texture != null and texture.get_image().detect_alpha() != Image.ALPHA_NONE:
		var shader := Shader.new()
		shader.code = """
shader_type spatial;
render_mode unshaded;
uniform sampler2D art : source_color;
uniform vec4 base : source_color;
void fragment() {
	vec4 pixel = texture(art, UV);
	ALBEDO = mix(base.rgb, pixel.rgb, pixel.a);
	ROUGHNESS = 1.0;
}
"""
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("art", texture)
		material.set_shader_parameter("base", base_color)
		return material
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE if texture != null else base_color
	material.roughness = 1.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func wall_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = base_color
	material.roughness = 1.0
	return material
