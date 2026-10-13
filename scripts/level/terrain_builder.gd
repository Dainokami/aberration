@tool
class_name TerrainBuilder
extends Node3D

const DEFAULT_STYLE := "res://data/terrain_style_profile.tres"
const TerrainBlendMapClass := preload("res://scripts/level/terrain_blend_map.gd")

@export var level_data: LevelData
@export var show_grid := true
@export var build_collision := true
@export var style_profile: TerrainStyleProfile

var generated: Node3D
var grass_material: Material
var rock_material: Material
var side_material: Material
var stair_material: StandardMaterial3D
var _tile_material_cache: Dictionary = {}
var _top_groups: Dictionary = {}
var _blend_groups: Dictionary = {}
var _multi_blend_levels: Dictionary = {}
var _blend_resources: Dictionary = {}

func _ready() -> void:
	rebuild()

func set_data(value: LevelData) -> void:
	level_data = value
	rebuild()

func rebuild() -> void:
	if generated and is_instance_valid(generated):
		remove_child(generated)
		generated.queue_free()
	generated = Node3D.new()
	generated.name = "Generated"
	add_child(generated)
	if level_data == null:
		return
	if style_profile == null:
		style_profile = load(DEFAULT_STYLE) as TerrainStyleProfile
	level_data.ensure_layout()
	_prepare_materials()
	_top_groups.clear()
	_blend_groups.clear()
	_blend_resources.clear()
	_prepare_multi_blend_levels()
	for y in level_data.map_size.y:
		for x in level_data.map_size.x:
			var cell := level_data.map_origin + Vector2i(x, y)
			if level_data.cell_exists(cell) and level_data.stair_at(cell) < 0:
				_build_cell(cell)
	_build_top_groups()
	_build_cliffs_and_rims()
	_build_shore_foam()
	for stair in level_data.stairs:
		_build_stair(stair)
	if show_grid:
		_build_grid()
	_build_spawn_marker()
	_build_objects()

func _build_objects() -> void:
	for record in level_data.objects:
		var definition := ObjectRules.definition(record)
		if definition == null or not definition.validate_asset().is_empty():
			continue
		var object := AssetFactory.make_asset(definition)
		if definition.fade_when_occluding and object.get_script() == null:
			object.set_script(load("res://scripts/assets/occlusion_fade.gd"))
		object.position = record.get("position", Vector3.ZERO)
		object.rotation.y = float(record.get("yaw", 0.0))
		object.scale = Vector3.ONE * float(record.get("scale", 1.0))
		object.set_meta("object_id", record.get("id", ""))
		generated.add_child(object)

func _prepare_materials() -> void:
	_tile_material_cache.clear()
	grass_material = _material_for_cell({"tile_id": "grass"})
	rock_material = _material_for_cell({"tile_id": "rock"})
	var side := StandardMaterial3D.new()
	side.albedo_color = Color("#403944")
	side.roughness = 1.0
	side_material = side
	stair_material = StandardMaterial3D.new()
	stair_material.albedo_color = Color("#776b71")
	stair_material.roughness = 1.0

func _prepare_multi_blend_levels() -> void:
	_multi_blend_levels.clear()
	var terrain_by_level := {}
	for y in level_data.map_size.y:
		for x in level_data.map_size.x:
			var cell := level_data.map_origin + Vector2i(x, y)
			if not level_data.cell_exists(cell) or level_data.stair_at(cell) >= 0:
				continue
			var elevation := level_data.elevation(cell)
			if not terrain_by_level.has(elevation):
				terrain_by_level[elevation] = {}
			terrain_by_level[elevation][level_data.tile_id(cell)] = true
	for elevation: int in terrain_by_level:
		var terrain_ids: Dictionary = terrain_by_level[elevation]
		if terrain_ids.size() > 1:
			_multi_blend_levels[elevation] = true
			_blend_groups[elevation] = []

