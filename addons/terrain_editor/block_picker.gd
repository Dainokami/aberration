@tool
extends RefCounted

## Logical voxel picking does not depend on rounded art, collision updates, or
## decorative objects. Coordinates and normals are local to TerrainBuilder.
static func raycast(data: LevelData, origin: Vector3, direction: Vector3,
		slice_limit := -1) -> Dictionary:
	var highest := LevelData.MAX_LAYERS - 1 if slice_limit < 0 else slice_limit
	var corner := data.map_world_origin()
	var minimum := Vector3(corner.x, 0, corner.y)
	var maximum := minimum + Vector3(data.map_size.x * LevelData.CELL_SIZE,
		data.surface_y(highest), data.map_size.y * LevelData.CELL_SIZE)
	var entry := 0.0
	var exit := INF
	var normal := Vector3i.ZERO
	for axis in 3:
		if absf(direction[axis]) < 0.000001:
			if origin[axis] < minimum[axis] or origin[axis] >= maximum[axis]:
				return {}
			continue
		var near := (minimum[axis] - origin[axis]) / direction[axis]
		var far := (maximum[axis] - origin[axis]) / direction[axis]
		if near > far:
			var swap := near
			near = far
			far = swap
		if near > entry:
			entry = near
			normal = Vector3i.ZERO
			normal[axis] = -1 if direction[axis] > 0 else 1
		exit = minf(exit, far)
	if entry > exit or exit < 0:
		return {}
	var point := origin + direction * (entry + 0.0001)
	var block := data.world_to_block(point)
	var step := Vector3i.ZERO
	var next := Vector3(INF, INF, INF)
	var delta := Vector3(INF, INF, INF)
	var grid_origin := Vector3(data.grid_world_origin.x, 0, data.grid_world_origin.y)
	var sizes := Vector3(LevelData.CELL_SIZE, LevelData.ELEVATION_STEP, LevelData.CELL_SIZE)
	for axis in 3:
		if absf(direction[axis]) < 0.000001:
			continue
		step[axis] = 1 if direction[axis] > 0 else -1
		var boundary := grid_origin[axis] + (
			block[axis] + (1 if step[axis] > 0 else 0)) * sizes[axis]
		next[axis] = (boundary - origin[axis]) / direction[axis]
		delta[axis] = absf(sizes[axis] / direction[axis])
	if normal == Vector3i.ZERO:
		normal[direction.abs().max_axis_index()] = -step[direction.abs().max_axis_index()]
	for iteration in data.map_size.x + data.map_size.y + LevelData.MAX_LAYERS + 6:
		var cell := Vector2i(block.x, block.z)
		if not data.in_bounds(cell) or block.y < 0 or block.y > highest or entry > exit:
			break
		if data.layer_exists(cell, block.y):
			return {"cell": cell, "layer": block.y, "block": block,
				"normal": normal, "position": origin + direction * entry}
		var axis := next.min_axis_index()
		entry = next[axis]
		block[axis] += step[axis]
		next[axis] += delta[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return {}
