class_name PartLoadout
extends Node

signal changed_loadout
signal note(message: String)
signal attacked(around: bool)

const UNSPECIFIED_SPEED := 2.4
const ENEMY_KINDS: PackedStringArray = ["enemy_small", "enemy_elite"]
const ATTACK_KINDS: PackedStringArray = ["enemy_small", "enemy_elite", "destructible_hard", "destructible_soft"]
const ATTACK_RANGE := 2.35

var upper_index := 0
var lower_index := 0
var breakthrough := false

var _attack_cooldown := 0.0
var _swing := 0.0
var _slam_queued := false
var _glide_left := 0.0
var _glide_armed := false
var _flying := false
var _climbing := false
var _climb_target: AffordanceProp
var _held: AffordanceProp
var _hold_mode := ""
var _stuck := false
var _diving := false
var _dive_point := Vector3.ZERO
var _dive_hit: Array[AffordanceProp] = []
var _jumps_left := 0
var _jump_buffer := 0.0
var _coyote := 0.0
var _was_floor := true
var _air_peak_y := 0.0
var _auto_timer := 0.0
var _rings: Array[Dictionary] = []


func handles_attack() -> bool:
	return true


func overrides_horizontal() -> bool:
	return true


func current_upper() -> PartDefinition:
	return PartCatalog.uppers()[upper_index]


func current_lower() -> PartDefinition:
	return PartCatalog.lowers()[lower_index]


func jump_count() -> int:
	return current_lower().jump_count_for(breakthrough)


func is_burrowed() -> bool:
	var lower := current_lower()
	return lower.burrow and _tags_overlap(lower.allowed_surfaces, _tags())


func controls_vertical() -> bool:
	if _climbing or _stuck or _diving or _flying:
		return true
	var upper := current_upper()
	if upper.air_mode != "":
		return true
	if jump_count() > 0:
		return true
	return _swim_controls_air()


func speed_on(tags: PackedStringArray) -> float:
	var lower := current_lower()
	var terrain_speed := TerrainMovementRules.speed_for_tags(lower.id, tags)
	if terrain_speed >= 0.0:
		return terrain_speed
	if lower.swim == "skim":
		if tags.has("fluid"):
			return PartDefinition.speed_value(PartDefinition.Band.HIGH)
		if tags.has("hard"):
			return PartDefinition.speed_value(PartDefinition.Band.LOW)
		return 0.0
	if lower.swim == "sink":
		if tags.has("fluid") or tags.has("hard"):
			return PartDefinition.speed_value(PartDefinition.Band.NORMAL)
		return 0.0
	if lower.swim == "hover_fast":
		if tags.has("fluid"):
			return PartDefinition.speed_value(PartDefinition.Band.HIGH)
		return 0.0
	if lower.swim == "fluid_and_hard":
		if tags.has("fluid") or tags.has("hard"):
			return PartDefinition.speed_value(PartDefinition.Band.NORMAL)
		return 0.0
	if lower.speed_band == PartDefinition.Band.NONE:
		return UNSPECIFIED_SPEED
	if not _tags_overlap(lower.allowed_surfaces, tags):
		return 0.0
	return PartDefinition.speed_value(lower.speed_band)


func can_stick_on(tags: PackedStringArray) -> bool:
	var upper := current_upper()
	if upper.can_stick and not _tag_blocked(upper.stick_blocked_tags, tags):
		return true
	return breakthrough and current_lower().breakthrough_stick_any


func equip(upper_id: String, lower_id: String) -> void:
	upper_index = _index_of(PartCatalog.uppers(), upper_id)
	lower_index = _index_of(PartCatalog.lowers(), lower_id)
	_release_all()
	changed_loadout.emit()


func summary() -> String:
	var upper := current_upper()
	var lower := current_lower()
	var tier := "突破" if breakthrough else "基础"
	return "上肢 %s %s  %s\n下肢 %s %s  %s\n%s｜%s\nZ上肢  X下肢  T%s  G交互  J攻击" % [
		upper.display_name, upper.rank_label(), upper.attack_text(),
		lower.display_name, lower.rank_label(), lower.blurb,
		upper.blurb, tier, tier,
	]


