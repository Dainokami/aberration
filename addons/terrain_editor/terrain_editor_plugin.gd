@tool
extends EditorPlugin

## ============================================================
## 畸变 关卡编辑器 v0.5  —  地形视觉 P0 / 物件 / 导入 / 预制
## ============================================================

enum ToolMode { GROUND = 0, ERASE = 2, STAIR = 3, SPAWN = 4 }
enum ViewMode { FREE, PERSPECTIVE_2_5D, TOP }
const BlockPicker := preload("res://addons/terrain_editor/block_picker.gd")
const INVALID_BLOCK := Vector3i(-999, -999, -999)
const EDIT_MODE_COLOR := Color("#f06a73")
const NAVIGATION_MODE_COLOR := Color("#65d58a")

# --- State --------------------------------------------------
var builder: TerrainBuilder
var data: LevelData
var current_path := ""
var dirty := false
var drawing := false
var stroke_erase := false
var stroke_button := MOUSE_BUTTON_LEFT
var stroke_plane := Plane()
var stroke_normal := Vector3i.UP
var stroke_block := INVALID_BLOCK
var hover_block := INVALID_BLOCK
var hover_normal := Vector3i.UP
var hover_point := Vector3.ZERO
var active_layer := 0
var _erase_button_down := false
var _alt_navigation := false
var _view_mode_badges: Array[PanelContainer] = []
var default_right_delete: CheckButton
var terrain_input_hint: Label
var last_mouse := Vector2.ZERO
var stroke_cells_before: Dictionary = {}
var stroke_aux_before: Dictionary = {}
var stroke_bounds_before := Rect2i()
var pending_bounds_before := Rect2i()
var touched: Dictionary = {}
var stair_direction := 0
var tile_turns := 0
var play_after_save := false
var tile_rotation_label: Label
var hover_cell := Vector2i(-999, -999)
var fixed_view_button: Button
var top_view_button: Button
var free_view_button: Button
var editing_camera: Camera3D
var fixed_view_active := false
var free_view_active := false
var free_view_states: Dictionary = {}
var view_mode: ViewMode = ViewMode.FREE
var fixed_view_cameras: Array[Camera3D] = []
var fixed_view_states: Dictionary = {}
var view_pan_offset := Vector3.ZERO
var top_view_size := 25.0
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
var slice_select: OptionButton
var layer_controls: Array[Control] = []
var erase_select: OptionButton
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
var world_gen_dialog
var world_gen_target: TerrainBuilder
var encounter_tools
var transition_tools
var preview_fov := -1.0
var preview_pitch := -1.0
var preview_distance := -1.0
var preview_target_height := INF
var picked_layer := -1
var _preview_key := ""
var _preview_pending := false

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
	world_tools.add_detail_page()
	encounter_tools = load("res://addons/terrain_editor/encounter_tools.gd").new()
	encounter_tools.setup(self, tabs)
	transition_tools = load("res://addons/terrain_editor/level_transition_tools.gd").new()
	transition_tools.setup(self, tabs)
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
	set_force_draw_over_forwarding_enabled()
	RenderingServer.frame_pre_draw.connect(_apply_fixed_view)
	get_tree().root.focus_exited.connect(_clear_view_input)
	get_tree().root.gui_focus_changed.connect(_view_focus_changed)
	if "--test-stream-editor" in OS.get_cmdline_user_args():
		_run_stream_checks.call_deferred()
	elif "--test-v2-editor" in OS.get_cmdline_user_args():
		_run_editor_checks.call_deferred()
	elif "--test-scene-placement" in OS.get_cmdline_user_args():
		_run_scene_placement_checks.call_deferred()
	elif "--test-worldgen-editor" in OS.get_cmdline_user_args():
		_run_worldgen_checks.call_deferred()
	elif "--test-encounter-editor" in OS.get_cmdline_user_args():
		_run_encounter_checks.call_deferred()
	elif "--test-transition-editor" in OS.get_cmdline_user_args():
		_run_transition_checks.call_deferred()

func _run_transition_checks() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	await load("res://tests/editor_level_transition_checks.gd").new().run(self)

func _run_stream_checks() -> void:
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	await load("res://tests/editor_chunk_streaming_checks.gd").new().run(self)

func _run_encounter_checks() -> void:
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	await load("res://tests/editor_encounter_checks.gd").new().run(self)

func _run_worldgen_checks() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	await load("res://tests/editor_world_generation_checks.gd").new().run(self)

func _run_scene_placement_checks() -> void:
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	await load("res://tests/editor_scene_mechanism_placement.gd").new().run(self)

func _run_editor_checks() -> void:
	# Wait for startup imports before tests create/delete temporary resources.
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var suite = load("res://tests/editor_v2_checks.gd").new()
	await suite.run(self)

func _exit_tree() -> void:
	_finish_terrain_stroke()
	if encounter_tools:
		encounter_tools.finish_stroke()
		encounter_tools.reset_overlay()
	if is_instance_valid(world_gen_dialog):
		world_gen_dialog.queue_free()
	_disable_2_5d_view()
	for badge in _view_mode_badges:
		if is_instance_valid(badge):
			badge.queue_free()
	_view_mode_badges.clear()
	get_tree().root.focus_exited.disconnect(_clear_view_input)
	get_tree().root.gui_focus_changed.disconnect(_view_focus_changed)
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
	_finish_terrain_stroke()
	if encounter_tools:
		encounter_tools.finish_stroke()
	if world_tools:
		world_tools.reset()
	if object is TerrainBuilder:
		if builder != object:
			_disable_2_5d_view()
		builder = object
		if not builder.chunks_changed.is_connected(_stream_overlay_changed):
			builder.chunks_changed.connect(_stream_overlay_changed)
		data = builder.level_data
		if data:
			data.ensure_layout()
			current_path = data.resource_path
			_set_status("已载入：" + current_path)
			_make_preview()
			_sync_tint_controls()
			_enable_initial_view.call_deferred(builder)
	else:
		_disable_2_5d_view()
		builder = null
		data = null
		if preview and is_instance_valid(preview):
			preview.queue_free()
	if encounter_tools:
		encounter_tools.sync()
	if transition_tools:
		transition_tools.sync()

func _enable_initial_view(target: TerrainBuilder) -> void:
	if builder == target and not fixed_view_active and not free_view_active:
		_enable_2_5d_view()

