@tool
extends EditorPlugin

enum ToolMode { GROUND, HEIGHT, ERASE, STAIR, SPAWN }

var dock: VBoxContainer
var mode_select: OptionButton
var terrain_select: OptionButton
var height_select: OptionButton
var brush_select: OptionButton
var status: Label
var dirty_label: Label
var file_dialog: EditorFileDialog
var confirm_dialog: ConfirmationDialog
var builder: TerrainBuilder
var data: LevelData
var current_path := ""
var dirty := false
var drawing := false
var stroke_before: Dictionary
var touched: Dictionary = {}
var stair_direction := 0
var preview: MeshInstance3D
var pending_action := ""
var world_tools
var dock_root: VBoxContainer
var last_stroke_cell := Vector2i(-999, -999)

func _enter_tree() -> void:
	_build_dock()
	world_tools = load("res://addons/terrain_editor/world_edit_tools.gd").new()
	dock_root = world_tools.setup(self)
	add_control_to_dock(DOCK_SLOT_LEFT_BR, dock_root)
	set_input_event_forwarding_always_enabled()
	if "--test-v2-editor" in OS.get_cmdline_user_args():
		_run_editor_checks.call_deferred()

func _run_editor_checks() -> void:
	await get_tree().process_frame
	var suite = load("res://tests/editor_v2_checks.gd").new()
	await suite.run(self)

func _exit_tree() -> void:
	if world_tools:
		world_tools.reset()
	if preview and is_instance_valid(preview):
		preview.queue_free()
	remove_control_from_docks(dock_root)
	dock_root.queue_free()
	world_tools = null

func _handles(object: Object) -> bool:
	return object is TerrainBuilder

func _edit(object: Object) -> void:
	if world_tools:
		world_tools.reset()
	if object is TerrainBuilder:
		builder = object
		data = builder.level_data
		if data:
			data.ensure_layout()
			current_path = data.resource_path
			_set_status("已载入：" + current_path)
			_make_preview()
	else:
		builder = null
		data = null
		if preview and is_instance_valid(preview):
			preview.queue_free()

func _build_dock() -> void:
	dock = VBoxContainer.new()
	dock.name = "地形编辑器"
	var title := Label.new()
	title.text = "畸变 关卡编辑器 v0.2"
	title.add_theme_font_size_override("font_size", 19)
	dock.add_child(title)
	dirty_label = Label.new()
	dock.add_child(dirty_label)
	var files := HBoxContainer.new()
	dock.add_child(files)
	for spec in [["新建", "_new_map"], ["打开", "_open_map"], ["保存", "_save_map"], ["另存为", "_save_as"]]:
		var button := Button.new()
		button.text = spec[0]
		button.pressed.connect(Callable(self, spec[1]))
		files.add_child(button)
	mode_select = _option("工具", ["地面", "高度", "擦除", "阶梯", "出生点"])
	terrain_select = _option("地表", ["草地", "岩地"])
	height_select = _option("高度", ["0m", "2m", "4m"])
	brush_select = _option("画笔", ["1×1", "3×3"])
	var rotate := HBoxContainer.new()
	dock.add_child(rotate)
	var rotate_label := Label.new()
	rotate_label.text = "阶梯方向"
	rotate.add_child(rotate_label)
	for spec in [["Q 左转", -1], ["E 右转", 1]]:
		var button := Button.new()
		button.text = spec[0]
		button.pressed.connect(_rotate_stair.bind(spec[1]))
		rotate.add_child(button)
	var grid := CheckBox.new()
	grid.text = "显示编辑格线"
	grid.button_pressed = true
	grid.toggled.connect(_toggle_grid)
	dock.add_child(grid)
	var play := Button.new()
	play.text = "保存并试玩当前地图"
	play.pressed.connect(_playtest)
	dock.add_child(play)
	var help := Label.new()
	help.text = "左键点击/拖动绘制\nQ/E 旋转阶梯；右键保留视口导航\n先在场景树选择 TerrainBuilder"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(help)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 70
	dock.add_child(status)
	file_dialog = EditorFileDialog.new()
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.add_filter("*.tres", "LevelData")
	file_dialog.file_selected.connect(_file_selected)
	file_dialog.canceled.connect(func(): pending_action = "")
	dock.add_child(file_dialog)
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "未保存的地图"
	confirm_dialog.dialog_text = "当前地图尚未保存。确定放弃修改吗？"
	confirm_dialog.confirmed.connect(_discard_pending)
	confirm_dialog.canceled.connect(func(): pending_action = "")
	confirm_dialog.add_button("保存后继续", false, "save")
	confirm_dialog.custom_action.connect(_save_pending)
	dock.add_child(confirm_dialog)
	_update_dirty()

