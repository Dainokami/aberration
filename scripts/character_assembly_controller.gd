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
}

enum LocomotionMode {
	HEAD_ROLL,
	SINGLE_ARM_HOP,
	DOUBLE_ARM_WALK,
	BIPED_WALK,
	QUADRUPED_WALK,
	SNAKE_SLITHER,
}

@export_range(0, 2) var arm_count := 2
@export var lower_body := LowerBody.BIPED
@export var wings_equipped := true
@export var attack_movement_lock_time := 0.34

var _preset_index := 3
var _movement_lock_remaining := 0.0
var _locomotion_phase := 0.0

const PRESETS := [
	{"name": "头部滚动", "arms": 0, "lower": LowerBody.NONE},
	{"name": "单臂跳跃", "arms": 1, "lower": LowerBody.NONE},
	{"name": "双臂支撑", "arms": 2, "lower": LowerBody.NONE},
	{"name": "双足行走", "arms": 2, "lower": LowerBody.BIPED},
	{"name": "四足移动", "arms": 2, "lower": LowerBody.QUADRUPED},
	{"name": "蛇形蠕动", "arms": 2, "lower": LowerBody.SNAKE},
]


func _ready() -> void:
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
		request_attack()
		get_viewport().set_input_as_handled()


func cycle_loadout() -> void:
	_preset_index = (_preset_index + 1) % PRESETS.size()
	var preset: Dictionary = PRESETS[_preset_index]
	arm_count = preset["arms"]
	lower_body = preset["lower"]
	loadout_changed.emit()


func resolve_locomotion() -> LocomotionMode:
	# 策划优先级：下肢 > 上肢 > 头部。翅膀是叠加能力，不替换地面移动。
	match lower_body:
		LowerBody.BIPED:
			return LocomotionMode.BIPED_WALK
		LowerBody.QUADRUPED:
			return LocomotionMode.QUADRUPED_WALK
		LowerBody.SNAKE:
			return LocomotionMode.SNAKE_SLITHER

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
			return 0.72 + (sin(_locomotion_phase) * 0.5 + 0.5) * 0.34
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
	return 1.0


func get_collision_height() -> float:
	match resolve_locomotion():
		LocomotionMode.HEAD_ROLL:
			return 1.02
		LocomotionMode.SINGLE_ARM_HOP, LocomotionMode.DOUBLE_ARM_WALK:
			return 1.72
	return 2.12


func get_locomotion_label() -> String:
	return PRESETS[_preset_index]["name"]


func get_loadout_summary() -> String:
	var lower_label: String = ["无", "双足", "四足", "蛇类"][lower_body]
	return "移动：%s  |  上肢：%d  下肢：%s  翅膀：%s" % [
		get_locomotion_label(), arm_count, lower_label, "有" if wings_equipped else "无"
	]


func can_fly() -> bool:
	return wings_equipped


func is_movement_locked() -> bool:
	return _movement_lock_remaining > 0.0


func request_attack() -> void:
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