func space_hint() -> String:
	match current_upper().air_mode:
		"flight":
			return "空格：起飞 / 按住上升，松开下降"
		"hover":
			return "离地悬停 · 按住空格滑向地面"
		"glide":
			return "离地后短暂滑行"
	if jump_count() > 1:
		return "空格：二段跳"
	if jump_count() == 1:
		return "空格：跳跃"
	return ""


func horizontal_velocity(wish: Vector3, delta: float) -> Vector3:
	var player := _player()
	if player == null:
		return Vector3.ZERO
	var current := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if _hold_mode == "throw":
		return current.move_toward(Vector3.ZERO, 48.0 * delta)
	if _climbing:
		var axes := player.camera_planar_axes()
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		return axes[0] * input.x * 3.2
	if _diving:
		var flat := _dive_point - player.global_position
		flat.y = 0.0
		if flat.length() > 0.35:
			return flat.normalized() * 12.0
		return Vector3.ZERO
	var effects := SceneMechanism.effects_at(player.global_position)
	var target := wish * speed_on(_tags()) * float(effects.speed_multiplier) \
		+ Vector3(effects.drift.x, 0, effects.drift.z)
	var accel := 34.0 if wish.length_squared() > 0.01 else 40.0
	if is_burrowed():
		accel *= 0.75
	if not player.is_on_floor() and not _flying and not _stuck:
		accel *= 0.55
	return current.move_toward(target, accel * delta)


func apply_vertical(player: PlayerController, delta: float) -> void:
	var upper := current_upper()
	var on_floor := player.is_on_floor() and not _climbing and not _stuck and not _flying and not _diving
	if on_floor and player.velocity.y <= 0.2:
		_jumps_left = jump_count()
		_glide_left = 0.0
		_glide_armed = false
	if Input.is_action_just_pressed("air_action"):
		_jump_buffer = 0.12
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if on_floor:
		_coyote = 0.12
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	if _climbing:
		if Input.is_action_just_pressed("air_action"):
			_climbing = false
			_climb_target = null
			player.velocity.y = 7.4
			return
		if _climb_target != null and _climb_target.ledge_height >= 0.0 and player.global_position.y >= _climb_target.ledge_height - 0.2:
			var landed := _climb_target.ledge_point
			_climbing = false
			_climb_target = null
			player.global_position = landed
			player.velocity = Vector3.ZERO
			note.emit("爬上去了")
			return
		var climb := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		player.velocity.y = climb * 3.4
		return
	if _diving:
		_tick_dive(player)
		return
	if _stuck:
		player.velocity.y = move_toward(player.velocity.y, 0.0, 24.0 * delta)
		return
	if upper.air_mode == "flight":
		_apply_flight(player, delta)
		return
	if _apply_swim_vertical(player, delta):
		return
	if _try_jump(player, on_floor):
		return
	if not on_floor and upper.air_mode == "hover":
		var descending := Input.is_action_pressed("air_action")
		var target := -2.6 if descending else 0.0
		player.velocity.y = move_toward(player.velocity.y, target, 16.0 * delta)
		return
	if not on_floor and upper.air_mode == "glide":
		if not _glide_armed:
			_glide_armed = true
			_glide_left = 0.85
		if _glide_left > 0.0:
			_glide_left -= delta
			player.velocity.y = move_toward(player.velocity.y, -1.25, 18.0 * delta)
			return
	if not player.is_on_floor():
		player.velocity.y -= 18.0 * delta
	elif player.velocity.y < 0.0:
		player.velocity.y = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_upper_part"):
		_stow_bag("upper")
		upper_index = (upper_index + 1) % PartCatalog.uppers().size()
		_release_all()
		_emit_change("上肢：%s" % current_upper().display_name)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_lower_part"):
		_stow_bag("lower")
		lower_index = (lower_index + 1) % PartCatalog.lowers().size()
		_release_all()
		_emit_change("下肢：%s" % current_lower().display_name)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_breakthrough"):
		breakthrough = not breakthrough
		_emit_change("突破能力已打开" if breakthrough else "回到基础能力")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("part_interact"):
		_interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack"):
		try_attack()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if _swing > 0.0:
		_swing = maxf(_swing - delta, 0.0)
		if _swing == 0.0 and _slam_queued:
			_slam_queued = false
			_slam(_player())
	_watch_landing()
	_auto_interact()
	_follow_held(delta)
	_tick_rings(delta)


