extends RigidBody3D

var item_id := "treasure"
var age := 0.0

func _physics_process(delta: float) -> void:
	age += delta
	if age < 0.5:
		return
	for group in ["player", "level_player"]:
		for actor in get_tree().get_nodes_in_group(group):
			if actor is Node3D and global_position.distance_to(actor.global_position) < 1.0:
				if SceneMechanism.store_item(actor, item_id):
					queue_free()
					return
				SceneMechanism.notify(actor, "背包已满，无法拾取")
