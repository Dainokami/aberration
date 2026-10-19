class_name LevelPortalPlacement
extends RefCounted

const PLAYER_HEIGHT := 1.6
const PLAYER_RADIUS := 0.34
const PORTAL_SIZE := Vector3(1.8, 3.2, 0.7)

## Only build the nearby cells. Monster ecology and region flags do not apply.
static func find_position(data: LevelData, player: CharacterBody3D,
		config: LevelTransitionConfig) -> Vector3:
	if not player.is_on_floor():
		return Vector3.INF
	var feet := player.global_position - Vector3.UP * 0.8
	var block := data.world_to_block(feet + Vector3.UP * 0.03)
	var support := Vector3i(block.x, block.y - 1, block.z)
	var cell := Vector2i(block.x, block.z)
	if not data.is_solid_layer(cell, support.y) or data.is_water_layer(cell, block.y):
		return Vector3.INF
	var reach := ceili(config.radius_max / LevelData.CELL_SIZE) + 2
	var view := data.region_view(Rect2i(cell - Vector2i.ONE * reach,
		Vector2i.ONE * (reach * 2 + 1)))
	view.objects = data.objects
	var nav := EncounterNavigation.new()
	nav.build(view)
	if not nav.ids.has(support):
		# On the upper half of a ramp the player's feet can still be below the
		# upper block's top. Match the authored stair surface in that same cell.
		for layer in data.layer_count(cell):
			var stair_support := Vector3i(cell.x, layer, cell.y)
			if data.stair_at(cell, layer) >= 0 and nav.ids.has(stair_support) \
					and absf(nav.graph.get_point_position(nav.ids[stair_support]).y - feet.y) < 0.6:
				support = stair_support
				break
		if not nav.ids.has(support):
			return Vector3.INF
	var space := player.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = PLAYER_RADIUS
	capsule.height = PLAYER_HEIGHT
	var body_query := PhysicsShapeQueryParameters3D.new()
	body_query.shape = capsule
	body_query.collision_mask = 1
	body_query.exclude = [player.get_rid()]
	var portal_query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = PORTAL_SIZE
	portal_query.shape = box
	portal_query.collision_mask = 1
	portal_query.exclude = [player.get_rid()]
	var queue: Array[int] = [int(nav.ids[support])]
	var visited := {queue[0]: true}
	var cursor := 0
	var best := Vector3.INF
	var best_distance := INF
	while cursor < queue.size():
		var id := queue[cursor]
		cursor += 1
		var point := nav.graph.get_point_position(id)
		var flat := Vector2(point.x - feet.x, point.z - feet.z).length()
		var index: Vector3i = nav.surfaces[id]
		if flat >= config.radius_min and flat <= config.radius_max \
				and flat < best_distance and data.stair_at(Vector2i(index.x, index.z), index.y) < 0:
			portal_query.transform = Transform3D(Basis.IDENTITY,
				point + Vector3.UP * (PORTAL_SIZE.y * 0.5 + 0.04))
			if space.intersect_shape(portal_query, 1).is_empty():
				best = point
				best_distance = flat
		for next in nav.graph.get_point_connections(id):
			if visited.has(next):
				continue
			var destination := nav.graph.get_point_position(next)
			if not _walkable_edge(space, body_query, point, destination):
				continue
			visited[next] = true
			queue.append(next)
	return best

static func _walkable_edge(space: PhysicsDirectSpaceState3D,
		query: PhysicsShapeQueryParameters3D, from: Vector3, to: Vector3) -> bool:
	# At the ends of a ramp the floor is not a straight line between cell centers.
	# Sample its real surface before sweeping the player's capsule along it.
	var steps := 8 if not is_equal_approx(from.y, to.y) else 1
	var previous := from
	for i in range(1, steps + 1):
		var point := from.lerp(to, float(i) / steps)
		if steps > 1:
			var ground_query := PhysicsRayQueryParameters3D.create(
				point + Vector3.UP * 0.4, point - Vector3.UP * 0.4, 1, query.exclude)
			var ground := space.intersect_ray(ground_query)
			if ground.is_empty() or Vector3(ground.normal).y < 0.64:
				return false
			point = ground.position
		query.motion = Vector3.ZERO
		query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.88)
		if not space.intersect_shape(query, 1).is_empty():
			return false
		query.transform.origin = previous + Vector3.UP * 0.88
		query.motion = point - previous
		if space.cast_motion(query)[0] < 0.99:
			return false
		previous = point
	return true