func try_attack() -> void:
	var player := _player()
	if player == null or _attack_cooldown > 0.0:
		return
	var upper := current_upper()
	if _flying and upper.has_ability("dive", breakthrough):
		var enemy := SceneProbe.nearest(player.global_position, 9.0, ENEMY_KINDS)
		_begin_dive(player, enemy)
		return
	if upper.attack_shape == PartDefinition.AttackShape.NONE:
		note.emit("这个部件没有攻击")
		return
	var power := PartDefinition.power_value(upper.attack_power)
	_attack_cooldown = PartDefinition.cooldown_for(upper.attack_rate)
	_swing = 0.24
	var target := _lock_attack_target(player)
	if target == null:
		note.emit("附近没有可攻击的对象")
	else:
		var rig := player.get_node_or_null("ArtRoot/PartSockets") as ModularCharacterRig
		if rig:
			rig.aim_attack(target.global_position - player.global_position)
		target.take_hit(power)
	var assembly := player.get_node_or_null("Assembly")
	if assembly and assembly.has_method("request_attack"):
		assembly.request_attack(_attack_channel(_displayed_upper_id()))
	attacked.emit(upper.attack_shape == PartDefinition.AttackShape.AROUND)
	if upper.has_ability("slam_end", breakthrough):
		_slam_queued = true
	if upper.has_ability("hurricane", breakthrough):
		_spawn_hurricane(player, power)


func _interact() -> void:
	var player := _player()
	if player == null:
		return
	if _hold_mode != "" or _climbing or _stuck:
		var throwing := _hold_mode == "throw"
		_release_all()
		note.emit("抛出去了" if throwing else "松开了")
		return
	var origin := player.global_position
	var nearby: SceneMechanism
	var distance := 2.5
	for node in get_tree().get_nodes_in_group("scene_mechanisms"):
		if not node is SceneMechanism or node.collected:
			continue
		var current := origin.distance_to(node.global_position)
		if current < distance:
			nearby = node
			distance = current
	if nearby != null and nearby.interact(player):
		return
	var upper := current_upper()
	if upper.has_ability("grab_climb", breakthrough):
		var pillar := SceneProbe.nearest(origin, 1.9, PackedStringArray(["climbable"]))
		if pillar:
			_attach_climb(player, pillar)
			return
	if upper.has_ability("grab_throw", breakthrough):
		if _try_throw_grab(origin):
			return
	if upper.has_ability("push_pull", breakthrough):
		var box := SceneProbe.nearest(origin, 1.9, PackedStringArray(["pushable"]))
		if box:
			_held = box
			_hold_mode = "push"
			box.set_carried(true)
			note.emit("抓住了，一起走；跳起来会把它举起")
			return
	if upper.can_stick and _tag_blocked(upper.stick_blocked_tags, _tags()):
		note.emit("这种表面吸不住")
		return
	if can_stick_on(_tags()):
		_stuck = true
		note.emit("吸附住了，松开 G 离开")
		return
	if upper.has_ability("smash_hard", breakthrough):
		var hard := SceneProbe.nearest(origin, 2.1, PackedStringArray(["destructible_hard"]))
		if hard:
			var destroyed := hard.take_hit(PartDefinition.power_value(upper.attack_power))
			note.emit("砸碎了" if destroyed else "砸了一下")
			return
	if upper.has_ability("dig_soft", breakthrough) and _tags().has("fluid"):
		var soft := SceneProbe.nearest(origin, 2.1, PackedStringArray(["destructible_soft"]))
		if soft:
			var dug := soft.take_hit(PartDefinition.power_value(upper.attack_power) + 6)
			note.emit("挖开了" if dug else "挖了一下")
			return
	note.emit("附近没有这个部件能用的东西")


func _attach_climb(player: PlayerController, pillar: AffordanceProp) -> void:
	_climbing = true
	_climb_target = pillar
	var side := player.global_position - pillar.global_position
	side.y = 0.0
	if side.length_squared() < 0.04:
		side = Vector3.RIGHT
	var parked := pillar.global_position + side.normalized() * 0.95
	parked.y = maxf(player.global_position.y, 0.45)
	player.global_position = parked
	player.velocity = Vector3.ZERO
	note.emit("抓住了，W/S 上下，再按 G 松开")


