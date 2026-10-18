@tool
class_name MonsterSpawnPoints
extends RefCounted

const INTERVAL := 30.0
const VISIBILITY_MARGIN := 4.0
const ECOLOGY_NAMES := {"grass": "草原", "rock": "岩石", "desert": "沙漠", "ocean": "海洋"}

static func create(label: String = "刷新点") -> Dictionary:
	return {"id": ObjectRules.new_id(), "name": label, "enabled": true,
		"cells": [], "max_alive": 2, "activation_radius": 0.0}

static func center(data: LevelData, point: Dictionary) -> Vector3:
	var result := Vector3.ZERO
	var cells: Array = point.get("cells", [])
	for cell: Vector3i in cells:
		result += data.world_center(Vector2i(cell.x, cell.z), cell.y)
	return result / maxf(1, cells.size())

static func contains(center_value: Vector3, radius: float, player_position: Vector3) -> bool:
	return Vector2(player_position.x - center_value.x, player_position.z - center_value.z).length_squared() \
		<= radius * radius

## Ground footprint of the gameplay camera, clipped to this finite map.
## A shallow camera has an asymmetric footprint; use the farthest visible edge.
static func automatic_radius(data: LevelData, focus: Vector3, camera: Camera3D = null) -> float:
	var profile := load("res://data/art_profile.tres") as ArtProfile
	var polygon := PackedVector2Array()
	var corners := [Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)]
	for corner: Vector2 in corners:
		var origin: Vector3
		var direction: Vector3
		if camera != null and camera.is_inside_tree():
			var screen := corner * camera.get_viewport().get_visible_rect().size
			origin = camera.project_ray_origin(screen)
			direction = camera.project_ray_normal(screen)
		else:
			var half := tan(deg_to_rad(profile.field_of_view) * 0.5)
			var offset := Vector3((corner.x * 2 - 1) * half * 16.0 / 9.0,
				(1 - corner.y * 2) * half, -1)
			origin = focus + profile.camera_direction() * profile.camera_distance
			direction = (profile.camera_basis() * offset).normalized()
			if not profile.perspective:
				origin += profile.camera_basis() * Vector3((corner.x - 0.5) * profile.orthographic_size * 16.0 / 9.0,
					(0.5 - corner.y) * profile.orthographic_size, 0)
				direction = -profile.camera_direction()
		var distance := (focus.y - origin.y) / direction.y if direction.y < -0.0001 else 4000.0
		var hit := origin + direction * clampf(distance, 0, 4000)
		polygon.append(Vector2(hit.x, hit.z))
	var first := data.world_center(data.map_origin, 0)
	var bounds := Rect2(Vector2(first.x, first.z) - Vector2.ONE * LevelData.CELL_SIZE * 0.5,
		Vector2(data.map_size) * LevelData.CELL_SIZE)
	for side in 4:
		var clipped := PackedVector2Array()
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			var va := a.x if side < 2 else a.y
			var vb := b.x if side < 2 else b.y
			var boundary: float = [bounds.position.x, bounds.end.x, bounds.position.y, bounds.end.y][side]
			var a_inside: bool = va >= boundary if side % 2 == 0 else va <= boundary
			var b_inside: bool = vb >= boundary if side % 2 == 0 else vb <= boundary
			if a_inside:
				clipped.append(a)
			if a_inside != b_inside:
				clipped.append(a.lerp(b, (boundary - va) / (vb - va)))
		polygon = clipped
	var radius := 0.0
	for vertex in polygon:
		radius = maxf(radius, vertex.distance_to(Vector2(focus.x, focus.z)))
	return maxf(8, radius + VISIBILITY_MARGIN)

static func radius(data: LevelData, point: Dictionary, focus: Vector3,
		camera: Camera3D = null) -> float:
	var custom := float(point.get("activation_radius", 0.0))
	return custom if custom > 0 else automatic_radius(data, focus, camera)

static func find(data: LevelData, id: String) -> Dictionary:
	for point in data.monster_spawn_points:
		if str(point.get("id", "")) == id:
			return point
	return {}

static func connected(cells: Array) -> bool:
	if cells.is_empty():
		return false
	if not cells[0] is Vector3i:
		return false
	var remaining := {}
	var layer: int = cells[0].y
	for cell in cells:
		if not cell is Vector3i or cell.y != layer or remaining.has(cell):
			return false
		remaining[cell] = true
	var queue: Array = [cells[0]]
	remaining.erase(cells[0])
	for index in cells.size():
		if index >= queue.size():
			break
		var current: Vector3i = queue[index]
		for direction: Vector2i in LevelData.DIRS:
			var next := current + Vector3i(direction.x, 0, direction.y)
			if remaining.has(next):
				remaining.erase(next)
				queue.append(next)
	return remaining.is_empty()

