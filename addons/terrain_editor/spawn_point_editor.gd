@tool
extends VBoxContainer

signal edited(before: Array[Dictionary], after: Array[Dictionary])
signal message(text: String)
signal overlay_changed

var data: LevelData
var selected_id := ""
var draft := {}
var drawing := false
var before: Array[Dictionary] = []
var touched := {}
var choice: OptionButton
var mode: OptionButton
var title_edit: LineEdit
var limit: SpinBox
var radius_control: SpinBox
var enabled: CheckButton
var info: Label
var syncing := false

func _init() -> void:
	name = "SpawnPointEditor"
	add_theme_constant_override("separation", 8)
	var hint := Label.new()
	hint.text = "新增刷新点 → 左键绘制相邻格 → 保存试玩\n玩家进入范围后每30秒补充1～2只，默认存活上限2只。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	var actions := HBoxContainer.new()
	add_child(actions)
	_button(actions, "新增刷新点", "NewSpawnPoint", new_point)
	_button(actions, "删除", "DeleteSpawnPoint", delete_point)
	choice = OptionButton.new()
	choice.name = "SpawnPointChoice"
	choice.item_selected.connect(func(index: int):
		finish_stroke()
		draft = {}
		selected_id = str(choice.get_item_metadata(index))
		mode.select(0)
		refresh())
	add_child(choice)
	mode = OptionButton.new()
	mode.name = "SpawnPointMode"
	for text in ["选择点 · 点击已有范围", "绘制范围 · 左键拖动", "擦除范围 · 左键拖动"]:
		mode.add_item(text)
	mode.item_selected.connect(func(_index: int): finish_stroke())
	add_child(mode)
	title_edit = LineEdit.new()
	title_edit.name = "SpawnPointName"
	title_edit.placeholder_text = "刷新点名称"
	title_edit.text_submitted.connect(func(value: String): _property("name", value.strip_edges()))
	title_edit.focus_exited.connect(func(): _property("name", title_edit.text.strip_edges()))
	add_child(title_edit)
	enabled = CheckButton.new()
	enabled.name = "SpawnPointEnabled"
	enabled.text = "启用选中刷新点"
	enabled.toggled.connect(func(value: bool): _property("enabled", value))
	add_child(enabled)
	limit = SpinBox.new()
	limit.name = "SpawnPointAliveLimit"
	limit.min_value = 1
	limit.max_value = 20
	limit.prefix = "存活上限 "
	limit.value_changed.connect(func(value: float): _property("max_alive", int(value)))
	add_child(limit)
	radius_control = SpinBox.new()
	radius_control.name = "SpawnPointActivationRadius"
	radius_control.min_value = 0
	radius_control.max_value = 2000
	radius_control.step = 1
	radius_control.prefix = "激活 / 追踪半径 "
	radius_control.suffix = "m"
	radius_control.tooltip_text = "0 = 自动：试玩相机可视地面范围 + 4m。\n刷新与追踪使用同一圆形范围；玩家离开后暂停计时、怪物返回点。"
	radius_control.value_changed.connect(func(value: float): _property("activation_radius", value))
	add_child(radius_control)
	info = Label.new()
	info.name = "SpawnPointInfo"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info)
	refresh()

func _button(parent: Node, text: String, node_name: String, callback: Callable) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)

func bind(value: LevelData) -> void:
	if drawing:
		finish_stroke()
	if data != value:
		selected_id = ""
		draft = {}
	data = value
	if data != null and not draft.is_empty() \
			and not MonsterSpawnPoints.find(data, str(draft.id)).is_empty():
		draft = {}
	refresh()

func current() -> Dictionary:
	return draft if not draft.is_empty() else MonsterSpawnPoints.find(data, selected_id) \
		if data != null else {}

