@tool
extends RefCounted

## ============================================================
## 物件 / 导入 / 预制  tabs  (tabs index 1, 2, 3)
## ============================================================

var host: EditorPlugin
var tabs: TabContainer
var library: ItemList
var paths: Array[String] = []
var object_mode
var placement_controls: Array[Control] = []
var adjustment_controls: Array[Control] = []
var object_help: Label
var scale_input: SpinBox
var yaw_input: SpinBox
var snap: CheckBox
var selected_id := ""
var dragging := false
var drag_before: Array[Dictionary] = []
var prefab: LevelPrefab
var prefab_mode
var prefab_sub_tabs: TabContainer
var objects_only: CheckBox
var prefab_turns := 0
var region_start := Vector2i(-1, -1)
var region := Rect2i()
var prefab_name_input: LineEdit
var prefab_library: ItemList
var prefab_paths: Array[String] = []
var prefab_info_label: Label
var ghost: Node3D
var last_cell := Vector2i(-999, -999)
var last_candidate: Dictionary = {}
var clipboard: Dictionary = {}
var search: LineEdit
var selected_label: Label
var object_info: Label
var detail_tools: VBoxContainer
const Picker := preload("res://addons/terrain_editor/surface_picker.gd")

func setup(plugin: EditorPlugin, tab_container: TabContainer) -> void:
	host = plugin
	tabs = tab_container

	# Tab 1: 物件
	var object_page := VBoxContainer.new()
	_page("物件", object_page)
	object_mode = load("res://addons/terrain_editor/mode_bar.gd").new()
	object_mode.add_mode("放置", 0)
	object_mode.add_mode("调整", 1)
	object_page.add_child(object_mode)
	object_mode.item_selected.connect(_object_mode_changed)
	object_help = _label(object_page, "选择物件后左键点击放置到地图。")
	var place_start := object_page.get_child_count()
	search = LineEdit.new()
	search.placeholder_text = "搜索物件名称"
	search.text_changed.connect(func(_text: String): refresh_library())
	object_page.add_child(search)
	library = ItemList.new()
	library.auto_height = true
	library.size_flags_vertical = Control.SIZE_FILL
	library.icon_mode = ItemList.ICON_MODE_TOP
	library.fixed_icon_size = host.ui_size(Vector2(48, 48))
	library.max_columns = 0
	library.same_column_width = true
	library.item_selected.connect(func(_index: int): object_mode.selected = 0; clear_ghost())
	object_page.add_child(library)
	library.fixed_column_width = host.ui_px(92)
	library.max_text_lines = 2
	library.item_selected.connect(_show_object_info)
	object_info = _label(object_page, "")
	_button(object_page, "刷新物件库", refresh_library)
	for i in range(place_start, object_page.get_child_count()):
		placement_controls.append(object_page.get_child(i))
	selected_label = _label(object_page, "未选择物件：请点击地图上的物件")
	adjustment_controls.append(selected_label)
	snap = CheckBox.new()
	snap.text = "吸附 2m 格中心（Shift 临时关闭）"
	snap.button_pressed = true
	object_page.add_child(snap)
	yaw_input = _spin(object_page, "旋转角度（Q/E 每次 90°）", -360, 360, 15, 0)
	scale_input = _spin(object_page, "统一缩放", 0.25, 4, 0.25, 1)
	var adjust_start := object_page.get_child_count()
	_button(object_page, "应用旋转 / 缩放", apply_transform)
	_button(object_page, "复制（Ctrl/Cmd+C）", copy_selected)
	_button(object_page, "删除（Delete）", delete_selected)
	for i in range(adjust_start, object_page.get_child_count()):
		adjustment_controls.append(object_page.get_child(i))
	_button(object_page, "粘贴为待放置物件（Ctrl/Cmd+V）", paste_selected)
	_object_mode_changed(0)

	# Tab 2: 导入
	var importer = load("res://addons/terrain_editor/asset_import_dock.gd").new()
	_page("导入", importer)
	importer.generated.connect(func(_path: String):
		refresh_library()
		if detail_tools != null:
			detail_tools.refresh_library()
		host.refresh_tile_list())

	# Tab 3: 预制
	_build_prefab_tab()

	tabs.tab_changed.connect(func(_index: int): clear_ghost(); region_start = Vector2i(-1, -1))
	refresh_library()

