extends SceneTree

## Offscreen deliverable render, not a substitute for interactive GUI acceptance.
func _init() -> void:
	render.call_deferred()

func render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var terrain := TerrainBuilder.new()
	terrain.level_data = load("res://data/levels/objects_acceptance.tres")
	terrain.show_grid = false
	world.add_child(terrain)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 39
	world.add_child(camera)
	var profile := load("res://data/art_profile.tres") as ArtProfile
	camera.position = profile.camera_offset
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#17212b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	world.add_child(light)
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var error := image.save_png("/tmp/aberration-v2-map.png")
	print("V2 render saved ", error)
	quit(error)