func _build_cell(cell: Vector2i) -> void:
	var cell_data := level_data.get_cell(cell)
	var tile := TileRegistry.find(level_data.tile_id(cell))
	if tile == null:
		tile = TileRegistry.find("grass")
	var top := Node3D.new()
	top.name = "Top_%d_%d" % [cell.x, cell.y]
	top.position = level_data.world_center(cell)
	top.set_meta("terrain_cell", cell)
	var elevation := level_data.elevation(cell)
	if _multi_blend_levels.has(elevation):
		_blend_groups[elevation].append(cell)
		top.set_meta("blend_terrains", TerrainBlendMapClass.cell_terrain_ids(level_data, cell))
	else:
		var transition := TerrainTopology.transition_info(level_data, cell)
		var lower: TileDefinition = transition.get("lower") as TileDefinition
		var transition_turns := 0
		var transition_mask_info := {}
		if lower != null:
			transition_mask_info = TerrainTopology.mask_info(
				int(transition["bits"]), cell, style_profile, true)
			transition_turns = int(transition_mask_info["uv_turns"])
		var rotation_turns := int(cell_data.get("rotation", 0))
		var mask_path: String = transition_mask_info.get("path", "")
		var lower_id := lower.tile_id if lower != null else ""
		var key := "%s|%d|%d|%s|%s|%d" % [
			tile.tile_id, elevation, rotation_turns,
			lower_id, mask_path, transition_turns]
		if not _top_groups.has(key):
			_top_groups[key] = {
				"tile": tile,
				"lower": lower,
				"mask_info": transition_mask_info,
				"transition_turns": transition_turns,
				"rotation_turns": rotation_turns,
				"cells": [],
			}
		_top_groups[key]["cells"].append(cell)
		if lower != null:
			top.set_meta("transition_upper", tile.tile_id)
			top.set_meta("transition_lower", lower.tile_id)
			top.set_meta("transition_bits", int(transition["bits"]))
			top.set_meta("transition_kind", transition_mask_info["kind"])
			top.set_meta("transition_variant", transition_mask_info["variant"])
	generated.add_child(top)
	if build_collision:
		_add_top_collision(top)
		_build_side_collisions(cell)

func _build_top_groups() -> void:
	_build_blended_top_groups()
	var full_mask := _load_mask(style_profile.regular_mask_path(255))
	for group: Dictionary in _top_groups.values():
		var tile: TileDefinition = group["tile"]
		var lower: TileDefinition = group["lower"]
		var mask_info: Dictionary = group["mask_info"]
		var transition_texture: Texture2D = null
		if lower != null:
			transition_texture = _load_mask(mask_info["path"])
		var material := TerrainMaterials.top_material(
			tile,
			lower,
			transition_texture,
			int(group["transition_turns"]),
			full_mask,
			level_data.terrain_tint(tile.tile_id),
			level_data.terrain_tint(lower.tile_id) if lower != null else tile.tint_default(),
			int(group["rotation_turns"]))
		var mesh := TerrainEdgeBuilder.make_top_group_mesh(
			level_data, group["cells"], tile, style_profile.corner_segments,
			style_profile.top_surface_offset_m)
		if mesh == null:
			continue
		var top := MeshInstance3D.new()
		top.name = "TerrainTop_%s_%d" % [tile.tile_id, int(group["rotation_turns"])]
		top.mesh = mesh
		top.material_override = material
		top.set_meta("terrain_cells", group["cells"])
		top.set_meta("terrain_tile", tile.tile_id)
		if lower != null:
			top.set_meta("transition_upper", tile.tile_id)
			top.set_meta("transition_lower", lower.tile_id)
			top.set_meta("transition_kind", mask_info["kind"])
			top.set_meta("transition_variant", mask_info["variant"])
		generated.add_child(top)

func _build_blended_top_groups() -> void:
	for elevation: int in _blend_groups:
		var cells: Array = _blend_groups[elevation]
		var blend := TerrainBlendMapClass.build(level_data, elevation, style_profile)
		_blend_resources[elevation] = blend
		var material := TerrainMaterials.blended_top_material(blend)
		var mesh := TerrainEdgeBuilder.make_blended_top_mesh(
			level_data, cells, style_profile.corner_segments,
			style_profile.top_surface_offset_m)
		if mesh == null:
			continue
		var top := MeshInstance3D.new()
		top.name = "TerrainTopBlend_%d" % elevation
		top.mesh = mesh
		top.material_override = material
		top.set_meta("terrain_cells", cells)
		top.set_meta("terrain_tiles", blend["terrain_ids"])
		top.set_meta("multi_blend", true)
		generated.add_child(top)

func refresh_blend_cells(changed_cells: Array[Vector2i]) -> bool:
	if changed_cells.is_empty() or level_data == null or style_profile == null:
		return false
	var by_elevation := {}
	for cell in changed_cells:
		if not level_data.in_bounds(cell) or not level_data.cell_exists(cell):
			return false
		var elevation := level_data.elevation(cell)
		if not _blend_resources.has(elevation):
			return false
		var blend: Dictionary = _blend_resources[elevation]
		if not blend["page_by_id"].has(level_data.tile_id(cell)):
			return false
		if not by_elevation.has(elevation):
			by_elevation[elevation] = []
		by_elevation[elevation].append(cell)
	for elevation: int in by_elevation:
		var dirty: Array[Vector2i] = []
		dirty.assign(by_elevation[elevation])
		TerrainBlendMapClass.update(
			_blend_resources[elevation], level_data, elevation, style_profile, dirty)
	return true