func add_detail_page() -> void:
	detail_tools = load("res://addons/terrain_editor/detail_dock.gd").new()
	_page("细节", detail_tools)
	detail_tools.setup(host)
	tabs.tab_changed.connect(func(_index: int):
		detail_tools.finish_stroke()
		detail_tools.clear_preview())

func _object_mode_changed(value: int) -> void:
	if dragging and host.data != null:
		dragging = false
		host._commit_objects(drag_before, host.data.objects, "移动物件")
	clear_ghost()
	for control in placement_controls:
		control.visible = value == 0
	for control in adjustment_controls:
		control.visible = value == 1
	object_help.text = ("选择物件卡片，再点击地面放置。下方旋转/缩放只影响下一次放置。"
		if value == 0 else "点击地图中的物件选中，按住拖动移动；修改参数后点击应用。")
	if value == 1:
		var index := _selected_index()
		if index >= 0:
			yaw_input.value = rad_to_deg(float(host.data.objects[index].get("yaw", 0)))
			scale_input.value = float(host.data.objects[index].get("scale", 1))

func _build_prefab_tab() -> void:
	var prefab_outer := VBoxContainer.new()
	prefab_outer.add_theme_constant_override("separation", 10)
	_page("预制", prefab_outer)
	var action_label := _label(prefab_outer, "预制操作")
	action_label.modulate = Color(1, 1, 1, 0.72)
	prefab_mode = load("res://addons/terrain_editor/mode_bar.gd").new()
	prefab_mode.name = "PrefabActionButtons"
	prefab_mode.add_theme_constant_override("separation", host.ui_px(8))
	prefab_mode.add_mode("制作预制", 0)
	prefab_mode.add_mode("使用预制", 1)
	for button: Button in prefab_mode.buttons.values():
		_style_prefab_action(button)
	prefab_outer.add_child(prefab_mode)
	prefab_sub_tabs = TabContainer.new()
	prefab_sub_tabs.tabs_visible = false
	prefab_sub_tabs.size_flags_vertical = Control.SIZE_FILL
	prefab_sub_tabs.use_hidden_tabs_for_min_size = false
	prefab_outer.add_child(prefab_sub_tabs)
	prefab_mode.item_selected.connect(func(index: int):
		prefab_sub_tabs.current_tab = index)

	# Sub-tab 0: 制作预制
	var make_page := VBoxContainer.new()
	make_page.name = "制作预制"
	make_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prefab_sub_tabs.add_child(make_page)

	_label(make_page, "在地图上点击起点，再点击终点，框选矩形区域。\n框选完成后输入名称并点击保存。")
	var name_row := HBoxContainer.new()
	make_page.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "预制名称"
	name_row.add_child(name_label)
	prefab_name_input = LineEdit.new()
	prefab_name_input.text = "new_camp"
	prefab_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(prefab_name_input)
	_button_to(make_page, "保存选区为预制", save_region)
	_button_to(make_page, "重新框选", _reset_region)

	# Sub-tab 1: 使用预制
	var use_page := VBoxContainer.new()
	use_page.name = "使用预制"
	use_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prefab_sub_tabs.add_child(use_page)

	_label(use_page, "预制库（点击下面的大卡片选择）")
	prefab_library = ItemList.new()
	prefab_library.auto_height = true
	prefab_library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prefab_library.size_flags_vertical = Control.SIZE_FILL
	prefab_library.icon_mode = ItemList.ICON_MODE_TOP
	prefab_library.fixed_icon_size = host.ui_size(Vector2(96, 80))
	prefab_library.max_columns = 0
	prefab_library.same_column_width = true
	prefab_library.item_selected.connect(_on_prefab_selected)
	use_page.add_child(prefab_library)
	prefab_info_label = _label(use_page, "当前未选择预制")
	_button_to(use_page, "刷新预制列表", refresh_prefab_list)
	_label(use_page, "选择卡片后，把鼠标移到地图上；绿色时左键投放，Q/E 旋转。")
	objects_only = CheckBox.new()
	objects_only.text = "仅投放物件（贴合目标地块高度）"
	use_page.add_child(objects_only)
	var rotate_row := HBoxContainer.new()
	use_page.add_child(rotate_row)
	_button_to(rotate_row, "左转 90°", rotate_prefab.bind(-1))
	_button_to(rotate_row, "右转 90°", rotate_prefab.bind(1))

	prefab_sub_tabs.tab_changed.connect(func(idx: int):
		prefab_mode.selected = idx
		clear_ghost()
		region_start = Vector2i(-1, -1)
		if idx == 1:
			refresh_prefab_list())

	refresh_prefab_list()

