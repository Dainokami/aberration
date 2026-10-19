extends SceneTree

var failures: Array[String] = []
var times: Array[float] = []
var level: Node3D
var stamp := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	print("STREAM RUNTIME ", value, " ", label)
	if not value:
		failures.append(label)

func frames(count: int, measure := false) -> void:
	for i in count:
		await process_frame
		if measure and stamp != 0:
			times.append((Time.get_ticks_usec() - stamp) / 1000.0)
		stamp = Time.get_ticks_usec()
		await physics_frame

func camera_ground_loaded(builder: TerrainBuilder, camera: Camera3D, data: LevelData) -> bool:
	var size := camera.get_viewport().get_visible_rect().size
	var plane := Plane(Vector3.UP, builder.global_position.y + data.surface_y(0))
	for screen in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y), size * 0.5]:
		var hit: Variant = plane.intersects_ray(
			camera.project_ray_origin(screen), camera.project_ray_normal(screen))
		if hit == null:
			return false
		if camera.global_position.distance_to(hit) > camera.far:
			continue
		var cell := data.world_to_cell(builder.to_local(hit))
		if data.in_bounds(cell) and not builder.stream_cell_loaded(cell):
			return false
	return true

func run() -> void:
	var map := LevelData.new()
	map.setup_blank(Vector2i(200, 200))
	for y in 200:
		for x in 200:
			var id := "grass" if x < 104 else "rock"
			map.columns[y * 200 + x] = {"layers": [{"tile_id": id}]}
	map.spawn_cell = Vector2i(100, 100)
	map.spawn_layer = 0
	map.level_transition = LevelTransitionConfig.new()
	map.level_transition.countdown_seconds = 7200
	map.encounter = EncounterConfig.default_config()
	map.encounter.enabled = true
	var point := MonsterSpawnPoints.create("移动验证")
	point.cells = [Vector3i(103, 0, 100)]
	point.activation_radius = 36.0
	map.monster_spawn_points.append(point)
	level = load("res://scenes/level_playtest.tscn").instantiate()
	level.prepared_level = map
	level.level_override = "/tmp/stream-runtime.tres"
	var start := Time.get_ticks_usec()
	root.add_child(level)
	current_scene = level
	level.testing = true
	var builder: TerrainBuilder = level.builder
	var player: CharacterBody3D = level.player
	var director: EncounterDirector = level.encounter_director
	if "--water" in OS.get_cmdline_user_args():
		# Runtime owns an isolated LevelData fork.
		for i in level.data.columns.size():
			level.data.columns[i] = {"layers": [{"tile_id": "grass"},
				{"tile_id": "water"}, {"tile_id": "water"}]}
		builder.rebuild()
		builder.follow_stream_camera(level.camera, player)
		player.position.y = level.data.surface_y(1)
		level.lower_part_id = "fish_tail"
		await frames(180)
		check(SceneProbe.tags_at(player.position).has("ocean"), "streamed water surface tags")
		level.test_direction = Vector3.RIGHT
		var first: Vector3 = player.position
		await frames(420, true)
		level.test_direction = Vector3.ZERO
		check(player.position.x > first.x + 25 and absf(player.position.y - first.y) < 0.2,
			"swims continuously through multiple streamed water chunks")
		print("STREAM WATER FRAME ", times[times.size()/2], " peak=", builder.chunk_stream.peak_build_usec/1000.0)
		level.queue_free()
		await process_frame
		await process_frame
		print("STREAM RUNTIME FAILURES ", failures)
		quit(0 if failures.is_empty() else 1)
		return
	check(builder.is_streaming() and builder.chunk_stream.actor == player, "runtime automatically streams around player and camera")
	check(builder.chunk_stream.view_margin_cells == TerrainChunkStream.CELL_MARGIN,
		"runtime keeps prefetch border beyond camera frustum")
	check(is_equal_approx(level.camera.far, 96.0),
		"runtime camera and stream share finite view distance")
	check(builder.chunk_stream.pending.is_empty() and not is_instance_valid(builder.chunk_stream.job_root)
		and builder.chunk_stream.wanted.keys().all(
			func(chunk): return builder._chunk_nodes.has(chunk)),
		"initial runtime view finishes before level becomes playable")
	check(builder.chunk_stream.wanted.size() > 9
		and camera_ground_loaded(builder, level.camera, level.data),
		"initial runtime load covers viewport and surrounding buffer")
	print("STREAM STARTUP MS ", (Time.get_ticks_usec() - start) / 1000.0)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/aberration-stream-initial.png")
	await frames(180)
	check(player.is_on_floor(), "player stands safely while remaining chunks stream")
	print("STREAM LOADED CHUNKS ", builder._chunk_nodes.size())
	director.set_physics_process(false)
	start = Time.get_ticks_usec()
	director.advance_spawn_points(30)
	print("STREAM INITIAL SPAWN MS ", (Time.get_ticks_usec() - start) / 1000.0)
	for i in 600:
		director._step_navigation()
		await frames(1)
		if not director.actors.is_empty():
			break
	check(director.actors.size() > 0, "30-second spawn works on streamed floor")
	check(director.navigation.values().all(func(nav): return nav.graph.get_point_count() < 15000),
		"monster navigation is regional rather than full 200 map")
	var monster: MonsterActor = director.actors[0] if not director.actors.is_empty() else null
	if monster != null:
		var hp := monster.health.current
		var old := player.position
		player.position = map.world_center(Vector2i(180, 180)) + Vector3.UP * 0.82
		builder.ensure_stream_position(player.global_position)
		builder.chunk_stream.select(builder, true)
		director._update_stream_actors()
		check(bool(monster.get_meta("stream_sleeping", false)) and monster.collision_layer == 0,
			"distant monster suspends physical simulation")
		player.position = old
		builder.chunk_stream.select(builder, true)
		director._update_stream_actors()
		check(not bool(monster.get_meta("stream_sleeping", false)) and monster.health.current == hp,
			"returning restores existing monster with same health")
		var home := monster.global_position
		var radius := monster.spawn_radius
		monster.global_position = map.world_center(Vector2i(150, 150))
		monster.spawn_radius = 500.0
		monster.path.clear()
		director._update_stream_actors()
		builder.chunk_stream.select(builder, true)
		await frames(90)
		check(builder.stream_cell_loaded(Vector2i(150, 150)) and monster.global_position.y > 1.8 \
			and not bool(monster.get_meta("stream_sleeping", false)),
			"custom large activation radius pins offscreen monster floor")
		monster.global_position = home
		monster.spawn_radius = radius
		director._update_stream_actors()
	director.set_physics_process(true)
	# Actual character physics crosses multiple chunk boundaries at 5m/s.
	level.test_direction = Vector3.RIGHT
	var walked := player.position
	await frames(420, true)
	level.test_direction = Vector3.ZERO
	check(player.position.x > walked.x + 25 and player.position.y > 2.5
		and player.is_on_floor(), "continuous walking across streamed chunk borders never falls")
	check(builder._chunk_nodes.size() < 300, "travel does not retain the complete map")
	var lit_tops := 0
	var tops := 0
	for nodes: Array in builder._chunk_nodes.values():
		for node in nodes:
			if is_instance_valid(node) and node is MeshInstance3D and node.has_meta("terrain_cells") \
					and not node.has_meta("terrain_bottom") and not node.has_meta("terrain_overlay"):
				tops += 1
				if node.material_override is ShaderMaterial \
						and "unshaded" not in node.material_override.shader.code:
					lit_tops += 1
	check(tops > 0 and tops == lit_tops, "newly streamed terrain continues receiving runtime light")
	if monster != null:
		check(monster.visual.sprites.all(func(sprite):
			return sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD \
				and sprite.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),
			"spawned monsters retain transparent silhouette shadows after sleep")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/aberration-stream-walk.png")
	stamp = 0
	# Change focus a long distance then return through the real reset action.
	player.position = map.world_center(Vector2i(180, 180)) + Vector3.UP * 0.82
	builder.ensure_stream_position(player.global_position)
	await frames(90)
	level.reset_player()
	await frames(2)
	check(player.position.distance_to(level.spawn_position) < 0.1 and player.is_on_floor(),
		"reset returns onto guaranteed loaded spawn collision")
	var controller: LevelTransitionController = level.transition_controller
	controller.advance(7200)
	controller.advance(1)
	check(controller.portal != null, "portal placement works with loaded local terrain")
	times.sort()
	print("STREAM FRAME MS median=", times[times.size() / 2],
		" p95=", times[int(times.size() * 0.95)], " maximum=", times.back(),
		" chunk_peak=", builder.chunk_stream.peak_build_usec / 1000.0,
		" total_stream_peak=", builder.chunk_stream.peak_total_usec / 1000.0)
	var output := FileAccess.open("/tmp/aberration-stream-frame-results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"median_ms": times[times.size() / 2],
		"p95_ms": times[int(times.size() * 0.95)], "maximum_ms": times.back(),
		"chunk_frame_peak_ms": builder.chunk_stream.peak_build_usec / 1000.0,
		"renderer": DisplayServer.get_name(), "failures": failures}, "\t"))
	level.queue_free()
	await process_frame
	await process_frame
	print("STREAM RUNTIME FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)
