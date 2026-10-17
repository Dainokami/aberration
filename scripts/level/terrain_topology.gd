@tool
class_name TerrainTopology
extends RefCounted

const BITS := [1, 2, 4, 8, 16, 32, 64, 128]
const VECTORS := [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const CARDINAL_BITS := [1, 2, 4, 8]
const CARDINALS := [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]
const IRREGULAR_CANONICAL := {
	110: "straight",
	76: "outer_corner",
	239: "inner_corner",
}
const MASK_SIZE := 256
static var _mask_images: Dictionary = {}
static var _mask_textures: Dictionary = {}
static var _source_images: Dictionary = {}
static var _full_texture: Texture2D

static func normalize_bits(bits: int) -> int:
	var normalized := bits & 255
	if (normalized & 1) == 0 or (normalized & 2) == 0:
		normalized &= ~16
	if (normalized & 2) == 0 or (normalized & 4) == 0:
		normalized &= ~32
	if (normalized & 4) == 0 or (normalized & 8) == 0:
		normalized &= ~64
	if (normalized & 8) == 0 or (normalized & 1) == 0:
		normalized &= ~128
	return normalized

static func rotate_bits_clockwise(bits: int, turns: int) -> int:
	var result := 0
	for i in BITS.size():
		if (bits & BITS[i]) == 0:
			continue
		var vector: Vector2i = VECTORS[i]
		for turn in posmod(turns, 4):
			vector = Vector2i(-vector.y, vector.x)
		var target := VECTORS.find(vector)
		if target >= 0:
			result |= BITS[target]
	return normalize_bits(result)

static func topology_bits(data: LevelData, cell: Vector2i, tile_id: String) -> int:
	var bits := 0
	var elevation := data.elevation(cell)
	for i in VECTORS.size():
		var neighbor: Vector2i = cell + VECTORS[i]
		if data.cell_exists(neighbor) \
				and data.elevation(neighbor) == elevation and data.tile_id(neighbor) == tile_id:
			bits |= BITS[i]
	return normalize_bits(bits)

static func silhouette_bits(data: LevelData, cell: Vector2i) -> int:
	var bits := 0
	var elevation := data.elevation(cell)
	for i in VECTORS.size():
		var neighbor: Vector2i = cell + VECTORS[i]
		if data.cell_exists(neighbor) \
				and data.elevation(neighbor) >= elevation:
			bits |= BITS[i]
	return normalize_bits(bits)

static func transition_info(data: LevelData, cell: Vector2i) -> Dictionary:
	var upper := TileRegistry.find(data.tile_id(cell))
	if upper == null:
		return {}
	var lower: TileDefinition = null
	for direction in CARDINALS:
		var neighbor: Vector2i = cell + direction
		if not data.cell_exists(neighbor) or data.stair_at(neighbor) >= 0:
			continue
		if data.elevation(neighbor) != data.elevation(cell):
			continue
		var candidate := TileRegistry.find(data.tile_id(neighbor))
		if candidate == null or not candidate.is_solid() or candidate.tile_id == upper.tile_id:
			continue
		if not _dominant(upper, candidate):
			continue
		if lower == null or candidate.transition_priority > lower.transition_priority \
				or (candidate.transition_priority == lower.transition_priority
					and candidate.tile_id > lower.tile_id):
			lower = candidate
	if lower == null:
		return {}
	return {
		"upper": upper,
		"lower": lower,
		"bits": topology_bits(data, cell, upper.tile_id),
	}

## Every boundary is made from the supplied irregular artwork. Full coverage
## needs no boundary art; composite masks keep a recipe instead of a disk path.
static func mask_info(bits: int, cell: Vector2i, style: TerrainStyleProfile) -> Dictionary:
	var normalized := normalize_bits(bits)
	var variant := stable_variant(cell, style.irregular_seed)
	var parts: Array[Dictionary] = []
	var kind := "full" if normalized == 255 else "composite"
	var path := ""
	var uv_turns := 0
	if normalized != 255:
		for canonical: int in IRREGULAR_CANONICAL:
			for turns in 4:
				if rotate_bits_clockwise(normalized, turns) != canonical:
					continue
				kind = IRREGULAR_CANONICAL[canonical]
				path = style.irregular_mask_path(kind, canonical, variant)
				uv_turns = posmod(4 - turns, 4)
				parts.append({"path": path, "turns": uv_turns})
				break
			if not parts.is_empty():
				break
		if parts.is_empty():
			parts = _composite_parts(normalized, style, variant)
	var key := "full" if normalized == 255 else "%s|%d|%d" % [
		style.irregular_mask_directory, normalized, variant]
	return {
		"path": path,
		"bits": normalized,
		# Images/textures returned below already include the recipe rotations.
		"uv_turns": 0,
		"source_turns": uv_turns,
		"kind": kind,
		"variant": variant if normalized != 255 else 0,
		"parts": parts,
		"key": key,
	}

## An absent cardinal neighbor cuts that side. Two adjacent missing sides use
## one painted outer corner; a missing diagonal between connected sides uses
## one inner corner. Intersecting these cuts covers all 47 normalized states.
static func _composite_parts(bits: int, style: TerrainStyleProfile,
		variant: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var corner_sides := 0
	for turns in 4:
		var absent_pair := rotate_bits_clockwise(3, turns)
		if (bits & absent_pair) == 0:
			result.append({"path": style.irregular_mask_path("outer_corner", 76, variant),
				"turns": turns})
			corner_sides |= absent_pair
		var diagonal := 1 << (4 + turns)
		if (bits & absent_pair) == absent_pair and (bits & diagonal) == 0:
			result.append({"path": style.irregular_mask_path("inner_corner", 239, variant),
				"turns": turns})
	for turns in 4:
		var side := 1 << turns
		if (bits & side) == 0 and (corner_sides & side) == 0:
			result.append({"path": style.irregular_mask_path("straight", 110, variant),
				"turns": turns})
	return result

static func mask_image(info: Dictionary) -> Image:
	var key: String = info["key"]
	if _mask_images.has(key):
		return _mask_images[key]
	var result: Image
	for part: Dictionary in info["parts"]:
		var source := _source_image(part["path"])
		if source == null:
			return null
		var rotated := source.duplicate() as Image
		for turn in int(part["turns"]):
			rotated.rotate_90(CLOCKWISE)
		if result == null:
			result = rotated
		else:
			var a := result.get_data()
			var b := rotated.get_data()
			for pixel in a.size():
				a[pixel] = mini(a[pixel], b[pixel])
			result = Image.create_from_data(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_R8, a)
	if result == null:
		result = Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_R8)
		result.fill(Color.WHITE)
	_mask_images[key] = result
	return result

static func mask_texture(info: Dictionary) -> Texture2D:
	var key: String = info["key"]
	if _mask_textures.has(key):
		return _mask_textures[key]
	var image := mask_image(info)
	if image == null:
		return null
	var texture := ImageTexture.create_from_image(image)
	_mask_textures[key] = texture
	return texture

static func full_texture() -> Texture2D:
	if _full_texture == null:
		var image := Image.create(1, 1, false, Image.FORMAT_R8)
		image.fill(Color.WHITE)
		_full_texture = ImageTexture.create_from_image(image)
	return _full_texture

static func clear_mask_cache() -> void:
	_mask_images.clear()
	_mask_textures.clear()
	_source_images.clear()

static func _source_image(path: String) -> Image:
	if _source_images.has(path):
		return _source_images[path]
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	if texture == null:
		push_error("缺少不规则地块过渡 Mask：" + path)
		return null
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_R8)
	if image.get_size() != Vector2i.ONE * MASK_SIZE:
		image.resize(MASK_SIZE, MASK_SIZE, Image.INTERPOLATE_BILINEAR)
	_source_images[path] = image
	return image

static func stable_variant(cell: Vector2i, seed: int) -> int:
	var value := cell.x * 73856093
	value ^= cell.y * 19349663
	value ^= seed * 83492791
	return posmod(value, 3) + 1

static func _dominant(a: TileDefinition, b: TileDefinition) -> bool:
	if a.transition_priority != b.transition_priority:
		return a.transition_priority > b.transition_priority
	return a.tile_id > b.tile_id
