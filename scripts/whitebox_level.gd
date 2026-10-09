class_name WhiteboxLevel
extends Node3D

const COLOR_GRASS := Color("6f9b58")
const COLOR_PATH := Color("9b6c3f")
const COLOR_CLIFF := Color("8f7052")
const COLOR_WOOD := Color("68472f")
const COLOR_STONE := Color("686875")
const COLOR_TREE := Color("52795b")
const COLOR_TRUNK := Color("71543f")
const COLOR_WATER := Color("5799bc")
const COLOR_GOAL := Color("e4aa32")

var _materials: Dictionary = {}


func _ready() -> void:
	_build_level()


func _build_level() -> void:
	# 参考《智慧的再现》的紧凑俯视野外：水体切分空间，桥和地形形成多路线。
	_create_visual_box("Water", Vector3(42.0, 0.08, 40.0), Vector3(0.0, -1.45, -2.0), COLOR_WATER)
	_create_box("SouthMeadow", Vector3(20.0, 0.5, 12.0), Vector3(0.0, -0.25, 8.0), COLOR_GRASS)
	_create_box("WestRiverBank", Vector3(10.0, 0.5, 8.0), Vector3(-7.0, -0.25, -2.0), COLOR_GRASS)
	_create_box("EastRiverBank", Vector3(10.0, 0.5, 10.0), Vector3(7.0, -0.25, -1.0), COLOR_GRASS)
	_create_box("NorthField", Vector3(24.0, 0.5, 10.0), Vector3(0.0, -0.25, -11.0), COLOR_GRASS)

	# 土路只负责引导视线，碰撞仍由草地区块承担。
	_create_visual_box("SouthPath", Vector3(3.2, 0.05, 9.2), Vector3(0.0, 0.025, 8.0), COLOR_PATH)
	_create_visual_box("WestPath", Vector3(3.0, 0.05, 7.5), Vector3(-6.0, 0.025, -1.8), COLOR_PATH)
	_create_visual_box("EastPath", Vector3(3.0, 0.05, 8.8), Vector3(6.0, 0.025, -1.0), COLOR_PATH)
	_create_visual_box("NorthPath", Vector3(7.5, 0.05, 3.0), Vector3(-3.6, 0.025, -9.0), COLOR_PATH)

	# 桥面和两岸齐平，沿南北接上草地。栏杆只挡两侧，不封住桥头。
	_create_box("RiverBridge", Vector3(4.6, 0.24, 8.4), Vector3(0.0, -0.12, -2.0), COLOR_WOOD)
	_create_box("BridgeRail_West", Vector3(0.16, 0.42, 5.2), Vector3(-1.9, 0.21, -2.0), COLOR_WOOD)
	_create_box("BridgeRail_East", Vector3(0.16, 0.42, 5.2), Vector3(1.9, 0.21, -2.0), COLOR_WOOD)
	_create_box("RiverStone_A", Vector3(1.0, 0.35, 1.0), Vector3(0.0, -0.05, -5.0), COLOR_STONE)
	_create_box("RiverStone_B", Vector3(0.8, 0.5, 0.8), Vector3(1.15, 0.05, -5.8), COLOR_STONE)

	# 北侧高台作为本段目标。坡道从东岸爬上去，角度低于可行走上限。
	# 南面留出坡道尽头的平地，避免胶囊体先撞上竖直崖壁。
	_create_box("NorthCliff", Vector3(9.0, 2.0, 5.6), Vector3(5.8, 1.0, -12.1), COLOR_CLIFF)
	_create_ramp("CliffRamp", 2.6, 2.08, 3.8, Vector3(2.2, 0.0, -4.6), COLOR_STONE)
	_create_box("CliffLanding", Vector3(2.6, 0.24, 1.4), Vector3(2.2, 1.88, -8.95), COLOR_STONE)

	# 遗迹门框和终点台，让远景目标在高俯角下依然清楚。
	_create_box("RuinPillar_Left", Vector3(0.65, 2.4, 0.65), Vector3(3.8, 3.2, -12.8), COLOR_STONE)
	_create_box("RuinPillar_Right", Vector3(0.65, 2.4, 0.65), Vector3(7.8, 3.2, -12.8), COLOR_STONE)
	_create_box("RuinLintel", Vector3(4.65, 0.55, 0.65), Vector3(5.8, 4.25, -12.8), COLOR_STONE)
	_create_box("GoalPlinth", Vector3(3.4, 0.3, 2.6), Vector3(5.8, 2.15, -11.2), COLOR_GOAL)
	_create_goal_trigger(Vector3(5.8, 3.0, -11.2))

	# 树林和岩石承担地图边界及视线引导，中心路线保持清爽。
	var tree_positions := [
		Vector3(-8.5, 0.0, 11.5), Vector3(-7.0, 0.0, 9.8), Vector3(-8.4, 0.0, 6.8),
		Vector3(8.5, 0.0, 10.8), Vector3(7.4, 0.0, 8.4), Vector3(9.0, 0.0, 5.2),
		Vector3(-10.5, 0.0, -0.2), Vector3(-9.0, 0.0, -4.7), Vector3(-6.8, 0.0, -5.2),
		Vector3(-10.2, 0.0, -12.8), Vector3(-7.6, 0.0, -14.4), Vector3(-4.8, 0.0, -14.6),
		Vector3(10.2, 0.0, -6.8), Vector3(10.4, 0.0, -14.2)
	]
	for index in range(tree_positions.size()):
		_create_tree("Tree_%02d" % index, tree_positions[index], 0.9 + float(index % 3) * 0.08)

	_create_rock("Rock_SouthWest", Vector3(-4.2, 0.0, 5.0), Vector3(1.4, 0.8, 1.1), 18.0)
	_create_rock("Rock_SouthEast", Vector3(4.5, 0.0, 3.8), Vector3(1.1, 1.0, 1.3), -25.0)
	_create_rock("Rock_WestBank", Vector3(-8.2, 0.0, -1.0), Vector3(1.6, 1.1, 1.0), 32.0)
	_create_rock("Rock_North", Vector3(-2.2, 0.0, -12.0), Vector3(1.3, 0.9, 1.5), -12.0)

	_create_box("Fence_A", Vector3(4.0, 0.65, 0.22), Vector3(-4.8, 0.38, 2.2), COLOR_WOOD, Vector3(0.0, 12.0, 0.0))
	_create_box("Fence_B", Vector3(3.4, 0.65, 0.22), Vector3(4.6, 0.38, 1.9), COLOR_WOOD, Vector3(0.0, -18.0, 0.0))


