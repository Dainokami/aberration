extends SceneTree

var viewport: SubViewport
var level: Node3D
var actors: Array[MonsterActor] = []
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func capture(name: String) -> Image:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png("/tmp/mechanical-" + name + ".png")
	return image

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1440, 900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var data := LevelData.new()
	data.setup_blank(Vector2i(24, 24))
	for i in data.columns.size():
		data.columns[i] = {"layers": [{"tile_id": "grass"}]}
	data.spawn_cell = Vector2i(12, 12)
	data.spawn_layer = 0
	data.level_transition = LevelTransitionConfig.new()
	data.level_transition.enabled = false
	level = load("res://scenes/level_playtest.tscn").instantiate()
	level.prepared_level = data
	level.level_override = "/tmp/mechanical-render-fixture.tres"
	viewport.add_child(level)
	assert(level.ready_for_play)
	level.testing = true
	level.process_mode = Node.PROCESS_MODE_DISABLED
	level.player.hide()
	for child in level.get_children():
		if child is CanvasLayer or child is SurfaceZone or child is AffordanceProp \
				or child.get_script() == load("res://scripts/limbs/limb_pickup.gd"):
			child.hide()
	var camera: Camera3D = level.camera
	camera.far = 100
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11
	var center := data.world_center(data.spawn_cell, 0)
	# Keep the production camera angle; only widen/center the lineup.
	camera.global_position = center + Vector3.UP * 0.8 + camera.global_basis.z * 24
	var right := camera.global_basis.x
	var back := Vector3(camera.global_basis.z.x, 0, camera.global_basis.z.z).normalized()
	var ids := ["wolf", "gerbil", "gibbon", "gorilla", "ostrich", "eagle", "albatross"]
	for i in ids.size():
		var definition := load("res://data/monsters/%s.tres" % ids[i]) as MonsterDefinition
		var actor := MonsterActor.new()
		actor.position = center + right * ((i % 4) * 4.0 - 6) + back * ((i / 4) * 9.0 - 4.5)
		if definition.movement == "air":
			actor.position.y += 0.6
		level.add_child(actor)
		actor.setup(definition, level.player, null, -1, EncounterConfig.default_config())
		actor.hp_label.text = definition.display_name + (" · 静态" if ids[i] == "wolf" else "")
		level.builder.runtime_lighting.apply(actor.visual)
		actors.append(actor)
	await capture("static")
	for actor in actors:
		actor.visual.animate(0.24, true, 0, false)
	var walking := await capture("walk")
	for actor in actors:
		actor.visual.play_attack(actor.definition.windup)
		actor.visual.animate(0, false, 0, false)
		actor.visual.animate(actor.definition.windup + 0.01, false, 1, false)
	await capture("attack")
	for actor in actors:
		actor.visual.cancel_attack()
		actor.visual.animate(0.24, true, 0, false)
		for sprite in actor.visual.sprites:
			sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var no_shadow := await capture("no-shadow")
	var shadow_pixels := 0
	for y in walking.get_height():
		for x in walking.get_width():
			var a := walking.get_pixel(x, y)
			var b := no_shadow.get_pixel(x, y)
			if (b.r + b.g + b.b - a.r - a.g - a.b) / 3.0 > 0.025:
				shadow_pixels += 1
	if shadow_pixels < 100:
		failures.append("animated monster shadows are missing")
	for actor in actors:
		actor.hp_label.hide()
		if actor.definition.sprite_frames != null:
			actor.take_damage(10000, "environment")
			actor.visual._process(0.45)
	await capture("death")
	for actor in actors:
		if actor.definition.sprite_frames != null:
			actor.visual._process(0.45)
	await capture("after-death")
	print("MECHANICAL RENDER shadow_pixels=", shadow_pixels, " FAILURES ", failures)
	level.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
