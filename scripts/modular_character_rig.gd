class_name ModularCharacterRig
extends Node3D

const PIXEL := 0.0043
const ANCHOR := Vector2(515.0, 536.0)
# 新拆分稿是 1850 宽的立绘。按参考画面把角色身高收到大约 2.2 米，和关卡里的人物比例接近。
const ANIM_PIXEL := 0.0022
const ANIM_NECK := Vector2(1064.14, 718.11)
const ANIM_LOWEST_Y := 1117.0

const HEAD_TEXTURE := preload("res://art/characters/psd/head.png")
const TORSO_TEXTURE := preload("res://art/characters/psd/torso.png")
const LEFT_ARM_TEXTURE := preload("res://art/characters/psd/arm_left.png")
const RIGHT_ARM_TEXTURE := preload("res://art/characters/psd/arm_right.png")
const LEFT_LEG_TEXTURE := preload("res://art/characters/psd/leg_left.png")
const RIGHT_LEG_TEXTURE := preload("res://art/characters/psd/leg_right.png")
const WING_LEFT_TEXTURE := preload("res://art/characters/psd/wing_left.png")
const WING_RIGHT_TEXTURE := preload("res://art/characters/psd/wing_right.png")
const LEG_TEXTURE := preload("res://art/characters/psd/leg_left.png")
const HOP_ARM_TEXTURE := preload("res://art/characters/psd/arm_hop.png")
const CRAWL_LEFT_TEXTURE := preload("res://art/characters/psd/arm_crawl_gorilla.png")
const CRAWL_RIGHT_TEXTURE := preload("res://art/characters/psd/arm_crawl_pirate.png")
const SNAKE_BODY_TEXTURE := preload("res://art/characters/psd/snake_body.png")
const SNAKE_LEFT_TEXTURE := preload("res://art/characters/psd/arm_snake_gorilla.png")
const SNAKE_RIGHT_TEXTURE := preload("res://art/characters/psd/arm_snake_pirate.png")
const ANIM_HEAD := preload("res://art/characters/anim/head.png")
const ANIM_EAR := preload("res://art/characters/anim/ear.png")
const ANIM_HOOD := preload("res://art/characters/anim/hood.png")
const ANIM_BANDAGE := preload("res://art/characters/anim/bandage.png")
const ANIM_TAIL := preload("res://art/characters/anim/tail.png")
const ANIM_ARM_UPPER := preload("res://art/characters/anim/arm_upper.png")
const ANIM_ARM_FORE := preload("res://art/characters/anim/arm_fore.png")
const ANIM_SCYTHE_GRIP := preload("res://art/characters/anim/scythe_grip.png")
const ANIM_SCYTHE_SHAFT := preload("res://art/characters/anim/scythe_shaft.png")
const ANIM_SCYTHE_BLADE := preload("res://art/characters/anim/scythe_blade.png")

# PSD 画布上的紧裁切框。拆分形态按这些框放回同一身体锚点，静止时和源文件重合。
const HOP_BOUNDS := Rect2(487, 516, 76, 145)
const CRAWL_LEFT_BOUNDS := Rect2(233, 495, 278, 243)
const CRAWL_RIGHT_BOUNDS := Rect2(551, 489, 83, 271)
const SNAKE_BODY_BOUNDS := Rect2(413, 466, 434, 282)
const SNAKE_LEFT_BOUNDS := Rect2(231, 276, 253, 290)
const SNAKE_RIGHT_BOUNDS := Rect2(566, 385, 153, 181)
const SNAKE_NECK := Vector2(524.0, 490.0)

@onready var assembly: CharacterAssemblyController = get_node("../../Assembly")
@onready var player: PlayerController = get_node("../..")

var _skeleton: Skeleton3D
var _bones: Dictionary = {}
var _base_positions: Dictionary = {}
var _attachments: Dictionary = {}
var _sprites: Dictionary = {}
var _anim_sockets: Array[String] = []
const HEAD_ROLL_RADIUS := 0.636

var _horizontal_speed := 0.0
var _slide_right := 0.0
var _slide_forward := 0.0
var _head_roll_angle := 0.0
var _roll_sign := 0.0
var _sprite_rest_position: Dictionary = {}
var _grounded := true
var _vertical_speed := 0.0
var _screen_direction := 1.0
var _wing_phase := 0.0
var _attack_time := 0.0
var _attack_channel: StringName = &""
var _air_blend := 0.0
var _snake_mirror := false


