@tool
extends EditorPlugin

## ============================================================
## 畸变 关卡编辑器 v0.5  —  地形视觉 P0 / 物件 / 导入 / 预制
## ============================================================

enum ToolMode { GROUND = 0, ERASE = 2, STAIR = 3, SPAWN = 4 }

# --- State --------------------------------------------------
var builder: TerrainBuilder
var data: LevelData
var current_path := ""
var dirty := false
var drawing := false
var stroke_cells_before: Dictionary = {}
var stroke_aux_before: Dictionary = {}
var stroke_full_before: Dictionary = {}
var pending_expansion_before: Dictionary = {}
var touched: Dictionary = {}
var stair_direction := 0
var tile_turns := 0
var play_after_save := false
var tile_rotation_label: Label
var hover_cell := Vector2i(-999, -999)
var fixed_view_button: Button
var editing_camera: Camera3D
var fixed_view_active := false
var fixed_view_cameras: Array[Camera3D] = []
var fixed_view_states: Dictionary = {}
var view_pan_offset := Vector3.ZERO
var view_move_keys := {KEY_W: false, KEY_A: false, KEY_S: false, KEY_D: false}
var preview: MeshInstance3D
var pending_action := ""
var last_stroke_cell := Vector2i(-999, -999)
var launcher_button: Button
var opening_workspace := false
var editor_dock: EditorDock
var dock_started_closed := false

const EDITOR_WORKSPACE_SCENE := "res://scenes/terrain_editor_v2.tscn"

# --- UI references -----------------------------------------
var dock_root: VBoxContainer
var tabs: TabContainer
var status: Label
var dirty_label: Label
var file_dialog: EditorFileDialog
var confirm_dialog: ConfirmationDialog

# Terrain tab
var tile_list: ItemList
var mode_select
var ground_controls: Array[Control] = []
var brush_controls: Array[Control] = []
var direction_controls: Array[Control] = []
var height_select: OptionButton
var brush_select: OptionButton
var tile_name_label: Label
var tile_height_label: Label
var tint_picker: ColorPickerButton
var tint_strength: HSlider
var tint_strength_label: Label
var placement_panel: PanelContainer
var tint_panel: PanelContainer

# Object & import & prefab managed by world_edit_tools
var world_tools
var view_settings
var preview_fov := -1.0
var preview_pitch := -1.0
var preview_distance := -1.0
var preview_target_height := INF

func _enter_tree() -> void:
	launcher_button = Button.new()
	launcher_button.text = "关卡编辑器"
	launcher_button.tooltip_text = "打开关卡编辑工作区，并自动选择 TerrainBuilder"
	launcher_button.pressed.connect(_open_editor_workspace)
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, launcher_button)
	_build_dock()
	world_tools = load("res://addons/terrain_editor/world_edit_tools.gd").new()
	world_tools.setup(self, tabs)
	view_settings = load("res://addons/terrain_editor/view_settings.gd").new()
	_add_page("视角", view_settings)
	view_settings.setup(self)
	editor_dock = EditorDock.new()
	editor_dock.title = "关卡编辑器"
	editor_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BR
	editor_dock.transient = true
	editor_dock.closable = true
	editor_dock.add_child(dock_root)
	add_dock(editor_dock)
	editor_dock.close()
	dock_started_closed = true
	set_input_event_forwarding_always_enabled()
	RenderingServer.frame_pre_draw.connect(_apply_fixed_view)
	if "--test-v2-editor" in OS.get_cmdline_user_args():
		_run_editor_checks.call_deferred()

func _run_editor_checks() -> void:
	await get_tree().process_frame
	var suite = load("res://tests/editor_v2_checks.gd").new()
	await suite.run(self)

func _exit_tree() -> void:
	_disable_2_5d_view()
	if RenderingServer.frame_pre_draw.is_connected(_apply_fixed_view):
		RenderingServer.frame_pre_draw.disconnect(_apply_fixed_view)
	if world_tools:
		world_tools.reset()
	if preview and is_instance_valid(preview):
		preview.queue_free()
	if is_instance_valid(launcher_button):
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, launcher_button)
		launcher_button.queue_free()
	if is_instance_valid(editor_dock):
		remove_dock(editor_dock)
		editor_dock.queue_free()
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
			_sync_tint_controls()
			_enable_2_5d_view.call_deferred()
	else:
		builder = null
		data = null
		if preview and is_instance_valid(preview):
			preview.queue_free()

func _open_editor_workspace() -> void:
	if opening_workspace:
		return
	opening_workspace = true
	launcher_button.disabled = true
	if is_instance_valid(editor_dock):
		editor_dock.make_visible()
	var target := _find_terrain_builder(EditorInterface.get_edited_scene_root())
	if target == null:
		EditorInterface.open_scene_from_path(EDITOR_WORKSPACE_SCENE)
		for frame in 12:
			await get_tree().process_frame
			target = _find_terrain_builder(EditorInterface.get_edited_scene_root())
			if target != null:
				break
	if target == null:
		_set_status("无法打开关卡编辑工作区：" + EDITOR_WORKSPACE_SCENE)
	else:
		EditorInterface.set_main_screen_editor("3D")
		var selection := EditorInterface.get_selection()
		selection.clear()
		selection.add_node(target)
		EditorInterface.edit_node(target)
		_edit(target)
		_set_status("关卡编辑器已打开")
	opening_workspace = false
	if is_instance_valid(launcher_button):
		launcher_button.disabled = false

func _find_terrain_builder(root: Node) -> TerrainBuilder:
	if root == null:
		return null
	if root is TerrainBuilder:
		return root as TerrainBuilder
	for child in root.get_children():
		var found := _find_terrain_builder(child)
		if found != null:
			return found
	return null

