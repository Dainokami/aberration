@tool
class_name LevelPrefab
extends Resource

@export var display_name := "营地"
@export var fragment: LevelData
@export var version := 3

static func fixed_view_rotation_blocker(data: LevelData) -> String:
	if data == null:
		return ""
	for record in data.objects:
		var definition := ObjectRules.definition(record)
		if definition == null or definition.supports_quarter_turns():
			continue
		var label := definition.display_name if not definition.display_name.is_empty() \
			else definition.asset_id
		return label if not label.is_empty() else str(record.get("definition", "")).get_file()
	return ""

static func capture(source: LevelData, region: Rect2i) -> Dictionary:
	if region.size.x <= 0 or region.size.y <= 0 or not source.in_bounds(region.position) or not source.in_bounds(region.end - Vector2i.ONE):
		return {"error": "选区超出地图"}
	var prefab := LevelPrefab.new()
	prefab.fragment = LevelData.new()
	prefab.fragment.setup_blank(region.size)
	var target := prefab.fragment
	target.terrain_tints = source.terrain_tints.duplicate(true)
	for index: Vector3i in source.encounter_regions:
		if region.has_point(Vector2i(index.x, index.z)):
			target.encounter_regions[Vector3i(index.x - region.position.x, index.y,
				index.z - region.position.y)] = source.encounter_regions[index].duplicate(true)
	for y in region.size.y:
		for x in region.size.x:
			var local := Vector2i(x, y)
			target.set_column(local, source.get_column(region.position + local))
	for stair in source.stairs:
		var low: Vector2i = stair["cell"]
		var high: Vector2i = low + LevelData.DIRS[int(stair["direction"])]
		if region.has_point(low) != region.has_point(high):
			return {"error": "选区切断阶梯，请完整包含或避开"}
		if region.has_point(low):
			var copy := stair.duplicate(true)
			copy["cell"] = low - region.position
			copy["layer"] = int(stair.get("layer", source.top_layer(low)))
			target.stairs.append(copy)
	for record in source.objects:
		var inside := false
		var outside := false
		var coverage := ObjectRules.covered_cells(source, record)
		if str(record.get("anchor_kind", "top")) in ["wall", "object_wall"]:
			coverage = [record["anchor_cell"]]
		for cell in coverage:
			inside = inside or region.has_point(cell)
			outside = outside or not region.has_point(cell)
		if inside and outside:
			return {"error": "选区切断物件碰撞占地"}
		if not inside:
			continue
		var copy := record.duplicate(true)
		var anchor: Vector2i = record.get("anchor_cell", source.world_to_cell(record["position"]))
		copy["position"] = target.world_center(anchor - region.position) + (record["position"] - source.world_center(anchor))
		copy["anchor_cell"] = anchor - region.position
		target.objects.append(copy)
	for record in target.objects:
		var parent_id := str(record.get("support_id", ""))
		if not parent_id.is_empty() and ObjectRules.find_record(target, parent_id).is_empty():
			return {"error": "选区切断物件支撑关系，请完整包含宿主和附件"}
	for record in source.details:
		var anchor: Vector2i = record["anchor_cell"]
		if not region.has_point(anchor):
			continue
		var copy := record.duplicate(true)
		copy["anchor_cell"] = anchor - region.position
		copy["position"] = target.world_center(copy["anchor_cell"]) + (
			record["position"] - source.world_center(anchor))
		if not DetailRules.validate_record(target, copy).is_empty():
			return {"error": "选区切断贴地细节，请扩大选区或先擦除边缘细节"}
		target.details.append(copy)
	# Player spawn is deliberately not captured: each level has exactly one.
	return {"error": "", "prefab": prefab}

func rotated_size(turns: int) -> Vector2i:
	return fragment.map_size if posmod(turns, 2) == 0 else Vector2i(fragment.map_size.y, fragment.map_size.x)

func rotate_cell(cell: Vector2i, turns: int) -> Vector2i:
	var size := fragment.map_size
	for step in posmod(turns, 4):
		cell = Vector2i(size.y - 1 - cell.y, cell.x)
		size = Vector2i(size.y, size.x)
	return cell

