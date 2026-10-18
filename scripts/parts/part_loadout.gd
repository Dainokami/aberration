class_name PartLoadout
extends Node

const MovementConfig := preload("res://scripts/movement_table.gd")

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
var _auto_arm := 0.0
var _rings: Array[Dictionary] = []
var _limb_part_cache: Dictionary = {}


func handles_attack() -> bool:
	return true


func overrides_horizontal() -> bool:
	var player := _player()
	var assembly := player.get_node_or_null("Assembly") as CharacterAssemblyController if player != null else null
	if assembly == null:
		return true
	var mode := assembly.resolve_locomotion()
	# 没有下肢时交给 Assembly 的头滚/单臂跳/双臂支撑速度曲线。
	return mode not in [
		CharacterAssemblyController.LocomotionMode.HEAD_ROLL,
		CharacterAssemblyController.LocomotionMode.SINGLE_ARM_HOP,
		CharacterAssemblyController.LocomotionMode.DOUBLE_ARM_WALK,
	]


func current_upper() -> PartDefinition:
	var bag := _limb_bag()
	if bag != null and not bag.equipped_upper.is_empty():
		return _part_for_limb(bag.equipped_upper, PartDefinition.Slot.UPPER)
	return PartCatalog.uppers()[upper_index]


func current_lower() -> PartDefinition:
	var bag := _limb_bag()
	if bag != null and not bag.equipped_lower.is_empty():
		return _part_for_limb(bag.equipped_lower, PartDefinition.Slot.LOWER)
	return PartCatalog.lowers()[lower_index]


func _limb_bag() -> LimbBag:
	var player := _player()
	return player.get_node_or_null("LimbBag") as LimbBag if player != null else null


func _part_for_limb(limb_id: String, slot: PartDefinition.Slot) -> PartDefinition:
	var key := "%d:%s" % [slot, limb_id]
	if _limb_part_cache.has(key):
		return _limb_part_cache[key] as PartDefinition
	# 地图拾取与 Z/X 调试共用 PartCatalog，装入背包后不能丢失原能力。
	var catalog_part := PartCatalog.find(limb_id)
	if catalog_part != null and catalog_part.slot == slot:
		_limb_part_cache[key] = catalog_part
		return catalog_part
	var part := PartDefinition.new()
	part.id = limb_id
	part.slot = slot
	if limb_id.is_empty():
		part.display_name = "无"
		part.blurb = "该槽位没有肢体"
		_limb_part_cache[key] = part
		return part
	var limb := LimbCatalog.find(limb_id)
	part.display_name = limb.display_name if limb != null else limb_id
	part.blurb = limb.blurb if limb != null else ""
	if limb != null:
		part.rank = clampi(limb.tier - 1, PartDefinition.Rank.R1, PartDefinition.Rank.R3)
		if slot == PartDefinition.Slot.UPPER and limb.visual == "scythe":
			part.attack_shape = PartDefinition.AttackShape.FACING
			part.attack_power = PartDefinition.Band.NORMAL if limb.tier <= 1 else PartDefinition.Band.HIGH
			part.attack_rate = PartDefinition.Band.NORMAL if not limb.rare else PartDefinition.Band.HIGH
	_limb_part_cache[key] = part
	return part


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
	if upper.has_ability("grab_climb", breakthrough):
		return true
	return _swim_controls_air()


