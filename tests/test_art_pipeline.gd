extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	print("ART CHECK ", condition, " ", label)
	if not condition:
		failures.append(label)

func _run() -> void:
	var path := "res://assets/derived_art/scene_pack_20261014/manifest.json"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(manifest["entries"].size() == 79, "manifest records all 79 archive images")
	# Original archive art stays local (gitignored); verify hashes only where it exists.
	var source_root := "res://assets/source_art/scene_pack_20261014/"
	if DirAccess.dir_exists_absolute(source_root):
		var hashes_match := true
		for entry: Dictionary in manifest["entries"]:
			hashes_match = hashes_match and FileAccess.get_sha256(
				source_root + str(entry["source"])) == entry["sha256"]
		check(hashes_match, "all 79 source files retain their archive hashes")
	else:
		print("ART CHECK skipped source hash check: original archive art is not in this checkout")
	for set_path in DetailSet.library():
		var detail := load(set_path) as DetailSet
		check(detail != null and detail.validate_asset().is_empty(), "valid detail atlas " + set_path)
		var overlap := false
		for i in detail.variants.size():
			for j in range(i + 1, detail.variants.size()):
				overlap = overlap or (detail.variants[i]["rect"] as Rect2i).intersects(detail.variants[j]["rect"])
		check(not overlap, "detail atlas regions never overlap")
	var modules: Dictionary = manifest["modules"]
	var body: Array = modules["cliff_body"]["span_m"]
	for id in ["painted_grass", "painted_meadow", "painted_earth"]:
		var tile := TileRegistry.find(id)
		# Painted courses keep their measured 256 px/m proportion instead of 4 × 2m stretching.
		check(tile != null and tile.world_space_top and tile.top_texture_span_m == Vector2(8, 8)
			and tile.cliff_texture_span_m.is_equal_approx(Vector2(body[0], body[1]))
			and tile.cliff_course_repeat, "terrain art dimensions " + id)
	var grass_tile := TileRegistry.find("painted_grass")
	var rim_material := TerrainMaterials.rim_material(grass_tile, grass_tile.tint_default())
	check(grass_tile.rim_cutout and grass_tile.has_soft_rim()
		and rim_material.shader.code.contains("ALPHA_SCISSOR_THRESHOLD")
		and is_equal_approx(grass_tile.rim_u_span_m, float(modules["rim_grass"]["span_m"])),
		"grass fringe is an alpha-tested cut-out at painted scale")
	check(not TileRegistry.find("painted_earth").has_soft_rim(), "bare earth has no grass fringe")
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	image.fill_rect(Rect2i(2, 2, 8, 8), Color("#80582c"))
	image.set_pixel(6, 6, Color.BLACK)
	var prepared := ArtPreparation.process(image, {"black_background": true, "trim": false})
	var output: Image = prepared["image"]
	check(output.get_pixel(0, 0).a == 0 and output.get_pixel(6, 6).a == 1
		and output.get_pixel(2, 2).is_equal_approx(image.get_pixel(2, 2)),
		"background preparation preserves enclosed black linework and source colours")
	check(image.get_pixel(0, 0).a == 1, "preparation leaves input image untouched")
	var rock := _prop("painted_rock")
	check(rock.get_node("Art").get_child_count() == 6, "rock scene contains six real textured faces")
	check((rock.get_node("ProxyCollision").get_child(0).shape as BoxShape3D).size == Vector3.ONE * 2,
		"rock collision is exactly one 2m cube")
	var chest := _prop("painted_treasurebox")
	await process_frame
	check(chest.has_method("interact") and chest.get_node("State_closed").visible
		and not chest.get_node("State_open").visible, "saved scene retains gameplay script and initial closed state")
	var chest_definition := load("res://assets/generated/painted_treasurebox/definition.tres") as PlaceableDefinition
	var before := FileAccess.get_sha256(chest_definition.resource_path)
	check(chest.interact(null) and not chest.get_node("State_closed").visible
		and chest.get_node("State_open").visible, "interacting changes the actual chest visual")
	check(not chest.interact(null), "chest cannot open twice")
	check(FileAccess.get_sha256(chest_definition.resource_path) == before, "runtime state cannot mutate asset file")
	var decayed := _prop("painted_decayrock")
	await process_frame
	check(not rock.apply_damage(99), "ordinary rock is indestructible")
	check(decayed.apply_damage(1) and decayed.state != "broken", "weathered rock tracks damage")
	check(decayed.apply_damage(99) and decayed.state == "broken" and not decayed.get_node("Art").visible,
		"weathered rock destruction removes its visual")
	await physics_frame
	check(decayed.get_node("ProxyCollision").get_child(0).disabled, "destroyed rock releases collision")
	print("ART PIPELINE TEST FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func _prop(id: String) -> Node3D:
	var definition := load("res://assets/generated/" + id + "/definition.tres") as PlaceableDefinition
	check(definition != null and definition.validate_asset().is_empty(), "valid definition " + id)
	var prop := AssetFactory.instantiate_asset(definition)
	root.add_child(prop)
	return prop
