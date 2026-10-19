extends SceneTree

var _level: Node3D
var _player: PlayerController
var _rig: ModularCharacterRig
var _data: LevelData
var _phase := "boot"
var _wait := 0
var _note := ""
var _peak := 0.0
var _right_peak := 0.0
var _props: Array[AffordanceProp] = []
var _rock: AffordanceProp
var _switch_step := 0


func _initialize() -> void:
	_level = (load("res://scenes/level_playtest.tscn") as PackedScene).instantiate()
	root.add_child(_level)
	process_frame.connect(_tick)


func _tick() -> void:
	_wait += 1
	if _phase == "boot":
		if _wait < 5:
			return
		_data = _level.get("data")
		if _player == null:
			var existing := _level.get_node_or_null("Player")
			if existing != null and not existing is PlayerController:
				_level.set("testing", true)
				_level.set("player", null)
				existing.free()
				var spawned := (load("res://scenes/player.tscn") as PackedScene).instantiate() as PlayerController
				spawned.name = "Player"
				spawned.position = _data.world_center(_data.spawn_cell) + Vector3(0.0, 0.08, 0.0)
				_level.add_child(spawned)
			_player = _level.get_node("Player") as PlayerController
			_rig = _player.get_node("ArtRoot/PartSockets") as ModularCharacterRig
			_player.parts.note.connect(func(message: String) -> void: _note = message)
			LimbField.scatter_ahead(_level, _player.global_position)
			return
		if _wait < 8:
			return
		if _data.spawn_cell != Vector2i(8, 13):
			_fail("loaded the wrong map, spawn %s" % _data.spawn_cell)
			return
		if not (_player is PlayerController) or _has_capsule(_player):
			_fail("playtest is not the articulated character")
			return
		if _player.parts.current_upper().id != "gorilla_arm" or _player.parts.current_lower().id != "wolf_leg":
			_fail("start limbs %s %s" % [_player.parts.current_upper().id, _player.parts.current_lower().id])
			return
		var field_ids := [
			"gorilla_arm", "gibbon_arm", "goose_wing", "octopus_arm", "bat_wing",
			"albatross_wing", "eagle_wing", "gerbil_paw", "wolf_leg", "ostrich_leg",
			"gerbil_leg", "kangaroo_leg", "demon_dog_leg", "octopus_leg", "goose_foot",
			"water_snake", "fish_tail", "snake_body", "mantis_arm",
		]
		for limb_id in field_ids:
			if _first_pickup(limb_id) == null:
				_fail("full map limb test field is missing %s" % limb_id)
				return
		if not _on("AnimArmUpper") or not _on("LeftLegSocket") or _on("AnimTail") or _on("HopArmSocket"):
			_fail("start picture is not the gorilla arm and wolf legs")
			return
		_goto("switch_upper")
		return
	if _phase == "switch_upper":
		var uppers: PackedStringArray = [
			"gorilla_arm", "gibbon_arm", "goose_wing", "octopus_arm",
			"bat_wing", "albatross_wing", "eagle_wing", "gerbil_paw", "gorilla_arm",
		]
		if not _expect_upper(uppers[_switch_step]):
			return
		if _player.parts.current_lower().id != "wolf_leg" or not _on("LeftLegSocket"):
			_fail("switching the upper limb changed the legs")
			return
		print("LIMB CYCLE upper ", uppers[_switch_step])
		_switch_step += 1
		if _switch_step < uppers.size():
			_tap("cycle_upper_part")
			return
		_switch_step = 0
		_goto("switch_lower")
		_tap("cycle_lower_part")
		return
	if _phase == "switch_lower":
		var lowers: PackedStringArray = [
			"ostrich_leg", "gerbil_leg", "kangaroo_leg", "demon_dog_leg",
			"octopus_leg", "goose_foot", "water_snake", "fish_tail", "wolf_leg",
		]
		if not _expect_lower(lowers[_switch_step]):
			return
		if _player.parts.current_upper().id != "gorilla_arm" or not _on("AnimArmUpper"):
			_fail("switching the lower limb changed the arm")
			return
		print("LIMB CYCLE lower ", lowers[_switch_step])
		_switch_step += 1
		if _switch_step < lowers.size():
			_tap("cycle_lower_part")
			return
		_goto("no_spin")
		_peak = 0.0
		_player.velocity = Vector3.ZERO
		Input.action_press("move_forward")
		return
	if _phase == "no_spin":
		_peak = maxf(_peak, _bone_angle("body"))
		if _wait < 24:
			return
		Input.action_release("move_forward")
		if _peak > 0.08:
			_fail("hop movement rotated the body by %s" % _peak)
			return
		if _player.assembly.resolve_locomotion() != CharacterAssemblyController.LocomotionMode.BIPED_WALK:
			_fail("wolf legs should keep locomotion priority over the gorilla arm")
			return
		_goto("aim_right")
		_attack_at(_player.global_position + Vector3(1.7, 0.0, 0.0))
		return
	if _phase == "aim_right":
		_sample_swing("anim_arm_upper")
		if _wait < 14:
			return
		var near := _props[0] as AffordanceProp
		if near.health != 18:
			_fail("gorilla hit for %d, expected 22" % (40 - near.health))
			return
		if absf(_peak) < 0.4 or _bone_angle("hop_arm") > 0.08:
			_fail("gorilla attack did not swing the gorilla arm")
			return
		_right_peak = _peak
		_free_props()
		_goto("aim_gap")
		return
	if _phase == "aim_gap":
		if _rig._attack_time > 0.0:
			return
		_goto("aim_forward")
		_attack_at(_player.global_position + Vector3(0.0, 0.0, -1.7))
		return
	if _phase == "aim_forward":
		_sample_swing("anim_arm_upper")
		if _wait < 14:
			return
		if absf(_peak) < 0.2 or absf(_peak - _right_peak) < 0.25:
			_fail("attack aim did not change with the target, peaks %s %s" % [_right_peak, _peak])
			return
		_free_props()
		_goto("nearest")
		var origin := _player.global_position
		_spawn_prop(origin + Vector3(1.6, 0.0, 0.0), 40)
		_spawn_prop(origin + Vector3(0.0, 0.0, -2.15), 40)
		_attack_at(Vector3.INF)
		return
	if _phase == "nearest":
		if _wait < 3:
			return
		var near := _props[0] as AffordanceProp
		var far := _props[1] as AffordanceProp
		if near.health != 18 or far.health != 40:
			_fail("nearest lock hit near=%d far=%d" % [near.health, far.health])
			return
		_free_props()
		_goto("miss")
		_spawn_prop(_player.global_position + Vector3(3.4, 0.0, 0.0), 40)
		_note = ""
		_attack_at(Vector3.INF)
		return
	if _phase == "miss":
		if _wait < 3:
			return
		var lone := _props[0] as AffordanceProp
		if lone.health != 40 or _note != "附近没有可攻击的对象":
			_fail("out of range health=%d note=%s" % [lone.health, _note])
			return
		_free_props()
		_goto("tree")
		var tree := _find_prop(Vector3(-3, 0, -3))
		if tree == null or tree.kind != "destructible_hard":
			_fail("map tree has no attackable prop")
			return
		var before := tree.health
		_stand(_surface_at(Vector3(-3 + 1.7, 0.0, -3)))
		_player.parts._attack_cooldown = 0.0
		_tap("attack")
		_phase = "tree_hit"
		_wait = 0
		_level.set_meta("tree_before", before)
		return
	if _phase == "tree_hit":
		if _wait < 3:
			return
		var tree := _find_prop(Vector3(-3, 0, -3))
		var fence := _find_prop(Vector3(-9, 0, -1))
		if tree.health != int(_level.get_meta("tree_before")) - 22:
			_fail("map tree health %d" % tree.health)
			return
		if fence != null and fence.health != fence.max_health:
			_fail("fence was hit while the tree was closer")
			return
		_goto("switch_arm")
		_tap("cycle_upper_part")
		return
	if _phase == "switch_arm":
		if _wait < 2:
			return
		if _player.parts.current_upper().id != "gibbon_arm" or not _on("HopArmSocket") or _on("AnimArmUpper"):
			_fail("Z did not show the gibbon arm")
			return
		_free_props()
		_goto("gibbon_hit")
		_spawn_prop(_player.global_position + Vector3(1.6, 0.0, 0.0), 40)
		_player.parts._attack_cooldown = 0.0
		_peak = 0.0
		_tap("attack")
		return
	if _phase == "gibbon_hit":
		_sample_swing("hop_arm")
		if _wait < 14:
			return
		var prop := _props[0] as AffordanceProp
		if prop.health != 26 or absf(_peak) < 0.4 or _bone_angle("anim_arm_upper") > 0.08:
			_fail("gibbon attack health=%d hop=%s arm=%s" % [prop.health, _peak, _bone_angle("anim_arm_upper")])
			return
		_free_props()
		var bag := _player.get_node("LimbBag") as LimbBag
		bag.try_add("mantis_arm")
		bag.move_bag_to_equip(bag.slots.find("mantis_arm"), "upper")
		if not _on("AnimScytheBlade") or _on("HopArmSocket"):
			_fail("mantis equip did not replace the gibbon arm; equipped=%s empty=%s mantis=%s" % [bag.equipped_upper, bag.slots.find(""), bag.slots.find("mantis_arm")])
			return
		_goto("scythe_hit")
		_spawn_prop(_player.global_position + Vector3(1.6, 0.0, 0.0), 40)
		_player.parts._attack_cooldown = 0.0
		_peak = 0.0
		_tap("attack")
		return
	if _phase == "scythe_hit":
		_sample_swing("anim_scythe_grip")
		if _wait < 14:
			return
		if absf(_peak) < 0.4 or _bone_angle("hop_arm") > 0.08 or _bone_angle("anim_arm_upper") > 0.08:
			_fail("mantis attack did not swing the scythe")
			return
		_free_props()
		_goto("lower")
		for _i in 7:
			_tap("cycle_lower_part")
		return
	if _phase == "lower":
		if _wait < 3:
			return
		if _player.parts.current_lower().id != "water_snake" or not _on("AnimTail") or _on("LeftLegSocket"):
			_fail("X did not show the water snake tail")
			return
		_stand(_player.global_position)
		_player.velocity = Vector3.ZERO
		_peak = 0.0
		Input.action_press("move_forward")
		_goto("snake_move")
		return
	if _phase == "snake_move":
		_peak = maxf(_peak, _bone_angle("body"))
		if _wait < 25:
			return
		Input.action_release("move_forward")
		if _player.velocity.z > -1.0:
			_fail("water snake did not move forward, vz=%s" % _player.velocity.z)
			return
		if _peak > 0.08:
			_fail("snake movement rotated the body by %s" % _peak)
			return
		if _player.assembly.resolve_locomotion() != CharacterAssemblyController.LocomotionMode.SNAKE_SLITHER:
			_fail("water snake should slither")
			return
		_tap("cycle_lower_part")
		_goto("fish")
		return
	if _phase == "fish":
		if _wait < 2:
			return
		if _player.parts.current_lower().id != "fish_tail" or not _on("AnimTail"):
			_fail("X did not show the fish tail")
			return
		var tail_art: Texture2D = _rig._sprites["AnimTail"].texture
		if tail_art == null or not tail_art.resource_path.ends_with("fish_tail.png"):
			_fail("fish tail is not using the new art")
			return
		_player.velocity = Vector3.ZERO
		var start := _player.global_position
		Input.action_press("move_forward")
		_level.set_meta("fish_start", start)
		_goto("fish_move")
		return
	if _phase == "fish_move":
		if _wait < 20:
			return
		Input.action_release("move_forward")
		var start: Vector3 = _level.get_meta("fish_start")
		if _player.global_position.distance_to(start) > 0.35:
			_fail("fish tail walked on hard ground")
			return
		var fluid := _south_zone("fluid")
		if fluid == null:
			_fail("playtest has no fluid")
			return
		_goto("fish_swim")
		_stand(_on_zone(fluid))
		_player.velocity = Vector3.ZERO
		_level.set_meta("swim_start", _player.global_position)
		Input.action_press("move_forward")
		return
	if _phase == "fish_swim":
		if _wait < 70:
			return
		Input.action_release("move_forward")
		var swim_start: Vector3 = _level.get_meta("swim_start")
		if _player.global_position.distance_to(swim_start) < 1.2:
			_fail("fish did not swim in fluid, moved %s" % _player.global_position.distance_to(swim_start))
			return
		for _i in 7:
			_tap("cycle_upper_part")
		_tap("cycle_lower_part")
		_goto("restore_arm")
		return
	if _phase == "restore_arm":
		if _wait < 3:
			return
		if _player.parts.current_upper().id != "gorilla_arm" or not _on("AnimArmUpper"):
			_fail("could not switch back to the gorilla arm, got %s" % _player.parts.current_upper().id)
			return
		if _player.parts.current_lower().id != "wolf_leg" or not _on("LeftLegSocket"):
			_fail("could not switch back to the wolf legs, got %s" % _player.parts.current_lower().id)
			return
		# 本测试已把全部 Z/X 调试肢体都轮换进 16 格背包，并额外装过螳螂臂；
		# 释放一个测试备件后再验证地图拾取，避免把满包误判成 G 输入失败。
		var pickup_bag := _player.get_node("LimbBag") as LimbBag
		if not pickup_bag.slots.has(""):
			var disposable := pickup_bag.slots.find("mantis_arm")
			pickup_bag.recycle_bag(disposable if disposable >= 0 else 0)
		_goto("pickup")
		var pickup := _first_pickup("snake_body")
		if pickup == null:
			_fail("no snake pickup in front of spawn")
			return
		_stand(pickup.global_position)
		_tap("part_interact")
		return
	if _phase == "pickup":
		if _wait < 3:
			return
		var bag := _player.get_node("LimbBag") as LimbBag
		if not bag.slots.has("snake_body"):
			_fail("G did not collect the snake")
			return
		_goto("rock")
		_rock = _find_prop(Vector3(11, 2, -9))
		if _rock == null or _rock.kind != "pushable":
			_fail("map rock is not pushable")
			return
		_level.set_meta("rock_start", _rock.global_position)
		_stand(_rock.global_position + Vector3(0.9, 0.08, 0.0))
		_tap("part_interact")
		return
	if _phase == "rock":
		if _wait < 2:
			return
		if _note != "抓住了，一起走；跳起来会把它举起":
			_fail("G on the rock said %s" % _note)
			return
		Input.action_press("move_right")
		_goto("rock_move")
		return
	if _phase == "rock_move":
		if _wait < 30:
			return
		Input.action_release("move_right")
		var start: Vector3 = _level.get_meta("rock_start")
		if _rock == null or _rock.global_position.distance_to(start) < 0.45:
			_fail("rock did not move")
			return
		_player.parts._release_all()
		_goto("grass")
		var grass_cell := _data.world_to_cell(Vector3(9, 0, -3))
		var grass_height := _data.elevation(grass_cell)
		var south := grass_cell + Vector2i(0, 1)
		var grass_start := _data.world_center(grass_cell)
		if _data.cell_exists(south) and _data.elevation(south) == grass_height:
			grass_start = _data.world_center(south)
		_stand(grass_start + Vector3(0, 0.08, 0))
		_player.velocity = Vector3.ZERO
		_level.set_meta("grass_z", _data.world_center(grass_cell).z)
		Input.action_press("move_forward")
		return
	if _phase == "grass":
		var grass_z := float(_level.get_meta("grass_z"))
		if _wait < 90 and _player.global_position.z > grass_z - 1.2:
			return
		Input.action_release("move_forward")
		if _player.global_position.z > grass_z - 0.8:
			_fail("grass blocked the player at z=%s grass=%s" % [_player.global_position.z, grass_z])
			return
		_goto("tent")
		var before := _hard_health_total()
		_level.set_meta("hard_before", before)
		_note = ""
		_stand(_surface_at(Vector3(6.4, 0.0, -9)))
		_tap("part_interact")
		return
	if _phase == "tent":
		if _wait < 3:
			return
		if _hard_health_total() != int(_level.get_meta("hard_before")) or not _note.contains("没有"):
			_fail("tent interaction health delta note=%s" % _note)
			return
		_goto("stair")
		var low := Vector2i(4, 5)
		var high := low + Vector2i(0, -1)
		_level.set_meta("stair_high", _data.world_center(high).y)
		_stand(_data.world_center(low) + Vector3(0, 0.08, 1.5))
		_player.velocity = Vector3.ZERO
		Input.action_press("move_forward")
		return
	if _phase == "stair":
		var target_y := float(_level.get_meta("stair_high"))
		if _wait < 160 and absf(_player.global_position.y - target_y) > 0.4:
			return
		Input.action_release("move_forward")
		if absf(_player.global_position.y - target_y) > 0.45:
			_fail("stair foot=%s expected=%s" % [_player.global_position.y, target_y])
			return
		var cliff := _find_cliff()
		if cliff.is_empty():
			_fail("map has no plain cliff to test")
			return
		_goto("cliff")
		_level.set_meta("cliff_y", float(cliff["y"]))
		_level.set_meta("cliff_at", cliff["at"])
		_stand(cliff["at"])
		_player.velocity = Vector3.ZERO
		Input.action_press(str(cliff["action"]))
		return
	if _phase == "cliff":
		if _wait < 50:
			return
		Input.action_release("move_forward")
		Input.action_release("move_back")
		Input.action_release("move_left")
		Input.action_release("move_right")
		if _player.global_position.y > float(_level.get_meta("cliff_y")) + 1.2:
			_fail("cliff was climbed, foot=%s" % _player.global_position.y)
			return
		if not _feet_are_hard():
			return
		_goto("climb")
		_stand(_level.get_meta("cliff_at"))
		_note = ""
		_tap("cycle_upper_part")
		_tap("part_interact")
		return
	if _phase == "climb":
		if _wait < 2:
			return
		if _player.parts.current_upper().id != "gibbon_arm" or not _note.contains("抓住"):
			_fail("gibbon did not grab the cliff, note=%s" % _note)
			return
		var target := _player.parts._climb_target
		if target == null or target.ledge_height < 0.0:
			_fail("cliff has no ledge")
			return
		_level.set_meta("ledge_y", target.ledge_point.y)
		_goto("climb_up")
		_note = ""
		Input.action_press("move_forward")
		return
	if _phase == "climb_up":
		if _wait < 160 and not _note.contains("爬上去了"):
			return
		Input.action_release("move_forward")
		var ledge_y := float(_level.get_meta("ledge_y"))
		if not _note.contains("爬上去了") or absf(_player.global_position.y - ledge_y) > 0.45:
			_fail("gibbon did not reach the top, foot=%s ledge=%s note=%s" % [_player.global_position.y, ledge_y, _note])
			return
		_tap("part_interact")
		for _step in 6:
			_tap("cycle_upper_part")
		var soft := _soft_tuft()
		if soft == null:
			_fail("map grass has no soft affordance")
			return
		_goto("dig")
		_stand(_soft_stand(soft))
		_level.set_meta("soft", soft)
		_level.set_meta("soft_health", soft.health)
		_note = ""
		_tap("part_interact")
		return
	if _phase == "dig":
		if _wait < 3:
			return
		var soft: AffordanceProp = _level.get_meta("soft")
		if _player.parts.current_upper().id != "gerbil_paw" or soft.health != int(_level.get_meta("soft_health")) or not _note.contains("没有"):
			_fail("gerbil dug hard ground, note=%s health=%s" % [_note, soft.health])
			return
		_goto("cut")
		_player.parts._attack_cooldown = 0.0
		_tap("attack")
		return
	if _phase == "cut":
		if _wait < 3:
			return
		var soft: AffordanceProp = _level.get_meta("soft")
		if soft.health >= int(_level.get_meta("soft_health")):
			_fail("attack did not cut the grass, health=%s" % soft.health)
			return
		var wet := _fluid_soft()
		if wet == null:
			_fail("fluid has no soft prop")
			return
		_goto("dig_fluid")
		_stand(_surface_at(wet.global_position + Vector3(0.75, 0.0, 0.0)))
		_level.set_meta("wet", wet)
		_level.set_meta("wet_health", wet.health)
		_note = ""
		_tap("part_interact")
		return
	if _phase == "dig_fluid":
		if _wait < 3:
			return
		var wet: AffordanceProp = _level.get_meta("wet")
		if wet.health >= int(_level.get_meta("wet_health")) or not _note.contains("挖"):
			_fail("gerbil did not dig in fluid, note=%s health=%s" % [_note, wet.health])
			return
		for _i in 4:
			_tap("cycle_upper_part")
		var desert := _zone_tagged("desert")
		if desert == null:
			_fail("playtest has no desert")
			return
		_goto("desert")
		_stand(_on_zone(desert))
		_note = ""
		_tap("part_interact")
		return
	if _phase == "desert":
		if _wait < 3:
			return
		if _player.parts.current_upper().id != "octopus_arm" or not _note.contains("吸不住"):
			_fail("octopus stuck to desert, note=%s" % _note)
			return
		_goto("stick")
		_stand(_data.world_center(_data.spawn_cell) + Vector3(0.0, 0.08, 0.0))
		_note = ""
		_tap("part_interact")
		return
	if _phase == "stick":
		if _wait < 3:
			return
		if not _note.contains("吸附"):
			_fail("octopus did not stick to hard ground, note=%s" % _note)
			return
		_tap("part_interact")
		print("EDITOR PLAY: PASS")
		quit(0)


