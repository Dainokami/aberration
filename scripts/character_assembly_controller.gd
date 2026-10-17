class_name CharacterAssemblyController
extends Node

signal loadout_changed
signal attack_started(channel: StringName, interrupted_movement: bool)
signal conflict_reported(message: String)

enum LowerBody {
	NONE,
	BIPED,
	QUADRUPED,
	SNAKE,
	TENTACLE,
}

enum LocomotionMode {
	HEAD_ROLL,
	SINGLE_ARM_HOP,
	DOUBLE_ARM_WALK,
	BIPED_WALK,
	QUADRUPED_WALK,
	SNAKE_SLITHER,
	TENTACLE_CRAWL,
}

@export_range(0, 2) var arm_count := 0
@export var lower_body := LowerBody.NONE
@export var wings_equipped := false
@export var attack_movement_lock_time := 0.34

var _preset_index := 0
var _movement_lock_remaining := 0.0
var _locomotion_phase := 0.0
var limbs_equipped := false
var limb_upper_id := ""
var limb_lower_id := ""
var part_wings := false

# 这套拆分稿只有本体、一条猩猩臂、一条虫子腿和蛇身。没有双足和四足的图。
const PRESETS := [
	{"name": "头部滚动", "arms": 0, "lower": LowerBody.NONE},
	{"name": "单臂跳跃", "arms": 1, "lower": LowerBody.NONE},
	{"name": "双臂支撑", "arms": 2, "lower": LowerBody.NONE},
	{"name": "蛇形蠕动", "arms": 0, "lower": LowerBody.SNAKE},
	{"name": "蛇身带臂", "arms": 2, "lower": LowerBody.SNAKE},
]


func _ready() -> void:
	_apply_preset(0)
	call_deferred("_emit_initial_loadout")