# ============================================================
# Build dock — tab order: 地形 / 物件 / 导入 / 预制
# ============================================================
func _build_dock() -> void:
	dock_root = VBoxContainer.new()
	dock_root.name = "关卡编辑器"
	dock_root.custom_minimum_size.x = 310

	var title := Label.new()
	title.text = "畸变 关卡编辑器 v0.5"
	title.add_theme_font_size_override("font_size", 19)
	dock_root.add_child(title)

	dirty_label = Label.new()
	dock_root.add_child(dirty_label)

	# File operations row
	var files := HBoxContainer.new()
	dock_root.add_child(files)
	for spec in [["新建", "_new_map"], ["打开", "_open_map"], ["保存", "_save_map"], ["另存为", "_save_as"], ["2.5D视角", "_fixed_view_pressed"]]:
		var button := Button.new()
		button.text = spec[0]
		button.pressed.connect(Callable(self, spec[1]))
		files.add_child(button)
		if spec[1] == "_fixed_view_pressed":
			fixed_view_button = button
			button.toggle_mode = true
			button.tooltip_text = "固定游戏视角；WASD平移，滚轮缩放。再次点击恢复普通Godot视口。"
	process_priority = 100

	# Tabs
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock_root.add_child(tabs)

	# Tab 0: 地形
	_build_terrain_tab()

	# Status bar
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock_root.add_child(status)

	# Bottom buttons
	var save_btn := Button.new()
	save_btn.text = "保存地图"
	save_btn.pressed.connect(_save_map)
	dock_root.add_child(save_btn)
	var play_btn := Button.new()
	play_btn.text = "保存并试玩当前地图"
	play_btn.pressed.connect(_playtest)
	dock_root.add_child(play_btn)

	_make_dialogs()

func _build_terrain_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "地形"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)
	placement_panel = _terrain_panel("地块摆放", Color("#6f91b8"))
	vbox.add_child(placement_panel)
	var placement := placement_panel.get_meta("content") as VBoxContainer
	tint_panel = _terrain_panel("地貌动态着色", Color("#c59b55"))
	vbox.add_child(tint_panel)
	var tint_content := tint_panel.get_meta("content") as VBoxContainer

	# Tool mode
	_add_label(placement, "工具模式")
	mode_select = load("res://addons/terrain_editor/mode_bar.gd").new()
	for spec in [["刷地块", ToolMode.GROUND], ["擦除", ToolMode.ERASE],
			["阶梯", ToolMode.STAIR], ["出生点", ToolMode.SPAWN]]:
		mode_select.add_mode(spec[0], spec[1])
	placement.add_child(mode_select)
	mode_select.item_selected.connect(_terrain_mode_changed)

	# Height selector
	ground_controls.append(_add_label(placement, "目标高度"))
	height_select = OptionButton.new()
	for item in ["0m", "2m", "4m"]:
		height_select.add_item(item)
	height_select.item_selected.connect(func(_index: int): _refresh_brush_preview())
	placement.add_child(height_select)
	ground_controls.append(height_select)

	# Brush size
	brush_controls.append(_add_label(placement, "画笔大小"))
	brush_select = OptionButton.new()
	for item in ["1×1", "3×3"]:
		brush_select.add_item(item)
	brush_select.item_selected.connect(func(_index: int): _refresh_brush_preview())
	placement.add_child(brush_select)
	brush_controls.append(brush_select)

	# Stair rotation
	var rotate := HBoxContainer.new()
	placement.add_child(rotate)
	direction_controls.append(rotate)
	var rotate_label := Label.new()
	rotate_label.text = "方向"
	rotate.add_child(rotate_label)
	for spec in [["Q 左转", -1], ["E 右转", 1]]:
		var button := Button.new()
		button.text = spec[0]
		button.pressed.connect(_rotate_stair.bind(spec[1]))
		rotate.add_child(button)
	tile_rotation_label = _add_label(placement, "地块朝向：0°（Q/E 旋转）")
	direction_controls.append(tile_rotation_label)

	# Separator
	var separator := HSeparator.new()
	placement.add_child(separator)
	ground_controls.append(separator)

	# Tile palette
	ground_controls.append(_add_label(placement, "地块列表（选一个再刷）"))

	tile_list = ItemList.new()
	tile_list.auto_height = true
	tile_list.size_flags_vertical = Control.SIZE_FILL
	tile_list.icon_mode = ItemList.ICON_MODE_TOP
	tile_list.fixed_icon_size = Vector2i(80, 72)
	tile_list.max_columns = 0
	tile_list.same_column_width = true
	tile_list.item_selected.connect(_on_tile_selected)
	placement.add_child(tile_list)
	ground_controls.append(tile_list)

	# Tile info
	tile_name_label = Label.new()
	tile_name_label.text = "未选择地块"
	placement.add_child(tile_name_label)
	ground_controls.append(tile_name_label)
	tile_height_label = Label.new()
	tile_height_label.text = ""
	placement.add_child(tile_height_label)
	ground_controls.append(tile_height_label)

	ground_controls.append(_add_label(tint_content, "地图级颜色覆盖"))
	tint_picker = ColorPickerButton.new()
	tint_picker.edit_alpha = false
	tint_picker.color = Color.WHITE
	tint_picker.tooltip_text = "只调整当前地图中的地貌色调，不修改源图片"
	tint_content.add_child(tint_picker)
	ground_controls.append(tint_picker)
	tint_strength_label = _add_label(tint_content, "着色强度：0%")
	ground_controls.append(tint_strength_label)
	tint_strength = HSlider.new()
	tint_strength.min_value = 0.0
	tint_strength.max_value = 1.0
	tint_strength.step = 0.05
	tint_strength.value_changed.connect(func(value: float):
		tint_strength_label.text = "着色强度：%d%%" % roundi(value * 100.0))
	tint_content.add_child(tint_strength)
	ground_controls.append(tint_strength)
	var tint_actions := HBoxContainer.new()
	tint_content.add_child(tint_actions)
	ground_controls.append(tint_actions)
	for spec in [["应用颜色", "_apply_current_tint"], ["恢复原色", "_clear_current_tint"]]:
		var tint_button := Button.new()
		tint_button.text = spec[0]
		tint_button.pressed.connect(Callable(self, spec[1]))
		tint_actions.add_child(tint_button)
	var tint_presets := HBoxContainer.new()
	tint_content.add_child(tint_presets)
	ground_controls.append(tint_presets)
	for preset in [
			["冷翠", Color("#6ea68b"), 0.45],
			["秋野", Color("#c58b56"), 0.48],
			["腐化", Color("#9a6ba8"), 0.52],
		]:
		var preset_button := Button.new()
		preset_button.text = preset[0]
		preset_button.tooltip_text = "一键应用%s色调" % preset[0]
		preset_button.pressed.connect(_apply_tint_preset.bind(preset[1], preset[2]))
		tint_presets.add_child(preset_button)

	var refresh_btn := Button.new()
	refresh_btn.text = "刷新地块列表"
	refresh_btn.pressed.connect(refresh_tile_list)
	placement.add_child(refresh_btn)
	ground_controls.append(refresh_btn)

	refresh_tile_list()
	_terrain_mode_changed(ToolMode.GROUND)

