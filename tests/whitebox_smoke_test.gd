extends SceneTree

var _player: PlayerController
var _start_position := Vector3.ZERO
var _frame := 0


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var floor := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.5, 20.0)
	floor_shape.shape = box
	floor.position.y = -0.25
	floor.add_child(floor_shape)
	world.add_child(floor)

	_player = load("res://scenes/player.tscn").instantiate() as PlayerController
	_player.position = Vector3(0.0, 0.05, 0.0)
	world.add_child(_player)
	_start_position = _player.position

	Input.action_press("move_forward")
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	_frame += 1

	if _frame == 15:
		Input.action_release("move_forward")
		if _player.global_position.distance_to(_start_position) < 0.15:
			_fail("WASD movement did not move the player")
			return
		Input.action_press("air_action")

	if _frame == 17:
		Input.action_release("air_action")

	if _frame == 24:
		if _player.global_position.y < 0.25:
			_fail("Default Space action did not take off")
			return
		_player.set_air_action(PlayerController.AirAction.JUMP)
		_player.global_position = Vector3(0.0, 0.05, 0.0)
		_player.velocity = Vector3.ZERO

	if _frame == 30:
		Input.action_press("air_action")

	if _frame == 33:
		Input.action_release("air_action")

	if _frame == 38:
		if _player.global_position.y < 0.25:
			_fail("Extensible jump mode did not jump")
			return
		_write_result("PASS: movement, default flight, and extensible jump responded in physics frames")
		print("WHITEBOX_SMOKE_TEST: PASS")
		quit(0)


func _fail(message: String) -> void:
	_write_result("FAIL: " + message)
	push_error("WHITEBOX_SMOKE_TEST: " + message)
	quit(1)


func _write_result(result: String) -> void:
	var file := FileAccess.open("res://tests/.last_result.txt", FileAccess.WRITE)
	if file:
		file.store_line(result)
