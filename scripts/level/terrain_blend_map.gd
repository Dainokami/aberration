@tool
class_name TerrainBlendMap
extends RefCounted

const MAX_TERRAIN_PAGES := 255
const MAX_LAYER_SIZE := 2048

static var _library_cache: Dictionary = {}
static var _pattern_cache: Dictionary = {}

static func supports_tile(tile_id: String) -> bool:
	return TileRegistry.find(tile_id) != null

static func build(data: LevelData, elevation: int,
		style: TerrainStyleProfile, raster_cache: Dictionary = {}) -> Dictionary:
	var library := _texture_library()
	var pixels_per_cell := maxi(style.blend_pixels_per_cell, 8)
	var image_size := data.map_size * pixels_per_cell
	var index_image := Image.create(
		image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
	var weight_image := Image.create(
		image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
	var rotation_image := Image.create(
		data.map_size.x, data.map_size.y, false, Image.FORMAT_R8)
	index_image.fill(Color.TRANSPARENT)
	weight_image.fill(Color.TRANSPARENT)
	rotation_image.fill(Color.BLACK)
	for y in data.map_size.y:
		for x in data.map_size.x:
			var local := Vector2i(x, y)
			var cell := data.map_origin + local
			if _belongs_to_level(data, cell, elevation):
				rotation_image.set_pixel(
					local.x, local.y,
					Color(float(posmod(int(data.get_cell(cell).get("rotation", 0)), 4)) / 3.0,
						0.0, 0.0))
				_paint_cached_cell(index_image, weight_image, data, cell, style,
					pixels_per_cell, library["page_by_id"], raster_cache)
	var index_texture := ImageTexture.create_from_image(index_image)
	var weight_texture := ImageTexture.create_from_image(weight_image)
	var rotation_texture := ImageTexture.create_from_image(rotation_image)
	var metadata := _metadata_textures(data, library["tiles"])
	return {
		"index_image": index_image,
		"weight_image": weight_image,
		"rotation_image": rotation_image,
		"index_texture": index_texture,
		"weight_texture": weight_texture,
		"rotation_texture": rotation_texture,
		"pixels_per_cell": pixels_per_cell,
		"origin": data.map_world_origin(),
		"world_size": Vector2(data.map_size) * LevelData.CELL_SIZE,
		"tiles": library["tiles"],
		"terrain_ids": library["terrain_ids"],
		"page_by_id": library["page_by_id"],
		"terrain_art": library["terrain_art"],
		"terrain_colors": metadata["colors"],
		"terrain_tints": metadata["tints"],
		"terrain_settings": metadata["settings"],
	}

static func update(blend: Dictionary, data: LevelData, elevation: int,
		style: TerrainStyleProfile, dirty_cells: Array[Vector2i],
		raster_cache: Dictionary = {}) -> void:
	var index_image: Image = blend["index_image"]
	var weight_image: Image = blend["weight_image"]
	var rotation_image: Image = blend["rotation_image"]
	var pixels_per_cell: int = blend["pixels_per_cell"]
	var repaint := {}
	for dirty_cell in dirty_cells:
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				var cell := dirty_cell + Vector2i(offset_x, offset_y)
				if data.in_bounds(cell):
					repaint[cell] = true
	for cell: Vector2i in repaint:
		var local := cell - data.map_origin
		_clear_cell(index_image, local, pixels_per_cell)
		_clear_cell(weight_image, local, pixels_per_cell)
		rotation_image.set_pixel(local.x, local.y, Color.BLACK)
		if _belongs_to_level(data, cell, elevation):
			rotation_image.set_pixel(
				local.x, local.y,
				Color(float(posmod(int(data.get_cell(cell).get("rotation", 0)), 4)) / 3.0,
					0.0, 0.0))
			_paint_cached_cell(index_image, weight_image, data, cell, style,
				pixels_per_cell, blend["page_by_id"], raster_cache)
	(blend["index_texture"] as ImageTexture).update(index_image)
	(blend["weight_texture"] as ImageTexture).update(weight_image)
	(blend["rotation_texture"] as ImageTexture).update(rotation_image)

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

static func clear_cache() -> void:
	_library_cache.clear()
	TerrainTopology.clear_mask_cache()
	_pattern_cache.clear()

## Shared only for one build/update: overlapping chunk halos rasterize a cell once.
static func _paint_cached_cell(index_image: Image, weight_image: Image,
		data: LevelData, cell: Vector2i, style: TerrainStyleProfile,
		pixels_per_cell: int, page_by_id: Dictionary, cache: Dictionary) -> void:
	var rect := Rect2i((cell - data.map_origin) * pixels_per_cell,
		Vector2i.ONE * pixels_per_cell)
	# Outer halo cells have an incomplete neighbor view. Do not cache those.
	var cacheable := data.map_bounds().encloses(Rect2i(cell - Vector2i.ONE, Vector2i(3, 3)))
	var key := Vector3i(cell.x, data.elevation(cell), cell.y)
	if cacheable and cache.has(key):
		var images: Array = cache[key]
		var source := Rect2i(Vector2i.ZERO, rect.size)
		index_image.blit_rect(images[0], source, rect.position)
		weight_image.blit_rect(images[1], source, rect.position)
		return
	_paint_cell(index_image, weight_image, data, cell, style, pixels_per_cell, page_by_id)
	if cacheable:
		cache[key] = [index_image.get_region(rect), weight_image.get_region(rect)]

static func _paint_cell(index_image: Image, weight_image: Image,
		data: LevelData, cell: Vector2i, style: TerrainStyleProfile,
		pixels_per_cell: int, page_by_id: Dictionary) -> void:
	var upper := TileRegistry.find(data.tile_id(cell))
	if upper == null or not page_by_id.has(upper.tile_id):
		return
	var upper_page: int = page_by_id[upper.tile_id]
	var lower_neighbors := _lower_neighbors(data, cell, upper, page_by_id)
	if lower_neighbors.is_empty():
		_fill_cell(index_image, weight_image,
			cell - data.map_origin, pixels_per_cell, upper_page)
		return
	var bits := _overlay_bits(data, cell, upper)
	var mask_info := TerrainTopology.mask_info(bits, cell, style)
	var mask := TerrainTopology.mask_image(mask_info)
	if mask == null:
		return
	var turns := int(mask_info["uv_turns"])
	var pattern := "%d|%s|%s|%d|%d" % [
		upper_page, str(lower_neighbors), mask_info["key"], turns, pixels_per_cell]
	var rect := Rect2i((cell - data.map_origin) * pixels_per_cell,
		Vector2i.ONE * pixels_per_cell)
	if _pattern_cache.has(pattern):
		var images: Array = _pattern_cache[pattern]
		index_image.blit_rect(images[0], Rect2i(Vector2i.ZERO, rect.size), rect.position)
		weight_image.blit_rect(images[1], Rect2i(Vector2i.ZERO, rect.size), rect.position)
		return
	var single_lower := int(lower_neighbors[0]["page"])
	for neighbor in lower_neighbors:
		if int(neighbor["page"]) != single_lower:
			single_lower = -1
			break
	if single_lower >= 0:
		index_image.fill_rect(rect, Color(float(upper_page) / 255.0,
			float(single_lower) / 255.0, 0.0, 0.0))
	for pixel_y in pixels_per_cell:
		for pixel_x in pixels_per_cell:
			var uv := Vector2(
				(float(pixel_x) + 0.5) / float(pixels_per_cell),
				(float(pixel_y) + 0.5) / float(pixels_per_cell))
			var upper_weight := _sample_mask(mask, _turn_uv(uv, turns))
			if single_lower >= 0:
				# With one neighboring material the distance scores cancel.
				weight_image.set_pixel(rect.position.x + pixel_x, rect.position.y + pixel_y,
					Color(upper_weight, 1.0 - upper_weight, 0.0, 0.0))
				continue
			var weights := {upper_page: upper_weight}
			var scores := {}
			var score_total := 0.0
			for record: Dictionary in lower_neighbors:
				var page: int = record["page"]
				var vector: Vector2i = record["vector"]
				var center := Vector2(0.5 + vector.x, 0.5 + vector.y)
				var score := 1.0 / maxf(uv.distance_squared_to(center), 0.001)
				scores[page] = float(scores.get(page, 0.0)) + score
				score_total += score
			if score_total <= 0.001:
				weights[upper_page] = 1.0
			else:
				var remainder := 1.0 - upper_weight
				for page: int in scores:
					weights[page] = float(weights.get(page, 0.0)) \
						+ remainder * float(scores[page]) / score_total
			_write_pixel(index_image, weight_image,
				(cell.x - data.map_origin.x) * pixels_per_cell + pixel_x,
				(cell.y - data.map_origin.y) * pixels_per_cell + pixel_y,
				weights)
	if _pattern_cache.size() >= 512:
		_pattern_cache.clear()
	_pattern_cache[pattern] = [index_image.get_region(rect), weight_image.get_region(rect)]

static func _write_pixel(index_image: Image, weight_image: Image,
		x: int, y: int, weights: Dictionary) -> void:
	var entries: Array[Dictionary] = []
	for page: int in weights:
		var weight: float = weights[page]
		if weight > 0.0001:
			entries.append({"page": page, "weight": weight})
	entries.sort_custom(_weight_descending)
	if entries.size() > 4:
		entries.resize(4)
	var total := 0.0
	for entry in entries:
		total += float(entry["weight"])
	if total <= 0.0001:
		return
	var pages := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var normalized := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for index in entries.size():
		pages[index] = float(entries[index]["page"]) / 255.0
		normalized[index] = float(entries[index]["weight"]) / total
	index_image.set_pixel(x, y, Color(pages[0], pages[1], pages[2], pages[3]))
	weight_image.set_pixel(
		x, y, Color(normalized[0], normalized[1], normalized[2], normalized[3]))

static func _weight_descending(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a["weight"]), float(b["weight"])):
		return float(a["weight"]) > float(b["weight"])
	return int(a["page"]) < int(b["page"])

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
		upper: TileDefinition, page_by_id: Dictionary) -> Array[Dictionary]:
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
		if not page_by_id.has(candidate.tile_id):
			continue
		result.append({
			"page": int(page_by_id[candidate.tile_id]),
			"vector": vector,
		})
	return result