func _ready() -> void:
	_build_skeleton()
	assembly.loadout_changed.connect(_apply_loadout)
	assembly.attack_started.connect(_on_attack_started)
	_apply_loadout()
	# 相机是 2.5D 固定视角，只在初始化时对齐一次；不能每帧重置角色的滚动姿态。
	call_deferred("_face_camera_once")


func _process(delta: float) -> void:
	_wing_phase += delta
	_attack_time = maxf(_attack_time - delta, 0.0)
	# 起飞后很快收起地面步态，落地再接回，避免腿在半空停在迈步中间。
	var air_target := 1.0 if player.is_flying() else 0.0
	_air_blend = move_toward(_air_blend, air_target, delta * 5.0)
	_reset_pose()
	_animate_locomotion()
	_animate_wings()
	_animate_attack()


func set_motion_state(horizontal_velocity: Vector3, grounded: bool, vertical_speed: float, screen_direction: float, delta: float) -> void:
	_horizontal_speed = horizontal_velocity.length()
	_grounded = grounded
	_vertical_speed = vertical_speed
	_slide_right = 0.0
	_slide_forward = 0.0
	if horizontal_velocity.length_squared() > 0.0001:
		var axes := _planar_axes()
		_slide_right = axes[0].dot(horizontal_velocity)
		_slide_forward = axes[1].dot(horizontal_velocity)
	# 和物理帧对齐。右移逆时针，远离镜头顺时针。对角时沿用来向，避免两个分量抵消后只滑不转。
	if assembly.resolve_locomotion() == CharacterAssemblyController.LocomotionMode.HEAD_ROLL:
		var speed := Vector2(_slide_right, _slide_forward).length()
		var turn := _slide_right - _slide_forward
		if absf(turn) > 0.45:
			_roll_sign = signf(turn)
		elif speed > 0.2 and _roll_sign == 0.0:
			_roll_sign = signf(_slide_right if absf(_slide_right) >= absf(_slide_forward) else -_slide_forward)
		if speed > 0.05 and _roll_sign != 0.0:
			_head_roll_angle += _roll_sign * speed * delta / HEAD_ROLL_RADIUS
	if absf(screen_direction) > 0.05:
		_screen_direction = signf(screen_direction)


