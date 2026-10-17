extends SceneTree

const ROOT := "res://assets/derived_art/scene_pack_20261015/"
const MANIFEST := ROOT + "manifest.json"
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var volumes := {}
	var volume_path := ROOT + "volume_manifest.json"
	if FileAccess.file_exists(volume_path):
		var volume_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(volume_path))
		for entry: Dictionary in volume_manifest["entries"]:
			volumes[entry["id"]] = entry
	elif "--refresh-1015-volume" in OS.get_cmdline_user_args():
		printerr("Run tools/prepare_scene_pack_1015_volume.py first")
		quit(1)
		return
	for entry: Dictionary in manifest["entries"]:
		if "--refresh-1015-volume" in OS.get_cmdline_user_args() and not volumes.has(entry["id"]):
			continue
		var d := PlaceableDefinition.new()
		d.asset_id = entry["id"]
		d.display_name = entry["name"]
		d.source_image = ROOT + str(entry["output"])
		d.source_manifest = MANIFEST
		d.profile = load("res://data/art_profile.tres")
		d.generator_version = 5
		d.preparation = entry.duplicate(true)
		d.image_size = Vector2.ONE * 2.1
		d.pivot = Vector2(0.5, 508.0 / 512.0)
		var size: Array = entry["world_size"]
		d.volume_size = Vector3(size[0], size[1], size[2])
		d.collision_size = d.volume_size
		d.fade_when_occluding = false
		# Keep the painted proportions while making the visible silhouette two metres wide/high.
		var fit: Array = entry["recipe"]["fit"]
		var visible_span := float(fit[1] if entry["kind"] in ["wall", "breakable", "decoration", "fragment"]
			else fit[0])
		d.image_size = Vector2.ONE * float(size[1]) * 512.0 / visible_span
		match str(entry["kind"]):
			"traction":
				d.category = "玩法物件"
				d.collision = PlaceableDefinition.Collision.BOX
				d.behaviour = PlaceableDefinition.Behaviour.ROCK
				d.preparation["runtime_interface"] = "pushable"
			"wall":
				d.category = "墙面附件"
				d.carrier = PlaceableDefinition.Carrier.WALL
				d.behaviour = PlaceableDefinition.Behaviour.CLIMBABLE
				d.image_size = Vector2.ONE * 2
				d.preparation["runtime_interface"] = "climb_surfaces"
			"breakable":
				d.category = "玩法物件"
				d.collision = PlaceableDefinition.Collision.BOX
				d.behaviour = PlaceableDefinition.Behaviour.BREAKABLE
				d.supports_objects = true
				d.max_health = 3
				d.preparation["damaged_asset"] = "painted_fissured_rock_damaged"
			"decoration":
				d.category = "岩石装饰"
			"fragment":
				d.category = "岩石装饰"
		if volumes.has(d.asset_id):
			var volume: Dictionary = volumes[d.asset_id]
			d.generator_version = 6
			d.carrier = PlaceableDefinition.Carrier.MULTI_FACE
			d.source_image = ROOT + str(volume["preview"])
			d.volume_size = Vector3.ONE * 2
			d.image_size = Vector2.ONE * 2
			for face: String in volume["faces"]:
				d.face_images[face] = ROOT + str(volume["faces"][face])
			d.preparation["volume"] = volume.duplicate(true)
			d.preparation["volume_manifest"] = volume_path
		elif entry["kind"] == "wall":
			# The artwork is a narrow vertical strip. Its interaction region still follows 2m modules.
			d.image_size = Vector2(2, 2)
		else:
			d.carrier = PlaceableDefinition.Carrier.PROJECTED_BOX
			d.preparation["wrap_depth_m"] = minf(0.3, float(size[2]) * 0.35)
			d.preparation["wrap_method"] = "silhouette_extrusion"
		_generate(d, str(entry["kind"]))
	print("1015 SCENE PACK IMPORT ERRORS: ", errors)
	quit(0 if errors.is_empty() else 1)