func _goto(next_phase: String) -> void:
	_phase = next_phase
	_wait = 0


func _attack_at(point: Vector3) -> void:
	if point != Vector3.INF:
		_spawn_prop(point, 40)
	_player.parts._attack_cooldown = 0.0
	_peak = 0.0
	_tap("attack")


func _spawn_prop(point: Vector3, health: int) -> AffordanceProp:
	var host := Node3D.new()
	host.position = point
	_level.add_child(host)
	var prop := AffordanceProp.new()
	prop.configure_host(host, "destructible_hard", health)
	prop.position = point
	_level.add_child(prop)
	_props.append(prop)
	return prop


func _free_props() -> void:
	for prop in _props:
		if prop == null or not is_instance_valid(prop):
			continue
		prop.spent = true
		if is_instance_valid(prop.host):
			prop.host.queue_free()
		prop.queue_free()
	_props.clear()


func _surface_at(point: Vector3) -> Vector3:
	var cell := _data.world_to_cell(point)
	if not _data.cell_exists(cell):
		return point
	return Vector3(point.x, _data.world_center(cell).y + 0.08, point.z)


func _find_prop(point: Vector3) -> AffordanceProp:
	var best: AffordanceProp = null
	var best_distance := 1.25
	for node in get_nodes_in_group("affordance"):
		var prop := node as AffordanceProp
		if prop == null:
			continue
		var distance := Vector2(prop.global_position.x, prop.global_position.z).distance_to(Vector2(point.x, point.z))
		if distance < best_distance:
			best = prop
			best_distance = distance
	return best