func refresh() -> void:
	if choice == null:
		return
	syncing = true
	choice.clear()
	if data != null:
		for point in data.monster_spawn_points:
			choice.add_item("%s · %d格" % [point.get("name", "刷新点"), point.cells.size()])
			choice.set_item_metadata(choice.item_count - 1, str(point.id))
			if str(point.id) == selected_id:
				choice.select(choice.item_count - 1)
	if not draft.is_empty():
		choice.add_item(str(draft.name) + " · 待绘制")
		choice.set_item_metadata(choice.item_count - 1, str(draft.id))
		choice.select(choice.item_count - 1)
	elif current().is_empty() and data != null and not data.monster_spawn_points.is_empty():
		selected_id = str(data.monster_spawn_points[0].id)
		choice.select(0)
	var point := current()
	title_edit.editable = not point.is_empty()
	title_edit.text = str(point.get("name", ""))
	enabled.disabled = point.is_empty()
	enabled.set_pressed_no_signal(bool(point.get("enabled", true)))
	limit.editable = not point.is_empty()
	limit.set_value_no_signal(int(point.get("max_alive", 2)))
	radius_control.editable = not point.is_empty()
	radius_control.set_value_no_signal(float(point.get("activation_radius", 0.0)))
	if point.is_empty():
		info.text = "尚无刷新点。未设置点时，本地图不刷新普通怪。\n静止区允许固定点刷新；禁刷区阻止刷新。"
	elif point.cells.is_empty():
		info.text = "在地图上点击第一格，再沿同层相邻格拖动扩大范围。"
	else:
		var ecologies := PackedStringArray()
		for ecology in MonsterSpawnPoints.ecosystems(data, point):
			ecologies.append(MonsterSpawnPoints.ECOLOGY_NAMES.get(ecology, ecology))
		var config := data.encounter if data.encounter != null else EncounterConfig.default_config()
		var names := MonsterSpawnPoints.species(data, point, config)
		var blocked: bool = point.cells.any(func(cell: Vector3i):
			return not data.is_surface_exposed(Vector2i(cell.x, cell.z), cell.y))
		info.text = "%d格 · 第%d层 · %s\n可刷新：%s" % [point.cells.size(), point.cells[0].y,
			" / ".join(ecologies), "、".join(names) if not names.is_empty() else "无；请检查怪池、禁刷或障碍"]
		if blocked:
			info.text += "\n部分格被上层遮挡，保留记录；露出后恢复刷新。"
		var focus := data.world_center(data.spawn_cell, data.spawn_layer) \
			if data.in_bounds(data.spawn_cell) else MonsterSpawnPoints.center(data, point)
		var radius := MonsterSpawnPoints.radius(data, point, focus)
		info.text += "\n同一激活/追踪圈：%s。离开暂停，怪物回点。" % (
			"自动（随试玩相机调整，可视边界+4m）" if float(point.get("activation_radius", 0)) == 0
			else "%.0fm" % radius)
	syncing = false
	overlay_changed.emit()

func new_point() -> void:
	finish_stroke()
	if data == null:
		message.emit("请先打开地图或生成预览")
		return
	draft = MonsterSpawnPoints.create("刷新点%d" % (data.monster_spawn_points.size() + 1))
	selected_id = str(draft.id)
	mode.select(1)
	refresh()

func delete_point() -> void:
	finish_stroke()
	if data == null or current().is_empty():
		return
	var old := data.monster_spawn_points.duplicate(true)
	for i in range(data.monster_spawn_points.size() - 1, -1, -1):
		if str(data.monster_spawn_points[i].id) == selected_id:
			data.monster_spawn_points.remove_at(i)
	draft = {}
	selected_id = ""
	if old != data.monster_spawn_points:
		edited.emit(old, data.monster_spawn_points.duplicate(true))
	refresh()

func _property(field: String, value: Variant) -> void:
	if syncing or data == null or current().is_empty() or drawing:
		return
	if field == "name" and str(value).is_empty():
		return
	if current().get(field) == value:
		return
	var old := data.monster_spawn_points.duplicate(true)
	current()[field] = value
	if draft.is_empty():
		edited.emit(old, data.monster_spawn_points.duplicate(true))
	refresh.call_deferred()

func begin_stroke() -> void:
	if data == null or mode.selected == 0:
		return
	drawing = true
	before = data.monster_spawn_points.duplicate(true)
	touched.clear()

func paint(cell: Vector3i) -> void:
	if data == null:
		return
	if mode.selected == 0:
		for point in data.monster_spawn_points:
			if cell in point.cells:
				selected_id = str(point.id)
				draft = {}
				refresh()
				return
		return
	if not drawing or touched.has(cell):
		return
	var point := current()
	if point.is_empty():
		message.emit("先新增或选择一个刷新点")
		return
	var error := MonsterSpawnPoints.edit(data, point, cell, mode.selected == 2)
	if not error.is_empty():
		message.emit(error)
		return
	touched[cell] = true
	if not draft.is_empty() and not point.cells.is_empty():
		data.monster_spawn_points.append(point)
		draft = {}
	elif point.cells.is_empty() and draft.is_empty():
		draft = point.duplicate(true)
		data.monster_spawn_points.erase(point)
	refresh()

func finish_stroke() -> void:
	if not drawing:
		return
	drawing = false
	if data != null and before != data.monster_spawn_points:
		edited.emit(before.duplicate(true), data.monster_spawn_points.duplicate(true))
	refresh()
