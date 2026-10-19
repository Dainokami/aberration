extends SceneTree

const Picker := preload("res://addons/terrain_editor/surface_picker.gd")
const Batch := preload("res://scripts/level/terrain_collision_batch.gd")
var failures: Array[String] = []
var checks := 0
var reports: Array[Dictionary] = []

func _init() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("SWIM JOLT CHECK ",label," ",value)
	if not value:
		failures.append(label)

func fixture(size: Vector2i, water := false) -> LevelData:
	var map := LevelData.new()
	map.setup_blank(size)
	for i in map.columns.size():
		map.columns[i] = {"layers":[{"tile_id":"grass"}]}
		if water:
			map.columns[i].layers.append({"tile_id":"water"})
			map.columns[i].layers.append({"tile_id":"water"})
	map.spawn_cell = size/2
	map.spawn_layer = 0
	return map

func run() -> void:
	await swim()
	for size in [Vector2i(64,64),Vector2i(96,64)]:
		await bodies(size)
	var output := FileAccess.open("/tmp/swim-jolt-counts.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(reports,"\t"))
	print("SWIM JOLT CHECKS ",checks," FAILURES ",failures)
	quit(0 if failures.is_empty() else 1)

func swim() -> void:
	var map := fixture(Vector2i(16,16),true)
	var world := Node3D.new()
	root.add_child(world)
	var builder := TerrainBuilder.new()
	builder.show_grid = false
	builder.level_data = map
	world.add_child(builder)
	var player := load("res://scenes/player.tscn").instantiate() as PlayerController
	player.position = map.world_center(map.spawn_cell,1)+Vector3.UP*0.1
	world.add_child(player)
	await physics_frame
	await physics_frame
	player.parts.equip("gorilla_arm","fish_tail")
	player.velocity = Vector3.ZERO
	var start := player.global_position
	Input.action_press("move_right")
	for i in 60:
		await physics_frame
	Input.action_release("move_right")
	var moved := player.global_position.x-start.x
	check(moved>4.2 and moved<5.3 and is_equal_approx(player.velocity.x,5.0) \
		and absf(player.global_position.y-start.y)<0.1,
		"fish swims 5m/s and holds depth in real stacked water (%.3fm)"%moved)
	player.velocity = Vector3.ZERO
	start = player.global_position
	Input.action_press("air_action")
	for i in 12:
		await physics_frame
	Input.action_release("air_action")
	check(player.global_position.y>start.y+0.7,"fish rises inside water on Space")
	player.global_position=Vector3(start.x,start.y,start.z)
	player.velocity=Vector3.ZERO
	var down := InputEventKey.new()
	down.physical_keycode=KEY_CTRL
	down.pressed=true
	Input.parse_input_event(down)
	for i in 12:
		await physics_frame
	down.pressed=false
	Input.parse_input_event(down)
	check(player.global_position.y<start.y-0.7,"fish dives inside water on Ctrl")
	player.velocity = Vector3.ZERO
	player.parts.equip("gorilla_arm","goose_foot")
	check(player.parts.speed_on(SceneProbe.tags_at(player.global_position))==0,
		"goose feet do not swim underwater")
	player.global_position=map.world_center(map.spawn_cell,2)
	check(player.parts.speed_on(SceneProbe.tags_at(player.global_position))==5,
		"goose feet move 5m/s on the water surface")
	player.parts.equip("gorilla_arm","fish_tail")
	player.global_position = map.world_center(map.spawn_cell,0)+Vector3(0,0.05,0)
	# Remove the surrounding water without shifting the solid floor.
	for y in range(6,11):
		for x in range(6,11):
			map.remove_layer(Vector2i(x,y),2)
			map.remove_layer(Vector2i(x,y),1)
	builder.rebuild_cells([Vector2i(6,6),Vector2i(10,10),Vector2i(8,8)])
	await physics_frame
	start = player.global_position
	Input.action_press("move_right")
	for i in 30:
		await physics_frame
	Input.action_release("move_right")
	check(absf(player.global_position.x-start.x)<0.1,"fish stops after leaving water")
	var zone := SurfaceZone.new()
	zone.tags = PackedStringArray(["fluid"])
	zone.bind_volume(Vector3(2,2,2))
	zone.position=player.global_position
	world.add_child(zone)
	check(not zone.is_class("CollisionObject3D") and player.parts.speed_on(SceneProbe.tags_at(
		player.global_position))==5,"legacy fluid overrides grass without physics body")
	world.free()
	await physics_frame

func bodies(size: Vector2i) -> void:
	var map := fixture(size)
	var builder := TerrainBuilder.new()
	builder.level_data=map
	builder.show_grid=false
	var start := Time.get_ticks_usec()
	root.add_child(builder)
	var count := builder.find_children("*","PhysicsBody3D",true,false).size()
	var chunks := builder._chunk_nodes.size()
	var ms := (Time.get_ticks_usec()-start)/1000.0
	check(count==chunks and count<=size.x*size.y/64,
		"%s uses one terrain body per chunk: %d bodies"%[size,count])
	check(builder.find_children("*","Area3D",true,false).is_empty(),
		"%s pure surface tags create no Jolt areas"%size)
	var old := builder.generated
	builder.rebuild()
	check(not is_instance_valid(old) and builder.find_children("*","PhysicsBody3D",
		true,false).size()==count,"full rebuild releases previous physics bodies immediately")
	await physics_frame
	await physics_frame
	var space := builder.get_world_3d().direct_space_state
	var target := Vector2i(7,8)
	var point := map.world_center(target,0)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*5,
		point-Vector3.UP*5))
	check(not hit.is_empty() and Batch.hit_metadata(hit.collider,hit.shape).cell==target,
		"shared body ray still identifies exact cell across chunk edge")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position=point+Vector3(0,12,8)
	camera.look_at(point)
	var picked := Picker.pick(builder,camera,camera.unproject_position(point))
	check(picked.get("cell",Vector2i(-1,-1))==target and picked.get("layer",-1)==0,
		"editor surface picker maps shared-body shape to original support")
	var remote: Array = builder._chunk_nodes[Vector2i(4,4)].duplicate()
	map.set_layer(target,2,{"tile_id":"rock"})
	builder.rebuild_cells([target])
	var retained := true
	for node in remote:
		retained=retained and is_instance_valid(node)
	check(retained,"local update preserves distant chunk physics bodies")
	builder.set_slice_layer(0)
	await physics_frame
	builder.set_slice_layer(-1)
	reports.append({"size":str(size),"chunks":chunks,"physics_bodies":count,
		"before_estimated_terrain_bodies":size.x*size.y*2,"initial_build_ms":ms})
	camera.free()
	builder.free()
	await physics_frame
	await generated_world(size)

