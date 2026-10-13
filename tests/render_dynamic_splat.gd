extends SceneTree

const OUTPUT_PATH := "/tmp/aberration-dynamic-splat.png"
const CLOSEUP_PATH := "/tmp/aberration-dynamic-splat-closeup.png"

func _init() -> void:
	_render.call_deferred()

func _render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1512, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var terrain := TerrainBuilder.new()
	terrain.level_data = load(
		"res://data/levels/dynamic_splat_acceptance.tres") as LevelData
	terrain.show_grid = false
	terrain.build_collision = false
	world.add_child(terrain)
	var camera := Camera3D.new()
	world.add_child(camera)
	var profile := load("res://data/art_profile.tres") as ArtProfile
	profile.configure(camera, Vector3(0.0, 1.4, 0.0))
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#20272c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.85
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.shadow_enabled = true
	world.add_child(light)
	for frame in 16:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	var closeup_profile := profile.duplicate() as ArtProfile
	closeup_profile.camera_distance = 17.0
	closeup_profile.pitch_degrees = 30.0
	closeup_profile.configure(camera, Vector3(8.0, 0.0, -8.0))
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var closeup := viewport.get_texture().get_image()
	var closeup_error := closeup.save_png(CLOSEUP_PATH)
	print("DYNAMIC SPLAT RENDER: ", error, " ", image.get_size(),
		" CLOSEUP: ", closeup_error)
	if error == OK:
		error = closeup_error
	quit(error)
