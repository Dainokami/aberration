extends GameplayProp

## The imported rock uses the same part-system interface as the existing demo rock.
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	var proxy := get_node_or_null("ProxyCollision") as CollisionObject3D
	if proxy == null or proxy.collision_layer == 0:
		return
	var handle := AffordanceProp.new()
	handle.name = "CarryHandle"
	handle.configure_host(self, "pushable", 1)
	var container := get_parent()
	container.add_child.call_deferred(handle)
	handle.set_meta("terrain_layer", get_meta("terrain_layer", -1))
	handle.tree_entered.connect(func(): handle.global_transform = global_transform, CONNECT_ONE_SHOT)
	tree_exiting.connect(func():
		if is_instance_valid(handle):
			handle.queue_free()
	)
