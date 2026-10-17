extends SceneTree

## Run with a real rendering backend (no --headless). Images go to /tmp.
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var terrain: TerrainBuilder
var title: Label
var errors: Array[String] = []

func _init() -> void:
	render.call_deferred()

func render() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1440, 960)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.fov = 38.0
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#20272c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.85
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.shadow_enabled = true
	world.add_child(light)
	title = Label.new()
	title.position = Vector2(32, 24)
	title.add_theme_font_size_override("font_size", 24)
	viewport.add_child(title)

	var columns := LevelData.new()
	columns.setup_blank(Vector2i(11, 3))
	for x in [1, 5, 9]:
		var cell := Vector2i(x, 1)
		columns.set_layer(cell, 0, {"tile_id": "grass"})
		columns.set_layer(cell, 1, {"tile_id": "rock"})
		columns.set_layer(cell, 2, {"tile_id": "sand"})
	columns.set_layer(Vector2i(5, 1), 1, {"tile_id": "ground_stone"})
	columns.set_layer(Vector2i(10, 1), 0, {"tile_id": "grass"})
	set_map(columns, Vector3(8, 13, 30), Vector3(0, 3, 0))
	await capture("columns",
		"Left: A/B/C    Center: replace B only    Right: adjacent lower column\nEach solid layer is 2m; only C has a visible top.")
	terrain.set_slice_layer(1)
	await capture("slice",
		"Slice at layer 1: C hidden, B exposed temporarily\nThe saved columns still contain A/B/C.")

	var stairs := LevelData.new()
	stairs.setup_blank(Vector2i(12, 12))
	var lows := [Vector2i(3, 3), Vector2i(7, 3), Vector2i(7, 8), Vector2i(3, 8)]
	for direction in 4:
		var low: Vector2i = lows[direction]
		var step: Vector2i = LevelData.DIRS[direction]
		for offset in [-1, 0, 1, 2]:
			stairs.set_layer(low + step * offset, 0 if offset < 1 else 1,
				{"tile_id": "grass" if offset < 1 else "sand"})
		stairs.stairs.append({"cell": low, "direction": direction})
	set_map(stairs, Vector3(19, 25, 29), Vector3(0, 2, 0))
	await capture("stairs", "Four stair directions: connected tops, filled steps, solid supports")

	var attachments := LevelData.new()
	attachments.setup_blank(Vector2i(6, 5))
	for y in 5:
		for x in 6:
			var cell := Vector2i(x, y)
			attachments.set_layer(cell, 0, {"tile_id": "sand"})
			if x < 3:
				attachments.set_layer(cell, 0, {"tile_id": "water"})
			else:
				attachments.set_layer(cell, 1, {"tile_id": "grass"})
				if y > 1:
					attachments.set_layer(cell, 1, {"tile_id": "decal_corruption"})
	set_map(attachments, Vector3(11, 15, 22), Vector3(0, 2, 0))
	await capture("attachments", "Water over sand support; masked overlay over raised grass")
	print("STACKED RENDER FAILURES: ", errors)
	quit(0 if errors.is_empty() else 1)

func set_map(data: LevelData, eye: Vector3, target: Vector3) -> void:
	if is_instance_valid(terrain):
		terrain.free()
	terrain = TerrainBuilder.new()
	terrain.level_data = data
	terrain.show_grid = false
	terrain.build_collision = false
	world.add_child(terrain)
	camera.position = eye
	camera.look_at(target)

func capture(suffix: String, caption: String) -> void:
	title.text = caption
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var path := "/tmp/aberration-stacked-%s.png" % suffix
	var error := image.save_png(path)
	if error != OK:
		errors.append("%s: %s" % [path, error_string(error)])
	print("STACKED RENDER ", path, " ", error)