func speed_on(tags: PackedStringArray) -> float:
	var lower := current_lower()
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
		return MovementConfig.band("unspecified", UNSPECIFIED_SPEED)
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
		var input := player.read_move_input()
		return _climb_tangent(player) * input.x * MovementConfig.number("part", "climb_strafe_speed", 3.2)
	if _diving:
		var flat := _dive_point - player.global_position
		flat.y = 0.0
		if flat.length() > 0.35:
			return flat.normalized() * 12.0
		return Vector3.ZERO
	var assembly := player.get_node_or_null("Assembly") as CharacterAssemblyController
	var mode := assembly.resolve_locomotion() if assembly != null else CharacterAssemblyController.LocomotionMode.BIPED_WALK
	var tentacle_crawl := mode == CharacterAssemblyController.LocomotionMode.TENTACLE_CRAWL
	var drive := 1.0
	if tentacle_crawl:
		drive = assembly.get_drive_multiplier()
	elif mode == CharacterAssemblyController.LocomotionMode.BIPED_WALK:
		drive = _biped_drive(assembly)
	var target := wish * speed_on(_tags()) * drive * player.hazard_speed_scale()
	var moving := wish.length_squared() > 0.01
	var accel := MovementConfig.number("part", "acceleration", 34.0) if moving else MovementConfig.number("part", "deceleration", 40.0)
	if tentacle_crawl:
		accel *= assembly.get_acceleration_multiplier() if moving else assembly.get_deceleration_multiplier()
	elif mode == CharacterAssemblyController.LocomotionMode.BIPED_WALK:
		accel *= _biped_response(moving)
	if is_burrowed():
		accel *= 0.75
	if not player.is_on_floor() and not _flying and not _stuck:
		accel *= MovementConfig.number("body", "air_control", 0.55)
	return current.move_toward(target, accel * delta)


func apply_vertical(player: PlayerController, delta: float) -> void:
	var upper := current_upper()
	var on_floor := player.is_on_floor() and not _climbing and not _stuck and not _flying and not _diving
	if on_floor and player.velocity.y <= 0.2:
		_jumps_left = jump_count()
		_glide_left = 0.0
		_glide_armed = false
	if Input.is_action_just_pressed("air_action"):
		_jump_buffer = MovementConfig.number("part", "jump_buffer_time", 0.12)
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if on_floor:
		_coyote = MovementConfig.number("part", "coyote_time", 0.12)
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	if not _climbing and _try_grab_on_jump(player):
		return

	if _climbing:
		if _climb_target == null:
			_climbing = false
			return
		if _climb_target.ledge_height >= 0.0 and player.global_position.y >= _climb_target.ledge_height - 0.2:
			var landed := _climb_target.ledge_point
			_climbing = false
			_climb_target = null
			player.global_position = landed
			player.velocity = Vector3.ZERO
			note.emit("爬上去了")
			return
		var climb := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		player.velocity.y = climb * MovementConfig.number("part", "climb_vertical_speed", 3.4)
		var base_y := _climb_target.global_position.y - 1.0
		if player.global_position.y <= base_y and player.velocity.y < 0.0:
			player.velocity.y = 0.0
		return
	if _diving:
		_tick_dive(player)
		return
	if _stuck:
		player.velocity.y = move_toward(player.velocity.y, 0.0, MovementConfig.number("part", "stuck_deceleration", 24.0) * delta)
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
		var target := -MovementConfig.number("part", "hover_fall_speed", 2.6) if descending else 0.0
		player.velocity.y = move_toward(player.velocity.y, target, MovementConfig.number("part", "hover_acceleration", 16.0) * delta)
		return
	if not on_floor and upper.air_mode == "glide":
		if not _glide_armed:
			_glide_armed = true
			_glide_left = 0.85
		if _glide_left > 0.0:
			_glide_left -= delta
			player.velocity.y = move_toward(player.velocity.y, -MovementConfig.number("part", "glide_fall_speed", 1.25), MovementConfig.number("part", "glide_acceleration", 18.0) * delta)
			return
	if not player.is_on_floor():
		player.velocity.y -= MovementConfig.number("part", "gravity", 18.0) * delta
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
	_maintain_climb()
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if _swing > 0.0:
		_swing = maxf(_swing - delta, 0.0)
		if _swing == 0.0 and _slam_queued:
			_slam_queued = false
			_slam(_player())
	_watch_landing()
	_auto_combat()
	_follow_held(delta)
	_tick_rings(delta)