func _stream_overlay_changed() -> void:
	if encounter_tools and is_instance_valid(builder) and builder.is_streaming():
		encounter_tools.refresh_overlay()

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
	dock_root.custom_minimum_size.x = ui_px(310)

	var title := Label.new()
	title.text = "畸变 关卡编辑器 v0.5"
	title.add_theme_font_size_override("font_size", 19)
	dock_root.add_child(title)

	dirty_label = Label.new()
	dock_root.add_child(dirty_label)

	# File operations row
	var files := HBoxContainer.new()
	dock_root.add_child(files)
	for spec in [["新建", "_new_map"], ["打开", "_open_map"], ["保存", "_save_map"], ["另存为", "_save_as"]]:
		var button := Button.new()
		button.text = spec[0]
		button.pressed.connect(Callable(self, spec[1]))
		files.add_child(button)
	default_right_delete = CheckButton.new()
	default_right_delete.name = "DefaultRightDelete"
	default_right_delete.text = "默认右键删除"
	default_right_delete.tooltip_text = "开启后右键删除地块，自由视角中移动视角使用alt+右键。\n关闭后删除地块必须alt+右键，自由视角中移动视角则直接右键"
	default_right_delete.button_pressed = EditorInterface.get_editor_settings().get_project_metadata(
		"terrain_editor", "default_right_delete", true)
	default_right_delete.toggled.connect(_right_delete_changed)
	files.add_child(default_right_delete)
	var generate_world := Button.new()
	generate_world.name = "OpenWorldGeneration"
	generate_world.text = "世界生成…"
	generate_world.tooltip_text = "用已保存地图作为特殊地块，生成有限世界"
	generate_world.pressed.connect(_open_world_generation)
	dock_root.add_child(generate_world)
	var view_modes := HBoxContainer.new()
	dock_root.add_child(view_modes)
	var view_label := Label.new()
	view_label.text = "编辑视角"
	view_modes.add_child(view_label)
	var view_group := ButtonGroup.new()
	for spec in [
			["2.5D", "_fixed_view_pressed",
				"固定游戏透视；WASD平移，滚轮缩放"],
			["俯视", "_top_view_pressed",
				"正交垂直俯视；适合精确选择和摆放格子"],
			["自由", "_free_view_pressed",
				"WASD移动，滚轮缩放，Alt＋右键拖动转向，中键拖动平移"],
		]:
		var button := Button.new()
		button.text = spec[0]
		button.tooltip_text = spec[2]
		button.toggle_mode = true
		button.button_group = view_group
		button.pressed.connect(Callable(self, spec[1]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view_modes.add_child(button)
		match spec[1]:
			"_fixed_view_pressed":
				fixed_view_button = button
			"_top_view_pressed":
				top_view_button = button
			"_free_view_pressed":
				free_view_button = button
	_sync_view_buttons()
	process_priority = 100

	# Tabs
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.tab_changed.connect(func(_index: int): _finish_terrain_stroke())
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
	for spec in [["选地块", ToolMode.GROUND],
			["阶梯", ToolMode.STAIR], ["出生点", ToolMode.SPAWN]]:
		mode_select.add_mode(spec[0], spec[1])
	placement.add_child(mode_select)
	mode_select.item_selected.connect(_terrain_mode_changed)

	# Viewing filters never choose where a block is placed.
	layer_controls.append(_add_label(placement, "地块显示层次"))
	slice_select = OptionButton.new()
	slice_select.name = "DisplayLayer"
	slice_select.add_item("显示全部层")
	for layer in LevelData.MAX_LAYERS:
		slice_select.add_item("仅显示至第 %d 层" % layer)
	slice_select.item_selected.connect(_slice_changed)
	placement.add_child(slice_select)
	_limit_layer_popup(slice_select)
	layer_controls.append(slice_select)
	terrain_input_hint = _add_label(placement,
		"左键：贴面摆放，可沿起始平面拖动绘制\n右键：每次点击只删除一块，长按不连续删除\nAlt＋右键：转动自由视角")
	terrain_input_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer_controls.append(terrain_input_hint)
	layer_controls.append(_add_label(placement, "右键擦除内容"))
	erase_select = OptionButton.new()
	for label in ["擦除实体块", "仅清除液体", "仅清除贴花", "仅移除阶梯"]:
		erase_select.add_item(label)
	placement.add_child(erase_select)
	erase_select.item_selected.connect(func(_index: int): _refresh_brush_preview())

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
	ground_controls.append(_add_label(placement, "地块列表（选择后在视口摆放）"))

	tile_list = ItemList.new()
	tile_list.auto_height = true
	tile_list.size_flags_vertical = Control.SIZE_FILL
	tile_list.icon_mode = ItemList.ICON_MODE_TOP
	tile_list.fixed_icon_size = ui_size(Vector2(80, 72))
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
	_sync_right_delete_hints()

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
	for control in layer_controls:
		control.visible = value in [ToolMode.GROUND, ToolMode.ERASE]
	erase_select.visible = value in [ToolMode.GROUND, ToolMode.ERASE]
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
	tile_height_label.text = "固定厚度：2m；贴面逐块堆叠" if t.is_block() else "附着在指向的外露顶面"
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
	_preview_key = ""
	_preview_pending = false
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
func _open_world_generation() -> void:
	if not _require_builder():
		return
	_finish_terrain_stroke()
	world_gen_target = builder
	if not is_instance_valid(world_gen_dialog):
		world_gen_dialog = load("res://addons/terrain_editor/world_gen_dialog.gd").new()
		world_gen_dialog.map_ready.connect(_apply_generated_world)
		add_child(world_gen_dialog)
	world_gen_dialog.popup_centered_clamped(ui_size(Vector2(1120, 760)), 0.9)

func _apply_generated_world(generated: LevelData) -> void:
	if not is_instance_valid(world_gen_target) or builder != world_gen_target:
		_set_status("工作场景已切换，请重新打开世界生成窗口")
		if is_instance_valid(world_gen_dialog):
			world_gen_dialog._status.text = "工作场景已切换，请关闭并重新打开本窗口后再应用"
		return
	if generated.encounter == null:
		generated.encounter = data.encounter.duplicate(true) as EncounterConfig \
			if data.encounter != null else null
	if generated.level_transition == null:
		generated.level_transition = data.level_transition.duplicate(true) as LevelTransitionConfig \
			if data.level_transition != null else null
	var before := {"map": data, "path": current_path, "dirty": dirty}
	var after := {"map": generated, "path": "", "dirty": true}
	var history := get_undo_redo()
	history.create_action("应用生成世界", UndoRedo.MERGE_DISABLE, builder)
	history.add_do_method(self, "_switch_generated_map", builder, before, after)
	history.add_undo_method(self, "_switch_generated_map", builder, after, before)
	history.commit_action()
	if is_instance_valid(world_gen_dialog):
		world_gen_dialog.confirm_applied()

func _switch_generated_map(target: TerrainBuilder, outgoing: Dictionary, incoming: Dictionary) -> void:
	# A stale action must never replace a subsequently opened unrelated map.
	if not is_instance_valid(target) or target.level_data != outgoing.map:
		return
	if builder == target:
		outgoing.path = current_path
		outgoing.dirty = dirty
		_finish_terrain_stroke()
		if world_tools:
			world_tools.reset()
	target.level_data = incoming.map
	target.rebuild()
	if builder == target:
		data = incoming.map
		current_path = incoming.path
		_set_dirty(incoming.dirty)
		_make_preview()
		_sync_tint_controls()
		if encounter_tools:
			encounter_tools.sync()
		if transition_tools:
			transition_tools.sync()
		_set_status("已切换地图 · 世界生成支持撤销/重做 · 请另存新地图")

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
	_preview_key = ""
	_preview_pending = false
	if data != null and is_instance_valid(builder):
		_update_preview(hover_cell)

func _slice_changed(index: int) -> void:
	if is_instance_valid(builder):
		builder.set_slice_layer(index - 1)
	if encounter_tools:
		encounter_tools.refresh_overlay()
	_refresh_brush_preview()

func _limit_layer_popup(option: OptionButton) -> void:
	var popup := option.get_popup()
	popup.prefer_native_menu = false
	popup.about_to_popup.connect(_resize_layer_popup.bind(popup))
	_resize_layer_popup(popup)

## Fixed pixel sizes in docks must follow the editor's HiDPI scale.
static func ui_px(value: float) -> int:
	return roundi(value * EditorInterface.get_editor_scale())

static func ui_size(value: Vector2) -> Vector2i:
	return Vector2i((value * EditorInterface.get_editor_scale()).round())

func _resize_layer_popup(popup: PopupMenu) -> void:
	_clear_view_input()
	var font := popup.get_theme_font("font")
	var row_height := font.get_height(popup.get_theme_font_size("font_size")) \
		+ popup.get_theme_constant("v_separation")
	var padding := popup.get_theme_stylebox("panel").get_minimum_size().y
	var available := get_tree().root.size.y * 0.45
	# Godot 4.7 ignores the whole limit if max width is below the menu's minimum.
	popup.max_size = Vector2i(maxi(1, get_tree().root.size.x),
		maxi(1, roundi(minf(row_height * 8 + padding, available))))

func _clear_view_input() -> void:
	for key in view_move_keys:
		view_move_keys[key] = false
	_finish_terrain_stroke()
	_erase_button_down = false
	_set_alt_navigation(false)

func _finish_terrain_stroke() -> void:
	if not drawing:
		return
	drawing = false
	_commit_stroke(_mode_name())
	stroke_erase = false

func _view_focus_changed(_control: Control) -> void:
	_clear_view_input()

func _text_input_focused() -> bool:
	var focus := get_tree().root.gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit

func _update_alt_state(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ALT:
		_set_alt_navigation(event.pressed)
	elif event is InputEventWithModifiers:
		_set_alt_navigation(event.alt_pressed)

func _set_alt_navigation(pressed: bool) -> void:
	if _alt_navigation == pressed:
		return
	_alt_navigation = pressed
	if free_view_active:
		if _right_button_navigates(pressed):
			_finish_terrain_stroke()
			_preview_pending = false
			if is_instance_valid(preview):
				preview.hide()
		elif is_instance_valid(editing_camera) and is_instance_valid(builder) and data != null:
			_update_terrain_target(editing_camera, last_mouse, false)
			_preview_pending = true
	_refresh_view_mode_badges()

func _right_button_deletes(alt: bool) -> bool:
	return alt != default_right_delete.button_pressed

func _right_button_navigates(alt: bool) -> bool:
	return not _right_button_deletes(alt)

func _right_delete_changed(value: bool) -> void:
	_finish_terrain_stroke()
	_erase_button_down = false
	EditorInterface.get_editor_settings().set_project_metadata(
		"terrain_editor", "default_right_delete", value)
	_refresh_view_mode_badges()
	_sync_right_delete_hints()
	_refresh_brush_preview()

func _sync_right_delete_hints() -> void:
	var deletion := "右键" if default_right_delete.button_pressed else "Alt＋右键"
	var navigation := "Alt＋右键" if default_right_delete.button_pressed else "右键"
	terrain_input_hint.text = "左键：贴面摆放，可沿起始平面拖动绘制\n%s：单次删除地块或物件，长按不连续删除\n%s：转动自由视角" % [deletion, navigation]
	free_view_button.tooltip_text = "WASD移动，滚轮缩放，%s拖动转向，中键平移" % navigation

## Native editor overlay: viewport-local, mouse-transparent, and never saved
## into the user's level scene.
func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	if free_view_active and is_instance_valid(builder) and data != null:
		var badge := overlay.get_node_or_null("TerrainEditModeBadge") as PanelContainer
		if badge == null:
			badge = PanelContainer.new()
			badge.name = "TerrainEditModeBadge"
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.position = ui_size(Vector2(12, 44))
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.06, 0.075, 0.09, 0.92)
			style.set_border_width_all(ui_px(1))
			style.set_corner_radius_all(ui_px(4))
			style.content_margin_left = ui_px(10)
			style.content_margin_right = ui_px(10)
			style.content_margin_top = ui_px(6)
			style.content_margin_bottom = ui_px(6)
			badge.add_theme_stylebox_override("panel", style)
			var label := Label.new()
			label.name = "State"
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_size_override("font_size", ui_px(14))
			badge.add_child(label)
			overlay.add_child(badge)
			_view_mode_badges.append(badge)
	_sync_view_mode_badges()

func _refresh_view_mode_badges() -> void:
	_sync_view_mode_badges()
	update_overlays()

func _sync_view_mode_badges() -> void:
	for index in range(_view_mode_badges.size() - 1, -1, -1):
		var badge := _view_mode_badges[index]
		if not is_instance_valid(badge):
			_view_mode_badges.remove_at(index)
			continue
		badge.visible = free_view_active and is_instance_valid(builder) and data != null
		var label := badge.get_node("State") as Label
		var navigating := _right_button_navigates(_alt_navigation)
		var color := NAVIGATION_MODE_COLOR if navigating else EDIT_MODE_COLOR
		label.text = "移动视角中" if navigating else "摆放/删除中"
		if label.get_theme_color("font_color") != color:
			label.add_theme_color_override("font_color", color)
		var style := badge.get_theme_stylebox("panel") as StyleBoxFlat
		if style.border_color != color:
			style.border_color = color

func _input(event: InputEvent) -> void:
	_update_alt_state(event)
	# A release can arrive outside the 3D viewport, after a popup or focus change.
	if event is InputEventKey and not event.pressed:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key in view_move_keys:
			view_move_keys[key] = false
	if event is InputEventMouseButton and not event.pressed:
		if encounter_tools and event.button_index == MOUSE_BUTTON_LEFT:
			encounter_tools.finish_stroke()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_erase_button_down = false
		if drawing and event.button_index == stroke_button:
			_finish_terrain_stroke()

# ============================================================
# Input forwarding
# ============================================================
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	editing_camera = camera
	if not is_instance_valid(builder) or data == null:
		builder = null
		data = null
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	_apply_fixed_view()
	_update_alt_state(event)
	if event is InputEventMouse:
		last_mouse = event.position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and not event.pressed:
		_erase_button_down = false
	if (fixed_view_active or free_view_active) and _handle_view_input(camera, event):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and _right_button_deletes(event.alt_pressed) and tabs.current_tab in [0, 1]:
		if event.pressed:
			if _erase_button_down or drawing:
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_erase_button_down = true
			# Objects are picked against terrain depth, including non-colliding art.
			var id: String = world_tools._pick_object(camera, event.position)
			if not id.is_empty():
				world_tools.delete_object(id)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if tabs.current_tab == 1:
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_erase_terrain_at(camera, event.position)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if free_view_active and _alt_navigation and event is InputEventMouse \
			and not (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	# Tabs 1+ (物件/导入/预制) handled by world_tools
	if encounter_tools and encounter_tools.active():
		return encounter_tools.handle(camera, event)
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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.alt_pressed:
		if event.pressed:
			if drawing:
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			stroke_erase = event.button_index == MOUSE_BUTTON_RIGHT
			if stroke_erase and mode_select.selected != ToolMode.GROUND:
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			_update_terrain_target(camera, event.position, stroke_erase)
			if hover_block == INVALID_BLOCK:
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			var cell := Vector2i(hover_block.x, hover_block.z)
			var can_expand: bool = mode_select.selected == ToolMode.GROUND and not stroke_erase
			if not data.in_bounds(cell) and not can_expand:
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			drawing = true
			stroke_button = event.button_index
			stroke_block = hover_block
			stroke_normal = hover_normal
			stroke_plane = Plane(Vector3(stroke_normal), hover_point)
			_begin_stroke()
			touched.clear()
			last_stroke_cell = Vector2i(-999, -999)
			if can_expand and not _ensure_ground_bounds(cell):
				drawing = false
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_paint(cell)
			if stroke_erase:
				# Erasure is committed on press, never continued on mouse motion.
				_finish_terrain_stroke()
			_refresh_brush_preview()
		else:
			if drawing and event.button_index == stroke_button:
				_finish_terrain_stroke()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion:
		_update_terrain_target(camera, event.position, stroke_erase if drawing else false)
		var cell := hover_cell
		_preview_pending = true
		if drawing and event.button_mask & MOUSE_BUTTON_MASK_LEFT and hover_block != INVALID_BLOCK:
			if mode_select.selected == ToolMode.GROUND and not stroke_erase \
					and not _ensure_ground_bounds(cell):
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_paint(cell)
		return EditorPlugin.AFTER_GUI_INPUT_STOP if drawing \
			or event.button_mask & MOUSE_BUTTON_MASK_RIGHT else EditorPlugin.AFTER_GUI_INPUT_PASS
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _erase_terrain_at(camera: Camera3D, mouse: Vector2) -> void:
	if mode_select.selected != ToolMode.GROUND:
		return
	stroke_erase = true
	_update_terrain_target(camera, mouse, true)
	if hover_block == INVALID_BLOCK:
		stroke_erase = false
		return
	drawing = true
	stroke_button = MOUSE_BUTTON_RIGHT
	_begin_stroke()
	touched.clear()
	_paint(hover_cell)
	_finish_terrain_stroke()
	_refresh_brush_preview()

func _handle_view_input(camera: Camera3D, event: InputEvent) -> bool:
	if event is InputEventKey:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key in view_move_keys:
			if not event.pressed:
				view_move_keys[key] = false
				return true
			if _text_input_focused() or event.ctrl_pressed or event.meta_pressed \
					or (event.alt_pressed and not free_view_active):
				return false
			view_move_keys[key] = true
			return true
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE \
				or (event.button_index == MOUSE_BUTTON_RIGHT and _right_button_navigates(event.alt_pressed)):
			return true
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			_zoom_editor_view(camera, pow(1.14, direction * maxf(event.factor, 0.1)))
			return true
	if event is InputEventMagnifyGesture:
		_zoom_editor_view(camera, 1.0 / maxf(event.factor, 0.01))
		return true
	if event is InputEventPanGesture:
		_zoom_editor_view(camera, exp(clampf(event.delta.y * 0.06, -1.0, 1.0)))
		return true
	if event is InputEventMouseMotion and (
			event.button_mask & MOUSE_BUTTON_MASK_MIDDLE \
			or (_right_button_navigates(event.alt_pressed) and event.button_mask & MOUSE_BUTTON_MASK_RIGHT)):
		if free_view_active:
			_drag_free_view(camera, event)
		return true
	return false

func _fixed_view_pressed() -> void:
	if fixed_view_active and view_mode == ViewMode.PERSPECTIVE_2_5D:
		_free_view_pressed()
	else:
		_enable_2_5d_view()

func _top_view_pressed() -> void:
	if fixed_view_active and view_mode == ViewMode.TOP:
		_free_view_pressed()
	else:
		_enable_fixed_view(ViewMode.TOP)

func _free_view_pressed() -> void:
	if not is_instance_valid(builder) or not builder.is_inside_tree():
		return
	if free_view_active:
		_sync_view_buttons()
		return
	if not fixed_view_active:
		_capture_view_cameras()
	if fixed_view_cameras.is_empty():
		return
	_apply_fixed_view()
	free_view_states.clear()
	for camera in fixed_view_cameras:
		if is_instance_valid(camera) and camera.is_inside_tree():
			free_view_states[camera.get_instance_id()] = {
				"transform": camera.global_transform, "projection": camera.projection,
				"fov": camera.fov, "size": camera.size,
			}
	fixed_view_active = false
	free_view_active = true
	view_mode = ViewMode.FREE
	_clear_view_input()
	_sync_view_buttons()
	_apply_fixed_view()
	_set_status("自由视角：WASD移动，滚轮/触控板缩放，%s拖动转向" % (
		"Alt＋右键" if default_right_delete.button_pressed else "右键"))

func _enable_2_5d_view() -> void:
	_enable_fixed_view(ViewMode.PERSPECTIVE_2_5D)

func _enable_fixed_view(mode: ViewMode) -> void:
	if not is_instance_valid(builder) or not builder.is_inside_tree():
		return
	if not fixed_view_active and not free_view_active:
		_capture_view_cameras()
	if fixed_view_cameras.is_empty():
		_set_status("没有可用的3D编辑视口")
		return
	EditorInterface.set_main_screen_editor("3D")
	fixed_view_active = true
	free_view_active = false
	free_view_states.clear()
	view_mode = mode
	_sync_view_buttons()
	_clear_view_input()
	_apply_fixed_view()
	_set_status(
		"俯视视角已固定；WASD平移，滚轮缩放"
		if mode == ViewMode.TOP
		else "2.5D视角已固定；WASD平移，滚轮缩放")

func _capture_view_cameras() -> void:
	var previous_camera := editing_camera
	fixed_view_cameras.clear()
	fixed_view_states.clear()
	for index in 4:
		var viewport := EditorInterface.get_editor_viewport_3d(index)
		if viewport != null and is_instance_valid(viewport.get_camera_3d()):
			var camera := viewport.get_camera_3d()
			if camera.is_inside_tree() and camera not in fixed_view_cameras:
				fixed_view_cameras.append(camera)
	if is_instance_valid(previous_camera) and previous_camera.is_inside_tree() \
			and previous_camera not in fixed_view_cameras:
		fixed_view_cameras.append(previous_camera)
	if fixed_view_cameras.is_empty():
		return
	editing_camera = previous_camera if previous_camera in fixed_view_cameras else fixed_view_cameras[0]
	for camera in fixed_view_cameras:
		fixed_view_states[camera.get_instance_id()] = {
			"camera": camera, "transform": camera.global_transform,
			"projection": camera.projection, "fov": camera.fov, "size": camera.size,
		}
	view_pan_offset = Vector3.ZERO

func _disable_2_5d_view() -> void:
	if fixed_view_active or free_view_active:
		for state: Dictionary in fixed_view_states.values():
			var camera: Camera3D = state["camera"]
			if not is_instance_valid(camera) or not camera.is_inside_tree():
				continue
			camera.global_transform = state["transform"]
			camera.projection = state["projection"]
			camera.fov = state["fov"]
			camera.size = state["size"]
	fixed_view_active = false
	free_view_active = false
	free_view_states.clear()
	view_mode = ViewMode.FREE
	fixed_view_cameras.clear()
	fixed_view_states.clear()
	_clear_view_input()
	_sync_view_buttons()

func _sync_view_buttons() -> void:
	if is_instance_valid(fixed_view_button):
		fixed_view_button.set_pressed_no_signal(
			view_mode == ViewMode.PERSPECTIVE_2_5D)
	if is_instance_valid(top_view_button):
		top_view_button.set_pressed_no_signal(view_mode == ViewMode.TOP)
	if is_instance_valid(free_view_button):
		free_view_button.set_pressed_no_signal(view_mode == ViewMode.FREE)
	_refresh_view_mode_badges()

func _process(delta: float) -> void:
	if is_instance_valid(builder) and builder.is_inside_tree():
		var stream_camera := editing_camera
		if not is_instance_valid(stream_camera):
			var viewport := EditorInterface.get_editor_viewport_3d(0)
			if viewport != null:
				stream_camera = viewport.get_camera_3d()
		if is_instance_valid(stream_camera):
			builder.follow_stream_camera(stream_camera)
	if transition_tools and (transition_tools.observed_data != data \
			or data != null and transition_tools.observed_config != data.level_transition):
		transition_tools.sync()
	if encounter_tools and (encounter_tools.observed_data != data \
			or data != null and encounter_tools.observed_config != data.encounter):
		encounter_tools.sync()
	if _preview_pending:
		_preview_pending = false
		if is_instance_valid(tabs) and tabs.current_tab == 0:
			_update_preview(hover_cell)
	if not (fixed_view_active or free_view_active) \
			or not is_instance_valid(builder) or not builder.is_inside_tree():
		return
	if _text_input_focused():
		_clear_view_input()
	var camera := editing_camera
	if not is_instance_valid(camera) and not fixed_view_cameras.is_empty():
		camera = fixed_view_cameras[0]
	if is_instance_valid(camera) and camera.is_inside_tree():
		if free_view_active:
			_move_free_view(camera, delta)
			_apply_fixed_view()
			return
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
	if not (fixed_view_active or free_view_active) \
			or not is_instance_valid(builder) or not builder.is_inside_tree():
		return
	var profile := load("res://data/art_profile.tres") as ArtProfile
	for camera in fixed_view_cameras:
		if is_instance_valid(camera) and camera.is_inside_tree():
			if free_view_active:
				var state: Dictionary = free_view_states.get(camera.get_instance_id(), {})
				if not state.is_empty():
					camera.global_transform = state["transform"]
					camera.projection = state["projection"]
					camera.fov = state["fov"]
					camera.size = state["size"]
			elif view_mode == ViewMode.TOP:
				_configure_top_camera(camera, profile)
			else:
				_configure_view_camera(camera, profile)

func _move_free_view(camera: Camera3D, delta: float) -> void:
	var state: Dictionary = free_view_states.get(camera.get_instance_id(), {})
	if state.is_empty():
		return
	var motion := Vector2(
		float(view_move_keys[KEY_D]) - float(view_move_keys[KEY_A]),
		float(view_move_keys[KEY_W]) - float(view_move_keys[KEY_S]))
	if motion == Vector2.ZERO:
		return
	var pose: Transform3D = state["transform"]
	# Moving into an orthographic view does not visibly move the scene.
	var forward := pose.basis.y if state["projection"] == Camera3D.PROJECTION_ORTHOGONAL \
		else -pose.basis.z
	pose.origin += (pose.basis.x * motion.x + forward * motion.y).normalized() \
		* maxf(_effective_distance() * 0.45, 4.0) * delta
	state["transform"] = pose

func _zoom_editor_view(camera: Camera3D, factor: float) -> void:
	if not free_view_active:
		_zoom_fixed_view(factor)
		return
	var state: Dictionary = free_view_states.get(camera.get_instance_id(), {})
	if state.is_empty():
		return
	if state["projection"] == Camera3D.PROJECTION_ORTHOGONAL:
		state["size"] = clampf(float(state["size"]) * factor, 2.0, 240.0)
	else:
		var pose: Transform3D = state["transform"]
		pose.origin += pose.basis.z * (factor - 1.0) * maxf(_effective_distance(), 4.0)
		state["transform"] = pose
	_apply_fixed_view()

func _drag_free_view(camera: Camera3D, event: InputEventMouseMotion) -> void:
	var state: Dictionary = free_view_states.get(camera.get_instance_id(), {})
	if state.is_empty():
		return
	var pose: Transform3D = state["transform"]
	if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		pose.origin += (-pose.basis.x * event.relative.x + pose.basis.y * event.relative.y) \
			* maxf(_effective_distance(), 4.0) * 0.0015
	else:
		pose.basis = Basis(Vector3.UP, -event.relative.x * 0.004) * pose.basis
		var pitch := asin(clampf(-pose.basis.z.y, -1.0, 1.0))
		var next_pitch := clampf(pitch - event.relative.y * 0.004, -PI * 0.495, PI * 0.495)
		pose.basis = (pose.basis * Basis(Vector3.RIGHT, next_pitch - pitch)).orthonormalized()
	state["transform"] = pose
	_apply_fixed_view()

func _zoom_fixed_view(factor: float) -> void:
	if view_mode == ViewMode.TOP:
		top_view_size = clampf(top_view_size * factor, 6.0, 120.0)
		_apply_fixed_view()
		return
	var profile := load("res://data/art_profile.tres") as ArtProfile
	if preview_distance < 0:
		preview_distance = profile.camera_distance
	preview_distance = clampf(preview_distance * factor, 8.0, 120.0)
	if view_settings != null:
		view_settings.set_distance_from_viewport(preview_distance)
	_apply_fixed_view()

func _effective_distance() -> float:
	if view_mode == ViewMode.TOP:
		return top_view_size
	return preview_distance if preview_distance >= 0 else (
		load("res://data/art_profile.tres") as ArtProfile).camera_distance

func apply_view_parameters(fov: float, pitch: float, distance: float, target_height: float) -> void:
	preview_fov = fov
	preview_pitch = pitch
	preview_distance = distance
	preview_target_height = target_height
	if not fixed_view_active or view_mode != ViewMode.PERSPECTIVE_2_5D:
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

func _configure_top_camera(camera: Camera3D, profile: ArtProfile) -> void:
	var target_height := profile.target_height if is_inf(preview_target_height) \
		else preview_target_height
	var center := builder.global_position + view_pan_offset \
		+ Vector3.UP * target_height
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = top_view_size
	camera.global_transform = Transform3D(
		Basis.looking_at(Vector3.DOWN, Vector3(0.0, 0.0, -1.0)),
		center + Vector3.UP * maxf(top_view_size, 20.0))

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
		_refresh_brush_preview()
		_set_dirty(true)
		if encounter_tools:
			encounter_tools.sync()

func _commit_objects(before: Array[Dictionary], after: Array[Dictionary], label: String) -> void:
	if data == null or before == after:
		return
	var target := data
	var undo_redo := get_undo_redo()
	undo_redo.create_action(label, UndoRedo.MERGE_DISABLE, target)
	undo_redo.add_do_method(self, "_apply_objects", target, after.duplicate(true))
	undo_redo.add_undo_method(self, "_apply_objects", target, before.duplicate(true))
	undo_redo.commit_action(false)
	if is_instance_valid(builder):
		builder.refresh_objects()
	_set_dirty(true)

func _apply_objects(target: LevelData, records: Array[Dictionary]) -> void:
	target.objects = records.duplicate(true)
	target.emit_changed()
	if target == data and is_instance_valid(builder):
		builder.refresh_objects()
		_set_dirty(true)

func _commit_details(target: LevelData, before: Array[Dictionary],
		after: Array[Dictionary], label: String) -> void:
	if before == after:
		return
	var undo_redo := get_undo_redo()
	undo_redo.create_action(label, UndoRedo.MERGE_DISABLE, target)
	undo_redo.add_do_method(self, "_apply_details", target, after.duplicate(true))
	undo_redo.add_undo_method(self, "_apply_details", target, before.duplicate(true))
	undo_redo.commit_action(false)
	if target == data:
		_set_dirty(true)

func _apply_details(target: LevelData, values: Array[Dictionary]) -> void:
	target.details = values.duplicate(true)
	target.emit_changed()
	if target == data and is_instance_valid(builder):
		builder.rebuild_details()
		_set_dirty(true)

func _begin_stroke() -> void:
	stroke_cells_before.clear()
	stroke_aux_before = _terrain_aux_snapshot(data)
	stroke_bounds_before = data.map_bounds()
	pending_bounds_before = Rect2i()

func _record_stroke_changes(changes: Array[Dictionary]) -> void:
	for change in changes:
		var cell: Vector2i = change["cell"]
		if not stroke_cells_before.has(cell):
			stroke_cells_before[cell] = change["before"].duplicate(true)

func _commit_stroke(label: String) -> void:
	if data == null or not is_instance_valid(builder):
		return
	var after_cells := {}
	for cell: Vector2i in stroke_cells_before:
		after_cells[cell] = data.column_snapshot(cell)
	var after_aux := _terrain_aux_snapshot(data)
	if stroke_cells_before.is_empty() and stroke_aux_before == after_aux \
			and stroke_bounds_before == data.map_bounds():
		return
	var target := data
	var undo_redo := get_undo_redo()
	undo_redo.create_action(label, UndoRedo.MERGE_DISABLE, target)
	undo_redo.add_do_method(
		self, "_apply_terrain_delta", target,
		after_cells.duplicate(true), after_aux.duplicate(true), data.map_bounds())
	undo_redo.add_undo_method(
		self, "_apply_terrain_delta", target,
		stroke_cells_before.duplicate(true), stroke_aux_before.duplicate(true), stroke_bounds_before)
	undo_redo.commit_action(false)
	_set_dirty(true)

func _terrain_aux_snapshot(target: LevelData) -> Dictionary:
	return {
		"stairs": target.stairs.duplicate(true),
		"spawn_cell": target.spawn_cell,
		"spawn_layer": target.spawn_layer,
		"objects": target.objects.duplicate(true),
		"details": target.details.duplicate(true),
		"monster_spawn_points": target.monster_spawn_points.duplicate(true),
	}

func _ground_brush_region(cell: Vector2i) -> Rect2i:
	var result := Rect2i(cell, Vector2i.ONE)
	for block in _brush_blocks(Vector3i(cell.x, active_layer, cell.y)):
		result = result.merge(Rect2i(Vector2i(block.x, block.z), Vector2i.ONE))
	return result

func _brush_blocks(center: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var size := 3 if brush_select.selected == 1 else 1
	var normal := stroke_normal if drawing else hover_normal
	var u := Vector3i.RIGHT if normal.x == 0 else Vector3i(0, 0, 1)
	var v := Vector3i(0, 0, 1) if normal.y != 0 else Vector3i.UP
	for y in size:
		for x in size:
			var block := center + u * (x - size / 2) + v * (y - size / 2)
			if block.y >= 0 and block.y < LevelData.MAX_LAYERS \
					and (builder.slice_layer_limit < 0 or block.y <= builder.slice_layer_limit):
				result.append(block)
	return result

func _blocks_for_cells(cells: Array[Vector2i]) -> Array[Vector3i]:
	var blocks: Array[Vector3i] = []
	for cell in cells:
		blocks.append(Vector3i(cell.x, active_layer, cell.y))
	return blocks

func _ensure_ground_bounds(cell: Vector2i) -> bool:
	if mode_select.selected != ToolMode.GROUND:
		return data.in_bounds(cell)
	var region := _ground_brush_region(cell)
	if data.contains_region(region):
		pending_bounds_before = Rect2i()
		return true
	pending_bounds_before = data.map_bounds()
	var error := data.expand_to_include(region)
	if not error.is_empty():
		pending_bounds_before = Rect2i()
		_set_status(error)
		return false
	return true

func _apply_terrain_delta(target: LevelData, cell_values: Dictionary,
		aux: Dictionary, bounds := Rect2i()) -> void:
	if bounds.has_area():
		target.resize_bounds(bounds)
	target.set_columns(cell_values)
	target.stairs.assign(aux["stairs"].duplicate(true))
	target.spawn_cell = aux["spawn_cell"]
	target.spawn_layer = int(aux.get("spawn_layer", -1))
	target.objects.assign(aux["objects"].duplicate(true))
	target.details.assign(aux.get("details", []).duplicate(true))
	target.monster_spawn_points.assign(aux.get("monster_spawn_points", []).duplicate(true))
	target.emit_changed()
	if target == data:
		if is_instance_valid(builder):
			var changed: Array[Vector2i] = []
			changed.assign(cell_values.keys())
			builder.rebuild_cells(changed)
		_refresh_brush_preview()
		if encounter_tools:
			encounter_tools.sync()
		_set_dirty(true)

func _mode_name() -> String:
	if stroke_erase:
		return "擦除地块"
	return {ToolMode.GROUND: "摆放地块", ToolMode.ERASE: "擦除地块",
		ToolMode.STAIR: "放置阶梯", ToolMode.SPAWN: "设置出生点"}.get(mode_select.selected, "编辑地图")

# ============================================================
# Terrain painting
# ============================================================
func _paint(cell: Vector2i) -> void:
	if data == null or not is_instance_valid(builder):
		return
	if not data.in_bounds(cell):
		return
	last_stroke_cell = cell
	var mode: int = mode_select.selected
	if mode == ToolMode.STAIR:
		_try_stair(cell)
		return
	if mode == ToolMode.SPAWN:
		if not data.is_surface_exposed(cell, active_layer):
			return
		data.spawn_cell = cell
		data.spawn_layer = active_layer
		builder.rebuild()
		return
	var erasing := mode == ToolMode.ERASE or (drawing and stroke_erase)
	var center := Vector3i(cell.x, active_layer, cell.y)
	var brush: Array[Vector3i] = []
	if erasing:
		brush.append(center)
	else:
		brush = _brush_blocks(center)
	var targets: Array[Vector3i] = []
	for block in brush:
		if data.in_bounds(Vector2i(block.x, block.z)) and not touched.has(block):
			targets.append(block)
	var changes: Array[Dictionary] = []
	if erasing:
		changes = _erase_blocks(targets)
	elif mode == ToolMode.GROUND:
		changes = _paint_ground_blocks(targets)
	if changes.is_empty():
		if pending_bounds_before.has_area():
			data.resize_bounds(pending_bounds_before)
			pending_bounds_before = Rect2i()
		return
	pending_bounds_before = Rect2i()
	_record_stroke_changes(changes)
	_preview_key = ""
	var dirty_cells: Array[Vector2i] = []
	for change in changes:
		dirty_cells.append(change["cell"])
	if mode == ToolMode.GROUND and not erasing and _can_refresh_blend(changes):
		if builder.refresh_blend_cells(dirty_cells):
			return
	builder.rebuild_cells(dirty_cells)

func _paint_single(cell: Vector2i, mode: int) -> void:
	if not data.in_bounds(cell) or touched.has(Vector3i(cell.x, active_layer, cell.y)):
		return
	var targets: Array[Vector2i] = [cell]
	if mode == ToolMode.GROUND:
		_paint_ground_cells(targets)
		return
	if mode != ToolMode.ERASE:
		return
	_erase_cells(targets)

func _erase_cells(targets: Array[Vector2i]) -> Array[Dictionary]:
	return _erase_blocks(_blocks_for_cells(targets))

func _erase_blocks(targets: Array[Vector3i]) -> Array[Dictionary]:
	var candidate := data.fork_for_edit()
	var changed := {}
	for block in targets:
		var cell := Vector2i(block.x, block.z)
		var layer := block.y
		if not data.in_bounds(cell) or touched.has(block):
			continue
		touched[block] = true
		if not candidate.layer_exists(cell, layer):
			continue
		if erase_select.selected > 0:
			if erase_select.selected == 3:
				var stair := candidate.stair_at(cell, layer)
				if stair < 0:
					continue
				candidate.stairs.remove_at(stair)
			else:
				candidate.clear_attachment(cell,
					"liquid" if erase_select.selected == 1 else "overlay", layer)
			changed[cell] = true
			continue
		# Remove only records depending on this exact support, never another height.
		ObjectRules.remove_terrain_support(candidate, cell, layer)
		var stair_idx := candidate.stair_at(cell, layer)
		if stair_idx >= 0:
			candidate.stairs.remove_at(stair_idx)
		if candidate.spawn_cell == cell and candidate.spawn_layer == layer:
			candidate.spawn_cell = Vector2i(-1, -1)
			candidate.spawn_layer = -1
		candidate.remove_layer(cell, layer)
		changed[cell] = true
	var changes := _column_changes(candidate, changed)
	if not changes.is_empty():
		DetailRules.prune_invalid(candidate)
		MonsterSpawnPoints.prune(candidate)
		_apply_candidate_columns(candidate, changes)
	return changes

func _paint_ground_cells(targets: Array[Vector2i]) -> Array[Dictionary]:
	return _paint_ground_blocks(_blocks_for_cells(targets))

func _paint_ground_blocks(targets: Array[Vector3i]) -> Array[Dictionary]:
	var pending: Array[Vector3i] = []
	for block in targets:
		if not data.in_bounds(Vector2i(block.x, block.z)) or touched.has(block):
			continue
		pending.append(block)
	if pending.is_empty():
		return []
	var result := _prepare_ground_blocks(pending)
	if not result["error"].is_empty():
		_set_status(result["error"])
		return []
	var candidate: LevelData = result["candidate"]
	var changes: Array[Dictionary] = result["changes"]
	for block in pending:
		touched[block] = true
	_apply_candidate_columns(candidate, changes)
	return changes

func _prepare_ground(pending: Array[Vector2i]) -> Dictionary:
	return _prepare_ground_blocks(_blocks_for_cells(pending))

func _prepare_ground_blocks(pending: Array[Vector3i]) -> Dictionary:
	var tile := selected_tile()
	var tile_id := tile.tile_id if tile else "grass"
	var candidate := data.fork_for_edit()
	var region := Rect2i()
	for block in pending:
		var cell := Vector2i(block.x, block.z)
		var point := Rect2i(cell, Vector2i.ONE)
		region = point if region.size == Vector2i.ZERO else region.merge(point)
	var expansion := candidate.expand_to_include(region)
	if not expansion.is_empty():
		return {"error": expansion}
	var changed := {}
	for block in pending:
		var cell := Vector2i(block.x, block.z)
		var layer := block.y
		if candidate.stair_at(cell, layer) >= 0:
			return {"error": "请先移除阶梯，再替换其地块"}
		# Occupied brush cells remain intact while a stroke extends the empty plane.
		if (tile == null or tile.is_block()) and candidate.layer_exists(cell, layer):
			continue
		var error := candidate.set_layer(cell, layer, {
			"tile_id": tile_id,
			"rotation": tile_turns,
		}, tile_id)
		if not error.is_empty():
			return {"error": error}
		changed[cell] = true
	DetailRules.prune_invalid(candidate)
	# Terrain changes cannot change image formats or atlas bounds. Validate
	# support/collision dependencies here; full validation still runs on play.
	var errors := candidate.validate_content(false)
	if errors.has("缺少有效的玩家出生点"):
		errors.remove_at(errors.find("缺少有效的玩家出生点"))
	if not errors.is_empty():
		return {"error": "无法绘制：" + "\n".join(errors)}
	return {"error": "", "candidate": candidate, "changes": _column_changes(candidate, changed)}

func _column_changes(candidate: LevelData, changed: Dictionary) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	for cell: Vector2i in changed:
		var before := data.column_snapshot(cell)
		var after := candidate.column_snapshot(cell)
		if before == after and candidate.stairs == data.stairs:
			continue
		changes.append({"cell": cell, "before": before, "after": after,
			"before_surface": data.get_cell(cell), "after_surface": candidate.get_cell(cell)})
	return changes

func _apply_candidate_columns(candidate: LevelData, changes: Array[Dictionary]) -> void:
	if changes.is_empty():
		return
	var values := {}
	for change in changes:
		values[change["cell"]] = change["after"]
	data.set_columns(values)
	data.objects = candidate.objects
	data.details = candidate.details
	data.stairs = candidate.stairs
	data.spawn_cell = candidate.spawn_cell
	data.spawn_layer = candidate.spawn_layer
	data.monster_spawn_points = candidate.monster_spawn_points
	data.emit_changed()

func _move_top_anchors(candidate: LevelData, cell: Vector2i,
		old_top: int, new_top: int) -> void:
	ObjectRules.move_top_anchors(candidate, cell, old_top, new_top)

func _ground_candidate(cell: Vector2i) -> Dictionary:
	if not data.in_bounds(cell):
		return {"error": "地块超出地图"}
	if data.stair_at(cell, active_layer) >= 0:
		return {"error": "请先移除阶梯，再替换其地块"}
	var targets: Array[Vector2i] = [cell]
	return _prepare_ground(targets)

func _can_refresh_blend(changes: Array[Dictionary]) -> bool:
	for change in changes:
		if active_layer != data.top_layer(change["cell"]):
			return false
		var old_layers: Array = change["before"].get("layers", [])
		var new_layers: Array = change["after"].get("layers", [])
		if old_layers.size() != new_layers.size() or active_layer >= old_layers.size() \
				or old_layers[active_layer].get("overlay", {}) != new_layers[active_layer].get("overlay", {}):
			return false
		var before: Dictionary = change["before_surface"]
		var after: Dictionary = change["after_surface"]
		if not bool(before.get("exists", false)) or not bool(after.get("exists", false)):
			return false
		if int(before.get("height", 0)) != int(after.get("height", 0)):
			return false
		var old_tile := TileRegistry.find(str(before.get("tile_id", "grass")))
		var new_tile := TileRegistry.find(str(after.get("tile_id", "grass")))
		if old_tile == null or new_tile == null \
				or not old_tile.is_solid() or not new_tile.is_solid() \
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
	var error := data.can_place_stair(cell, stair_direction, active_layer)
	if not error.is_empty():
		_set_status(error)
		return
	data.stairs.append({
		"cell": cell,
		"direction": stair_direction,
		"layer": active_layer,
	})
	builder.rebuild()

func _pick(camera: Camera3D, mouse: Vector2) -> Vector2i:
	picked_layer = -1
	var inverse := builder.global_transform.affine_inverse()
	var origin := inverse * camera.project_ray_origin(mouse)
	var ray := inverse.basis * camera.project_ray_normal(mouse)
	var hit := BlockPicker.raycast(data, origin, ray, builder.slice_layer_limit)
	if not hit.is_empty():
		picked_layer = int(hit["layer"])
		return hit["cell"]
	if absf(ray.y) > 0.00001:
		var distance := -origin.y / ray.y
		if distance >= 0:
			return data.world_to_cell(origin + ray * distance)
	return Vector2i(-999, -999)

func _update_terrain_target(camera: Camera3D, mouse: Vector2, erase: bool) -> void:
	hover_block = INVALID_BLOCK
	hover_cell = Vector2i(-999, -999)
	var inverse := builder.global_transform.affine_inverse()
	var origin := inverse * camera.project_ray_origin(mouse)
	var ray := (inverse.basis * camera.project_ray_normal(mouse)).normalized()
	if drawing:
		var point: Variant = stroke_plane.intersects_ray(origin, ray)
		if point == null:
			return
		hover_block = data.world_to_block(point)
		var axis := Vector3(stroke_normal).abs().max_axis_index()
		hover_block[axis] = stroke_block[axis]
		hover_normal = stroke_normal
		hover_point = point
	else:
		var tile := selected_tile()
		var solid := tile == null or tile.is_block()
		var hit := BlockPicker.raycast(data, origin, ray, builder.slice_layer_limit)
		if not hit.is_empty():
			hover_block = hit["block"]
			picked_layer = int(hit["layer"])
			hover_normal = hit["normal"]
			hover_point = hit["position"]
			if not erase:
				if mode_select.selected == ToolMode.GROUND and solid:
					hover_block += hover_normal
				elif hover_normal != Vector3i.UP:
					hover_block = INVALID_BLOCK
		elif not erase and solid and mode_select.selected == ToolMode.GROUND \
				and absf(ray.y) > 0.00001 and -origin.y / ray.y >= 0:
			hover_point = origin + ray * (-origin.y / ray.y)
			hover_block = data.world_to_block(hover_point)
			hover_block.y = 0
			hover_normal = Vector3i.UP
	if hover_block.y < 0 or hover_block.y >= LevelData.MAX_LAYERS \
			or (builder.slice_layer_limit >= 0 and hover_block.y > builder.slice_layer_limit):
		hover_block = INVALID_BLOCK
	if hover_block == INVALID_BLOCK:
		return
	active_layer = hover_block.y
	hover_cell = Vector2i(hover_block.x, hover_block.z)

func _update_preview(cell: Vector2i) -> void:
	hover_cell = cell
	if data == null or not is_instance_valid(builder) or not is_instance_valid(preview):
		return
	if free_view_active and _alt_navigation and default_right_delete.button_pressed:
		preview.hide()
		return
	var selected := selected_tile()
	if cell == Vector2i(-999, -999):
		preview.visible = false
		_set_status(terrain_input_hint.text)
		return
	var erasing: bool = (drawing and stroke_erase) or mode_select.selected == ToolMode.ERASE
	var key := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		data.get_instance_id(), cell, mode_select.selected, active_layer,
		slice_select.selected, tile_turns, stair_direction, brush_select.selected,
		selected.tile_id if selected else "", erase_select.selected,
		hover_normal, erasing]
	if key == _preview_key and preview.visible:
		return
	_preview_key = key
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
	if mode == ToolMode.GROUND and not erasing:
		preview.visible = true
		preview.mesh = null
		preview.position = Vector3.ZERO
		var expansion_error := data.expansion_error(_ground_brush_region(cell))
		var error_text := expansion_error
		var valid := expansion_error.is_empty()
		var fragment := LevelData.new()
		var region := _ground_brush_region(cell)
		fragment.setup_blank(region.size)
		fragment.terrain_tints = data.terrain_tints.duplicate(true)
		var tile := selected_tile()
		var id := tile.tile_id if tile else "grass"
		var targets := _brush_blocks(Vector3i(cell.x, active_layer, cell.y))
		var check := _prepare_ground_blocks(targets)
		if not check["error"].is_empty():
			valid = false
			error_text = check["error"]
		if valid and check["changes"].is_empty() and not drawing:
			valid = false
			error_text = "该位置已有地块；右键可擦除"
		for block in targets:
			var local := Vector2i(block.x, block.z) - region.position
			var support_id := id if tile == null or tile.is_block() else "grass"
			if valid and tile != null and not tile.is_block():
				support_id = (check["candidate"] as LevelData).solid_tile_id(
					Vector2i(block.x, block.z), block.y)
			fragment.set_layer(local, block.y, {"tile_id": support_id, "rotation": tile_turns})
			if tile != null and not tile.is_block():
				fragment.set_layer(local, block.y, {"tile_id": id, "rotation": tile_turns})
		var display := TerrainBuilder.new()
		display.level_data = fragment
		display.show_grid = false
		display.build_collision = false
		display.slice_layer_limit = builder.slice_layer_limit
		display.position = data.world_center(region.position, active_layer) \
			- fragment.world_center(Vector2i.ZERO, active_layer) \
			+ Vector3(0, 0.035, 0)
		preview.add_child(display)
		# Same builder/materials as the final terrain, plus a translucent overlay.
		for node in display.generated.get_children():
			if node is MeshInstance3D:
				var overlay := StandardMaterial3D.new()
				overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				overlay.albedo_color = Color(0.3, 1, 0.5, 0.08) if valid else Color(1, 0.1, 0.1, 0.55)
				node.material_overlay = overlay
		_set_status("地块预览：顶面 %dm / %d°；左键摆放，%s单次删除" % [
			roundi(data.surface_y(active_layer)), tile_turns * 90,
			"右键" if default_right_delete.button_pressed else "Alt＋右键"]
			if valid else "红色区域不可绘制：" + error_text)
		return
	if mode == ToolMode.STAIR:
		var low := cell
		var high: Vector2i = cell + LevelData.DIRS[stair_direction]
		var valid := data.can_place_stair(low, stair_direction, active_layer).is_empty()
		preview.visible = true
		preview.mesh = null
		preview.position = Vector3.ZERO
		var fragment := LevelData.new()
		fragment.setup_blank(Vector2i(3, 3))
		var local_low := Vector2i(1, 1)
		var local_high: Vector2i = local_low + LevelData.DIRS[stair_direction]
		var low_height := active_layer
		var low_tile := data.solid_tile_id(low, low_height)
		var high_tile := data.solid_tile_id(high, low_height + 1)
		fragment.set_layer(local_low, low_height, {
			"tile_id": low_tile,
			"rotation": 0,
		})
		fragment.set_layer(local_high, low_height + 1, {
			"tile_id": high_tile,
			"rotation": 0,
		})
		fragment.stairs.append({
			"cell": local_low,
			"direction": stair_direction,
			"layer": low_height,
		})
		var display := TerrainBuilder.new()
		display.level_data = fragment
		display.show_grid = false
		display.build_collision = false
		display.position = data.world_center(low, 0) \
			- fragment.world_center(local_low, 0) + Vector3(0, 0.035, 0)
		preview.add_child(display)
		for node in display.find_children("*", "MeshInstance3D", true, false):
			var overlay := StandardMaterial3D.new()
			overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			overlay.albedo_color = Color(0.25, 1.0, 0.55, 0.18) \
				if valid else Color(1.0, 0.12, 0.12, 0.5)
			(node as MeshInstance3D).material_overlay = overlay
		_set_status("楼梯预览：从当前格升向 %d°" % (stair_direction * 90)
			if valid else "红色楼梯不可放置：" + data.can_place_stair(
				low, stair_direction, active_layer))
		return
	preview.visible = true
	preview.position = Vector3.ZERO
	preview.mesh = null
	var mesh := BoxMesh.new()
	mesh.size = Vector3(LevelData.CELL_SIZE, LevelData.ELEVATION_STEP, LevelData.CELL_SIZE) * 1.015 \
		if erasing else Vector3(LevelData.CELL_SIZE, 0.12, LevelData.CELL_SIZE)
	var mat := preview.material_override as StandardMaterial3D
	mat.albedo_color = Color(1, 0.25, 0.15, 0.3) if erasing else Color(1, 1, 0.3, 0.45)
	for block in _brush_blocks(Vector3i(cell.x, active_layer, cell.y)):
		var marker := MeshInstance3D.new()
		marker.mesh = mesh
		marker.material_override = mat
		marker.position = data.world_layer_center(Vector2i(block.x, block.z), block.y) if erasing \
			else data.world_center(cell, active_layer) + Vector3.UP * 0.08
		preview.add_child(marker)
		if not erasing:
			break

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