func _style_prefab_action(button: Button) -> void:
	button.custom_minimum_size.y = host.ui_px(40)
	button.add_theme_stylebox_override("normal",
		_button_style(Color("#303943"), Color("#6c7885")))
	button.add_theme_stylebox_override("hover",
		_button_style(Color("#3b4853"), Color("#8b98a6")))
	button.add_theme_stylebox_override("pressed",
		_button_style(Color("#23594f"), Color("#80d6b5"), 2))
	button.add_theme_stylebox_override("focus",
		_button_style(Color("#303943"), Color("#80d6b5"), 2))
	button.add_theme_color_override("font_pressed_color", Color("#e8fff8"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)

func _button_style(background: Color, border: Color, width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(host.ui_px(width))
	style.set_corner_radius_all(host.ui_px(4))
	style.content_margin_left = host.ui_px(10)
	style.content_margin_right = host.ui_px(10)
	style.content_margin_top = host.ui_px(7)
	style.content_margin_bottom = host.ui_px(7)
	return style

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

func _button_to(parent: Node, text: String, action: Callable) -> void:
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

# ============================================================
# Object library (visual grid, not dropdown)
# ============================================================
func refresh_library() -> void:
	if library == null:
		return
	var selected := library.get_selected_items()
	var previous := paths[selected[0]] if not selected.is_empty() and selected[0] < paths.size() else ""
	library.clear()
	paths.clear()
	for path in ObjectRules.library():
		var d := load(path) as PlaceableDefinition
		if d == null or (not search.text.is_empty() and not d.display_name.containsn(search.text)):
			continue
		paths.append(path)
		var texture: Texture2D = null
		if not d.thumbnail_path.is_empty() and ResourceLoader.exists(d.thumbnail_path):
			texture = load(d.thumbnail_path) as Texture2D
		if texture == null:
			texture = load(d.source_image) as Texture2D
		var index := library.add_item(d.display_name, texture)
		library.set_item_tooltip(index, "%s · %s\n%.1f × %.1f × %.1f 米" % [
			d.display_name, d.behaviour_label(), d.volume_size.x, d.volume_size.y, d.volume_size.z])
	if library.item_count > 0:
		var index := maxi(0, paths.find(previous))
		library.select(index)
		_show_object_info(index)
	elif object_info != null:
		object_info.text = "没有匹配的物件"

func _show_object_info(index: int) -> void:
	if object_info == null or index < 0 or index >= paths.size():
		return
	var d := load(paths[index]) as PlaceableDefinition
	var placement := "点击外露侧壁放置" if d.carrier == PlaceableDefinition.Carrier.WALL \
		else "可放地面或承托物件的顶面"
	object_info.text = "%s · %s\n%s" % [d.display_name, d.behaviour_label(), placement]
	if d.supports_objects:
		object_info.text += "\n可承托其他物件"
	if d.behaviour == PlaceableDefinition.Behaviour.BREAKABLE:
		object_info.text += " · 耐久 %d" % d.max_health

# ============================================================
# Prefab library (visual grid)
# ============================================================
const PREFAB_DIR := "res://data/prefabs"

func refresh_prefab_list() -> void:
	if prefab_library == null:
		return
	prefab_library.clear()
	prefab_paths.clear()
	if not DirAccess.dir_exists_absolute(PREFAB_DIR):
		return
	for file in DirAccess.get_files_at(PREFAB_DIR):
		if not file.ends_with(".tres"):
			continue
		var path := PREFAB_DIR.path_join(file)
		# Skip interrupted/corrupt files without asking ResourceLoader to parse
		# them (which otherwise floods the editor output with parse errors).
		var header := FileAccess.get_file_as_string(path).left(64)
		if not header.begins_with("[gd_resource"):
			continue
		var loaded := load(path) as LevelPrefab
		if loaded == null or loaded.fragment == null:
			continue
		prefab_paths.append(path)
		# Generate a simple colored icon showing the prefab size
		var icon := _prefab_icon(loaded)
		prefab_library.add_item(loaded.display_name + " (%dx%d)" % [loaded.fragment.map_size.x, loaded.fragment.map_size.y], icon)
	if prefab_library.item_count > 0:
		prefab_library.select(0)
		_on_prefab_selected(0)
	else:
		prefab = null
		prefab_info_label.text = "预制库为空：请先到“制作预制”框选并保存。"

func _prefab_icon(p: LevelPrefab) -> ImageTexture:
	# Mini map icon: each cell is a pixel, scaled up
	var sz := p.fragment.map_size
	var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.2, 0.2))
	var cell_w := 48.0 / sz.x
	var cell_h := 48.0 / sz.y
	for y in sz.y:
		for x in sz.x:
			if p.fragment.cell_exists(Vector2i(x, y)):
				var color := Color(0.45, 0.65, 0.35)
				var h := p.fragment.elevation(Vector2i(x, y))
				color = color.lightened(h * 0.15)
				for py in range(int(y * cell_h), int((y + 1) * cell_h)):
					for px in range(int(x * cell_w), int((x + 1) * cell_w)):
						if px < 48 and py < 48:
							image.set_pixel(px, py, color)
	return ImageTexture.create_from_image(image)

