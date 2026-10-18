extends SceneTree

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var recipe := WorldGenConfig.new()
	recipe.width=96
	recipe.height=64
	var generator := WorldGenerator.new()
	if not generator.prepare(recipe).is_empty():
		quit(1)
		return
	var result := generator.generate()
	var map: LevelData=result.data
	# A real water column beside spawn makes swimming reproducible.
	for y in range(map.spawn_cell.y-4,map.spawn_cell.y+5):
		for x in range(map.spawn_cell.x-5,map.spawn_cell.x+6):
			map.set_layer(Vector2i(x,y),2,{"tile_id":"water"})
	map.encounter=EncounterConfig.default_config()
	map.encounter.enabled=true
	var path := "/tmp/swim-jolt-metal-map.tres"
	ResourceSaver.save(map,path)
	var play := load("res://scripts/runtime/level_playtest.gd").new() as Node3D
	play.level_override=path
	root.add_child(play)
	var original: CharacterBody3D=play.player
	play.player=null
	original.remove_child(play.combat_health)
	var player := load("res://scenes/player.tscn").instantiate() as PlayerController
	player.name="Player"
	player.position=map.world_center(map.spawn_cell,2)
	play.add_child(player)
	player.add_child(play.combat_health)
	original.free()
	play.camera_rig.target=player
	play.encounter_director.player=player
	await physics_frame
	await physics_frame
	player.parts.equip("gorilla_arm","fish_tail")
	play.encounter_director.set_physics_process(false)
	player.velocity=Vector3.ZERO
	var start := player.global_position
	Input.action_press("move_right")
	for i in 60:
		await physics_frame
	Input.action_release("move_right")
	var velocity := player.velocity.x
	var distance := player.global_position.x-start.x
	print("SWIM METAL fish distance ",distance," final speed ",velocity)
	var count := play.find_children("*","CollisionObject3D",true,false).size()
	var label := Label.new()
	label.position=Vector2(18,450)
	label.add_theme_font_override("font",play.runtime_font())
	label.text="96×64 实际生成世界 · 碰撞对象 %d / Jolt 10240\n鱼尾水面游泳：末速度 %.1fm/s · 水平移动 %.2fm"%[
		count,velocity,distance]
	play.get_node("EncounterLayer").add_child(label)
	var folder := "/Users/bytedance/Desktop/godot/游泳与物理碰撞_验收截图"
	DirAccess.make_dir_recursive_absolute(folder)
	for i in 30:
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/01_鱼尾游泳_96x64.png")
	player.set_physics_process(false)
	play.camera_rig.target=null
	play.camera_rig.global_position=Vector3(0,110,120)
	play.camera_rig.look_at(Vector3(0,4,0))
	play.camera.size=190
	play.camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	for i in 30:
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/02_96x64世界碰撞.png")
	print("SWIM METAL collision objects ",count," chunks ",play.builder._chunk_nodes.size())
	if "--keep-window" in OS.get_cmdline_user_args():
		print("SWIM METAL ready for UI")
	else:
		quit(0 if absf(velocity-5)<0.01 else 1)
