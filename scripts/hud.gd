class_name WhiteboxHUD
extends CanvasLayer

@export_node_path("PlayerController") var player_path: NodePath

@onready var player: PlayerController = get_node_or_null(player_path)
@onready var assembly: CharacterAssemblyController = player.get_node("Assembly") if player else null
@onready var mode_label: Label = $SafeArea/TopLeft/Content/Mode
@onready var status_label: Label = $SafeArea/TopLeft/Content/Status
@onready var assembly_label: Label = $SafeArea/TopLeft/Content/Assembly
@onready var parts_label: Label = $SafeArea/TopLeft/Content/Parts
@onready var conflict_label: Label = $SafeArea/TopLeft/Content/Conflict

var parts: PartLoadout
@onready var objective_label: Label = $SafeArea/ObjectivePanel/Objective

var _goal_reached := false
var _conflict_timer := 0.0
var _key_help: ColorRect


func _ready() -> void:
	add_to_group("hud")
	if player:
		player.air_action_changed.connect(_on_air_action_changed)
		player.respawned.connect(_on_player_respawned)
		_on_air_action_changed(player.air_action)
	if assembly:
		assembly.loadout_changed.connect(_on_loadout_changed)
		assembly.conflict_reported.connect(_on_conflict_reported)
		_on_loadout_changed()
	if player:
		parts = player.get_node_or_null("PartLoadout") as PartLoadout
	if parts:
		parts.changed_loadout.connect(_on_loadout_changed)
		parts.note.connect(_on_conflict_reported)
		_on_loadout_changed()
	if player:
		var limbs := player.get_node_or_null("LimbBag") as LimbBag
		if limbs:
			limbs.note.connect(_on_conflict_reported)
	_apply_playtest_caption()
	_build_key_help()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_wings"):
		return
	if _key_help == null:
		return
	_key_help.visible = not _key_help.visible
	get_viewport().set_input_as_handled()


func _build_key_help() -> void:
	var dim := ColorRect.new()
	dim.name = "KeyHelp"
	dim.visible = false
	dim.color = Color(0.05, 0.035, 0.04, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var card := Label.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -560.0
	card.offset_top = -380.0
	card.offset_right = 560.0
	card.offset_bottom = 380.0
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_theme_font_size_override("font_size", 28)
	card.add_theme_color_override("font_color", Color(0.97, 0.91, 0.8))
	card.text = "W A S D 移动\nSpace 跳跃 / 起飞\nG 捡肢体、推拉砸挖\nJ 攻击\nZ 上肢  X 下肢  T 突破\nTab 背包  1 属性  2 培养\n右键回收  Esc 关闭\nQ 打开或关闭这份说明"
	dim.add_child(card)
	_key_help = dim


func _process(delta: float) -> void:
	if not player:
		return
	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	status_label.text = "速度 %.1f   高度 %.1f   %s" % [horizontal_speed, player.global_position.y, "地面" if player.is_on_floor() else "空中"]
	if assembly:
		assembly_label.text = assembly.get_loadout_summary()
	if parts and parts_label:
		parts_label.text = parts.summary()
		var hint := parts.space_hint()
		if hint != "":
			mode_label.text = hint
	_conflict_timer = maxf(_conflict_timer - delta, 0.0)
	if _conflict_timer <= 0.0:
		conflict_label.text = ""


func show_goal_message() -> void:
	if _goal_reached:
		return
	_goal_reached = true
	objective_label.text = "抵达上层目标区 · 白盒路线验证完成"
	$SafeArea/ObjectivePanel.modulate = Color("ffe39a")


func _on_air_action_changed(_mode: PlayerController.AirAction) -> void:
	_on_loadout_changed()


func _on_player_respawned() -> void:
	if _is_level_playtest():
		objective_label.text = "已回到出生点"
		return
	objective_label.text = "落水已复位 · 前往远端金色目标区"


func _apply_playtest_caption() -> void:
	if not _is_level_playtest():
		return
	$SafeArea/TopLeft/Content/Title.text = "关卡试玩"
	$SafeArea/TopLeft/Content/Controls.text = "按 Q 查看按键"
	objective_label.text = "蓝块是流体，黄块是沙漠。长臂猿对崖壁按 G，再按 W 爬上去。"


func _is_level_playtest() -> bool:
	return player != null and player.has_meta("playtest_level")


func _on_loadout_changed() -> void:
	if not assembly:
		return
	mode_label.text = "空格：按住起飞 / 松开缓降" if assembly.can_fly() else "空格：需要装备翅膀"


func _on_conflict_reported(message: String) -> void:
	conflict_label.text = message
	_conflict_timer = 3.2
