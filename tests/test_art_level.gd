extends SceneTree

const ROCK := "res://assets/generated/painted_rock/definition.tres"
const WALL := "res://assets/generated/painted_climb_surface/definition.tres"
const DETAILS := "res://data/details/painted_upright.tres"
const FLAT_DETAILS := "res://data/details/painted_flat.tres"
const Picker := preload("res://addons/terrain_editor/surface_picker.gd")
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	print("ART LEVEL CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func _init() -> void:
	run.call_deferred()

func map_fixture() -> LevelData:
	var data := LevelData.new()
	data.setup_blank(Vector2i(12, 4))
	for y in 4:
		for x in 12:
			data.set_layer(Vector2i(x, y), 0, {"tile_id": "grass"})
	data.spawn_cell = Vector2i(0, 3)
	data.spawn_layer = 0
	return data

func record(data: LevelData, id: String, path: String, cell: Vector2i) -> Dictionary:
	return ObjectRules.anchor_record(data, {"id": id, "definition": path,
		"position": data.world_center(cell), "yaw": 0.0, "scale": 1.0})

func run() -> void:
	var data := map_fixture()
	var root_rock := record(data, "root", ROCK, Vector2i(4, 1))
	data.objects.append(root_rock)
	var upper := ObjectRules.object_anchor(data, record(data, "upper", ROCK, Vector2i(4, 1)),
		"root", root_rock["position"] + Vector3.UP * 2)
	data.objects.append(upper)
	var cliff := Vector2i(1, 1)
	data.set_layer(cliff, 1, {"tile_id": "rock"})
	data.set_layer(cliff, 2, {"tile_id": "rock"})
	var wall := ObjectRules.wall_anchor(data, record(data, "wall", WALL, cliff), cliff, 1, 2)
	data.objects.append(wall)
	var rock_wall := Picker.placement(data, record(data, "rock_wall", WALL, Vector2i(4, 1)),
		{"kind": "object", "id": "root", "position": root_rock["position"] + Vector3(0, 1, 1),
		"normal": Vector3.BACK})
	data.objects.append(rock_wall)
	check(data.validate().is_empty(), "top stack and both wall anchor types validate")
	var bad := upper.duplicate(true)
	bad["position"] += Vector3.RIGHT
	bad["support_offset"] += Vector3.RIGHT
	check(not ObjectRules.validate_record(data, bad, "upper").is_empty(), "overhanging stack rejected")
	bad = root_rock.duplicate(true)
	bad["anchor_kind"] = "object"
	bad["support_id"] = "upper"
	bad["support_offset"] = Vector3.DOWN * 2
	var cycle := data.fork_for_edit()
	cycle.objects[0] = bad
	check(not ObjectRules.validate_all(cycle).is_empty(), "support cycle rejected")
	var hidden_wall := data.fork_for_edit()
	hidden_wall.set_layer(cliff + Vector2i(0, 1), 1, {"tile_id": "grass"})
	check(ObjectRules.validate_all(hidden_wall).is_empty() and ObjectRules.is_hidden(hidden_wall, wall),
		"buried wall remains valid saved data and is hidden by its neighboring block")
	var invalid := data.fork_for_edit()
	invalid.objects.append(invalid.objects[0].duplicate(true))
	invalid.objects[1]["definition"] = "res://missing_object_definition.tres"
	var invalid_errors := ObjectRules.validate_all(invalid)
	check(invalid_errors.has("物件 ID 为空或重复")
		and invalid_errors.has("物件 upper：物件定义缺失"),
		"batch validation still reports duplicate IDs and missing definitions")
	check(ObjectRules.validate_all(data).is_empty(),
		"validation does not retain errors from another map")

	var center := data.world_center(Vector2i(7, 2))
	var scattered := DetailRules.scatter(data, DETAILS, center, 1.4, 20, 314, "stroke")
	check(not scattered.is_empty() and scattered == DetailRules.scatter(
		data, DETAILS, center, 1.4, 20, 314, "stroke"), "scatter is reproducible including IDs and transforms")
	var one_cell := LevelData.new()
	one_cell.setup_blank(Vector2i(3, 3))
	var one_cell_center := Vector2i(1, 1)
	one_cell.set_layer(one_cell_center, 0, {"tile_id": "grass"})
	var fitted := DetailRules.scatter(one_cell, FLAT_DETAILS,
		one_cell.world_center(one_cell_center), 1.5, 12, 90210, "large", 0, 1.0)
	var fitted_valid := not fitted.is_empty()
	for item in fitted:
		fitted_valid = fitted_valid and DetailRules.validate_record(one_cell, item).is_empty()
	check(fitted_valid,
		"large ground detail finds complete support instead of disappearing")
	check(DetailRules.scatter(one_cell, FLAT_DETAILS,
		one_cell.world_center(one_cell_center), 1.5, 12, 90210,
		"too_large", 0, 1.5).is_empty(),
		"ground detail still rejects a size that has no complete terrain support")
	data.details = scattered
	check(DetailRules.validate_all(data).is_empty(), "scatter rests on true terrain tops")
	var snapshot := data.clone_data()
	var candidate := data.fork_for_edit()
	candidate.details[0]["position"] += Vector3.UP
	check(data.clone_data() == snapshot, "candidate details are isolated from original")
	candidate = data.fork_for_edit()
	candidate.set_layer(Vector2i(4, 1), 1, {"tile_id": "sand"})
	ObjectRules.move_top_anchors(candidate, Vector2i(4, 1), 0, 1)
	check(candidate.objects[0]["position"].y == 4 and candidate.objects[1]["position"].y == 6 \
		and ObjectRules.find_record(candidate, "rock_wall")["position"].y == 4 \
		and ObjectRules.find_record(candidate, "wall")["position"] == wall["position"] \
		and candidate.validate().is_empty(), "raising terrain moves stack and host wall but preserves terrain wall layer")
	ObjectRules.remove_terrain_support(candidate, Vector2i(4, 1), 1)
	check(candidate.objects.size() == 1 and candidate.objects[0]["id"] == "wall",
		"removing support cascades through stacked objects and host attachments")
	candidate.restore_data(snapshot)
	check(candidate.clone_data() == snapshot, "snapshot restoration recovers complete support graph and details")
	var v6 := snapshot.duplicate(true)
	v6["format_version"] = 6
	v6.erase("details")
	candidate.restore_data(v6)
	check(candidate.objects[0]["position"] == root_rock["position"] \
		and candidate.details.is_empty() and candidate.format_version == LevelData.FORMAT_VERSION,
		"v6 migration adds empty details without lifting already migrated terrain")
	var output := "user://art_level_roundtrip.tres"
	check(ResourceSaver.save(data, output) == OK, "v7 map saves")
	var loaded := ResourceLoader.load(output, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(same_saved_values(loaded.clone_data(), snapshot),
		"v7 reload preserves IDs and transforms within 0.01mm text precision")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(output))

	# Reverse object storage order to prove prefab graph remapping is order independent.
	var reversed := data.fork_for_edit()
	reversed.objects.reverse()
	var capture := LevelPrefab.capture(reversed, reversed.map_bounds())
	check(capture["error"].is_empty(), "prefab captures layers, wall anchors, support graph and details")
	var prefab: LevelPrefab = capture["prefab"]
	var destination := LevelData.new()
	destination.setup_blank(Vector2i(18, 18))
	for turns in 4:
		var result := prefab.stamp(destination, Vector2i(2, 2), turns)
		if turns > 0:
			check(not result["error"].is_empty(),
				"fixed-camera wall attachment rejects prefab rotation %d" % turns)
			continue
		check(result["error"].is_empty(), "authored prefab direction remains valid")
		if not result["error"].is_empty():
			continue
		var stamped := LevelData.new()
		stamped.restore_data(result["snapshot"])
		var relation_count := 0
		for item in stamped.objects:
			if item.has("support_id"):
				relation_count += 1
				check(not ObjectRules.find_record(stamped, item["support_id"]).is_empty()
					and item["support_id"] != "root", "prefab remaps host IDs")
		check(relation_count == 2 and stamped.details.size() == data.details.size(),
			"prefab retains all attachments and details")
	await check_render_and_pick(data)
	print("ART LEVEL TEST FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func check_render_and_pick(data: LevelData) -> void:
	# Put one detail into a remote chunk and verify that local changes preserve it.
	data.details.append(DetailRules.make_record(data, DETAILS, "detail_07",
		data.world_center(Vector2i(10, 1)), "remote"))
	var builder := TerrainBuilder.new()
	builder.show_grid = false
	builder.level_data = data
	root.add_child(builder)
	var renderer := builder.detail_renderer
	var remote_id := 0
	var remote_key := ""
	for key: String in renderer.groups:
		if key.begins_with("1,0|"):
			remote_key = key
			remote_id = renderer.groups[key].get_instance_id()
	check(renderer.find_children("*", "CollisionObject3D", true, false).is_empty(),
		"detail batches never create collision")
	data.details.append(DetailRules.make_record(data, DETAILS, "detail_12",
		data.world_center(Vector2i(2, 2)), "local"))
	builder.rebuild_details()
	check(renderer.groups[remote_key].get_instance_id() == remote_id,
		"detail brush preserves untouched chunk nodes")
	var transforms := {}
	for key: String in renderer.groups:
		transforms[key] = renderer.groups[key].multimesh.buffer
	builder.rebuild()
	var matches := true
	for key: String in builder.detail_renderer.groups:
		matches = matches and transforms[key] == builder.detail_renderer.groups[key].multimesh.buffer
	check(matches, "full rebuild reproduces every detail instance and atlas UV")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8
	var cliff := Vector2i(1, 1)
	var target := data.world_center(cliff, 1)
	camera.position = target + Vector3.UP * 10
	camera.look_at(target, Vector3.FORWARD)
	builder.set_slice_layer(1)
	await physics_frame
	await physics_frame
	var hit := Picker.pick(builder, camera, camera.unproject_position(target))
	check(hit.has("error") and str(hit["error"]).contains("切片"),
		"temporary slice caps cannot become object or detail supports")
	builder.set_slice_layer(-1)
	await physics_frame
	await physics_frame
	hit = Picker.pick(builder, camera, camera.unproject_position(data.world_center(cliff)))
	check(hit.get("kind") == "terrain" and hit.get("layer") == 2,
		"real top surface becomes pickable after leaving slice")
	builder.free()
	camera.free()

func same_saved_values(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is float:
		return absf(a - b) < 0.00001
	if a is Vector3:
		return a.distance_to(b) < 0.00001
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not same_saved_values(a[key], b[key]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not same_saved_values(a[i], b[i]):
				return false
		return true
	return a == b
