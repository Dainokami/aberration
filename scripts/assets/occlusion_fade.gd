extends Node3D

var fade_materials: Array[StandardMaterial3D] = []
var visual_meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.material_override is StandardMaterial3D:
			var material := (mesh.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh.material_override = material
			visual_meshes.append(mesh)
			fade_materials.append(material)

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("level_player") as Node3D
	if camera == null or player == null:
		return
	var camera_to_player := player.global_position - camera.global_position
	var player_distance := camera_to_player.length()
	var direction := camera_to_player / maxf(player_distance, 0.001)
	var blocked := false
	for mesh in visual_meshes:
		var local_origin := mesh.global_transform.affine_inverse() * camera.global_position
		var local_direction := mesh.global_basis.inverse() * direction
		var hit: Variant = mesh.get_aabb().grow(0.15).intersects_ray(local_origin, local_direction)
		if hit == null:
			continue
		var world_hit: Vector3 = mesh.global_transform * (hit as Vector3)
		if camera.global_position.distance_to(world_hit) < player_distance - 0.1:
			blocked = true
			break
	var target := 0.24 if blocked else 1.0
	for material in fade_materials:
		material.albedo_color.a = move_toward(material.albedo_color.a, target, delta * 5.0)