func _hard_health_total() -> int:
	var total := 0
	for node in get_nodes_in_group("affordance"):
		var prop := node as AffordanceProp
		if prop and prop.kind == "destructible_hard" and not prop.spent:
			total += prop.health
	return total


func _first_pickup(limb_id: String) -> Node3D:
	for node in get_nodes_in_group("limb_pickup"):
		if str(node.get("limb_id")) == limb_id:
			return node as Node3D
	return null


func _feet_are_hard() -> bool:
	var feet := _player.global_position
	if not SceneProbe.tags_at(feet).has("hard") or not _zone_covers(feet):
		_fail("feet are not on a mapped hard surface")
		return false
	var rock := _first_cell(LevelData.TERRAIN_ROCK)
	if rock.x < 0:
		_fail("map has no rock cell")
		return false
	var rock_point := _data.world_center(rock) + Vector3(0.0, 0.2, 0.0)
	if not SceneProbe.tags_at(rock_point).has("hard") or not _zone_covers(rock_point):
		_fail("rock cell is not a hard surface")
		return false
	return true


func _zone_tagged(tag: String) -> SurfaceZone:
	return _south_zone(tag)


func _south_zone(tag: String) -> SurfaceZone:
	var best: SurfaceZone = null
	for node in _level.get_tree().get_nodes_in_group("surface_zone"):
		var zone := node as SurfaceZone
		if zone == null or not zone.tags.has(tag):
			continue
		if tag == "fluid" and zone.tags.has("hard"):
			continue
		if best == null or zone.global_position.z > best.global_position.z:
			best = zone
	return best


