extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error("3C_INTERACTION: " + label)


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as PlayerController
	stage.add_child(player)
	player.global_position = Vector3(200.0, 0.08, 0.0)
	player.set_physics_process(false)

	var wall := StaticBody3D.new()
	wall.position = Vector3(200.0, 1.0, -1.0)
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(4.0, 3.0, 0.2)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	stage.add_child(wall)

	var host := Node3D.new()
	host.position = Vector3(200.0, 0.0, -2.0)
	stage.add_child(host)
	var target := AffordanceProp.new()
	target.configure_host(host, "enemy_small", 20)
	target.position = host.position
	stage.add_child(target)
	await physics_frame

	var blocked := SceneProbe.nearest_reachable(
		player, 3.0, PackedStringArray(["enemy_small"]))
	_check(blocked == null, "attack target must not lock through a wall")
	wall.queue_free()
	await physics_frame
	var visible := SceneProbe.nearest_reachable(
		player, 3.0, PackedStringArray(["enemy_small"]))
	_check(visible == target, "visible attack target should be selectable")

	var hard_host := Node3D.new()
	hard_host.position = player.global_position + Vector3.RIGHT
	stage.add_child(hard_host)
	var hard := AffordanceProp.new()
	hard.configure_host(hard_host, "destructible_hard", 20)
	hard.position = hard_host.position
	stage.add_child(hard)
	await physics_frame
	player.parts._auto_combat()
	_check(hard.health == 20, "nearby destructibles must not take automatic proximity damage")
	player.parts._interact()
	_check(hard.health < 20, "G interaction should still activate equipped destruction abilities")

	player.parts._diving = true
	player.parts._dive_point = player.global_position
	player.parts._tick_dive(player)
	_check(not player.parts._diving and player.velocity.y < 0.0,
		"dive must hand control back to gravity after reaching its target")

	if failures.is_empty():
		print("3C_INTERACTION: PASS")
		quit(0)
	else:
		print("3C_INTERACTION: FAIL ", failures)
		quit(1)
