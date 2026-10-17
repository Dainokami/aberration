extends SceneTree

var viewport: SubViewport
var world: Node3D
var camera: Camera3D

func _initialize() -> void:
	render.call_deferred()

func render() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#20272c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 1.0
	world.add_child(environment)
	camera = Camera3D.new()
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 25
	world.add_child(camera)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/derived_art/scene_pack_20261016/manifest.json"))
	var output := ProjectSettings.globalize_path("res://../海洋与场景资产验收画面")
	DirAccess.make_dir_recursive_absolute(output)
	for page in 4:
		var holder := Node3D.new()
		world.add_child(holder)
		camera.position = Vector3(0, 12, 29)
		camera.look_at(Vector3(0, 2, 0))
		for index in range(page * 8, mini((page + 1) * 8, manifest.entries.size())):
			var entry: Dictionary = manifest.entries[index]
			var d := load("res://assets/generated/" + entry.id + "/definition.tres") as PlaceableDefinition
			var asset := AssetFactory.instantiate_asset(d)
			holder.add_child(asset)
			asset.set_process(false)
			asset.set_physics_process(false)
			var local := index % 8
			asset.position = Vector3((local % 4 - 1.5) * 6, 0, (1 - local / 4) * 15 - 7)
			var label := Label3D.new()
			label.text = entry.id
			label.font_size = 28
			label.pixel_size = 0.012
			label.position = asset.position + Vector3(0,-0.4,1)
			holder.add_child(label)
		await capture(output.path_join("assets_%d.png" % (page + 1)))
		holder.free()
	var data := LevelData.new()
	data.setup_blank(Vector2i(8, 7))
	for y in 7:
		for x in 8:
			var cell := Vector2i(x,y)
			data.set_layer(cell,0,{"tile_id":"sand"})
			if x < 5:
				data.set_layer(cell,1,{"tile_id":"water"})
				data.set_layer(cell,2,{"tile_id":"water"})
			else:
				data.set_layer(cell,1,{"tile_id":"rock"})
				data.set_layer(cell,2,{"tile_id":"grass"})
	for spec in [["scene1016_remains_1534",Vector2i(1,3)],
			["scene1016_chest_1541",Vector2i(2,4)], ["scene1016_bubbles_1x3",Vector2i(2,1)]]:
		data.objects.append(ObjectRules.anchor_record(data,{"id":spec[0],
			"definition":"res://assets/generated/" + spec[0] + "/definition.tres",
			"position":data.world_center(spec[1],0),"scale":1.0,"yaw":0.0}))
	var terrain := TerrainBuilder.new()
	terrain.level_data = data
	terrain.show_grid = false
	terrain.build_collision = false
	world.add_child(terrain)
	camera.position = Vector3(13,14,25)
	camera.look_at(Vector3(0,2,0))
	await capture(output.path_join("ocean_surface.png"))
	camera.position = Vector3(10,3.5,18)
	camera.look_at(Vector3(0,3,0))
	await capture(output.path_join("ocean_underwater.png"))
	print("OCEAN1016 METAL RENDER COMPLETE")
	quit()

func capture(path: String) -> void:
	for index in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	assert(image.save_png(path) == OK)
	print("RENDER ", path)
