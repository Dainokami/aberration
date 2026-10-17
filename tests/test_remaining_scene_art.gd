extends SceneTree

const ROOT := "res://assets/derived_art/scene_pack_20261014/"
const IDS := ["painted_climbingrock", "painted_climbingrock_alt", "painted_rock_alt", "painted_decayrock_alt"]
const WALL := "res://assets/generated/painted_climb_surface/definition.tres"
const Picker := preload("res://addons/terrain_editor/surface_picker.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	print("REMAINING ART CHECK ", value, " ", label)
	if not value:
		failures.append(label)

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		ROOT + "remaining_objects_manifest.json"))
	var library := ObjectRules.library()
	for id: String in IDS:
		var path := _path(id)
		var d := load(path) as PlaceableDefinition
		check(library.has(path) and d != null and d.validate_asset().is_empty(),
			"valid resource in editor library: " + id)
		check(d.volume_size == Vector3.ONE * 2 and d.collision_size == Vector3.ONE * 2
			and d.supports_objects, "solid 2m support volume: " + id)
		var expected := str(manifest["variants"][id])
		check(str(d.face_images["top"]).ends_with(expected + ".png"), "uses supplied alternate top: " + id)
		var instance := AssetFactory.instantiate_asset(d)
		check(instance is GameplayProp and instance.get_node("Art").get_child_count() == 6,
			"saved scene retains all faces and gameplay script: " + id)
		for face: String in ["front", "back", "left", "right", "top"]:
			var mesh := instance.get_node("Art/" + face.capitalize()) as MeshInstance3D
			var material := mesh.material_override as StandardMaterial3D
			check(material.albedo_texture.resource_path == d.face_images[face],
				"actual scene material " + id + "/" + face)
		instance.free()
	for entry: Dictionary in manifest["entries"]:
		var image := (load(ROOT + str(entry["output"])) as Texture2D).get_image()
		if image.is_compressed():
			image.decompress()
		check(image.get_size() == Vector2i(1024, 1024) and not image.is_invisible()
			and image.detect_alpha() == Image.ALPHA_NONE and image.has_mipmaps(),
			"rectified solid face with mipmaps: " + str(entry["id"]))
		var source := "res://assets/source_art/scene_pack_20261014/" + str(entry["source"])
		if FileAccess.file_exists(source):
			check(FileAccess.get_sha256(source) == entry["sha256"], "original climbing image unchanged")
	var existing_rock := load(_path("painted_rock")) as PlaceableDefinition
	check(str(existing_rock.face_images["top"]).ends_with("rock_topface2.png"),
		"original rock retains its original top")
	var data := fixture()
	check(data.validate().is_empty(), "new solids support stacks and climb attachments")
	var snapshot := data.clone_data()
	var saved_path := "user://remaining_scene_art_roundtrip.tres"
	check(ResourceSaver.save(data, saved_path) == OK, "supplement map saves")
	var loaded := ResourceLoader.load(saved_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded != null and loaded.validate().is_empty() and loaded.clone_data() == snapshot,
		"reload retains all definitions and anchor relationships")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 960)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var builder := TerrainBuilder.new()
	builder.level_data = loaded
	builder.show_grid = false
	viewport.add_child(builder)
	await physics_frame
	await physics_frame
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8
	var target := data.world_center(Vector2i(8, 2)) + Vector3.UP * 2
	camera.position = target + Vector3.UP * 10
	camera.look_at(target, Vector3.FORWARD)
	camera.current = true
	var hit := Picker.pick(builder, camera, camera.unproject_position(target))
	check(hit.get("kind") == "object" and hit.get("id") == "supplement_2",
		"editor surface picker discovers actual new rock top")
	var prop: GameplayProp
	# Generated sibling names may be automatic; locate by stable record metadata.
	for node in builder.generated.get_children():
		if node.get_meta("object_id", "") == "supplement_3":
			prop = node
	var style := load("res://data/terrain_style_profile.tres") as TerrainStyleProfile
	var coverage := TerrainTopology.mask_info(255, Vector2i.ZERO, style)
	check(coverage["kind"] == "full" and coverage["parts"].is_empty()
		and TerrainTopology.mask_image(coverage).get_pixel(0, 0).r == 1.0,
		"full terrain coverage needs no boundary artwork")
	if "--capture-remaining-art" in OS.get_cmdline_user_args():
		var profile := load("res://data/art_profile.tres") as ArtProfile
		profile.configure(camera, Vector3(0, 3, 0), 17)
		await capture(viewport, "/tmp/aberration-remaining-art-overview.png")
		for node in builder.generated.get_children():
			var id := str(node.get_meta("object_id", ""))
			if id.begins_with("grips_") or id == "supplement_stack":
				node.visible = false
		for i in IDS.size():
			var center := data.world_center(Vector2i(2 + i * 3, 2)) + Vector3.UP
			profile.configure(camera, center, 4.5)
			await capture(viewport, "/tmp/aberration-remaining-art-" + IDS[i] + ".png")
			camera.position = center + Vector3(5, 4, 6)
			camera.look_at(center)
			await capture(viewport, "/tmp/aberration-remaining-art-" + IDS[i] + "-side.png")
	check(prop != null and prop.apply_damage(3) and prop.state == "broken",
		"new weathered variant retains damage behavior")
	viewport.free()
	print("REMAINING SCENE ART TEST FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func fixture() -> LevelData:
	var data := LevelData.new()
	data.setup_blank(Vector2i(14, 6))
	for y in 6:
		for x in 14:
			data.set_layer(Vector2i(x, y), 0, {"tile_id": "painted_grass"})
	data.spawn_cell = Vector2i.ZERO
	data.spawn_layer = 0
	for i in IDS.size():
		var cell := Vector2i(2 + i * 3, 2)
		var record := ObjectRules.anchor_record(data, {"id": "supplement_%d" % i,
			"definition": _path(IDS[i]), "position": data.world_center(cell),
			"yaw": 0.0, "scale": 1.0})
		data.objects.append(record)
		var wall := Picker.placement(data, {"id": "grips_%d" % i, "definition": WALL,
			"position": record["position"], "yaw": 0.0, "scale": 1.0},
			{"kind": "object", "id": record["id"], "position": record["position"] + Vector3(0, 1, 1),
				"normal": Vector3.BACK})
		data.objects.append(wall)
	var stack := ObjectRules.object_anchor(data, {"id": "supplement_stack",
		"definition": _path("painted_rock_alt"), "yaw": 0.0, "scale": 1.0},
		"supplement_0", data.world_center(Vector2i(2, 2)) + Vector3.UP * 2)
	data.objects.append(stack)
	return data

func _path(id: String) -> String:
	return "res://assets/generated/" + id + "/definition.tres"

func capture(viewport: SubViewport, path: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(path) == OK, "Metal screenshot: " + path)
