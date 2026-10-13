@tool
class_name TerrainBlendMap
extends RefCounted

const TILE_IDS := ["grass", "rock", "sand", "water"]

static var _mask_cache: Dictionary = {}

static func supports_tile(tile_id: String) -> bool:
	return TILE_IDS.find(tile_id) >= 0

static func build(data: LevelData, elevation: int,
		style: TerrainStyleProfile) -> Dictionary:
	var pixels_per_cell := maxi(style.blend_pixels_per_cell, 8)
	var image_size := data.map_size * pixels_per_cell
	var image := Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in data.map_size.y:
		for x in data.map_size.x:
			var cell := Vector2i(x, y)
			if not _belongs_to_level(data, cell, elevation):
				continue
			_paint_cell(image, data, cell, style, pixels_per_cell)
	var texture := ImageTexture.create_from_image(image)
	return {
		"image": image,
		"texture": texture,
		"pixels_per_cell": pixels_per_cell,
		"origin": -Vector2(data.map_size) * LevelData.CELL_SIZE * 0.5,
		"world_size": Vector2(data.map_size) * LevelData.CELL_SIZE,
		"tiles": _tile_definitions(),
	}

static func cell_terrain_ids(data: LevelData, cell: Vector2i) -> PackedStringArray:
	var result := PackedStringArray()
	if not data.cell_exists(cell):
		return result
	var elevation := data.elevation(cell)
	_append_unique(result, data.tile_id(cell))
	for vector in TerrainTopology.VECTORS:
		var neighbor: Vector2i = cell + vector
		if _belongs_to_level(data, neighbor, elevation):
			_append_unique(result, data.tile_id(neighbor))
	return result

static func _paint_cell(image: Image, data: LevelData, cell: Vector2i,
		style: TerrainStyleProfile, pixels_per_cell: int) -> void:
	var upper := TileRegistry.find(data.tile_id(cell))
	if upper == null:
		return
	var upper_channel := TILE_IDS.find(upper.tile_id)
	if upper_channel < 0:
		return
	var lower_neighbors := _lower_neighbors(data, cell, upper)
	if lower_neighbors.is_empty():
		_fill_cell(image, cell, pixels_per_cell, upper_channel)
		return
	var bits := _overlay_bits(data, cell, upper)
	var mask_info := TerrainTopology.mask_info(bits, cell, style, true)
	var mask := _mask_image(mask_info["path"])
	var turns := int(mask_info["uv_turns"])
	for pixel_y in pixels_per_cell:
		for pixel_x in pixels_per_cell:
			var uv := Vector2(
				(float(pixel_x) + 0.5) / float(pixels_per_cell),
				(float(pixel_y) + 0.5) / float(pixels_per_cell))
			var upper_weight := _sample_mask(mask, _turn_uv(uv, turns))
			var weights := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
			weights[upper_channel] = upper_weight
			var scores := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
			var score_total := 0.0
			for record: Dictionary in lower_neighbors:
				var channel := TILE_IDS.find(record["tile_id"])
				if channel < 0:
					continue
				var vector: Vector2i = record["vector"]
				var center := Vector2(0.5 + vector.x, 0.5 + vector.y)
				var score := 1.0 / maxf(uv.distance_squared_to(center), 0.001)
				scores[channel] += score
				score_total += score
			if score_total <= 0.001:
				weights[upper_channel] = 1.0
			else:
				var remainder := 1.0 - upper_weight
				for channel in 4:
					weights[channel] += remainder * scores[channel] / score_total
			image.set_pixel(
				cell.x * pixels_per_cell + pixel_x,
				cell.y * pixels_per_cell + pixel_y,
				Color(weights[0], weights[1], weights[2], weights[3]))

static func _overlay_bits(data: LevelData, cell: Vector2i,
		upper: TileDefinition) -> int:
	var result := 0
	var elevation := data.elevation(cell)
	for i in TerrainTopology.VECTORS.size():
		var neighbor: Vector2i = cell + TerrainTopology.VECTORS[i]
		var connected := true
		if _belongs_to_level(data, neighbor, elevation):
			var candidate := TileRegistry.find(data.tile_id(neighbor))
			if candidate != null and candidate.tile_id != upper.tile_id \
					and TerrainTransition.dominant(upper, candidate):
				connected = false
		if connected:
			result |= TerrainTopology.BITS[i]
	return TerrainTopology.normalize_bits(result)

static func _lower_neighbors(data: LevelData, cell: Vector2i,
		upper: TileDefinition) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var elevation := data.elevation(cell)
	for vector in TerrainTopology.VECTORS:
		var neighbor: Vector2i = cell + vector
		if not _belongs_to_level(data, neighbor, elevation):
			continue
		var candidate := TileRegistry.find(data.tile_id(neighbor))
		if candidate == null or candidate.tile_id == upper.tile_id:
			continue
		if not TerrainTransition.dominant(upper, candidate):
			continue
		result.append({
			"tile_id": candidate.tile_id,
			"vector": vector,
		})
	return result

static func _belongs_to_level(data: LevelData, cell: Vector2i,
		elevation: int) -> bool:
	return data.in_bounds(cell) and data.cell_exists(cell) \
		and data.stair_at(cell) < 0 and data.elevation(cell) == elevation

static func _fill_cell(image: Image, cell: Vector2i, pixels_per_cell: int,
		channel: int) -> void:
	var weights := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	weights[channel] = 1.0
	var color := Color(weights[0], weights[1], weights[2], weights[3])
	for pixel_y in pixels_per_cell:
		for pixel_x in pixels_per_cell:
			image.set_pixel(
				cell.x * pixels_per_cell + pixel_x,
				cell.y * pixels_per_cell + pixel_y,
				color)

static func _mask_image(path: String) -> Image:
	if _mask_cache.has(path):
		return _mask_cache[path]
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	var image := texture.get_image() if texture != null else null
	if image != null and image.is_compressed():
		image.decompress()
	_mask_cache[path] = image
	return image

static func _sample_mask(image: Image, uv: Vector2) -> float:
	if image == null or image.is_empty():
		return 1.0
	var position := Vector2(
		clampf(uv.x, 0.0, 1.0) * float(image.get_width() - 1),
		clampf(uv.y, 0.0, 1.0) * float(image.get_height() - 1))
	var x0 := floori(position.x)
	var y0 := floori(position.y)
	var x1 := mini(x0 + 1, image.get_width() - 1)
	var y1 := mini(y0 + 1, image.get_height() - 1)
	var tx := position.x - float(x0)
	var ty := position.y - float(y0)
	var top := lerpf(image.get_pixel(x0, y0).r, image.get_pixel(x1, y0).r, tx)
	var bottom := lerpf(image.get_pixel(x0, y1).r, image.get_pixel(x1, y1).r, tx)
	return lerpf(top, bottom, ty)

static func _turn_uv(value: Vector2, turns: int) -> Vector2:
	match posmod(turns, 4):
		1:
			return Vector2(value.y, 1.0 - value.x)
		2:
			return Vector2.ONE - value
		3:
			return Vector2(1.0 - value.y, value.x)
	return value

static func _tile_definitions() -> Array[TileDefinition]:
	var result: Array[TileDefinition] = []
	for tile_id in TILE_IDS:
		result.append(TileRegistry.find(tile_id))
	return result

static func _append_unique(values: PackedStringArray, value: String) -> void:
	if values.find(value) < 0:
		values.append(value)