func _try_throw_grab(origin: Vector3) -> bool:
	var kinds := PackedStringArray(["enemy_small", "pushable", "grabbable"])
	var target := SceneProbe.nearest(origin, 2.2, kinds)
	var elite := SceneProbe.nearest(origin, 2.2, PackedStringArray(["enemy_elite"]))
	if elite != null and (target == null or origin.distance_to(elite.global_position) < origin.distance_to(target.global_position)):
		note.emit("抓不住精英和 BOSS")
		return true
	if target == null:
		return false
	_held = target
	_hold_mode = "throw"
	target.set_carried(true)
	note.emit("抓住了，再按 G 沿面朝方向抛出")
	return true


func _stow_bag(slot_name: String) -> void:
	var bag := _player().get_node_or_null("LimbBag") as LimbBag
	if bag:
		bag.stow_equipped(slot_name)


func _release_all() -> void:
	if _held != null and is_instance_valid(_held):
		if _hold_mode == "throw":
			_held.throw_along(_facing(_player()))
		else:
			_held.drop()
	_held = null
	_hold_mode = ""
	_climbing = false
	_climb_target = null
	_stuck = false
	_flying = false
	_diving = false


func _emit_change(message: String) -> void:
	changed_loadout.emit()
	note.emit(message)


func _watch_landing() -> void:
	var player := _player()
	if player == null:
		return
	var on_floor := player.is_on_floor()
	if not on_floor:
		_air_peak_y = maxf(_air_peak_y, player.global_position.y)
	elif not _was_floor:
		var drop := _air_peak_y - player.global_position.y
		_air_peak_y = player.global_position.y
		if _diving:
			_diving = false
			_flying = false
			_slam(player)
		elif drop >= 2.4 and current_upper().has_ability("slam_fall", breakthrough):
			_slam(player)
			note.emit("落地砸击")
	_was_floor = on_floor


func _auto_interact() -> void:
	if _auto_timer > 0.0:
		_auto_timer -= get_physics_process_delta_time()
		return
	var player := _player()
	if player == null:
		return
	var origin := player.global_position
	var upper := current_upper()
	var lower := current_lower()
	var tags := _tags()
	if upper.has_ability("smash_hard", breakthrough):
		var hard := SceneProbe.nearest(origin, 1.35, PackedStringArray(["destructible_hard"]))
		if hard:
			var destroyed := hard.take_hit(PartDefinition.power_value(upper.attack_power))
			_auto_timer = 0.45
			if destroyed:
				note.emit("击碎了硬物件")
			return
	if upper.has_ability("dig_soft", breakthrough) and tags.has("fluid"):
		var soft := SceneProbe.nearest(origin, 1.45, PackedStringArray(["destructible_soft"]))
		if soft:
			var dug := soft.take_hit(PartDefinition.power_value(upper.attack_power) + 6)
			_auto_timer = 0.28
			if dug:
				note.emit("在流体里挖开了")
			return
	if lower.has_ability("smash_near", breakthrough):
		var nearby := SceneProbe.nearest(origin, 1.35, PackedStringArray(["destructible_hard", "destructible_soft"]))
		if nearby:
			var smashed := nearby.take_hit(10)
			_auto_timer = 0.4
			if smashed:
				note.emit("靠近时拆掉了物件")
			return
	if is_burrowed() and upper.has_ability("burrow_ambush", breakthrough):
		var enemy := SceneProbe.nearest(origin, 1.55, ENEMY_KINDS)
		if enemy:
			var ambushed := enemy.take_hit(PartDefinition.power_value(upper.attack_power) + 6)
			_auto_timer = 0.45
			if ambushed:
				note.emit("从下面突袭")


func _follow_held(delta: float) -> void:
	if _held == null or not is_instance_valid(_held) or _held.spent:
		_held = null
		_hold_mode = ""
		return
	var player := _player()
	var hold := player.global_position + _facing(player) * 1.15
	var lifted := _hold_mode == "push" and (not player.is_on_floor() or player.velocity.y > 0.4)
	if current_upper().has_ability("lift_jump", breakthrough) and lifted:
		hold.y = player.global_position.y + 1.15
	elif _hold_mode == "throw":
		hold = player.global_position + Vector3(0.0, 1.2, 0.0)
	else:
		hold.y = player.global_position.y + 0.02
	var follow := 1.0 - exp(-14.0 * delta)
	_held.global_position = _held.global_position.lerp(hold, follow)


