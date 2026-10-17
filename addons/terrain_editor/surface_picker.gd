@tool
extends RefCounted

const BlockPicker := preload("res://addons/terrain_editor/block_picker.gd")

static func pick(builder: TerrainBuilder, camera: Camera3D, mouse: Vector2,
		ignore_id := "", target_definition: PlaceableDefinition = null) -> Dictionary:
	if builder.get_world_3d() == null:
		return {}
	var origin := camera.project_ray_origin(mouse)
	if target_definition != null and target_definition.requires_seabed:
		var inverse := builder.global_transform.affine_inverse()
		var hit := BlockPicker.raycast(builder.level_data, inverse * origin,
			inverse.basis * camera.project_ray_normal(mouse), builder.slice_layer_limit)
		if not hit.is_empty() and builder.level_data.is_water_layer(hit.cell, hit.layer):
			var data := builder.level_data
			var cell: Vector2i = hit.cell
			var layer := int(hit.layer)
			while data.is_water_layer(cell, layer):
				layer -= 1
			if not data.is_solid_layer(cell, layer) or not data.is_surface_exposed(cell, layer) \
					or data.stair_at(cell, layer) >= 0:
				return {"error": "水块下方没有海底实体地形；请先在水底放置草原、岩石或沙漠地块"}
			var point: Vector3 = hit.position
			point.y = data.surface_y(layer)
			return {"kind": "terrain", "cell": cell, "layer": layer,
				"position": point, "normal": Vector3.UP, "through_water": true}
	var end := origin + camera.project_ray_normal(mouse) * 1000.0
	var excluded: Array[RID] = []
	for attempt in 64:
		var query := PhysicsRayQueryParameters3D.create(origin, end)
		query.exclude = excluded
		query.collide_with_areas = false
		var hit := builder.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider: Node = hit["collider"]
		var root := collider
		while root != null and root != builder and not root.has_meta("object_id"):
			root = root.get_parent()
		var id := str(root.get_meta("object_id", "")) if root != null else ""
		if not builder.is_ancestor_of(collider) or (not ignore_id.is_empty() and id == ignore_id):
			excluded.append(hit["rid"])
			continue
		var inverse := builder.global_transform.affine_inverse()
		var position: Vector3 = inverse * (hit["position"] as Vector3)
		var normal: Vector3 = (inverse.basis * (hit["normal"] as Vector3)).normalized()
		if not id.is_empty():
			return {"kind": "object", "id": id, "position": position, "normal": normal}
		if collider.has_meta("terrain_cell"):
			var cell: Vector2i = collider.get_meta("terrain_cell")
			var layer := int(collider.get_meta("terrain_layer", -1))
			if normal.y > 0.7 and (collider.get_meta("slice_cap", false) \
					or not builder.level_data.is_surface_exposed(cell, layer)):
				return {"error": "这里是切片显示的临时盖面；请显示真实顶面后再摆放"}
			return {"kind": "terrain", "cell": cell, "layer": layer,
				"position": position, "normal": normal}
		# Stairs and unrelated collision are not valid flat supports.
		return {"error": "此处不是可摆放的平面"}
	return {}

static func placement(data: LevelData, record: Dictionary, surface: Dictionary,
		snap := true) -> Dictionary:
	if surface.is_empty() or surface.has("error") or record.is_empty():
		return {}
	var d := ObjectRules.definition(record)
	if d == null:
		return {}
	var copy := record.duplicate(true)
	var normal: Vector3 = surface["normal"]
	var point: Vector3 = surface["position"]
	var wall := d.carrier == PlaceableDefinition.Carrier.WALL
	if not wall and normal.y < 0.7:
		return {}
	if wall and absf(normal.y) > 0.1:
		return {}
	if surface["kind"] == "terrain":
		var cell: Vector2i = surface["cell"]
		if wall:
			if maxf(absf(normal.x), absf(normal.z)) < 0.98:
				return {}
			var direction := direction_for(normal)
			if data.has_terrain_volume(cell + LevelData.DIRS[direction], int(surface["layer"])):
				return {}
			var offset := Vector2.ZERO
			if not snap:
				var center := data.world_center(cell, int(surface["layer"])) - Vector3.UP * LevelData.ELEVATION_STEP
				var relative := point - center
				var size := d.image_size * float(copy.get("scale", 1.0))
				offset = Vector2(relative.dot(Vector3(normal.z, 0, -normal.x)),
					relative.y - size.y * 0.5)
				offset.x = clampf(offset.x, -maxf(0, (LevelData.CELL_SIZE - size.x) * 0.5),
					maxf(0, (LevelData.CELL_SIZE - size.x) * 0.5))
				offset.y = clampf(offset.y, 0, maxf(0, LevelData.ELEVATION_STEP - size.y))
			return ObjectRules.wall_anchor(data, copy, cell, int(surface["layer"]), direction, offset)
		var layer := int(surface["layer"])
		if not data.is_surface_exposed(cell, layer):
			return {}
		copy["position"] = data.world_center(cell, layer) if snap else Vector3(
			point.x, data.surface_y(layer), point.z)
		copy["anchor_kind"] = "top"
		copy.erase("support_id")
		return ObjectRules.anchor_record(data, copy)
	var parent := ObjectRules.find_record(data, surface["id"])
	var parent_d := ObjectRules.definition(parent)
	if parent_d == null or not parent_d.supports_objects:
		return {}
	var transform := ObjectRules.transform_of(parent)
	var local := transform.affine_inverse() * point
	var direction := 2
	if wall:
		var local_normal := (transform.basis.inverse() * normal).normalized()
		direction = direction_for(local_normal)
		local_normal = ObjectRules.wall_normal(direction)
		var relative_size := d.image_size * float(copy.get("scale", 1.0)) / float(parent.get("scale", 1.0))
		var offset := parent_d.collision_offset
		var half := parent_d.collision_size * 0.5
		var width := parent_d.collision_size.x if direction % 2 == 0 else parent_d.collision_size.z
		var tangent := Vector3(local_normal.z, 0, -local_normal.x)
		var along := 0.0 if snap else clampf((local - offset).dot(tangent),
			-maxf(0, (width - relative_size.x) * 0.5), maxf(0, (width - relative_size.x) * 0.5))
		var height := 0.0 if snap else clampf(local.y - offset.y - relative_size.y * 0.5,
			0, maxf(0, parent_d.collision_size.y - relative_size.y))
		local = offset + local_normal * (half.z if direction % 2 == 0 else half.x) \
			+ tangent * along + Vector3.UP * height
		copy["yaw"] = float(parent.get("yaw", 0.0)) + atan2(local_normal.x, local_normal.z)
	else:
		if snap:
			local.x = parent_d.collision_offset.x
			local.z = parent_d.collision_offset.z
		local.y = parent_d.collision_offset.y + parent_d.collision_size.y
	return ObjectRules.object_anchor(data, copy, surface["id"], transform * local, wall, direction)

static func direction_for(normal: Vector3) -> int:
	if absf(normal.x) > absf(normal.z):
		return 1 if normal.x > 0 else 3
	return 2 if normal.z > 0 else 0