func try_attack() -> void:
	var player := _player()
	if player == null or _attack_cooldown > 0.0:
		return
	var upper := current_upper()
	if _flying and upper.has_ability("dive", breakthrough):
		var enemy := SceneProbe.nearest_reachable(player, 9.0, ENEMY_KINDS)
		_begin_dive(player, enemy)
		return
	if upper.attack_shape == PartDefinition.AttackShape.NONE:
		note.emit("这个部件没有攻击")
		return
	var power := PartDefinition.power_value(upper.attack_power)
	_attack_cooldown = PartDefinition.cooldown_for(upper.attack_rate)
	_swing = 0.24
	var target := _lock_attack_target(player)
	var rig := player.get_node_or_null("ArtRoot/PartSockets") as ModularCharacterRig
	if target == null:
		if rig:
			rig.aim_attack(Vector3.ZERO)
		note.emit("附近没有可攻击的对象")
	else:
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
	var upper := current_upper()
	var lower := current_lower()
	if upper.has_ability("grab_climb", breakthrough):
		var pillar := SceneProbe.nearest_reachable(player, 1.9, PackedStringArray(["climbable"]))
		if pillar:
			_attach_climb(player, pillar)
			return
	if upper.has_ability("grab_throw", breakthrough):
		if _try_throw_grab(origin):
			return
	if upper.has_ability("push_pull", breakthrough):
		var box := SceneProbe.nearest_reachable(player, 1.9, PackedStringArray(["pushable"]))
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
		var hard := SceneProbe.nearest_reachable(player, 2.1, PackedStringArray(["destructible_hard"]))
		if hard:
			var destroyed := hard.take_hit(PartDefinition.power_value(upper.attack_power))
			note.emit("砸碎了" if destroyed else "砸了一下")
			return
	if upper.has_ability("dig_soft", breakthrough) and _tags().has("fluid"):
		var soft := SceneProbe.nearest_reachable(player, 2.1, PackedStringArray(["destructible_soft"]))
		if soft:
			var dug := soft.take_hit(PartDefinition.power_value(upper.attack_power) + 6)
			note.emit("挖开了" if dug else "挖了一下")
			return
	if lower.has_ability("smash_near", breakthrough):
		var nearby := SceneProbe.nearest_reachable(player, 2.1, PackedStringArray(["destructible_hard", "destructible_soft"]))
		if nearby:
			var smashed := nearby.take_hit(10)
			note.emit("震碎了" if smashed else "震击了一下")
			return
	note.emit("附近没有这个部件能用的东西")


func _climb_outward() -> Vector3:
	if _climb_target == null:
		return Vector3.BACK
	var outward := _climb_target.global_position - _climb_target.ledge_point
	outward.y = 0.0
	if outward.length_squared() < 0.0001:
		outward = Vector3.BACK
	return outward.normalized()


func _climb_tangent(player: PlayerController) -> Vector3:
	var tangent := _climb_outward().cross(Vector3.UP)
	if tangent.length_squared() < 0.0001:
		return player.camera_planar_axes()[0]
	tangent = tangent.normalized()
	if tangent.dot(player.camera_planar_axes()[0]) < 0.0:
		tangent = -tangent
	return tangent


func _maintain_climb() -> void:
	var player := _player()
	if player == null or not _climbing or _climb_target == null or not is_instance_valid(_climb_target):
		return
	_retarget_climb(player)
	var outward := _climb_outward()
	var marker := _climb_target.global_position
	var along := player.global_position - marker
	along -= outward * along.dot(outward)
	along.y = 0.0
	var stuck := marker + outward * 0.95 + along
	stuck.y = maxf(player.global_position.y, marker.y - 1.0)
	player.global_position = stuck


func _retarget_climb(player: PlayerController) -> void:
	var outward := _climb_outward()
	var best := _climb_target
	var best_distance := _climb_planar_distance(player.global_position, best.global_position)
	for node in player.get_tree().get_nodes_in_group("affordance"):
		if not node is AffordanceProp or node == _climb_target:
			continue
		var marker := node as AffordanceProp
		if marker.kind != "climbable":
			continue
		var other := marker.global_position - marker.ledge_point
		other.y = 0.0
		if other.length_squared() < 0.0001 or other.normalized().dot(outward) < 0.99:
			continue
		var distance := _climb_planar_distance(player.global_position, marker.global_position)
		if distance + 0.15 < best_distance:
			best_distance = distance
			best = marker
	_climb_target = best


