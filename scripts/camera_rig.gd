class_name FollowCameraRig
extends Node3D

@export_node_path("Node3D") var target_path: NodePath
@export var offset := Vector3(0.0, 13.5, 10.5)
@export var focus_offset := Vector3(0.0, 0.75, 0.0)
@export var position_smoothing := 7.5

@onready var target: Node3D = get_node_or_null(target_path)


func get_planar_axes() -> Array[Vector3]:
	# 跟随有延迟，不能用相机当前朝向来转向，否则按住侧移会慢慢画弧。
	var flat := Vector3(offset.x, 0.0, offset.z)
	var forward := Vector3(0.0, 0.0, -1.0)
	if flat.length_squared() > 0.0001:
		forward = -flat.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	return [right, forward]


func _ready() -> void:
	if target:
		global_position = target.global_position + offset
		look_at(target.global_position + focus_offset, Vector3.UP)


func _process(delta: float) -> void:
	if not target:
		return
	var desired_position := target.global_position + offset
	var smoothing_weight := 1.0 - exp(-position_smoothing * delta)
	global_position = global_position.lerp(desired_position, smoothing_weight)
	look_at(target.global_position + focus_offset, Vector3.UP)
