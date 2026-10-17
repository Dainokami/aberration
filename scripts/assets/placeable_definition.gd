@tool
class_name PlaceableDefinition
extends Resource

enum Carrier { CARD, GROUND, PROJECTED_BOX, PROJECTED_WEDGE, MULTI_FACE, WALL }
enum Collision { NONE, BOX, CYLINDER }
enum Behaviour { DECORATION, ROCK, BREAKABLE, CHEST, CLIMBABLE }

@export var asset_id := ""
@export var display_name := ""
@export var category := "装饰"
@export var source_image := ""
@export var foreground_image := ""
@export var scene_path := ""
@export var thumbnail_path := ""
@export var carrier: Carrier = Carrier.CARD
@export var image_size := Vector2(4, 5)
## Normalized image coordinate; (0.5,1) means bottom center is ground contact.
@export var pivot := Vector2(0.5, 1.0)
@export var volume_size := Vector3(2, 3, 2)
@export var collision: Collision = Collision.NONE
@export var collision_size := Vector3(1, 2, 1)
@export var collision_offset := Vector3.ZERO
@export var fade_foreground := false
## Fade the complete object when it sits between the gameplay camera and player.
@export var fade_when_occluding := true
@export var profile: ArtProfile
@export var generator_version := 2
## MULTI_FACE uses rectified images. UV perspective is removed during preparation.
@export var face_images: Dictionary = {}
@export var state_images: Dictionary = {}
## Different poses may shift the painted contact even with a shared canvas.
@export var state_pivots: Dictionary = {}
@export var behaviour: Behaviour = Behaviour.DECORATION
@export var supports_objects := false
@export_range(1, 1000) var max_health := 3
@export var source_manifest := ""
## Recipes keep source quads/masks editable instead of baking away provenance.
@export var preparation: Dictionary = {}
## Explicit cells in metres: size and offset, independent of the painted canvas.
@export var spatial_cells: Array[Vector3] = []
@export var cell_size := Vector3(2, 2, 2)
@export var mechanism := ""
@export var ecosystems: PackedStringArray = []
@export var requires_seabed := false
@export var mechanism_parameters: Dictionary = {}

func validate_asset() -> PackedStringArray:
	var errors := PackedStringArray()
	if asset_id.is_empty() or not asset_id.is_valid_identifier():
		errors.append("资源 ID 必须是英文字母、数字、下划线，且不能以数字开头")
	if not ResourceLoader.exists(source_image):
		errors.append("源图片不存在：" + source_image)
	elif not load(source_image) is Texture2D:
		errors.append("主图片必须是 Texture2D")
	if not foreground_image.is_empty() and not ResourceLoader.exists(foreground_image):
		errors.append("前景图片不存在")
	elif not foreground_image.is_empty() and not load(foreground_image) is Texture2D:
		errors.append("前景图片必须是 Texture2D")
	if image_size.x <= 0 or image_size.y <= 0 or volume_size.x <= 0 or volume_size.y <= 0 or volume_size.z <= 0:
		errors.append("尺寸必须大于零")
	if collision_size.x <= 0 or collision_size.y <= 0 or collision_size.z <= 0:
		errors.append("碰撞尺寸必须大于零")
	if profile == null:
		errors.append("缺少固定相机配置")
	if carrier == Carrier.MULTI_FACE:
		for face in ["front", "back", "left", "right", "top"]:
			var path := str(face_images.get(face, ""))
			if not ResourceLoader.exists(path) or not load(path) is Texture2D:
				errors.append("缺少面片：" + face)
	for state in state_images:
		var path := str(state_images[state])
		if not ResourceLoader.exists(path) or not load(path) is Texture2D:
			errors.append("状态图缺失：" + str(state))
	for state in state_pivots:
		var value: Vector2 = state_pivots[state]
		if not value.is_finite() or value.x < 0 or value.x > 1 or value.y < 0 or value.y > 1:
			errors.append("状态接地点无效：" + str(state))
	if behaviour == Behaviour.CHEST and mechanism != "chest" and (not state_images.has("closed") or
			not state_images.has("open")):
		errors.append("宝箱需要关闭和开启两张状态图")
	if supports_objects and collision != Collision.BOX:
		errors.append("可承托物件必须使用盒体碰撞")
	if carrier == Carrier.WALL and collision != Collision.NONE:
		errors.append("贴墙物件共用宿主碰撞，请关闭独立阻挡")
	return errors

func behaviour_label() -> String:
	return ["装饰", "可登顶", "可破坏", "可交互", "可攀爬"][behaviour]

func footprint(scale_value: float, yaw: float) -> Vector2:
	var size := Vector2(collision_size.x, collision_size.z)
	if not spatial_cells.is_empty():
		var first := Vector2(INF, INF)
		var last := Vector2(-INF, -INF)
		for point in spatial_cells:
			var offset := Basis(Vector3.UP, yaw) * point
			var half := Vector2(absf(cos(yaw)) * cell_size.x + absf(sin(yaw)) * cell_size.z,
				absf(sin(yaw)) * cell_size.x + absf(cos(yaw)) * cell_size.z) * 0.5
			first = first.min(Vector2(offset.x, offset.z) - half)
			last = last.max(Vector2(offset.x, offset.z) + half)
		return (last - first) * scale_value
	if collision == Collision.CYLINDER:
		size = Vector2.ONE * maxf(collision_size.x, collision_size.z)
		return size * scale_value
	if collision == Collision.NONE:
		size = Vector2(0.15, 0.15)
	return Vector2(absf(cos(yaw)) * size.x + absf(sin(yaw)) * size.y,
		absf(sin(yaw)) * size.x + absf(cos(yaw)) * size.y) * scale_value
