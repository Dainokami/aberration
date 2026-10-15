@tool
class_name DetailSet
extends Resource

enum DetailOrientation { GROUND, CARD }

@export var set_id := ""
@export var display_name := ""
@export var atlas_path := ""
@export var orientation: DetailOrientation = DetailOrientation.GROUND
## Each variant has id, name, rect (Rect2i), size (Vector2, metres), pivot.
@export var variants: Array[Dictionary] = []
@export var source_manifest := ""
@export var version := 1

func validate_asset() -> PackedStringArray:
	var errors := PackedStringArray()
	if not set_id.is_valid_identifier():
		errors.append("细节套件 ID 无效")
	var texture := load(atlas_path) as Texture2D if ResourceLoader.exists(atlas_path) else null
	if texture == null:
		errors.append("细节图集缺失")
	if variants.is_empty():
		errors.append("细节套件没有变体")
	var ids := {}
	for variant in variants:
		var id := str(variant.get("id", ""))
		var rect: Rect2i = variant.get("rect", Rect2i())
		var size: Vector2 = variant.get("size", Vector2.ZERO)
		if id.is_empty() or ids.has(id):
			errors.append("细节 ID 缺失或重复")
		ids[id] = true
		if size.x <= 0 or size.y <= 0 or not size.is_finite():
			errors.append("细节尺寸无效：" + id)
		if rect.size.x <= 0 or rect.size.y <= 0 or (texture != null and
				not Rect2i(Vector2i.ZERO, texture.get_size()).encloses(rect)):
			errors.append("细节图集区域越界：" + id)
	return errors

func variant_index(id: String) -> int:
	for index in variants.size():
		if variants[index].get("id", "") == id:
			return index
	return -1

func thumbnail(index: int) -> AtlasTexture:
	if index < 0 or index >= variants.size() or not ResourceLoader.exists(atlas_path):
		return null
	var result := AtlasTexture.new()
	result.atlas = load(atlas_path)
	result.region = Rect2(variants[index]["rect"])
	result.filter_clip = true
	return result

static func library(directory := "res://data/details") -> Array[String]:
	var result: Array[String] = []
	if not DirAccess.dir_exists_absolute(directory):
		return result
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".tres"):
			result.append(directory.path_join(file))
	result.sort()
	return result