func _add_top_collision(top: Node3D) -> void:
	var body := StaticBody3D.new()
	body.set_meta("terrain_cell", top.get_meta("terrain_cell"))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(LevelData.CELL_SIZE, 0.1, LevelData.CELL_SIZE)
	shape.shape = box
	shape.position.y = -0.05
	body.add_child(shape)
	top.add_child(body)

func _build_side_collisions(cell: Vector2i) -> void:
	var high_y := level_data.elevation(cell) * LevelData.ELEVATION_STEP
	for direction in 4:
		var neighbor: Vector2i = cell + LevelData.DIRS[direction]
		var low_y := LevelData.BASE_Y
		if level_data.cell_exists(neighbor):
			low_y = level_data.elevation(neighbor) * LevelData.ELEVATION_STEP
		if high_y <= low_y:
			continue
		var offset: Vector2i = LevelData.DIRS[direction]
		var center := level_data.world_center(cell)
		center += Vector3(offset.x, 0, offset.y) * LevelData.CELL_SIZE * 0.5
		center.y = low_y + (high_y - low_y) * 0.5
		var size := Vector3(LevelData.CELL_SIZE, high_y - low_y, 0.08)
		if direction % 2 == 1:
			size = Vector3(0.08, high_y - low_y, LevelData.CELL_SIZE)
		_add_collision_box(center, size, "CliffCollision")

func _build_cliffs_and_rims() -> void:
	for group in TerrainEdgeBuilder.cliff_groups(level_data):
		var tile: TileDefinition = group["tile"]
		var high_y := int(group["high_level"]) * LevelData.ELEVATION_STEP
		var low_level := int(group["low_level"])
		var low_y := low_level * LevelData.ELEVATION_STEP if low_level >= 0 else LevelData.BASE_Y
		var radius := tile.corner_radius_m if style_profile.use_soft_rims and tile.has_soft_rim() else 0.0
		var paths := TerrainEdgeBuilder.traced_world_paths(
			level_data, group["edges"], radius, style_profile.corner_segments)
		for path in paths:
			var cliff_top := high_y
			if style_profile.use_soft_rims and tile.has_soft_rim():
				cliff_top -= tile.rim_drop_m
			var cliff_mesh := TerrainEdgeBuilder.make_cliff_mesh(
				path, cliff_top, low_y, tile.cliff_texture_span_m)
			if cliff_mesh != null:
				var cliff := MeshInstance3D.new()
				cliff.name = "Side"
				cliff.mesh = cliff_mesh
				cliff.material_override = TerrainMaterials.cliff_material(
					tile, level_data.terrain_tint(tile.tile_id))
				cliff.set_meta("terrain_tile", tile.tile_id)
				cliff.set_meta("high_level", int(group["high_level"]))
				cliff.set_meta("low_level", low_level)
				generated.add_child(cliff)
			if not style_profile.use_soft_rims or not tile.has_soft_rim():
				continue
			var rim_mesh := TerrainEdgeBuilder.make_rim_mesh(path, high_y, tile, style_profile)
			if rim_mesh != null:
				var rim := MeshInstance3D.new()
				rim.name = "Rim"
				rim.mesh = rim_mesh
				rim.material_override = TerrainMaterials.rim_material(
					tile, level_data.terrain_tint(tile.tile_id))
				rim.set_meta("terrain_tile", tile.tile_id)
				generated.add_child(rim)

func _build_shore_foam() -> void:
	if not style_profile.use_shore_foam:
		return
	for group in TerrainEdgeBuilder.foam_groups(level_data):
		var land: TileDefinition = group["land"]
		var water: TileDefinition = group["water"]
		var paths := TerrainEdgeBuilder.traced_world_paths(
			level_data, group["edges"], land.corner_radius_m, style_profile.corner_segments)
		var water_y := int(group["water_level"]) * LevelData.ELEVATION_STEP
		for path in paths:
			var mesh := TerrainEdgeBuilder.make_foam_mesh(path, water_y, water, style_profile)
			if mesh == null:
				continue
			var foam := MeshInstance3D.new()
			foam.name = "ShoreFoam"
			foam.mesh = mesh
			foam.material_override = TerrainMaterials.foam_material(water)
			foam.set_meta("water_level", int(group["water_level"]))
			generated.add_child(foam)

