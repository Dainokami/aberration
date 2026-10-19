extends SceneTree

var failures: Array[String] = []
var viewport: SubViewport
var level: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	print("LIGHTING CHECK ", value, " ", label)
	if not value:
		failures.append(label)

func fixture() -> LevelData:
	var data := LevelData.new()
	data.setup_blank(Vector2i(48, 48))
	for y in 48:
		for x in 48:
			var cell := Vector2i(x, y)
			var tile := "grass" if x < 28 else "sand"
			data.set_layer(cell, 0, {"tile_id": tile})
			if x >= 34:
				data.set_layer(cell, 1, {"tile_id": "water"})
			if x >= 18 and x <= 25 and y >= 18 and y <= 21:
				data.set_layer(cell, 1, {"tile_id": "rock"})
				data.set_layer(cell, 2, {"tile_id": "grass"})
	data.spawn_cell = Vector2i(24, 26)
	data.spawn_layer = 0
	data.encounter = EncounterConfig.default_config()
	data.encounter.enabled = true
	data.level_transition = LevelTransitionConfig.new()
	data.level_transition.enabled = false
	for spec in [
		["tree_olive", Vector2i(20, 24), 0],
		["tree_olive", Vector2i(27, 23), 0],
		["tree_dead", Vector2i(31, 23), 0],
		["painted_rock", Vector2i(22, 24), 0],
		["scene1016_chest_1538", Vector2i(26, 26), 0],
		["tree_olive", Vector2i(21, 20), 2],
		["painted_rock", Vector2i(24, 20), 2],
	]:
		data.objects.append(ObjectRules.anchor_record(data, {
			"id": "lighting_%d" % data.objects.size(),
			"definition": "res://assets/generated/%s/definition.tres" % spec[0],
			"position": data.world_center(spec[1], spec[2]), "scale": 1.0, "yaw": 0.0,
		}))
	return data

func capture(path: String) -> Image:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(image.save_png(path) == OK, "capture " + path.get_file())
	return image

func darkened_pixels(lit: Image, reference: Image, threshold := 0.025) -> Dictionary:
	var count := 0
	var first := Vector2i(lit.get_width(), lit.get_height())
	var last := Vector2i.ZERO
	for y in lit.get_height():
		for x in lit.get_width():
			var a := lit.get_pixel(x, y)
			var b := reference.get_pixel(x, y)
			var difference := (b.r + b.g + b.b - a.r - a.g - a.b) / 3.0
			if difference > threshold:
				count += 1
				first = first.min(Vector2i(x, y))
				last = last.max(Vector2i(x, y))
	return {"pixels": count, "bounds": Rect2i(first, (last - first + Vector2i.ONE).max(Vector2i.ZERO))}

func measure() -> Dictionary:
	var times: Array[float] = []
	for i in 90:
		var start := Time.get_ticks_usec()
		await process_frame
		times.append((Time.get_ticks_usec() - start) / 1000.0)
	times.sort()
	return {"median_ms": times[45], "p95_ms": times[85]}

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	level = load("res://scenes/level_playtest.tscn").instantiate()
	level.prepared_level = fixture()
	level.level_override = "/tmp/environment-lighting-fixture.tres"
	if "--baseline" in OS.get_cmdline_user_args():
		level.lighting_profile = null
	viewport.add_child(level)
	check(level.ready_for_play, "runtime scene finishes initialization")
	if not level.ready_for_play:
		quit(1)
		return
	level.testing = true
	for child in level.get_children():
		if child is CanvasLayer:
			child.hide()
		# Hide only the existing tutorial markers/pickups for a clear art comparison.
		if child is SurfaceZone or child.get_script() == load("res://scripts/limbs/limb_pickup.gd"):
			child.hide()
	var director: EncounterDirector = level.encounter_director
	director.set_physics_process(false)
	var definition := load("res://data/monsters/wolf.tres") as MonsterDefinition
	var monster := director._spawn(definition, director.nav_for(definition), -1, {
		"id": "lighting_wolf", "cells": [Vector3i(22, 0, 27)], "activation_radius": 32.0})
	check(monster != null, "real monster visual participates in lighting scene")
	if monster != null:
		monster.set_physics_process(false)
		monster.hp_label.hide()
	for i in 10:
		await physics_frame
	level.process_mode = Node.PROCESS_MODE_DISABLED
	var name := "before" if "--baseline" in OS.get_cmdline_user_args() else "after"
	var final_image := await capture("/tmp/environment-lighting-" + name + ".png")
	var timings := await measure()
	if name == "after":
		var sun := level.get_node("Sun") as DirectionalLight3D
		var environment: Environment = level.get_node("WorldLighting").environment
		environment.ssao_enabled = false
		var no_ao := await capture("/tmp/environment-lighting-no-ao.png")
		var ao_pixels := darkened_pixels(final_image, no_ao, 0.004)
		check(ao_pixels.pixels > 50, "contact occlusion changes visible creases and contacts")
		sun.shadow_enabled = false
		var no_shadow := await capture("/tmp/environment-lighting-no-shadow.png")
		var shadow_pixels := darkened_pixels(no_ao, no_shadow)
		check(shadow_pixels.pixels > 500, "directional shadows actually darken receiving terrain")
		sun.shadow_enabled = true
		var tree: Node3D = level.builder._object_nodes["lighting_2"]
		var art := tree.get_node("Art") as MeshInstance3D
		var caster := art.get_node("LightingShadow") as MeshInstance3D
		caster.hide()
		var no_tree := await capture("/tmp/environment-lighting-no-tree-shadow.png")
		var tree_pixels := darkened_pixels(no_ao, no_tree)
		var bounds: Rect2i = tree_pixels.bounds
		var coverage := float(tree_pixels.pixels) / maxf(1.0, bounds.get_area())
		check(tree_pixels.pixels > 20 and coverage < 0.8,
			"transparent tree casts a shaped silhouette rather than a filled rectangle")
		caster.show()
		environment.ssao_enabled = true
		var original := AssetFactory.instantiate_asset(load("res://assets/generated/tree_dead/definition.tres"))
		var original_art := original.get_node("Art") as MeshInstance3D
		check(original_art.material_override != art.material_override \
			and original_art.material_override.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
			"runtime lighting does not mutate saved/shared art material")
		original.free()
		check(caster.get_parent() == art and caster.mesh == art.mesh,
			"shadow follows the original mesh transform and streamed lifetime")
		tree.hide()
		check(not caster.is_visible_in_tree(), "hidden or destroyed prop cannot leave a visible shadow")
		tree.show()
		for material in tree.fade_materials:
			check(material == tree.visual_meshes[tree.fade_materials.find(material)].material_override,
				"occlusion fade retains the visible runtime material")
		print("LIGHTING PIXELS shadow=", shadow_pixels.pixels, " ao=", ao_pixels.pixels,
			" tree=", tree_pixels.pixels, " tree_coverage=", coverage)
	print("LIGHTING PERFORMANCE ", name, " ", JSON.stringify(timings))
	var report := FileAccess.open("/tmp/environment-lighting-" + name + ".json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"timings": timings, "failures": failures}, "\t"))
	level.queue_free()
	await process_frame
	await process_frame
	print("LIGHTING FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)
