@tool
extends RefCounted

var host: EditorPlugin
var tabs: TabContainer
var library: ItemList
var paths: Array[String] = []
var object_mode: OptionButton
var scale_input: SpinBox
var yaw_input: SpinBox
var snap: CheckBox
var selected_id := ""
var dragging := false
var drag_before: Dictionary
var prefab: LevelPrefab
var prefab_mode: OptionButton
var objects_only: CheckBox
var prefab_turns := 0
var region_start := Vector2i(-1, -1)
var region := Rect2i()
var prefab_dialog: EditorFileDialog
var ghost: Node3D
var last_cell := Vector2i(-999, -999)
var last_candidate: Dictionary = {}
var clipboard: Dictionary = {}
var search: LineEdit
var selected_label: Label

func setup(plugin: EditorPlugin) -> VBoxContainer:
	host = plugin
	var root := VBoxContainer.new()
	root.name = "关卡编辑器"
	root.custom_minimum_size.x = 310
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	var terrain: VBoxContainer = host.dock
	terrain.name = "地形"
	_page("地形", terrain)
	var importer = load("res://addons/terrain_editor/asset_import_dock.gd").new()
	_page("导入", importer)
	importer.generated.connect(func(_path: String): refresh_library())
	var object_page := VBoxContainer.new()
	_page("物件", object_page)
	_label(object_page, "图片保持固定相机外观；旋转会改变纸片朝向。\n单视角资产不保证任意旋转仍能还原原画。")
	search = LineEdit.new()
	search.placeholder_text = "搜索物件名称 / 分类"
	search.text_changed.connect(func(_text: String): refresh_library())
	object_page.add_child(search)
	library = ItemList.new()
	library.custom_minimum_size.y = 180
	library.icon_mode = ItemList.ICON_MODE_LEFT
	library.fixed_icon_size = Vector2i(48, 48)
	library.item_selected.connect(func(_index: int): object_mode.selected = 0; clear_ghost())
	object_page.add_child(library)
	_button(object_page, "刷新物件库", refresh_library)
	object_mode = _option(object_page, ["放置：左键连续放置", "选择 / 拖动移动：左键"])
	snap = CheckBox.new()
	snap.text = "吸附 2m 格中心（Shift 临时关闭）"
	snap.button_pressed = true
	object_page.add_child(snap)
	yaw_input = _spin(object_page, "旋转角度（Q/E 每次 90°）", -360, 360, 15, 0)
	scale_input = _spin(object_page, "统一缩放", 0.25, 4, 0.25, 1)
	selected_label = _label(object_page, "未选择物件")
	_button(object_page, "应用旋转 / 缩放到选中物件", apply_transform)
	_button(object_page, "复制选中（Ctrl/Cmd+C）", copy_selected)
	_button(object_page, "粘贴为待放置物件（Ctrl/Cmd+V）", paste_selected)
	_button(object_page, "删除选中（Delete）", delete_selected)
	_button(object_page, "校验地图", validate_map)
	var prefab_page := VBoxContainer.new()
	_page("预制", prefab_page)
	_label(prefab_page, "框选矩形包含地形、阶梯和物件；不带玩家出生点。\n保存选区后，打开预制即可重复投放。\n覆盖地形会替换整个矩形（含空格），不自动融合。")
	prefab_mode = _option(prefab_page, ["框选：点击起点，再点击终点", "投放预制：左键投放，Q/E 旋转"])
	_button(prefab_page, "保存选区为营地预制", save_region)
	_button(prefab_page, "打开营地预制", open_prefab)
	objects_only = CheckBox.new()
	objects_only.text = "仅投放物件（贴合目标地块高度）"
	prefab_page.add_child(objects_only)
	_button(prefab_page, "左转 90°", rotate_prefab.bind(-1))
	_button(prefab_page, "右转 90°", rotate_prefab.bind(1))
	prefab_dialog = EditorFileDialog.new()
	prefab_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	prefab_dialog.add_filter("*.tres", "LevelPrefab")
	prefab_dialog.file_selected.connect(_prefab_file)
	root.add_child(prefab_dialog)
	# Keep status/save/play reachable regardless of which tab is active.
	terrain.remove_child(host.status)
	root.add_child(host.status)
	_button(root, "保存地图", host._save_map)
	_button(root, "保存并试玩当前地图", host._playtest)
	tabs.tab_changed.connect(func(_index: int): clear_ghost(); region_start = Vector2i(-1, -1))
	refresh_library()
	return root

func _page(title: String, content: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)

func _option(parent: Node, items: Array[String]) -> OptionButton:
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	parent.add_child(option)
	return option

