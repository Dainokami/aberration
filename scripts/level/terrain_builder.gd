@tool
class_name TerrainBuilder
extends Node3D

const DEFAULT_STYLE := "res://data/terrain_style_profile.tres"
const TerrainBlendMapClass := preload("res://scripts/level/terrain_blend_map.gd")
const CHUNK_SIZE := 8

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
var _overlay_groups: Dictionary = {}
var slice_layer_limit := -1
var _slice_caps: Node3D
var _chunk_nodes: Dictionary = {}
var _build_region := Rect2i()
var _current_chunk := Vector2i.ZERO
var _built_bounds := Rect2i()
var _built_data: LevelData
var _built_grid_origin := Vector2.ZERO
var _built_stairs: Array[Dictionary] = []
var _used_blends: Dictionary = {}
var _raster_cache: Dictionary = {}
var _surface_views: Dictionary = {}
var _object_nodes: Dictionary = {}
var _object_signatures: Dictionary = {}
var _affordance_nodes: Dictionary = {}
var _applied_slice_limit := -1
var detail_renderer: DetailRenderer

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
	_chunk_nodes.clear()
	_blend_resources.clear()
	_raster_cache.clear()
	_surface_views.clear()
	_object_nodes.clear()
	_object_signatures.clear()
	_affordance_nodes.clear()
	_applied_slice_limit = -1
	_built_bounds = level_data.map_bounds()
	_built_data = level_data
	_built_grid_origin = level_data.grid_world_origin
	var chunks := {}
	for index in level_data.columns.size():
		if (level_data.columns[index].get("layers", []) as Array).is_empty():
			continue
		var cell := level_data.map_origin + Vector2i(
			index % level_data.map_size.x, index / level_data.map_size.x)
		chunks[_chunk_for(cell)] = true
	for chunk: Vector2i in chunks:
		_build_chunk(chunk)
	_raster_cache.clear()
	if show_grid:
		_build_grid()
	_build_spawn_marker()
	_build_objects()
	rebuild_details()
	_built_stairs = level_data.stairs.duplicate(true)
	_apply_slice_visibility()

func _chunk_for(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK_SIZE), floori(float(cell.y) / CHUNK_SIZE))

func _surface(layer: int) -> LevelData:
	if not _surface_views.has(layer):
		_surface_views[layer] = level_data.surface_view(layer)
	return _surface_views[layer]

func _build_chunk(chunk: Vector2i) -> void:
	_current_chunk = chunk
	_used_blends.clear()
	_build_region = Rect2i(chunk * CHUNK_SIZE, Vector2i.ONE * CHUNK_SIZE).intersection(
		level_data.map_bounds())
	if _build_region.size.x <= 0 or _build_region.size.y <= 0:
		return
	var first_child := generated.get_child_count()
	_top_groups.clear()
	_blend_groups.clear()
	_overlay_groups.clear()
	_prepare_multi_blend_levels()
	for y in range(_build_region.position.y, _build_region.end.y):
		for x in range(_build_region.position.x, _build_region.end.x):
			var cell := Vector2i(x, y)
			if level_data.cell_exists(cell):
				for water_layer in level_data.layer_count(cell):
					if level_data.is_water_layer(cell, water_layer):
						_build_water(cell, water_layer)
				for layer in level_data.exposed_layers(cell):
					if level_data.is_solid_layer(cell, layer) and level_data.stair_at(cell, layer) < 0:
						_build_cell(cell, _surface(layer))
				_build_bottoms(cell)
				if build_collision:
					_build_side_collisions(cell)
	_build_top_groups()
	_build_overlays()
	_build_cliffs_and_rims()
	_build_shore_foam()
	for stair in level_data.stairs:
		if _chunk_for(stair["cell"]) == chunk:
			_build_stair(stair)
	_mark_limb_surfaces(_build_region)
	var nodes: Array[Node] = []
	for i in range(first_child, generated.get_child_count()):
		var node := generated.get_child(i)
		node.set_meta("terrain_chunk", chunk)
		nodes.append(node)
	_chunk_nodes[chunk] = nodes
	for key: Vector3i in _blend_resources.keys():
		if key.x == chunk.x and key.z == chunk.y and not _used_blends.has(key):
			_blend_resources.erase(key)

