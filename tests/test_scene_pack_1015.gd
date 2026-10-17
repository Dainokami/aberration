extends SceneTree

const ROOT := "res://assets/derived_art/scene_pack_20261015/"
const Picker := preload("res://addons/terrain_editor/surface_picker.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	print("1015 CHECK ", value, " ", label)
	if not value:
		failures.append(label)

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	check(manifest["sources"].size() == 8 and manifest["entries"].size() == 11,
		"eight source images become eleven placeable assets")
	for source: Dictionary in manifest["sources"]:
		var path := "res://assets/source_art/scene_pack_20261015/" + str(source["source"])
		if FileAccess.file_exists(path):
			check(FileAccess.get_sha256(path) == source["sha256"], "immutable source " + str(source["id"]))
	var library := ObjectRules.library()
	for entry: Dictionary in manifest["entries"]:
		var path := asset_path(entry["id"])
		var d := load(path) as PlaceableDefinition
		check(library.has(path) and d.validate_asset().is_empty(), "editor resource " + str(entry["name"]))
		var image := (load(d.source_image) as Texture2D).get_image()
		check(image.get_size() == Vector2i(512, 512) and image.has_mipmaps(), "512 canvas and mipmaps")
		var prop := AssetFactory.instantiate_asset(d)
		if d.carrier == PlaceableDefinition.Carrier.MULTI_FACE:
			check_cube(prop, d)
		elif entry["kind"] != "wall":
			var mesh := prop.get_node("Art") as MeshInstance3D
			var arrays := mesh.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var depths := {}
			var floor_valid := true
			for p in vertices:
				depths[snappedf((d.profile.camera_basis().inverse() * p).z, 0.001)] = true
				floor_valid = floor_valid and p.y >= -0.001
			check(depths.size() > 1 and floor_valid, "solid silhouette wrapper stays above its anchor")
		prop.free()
	var intact := load(asset_path("painted_fissured_rock")) as PlaceableDefinition
	var damaged := load(asset_path("painted_fissured_rock_damaged")) as PlaceableDefinition
	check(intact.preparation["recipe"]["crop"] == damaged.preparation["recipe"]["crop"]
		and intact.pivot == damaged.pivot and intact.image_size == damaged.image_size,
		"intact and damaged wall share framing and contact")
	check(intact.carrier == PlaceableDefinition.Carrier.MULTI_FACE
		and damaged.carrier == PlaceableDefinition.Carrier.MULTI_FACE,
		"intact and damaged wall have matching complete cube volumes")
	var data := fixture(manifest)
	check(data.validate().is_empty(), "all imported solids and wall attachments validate")
	var path := "user://scene_pack_1015_roundtrip.tres"
	check(ResourceSaver.save(data, path) == OK, "map saves")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded != null and loaded.validate().is_empty() and loaded.clone_data() == data.clone_data(),
		"map reload retains definitions and wall host")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 960)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var builder := TerrainBuilder.new()
	builder.show_grid = false
	builder.level_data = loaded
	viewport.add_child(builder)
	await process_frame
	await process_frame
	await physics_frame
	var handles: Array[AffordanceProp] = []
	for node in get_nodes_in_group("affordance"):
		if node is AffordanceProp and node.host != null and builder.is_ancestor_of(node.host):
			handles.append(node)
	check(handles.size() == 5, "all five traction variants expose existing carry interface")
	var handle := handles[0]
	var host := handle.host
	var body := host.get_node("ProxyCollision") as StaticBody3D
	check((body.get_node("Shape").shape as BoxShape3D).size == Vector3.ONE * 2,
		"traction collision matches 2m cell volume")
	handle.set_carried(true)
	check(body.collision_layer == 0, "carrying disables host collision")
	var original := host.global_position
	handle.global_position += Vector3.RIGHT * 0.4
	await physics_frame
	check(host.global_position.is_equal_approx(original + Vector3.RIGHT * 0.4), "carried visual follows handle")
	handle.drop()
	check(body.collision_layer == 1 and not handle.ballistic, "drop restores collision")
	handle.throw_along(Vector3.RIGHT)
	check(handle.ballistic and handle.throw_velocity.y > 0, "existing throw interface accepts new rock")
	handle.drop()
	handle.global_position = original
	await physics_frame
	var wall: GameplayProp
	var breakable: GameplayProp
	for node in builder.generated.get_children():
		if node.get_meta("object_id", "") == "clinging_wall":
			wall = node
		if node.get_meta("object_id", "") == "fissured":
			breakable = node
	check(wall != null and wall.is_in_group("climb_surfaces")
		and wall.get_node("InteractionArea/Shape").shape.size == Vector3(2, 2, 0.16),
		"new climbing art is an existing 2m wall interaction surface")
	if "--capture-1015-art" in OS.get_cmdline_user_args():
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.current = true
		var profile := load("res://data/art_profile.tres") as ArtProfile
		profile.configure(camera, Vector3(0, 2, 0), 18)
		await capture(viewport, "/tmp/art1015-overview.png")
		wall.visible = false
		for id: String in ["traction_1", "traction_2", "traction_3", "traction_4",
				"traction_5", "fissured", "clinging_wall"]:
			if id == "clinging_wall":
				wall.visible = true
			var record := ObjectRules.find_record(data, id)
			var center: Vector3 = record["position"] + Vector3.UP
			profile.configure(camera, center, 4.5)
			await capture(viewport, "/tmp/art1015-" + id + ".png")
			if id != "clinging_wall":
				camera.position = center + Vector3(5, 4, 6)
				camera.look_at(center)
				await capture(viewport, "/tmp/art1015-" + id + "-side.png")
	check(breakable.apply_damage(1) and breakable.state != "broken", "fissured rock keeps 3 health")
	check(breakable.apply_damage(2) and breakable.state == "broken", "fissured rock breaks at zero health")
	await process_frame
	await physics_frame
	check(breakable.get_node("ProxyCollision/Shape").disabled, "broken rock releases collision")
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var target := data.world_center(Vector2i(5, 2)) + Vector3.UP * 2
	camera.position = target + Vector3.UP * 10
	camera.look_at(target, Vector3.FORWARD)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5
	await physics_frame
	var hit := Picker.pick(builder, camera, camera.unproject_position(target))
	check(hit.get("kind") == "object" and hit.get("id") == "traction_2",
		"editor picks actual imported solid collision")
	var saved_snapshot := data.clone_data()
	ObjectRules.remove_with_dependents(data, ["fissured"])
	check(ObjectRules.find_record(data, "clinging_wall").is_empty(), "destroyed host removes wall dependents")
	data.restore_data(saved_snapshot)
	viewport.free()
	print("1015 SCENE PACK TEST FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func asset_path(id: String) -> String:
	return "res://assets/generated/" + id + "/definition.tres"

func check_cube(prop: Node3D, d: PlaceableDefinition) -> void:
	var art := prop.get_node("Art") as Node3D
	check(art.get_child_count() == 6, "cube has six textured faces " + d.asset_id)
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for face: MeshInstance3D in art.get_children():
		var vertices: PackedVector3Array = face.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point := art.transform * face.transform * vertex
			minimum = minimum.min(point)
			maximum = maximum.max(point)
		var material := face.material_override as StandardMaterial3D
		var image := material.albedo_texture.get_image()
		if image.is_compressed():
			image.decompress()
		check(image.get_size() == Vector2i(512, 512) and image.detect_alpha() == Image.ALPHA_NONE
			and image.has_mipmaps() and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
			"cube face is opaque at every edge " + d.asset_id + "/" + str(face.name))
	var size := maximum - minimum
	check(size.is_equal_approx(Vector3.ONE * 2) and minimum.is_equal_approx(Vector3(-1, 0, -1)),
		"visible geometry fills exact 2m cube " + d.asset_id)
	if d.collision == PlaceableDefinition.Collision.BOX:
		var shape := prop.get_node("ProxyCollision/Shape") as CollisionShape3D
		var collision_minimum := shape.position - (shape.shape as BoxShape3D).size * 0.5
		check(collision_minimum.is_equal_approx(minimum)
			and (shape.shape as BoxShape3D).size.is_equal_approx(size),
			"visible cube and collision share every boundary " + d.asset_id)
		# Uniform scaling and all four editor turns must keep both volumes aligned.
		for turns in 4:
			var transform := Transform3D(Basis(Vector3.UP, turns * PI * 0.5).scaled(Vector3.ONE * 1.5),
				Vector3(3, 4, 5))
			check((transform * AABB(minimum, size)).is_equal_approx(
				transform * AABB(collision_minimum, (shape.shape as BoxShape3D).size)),
				"rotation/scaling preserve visual collision alignment %s/%d" % [d.asset_id, turns])

func fixture(manifest: Dictionary) -> LevelData:
	var data := LevelData.new()
	data.setup_blank(Vector2i(20, 8))
	for y in 8:
		for x in 20:
			data.set_layer(Vector2i(x, y), 0, {"tile_id": "painted_grass"})
	data.spawn_cell = Vector2i.ZERO
	data.spawn_layer = 0
	for i in 5:
		data.objects.append(ObjectRules.anchor_record(data, {"id": "traction_%d" % (i + 1),
			"definition": asset_path("painted_traction_rock_%02d" % (i + 1)),
			"position": data.world_center(Vector2i(2 + i * 3, 2)), "yaw": 0.0, "scale": 1.0}))
	var fissured := ObjectRules.anchor_record(data, {"id": "fissured",
		"definition": asset_path("painted_fissured_rock"), "yaw": 0.0, "scale": 1.0,
		"position": data.world_center(Vector2i(8, 5))})
	data.objects.append(fissured)
	data.objects.append(Picker.placement(data, {"id": "clinging_wall",
		"definition": asset_path("painted_clinging_wall"), "yaw": 0.0, "scale": 1.0},
		{"kind": "object", "id": "fissured", "position": fissured["position"] + Vector3(0, 1, 1),
			"normal": Vector3.BACK}))
	var column := 3
	for entry: Dictionary in manifest["entries"]:
		if entry["kind"] not in ["decoration", "fragment"]:
			continue
		data.objects.append(ObjectRules.anchor_record(data, {"id": entry["id"],
			"definition": asset_path(entry["id"]), "yaw": 0.0, "scale": 1.0,
			"position": data.world_center(Vector2i(column, 5))}))
		column += 3
	return data

func capture(viewport: SubViewport, path: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(path) == OK, "Metal screenshot " + path)