func _on_prefab_selected(index: int) -> void:
	if index < 0 or index >= prefab_paths.size():
		prefab = null
		if prefab_info_label != null:
			prefab_info_label.text = "当前未选择预制"
		return
	var loaded := load(prefab_paths[index]) as LevelPrefab
	if loaded != null and loaded.fragment != null:
		prefab = loaded
		prefab_turns = 0
		clear_ghost()
		prefab_info_label.text = "当前选择：%s　尺寸：%d×%d 格" % [
			prefab.display_name, prefab.fragment.map_size.x, prefab.fragment.map_size.y]
		host._set_status("已选择预制：" + prefab.display_name)

func _reset_region() -> void:
	region_start = Vector2i(-1, -1)
	region = Rect2i()
	clear_ghost()
	host._set_status("已重置框选，请重新点击起点")

# ============================================================
# Active check
# ============================================================
func active() -> bool:
	return tabs.current_tab != 0

func clear_ghost() -> void:
	if is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null
	last_cell = Vector2i(-999, -999)

func reset() -> void:
	if detail_tools != null:
		detail_tools.finish_stroke()
		detail_tools.clear_preview()
	clear_ghost()
	selected_id = ""
	dragging = false
	region_start = Vector2i(-1, -1)
	region = Rect2i()

# ============================================================
# Object helpers
# ============================================================
func _selected_index() -> int:
	if host.data == null:
		return -1
	for i in host.data.objects.size():
		if str(host.data.objects[i].get("id", "")) == selected_id:
			return i
	return -1

func _point(camera: Camera3D, mouse: Vector2, free_move: bool) -> Vector3:
	var data: LevelData = host.data
	var cell: Vector2i = host._pick(camera, mouse)
	var layer: int = maxi(host.picked_layer, 0)
	var result := data.world_center(cell, layer)
	if not free_move:
		return result
	var inverse: Transform3D = host.builder.global_transform.affine_inverse()
	var origin := inverse * camera.project_ray_origin(mouse)
	var ray := inverse.basis * camera.project_ray_normal(mouse)
	if absf(ray.y) < 0.00001:
		return Vector3(INF, INF, INF)
	var distance := (result.y - origin.y) / ray.y
	var projected := origin + ray * maxf(distance, 0.0)
	if data.world_to_cell(projected) == cell:
		result = projected
	return result

func _pick_object(camera: Camera3D, mouse: Vector2) -> String:
	var origin := camera.project_ray_origin(mouse)
	var ray := camera.project_ray_normal(mouse)
	var inverse_builder: Transform3D = host.builder.global_transform.affine_inverse()
	var terrain: Dictionary = host.BlockPicker.raycast(host.data, inverse_builder * origin,
		inverse_builder.basis * ray, host.builder.slice_layer_limit)
	var best := INF
	if not terrain.is_empty():
		best = origin.distance_to(host.builder.global_transform * terrain["position"]) + 0.02
	var id := ""
	if not is_instance_valid(host.builder.generated):
		return id
	for object: Node3D in host.builder._object_nodes.values():
		if not is_instance_valid(object) or not object.is_visible_in_tree():
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
	return ObjectRules.anchor_record(host.data, {
		"id": ObjectRules.new_id(), "definition": paths[chosen[0]], "position": position,
		"yaw": deg_to_rad(yaw_input.value), "scale": scale_input.value})

