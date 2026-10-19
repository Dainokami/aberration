class_name LevelTransitionController
extends Node3D

signal status_changed(remaining_seconds: float, state: int)
signal transition_requested(target_level: String)
signal report(message: String)

enum State { DISABLED, COUNTDOWN, WAITING, OPEN, TRANSITIONING, STOPPED }
const PORTAL_SCENE := preload("res://assets/placeholders/level_portal.tscn")

var data: LevelData
var player: CharacterBody3D
var config: LevelTransitionConfig
var remaining := 0.0
var state: State = State.DISABLED
var portal: LevelPortal
var retry_left := 0.0

func setup(level: LevelData, actor: CharacterBody3D) -> void:
	data = level
	player = actor
	config = level.level_transition.duplicate(true) as LevelTransitionConfig \
		if level.level_transition != null else LevelTransitionConfig.new()
	remaining = config.countdown_seconds
	var errors := config.errors(false)
	state = State.COUNTDOWN if config.enabled and errors.is_empty() else State.DISABLED
	if not errors.is_empty():
		report.emit("\n".join(errors))
	status_changed.emit(remaining, state)

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not is_instance_valid(player) or get_tree().paused:
		return
	if float(player.get_meta("scene_health", 100.0)) <= 0:
		stop()
		return
	if state == State.COUNTDOWN:
		remaining = maxf(0, remaining - maxf(0, delta))
		if remaining <= 0:
			state = State.WAITING
		status_changed.emit(remaining, state)
	if state == State.WAITING:
		retry_left -= maxf(0, delta)
		if retry_left > 0:
			return
		retry_left = 1.0
		var position_found := LevelPortalPlacement.find_position(data, player, config)
		if position_found == Vector3.INF:
			return
		portal = PORTAL_SCENE.instantiate() as LevelPortal
		add_child(portal)
		portal.global_position = position_found
		state = State.OPEN
		status_changed.emit(remaining, state)
		report.emit("传送门已开启，靠近后按 E 进入下一关")

func interaction_text() -> String:
	return "E 进入下一关" if state == State.OPEN and is_instance_valid(portal) \
		and portal.can_interact(player) else ""

func attempt_interact() -> bool:
	if get_tree().paused or not is_instance_valid(player) \
			or float(player.get_meta("scene_health", 100.0)) <= 0:
		return false
	if interaction_text().is_empty():
		return false
	state = State.TRANSITIONING
	portal.active = false
	status_changed.emit(remaining, state)
	transition_requested.emit(config.target_level)
	return true

func transition_failed(message: String) -> void:
	if state != State.TRANSITIONING:
		return
	state = State.OPEN
	if is_instance_valid(portal):
		portal.active = true
	status_changed.emit(remaining, state)
	report.emit(message)

func stop() -> void:
	if state in [State.DISABLED, State.STOPPED]:
		return
	state = State.STOPPED
	if is_instance_valid(portal):
		portal.active = false
	status_changed.emit(remaining, state)
