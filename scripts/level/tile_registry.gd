@tool
class_name TileRegistry
extends RefCounted

const BUILTIN_GRASS := "grass"
const BUILTIN_ROCK := "rock"
const CUSTOM_DIR := "res://data/tiles"

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
	# Built-in tiles always come first.
	var grass := TileDefinition.new()
	grass.tile_id = BUILTIN_GRASS
	grass.display_name = "草地"
	grass.base_color = Color("#738858")
	grass.default_height = 0
	grass.is_builtin = true
	_cache.append(grass)

	var rock := TileDefinition.new()
	rock.tile_id = BUILTIN_ROCK
	rock.display_name = "岩地"
	rock.base_color = Color("#756d70")
	rock.default_height = 0
	rock.is_builtin = true
	_cache.append(rock)

	# Scan custom tiles from disk.
	if DirAccess.dir_exists_absolute(CUSTOM_DIR):
		for file in DirAccess.get_files_at(CUSTOM_DIR):
			if file.ends_with(".tres"):
				var path := CUSTOM_DIR.path_join(file)
				var res := load(path) as TileDefinition
				if res != null and not res.tile_id.is_empty():
					_cache.append(res)
	_dirty = false
