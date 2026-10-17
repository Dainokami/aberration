@tool
extends VBoxContainer

const Picker := preload("res://addons/terrain_editor/surface_picker.gd")
var host: EditorPlugin
var mode
var sets: OptionButton
var paths: Array[String] = []
var search: LineEdit
var palette: ItemList
var visible_variants: Array[int] = []
var radius: SpinBox
var density: SpinBox
var size_input: SpinBox
var seed_input: SpinBox
var random_seed_button: Button
var reload_button: Button
var apply_hint: Label
var scatter_source
var selection_controls: VBoxContainer
var selection_panel: PanelContainer
var info_caption: Label
var info: Label
var advanced: Button
var parameters: VBoxContainer
var scatter_controls: Array[Control] = []
var radius_controls: Array[Control] = []
var seed_controls: Array[Control] = []
var ghost: DetailRenderer
var ring: MeshInstance3D
var drawing := false
var stroke_data: LevelData
var before: Array[Dictionary] = []
var stroke_id := ""
var sample_index := 0
var last_point := Vector3(INF, INF, INF)

func setup(plugin: EditorPlugin) -> void:
	host = plugin
	name = "DetailTools"
	add_theme_constant_override("separation", 8)
	mode = load("res://addons/terrain_editor/mode_bar.gd").new()
	mode.add_mode("单件", 0)
	mode.add_mode("散布", 1)
	mode.add_mode("擦除", 2)
	add_child(mode)
	mode.item_selected.connect(_mode_changed)
	_label("草屑、碎石与贴地纹理\n左键编辑真实顶面，一笔操作可整体撤销。")
	sets = OptionButton.new()
	sets.name = "DetailSet"
	sets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sets.clip_text = true
	add_child(sets)
	host._limit_layer_popup(sets)
	sets.item_selected.connect(func(_index: int): refresh_palette())
	search = LineEdit.new()
	search.placeholder_text = "搜索细节名称"
	search.text_changed.connect(func(_text: String): refresh_palette())
	add_child(search)
	reload_button = Button.new()
	reload_button.name = "ReloadDetailLibrary"
	reload_button.text = "重新加载素材"
	reload_button.tooltip_text = "仅在导入新的细节素材后使用；画笔设置无需重新加载。"
	reload_button.pressed.connect(refresh_library)
	add_child(reload_button)
	var radius_label := _label("笔刷半径 · 米")
	radius = _spin(0.25, 6, 0.25, 1.5)
	radius.tooltip_text = "圆圈表示素材中心的散布范围，不会裁切素材图片。"
	radius_controls = [radius_label, radius]
	var density_label := _label("每次散布数量")
	density = _spin(1, 60, 1, 12)
	var source_label := _label("散布内容")
	scatter_source = load("res://addons/terrain_editor/mode_bar.gd").new()
	scatter_source.name = "ScatterSource"
	scatter_source.add_mode("混合全部", 0)
	scatter_source.add_mode("单一散布", 1)
	scatter_source.selected = 1
	scatter_source.add_theme_constant_override("separation", host.ui_px(6))
	for button: Button in scatter_source.buttons.values():
		_style_scatter_choice(button)
	add_child(scatter_source)
	scatter_source.item_selected.connect(_scatter_source_changed)
	scatter_controls = [density_label, density, source_label, scatter_source]
	advanced = Button.new()
	advanced.name = "DetailMoreSettings"
	advanced.text = "▸ 更多设置"
	advanced.toggle_mode = true
	advanced.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(advanced)
	parameters = VBoxContainer.new()
	parameters.name = "DetailParameters"
	parameters.add_theme_constant_override("separation", 6)
	add_child(parameters)
	parameters.visible = false
	advanced.toggled.connect(func(open: bool):
		parameters.visible = open and mode.selected != 2
		advanced.text = "▾ 更多设置" if open else "▸ 更多设置")
	var label := _label_to(parameters, "素材大小")
	size_input = SpinBox.new()
	size_input.min_value = 0.3
	size_input.max_value = 3.4
	size_input.step = 0.1
	size_input.value = 1
	size_input.tooltip_text = "1.0 为素材原始尺寸；输入后按 Enter 应用到下一笔。"
	parameters.add_child(size_input)
	label = _label_to(parameters, "散布种子")
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", host.ui_px(6))
	parameters.add_child(seed_row)
	seed_input = SpinBox.new()
	seed_input.min_value = 0
	seed_input.max_value = 999999
	seed_input.value = 20261014 % 1000000
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_input.tooltip_text = "种子相同会得到相同的散布位置；输入后按 Enter 应用。"
	seed_row.add_child(seed_input)
	random_seed_button = Button.new()
	random_seed_button.name = "RandomizeDetailSeed"
	random_seed_button.text = "随机"
	random_seed_button.tooltip_text = "生成并立即应用一个新的散布种子"
	random_seed_button.pressed.connect(_randomize_seed)
	seed_row.add_child(random_seed_button)
	apply_hint = _label_to(parameters, "修改后按回车应用到下一笔")
	apply_hint.modulate = Color(1, 1, 1, 0.62)
	seed_controls = [label, seed_row]
	selection_panel = PanelContainer.new()
	selection_panel.name = "DetailSelectionPanel"
	selection_panel.add_theme_stylebox_override("panel",
		_info_style(Color("#80d6b5"), Color("#1d3330")))
	add_child(selection_panel)
	var selection_info := VBoxContainer.new()
	selection_info.add_theme_constant_override("separation", 3)
	selection_panel.add_child(selection_info)
	info_caption = _label_to(selection_info, "当前素材")
	info_caption.name = "DetailInfoCaption"
	info_caption.add_theme_color_override("font_color", Color("#80d6b5"))
	info = _label_to(selection_info, "选择下面的素材卡片")
	info.name = "DetailInfo"
	selection_controls = VBoxContainer.new()
	selection_controls.name = "DetailSelectionControls"
	selection_controls.add_theme_constant_override("separation", 6)
	add_child(selection_controls)
	remove_child(search)
	selection_controls.add_child(search)
	remove_child(reload_button)
	selection_controls.add_child(reload_button)
	palette = ItemList.new()
	palette.name = "DetailPalette"
	palette.auto_height = true
	palette.icon_mode = ItemList.ICON_MODE_TOP
	palette.fixed_icon_size = host.ui_size(Vector2(56, 48))
	# Three readable cards across a 310px dock; names wrap to two lines.
	palette.fixed_column_width = host.ui_px(84)
	palette.max_columns = 0
	palette.same_column_width = true
	palette.max_text_lines = 2
	palette.item_selected.connect(_selected)
	selection_controls.add_child(palette)
	for spin in [radius, density, size_input, seed_input]:
		spin.value_changed.connect(func(_value: float): _settings_changed())
	refresh_library()
	_mode_changed(0)

