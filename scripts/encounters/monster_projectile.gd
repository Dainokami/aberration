class_name MonsterProjectile
extends Node3D

var target: Node3D
var direction := Vector3.FORWARD
var damage := 14.0
var life := 3.0

func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#847a70")
	mesh.material_override = material
	add_child(mesh)

func _physics_process(delta: float) -> void:
	life -= delta
	var next := global_position + direction * 10 * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next, 1)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty() or life <= 0:
		queue_free()
		return
	if is_instance_valid(target) and _segment_distance(target.global_position, global_position, next) < 0.5:
		CombatHealth.hurt(target, damage, "monster")
		queue_free()
		return
	global_position = next

func _segment_distance(point: Vector3, start: Vector3, end: Vector3) -> float:
	var line := end - start
	var weight := clampf((point - start).dot(line) / maxf(0.00001, line.length_squared()), 0, 1)
	return point.distance_to(start + line * weight)
