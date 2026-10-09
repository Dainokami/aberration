@tool
class_name TerrainBuilder
extends Node3D

@export var level_data: LevelData
@export var show_grid := true
@export var build_collision := true

var generated: Node3D
var grass_material: ShaderMaterial
var rock_material: ShaderMaterial
var side_material: ShaderMaterial
var stair_material: StandardMaterial3D

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
	level_data.ensure_layout()
	_prepare_materials()
	for y in level_data.map_size.y:
		for x in level_data.map_size.x:
			var cell := Vector2i(x, y)
			if level_data.cell_exists(cell) and level_data.stair_at(cell) < 0:
				_build_cell(cell)
	for stair in level_data.stairs:
		_build_stair(stair)
	if show_grid:
		_build_grid()
	_build_spawn_marker()
	_build_objects()

func _build_objects() -> void:
	for record in level_data.objects:
		var definition := ObjectRules.definition(record)
		if definition == null or not ResourceLoader.exists(definition.scene_path):
			continue
		var packed := load(definition.scene_path) as PackedScene
		if packed == null:
			continue
		var object := packed.instantiate() as Node3D
		object.position = record.get("position", Vector3.ZERO)
		object.rotation.y = float(record.get("yaw", 0.0))
		object.scale = Vector3.ONE * float(record.get("scale", 1.0))
		object.set_meta("object_id", record.get("id", ""))
		generated.add_child(object)

func _terrain_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform vec4 base : source_color;
varying vec3 world_pos;
void vertex(){ world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
	float stroke=sin(world_pos.x*5.7+sin(world_pos.z*3.1))*sin(world_pos.z*7.3);
	float macro=sin(world_pos.x*0.55)*cos(world_pos.z*0.42);
	ALBEDO=base.rgb*(0.94+stroke*0.035+macro*0.07);
	ROUGHNESS=1.0;
}
"""
	return shader

func _prepare_materials() -> void:
	var shader := _terrain_shader()
	grass_material = ShaderMaterial.new()
	grass_material.shader = shader
	grass_material.set_shader_parameter("base", Color("#738858"))
	rock_material = ShaderMaterial.new()
	rock_material.shader = shader
	rock_material.set_shader_parameter("base", Color("#756d70"))
	side_material = ShaderMaterial.new()
	side_material.shader = shader
	side_material.set_shader_parameter("base", Color("#403944"))
	stair_material = StandardMaterial3D.new()
	stair_material.albedo_color = Color("#776b71")
	stair_material.roughness = 1.0

func _build_cell(cell: Vector2i) -> void:
	var data := level_data.get_cell(cell)
	var center := level_data.world_center(cell)
	var top := _box("Top_%d_%d" % [cell.x, cell.y], center - Vector3(0, 0.05, 0),
		Vector3(LevelData.CELL_SIZE, 0.1, LevelData.CELL_SIZE),
		grass_material if int(data["terrain"]) == LevelData.TERRAIN_GRASS else rock_material, true)
	top.set_meta("terrain_cell", cell)
	if top.get_child_count() > 0:
		top.get_child(0).set_meta("terrain_cell", cell)
	for direction in 4:
		var neighbor: Vector2i = cell + LevelData.DIRS[direction]
		var neighbor_level := LevelData.BASE_Y
		if level_data.cell_exists(neighbor) and level_data.stair_at(neighbor) < 0:
			neighbor_level = level_data.elevation(neighbor) * LevelData.ELEVATION_STEP
		var top_y := center.y
		if top_y <= neighbor_level:
			continue
		var height := top_y - neighbor_level
		var offset: Vector2i = LevelData.DIRS[direction]
		var side_center := center + Vector3(offset.x, 0, offset.y) * LevelData.CELL_SIZE * 0.5
		side_center.y = neighbor_level + height * 0.5
		var size := Vector3(LevelData.CELL_SIZE, height, 0.08)
		if direction % 2 == 1:
			size = Vector3(0.08, height, LevelData.CELL_SIZE)
		_box("Side", side_center, size, side_material, true)

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
		if node.has_meta("terrain_cell"):
			body.set_meta("terrain_cell", node.get_meta("terrain_cell"))
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		node.add_child(body)
	return node

func _build_stair(stair: Dictionary) -> void:
	var low: Vector2i = stair["cell"]
	var direction: int = int(stair["direction"]) % 4
	var vector: Vector2i = LevelData.DIRS[direction]
	var low_height := level_data.elevation(low) * LevelData.ELEVATION_STEP
	var low_center := level_data.world_center(low)
	var high_center := level_data.world_center(low + vector)
	var center := (low_center + high_center) * 0.5
	var horizontal := Vector3(vector.x, 0, vector.y)
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
	# Direction 0 is north (-Z): local +Z is low, local -Z is high.
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
	for x in level_data.map_size.x + 1:
		var world_x := -total_x * 0.5 + x * LevelData.CELL_SIZE
		_box("Grid", Vector3(world_x, 0.025, 0), Vector3(0.018, 0.018, total_z), material, false)
	for z in level_data.map_size.y + 1:
		var world_z := -total_z * 0.5 + z * LevelData.CELL_SIZE
		_box("Grid", Vector3(0, 0.025, world_z), Vector3(total_x, 0.018, 0.018), material, false)

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