func _apply_flight(player: PlayerController, delta: float) -> void:
	var grounded := player.is_on_floor()
	if not _flying and Input.is_action_just_pressed("air_action") and (grounded or _coyote > 0.0):
		_flying = true
		player.velocity.y = 3.2
		return
	if _flying:
		var target := 4.0 if Input.is_action_pressed("air_action") else -3.2
		player.velocity.y = move_toward(player.velocity.y, target, 14.0 * delta)
		if grounded and player.velocity.y <= 0.0:
			_flying = false
			player.velocity.y = 0.0
		return
	if not grounded:
		player.velocity.y -= 18.0 * delta
	else:
		player.velocity.y = 0.0


func _apply_swim_vertical(player: PlayerController, delta: float) -> bool:
	if not _tags().has("fluid"):
		return false
	if _tags().has("ocean"):
		var lower := current_lower().id
		if lower == "goose_foot":
			var surface_y := SceneProbe.water_surface_y(player.global_position)
			if surface_y > -INF:
				player.velocity.y = clampf((surface_y - player.global_position.y) * 12.0, -3.0, 5.0)
			return true
		if lower in ["fish_tail", "water_snake", "octopus_leg"]:
			var vertical := (1.0 if Input.is_action_pressed("air_action") else 0.0) \
				- (1.0 if Input.is_physical_key_pressed(KEY_CTRL) else 0.0)
			var effects := SceneMechanism.effects_at(player.global_position)
			player.velocity.y = vertical * TerrainMovementRules.speed(lower, "ocean") + effects.drift.y
			player.set_meta("scene_oxygen", minf(100.0,
				float(player.get_meta("scene_oxygen", 100.0)) + effects.oxygen * delta))
			return true
	match current_lower().swim:
		"hover_fast", "skim":
			player.velocity.y = move_toward(player.velocity.y, 0.0, 22.0 * delta)
			return true
		"sink":
			var moving := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.1
			var target := 0.0 if moving else -1.8
			player.velocity.y = move_toward(player.velocity.y, target, 8.0 * delta)
			return true
		_:
			return false


func _try_jump(player: PlayerController, on_floor: bool) -> bool:
	if jump_count() <= 0 or current_upper().air_mode == "flight":
		return false
	var ground_jump := _jump_buffer > 0.0 and _coyote > 0.0
	var air_jump := _jump_buffer > 0.0 and not on_floor and _coyote <= 0.0 and _jumps_left > 0 and jump_count() > 1
	if not ground_jump and not air_jump:
		return false
	player.velocity.y = 7.4
	_jump_buffer = 0.0
	_coyote = 0.0
	if ground_jump:
		_jumps_left = jump_count() - 1
	else:
		_jumps_left -= 1
	return true


func _swim_controls_air() -> bool:
	var swim := current_lower().swim
	return swim == "hover_fast" or swim == "skim" or swim == "sink" \
		or (_tags().has("ocean") and swim == "fluid_and_hard")


func _begin_dive(player: PlayerController, enemy: AffordanceProp) -> void:
	_diving = true
	_dive_hit.clear()
	if enemy:
		_dive_point = enemy.global_position
	else:
		_dive_point = player.global_position + _facing(player) * 4.0 + Vector3.DOWN * 3.0
	note.emit("俯冲")


func _tick_dive(player: PlayerController) -> void:
	var to := _dive_point - player.global_position
	if to.length() < 0.45:
		player.velocity = Vector3.ZERO
		return
	player.velocity = to.normalized() * 13.0
	for prop in SceneProbe.each_kind(ENEMY_KINDS):
		if _dive_hit.has(prop):
			continue
		if player.global_position.distance_to(prop.global_position) > 1.25:
			continue
		_dive_hit.append(prop)
		prop.take_hit(PartDefinition.power_value(current_upper().attack_power))


func sync_movement() -> void:
	var player := _player()
	if player == null:
		return
	var assembly := player.get_node_or_null("Assembly") as CharacterAssemblyController
	if assembly:
		assembly.apply_part_movement(_displayed_upper_id(), _displayed_lower_id())