func _build_skeleton() -> void:
	_skeleton = Skeleton3D.new()
	_skeleton.name = "RuntimeSkeleton"
	add_child(_skeleton)

	# root 是地面原点；所有部件均以关节为锚点向外延伸。
	# 相邻贴图在接缝处保留约 3~6 像素重叠，避免缩放或抗锯齿产生白缝。
	_add_bone("root", "", Vector3.ZERO)
	_add_bone("body", "root", Vector3(0.0, 0.92, 0.0))
	# PSD 坐标换算：身体锚点为 (515,536)，头部旋转枢轴在颈根 (515,500)。
	_add_bone("head", "body", Vector3(0.0, 0.155, 0.0))
	_add_bone("left_arm", "body", Vector3(-0.138, 0.219, 0.0))
	_add_bone("right_arm", "body", Vector3(0.125, 0.219, 0.0))
	_add_bone("left_leg", "body", Vector3(-0.188, -0.082, 0.0))
	_add_bone("right_leg", "body", Vector3(0.121, -0.120, 0.0))
	_add_bone("quad_front_left", "body", Vector3(-0.35, -0.30, 0.015))
	_add_bone("quad_front_right", "body", Vector3(0.35, -0.30, 0.015))
	_add_bone("quad_back_left", "body", Vector3(-0.14, -0.30, -0.015))
	_add_bone("quad_back_right", "body", Vector3(0.14, -0.30, -0.015))
	_add_bone("hop_arm", "body", Vector3.ZERO)
	_add_bone("crawl_left", "body", Vector3.ZERO)
	_add_bone("crawl_right", "body", Vector3.ZERO)
	_add_bone("snake_body", "body", Vector3.ZERO)
	_add_bone("snake_arm_left", "body", Vector3.ZERO)
	_add_bone("snake_arm_right", "body", Vector3.ZERO)
	_add_bone("left_wing", "body", Vector3(-0.142, 0.275, -0.04))
	_add_bone("right_wing", "body", Vector3(0.228, 0.275, -0.04))

	# 这些局部坐标直接对应 PSD 中的可见轮廓，不再按占位图的矩形中心猜接缝。
	_attach_sprite("head", "HeadSocket", HEAD_TEXTURE, Vector3(0.041, 0.654, 0.045), PIXEL, 8)
	_attach_sprite("body", "BodySocket", TORSO_TEXTURE, Vector3.ZERO, PIXEL, 6)
	_attach_sprite("left_arm", "LeftHandSocket", LEFT_ARM_TEXTURE, Vector3(-0.273, -0.258, 0.035), PIXEL, 7)
	_attach_sprite("right_arm", "RightHandSocket", RIGHT_ARM_TEXTURE, Vector3(0.273, -0.258, 0.035), PIXEL, 7)
	_attach_sprite("left_leg", "LeftLegSocket", LEFT_LEG_TEXTURE, Vector3(0.014, -0.353, 0.02), PIXEL, 5)
	_attach_sprite("right_leg", "RightLegSocket", RIGHT_LEG_TEXTURE, Vector3(0.127, -0.295, 0.02), PIXEL, 5)
	_attach_sprite("quad_front_left", "QuadFrontLeftSocket", LEG_TEXTURE, Vector3(0.0, -0.21, 0.02), PIXEL, 5, false, 1.15)
	_attach_sprite("quad_front_right", "QuadFrontRightSocket", LEG_TEXTURE, Vector3(0.0, -0.21, 0.02), PIXEL, 5, true, 1.15)
	_attach_sprite("quad_back_left", "QuadBackLeftSocket", LEG_TEXTURE, Vector3(0.0, -0.21, 0.01), PIXEL, 4, false, 1.15)
	_attach_sprite("quad_back_right", "QuadBackRightSocket", LEG_TEXTURE, Vector3(0.0, -0.21, 0.01), PIXEL, 4, true, 1.15)
	_attach_sprite("hop_arm", "HopArmSocket", HOP_ARM_TEXTURE, Vector3.ZERO, PIXEL, 7)
	_attach_sprite("crawl_left", "CrawlLeftSocket", CRAWL_LEFT_TEXTURE, Vector3.ZERO, PIXEL, 7)
	_attach_sprite("crawl_right", "CrawlRightSocket", CRAWL_RIGHT_TEXTURE, Vector3.ZERO, PIXEL, 7)
	_attach_sprite("snake_body", "SnakeBodySocket", SNAKE_BODY_TEXTURE, Vector3.ZERO, PIXEL, 4)
	_attach_sprite("snake_arm_left", "SnakeArmLeftSocket", SNAKE_LEFT_TEXTURE, Vector3.ZERO, PIXEL, 7)
	_attach_sprite("snake_arm_right", "SnakeArmRightSocket", SNAKE_RIGHT_TEXTURE, Vector3.ZERO, PIXEL, 7)
	_attach_sprite("left_wing", "LeftWingSocket", WING_LEFT_TEXTURE, Vector3(-0.434, -0.002, -0.04), PIXEL, 1)
	_attach_sprite("right_wing", "RightWingSocket", WING_RIGHT_TEXTURE, Vector3(0.434, -0.002, -0.04), PIXEL, 1)
	# 单臂的锥尖接在躯干底边，躯干留在头和锥之间。
	_layout_baked_part("hop_arm", "HopArmSocket", HOP_BOUNDS, Vector2(515.0, 592.0), 0.03)
	# 双臂不按 PSD 散开。肩头插进下巴，手和钩垂在头下面，像两条腿直接长进脑袋。
	_plug_part("crawl_left", "CrawlLeftSocket", CRAWL_LEFT_BOUNDS, Vector2(477.0, 511.0), Vector2(508.0, 472.0), 0.02)
	_plug_part("crawl_right", "CrawlRightSocket", CRAWL_RIGHT_BOUNDS, Vector2(592.5, 489.0), Vector2(552.0, 468.0), 0.03)
	_layout_baked_part("snake_body", "SnakeBodySocket", SNAKE_BODY_BOUNDS, SNAKE_NECK, 0.0)
	_layout_baked_part("snake_arm_left", "SnakeArmLeftSocket", SNAKE_LEFT_BOUNDS, _top_center(SNAKE_LEFT_BOUNDS), 0.04)
	_layout_baked_part("snake_arm_right", "SnakeArmRightSocket", SNAKE_RIGHT_BOUNDS, _top_center(SNAKE_RIGHT_BOUNDS), 0.045)
	for socket_name in _sprites:
		_sprite_rest_position[socket_name] = (_sprites[socket_name] as Sprite3D).position
	# 相机看到的是贴图背面，头和躯干再翻一次，脸和胸口的左右才和行进方向一致。
	(_sprites["HeadSocket"] as Sprite3D).flip_h = true
	(_sprites["BodySocket"] as Sprite3D).flip_h = true
	_build_anim_skeleton()