func rebuild_cells(changed: Array[Vector2i]) -> void:
	if not is_instance_valid(generated) or level_data != _built_data \
			or _built_grid_origin != level_data.grid_world_origin:
		rebuild()
		return
	_surface_views.clear()
	var bounds := level_data.map_bounds()
	var bounds_changed := bounds != _built_bounds
	var dirty := {}
	for cell in changed:
		for y in range(-1, 2):
			for x in range(-1, 2):
				dirty[_chunk_for(cell + Vector2i(x, y))] = true
	if bounds_changed:
		# Grid/world coordinates stay fixed when the map grows. Retain interior
		# chunks and rebuild only changed edge extents (including texture halos).
		var candidates := {}
		for chunk: Vector2i in _chunk_nodes:
			candidates[chunk] = true
		for chunk: Vector2i in dirty:
			candidates[chunk] = true
		for chunk: Vector2i in candidates:
			var region := Rect2i(chunk * CHUNK_SIZE, Vector2i.ONE * CHUNK_SIZE)
			if not _chunk_nodes.has(chunk) \
					or region.intersection(_built_bounds) != region.intersection(bounds):
				dirty[chunk] = true
		# A blend's dimensions and world-space origin must match its new halo.
		# Drop resized textures before partial updates to avoid indexing old images.
		for key: Vector3i in _blend_resources.keys():
			var chunk := Vector2i(key.x, key.z)
			var region := Rect2i(chunk * CHUNK_SIZE, Vector2i.ONE * CHUNK_SIZE)
			var clipped := region.intersection(bounds)
			var expected := clipped.grow(2).intersection(bounds) if clipped.has_area() else Rect2i()
			if _blend_resources[key]["region"] != expected:
				dirty[chunk] = true
				_blend_resources.erase(key)
		_built_bounds = bounds
	if _built_stairs != level_data.stairs:
		for stair in _built_stairs + level_data.stairs:
			dirty[_chunk_for(stair["cell"])] = true
			dirty[_chunk_for(stair["cell"] + LevelData.DIRS[int(stair["direction"])])] = true
	var repaint := changed.duplicate()
	if _built_stairs != level_data.stairs:
		for stair in _built_stairs + level_data.stairs:
			for point in level_data.stair_cells(stair):
				if Vector2i(point) not in repaint:
					repaint.append(Vector2i(point))
	_update_blend_pixels(repaint)
	for chunk: Vector2i in dirty:
		for node: Node in _chunk_nodes.get(chunk, []):
			if is_instance_valid(node):
				node.free()
		_chunk_nodes.erase(chunk)
		_build_chunk(chunk)
	_raster_cache.clear()
	for node in generated.get_children():
		if node.name == "SpawnMarker" \
				or (bounds_changed and node.has_meta("terrain_grid")):
			node.free()
	if bounds_changed and show_grid:
		_build_grid()
	_build_objects()
	rebuild_details()
	_build_spawn_marker()
	_built_stairs = level_data.stairs.duplicate(true)
	_apply_slice_visibility()

func _build_objects() -> void:
	var wanted := {}
	var definitions := {}
	var visibility := {}
	for record in level_data.objects:
		var id := str(record.get("id", ""))
		var path := str(record.get("definition", ""))
		if not definitions.has(path):
			definitions[path] = ObjectRules.definition(record)
		if ObjectRules.is_hidden(level_data, record, visibility):
			continue
		var definition: PlaceableDefinition = definitions[path]
		if definition == null or not definition.validate_asset().is_empty():
			continue
		wanted[id] = true
		var signature := hash([record, build_collision])
		var previous: Node3D = _object_nodes.get(id)
		if is_instance_valid(previous) and _object_signatures.get(id) == signature:
			continue
		if is_instance_valid(previous):
			previous.free()
		if is_instance_valid(_affordance_nodes.get(id)):
			(_affordance_nodes[id] as Node).free()
		_affordance_nodes.erase(id)
		var object := AssetFactory.instantiate_asset(definition)
		if object is SceneMechanism:
			object.level_data = level_data
		if definition.fade_when_occluding and object.get_script() == null:
			object.set_script(load("res://scripts/assets/occlusion_fade.gd"))
		object.position = record.get("position", Vector3.ZERO)
		object.rotation.y = float(record.get("yaw", 0.0))
		object.scale = Vector3.ONE * float(record.get("scale", 1.0))
		if object is SceneMechanism and definition.mechanism == "bubbles":
			var water_cell: Vector2i = record.get("anchor_cell")
			var water_layer := int(record.get("anchor_layer", 0)) + 1
			while level_data.is_water_layer(water_cell, water_layer + 1):
				water_layer += 1
			object.clip_bubbles(level_data.surface_y(water_layer))
		object.set_meta("object_id", record.get("id", ""))
		object.set_meta("support_id", record.get("support_id", ""))
		object.set_meta("anchor_kind", record.get("anchor_kind", "top"))
		object.set_meta("wall_direction", record.get("wall_direction", -1))
		if not Engine.is_editor_hint() and object is GameplayProp:
			object.instance_id = str(record.get("id", ""))
		object.set_meta("terrain_layer", int(record.get(
			"anchor_layer",
			level_data.elevation(level_data.world_to_cell(object.position)))))
		generated.add_child(object)
		_object_nodes[id] = object
		_object_signatures[id] = signature
		_bind_affordance(object, definition.asset_id)
		if not build_collision:
			for collision in object.find_children("*", "CollisionObject3D", true, false):
				collision.collision_layer = 0
				collision.collision_mask = 0
	for id: String in _object_nodes.keys():
		if wanted.has(id):
			continue
		var object: Node3D = _object_nodes[id]
		if is_instance_valid(object):
			object.free()
		if is_instance_valid(_affordance_nodes.get(id)):
			(_affordance_nodes[id] as Node).free()
		_affordance_nodes.erase(id)
		_object_nodes.erase(id)
		_object_signatures.erase(id)

func refresh_objects() -> void:
	_build_objects()
	if slice_layer_limit >= 0:
		for node: Node3D in _object_nodes.values():
			_set_slice_visible(node, int(node.get_meta("terrain_layer", -1)) <= slice_layer_limit)
		for node: Node3D in _affordance_nodes.values():
			_set_slice_visible(node, int(node.get_meta("terrain_layer", -1)) <= slice_layer_limit)