func _create_ramp(node_name: String, width: float, rise: float, run: float, south_lip: Vector3, color: Color) -> void:
	var length := sqrt(rise * rise + run * run)
	var angle := atan2(rise, run)
	var thickness := 0.28
	var body := StaticBody3D.new()
	body.name = node_name
	# 正 X 旋转让北端抬高。再下移半个厚度，让坡面低端贴住地面。
	body.rotation.x = angle
	var surface_lift := thickness * 0.5 * cos(angle)
	body.position = south_lip + Vector3(0.0, rise * 0.5 - surface_lift, -run * 0.5)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(width, thickness, length)
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _get_material(color)
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thickness, length)
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _create_box(node_name: String, size: Vector3, center: Vector3, color: Color, rotation_degrees_value := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = center
	body.rotation_degrees = rotation_degrees_value

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _get_material(color)
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	add_child(body)
	return body


func _create_visual_box(node_name: String, size: Vector3, center: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = center
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _get_material(color)
	add_child(mesh_instance)
	return mesh_instance


func _create_tree(node_name: String, ground_position: Vector3, scale_value: float) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = ground_position
	body.scale = Vector3.ONE * scale_value

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.26
	trunk_mesh.bottom_radius = 0.34
	trunk_mesh.height = 1.45
	trunk.mesh = trunk_mesh
	trunk.position.y = 0.725
	trunk.material_override = _get_material(COLOR_TRUNK)
	body.add_child(trunk)

	var canopy := MeshInstance3D.new()
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 1.05
	canopy_mesh.height = 1.8
	canopy.mesh = canopy_mesh
	canopy.position.y = 1.85
	canopy.material_override = _get_material(COLOR_TREE)
	body.add_child(canopy)

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.38
	shape.height = 1.5
	collision.shape = shape
	collision.position.y = 0.75
	body.add_child(collision)
	add_child(body)


func _create_rock(node_name: String, ground_position: Vector3, size: Vector3, yaw_degrees: float) -> void:
	_create_box(node_name, size, ground_position + Vector3.UP * size.y * 0.5, COLOR_STONE, Vector3(0.0, yaw_degrees, 8.0))


func _create_goal_trigger(center: Vector3) -> void:
	var area := Area3D.new()
	area.name = "GoalTrigger"
	area.position = center
	area.collision_layer = 0
	area.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.2, 2.0, 3.5)
	collision.shape = shape
	area.add_child(collision)
	area.body_entered.connect(_on_goal_body_entered)
	add_child(area)


func _get_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(true)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if color == COLOR_WATER:
		material.metallic = 0.05
	_materials[key] = material
	return material


func _on_goal_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		get_tree().call_group("hud", "show_goal_message")