func _anim_delta(point: Vector2, origin: Vector2, depth: float) -> Vector3:
	return Vector3((point.x - origin.x) * ANIM_PIXEL, (origin.y - point.y) * ANIM_PIXEL, depth)


func _bind_anim_sprite(bone_name: String, socket_name: String, texture: Texture2D, pivot: Vector2, center: Vector2, depth: float, priority: int) -> void:
	var placed := _anim_delta(center, pivot, depth)
	_attach_sprite(bone_name, socket_name, texture, placed, ANIM_PIXEL, priority, false)
	_anim_sockets.append(socket_name)
	_sprite_rest_position[socket_name] = placed


func _build_anim_skeleton() -> void:
	# 关节取两张贴图重叠区域的中心，父子关系按原画的连接来。
	var neck := ANIM_NECK
	var ear_joint := Vector2(934.95, 480.59)
	var hood_joint := Vector2(1166.05, 497.49)
	var tail_joint := Vector2(1069.98, 762.50)
	var shoulder := Vector2(1264.18, 739.11)
	var elbow := Vector2(1693.23, 615.27)
	var grip_joint := Vector2(855.99, 648.25)
	var shaft_joint := Vector2(655.97, 271.04)
	var blade_joint := Vector2(378.08, 212.21)
	_add_bone("anim_head", "body", Vector3.ZERO)
	_add_bone("anim_ear", "anim_head", _anim_delta(ear_joint, neck, 0.0))
	_add_bone("anim_hood", "anim_head", _anim_delta(hood_joint, neck, 0.0))
	_add_bone("anim_tail", "body", _anim_delta(tail_joint, neck, 0.0))
	_add_bone("anim_arm_upper", "body", _anim_delta(shoulder, neck, 0.0))
	_add_bone("anim_arm_fore", "anim_arm_upper", _anim_delta(elbow, shoulder, 0.0))
	_add_bone("anim_scythe_grip", "body", _anim_delta(grip_joint, neck, 0.0))
	_add_bone("anim_scythe_shaft", "anim_scythe_grip", _anim_delta(shaft_joint, grip_joint, 0.0))
	_add_bone("anim_scythe_blade", "anim_scythe_shaft", _anim_delta(blade_joint, shaft_joint, 0.0))
	_bind_anim_sprite("body", "AnimBandage", ANIM_BANDAGE, neck, Vector2(1067.0, 746.5), 0.01, 5)
	_bind_anim_sprite("anim_head", "AnimHead", ANIM_HEAD, neck, Vector2(1054.0, 617.0), 0.03, 9)
	_bind_anim_sprite("anim_ear", "AnimEar", ANIM_EAR, ear_joint, Vector2(920.5, 343.5), 0.0, 6)
	_bind_anim_sprite("anim_hood", "AnimHood", ANIM_HOOD, hood_joint, Vector2(1295.0, 468.5), -0.02, 3)
	_bind_anim_sprite("anim_tail", "AnimTail", ANIM_TAIL, tail_joint, Vector2(820.5, 835.5), -0.01, 2)
	_bind_anim_sprite("anim_arm_upper", "AnimArmUpper", ANIM_ARM_UPPER, shoulder, Vector2(1500.0, 672.5), 0.02, 7)
	_bind_anim_sprite("anim_arm_fore", "AnimArmFore", ANIM_ARM_FORE, elbow, Vector2(1655.5, 408.5), 0.03, 8)
	_bind_anim_sprite("anim_scythe_grip", "AnimScytheGrip", ANIM_SCYTHE_GRIP, grip_joint, Vector2(755.5, 488.0), 0.04, 10)
	_bind_anim_sprite("anim_scythe_shaft", "AnimScytheShaft", ANIM_SCYTHE_SHAFT, shaft_joint, Vector2(537.0, 246.5), 0.045, 10)
	_bind_anim_sprite("anim_scythe_blade", "AnimScytheBlade", ANIM_SCYTHE_BLADE, blade_joint, Vector2(203.0, 453.5), 0.05, 10)