func _on_zone(zone: SurfaceZone) -> Vector3:
	return _surface_at(zone.global_position)


func _fluid_soft() -> AffordanceProp:
	for prop in SceneProbe.each_kind(PackedStringArray(["destructible_soft"])):
		if SceneProbe.tags_at(prop.global_position).has("fluid"):
			return prop
	return null


func _zone_covers(point: Vector3) -> bool:
	for node in _level.get_tree().get_nodes_in_group("surface_zone"):
		var zone := node as SurfaceZone
		if zone and zone.covers(point):
			return true
	return false


func _first_cell(terrain_id: int) -> Vector2i:
	for x in _data.map_size.x:
		for y in _data.map_size.y:
			var cell := Vector2i(x, y)
			if not _data.cell_exists(cell) or _data.stair_at(cell) >= 0:
				continue
			var cell_data := _data.get_cell(cell)
			var tile_id := str(cell_data.get("tile_id", ""))
			var matches := int(cell_data.get("terrain", -1)) == terrain_id
			if terrain_id == LevelData.TERRAIN_ROCK and tile_id == "rock":
				matches = true
			if terrain_id == LevelData.TERRAIN_GRASS and (tile_id == "grass" or tile_id == ""):
				matches = matches or tile_id == "grass"
			if matches:
				return cell
	return Vector2i(-1, -1)


