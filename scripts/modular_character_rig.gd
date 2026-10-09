class_name ModularCharacterRig
extends Node3D

const PIXEL := 0.0043
const ANCHOR := Vector2(515.0, 536.0)

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
	# 和物理帧对齐。右移顺时针，远离镜头逆时针。对角时沿用来向，避免两个分量抵消后只滑不转。
	if assembly.resolve_locomotion() == CharacterAssemblyController.LocomotionMode.HEAD_ROLL:
		var speed := Vector2(_slide_right, _slide_forward).length()
		var turn := -_slide_right + _slide_forward
		if absf(turn) > 0.45:
			_roll_sign = signf(turn)
		elif speed > 0.2 and _roll_sign == 0.0:
			_roll_sign = signf((-_slide_right) if absf(_slide_right) >= absf(_slide_forward) else _slide_forward)
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
	var mode := assembly.resolve_locomotion()
	var snake := mode == CharacterAssemblyController.LocomotionMode.SNAKE_SLITHER
	var quadruped := mode == CharacterAssemblyController.LocomotionMode.QUADRUPED_WALK
	var biped := mode == CharacterAssemblyController.LocomotionMode.BIPED_WALK
	var hop := mode == CharacterAssemblyController.LocomotionMode.SINGLE_ARM_HOP
	# 双足和单臂都带躯干。双腿只和双足一起出现。
	_attachments["HeadSocket"].visible = true
	_attachments["BodySocket"].visible = biped or hop
	_attachments["LeftLegSocket"].visible = biped
	_attachments["RightLegSocket"].visible = biped
	_attachments["LeftHandSocket"].visible = (biped or quadruped) and assembly.arm_count >= 1
	_attachments["RightHandSocket"].visible = (biped or quadruped) and assembly.arm_count >= 2
	for socket_name in ["QuadFrontLeftSocket", "QuadFrontRightSocket", "QuadBackLeftSocket", "QuadBackRightSocket"]:
		_attachments[socket_name].visible = quadruped
	_attachments["HopArmSocket"].visible = mode == CharacterAssemblyController.LocomotionMode.SINGLE_ARM_HOP
	_attachments["CrawlLeftSocket"].visible = mode == CharacterAssemblyController.LocomotionMode.DOUBLE_ARM_WALK
	_attachments["CrawlRightSocket"].visible = mode == CharacterAssemblyController.LocomotionMode.DOUBLE_ARM_WALK
	_attachments["SnakeBodySocket"].visible = snake
	_attachments["SnakeArmLeftSocket"].visible = snake and assembly.arm_count >= 1
	_attachments["SnakeArmRightSocket"].visible = snake and assembly.arm_count >= 2
	_attachments["LeftWingSocket"].visible = assembly.wings_equipped
	_attachments["RightWingSocket"].visible = assembly.wings_equipped


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
			# 贴图绕自身中心转。转骨骼会把整颗头甩离地面，BoneAttachment 也跟不住补偿后的位置。
			_set_bone_position("root", Vector3(0.0, _ground_root(496.0), 0.0))
			_spin_with_head("HeadSocket", _head_roll_angle)
			_spin_with_head("LeftWingSocket", _head_roll_angle)
			_spin_with_head("RightWingSocket", _head_roll_angle)

		CharacterAssemblyController.LocomotionMode.SINGLE_ARM_HOP:
			# 单臂是 PSD 里已经画好的支撑锥，枢轴在锥顶。弹跳主要抬根节点，避免把贴图甩离接缝。
			var hop := maxf(sin(phase), 0.0) if moving else 0.0
			var compression := maxf(-sin(phase), 0.0) if moving else 0.0
			_set_bone_position("root", Vector3(0.0, _ground_root(737.0) + hop * 0.42 - compression * 0.045, 0.0))
			_set_bone_rotation("hop_arm", deg_to_rad(-6.0 - compression * 16.0 + hop * 8.0) * amount)

		CharacterAssemblyController.LocomotionMode.DOUBLE_ARM_WALK:
			var support := sin(phase) if moving else 0.0
			# 猩猩臂横着画的，肩头插进下巴后转 90 度，拳头朝下。钩手本来就竖直。
			_set_bone_position("root", Vector3(support * 0.04 * amount, _ground_root(748.0) + absf(support) * 0.02 * amount, 0.0))
			_set_bone_rotation("crawl_left", deg_to_rad(-90.0) + support * 0.1 * amount)
			_set_bone_rotation("crawl_right", deg_to_rad(-4.0) - support * 0.08 * amount)

		CharacterAssemblyController.LocomotionMode.BIPED_WALK:
			# 标准步行作为基准步态：速度平滑、上下起伏最小。
			var stride := sin(phase) if moving else 0.0
			# PSD 的脚底位于身体锚点下约 183px，root 下沉后脚底落到关卡地面。
			# 空中腿和摆臂都回到站立，只留翅膀拍动和机身俯仰。
			_set_bone_position("root", Vector3(0.0, -0.135 + absf(sin(phase * 2.0)) * 0.038 * amount * gait, 0.0))
			_set_bone_rotation("left_leg", stride * 0.42 * amount * gait)
			_set_bone_rotation("right_leg", -stride * 0.42 * amount * gait)
			_set_bone_rotation("left_arm", -stride * 0.17 * amount * gait)
			_set_bone_rotation("right_arm", stride * 0.17 * amount * gait)

		CharacterAssemblyController.LocomotionMode.QUADRUPED_WALK:
			# 四足采用对角小跑，身体压低，步频和响应都高于双足。
			var trot := sin(phase) if moving else 0.0
			_set_bone_position("root", Vector3(0.0, -0.08 + absf(sin(phase * 2.0)) * 0.025 * amount * gait, 0.0))
			_set_bone_rotation("body", trot * 0.035 * amount * gait)
			_set_bone_rotation("quad_front_left", trot * 0.48 * amount * gait)
			_set_bone_rotation("quad_front_right", -trot * 0.48 * amount * gait)
			_set_bone_rotation("quad_back_left", -trot * 0.48 * amount * gait)
			_set_bone_rotation("quad_back_right", trot * 0.48 * amount * gait)

		CharacterAssemblyController.LocomotionMode.SNAKE_SLITHER:
			# 整条蛇身是一张贴图，绕颈根小幅摆动。尾尖离枢轴较远，幅度保持得很小。
			var wave := sin(phase) if moving else 0.0
			_set_bone_position("root", Vector3(wave * 0.06 * amount * gait, _ground_root(748.0), 0.0))
			_set_bone_rotation("snake_body", wave * 0.16 * amount * gait)
			_set_bone_rotation("snake_arm_left", wave * 0.1 * amount * gait)
			_set_bone_rotation("snake_arm_right", -wave * 0.1 * amount * gait)
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


func _face_travel() -> void:
	if assembly.resolve_locomotion() == CharacterAssemblyController.LocomotionMode.HEAD_ROLL:
		return
	# 绕世界上方转，侧移时头和躯干一起看向行进方向。
	var yaw := clampf(_slide_right / 4.5, -1.0, 1.0) * 0.5
	var up_axis := (global_transform.basis.inverse() * Vector3.UP).normalized()
	var index: int = _bones["body"]
	var current := _skeleton.get_bone_pose_rotation(index)
	_skeleton.set_bone_pose_rotation(index, Quaternion(up_axis, yaw) * current)


func _face_camera_once() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		look_at(camera.global_position, Vector3.UP)


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