func _process(delta: float) -> void:
	_movement_lock_remaining = maxf(_movement_lock_remaining - delta, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_loadout"):
		cycle_loadout()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_wings"):
		wings_equipped = not wings_equipped
		loadout_changed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack"):
		var parts := get_node_or_null("../PartLoadout")
		if parts != null and parts.has_method("handles_attack") and parts.handles_attack():
			return
		request_attack()
		get_viewport().set_input_as_handled()


func cycle_loadout() -> void:
	var bag := get_node_or_null("../LimbBag")
	if bag != null and bag.has_method("has_equipped") and bool(bag.call("has_equipped")):
		bag.call("report", "身上有肢体，先卸下来再用 C 看旧拼接")
		return
	_apply_preset((_preset_index + 1) % PRESETS.size())
	loadout_changed.emit()


func apply_limb_loadout(upper_id: String, lower_id: String) -> void:
	limbs_equipped = true
	limb_upper_id = upper_id
	limb_lower_id = lower_id
	var upper := LimbCatalog.find(upper_id)
	var lower := LimbCatalog.find(lower_id)
	arm_count = 1 if upper != null and upper.visual == "scythe" else 0
	lower_body = LowerBody.SNAKE if lower != null and lower.visual == "tail" else LowerBody.NONE
	wings_equipped = false
	loadout_changed.emit()


func clear_limb_drive() -> void:
	if not limbs_equipped and limb_upper_id.is_empty() and limb_lower_id.is_empty():
		return
	limbs_equipped = false
	limb_upper_id = ""
	limb_lower_id = ""
	_apply_preset(_preset_index)
	loadout_changed.emit()


func _apply_preset(index: int) -> void:
	_preset_index = index
	var preset: Dictionary = PRESETS[index]
	arm_count = preset["arms"]
	lower_body = preset["lower"]


func apply_part_movement(upper_id: String, lower_id: String) -> void:
	part_wings = upper_id in ["goose_wing", "bat_wing", "albatross_wing", "eagle_wing"]
	if upper_id == "octopus_arm":
		arm_count = 2
	elif upper_id in ["gorilla_arm", "gibbon_arm", "gerbil_paw", "mantis_arm", "mantis_blade", "mantis_king"]:
		arm_count = 1
	else:
		arm_count = 0
	if lower_id in ["water_snake", "fish_tail", "snake_body", "python_body", "crowned_snake"]:
		lower_body = LowerBody.SNAKE
	elif lower_id == "octopus_leg":
		lower_body = LowerBody.TENTACLE
	elif not lower_id.is_empty():
		# 策划优先级为下肢 > 上肢 > 头；有普通下肢时不能退回手臂支撑。
		lower_body = LowerBody.BIPED
	elif arm_count > 0:
		lower_body = LowerBody.NONE
	else:
		lower_body = LowerBody.NONE


func resolve_locomotion() -> LocomotionMode:
	# 下肢的蛇行优先。其余时候上肢决定是跳、爬还是用腿走。翅膀只叠加飞行。
	match lower_body:
		LowerBody.BIPED:
			return LocomotionMode.BIPED_WALK
		LowerBody.QUADRUPED:
			return LocomotionMode.QUADRUPED_WALK
		LowerBody.SNAKE:
			return LocomotionMode.SNAKE_SLITHER
		LowerBody.TENTACLE:
			return LocomotionMode.TENTACLE_CRAWL

	if arm_count >= 2:
		return LocomotionMode.DOUBLE_ARM_WALK
	if arm_count == 1:
		return LocomotionMode.SINGLE_ARM_HOP
	return LocomotionMode.HEAD_ROLL


func get_speed_multiplier() -> float:
	match resolve_locomotion():
		LocomotionMode.HEAD_ROLL:
			return 0.72
		LocomotionMode.SINGLE_ARM_HOP:
			return 0.68
		LocomotionMode.DOUBLE_ARM_WALK:
			return 0.82
		LocomotionMode.BIPED_WALK:
			return 1.0
		LocomotionMode.QUADRUPED_WALK:
			return 1.18
		LocomotionMode.SNAKE_SLITHER:
			var snake_scale := 1.0
			if limbs_equipped:
				var lower := LimbCatalog.find(limb_lower_id)
				if lower != null:
					snake_scale = lower.speed_scale
			return 0.9 * snake_scale
		LocomotionMode.TENTACLE_CRAWL:
			return 0.9
	return 1.0


func advance_locomotion(delta: float, motion_amount: float) -> void:
	# 由玩家物理循环推进，表现层和实际位移共用同一个步态时钟。
	# motion_amount 同时考虑输入和惯性，松开按键后滚动/蛇行不会立刻僵住。
	if motion_amount <= 0.015:
		return
	_locomotion_phase = fmod(_locomotion_phase + delta * get_cadence() * clampf(motion_amount, 0.35, 1.25), TAU)


func get_locomotion_phase() -> float:
	return _locomotion_phase


func get_cadence() -> float:
	match resolve_locomotion():
		LocomotionMode.HEAD_ROLL:
			return 9.5
		LocomotionMode.SINGLE_ARM_HOP:
			return 5.2
		LocomotionMode.DOUBLE_ARM_WALK:
			return 7.2
		LocomotionMode.BIPED_WALK:
			return 9.0
		LocomotionMode.QUADRUPED_WALK:
			return 11.5
		LocomotionMode.SNAKE_SLITHER:
			return 6.2
		LocomotionMode.TENTACLE_CRAWL:
			return 6.8
	return 8.0


func get_drive_multiplier() -> float:
	# 速度脉冲负责手感差异；平均速度仍由 get_speed_multiplier 控制。
	match resolve_locomotion():
		LocomotionMode.HEAD_ROLL:
			return 1.0
		LocomotionMode.SINGLE_ARM_HOP:
			var hop_push := maxf(sin(_locomotion_phase), 0.0)
			return 0.28 + hop_push * 1.18
		LocomotionMode.DOUBLE_ARM_WALK:
			return 0.62 + absf(cos(_locomotion_phase)) * 0.46
		LocomotionMode.BIPED_WALK:
			return 0.96 + absf(sin(_locomotion_phase * 2.0)) * 0.08
		LocomotionMode.QUADRUPED_WALK:
			return 0.92 + absf(sin(_locomotion_phase * 2.0)) * 0.16
		LocomotionMode.SNAKE_SLITHER:
			# 只留很轻的起伏。大幅一冲一停会让身体看起来在跟路线较劲。
			return 0.92 + sin(_locomotion_phase) * 0.08
		LocomotionMode.TENTACLE_CRAWL:
			# 两侧触手轮流吸附、收缩。低谷仍保留推进，避免操作完全停顿。
			return 0.68 + pow(absf(sin(_locomotion_phase)), 1.35) * 0.48
	return 1.0


func get_acceleration_multiplier() -> float:
	match resolve_locomotion():
		LocomotionMode.HEAD_ROLL:
			return 0.34
		LocomotionMode.SINGLE_ARM_HOP:
			return 0.88
		LocomotionMode.DOUBLE_ARM_WALK:
			return 0.72
		LocomotionMode.BIPED_WALK:
			return 1.0
		LocomotionMode.QUADRUPED_WALK:
			return 1.28
		LocomotionMode.SNAKE_SLITHER:
			return 0.56
		LocomotionMode.TENTACLE_CRAWL:
			return 0.7
	return 1.0


func get_deceleration_multiplier() -> float:
	match resolve_locomotion():
		LocomotionMode.HEAD_ROLL:
			return 0.18
		LocomotionMode.SINGLE_ARM_HOP:
			return 0.72
		LocomotionMode.DOUBLE_ARM_WALK:
			return 1.18
		LocomotionMode.BIPED_WALK:
			return 1.0
		LocomotionMode.QUADRUPED_WALK:
			return 1.22
		LocomotionMode.SNAKE_SLITHER:
			return 0.42
		LocomotionMode.TENTACLE_CRAWL:
			return 0.58
	return 1.0


func get_collision_height() -> float:
	match resolve_locomotion():
		LocomotionMode.HEAD_ROLL:
			return 1.02
		LocomotionMode.SINGLE_ARM_HOP, LocomotionMode.DOUBLE_ARM_WALK:
			return 1.65
		LocomotionMode.BIPED_WALK, LocomotionMode.QUADRUPED_WALK:
			return 2.12
		LocomotionMode.SNAKE_SLITHER:
			return 2.2
		LocomotionMode.TENTACLE_CRAWL:
			return 1.88
	return 1.65


func get_locomotion_label() -> String:
	if limbs_equipped:
		return "蛇行" if resolve_locomotion() == LocomotionMode.SNAKE_SLITHER else "站立"
	return PRESETS[_preset_index]["name"]


func get_loadout_summary() -> String:
	if limbs_equipped:
		return "移动：%s  |  上肢：%s  下肢：%s" % [
			get_locomotion_label(), _limb_name(limb_upper_id), _limb_name(limb_lower_id)
		]
	var lower_label: String = ["无", "双足", "四足", "蛇类", "触手"][lower_body]
	return "移动：%s  |  上肢：%d  下肢：%s  翅膀：%s" % [
		get_locomotion_label(), arm_count, lower_label, "有" if can_fly() else "无"
	]


func _limb_name(limb_id: String) -> String:
	if limb_id.is_empty():
		return "无"
	var limb := LimbCatalog.find(limb_id)
	return limb.display_name if limb else limb_id


func can_fly() -> bool:
	return wings_equipped or part_wings


func is_movement_locked() -> bool:
	return _movement_lock_remaining > 0.0


func request_attack(channel: StringName = &"") -> void:
	if channel != &"":
		var uses_locomotion_limb := lower_body == LowerBody.NONE and arm_count > 0 \
			and channel not in [&"head", &"wings"]
		if uses_locomotion_limb:
			_movement_lock_remaining = attack_movement_lock_time
			conflict_reported.emit("冲突：上肢同时负责移动和攻击；当前策略为攻击短暂中断移动。")
		else:
			conflict_reported.emit("下肢承担移动，上肢可在移动中攻击。")
		attack_started.emit(channel, uses_locomotion_limb)
		return
	var arms_used_for_locomotion := lower_body == LowerBody.NONE and arm_count > 0
	if arm_count == 0:
		conflict_reported.emit("无上肢：改用低威力头部撞击；未来可由头部攻击模组替换。")
		attack_started.emit(&"head", false)
		return

	if arms_used_for_locomotion:
		_movement_lock_remaining = attack_movement_lock_time
		conflict_reported.emit("冲突：上肢同时负责移动和攻击；当前策略为攻击短暂中断移动。")
		attack_started.emit(&"left_arm" if arm_count == 1 else &"right_arm", true)
		return

	conflict_reported.emit("下肢承担移动，上肢可在移动中攻击。")
	attack_started.emit(&"right_arm", false)


func _emit_initial_loadout() -> void:
	loadout_changed.emit()
