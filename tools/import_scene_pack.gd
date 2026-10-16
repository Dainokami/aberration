extends SceneTree

const PACK := "scene_pack_20261014"
const ROOT := "res://assets/derived_art/" + PACK + "/"
var manifest: Dictionary
var entries: Dictionary = {}
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	for entry: Dictionary in manifest["entries"]:
		entries[entry["id"]] = entry
	for folder in ["res://data/terrain_art", "res://data/details"]:
		DirAccess.make_dir_recursive_absolute(folder)
	_make_terrain()
	_make_details()
	_make_objects()
	print("SCENE PACK IMPORT ERRORS: ", errors)
	quit(0 if errors.is_empty() else 1)

func _save_new(resource: Resource, path: String) -> void:
	if FileAccess.file_exists(path):
		var existing := load(path)
		var belongs_to_pack: bool = (existing is TerrainArtSet and existing.source_manifest == ROOT + "manifest.json") \
			or (existing is DetailSet and existing.source_manifest == ROOT + "manifest.json") \
			or (existing is TileDefinition and existing.art_set != null and existing.art_set.source_manifest == ROOT + "manifest.json")
		if "--refresh-scene-pack" not in OS.get_cmdline_user_args() or not belongs_to_pack:
			print("Already present: ", path)
			return
	var result := ResourceSaver.save(resource, path)
	if result != OK:
		errors.append(path + ": " + error_string(result))

func _make_terrain() -> void:
	var names := {"grass": "手绘草地", "meadow": "手绘草坪", "earth": "手绘泥土"}
	var modules: Dictionary = manifest["modules"]
	var order := 50
	for id: String in names:
		var art := TerrainArtSet.new()
		art.set_id = "painted_" + id
		art.display_name = names[id]
		art.top_path = ROOT + "terrain/" + id + ".png"
		art.cliff_path = ROOT + "terrain/cliff_body.png"
		var body: Array = modules["cliff_body"]["span_m"]
		art.cliff_span = Vector2(body[0], body[1])
		if id != "earth":
			art.rim_paths = PackedStringArray([ROOT + "terrain/rim_grass.png"])
			art.rim_span = modules["rim_grass"]["span_m"]
			art.rim_rise = modules["rim_grass"]["rise_m"]
			art.rim_drop = modules["rim_grass"]["drop_m"]
		art.slope_side_path = ROOT + "terrain/slope.png"
		art.source_manifest = ROOT + "manifest.json"
		var path := "res://data/terrain_art/" + art.set_id + ".tres"
		_save_new(art, path)
		var tile := TileDefinition.new()
		tile.tile_id = art.set_id
		tile.display_name = art.display_name
		tile.art_set = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainArtSet
		tile.resolve_art()
		tile.transition_priority = order
		tile.base_color = Color("#927344")
		order += 10
		_save_new(tile, "res://data/tiles/" + tile.tile_id + ".tres")
	TileRegistry.invalidate()

func _make_details() -> void:
	for name: String in manifest["atlases"]:
		var data: Dictionary = manifest["atlases"][name]
		var detail := DetailSet.new()
		detail.set_id = "painted_" + name
		detail.display_name = "泥斑与落叶" if name == "flat" else "草簇与碎石"
		detail.orientation = DetailSet.DetailOrientation.GROUND if name == "flat" else DetailSet.DetailOrientation.CARD
		detail.atlas_path = ROOT + data["image"]
		detail.source_manifest = ROOT + "manifest.json"
		for variant: Dictionary in data["variants"]:
			var rect: Array = variant["rect"]
			detail.variants.append({
				"id": variant["id"], "name": variant["name"],
				"rect": Rect2i(rect[0], rect[1], rect[2], rect[3]),
				"size": Vector2(variant["size_m"][0], variant["size_m"][1]),
				"pivot": Vector2(variant["pivot"][0], variant["pivot"][1]),
			})
		_save_new(detail, "res://data/details/" + detail.set_id + ".tres")

func _base(id: String, display_name: String) -> PlaceableDefinition:
	var entry: Dictionary = entries[id]
	var definition := PlaceableDefinition.new()
	definition.asset_id = "painted_" + id
	definition.display_name = display_name
	definition.source_image = ROOT + entry["output"]
	definition.source_manifest = ROOT + "manifest.json"
	definition.preparation = entry["recipe"]
	definition.image_size = Vector2(entry["size_m"][0], entry["size_m"][1])
	definition.profile = load("res://data/art_profile.tres")
	definition.generator_version = 3
	return definition