static func edit(data: LevelData, point: Dictionary, cell: Vector3i, erase := false) -> String:
	var cells: Array = point.get("cells", []).duplicate()
	if erase:
		if cell not in cells:
			return ""
		cells.erase(cell)
		if not cells.is_empty() and not connected(cells):
			return "擦除会拆开刷新点；请从边缘擦除，或另建刷新点"
	else:
		var flat := Vector2i(cell.x, cell.z)
		if not data.layer_exists(flat, cell.y) or not data.is_surface_exposed(flat, cell.y):
			return "请选择真实外露的地块或水面"
		if cell in cells:
			return ""
		for other in data.monster_spawn_points:
			if str(other.id) != str(point.id) and cell in other.cells:
				return "该格已属于其他刷新点"
		cells.append(cell)
		if not connected(cells):
			return "同一刷新点须在同一高度层，沿相邻格连续绘制"
	point.cells = cells
	return ""

static func errors(data: LevelData) -> PackedStringArray:
	var result := PackedStringArray()
	var ids := {}
	var occupied := {}
	for point in data.monster_spawn_points:
		var id := str(point.get("id", ""))
		var label := str(point.get("name", "刷新点"))
		var cells: Array = point.get("cells", [])
		if id.is_empty() or ids.has(id):
			result.append(label + "：ID缺失或重复")
		ids[id] = true
		if not connected(cells):
			result.append(label + "：范围须为同层相邻格且不能为空")
		if int(point.get("max_alive", 2)) < 1 or int(point.get("max_alive", 2)) > 20:
			result.append(label + "：存活上限须为1～20")
		var activation_radius := float(point.get("activation_radius", 0.0))
		if not is_finite(activation_radius) or activation_radius < 0:
			result.append(label + "：激活/追踪半径须为非负有限数，0为自动")
		for cell in cells:
			if not cell is Vector3i:
				result.append(label + "：无效格坐标")
				continue
			if not data.layer_exists(Vector2i(cell.x, cell.z), cell.y):
				result.append(label + "：落脚地块不存在")
			if occupied.has(cell):
				result.append(label + "：与其他刷新点重叠")
			occupied[cell] = true
	return result

static func prune(data: LevelData) -> void:
	var kept: Array[Dictionary] = []
	var used_ids := {}
	for point in data.monster_spawn_points:
		used_ids[str(point.id)] = true
	for point in data.monster_spawn_points:
		var remaining: Array = point.cells.filter(func(cell: Vector3i):
			return data.layer_exists(Vector2i(cell.x, cell.z), cell.y))
		# Terrain removal may divide a point. Preserve every surviving component.
		var part := 0
		while not remaining.is_empty():
			var group: Array = [remaining.pop_front()]
			var cursor := 0
			while cursor < group.size():
				var current: Vector3i = group[cursor]
				for direction: Vector2i in LevelData.DIRS:
					var next := current + Vector3i(direction.x, 0, direction.y)
					if next in remaining:
						remaining.erase(next)
						group.append(next)
				cursor += 1
			var copy := point.duplicate(true)
			copy.cells = group
			if part > 0:
				var suffix := part
				while used_ids.has("%s/part%d" % [point.id, suffix]):
					suffix += 1
				copy.id = "%s/part%d" % [point.id, suffix]
				used_ids[str(copy.id)] = true
				copy.name = "%s · %d" % [point.get("name", "刷新点"), part + 1]
			kept.append(copy)
			part += 1
	data.monster_spawn_points = kept

static func ecosystems(data: LevelData, point: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for cell: Vector3i in point.get("cells", []):
		var ecology := ObjectRules.ecosystem_at(data, Vector2i(cell.x, cell.z), cell.y)
		if ecology not in result:
			result.append(ecology)
	return result

static func species(data: LevelData, point: Dictionary, config: EncounterConfig) -> PackedStringArray:
	var result := PackedStringArray()
	for rule in config.monster_pool:
		if not bool(rule.get("enabled", true)) or float(rule.get("weight", 1)) <= 0:
			continue
		var monster := config.ordinary_definition(rule)
		if monster == null or not monster.available():
			continue
		for index: Vector3i in point.get("cells", []):
			var cell := Vector2i(index.x, index.z)
			if not data.is_surface_exposed(cell, index.y) \
					or EncounterRegions.forbidden(data, cell, index.y) \
					or data.stair_at(cell, index.y) >= 0:
				continue
			var water := data.is_water_layer(cell, index.y)
			var dry := data.is_solid_layer(cell, index.y) and not data.is_water_layer(cell, index.y + 1)
			if not water and not dry or water and monster.movement == "land" \
					or dry and monster.movement == "aquatic":
				continue
			if ObjectRules.ecosystem_at(data, cell, index.y) in monster.ecosystems:
				result.append(monster.display_name)
				break
	return result