func _option(label_text: String, items: Array[String]) -> OptionButton:
	var row := HBoxContainer.new()
	dock.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 70
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		option.add_item(item)
	row.add_child(option)
	return option

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_instance_valid(builder) or data == null:
		return AFTER_GUI_INPUT_PASS
	if world_tools.active():
		return world_tools.handle(camera, event)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_rotate_stair(-1)
			return AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_E:
			_rotate_stair(1)
			return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			return AFTER_GUI_INPUT_PASS
		var cell := _pick_cell(camera, event.position)
		_update_preview(cell)
		if drawing and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_apply_line(cell)
			return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _pick_cell(camera, event.position)
		if event.pressed:
			drawing = true
			stroke_before = data.clone_data()
			touched.clear()
			last_stroke_cell = cell
			_apply_brush(cell)
		else:
			if drawing:
				drawing = false
				_commit_stroke()
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS

func _pick_cell(camera: Camera3D, mouse: Vector2) -> Vector2i:
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 1000.0)
	var result := builder.get_world_3d().direct_space_state.intersect_ray(query)
	if result and result.collider and result.collider.has_meta("terrain_cell"):
		return result.collider.get_meta("terrain_cell")
	var plane_y := height_select.selected * LevelData.ELEVATION_STEP
	if absf(direction.y) < 0.0001:
		return Vector2i(-999, -999)
	var distance := (plane_y - origin.y) / direction.y
	if distance < 0:
		return Vector2i(-999, -999)
	return data.world_to_cell(origin + direction * distance)

