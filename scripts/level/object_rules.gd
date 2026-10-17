@tool
class_name ObjectRules
extends RefCounted

static func new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func anchor_record(data: LevelData, record: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	if str(result.get("anchor_kind", "top")) != "top":
		return result
	var cell := data.world_to_cell(result.get("position", Vector3.ZERO))
	result["anchor_kind"] = "top"
	result["anchor_cell"] = cell
	result["anchor_layer"] = data.layer_at_surface(result.get("position", Vector3.ZERO))
	return result

## Covered content remains in LevelData, but is not instantiated or collidable.
## Host attachments follow their root's visibility, independent of record order.
static func is_hidden(data: LevelData, record: Dictionary, cache: Dictionary = {}) -> bool:
	var id := str(record.get("id", ""))
	if cache.has(id):
		return cache[id]
	var root := record
	var seen := {}
	while not str(root.get("support_id", "")).is_empty():
		var parent_id := str(root["support_id"])
		if seen.has(parent_id):
			return true
		seen[parent_id] = true
		root = find_record(data, parent_id)
		if root.is_empty():
			return true
	var cell: Vector2i = root.get("anchor_cell", Vector2i(-999, -999))
	var layer := int(root.get("anchor_layer", -1))
	var hidden := not data.layer_exists(cell, layer)
	if str(root.get("anchor_kind", "top")) == "wall":
		var direction := int(root.get("wall_direction", 0))
		hidden = hidden or data.has_terrain_volume(cell + LevelData.DIRS[posmod(direction, 4)], layer)
	else:
		hidden = hidden or not data.is_surface_exposed(cell, layer)
		if not hidden:
			for covered in covered_cells(data, root):
				if not data.is_surface_exposed(covered, layer):
					hidden = true
					break
	cache[id] = hidden
	return hidden

static func find_record(data: LevelData, id: String) -> Dictionary:
	for record in data.objects:
		if str(record.get("id", "")) == id:
			return record
	return {}

static func transform_of(record: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, float(record.get("yaw", 0.0))).scaled(
		Vector3.ONE * float(record.get("scale", 1.0))), record.get("position", Vector3.ZERO))

static func wall_normal(direction: int) -> Vector3:
	var direction_2d: Vector2i = LevelData.DIRS[posmod(direction, 4)]
	return Vector3(direction_2d.x, 0, direction_2d.y)

static func wall_anchor(data: LevelData, record: Dictionary, cell: Vector2i,
		layer: int, direction: int, offset := Vector2.ZERO) -> Dictionary:
	var copy := record.duplicate(true)
	var normal := wall_normal(direction)
	copy["anchor_kind"] = "wall"
	copy["anchor_cell"] = cell
	copy["anchor_layer"] = layer
	copy["wall_direction"] = posmod(direction, 4)
	copy["wall_offset"] = offset
	copy["position"] = data.world_layer_center(cell, layer) \
		+ normal * (LevelData.CELL_SIZE * 0.5) \
		+ Vector3(normal.z, 0, -normal.x) * offset.x \
		+ Vector3.UP * (offset.y - LevelData.ELEVATION_STEP * 0.5)
	copy["yaw"] = atan2(normal.x, normal.z)
	copy.erase("support_id")
	return copy

static func object_anchor(data: LevelData, record: Dictionary, parent_id: String,
		position: Vector3, wall := false, direction := 2) -> Dictionary:
	var copy := record.duplicate(true)
	var parent := find_record(data, parent_id)
	if parent.is_empty():
		return {}
	copy["anchor_kind"] = "object_wall" if wall else "object"
	copy["support_id"] = parent_id
	copy["position"] = position
	copy["support_offset"] = transform_of(parent).affine_inverse() * position
	copy["anchor_cell"] = parent.get("anchor_cell", data.world_to_cell(position))
	copy["anchor_layer"] = int(parent.get("anchor_layer", -1))
	copy["support_yaw"] = float(copy.get("yaw", 0.0)) - float(parent.get("yaw", 0.0))
	if wall:
		copy["wall_direction"] = posmod(direction, 4)
	return copy

