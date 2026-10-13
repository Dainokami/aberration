@tool
class_name TerrainEdgeBuilder
extends RefCounted

static func make_top_mesh(data: LevelData, cell: Vector2i,
		tile: TileDefinition, corner_segments: int) -> ArrayMesh:
	var points := _top_polygon(data, cell, tile, corner_segments)
	return _top_mesh_from_polygon(points, Vector3.ZERO)

static func make_top_group_mesh(data: LevelData, cells: Array,
		tile: TileDefinition, corner_segments: int, surface_offset: float) -> ArrayMesh:
	if cells.is_empty():
		return null
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := LevelData.CELL_SIZE * 0.5
	for cell: Vector2i in cells:
		var points := _top_polygon(data, cell, tile, corner_segments)
		var indices := Geometry2D.triangulate_polygon(points)
		var center := data.world_center(cell) + Vector3(0, surface_offset, 0)
		for index in indices:
			var point := points[index]
			tool.set_uv(Vector2(
				(point.x + half) / LevelData.CELL_SIZE,
				(point.y + half) / LevelData.CELL_SIZE))
			tool.add_vertex(center + Vector3(point.x, 0.0, point.y))
	tool.generate_normals()
	return tool.commit()

static func make_blended_top_mesh(data: LevelData, cells: Array,
		corner_segments: int, surface_offset: float) -> ArrayMesh:
	if cells.is_empty():
		return null
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := LevelData.CELL_SIZE * 0.5
	for cell: Vector2i in cells:
		var tile := TileRegistry.find(data.tile_id(cell))
		if tile == null:
			continue
		var points := _top_polygon(data, cell, tile, corner_segments)
		var indices := Geometry2D.triangulate_polygon(points)
		var center := data.world_center(cell) + Vector3(0, surface_offset, 0)
		for index in indices:
			var point := points[index]
			tool.set_uv(Vector2(
				(point.x + half) / LevelData.CELL_SIZE,
				(point.y + half) / LevelData.CELL_SIZE))
			tool.add_vertex(center + Vector3(point.x, 0.0, point.y))
	tool.generate_normals()
	return tool.commit()

static func _top_polygon(data: LevelData, cell: Vector2i,
		tile: TileDefinition, corner_segments: int) -> PackedVector2Array:
	var half := LevelData.CELL_SIZE * 0.5
	var radius := clampf(tile.corner_radius_m, 0.0, half * 0.9)
	var exposed := []
	for direction in 4:
		var neighbor: Vector2i = cell + LevelData.DIRS[direction]
		exposed.append(not data.cell_exists(neighbor)
			or data.elevation(neighbor) < data.elevation(cell))
	var points := PackedVector2Array()
	_append_top_corner(points, Vector2(-half + radius, -half + radius),
		PI, PI * 1.5, exposed[3] and exposed[0], radius, corner_segments,
		Vector2(-half, -half))
	_append_top_corner(points, Vector2(half - radius, -half + radius),
		PI * 1.5, PI * 2.0, exposed[0] and exposed[1], radius, corner_segments,
		Vector2(half, -half))
	_append_top_corner(points, Vector2(half - radius, half - radius),
		0.0, PI * 0.5, exposed[1] and exposed[2], radius, corner_segments,
		Vector2(half, half))
	_append_top_corner(points, Vector2(-half + radius, half - radius),
		PI * 0.5, PI, exposed[2] and exposed[3], radius, corner_segments,
		Vector2(-half, half))
	return points

static func _top_mesh_from_polygon(points: PackedVector2Array,
		offset: Vector3) -> ArrayMesh:
	var half := LevelData.CELL_SIZE * 0.5
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.is_empty():
		return null
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		var point := points[index]
		tool.set_uv(Vector2(
			(point.x + half) / LevelData.CELL_SIZE,
			(point.y + half) / LevelData.CELL_SIZE))
		tool.add_vertex(offset + Vector3(point.x, 0.0, point.y))
	tool.generate_normals()
	return tool.commit()

static func cliff_groups(data: LevelData) -> Array[Dictionary]:
	var grouped := {}
	for y in data.map_size.y:
		for x in data.map_size.x:
			var cell := Vector2i(x, y)
			if not data.cell_exists(cell) or data.stair_at(cell) >= 0:
				continue
			var tile := TileRegistry.find(data.tile_id(cell))
			if tile == null or tile.is_water():
				continue
			var high_level := data.elevation(cell)
			for direction in 4:
				var neighbor: Vector2i = cell + LevelData.DIRS[direction]
				var low_level := -1
				if data.cell_exists(neighbor):
					low_level = data.elevation(neighbor)
				if high_level <= low_level:
					continue
				var key := "%s|%d|%d" % [tile.tile_id, high_level, low_level]
				if not grouped.has(key):
					grouped[key] = {
						"tile": tile,
						"high_level": high_level,
						"low_level": low_level,
						"edges": [],
					}
				grouped[key]["edges"].append(_edge_for(cell, direction))
	var result: Array[Dictionary] = []
	for group: Dictionary in grouped.values():
		result.append(group)
	return result

