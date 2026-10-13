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
		if data.cell_exists(neighbor) and data.stair_at(neighbor) < 0 \
				and data.elevation(neighbor) == elevation and data.tile_id(neighbor) == tile_id:
			bits |= BITS[i]
	return normalize_bits(bits)

static func silhouette_bits(data: LevelData, cell: Vector2i) -> int:
	var bits := 0
	var elevation := data.elevation(cell)
	for i in VECTORS.size():
		var neighbor: Vector2i = cell + VECTORS[i]
		if data.cell_exists(neighbor) and data.stair_at(neighbor) < 0 \
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
		if candidate == null or candidate.tile_id == upper.tile_id:
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

static func mask_info(bits: int, cell: Vector2i, style: TerrainStyleProfile,
		allow_irregular := true) -> Dictionary:
	var normalized := normalize_bits(bits)
	if allow_irregular and style.use_irregular_masks:
		for canonical: int in IRREGULAR_CANONICAL:
			for turns in 4:
				if rotate_bits_clockwise(normalized, turns) != canonical:
					continue
				var variant := stable_variant(cell, style.irregular_seed)
				var kind: String = IRREGULAR_CANONICAL[canonical]
				var path := style.irregular_mask_path(kind, canonical, variant)
				if ResourceLoader.exists(path):
					return {
						"path": path,
						"bits": normalized,
						"uv_turns": posmod(4 - turns, 4),
						"kind": kind,
						"variant": variant,
						"fallback": false,
					}
	var regular := style.regular_mask_path(normalized)
	return {
		"path": regular,
		"bits": normalized,
		"uv_turns": 0,
		"kind": "regular",
		"variant": 0,
		"fallback": true,
	}

static func stable_variant(cell: Vector2i, seed: int) -> int:
	var value := cell.x * 73856093
	value ^= cell.y * 19349663
	value ^= seed * 83492791
	return posmod(value, 3) + 1

static func _dominant(a: TileDefinition, b: TileDefinition) -> bool:
	if a.transition_priority != b.transition_priority:
		return a.transition_priority > b.transition_priority
	return a.tile_id > b.tile_id
