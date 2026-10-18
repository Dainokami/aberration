class_name SurfaceZone
extends Node3D

@export var tags: PackedStringArray = PackedStringArray(["fluid"])

var _box: BoxShape3D


func _ready() -> void:
	add_to_group("surface_zone")


func bind_volume(size: Vector3) -> void:
	_box = BoxShape3D.new()
	_box.size = size


func setup(size: Vector3, zone_tags: PackedStringArray, tint: Color) -> void:
	tags = zone_tags
	bind_volume(size)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	mesh.material_override = material
	add_child(mesh)


func covers(point: Vector3) -> bool:
	if _box == null:
		return false
	var xform := transform
	if is_inside_tree():
		force_update_transform()
		xform = global_transform
	var local: Vector3 = xform.affine_inverse() * point
	var half := _box.size * 0.5
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z
