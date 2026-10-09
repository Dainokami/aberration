class_name PlayerVisualRig
extends Node3D

enum VisualMode {
	COMPOSITE,
	PARTS,
}

@export var visual_mode := VisualMode.COMPOSITE
@export var bob_height := 0.055
@export var bob_speed := 10.0
@export var move_lean_degrees := 4.0
@export var idle_hover_height := 0.025

@onready var composite: Sprite3D = $Composite
@onready var part_sockets: Node3D = $PartSockets
@onready var modular_rig: ModularCharacterRig = $PartSockets

var _base_position := Vector3.ZERO
var _horizontal_speed := 0.0
var _grounded := true
var _vertical_speed := 0.0
var _screen_direction := 0.0
var _motion_time := 0.0


func _ready() -> void:
	_base_position = position
	_apply_visual_mode()


func _process(delta: float) -> void:
	var normalized_speed := clampf(_horizontal_speed / 6.0, 0.0, 1.0)
	_motion_time += delta * lerpf(2.0, bob_speed, normalized_speed)
	# 分件骨架自己贴地，再整体上下晃会把脚和滚动中的头抬离地面。
	var bob := 0.0
	if visual_mode == VisualMode.COMPOSITE:
		bob = sin(_motion_time) * bob_height * normalized_speed if _grounded else sin(_motion_time * 0.55) * idle_hover_height
	position = _base_position + Vector3.UP * bob
	# 移动倾斜由 ModularCharacterRig 的具体步态负责；这里不再把整个角色
	# 每帧强制校正到某个朝向，避免抵消头部滚动和肢体支撑动作。

	if visual_mode == VisualMode.COMPOSITE and absf(_screen_direction) > 0.08:
		composite.flip_h = _screen_direction < 0.0


func set_motion_state(horizontal_velocity: Vector3, grounded: bool, vertical_speed: float, screen_direction: float, delta: float) -> void:
	_horizontal_speed = horizontal_velocity.length()
	_grounded = grounded
	_vertical_speed = vertical_speed
	_screen_direction = screen_direction
	modular_rig.set_motion_state(horizontal_velocity, grounded, vertical_speed, screen_direction, delta)


func set_visual_mode(new_mode: VisualMode) -> void:
	visual_mode = new_mode
	_apply_visual_mode()


func _apply_visual_mode() -> void:
	if not is_node_ready():
		return
	composite.visible = visual_mode == VisualMode.COMPOSITE
	part_sockets.visible = visual_mode == VisualMode.PARTS
