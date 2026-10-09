@tool
class_name PlaceableDefinition
extends Resource

enum Carrier { CARD, GROUND, PROJECTED_BOX, PROJECTED_WEDGE }
enum Collision { NONE, BOX, CYLINDER }

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
@export var profile: ArtProfile
@export var generator_version := 2

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
	return errors

func footprint(scale_value: float, yaw: float) -> Vector2:
	var size := Vector2(collision_size.x, collision_size.z)
	if collision == Collision.CYLINDER:
		size = Vector2.ONE * maxf(collision_size.x, collision_size.z)
		return size * scale_value
	if collision == Collision.NONE:
		size = Vector2(0.15, 0.15)
	return Vector2(absf(cos(yaw)) * size.x + absf(sin(yaw)) * size.y,
		absf(sin(yaw)) * size.x + absf(cos(yaw)) * size.y) * scale_value
