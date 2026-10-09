extends MeshInstance3D

## Only an explicitly supplied foreground layer fades; never invent layer separation.
var fade_material: StandardMaterial3D

func _ready() -> void:
	fade_material = material_override.duplicate() as StandardMaterial3D
	fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = fade_material

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("level_player") as Node3D
	if camera == null or player == null:
		return
	var ray := (player.global_position - camera.global_position).normalized()
	var local_origin := global_transform.affine_inverse() * camera.global_position
	var local_direction := global_basis.inverse() * ray
	var blocked: bool = get_aabb().grow(0.3).intersects_ray(local_origin, local_direction) != null
	blocked = blocked and camera.global_position.distance_to(player.global_position) > camera.global_position.distance_to(global_position)
	fade_material.albedo_color.a = move_toward(fade_material.albedo_color.a, 0.22 if blocked else 1.0, delta * 4)
