@tool
class_name TerrainArtSet
extends Resource

## Source art and metre scales for one continuous terrain material.
## Corner geometry follows the existing terrain topology; the rim strip bends
## around it, so a perspective drawing is never stretched onto a top-face tile.
@export var set_id := ""
@export var display_name := ""
@export var top_path := ""
@export var top_span := Vector2(8, 8)
@export var cliff_path := ""
## X repeats along the wall; Y is one 2m layer, so each layer shows the art once.
@export var cliff_span := Vector2(4, 2)
@export var rim_paths: PackedStringArray = []
@export var rim_span := 4.0
## Painted fringe above / below the top edge, in metres.
@export var rim_rise := 0.1
@export var rim_drop := 0.15
@export var corner_radius := 0.25
@export var slope_side_path := ""
@export var source_manifest := ""
@export var version := 1

func validate_asset() -> PackedStringArray:
	var errors := PackedStringArray()
	if not set_id.is_valid_identifier():
		errors.append("地形套件 ID 无效")
	for path in [top_path, cliff_path, slope_side_path] + Array(rim_paths):
		if path == "" and path != top_path:
			continue
		if not ResourceLoader.exists(path) or not load(path) is Texture2D:
			errors.append("地形图片缺失：" + str(path))
	if top_span.x <= 0 or top_span.y <= 0 or cliff_span.x <= 0 or cliff_span.y <= 0:
		errors.append("纹理世界尺寸必须大于零")
	if rim_span <= 0 or rim_rise < 0 or rim_drop < 0:
		errors.append("边缘尺寸无效")
	return errors

func apply_to(tile: Resource) -> void:
	tile.texture_path = top_path
	tile.world_space_top = true
	tile.top_texture_span_m = top_span
	tile.cliff_texture_path = cliff_path
	tile.cliff_texture_span_m = cliff_span
	tile.cliff_course_repeat = true
	tile.rim_texture_path = rim_paths[0] if not rim_paths.is_empty() else ""
	tile.rim_u_span_m = rim_span
	tile.rim_drop_m = rim_drop if not rim_paths.is_empty() else 0.0
	tile.rim_cutout = not rim_paths.is_empty()
	tile.rim_alpha_range = Vector2(0, 1)
	# A flat strip 1.2cm in front of the wall: tufts above the edge, band below it.
	var profile: Array[Vector2] = []
	if not rim_paths.is_empty():
		profile = [Vector2(0.012, rim_rise), Vector2(0.012, -rim_drop)]
	tile.grass_roll_profile = profile
	tile.corner_radius_m = corner_radius
