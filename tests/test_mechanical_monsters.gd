extends SceneTree

const SPECIES := ["wolf", "gerbil", "gibbon", "gorilla", "ostrich", "eagle", "albatross"]
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("MECHANICAL FAIL ", label)

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/derived_art/mechanical_monsters_20261020/manifest.json"))
	for id in SPECIES:
		var definition := load("res://data/monsters/%s.tres" % id) as MonsterDefinition
		check(definition.errors().is_empty(), id + " valid production definition")
		var art: Dictionary = manifest.assets[id]
		check(FileAccess.get_sha256(art.source) == art.source_sha256, id + " preserved source")
		check(FileAccess.get_sha256(art.static) == art.static_sha256, id + " static derivative")
		check(definition.parts.is_empty(), id + " no old body parts")
		var visual := MonsterVisual.new()
		root.add_child(visual)
		visual.setup(definition)
		var sprite := visual.sprites[0]
		var lighting := RuntimeLighting.new()
		lighting.apply(visual)
		visual.animate(0.01, false, 0, false)
		check(not sprite.flip_h, id + " initial source orientation")
		visual.facing_left = not definition.image_faces_left
		visual.animate(0.01, false, 0, false)
		check(sprite.flip_h, id + " mirrored movement orientation")
		if id == "wolf":
			var original := sprite.texture
			visual.play_attack(definition.windup)
			visual.animate(1, true, 0.5, false)
			check(definition.sprite_frames == null and sprite.texture == original \
				and sprite.rotation == Vector3.ZERO, "wolf remains completely static")
			check(not visual.play_death(), "wolf has no fabricated death animation")
		else:
			var frames := definition.sprite_frames
			check(frames != null, id + " animation resource")
			for state in [&"walk", &"attack", &"death"]:
				check(FileAccess.get_sha256(art.animations[state].path) \
					== art.animations[state].sha256, id + "/" + state + " unchanged strip")
				check(frames.get_frame_count(state) == 8, id + "/" + state + " eight frames")
				check(frames.get_animation_loop(state) == (state == &"walk"), id + "/" + state + " loop")
				for i in 8:
					var texture := frames.get_frame_texture(state, i) as AtlasTexture
					check(texture.region == Rect2(i * 384, 0, 384, 384) \
						and texture.atlas.get_size() == Vector2(3072, 384), id + " frame region")
			check(frames.get_frame_texture(&"death", 7).get_image().is_invisible(),
				id + " transparent final death frame")
			visual.animate(0.12, true, 0, false)
			check(visual.animation == &"walk" and visual.frame > 0, id + " moving animates")
			check(is_equal_approx(sprite.position.y, 0) and is_equal_approx(
				sprite.offset.y + 192, definition.animation_anchor_y), id + " feet pivot")
			visual.play_attack(definition.windup)
			visual.animate(0, false, 0, false)
			visual.animate(definition.windup - 0.01, true, 0.5, true)
			check(visual.animation == &"attack" and visual.frame == 3 \
				and sprite.modulate != Color.WHITE, id + " hit flash preserves anticipation")
			visual.animate(0.011, false, 1, false)
			check(visual.frame == 4, id + " impact matches gameplay windup")
			visual.animate(0.4, false, 0, false)
			check(visual.animation == &"idle", id + " attack finishes once")
			visual.play_attack(definition.windup)
			visual.cancel_attack()
			check(visual.animation == &"idle", id + " leaving range cancels attack")
			var finished := [0]
			visual.death_finished.connect(func(): finished[0] += 1)
			check(visual.play_death(), id + " death starts")
			visual.set_process(false)
			visual._process(0.45)
			check(visual.animation == &"death" and visual.frame == 4, id + " smoke visible before cleanup")
			visual.animate(1, true, 1, true)
			check(visual.animation == &"death" and visual.frame == 4, id + " death cannot be interrupted")
			visual._process(0.45)
			check(finished[0] == 1 and visual.frame == 7, id + " complete death signal")
		check(sprite.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED \
			and sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD, id + " keeps silhouette shadows")
		visual.free()
	await combat_checks()
	print("MECHANICAL CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)

func combat_checks() -> void:
	var data := LevelData.new()
	data.setup_blank(Vector2i(16, 16))
	for i in data.columns.size():
		data.columns[i] = {"layers": [{"tile_id": "grass"}]}
	data.spawn_cell = Vector2i(8, 8)
	data.encounter = EncounterConfig.default_config()
	data.encounter.enabled = true
	var point := MonsterSpawnPoints.create("Mechanical test")
	point.cells = [Vector3i(9, 0, 8), Vector3i(10, 0, 8)]
	data.monster_spawn_points.append(point)
	var world := Node3D.new()
	root.add_child(world)
	var builder := TerrainBuilder.new()
	builder.show_grid = false
	builder.level_data = data
	builder.runtime_lighting = RuntimeLighting.new()
	world.add_child(builder)
	var player := Node3D.new()
	player.position = data.world_center(data.spawn_cell, 0) + Vector3.UP * 0.8
	world.add_child(player)
	var hp := CombatHealth.new()
	hp.name = "CombatHealth"
	player.add_child(hp)
	hp.setup(10000)
	var director := EncounterDirector.new()
	world.add_child(director)
	director.setup(data, player)
	director.set_physics_process(false)
	await physics_frame
	for id in SPECIES:
		var monster := load("res://data/monsters/%s.tres" % id) as MonsterDefinition
		var nav := director.nav_for(monster)
		# Explicit spawn tests all art on one fixture; normal point ecosystem
		# filtering is covered by test_monster_spawn_points.gd.
		var actor := MonsterActor.new()
		actor.position = player.position + Vector3(1, -0.8, 0)
		director.add_child(actor)
		actor.setup(monster, player, nav, -1, director.config)
		actor.set_meta("spawn_point_id", point.id)
		actor.set_spawn_range(player.position, 10)
		actor.defeated.connect(director._defeated)
		director.actors.append(actor)
		var hits := [0]
		actor.defeated.connect(func(_actor, _cause): hits[0] += 1)
		var before := hp.current
		for i in 22:
			await physics_frame
		if id != "wolf":
			check(actor.visual.animation == &"attack" and actor.visual.frame in [3, 4, 5],
				id + " actor drives attack")
		for i in 8:
			await physics_frame
		check(hp.current < before, id + " real attack damages target")
		actor.set_physics_process(false)
		var stopped_frame := actor.visual.frame
		for i in 10:
			await physics_frame
		check(actor.visual.frame == stopped_frame, id + " paused actor does not advance live animation")
		var drop_count := get_nodes_in_group("monster_drop").size()
		actor.take_damage(10000, "player")
		actor.take_damage(10000, "player")
		check(hits[0] == 1 and director.point_alive(str(point.id)) == 0,
			id + " death releases spawn slot exactly once")
		check(actor.collision_layer == 0 and actor.collision_mask == 0 \
			and not actor.is_in_group("enemies") and actor.adapter.spent and not actor.hp_label.visible,
			id + " corpse cannot collide attack or be targeted")
		check(get_nodes_in_group("monster_drop").size() == drop_count + monster.drop_items().size(),
			id + " exactly one set of drops")
		if id != "wolf":
			check(not actor.is_queued_for_deletion() and actor.visual.animation == &"death",
				id + " retains node for death")
		for i in 60:
			await physics_frame
		check(not is_instance_valid(actor), id + " actor freed after death completes")
	# Environmental kills do not produce loot.
	var definition := load("res://data/monsters/gorilla.tres") as MonsterDefinition
	var elite := MonsterActor.new()
	director.add_child(elite)
	elite.setup(definition, player, director.nav_for(definition), 0, director.config)
	elite.defeated.connect(director._defeated)
	director.actors.append(elite)
	var drops_before := get_nodes_in_group("monster_drop").size()
	elite.take_damage(10000, "fog")
	check(director.timeline.elites[0] == 4 and get_nodes_in_group("monster_drop").size() == drops_before,
		"animated elite environmental death retains original reward rules")
	# Map unload during animation must remove the entire effect safely.
	world.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(elite), "scene unload cleans pending death animation")
