extends SceneTree

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("ENCOUNTER CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func fixture(size := Vector2i(32, 32)) -> LevelData:
	var data := LevelData.new()
	data.setup_blank(size)
	for i in data.columns.size():
		data.columns[i] = {"layers": [{"tile_id": "grass"}]}
	data.spawn_cell = size / 2
	data.spawn_layer = 0
	return data

func run() -> void:
	var config := EncounterConfig.default_config()
	check(config.errors().is_empty() and config.monster_pool.size() == 14,
		"14 design entries and only supplied art enabled")
	var available := 0
	for rule in config.monster_pool:
		if rule.enabled:
			available += 1
	check(available == 12, "12 supplied species have valid textures including eagle and albatross")
	var tuned := config.definition_for("res://data/monsters/wolf.tres",
		{"max_health":123.0,"ecosystems":PackedStringArray(["rock"])})
	check(tuned.max_health == 123 and tuned.ecosystems == PackedStringArray(["rock"]) \
		and load("res://data/monsters/wolf.tres").max_health == 40,
		"per-map monster tuning preserves catalog source")
	var clock := EncounterTimeline.new()
	clock.setup(config)
	check(clock.advance(20, true, false).is_empty() and clock.elapsed == 0,
		"no clock before player control")
	check(clock.advance(9, true, true).is_empty(), "no early ordinary wave")
	check(clock.advance(30, false, true).is_empty() and clock.elapsed == 9,
		"static zone pauses rather than resets")
	check(clock.advance(1, true, true) == ["regular"], "resumes at saved second")
	check(clock.advance(290, true, true).count("regular") == 29 and clock.elites[0] == 1,
		"300s ordinary waves and elite1 independent")
	clock.elite_spawned(0)
	var events := clock.advance(300, true, true)
	check(events.count("regular") == 30 and events.has("elite_1"), "600s regular and elite2 together")
	clock.elite_spawned(1)
	check(not clock.advance(300, true, true).has("boss"), "900s no gate with living elites")
	clock.elite_died(0, "player")
	clock.elite_died(1, "player")
	check(clock.advance(0, false, true).has("boss"), "late kills trigger even after entering static zone")
	clock.boss_spawned = true
	check(clock.advance(1000, true, true).is_empty(), "boss phase stops additional spawns")
	clock.setup(config)
	clock.advance(900, true, true)
	clock.elite_died(0, "fog")
	clock.elite_died(1, "player")
	check(not clock.advance(0, true, true).has("boss"), "environment death is not a player elite kill")
	check(clock.advance(300, true, true).has("boss"), "1200s force gate regardless of kills")
	clock.setup(config)
	clock.advance(1200,true,true)
	check(clock.advance(0,true,true).has("elite_0"),
		"pending gate does not suppress required elite retries")
	var data := fixture()
	var center := data.world_center(data.spawn_cell, 0)
	data.generation = {"zone_origin": data.map_origin, "zone_size": data.map_size,
		"zones": PackedByteArray()}
	EncounterRegions.paint(data, Vector2i(5, 5), 0, 1)
	EncounterRegions.paint(data, Vector2i(5, 5), 0, 2)
	check(EncounterRegions.zone(data, Vector2i(5, 5), 0) == 1 \
		and EncounterRegions.forbidden(data, Vector2i(5, 5), 0), "zone and forbidden independent")
	check(EncounterRegions.zone(data, Vector2i(5, 5), 2) == 0, "layers do not share overrides")
	data.encounter = config
	check(data.clone_data() == data.clone_data(), "map snapshots compare configuration values")
	var fork := data.fork_for_edit()
	fork.encounter.interval = 20
	EncounterRegions.paint(fork, Vector2i(5, 5), 0, 0)
	check(data.encounter.interval == 10 and EncounterRegions.zone(data, Vector2i(5, 5), 0) == 1,
		"editing fork isolates settings and region records")
	var saved := "user://encounter_test_roundtrip.tres"
	check(ResourceSaver.save(data, saved) == OK, "map saves encounter settings")
	var loaded := ResourceLoader.load(saved, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	check(loaded.encounter != null and loaded.encounter.interval == 10 \
		and loaded.encounter_regions == data.encounter_regions, "settings and layer tags survive reload")
	var monster := load("res://data/monsters/demon_dog.tres") as MonsterDefinition
	var nav := EncounterNavigation.new()
	nav.build(data, monster)
	var candidates := nav.candidates(center, 9, 12, monster)
	check(not candidates.is_empty(), "ring has legal spawn points")
	var valid := true
	for id in candidates:
		var at := nav.graph.get_point_position(id)
		var distance := Vector2(at.x-center.x, at.z-center.z).length()
		valid = valid and distance >= 9 and distance <= 12
	check(valid, "final snapped positions stay within 9–12m")
	var blocked_id := candidates[0]
	var blocked_key: Vector3i = nav.surfaces[blocked_id]
	EncounterRegions.paint(data, Vector2i(blocked_key.x, blocked_key.z), blocked_key.y, 2)
	check(not nav.candidates(center, 9, 12, monster).has(blocked_id), "forbidden region excludes candidate")
	var static_id := candidates[1]
	var static_key: Vector3i = nav.surfaces[static_id]
	EncounterRegions.paint(data, Vector2i(static_key.x, static_key.z), static_key.y, 1)
	check(not nav.candidates(center, 9, 12, monster).has(static_id), "static region cannot spawn")
	check(not nav.path(center, nav.graph.get_point_position(static_id)).is_empty(),
		"navigation can enter static region")
	var obstacle := data.world_center(Vector2i(18, 16), 0)
	data.objects.append({"id": "rock", "definition": "res://assets/generated/painted_rock/definition.tres",
		"position": obstacle, "yaw": 0.0, "scale": 1.0, "anchor_cell": Vector2i(18,16),
		"anchor_layer": 0, "anchor_kind": "top"})
	nav.build(data, monster)
	check(not nav.ids.has(Vector3i(18,0,16)), "real object collision blocks navigation node")
	var route := nav.path(center, data.world_center(Vector2i(20,16),0))
	check(route.size() > 3, "path routes around object")
	var island := fixture(Vector2i(16,16))
	for y in 16:
		island.columns[island.index(Vector2i(8,y))] = {"layers":[]}
	nav.build(island, monster)
	check(nav.path(island.world_center(Vector2i(6,8),0), island.world_center(Vector2i(10,8),0)).is_empty(),
		"cannot cross disconnected air strip")
	var stair_map := fixture(Vector2i(8,8))
	for y in 4:
		for x in 8:
			stair_map.columns[stair_map.index(Vector2i(x,y))] = {"layers":[{"tile_id":"grass"},{"tile_id":"grass"}]}
	stair_map.stairs.append({"cell":Vector2i(3,4),"layer":0,"direction":0})
	nav.build(stair_map, monster)
	check(not nav.path(stair_map.world_center(Vector2i(3,5),0),
		stair_map.world_center(Vector2i(3,2),1)).is_empty(), "real stairs connect two heights")
	stair_map.stairs.clear()
	nav.build(stair_map, monster)
	check(nav.path(stair_map.world_center(Vector2i(3,5),0),
		stair_map.world_center(Vector2i(3,2),1)).is_empty(), "cliff without stair cannot connect")
	var generation := fixture(Vector2i(8,8))
	generation.generation = {"zone_origin":Vector2i.ZERO,"zone_size":Vector2i(8,8),
		"zones":PackedByteArray([0,1,0,0,0,0,0,0])}
	generation.resize_bounds(Rect2i(Vector2i(-3,-3),Vector2i(14,14)))
	check(EncounterRegions.zone(generation,Vector2i(1,0),0)==1,
		"expansion preserves original generated zone origin")
	var water_map := fixture(Vector2i(16,16))
	for y in 16:
		for x in range(8,16):
			water_map.set_layer(Vector2i(x,y),1,{"tile_id":"water"})
	nav.build(water_map,monster)
	check(not nav.ids.has(Vector3i(9,1,8)) and not nav.ids.has(Vector3i(9,0,8)),
		"land monster cannot spawn on water or submerged floor")
	var amphibian := load("res://data/monsters/goose.tres") as MonsterDefinition
	nav.build(water_map,amphibian)
	check(nav.ids.has(Vector3i(9,1,8)) and not nav.path(water_map.world_center(
		Vector2i(6,8),0),water_map.world_center(Vector2i(9,8),1)).is_empty(),
		"amphibian can connect shoreline and water surface")
	var source := fixture(Vector2i(8,8))
	source.encounter = config
	EncounterRegions.paint(source,Vector2i(1,1),0,1)
	var prefab: LevelPrefab = LevelPrefab.capture(source,Rect2i(Vector2i.ZERO,Vector2i(3,3))).prefab
	var destination := fixture(Vector2i(16,16))
	var stamp := prefab.stamp(destination,Vector2i(2,2),1)
	destination.restore_data(stamp.snapshot)
	check(prefab.fragment.encounter == null and EncounterRegions.zone(
		destination,Vector2i(3,3),0)==1, "prefab rotates region without carrying map encounter config")
	await runtime_checks()
	await stair_runtime_check()
	print("ENCOUNTER CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)

func runtime_checks() -> void:
	var data := fixture()
	data.encounter = EncounterConfig.default_config()
	data.encounter.enabled = true
	data.encounter.monster_pool = [{"path":"res://data/monsters/demon_dog.tres","weight":1.0,"enabled":true}]
	var point := MonsterSpawnPoints.create("运行测试")
	point.cells = [Vector3i(21, 0, 16), Vector3i(22, 0, 16)]
	data.monster_spawn_points.append(point)
	var world := Node3D.new()
	root.add_child(world)
	var builder := TerrainBuilder.new()
	builder.show_grid = false
	builder.level_data = data
	world.add_child(builder)
	var player := CharacterBody3D.new()
	player.position = data.world_center(data.spawn_cell,0) + Vector3.UP * 0.8
	world.add_child(player)
	var hp := CombatHealth.new()
	hp.name = "CombatHealth"
	player.add_child(hp)
	hp.setup(100)
	CombatHealth.hurt(player, 1, "environment")
	check(hp.current == 99, "environment mechanism shares player health")
	hp.setup(100)
	var director := EncounterDirector.new()
	world.add_child(director)
	director.setup(data,player)
	director.control_ready = true
	director.set_physics_process(false)
	await physics_frame
	director._physics_process(29)
	check(director.actors.is_empty(), "fixed ordinary points do not spawn before 30 seconds")
	director._physics_process(1)
	check(director.actors.size() in [1,2], "production director creates 1–2 actual actors")
	if not director.actors.is_empty():
		var actor := director.actors[0]
		check(actor.visual.sprites.size()>0 and actor.visual.sprites[0].texture != null,
			"spawned actor displays real imported artwork")
		var old := actor.global_position
		for i in 90:
			await physics_frame
		check(actor.global_position.distance_to(old)>1, "spawned monster actually tracks player")
		check(absf(actor.global_position.y - data.surface_y(0)) < 0.2,
			"actor movement stays on production terrain collision")
		var surface := director.player_surface()
		EncounterRegions.paint(data,Vector2i(surface.x,surface.z),surface.y,1)
		var elapsed := director.timeline.elapsed
		director._physics_process(15)
		check(director.timeline.elapsed==elapsed, "production clock pauses in static region")
		old = actor.global_position
		for i in 30:
			await physics_frame
		check(actor.global_position.distance_to(old)>0.1, "AI keeps moving while clock is paused")
		actor.global_position = player.global_position - Vector3.UP*0.8 + Vector3.RIGHT
		actor.repath()
		for i in 60:
			await physics_frame
		check(hp.current < 100, "enemy attack actually damages player")
		actor.take_damage(10000,"player")
		check(actor.health.dead, "player damage kills actor")
		check(director.interact().begins_with("拾取") \
			and player.get_meta("scene_inventory", []).size() == 1,
			"player kill drops collectible matching limb")
		director.timeline.elapsed=1200
		director._spawn_gate()
		check(director.gate != null and director.timeline.boss_spawned, "forced phase creates actual Boss gate")
		var original_gate := director.gate
		director._spawn_gate()
		check(original_gate==director.gate, "only one gate")
		player.global_position = director.gate.global_position + Vector3.UP * 0.8
		check(director.interact() == "未配置 Boss 目标场景" and director.timeline.running,
			"unconfigured gate reports destination and preserves control")
		if director.fog != null:
			var radius := director.fog.radius
			director.fog.step(1)
			check(is_equal_approx(director.fog.radius,maxf(30,radius-3)), "fog shrinks exactly 3m/s")
			player.global_position=director.fog.center+Vector3(50,0,0)
			radius=hp.current
			director.fog.radius=30
			director.fog.step(0.5)
			check(hp.current<radius, "fog inflicts continuous player damage")
			check(director.fog.covered(director.fog.center+Vector3(31,100,0)),
				"height cannot bypass fog boundary")
	world.queue_free()
	await process_frame

func stair_runtime_check() -> void:
	var map := fixture(Vector2i(8,8))
	for y in 4:
		for x in 8:
			map.set_layer(Vector2i(x,y),1,{"tile_id":"grass"})
	map.stairs.append({"cell":Vector2i(3,4),"layer":0,"direction":0})
	var world := Node3D.new()
	root.add_child(world)
	var builder := TerrainBuilder.new()
	builder.show_grid = false
	builder.level_data = map
	world.add_child(builder)
	var player := Node3D.new()
	player.position = map.world_center(Vector2i(3,2),1)+Vector3.UP*0.8
	world.add_child(player)
	var config := EncounterConfig.default_config()
	var monster := load("res://data/monsters/wolf.tres") as MonsterDefinition
	var nav := EncounterNavigation.new()
	nav.build(map,monster)
	var actor := MonsterActor.new()
	actor.position = map.world_center(Vector2i(3,6),0)
	world.add_child(actor)
	actor.setup(monster,player,nav,-1,config)
	actor.repath()
	for i in 180:
		await physics_frame
	check(actor.global_position.y > 3.8 and actor.global_position.z < map.world_center(
		Vector2i(3,3),1).z+0.8, "actual actor climbs production stair collision to upper target")
	world.queue_free()
	await process_frame