# ============================================================
# Input handler
# ============================================================
func handle(camera: Camera3D, event: InputEvent) -> int:
	if host.preview and is_instance_valid(host.preview):
		host.preview.visible = false
	# Import and view settings do not own 3D editing input.
	if tabs.current_tab in [2, 4]:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if tabs.current_tab == 5:
		return detail_tools.handle(camera, event)
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
		if tabs.current_tab == 1:
			if object_mode.selected == 1 and (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE):
				delete_selected()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.ctrl_pressed or event.meta_pressed:
				if event.keycode == KEY_C and object_mode.selected == 1:
					copy_selected()
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				if event.keycode == KEY_V:
					paste_selected()
					return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if tabs.current_tab == 1:
			var surface := Picker.pick(host.builder, camera, event.position, selected_id if dragging else "")
			if dragging:
				_move_selected_surface(surface, snap.button_pressed and not event.shift_pressed)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if object_mode.selected == 0:
				_preview_object(_surface_candidate(surface, snap.button_pressed and not event.shift_pressed))
				if surface.has("error"):
					host._set_status(surface["error"])
		elif tabs.current_tab == 3:
			var point := _point(camera, event.position, not snap.button_pressed or event.shift_pressed)
			if not point.is_finite():
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			_preview_prefab(host.data.world_to_cell(point))
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if tabs.current_tab == 1:
			if object_mode.selected == 0 and event.pressed:
				var surface := Picker.pick(host.builder, camera, event.position)
				place_object(_surface_candidate(surface, snap.button_pressed and not event.shift_pressed))
				if surface.has("error"):
					host._set_status(surface["error"])
			elif object_mode.selected == 1:
				if event.pressed:
					selected_id = _pick_object(camera, event.position)
					var index := _selected_index()
					if index >= 0:
						yaw_input.value = rad_to_deg(float(host.data.objects[index].get("yaw", 0)))
						scale_input.value = float(host.data.objects[index].get("scale", 1))
						var definition := ObjectRules.definition(host.data.objects[index])
						selected_label.text = "选中：" + (definition.display_name if definition != null else selected_id.left(8))
						drag_before = host.data.objects.duplicate(true)
						dragging = true
						_preview_object(host.data.objects[index], selected_id)
					else:
						selected_label.text = "未选择物件：请点击地图上的物件"
						clear_ghost()
				elif dragging:
					dragging = false
					host._commit_objects(drag_before, host.data.objects, "移动物件")
		elif tabs.current_tab == 3 and event.pressed:
			var point := _point(camera, event.position, not snap.button_pressed or event.shift_pressed)
			if point.is_finite():
				_prefab_click(host.data.world_to_cell(point))
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

# ============================================================
# Object preview / place / move / delete
# ============================================================
func _surface_candidate(surface: Dictionary, snapped: bool) -> Dictionary:
	return Picker.placement(host.data, _candidate(Vector3.ZERO), surface, snapped)

func _preview_object(record: Dictionary, ignore := "") -> void:
	clear_ghost()
	if record.is_empty():
		host._set_status("指向有效支撑面：普通物件选顶面，墙面附件选外露侧壁")
		return
	var d := ObjectRules.definition(record)
	if d == null:
		return
	var error := ObjectRules.validate_record(host.data, record, ignore)
	ghost = AssetFactory.make_asset(d)
	for body in ghost.find_children("*", "CollisionObject3D", true, false):
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
		host._set_status("请选择物件并指向匹配的顶面或侧壁")
		return
	var error := ObjectRules.validate_record(host.data, record)
	if not error.is_empty():
		host._set_status(error)
		return
	var before: Array[Dictionary] = host.data.objects.duplicate(true)
	host.data.objects.append(ObjectRules.anchor_record(host.data, record))
	host._commit_objects(before, host.data.objects, "放置物件")