func _terrain_panel(title: String, border_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.35)
	style.border_color = border_color
	style.set_border_width_all(2)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)
	var heading := Label.new()
	heading.text = title
	heading.modulate = border_color.lightened(0.18)
	heading.add_theme_font_size_override("font_size", 15)
	content.add_child(heading)
	panel.set_meta("content", content)
	return panel

func _add_page(title: String, content: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

func _terrain_mode_changed(value: int) -> void:
	if drawing and data != null:
		drawing = false
		_commit_stroke("绘制地块")
	for control in ground_controls:
		control.visible = value == ToolMode.GROUND
	for control in brush_controls:
		control.visible = value in [ToolMode.GROUND, ToolMode.ERASE]
	for control in direction_controls:
		control.visible = value in [ToolMode.GROUND, ToolMode.STAIR]
	if is_instance_valid(tint_panel):
		tint_panel.visible = value == ToolMode.GROUND
	tile_rotation_label.text = "方向：%d°（Q/E 旋转）" % (
		(stair_direction if value == ToolMode.STAIR else tile_turns) * 90)
	touched.clear()
	last_stroke_cell = Vector2i(-999, -999)
	_refresh_brush_preview()

func _add_label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

func refresh_tile_list() -> void:
	TileRegistry.invalidate()
	tile_list.clear()
	for t in TileRegistry.all_tiles():
		var icon: Texture2D = _tile_model_icon(t)
		tile_list.add_item(t.display_name, icon)
	if tile_list.item_count > 0:
		tile_list.select(0)
		_on_tile_selected(0)

func _tile_model_icon(tile: TileDefinition) -> ImageTexture:
	# A deterministic fixed-camera 2.5D render of a 2m tile. This is generated
	# in memory so imported tiles immediately receive a useful palette preview
	# without requiring a separate thumbnail rendering scene.
	var image := Image.create(80, 72, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var top_source: Image = null
	if not tile.texture_path.is_empty() and ResourceLoader.exists(tile.texture_path):
		var texture := load(tile.texture_path) as Texture2D
		if texture != null:
			top_source = texture.get_image()
			if top_source.is_compressed():
				top_source.decompress()
	var top := PackedVector2Array([
		Vector2(40, 5), Vector2(73, 22), Vector2(40, 40), Vector2(7, 22)])
	var left := PackedVector2Array([
		Vector2(7, 22), Vector2(40, 40), Vector2(40, 65), Vector2(7, 47)])
	var right := PackedVector2Array([
		Vector2(40, 40), Vector2(73, 22), Vector2(73, 47), Vector2(40, 65)])
	var tint := data.terrain_tint(tile.tile_id) if data != null else tile.tint_default()
	var left_color := _preview_tint(tile.base_color.darkened(0.35), tint)
	var right_color := _preview_tint(tile.base_color.darkened(0.22), tint)
	for y in 72:
		for x in 80:
			var point := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.is_point_in_polygon(point, left):
				image.set_pixel(x, y, left_color)
			elif Geometry2D.is_point_in_polygon(point, right):
				image.set_pixel(x, y, right_color)
			elif Geometry2D.is_point_in_polygon(point, top):
				var sum_uv := (point.y - 5.0) / 17.5
				var difference_uv := (point.x - 40.0) / 33.0
				var uv := Vector2(
					(sum_uv + difference_uv) * 0.5,
					(sum_uv - difference_uv) * 0.5).clamp(Vector2.ZERO, Vector2.ONE)
				var color := tile.base_color
				if top_source != null and not top_source.is_empty():
					var sx := clampi(int(uv.x * (top_source.get_width() - 1)), 0, top_source.get_width() - 1)
					var sy := clampi(int(uv.y * (top_source.get_height() - 1)), 0, top_source.get_height() - 1)
					color = top_source.get_pixel(sx, sy)
					if color.a < 0.15:
						color = tile.base_color
				color = _preview_tint(color, tint)
				image.set_pixel(x, y, color.lightened(0.08))
	_draw_icon_edge(image, Vector2i(40, 5), Vector2i(73, 22))
	_draw_icon_edge(image, Vector2i(73, 22), Vector2i(73, 47))
	_draw_icon_edge(image, Vector2i(73, 47), Vector2i(40, 65))
	_draw_icon_edge(image, Vector2i(40, 65), Vector2i(7, 47))
	_draw_icon_edge(image, Vector2i(7, 47), Vector2i(7, 22))
	_draw_icon_edge(image, Vector2i(7, 22), Vector2i(40, 5))
	_draw_icon_edge(image, Vector2i(7, 22), Vector2i(40, 40))
	_draw_icon_edge(image, Vector2i(40, 40), Vector2i(73, 22))
	_draw_icon_edge(image, Vector2i(40, 40), Vector2i(40, 65))
	return ImageTexture.create_from_image(image)

func _preview_tint(color: Color, tint: Color) -> Color:
	if tint.a <= 0.001:
		return color
	var luminance := maxf(tint.r * 0.299 + tint.g * 0.587 + tint.b * 0.114, 0.05)
	var shifted := Color(
		clampf(color.r * tint.r / luminance, 0.0, 1.0),
		clampf(color.g * tint.g / luminance, 0.0, 1.0),
		clampf(color.b * tint.b / luminance, 0.0, 1.0),
		color.a)
	return color.lerp(shifted, tint.a)

func _draw_icon_edge(image: Image, start: Vector2i, end: Vector2i) -> void:
	var delta := (end - start).abs()
	var step := Vector2i(1 if start.x < end.x else -1, 1 if start.y < end.y else -1)
	var error := delta.x - delta.y
	var point := start
	while true:
		if point.x >= 0 and point.y >= 0 and point.x < image.get_width() and point.y < image.get_height():
			image.set_pixel(point.x, point.y, Color(0.08, 0.1, 0.1, 0.75))
		if point == end:
			break
		var twice := error * 2
		if twice > -delta.y:
			error -= delta.y
			point.x += step.x
		if twice < delta.x:
			error += delta.x
			point.y += step.y

func _on_tile_selected(index: int) -> void:
	var tiles := TileRegistry.all_tiles()
	if index < 0 or index >= tiles.size():
		tile_name_label.text = "未选择地块"
		tile_height_label.text = ""
		return
	var t := tiles[index]
	tile_name_label.text = "名称：%s（ID: %s）" % [t.display_name, t.tile_id]
	tile_height_label.text = "默认高度：%dm" % (t.default_height * 2)
	_sync_tint_controls()
	_refresh_brush_preview()

func _sync_tint_controls() -> void:
	if tint_picker == null or tint_strength == null:
		return
	var tile := selected_tile()
	var tint := data.terrain_tint(tile.tile_id) if data != null and tile != null \
		else Color(1.0, 1.0, 1.0, 0.0)
	tint_picker.color = Color(tint.r, tint.g, tint.b, 1.0)
	tint_strength.set_value_no_signal(tint.a)
	tint_strength_label.text = "着色强度：%d%%" % roundi(tint.a * 100.0)

func _apply_current_tint() -> void:
	var tile := selected_tile()
	if data == null or tile == null:
		_set_status("请先打开地图并选择地貌")
		return
	var tile_id := tile.tile_id
	var before := data.clone_data()
	var color := tint_picker.color
	color.a = tint_strength.value
	data.set_terrain_tint(tile_id, color)
	_commit_external(before, data.clone_data(), "调整地貌颜色")
	refresh_tile_list()
	var tiles := TileRegistry.all_tiles()
	for index in tiles.size():
		if tiles[index].tile_id == tile_id:
			tile_list.select(index)
			_on_tile_selected(index)
			break
	_set_status("已更新%s着色；源图片保持不变" % tile.display_name)

func _clear_current_tint() -> void:
	tint_strength.value = 0.0
	_apply_current_tint()

func _apply_tint_preset(color: Color, strength: float) -> void:
	tint_picker.color = color
	tint_strength.value = strength
	_apply_current_tint()

func selected_tile() -> TileDefinition:
	var selected := tile_list.get_selected_items()
	if selected.is_empty():
		return null
	var tiles := TileRegistry.all_tiles()
	if selected[0] >= tiles.size():
		return null
	return tiles[selected[0]]

# ============================================================
# Dialogs
# ============================================================
func _make_dialogs() -> void:
	file_dialog = EditorFileDialog.new()
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.add_filter("*.tres", "LevelData")
	file_dialog.file_selected.connect(_file_selected)
	file_dialog.canceled.connect(func(): play_after_save = false)
	dock_root.add_child(file_dialog)
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.dialog_text = "当前地图未保存。放弃修改？"
	confirm_dialog.ok_button_text = "放弃"
	confirm_dialog.confirmed.connect(_confirm_discard)
	dock_root.add_child(confirm_dialog)
	confirm_dialog.canceled.connect(func(): pending_action = "")

# ============================================================
# Status / dirty / preview
# ============================================================
func _set_status(text: String) -> void:
	status.text = text

func _set_dirty(value: bool) -> void:
	dirty = value
	dirty_label.text = ("(未保存)" if dirty else "") + (" · " + current_path.get_file() if not current_path.is_empty() else "")

func _make_preview() -> void:
	if not _require_builder("请先在场景树中选择 TerrainBuilder"):
		return
	if preview and is_instance_valid(preview):
		preview.queue_free()
	preview = MeshInstance3D.new()
	preview.name = "BrushPreview"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0.3, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview.material_override = mat
	builder.add_child(preview)

# ============================================================
# File operations
# ============================================================
func _require_builder(message := "请先在场景树中选择 TerrainBuilder") -> bool:
	if builder != null and is_instance_valid(builder):
		return true
	# Never retain half-edited data after its scene node was removed or the
	# selection changed while a file/confirmation dialog was open.
	builder = null
	data = null
	drawing = false
	play_after_save = false
	if not message.is_empty():
		_set_status(message)
	return false

func _new_map() -> void:
	if not _require_builder():
		return
	if dirty:
		pending_action = "new"
		confirm_dialog.popup_centered()
		return
	data = LevelData.new()
	data.setup_blank()
	builder.level_data = data
	builder.rebuild()
	current_path = ""
	_set_dirty(false)
	_set_status("新建空白地图")
	_make_preview()
	_sync_tint_controls()

func _open_map() -> void:
	if not _require_builder():
		return
	if dirty:
		pending_action = "open"
		confirm_dialog.popup_centered()
		return
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.popup_centered_ratio(0.7)

func _save_map() -> bool:
	if data == null or not _require_builder():
		return false
	if not _is_map_file(current_path):
		_save_as()
		return false
	var error := ResourceSaver.save(data, current_path)
	if error != OK:
		_set_status("保存失败：" + str(error))
		return false
	_set_dirty(false)
	EditorInterface.get_resource_filesystem().scan()
	_set_status("已保存：" + current_path)
	return true

func _is_map_file(path: String) -> bool:
	return path.begins_with("res://") and not path.contains("::") and path.get_extension() == "tres"

func _save_as() -> void:
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_path = current_path if _is_map_file(current_path) else "res://data/levels/my_map.tres"
	file_dialog.popup_centered_ratio(0.7)

func _file_selected(path: String) -> void:
	if file_dialog.file_mode == EditorFileDialog.FILE_MODE_SAVE_FILE:
		if data == null:
			play_after_save = false
			_set_status("当前没有可保存的地图")
			return
		var old_path := current_path
		current_path = path
		var saved := _save_map()
		if not saved:
			current_path = old_path
		var should_play := play_after_save
		play_after_save = false
		if saved and should_play:
			_start_saved_playtest()
	else:
		if not _require_builder():
			return
		var loaded := load(path) as LevelData
		if loaded == null:
			_set_status("不是有效的地图文件")
			return
		data = loaded
		data.ensure_layout()
		builder.level_data = data
		builder.rebuild()
		current_path = path
		_set_dirty(false)
		_set_status("已打开：" + path)
		_make_preview()
		_sync_tint_controls()

func _confirm_discard() -> void:
	if not _require_builder("操作已取消：请重新选择 TerrainBuilder"):
		pending_action = ""
		return
	_set_dirty(false)
	if pending_action == "new":
		_new_map()
	elif pending_action == "open":
		_open_map()
	pending_action = ""

func _rotate_stair(delta: int) -> void:
	if mode_select.selected not in [ToolMode.GROUND, ToolMode.STAIR]:
		return
	if mode_select.selected == ToolMode.STAIR:
		stair_direction = posmod(stair_direction + delta, 4)
		_set_status("阶梯方向 %d°" % (stair_direction * 90))
	else:
		tile_turns = posmod(tile_turns + delta, 4)
	tile_rotation_label.text = "方向：%d°（Q/E 旋转）" % (
		(stair_direction if mode_select.selected == ToolMode.STAIR else tile_turns) * 90)
	_set_status(tile_rotation_label.text)
	_refresh_brush_preview()

func _refresh_brush_preview() -> void:
	if data != null and is_instance_valid(builder) and data.in_bounds(hover_cell):
		_update_preview(hover_cell)

# ============================================================
# Input forwarding
# ============================================================
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	editing_camera = camera
	if fixed_view_active:
		if event is InputEventKey and event.keycode in view_move_keys and not (
				get_viewport().gui_get_focus_owner() is LineEdit):
			view_move_keys[event.keycode] = event.pressed
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_fixed_view(0.88)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_fixed_view(1.14)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event is InputEventMouseMotion and event.button_mask & (
				MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	if not is_instance_valid(builder) or data == null:
		builder = null
		data = null
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	# Tabs 1+ (物件/导入/预制) handled by world_tools
	if world_tools and world_tools.active():
		return world_tools.handle(camera, event)
	# Tab 0: terrain
	if tabs.current_tab != 0:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_rotate_stair(-1)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_E:
			_rotate_stair(1)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var cell := _pick(camera, event.position)
			var can_expand: bool = mode_select.selected == ToolMode.GROUND
			if not data.in_bounds(cell) and not can_expand:
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			drawing = true
			_begin_stroke()
			touched.clear()
			last_stroke_cell = Vector2i(-999, -999)
			if can_expand and not _ensure_ground_bounds(cell):
				drawing = false
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_paint(cell)
		else:
			if drawing:
				drawing = false
				_commit_stroke(_mode_name())
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion:
		var cell := _pick(camera, event.position)
		_update_preview(cell)
		if drawing and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if mode_select.selected == ToolMode.GROUND \
					and not _ensure_ground_bounds(cell):
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_paint(cell)
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _fixed_view_pressed() -> void:
	if fixed_view_active:
		_disable_2_5d_view()
	else:
		_enable_2_5d_view()

func _enable_2_5d_view() -> void:
	if not is_instance_valid(builder):
		return
	var previous_camera := editing_camera
	fixed_view_cameras.clear()
	fixed_view_states.clear()
	for index in 4:
		var viewport := EditorInterface.get_editor_viewport_3d(index)
		if viewport != null and is_instance_valid(viewport.get_camera_3d()):
			var camera := viewport.get_camera_3d()
			if camera not in fixed_view_cameras:
				fixed_view_cameras.append(camera)
	if is_instance_valid(previous_camera) and previous_camera not in fixed_view_cameras:
		fixed_view_cameras.append(previous_camera)
	if fixed_view_cameras.is_empty():
		_set_status("没有可用的3D编辑视口")
		fixed_view_button.set_pressed_no_signal(false)
		return
	editing_camera = fixed_view_cameras[0]
	for camera in fixed_view_cameras:
		fixed_view_states[camera.get_instance_id()] = {
			"camera": camera,
			"transform": camera.global_transform,
			"projection": camera.projection,
			"fov": camera.fov,
			"size": camera.size,
		}
	EditorInterface.set_main_screen_editor("3D")
	view_pan_offset = Vector3.ZERO
	fixed_view_active = true
	fixed_view_button.set_pressed_no_signal(true)
	for key in view_move_keys:
		view_move_keys[key] = false
	_apply_fixed_view()
	_set_status("2.5D视角已固定；WASD平移，滚轮缩放")

func _disable_2_5d_view() -> void:
	if fixed_view_active:
		for state: Dictionary in fixed_view_states.values():
			var camera: Camera3D = state["camera"]
			if not is_instance_valid(camera):
				continue
			camera.global_transform = state["transform"]
			camera.projection = state["projection"]
			camera.fov = state["fov"]
			camera.size = state["size"]
	fixed_view_active = false
	fixed_view_cameras.clear()
	fixed_view_states.clear()
	for key in view_move_keys:
		view_move_keys[key] = false
	if is_instance_valid(fixed_view_button):
		fixed_view_button.set_pressed_no_signal(false)

func _process(delta: float) -> void:
	if not fixed_view_active or not is_instance_valid(builder):
		return
	var camera := editing_camera
	if not is_instance_valid(camera) and not fixed_view_cameras.is_empty():
		camera = fixed_view_cameras[0]
	if is_instance_valid(camera):
		var right := camera.global_basis.x
		right.y = 0
		right = right.normalized()
		var up_screen := camera.global_basis.y
		up_screen.y = 0
		up_screen = up_screen.normalized()
		var input := Vector2(
			float(view_move_keys[KEY_D]) - float(view_move_keys[KEY_A]),
			float(view_move_keys[KEY_W]) - float(view_move_keys[KEY_S]))
		if input.length_squared() > 0:
			var speed := maxf(_effective_distance() * 0.45, 4.0)
			view_pan_offset += (right * input.x + up_screen * input.y).normalized() * speed * delta
	_apply_fixed_view()

func _apply_fixed_view() -> void:
	if not fixed_view_active or not is_instance_valid(builder):
		return
	var profile := load("res://data/art_profile.tres") as ArtProfile
	for camera in fixed_view_cameras:
		if is_instance_valid(camera):
			_configure_view_camera(camera, profile)

func _zoom_fixed_view(factor: float) -> void:
	var profile := load("res://data/art_profile.tres") as ArtProfile
	if preview_distance < 0:
		preview_distance = profile.camera_distance
	preview_distance = clampf(preview_distance * factor, 8.0, 120.0)
	if view_settings != null:
		view_settings.set_distance_from_viewport(preview_distance)
	_apply_fixed_view()

func _effective_distance() -> float:
	return preview_distance if preview_distance >= 0 else (
		load("res://data/art_profile.tres") as ArtProfile).camera_distance

func apply_view_parameters(fov: float, pitch: float, distance: float, target_height: float) -> void:
	preview_fov = fov
	preview_pitch = pitch
	preview_distance = distance
	preview_target_height = target_height
	if not fixed_view_active:
		_enable_2_5d_view()
	else:
		_apply_fixed_view()

func _configure_view_camera(camera: Camera3D, source: ArtProfile) -> void:
	var profile := source.duplicate() as ArtProfile
	if preview_fov >= 0:
		profile.field_of_view = preview_fov
	if preview_pitch >= 0:
		profile.pitch_degrees = preview_pitch
	if preview_distance >= 0:
		profile.camera_distance = preview_distance
	if not is_inf(preview_target_height):
		profile.target_height = preview_target_height
	profile.configure(camera, builder.global_position + view_pan_offset)

func _commit_external(before: Dictionary, after: Dictionary, label: String,
		apply_after := true) -> void:
	if data == null or not is_instance_valid(builder) or before == after:
		return
	# Bind history and callbacks to the original map, never the current map.
	var target := data
	var undo_redo := get_undo_redo()
	undo_redo.create_action(label, UndoRedo.MERGE_DISABLE, target)
	undo_redo.add_do_method(self, "_apply_map_snapshot", target, after.duplicate(true))
	undo_redo.add_undo_method(self, "_apply_map_snapshot", target, before.duplicate(true))
	undo_redo.commit_action(apply_after)
	if not apply_after:
		_set_dirty(true)

func _apply_snapshot(snapshot: Dictionary) -> void:
	_apply_map_snapshot(data, snapshot)

func _apply_map_snapshot(target: LevelData, snapshot: Dictionary) -> void:
	target.restore_data(snapshot)
	if target == data:
		if is_instance_valid(builder):
			builder.rebuild()
		_sync_tint_controls()
		_set_dirty(true)

func _begin_stroke() -> void:
	stroke_cells_before.clear()
	stroke_aux_before = _terrain_aux_snapshot(data)
	stroke_full_before.clear()
	pending_expansion_before.clear()

func _record_stroke_changes(changes: Array[Dictionary]) -> void:
	for change in changes:
		var cell: Vector2i = change["cell"]
		if not stroke_cells_before.has(cell):
			stroke_cells_before[cell] = change["before"].duplicate(true)

func _commit_stroke(label: String) -> void:
	if data == null or not is_instance_valid(builder):
		return
	if not stroke_full_before.is_empty():
		_commit_external(stroke_full_before, data.clone_data(), label, false)
		return
	var after_cells := {}
	for cell: Vector2i in stroke_cells_before:
		after_cells[cell] = data.get_cell(cell).duplicate(true)
	var after_aux := _terrain_aux_snapshot(data)
	if stroke_cells_before.is_empty() and stroke_aux_before == after_aux:
		return
	var target := data
	var undo_redo := get_undo_redo()
	undo_redo.create_action(label, UndoRedo.MERGE_DISABLE, target)
	undo_redo.add_do_method(
		self, "_apply_terrain_delta", target,
		after_cells.duplicate(true), after_aux.duplicate(true))
	undo_redo.add_undo_method(
		self, "_apply_terrain_delta", target,
		stroke_cells_before.duplicate(true), stroke_aux_before.duplicate(true))
	undo_redo.commit_action(false)
	_set_dirty(true)

func _terrain_aux_snapshot(target: LevelData) -> Dictionary:
	return {
		"stairs": target.stairs.duplicate(true),
		"spawn_cell": target.spawn_cell,
		"objects": target.objects.duplicate(true),
	}

func _stroke_start_snapshot() -> Dictionary:
	var snapshot := data.clone_data()
	for cell: Vector2i in stroke_cells_before:
		if data.in_bounds(cell):
			snapshot["cells"][data.index(cell)] = \
				stroke_cells_before[cell].duplicate(true)
	snapshot["stairs"] = stroke_aux_before["stairs"].duplicate(true)
	snapshot["spawn_cell"] = stroke_aux_before["spawn_cell"]
	snapshot["objects"] = stroke_aux_before["objects"].duplicate(true)
	return snapshot

func _ground_brush_region(cell: Vector2i) -> Rect2i:
	var brush_size := 3 if brush_select.selected == 1 else 1
	var half := brush_size / 2
	return Rect2i(cell - Vector2i(half, half), Vector2i(brush_size, brush_size))

func _ensure_ground_bounds(cell: Vector2i) -> bool:
	if mode_select.selected != ToolMode.GROUND:
		return data.in_bounds(cell)
	var region := _ground_brush_region(cell)
	if data.contains_region(region):
		pending_expansion_before.clear()
		return true
	var captured_snapshot := false
	if stroke_full_before.is_empty():
		stroke_full_before = _stroke_start_snapshot()
		captured_snapshot = true
	pending_expansion_before = data.clone_data()
	var error := data.expand_to_include(region)
	if not error.is_empty():
		pending_expansion_before.clear()
		if captured_snapshot:
			stroke_full_before.clear()
		_set_status(error)
		return false
	return true

func _apply_terrain_delta(target: LevelData, cell_values: Dictionary,
		aux: Dictionary) -> void:
	target.set_cells(cell_values)
	target.stairs.assign(aux["stairs"].duplicate(true))
	target.spawn_cell = aux["spawn_cell"]
	target.objects.assign(aux["objects"].duplicate(true))
	target.emit_changed()
	if target == data:
		if is_instance_valid(builder):
			builder.rebuild()
		_set_dirty(true)

func _mode_name() -> String:
	return {ToolMode.GROUND: "刷地块", ToolMode.ERASE: "擦除地块",
		ToolMode.STAIR: "放置阶梯", ToolMode.SPAWN: "设置出生点"}.get(mode_select.selected, "编辑地图")

# ============================================================
# Terrain painting
# ============================================================
func _paint(cell: Vector2i) -> void:
	if data == null or not is_instance_valid(builder):
		return
	if not data.in_bounds(cell):
		return
	if cell == last_stroke_cell:
		return
	last_stroke_cell = cell
	var mode: int = mode_select.selected
	if mode == ToolMode.STAIR:
		_try_stair(cell)
		return
	if mode == ToolMode.SPAWN:
		data.spawn_cell = cell
		builder.rebuild()
		return
	var brush_size := 3 if brush_select.selected == 1 else 1
	var half := brush_size / 2
	var targets: Array[Vector2i] = []
	for dy in brush_size:
		for dx in brush_size:
			var target := cell + Vector2i(dx - half, dy - half)
			if data.in_bounds(target) and not touched.has(target):
				targets.append(target)
	var changes: Array[Dictionary] = []
	if mode == ToolMode.GROUND:
		changes = _paint_ground_cells(targets)
	elif mode == ToolMode.ERASE:
		changes = _erase_cells(targets)
	if changes.is_empty():
		if not pending_expansion_before.is_empty():
			data.restore_data(pending_expansion_before)
			pending_expansion_before.clear()
			builder.rebuild()
		return
	pending_expansion_before.clear()
	_record_stroke_changes(changes)
	if mode == ToolMode.GROUND and _can_refresh_blend(changes):
		var dirty_cells: Array[Vector2i] = []
		for change in changes:
			dirty_cells.append(change["cell"])
		if builder.refresh_blend_cells(dirty_cells):
			return
	builder.rebuild()

func _paint_single(cell: Vector2i, mode: int) -> void:
	if not data.in_bounds(cell) or touched.has(cell):
		return
	var targets: Array[Vector2i] = [cell]
	if mode == ToolMode.GROUND:
		_paint_ground_cells(targets)
		return
	if mode != ToolMode.ERASE:
		return
	_erase_cells(targets)

func _erase_cells(targets: Array[Vector2i]) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	var values := {}
	var content_changed := false
	for cell in targets:
		if not data.in_bounds(cell) or touched.has(cell):
			continue
		touched[cell] = true
		# Removing support also removes its objects (including decorative ones).
		for i in range(data.objects.size() - 1, -1, -1):
			var record: Dictionary = data.objects[i]
			if data.world_to_cell(record["position"]) == cell or cell in ObjectRules.covered_cells(data, record):
				data.objects.remove_at(i)
				content_changed = true
		var stair_idx := data.stair_at(cell)
		if stair_idx >= 0:
			data.stairs.remove_at(stair_idx)
			content_changed = true
			var stair_cell := data.get_cell(cell).duplicate(true)
			changes.append({
				"cell": cell,
				"before": stair_cell,
				"after": stair_cell,
			})
		elif data.cell_exists(cell):
			if data.spawn_cell == cell:
				data.spawn_cell = Vector2i(-1, -1)
			var old_value := data.get_cell(cell).duplicate(true)
			var new_value := {
				"exists": false,
				"terrain": 0,
				"height": 0,
				"tile_id": "grass",
				"rotation": 0,
			}
			values[cell] = new_value
			changes.append({
				"cell": cell,
				"before": old_value,
				"after": new_value,
			})
	if not values.is_empty():
		data.set_cells(values)
	elif content_changed:
		data.emit_changed()
	return changes

func _paint_ground_cells(targets: Array[Vector2i]) -> Array[Dictionary]:
	var pending: Array[Vector2i] = []
	for cell in targets:
		if not data.in_bounds(cell) or touched.has(cell):
			continue
		if data.stair_at(cell) >= 0:
			_set_status("请先移除阶梯，再替换其地块")
			return []
		pending.append(cell)
	if pending.is_empty():
		return []
	var tile := selected_tile()
	var tile_id := tile.tile_id if tile else "grass"
	var new_height := height_select.selected
	var values := {}
	var changes: Array[Dictionary] = []
	var height_changes := {}
	for cell in pending:
		var old_value := data.get_cell(cell).duplicate(true)
		var new_value := {
			"exists": true,
			"terrain": TileRegistry.id_to_legacy_terrain(tile_id),
			"height": new_height,
			"tile_id": tile_id,
			"rotation": tile_turns,
		}
		touched[cell] = true
		if old_value == new_value:
			continue
		values[cell] = new_value
		changes.append({
			"cell": cell,
			"before": old_value,
			"after": new_value,
		})
		var old_height := int(old_value.get("height", 0))
		if bool(old_value.get("exists", false)) and old_height != new_height:
			height_changes[cell] = new_height - old_height
	if changes.is_empty():
		return changes
	if height_changes.is_empty():
		data.set_cells(values)
		return changes
	var candidate := LevelData.new()
	candidate.restore_data(data.clone_data())
	candidate.set_cells(values)
	for record in candidate.objects:
		var anchor := candidate.world_to_cell(record["position"])
		if height_changes.has(anchor):
			record["position"].y += int(height_changes[anchor]) * LevelData.ELEVATION_STEP
	var errors := candidate.validate()
	if errors.has("缺少有效的玩家出生点"):
		errors.remove_at(errors.find("缺少有效的玩家出生点"))
	if not errors.is_empty():
		for cell in pending:
			touched.erase(cell)
		_set_status("无法改变高度：" + "\n".join(errors))
		return []
	data.restore_data(candidate.clone_data())
	return changes

func _ground_candidate(cell: Vector2i) -> Dictionary:
	if not data.in_bounds(cell):
		return {"error": "地块超出地图"}
	if data.stair_at(cell) >= 0:
		return {"error": "请先移除阶梯，再替换其地块"}
	var candidate := LevelData.new()
	var tile := selected_tile()
	var id := tile.tile_id if tile else "grass"
	var old_height := data.elevation(cell)
	var new_height := height_select.selected
	if not data.cell_exists(cell) or old_height == new_height:
		return {"error": "", "snapshot": {}}
	candidate.restore_data(data.clone_data())
	candidate.set_cell(cell, {"exists": true, "terrain": TileRegistry.id_to_legacy_terrain(id),
		"height": new_height, "tile_id": id, "rotation": tile_turns})
	# Objects anchored on this tile follow its height. Objects spanning several
	# tiles must still have level support; reject the whole edit if not.
	if old_height != new_height:
		for record in candidate.objects:
			if candidate.world_to_cell(record["position"]) == cell:
				record["position"].y += (new_height - old_height) * LevelData.ELEVATION_STEP
		var errors := candidate.validate()
		# A map in progress need not have a spawn point, but changing terrain
		# must not disconnect existing stairs or leave objects unsupported.
		if errors.has("缺少有效的玩家出生点"):
			errors.remove_at(errors.find("缺少有效的玩家出生点"))
		if not errors.is_empty():
			return {"error": "无法改变高度：" + "\n".join(errors)}
	return {"error": "", "snapshot": candidate.clone_data()}

func _can_refresh_blend(changes: Array[Dictionary]) -> bool:
	for change in changes:
		var before: Dictionary = change["before"]
		var after: Dictionary = change["after"]
		if not bool(before.get("exists", false)) or not bool(after.get("exists", false)):
			return false
		if int(before.get("height", 0)) != int(after.get("height", 0)):
			return false
		var old_tile := TileRegistry.find(str(before.get("tile_id", "grass")))
		var new_tile := TileRegistry.find(str(after.get("tile_id", "grass")))
		if old_tile == null or new_tile == null \
				or old_tile.surface_kind != new_tile.surface_kind:
			return false
		var cell: Vector2i = change["cell"]
		var elevation := data.elevation(cell)
		for direction in LevelData.DIRS:
			var neighbor: Vector2i = cell + direction
			if not data.cell_exists(neighbor) or data.elevation(neighbor) != elevation:
				return false
	return true

func _try_stair(cell: Vector2i) -> void:
	if data == null or not is_instance_valid(builder):
		return
	var error := data.can_place_stair(cell, stair_direction)
	if not error.is_empty():
		_set_status(error)
		return
	data.stairs.append({"cell": cell, "direction": stair_direction})
	builder.rebuild()

func _pick(camera: Camera3D, mouse: Vector2) -> Vector2i:
	var origin := camera.project_ray_origin(mouse)
	var ray := camera.project_ray_normal(mouse)
	var best := INF
	var result := Vector2i(-1, -1)
	if absf(ray.y) < 0.00001:
		return result
	for elevation: int in [2, 1, 0]:
		var distance := (elevation * LevelData.ELEVATION_STEP - origin.y) / ray.y
		if distance < 0 or distance >= best:
			continue
		var p := origin + ray * distance
		var cell := data.world_to_cell(p)
		if data.cell_exists(cell) and data.elevation(cell) == elevation:
			result = cell
			best = distance
	if is_inf(best):
		var height := height_select.selected
		var distance: float = (height * LevelData.ELEVATION_STEP - origin.y) / ray.y
		var p := origin + ray * maxf(distance, 0)
		result = data.world_to_cell(p)
	return result

func _update_preview(cell: Vector2i) -> void:
	hover_cell = cell
	if data == null or not is_instance_valid(builder) or not is_instance_valid(preview):
		return
	for child in preview.get_children():
		preview.remove_child(child)
		child.queue_free()
	preview.rotation = Vector3.ZERO
	preview.material_override = StandardMaterial3D.new()
	var preview_mat := preview.material_override as StandardMaterial3D
	preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mode: int = mode_select.selected
	if not data.in_bounds(cell) and mode != ToolMode.GROUND:
		preview.visible = false
		return
	if mode == ToolMode.GROUND:
		preview.visible = true
		preview.mesh = null
		preview.position = Vector3.ZERO
		var expansion_error := data.expansion_error(_ground_brush_region(cell))
		var error_text := expansion_error
		var valid := expansion_error.is_empty()
		var fragment := LevelData.new()
		var brush_size := 3 if brush_select.selected == 1 else 1
		fragment.setup_blank(Vector2i(brush_size, brush_size))
		fragment.terrain_tints = data.terrain_tints.duplicate(true)
		var tile := selected_tile()
		var id := tile.tile_id if tile else "grass"
		for y in brush_size:
			for x in brush_size:
				var target := cell + Vector2i(x - brush_size / 2, y - brush_size / 2)
				if data.in_bounds(target):
					var check := _ground_candidate(target)
					if not check["error"].is_empty():
						valid = false
						if error_text.is_empty():
							error_text = check["error"]
				fragment.set_cell(Vector2i(x, y), {"exists": true, "tile_id": id,
					"terrain": TileRegistry.id_to_legacy_terrain(id),
					"height": height_select.selected, "rotation": tile_turns})
		var display := TerrainBuilder.new()
		display.level_data = fragment
		display.show_grid = false
		display.build_collision = false
		display.position = data.world_center(cell, 0) + Vector3(0, 0.035, 0)
		preview.add_child(display)
		# Same builder/materials as the final terrain, plus a translucent overlay.
		for node in display.generated.get_children():
			if node is MeshInstance3D:
				var overlay := StandardMaterial3D.new()
				overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				overlay.albedo_color = Color(0.3, 1, 0.5, 0.08) if valid else Color(1, 0.1, 0.1, 0.55)
				node.material_overlay = overlay
		_set_status("地块预览：%d° / %dm，左键绘制" % [tile_turns * 90, height_select.selected * 2]
			if valid else "红色区域不可绘制：" + error_text)
		return
	if mode == ToolMode.STAIR:
		var low := cell
		var high: Vector2i = cell + LevelData.DIRS[stair_direction]
		var valid := data.can_place_stair(low, stair_direction).is_empty()
		var center := data.world_center(low)
		if data.in_bounds(high):
			center = (center + data.world_center(high)) * 0.5
		center.y += 0.1
		preview.visible = true
		var mesh := BoxMesh.new()
		mesh.size = Vector3(LevelData.CELL_SIZE, 0.18, LevelData.CELL_SIZE * 2)
		if stair_direction % 2 == 1:
			mesh.size = Vector3(LevelData.CELL_SIZE * 2, 0.18, LevelData.CELL_SIZE)
		preview.mesh = mesh
		preview.position = center
		var mat := preview.material_override as StandardMaterial3D
		mat.albedo_color = Color(0.3, 1, 0.5, 0.5) if valid else Color(1, 0.2, 0.2, 0.5)
		return
	var brush_size := 3 if brush_select.selected == 1 and mode <= ToolMode.ERASE else 1
	var height := data.elevation(cell) if data.cell_exists(cell) else height_select.selected
	var center := data.world_center(cell, height)
	preview.visible = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3(LevelData.CELL_SIZE * brush_size, 0.12, LevelData.CELL_SIZE * brush_size)
	preview.mesh = mesh
	preview.position = center + Vector3(0, 0.08, 0)
	var mat := preview.material_override as StandardMaterial3D
	mat.albedo_color = Color(1, 1, 0.3, 0.45) if mode != ToolMode.ERASE else Color(1, 0.25, 0.15, 0.45)

func _playtest() -> void:
	if data == null or not _require_builder():
		return
	if not _is_map_file(current_path):
		play_after_save = true
		_save_as()
		return
	play_after_save = false
	if not _save_map():
		return
	_start_saved_playtest()

func _start_saved_playtest() -> void:
	if not _write_playtest_request():
		return
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
	_set_status("正在试玩当前地图：" + current_path)
	EditorInterface.play_custom_scene("res://scenes/level_playtest.tscn")

func _write_playtest_request(request_path := "user://terrain_playtest.cfg") -> bool:
	if data == null or not _require_builder() or not _is_map_file(current_path):
		_set_status("请先将当前地图保存为独立 .tres 文件")
		return false
	var errors := data.validate()
	if not errors.is_empty():
		_set_status("\n".join(errors))
		return false
	var config := ConfigFile.new()
	config.set_value("playtest", "level_path", current_path)
	var error := config.save(request_path)
	if error != OK:
		_set_status("无法写入试玩请求：" + error_string(error))
		return false
	return true