func _bind_affordance(object: Node3D, asset_id: String) -> void:
	if Engine.is_editor_hint() or not build_collision:
		return
	var kind := ""
	var health := 1
	if object is SceneMechanism and object.definition.mechanism == "vine":
		var marker := AffordanceProp.new()
		marker.configure_host(object, "climbable", 1)
		marker.position = object.position
		marker.rotation = object.rotation
		marker.ledge_height = object.position.y + object.definition.image_size.y
		marker.ledge_point = object.position + Vector3.UP * (object.definition.image_size.y + 0.08) \
			- object.basis.z * 0.6
		generated.add_child(marker)
		_affordance_nodes[str(object.get_meta("object_id", ""))] = marker
		return
	match asset_id:
		"demo_rock":
			kind = "pushable"
		"demo_tree", "demo_fence":
			kind = "destructible_hard"
			health = 40
		"demo_grass":
			kind = "destructible_soft"
			health = 16
		_:
			return
	var prop := AffordanceProp.new()
	prop.configure_host(object, kind, health)
	prop.position = object.position
	prop.rotation = object.rotation
	prop.set_meta("terrain_layer", object.get_meta("terrain_layer"))
	generated.add_child(prop)
	_affordance_nodes[str(object.get_meta("object_id", ""))] = prop


func rebuild_details() -> void:
	if not is_instance_valid(detail_renderer) or detail_renderer.get_parent() != generated:
		detail_renderer = DetailRenderer.new()
		detail_renderer.name = "Details"
		generated.add_child(detail_renderer)
	detail_renderer.refresh(level_data)
	detail_renderer.set_slice_layer(slice_layer_limit)

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
	var sample_region := _build_region.grow(1).intersection(level_data.map_bounds())
	for y in range(sample_region.position.y, sample_region.end.y):
		for x in range(sample_region.position.x, sample_region.end.x):
			var cell := Vector2i(x, y)
			for elevation in level_data.exposed_layers(cell):
				if not level_data.is_solid_layer(cell, elevation) or level_data.stair_at(cell, elevation) >= 0:
					continue
				if not terrain_by_level.has(elevation):
					terrain_by_level[elevation] = {}
				terrain_by_level[elevation][_surface(elevation).tile_id(cell)] = true
	for elevation: int in terrain_by_level:
		var terrain_ids: Dictionary = terrain_by_level[elevation]
		if terrain_ids.size() > 1:
			_multi_blend_levels[elevation] = true
			_blend_groups[elevation] = []

func _build_cell(cell: Vector2i, surface: LevelData) -> void:
	var cell_data := surface.get_cell(cell)
	var tile := TileRegistry.find(surface.tile_id(cell))
	if tile == null:
		tile = TileRegistry.find("grass")
	var top := Node3D.new()
	top.name = "Top_%d_%d" % [cell.x, cell.y]
	top.position = surface.world_center(cell)
	top.set_meta("terrain_cell", cell)
	var elevation := surface.elevation(cell)
	top.set_meta("terrain_layer", elevation)
	if _multi_blend_levels.has(elevation):
		_blend_groups[elevation].append(cell)
		top.set_meta("blend_terrains", TerrainBlendMapClass.cell_terrain_ids(surface, cell))
	else:
		var transition := TerrainTopology.transition_info(surface, cell)
		var lower: TileDefinition = transition.get("lower") as TileDefinition
		var transition_turns := 0
		var transition_mask_info := {}
		if lower != null:
			transition_mask_info = TerrainTopology.mask_info(
				int(transition["bits"]), cell, style_profile)
			transition_turns = int(transition_mask_info["uv_turns"])
		var rotation_turns := int(cell_data.get("rotation", 0))
		var mask_key: String = transition_mask_info.get("key", "")
		var lower_id := lower.tile_id if lower != null else ""
		var key := "%s|%d|%d|%s|%s|%d" % [
			tile.tile_id, elevation, rotation_turns,
			lower_id, mask_key, transition_turns]
		if not _top_groups.has(key):
			_top_groups[key] = {
				"tile": tile,
				"elevation": elevation,
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
	var overlay_id := surface.overlay_tile_id(cell)
	if not overlay_id.is_empty():
		var overlay_record := surface.get_attachment(cell, "overlay")
		var bits := 0
		for i in TerrainTopology.VECTORS.size():
			var neighbor: Vector2i = cell + TerrainTopology.VECTORS[i]
			if surface.top_layer(neighbor) == elevation \
					and surface.overlay_tile_id(neighbor) == overlay_id:
				bits |= TerrainTopology.BITS[i]
		var mask := TerrainTopology.mask_info(bits, cell, style_profile)
		var overlay_key := "%s|%d|%d|%s|%d" % [
			overlay_id, elevation, int(overlay_record.get("rotation", 0)),
			mask["key"], int(mask["uv_turns"])]
		if not _overlay_groups.has(overlay_key):
			_overlay_groups[overlay_key] = {
				"tile": TileRegistry.find(overlay_id),
				"elevation": elevation,
				"mask": mask,
				"rotation_turns": int(overlay_record.get("rotation", 0)),
				"cells": [],
			}
		_overlay_groups[overlay_key]["cells"].append(cell)
	generated.add_child(top)
	if build_collision:
		_add_top_collision(top)

func _build_water(cell: Vector2i, layer: int) -> void:
	var tile := TileRegistry.find(level_data.tile_id(cell, layer))
	var center := level_data.world_layer_center(cell, layer)
	var volume := Node3D.new()
	volume.name = "Ocean_%d_%d_%d" % [cell.x, layer, cell.y]
	volume.position = center
	volume.set_meta("terrain_cell", cell)
	volume.set_meta("terrain_layer", layer)
	volume.set_meta("water_volume", true)
	generated.add_child(volume)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(tile.base_color, 0.22)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 1
	var faces := [
		[Vector3(-1,-1,-1), Vector3(-1,1,-1), Vector3(1,1,-1), Vector3(1,-1,-1)],
		[Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(1,1,1), Vector3(1,-1,1)],
		[Vector3(1,-1,1), Vector3(1,1,1), Vector3(-1,1,1), Vector3(-1,-1,1)],
		[Vector3(-1,-1,1), Vector3(-1,1,1), Vector3(-1,1,-1), Vector3(-1,-1,-1)],
		[Vector3(-1,-1,1), Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,-1,1)],
	]
	for direction in 5:
		var neighbor: Vector2i = cell + LevelData.DIRS[direction] if direction < 4 else cell
		var neighbor_layer := layer if direction < 4 else layer - 1
		if level_data.layer_exists(neighbor, neighbor_layer):
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(faces[direction])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var visual := MeshInstance3D.new()
		visual.name = "Underwater_%d" % direction
		visual.mesh = mesh
		visual.material_override = material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		volume.add_child(visual)
	if level_data.is_surface_exposed(cell, layer):
		var surface := MeshInstance3D.new()
		surface.name = "WaterSurface"
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * LevelData.CELL_SIZE
		surface.mesh = plane
		surface.position.y = LevelData.ELEVATION_STEP * 0.5 + 0.015
		var top_material := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D water_art : source_color, repeat_enable;
