class_name BossGate
extends Node3D

signal entered
var target_scene := ""

func _ready() -> void:
	add_to_group("boss_gate")
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#5f5089")
	material.emission_enabled = true
	material.emission = Color("#9d74d9")
	material.emission_energy_multiplier = 0.7
	for at in [Vector3(-0.65, 1.5, 0), Vector3(0.65, 1.5, 0), Vector3(0, 3, 0)]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 3, 0.3) if at.x != 0 else Vector3(1.6, 0.3, 0.3)
		mesh.mesh = box
		mesh.material_override = material
		mesh.position = at
		add_child(mesh)
	var label := Label3D.new()
	label.text = "BOSS"
	label.position.y = 3.5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.012
	add_child(label)

func interact(player: Node3D) -> String:
	if player.global_position.distance_to(global_position + Vector3.UP * 0.8) > 2.5:
		return ""
	var query := PhysicsRayQueryParameters3D.create(player.global_position,
		global_position + Vector3.UP, 1)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return "Boss 门被障碍遮挡"
	if target_scene.is_empty():
		return "未配置 Boss 目标场景"
	if not ResourceLoader.exists(target_scene):
		return "Boss 目标场景缺失"
	var error := get_tree().change_scene_to_file(target_scene)
	if error != OK:
		return "Boss 场景加载失败"
	entered.emit()
	return "进入 Boss 阶段"
