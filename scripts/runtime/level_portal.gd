class_name LevelPortal
extends Node3D

const INTERACTION_REACH := 2.5
var active := true

func can_interact(player: CharacterBody3D) -> bool:
	if not active or not is_instance_valid(player) or not is_inside_tree():
		return false
	var target := global_position + Vector3.UP * 0.8
	if player.global_position.distance_to(target) > INTERACTION_REACH:
		return false
	var query := PhysicsRayQueryParameters3D.create(player.global_position,
		target, 1, [player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