func _displayed_lower_id() -> String:
	var player := _player()
	if player == null:
		return current_lower().id
	var bag := player.get_node_or_null("LimbBag") as LimbBag
	if bag != null and not bag.equipped_lower.is_empty():
		return bag.equipped_lower
	return current_lower().id


func _displayed_upper_id() -> String:
	var player := _player()
	if player == null:
		return current_upper().id
	var bag := player.get_node_or_null("LimbBag") as LimbBag
	if bag != null and not bag.equipped_upper.is_empty():
		return bag.equipped_upper
	return current_upper().id


func _attack_channel(limb_id: String) -> StringName:
	match limb_id:
		"gorilla_arm":
			return &"anim_arm"
		"gibbon_arm", "gerbil_paw":
			return &"hop_arm"
		"octopus_arm":
			return &"crawl"
		"goose_wing", "bat_wing", "albatross_wing", "eagle_wing":
			return &"wings"
		"mantis_arm", "mantis_blade", "mantis_king":
			return &"scythe"
		_:
			return &"anim_arm"


func _lock_attack_target(player: PlayerController) -> AffordanceProp:
	return SceneProbe.nearest(player.global_position, ATTACK_RANGE, ATTACK_KINDS)


func _slam(player: PlayerController) -> void:
	if player == null:
		return
	var power := maxi(PartDefinition.power_value(current_upper().attack_power), 10)
	for prop in SceneProbe.each_kind(ENEMY_KINDS):
		if player.global_position.distance_to(prop.global_position) <= 2.7:
			prop.take_hit(power)
	attacked.emit(true)


func _spawn_hurricane(player: PlayerController, power: int) -> void:
	var enemy := SceneProbe.nearest(player.global_position, 8.0, PackedStringArray(["enemy_small"]))
	var at := enemy.global_position if enemy else player.global_position + _facing(player) * 2.0
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.2, 0.12, 3.2)
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 1, 1, 0.55)
	mesh.material_override = material
	player.get_parent().add_child(mesh)
	mesh.global_position = at + Vector3.UP * 0.4
	_rings.append({"mesh": mesh, "life": 1.35, "tick": 0.0, "power": maxi(power / 2, 4), "at": at})
	note.emit("小飓风")


func _tick_rings(delta: float) -> void:
	for index in range(_rings.size() - 1, -1, -1):
		var ring: Dictionary = _rings[index]
		ring["life"] = float(ring["life"]) - delta
		ring["tick"] = float(ring["tick"]) - delta
		var at: Vector3 = ring["at"]
		for prop in SceneProbe.each_kind(PackedStringArray(["enemy_small"])):
			var to := at - prop.global_position
			to.y = 0.0
			if to.length() > 4.2 or to.length() < 0.15:
				continue
			prop.global_position += to.normalized() * minf(to.length(), 3.2 * delta)
			if float(ring["tick"]) <= 0.0:
				prop.take_hit(int(ring["power"]))
		if float(ring["tick"]) <= 0.0:
			ring["tick"] = 0.35
		_rings[index] = ring
		if float(ring["life"]) <= 0.0:
			var mesh := ring["mesh"] as Node
			if mesh:
				mesh.queue_free()
			_rings.remove_at(index)


func _facing(player: PlayerController) -> Vector3:
	if player == null:
		return Vector3(0.0, 0.0, -1.0)
	var velocity := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if velocity.length_squared() > 0.16:
		return velocity.normalized()
	return player.camera_planar_axes()[1]


func _tags() -> PackedStringArray:
	var player := _player()
	if player == null:
		return PackedStringArray(["hard"])
	return SceneProbe.tags_at(player.global_position)


func _player() -> PlayerController:
	return get_parent() as PlayerController


func _index_of(parts: Array[PartDefinition], part_id: String) -> int:
	for index in parts.size():
		if parts[index].id == part_id:
			return index
	return 0


func _tags_overlap(allowed: PackedStringArray, tags: PackedStringArray) -> bool:
	for tag in allowed:
		if tags.has(tag):
			return true
	return false


func _tag_blocked(blocked: PackedStringArray, tags: PackedStringArray) -> bool:
	for tag in blocked:
		if tags.has(tag):
			return true
	return false
