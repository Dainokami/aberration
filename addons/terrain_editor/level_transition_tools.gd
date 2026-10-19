@tool
extends RefCounted

var host: EditorPlugin
var page: VBoxContainer
var controls := {}
var config: LevelTransitionConfig
var observed_data: LevelData
var observed_config: LevelTransitionConfig
var syncing := false
var target_dialog: EditorFileDialog
var dialog_target: LevelData
var choose_button: Button
var validate_button: Button

func setup(plugin: EditorPlugin, tabs: TabContainer) -> void:
	host = plugin
	var scroll := ScrollContainer.new()
	scroll.name = "流程"
	tabs.add_child(scroll)
	page = VBoxContainer.new()
	page.name = "LevelTransitionSettings"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", host.ui_px(8))
	scroll.add_child(page)
	_label("倒计时传送门")
	_label("玩家开始操作后计时，归零后在附近空地生成传送门。\n靠近按 E 进入下一关。游戏暂停时计时暂停。")
	var enabled := CheckButton.new()
	enabled.name = "LevelTransitionEnabled"
	enabled.text = "启用倒计时传送门"
	enabled.toggled.connect(func(value: bool): change("enabled", value))
	page.add_child(enabled)
	controls.enabled = enabled
	_number("countdown_seconds", "倒计时 / 秒", 0.1, 7200, 0.1)
	_label("目标地图")
	var target := LineEdit.new()
	target.name = "PortalTargetLevel"
	target.placeholder_text = "res://data/levels/..."
	target.text_submitted.connect(func(value: String): change("target_level", value.strip_edges()))
	target.focus_exited.connect(func():
		if not syncing and observed_data == host.data:
			change("target_level", target.text.strip_edges()))
	page.add_child(target)
	controls.target_level = target
	choose_button = Button.new()
	choose_button.name = "ChoosePortalTarget"
	choose_button.text = "选择目标地图…"
	choose_button.pressed.connect(func():
		dialog_target = host.data
		target_dialog.popup_centered_clamped(Vector2i(800, 600)))
	page.add_child(choose_button)
	target_dialog = EditorFileDialog.new()
	target_dialog.name = "PortalTargetDialog"
	target_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	target_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	target_dialog.add_filter("*.tres", "关卡地图（LevelData）")
	target_dialog.file_selected.connect(func(path: String):
		if host.data != dialog_target or dialog_target == null:
			host._set_status("地图已切换，请重新选择目标地图")
			return
		if not ResourceLoader.load(path) is LevelData:
			host._set_status("请选择 LevelData 关卡地图")
			return
		change("target_level", path))
	page.add_child(target_dialog)
	_number("radius_min", "生成最近距离 / 米", 2, 32, 0.5)
	_number("radius_max", "生成最远距离 / 米", 2, 32, 0.5)
	_label("无安全落点时会等待并重试。旧地图默认 60 秒，目标为演示终点；关闭本开关可作为终点关卡。")
	validate_button = Button.new()
	validate_button.name = "ValidateLevelTransition"
	validate_button.text = "检查传送配置"
	validate_button.pressed.connect(func():
		var errors := config.errors()
		host._set_status("传送配置有效" if errors.is_empty() else "\n".join(errors)))
	page.add_child(validate_button)
	sync()

func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(label)

func _number(field: String, title: String, minimum: float, maximum: float, step: float) -> void:
	_label(title)
	var spin := SpinBox.new()
	spin.name = field
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value_changed.connect(func(value: float): change(field, value))
	page.add_child(spin)
	controls[field] = spin

func sync() -> void:
	syncing = true
	observed_data = host.data
	observed_config = observed_data.level_transition if observed_data != null else null
	config = observed_config if observed_config != null else LevelTransitionConfig.new()
	for field in controls:
		var control: Control = controls[field]
		if control is CheckButton:
			control.set_pressed_no_signal(config.get(field))
			control.disabled = observed_data == null
		elif control is SpinBox:
			control.set_value_no_signal(config.get(field))
			control.editable = observed_data != null
		elif control is LineEdit:
			control.text = config.get(field)
			control.editable = observed_data != null
	choose_button.disabled = observed_data == null
	validate_button.disabled = observed_data == null
	syncing = false

func change(field: String, value: Variant) -> void:
	if syncing or host.data == null or config.get(field) == value:
		return
	var next := config.duplicate(true) as LevelTransitionConfig
	next.set(field, value)
	var target: LevelData = host.data
	var history := host.get_undo_redo()
	history.create_action("设置倒计时传送门", UndoRedo.MERGE_DISABLE, target)
	history.add_do_method(self, "_apply", target, next)
	history.add_undo_method(self, "_apply", target, target.level_transition)
	history.commit_action()

func _apply(target: LevelData, value: LevelTransitionConfig) -> void:
	target.level_transition = value
	target.emit_changed()
	if host.data == target:
		host._set_dirty(true)
		sync()
