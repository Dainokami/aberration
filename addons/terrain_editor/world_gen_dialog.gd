@tool
extends Window

signal map_ready(data: LevelData)
const Preview := preload("res://addons/terrain_editor/world_gen_preview.gd")
var config := WorldGenConfig.new()
var result: LevelData
var _thread: Thread
var _generator: WorldGenerator
var _inputs := {}
var _loading := false
var _preview
var _report: RichTextLabel
var _status: Label
var _size_label: Label
var _generate: Button
var _apply: Button
var _cancel: Button
var _tabs: TabContainer
var _source_rows: VBoxContainer
var _file: EditorFileDialog
var _file_action := ""
var _mode: OptionButton
var _started := 0

func _ready() -> void:
	name = "WorldGeneration"
	title = "有限世界生成"
	var editor_scale := EditorInterface.get_editor_scale()
	# Editor theme metrics are already scaled; use the engine theme with one canvas scale.
	theme = ThemeDB.get_default_theme().duplicate()
	var editor_font := EditorInterface.get_base_control().get_theme_font("font", "Label")
	theme.default_font = editor_font
	for type in theme.get_type_list():
		for font_name in theme.get_font_list(type):
			theme.set_font(font_name, type, editor_font)
	content_scale_factor = editor_scale
	min_size = Vector2i(Vector2(880, 620) * editor_scale)
	size = Vector2i(Vector2(1120, 760) * editor_scale)
	close_requested.connect(_close)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var heading := Label.new()
	heading.text = "有限世界 · 从人工地块构建完整地图"
	heading.add_theme_font_size_override("font_size", 22)
	root.add_child(heading)
	var hint := Label.new()
	hint.text = "固定种子可复现　·　每格 2m　·　应用后可继续编辑、撤销、另存"
	root.add_child(hint)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 420
	root.add_child(split)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size.x = 405
	split.add_child(_tabs)
	var basic := _page("世界")
	_number(basic, "seed_value", "随机种子", 0, 2147483647, 1)
	_button(basic, "换一个种子", func():
		_inputs.seed_value.value = randi_range(0, 2147483647))
	_number(basic, "width", "宽 / 格", 16, 600, 1)
	_number(basic, "height", "高 / 格", 16, 600, 1)
	_size_label = _label(basic, "")
	_number(basic, "region_count", "生态区域数", 1, 64, 1)
	_number(basic, "boundary_noise", "边界起伏", 0, 1, 0.01)
	for spec in [["grass_weight", "草原权重"], ["rock_weight", "岩石权重"],
			["sand_weight", "沙漠权重"], ["water_weight", "海洋权重"]]:
		_number(basic, spec[0], spec[1], 0, 20, 0.5)
	_label(basic, "权重控制生态种子比例；出生核心始终有陆地。\n600格是数据上限，大图应用会增加3D重建耗时。")
	var zones := _page("功能区")
	_number(zones, "spawn_radius", "出生核心半径 / 格", 2, 290, 1)
	_number(zones, "static_count", "静止核心数", 0, 16, 1)
	_number(zones, "static_radius", "静止核心半径 / 格", 0, 600, 1)
	_number(zones, "falloff", "距离衰减 / 格", 0, 600, 1)
	_number(zones, "resource_density", "采集物 / 千格", 0, 50, 0.5)
	_number(zones, "environment_density", "环境物件 / 千格", 0, 50, 0.5)
	_number(zones, "cluster_gap", "资源簇间距 / 格", 1, 100, 1)
	_number(zones, "item_gap", "簇内物件间距 / 格", 1, 30, 1)
	_label(zones, "采集物仅在静止区散布；出生核心保持净空。\n密度是目标值，实际数量受生态与占地限制。\n功能区标签尚未接入正式战斗计时。")
	var special := _page("特殊地块")
	_number(special, "prefab_budget", "总预算 / 件", 0, 32, 1)
	_number(special, "prefab_gap", "最小间距 / 格", 1, 30, 1)
	_button(special, "添加已保存地图 / 预制…", func(): _choose("source"))
	_label(special, "完整复制地形、物件、空气层和阶梯。\n最少为必选，最多与权重控制额外投放。\n含食物/材料的格子必须落在静止区。")
	_source_rows = VBoxContainer.new()
	_source_rows.add_theme_constant_override("separation", 12)
	special.add_child(_source_rows)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_mode = OptionButton.new()
	for label in ["生态预览", "功能区预览", "通路预览"]:
		_mode.add_item(label)
	_mode.item_selected.connect(func(index: int): _preview.show_map(result, index))
	right.add_child(_mode)
	_preview = Preview.new()
	_preview.name = "WorldPreview"
	_preview.custom_minimum_size = Vector2(360, 280)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(_preview)
	_label(right, "白点 出生　白框 特殊地块　金线 通路 / 入口\n草原 绿 · 岩石 灰 · 沙漠 黄 · 海洋 蓝\n功能区：青色 静止区 · 棕色 探索战斗区")
	_report = RichTextLabel.new()
	_report.custom_minimum_size.y = 115
	_report.bbcode_enabled = false
	right.add_child(_report)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	var actions := HBoxContainer.new()
	root.add_child(actions)
	_button(actions, "加载配方…", func(): _choose("load"))
	_button(actions, "保存配方…", func(): _choose("save"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_cancel = _button(actions, "取消生成", _cancel_generation)
	_cancel.disabled = true
	_generate = _button(actions, "生成预览", _start)
	_generate.name = "GenerateWorld"
	_apply = _button(actions, "应用为新地图", _apply_result)
	_apply.name = "ApplyWorld"
	_apply.disabled = true
	_file = EditorFileDialog.new()
	_file.theme = EditorInterface.get_editor_theme()
	_file.access = EditorFileDialog.ACCESS_RESOURCES
	_file.filters = PackedStringArray(["*.tres ; 地图、预制或生成配方"])
	_file.file_selected.connect(_file_selected)
	add_child(_file)
	_sync()

func _page(label: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = label
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 9)
	scroll.add_child(box)
	return box

func _label(parent: Node, value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _number(parent: Node, key: String, label: String, low: float, high: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var title_label := Label.new()
	title_label.text = label
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	var spin := SpinBox.new()
	spin.name = key
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.custom_minimum_size.x = 145
	spin.value = config.get(key)
	row.add_child(spin)
	_inputs[key] = spin
	spin.value_changed.connect(func(value: float):
		if _loading:
			return
		config.set(key, int(value) if step == 1 else value)
		_changed())

func _sync() -> void:
	_loading = true
	for key in _inputs:
		_inputs[key].value = config.get(key)
	_loading = false
	_rebuild_sources()
	_changed()

func _changed() -> void:
	if _apply == null:
		return
	_apply.disabled = true
	_size_label.text = "%d × %d 米　·　%d 格" % [
		config.width * 2, config.height * 2, config.width * config.height]
	_status.text = "参数已改变，请重新生成；旧预览不可应用" if result != null else "设置参数，添加特殊地块后生成；也可先预览纯地形"

func _rebuild_sources() -> void:
	for child in _source_rows.get_children():
		child.queue_free()
		_source_rows.remove_child(child)
	for i in config.prefabs.size():
		var rule := config.prefabs[i]
		var panel := VBoxContainer.new()
		_source_rows.add_child(panel)
		var description := str(rule.path).get_file()
		if ResourceLoader.exists(str(rule.path)):
			var source := load(str(rule.path))
			var fragment: LevelData
			if source is LevelData:
				fragment = source
			elif source is LevelPrefab:
				fragment = source.fragment
			if fragment != null:
				description += " · %d×%d 格" % [fragment.map_size.x, fragment.map_size.y]
		_label(panel, description).tooltip_text = str(rule.path)
		var row := HBoxContainer.new()
		panel.add_child(row)
		for field in ["minimum", "maximum", "weight"]:
			var spin := SpinBox.new()
			spin.min_value = 0
			spin.max_value = 32
			spin.custom_minimum_size.x = 106
			spin.prefix = {"minimum": "至少 ", "maximum": "至多 ", "weight": "权重 "}[field]
			spin.value = rule.get(field, 1)
			row.add_child(spin)
			spin.value_changed.connect(func(value: float):
				rule[field] = int(value)
				_changed())
		var options := HBoxContainer.new()
		panel.add_child(options)
		var zone := OptionButton.new()
		for label in ["任意区域", "探索战斗区", "时间静止区"]:
			zone.add_item(label)
		zone.select(["any", "explore", "static"].find(rule.get("zone", "any")))
		zone.item_selected.connect(func(index: int):
			rule.zone = ["any", "explore", "static"][index]
			_changed())
		options.add_child(zone)
		var rotate := CheckBox.new()
		rotate.text = "旋转"
		rotate.button_pressed = rule.get("rotate", true)
		rotate.toggled.connect(func(value: bool):
			rule.rotate = value
			_changed())
		options.add_child(rotate)
		_button(options, "移除", func():
			config.prefabs.remove_at(i)
			_rebuild_sources()
			_changed())

func _choose(action: String) -> void:
	if _thread != null:
		return
	_file_action = action
	_file.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE if action == "save" else EditorFileDialog.FILE_MODE_OPEN_FILE
	_file.title = {"source": "选择已保存地图或预制", "load": "加载世界生成配方",
		"save": "保存世界生成配方"}[action]
	_file.current_path = "res://data/world_recipe.tres" if action == "save" else "res://data/"
	_file.popup_centered_ratio(0.75)

func _file_selected(path: String) -> void:
	if _file_action == "save":
		var error := ResourceSaver.save(config, path)
		_status.text = "配方已保存：" + path if error == OK else "配方保存失败：" + str(error)
		EditorInterface.get_resource_filesystem().scan()
		return
	var resource := load(path)
	if _file_action == "load":
		if resource is WorldGenConfig:
			config = resource.duplicate(true) as WorldGenConfig
			_sync()
			_status.text = "已加载配方，请重新生成"
		else:
			_status.text = "这不是世界生成配方"
		return
	if not resource is LevelData and not resource is LevelPrefab:
		_status.text = "请选择 LevelData 地图或 LevelPrefab 预制"
		return
	config.prefabs.append({"path": path, "minimum": 1, "maximum": 1,
		"weight": 1, "zone": "any", "rotate": true})
	_rebuild_sources()
	_changed()

func _start() -> void:
	if _thread != null:
		return
	_generator = WorldGenerator.new()
	var error := _generator.prepare(config)
	_apply.disabled = true
	if not error.is_empty():
		_status.text = "无法生成：" + error
		return
	_thread = Thread.new()
	_started = Time.get_ticks_msec()
	_busy(true)
	error = str(_thread.start(_generator.generate))
	if error != str(OK):
		_thread = null
		_busy(false)
		_status.text = "无法启动生成线程：" + error

func _process(_delta: float) -> void:
	if _thread == null:
		return
	_status.text = _generator.status() + "… %.1fs" % ((Time.get_ticks_msec() - _started) / 1000.0)
	if _thread.is_alive():
		return
	var output: Dictionary = _thread.wait_to_finish()
	_thread = null
	_busy(false)
	if not str(output.get("error", "")).is_empty():
		_status.text = str(output.error)
		return
	result = output.data
	_preview.show_map(result, _mode.selected)
	_apply.disabled = false
	var static_cells := (result.generation.zones as PackedByteArray).count(1)
	_report.text = "%d×%d 格 / %d×%d 米　种子 %d\n特殊地块 %d　物件 %d　通路 %d 格\n静止区 %.1f%%　草/岩/沙/海实际格数 %s\n%s" % [
		config.width, config.height, config.width * 2, config.height * 2, config.seed_value,
		result.generation.placements.size(), result.objects.size(), result.generation.roads.size(),
		100.0 * static_cells / (config.width * config.height), str(result.generation.biome_counts),
		"\n".join(output.warnings)]
	_status.text = "生成成功 · 校验通过 · %.2fs" % ((Time.get_ticks_msec() - _started) / 1000.0)

func _busy(value: bool) -> void:
	_generate.disabled = value
	_cancel.disabled = not value
	_tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
	for input in _inputs.values():
		input.editable = not value
	# Stop all parameter controls, including source-rule controls, while running.
	for control in _tabs.find_children("*", "BaseButton", true, false):
		control.disabled = value
	for control in _tabs.find_children("*", "SpinBox", true, false):
		control.editable = not value

func _cancel_generation() -> void:
	if _generator != null:
		_generator.cancel()
		_status.text = "正在取消…"

func _apply_result() -> void:
	if result == null or _apply.disabled:
		return
	map_ready.emit(result)

func confirm_applied() -> void:
	hide()
	_apply.disabled = true
	_status.text = "已应用为新地图；再次应用前请重新生成"

func _close() -> void:
	if _thread != null:
		_cancel_generation()
	hide()

func _exit_tree() -> void:
	if _thread != null:
		_generator.cancel()
		_thread.wait_to_finish()
		_thread = null