func _soft_tuft() -> AffordanceProp:
	var best: AffordanceProp = null
	var best_gap := -1.0
	for prop in SceneProbe.each_kind(PackedStringArray(["destructible_soft"])):
		if SceneProbe.tags_at(prop.global_position).has("fluid"):
			continue
		var hard := SceneProbe.nearest(prop.global_position, 12.0, PackedStringArray(["destructible_hard"]))
		var gap := 12.0 if hard == null else prop.global_position.distance_to(hard.global_position)
		if gap > best_gap:
			best_gap = gap
			best = prop
	return best


func _soft_stand(soft: AffordanceProp) -> Vector3:
	var away := Vector3(0.0, 0.0, 1.0)
	var hard := SceneProbe.nearest(soft.global_position, 12.0, PackedStringArray(["destructible_hard"]))
	if hard:
		away = soft.global_position - hard.global_position
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = Vector3(0.0, 0.0, 1.0)
		away = away.normalized()
	return _surface_at(soft.global_position + away * 1.45)


func _find_cliff() -> Dictionary:
	for x in _data.map_size.x:
		for y in _data.map_size.y:
			var cell := Vector2i(x, y)
			if not _data.cell_exists(cell):
				continue
			for direction in 4:
				var neighbor: Vector2i = cell + LevelData.DIRS[direction]
				if not _data.cell_exists(neighbor):
					continue
				if _data.elevation(neighbor) < _data.elevation(cell) + 1:
					continue
				if _stair_between(cell, neighbor):
					continue
				var actions: PackedStringArray = ["move_forward", "move_right", "move_back", "move_left"]
				var action := actions[direction]
				return {
					"at": _data.world_center(cell) + Vector3(0, 0.08, 0),
					"y": _data.world_center(cell).y,
					"action": action,
				}
	return {}


