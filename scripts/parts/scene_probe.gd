class_name SceneProbe
extends RefCounted

# 部件和关卡之间只经过这里。
# 查到的是表面标签和交互物种类，不是地形网格、生态或关卡资源。


static func tags_at(point: Vector3) -> PackedStringArray:
	var found := PackedStringArray()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		found.append("hard")
		return found
	for node in tree.get_nodes_in_group("surface_zone"):
		var zone := node as SurfaceZone
		if zone == null or not zone.covers(point):
			continue
		for tag in zone.tags:
			if not found.has(tag):
				found.append(tag)
	if found.is_empty():
		found.append("hard")
	return found


static func nearest(origin: Vector3, radius: float, kinds: PackedStringArray) -> AffordanceProp:
	var best: AffordanceProp = null
	var best_distance := radius
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("affordance"):
		var prop := node as AffordanceProp
		if prop == null or prop.spent or not kinds.has(prop.kind):
			continue
		var distance := origin.distance_to(prop.global_position)
		if distance > best_distance:
			continue
		best_distance = distance
		best = prop
	return best


static func nearest_reachable(actor: CollisionObject3D, radius: float, kinds: PackedStringArray) -> AffordanceProp:
	if actor == null or not actor.is_inside_tree():
		return null
	var best: AffordanceProp = null
	var best_distance := radius
	var eye := actor.global_position + Vector3.UP * 0.65
	for prop in each_kind(kinds):
		var target := prop.interaction_point()
		var distance := actor.global_position.distance_to(target)
		if distance > best_distance:
			continue
		if not is_reachable(actor, prop, eye, target):
			continue
		best_distance = distance
		best = prop
	return best


static func is_reachable(actor: CollisionObject3D, prop: AffordanceProp,
		eye := Vector3.INF, target := Vector3.INF) -> bool:
	if actor == null or prop == null or not actor.is_inside_tree():
		return false
	if not eye.is_finite():
		eye = actor.global_position + Vector3.UP * 0.65
	if not target.is_finite():
		target = prop.interaction_point()
	var query := PhysicsRayQueryParameters3D.create(eye, target, 1, [actor.get_rid()])
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or prop.owns_collider(hit.get("collider")):
		return true
	# 攀爬标记贴在地形碰撞面上，本身没有碰撞体；射线命中标记所在表面可用。
	var hit_at: Vector3 = hit.get("position", Vector3.INF)
	return prop.kind == "climbable" and hit_at.distance_to(target) <= 0.75


static func each_kind(kinds: PackedStringArray) -> Array[AffordanceProp]:
	var found: Array[AffordanceProp] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return found
	for node in tree.get_nodes_in_group("affordance"):
		var prop := node as AffordanceProp
		if prop == null or prop.spent or not kinds.has(prop.kind):
			continue
		found.append(prop)
	return found
