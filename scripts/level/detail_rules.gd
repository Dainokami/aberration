@tool
class_name DetailRules
extends RefCounted

const MAX_DETAILS := 50000

static func definition(record: Dictionary) -> DetailSet:
	var path := str(record.get("set", ""))
	return load(path) as DetailSet if ResourceLoader.exists(path) else null

static func validate_record(data: LevelData, record: Dictionary, set: DetailSet = null) -> String:
	if set == null:
		set = definition(record)
	if set == null:
		return "细节套件缺失"
	var variant := set.variant_index(str(record.get("variant", "")))
	if variant < 0:
		return "细节变体不存在"
	var position: Vector3 = record.get("position", Vector3(INF, INF, INF))
	var scale_value := float(record.get("scale", 1.0))
	var yaw := float(record.get("yaw", 0.0))
	if not position.is_finite() or not is_finite(scale_value) or scale_value < 0.25 \
			or scale_value > 4.0 or not is_finite(yaw):
		return "细节位置、朝向或尺寸无效"
	var cell := data.world_to_cell(position)
	var layer := int(record.get("anchor_layer", -1))
	if record.get("anchor_cell", cell) != cell or not data.layer_exists(cell, layer) \
			or data.stair_at(cell, layer) >= 0 \
			or not data.get_attachment(cell, "liquid", layer).is_empty() \
			or absf(position.y - data.surface_y(layer)) > 0.02:
		return "细节需要对应高度的真实、干燥地面"
	for covered in support_cells(data, record, set):
		if not data.layer_exists(covered, layer) or data.stair_at(covered, layer) >= 0 \
				or not data.get_attachment(covered, "liquid", layer).is_empty():
			return "贴地细节跨出地面、阶梯或高差边缘"
	return ""

static func support_cells(data: LevelData, record: Dictionary, set: DetailSet) -> Array[Vector2i]:
	var position: Vector3 = record["position"]
	var cells: Array[Vector2i] = [data.world_to_cell(position)]
	if set.orientation != DetailSet.DetailOrientation.GROUND:
		return cells
	var value: Dictionary = set.variants[set.variant_index(str(record["variant"]))]
	var size: Vector2 = value["size"] * float(record.get("scale", 1.0))
	var pivot: Vector2 = value.get("pivot", Vector2(0.5, 0.5))
	var rotation := Basis(Vector3.UP, float(record.get("yaw", 0.0)))
	var steps := Vector2i(maxi(1, ceili(size.x)), maxi(1, ceili(size.y)))
	for y in steps.y + 1:
		for x in steps.x + 1:
			var uv := Vector2(float(x) / steps.x, float(y) / steps.y)
			var point := position + rotation * Vector3(
				(uv.x - pivot.x) * size.x, 0, (uv.y - pivot.y) * size.y)
			var cell := data.world_to_cell(point.lerp(position, 0.001))
			if cell not in cells:
				cells.append(cell)
	return cells

static func is_hidden(data: LevelData, record: Dictionary, set: DetailSet = null) -> bool:
	var layer := int(record.get("anchor_layer", -1))
	if not data.is_surface_exposed(record.get("anchor_cell", Vector2i(-999, -999)), layer):
		return true
	if set == null:
		set = definition(record)
	if set == null or set.variant_index(str(record.get("variant", ""))) < 0:
		return true
	for cell in support_cells(data, record, set):
		if not data.is_surface_exposed(cell, layer):
			return true
	return false

static func validate_all(data: LevelData, check_assets := true) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.details.size() > MAX_DETAILS:
		errors.append("细节总数超过 %d" % MAX_DETAILS)
	var ids := {}
	var sets := {}
	for record in data.details:
		var id := str(record.get("id", ""))
		if id.is_empty() or ids.has(id):
			errors.append("细节 ID 为空或重复")
		ids[id] = true
		var path := str(record.get("set", ""))
		if not sets.has(path):
			sets[path] = definition(record)
			if sets[path] != null and check_assets:
				errors.append_array(sets[path].validate_asset())
		var error := validate_record(data, record, sets[path])
		if not error.is_empty():
			errors.append("细节 %s：%s" % [id.left(6), error])
	return errors

static func make_record(data: LevelData, path: String, variant: String,
		position: Vector3, id := "", seed_value := 0, yaw := 0.0,
		scale_value := 1.0, flip := false) -> Dictionary:
	var cell := data.world_to_cell(position)
	var layer := data.layer_at_surface(position)
	position.y = data.surface_y(layer)
	return {"id": ObjectRules.new_id() if id.is_empty() else id,
		"set": path, "variant": variant, "position": position,
		"anchor_cell": cell, "anchor_layer": layer,
		"seed": seed_value, "yaw": yaw, "scale": scale_value, "flip": flip}