static func support_error(data: LevelData, record: Dictionary) -> String:
	var d := definition(record)
	var position: Vector3 = record.get("position", Vector3.ZERO)
	var kind := str(record.get("anchor_kind", "top"))
	var cell: Vector2i = record.get("anchor_cell", data.world_to_cell(position))
	var layer := int(record.get("anchor_layer", data.top_layer(cell)))
	if d == null:
		return "物件定义缺失"
	if not d.ecosystems.is_empty():
		var ecosystem := ecosystem_at(data, cell, layer)
		if ecosystem not in d.ecosystems:
			return "此物件仅适用于：" + "、".join(d.ecosystems)
	if d.requires_seabed and (not data.is_solid_layer(cell, layer) \
			or not data.is_water_layer(cell, layer + 1)):
		return "此物件必须放在海洋中的真实海底地形上"
	if d.carrier == PlaceableDefinition.Carrier.WALL and kind not in ["wall", "object_wall"]:
		return "墙面附件必须放在外露侧壁"
	if d.carrier != PlaceableDefinition.Carrier.WALL and kind in ["wall", "object_wall"]:
		return "此物件需要顶面支撑"
	if kind == "top":
		if cell != data.world_to_cell(position) or not data.is_solid_layer(cell, layer) \
				or data.stair_at(cell, layer) >= 0:
			return "物件落地点必须是普通地块"
		if absf(position.y - data.surface_y(layer)) > 0.02:
			return "物件悬空或埋入地面，请移动到有效地块"
		for covered in covered_cells(data, record):
			if not data.is_solid_layer(covered, layer) or data.stair_at(covered, layer) >= 0:
				return "碰撞占地越界、跨高差、跨阶梯或缺少地面支撑"
			if not d.ecosystems.is_empty() and ecosystem_at(data, covered, layer) not in d.ecosystems:
				return "物件占地跨越不适用的生态"
			if d.requires_seabed and not data.is_water_layer(covered, layer + 1):
				return "气泡占地必须全部位于海洋内"
	elif kind == "wall":
		var direction := int(record.get("wall_direction", -1))
		if direction < 0 or direction > 3 or not data.layer_exists(cell, layer):
			return "墙面附件的支撑层不存在"
		if data.stair_at(cell, layer) >= 0:
			return "阶梯侧壁不能承托墙面附件"
		var expected := wall_anchor(data, record, cell, layer, direction,
			record.get("wall_offset", Vector2.ZERO))
		if not position.is_equal_approx(expected["position"]) \
				or absf(wrapf(float(record.get("yaw", 0.0)) - float(expected["yaw"]), -PI, PI)) > 0.01:
			return "墙面附件的位置或朝向与支撑面不一致"
		var offset: Vector2 = record.get("wall_offset", Vector2.ZERO)
		var size := d.image_size * float(record.get("scale", 1.0))
		if absf(offset.x) + size.x * 0.5 > LevelData.CELL_SIZE * 0.5 + 0.01 \
				or offset.y < -0.01 or offset.y + size.y > LevelData.ELEVATION_STEP + 0.01:
			return "附件超出这一层侧壁，请减小尺寸或调整位置"
	elif kind in ["object", "object_wall"]:
		var parent_id := str(record.get("support_id", ""))
		var parent := find_record(data, parent_id)
		var parent_d := definition(parent)
		if parent.is_empty() or parent_d == null or not parent_d.supports_objects:
			return "宿主物件不存在或不能承托附件"
		var seen := {str(record.get("id", "")): true}
		var ancestor := parent
		while not ancestor.is_empty():
			var id := str(ancestor.get("id", ""))
			if seen.has(id):
				return "物件支撑关系不能形成循环"
			seen[id] = true
			ancestor = find_record(data, str(ancestor.get("support_id", "")))
		var local: Vector3 = record.get("support_offset", Vector3(INF, INF, INF))
		if not local.is_finite() or not position.is_equal_approx(transform_of(parent) * local):
			return "物件位置与宿主锚点不一致"
		if cell != parent.get("anchor_cell") or layer != int(parent.get("anchor_layer", -1)):
			return "物件层锚点与宿主不一致"
		var box := AABB(parent_d.collision_offset - Vector3(
			parent_d.collision_size.x * 0.5, 0, parent_d.collision_size.z * 0.5),
			parent_d.collision_size)
		if kind == "object":
			if absf(local.y - box.end.y) > 0.02:
				return "叠放物件必须接触宿主顶面"
			var rect := bounds(data, record)
			var inverse := transform_of(parent).affine_inverse()
			for corner in [rect.position, Vector2(rect.end.x, rect.position.y),
					rect.end, Vector2(rect.position.x, rect.end.y)]:
				var p: Vector3 = inverse * Vector3(corner.x, position.y, corner.y)
				if p.x < box.position.x - 0.01 or p.x > box.end.x + 0.01 \
						or p.z < box.position.z - 0.01 or p.z > box.end.z + 0.01:
					return "叠放物件的碰撞占地超出宿主顶面"
		else:
			var direction := int(record.get("wall_direction", -1))
			if direction < 0 or direction > 3:
				return "宿主侧面方向无效"
			var normal := wall_normal(direction)
			var face_distance := box.size.z * 0.5 if direction % 2 == 0 else box.size.x * 0.5
			var face_width := box.size.x if direction % 2 == 0 else box.size.z
			var size := d.image_size * float(record.get("scale", 1.0)) / float(parent.get("scale", 1.0))
			var relative := local - parent_d.collision_offset
			if absf(relative.dot(normal) - face_distance) > 0.02 \
					or absf(relative.dot(Vector3(normal.z, 0, -normal.x))) + size.x * 0.5 > face_width * 0.5 + 0.01 \
					or relative.y < -0.01 or relative.y + size.y > box.size.y + 0.01:
				return "墙面附件超出宿主侧面"
			var expected_yaw := float(parent.get("yaw", 0.0)) + atan2(normal.x, normal.z)
			if absf(wrapf(float(record.get("yaw", 0.0)) - expected_yaw, -PI, PI)) > 0.01:
				return "墙面附件朝向必须与宿主侧面一致"
	else:
		return "未知支撑类型"
	return ""

