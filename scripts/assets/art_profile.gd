@tool
class_name ArtProfile
extends Resource

## Camera orientation is part of the art contract, not inferred from PNG pixels.
@export var camera_offset := Vector3(19, 22, 25)
@export var orthographic_size := 25.0
@export var version := 1
@export var perspective := true
@export_range(15, 90) var field_of_view := 35.0
@export_range(5, 65, 0.1) var pitch_degrees := 22.0
@export_range(8, 120, 0.1) var camera_distance := 36.8
@export_range(-10, 20, 0.1) var target_height := 0.0

func configure(camera: Camera3D, center := Vector3.ZERO, framing_height := -1.0) -> void:
	center.y += target_height
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE if perspective else Camera3D.PROJECTION_ORTHOGONAL
	camera.fov = field_of_view
	camera.size = orthographic_size if framing_height < 0 else framing_height
	var distance := camera_distance
	if framing_height > 0 and perspective:
		distance = framing_height / (2.0 * tan(deg_to_rad(field_of_view) * 0.5))
	camera.global_transform = Transform3D(camera_basis(), center + camera_direction() * distance)

func project_art(point: Vector3, size: Vector2, pivot: Vector2) -> Vector2:
	var screen := camera_basis().inverse() * point
	if perspective:
		screen *= camera_distance / maxf(0.1, camera_distance - screen.z)
	return Vector2(screen.x / size.x + pivot.x, pivot.y - screen.y / size.y)

func camera_direction() -> Vector3:
	var radians := deg_to_rad(pitch_degrees)
	return Vector3(0, sin(radians), cos(radians)).normalized()

func camera_basis() -> Basis:
	return Basis.looking_at(-camera_direction(), Vector3.UP)
