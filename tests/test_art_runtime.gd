extends SceneTree

var failures: Array[String] = []
var game

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, title: String) -> void:
	print("ART RUNTIME CHECK ", title, " ", value)
	if not value:
		failures.append(title)

func _run() -> void:
	var path := "res://data/levels/art_acceptance.tres"
	var hash := FileAccess.get_sha256(path)
	game = load("res://scenes/level_playtest.tscn").instantiate()
	game.level_override = path
	root.add_child(game)
	game.testing = true
	for i in 5:
		await physics_frame
	check(game.data.objects.size() == 14, "actual playtest loads every art object")
	var chest := _prop("chest")
	check(chest != null, "runtime instantiates saved chest scene")
	game.player.position = chest.position + Vector3(0, 0.82, 1.45)
	game.player.velocity = Vector3.ZERO
	for i in 5:
		await physics_frame
	check(game.attempt_interact() and chest.state == "open" and chest.get_node("State_open").visible,
		"E opens nearby chest visual")
	check(not game.attempt_interact(), "opened chest cannot trigger again")
	game.player.position = chest.position + Vector3(0, 0.82, 2.0)
	var wall := _obstacle(chest.position + Vector3(0, 1.0, 1.1), Vector3(3, 2, 0.2))
	for i in 3:
		await physics_frame
	check(game._nearest_prop() == null, "interaction ray cannot pass through a wall")
	wall.queue_free()
	await physics_frame
	var rock := _prop("rock")
	game.player.position = rock.position + Vector3(0, 0.82, 1.65)
	game.player.velocity = Vector3.ZERO
	for i in 8:
		await physics_frame
	game.jump_requested = true
	game.test_direction = Vector3.FORWARD
	for i in 24:
		await physics_frame
	game.test_direction = Vector3.ZERO
	for i in 55:
		await physics_frame
	check(absf(game.player.position.y - 0.8 - (rock.position.y + 2)) < 0.12,
		"Space jump lands on real 2m rock collision")
	var climb := _prop("terrain_climb")
	game.player.position = climb.position + Vector3(0, 0.82, 0.7)
	game.player.velocity = Vector3.ZERO
	for i in 5:
		await physics_frame
	check(not game.attempt_interact() and not game.climbing, "climbing requires ability")
	game.climb_enabled = true
	var target: Vector3 = game._climb_position(climb)
	var obstruction := _obstacle(target, Vector3(1.2, 1.5, 1.2))
	for i in 3:
		await physics_frame
	check(not game.attempt_interact() and not game.climbing, "blocked climb attachment is rejected")
	obstruction.queue_free()
	for i in 3:
		await physics_frame
	var climb_up := _add_climb_surface("test_climb_up", climb, Vector3.UP * 2)
	var climb_right := _add_climb_surface("test_climb_right", climb_up, Vector3.RIGHT * 2)
	var climb_wrong_face := _add_climb_surface(
		"test_climb_wrong_face", climb_right, Vector3.UP * 2)
	climb_wrong_face.rotation.y += PI * 0.5
	var climb_gap := _add_climb_surface("test_climb_gap", climb_right, Vector3.UP * 4)
	await process_frame
	check(game.attempt_interact() and game.climbing, "E attaches to a nearby climbable surface")
	await _finish_climb_move()
	check(game.climb_prop == climb and game.player.position.distance_to(target) < 0.04,
		"attachment snaps to the surface without climbing to the top")
	game.climb_input_armed = true
	game.test_climb_input = Vector2.UP
	await physics_frame
	game.test_climb_input = Vector2.ZERO
	check(game.climb_moving and game.climb_next_prop == climb_up,
		"W input accepts an adjacent upper surface")
	await _finish_climb_move()
	check(game.climb_prop == climb_up and game.player.position.distance_to(
		game._climb_position(climb_up)) < 0.04, "W moves to the upper climbable surface")
	var move_obstruction := _obstacle(game._climb_position(climb_right), Vector3(1.2, 1.5, 1.2))
	await physics_frame
	check(not game.request_climb_move(Vector2i(1, 0)) and game.climb_prop == climb_up,
		"an obstructed adjacent surface cannot be entered")
	move_obstruction.queue_free()
	for i in 3:
		await physics_frame
	check(game.request_climb_move(Vector2i(1, 0)), "D accepts an adjacent right surface")
	await _finish_climb_move()
	check(game.climb_prop == climb_right, "D moves right across climbable surfaces")
	var blocked_position: Vector3 = game.player.position
	check(not game.request_climb_move(Vector2i(0, -1))
		and game.player.position.is_equal_approx(blocked_position),
		"movement ignores a rotated surface and cannot skip a missing surface")
	check(game.request_climb_move(Vector2i(-1, 0)), "A accepts an adjacent left surface")
	await _finish_climb_move()
	check(game.climb_prop == climb_up, "A moves left across climbable surfaces")
	check(game.request_climb_move(Vector2i(0, 1)), "S accepts an adjacent lower surface")
	await _finish_climb_move()
	check(game.climb_prop == climb, "S moves down across climbable surfaces")
	check(game.attempt_interact() and not game.climbing, "E detaches from a climbable surface")
	game.player.position = climb.position + Vector3(0, 0.82, 0.7)
	game.player.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	check(game.attempt_interact() and game.climbing, "E can attach again after detaching")
	await _finish_climb_move()
	game._end_climb(true)
	check(not game.climbing and game.player.velocity.y > 0,
		"Space-style detach jumps away from the wall")
	climb_up.queue_free()
	climb_right.queue_free()
	climb_wrong_face.queue_free()
	climb_gap.queue_free()
	await process_frame
	var breakable := _prop("breakable")
	game.player.position = breakable.position + Vector3(0, 0.82, 1.5)
	game.player.velocity = Vector3.ZERO
	for i in 5:
		await physics_frame
	check(game.attempt_damage() and breakable.health == 2,
		"J damages supporting rock even when its climbing attachment is in front")
	game.attempt_damage()
	game.attempt_damage()
	for i in 5:
		await physics_frame
	check(_prop("breakable") == null and _prop("stack_rock") == null and _prop("breakable_wall") == null,
		"destruction removes host collision and all dependent instances")
	check(game.data.validate().is_empty(), "runtime support graph remains valid after destruction")
	var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(source.objects.size() == 14 and FileAccess.get_sha256(path) == hash,
		"playtest state leaves saved map unchanged")
	print("ART RUNTIME TEST FAILURES: ", failures)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _prop(id: String) -> Node3D:
	for child in game.builder.generated.get_children():
		if child.get_meta("object_id", "") == id and not child.is_queued_for_deletion():
			return child
	return null

func _obstacle(position: Vector3, size: Vector3) -> StaticBody3D:
	var node := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	node.add_child(collision)
	game.add_child(node)
	node.position = position
	return node

func _add_climb_surface(id: String, source: GameplayProp, offset: Vector3) -> GameplayProp:
	var prop := AssetFactory.instantiate_asset(source.definition) as GameplayProp
	prop.instance_id = id
	prop.position = source.position + offset
	prop.rotation = source.rotation
	prop.set_meta("object_id", id)
	game.builder.generated.add_child(prop)
	return prop

func _finish_climb_move() -> void:
	for i in 120:
		await physics_frame
		if not game.climb_moving:
			return