## The seed generates a preview once; the resulting transforms are saved verbatim.
static func scatter(data: LevelData, path: String, center: Vector3, radius: float,
		count: int, seed_value: int, stroke_id: String, variant := -1,
		scale_value := 1.0, spacing := 0.15) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var set := load(path) as DetailSet if ResourceLoader.exists(path) else null
	if set == null or set.variants.is_empty():
		return result
	var wanted := mini(count, MAX_DETAILS - data.details.size())
	if wanted <= 0:
		return result
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var attempts := 0
	var max_attempts := maxi(24, wanted * 8)
	while result.size() < wanted and attempts < max_attempts:
		var selected := variant if variant >= 0 and variant < set.variants.size() \
			else random.randi_range(0, set.variants.size() - 1)
		var instance_scale := scale_value * random.randf_range(0.85, 1.15)
		var yaw := random.randf() * TAU if set.orientation == DetailSet.DetailOrientation.GROUND else 0.0
		var center_radius := maxf(radius, 0.0)
		if set.orientation == DetailSet.DetailOrientation.GROUND:
			center_radius = maxf(center_radius - _footprint_radius(
				set.variants[selected], instance_scale), 0.0)
		var angle := random.randf() * TAU
		var distance := sqrt(random.randf()) * center_radius
		var position := center + Vector3(cos(angle), 0, sin(angle)) * distance
		var record := make_record(data, path, str(set.variants[selected]["id"]),
			position, "%s_%d" % [stroke_id, attempts], seed_value, yaw,
			instance_scale, random.randf() > 0.5)
		attempts += 1
		if not validate_record(data, record, set).is_empty() or is_hidden(data, record, set):
			continue
		if not _crowded(data.details, result, record["position"], spacing):
			result.append(record)
	# A near-cell-sized decal has very little valid random-center area. Give it a
	# deterministic centered chance before reporting that the support is too small.
	if result.is_empty():
		var choices: Array[int] = []
		if variant >= 0 and variant < set.variants.size():
			choices.append(variant)
		else:
			for i in set.variants.size():
				choices.append(i)
		for selected in choices:
			var record := make_record(data, path, str(set.variants[selected]["id"]),
				center, stroke_id + "_center", seed_value, 0.0, scale_value, false)
			if validate_record(data, record, set).is_empty() and not is_hidden(data, record, set) \
					and not _crowded(data.details, result, center, spacing):
				result.append(record)
				break
	return result

static func _footprint_radius(variant: Dictionary, scale_value: float) -> float:
	var size: Vector2 = variant["size"] * scale_value
	var pivot: Vector2 = variant.get("pivot", Vector2(0.5, 0.5))
	var result := 0.0
	for uv in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
		result = maxf(result, Vector2(
			(uv.x - pivot.x) * size.x, (uv.y - pivot.y) * size.y).length())
	return result

static func _crowded(existing: Array, pending: Array[Dictionary],
		position: Vector3, spacing: float) -> bool:
	for record in existing:
		if (record["position"] as Vector3).distance_to(position) < spacing:
			return true
	for record in pending:
		if (record["position"] as Vector3).distance_to(position) < spacing:
			return true
	return false

static func remove_support(data: LevelData, cell: Vector2i, layer: int) -> void:
	for i in range(data.details.size() - 1, -1, -1):
		var record := data.details[i]
		if record.get("anchor_cell") == cell and int(record.get("anchor_layer", -1)) == layer:
			data.details.remove_at(i)

static func prune_invalid(data: LevelData) -> void:
	var sets := {}
	for i in range(data.details.size() - 1, -1, -1):
		var record := data.details[i]
		var path := str(record.get("set", ""))
		if not sets.has(path):
			sets[path] = definition(record)
		if not validate_record(data, record, sets[path]).is_empty():
			data.details.remove_at(i)

static func move_support(data: LevelData, cell: Vector2i, old_top: int, new_top: int) -> void:
	for record in data.details:
		if record.get("anchor_cell") == cell and int(record.get("anchor_layer", -1)) == old_top:
			record["position"] += Vector3.UP * ((new_top - old_top) * LevelData.ELEVATION_STEP)
			record["anchor_layer"] = new_top
