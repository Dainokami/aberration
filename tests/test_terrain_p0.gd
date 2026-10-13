extends SceneTree

const TerrainBlendMapClass := preload("res://scripts/level/terrain_blend_map.gd")

var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	print("P0 CHECK ", label, " ", condition)
	if not condition:
		failures.append(label)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var style := load("res://data/terrain_style_profile.tres") as TerrainStyleProfile
	check(style != null, "style profile loads")
	_check_topology(style)
	_check_resources()
	_check_tint_roundtrip()
	_check_multi_blend(style)
	_check_render_structure(style)
	print("P0 TERRAIN TEST FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func _check_topology(style: TerrainStyleProfile) -> void:
	var canonical := {}
	for bits in 256:
		canonical[TerrainTopology.normalize_bits(bits)] = true
	check(canonical.size() == 47, "256 neighbor states normalize to 47 masks")
	for bits: int in canonical:
		check(ResourceLoader.exists(style.regular_mask_path(bits)),
			"regular mask exists %03d" % bits)
	for canonical_bits in [110, 76, 239]:
		for turns in 4:
			var rotated := TerrainTopology.rotate_bits_clockwise(canonical_bits, turns)
			var info := TerrainTopology.mask_info(rotated, Vector2i(7, 11), style, true)
			check(not info["fallback"] and ResourceLoader.exists(info["path"]),
				"irregular topology %03d rotation %d" % [canonical_bits, turns])
	var first := TerrainTopology.mask_info(110, Vector2i(3, 5), style, true)
	var second := TerrainTopology.mask_info(110, Vector2i(3, 5), style, true)
	check(first["variant"] == second["variant"] and first["path"] == second["path"],
		"irregular variant is stable")

func _check_resources() -> void:
	for tile_id in ["grass", "rock", "sand", "water"]:
		var tile := TileRegistry.find(tile_id)
		check(tile != null and ResourceLoader.exists(tile.texture_path),
			"handoff top texture loads " + tile_id)
		if tile_id != "water":
			check(ResourceLoader.exists(tile.cliff_texture_path)
				and ResourceLoader.exists(tile.rim_texture_path)
				and tile.has_soft_rim(), "soft cliff resources load " + tile_id)
	var water := TileRegistry.find("water")
	check(water.is_water() and ResourceLoader.exists(water.foam_texture_path),
		"water uses dedicated foam without cliff")

func _check_tint_roundtrip() -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(2, 2))
	var tint := Color("#78a8c0")
	tint.a = 0.6
	data.set_terrain_tint("grass", tint)
	var snapshot := data.clone_data()
	var restored := LevelData.new()
	restored.restore_data(snapshot)
	check(restored.terrain_tint("grass").is_equal_approx(tint),
		"terrain tint survives snapshots")
	var path := "res://data/levels/test_p0_tint.tres"
	check(ResourceSaver.save(restored, path) == OK, "terrain tint saves")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded != null and loaded.terrain_tint("grass").is_equal_approx(tint),
		"terrain tint reloads")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check_multi_blend(style: TerrainStyleProfile) -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(4, 4))
	for y in data.map_size.y:
		for x in data.map_size.x:
			var tile_id := "grass"
			if x >= 2 and y < 2:
				tile_id = "rock"
			elif x < 2 and y >= 2:
				tile_id = "sand"
			elif x >= 2 and y >= 2:
				tile_id = "water"
			data.set_cell(Vector2i(x, y), {
				"exists": true,
				"terrain": 0,
				"tile_id": tile_id,
				"height": 0,
			})
	var blend := TerrainBlendMapClass.build(data, 0, style)
	var image: Image = blend["image"]
	var pixels_per_cell: int = blend["pixels_per_cell"]
	var junction := Vector2i(2, 2) * pixels_per_cell
	var max_active_channels := 0
	var normalized := true
	for y in range(junction.y - 2, junction.y + 2):
		for x in range(junction.x - 2, junction.x + 2):
			var weights := image.get_pixel(x, y)
			var total := weights.r + weights.g + weights.b + weights.a
			normalized = normalized and absf(total - 1.0) < 0.025
			var active := 0
			for weight in [weights.r, weights.g, weights.b, weights.a]:
				if weight > 0.02:
					active += 1
			max_active_channels = maxi(max_active_channels, active)
	check(normalized, "multi-terrain weights stay normalized")
	check(max_active_channels >= 3,
		"three or more terrain channels survive at a junction")
	var builder := TerrainBuilder.new()
	builder.level_data = data
	builder.show_grid = false
	builder.build_collision = false
	root.add_child(builder)
	builder.rebuild()
	var top := _top_visual(builder, Vector2i(1, 1))
	var material := top.material_override as ShaderMaterial
	check(top.get_meta("multi_blend", false)
		and material.get_shader_parameter("blend_weights") is Texture2D,
		"built-in terrain layer uses one multi-blend weight map")
	check(material.get_shader_parameter("terrain0_art") is Texture2D
		and material.get_shader_parameter("terrain1_art") is Texture2D
		and material.get_shader_parameter("terrain2_art") is Texture2D
		and material.get_shader_parameter("terrain3_art") is Texture2D,
		"multi-blend shader receives all four terrain textures")
	builder.queue_free()