## Build a candidate snapshot first. Caller commits once, only after all checks pass.
func stamp(destination: LevelData, anchor: Vector2i, turns: int, objects_only := false) -> Dictionary:
	if fragment == null:
		return {"error": "预制数据缺失"}
	fragment.ensure_layout()
	var blocker := fixed_view_rotation_blocker(fragment)
	if posmod(turns, 4) != 0 and not blocker.is_empty():
		return {"error": "预制包含固定视角物件「%s」，只能按原方向投放" % blocker}
	var area := Rect2i(anchor, rotated_size(turns))
	if not destination.in_bounds(anchor) or not destination.in_bounds(area.end - Vector2i.ONE):
		return {"error": "预制超出地图"}
	var candidate := LevelData.new()
	candidate.restore_data(destination.clone_data())
	for index: Vector3i in fragment.encounter_regions:
		var local := Vector2i(index.x, index.z) - fragment.map_origin
		var target := anchor + rotate_cell(local, turns)
		var layer := index.y
		if objects_only:
			layer += candidate.top_layer(target) - fragment.top_layer(Vector2i(index.x, index.z))
		candidate.encounter_regions[Vector3i(target.x, layer, target.y)] = \
			fragment.encounter_regions[index].duplicate(true)
	if not objects_only:
		if area.has_point(candidate.spawn_cell):
			return {"error": "预制覆盖玩家出生点，请先移动出生点"}
		for stair in candidate.stairs:
			for cell: Vector2 in candidate.stair_cells(stair):
				if area.has_point(Vector2i(cell)):
					return {"error": "预制覆盖已有阶梯，请先删除"}
		for record in candidate.objects:
			var coverage := ObjectRules.covered_cells(candidate, record)
			if str(record.get("anchor_kind", "top")) in ["wall", "object_wall"]:
				coverage = [record["anchor_cell"]]
			for cell in coverage:
				if area.has_point(cell):
					return {"error": "预制覆盖已有物件，请先移动或删除"}
		for y in fragment.map_size.y:
			for x in fragment.map_size.x:
				var cell := fragment.map_origin + Vector2i(x, y)
				var rotated := fragment.column_snapshot(cell)
				for layer: Dictionary in rotated["layers"]:
					if layer.is_empty():
						continue
					layer["rotation"] = posmod(int(layer.get("rotation", 0)) + turns, 4)
					for role in ["liquid", "overlay"]:
						var surface: Dictionary = layer.get(role, {})
						if not surface.is_empty():
							surface["rotation"] = posmod(int(surface.get("rotation", 0)) + turns, 4)
				candidate.set_column(anchor + rotate_cell(cell - fragment.map_origin, turns), rotated)
		for stair in fragment.stairs:
			var copy := stair.duplicate(true)
			copy["cell"] = anchor + rotate_cell(stair["cell"] - fragment.map_origin, turns)
			copy["direction"] = posmod(int(stair["direction"]) + turns, 4)
			copy["layer"] = int(stair.get("layer", fragment.top_layer(stair["cell"])))
			candidate.stairs.append(copy)
		for i in range(candidate.details.size() - 1, -1, -1):
			if area.has_point(candidate.details[i]["anchor_cell"]):
				candidate.details.remove_at(i)
		DetailRules.prune_invalid(candidate)
	var rotation_basis := Basis(Vector3.UP, -posmod(turns, 4) * PI * 0.5)
	var remapped_ids := {}
	for record in fragment.objects:
		remapped_ids[str(record["id"])] = ObjectRules.new_id()
	for record in fragment.objects:
		var copy := record.duplicate(true)
		var old_cell: Vector2i = record.get("anchor_cell", fragment.world_to_cell(record["position"]))
		var new_cell := anchor + rotate_cell(old_cell - fragment.map_origin, turns)
		var offset: Vector3 = record["position"] - fragment.world_center(old_cell)
		copy["position"] = candidate.world_center(new_cell) + rotation_basis * offset
		copy["anchor_cell"] = new_cell
		if str(copy.get("anchor_kind", "top")) == "wall":
			copy["wall_direction"] = posmod(int(copy.get("wall_direction", 0)) + turns, 4)
		if objects_only:
			copy["anchor_layer"] = int(record["anchor_layer"]) \
				+ candidate.top_layer(new_cell) - fragment.top_layer(old_cell)
		copy["yaw"] = float(copy.get("yaw", 0.0)) - posmod(turns, 4) * PI * 0.5
		copy["id"] = remapped_ids[str(record["id"])]
		if copy.has("support_id"):
			copy["support_id"] = remapped_ids.get(str(copy["support_id"]), "")
		candidate.objects.append(copy)
	ObjectRules.sync_dependents(candidate)
	for record in fragment.details:
		var copy := record.duplicate(true)
		var old_cell: Vector2i = record["anchor_cell"]
		var new_cell := anchor + rotate_cell(old_cell - fragment.map_origin, turns)
		copy["id"] = ObjectRules.new_id()
		copy["anchor_cell"] = new_cell
		copy["anchor_layer"] = int(record["anchor_layer"])
		if objects_only:
			copy["anchor_layer"] += candidate.top_layer(new_cell) - fragment.top_layer(old_cell)
		copy["position"] = candidate.world_center(new_cell) + rotation_basis * (
			record["position"] - fragment.world_center(old_cell))
		copy["yaw"] = float(record.get("yaw", 0.0)) - posmod(turns, 4) * PI * 0.5
		candidate.details.append(copy)
	# Validate stairs without requiring a spawn point on a work-in-progress map.
	var errors := candidate.validate()
	if not errors.is_empty() and errors[0] == "缺少有效的玩家出生点":
		errors.remove_at(0)
	if not errors.is_empty():
		return {"error": "\n".join(errors)}
	return {"error": "", "snapshot": candidate.clone_data()}