static func _belongs_to_level(data: LevelData, cell: Vector2i,
		elevation: int) -> bool:
	return data.in_bounds(cell) and data.cell_exists(cell) \
		and data.is_solid_layer(cell, elevation) \
		and data.stair_at(cell) < 0 and data.elevation(cell) == elevation

static func _fill_cell(index_image: Image, weight_image: Image,
		cell: Vector2i, pixels_per_cell: int, page: int) -> void:
	var index_color := Color(float(page) / 255.0, 0.0, 0.0, 0.0)
	var weight_color := Color(1.0, 0.0, 0.0, 0.0)
	var rect := Rect2i(cell * pixels_per_cell, Vector2i.ONE * pixels_per_cell)
	index_image.fill_rect(rect, index_color)
	weight_image.fill_rect(rect, weight_color)

static func _clear_cell(image: Image, cell: Vector2i,
		pixels_per_cell: int) -> void:
	image.fill_rect(Rect2i(cell * pixels_per_cell, Vector2i.ONE * pixels_per_cell),
		Color.TRANSPARENT)

static func _texture_library() -> Dictionary:
	var tiles: Array[TileDefinition] = []
	tiles.assign(TileRegistry.all_tiles())
	tiles.sort_custom(_tile_id_ascending)
	if tiles.size() > MAX_TERRAIN_PAGES:
		push_warning("地貌数量超过 %d，超出的地貌不会进入混合纹理数组" % MAX_TERRAIN_PAGES)
		tiles.resize(MAX_TERRAIN_PAGES)
	var cache_key := _library_cache_key(tiles)
	if _library_cache.has(cache_key):
		return _library_cache[cache_key]
	var target_size := _target_layer_size(tiles)
	var images: Array[Image] = []
	var page_by_id := {}
	var terrain_ids := PackedStringArray()
	for page in tiles.size():
		var tile := tiles[page]
		images.append(_layer_image(tile, target_size))
		page_by_id[tile.tile_id] = page
		terrain_ids.append(tile.tile_id)
	var terrain_art := Texture2DArray.new()
	var error := terrain_art.create_from_images(images)
	if error != OK:
		push_error("无法创建地貌 Texture2DArray：%s" % error_string(error))
	var library := {
		"tiles": tiles,
		"terrain_ids": terrain_ids,
		"page_by_id": page_by_id,
		"terrain_art": terrain_art,
	}
	_library_cache.clear()
	_library_cache[cache_key] = library
	return library