func _label(text: String) -> Label:
	return _label_to(self, text)

func _label_to(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _info_style(accent: Color, background: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = accent
	style.set_border_width_all(host.ui_px(1))
	style.set_corner_radius_all(host.ui_px(4))
	style.content_margin_left = host.ui_px(10)
	style.content_margin_right = host.ui_px(10)
	style.content_margin_top = host.ui_px(8)
	style.content_margin_bottom = host.ui_px(8)
	return style

func _style_scatter_choice(button: Button) -> void:
	button.custom_minimum_size.y = host.ui_px(36)
	button.add_theme_stylebox_override("normal",
		_choice_style(Color("#2d373c"), Color("#59666d")))
	button.add_theme_stylebox_override("hover",
		_choice_style(Color("#38464b"), Color("#7a888e")))
	button.add_theme_stylebox_override("pressed",
		_choice_style(Color("#20594d"), Color("#80d6b5"), 2))
	button.add_theme_stylebox_override("focus",
		_choice_style(Color("#2d373c"), Color("#80d6b5"), 2))
	button.add_theme_color_override("font_pressed_color", Color("#e8fff8"))

func _choice_style(background: Color, border: Color, width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(host.ui_px(width))
	style.set_corner_radius_all(host.ui_px(4))
	style.content_margin_top = host.ui_px(6)
	style.content_margin_bottom = host.ui_px(6)
	return style

func _spin(low: float, high: float, step_value: float, initial: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step_value
	spin.value = initial
	add_child(spin)
	return spin

func _mode_changed(value: int) -> void:
	finish_stroke()
	clear_preview()
	for control in scatter_controls:
		control.visible = value == 1
	for control in radius_controls:
		control.visible = value != 0
	for control in seed_controls:
		control.visible = value == 1
	if advanced != null:
		advanced.visible = value != 2
	if parameters != null:
		parameters.visible = value != 2 and advanced.button_pressed
	_refresh_selection_visibility()

func _scatter_source_changed(_value: int) -> void:
	finish_stroke()
	clear_preview()
	_refresh_selection_visibility()

func _refresh_selection_visibility() -> void:
	if selection_controls == null:
		return
	var show_cards: bool = mode.selected == 0 \
		or (mode.selected == 1 and scatter_source.selected == 1)
	selection_controls.visible = show_cards
	selection_panel.visible = true
	_update_info()

func _settings_changed() -> void:
	clear_preview()
	_update_info()

func _randomize_seed() -> void:
	var random := RandomNumberGenerator.new()
	random.randomize()
	var next_seed := random.randi_range(0, 999999)
	if next_seed == int(seed_input.value):
		next_seed = (next_seed + 1) % 1000000
	seed_input.value = next_seed
	_settings_changed()
	host._set_status("已应用散布种子：%d" % next_seed)

func current_set() -> DetailSet:
	if sets.selected < 0 or sets.selected >= paths.size():
		return null
	return load(paths[sets.selected]) as DetailSet

func refresh_library() -> void:
	var selected_path := paths[sets.selected] if sets.selected >= 0 and sets.selected < paths.size() else ""
	sets.clear()
	paths = DetailSet.library()
	for path in paths:
		var set := load(path) as DetailSet
		sets.add_item(set.display_name if set != null else path.get_file())
	if not paths.is_empty():
		sets.select(maxi(0, paths.find(selected_path)))
	refresh_palette()

func refresh_palette() -> void:
	var selected := palette.get_selected_items()
	var old_variant := visible_variants[selected[0]] if not selected.is_empty() and selected[0] < visible_variants.size() else -1
	palette.clear()
	visible_variants.clear()
	var set := current_set()
	if set == null:
		return
	for index in set.variants.size():
		var variant: Dictionary = set.variants[index]
		var label := str(variant.get("name", variant["id"]))
		if not search.text.is_empty() and not label.containsn(search.text):
			continue
		visible_variants.append(index)
		# Atlas names carry a "01_" sort prefix; show the name first, then the
		# number that tells repeated names (落叶 32 / 落叶 33) apart.
		var prefix := label.get_slice("_", 0)
		var title := label
		if label.contains("_") and prefix.is_valid_int():
			title = label.substr(prefix.length() + 1) + " " + prefix
		var item := palette.add_item(title.replace("_", " "), set.thumbnail(index))
		var size: Vector2 = variant["size"]
		palette.set_item_tooltip(item, "%s\n%.2f × %.2f 米 · %s" % [
			label, size.x, size.y, "贴地" if set.orientation == 0 else "固定视角立片"])
	if palette.item_count > 0:
		var index := maxi(0, visible_variants.find(old_variant))
		palette.select(index)
		_selected(index)
	else:
		info_caption.text = "当前素材"
		info.text = "没有匹配的细节"

func _selected(index: int) -> void:
	if info == null:
		return
	var set := current_set()
	if set == null or index >= visible_variants.size():
		return
	_update_info()
	clear_preview()

func _update_info() -> void:
	if info == null:
		return
	var set := current_set()
	if set == null:
		info_caption.text = "当前素材"
		info.text = "没有可用的细节套件"
		return
	if mode.selected == 2:
		info_caption.text = "当前擦除"
		info.text = "%s\n只擦除这一套细节，不影响地形和玩法物件" % set.display_name
		return
	if mode.selected == 1 and scatter_source.selected == 0:
		info_caption.text = "当前散布"
		info.text = "%s\n混合全部 %d 种素材 · 每次 %d 个 · 种子 %d" % [
			set.display_name, set.variants.size(), int(density.value), int(seed_input.value)]
		return
	var selected := palette.get_selected_items()
	if selected.is_empty() or selected[0] >= visible_variants.size():
		info_caption.text = "当前素材"
		info.text = "选择下面的素材卡片"
		return
	var variant: Dictionary = set.variants[visible_variants[selected[0]]]
	var source_size: Vector2 = variant["size"]
	var size := source_size * size_input.value
	var title := _display_title(str(variant.get("name", variant["id"])))
	var count_text := " · 每次 %d 个 · 种子 %d" % [
		int(density.value), int(seed_input.value)] if mode.selected == 1 else ""
	info_caption.text = "单一散布" if mode.selected == 1 else "当前素材"
	info.text = "%s\n%s · %.2f × %.2f 米 · 无碰撞%s" % [
		title, "贴地" if set.orientation == 0 else "固定视角立片",
		size.x, size.y, count_text]

static func _display_title(value: String) -> String:
	var prefix := value.get_slice("_", 0)
	var title := value
	if value.contains("_") and prefix.is_valid_int():
		title = value.substr(prefix.length() + 1) + " " + prefix
	return title.replace("_", " ")

func records_at(point: Vector3, id: String, seed_value: int) -> Array[Dictionary]:
	var set := current_set()
	if set == null:
		return []
	if mode.selected == 1 and scatter_source.selected == 0:
		return DetailRules.scatter(host.data, paths[sets.selected], point, radius.value,
			int(density.value), seed_value, id, -1, size_input.value)
	var selected := palette.get_selected_items()
	if selected.is_empty():
		return []
	var variant := visible_variants[selected[0]]
	if mode.selected == 1:
		return DetailRules.scatter(host.data, paths[sets.selected], point, radius.value,
			int(density.value), seed_value, id, variant, size_input.value)
	var record := DetailRules.make_record(host.data, paths[sets.selected],
		str(set.variants[variant]["id"]), point, id, seed_value, 0, size_input.value)
	if not DetailRules.validate_record(host.data, record, set).is_empty():
		return []
	return [record]

func handle(camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		clear_preview()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		finish_stroke()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if not event is InputEventMouseMotion and not (event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var surface := Picker.pick(host.builder, camera, event.position)
	if surface.is_empty() or surface.has("error") or surface.get("kind") != "terrain" \
			or (surface.get("normal", Vector3.ZERO) as Vector3).y < 0.7:
		clear_preview()
		host._set_status(surface.get("error", "细节需要真实的地形顶面"))
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	var point: Vector3 = surface["position"]
	point.y = host.data.world_center(surface["cell"]).y
	if event is InputEventMouseButton:
		finish_stroke()
		drawing = true
		stroke_data = host.data
		before = stroke_data.details.duplicate(true)
		stroke_id = ObjectRules.new_id()
		sample_index = 0
		last_point = Vector3(INF, INF, INF)
	if drawing:
		if host.data != stroke_data:
			finish_stroke()
		elif not last_point.is_finite() or (mode.selected != 0 and
				last_point.distance_to(point) >= maxf(0.25, radius.value * 0.5)):
			paint_at(point)
	preview_at(point)
	return EditorPlugin.AFTER_GUI_INPUT_STOP

func paint_at(point: Vector3) -> void:
	if mode.selected == 2:
		for i in range(stroke_data.details.size() - 1, -1, -1):
			var record := stroke_data.details[i]
			if sets.selected < 0 or record.get("set") != paths[sets.selected]:
				continue
			var relative: Vector3 = record["position"] - point
			if absf(relative.y) < 0.05 and Vector2(relative.x, relative.z).length() <= radius.value:
				stroke_data.details.remove_at(i)
	else:
		var seed_value := int(seed_input.value) + sample_index
		var records := records_at(point, "%s_%d" % [stroke_id, sample_index], seed_value)
		if records.is_empty():
			host._set_status(_empty_placement_message())
		else:
			stroke_data.details.append_array(records)
	stroke_data.emit_changed()
	host.builder.rebuild_details()
	last_point = point
	sample_index += 1

func finish_stroke() -> void:
	if not drawing:
		return
	drawing = false
	if stroke_data != null:
		host._commit_details(stroke_data, before, stroke_data.details.duplicate(true),
			"擦除细节" if mode.selected == 2 else "绘制细节")
	stroke_data = null
	before.clear()

func preview_at(point: Vector3) -> void:
	clear_preview()
	var invalid := false
	if mode.selected != 2:
		var preview := LevelData.new()
		preview.details = records_at(point, "preview", int(seed_input.value) + sample_index)
		invalid = preview.details.is_empty()
		ghost = DetailRenderer.new()
		host.builder.add_child(ghost)
		ghost.refresh(preview)
		for group in ghost.groups.values():
			group.transparency = 0.25
		host._set_status(_empty_placement_message() if invalid else
			"左键%s · 当前地图 %d 个细节" % [
				"放置" if mode.selected == 0 else "散布", host.data.details.size()])
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#ed9d7c") if mode.selected == 2 or invalid else Color("#80d6b5")
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	var reach := radius.value if mode.selected != 0 else 0.15
	for i in 49:
		var angle := TAU * i / 48
		mesh.surface_add_vertex(Vector3(cos(angle) * reach, 0.07, sin(angle) * reach))
	mesh.surface_end()
	ring = MeshInstance3D.new()
	ring.mesh = mesh
	ring.position = point
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.builder.add_child(ring)

func _empty_placement_message() -> String:
	var set := current_set()
	if set != null and set.orientation == DetailSet.DetailOrientation.GROUND:
		return "当前尺寸在这里缺少完整的同高干燥地面；请调小素材或移动笔刷"
	return "笔刷范围内没有可用位置；请移动笔刷或扩大半径"

func clear_preview() -> void:
	if is_instance_valid(ghost):
		ghost.free()
	ghost = null
	if is_instance_valid(ring):
		ring.free()
	ring = null