func _add_bone(bone_name: String, parent_name: String, rest_position: Vector3) -> void:
	var bone_index := _skeleton.add_bone(bone_name)
	_bones[bone_name] = bone_index
	_base_positions[bone_name] = rest_position
	if not parent_name.is_empty():
		_skeleton.set_bone_parent(bone_index, _bones[parent_name])
	_skeleton.set_bone_rest(bone_index, Transform3D(Basis.IDENTITY, rest_position))
	_skeleton.set_bone_pose_position(bone_index, rest_position)


func _attach_sprite(bone_name: String, socket_name: String, texture: Texture2D, local_position: Vector3, pixel_size: float, priority: int, flip_h := false, scale_y := 1.0) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.name = socket_name
	_skeleton.add_child(attachment)
	attachment.bone_name = bone_name

	var sprite := Sprite3D.new()
	sprite.name = "Art"
	sprite.texture = texture
	sprite.position = local_position
	sprite.pixel_size = pixel_size
	sprite.scale.y = scale_y
	sprite.double_sided = true
	sprite.render_priority = priority
	sprite.flip_h = flip_h
	attachment.add_child(sprite)
	_attachments[socket_name] = attachment
	_sprites[socket_name] = sprite


func _apply_loadout() -> void:
	if _attachments.is_empty():
		return
	for socket_name in [
		"HeadSocket", "BodySocket", "LeftLegSocket", "RightLegSocket",
		"LeftHandSocket", "RightHandSocket",
		"QuadFrontLeftSocket", "QuadFrontRightSocket", "QuadBackLeftSocket", "QuadBackRightSocket",
		"HopArmSocket", "CrawlLeftSocket", "CrawlRightSocket",
		"SnakeBodySocket", "SnakeArmLeftSocket", "SnakeArmRightSocket",
		"LeftWingSocket", "RightWingSocket",
	]:
		_attachments[socket_name].visible = false
	var snake := assembly.resolve_locomotion() == CharacterAssemblyController.LocomotionMode.SNAKE_SLITHER
	var show_arm := assembly.arm_count >= 1
	var show_bug_leg := assembly.arm_count >= 2
	for socket_name in ["AnimHead", "AnimEar", "AnimHood", "AnimBandage"]:
		_attachments[socket_name].visible = true
	_attachments["AnimTail"].visible = snake
	_attachments["AnimArmUpper"].visible = show_arm
	_attachments["AnimArmFore"].visible = show_arm
	for socket_name in ["AnimScytheGrip", "AnimScytheShaft", "AnimScytheBlade"]:
		_attachments[socket_name].visible = show_bug_leg


func _reset_pose() -> void:
	for bone_name in _bones:
		var bone_index: int = _bones[bone_name]
		_skeleton.set_bone_pose_position(bone_index, _base_positions[bone_name])
		_skeleton.set_bone_pose_rotation(bone_index, Quaternion.IDENTITY)


