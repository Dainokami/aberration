class_name PlayerController
extends CharacterBody3D

signal air_action_changed(mode: AirAction)
signal jumped
signal landed
signal respawned

enum AirAction {
	JUMP,
	FLIGHT,
}

@export_category("Ground Movement")
@export var move_speed := 6.0
@export var ground_acceleration := 34.0
@export var ground_deceleration := 42.0
@export var air_control := 0.55

@export_category("Air Action")
@export var air_action := AirAction.FLIGHT
@export var jump_height := 1.8
@export var jump_time_to_peak := 0.38
@export var jump_time_to_fall := 0.32
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12
@export var flight_climb_speed := 4.0
@export var flight_fall_speed := 3.2
@export var flight_vertical_acceleration := 14.0

@export_category("Recovery")
@export var respawn_position := Vector3(0.0, 1.0, 7.0)
@export var fall_reset_height := -5.0

@onready var visual_rig: PlayerVisualRig = $ArtRoot
@onready var assembly: CharacterAssemblyController = $Assembly
@onready var collision: CollisionShape3D = $Collision

var _coyote_remaining := 0.0
var _jump_buffer_remaining := 0.0
var _was_grounded := false
var _is_flying := false


func _ready() -> void:
	add_to_group("player")
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(48.0)
	respawn_position = global_position
	# 场景里的子资源可能被多个实例共享，运行时调整前先复制。
	collision.shape = collision.shape.duplicate()
	assembly.loadout_changed.connect(_update_collision_for_loadout)
	_update_collision_for_loadout()


func _physics_process(delta: float) -> void:
	_update_ground_memory(delta)
	_update_horizontal_velocity(delta)
	_update_vertical_velocity(delta)
	move_and_slide()
	_update_landing_state()
	_update_visuals(delta)

	if global_position.y < fall_reset_height:
		respawn()


func set_air_action(new_action: AirAction) -> void:
	if air_action == new_action:
		return
	air_action = new_action
	_is_flying = false
	_jump_buffer_remaining = 0.0
	air_action_changed.emit(air_action)


func respawn() -> void:
	global_position = respawn_position
	velocity = Vector3.ZERO
	_is_flying = false
	respawned.emit()


func get_air_action_label() -> String:
	return "跳跃" if air_action == AirAction.JUMP else "飞行"


func is_flying() -> bool:
	return _is_flying


func _update_ground_memory(delta: float) -> void:
	if is_on_floor():
		_coyote_remaining = coyote_time
	else:
		_coyote_remaining = maxf(_coyote_remaining - delta, 0.0)

	if Input.is_action_just_pressed("air_action"):
		_jump_buffer_remaining = jump_buffer_time
	else:
		_jump_buffer_remaining = maxf(_jump_buffer_remaining - delta, 0.0)


func _update_horizontal_velocity(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if assembly.is_movement_locked():
		input_vector = Vector2.ZERO
	var move_axes := _camera_planar_axes()
	var move_direction := (move_axes[0] * input_vector.x) + (move_axes[1] * -input_vector.y)

	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()

	var current_horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var motion_amount := maxf(input_vector.length(), current_horizontal.length() / maxf(move_speed, 0.01))
	assembly.advance_locomotion(delta, motion_amount)
	var target_velocity := move_direction * move_speed * assembly.get_speed_multiplier() * assembly.get_drive_multiplier()
	var control_multiplier := 1.0 if is_on_floor() else air_control
	var acceleration := ground_acceleration * assembly.get_acceleration_multiplier() if move_direction.length_squared() > 0.01 else ground_deceleration * assembly.get_deceleration_multiplier()
	current_horizontal = current_horizontal.move_toward(target_velocity, acceleration * control_multiplier * delta)
	velocity.x = current_horizontal.x
	velocity.z = current_horizontal.z


func _update_vertical_velocity(delta: float) -> void:
	if air_action == AirAction.JUMP:
		_update_jump(delta)
	else:
		_update_flight(delta)


func _update_jump(delta: float) -> void:
	var jump_gravity := (2.0 * jump_height) / pow(jump_time_to_peak, 2.0)
	var fall_gravity := (2.0 * jump_height) / pow(jump_time_to_fall, 2.0)
	var jump_velocity := jump_gravity * jump_time_to_peak

	if _jump_buffer_remaining > 0.0 and _coyote_remaining > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_remaining = 0.0
		_coyote_remaining = 0.0
		jumped.emit()
	elif not is_on_floor():
		velocity.y -= (jump_gravity if velocity.y > 0.0 else fall_gravity) * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0


func _update_flight(delta: float) -> void:
	if not assembly.can_fly():
		_is_flying = false
		if not is_on_floor():
			velocity.y -= 18.0 * delta
		else:
			velocity.y = 0.0
		return

	if not _is_flying and Input.is_action_just_pressed("air_action") and (is_on_floor() or _coyote_remaining > 0.0):
		_is_flying = true
		velocity.y = flight_climb_speed * 0.75
		jumped.emit()
	elif _is_flying:
		var target_vertical_speed := flight_climb_speed if Input.is_action_pressed("air_action") else -flight_fall_speed
		velocity.y = move_toward(velocity.y, target_vertical_speed, flight_vertical_acceleration * delta)
	elif not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = 0.0


func _update_landing_state() -> void:
	var grounded_now := is_on_floor()
	if grounded_now and not _was_grounded:
		_is_flying = false
		landed.emit()
	_was_grounded = grounded_now


func _update_visuals(delta: float) -> void:
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var screen_direction := 0.0
	if horizontal_velocity.length_squared() > 0.01:
		screen_direction = _camera_planar_axes()[0].dot(horizontal_velocity.normalized())
	visual_rig.set_motion_state(horizontal_velocity, is_on_floor(), velocity.y, screen_direction, delta)


func _camera_planar_axes() -> Array[Vector3]:
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


func _update_collision_for_loadout() -> void:
	var capsule := collision.shape as CapsuleShape3D
	if capsule == null:
		return
	var target_height := assembly.get_collision_height()
	capsule.height = target_height
	capsule.radius = minf(0.42, target_height * 0.42)
	collision.position.y = target_height * 0.5