func _climb_planar_distance(a: Vector3, b: Vector3) -> float:
	a.y = 0.0
	b.y = 0.0
	return a.distance_to(b)


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
	note.emit("抓住了，W 上 S 下 A 左 D 右，再按 G 松开")


func _try_throw_grab(origin: Vector3) -> bool:
	var player := _player()
	if player == null:
		return false
	var kinds := PackedStringArray(["enemy_small", "pushable", "grabbable"])
	var target := SceneProbe.nearest_reachable(player, 2.2, kinds)
	var elite := SceneProbe.nearest_reachable(player, 2.2, PackedStringArray(["enemy_elite"]))
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


func _auto_combat() -> void:
	var delta := get_physics_process_delta_time()
	if _auto_timer > 0.0:
		_auto_timer -= delta
		return
	var player := _player()
	if player == null:
		return
	var upper := current_upper()
	var lower := current_lower()
	var smash: AffordanceProp = null
	var smash_kind := ""
	if upper.has_ability("smash_hard", breakthrough):
		smash = SceneProbe.nearest_reachable(player, 2.1, PackedStringArray(["destructible_hard"]))
		smash_kind = "hard"
	if smash == null and lower.has_ability("smash_near", breakthrough):
		smash = SceneProbe.nearest_reachable(player, 2.1, PackedStringArray(["destructible_hard", "destructible_soft"]))
		smash_kind = "near"
	var ambush: AffordanceProp = null
	if is_burrowed() and upper.has_ability("burrow_ambush", breakthrough):
		ambush = SceneProbe.nearest_reachable(player, 1.55, ENEMY_KINDS)
	if smash == null and ambush == null:
		_auto_arm = 0.0
		return
	_auto_arm += delta
	if _auto_arm < 0.3:
		return
	_auto_arm = 0.0
	_auto_timer = 0.45
	if smash != null and smash_kind == "hard":
		var destroyed := smash.take_hit(PartDefinition.power_value(upper.attack_power))
		note.emit("砸碎了" if destroyed else "砸了一下")
		return
	if smash != null:
		var smashed := smash.take_hit(10)
		note.emit("震碎了" if smashed else "震击了一下")
		return
	var ambushed := ambush.take_hit(PartDefinition.power_value(upper.attack_power) + 6)
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
		player.velocity.y = MovementConfig.number("part", "flight_launch_speed", 3.2)
		return
	if _flying:
		var target := MovementConfig.number("part", "flight_climb_speed", 4.0) if Input.is_action_pressed("air_action") else -MovementConfig.number("part", "flight_fall_speed", 3.2)
		player.velocity.y = move_toward(player.velocity.y, target, MovementConfig.number("part", "flight_acceleration", 14.0) * delta)
		if grounded and player.velocity.y <= 0.0:
			_flying = false
			player.velocity.y = 0.0
		return
	if not grounded:
		player.velocity.y -= MovementConfig.number("part", "gravity", 18.0) * delta
	else:
		player.velocity.y = 0.0


func _apply_swim_vertical(player: PlayerController, delta: float) -> bool:
	if not _tags().has("fluid"):
		return false
	match current_lower().swim:
		"hover_fast", "skim":
			player.velocity.y = move_toward(player.velocity.y, 0.0, MovementConfig.number("part", "swim_skim_acceleration", 22.0) * delta)
			return true
		"sink":
			var moving := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.1
			var target := 0.0 if moving else -MovementConfig.number("part", "swim_sink_speed", 1.8)
			player.velocity.y = move_toward(player.velocity.y, target, MovementConfig.number("part", "swim_acceleration", 8.0) * delta)
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
	player.velocity.y = MovementConfig.number("part", "jump_speed", 7.4)
	_jump_buffer = 0.0
	_coyote = 0.0
	if ground_jump:
		_jumps_left = jump_count() - 1
	else:
		_jumps_left -= 1
	return true