static func foam_groups(data: LevelData) -> Array[Dictionary]:
	var grouped := {}
	for y in data.map_size.y:
		for x in data.map_size.x:
			var cell := Vector2i(x, y)
			if not data.cell_exists(cell) or data.stair_at(cell) >= 0:
				continue
			var land := TileRegistry.find(data.tile_id(cell))
			if land == null or land.is_water():
				continue
			for direction in 4:
				var neighbor: Vector2i = cell + LevelData.DIRS[direction]
				if not data.cell_exists(neighbor) or data.stair_at(neighbor) >= 0:
					continue
				var water := TileRegistry.find(data.tile_id(neighbor))
				if water == null or not water.is_water():
					continue
				var water_level := data.elevation(neighbor)
				if water_level > data.elevation(cell):
					continue
				var key := "%s|%s|%d" % [land.tile_id, water.tile_id, water_level]
				if not grouped.has(key):
					grouped[key] = {
						"land": land,
						"water": water,
						"water_level": water_level,
						"edges": [],
					}
				grouped[key]["edges"].append(_edge_for(cell, direction))
	var result: Array[Dictionary] = []
	for group: Dictionary in grouped.values():
		result.append(group)
	return result

static func traced_world_paths(data: LevelData, edges: Array,
		radius: float, corner_segments: int) -> Array[PackedVector2Array]:
	var grid_paths := _trace_grid_paths(edges)
	var result: Array[PackedVector2Array] = []
	for grid_path in grid_paths:
		var world_path := PackedVector2Array()
		for point: Vector2i in grid_path:
			world_path.append(_grid_vertex_to_world(data, point))
		result.append(_smooth_path(world_path, radius, corner_segments))
	return result

static func make_cliff_mesh(path: PackedVector2Array, high_y: float, low_y: float,
		texture_span: Vector2) -> ArrayMesh:
	if path.size() < 2 or high_y <= low_y:
		return null
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lengths := _path_lengths(path)
	for i in path.size():
		var point := path[i]
		var u := lengths[i] / maxf(texture_span.x, 0.001)
		tool.set_uv(Vector2(u, -high_y / maxf(texture_span.y, 0.001)))
		tool.add_vertex(Vector3(point.x, high_y, point.y))
		tool.set_uv(Vector2(u, -low_y / maxf(texture_span.y, 0.001)))
		tool.add_vertex(Vector3(point.x, low_y, point.y))
	for i in path.size() - 1:
		var a := i * 2
		var b := a + 2
		tool.add_index(a)
		tool.add_index(a + 1)
		tool.add_index(b)
		tool.add_index(b)
		tool.add_index(a + 1)
		tool.add_index(b + 1)
	tool.generate_normals()
	return tool.commit()

static func make_rim_mesh(path: PackedVector2Array, high_y: float,
		tile: TileDefinition, style: TerrainStyleProfile) -> ArrayMesh:
	if path.size() < 2 or not tile.has_soft_rim():
		return null
	var profile := _cross_section(tile, style.rim_segments)
	if profile.size() < 2:
		return null
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lengths := _path_lengths(path)
	var closed := path.size() > 2 and path[0].is_equal_approx(path[path.size() - 1])
	for i in path.size():
		var tangent := _path_tangent(path, i, closed)
		var outward := Vector2(tangent.y, -tangent.x).normalized()
		for j in profile.size():
			var sample: Vector2 = profile[j]
			var t := float(j) / float(profile.size() - 1)
			var u := lengths[i] / maxf(tile.rim_u_span_m, 0.001)
			tool.set_uv(Vector2(u, lerpf(tile.rim_alpha_range.x, tile.rim_alpha_range.y, t)))
			tool.set_uv2(Vector2(t, 0.0))
			tool.add_vertex(Vector3(
				path[i].x + outward.x * sample.x,
				high_y + sample.y + style.rim_surface_offset_m,
				path[i].y + outward.y * sample.x))
	for i in path.size() - 1:
		for j in profile.size() - 1:
			var a := i * profile.size() + j
			var b := (i + 1) * profile.size() + j
			tool.add_index(a)
			tool.add_index(a + 1)
			tool.add_index(b)
			tool.add_index(b)
			tool.add_index(a + 1)
			tool.add_index(b + 1)
	tool.generate_normals()
	return tool.commit()

static func make_foam_mesh(path: PackedVector2Array, water_y: float,
		water: TileDefinition, style: TerrainStyleProfile) -> ArrayMesh:
	if path.size() < 2 or water.foam_texture_path.is_empty():
		return null
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lengths := _path_lengths(path)
	var closed := path.size() > 2 and path[0].is_equal_approx(path[path.size() - 1])
	for i in path.size():
		var tangent := _path_tangent(path, i, closed)
		var outward := Vector2(tangent.y, -tangent.x).normalized()
		var u := lengths[i] / maxf(water.foam_u_span_m, 0.001)
		for j in 2:
			var across := float(j)
			tool.set_uv(Vector2(u, lerpf(
				water.foam_alpha_range.x, water.foam_alpha_range.y, across)))
			tool.add_vertex(Vector3(
				path[i].x + outward.x * water.foam_width_m * across,
				water_y + style.foam_surface_offset_m,
				path[i].y + outward.y * water.foam_width_m * across))
	for i in path.size() - 1:
		var a := i * 2
		var b := a + 2
		tool.add_index(a)
		tool.add_index(b)
		tool.add_index(a + 1)
		tool.add_index(b)
		tool.add_index(b + 1)
		tool.add_index(a + 1)
	tool.generate_normals()
	return tool.commit()