uniform vec2 world_origin;
uniform vec4 water_tint : source_color;
varying vec3 world_point;
void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec4 pixel = texture(water_art, (world_point.xz - world_origin) / 8.0);
	ALBEDO = mix(pixel.rgb, water_tint.rgb, water_tint.a);
	ALPHA = 0.42;
}
"""
		top_material.shader = shader
		top_material.render_priority = 2
		top_material.set_shader_parameter("water_art", load(tile.texture_path))
		top_material.set_shader_parameter("world_origin", level_data.grid_world_origin)
		top_material.set_shader_parameter("water_tint", level_data.terrain_tint(tile.tile_id))
		surface.material_override = top_material
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		volume.add_child(surface)
	if build_collision and not Engine.is_editor_hint():
		_mark_surface(center, PackedStringArray(["fluid", "ocean"]),
			Vector3.ONE * LevelData.CELL_SIZE, layer)
		if level_data.is_surface_exposed(cell, layer):
			_mark_surface(level_data.world_center(cell, layer),
				PackedStringArray(["fluid", "ocean", "water_surface"]),
				Vector3(LevelData.CELL_SIZE, 0.25, LevelData.CELL_SIZE), layer)

func _build_top_groups() -> void:
	_build_blended_top_groups()
	var full_mask := TerrainTopology.full_texture()
	for group: Dictionary in _top_groups.values():
		var tile: TileDefinition = group["tile"]
		var lower: TileDefinition = group["lower"]
		var mask_info: Dictionary = group["mask_info"]
		var transition_texture: Texture2D = null
		if lower != null:
			transition_texture = TerrainTopology.mask_texture(mask_info)
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
			_surface(int(group["elevation"])), group["cells"], tile, style_profile.corner_segments,
			style_profile.top_surface_offset_m)
		if mesh == null:
			continue
		var top := MeshInstance3D.new()
		top.name = "TerrainTop_%s_%d" % [tile.tile_id, int(group["rotation_turns"])]
		top.mesh = mesh
		top.material_override = material
		top.set_meta("terrain_cells", group["cells"])
		top.set_meta("terrain_tile", tile.tile_id)
		top.set_meta("terrain_layer", int(group["elevation"]))
		if lower != null:
			top.set_meta("transition_upper", tile.tile_id)
			top.set_meta("transition_lower", lower.tile_id)
			top.set_meta("transition_kind", mask_info["kind"])
			top.set_meta("transition_variant", mask_info["variant"])
		generated.add_child(top)

func _build_blended_top_groups() -> void:
	for elevation: int in _blend_groups:
		var cells: Array = _blend_groups[elevation]
		if cells.is_empty():
			continue
		var key := Vector3i(_current_chunk.x, elevation, _current_chunk.y)
		var blend: Dictionary = _blend_resources.get(key, {})
		if blend.is_empty():
			var blend_data := _surface(elevation).region_view(_build_region.grow(2))
			blend = TerrainBlendMapClass.build(blend_data, elevation, style_profile, _raster_cache)
			blend["region"] = blend_data.map_bounds()
			_blend_resources[key] = blend
		_used_blends[key] = true
		var material := TerrainMaterials.blended_top_material(blend)
		var mesh := TerrainEdgeBuilder.make_blended_top_mesh(
			_surface(elevation), cells, style_profile.corner_segments,
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
		top.set_meta("terrain_layer", elevation)
		generated.add_child(top)

func _build_overlays() -> void:
	for group: Dictionary in _overlay_groups.values():
		var tile: TileDefinition = group["tile"]
		if tile == null:
			continue
		var mesh := TerrainEdgeBuilder.make_overlay_mesh(
			_surface(int(group["elevation"])),
			group["cells"],
			style_profile.corner_segments,
			style_profile.top_surface_offset_m + 0.018)
		if mesh == null:
			continue
		var overlay := MeshInstance3D.new()
		overlay.name = "TerrainOverlay_%s_%d" % [
			tile.tile_id, int(group["rotation_turns"])]
		overlay.mesh = mesh
		overlay.material_override = TerrainMaterials.overlay_material(
			tile,
			level_data.terrain_tint(tile.tile_id),
			int(group["rotation_turns"]),
			TerrainTopology.mask_texture(group["mask"]), int(group["mask"]["uv_turns"]))
		overlay.set_meta("terrain_cells", group["cells"])
		overlay.set_meta("terrain_tile", tile.tile_id)
		overlay.set_meta("terrain_overlay", true)
		overlay.set_meta("terrain_layer", int(group["elevation"]))
		generated.add_child(overlay)

func refresh_blend_cells(changed_cells: Array[Vector2i]) -> bool:
	if changed_cells.is_empty() or level_data == null or style_profile == null:
		return false
	for cell in changed_cells:
		if not level_data.in_bounds(cell) or not level_data.cell_exists(cell):
			return false
		var elevation := level_data.elevation(cell)
		var chunk := _chunk_for(cell)
		if not _blend_resources.has(Vector3i(chunk.x, elevation, chunk.y)):
			return false
		for offset in TerrainTopology.VECTORS:
			var neighbor: Vector2i = cell + offset
			var neighbor_chunk := _chunk_for(neighbor)
			if level_data.cell_exists(neighbor) and level_data.top_layer(neighbor) == elevation \
					and not _blend_resources.has(Vector3i(neighbor_chunk.x, elevation, neighbor_chunk.y)):
				return false
	_surface_views.clear()
	_update_blend_pixels(changed_cells)
	return true

func _update_blend_pixels(changed_cells: Array[Vector2i]) -> void:
	# All bordering chunk textures need the same refreshed halo pixels.
	var cache := {}
	for key: Vector3i in _blend_resources:
		var blend: Dictionary = _blend_resources[key]
		var dirty: Array[Vector2i] = []
		for cell in changed_cells:
			if (blend["region"] as Rect2i).grow(1).has_point(cell):
				dirty.append(cell)
		if dirty.is_empty():
			continue
		TerrainBlendMapClass.update(
			blend, _surface(key.y).region_view(blend["region"]), key.y, style_profile, dirty, cache)

func _add_top_collision(top: Node3D) -> void:
	var body := StaticBody3D.new()
	body.set_meta("terrain_cell", top.get_meta("terrain_cell"))
	body.set_meta("terrain_layer", top.get_meta("terrain_layer"))
	body.set_meta("slice_cap", top.get_meta("slice_cap", false))
	var shape := CollisionShape3D.new()
	var cell: Vector2i = top.get_meta("terrain_cell")
	var layer := int(top.get_meta("terrain_layer"))
	var tile := TileRegistry.find(level_data.solid_tile_id(cell, layer))
	var polygon := TerrainEdgeBuilder._top_polygon(level_data, cell, tile,
		style_profile.corner_segments, layer)
	var prism := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for point in polygon:
		points.append(Vector3(point.x, 0, point.y))
		points.append(Vector3(point.x, -0.1, point.y))
	prism.points = points
	shape.shape = prism
	body.add_child(shape)
	top.add_child(body)

func _build_side_collisions(cell: Vector2i) -> void:
	for layer in level_data.layer_count(cell):
		if not level_data.has_terrain_volume(cell, layer):
			continue
		var faces := PackedVector3Array()
		if not level_data.has_terrain_volume(cell, layer - 1):
			faces.append_array(TerrainEdgeBuilder.make_bottom_mesh(
				level_data, cell, layer, style_profile.corner_segments).get_faces())
		for path in TerrainEdgeBuilder.exposed_layer_paths(
				level_data, cell, layer, style_profile.corner_segments):
			var mesh := TerrainEdgeBuilder.make_cliff_mesh(path,
				level_data.surface_y(layer), layer * LevelData.ELEVATION_STEP, Vector2.ONE)
			faces.append_array(mesh.get_faces())
		if faces.is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = "CliffCollision"
		body.set_meta("terrain_cell", cell)
		body.set_meta("terrain_layer", layer)
		var collision := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		collision.shape = shape
		body.add_child(collision)
		generated.add_child(body)

func _build_bottoms(cell: Vector2i) -> void:
	for layer in level_data.layer_count(cell):
		if not level_data.has_terrain_volume(cell, layer) \
				or level_data.has_terrain_volume(cell, layer - 1):
			continue
		var tile := TileRegistry.find(level_data.solid_tile_id(cell, layer))
		if tile == null:
			continue
		var bottom := MeshInstance3D.new()
		bottom.name = "Bottom"
		bottom.mesh = TerrainEdgeBuilder.make_bottom_mesh(
			level_data, cell, layer, style_profile.corner_segments)
		bottom.material_override = TerrainMaterials.cliff_material(
			tile, level_data.terrain_tint(tile.tile_id))
		bottom.set_meta("terrain_cell", cell)
		bottom.set_meta("terrain_layer", layer)
		bottom.set_meta("terrain_bottom", true)
		generated.add_child(bottom)

func _build_cliffs_and_rims() -> void:
	for group in TerrainEdgeBuilder.cliff_groups(level_data, _build_region,
			style_profile.corner_segments):
		var tile: TileDefinition = group["tile"]
		var high_y := float(group["high_y"])
		var low_y := float(group["low_y"])
		for path in group["paths"]:
			var cliff_mesh := TerrainEdgeBuilder.make_cliff_mesh(
				path, high_y, low_y, tile.cliff_texture_span_m)
			if cliff_mesh != null:
				var cliff := MeshInstance3D.new()
				cliff.name = "Side"
				cliff.mesh = cliff_mesh
				cliff.material_override = TerrainMaterials.cliff_material(
					tile, level_data.terrain_tint(tile.tile_id))
				cliff.set_meta("terrain_tile", tile.tile_id)
				cliff.set_meta("terrain_layer", int(group["layer"]))
				cliff.set_meta("terrain_side", true)
				generated.add_child(cliff)
		if not style_profile.use_soft_rims or not tile.has_soft_rim() \
				or group["rim_paths"].is_empty():
			continue
		for path in group["rim_paths"]:
			var rim_mesh := TerrainEdgeBuilder.make_rim_mesh(
				path, high_y, tile, style_profile)
			if rim_mesh != null:
				var rim := MeshInstance3D.new()
				rim.name = "Rim"
				rim.mesh = rim_mesh
				rim.material_override = TerrainMaterials.rim_material(
					tile, level_data.terrain_tint(tile.tile_id))
				rim.set_meta("terrain_tile", tile.tile_id)
				rim.set_meta("terrain_layer", int(group["layer"]))
				rim.set_meta("terrain_rim", true)
				generated.add_child(rim)

func _build_shore_foam() -> void:
	if not style_profile.use_shore_foam:
		return
	for group in TerrainEdgeBuilder.foam_groups(level_data, _build_region):
		var land: TileDefinition = group["land"]
		var water: TileDefinition = group["water"]
		var paths := TerrainEdgeBuilder.traced_world_paths(
			level_data, group["edges"], land.corner_radius_m, style_profile.corner_segments)
		var water_y := level_data.surface_y(int(group["water_level"]))
		for path in paths:
			var mesh := TerrainEdgeBuilder.make_foam_mesh(path, water_y, water, style_profile)
			if mesh == null:
				continue
			var foam := MeshInstance3D.new()
			foam.name = "ShoreFoam"
			foam.mesh = mesh
			foam.material_override = TerrainMaterials.foam_material(water)
			foam.set_meta("water_level", int(group["water_level"]))
			foam.set_meta("terrain_layer", int(group["water_level"]))
			generated.add_child(foam)

func _build_stair(stair: Dictionary) -> void:
	var low: Vector2i = stair["cell"]
	var direction: int = int(stair["direction"]) % 4
	var vector: Vector2i = LevelData.DIRS[direction]
	var layer := int(stair.get("layer", level_data.top_layer(low)))
	var low_height := level_data.surface_y(layer)
	var low_center := level_data.world_center(low, layer)
	var high_center := level_data.world_center(low + vector, layer + 1)
	var center := (low_center + high_center) * 0.5
	var run_vector := Vector3(vector.x, 0.0, vector.y)
	var run_start := low_center - run_vector * LevelData.CELL_SIZE * 0.5
	var run_end := high_center + run_vector * LevelData.CELL_SIZE * 0.5
	var tile := TileRegistry.find(level_data.solid_tile_id(low + vector, layer + 1))
	var step_material: Material = stair_material
	var top_material: Material
	if tile != null and tile.art_set != null:
		step_material = TerrainMaterials.cliff_material(tile, level_data.terrain_tint(tile.tile_id), true)
		top_material = TerrainMaterials.top_material(tile, null, null, 0, null,
			level_data.terrain_tint(tile.tile_id), Color.TRANSPARENT, 0)
	for i in 10:
		var progress := (float(i) + 0.5) / 10.0
		var pos := run_start.lerp(run_end, progress)
		var step_height := low_height + LevelData.ELEVATION_STEP * (float(i) + 1.0) / 10.0
		var thickness := step_height - low_height
		pos.y = low_height + thickness * 0.5
		var size := Vector3(LevelData.CELL_SIZE, thickness, LevelData.CELL_SIZE * 2.0 / 10.0)
		if direction % 2 == 1:
			size = Vector3(LevelData.CELL_SIZE * 2.0 / 10.0, thickness, LevelData.CELL_SIZE)
		var step := _box("StairVisual_%02d" % i, pos, size, step_material, false)
		step.set_meta("stair_step", i)
		step.set_meta("stair_low_cell", low)
		step.set_meta("terrain_layer", layer + 1)
		if top_material != null:
			var top := MeshInstance3D.new()
			top.name = "StairTop_%02d" % i
			var plane := PlaneMesh.new()
			plane.size = Vector2(size.x, size.z)
			top.mesh = plane
			top.material_override = top_material
			top.position = pos + Vector3.UP * (thickness * 0.5 + 0.003)
			top.set_meta("terrain_layer", layer + 1)
			generated.add_child(top)
	if tile != null and tile.art_set != null and not tile.art_set.slope_side_path.is_empty():
		_build_slope_art(run_start, run_end, low_height, tile, layer + 1)
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
	body.set_meta("terrain_cell", low)
	body.set_meta("terrain_layer", layer + 1)
	body.set_meta("stair_low_cell", low)
	generated.add_child(body)

func _build_slope_art(start: Vector3, end: Vector3, bottom: float,
		tile: TileDefinition, layer: int) -> void:
	var texture := load(tile.art_set.slope_side_path) as Texture2D
	if texture == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.15
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_repeat = false
	var sideways := (end - start).normalized().cross(Vector3.UP) * (LevelData.CELL_SIZE * 0.5 + 0.006)
	for side in [-1, 1]:
		var points := PackedVector3Array([
			Vector3(start.x, bottom + LevelData.ELEVATION_STEP, start.z),
			Vector3(start.x, bottom, start.z), Vector3(end.x, bottom, end.z),
			Vector3(end.x, bottom + LevelData.ELEVATION_STEP, end.z)])
		for i in points.size():
			points[i] += sideways * side
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
			Vector2.ZERO, Vector2.DOWN, Vector2.ONE, Vector2.RIGHT])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var node := MeshInstance3D.new()
		node.name = "SlopeArt"
		node.mesh = mesh
		node.material_override = material
		node.set_meta("terrain_layer", layer)
		node.set_meta("slope_side", true)
		generated.add_child(node)

func _mark_limb_surfaces(bounds: Rect2i) -> void:
	if level_data == null or generated == null or Engine.is_editor_hint() or not build_collision:
		return
	for stair in level_data.stairs:
		var low: Vector2i = stair["cell"]
		if not bounds.has_point(low):
			continue
		var direction := int(stair.get("direction", 0)) % 4
		var high: Vector2i = low + LevelData.DIRS[direction]
		var layer := int(stair.get("layer", level_data.top_layer(low)))
		if not level_data.layer_exists(low, layer) or not level_data.layer_exists(high, layer + 1):
			continue
		var low_center := level_data.world_center(low, layer)
		var high_center := level_data.world_center(high, layer + 1)
		var span := high_center.y - low_center.y
		var stair_center := (low_center + high_center) * 0.5
		stair_center.y = low_center.y + span * 0.5 + 0.45
		var stair_size := Vector3(LevelData.CELL_SIZE, span + 1.3, LevelData.CELL_SIZE * 2.0)
		if direction % 2 == 1:
			stair_size = Vector3(LevelData.CELL_SIZE * 2.0, span + 1.3, LevelData.CELL_SIZE)
		_mark_surface(stair_center, PackedStringArray(["hard"]), stair_size, layer + 1)
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			for layer in level_data.exposed_layers(cell):
				if not level_data.is_solid_layer(cell, layer) or level_data.stair_at(cell, layer) >= 0:
					continue
				var center := level_data.world_center(cell, layer)
				_mark_surface(center + Vector3(0.0, 0.45, 0.0), _surface_tags_for_cell(cell, layer),
					Vector3(LevelData.CELL_SIZE, 1.2, LevelData.CELL_SIZE), layer)
				for direction in 4:
					var neighbor: Vector2i = cell + LevelData.DIRS[direction]
					for lower in level_data.exposed_layers(neighbor):
						if lower >= layer or level_data.stair_at(neighbor, lower) >= 0:
							continue
						var solid_wall := true
						for wall_layer in range(lower + 1, layer + 1):
							if not level_data.has_terrain_volume(cell, wall_layer):
								solid_wall = false
								break
						if not solid_wall:
							continue
						var offset: Vector2i = LevelData.DIRS[direction]
						var face := center + Vector3(offset.x, 0.0, offset.y) * LevelData.CELL_SIZE * 0.5
						face.y = level_data.surface_y(lower) + 1.0
						_mark_climb(face, center.y, center + Vector3(0.0, 0.08, 0.0), layer)


func _surface_tags_for_cell(cell: Vector2i, layer: int) -> PackedStringArray:
	var surface := _surface(layer)
	var tile := TileRegistry.find(surface.tile_id(cell))
	if tile != null and tile.is_water():
		return PackedStringArray(["fluid"])
	if surface.tile_id(cell) == TileRegistry.BUILTIN_SAND:
		return PackedStringArray(["desert", "hard"])
	return PackedStringArray(["hard", "rock"]) if surface.tile_id(cell) == "rock" \
		else PackedStringArray(["hard", "grass"])


func _mark_surface(center: Vector3, zone_tags: PackedStringArray,
		size := Vector3(LevelData.CELL_SIZE, 1.2, LevelData.CELL_SIZE), layer := -1) -> void:
	var zone := SurfaceZone.new()
	zone.tags = zone_tags
	zone.bind_volume(size)
	zone.position = center
	zone.set_meta("limb_marker", true)
	zone.set_meta("terrain_layer", layer)
	generated.add_child(zone)


func _mark_climb(face: Vector3, top_y: float, onto: Vector3, layer: int) -> void:
	var prop := AffordanceProp.new()
	prop.configure_marker("climbable")
	prop.ledge_height = top_y
	prop.ledge_point = onto
	prop.position = face
	prop.set_meta("limb_marker", true)
	prop.set_meta("terrain_layer", layer)
	generated.add_child(prop)


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
		var line := _box("Grid", Vector3(world_x, 0.025, center.y),
			Vector3(0.018, 0.018, total_z), material, false)
		line.set_meta("terrain_grid", true)
	for z in level_data.map_size.y + 1:
		var world_z := origin.y + z * LevelData.CELL_SIZE
		var line := _box("Grid", Vector3(center.x, 0.025, world_z),
			Vector3(total_x, 0.018, 0.018), material, false)
		line.set_meta("terrain_grid", true)

func _build_spawn_marker() -> void:
	if not level_data.is_surface_exposed(level_data.spawn_cell, level_data.spawn_layer):
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
	marker.position = level_data.world_center(level_data.spawn_cell, level_data.spawn_layer) \
		+ Vector3(0, 0.12, 0)
	marker.set_meta("terrain_layer", level_data.spawn_layer)
	generated.add_child(marker)

func set_slice_layer(layer: int) -> void:
	slice_layer_limit = clampi(layer, -1, LevelData.MAX_LAYERS - 1)
	if generated != null and is_instance_valid(generated):
		_apply_slice_visibility()

func _apply_slice_visibility() -> void:
	if generated == null or not is_instance_valid(generated):
		return
	if is_instance_valid(detail_renderer):
		detail_renderer.set_slice_layer(slice_layer_limit)
	if slice_layer_limit < 0 and _applied_slice_limit < 0:
		return
	_applied_slice_limit = slice_layer_limit
	if is_instance_valid(_slice_caps):
		_slice_caps.free()
	_slice_caps = null
	for child in generated.get_children():
		if child.has_meta("terrain_layer"):
			var visible := slice_layer_limit < 0 \
				or int(child.get_meta("terrain_layer", -1)) <= slice_layer_limit
			_set_slice_visible(child, visible)
	if slice_layer_limit < 0:
		return
	_slice_caps = Node3D.new()
	_slice_caps.name = "SliceCaps"
	generated.add_child(_slice_caps)
	var groups := {}
	for y in level_data.map_size.y:
		for x in level_data.map_size.x:
			var cell := level_data.map_origin + Vector2i(x, y)
			if not level_data.is_solid_layer(cell, slice_layer_limit):
				continue
			var stair := level_data.stair_at(cell, slice_layer_limit)
			var cut_stair := stair >= 0 and int(level_data.stairs[stair].get(
				"layer", level_data.top_layer(level_data.stairs[stair]["cell"]))) + 1 > slice_layer_limit
			if level_data.is_surface_exposed(cell, slice_layer_limit) and not cut_stair:
				continue
			var tile_id := level_data.solid_tile_id(cell, slice_layer_limit)
			var turns := int(level_data.get_layer(cell, slice_layer_limit).get("rotation", 0))
			var key := "%s|%d" % [tile_id, turns]
			if not groups.has(key):
				groups[key] = {"tile": tile_id, "turns": turns, "cells": []}
			groups[key]["cells"].append(cell)
			if build_collision:
				_add_slice_cap_collision(cell, slice_layer_limit)
	for group: Dictionary in groups.values():
		var tile_id: String = group["tile"]
		var tile := TileRegistry.find(tile_id)
		if tile == null:
			continue
		var mesh := TerrainEdgeBuilder.make_layer_top_mesh(
			level_data,
			group["cells"],
			slice_layer_limit,
			tile,
			style_profile.corner_segments,
			style_profile.top_surface_offset_m)
		if mesh == null:
			continue
		var cap := MeshInstance3D.new()
		cap.name = "SliceCap_%s_%d" % [tile_id, slice_layer_limit]
		cap.mesh = mesh
		cap.material_override = TerrainMaterials.top_material(
			tile,
			null,
			null,
			0,
			TerrainTopology.full_texture(),
			level_data.terrain_tint(tile_id),
			tile.tint_default(),
			int(group["turns"]))
		cap.set_meta("terrain_cells", group["cells"])
		cap.set_meta("terrain_layer", slice_layer_limit)
		cap.set_meta("slice_cap", true)
		_slice_caps.add_child(cap)

func _set_slice_visible(node: Node, visible: bool) -> void:
	if node.has_meta("slice_visible") and node.get_meta("slice_visible") == visible:
		return
	node.set_meta("slice_visible", visible)
	if node is Node3D:
		(node as Node3D).visible = visible
	for body in node.find_children("*", "CollisionObject3D", true, false):
		var collision := body as CollisionObject3D
		if not collision.has_meta("slice_collision_layer"):
			collision.set_meta("slice_collision_layer", collision.collision_layer)
		collision.collision_layer = int(
			collision.get_meta("slice_collision_layer", 1)) if visible else 0
	if node is CollisionObject3D:
		var collision := node as CollisionObject3D
		if not collision.has_meta("slice_collision_layer"):
			collision.set_meta("slice_collision_layer", collision.collision_layer)
		collision.collision_layer = int(
			collision.get_meta("slice_collision_layer", 1)) if visible else 0

func _add_slice_cap_collision(cell: Vector2i, layer: int) -> void:
	var body := Node3D.new()
	body.name = "SliceCapCollision"
	body.position = level_data.world_center(cell, layer)
	body.set_meta("terrain_cell", cell)
	body.set_meta("terrain_layer", layer)
	body.set_meta("slice_cap", true)
	_add_top_collision(body)
	_slice_caps.add_child(body)

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
