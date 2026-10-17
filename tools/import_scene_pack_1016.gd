extends SceneTree

const MANIFEST := "res://assets/derived_art/scene_pack_20261016/manifest.json"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var errors: Array[String] = []
	for entry: Dictionary in manifest.entries:
		var d := PlaceableDefinition.new()
		d.asset_id = entry.id
		d.display_name = entry.display_name
		d.category = entry.category
		d.source_image = entry.image
		d.source_manifest = MANIFEST
		d.preparation = entry
		d.profile = load("res://data/art_profile.tres")
		d.generator_version = 4
		d.image_size = Vector2(entry.image_size_m[0], entry.image_size_m[1])
		d.pivot = Vector2(entry.pivot[0], entry.pivot[1])
		d.cell_size = Vector3(entry.cell_size_m[0], entry.cell_size_m[1], entry.cell_size_m[2])
		d.volume_size = Vector3(d.image_size.x, d.cell_size.y, entry.layout[1] * 2)
		d.collision_size = Vector3(entry.layout[0] * 2, d.cell_size.y, entry.layout[1] * 2)
		d.collision_offset = Vector3((entry.layout[0] - 1), 0, (entry.layout[1] - 1))
		d.mechanism = entry.kind
		d.ecosystems = PackedStringArray(entry.ecosystems)
		d.requires_seabed = entry.requires_seabed
		d.mechanism_parameters = entry.parameters
		for point: Array in entry.spatial_cells_m:
			d.spatial_cells.append(Vector3(point[0], point[1], point[2]))
		if entry.solid_collision:
			d.collision = PlaceableDefinition.Collision.BOX
		if d.mechanism == "quicksand":
			d.carrier = PlaceableDefinition.Carrier.GROUND
			d.pivot = Vector2(0.5, 0.5)
			d.fade_when_occluding = false
		if d.mechanism == "vine":
			d.carrier = PlaceableDefinition.Carrier.WALL
			d.behaviour = PlaceableDefinition.Behaviour.CLIMBABLE
			d.collision_size = Vector3(2, 2, 0.16)
			d.fade_when_occluding = false
		if d.mechanism == "chest":
			d.behaviour = PlaceableDefinition.Behaviour.CHEST
			d.fade_when_occluding = false
		var folder := "res://assets/generated/" + d.asset_id
		if DirAccess.dir_exists_absolute(folder):
			var existing := load(folder.path_join("definition.tres")) as PlaceableDefinition
			if existing == null or existing.source_manifest != MANIFEST:
				errors.append("资源 ID 冲突：" + d.asset_id)
			elif "--refresh-scene1016" in OS.get_cmdline_user_args():
				d.scene_path = existing.scene_path
				d.thumbnail_path = existing.thumbnail_path
				var node := AssetFactory.make_asset(d)
				var packed := PackedScene.new()
				var result := packed.pack(node)
				node.free()
				if result == OK:
					result = ResourceSaver.save(packed, d.scene_path)
				if result == OK:
					result = ResourceSaver.save(d, folder.path_join("definition.tres"))
				if result != OK:
					errors.append(d.asset_id + ": " + error_string(result))
			continue
		var error := AssetFactory.generate(d, folder)
		if not error.is_empty():
			errors.append(d.asset_id + "：" + error)
	print("SCENE1016 IMPORT ERRORS: ", errors)
	quit(0 if errors.is_empty() else 1)