func _generate(definition: PlaceableDefinition) -> void:
	var folder := "res://assets/generated/" + definition.asset_id
	if DirAccess.dir_exists_absolute(folder):
		var existing := load(folder.path_join("definition.tres")) as PlaceableDefinition
		if "--refresh-scene-pack" not in OS.get_cmdline_user_args() or existing == null \
				or existing.source_manifest != ROOT + "manifest.json":
			print("Already present: ", folder)
			return
		# Explicit refresh is limited to this pack's own generated scenes.
		definition.scene_path = folder.path_join("asset.tscn")
		definition.thumbnail_path = folder.path_join("thumbnail.png")
		var root := AssetFactory.make_asset(definition)
		var packed := PackedScene.new()
		var result := packed.pack(root)
		root.free()
		if result == OK:
			result = ResourceSaver.save(packed, definition.scene_path)
		if result == OK:
			result = ResourceSaver.save(definition, folder.path_join("definition.tres"))
		var thumbnail := (load(definition.source_image) as Texture2D).get_image()
		if thumbnail.is_compressed():
			thumbnail.decompress()
		var ratio := minf(128.0 / thumbnail.get_width(), 128.0 / thumbnail.get_height())
		thumbnail.resize(maxi(1, roundi(thumbnail.get_width() * ratio)),
			maxi(1, roundi(thumbnail.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
		var canvas := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		canvas.blit_rect(thumbnail, Rect2i(Vector2i.ZERO, thumbnail.get_size()),
			(Vector2i(128, 128) - thumbnail.get_size()) / 2)
		if result == OK:
			result = canvas.save_png(definition.thumbnail_path)
		if result != OK:
			errors.append(definition.asset_id + ": " + error_string(result))
		return
	var error := AssetFactory.generate(definition, folder)
	if not error.is_empty():
		errors.append(definition.asset_id + ": " + error)

func _make_objects() -> void:
	var names := {
		"bigtree": "蓝杉", "bigtree2": "细柏", "bigtree3": "果树", "pillar": "石柱",
		"biggrass": "阔叶草簇", "smallgrass": "细叶草", "samllflowers": "红花", "smallbush": "小灌木",
	}
	for id: String in names:
		var d := _base(id, names[id])
		d.category = "树木" if id.begins_with("bigtree") else "柱子" if id == "pillar" else "植被"
		d.pivot = Vector2(0.5, 0.99)
		if d.category in ["树木", "柱子"]:
			d.collision = PlaceableDefinition.Collision.CYLINDER
			d.collision_size = Vector3(0.6, 2, 0.6)
		_generate(d)
	for prefix in ["rock", "decayrock"]:
		var d := _base(prefix + "_frontface", "岩石块" if prefix == "rock" else "风化岩石")
		d.asset_id = "painted_" + prefix
		d.category = "玩法物件"
		d.carrier = PlaceableDefinition.Carrier.MULTI_FACE
		d.behaviour = PlaceableDefinition.Behaviour.ROCK if prefix == "rock" else PlaceableDefinition.Behaviour.BREAKABLE
		d.supports_objects = true
		d.volume_size = Vector3.ONE * 2
		d.collision = PlaceableDefinition.Collision.BOX
		d.collision_size = Vector3.ONE * 2
		d.fade_when_occluding = false
		d.face_images = {
			"front": ROOT + "objects/" + prefix + "_frontface.png",
			"back": ROOT + "objects/" + prefix + "_frontface.png",
			"left": ROOT + "objects/" + prefix + "_sideface.png",
			"right": ROOT + "objects/" + prefix + "_sideface2.png",
			"top": ROOT + "objects/" + prefix + "_topface2.png",
		}
		_generate(d)
	var chest := _base("treasurebox", "独眼宝箱")
	chest.category = "玩法物件"
	chest.behaviour = PlaceableDefinition.Behaviour.CHEST
	chest.state_images = {
		"closed": ROOT + "objects/treasurebox.png", "open": ROOT + "objects/treasurebox_open.png",
	}
	chest.pivot = Vector2(0.53, 0.92)
	chest.state_pivots = {"open": Vector2(0.53, 0.95)}
	chest.collision = PlaceableDefinition.Collision.BOX
	chest.collision_size = Vector3(1.5, 1.2, 1.5)
	chest.fade_when_occluding = false
	_generate(chest)
	var wall := _base("climbingrock_frontface", "攀岩抓点")
	wall.asset_id = "painted_climb_surface"
	wall.source_image = ROOT + "objects/climb_grips.png"
	wall.category = "墙面附件"
	wall.carrier = PlaceableDefinition.Carrier.WALL
	wall.behaviour = PlaceableDefinition.Behaviour.CLIMBABLE
	wall.image_size = Vector2(2, 2)
	wall.collision_size = Vector3(2, 2, 0.16)
	wall.fade_when_occluding = false
	_generate(wall)
