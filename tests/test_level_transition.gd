extends SceneTree

var failures: Array[String] = []
var checks := 0
const SOURCE_PATH := "/tmp/aberration-portal-source.tres"

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("PORTAL CHECK ", label, " ", value)
	if not value:
		failures.append(label)

func flat_map(size := Vector2i(16, 16)) -> LevelData:
	var map := LevelData.new()
	map.setup_blank(size)
	for i in map.columns.size():
		map.columns[i] = {"layers": [{"tile_id": "grass"}]}
	map.spawn_cell = size / 2
	map.spawn_layer = 0
	return map

func spawn_level(map: LevelData) -> Node3D:
	var level := load("res://scenes/level_playtest.tscn").instantiate() as Node3D
	level.set("prepared_level", map)
	level.set("level_override", SOURCE_PATH)
	root.add_child(level)
	current_scene = level
	level.set("testing", true)
	level.get("transition_controller").set_physics_process(false)
	return level

func frames(count := 8) -> void:
	for i in count:
		await physics_frame
		await process_frame

func dispose(level: Node) -> void:
	level.queue_free()
	await process_frame
	await physics_frame

func wall(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	parent.add_child(body)
	body.global_position = position
	return body

func run() -> void:
	test_data()
	await test_countdown_and_transfer()
	await test_waiting_and_obstacles()
	await test_jump_and_stairs()
	await test_death_and_disabled()
	print("PORTAL CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)

func test_data() -> void:
	var map := flat_map()
	check(map.level_transition == null, "legacy maps retain optional configuration")
	var config := LevelTransitionConfig.new()
	check(config.errors().is_empty(), "default target exists and is LevelData")
	map.level_transition = config
	config.countdown_seconds = 3.0
	config.radius_min = 2.0
	var fork := map.fork_for_edit()
	fork.level_transition.countdown_seconds = 7
	check(config.countdown_seconds == 3, "fork does not share mutable flow settings")
	var snapshot := map.clone_data()
	map.level_transition.countdown_seconds = 9
	map.restore_data(snapshot)
	check(map.level_transition.countdown_seconds == 3, "snapshot restores flow")
	check(ResourceSaver.save(map, SOURCE_PATH) == OK, "save flow with map")
	var reopened := load(SOURCE_PATH) as LevelData
	check(reopened.level_transition.countdown_seconds == 3 \
		and reopened.level_transition.radius_min == 2, "reload retains settings")
	var prefab: LevelPrefab = LevelPrefab.capture(map, Rect2i(3, 3, 3, 3)).prefab
	check(prefab.fragment.level_transition == null, "prefab carries no whole-level flow")
	config.countdown_seconds = NAN
	check(not config.errors(false).is_empty(), "invalid timer rejected")
	config.countdown_seconds = 1
	config.radius_max = 1
	check(not config.errors(false).is_empty(), "invalid radii rejected")
	var destination := load(LevelTransitionConfig.DEFAULT_TARGET) as LevelData
	check(destination.validate().is_empty() and not destination.level_transition.enabled,
		"destination has valid spawn and terminates the chain")

func test_countdown_and_transfer() -> void:
	var level := spawn_level(flat_map(Vector2i(24, 24)))
	await frames()
	var controller: LevelTransitionController = level.get("transition_controller")
	var player: CharacterBody3D = level.get("player")
	var hud := level.get_node("LevelTransitionLayer/LevelTransitionHUD") as LevelTransitionHUD
	check(controller.state == LevelTransitionController.State.COUNTDOWN \
		and controller.remaining == 60, "default begins at 60 when ready")
	check(hud.countdown_label.text.ends_with("01:00"), "actual HUD displays countdown")
	controller.advance(59)
	check(controller.portal == null and controller.remaining == 1, "no early portal")
	paused = true
	controller.advance(10)
	check(controller.remaining == 1, "paused game does not count")
	paused = false
	var old_spawn: Vector3 = level.get("spawn_position")
	player.position += Vector3(12, 0, 0)
	await frames()
	var data: LevelData = level.get("data")
	var cell := data.world_to_cell(player.global_position)
	EncounterRegions.paint(data, cell, 0, 1)
	controller.advance(1)
	check(controller.remaining == 0 and controller.state == LevelTransitionController.State.OPEN,
		"stationary zone still counts and creates portal")
	if controller.portal == null:
		await dispose(level)
		return
	var portal := controller.portal
	var flat := Vector2(portal.position.x - player.position.x, portal.position.z - player.position.z).length()
	check(flat >= 4 and flat <= 8 and portal.global_position.distance_to(old_spawn) > 8,
		"portal appears near current player, not initial spawn")
	check(is_equal_approx(portal.global_position.y, 2.0), "portal rests on terrain")
	controller.advance(120)
	check(controller.portal == portal and controller.get_child_count() == 1, "only one portal")
	check(not controller.attempt_interact(), "out of range cannot enter")
	player.position = portal.global_position + Vector3(0, 0.82, 1.5)
	await frames()
	check(controller.interaction_text() == "E 进入下一关", "nearby portal offers interaction")
	var blocker := wall(level, portal.global_position + Vector3(0, 1.2, 0.75), Vector3(4, 2.3, 0.12))
	await frames(2)
	check(not controller.attempt_interact(), "cannot interact through physical wall")
	blocker.queue_free()
	await frames(2)
	controller.config.target_level = "/tmp/portal-missing-map.tres"
	check(level.call("attempt_interact"), "interaction routes through runtime")
	check(controller.state == LevelTransitionController.State.TRANSITIONING \
		and not controller.attempt_interact(), "repeated input blocked while switching")
	await frames(2)
	check(is_instance_valid(level) and controller.state == LevelTransitionController.State.OPEN \
		and portal.active, "missing target keeps current level and restores portal")
	var invalid := flat_map()
	invalid.spawn_cell = Vector2i(-1, -1)
	ResourceSaver.save(invalid, "/tmp/portal-invalid-target.tres")
	controller.config.target_level = "/tmp/portal-invalid-target.tres"
	level.call("attempt_interact")
	await frames(2)
	check(controller.state == LevelTransitionController.State.OPEN \
		and is_instance_valid(player), "invalid destination spawn leaves source playable")
	ResourceSaver.save(LevelTransitionConfig.new(), "/tmp/portal-wrong-type.tres")
	controller.config.target_level = "/tmp/portal-wrong-type.tres"
	level.call("attempt_interact")
	await frames(2)
	check(controller.state == LevelTransitionController.State.OPEN, "wrong resource type handled")
	var inventory := ["fruit", "stone"]
	player.set_meta("scene_inventory", inventory)
	player.set_meta("scene_health", 63.0)
	player.set_meta("scene_oxygen", 71.0)
	level.set("lower_part_id", "wolf_leg")
	level.set("climb_enabled", true)
	controller.config.target_level = LevelTransitionConfig.DEFAULT_TARGET
	var old_ref: WeakRef = weakref(level)
	var old_player_ref: WeakRef = weakref(player)
	# Send real input through Godot's input dispatch, then release it.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	key = InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = false
	Input.parse_input_event(key)
	await frames(5)
	var next := current_scene
	check(old_ref.get_ref() == null and old_player_ref.get_ref() == null, "old scene and player freed")
	check(next != null and next.get("loaded_level_path") == LevelTransitionConfig.DEFAULT_TARGET,
		"real E input loads destination LevelData")
	if next != null and next != level:
		var next_player: CharacterBody3D = next.get("player")
		var next_spawn: Vector3 = next.get("spawn_position")
		check(next_player.position.distance_to(next_spawn) < 0.2, "arrives at target spawn")
		check(next.get("lower_part_id") == "wolf_leg" and next.get("climb_enabled"),
			"limb selection and climb ability preserved")
		check(next_player.get_meta("scene_inventory") == inventory \
			and next_player.get_meta("scene_oxygen") == 71.0 \
			and next.get("combat_health").current == 63.0, "inventory oxygen and health preserved")
		check(next.get("transition_controller").state == LevelTransitionController.State.DISABLED,
			"destination obeys its own disabled flow")
		await dispose(next)
	elif is_instance_valid(level):
		await dispose(level)

func test_waiting_and_obstacles() -> void:
	var level := spawn_level(flat_map(Vector2i(3, 3)))
	await frames()
	var controller: LevelTransitionController = level.get("transition_controller")
	controller.advance(60)
	check(controller.state == LevelTransitionController.State.WAITING \
		and controller.portal == null, "small map waits instead of spawning outside")
	controller.config.radius_min = 2
	controller.config.radius_max = 3
	controller.advance(1)
	check(controller.state == LevelTransitionController.State.OPEN, "waiting retries when valid space available")
	await dispose(level)
	var map := flat_map()
	map.set_layer(map.spawn_cell, 1, {"tile_id": "water"})
	level = spawn_level(map)
	await frames()
	controller = level.get("transition_controller")
	controller.advance(60)
	check(controller.state == LevelTransitionController.State.WAITING, "underwater floor is not a portal start")
	await dispose(level)
	level = spawn_level(flat_map())
	await frames()
	controller = level.get("transition_controller")
	var player: CharacterBody3D = level.get("player")
	var ceiling := wall(level, Vector3(0, 4.6, 0), Vector3(40, 0.2, 40))
	await frames(2)
	controller.advance(60)
	check(controller.state == LevelTransitionController.State.WAITING, "low ceiling rejects portal volume")
	ceiling.queue_free()
	await frames(2)
	# A physical barrier enclosing the player must block all paths even if absent in LevelData.
	var barriers: Array[StaticBody3D] = []
	for side in [-1, 1]:
		barriers.append(wall(level, player.position + Vector3(side * 1.2, 0.5, 0), Vector3(0.2, 3, 3)))
		barriers.append(wall(level, player.position + Vector3(0, 0.5, side * 1.2), Vector3(3, 3, 0.2)))
	await frames(2)
	controller.advance(1)
	check(controller.state == LevelTransitionController.State.WAITING, "physical barriers reject unreachable ground")
	for barrier in barriers:
		barrier.queue_free()
	await frames(2)
	controller.advance(1)
	check(controller.state == LevelTransitionController.State.OPEN, "removed obstacles permit retry")
	await dispose(level)
	map = flat_map()
	for i in map.columns.size():
		map.columns[i] = {"layers": [{}, {}, {"tile_id": "rock"}]}
	map.spawn_layer = 2
	level = spawn_level(map)
	await frames()
	controller = level.get("transition_controller")
	controller.advance(60)
	check(controller.portal != null and is_equal_approx(controller.portal.global_position.y, 6),
		"upper suspended floor uses actual support height")
	await dispose(level)

func test_jump_and_stairs() -> void:
	var level := spawn_level(flat_map())
	await frames()
	var player: CharacterBody3D = level.get("player")
	var controller: LevelTransitionController = level.get("transition_controller")
	player.position.y += 3
	await frames(2)
	controller.advance(60)
	check(controller.state == LevelTransitionController.State.WAITING, "airborne expiry waits for landing")
	await frames(70)
	controller.advance(1)
	check(controller.state == LevelTransitionController.State.OPEN, "landing allows portal retry")
	await dispose(level)
	var map := flat_map(Vector2i(8, 8))
	for i in map.columns.size():
		map.columns[i] = {"layers": []}
	for y in range(2, 6):
		map.columns[map.index(Vector2i(3, y))] = {"layers": [{"tile_id": "grass"}]}
		if y < 4:
			map.columns[map.index(Vector2i(3, y))] = {
				"layers": [{"tile_id": "grass"}, {"tile_id": "grass"}]}
	map.spawn_cell = Vector2i(3, 5)
	map.level_transition = LevelTransitionConfig.new()
	map.level_transition.radius_min = 5.5
	level = spawn_level(map)
	await frames()
	controller = level.get("transition_controller")
	controller.advance(60)
	check(controller.state == LevelTransitionController.State.WAITING, "unconnected upper cliff is unreachable")
	await dispose(level)
	map.stairs.append({"cell": Vector2i(3, 4), "layer": 0, "direction": 0})
	level = spawn_level(map)
	await frames()
	controller = level.get("transition_controller")
	controller.advance(60)
	check(controller.portal != null and is_equal_approx(controller.portal.global_position.y, 4),
		"physical staircase leads to reachable portal above")
	var player_on_stair: CharacterBody3D = level.get("player")
	player_on_stair.position = map.world_center(Vector2i(3, 3), 1) + Vector3.UP * 0.4
	await frames()
	var config := LevelTransitionConfig.new()
	config.radius_min = 2
	config.radius_max = 8
	check(LevelPortalPlacement.find_position(map, player_on_stair, config) != Vector3.INF,
		"player standing on upper ramp can find nearby ground")
	await dispose(level)

func test_death_and_disabled() -> void:
	var map := flat_map()
	map.level_transition = LevelTransitionConfig.new()
	map.level_transition.enabled = false
	var level := spawn_level(map)
	await frames()
	var controller: LevelTransitionController = level.get("transition_controller")
	controller.advance(1000)
	check(controller.state == LevelTransitionController.State.DISABLED and controller.portal == null,
		"explicit endpoint stays disabled")
	await dispose(level)
	map = flat_map()
	map.encounter = EncounterConfig.default_config()
	map.encounter.enabled = true
	level = spawn_level(map)
	await frames()
	controller = level.get("transition_controller")
	controller.advance(60)
	check(controller.state == LevelTransitionController.State.OPEN \
		and level.get("encounter_director") != null, "portal works with encounters enabled")
	var player: CharacterBody3D = level.get("player")
	var director: EncounterDirector = level.get("encounter_director")
	director._spawn_gate()
	var original_gate := director.gate
	check(is_instance_valid(original_gate) and is_instance_valid(controller.portal),
		"Boss gate and countdown portal can coexist")
	var drop := MonsterDrop.new()
	drop.item_id = "wolf_leg"
	drop.position = player.position
	director.add_child(drop)
	check(level.call("attempt_interact") and player.get_meta("scene_inventory", []).has("wolf_leg"),
		"out of portal range E still collects encounter drops")
	var hud := level.get_node("EncounterLayer/EncounterHUD") as EncounterHUD
	check(hud.get_global_transform_with_canvas().origin == Vector2.ZERO \
		and hud.text_label.position.y == 257, "shift HUD text without moving world direction cues")
	var health: CombatHealth = level.get("combat_health")
	health.damage(1000)
	check(controller.state == LevelTransitionController.State.STOPPED \
		and not controller.attempt_interact(), "death stops active portal")
	await dispose(level)
