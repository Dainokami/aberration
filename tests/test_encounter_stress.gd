extends SceneTree

var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	print("ENCOUNTER STRESS CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var map := LevelData.new()
	map.setup_blank(Vector2i(32,32))
	for i in map.columns.size():
		map.columns[i] = {"layers":[{"tile_id":"grass"}]}
	map.spawn_cell = Vector2i(16,16)
	map.spawn_layer = 0
	map.encounter = EncounterConfig.default_config()
	map.encounter.enabled = true
	map.encounter.count_min = 2
	map.encounter.count_max = 2
	map.encounter.monster_pool = [{"path":"res://data/monsters/demon_dog.tres","enabled":true,"weight":1}]
	map.encounter.elite_one_ecosystems = PackedStringArray(["grass"])
	var world := Node3D.new()
	root.add_child(world)
	var builder := TerrainBuilder.new()
	builder.level_data = map
	builder.show_grid = false
	world.add_child(builder)
	var player := Node3D.new()
	player.position = map.world_center(map.spawn_cell,0) + Vector3.UP*0.8
	world.add_child(player)
	var hp := CombatHealth.new()
	hp.name = "CombatHealth"
	player.add_child(hp)
	hp.setup(100000)
	var director := EncounterDirector.new()
	world.add_child(director)
	director.setup(map,player)
	director.control_ready = true
	director.set_physics_process(false)
	await physics_frame
	var started := Time.get_ticks_usec()
	var elite_pair_alive := false
	var path_duration := 0.0
	for wave in 120:
		director._physics_process(10)
		for i in director.actors.size():
			var actor := director.actors[i]
			actor.set_physics_process(false)
			actor.global_position = map.world_center(Vector2i(i%8,i/8),0)
		if wave == 60:
			elite_pair_alive = director.timeline.elites == [2,2]
		if wave == 118:
			var path_started := Time.get_ticks_usec()
			for actor in director.actors:
				actor.repath()
			path_duration = (Time.get_ticks_usec()-path_started)/1000.0
		await physics_frame
	var duration := (Time.get_ticks_usec()-started)/1000.0
	check(director.spawn_count == 242 and director.skipped == 0,
		"120 full waves produce 240 ordinary plus two elites without hidden cap")
	check(director.timeline.boss_spawned and director.gate != null,
		"20-minute forced gate runs after full retained crowd")
	check(elite_pair_alive, "elite spawns remain independent and unique before fog")
	print("ENCOUNTER STRESS full timeline ms ",duration,
		" 240 cached AStar requests ms ",path_duration)
	for actor in director.actors:
		actor.global_position = director.fog.center+Vector3(40,0,0)
	director.fog.radius = 30
	var outside := 0
	for actor in director.actors:
		if director.fog.covered(actor.global_position):
			outside += 1
	var before := director.actors.size()
	director.fog.step(5)
	check(director.actors.size() == before-outside and outside>0,
		"fog rapidly kills ordinary and elite crowd outside radius")
	var player_killed := false
	for status in director.timeline.elites:
		player_killed = player_killed or status == 3
	check(not player_killed,"fog deaths do not count as player elite kills")
	director.stop()
	world.queue_free()
	await process_frame
	print("ENCOUNTER STRESS FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)