func _brush_cells(center: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var radius := 0 if brush_select.selected == 0 else 1
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var cell := Vector2i(x, y)
			if data.in_bounds(cell):
				result.append(cell)
	return result

func _apply_brush(center: Vector2i) -> void:
	if not data.in_bounds(center):
		return
	var mode := mode_select.selected
	if mode == ToolMode.STAIR:
		if touched.has(center):
			return
		touched[center] = true
		if _object_occupies(center) or _object_occupies(center + LevelData.DIRS[stair_direction]):
			_set_status("物件占用该区域，请先移动或删除物件")
			return
		var error := data.can_place_stair(center, stair_direction)
		if not error.is_empty():
			_set_status(error)
			return
		data.stairs.append({"cell": center, "direction": stair_direction})
		data.emit_changed()
		builder.rebuild()
		return
	for cell in _brush_cells(center):
		if touched.has(cell):
			continue
		touched[cell] = true
		if mode == ToolMode.SPAWN:
			if data.cell_exists(cell) and data.stair_at(cell) < 0:
				var old_spawn := data.spawn_cell
				data.spawn_cell = cell
				if not ObjectRules.validate_all(data).is_empty():
					data.spawn_cell = old_spawn
					_set_status("出生点与阻挡物冲突")
				data.emit_changed()
			else:
				_set_status("出生点只能放在普通地块顶面")
			continue
		var stair_index := data.stair_at(cell)
		if stair_index >= 0:
			if mode == ToolMode.ERASE:
				data.stairs.remove_at(stair_index)
				data.emit_changed()
			else:
				_set_status("该格被阶梯占用，请先用擦除工具删除阶梯")
			continue
		var value := data.get_cell(cell).duplicate(true)
		if _object_occupies(cell) and (mode == ToolMode.ERASE or (
				mode in [ToolMode.GROUND, ToolMode.HEIGHT] and data.elevation(cell) != height_select.selected)):
			_set_status("该地块支撑物件，请先移动或删除物件")
			continue
		match mode:
			ToolMode.GROUND:
				value = {"exists": true, "terrain": terrain_select.selected,
					"height": height_select.selected}
			ToolMode.HEIGHT:
				if bool(value.get("exists", false)):
					value["height"] = height_select.selected
			ToolMode.ERASE:
				value["exists"] = false
				if data.spawn_cell == cell:
					data.spawn_cell = Vector2i(-1, -1)
		data.set_cell(cell, value)
	builder.rebuild()

func _commit_stroke() -> void:
	var after := data.clone_data()
	_commit_external(stroke_before, after, "编辑地形")

func _commit_external(before: Dictionary, after: Dictionary, label: String) -> void:
	if after == before:
		return
	var undo := get_undo_redo()
	undo.create_action(label, UndoRedo.MERGE_DISABLE, data)
	undo.add_do_method(self, "_restore_target", data, after)
	undo.add_undo_method(self, "_restore_target", data, before)
	undo.add_do_reference(data)
	undo.commit_action()

func _restore_target(target: LevelData, snapshot: Dictionary) -> void:
	target.restore_data(snapshot)
	if target == data and is_instance_valid(builder):
		builder.rebuild()
		_mark_dirty()
		if world_tools:
			world_tools.clear_ghost()

func _object_occupies(cell: Vector2i) -> bool:
	for record in data.objects:
		if cell in ObjectRules.covered_cells(data, record):
			return true
	return false

func _apply_line(cell: Vector2i) -> void:
	if not data.in_bounds(cell):
		return
	if not data.in_bounds(last_stroke_cell):
		last_stroke_cell = cell
	var difference := cell - last_stroke_cell
	var steps := maxi(absi(difference.x), absi(difference.y))
	for step in range(1, steps + 1):
		_apply_brush(Vector2i(Vector2(last_stroke_cell).lerp(Vector2(cell), float(step) / steps).round()))
	last_stroke_cell = cell

func _make_preview() -> void:
	if preview and is_instance_valid(preview):
		preview.queue_free()
	preview = MeshInstance3D.new()
	preview.name = "TerrainBrushPreview"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(LevelData.CELL_SIZE, 0.08, LevelData.CELL_SIZE)
	preview.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.85, 1.0, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview.material_override = material
	builder.add_child(preview)

func _update_preview(cell: Vector2i) -> void:
	if preview == null or not is_instance_valid(preview):
		return
	preview.visible = data.in_bounds(cell)
	if not preview.visible:
		return
	var level := data.elevation(cell) if data.cell_exists(cell) else height_select.selected
	preview.position = data.world_center(cell, level) + Vector3(0, 0.08, 0)
	var brush_scale := 1.0 if brush_select.selected == 0 else 3.0
	preview.scale = Vector3(brush_scale, 1, brush_scale)
	var material := preview.material_override as StandardMaterial3D
	var invalid := mode_select.selected == ToolMode.STAIR and not data.can_place_stair(cell, stair_direction).is_empty()
	material.albedo_color = Color(1.0, 0.2, 0.2, 0.42) if invalid else Color(0.25, 0.85, 1.0, 0.35)

func _rotate_stair(delta: int) -> void:
	stair_direction = posmod(stair_direction + delta, 4)
	_set_status("阶梯方向：" + ["北", "东", "南", "西"][stair_direction])

func _toggle_grid(value: bool) -> void:
	if builder:
		builder.show_grid = value
		builder.rebuild()
		_make_preview()

func _new_map() -> void:
	if _guard_dirty("new"):
		return
	_do_new()

func _do_new() -> void:
	if builder == null:
		_set_status("请先打开 terrain_editor_test.tscn 并选择 TerrainBuilder")
		return
	world_tools.reset()
	data = LevelData.new()
	data.setup_blank()
	builder.level_data = data
	builder.rebuild()
	current_path = ""
	dirty = true
	_update_dirty()
	_make_preview()

func _open_map() -> void:
	if _guard_dirty("open"):
		return
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.popup_centered_ratio(0.7)

func _save_map() -> bool:
	if data == null:
		return false
	if current_path.is_empty():
		_save_as()
		return false
	var result := ResourceSaver.save(data, current_path)
	if result != OK:
		dirty = true
		_update_dirty()
		_set_status("保存失败：错误码 %d" % result)
		return false
	dirty = false
	_update_dirty()
	_set_status("已保存：" + current_path)
	return true

func _save_as() -> void:
	if data == null:
		return
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_file = "new_level.tres"
	file_dialog.popup_centered_ratio(0.7)

func _file_selected(path: String) -> void:
	if file_dialog.file_mode == EditorFileDialog.FILE_MODE_SAVE_FILE:
		var previous_path := current_path
		current_path = path
		if not _save_map():
			current_path = previous_path
			_update_dirty()
		elif not pending_action.is_empty():
			_discard_pending()
		return
	var loaded := load(path) as LevelData
	if loaded == null:
		_set_status("不是有效的 LevelData：" + path)
		return
	world_tools.reset()
	data = loaded
	data.ensure_layout()
	builder.level_data = data
	builder.rebuild()
	current_path = path
	dirty = false
	_update_dirty()
	_make_preview()

func _guard_dirty(action: String) -> bool:
	if not dirty:
		return false
	pending_action = action
	confirm_dialog.popup_centered()
	return true

func _discard_pending() -> void:
	if pending_action == "new":
		_do_new()
	elif pending_action == "open":
		# Keep the old map and dirty flag until a replacement actually loads.
		file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		file_dialog.popup_centered_ratio(0.7)
	pending_action = ""

func _save_pending(_action: StringName) -> void:
	confirm_dialog.hide()
	if _save_map():
		_discard_pending()

func _playtest() -> void:
	if data == null:
		return
	var errors := data.validate()
	if not errors.is_empty():
		_set_status("无法试玩：\\n" + "\\n".join(errors))
		return
	if current_path.is_empty():
		_set_status("请先另存地图，再开始试玩")
		_save_as()
		return
	if not _save_map():
		return
	var request := ConfigFile.new()
	request.set_value("playtest", "level", current_path)
	if request.save("user://terrain_playtest.cfg") != OK:
		_set_status("无法写入本地试玩请求")
		return
	get_editor_interface().play_custom_scene("res://scenes/level_playtest.tscn")

func _mark_dirty() -> void:
	dirty = true
	_update_dirty()

func _update_dirty() -> void:
	dirty_label.text = ("● 未保存" if dirty else "✓ 已保存") + (
		"　" + current_path if not current_path.is_empty() else "　未命名地图")

func _set_status(message: String) -> void:
	status.text = message
