@tool
class_name TileRegistry
extends RefCounted

const BUILTIN_GRASS := "grass"
const BUILTIN_ROCK := "rock"
const BUILTIN_SAND := "sand"
const BUILTIN_WATER := "water"
const CUSTOM_DIR := "res://data/tiles"
const BUILTIN_PATHS := [
	"res://data/tiles/grass.tres",
	"res://data/tiles/rock.tres",
	"res://data/tiles/sand.tres",
	"res://data/tiles/water.tres",
]

static var _cache: Array[TileDefinition] = []
static var _dirty := true

static func invalidate() -> void:
	_dirty = true

static func all_tiles() -> Array[TileDefinition]:
	if _dirty:
		_rebuild()
	return _cache

static func find(tile_id: String) -> TileDefinition:
	for t in all_tiles():
		if t.tile_id == tile_id:
			return t
	return null

## Map old integer terrain types to tile IDs for backward compatibility.
static func legacy_terrain_to_id(terrain: int) -> String:
	return BUILTIN_ROCK if terrain == 1 else BUILTIN_GRASS

## Map tile ID back to legacy terrain int for data compatibility.
static func id_to_legacy_terrain(tile_id: String) -> int:
	return 1 if tile_id == BUILTIN_ROCK else 0

static func next_transition_priority() -> int:
	var highest := 0
	for tile in all_tiles():
		highest = maxi(highest, tile.transition_priority)
	return mini(highest + 10, 100)

static func _rebuild() -> void:
	_cache.clear()
	var ids := {}
	for path in BUILTIN_PATHS:
		var builtin := load(path) as TileDefinition
		if builtin != null:
			_cache.append(builtin)
			ids[builtin.tile_id] = true

	# Scan custom tiles from disk.
	if DirAccess.dir_exists_absolute(CUSTOM_DIR):
		for file in DirAccess.get_files_at(CUSTOM_DIR):
			if file.ends_with(".tres"):
				var path := CUSTOM_DIR.path_join(file)
				var res := load(path) as TileDefinition
				if res != null and not res.tile_id.is_empty() and not ids.has(res.tile_id):
					_cache.append(res)
					ids[res.tile_id] = true
	for tile in _cache:
		tile.resolve_art()
	_dirty = false