func _animate_locomotion() -> void:
	var amount := clampf(_horizontal_speed / maxf(6.0 * assembly.get_speed_multiplier(), 0.01), 0.0, 1.2)
	var phase := assembly.get_locomotion_phase()
	var moving := amount > 0.025
	# 飞行时推进仍在，但下肢不再循环地面动作。1 表示完全悬空。
	var gait := 1.0 - _air_blend
	_restore_rolled_sprites()

	match assembly.resolve_locomotion():
		CharacterAssemblyController.LocomotionMode.HEAD_ROLL:
			# 本体绕头心滚。耳朵离头心最远，半径按耳朵顶端留出。
			var center := _anim_delta(Vector2(1054.0, 617.0), ANIM_NECK, 0.0)
			_set_bone_position("root", Vector3(0.0, 0.02 + 1.08 - _base_positions["body"].y - center.y, 0.0))
			var turned := Basis(Vector3.FORWARD, _head_roll_angle)
			var body_index: int = _bones["body"]
			_skeleton.set_bone_pose_position(body_index, _base_positions["body"] + center - turned * center)
			_skeleton.set_bone_pose_rotation(body_index, Quaternion(Vector3.FORWARD, _head_roll_angle))

		CharacterAssemblyController.LocomotionMode.SINGLE_ARM_HOP:
			# 猩猩臂是唯一的支撑。起跳抬根，落地时手臂多弯一点。
			var hop := maxf(sin(phase), 0.0) if moving else 0.0
			var compression := maxf(-sin(phase), 0.0) if moving else 0.0
			_set_bone_position("root", Vector3(0.0, _anim_ground(848.0) + hop * 0.42 - compression * 0.045, 0.0))
			_set_bone_rotation("anim_arm_upper", (-compression * 0.45 + hop * 0.25) * amount)
			_set_bone_rotation("anim_arm_fore", (-compression * 0.35 + hop * 0.15) * amount)

		CharacterAssemblyController.LocomotionMode.DOUBLE_ARM_WALK:
			# 猩猩臂和虫子腿交替撑地，身体横着穿过行进方向。
			var support := sin(phase) if moving else 0.0
			var brace := _weave_offset(support * 0.05 * amount)
			_set_bone_position("root", Vector3(brace.x, _anim_ground(848.0) + absf(support) * 0.03 * amount + brace.y, brace.z))
			_set_bone_rotation("anim_arm_upper", support * 0.28 * amount)
			_set_bone_rotation("anim_arm_fore", support * 0.16 * amount)
			_set_bone_rotation("anim_scythe_grip", -support * 0.22 * amount)
			_set_bone_rotation("anim_scythe_shaft", -support * 0.1 * amount)

		CharacterAssemblyController.LocomotionMode.BIPED_WALK, CharacterAssemblyController.LocomotionMode.QUADRUPED_WALK:
			_set_bone_position("root", Vector3(0.0, _anim_ground(848.0), 0.0))

		CharacterAssemblyController.LocomotionMode.SNAKE_SLITHER:
			# 身子横着穿过路线，尾巴比身体晚一拍，波从头部往后传。
			var wave := sin(phase) if moving else 0.0
			var tail_wave := sin(phase - 1.15) if moving else 0.0
			var weave := _weave_offset(wave * 0.22 * amount * gait)
			_set_bone_position("root", Vector3(weave.x, _anim_ground(ANIM_LOWEST_Y) + weave.y, weave.z))
			_set_bone_rotation("body", -wave * 0.16 * amount * gait)
			_set_bone_rotation("anim_tail", tail_wave * 0.55 * amount * gait)
			if assembly.arm_count >= 1:
				_set_bone_rotation("anim_arm_upper", -wave * 0.12 * amount * gait)
				_set_bone_rotation("anim_arm_fore", -wave * 0.08 * amount * gait)
			if assembly.arm_count >= 2:
				_set_bone_rotation("anim_scythe_grip", wave * 0.1 * amount * gait)
	_face_travel()


func _animate_wings() -> void:
	if not assembly.wings_equipped:
		return
	var flying := player.is_flying()
	var rate := 12.0 if flying else 2.6
	var amplitude := deg_to_rad(32.0 if flying else 6.0)
	var flap := sin(_wing_phase * rate) * amplitude
	_set_bone_rotation("left_wing", -flap)
	_set_bone_rotation("right_wing", flap)
	if flying:
		_offset_bone_position("root", Vector3(0.0, sin(_wing_phase * 6.0) * 0.045, 0.0))
		_offset_bone_rotation("root", clampf(-_vertical_speed * 0.018, -0.10, 0.10))


