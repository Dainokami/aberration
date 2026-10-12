class_name AffordanceProp
extends StaticBody3D

# kind 是部件认识的全部接口：pushable、climbable、destructible_hard、
# destructible_soft、grabbable、enemy_small、enemy_elite。
@export var kind := "pushable"
@export var box_size := Vector3(1, 1, 1)
@export var max_health := 3

var health := 3
var spent := false
var ballistic := false
var throw_velocity := Vector3.ZERO


func _ready() -> void:
	add_to_group("affordance")
	health = max_health
	collision_layer = 1
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	shape.position.y = box_size.y * 0.5
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_size
	mesh.mesh = box_mesh
	mesh.position.y = box_size.y * 0.5
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.96, 0.96, 0.94)
	mesh.material_override = material
	mesh.name = "Block"
	add_child(mesh)


func take_hit(amount: int) -> bool:
	if spent or amount <= 0:
		return false
	if kind == "pushable" or kind == "climbable" or kind == "grabbable":
		return false
	health -= amount
	var block := get_node_or_null("Block") as MeshInstance3D
	if block and block.material_override is StandardMaterial3D:
		(block.material_override as StandardMaterial3D).albedo_color = Color(0.75, 0.75, 0.75)
	if health > 0:
		return false
	spent = true
	visible = false
	collision_layer = 0
	return true


func set_carried(carried: bool) -> void:
	collision_layer = 0 if carried else 1


func throw_along(direction: Vector3) -> void:
	set_carried(false)
	ballistic = true
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.01:
		flat = Vector3.FORWARD
	throw_velocity = flat.normalized() * 9.0 + Vector3.UP * 6.0


func drop() -> void:
	set_carried(false)
	ballistic = false
	throw_velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not ballistic:
		return
	throw_velocity.y -= 14.0 * delta
	global_position += throw_velocity * delta
	if global_position.y <= 0.05:
		global_position.y = 0.05
		ballistic = false
		throw_velocity = Vector3.ZERO
		collision_layer = 1