func _swim_controls_air() -> bool:
	var swim := current_lower().swim
	return swim == "hover_fast" or swim == "skim" or swim == "sink"


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
		# 目标可能在半空或已消失；到点后必须退出俯冲，让重力和落地结算接管。
		_diving = false
		_flying = false
		player.velocity = Vector3.DOWN * 1.5
		return
	player.velocity = to.normalized() * 13.0
	for prop in SceneProbe.each_kind(ENEMY_KINDS):
		if _dive_hit.has(prop):
			continue
		if player.global_position.distance_to(prop.global_position) > 1.25:
			continue
		if not SceneProbe.is_reachable(player, prop):
			continue
		_dive_hit.append(prop)
		prop.take_hit(PartDefinition.power_value(current_upper().attack_power))


func _biped_drive(assembly: CharacterAssemblyController) -> float:
	var phase := assembly.get_locomotion_phase()
	match current_lower().id:
		"kangaroo_leg":
			# 双腿一起蹬地，腾空时才有推进，平均速度仍接近原档位。
			return 0.72 + maxf(sin(phase), 0.0) * 0.88
		"ostrich_leg":
			return 0.92 + absf(sin(phase * 2.0)) * 0.16
		"goose_foot":
			return 0.86 + absf(sin(phase)) * 0.22
		"gerbil_leg":
			return 0.9 + absf(sin(phase * 2.0)) * 0.2
		"demon_dog_leg":
			return 0.94
		_:
			return 1.0


func _biped_response(moving: bool) -> float:
	match current_lower().id:
		"ostrich_leg":
			return 1.25 if moving else 1.05
		"kangaroo_leg":
			return 0.85 if moving else 1.15
		"demon_dog_leg":
			return 0.7
		"goose_foot":
			return 0.8
		"gerbil_leg":
			return 1.15 if moving else 1.3
		_:
			return 1.0


func sync_movement() -> void:
	var player := _player()
	if player == null:
		return
	var assembly := player.get_node_or_null("Assembly") as CharacterAssemblyController
	if assembly:
		assembly.apply_part_movement(_displayed_upper_id(), _displayed_lower_id())


func _displayed_lower_id() -> String:
	return current_lower().id


func _displayed_upper_id() -> String:
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
	var facing := _facing(player)
	var around := current_upper().attack_shape == PartDefinition.AttackShape.AROUND
	var best: AffordanceProp = null
	var best_distance := ATTACK_RANGE
	for prop in SceneProbe.each_kind(ATTACK_KINDS):
		var offset := prop.interaction_point() - player.global_position
		var distance := offset.length()
		if distance > best_distance:
			continue
		if not around:
			var flat := Vector3(offset.x, 0.0, offset.z)
			if flat.length_squared() > 0.0001 and flat.normalized().dot(facing) < 0.0:
				continue
		if not SceneProbe.is_reachable(player, prop):
			continue
		best_distance = distance
		best = prop
	return best


func _try_grab_on_jump(player: PlayerController) -> bool:
	if not Input.is_action_just_pressed("air_action"):
		return false
	if not current_upper().has_ability("grab_climb", breakthrough):
		return false
	var pillar := SceneProbe.nearest_reachable(player, 1.9, PackedStringArray(["climbable"]))
	if pillar == null:
		return false
	_jump_buffer = 0.0
	_attach_climb(player, pillar)
	return true


func _slam(player: PlayerController) -> void:
	if player == null:
		return
	var power := maxi(PartDefinition.power_value(current_upper().attack_power), 10)
	for prop in SceneProbe.each_kind(ENEMY_KINDS):
		if player.global_position.distance_to(prop.global_position) <= 2.7 \
				and SceneProbe.is_reachable(player, prop):
			prop.take_hit(power)
	attacked.emit(true)


func _spawn_hurricane(player: PlayerController, power: int) -> void:
	var enemy := SceneProbe.nearest_reachable(player, 8.0, PackedStringArray(["enemy_small"]))
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