func _spin(parent: Node, title: String, low: float, high: float, step: float, value: float) -> SpinBox:
	_label(parent, title)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	parent.add_child(spin)
	return spin

func refresh_library() -> void:
	if library == null:
		return
	library.clear()
	paths.clear()
	for path in ObjectRules.library():
		var d := load(path) as PlaceableDefinition
		if d == null or (not search.text.is_empty() and not (d.display_name + d.category).containsn(search.text)):
			continue
		paths.append(path)
		var texture := load(d.source_image) as Texture2D
		library.add_item("%s · %s" % [d.display_name, d.category], texture)
	if library.item_count > 0:
		library.select(0)

func active() -> bool:
	return tabs.current_tab != 0

func clear_ghost() -> void:
	if is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null
	last_cell = Vector2i(-999, -999)

func reset() -> void:
	clear_ghost()
	selected_id = ""
	dragging = false
	region_start = Vector2i(-1, -1)
	region = Rect2i()

func _selected_index() -> int:
	if host.data == null:
		return -1
	for i in host.data.objects.size():
		if str(host.data.objects[i].get("id", "")) == selected_id:
			return i
	return -1

func _point(camera: Camera3D, mouse: Vector2, free_move: bool) -> Vector3:
	var data: LevelData = host.data
	var origin := camera.project_ray_origin(mouse)
	var ray := camera.project_ray_normal(mouse)
	var best := INF
	var result := Vector3(INF, INF, INF)
	if absf(ray.y) < 0.00001:
		return result
	# Pick terrain surfaces geometrically: props and cliff walls never hide the brush.
	for elevation: int in [2, 1, 0]:
		var distance := (elevation * LevelData.ELEVATION_STEP - origin.y) / ray.y
		if distance < 0 or distance >= best:
			continue
		var p := origin + ray * distance
		var cell := data.world_to_cell(p)
		if data.cell_exists(cell) and data.elevation(cell) == elevation:
			result = p if free_move else data.world_center(cell)
			best = distance
	if is_inf(best):
		var distance: float = (host.height_select.selected * LevelData.ELEVATION_STEP - origin.y) / ray.y
		result = origin + ray * maxf(distance, 0)
		if not free_move:
			result = data.world_center(data.world_to_cell(result), host.height_select.selected)
	return result

func _pick_object(camera: Camera3D, mouse: Vector2) -> String:
	var origin := camera.project_ray_origin(mouse)
	var ray := camera.project_ray_normal(mouse)
	var best := INF
	var id := ""
	if not is_instance_valid(host.builder.generated):
		return id
	for object in host.builder.generated.get_children():
		if not object.has_meta("object_id"):
			continue
		for child in object.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			var inverse := mesh.global_transform.affine_inverse()
			var hit: Variant = mesh.get_aabb().grow(0.1).intersects_ray(inverse * origin, inverse.basis * ray)
			if hit == null:
				continue
			var distance := origin.distance_to(mesh.global_transform * (hit as Vector3))
			if distance < best:
				best = distance
				id = object.get_meta("object_id")
	return id

func _candidate(position: Vector3) -> Dictionary:
	var chosen := library.get_selected_items()
	if chosen.is_empty() or chosen[0] >= paths.size():
		return {}
	return {"id": ObjectRules.new_id(), "definition": paths[chosen[0]], "position": position,
		"yaw": deg_to_rad(yaw_input.value), "scale": scale_input.value}