## Resolve parent transforms in dependency order. Cycles are rejected by validation.
static func sync_dependents(data: LevelData) -> void:
	var resolved := {}
	for record in data.objects:
		if str(record.get("support_id", "")).is_empty():
			resolved[str(record.get("id", ""))] = true
	for step in data.objects.size():
		var progressed := false
		for record in data.objects:
			var id := str(record.get("id", ""))
			var parent_id := str(record.get("support_id", ""))
			if resolved.has(id) or not resolved.has(parent_id):
				continue
			var parent := find_record(data, parent_id)
			record["position"] = transform_of(parent) * (record.get("support_offset", Vector3.ZERO) as Vector3)
			record["yaw"] = float(parent.get("yaw", 0.0)) + float(record.get("support_yaw", 0.0))
			record["anchor_cell"] = parent["anchor_cell"]
			record["anchor_layer"] = parent["anchor_layer"]
			resolved[id] = true
			progressed = true
		if not progressed:
			break

static func remove_with_dependents(data: LevelData, ids: Array[String]) -> void:
	var removed := {}
	for id in ids:
		removed[id] = true
	for step in data.objects.size():
		var changed := false
		for record in data.objects:
			var id := str(record.get("id", ""))
			if not removed.has(id) and removed.has(str(record.get("support_id", ""))):
				removed[id] = true
				changed = true
		if not changed:
			break
	for i in range(data.objects.size() - 1, -1, -1):
		if removed.has(str(data.objects[i].get("id", ""))):
			data.objects.remove_at(i)

static func remove_terrain_support(data: LevelData, cell: Vector2i, layer: int) -> void:
	var ids: Array[String] = []
	for record in data.objects:
		var kind := str(record.get("anchor_kind", "top"))
		if int(record.get("anchor_layer", -1)) != layer:
			continue
		if (kind == "top" and cell in covered_cells(data, record)) or \
				(kind == "wall" and record.get("anchor_cell") == cell):
			ids.append(str(record.get("id", "")))
	remove_with_dependents(data, ids)
	DetailRules.remove_support(data, cell, layer)

static func move_top_anchors(data: LevelData, cell: Vector2i, old_top: int, new_top: int) -> void:
	if old_top < 0 or old_top == new_top:
		return
	for record in data.objects:
		if str(record.get("anchor_kind", "top")) != "top" \
				or record.get("anchor_cell") != cell \
				or int(record.get("anchor_layer", -1)) != old_top:
			continue
		record["position"] += Vector3.UP * ((new_top - old_top) * LevelData.ELEVATION_STEP)
		record["anchor_layer"] = new_top
	sync_dependents(data)
	DetailRules.move_support(data, cell, old_top, new_top)

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
	var d := definition(record)
	if d != null and not d.spatial_cells.is_empty():
		var result: Array[Vector2i] = []
		var transform := transform_of(record)
		for offset in d.spatial_cells:
			var corners: Array[Vector3] = []
			for x in [-0.499, 0.499]:
				for z in [-0.499, 0.499]:
					corners.append(transform * (offset + Vector3(x * d.cell_size.x, 0, z * d.cell_size.z)))
			var first := Vector2i(999999, 999999)
			var last := Vector2i(-999999, -999999)
			for corner in corners:
				first = first.min(data.world_to_cell(corner))
				last = last.max(data.world_to_cell(corner))
			for y in range(first.y, last.y + 1):
				for x in range(first.x, last.x + 1):
					var cell := Vector2i(x, y)
					if cell not in result:
						result.append(cell)
		return result
	var rect := bounds(data, record)
	var first := data.world_to_cell(Vector3(rect.position.x + 0.001, 0, rect.position.y + 0.001))
	var last := data.world_to_cell(Vector3(rect.end.x - 0.001, 0, rect.end.y - 0.001))
	var result: Array[Vector2i] = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			result.append(Vector2i(x, y))
	return result

