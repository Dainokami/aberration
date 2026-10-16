class_name PartBlocks
extends Node3D

var _upper: MeshInstance3D
var _lower: MeshInstance3D
var _swing := 0.0
var _around := false
var _loadout: PartLoadout


func _ready() -> void:
	_upper = _white_box(Vector3(0.28, 0.92, 0.22))
	_upper.position = Vector3(0.95, 1.2, 0.0)
	add_child(_upper)
	_lower = _white_box(Vector3(0.7, 0.22, 0.95))
	_lower.position = Vector3(0.0, 0.2, 0.2)
	add_child(_lower)
	_loadout = get_parent().get_node_or_null("PartLoadout") as PartLoadout
	if _loadout:
		_loadout.attacked.connect(_on_attacked)
		_loadout.changed_loadout.connect(_refresh_shape)
		_refresh_shape()


func _process(delta: float) -> void:
	_swing = maxf(_swing - delta, 0.0)
	var bob := sin(Time.get_ticks_msec() * 0.006) * 0.04
	_upper.position.y = 1.2 + bob
	_upper.rotation.z = sin(Time.get_ticks_msec() * 0.004) * 0.18
	if _swing > 0.0:
		var strike := sin((1.0 - _swing / 0.22) * PI)
		if _around:
			_upper.position.x = 0.2
			_upper.rotation.y = strike * 1.4
		else:
			_upper.position.z = -0.55 * strike
	else:
		_upper.position.x = 0.95
		_upper.position.z = 0.0
		_upper.rotation.y = 0.0
	if _loadout and _loadout.is_burrowed():
		_lower.position.y = -0.02
	else:
		_lower.position.y = 0.2


func _on_attacked(around: bool) -> void:
	_around = around
	_swing = 0.22


func _refresh_shape() -> void:
	if _loadout == null:
		return
	var upper := _loadout.current_upper()
	var lower := _loadout.current_lower()
	_resize(_upper, _upper_size(upper.id))
	_resize(_lower, _lower_size(lower.id))


func _upper_size(part_id: String) -> Vector3:
	match part_id:
		"gibbon_arm":
			return Vector3(0.16, 1.35, 0.16)
		"goose_wing", "bat_wing", "albatross_wing", "eagle_wing":
			return Vector3(0.9, 0.12, 0.55)
		"octopus_arm":
			return Vector3(0.22, 0.7, 0.22)
		"gerbil_paw":
			return Vector3(0.4, 0.28, 0.4)
		_:
			return Vector3(0.34, 0.9, 0.28)


func _lower_size(part_id: String) -> Vector3:
	match part_id:
		"ostrich_leg":
			return Vector3(0.28, 0.7, 0.28)
		"kangaroo_leg":
			return Vector3(0.45, 0.55, 0.7)
		"goose_foot":
			return Vector3(0.8, 0.12, 0.45)
		"water_snake", "fish_tail":
			return Vector3(0.35, 0.22, 1.15)
		"octopus_leg":
			return Vector3(0.3, 0.45, 0.3)
		_:
			return Vector3(0.55, 0.24, 0.85)


func _white_box(size: Vector3) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.97, 0.97, 0.95)
	mesh_instance.material_override = material
	return mesh_instance


func _resize(mesh_instance: MeshInstance3D, size: Vector3) -> void:
	var box := mesh_instance.mesh as BoxMesh
	if box:
		box.size = size
