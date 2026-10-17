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
	_check_all_transition_shapes(style)
	_check_resources()
	_check_tint_roundtrip()
	_check_multi_blend(style)
	_check_render_structure(style)
	_check_stacked_columns()
	_check_stair_geometry()
	print("P0 TERRAIN TEST FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func _check_topology(style: TerrainStyleProfile) -> void:
	var canonical := {}
	for bits in 256:
		canonical[TerrainTopology.normalize_bits(bits)] = true
	check(canonical.size() == 47, "256 neighbor states normalize to 47 masks")
	check(not DirAccess.dir_exists_absolute(
		"res://assets/source_art/terrain_handoff_v02/masks/regular"),
		"removed mask directory is absent")
	var cell := Vector2i(7, 11)
	for bits: int in canonical:
		var info := TerrainTopology.mask_info(bits, cell, style)
		var image := TerrainTopology.mask_image(info)
		var sources_valid := true
		for part: Dictionary in info["parts"]:
			sources_valid = sources_valid and str(part["path"]).begins_with(
				style.irregular_mask_directory + "/") and ResourceLoader.exists(part["path"])
		check(image != null and image.get_pixel(128, 128).r > 0.99
			and sources_valid and (bits == 255 or not info["parts"].is_empty()),
			"irregular sources cover topology %03d and retain its center" % bits)
		# Connected sides retain coverage; missing sides cut into the cell.
		var side_centers := [Vector2i(128, 3), Vector2i(252, 128),
			Vector2i(128, 252), Vector2i(3, 128)]
		var edges_valid := true
		for direction in 4:
			var point: Vector2i = side_centers[direction]
			var expected := 1.0 if (bits & (1 << direction)) != 0 else 0.0
			edges_valid = edges_valid and absf(image.get_pixelv(point).r - expected) < 0.01
		check(edges_valid, "mask respects all four neighbor sides %03d" % bits)
		check(TerrainTopology.mask_texture(info) == TerrainTopology.mask_texture(info)
			and TerrainTopology.mask_image(info) == image,
			"cached masks are reused %03d" % bits)
	for canonical_bits in [110, 76, 239]:
		for turns in 4:
			var rotated := TerrainTopology.rotate_bits_clockwise(canonical_bits, turns)
			var info := TerrainTopology.mask_info(rotated, cell, style)
			var source := (load(info["path"]) as Texture2D).get_image()
			if source.is_compressed():
				source.decompress()
			source.clear_mipmaps()
			source.convert(Image.FORMAT_R8)
			for turn in turns:
				source.rotate_90(CLOCKWISE)
			check(TerrainTopology.mask_image(info).get_data() == source.get_data(),
				"painted canonical shape is preserved at rotation %03d/%d" % [canonical_bits, turns])
	var first := TerrainTopology.mask_info(0, Vector2i(3, 5), style)
	var second := TerrainTopology.mask_info(0, Vector2i(3, 5), style)
	check(first["variant"] == second["variant"] and first["key"] == second["key"],
		"irregular variant is stable")
	check(TerrainTopology.full_texture().get_image().get_pixel(0, 0).r == 1.0,
		"ordinary tops and slice caps use generated white coverage")
	var variant_cells := {}
	for x in 12:
		var candidate := Vector2i(x, 5)
		variant_cells[TerrainTopology.stable_variant(candidate, style.irregular_seed)] = candidate
	var variants := {}
	for variant: int in variant_cells:
		var info := TerrainTopology.mask_info(0, variant_cells[variant], style)
		variants[TerrainTopology.mask_image(info).get_data().hex_encode().sha256_text()] = true
	check(variants.size() == 3, "composite masks preserve three distinct painted variants")

func _check_all_transition_shapes(style: TerrainStyleProfile) -> void:
	var shapes := {}
	for bits in 256:
		shapes[TerrainTopology.normalize_bits(bits)] = true
	var changed_cell := Vector2i(1, 1)
	for bits: int in shapes:
		var data := LevelData.new()
		data.setup_blank(Vector2i(3, 3))
		for y in 3:
			for x in 3:
				data.set_layer(Vector2i(x, y), 0, {"tile_id": "sand"})
		data.set_layer(changed_cell, 0, {"tile_id": "grass"})
		for i in TerrainTopology.BITS.size():
			if (bits & TerrainTopology.BITS[i]) != 0:
				data.set_layer(changed_cell + TerrainTopology.VECTORS[i], 0, {"tile_id": "grass"})
		var blend := TerrainBlendMapClass.build(data, 0, style)
		var weights: Image = blend["weight_image"]
		var indices: Image = blend["index_image"]
		var grass_page: int = blend["page_by_id"]["grass"]
		var has_both := false
		var normalized := true
		var retains_center := false
		var size: int = blend["pixels_per_cell"]
		for y in size:
			for x in size:
				var w := weights.get_pixel(size + x, size + y)
				var pages := indices.get_pixel(size + x, size + y)
				normalized = normalized and absf(w.r + w.g + w.b + w.a - 1.0) < 0.015
				has_both = has_both or (w.r > 0.01 and w.g > 0.01)
				if x == size / 2 and y == size / 2:
					retains_center = roundi(pages.r * 255) == grass_page and w.r > 0.99
		check(normalized and retains_center and (has_both or bits == 255),
			"actual blend has irregular transition and normalized weights %03d" % bits)
		var dirty: Array[Vector2i] = [changed_cell]
		data.set_layer(changed_cell, 0, {"tile_id": "sand"})
		TerrainBlendMapClass.update(blend, data, 0, style, dirty)
		var rebuilt := TerrainBlendMapClass.build(data, 0, style)
		check(weights.get_data() == (rebuilt["weight_image"] as Image).get_data()
			and indices.get_data() == (rebuilt["index_image"] as Image).get_data(),
			"incremental transition matches rebuild %03d" % bits)

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
	data.setup_blank(Vector2i(8, 4))
	var custom_ids := [
		"ground_forest", "ground_stone", "sand", "rock"]
	var builtin_ids := ["grass", "rock", "sand", "water"]
	for y in data.map_size.y:
		for x in data.map_size.x:
			var local_x := x % 4
			var quadrant := (1 if local_x >= 2 else 0) + (2 if y >= 2 else 0)
			var tile_id: String = (
				custom_ids[quadrant] if x < 4 else builtin_ids[quadrant])
			data.set_cell(Vector2i(x, y), {
				"exists": true,
				"terrain": 0,
				"tile_id": tile_id,
				"height": 0,
			})
	var blend := TerrainBlendMapClass.build(data, 0, style)
	var weight_image: Image = blend["weight_image"]
	var index_image: Image = blend["index_image"]
	var pixels_per_cell: int = blend["pixels_per_cell"]
	var junction := Vector2i(2, 2) * pixels_per_cell
	var max_active_channels := 0
	var normalized := true
	var active_custom_ids := {}
	for y in range(junction.y - 2, junction.y + 2):
		for x in range(junction.x - 2, junction.x + 2):
			var weights := weight_image.get_pixel(x, y)
			var indices := index_image.get_pixel(x, y)
			var total := weights.r + weights.g + weights.b + weights.a
			normalized = normalized and absf(total - 1.0) < 0.025
			var active := 0
			var channels := [weights.r, weights.g, weights.b, weights.a]
			var pages := [indices.r, indices.g, indices.b, indices.a]
			for channel in 4:
				var weight: float = channels[channel]
				if weight > 0.02:
					active += 1
					var page := roundi(float(pages[channel]) * 255.0)
					active_custom_ids[blend["terrain_ids"][page]] = true
			max_active_channels = maxi(max_active_channels, active)
	check(normalized, "multi-terrain weights stay normalized")
	check(max_active_channels >= 3,
		"three or more terrain channels survive at a junction")
	check(active_custom_ids.size() >= 3,
		"top-only custom terrains survive together at a junction")
	check(blend["terrain_ids"].size() >= 8,
		"one texture array supports more than four terrains globally")
	for tile_id in custom_ids + builtin_ids:
		check(blend["terrain_ids"].has(tile_id),
			"dynamic texture array contains " + tile_id)
	var builder := TerrainBuilder.new()
	builder.level_data = data
	builder.show_grid = false
	builder.build_collision = false
	root.add_child(builder)
	builder.rebuild()
	var top := _top_visual(builder, Vector2i(1, 1))
	var material := top.material_override as ShaderMaterial
	check(top.get_meta("multi_blend", false)
		and material.get_shader_parameter("blend_indices") is Texture2D
		and material.get_shader_parameter("blend_weights") is Texture2D,
		"dynamic terrain layer receives index and weight maps")
	check(material.get_shader_parameter("terrain_art") is Texture2DArray,
		"multi-blend shader receives a terrain texture array")
	data.set_layer(Vector2i(1, 1), 0, {
		"tile_id": data.solid_tile_id(Vector2i(1, 1)),
		"rotation": 3,
	})
	var dirty: Array[Vector2i] = [Vector2i(1, 1)]
	check(builder.refresh_blend_cells(dirty),
		"flat terrain edit refreshes the existing blend resource")
	var rotations: Image = builder._blend_resources[Vector3i.ZERO]["rotation_image"]
	check(rotations.get_pixel(1, 1).r > 0.99,
		"dynamic blend preserves per-cell art rotation")
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
	var terrain_ids: PackedStringArray = grass_top.get_meta("terrain_tiles")
	var grass_page := terrain_ids.find("grass")
	var settings := (
		top_material.get_shader_parameter("terrain_settings") as Texture2D).get_image()
	var tint_lookup := (
		top_material.get_shader_parameter("terrain_tints") as Texture2D).get_image()
	var settings_pixel := settings.get_pixel(grass_page, 0)
	var tint_pixel := tint_lookup.get_pixel(grass_page, 0)
	check(top_material != null
		and is_equal_approx(settings_pixel.r, 8.0)
		and is_equal_approx(settings_pixel.g, 8.0)
		and absf(tint_pixel.r - tint.r) < 0.015
		and absf(tint_pixel.g - tint.g) < 0.015
		and absf(tint_pixel.b - tint.b) < 0.015
		and absf(tint_pixel.a - tint.a) < 0.015,
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
	var water_sides := water_builder.generated.find_children(
		"Side", "MeshInstance3D", false, false)
	var no_vertical_water := true
	for side in water_sides:
		no_vertical_water = no_vertical_water \
			and side.get_meta("terrain_tile", "") != "water"
	check(no_vertical_water,
		"liquid never creates a vertical water wall")
	builder.queue_free()
	water_builder.queue_free()

func _check_stacked_columns() -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i.ONE)
	var cell := Vector2i.ZERO
	data.set_layer(cell, 0, {"tile_id": "grass"})
	data.set_layer(cell, 1, {"tile_id": "rock"})
	data.set_layer(cell, 2, {"tile_id": "sand"})
	var builder := TerrainBuilder.new()
	builder.level_data = data
	builder.show_grid = false
	builder.build_collision = true
	root.add_child(builder)
	builder.rebuild()
	var sides: Array[MeshInstance3D] = []
	for child in builder.generated.get_children():
		if child is MeshInstance3D and child.get_meta("terrain_side", false):
			sides.append(child)
	var layer_tiles := {}
	var ranges_valid := true
	for side in sides:
		var layer := int(side.get_meta("terrain_layer", -1))
		layer_tiles[layer] = side.get_meta("terrain_tile", "")
		var bounds := (side as MeshInstance3D).mesh.get_aabb()
		ranges_valid = ranges_valid \
			and bounds.position.y >= layer * LevelData.ELEVATION_STEP - 0.01 \
			and bounds.end.y <= data.surface_y(layer) + 0.01
	check(layer_tiles == {0: "grass", 1: "rock", 2: "sand"}
		and ranges_valid,
		"each exposed solid layer builds only its own 2m side segment")
	var top := _top_visual(builder, cell)
	check(top != null and top.mesh.get_aabb().position.y > 5.9
		and builder.generated.find_children(
			"TerrainTop_*", "MeshInstance3D", false, false).size() == 1,
		"stack builds only the highest top surface")
	var collision_layers := {}
	for collision in builder.generated.get_children():
		if collision is StaticBody3D and collision.has_meta("terrain_layer"):
			collision_layers[int(
				collision.get_meta("terrain_layer", -1))] = true
	check(collision_layers.has(0) and collision_layers.has(1)
		and collision_layers.has(2),
		"stacked side collisions preserve layer metadata")
	data.set_layer(cell, 1, {"tile_id": "ground_stone"})
	builder.rebuild()
	var replaced := {}
	for side in builder.generated.get_children():
		if side is MeshInstance3D and side.get_meta("terrain_side", false):
			replaced[int(side.get_meta("terrain_layer", -1))] = \
				side.get_meta("terrain_tile", "")
	check(replaced == {0: "grass", 1: "ground_stone", 2: "sand"},
		"middle replacement changes only the exposed middle side material")
	builder.queue_free()

func _check_stair_geometry() -> void:
	for direction in 4:
		var data := LevelData.new()
		data.setup_blank(Vector2i(5, 5))
		var low := Vector2i(2, 2)
		var high: Vector2i = low + LevelData.DIRS[direction]
		var lateral: Vector2i = low + LevelData.DIRS[(direction + 1) % 4]
		for cell in [low, high, lateral]:
			data.set_cell(cell, {
				"exists": true,
				"terrain": 0,
				"tile_id": "grass",
				"height": 1 if cell == high else 0,
				"rotation": 0,
			})
		data.stairs.append({"cell": low, "direction": direction})
		var builder := TerrainBuilder.new()
		builder.level_data = data
		builder.show_grid = false
		builder.build_collision = true
		root.add_child(builder)
		builder.rebuild()
		var steps: Array[MeshInstance3D] = []
		for node in builder.generated.get_children():
			if node is MeshInstance3D and node.has_meta("stair_step"):
				steps.append(node)
		steps.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D):
			return int(a.get_meta("stair_step")) < int(b.get_meta("stair_step")))
		var run := Vector3(
			LevelData.DIRS[direction].x, 0.0, LevelData.DIRS[direction].y)
		var low_center := data.world_center(low)
		var minimum := INF
		var maximum := -INF
		var rising := steps.size() == 10
		var previous_top := -INF
		for step in steps:
			var box := step.mesh as BoxMesh
			var half_length := (
				box.size.z if direction % 2 == 0 else box.size.x) * 0.5
			var along := (step.position - low_center).dot(run)
			minimum = minf(minimum, along - half_length)
			maximum = maxf(maximum, along + half_length)
			var top := step.position.y + box.size.y * 0.5
			rising = rising and top > previous_top
			previous_top = top
		check(steps.size() == 10 and absf(minimum + 1.0) < 0.01
			and absf(maximum - 3.0) < 0.01 and rising
			and absf(previous_top
				- (low_center.y + LevelData.ELEVATION_STEP)) < 0.01,
			"stair spans two full cells and rises in direction %d" % direction)
		var ramps := builder.generated.find_children(
			"StairRamp", "StaticBody3D", false, false)
		var ramp := ramps[0] as StaticBody3D if not ramps.is_empty() else null
		check(ramp != null and ramp.get_meta("terrain_cell") == low,
			"stair ramp is pickable from low cell direction %d" % direction)
		var lateral_bits := TerrainTopology.silhouette_bits(data, lateral)
		var toward_stair := TerrainTopology.VECTORS.find(low - lateral)
		check(toward_stair >= 0
			and (lateral_bits & TerrainTopology.BITS[toward_stair]) != 0,
			"stair footprint supports neighboring silhouette direction %d" % direction)
		builder.queue_free()

func _top_visual(builder: TerrainBuilder, cell: Vector2i) -> MeshInstance3D:
	for child in builder.generated.get_children():
		if child is MeshInstance3D and cell in child.get_meta("terrain_cells", []):
			return child
	return null
