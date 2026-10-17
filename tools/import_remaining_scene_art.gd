extends SceneTree

const ROOT := "res://assets/derived_art/scene_pack_20261014/"
const MANIFEST := ROOT + "remaining_objects_manifest.json"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not FileAccess.file_exists(MANIFEST):
		printerr("Run tools/prepare_remaining_scene_art.py first")
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for prefix: String in ["rock", "decayrock"]:
		var d := _copy("painted_" + prefix)
		d.asset_id = "painted_" + prefix + "_alt"
		d.display_name = "岩石块·顶面二" if prefix == "rock" else "风化岩石·顶面二"
		d.source_image = ROOT + "objects/" + prefix + "_topface.png"
		d.source_manifest = MANIFEST
		d.face_images["top"] = d.source_image
		d.preparation = {"base_asset": "painted_" + prefix, "top_source": prefix + "_topface",
			"base_manifest": ROOT + "manifest.json"}
		_generate(d)
	var recipes := {}
	for entry: Dictionary in manifest["entries"]:
		recipes[entry["id"]] = entry
	for suffix: String in ["", "_alt"]:
		var d := _copy("painted_rock")
		d.asset_id = "painted_climbingrock" + suffix
		d.display_name = "攀岩岩块" if suffix.is_empty() else "攀岩岩块·顶面二"
		d.source_manifest = MANIFEST
		d.source_image = ROOT + "remaining_objects/climbingrock" + suffix + "_preview.png"
		d.face_images = {
			"front": ROOT + "remaining_objects/climbingrock_frontface.png",
			"back": ROOT + "remaining_objects/climbingrock_frontface.png",
			"left": ROOT + "remaining_objects/climbingrock_sideface3.png",
			"right": ROOT + "remaining_objects/climbingrock_sideface2.png",
			"top": ROOT + "remaining_objects/" + str(manifest["variants"][d.asset_id]) + ".png",
		}
		d.preparation = {"faces": recipes.duplicate(true), "top_source": manifest["variants"][d.asset_id],
			"climb_attachment": "painted_climb_surface"}
		_generate(d)
	print("REMAINING SCENE ART IMPORT FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func _copy(id: String) -> PlaceableDefinition:
	var original := load("res://assets/generated/" + id + "/definition.tres") as PlaceableDefinition
	var d := original.duplicate(true) as PlaceableDefinition
	d.scene_path = ""
	d.thumbnail_path = ""
	d.generator_version = 4
	return d

func _generate(d: PlaceableDefinition) -> void:
	var folder := "res://assets/generated/" + d.asset_id
	if DirAccess.dir_exists_absolute(folder):
		var existing := load(folder.path_join("definition.tres")) as PlaceableDefinition
		if existing == null or existing.source_manifest != MANIFEST or not existing.validate_asset().is_empty() \
				or not ResourceLoader.exists(existing.scene_path):
			failures.append("Existing resource is invalid or belongs to another import: " + d.asset_id)
		else:
			print("Already present: ", d.asset_id)
		return
	var error := AssetFactory.generate(d, folder)
	if not error.is_empty():
		failures.append(d.asset_id + ": " + error)