static func _metadata_textures(data: LevelData,
		tiles: Array[TileDefinition]) -> Dictionary:
	var width := maxi(tiles.size(), 1)
	var colors := Image.create(width, 1, false, Image.FORMAT_RGBA8)
	var tints := Image.create(width, 1, false, Image.FORMAT_RGBA8)
	var settings := Image.create(width, 1, false, Image.FORMAT_RGBAF)
	for page in tiles.size():
		var tile := tiles[page]
		colors.set_pixel(page, 0, tile.base_color)
		tints.set_pixel(page, 0, data.terrain_tint(tile.tile_id))
		settings.set_pixel(page, 0, Color(
			maxf(tile.top_texture_span_m.x, 0.001),
			maxf(tile.top_texture_span_m.y, 0.001),
			1.0 if tile.world_space_top else 0.0,
			0.0))
	return {
		"colors": ImageTexture.create_from_image(colors),
		"tints": ImageTexture.create_from_image(tints),
		"settings": ImageTexture.create_from_image(settings),
	}

static func _target_layer_size(tiles: Array[TileDefinition]) -> Vector2i:
	var result := Vector2i.ONE
	for tile in tiles:
		if tile.texture_path.is_empty() or not ResourceLoader.exists(tile.texture_path):
			continue
		var texture := load(tile.texture_path) as Texture2D
		if texture != null:
			result.x = maxi(result.x, texture.get_width())
			result.y = maxi(result.y, texture.get_height())
	result.x = mini(result.x, MAX_LAYER_SIZE)
	result.y = mini(result.y, MAX_LAYER_SIZE)
	return result

static func _layer_image(tile: TileDefinition, target_size: Vector2i) -> Image:
	var image: Image
	if not tile.texture_path.is_empty() and ResourceLoader.exists(tile.texture_path):
		var texture := load(tile.texture_path) as Texture2D
		image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		image = Image.create(target_size.x, target_size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(tile.base_color.r, tile.base_color.g, tile.base_color.b, 0.0))
	else:
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		if image.get_size() != target_size:
			image.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	if not image.has_mipmaps():
		image.generate_mipmaps()
	return image

static func _library_cache_key(tiles: Array[TileDefinition]) -> String:
	var parts := PackedStringArray()
	for tile in tiles:
		var modified := 0
		if not tile.texture_path.is_empty() and ResourceLoader.exists(tile.texture_path):
			modified = int(FileAccess.get_modified_time(
				ProjectSettings.globalize_path(tile.texture_path)))
		parts.append("%s|%s|%d" % [tile.tile_id, tile.texture_path, modified])
	return ";".join(parts)

static func _tile_id_ascending(a: TileDefinition, b: TileDefinition) -> bool:
	return a.tile_id < b.tile_id

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

static func _append_unique(values: PackedStringArray, value: String) -> void:
	if values.find(value) < 0:
		values.append(value)
