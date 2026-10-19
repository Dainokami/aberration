class_name EncounterNavigation
extends RefCounted

var data: LevelData
var graph := AStar3D.new()
var ids := {}
var surfaces := {}
var blocked_volumes: Array[AABB] = []
var radius := 0.35
var height := 1.5
var movement := "land"
var components := {}
var building := false
var _build_cells: Array[Vector2i] = []
var _build_indices: Array = []
var _build_cursor := 0
var _build_phase := 0
var _component_queue: Array[int] = []
var _component_cursor := 0
var _component_id := 0

func build_incremental(level: LevelData, monster: MonsterDefinition, chunks: Dictionary,
		selected_objects: Variant = null) -> void:
	_initialize_graph(level, monster, selected_objects)
	_build_cells.clear()
	for chunk: Vector2i in chunks:
		var region := TerrainChunkStream.chunk_region(data, chunk)
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				_build_cells.append(Vector2i(x, y))
	_build_cursor = 0
	_build_phase = 0
	_component_id = 0
	_component_cursor = 0
	_component_queue.clear()
	building = true

func step_build(budget_usec := 2000) -> void:
	var start := Time.get_ticks_usec()
	while building and Time.get_ticks_usec() - start < budget_usec:
		if _build_phase == 0:
			if _build_cursor >= _build_cells.size():
				_build_indices = ids.keys()
				_build_cursor = 0
				_build_phase = 1
				continue
			_add_cell(_build_cells[_build_cursor])
			_build_cursor += 1
		elif _build_phase == 1:
			if _build_cursor >= _build_indices.size():
				_build_indices = surfaces.keys()
				_build_cursor = 0
				_build_phase = 2
				continue
			_connect_point(_build_indices[_build_cursor])
			_build_cursor += 1
		else:
			if _component_cursor < _component_queue.size():
				for next in graph.get_point_connections(_component_queue[_component_cursor]):
					if not components.has(next):
						components[next] = _component_id
						_component_queue.append(next)
				_component_cursor += 1
			elif _build_cursor < _build_indices.size():
				var id: int = _build_indices[_build_cursor]
				_build_cursor += 1
				if components.has(id):
					continue
				_component_id += 1
				components[id] = _component_id
				_component_queue = [id]
				_component_cursor = 0
			else:
				building = false
				_build_cells.clear()
				_build_indices.clear()
				_component_queue.clear()

func build(level: LevelData, monster: MonsterDefinition = null, chunks: Variant = null) -> void:
	_initialize_graph(level, monster)
	var regions: Array[Rect2i] = [data.map_bounds()]
	if chunks != null:
		regions.clear()
		for chunk: Vector2i in chunks:
			regions.append(TerrainChunkStream.chunk_region(data, chunk))
	for region in regions:
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				_add_cell(Vector2i(x, y))
	_connect_graph()

func _initialize_graph(level: LevelData, monster: MonsterDefinition = null,
		selected_objects: Variant = null) -> void:
	data = level
	if monster != null:
		radius = monster.body_radius
		height = monster.body_height
		movement = monster.movement
	graph.clear()
	ids.clear()
	surfaces.clear()
	components.clear()
	blocked_volumes.clear()
	var records: Array = data.objects if selected_objects == null else selected_objects
	for record in records:
		var definition := ObjectRules.definition(record)
		if definition == null or ObjectRules.is_hidden(data, record) \
				or definition.collision == PlaceableDefinition.Collision.NONE:
			continue
		var bounds := ObjectRules.collision_regions(data, record)
		var scale_value := float(record.get("scale", 1.0))
		var bottom := float(record.position.y) + definition.collision_offset.y * scale_value
		for rect in bounds:
			blocked_volumes.append(AABB(Vector3(rect.position.x, bottom, rect.position.y),
				Vector3(rect.size.x, definition.collision_size.y * scale_value, rect.size.y)))
func _add_cell(cell: Vector2i) -> void:
	for layer in data.layer_count(cell):
		var dry := data.is_solid_layer(cell, layer) and not data.is_water_layer(cell, layer + 1)
		var water := data.is_water_layer(cell, layer) and not data.layer_exists(cell, layer + 1)
		if not dry and not water:
			continue
		if water and movement == "land" or dry and movement == "aquatic":
			continue
		if not data.is_surface_exposed(cell, layer):
			continue
		var point := data.world_center(cell, layer)
		var stair := data.stair_at(cell, layer)
		if stair >= 0:
			point.y += 0.5 if cell == Vector2i(data.stairs[stair].cell) else -0.5
		if movement == "air":
			point.y += 1.2
		if not clear_at(point, cell, layer):
			continue
		var index := Vector3i(cell.x, layer, cell.y)
		var id := graph.get_point_count()
		graph.add_point(id, point)
		ids[index] = id
		surfaces[id] = index

func _connect_graph() -> void:
	for index: Vector3i in ids:
		_connect_point(index)
	var component := 0
	for id in surfaces:
		if components.has(id):
			continue
		var queue: Array[int] = [id]
		components[id] = component
		var cursor := 0
		while cursor < queue.size():
			for next in graph.get_point_connections(queue[cursor]):
				if not components.has(next):
					components[next] = component
					queue.append(next)
			cursor += 1
		component += 1

