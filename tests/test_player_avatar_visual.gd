extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	print("PLAYER AVATAR CHECK ", label, " ", condition)
	if not condition:
		failures.append(label)


func _run() -> void:
	var packed := load("res://scenes/player_avatar_visual.tscn") as PackedScene
	var avatar := packed.instantiate() as Node3D
	root.add_child(avatar)
	var sprite := avatar.get_node("Composite") as Sprite3D
	check(sprite != null and sprite.texture.resource_path \
		== "res://art/characters/prototype/character_composite.png",
		"shared preview uses the 3C character artwork")
	check(sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED
		and is_equal_approx(sprite.pixel_size, 0.00435),
		"shared preview keeps the approved character scale and camera-facing mode")
	check(avatar.find_children("*", "CollisionObject3D", true, false).is_empty(),
		"shared preview has no editor collision")
	avatar.queue_free()
	await process_frame

	if Engine.is_editor_hint():
		await _check_editor_marker()
	else:
		await _check_runtime_player()

	print("PLAYER AVATAR FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)


func _check_editor_marker() -> void:
	var data := load("res://data/levels/acceptance_map.tres") as LevelData
	var builder := TerrainBuilder.new()
	builder.show_grid = false
	builder.build_collision = false
	builder.level_data = data
	root.add_child(builder)
	await process_frame
	var marker := builder.generated.get_node_or_null("SpawnMarker") as Node3D
	check(marker != null and marker.get_node_or_null("Composite") is Sprite3D,
		"editor spawn marker displays the shared character")
	check(marker != null and marker.position.is_equal_approx(
		data.world_center(data.spawn_cell, data.spawn_layer)),
		"editor character stands on the saved spawn surface")
	builder.queue_free()
	await process_frame


func _check_runtime_player() -> void:
	var playtest = load("res://scenes/level_playtest.tscn").instantiate()
	playtest.level_override = "res://data/levels/acceptance_map.tres"
	root.add_child(playtest)
	for frame in 5:
		await physics_frame
	var player := playtest.player as CharacterBody3D
	var collision := player.get_child(0) as CollisionShape3D
	var visual := player.get_node_or_null("CharacterVisual") as Node3D
	check(collision != null and collision.shape is CapsuleShape3D,
		"playtest keeps the existing invisible capsule collision")
	check(visual != null and visual.get_node_or_null("Composite") is Sprite3D,
		"playtest replaces the visible capsule with the shared character")
	check(not _has_capsule_mesh(player),
		"playtest no longer renders a capsule mesh")
	check(visual != null and is_equal_approx(visual.position.y, -playtest.PLAYER_HALF_HEIGHT),
		"playtest character feet align with the collision body")
	playtest.queue_free()
	await process_frame


func _has_capsule_mesh(node: Node) -> bool:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if (child as MeshInstance3D).mesh is CapsuleMesh:
			return true
	return false
