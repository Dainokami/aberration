@tool
class_name ObjectRules
extends RefCounted

static func new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func definition(record: Dictionary) -> PlaceableDefinition:
	var path: String = record.get("definition", "")
	return load(path) as PlaceableDefinition if ResourceLoader.exists(path) else null

static func bounds(data: LevelData, record: Dictionary) -> Rect2:
	var d := definition(record)
	if d == null:
		return Rect2()
	var scale_value := float(record.get("scale", 1.0))
	var yaw := float(record.get("yaw", 0.0))
	var position: Vector3 = record.get("position", Vector3.ZERO)
	var offset := Basis(Vector3.UP, yaw) * d.collision_offset * scale_value
	var size := d.footprint(scale_value, yaw)
	var origin := Vector2(position.x + offset.x, position.z + offset.z)
	return Rect2(origin - size * 0.5, size)

static func covered_cells(data: LevelData, record: Dictionary) -> Array[Vector2i]:
	var rect := bounds(data, record)
	var first := data.world_to_cell(Vector3(rect.position.x + 0.001, 0, rect.position.y + 0.001))
	var last := data.world_to_cell(Vector3(rect.end.x - 0.001, 0, rect.end.y - 0.001))
	var result: Array[Vector2i] = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			result.append(Vector2i(x, y))
	return result

static func validate_record(data: LevelData, record: Dictionary, ignore_id := "") -> String:
	var d := definition(record)
	if d == null:
		return "物件定义缺失"
	if not d.validate_asset().is_empty() or not ResourceLoader.exists(d.scene_path):
		return "物件源图、相机或生成场景缺失/无效"
	var scale_value := float(record.get("scale", 1.0))
	if not is_finite(scale_value) or scale_value < 0.25 or scale_value > 4:
		return "缩放须在 0.25～4 之间"
	var position: Vector3 = record.get("position", Vector3.ZERO)
	var cell := data.world_to_cell(position)
	if not data.cell_exists(cell) or data.stair_at(cell) >= 0:
		return "物件落地点必须是普通地块"
	if absf(position.y - data.world_center(cell).y) > 0.02:
		return "物件悬空或埋入地面，请移动到有效地块"
	for covered in covered_cells(data, record):
		if not data.cell_exists(covered) or data.stair_at(covered) >= 0 or data.elevation(covered) != data.elevation(cell):
			return "碰撞占地越界、跨高差、跨阶梯或缺少地面支撑"
	if d.collision != PlaceableDefinition.Collision.NONE:
		var rect := bounds(data, record)
		if data.in_bounds(data.spawn_cell):
			var spawn := data.world_center(data.spawn_cell)
			if absf(spawn.y - position.y) < 0.1 and rect.grow(0.35).has_point(Vector2(spawn.x, spawn.z)):
				return "阻挡物压住玩家出生点"
		for other in data.objects:
			if str(other.get("id", "")) == ignore_id:
				continue
			var other_d := definition(other)
			if other_d == null or other_d.collision == PlaceableDefinition.Collision.NONE:
				continue
			var other_pos: Vector3 = other.get("position", Vector3.ZERO)
			if absf(other_pos.y - position.y) < maxf(d.collision_size.y, other_d.collision_size.y) and rect.intersects(bounds(data, other)):
				return "与已有阻挡物的保守包围框重叠"
	return ""

static func validate_all(data: LevelData) -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {}
	for record in data.objects:
		var id: String = record.get("id", "")
		if id.is_empty() or ids.has(id):
			errors.append("物件 ID 为空或重复")
		ids[id] = true
		var error := validate_record(data, record, id)
		if not error.is_empty():
			errors.append("物件 %s：%s" % [id.left(6), error])
	return errors

static func library(directory := "res://assets/generated") -> Array[String]:
	var paths: Array[String] = []
	if not DirAccess.dir_exists_absolute(directory):
		return paths
	for folder in DirAccess.get_directories_at(directory):
		paths.append_array(library(directory.path_join(folder)))
	for file in DirAccess.get_files_at(directory):
		if file == "definition.tres":
			paths.append(directory.path_join(file))
	paths.sort()
	return paths