func handle(camera: Camera3D, event: InputEvent) -> int:
	if host.preview and is_instance_valid(host.preview):
		host.preview.visible = false
	if tabs.current_tab == 1:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_Q, KEY_E]:
			var delta := -1 if event.keycode == KEY_Q else 1
			if tabs.current_tab == 3:
				rotate_prefab(delta)
			else:
				yaw_input.value = wrapf(yaw_input.value + delta * 90, -360, 360)
				if object_mode.selected == 1:
					apply_transform()
			clear_ghost()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if tabs.current_tab == 2:
			if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
				delete_selected()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.ctrl_pressed or event.meta_pressed:
				if event.keycode == KEY_C:
					copy_selected()
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				if event.keycode == KEY_V:
					paste_selected()
					return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		var point := _point(camera, event.position, not snap.button_pressed or event.shift_pressed)
		if not point.is_finite():
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if tabs.current_tab == 2:
			if dragging:
				_move_selected(point)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if object_mode.selected == 0:
				_preview_object(_candidate(point))
		else:
			_preview_prefab(host.data.world_to_cell(point))
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var point := _point(camera, event.position, not snap.button_pressed or event.shift_pressed)
		if not point.is_finite():
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if tabs.current_tab == 2:
			if object_mode.selected == 0 and event.pressed:
				place_object(_candidate(point))
			elif object_mode.selected == 1:
				if event.pressed:
					selected_id = _pick_object(camera, event.position)
					var index := _selected_index()
					if index >= 0:
						yaw_input.value = rad_to_deg(float(host.data.objects[index].get("yaw", 0)))
						scale_input.value = float(host.data.objects[index].get("scale", 1))
						selected_label.text = "选中：" + selected_id.left(8)
						drag_before = host.data.clone_data()
						dragging = true
						_preview_object(host.data.objects[index], selected_id)
				elif dragging:
					dragging = false
					host._commit_external(drag_before, host.data.clone_data(), "移动物件")
		elif event.pressed:
			_prefab_click(host.data.world_to_cell(point))
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _preview_object(record: Dictionary, ignore := "") -> void:
	clear_ghost()
	if record.is_empty():
		return
	var d := ObjectRules.definition(record)
	if d == null:
		return
	var error := ObjectRules.validate_record(host.data, record, ignore)
	ghost = AssetFactory.make_asset(d)
	for body in ghost.find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 0
		body.collision_mask = 0
	ghost.position = record["position"]
	ghost.rotation.y = record["yaw"]
	ghost.scale = Vector3.ONE * float(record["scale"])
	for mesh in ghost.find_children("*", "MeshInstance3D", true, false):
		var mat := (mesh.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.5, 1, 0.7, 0.5) if error.is_empty() else Color(1, 0.2, 0.2, 0.5)
		mesh.material_override = mat
	host.builder.add_child(ghost)
	var footprint := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(maxf(d.collision_size.x, 0.3), 0.06, maxf(d.collision_size.z, 0.3))
	footprint.mesh = box
	footprint.position = Vector3(d.collision_offset.x, 0.08, d.collision_offset.z)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 1, 0.5, 0.5) if error.is_empty() else Color(1, 0.2, 0.2, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	footprint.material_override = mat
	ghost.add_child(footprint)
	host._set_status("绿色：可以放置" if error.is_empty() else error)

func place_object(record: Dictionary) -> void:
	if record.is_empty():
		host._set_status("请先导入或选择物件")
		return
	var error := ObjectRules.validate_record(host.data, record)
	if not error.is_empty():
		host._set_status(error)
		return
	var before: Dictionary = host.data.clone_data()
	host.data.objects.append(record)
	host._commit_external(before, host.data.clone_data(), "放置物件")

func _move_selected(point: Vector3) -> void:
	var index := _selected_index()
	if index < 0:
		return
	var record: Dictionary = host.data.objects[index].duplicate(true)
	record["position"] = point
	var error := ObjectRules.validate_record(host.data, record, selected_id)
	_preview_object(record, selected_id)
	if not error.is_empty():
		return
	host.data.objects[index] = record
	host.builder.rebuild()

func apply_transform() -> void:
	var index := _selected_index()
	if index < 0:
		return
	var record: Dictionary = host.data.objects[index].duplicate(true)
	record["yaw"] = deg_to_rad(yaw_input.value)
	record["scale"] = scale_input.value
	var error := ObjectRules.validate_record(host.data, record, selected_id)
	if not error.is_empty():
		host._set_status(error)
		return
	var before: Dictionary = host.data.clone_data()
	host.data.objects[index] = record
	host._commit_external(before, host.data.clone_data(), "调整物件")
	_preview_object(record, selected_id)

func delete_selected() -> void:
	var index := _selected_index()
	if index < 0:
		return
	var before: Dictionary = host.data.clone_data()
	host.data.objects.remove_at(index)
	host._commit_external(before, host.data.clone_data(), "删除物件")
	selected_id = ""
	selected_label.text = "未选择物件"
	clear_ghost()

func copy_selected() -> void:
	var index := _selected_index()
	if index >= 0:
		clipboard = host.data.objects[index].duplicate(true)
		host._set_status("已复制，粘贴后在视口点击目标地块")

func paste_selected() -> void:
	if clipboard.is_empty():
		return
	var index := paths.find(clipboard["definition"])
	if index < 0:
		search.text = ""
		refresh_library()
		index = paths.find(clipboard["definition"])
	if index < 0:
		return
	library.select(index)
	yaw_input.value = rad_to_deg(float(clipboard["yaw"]))
	scale_input.value = clipboard["scale"]
	object_mode.selected = 0

func validate_map() -> void:
	if host.data == null:
		return
	var errors: PackedStringArray = host.data.validate()
	host._set_status("校验通过" if errors.is_empty() else "\n".join(errors))

func rotate_prefab(delta: int) -> void:
	prefab_turns = posmod(prefab_turns + delta, 4)
	clear_ghost()
	host._set_status("预制旋转 %d°" % (prefab_turns * 90))

func _prefab_click(cell: Vector2i) -> void:
	if not host.data.in_bounds(cell):
		return
	if prefab_mode.selected == 0:
		if region_start.x < 0:
			region_start = cell
			host._set_status("请选择选区终点")
		else:
			region = Rect2i(region_start.min(cell), (cell - region_start).abs() + Vector2i.ONE)
			region_start = Vector2i(-1, -1)
			host._set_status("选区 %s，大小 %s；点击“保存选区”" % [region.position, region.size])
			_region_preview(region, true)
	elif prefab != null:
		var result := prefab.stamp(host.data, cell, prefab_turns, objects_only.button_pressed)
		if not result["error"].is_empty():
			host._set_status(result["error"])
			return
		host._commit_external(host.data.clone_data(), result["snapshot"], "投放营地预制")

func _preview_prefab(cell: Vector2i) -> void:
	if cell == last_cell:
		return
	if prefab_mode.selected == 0:
		if region_start.x >= 0:
			_region_preview(Rect2i(region_start.min(cell), (cell - region_start).abs() + Vector2i.ONE), true)
	elif prefab != null:
		var result := prefab.stamp(host.data, cell, prefab_turns, objects_only.button_pressed)
		var valid: bool = result["error"].is_empty()
		_region_preview(Rect2i(cell, prefab.rotated_size(prefab_turns)), valid)
		if valid:
			var snapshot := LevelData.new()
			snapshot.restore_data(result["snapshot"])
			# Preview just the incoming fragment, not a duplicate of the whole map.
			var capture := LevelPrefab.capture(snapshot, Rect2i(cell, prefab.rotated_size(prefab_turns)))
			if capture["error"].is_empty():
				var fragment: LevelData = capture["prefab"].fragment
				var display := TerrainBuilder.new()
				display.level_data = fragment
				display.show_grid = false
				display.build_collision = false
				var a: Vector3 = host.data.world_center(cell, 0)
				display.position = a - fragment.world_center(Vector2i.ZERO, 0)
				ghost.add_child(display)
				for body in display.find_children("*", "StaticBody3D", true, false):
					body.collision_layer = 0
					body.collision_mask = 0
				for mesh in display.find_children("*", "MeshInstance3D", true, false):
					var material := StandardMaterial3D.new()
					material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					material.albedo_color = Color(0.35, 1, 0.65, 0.35)
					mesh.material_override = material
		host._set_status("可以整体投放" if valid else result["error"])
	last_cell = cell

func _region_preview(rect: Rect2i, valid: bool) -> void:
	clear_ghost()
	ghost = Node3D.new()
	host.builder.add_child(ghost)
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(rect.size.x * LevelData.CELL_SIZE, 0.08, rect.size.y * LevelData.CELL_SIZE)
	node.mesh = box
	node.position = host.data.world_center(rect.position, host.height_select.selected) + Vector3(
		(rect.size.x - 1) * LevelData.CELL_SIZE * 0.5, 0.12, (rect.size.y - 1) * LevelData.CELL_SIZE * 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 1, 0.6, 0.4) if valid else Color(1, 0.2, 0.2, 0.4)
	node.material_override = mat
	ghost.add_child(node)

func save_region() -> void:
	if host.data == null:
		return
	var result := LevelPrefab.capture(host.data, region)
	if not result["error"].is_empty():
		host._set_status(result["error"])
		return
	prefab = result["prefab"]
	prefab_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	prefab_dialog.current_path = "res://data/prefabs/new_camp.tres"
	prefab_dialog.popup_centered_ratio(0.7)

func open_prefab() -> void:
	prefab_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	prefab_dialog.popup_centered_ratio(0.7)

func _prefab_file(path: String) -> void:
	if prefab_dialog.file_mode == EditorFileDialog.FILE_MODE_SAVE_FILE:
		var error := ResourceSaver.save(prefab, path)
		host._set_status("预制已保存：" + path if error == OK else "预制保存失败：" + str(error))
		if error == OK:
			EditorInterface.get_resource_filesystem().scan()
	else:
		var loaded := load(path) as LevelPrefab
		if loaded == null or loaded.fragment == null:
			host._set_status("不是有效的营地预制")
			return
		prefab = loaded
		prefab_mode.selected = 1
		prefab_turns = 0
		host._set_status("已打开预制，在地图上移动鼠标查看投放范围")
	clear_ghost()
