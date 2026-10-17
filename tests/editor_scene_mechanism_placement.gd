@tool
extends RefCounted

var failures: Array[String] = []
const MANIFEST := "res://assets/derived_art/scene_pack_20261016/manifest.json"

func check(condition: bool, label: String) -> void:
	print("EDITOR PLACEMENT ", label, " ", condition)
	if not condition:
		failures.append(label)

func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1000, 800)
	viewport.own_world_3d = true
	tree.root.add_child(viewport)
	var builder := TerrainBuilder.new()
	builder.show_grid = false
	viewport.add_child(builder)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12
	viewport.add_child(camera)
	camera.current = true
	plugin._edit(builder)
	var tools = plugin.world_tools
	tools.refresh_library()
	plugin.tabs.current_tab = 1
	tools.object_mode.selected = 0
	tools.scale_input.value = 1
	tools.yaw_input.value = 0
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var report: Array[Dictionary] = []
	for entry: Dictionary in manifest.entries:
		var before := failures.size()
		var data := LevelData.new()
		data.setup_blank(Vector2i(6, 6))
		var eco: String = entry.ecosystems[0]
		for y in 6:
			for x in 6:
				var cell := Vector2i(x, y)
				data.set_layer(cell, 0, {"tile_id": "sand" if eco == "desert"
					else "rock" if eco == "rock" else "grass"})
				if eco == "ocean":
					for layer in range(1, 4):
						data.set_layer(cell, layer, {"tile_id": "water"})
		var cell := Vector2i(2, 2)
		tools.clear_ghost()
		builder.level_data = data
		plugin.data = data
		builder.rebuild()
		var point := data.world_center(cell, 0)
		if entry.kind == "vine":
			cell = Vector2i(0, 2)
			point = data.world_layer_center(cell, 0) + Vector3.LEFT
			camera.position = point + Vector3.LEFT * 10
			camera.look_at(point, Vector3.UP)
		else:
			camera.position = point + Vector3(0, 12, 0.01)
			camera.look_at(point, Vector3.FORWARD)
		if entry.kind == "bubbles":
			# Click the water's side, with an oblique ray that would otherwise
			# reach a different ground cell. The selected water column owns it.
			point = data.world_layer_center(Vector2i(0, 2), 1) + Vector3.LEFT
			camera.position = point + Vector3(-8, 4, 0)
			camera.look_at(point)
		var path: String = "res://assets/generated/" + entry.id + "/definition.tres"
		var index: int = tools.paths.find(path)
		check(index >= 0, entry.id + " library")
		tools.library.select(index)
		for frame in 3:
			await tree.physics_frame
		var mouse := camera.unproject_position(point)
		var motion := InputEventMouseMotion.new()
		motion.position = mouse
		tools.handle(camera, motion)
		check(is_instance_valid(tools.ghost), entry.id + " actual hover preview")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = mouse
		tools.handle(camera, click)
		check(data.objects.size() == 1, entry.id + " left-click stores object")
		if data.objects.size() == 1:
			var record: Dictionary = data.objects[0]
			var id := str(record.id)
			if entry.kind == "bubbles":
				check(record.anchor_cell == Vector2i(0,2) and record.anchor_layer == 0,
					entry.id + " clicking water anchors to seabed in the same column")
			check(builder._object_nodes.has(id), entry.id + " actual generated node")
			if builder._object_nodes.has(id):
				var object: Node3D = builder._object_nodes[id]
				check(object.get_script().is_tool(), entry.id + " executable editor script")
				check(object.get("level_data") == data, entry.id + " bound LevelData")
				check(object.visible, entry.id + " visible after placement")
				check(not object.is_physics_processing() and not object.is_in_group("scene_mechanisms"),
					entry.id + " editor does not execute gameplay")
			var history: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(
				plugin.get_undo_redo().get_object_history_id(data))
			history.undo()
			check(data.objects.is_empty() and builder._object_nodes.is_empty(), entry.id + " real undo")
			history.redo()
			check(data.objects.size() == 1 and builder._object_nodes.has(id), entry.id + " real redo")
			var output := "user://scene_mechanism_editor_roundtrip.tres"
			check(ResourceSaver.save(data, output) == OK, entry.id + " save")
			var loaded := ResourceLoader.load(output, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
			builder.level_data = loaded
			builder.rebuild()
			check(builder._object_nodes.has(id), entry.id + " reload rebuild")
			DirAccess.remove_absolute(output)
		report.append({"id": entry.id, "passed": failures.size() == before})
		tools.clear_ghost()
	await check_single_water_block(plugin, tools, builder, camera)
	await check_unsupported_water(plugin, tools, builder, camera)
	var output := FileAccess.open("/tmp/scene-mechanism-editor-placement.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"assets": report, "failures": failures}, "\t"))
	output.close()
	plugin.builder = null
	plugin.data = null
	viewport.free()
	print("EDITOR SCENE PLACEMENT FAILURES: ", failures)
	tree.quit(0 if failures.is_empty() else 1)

func check_single_water_block(plugin: EditorPlugin, tools: RefCounted,
		builder: TerrainBuilder, camera: Camera3D) -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(3,3))
	var cell := Vector2i(1,1)
	data.set_layer(cell,0,{"tile_id":"rock"})
	data.set_layer(cell,1,{"tile_id":"water"})
	tools.clear_ghost()
	builder.level_data = data
	plugin.data = data
	builder.rebuild()
	tools.library.select(tools.paths.find("res://assets/generated/scene1016_bubbles_1x1/definition.tres"))
	var point := data.world_center(cell,1)
	camera.position = point + Vector3(0,10,0.01)
	camera.look_at(point,Vector3.FORWARD)
	for frame in 3:
		await plugin.get_tree().physics_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(point)
	tools.handle(camera,click)
	check(data.objects.size() == 1 and data.objects[0].anchor_cell == cell
		and data.objects[0].anchor_layer == 0 and builder._object_nodes.size() == 1,
		"one water block over one rock block accepts one bubble by water-surface click")

func check_unsupported_water(plugin: EditorPlugin, tools: RefCounted,
		builder: TerrainBuilder, camera: Camera3D) -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(3,3))
	var cell := Vector2i(1,1)
	data.set_layer(cell,0,{"tile_id":"water"})
	builder.level_data = data
	plugin.data = data
	builder.rebuild()
	tools.library.select(tools.paths.find("res://assets/generated/scene1016_bubbles_1x1/definition.tres"))
	var point := data.world_center(cell,0)
	camera.position = point + Vector3(0,10,0.01)
	camera.look_at(point, Vector3.FORWARD)
	for frame in 3:
		await plugin.get_tree().physics_frame
	var surface: Dictionary = tools._pick_placement_surface(camera, camera.unproject_position(point))
	check(str(surface.get("error","")).contains("没有海底实体地形"),
		"unsupported water gives specific seabed guidance")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(point)
	tools.handle(camera, click)
	check(data.objects.is_empty() and builder._object_nodes.is_empty(),
		"unsupported water does not place bubbles on a distant surface")