func _animate_attack() -> void:
	if _attack_time <= 0.0:
		return
	var progress := 1.0 - (_attack_time / 0.32)
	var strike := sin(clampf(progress, 0.0, 1.0) * PI)
	if _attack_channel == &"head":
		_offset_bone_position("head", Vector3(0.0, 0.0, 0.22 * strike))
		return
	var mode := assembly.resolve_locomotion()
	if mode == CharacterAssemblyController.LocomotionMode.SINGLE_ARM_HOP:
		_set_bone_rotation("hop_arm", deg_to_rad(-75.0) * strike)
	elif mode == CharacterAssemblyController.LocomotionMode.DOUBLE_ARM_WALK:
		if _attack_channel == &"left_arm":
			_set_bone_rotation("crawl_left", deg_to_rad(-60.0) * strike)
		else:
			_set_bone_rotation("crawl_right", deg_to_rad(60.0) * strike)
	elif mode == CharacterAssemblyController.LocomotionMode.SNAKE_SLITHER:
		if _attack_channel == &"left_arm":
			_set_bone_rotation("snake_arm_left", deg_to_rad(-50.0) * strike)
		else:
			_set_bone_rotation("snake_arm_right", deg_to_rad(50.0) * strike)
	elif _attack_channel == &"left_arm":
		_set_bone_rotation("left_arm", deg_to_rad(-85.0) * strike)
	else:
		_set_bone_rotation("right_arm", deg_to_rad(85.0) * strike)


func _psd_to_body(pixel: Vector2, depth: float) -> Vector3:
	return Vector3((pixel.x - ANCHOR.x) * PIXEL, (ANCHOR.y - pixel.y) * PIXEL, depth)


func _top_center(bounds: Rect2) -> Vector2:
	return Vector2(bounds.get_center().x, bounds.position.y)


func _plug_part(bone_name: String, socket_name: String, bounds: Rect2, art_pivot: Vector2, plug: Vector2, depth: float) -> void:
	# 贴图上的 art_pivot 对齐到 plug，用来把肢体从原 PSD 位置挪到头底下。
	var plug_pos := _psd_to_body(plug, depth)
	_base_positions[bone_name] = plug_pos
	_skeleton.set_bone_rest(_bones[bone_name], Transform3D(Basis.IDENTITY, plug_pos))
	var center := bounds.get_center()
	var sprite: Sprite3D = _sprites[socket_name]
	sprite.position = Vector3((center.x - art_pivot.x) * PIXEL, (art_pivot.y - center.y) * PIXEL, 0.0)


func _layout_baked_part(bone_name: String, socket_name: String, bounds: Rect2, pivot: Vector2, depth: float) -> void:
	var pivot_pos := _psd_to_body(pivot, depth)
	var center_pos := _psd_to_body(bounds.get_center(), depth)
	_base_positions[bone_name] = pivot_pos
	_skeleton.set_bone_rest(_bones[bone_name], Transform3D(Basis.IDENTITY, pivot_pos))
	var sprite: Sprite3D = _sprites[socket_name]
	sprite.position = center_pos - pivot_pos


func _anim_ground(lowest_psd_y: float) -> float:
	return 0.02 - _base_positions["body"].y - (ANIM_NECK.y - lowest_psd_y) * ANIM_PIXEL


func _ground_root(lowest_psd_y: float) -> float:
	# 把指定 PSD 像素的底边放到骨架原点上方一点点。身体骨骼本身在 0.92。
	return 0.02 - _base_positions["body"].y - (ANCHOR.y - lowest_psd_y) * PIXEL


func _restore_rolled_sprites() -> void:
	for socket_name in ["HeadSocket", "LeftWingSocket", "RightWingSocket"]:
		var sprite: Sprite3D = _sprites[socket_name]
		sprite.rotation = Vector3.ZERO
		sprite.position = _sprite_rest_position[socket_name]


func _spin_with_head(socket_name: String, angle: float) -> void:
	var sprite: Sprite3D = _sprites[socket_name]
	var attachment := sprite.get_parent() as BoneAttachment3D
	var bone_origin: Vector3 = _base_positions[attachment.bone_name]
	var rest_in_body: Vector3 = bone_origin + _sprite_rest_position[socket_name]
	var head_center: Vector3 = _base_positions["head"] + _sprite_rest_position["HeadSocket"]
	var spun: Vector3 = head_center + Basis(Vector3.FORWARD, angle) * (rest_in_body - head_center)
	sprite.position = spun - bone_origin
	# 正 Z 旋转和骨骼的 FORWARD（-Z）相反，取负后右移仍是顺时针。
	sprite.rotation = Vector3(0.0, 0.0, -angle)


