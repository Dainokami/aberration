extends SceneTree

var failures: Array[String] = []
var output_dir := "/tmp/portal-captures"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			output_dir = arg.trim_prefix("--capture-dir=")
	run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output_dir.path_join(name + ".png"))
	if error != OK:
		failures.append("capture " + name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	var level := load("res://scenes/portal_demo.tscn").instantiate() as Node3D
	root.add_child(level)
	current_scene = level
	await frames(10)
	var hud := level.get_node("LevelTransitionLayer/LevelTransitionHUD") as LevelTransitionHUD
	if not hud.countdown_label.text.contains("倒计时"):
		failures.append("initial countdown")
	await capture("01_countdown")
	root.size = Vector2i(800, 600)
	await frames(2)
	if absf(hud.countdown_label.get_global_rect().get_center().x \
			- root.get_visible_rect().size.x * 0.5) > 1:
		failures.append("narrow HUD center")
	await capture("02_countdown_800")
	root.size = Vector2i(1280, 800)
	var controller: LevelTransitionController = level.get("transition_controller")
	for i in 420:
		if controller.state == LevelTransitionController.State.OPEN:
			break
		await frames(1)
	if controller.portal == null:
		failures.append("real-time expiry spawns portal")
		finish()
		return
	await capture("03_portal_open")
	var player: CharacterBody3D = level.get("player")
	var camera: Camera3D = level.get("camera")
	for i in 300:
		var difference := controller.portal.global_position - player.global_position
		difference.y = 0
		if difference.length() < 2.0:
			break
		var forward := camera.global_basis.z
		forward.y = 0
		var right := camera.global_basis.x
		right.y = 0
		var axis := Vector2(difference.normalized().dot(right.normalized()),
			difference.normalized().dot(forward.normalized()))
		for action in ["move_up", "move_down", "move_left", "move_right"]:
			Input.action_release(action)
		Input.action_press("move_left" if axis.x < 0 else "move_right", absf(axis.x))
		Input.action_press("move_up" if axis.y < 0 else "move_down", absf(axis.y))
		await frames(1)
	for action in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(action)
	await frames(3)
	if controller.interaction_text().is_empty() or level.get("interaction_label").text != "E 进入下一关":
		failures.append("walk to portal displays E hint")
	await capture("04_interaction")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	key = InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = false
	Input.parse_input_event(key)
	await frames(15)
	if current_scene.get("loaded_level_path") != LevelTransitionConfig.DEFAULT_TARGET:
		failures.append("E input transitions")
	await capture("05_destination")
	finish()

func finish() -> void:
	print("PORTAL VISUAL FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)