func _move_selected(point: Vector3) -> void:
	var index := _selected_index()
	if index < 0:
		return
	var record: Dictionary = host.data.objects[index].duplicate(true)
	record["position"] = point
	record["anchor_kind"] = "top"
	record.erase("support_id")
	record = ObjectRules.anchor_record(host.data, record)
	_apply_moved_record(record, index)

func _move_selected_surface(surface: Dictionary, snapped: bool) -> void:
	var index := _selected_index()
	if index < 0:
		return
	var record := Picker.placement(host.data, host.data.objects[index], surface, snapped)
	if record.is_empty():
		host._set_status(surface.get("error", "移动目标缺少有效支撑面"))
		return
	_apply_moved_record(record, index)

func _apply_moved_record(record: Dictionary, index: int) -> void:
	var candidate: LevelData = host.data.fork_for_edit()
	candidate.objects[index] = record
	ObjectRules.sync_dependents(candidate)
	var errors := ObjectRules.validate_all(candidate)
	_preview_object(record, selected_id)
	if not errors.is_empty():
		host._set_status("\n".join(errors))
		return
	host.data.objects = candidate.objects
	host.builder.refresh_objects()

func apply_transform() -> void:
	var index := _selected_index()
	if index < 0:
		return
	var record: Dictionary = host.data.objects[index].duplicate(true)
	record["yaw"] = deg_to_rad(yaw_input.value)
	record["scale"] = scale_input.value
	if record.has("support_id"):
		var parent := ObjectRules.find_record(host.data, record["support_id"])
		record["support_yaw"] = float(record["yaw"]) - float(parent.get("yaw", 0.0))
	var candidate: LevelData = host.data.fork_for_edit()
	candidate.objects[index] = record
	ObjectRules.sync_dependents(candidate)
	var errors := ObjectRules.validate_all(candidate)
	if not errors.is_empty():
		host._set_status("\n".join(errors))
		return
	var before: Array[Dictionary] = host.data.objects.duplicate(true)
	host.data.objects = candidate.objects
	host._commit_objects(before, host.data.objects, "调整物件")
	_preview_object(record, selected_id)

func delete_selected() -> void:
	delete_object(selected_id)

func delete_object(id: String) -> void:
	if ObjectRules.find_record(host.data, id).is_empty():
		return
	var before: Array[Dictionary] = host.data.objects.duplicate(true)
	ObjectRules.remove_with_dependents(host.data, [id])
	host._commit_objects(before, host.data.objects, "删除物件")
	selected_id = ""
	selected_label.text = "未选择物件"
	clear_ghost()

func copy_selected() -> void:
	var index := _selected_index()
	if index >= 0:
		clipboard = host.data.objects[index].duplicate(true)
		host._set_status("已复制")

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

# ============================================================
# Prefab
# ============================================================
func rotate_prefab(delta: int) -> void:
	prefab_turns = posmod(prefab_turns + delta, 4)
	clear_ghost()
	host._set_status("预制旋转 %d°" % (prefab_turns * 90))

func _prefab_click(cell: Vector2i) -> void:
	if not host.data.in_bounds(cell):
		return
	# Sub-tab 0 = 制作预制 (frame select mode)
	if prefab_sub_tabs.current_tab == 0:
		if region_start.x < 0:
			region_start = cell
			host._set_status("请选择选区终点")
		else:
			region = Rect2i(region_start.min(cell), (cell - region_start).abs() + Vector2i.ONE)
			region_start = Vector2i(-1, -1)
			var capture := LevelPrefab.capture(host.data, region)
			var valid: bool = capture["error"].is_empty()
			host._set_status(
				"选区 %s，大小 %s。输入名称后点击保存。" % [region.position, region.size]
				if valid else capture["error"])
			_region_preview(region, valid, host.data)
	# Sub-tab 1 = 使用预制
	elif prefab_sub_tabs.current_tab == 1 and prefab != null:
		var before: Dictionary = host.data.clone_data()
		var result := prefab.stamp(host.data, cell, prefab_turns, objects_only.button_pressed)
		if not result["error"].is_empty():
			host._set_status(result["error"])
			return
		host._commit_external(before, result["snapshot"], "投放营地预制")
		host._set_status("预制已投放；可用 Ctrl/Cmd+Z 撤销")
		clear_ghost()