func _load_mask(path: String) -> Texture2D:
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return TerrainTransition.ensure_default_mask()

func _add_collision_box(position_value: Vector3, size: Vector3, label: String) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = position_value
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	generated.add_child(body)

func _build_stair(stair: Dictionary) -> void:
	var low: Vector2i = stair["cell"]
	var direction: int = int(stair["direction"]) % 4
	var vector: Vector2i = LevelData.DIRS[direction]
	var low_height := level_data.elevation(low) * LevelData.ELEVATION_STEP
	var low_center := level_data.world_center(low)
	var high_center := level_data.world_center(low + vector)
	var center := (low_center + high_center) * 0.5
	for i in 10:
		var progress := (float(i) + 0.5) / 10.0
		var pos := low_center.lerp(high_center, progress)
		var step_height := low_height + LevelData.ELEVATION_STEP * (float(i) + 1.0) / 10.0
		pos.y = step_height - 0.1
		var size := Vector3(LevelData.CELL_SIZE, 0.2, LevelData.CELL_SIZE * 2.0 / 10.0)
		if direction % 2 == 1:
			size = Vector3(LevelData.CELL_SIZE * 2.0 / 10.0, 0.2, LevelData.CELL_SIZE)
		_box("StairVisual", pos, size, stair_material, false)
	if not build_collision:
		return
	var body := StaticBody3D.new()
	body.name = "StairRamp"
	var collision := CollisionShape3D.new()
	var wedge := ConvexPolygonShape3D.new()
	var half_width := LevelData.CELL_SIZE * 0.5
	var half_length := LevelData.CELL_SIZE
	wedge.points = PackedVector3Array([
		Vector3(-half_width, 0, half_length), Vector3(half_width, 0, half_length),
		Vector3(-half_width, 0, -half_length), Vector3(half_width, 0, -half_length),
		Vector3(-half_width, LevelData.ELEVATION_STEP, -half_length),
		Vector3(half_width, LevelData.ELEVATION_STEP, -half_length)])
	collision.shape = wedge
	body.add_child(collision)
	body.position = center
	body.position.y = low_height
	body.rotation.y = -float(direction) * PI * 0.5
	generated.add_child(body)

func _build_grid() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.95, 1.0, 0.25)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var total_x := level_data.map_size.x * LevelData.CELL_SIZE
	var total_z := level_data.map_size.y * LevelData.CELL_SIZE
	var origin := level_data.map_world_origin()
	var center := origin + Vector2(total_x, total_z) * 0.5
	for x in level_data.map_size.x + 1:
		var world_x := origin.x + x * LevelData.CELL_SIZE
		_box("Grid", Vector3(world_x, 0.025, center.y),
			Vector3(0.018, 0.018, total_z), material, false)
	for z in level_data.map_size.y + 1:
		var world_z := origin.y + z * LevelData.CELL_SIZE
		_box("Grid", Vector3(center.x, 0.025, world_z),
			Vector3(total_x, 0.018, 0.018), material, false)

func _build_spawn_marker() -> void:
	if not level_data.in_bounds(level_data.spawn_cell) or not level_data.cell_exists(level_data.spawn_cell):
		return
	var marker := MeshInstance3D.new()
	marker.name = "SpawnMarker"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.28
	mesh.bottom_radius = 0.55
	mesh.height = 0.18
	marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ffb347")
	material.emission_enabled = true
	material.emission = Color("#ff772f")
	marker.material_override = material
	marker.position = level_data.world_center(level_data.spawn_cell) + Vector3(0, 0.12, 0)
	generated.add_child(marker)

func _box(label: String, position_value: Vector3, size: Vector3,
		material: Material, collision: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = position_value
	generated.add_child(node)
	if collision and build_collision:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		node.add_child(body)
	return node

func _material_for_cell(data: Dictionary) -> Material:
	var tile_id: String = data.get("tile_id", "")
	if tile_id.is_empty():
		tile_id = TileRegistry.legacy_terrain_to_id(int(data.get("terrain", 0)))
	if _tile_material_cache.has(tile_id):
		return _tile_material_cache[tile_id]
	var tile := TileRegistry.find(tile_id)
	if tile == null:
		tile = TileRegistry.find("grass")
	var material := tile.top_material()
	_tile_material_cache[tile_id] = material
	return material