func _stair_between(low: Vector2i, high: Vector2i) -> bool:
	for stair in _data.stairs:
		var cells := _data.stair_cells(stair)
		if cells[0] == Vector2(low) and cells[1] == Vector2(high):
			return true
	return false


func _stand(at: Vector3) -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = at


func _tap(action: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _on(socket_name: String) -> bool:
	return _rig._attachments[socket_name].visible


func _scale(socket_name: String) -> float:
	return _rig._sprites[socket_name].scale.x


func _tint(socket_name: String) -> Color:
	return _rig._sprites[socket_name].modulate


func _uses_art(socket_name: String, file_name: String) -> bool:
	var drawn := _rig._sprites[socket_name].texture as Texture2D
	return drawn != null and drawn.resource_path.ends_with(file_name) and _tint(socket_name).is_equal_approx(Color.WHITE)


func _expect_upper(part_id: String) -> bool:
	if _player.parts.current_upper().id != part_id:
		_fail("upper id %s, expected %s" % [_player.parts.current_upper().id, part_id])
		return false
	var ok := true
	match part_id:
		"gorilla_arm":
			ok = _on("AnimArmUpper") and _on("AnimArmFore") and not _on("HopArmSocket") and not _on("LeftWingSocket") and not _on("AnimScytheBlade") and not _on("CrawlLeftSocket")
		"gibbon_arm":
			ok = _on("HopArmSocket") and not _on("AnimArmUpper") and not _on("LeftWingSocket") and is_equal_approx(_scale("HopArmSocket"), 1.0)
		"gerbil_paw":
			ok = _on("HopArmSocket") and not _on("AnimArmUpper") and is_equal_approx(_scale("HopArmSocket"), 0.55)
		"octopus_arm":
			ok = _on("CrawlLeftSocket") and _on("CrawlRightSocket") and not _on("AnimArmUpper") and not _on("HopArmSocket") and not _on("LeftWingSocket")
		"goose_wing", "bat_wing", "albatross_wing", "eagle_wing":
			ok = _on("LeftWingSocket") and _on("RightWingSocket") and not _on("AnimArmUpper") and not _on("HopArmSocket")
	if part_id == "goose_wing" and not _tint("LeftWingSocket").is_equal_approx(Color(0.92, 0.92, 0.9)):
		ok = false
	if part_id == "bat_wing" and not _uses_art("LeftWingSocket", "bat_wing_left.png"):
		ok = false
	if part_id == "albatross_wing" and not _uses_art("LeftWingSocket", "albatross_wing_left.png"):
		ok = false
	if part_id == "eagle_wing" and not _uses_art("LeftWingSocket", "eagle_wing_left.png"):
		ok = false
	if not ok:
		_fail("upper %s drew the wrong sockets" % part_id)
		return false
	var mode := _player.assembly.resolve_locomotion()
	# 狼腿在整个上肢轮换期间保持装备；下肢移动优先于所有上肢。
	var expected := CharacterAssemblyController.LocomotionMode.BIPED_WALK
	if part_id in ["goose_wing", "bat_wing", "albatross_wing", "eagle_wing"]:
		if not _player.assembly.part_wings:
			_fail("upper %s did not enable wing movement" % part_id)
			return false
	if mode != expected:
		_fail("upper %s movement %s" % [part_id, mode])
		return false
	return true


func _expect_lower(part_id: String) -> bool:
	if _player.parts.current_lower().id != part_id:
		_fail("lower id %s, expected %s" % [_player.parts.current_lower().id, part_id])
		return false
	var ok := true
	match part_id:
		"wolf_leg":
			ok = _on("LeftLegSocket") and _on("RightLegSocket") and not _on("AnimTail") and is_equal_approx(_scale("LeftLegSocket"), 1.0)
		"ostrich_leg":
			ok = _on("LeftLegSocket") and not _on("AnimTail") and is_equal_approx(_scale("LeftLegSocket"), 1.25)
		"gerbil_leg":
			ok = _on("LeftLegSocket") and is_equal_approx(_scale("LeftLegSocket"), 0.62)
		"kangaroo_leg":
			ok = _on("LeftLegSocket") and is_equal_approx(_scale("LeftLegSocket"), 1.15)
		"demon_dog_leg":
			ok = _on("LeftLegSocket") and not _on("AnimTail") and _tint("LeftLegSocket").is_equal_approx(Color(0.45, 0.18, 0.18))
		"octopus_leg":
			ok = _on("LeftLegSocket") and _tint("LeftLegSocket").is_equal_approx(Color(0.4, 0.48, 0.78))
		"goose_foot":
			ok = _on("LeftLegSocket") and not _on("AnimTail") and is_equal_approx(_scale("LeftLegSocket"), 1.35)
		"water_snake":
			ok = _on("AnimTail") and not _on("LeftLegSocket") and _tint("AnimTail").is_equal_approx(Color.WHITE)
		"fish_tail":
			ok = _on("AnimTail") and not _on("LeftLegSocket") and _uses_art("AnimTail", "fish_tail.png")
	if not ok:
		_fail("lower %s drew the wrong sockets" % part_id)
		return false
	var mode := _player.assembly.resolve_locomotion()
	var expected := CharacterAssemblyController.LocomotionMode.BIPED_WALK
	if part_id == "water_snake" or part_id == "fish_tail":
		expected = CharacterAssemblyController.LocomotionMode.SNAKE_SLITHER
	elif part_id == "octopus_leg":
		expected = CharacterAssemblyController.LocomotionMode.TENTACLE_CRAWL
	if mode != expected:
		_fail("lower %s movement %s" % [part_id, mode])
		return false
	var speed := _player.parts.speed_on(PackedStringArray(["hard"]))
	if part_id == "ostrich_leg" and speed < 8.0:
		_fail("ostrich should move fast, speed %s" % speed)
		return false
	if part_id == "demon_dog_leg" and not is_equal_approx(speed, PartDefinition.speed_value(PartDefinition.Band.HIGH)):
		_fail("demon dog speed %s" % speed)
		return false
	if part_id == "fish_tail" and speed != 0.0:
		_fail("fish should not walk on hard ground")
		return false
	return true


func _sample_swing(bone_name: String) -> void:
	if _rig._attack_time <= 0.0:
		return
	var swing := _bone_swing(bone_name)
	if absf(swing) > absf(_peak):
		_peak = swing


func _bone_swing(bone_name: String) -> float:
	var rotation: Quaternion = _rig._skeleton.get_bone_pose_rotation(_rig._bones[bone_name])
	return 2.0 * atan2(-rotation.z, rotation.w)


func _bone_angle(bone_name: String) -> float:
	var rotation: Quaternion = _rig._skeleton.get_bone_pose_rotation(_rig._bones[bone_name])
	return Quaternion.IDENTITY.angle_to(rotation)


func _has_capsule(body: Node) -> bool:
	for child in body.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node and mesh_node.mesh is CapsuleMesh:
			return true
	return false


func _fail(message: String) -> void:
	push_error("EDITOR PLAY: " + message)
	print("EDITOR PLAY: FAIL " + message)
	quit(1)