func _preview_prefab(cell: Vector2i) -> void:
	if cell == last_cell:
		return
	# Sub-tab 0: frame selection preview
	if prefab_sub_tabs.current_tab == 0:
		if region_start.x >= 0:
			var selecting := Rect2i(region_start.min(cell), (cell - region_start).abs() + Vector2i.ONE)
			var capture := LevelPrefab.capture(host.data, selecting)
			_region_preview(selecting, capture["error"].is_empty(), host.data)
	# Sub-tab 1: stamp preview
	elif prefab_sub_tabs.current_tab == 1 and prefab != null:
		var result := prefab.stamp(host.data, cell, prefab_turns, objects_only.button_pressed)
		var valid: bool = result["error"].is_empty()
		var preview_data: LevelData = host.data
		if valid:
			preview_data = LevelData.new()
			preview_data.restore_data(result["snapshot"])
		_region_preview(Rect2i(cell, prefab.rotated_size(prefab_turns)), valid, preview_data)
		if valid:
			var capture := LevelPrefab.capture(preview_data, Rect2i(cell, prefab.rotated_size(prefab_turns)))
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

func _region_preview(rect: Rect2i, valid: bool, preview_data: LevelData = null) -> void:
	clear_ghost()
	ghost = Node3D.new()
	host.builder.add_child(ghost)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 1, 0.6, 0.4) if valid else Color(1, 0.2, 0.2, 0.4)
	var source: LevelData = preview_data if preview_data != null else host.data
	# Draw one thin overlay per cell so the selection follows the actual terrain
	# rather than floating at the height dropdown's current value.
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if not source.in_bounds(cell):
				continue
			var node := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(LevelData.CELL_SIZE * 0.94, 0.08, LevelData.CELL_SIZE * 0.94)
			node.mesh = box
			var level: int = source.elevation(cell) if source.cell_exists(cell) else 0
			node.position = source.world_center(cell, level) + Vector3(0, 0.12, 0)
			node.material_override = mat
			ghost.add_child(node)

func save_region() -> void:
	if host.data == null:
		host._set_status("没有打开地图，无法保存预制")
		return
	if region.size.x <= 0 or region.size.y <= 0:
		host._set_status("请先在地图上点击起点和终点完成框选")
		return
	var result := LevelPrefab.capture(host.data, region)
	if not result["error"].is_empty():
		host._set_status(result["error"])
		return
	# Save directly to fixed directory with user-given name
	var name := prefab_name_input.text.strip_edges()
	if name.is_empty():
		name = "unnamed"
	# Sanitize filename
	var safe_name := ""
	for c in name:
		if c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			safe_name += c
		else:
			safe_name += "_"
	if safe_name.is_empty():
		safe_name = "camp"
	var dir := PREFAB_DIR
	var absolute_dir := ProjectSettings.globalize_path(dir)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK:
		host._set_status("无法创建预制目录：%s（错误 %s）" % [absolute_dir, mkdir_error])
		return
	var path := dir.path_join(safe_name + ".tres")
	# FileAccess catches corrupt/unimported files too. ResourceLoader.exists()
	# only reports resources it can recognize, which made repeated saves try to
	# overwrite an invalid .tres and return ERR_FILE_UNRECOGNIZED (15).
	var counter := 2
	while FileAccess.file_exists(path):
		path = dir.path_join(safe_name + "_%d.tres" % counter)
		counter += 1
	prefab = result["prefab"]
	prefab.display_name = name
	# Write a complete resource to another valid .tres first, then rename it.
	# A failed save can no longer leave the final filename in a broken state.
	var temp_path := dir.path_join(".prefab_pending_%s.tres" % ObjectRules.new_id())
	var error := ResourceSaver.save(prefab, temp_path)
	if error == OK:
		var rename_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(temp_path),
			ProjectSettings.globalize_path(path))
		if rename_error != OK:
			error = rename_error
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	if error == OK:
		host._set_status("预制已保存：" + path)
		EditorInterface.get_resource_filesystem().scan()
		await host.get_tree().process_frame
		refresh_prefab_list()
		var selected := prefab_paths.find(path)
		if selected >= 0:
			prefab_library.select(selected)
			_on_prefab_selected(selected)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		host._set_status("预制保存失败：%s（错误 %s：%s）" % [
			ProjectSettings.globalize_path(path), error, error_string(error)])

func open_prefab() -> void:
	# No longer needed — prefab selection via library
	pass