func generated_world(size: Vector2i) -> void:
	var config := WorldGenConfig.new()
	config.width=size.x
	config.height=size.y
	var generator := WorldGenerator.new()
	check(generator.prepare(config).is_empty(),"large mixed world prepares %s"%size)
	var result := generator.generate()
	var map: LevelData=result.data
	var world := Node3D.new()
	root.add_child(world)
	var builder := TerrainBuilder.new()
	builder.level_data=map
	builder.show_grid=false
	world.add_child(builder)
	var count := builder.find_children("*","CollisionObject3D",true,false).size()
	check(count<10240,"mixed generated %s builds below Jolt limit: %d collision objects"%[size,count])
	var player := Node3D.new()
	player.position=map.world_center(map.spawn_cell,map.spawn_layer)+Vector3.UP*0.8
	world.add_child(player)
	map.encounter=EncounterConfig.default_config()
	map.encounter.enabled=true
	var point := MonsterSpawnPoints.create("大地图碰撞回归刷新点")
	var first := map.spawn_cell + Vector2i(2,0)
	var second := first + Vector2i.RIGHT
	point.cells = [
		Vector3i(first.x,map.spawn_layer,first.y),
		Vector3i(second.x,map.spawn_layer,second.y),
	]
	map.monster_spawn_points.append(point)
	var director := EncounterDirector.new()
	world.add_child(director)
	director.setup(map,player)
	director.control_ready=true
	director.set_physics_process(false)
	await physics_frame
	await physics_frame
	director._physics_process(30)
	check(director.actors.size() in [1,2],"large mixed world can actually spawn enemies")
	director.stop()
	reports.append({"size":str(size),"scenario":"mixed_world",
		"physics_collision_objects":count,"objects":map.objects.size(),
		"terrain_chunks":builder._chunk_nodes.size()})
	world.free()
	await physics_frame