static func ecosystem_at(data: LevelData, cell: Vector2i, layer: int) -> String:
	if data.is_water_layer(cell, layer) or data.is_water_layer(cell, layer + 1):
		return "ocean"
	var id := data.tile_id(cell, layer)
	if id == "sand":
		return "desert"
	if id in ["rock", "ground_stone"] or "rock" in id:
		return "rock"
	return "grass"

static func collision_regions(data: LevelData, record: Dictionary) -> Array[Rect2]:
	var d := definition(record)
	var result: Array[Rect2] = []
	if d == null:
		return result
	if d.spatial_cells.is_empty():
		result.append(bounds(data, record))
		return result
	var transform := transform_of(record)
	var yaw := float(record.get("yaw", 0.0))
	var scale_value := float(record.get("scale", 1.0))
	var size := Vector2(absf(cos(yaw)) * d.cell_size.x + absf(sin(yaw)) * d.cell_size.z,
		absf(sin(yaw)) * d.cell_size.x + absf(cos(yaw)) * d.cell_size.z) * scale_value
	for offset in d.spatial_cells:
		var center := transform * offset
		result.append(Rect2(Vector2(center.x, center.z) - size * 0.5, size))
	return result

static func validate_record(data: LevelData, record: Dictionary, ignore_id := "",
		visibility: Dictionary = {}, check_assets := true, assets: Dictionary = {}) -> String:
	var d := definition(record)
	if d == null:
		return "物件定义缺失"
	var path := str(record.get("definition", ""))
	if check_assets and not assets.has(path):
		assets[path] = d.validate_asset().is_empty() and ResourceLoader.exists(d.scene_path)
	if check_assets and not bool(assets[path]):
		return "物件源图、相机或生成场景缺失/无效"
	var scale_value := float(record.get("scale", 1.0))
	if not is_finite(scale_value) or scale_value < 0.25 or scale_value > 4:
		return "缩放须在 0.25～4 之间"
	var position: Vector3 = record.get("position", Vector3.ZERO)
	if not position.is_finite():
		return "物件位置无效"
	if not is_finite(float(record.get("yaw", 0.0))):
		return "物件朝向无效"
	var error := support_error(data, record)
	if not error.is_empty():
		return error
	if is_hidden(data, record, visibility):
		return ""
	if d.collision != PlaceableDefinition.Collision.NONE:
		var rect := bounds(data, record)
		var bottom := position.y + d.collision_offset.y * scale_value
		var top := bottom + d.collision_size.y * scale_value
		if data.in_bounds(data.spawn_cell):
			var spawn := data.world_center(data.spawn_cell, data.spawn_layer)
			for region in collision_regions(data, record):
				if bottom < spawn.y + 1.7 and top > spawn.y \
						and region.grow(0.35).has_point(Vector2(spawn.x, spawn.z)):
					return "阻挡物压住玩家出生点"
		for other in data.objects:
			if str(other.get("id", "")) == ignore_id:
				continue
			if is_hidden(data, other, visibility):
				continue
			var other_d := definition(other)
			if other_d == null or other_d.collision == PlaceableDefinition.Collision.NONE:
				continue
			var other_pos: Vector3 = other.get("position", Vector3.ZERO)
			var other_scale := float(other.get("scale", 1.0))
			var other_bottom := other_pos.y + other_d.collision_offset.y * other_scale
			var other_top := other_bottom + other_d.collision_size.y * other_scale
			if bottom < other_top - 0.01 and top > other_bottom + 0.01 \
					and rect.intersects(bounds(data, other)):
				if d.spatial_cells.is_empty() and other_d.spatial_cells.is_empty():
					return "与已有阻挡物的保守包围框重叠"
				for region in collision_regions(data, record):
					for other_region in collision_regions(data, other):
						if region.intersects(other_region):
							return "与已有阻挡物的保守包围框重叠"
	return ""

static func validate_all(data: LevelData, check_assets := true) -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {}
	# ResourceLoader's cache is weak. Generated scenes embed their own definitions,
	# so repeatedly loading a definition during pairwise checks can reparse its
	# .tres file each time. Retain each definition for this validation pass only.
	var definitions := {}
	var visibility := {}
	var assets := {}
	for record in data.objects:
		var path := str(record.get("definition", ""))
		if not definitions.has(path):
			definitions[path] = definition(record)
	for record in data.objects:
		var id: String = record.get("id", "")
		if id.is_empty() or ids.has(id):
			errors.append("物件 ID 为空或重复")
		ids[id] = true
		var error := validate_record(data, record, id, visibility, check_assets, assets)
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
