extends SceneTree

## Run with a real rendering backend (no --headless). Images go to /tmp.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 960)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := load("res://scenes/art_acceptance.tscn").instantiate() as Node3D
	viewport.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	var profile := load("res://data/art_profile.tres") as ArtProfile
	var terrain := world.get_node("TerrainBuilder") as TerrainBuilder
	var data := terrain.level_data
	profile.configure(camera, Vector3(0, 2, 0), 21)
	camera.current = true
	await _capture(viewport, "/tmp/aberration-art-overview.png")
	profile.configure(camera, Vector3(3, 3, 5), 11)
	await _capture(viewport, "/tmp/aberration-art-props.png")
	# Close views judge the grass fringe and the chest contact at near pixel scale.
	profile.configure(camera, data.world_center(Vector2i(3, 6)) + Vector3(0, -0.6, 1), 4.5)
	await _capture(viewport, "/tmp/aberration-art-edge.png")
	var chest: Node3D
	for node in get_nodes_in_group("gameplay_props"):
		if node.definition.behaviour == PlaceableDefinition.Behaviour.CHEST:
			chest = node
	profile.configure(camera, chest.global_position + Vector3(0, 0.6, 0), 2.6)
	await _capture(viewport, "/tmp/aberration-art-chest-closed.png")
	chest.interact(null)
	await _capture(viewport, "/tmp/aberration-art-chest-open.png")
	var slopes := 0
	var rims := 0
	for node in terrain.generated.find_children("*", "MeshInstance3D", true, false):
		# Repeated sibling names become "@MeshInstance3D@12"; count by metadata.
		if node.has_meta("slope_side"):
			slopes += 1
		if node.has_meta("terrain_rim"):
			rims += 1
	var failures: Array[String] = []
	if slopes < 2:
		failures.append("missing slope side art")
	if rims < 2:
		failures.append("missing grass rim")
	print("ART RENDER surfaces: rims=", rims, " slope sides=", slopes)
	print("ART RENDER TEST FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func _capture(viewport: SubViewport, path: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image().save_png(path)
	print("ART RENDER ", path, " ", error_string(result))