func _connect_point(index: Vector3i) -> void:
	var id: int = ids[index]
	for direction: Vector2i in LevelData.DIRS:
		for offset in [-1, 0, 1]:
			var other := Vector3i(index.x + direction.x, index.y + offset, index.z + direction.y)
			if not ids.has(other):
				continue
			var next: int = ids[other]
			if graph.are_points_connected(id, next):
				continue
			var shore := movement == "amphibious" and (
				data.is_water_layer(Vector2i(index.x,index.z),index.y) \
				or data.is_water_layer(Vector2i(other.x,other.z),other.y))
			if offset != 0 and movement != "air" and not shore and not _stair_connects(index, other):
				continue
			if _edge_clear(graph.get_point_position(id), graph.get_point_position(next)):
				graph.connect_points(id, next)

func _stair_connects(a: Vector3i, b: Vector3i) -> bool:
	var cell := Vector2i(a.x, a.z)
	var stair_index := data.stair_at(cell, a.y)
	if stair_index < 0:
		return false
	var stair: Dictionary = data.stairs[stair_index]
	var low: Vector2i = stair.cell
	var high: Vector2i = low + LevelData.DIRS[int(stair.direction)]
	return (cell == low and Vector2i(b.x, b.z) == high and b.y == a.y + 1) \
		or (cell == high and Vector2i(b.x, b.z) == low and b.y == a.y - 1)

func _edge_clear(a: Vector3, b: Vector3) -> bool:
	for step in [0.25, 0.5, 0.75]:
		var point := a.lerp(b, step)
		for box in blocked_volumes:
			if _body_box(point).intersects(box):
				return false
	return true

func _body_box(point: Vector3) -> AABB:
	return AABB(point + Vector3(-radius, 0.05, -radius),
		Vector3(radius * 2, height, radius * 2))

func clear_at(point: Vector3, cell: Vector2i, layer: int) -> bool:
	if radius >= LevelData.CELL_SIZE * 0.5:
		return false
	var body := _body_box(point)
	for box in blocked_volumes:
		if body.intersects(box):
			return false
	for upper in range(layer + 1, data.layer_count(cell)):
		if data.is_solid_layer(cell, upper) \
				and upper * LevelData.ELEVATION_STEP < body.end.y - 0.01:
			return false
	return true

func nearest_id(point: Vector3) -> int:
	var cell := data.world_to_cell(point)
	var best := -1
	var distance := INF
	for y in range(cell.y - 2, cell.y + 3):
		for x in range(cell.x - 2, cell.x + 3):
			var candidate := Vector2i(x, y)
			for layer in data.layer_count(candidate):
				var index := Vector3i(x, layer, y)
				if not ids.has(index):
					continue
				var id: int = ids[index]
				var d := graph.get_point_position(id).distance_squared_to(point)
				if d < distance:
					best = id
					distance = d
	return best

func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if building:
		return PackedVector3Array()
	var start := nearest_id(from)
	var end := nearest_id(to)
	if start < 0 or end < 0:
		return PackedVector3Array()
	return graph.get_point_path(start, end)

func candidates(center: Vector3, inner: float, outer: float,
		monster: MonsterDefinition, occupied: Array[Vector3] = []) -> Array[int]:
	var result: Array[int] = []
	if building:
		return result
	var player_id := nearest_id(center)
	if player_id < 0:
		return result
	var cell := data.world_to_cell(center)
	var reach := ceili(outer / LevelData.CELL_SIZE) + 1
	for y in range(cell.y - reach, cell.y + reach + 1):
		for x in range(cell.x - reach, cell.x + reach + 1):
			var candidate := Vector2i(x, y)
			for layer in data.layer_count(candidate):
				var index := Vector3i(x, layer, y)
				if not ids.has(index):
					continue
				var id: int = ids[index]
				var point := graph.get_point_position(id)
				var flat := Vector2(point.x - center.x, point.z - center.z).length()
				if flat < inner or flat > outer or components[id] != components[player_id]:
					continue
				if spawn_error(id, monster, occupied).is_empty():
					result.append(id)
	return result

func point_candidates(point: Dictionary, monster: MonsterDefinition,
		occupied: Array[Vector3] = []) -> Array[int]:
	var result: Array[int] = []
	if building:
		return result
	for index: Vector3i in point.get("cells", []):
		if ids.has(index) and spawn_error(ids[index], monster, occupied, true).is_empty():
			result.append(ids[index])
	return result

func spawn_error(id: int, monster: MonsterDefinition, occupied: Array[Vector3] = [],
		fixed_point := false) -> String:
	if not surfaces.has(id):
		return "无可行走表面"
	var index: Vector3i = surfaces[id]
	var cell := Vector2i(index.x, index.z)
	if not fixed_point and EncounterRegions.zone(data, cell, index.y) != 0:
		return "时间静止区"
	if EncounterRegions.forbidden(data, cell, index.y):
		return "禁止生成区域"
	if monster != null and ObjectRules.ecosystem_at(data, cell, index.y) not in monster.ecosystems:
		return "生态不匹配"
	if data.stair_at(cell, index.y) >= 0:
		return "阶梯生成点"
	var point := graph.get_point_position(id)
	for actor in occupied:
		if actor.distance_to(point) < radius * 2 + 0.2:
			return "其他怪物占用"
	return ""
