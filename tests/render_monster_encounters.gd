extends SceneTree

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var play := load("res://scripts/runtime/level_playtest.gd").new() as Node3D
	play.level_override = "res://data/levels/monster_spawn_points_demo.tres"
	root.add_child(play)
	await physics_frame
	await physics_frame
	print("MONSTER RENDER ready paused=",paused, " control=",play.encounter_director.control_ready)
	var director: EncounterDirector = play.encounter_director
	director.set_physics_process(false)
	play.combat_health.setup(10000)
	director._physics_process(29)
	assert(director.actors.is_empty())
	director._physics_process(1)
	assert(not director.actors.is_empty())
	var counter := 0
	for actor in director.actors:
		actor.global_position = play.player.global_position + Vector3(counter*2-2,-0.8,3)
		actor.repath()
		counter += 1
	for i in 60:
		await physics_frame
	print("MONSTER RENDER actual actors ",director.actors.size()," hp ",play.combat_health.current)
	await RenderingServer.frame_post_draw
	var folder := "/Users/bytedance/Desktop/godot/小怪刷新点_验收截图"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+"/01_怪物追踪与生命.png")
	if "--spawn-range-proof" in OS.get_cmdline_user_args():
		# Natural offscreen spawning, without relocating the monsters for framing.
		for actor in director.actors.duplicate():
			actor.queue_free()
		director.actors.clear()
		await physics_frame
		var point := MonsterSpawnPoints.create("画面外营地")
		point.id = "render_offscreen_point"
		point.cells = [Vector3i(17, 0, 27), Vector3i(18, 0, 27)]
		play.data.monster_spawn_points.assign([point])
		director.point_clocks.clear()
		director._update_point_ranges()
		var center := MonsterSpawnPoints.center(play.data, point)
		var in_screen: bool = not play.camera.is_position_behind(center) \
			and Rect2(Vector2.ZERO, root.size).has_point(play.camera.unproject_position(center))
		print("RANGE METAL offscreen=", not in_screen, " active=", director.point_active(point),
			" radius=", director.point_radius(point))
		assert(not in_screen and director.point_active(point))
		director._physics_process(30)
		assert(not director.actors.is_empty())
		for actor in director.actors:
			actor.set_physics_process(false)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/06_画面外激活与方向提示.png")
	for i in 2:
		print("MONSTER RENDER spawning elite ",i)
		director._spawn_elite(i)
		print("MONSTER RENDER spawned elite ",i)
		var elite: MonsterActor = director.actors.back()
		elite.take_damage(100000,"player")
	director.timeline.elapsed=900
	print("MONSTER RENDER requesting phase")
	director._physics_process(1)
	print("MONSTER RENDER elite states ",director.timeline.elites,
		" diagnostics ",director.diagnostics)
	print("MONSTER RENDER gate ",director.gate != null," elapsed ",director.timeline.elapsed)
	if director.gate != null:
		play.player.global_position=director.gate.global_position+Vector3(0,0.8,5)
		play.camera_rig.global_position = play.player.global_position + play.camera_rig.offset
		play.camera_rig.look_at(play.player.global_position + play.camera_rig.focus_offset)
	for i in 60:
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/02_Boss门与箭头.png")
	if director.fog != null:
		director.fog.step(30)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/03_浓雾安全区.png")
	if "--keep-window" in OS.get_cmdline_user_args():
		director.set_physics_process(true)
		print("MONSTER RENDER ready for UI")
	else:
		quit()
