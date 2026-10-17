@tool
class_name TileDefinition
extends Resource

enum SurfaceKind { LAND, WATER }
enum TerrainRole { SOLID, LIQUID, OVERLAY }

## Unique identifier. Built-in tiles use short names like "grass", "rock".
## Custom tiles use generated IDs from import.
@export var tile_id := ""
## Display name shown in the palette.
@export var display_name := ""
## Optional continuous art kit; legacy individual texture fields remain supported.
@export var art_set: TerrainArtSet
## Path to the albedo texture for the top face. Empty means use base_color shader.
@export var texture_path := ""
## Path to a 64x64 thumbnail for the palette list. Empty means auto-generate.
@export var thumbnail_path := ""
## Base color used for side walls and as fallback when no texture.
@export var base_color := Color(0.45, 0.53, 0.34)
## Default bottom-layer index; each solid occupies exactly 2m.
@export var default_height := 0
## Whether this is a built-in tile (not saved to disk).
@export var is_builtin := false
## Higher terrain visually grows over lower terrain on same-height boundaries.
@export_range(-100, 100) var transition_priority := 0
## Optional grayscale image. White is the terrain side of an irregular edge.
## Empty uses the project's generated default transition mask.
@export var transition_mask_path := ""
## Continuous terrain art settings. Legacy/imported tiles keep 2m local UVs.
@export var world_space_top := false
@export var top_texture_span_m := Vector2(2.0, 2.0)
@export var cliff_texture_path := ""
@export var cliff_texture_span_m := Vector2(4.0, 4.0)
@export var rim_texture_path := ""
@export var rim_u_span_m := 8.0
@export var rim_alpha_range := Vector2(0.0, 1.0)
@export var rim_inset_m := 0.0
@export var rim_outset_m := 0.0
@export var rim_drop_m := 0.0
@export var corner_radius_m := 0.0
@export var grass_roll_profile: Array[Vector2] = []
## Painted edge module: an alpha-tested fringe overlaid on the wall, instead of
## the legacy opaque rim that blends top and cliff colours underneath.
@export var rim_cutout := false
## Each 2m layer shows the cliff art once, top of the art at the top of the layer.
## Legacy tiles mirror the art every texture span instead.
@export var cliff_course_repeat := false
@export var surface_kind: SurfaceKind = SurfaceKind.LAND
## Storage/rendering role in stacked terrain columns.
@export var terrain_role: TerrainRole = TerrainRole.SOLID
@export var foam_texture_path := ""
@export var foam_u_span_m := 8.0
@export var foam_width_m := 0.35
@export var foam_alpha_range := Vector2(0.0, 1.0)

func resolve_art() -> void:
	if art_set != null:
		art_set.apply_to(self)

func is_water() -> bool:
	return terrain_role == TerrainRole.LIQUID \
		or surface_kind == SurfaceKind.WATER

func is_solid() -> bool:
	return terrain_role == TerrainRole.SOLID and not is_water()

func is_overlay() -> bool:
	return terrain_role == TerrainRole.OVERLAY

func is_block() -> bool:
	return is_solid() or is_water()

func has_soft_rim() -> bool:
	return not rim_texture_path.is_empty() and rim_drop_m > 0.0

func tint_default() -> Color:
	return Color(1.0, 1.0, 1.0, 0.0)

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
