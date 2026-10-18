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
	if found.has("fluid") or found.has("ocean"):
		# The ground beneath a water volume is not the actor's movement surface.
		for tag in ["grass", "rock", "desert"]:
			var index := found.find(tag)
			if index >= 0:
				found.remove_at(index)
	if found.is_empty():
		found.append("hard")
	return found

static func water_surface_y(point: Vector3) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	var highest := -INF
	if tree == null:
		return highest
	for zone in tree.get_nodes_in_group("surface_zone"):
		if zone is SurfaceZone and zone.tags.has("water_surface"):
			var sample := Vector3(point.x, zone.global_position.y, point.z)
			if zone.covers(sample):
				highest = maxf(highest, zone.global_position.y)
	return highest


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