func _check_render_structure(style: TerrainStyleProfile) -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(6, 6))
	for y in range(1, 5):
		for x in range(1, 5):
			data.set_cell(Vector2i(x, y), {
				"exists": true, "terrain": 0, "tile_id": "water", "height": 0})
	for y in range(1, 4):
		for x in range(1, 5):
			data.set_cell(Vector2i(x, y), {
				"exists": true, "terrain": 0, "tile_id": "grass", "height": 2})
	data.set_cell(Vector2i(2, 1), {
		"exists": true, "terrain": 0, "tile_id": "sand", "height": 2})
	var tint := Color("#7aa594")
	tint.a = 0.45
	data.set_terrain_tint("grass", tint)
	var builder := TerrainBuilder.new()
	builder.level_data = data
	builder.show_grid = false
	builder.build_collision = false
	root.add_child(builder)
	builder.rebuild()
	var sides := builder.generated.find_children("Side", "MeshInstance3D", false, false)
	var rims := builder.generated.find_children("Rim", "MeshInstance3D", false, false)
	var foam := builder.generated.find_children("ShoreFoam", "MeshInstance3D", false, false)
	check(not sides.is_empty(), "height differences build continuous cliff meshes")
	check(not rims.is_empty(), "land cliffs build soft rim meshes")
	check(rims.size() < sides.size() * 2, "4m cliffs do not duplicate a middle rim")
	check(not foam.is_empty(), "land-water boundaries build shoreline foam")
	for node in sides + rims + foam:
		var mesh_instance := node as MeshInstance3D
		check(mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0,
			"generated edge mesh is non-empty " + node.name)
	var grass_top := _top_visual(builder, Vector2i(1, 1))
	var top_material := grass_top.material_override as ShaderMaterial
	check(top_material != null
		and top_material.get_shader_parameter("terrain0_span") == Vector2(8, 8)
		and top_material.get_shader_parameter("terrain0_tint").is_equal_approx(tint),
		"top material uses continuous 8m sampling and map tint")
	var water_only := LevelData.new()
	water_only.setup_blank(Vector2i(1, 1))
	water_only.set_cell(Vector2i.ZERO, {
		"exists": true, "terrain": 0, "tile_id": "water", "height": 0})
	var water_builder := TerrainBuilder.new()
	water_builder.level_data = water_only
	water_builder.show_grid = false
	water_builder.build_collision = false
	root.add_child(water_builder)
	water_builder.rebuild()
	check(water_builder.generated.find_children(
		"Side", "MeshInstance3D", false, false).is_empty(),
		"water never creates a vertical water wall")
	builder.queue_free()
	water_builder.queue_free()

func _top_visual(builder: TerrainBuilder, cell: Vector2i) -> MeshInstance3D:
	for child in builder.generated.get_children():
		if child is MeshInstance3D and cell in child.get_meta("terrain_cells", []):
			return child
	return null