static func _edge_for(cell: Vector2i, direction: int) -> Dictionary:
	match direction:
		0:
			return {"start": cell, "end": cell + Vector2i(1, 0)}
		1:
			return {"start": cell + Vector2i(1, 0), "end": cell + Vector2i(1, 1)}
		2:
			return {"start": cell + Vector2i(1, 1), "end": cell + Vector2i(0, 1)}
		_:
			return {"start": cell + Vector2i(0, 1), "end": cell}

static func _append_top_corner(points: PackedVector2Array, center: Vector2,
		from_angle: float, to_angle: float, rounded: bool, radius: float,
		segments: int, square_corner: Vector2) -> void:
	if not rounded or radius <= 0.001:
		points.append(square_corner)
		return
	for step in maxi(segments, 2) + 1:
		var angle := lerpf(from_angle, to_angle,
			float(step) / float(maxi(segments, 2)))
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

static func _trace_grid_paths(edges: Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var used := {}
	for first_index in edges.size():
		if used.has(first_index):
			continue
		var path := PackedVector2Array()
		var edge: Dictionary = edges[first_index]
		used[first_index] = true
		path.append(edge["start"])
		path.append(edge["end"])
		var current: Vector2i = edge["end"]
		var guard := edges.size() + 1
		while guard > 0 and Vector2(current) != path[0]:
			guard -= 1
			var next_index := -1
			for candidate in edges.size():
				if used.has(candidate):
					continue
				if edges[candidate]["start"] == current:
					next_index = candidate
					break
			if next_index < 0:
				break
			used[next_index] = true
			current = edges[next_index]["end"]
			path.append(current)
		result.append(path)
	return result

static func _grid_vertex_to_world(data: LevelData, point: Vector2i) -> Vector2:
	var origin := -Vector2(data.map_size) * LevelData.CELL_SIZE * 0.5
	return origin + Vector2(point) * LevelData.CELL_SIZE

static func _smooth_path(path: PackedVector2Array, radius: float,
		segments: int) -> PackedVector2Array:
	if path.size() < 3 or radius <= 0.001:
		return path
	var closed := path[0] == path[path.size() - 1]
	var points := path.duplicate()
	if closed:
		points.remove_at(points.size() - 1)
	var result := PackedVector2Array()
	for i in points.size():
		if not closed and (i == 0 or i == points.size() - 1):
			result.append(points[i])
			continue
		var previous: Vector2 = points[posmod(i - 1, points.size())]
		var current: Vector2 = points[i]
		var following: Vector2 = points[(i + 1) % points.size()]
		var incoming := (current - previous).normalized()
		var outgoing := (following - current).normalized()
		if absf(incoming.cross(outgoing)) < 0.001:
			result.append(current)
			continue
		var local_radius := minf(radius, minf(
			previous.distance_to(current) * 0.45,
			current.distance_to(following) * 0.45))
		var before := current - incoming * local_radius
		var after := current + outgoing * local_radius
		result.append(before)
		for step in range(1, maxi(segments, 2) + 1):
			var t := float(step) / float(maxi(segments, 2))
			result.append(before * (1.0 - t) * (1.0 - t)
				+ current * 2.0 * (1.0 - t) * t + after * t * t)
	if closed and not result.is_empty():
		result.append(result[0])
	return result

static func _path_lengths(path: PackedVector2Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(path.size())
	var total := 0.0
	for i in path.size():
		if i > 0:
			total += path[i - 1].distance_to(path[i])
		result[i] = total
	return result

static func _path_tangent(path: PackedVector2Array, index: int, closed: bool) -> Vector2:
	var last := path.size() - 1
	if closed:
		var previous := path[last - 1] if index == 0 or index == last else path[index - 1]
		var following := path[1] if index == 0 or index == last else path[index + 1]
		return (following - previous).normalized()
	if index == 0:
		return (path[1] - path[0]).normalized()
	if index == last:
		return (path[last] - path[last - 1]).normalized()
	return (path[index + 1] - path[index - 1]).normalized()

static func _cross_section(tile: TileDefinition, segments: int) -> PackedVector2Array:
	if not tile.grass_roll_profile.is_empty():
		return PackedVector2Array(tile.grass_roll_profile)
	var result := PackedVector2Array()
	for step in maxi(segments, 2) + 1:
		var t := float(step) / float(maxi(segments, 2))
		var distance := -tile.rim_inset_m + tile.rim_inset_m * sin(PI * t * 0.5)
		var height := -tile.rim_drop_m + tile.rim_drop_m * cos(PI * t * 0.5)
		result.append(Vector2(distance, height))
	return result