func _planar_axes() -> Array[Vector3]:
	var camera := get_viewport().get_camera_3d()
	if camera and camera.get_parent() is FollowCameraRig:
		return (camera.get_parent() as FollowCameraRig).get_planar_axes()
	var forward := Vector3(0.0, 0.0, -1.0)
	var right := Vector3(1.0, 0.0, 0.0)
	if camera:
		forward = -camera.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			forward = forward.normalized()
		right = Vector3.UP.cross(forward).normalized()
	return [right, forward]


func _travel_yaw() -> float:
	var speed := Vector2(_slide_right, _slide_forward).length()
	if speed < 0.25:
		return 0.0
	# 其他形态只轻轻侧过脸，避免立绘转到侧面。
	if assembly.resolve_locomotion() != CharacterAssemblyController.LocomotionMode.SNAKE_SLITHER:
		_snake_mirror = false
		return clampf(_slide_right / 4.5, -1.0, 1.0) * 0.5
	# 静止时尾巴伸向画面左侧。正偏航把脑袋转向画面上方，所以尾巴落后于行进方向。
	# 偏航超过约 100° 时改镜像，避免立绘转到侧面变成一条线。
	var heading := atan2(_slide_right, _slide_forward)
	var yaw := wrapf(PI * 0.5 - heading, -PI, PI)
	_snake_mirror = false
	if yaw > PI * 0.55:
		_snake_mirror = true
		yaw -= PI
	elif yaw < -PI * 0.55:
		_snake_mirror = true
		yaw += PI
	if _snake_mirror:
		yaw = -yaw
	return clampf(yaw, -1.25, 1.25)


func _weave_offset(signed_amount: float) -> Vector3:
	# 横移轴和行进方向垂直，所以蠕动是穿过路线，而不是顺着画面左右滑。
	var axes := _planar_axes()
	var side := axes[0] * _slide_forward - axes[1] * _slide_right
	side.y = 0.0
	if side.length_squared() < 0.0001:
		side = axes[0]
	else:
		side = side.normalized()
	return global_transform.basis.inverse() * (side * signed_amount)


func _face_travel() -> void:
	var index: int = _bones["body"]
	if assembly.resolve_locomotion() == CharacterAssemblyController.LocomotionMode.HEAD_ROLL:
		_snake_mirror = false
		_skeleton.set_bone_pose_scale(index, Vector3.ONE)
		return
	var up_axis := (global_transform.basis.inverse() * Vector3.UP).normalized()
	var current := _skeleton.get_bone_pose_rotation(index)
	_skeleton.set_bone_pose_rotation(index, Quaternion(up_axis, _travel_yaw()) * current)
	_skeleton.set_bone_pose_scale(index, Vector3(-1.0 if _snake_mirror else 1.0, 1.0, 1.0))


func _face_camera_once() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		# 朝相机的反方向看，让贴图的正面（+Z）朝向镜头，同时头顶仍朝上。
		var away := global_position - (camera.global_position - global_position)
		look_at(away, Vector3.UP)


func _set_bone_rotation(bone_name: String, angle: float) -> void:
	_skeleton.set_bone_pose_rotation(_bones[bone_name], Quaternion(Vector3.FORWARD, angle))


func _offset_bone_rotation(bone_name: String, angle: float) -> void:
	var index: int = _bones[bone_name]
	var current := _skeleton.get_bone_pose_rotation(index)
	_skeleton.set_bone_pose_rotation(index, current * Quaternion(Vector3.FORWARD, angle))


func _set_bone_position(bone_name: String, position_offset: Vector3) -> void:
	_skeleton.set_bone_pose_position(_bones[bone_name], _base_positions[bone_name] + position_offset)


func _offset_bone_position(bone_name: String, position_offset: Vector3) -> void:
	var index: int = _bones[bone_name]
	_skeleton.set_bone_pose_position(index, _skeleton.get_bone_pose_position(index) + position_offset)


func _on_attack_started(channel: StringName, _interrupted_movement: bool) -> void:
	_attack_channel = channel
	_attack_time = 0.32