func _generate(d: PlaceableDefinition, kind: String) -> void:
	var directory := "res://assets/generated/" + d.asset_id
	if DirAccess.dir_exists_absolute(directory):
		var existing := load(directory.path_join("definition.tres")) as PlaceableDefinition
		if existing == null or existing.source_manifest != MANIFEST or not existing.validate_asset().is_empty() \
				or not ResourceLoader.exists(existing.scene_path):
			errors.append("Existing ID is invalid or belongs to another pack: " + d.asset_id)
			return
		if "--refresh-1015" not in OS.get_cmdline_user_args() \
				and "--refresh-1015-volume" not in OS.get_cmdline_user_args():
			print("Already present: ", d.asset_id)
			return
		d.scene_path = directory.path_join("asset.tscn")
		d.thumbnail_path = directory.path_join("thumbnail.png")
	else:
		var error := AssetFactory.generate(d, directory)
		if not error.is_empty():
			errors.append(d.asset_id + ": " + error)
			return
	var prop := AssetFactory.make_asset(d)
	if kind != "wall" and d.carrier != PlaceableDefinition.Carrier.MULTI_FACE:
		var original := prop.get_node("Art") as MeshInstance3D
		var wrapped := _wrapped_visual(d)
		wrapped.set_surface_override_material(0, original.material_override)
		var outline := StandardMaterial3D.new()
		outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outline.cull_mode = BaseMaterial3D.CULL_DISABLED
		outline.albedo_color = Color("#211b20")
		wrapped.set_surface_override_material(1, outline)
		wrapped.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		prop.remove_child(original)
		original.free()
		wrapped.name = "Art"
		prop.add_child(wrapped)
		wrapped.owner = prop
	if kind == "traction":
		prop.set_script(load("res://scripts/runtime/traction_rock.gd"))
		prop.set("definition", d)
	var packed := PackedScene.new()
	var result := packed.pack(prop)
	prop.free()
	if result == OK:
		result = ResourceSaver.save(packed, d.scene_path)
	if result == OK:
		result = ResourceSaver.save(d, directory.path_join("definition.tres"))
	if result == OK and d.carrier == PlaceableDefinition.Carrier.MULTI_FACE:
		var preview := (load(d.source_image) as Texture2D).get_image()
		if preview.is_compressed():
			preview.decompress()
		preview.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		result = preview.save_png(d.thumbnail_path)
	if result != OK:
		errors.append(d.asset_id + ": " + error_string(result))

func _wrapped_visual(d: PlaceableDefinition) -> MeshInstance3D:
	var image := (load(d.source_image) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	var points := PackedVector2Array()
	for y in image.get_height():
		var left := -1
		var right := -1
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.15:
				if left < 0:
					left = x
				right = x
		if left >= 0:
			points.append(Vector2(left, y) / Vector2(image.get_size()))
			points.append(Vector2(right + 1, y + 1) / Vector2(image.get_size()))
	var hull := Geometry2D.convex_hull(points)
	hull.remove_at(hull.size() - 1)
	while hull.size() > 16:
		var least := INF
		var remove := 0
		for i in hull.size():
			var a := hull[posmod(i - 1, hull.size())]
			var area := absf((hull[i] - a).cross(hull[(i + 1) % hull.size()] - a))
			if area < least:
				least = area
				remove = i
		hull.remove_at(remove)
	var front := PackedVector3Array()
	var back := PackedVector3Array()
	var basis := d.profile.camera_basis()
	var distance := d.profile.camera_distance
	for uv in hull:
		var screen := Vector2((uv.x - d.pivot.x) * d.image_size.x,
			(d.pivot.y - uv.y) * d.image_size.y)
		var point := basis * Vector3(screen.x, screen.y, 0)
		front.append(point)
		# Extrude along the camera ray: the fixed view retains the supplied silhouette.
		# Shorten the lower edge's extrusion so the wrapping mesh cannot enter the ground.
		var floor_limit := point.y / maxf(0.001, basis.z.y - point.y / distance)
		var depth := clampf(floor_limit, 0, float(d.preparation["wrap_depth_m"]))
		back.append(basis * Vector3(screen.x * (1 + depth / distance),
			screen.y * (1 + depth / distance), -depth))
	var vertices := front + back
	var uvs := hull + hull
	var indices := Geometry2D.triangulate_polygon(hull)
	var cap := indices.duplicate()
	var count := hull.size()
	for i in range(0, cap.size(), 3):
		indices.append_array(PackedInt32Array([cap[i + 2] + count, cap[i + 1] + count, cap[i] + count]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var sides := PackedInt32Array()
	for i in count:
		var next := (i + 1) % count
		sides.append_array(PackedInt32Array([i, next, next + count, i, next + count, i + count]))
	arrays[Mesh.ARRAY_INDEX] = sides
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	return visual
