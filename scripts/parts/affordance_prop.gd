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
var host: Node3D
var rest_y := 0.0
var ledge_height := -1.0
var ledge_point := Vector3.ZERO
var _plain := false


func configure_host(body: Node3D, kind_name: String, health_value: int) -> void:
	host = body
	kind = kind_name
	max_health = health_value
	health = health_value
	_plain = true


func configure_marker(kind_name: String) -> void:
	kind = kind_name
	max_health = 1
	health = 1
	_plain = true


func _ready() -> void:
	add_to_group("affordance")
	health = max_health
	rest_y = global_position.y
	if _plain:
		return
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
	var gameplay := host as GameplayProp
	if gameplay != null:
		if not gameplay.apply_damage(amount):
			return false
		health = gameplay.health
		spent = gameplay.state == "broken"
		return spent
	health -= amount
	var block := get_node_or_null("Block") as MeshInstance3D
	if block and block.material_override is StandardMaterial3D:
		(block.material_override as StandardMaterial3D).albedo_color = Color(0.75, 0.75, 0.75)
	if health > 0:
		_tint_host(1.0 - float(health) / float(maxi(max_health, 1)))
		return false
	spent = true
	if host:
		host.visible = false
		_set_host_collision(false)
	else:
		visible = false
		collision_layer = 0
	return true


func interaction_point() -> Vector3:
	if host != null and is_instance_valid(host):
		var shapes := host.find_children("*", "CollisionShape3D", true, false)
		if not shapes.is_empty():
			return (shapes[0] as CollisionShape3D).global_position
	return global_position + Vector3.UP * maxf(box_size.y * 0.5, 0.35)


func owns_collider(collider: Object) -> bool:
	var node := collider as Node
	if node == null:
		return false
	if node == self or is_ancestor_of(node):
		return true
	return host != null and is_instance_valid(host) and (node == host or host.is_ancestor_of(node))


func set_carried(carried: bool) -> void:
	if host:
		_set_host_collision(not carried)
		return
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
	if ballistic:
		throw_velocity.y -= 14.0 * delta
		global_position += throw_velocity * delta
		if throw_velocity.y <= 0.0 and global_position.y <= rest_y:
			global_position.y = rest_y
			ballistic = false
			throw_velocity = Vector3.ZERO
			collision_layer = 0 if host else 1
			if host:
				_set_host_collision(true)
	if host and is_instance_valid(host):
		host.global_position = global_position


func _set_host_collision(enabled: bool) -> void:
	if host == null:
		return
	_set_collision(host, enabled)


func _set_collision(node: Node, enabled: bool) -> void:
	var body := node as CollisionObject3D
	if body and body != self:
		body.collision_layer = 1 if enabled else 0
	for child in node.get_children():
		_set_collision(child, enabled)


func _tint_host(amount: float) -> void:
	if host == null:
		return
	_tint(host, Color(1, 1, 1).lerp(Color(0.55, 0.42, 0.38), clampf(amount, 0.0, 1.0)))


func _tint(node: Node, color: Color) -> void:
	if node is Sprite3D:
		(node as Sprite3D).modulate = color
	elif node is MeshInstance3D and (node as MeshInstance3D).material_override is StandardMaterial3D:
		((node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = color
	for child in node.get_children():
		_tint(child, color)
