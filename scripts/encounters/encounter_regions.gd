@tool
class_name EncounterRegions
extends RefCounted

static func key(cell: Vector2i, layer: int) -> Vector3i:
	return Vector3i(cell.x, layer, cell.y)

static func zone(data: LevelData, cell: Vector2i, layer: int) -> int:
	var record: Dictionary = data.encounter_regions.get(key(cell, layer), {})
	if record.has("zone"):
		return int(record.zone)
	var origin: Vector2i = data.generation.get("zone_origin", data.map_origin)
	var size: Vector2i = data.generation.get("zone_size", data.map_size)
	var zones: PackedByteArray = data.generation.get("zones", PackedByteArray())
	var local := cell - origin
	if Rect2i(Vector2i.ZERO, size).has_point(local):
		var index := local.y * size.x + local.x
		if index >= 0 and index < zones.size():
			return int(zones[index])
	return 0

static func forbidden(data: LevelData, cell: Vector2i, layer: int) -> bool:
	return bool(data.encounter_regions.get(key(cell, layer), {}).get("forbidden", false))

static func paint(data: LevelData, cell: Vector2i, layer: int, mode: int) -> void:
	var index := key(cell, layer)
	var record: Dictionary = data.encounter_regions.get(index, {}).duplicate(true)
	match mode:
		0, 1:
			record.zone = mode
		2:
			record.forbidden = true
		3:
			data.encounter_regions.erase(index)
			return
		4:
			record.erase("forbidden")
	data.encounter_regions[index] = record

static func errors(data: LevelData) -> PackedStringArray:
	var result := PackedStringArray()
	for index in data.encounter_regions:
		if not index is Vector3i or index.y < 0 or index.y >= LevelData.MAX_LAYERS:
			result.append("怪物区域层坐标无效")
			continue
		var record: Variant = data.encounter_regions[index]
		if not record is Dictionary or int(record.get("zone", 0)) not in [0, 1]:
			result.append("怪物区域标签无效")
	return result
