@tool
extends VBoxContainer

## Additional art inputs and image-only worker. The host retains the legacy API.
var host
var slots: Dictionary = {}
var recipes: Dictionary = {}
var original_paths: Dictionary = {}
var slot_list: VBoxContainer
var tools: VBoxContainer
var slot_choice: OptionButton
var black: CheckBox
var trim: CheckBox
var threshold: SpinBox
var rectify: CheckBox
var corners: Array[SpinBox] = []
var mask_path := ""
var mask_label: Label
var before_view: TextureRect
var after_view: TextureRect
var status: Label
var process_button: Button
var worker: Thread
var busy := false
var applied := false
var atlas_result: Dictionary = {}
var manifest_path := ""
var behaviour: OptionButton
var supports: CheckBox
var health: SpinBox
var detail_orientation: OptionButton
var type_hint: Label
var behaviour_section: VBoxContainer
var terrain_section: VBoxContainer
var detail_section: VBoxContainer
var top_span: SpinBox
var cliff_span: SpinBox
var cliff_height: SpinBox
var rim_span: SpinBox
var rim_rise: SpinBox
var rim_drop: SpinBox
var importing := false
var state_section: VBoxContainer
var state_preview: OptionButton
var separate_pivot: CheckBox
var open_u: SpinBox
var open_v: SpinBox

func setup(dock) -> void:
	host = dock
	add_theme_constant_override("separation", 8)
	type_hint = _label(self, "")
	slot_list = VBoxContainer.new()
	add_child(slot_list)
	terrain_section = VBoxContainer.new()
	add_child(terrain_section)
	top_span = _spin(terrain_section, "顶面重复宽度 · 米", 0.1, 64, 8)
	cliff_span = _spin(terrain_section, "侧壁图宽 · 米", 0.1, 64, 4)
	cliff_height = _spin(terrain_section, "侧壁图高 · 米（2 = 每层一张）", 0.1, 16, 2)
	rim_span = _spin(terrain_section, "边缘图宽 · 米", 0.1, 64, 4)
	rim_rise = _spin(terrain_section, "边缘高出顶面 · 米", 0, 1, 0.1)
	rim_drop = _spin(terrain_section, "边缘垂下侧壁 · 米", 0, 1, 0.15)
	for spin in [top_span, cliff_span, cliff_height, rim_span, rim_rise, rim_drop]:
		spin.value_changed.connect(func(_value: float): host._schedule_preview())
	detail_section = VBoxContainer.new()
	add_child(detail_section)
	detail_orientation = _option(detail_section, ["贴地细节", "固定视角立片"])
	_label(detail_section, "首图和变体一起打包为图集。显示宽度决定每个变体的宽度；细节不阻挡角色。")
	behaviour_section = VBoxContainer.new()
	add_child(behaviour_section)
	behaviour = _option(behaviour_section, ["装饰", "可登顶岩石", "可破坏岩石", "宝箱", "攀岩点"], "玩法")
	supports = CheckBox.new()
	supports.text = "可承托其他物件"
	behaviour_section.add_child(supports)
	health = _spin(behaviour_section, "耐久", 1, 1000, 3)
	behaviour.item_selected.connect(func(index: int):
		health.get_parent().visible = index == PlaceableDefinition.Behaviour.BREAKABLE
		host._schedule_preview())
	supports.toggled.connect(func(_value: bool): host._schedule_preview())
	state_section = VBoxContainer.new()
	add_child(state_section)
	state_preview = _option(state_section, ["预览关闭状态", "预览开启状态"])
	state_preview.item_selected.connect(func(_index: int): host._schedule_preview())
	separate_pivot = CheckBox.new()
	separate_pivot.text = "单独调整开启状态接地点"
	state_section.add_child(separate_pivot)
	open_u = _spin(state_section, "开启接地点 U", 0, 1, 0.5)
	open_v = _spin(state_section, "开启接地点 V", 0, 1, 1)
	for spin in [open_u, open_v]:
		spin.step = 0.001
		spin.get_parent().visible = false
		spin.value_changed.connect(func(_value: float): host._schedule_preview())
	separate_pivot.toggled.connect(func(value: bool):
		open_u.get_parent().visible = value
		open_v.get_parent().visible = value
		host._schedule_preview())
	var toggle := Button.new()
	toggle.text = "▸ 图片处理与对照"
	toggle.toggle_mode = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(toggle)
	tools = VBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	tools.visible = false
	add_child(tools)
	toggle.toggled.connect(func(open: bool):
		tools.visible = open
		toggle.text = "▾ 图片处理与对照" if open else "▸ 图片处理与对照")
	slot_choice = _option(tools, [], "当前图片")
	slot_choice.item_selected.connect(_select_recipe)
	black = CheckBox.new()
	black.text = "清除与画布边缘相连的黑底"
	tools.add_child(black)
	threshold = _spin(tools, "黑底阈值", 0, 64, 8)
	trim = CheckBox.new()
	trim.text = "裁去透明留白"
	trim.button_pressed = true
	tools.add_child(trim)
	rectify = CheckBox.new()
	rectify.text = "面片四角校正"
	tools.add_child(rectify)
	var quad_controls := VBoxContainer.new()
	quad_controls.visible = false
	tools.add_child(quad_controls)
	_label(quad_controls, "按左上 → 右上 → 右下 → 左下填写 U/V（0～1）。")
	var values := [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]
	for i in 4:
		var row := HBoxContainer.new()
		quad_controls.add_child(row)
		for value: float in [values[i].x, values[i].y]:
			var spin := SpinBox.new()
			spin.min_value = 0
			spin.max_value = 1
			spin.step = 0.001
			spin.value = value
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(spin)
			corners.append(spin)
	_button(quad_controls, "从透明轮廓估算四角", _estimate_quad)
	rectify.toggled.connect(func(value: bool): quad_controls.visible = value)
	mask_label = _label(tools, "未指定遮罩")
	_button(tools, "选择灰度遮罩", func(): host._choose_image("__mask"))
	_button(tools, "清除遮罩", func(): mask_path = ""; mask_label.text = "未指定遮罩")
	_label(tools, "遮罩：白色保留、黑色透明。原图会完整保留；黑色轮廓粘连背景时请用遮罩修正。")
	_button(tools, "保存当前槽位参数", _save_recipe)
	process_button = _button(tools, "处理全部图片 / 生成图集", process_images)
	var compare := HBoxContainer.new()
	compare.add_theme_constant_override("separation", 8)
	tools.add_child(compare)
	before_view = _image_view(compare, "原图")
	after_view = _image_view(compare, "处理稿")
	status = _label(tools, "处理后再生成资源。面片无需校正时可直接使用原图。")
	set_mode(0)

func set_mode(mode: int) -> void:
	for child in slot_list.get_children():
		slot_list.remove_child(child)
		child.queue_free()
	slots.clear()
	recipes.clear()
	original_paths.clear()
	atlas_result.clear()
	applied = false
	manifest_path = ""
	var names: Dictionary = {}
	match mode:
		2:
			names = {"cliff": "侧壁", "rim": "边缘", "slope": "坡面侧图"}
		3:
			names = {"variant_1": "变体 2", "variant_2": "变体 3", "variant_3": "变体 4",
				"variant_4": "变体 5", "variant_5": "变体 6", "variant_6": "变体 7", "variant_7": "变体 8"}
		4:
			names = {"left": "左面", "right": "右面", "back": "背面", "top": "顶面"}
		5:
			names = {"open": "开启状态"}
	for key: String in names:
		var row := HBoxContainer.new()
		slot_list.add_child(row)
		var select := _button(row, names[key], func(): host._choose_image(key))
		# Same column as the dock's 名称 / ID labels, so file names line up with values.
		select.custom_minimum_size.x = host.LABEL_WIDTH * EditorInterface.get_editor_scale()
		var label := Label.new()
		label.text = "未选择 · 复用正面" if key == "back" else "未选择"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(label)
		slots[key] = {"path": "", "label": label, "title": names[key]}
	terrain_section.visible = mode == 2
	detail_section.visible = mode == 3
	state_section.visible = mode == 5
	behaviour_section.visible = mode in [0, 4, 5, 6]
	behaviour.selected = 1 if mode == 4 else 3 if mode == 5 else 4 if mode == 6 else 0
	behaviour.disabled = mode in [5, 6]
	supports.button_pressed = mode == 4
	supports.visible = mode not in [5, 6]
	health.get_parent().visible = false
	type_hint.text = [
		"主图 → 单张物件。显示尺寸与碰撞范围可分别调整。",
		"主图 → 单个地块。使用透明图时，留白显示基底颜色。",
		"主图用作连续顶面；补充侧壁与边缘，组成同一种地形。边缘图透明区域会露出侧壁。",
		"主图作为第一个变体，可补充七张图片后生成细节图集。",
		"主图用作正面；各面校正成方形后包裹真实盒体。",
		"主图是关闭状态。两张图应使用相同画布和接地点。",
		"主图贴在外露侧壁。使用宿主碰撞，E 键攀爬。"
	][mode]
	_rebuild_choices()

func accept_slot(key: String, path: String) -> void:
	if key == "__mask":
		mask_path = path
		mask_label.text = path.get_file()
		mask_label.tooltip_text = path
		return
	if slots.has(key):
		slots[key]["path"] = path
		slots[key]["label"].text = path.get_file()
		slots[key]["label"].tooltip_text = path
		original_paths.erase(key)
		applied = false
		atlas_result.clear()
	_rebuild_choices()
	host._schedule_preview()

func source_changed() -> void:
	original_paths.erase("source")
	applied = false
	atlas_result.clear()
	_rebuild_choices()

func paths() -> Dictionary:
	var result := {"source": str(host.fields["source"].text)}
	for key: String in slots:
		if not str(slots[key]["path"]).is_empty():
			result[key] = str(slots[key]["path"])
	return result

func _rebuild_choices() -> void:
	slot_choice.clear()
	for key: String in paths():
		slot_choice.add_item("主图" if key == "source" else str(slots[key]["title"]))
		slot_choice.set_item_metadata(slot_choice.item_count - 1, key)
	if slot_choice.item_count > 0:
		slot_choice.select(0)
		_select_recipe(0)

func _current_key() -> String:
	return str(slot_choice.get_item_metadata(slot_choice.selected)) if slot_choice.selected >= 0 else "source"

func _save_recipe() -> void:
	var quad := []
	if rectify.button_pressed:
		for i in 4:
			quad.append([corners[i * 2].value, corners[i * 2 + 1].value])
	recipes[_current_key()] = {"black_background": black.button_pressed,
		"threshold": threshold.value, "trim": trim.button_pressed,
		"quad": quad, "mask_path": mask_path, "max_size": 1024}

func _select_recipe(_index: int) -> void:
	var key := _current_key()
	var recipe: Dictionary = recipes.get(key, {})
	black.button_pressed = recipe.get("black_background", false)
	threshold.value = recipe.get("threshold", 8)
	trim.button_pressed = recipe.get("trim", host.generate_as.selected not in [2, 4, 5])
	rectify.button_pressed = not recipe.get("quad", []).is_empty()
	var quad: Array = recipe.get("quad", [])
	for i in quad.size():
		corners[i * 2].value = quad[i][0]
		corners[i * 2 + 1].value = quad[i][1]
	mask_path = recipe.get("mask_path", "")
	mask_label.text = mask_path.get_file() if not mask_path.is_empty() else "未指定遮罩"
	var current: String = paths().get(key, "")
	_show_image(before_view, original_paths.get(key, current))
	_show_image(after_view, current if applied else "")

func _show_image(view: TextureRect, path: String) -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path)) \
		if not path.is_empty() and FileAccess.file_exists(path) else null
	view.texture = ImageTexture.create_from_image(image) if image != null else null

func _estimate_quad() -> void:
	var path: String = paths().get(_current_key(), "")
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		status.text = "先为这个槽位选择图片。"
		return
	var quad := ArtPreparation.estimate_quad(image)
	for i in 4:
		corners[i * 2].value = quad[i].x
		corners[i * 2 + 1].value = quad[i].y
	_save_recipe()
	status.text = "四角已估算，请在处理对照中检查是否保留了完整面片。"

func process_images() -> void:
	if busy:
		return
	_save_recipe()
	var input := paths()
	for key: String in input:
		if original_paths.has(key):
			input[key] = original_paths[key]
	if str(input.get("source", "")).is_empty():
		status.text = "请先选择主图。"
		return
	busy = true
	process_button.disabled = true
	host.generate_button.disabled = true
	host.generate_as.disabled = true
	status.text = "正在处理图片…"
	var options := recipes.duplicate(true)
	var mode: int = host.generate_as.selected
	var output_dir := "res://assets/derived_art/imported/" + ObjectRules.new_id()
	worker = Thread.new()
	var error := worker.start(_process_worker.bind(input, options, mode, output_dir))
	if error != OK:
		worker = null
		_finish_job("无法启动图片处理：" + error_string(error))
		return
	while worker.is_alive():
		await get_tree().process_frame
	var result: Dictionary = worker.wait_to_finish()
	worker = null
	if not str(result.get("error", "")).is_empty():
		_finish_job(result["error"])
		return
	EditorInterface.get_resource_filesystem().scan()
	for attempt in 150:
		var ready := not EditorInterface.get_resource_filesystem().is_scanning()
		for path: String in result["paths"].values():
			ready = ready and _imported(path)
		if result.has("atlas"):
			ready = ready and _imported(result["atlas"]["path"])
		if ready:
			break
		await get_tree().create_timer(0.1).timeout
		if attempt == 149:
			_finish_job("处理稿已保存，Godot 导入尚未完成，请稍后重试。")
			return
	original_paths = input
	manifest_path = output_dir.path_join("recipe.json")
	atlas_result = result.get("atlas", {})
	host.fields["source"].text = result["paths"]["source"]
	for key: String in slots:
		if result["paths"].has(key):
			slots[key]["path"] = result["paths"][key]
			slots[key]["label"].text = "已处理 · " + str(input[key]).get_file()
	applied = true
	host._calculate_defaults()
	_select_recipe(slot_choice.selected)
	_finish_job("处理完成。检查对照与下方预览，再生成资源。")

static func _process_worker(input: Dictionary, recipes_data: Dictionary, mode: int, directory: String) -> Dictionary:
	var processed: Dictionary = {}
	var images: Array[Image] = []
	var sizes: Array[Vector2i] = []
	var saved := {}
	for key: String in input:
		var image := Image.load_from_file(ProjectSettings.globalize_path(input[key]))
		if image == null:
			return {"error": "无法读取图片：" + str(input[key]).get_file()}
		var recipe: Dictionary = recipes_data.get(key, {"trim": mode not in [2, 4, 5]}).duplicate(true)
		if mode == 5:
			recipe["trim"] = false
		var quad := PackedVector2Array()
		for point: Array in recipe.get("quad", []):
			quad.append(Vector2(point[0], point[1]))
		recipe["quad"] = quad
		var mask: String = recipe.get("mask_path", "")
		if not mask.is_empty():
			recipe["mask"] = Image.load_from_file(ProjectSettings.globalize_path(mask))
			if recipe["mask"] == null:
				return {"error": "遮罩读取失败"}
		var result := ArtPreparation.process(image, recipe)
		if not str(result.get("error", "")).is_empty():
			return result
		processed[key] = result["image"]
		images.append(result["image"])
		sizes.append(result["image"].get_size())
	var atlas := {}
	if mode == 3:
		atlas = ArtPreparation.build_atlas(images)
		if not str(atlas.get("error", "")).is_empty():
			return atlas
	var mkdir := DirAccess.make_dir_recursive_absolute(directory)
	if mkdir != OK:
		return {"error": "无法创建处理稿目录"}
	for key: String in processed:
		var path := directory.path_join(key + ".png")
		if _save_art_png(processed[key], path) != OK:
			return {"error": "无法保存处理稿"}
		saved[key] = path
	var result := {"error": "", "paths": saved}
	if mode == 3:
		var path := directory.path_join("atlas.png")
		if _save_art_png(atlas["image"], path) != OK:
			return {"error": "无法保存图集"}
		result["atlas"] = {"path": path, "rects": atlas["rects"], "sizes": sizes,
			"keys": input.keys(), "names": input.values()}
	var file := FileAccess.open(directory.path_join("recipe.json"), FileAccess.WRITE)
	if file == null:
		return {"error": "无法保存处理配方"}
	file.store_string(JSON.stringify({"version": 1, "sources": input, "recipes": recipes_data, "outputs": saved}, "\t"))
	file.close()
	return result

## Settings are written before the PNG, so the first import already matches the
## scene pack: mipmaps for 3D minification, and no 3D auto-detect that would later
## reimport the art as VRAM-compressed.
static func _save_art_png(image: Image, path: String) -> Error:
	var settings := ConfigFile.new()
	settings.set_value("remap", "importer", "texture")
	settings.set_value("remap", "type", "CompressedTexture2D")
	settings.set_value("params", "mipmaps/generate", true)
	settings.set_value("params", "detect_3d/compress_to", 0)
	var error := settings.save(path + ".import")
	return error if error != OK else image.save_png(path)

## The pre-written .import file makes ResourceLoader.exists() true before Godot has
## imported the image, so readiness is the imported output itself.
static func _imported(path: String) -> bool:
	var settings := ConfigFile.new()
	if settings.load(path + ".import") != OK:
		return false
	var outputs: Array = settings.get_value("deps", "dest_files", [])
	for output: String in outputs:
		if not FileAccess.file_exists(output):
			return false
	return not outputs.is_empty()

func _finish_job(text: String) -> void:
	busy = false
	process_button.disabled = false
	host.generate_as.disabled = false
	host.generate_button.disabled = host.analysis.is_empty()
	status.text = text

func configure_definition(d: PlaceableDefinition) -> void:
	d.behaviour = behaviour.selected
	d.supports_objects = supports.button_pressed
	d.max_health = int(health.value)
	d.source_manifest = manifest_path
	d.preparation = {"sources": original_paths.duplicate(), "recipes": recipes.duplicate(true)}
	match host.generate_as.selected:
		4:
			d.carrier = PlaceableDefinition.Carrier.MULTI_FACE
			d.face_images = {"front": d.source_image}
			for key: String in ["left", "right", "back", "top"]:
				d.face_images[key] = slots[key]["path"]
			if str(d.face_images["back"]).is_empty():
				d.face_images["back"] = d.source_image
		5:
			d.state_images = {"closed": d.source_image, "open": slots["open"]["path"]}
			if separate_pivot.button_pressed:
				d.state_pivots["open"] = Vector2(open_u.value, open_v.value)
		6:
			d.carrier = PlaceableDefinition.Carrier.WALL
			d.collision = PlaceableDefinition.Collision.NONE
			d.supports_objects = false

func make_terrain() -> TerrainArtSet:
	var art := TerrainArtSet.new()
	art.set_id = str(host.fields["id"].text).strip_edges()
	art.display_name = str(host.fields["name"].text).strip_edges()
	art.top_path = host.fields["source"].text
	art.top_span = Vector2.ONE * top_span.value
	art.cliff_path = slots["cliff"]["path"]
	art.cliff_span = Vector2(cliff_span.value, cliff_height.value)
	if not str(slots["rim"]["path"]).is_empty():
		art.rim_paths.append(slots["rim"]["path"])
	art.rim_span = rim_span.value
	art.rim_rise = rim_rise.value
	art.rim_drop = rim_drop.value
	art.slope_side_path = slots["slope"]["path"]
	art.source_manifest = manifest_path
	return art

func make_details() -> DetailSet:
	var detail := DetailSet.new()
	detail.set_id = str(host.fields["id"].text).strip_edges()
	detail.display_name = str(host.fields["name"].text).strip_edges()
	detail.orientation = detail_orientation.selected
	detail.source_manifest = manifest_path
	if atlas_result.is_empty():
		return detail
	detail.atlas_path = atlas_result["path"]
	for i in atlas_result["rects"].size():
		var size: Vector2i = atlas_result["sizes"][i]
		detail.variants.append({"id": "variant_%d" % i,
			"name": str(atlas_result["names"][i]).get_file().get_basename(),
			"rect": atlas_result["rects"][i],
			"size": Vector2(host.display_width.value, host.display_width.value * float(size.y) / size.x),
			"pivot": Vector2(0.5, 0.5 if detail.orientation == 0 else 1.0)})
	return detail

func _exit_tree() -> void:
	if worker != null and worker.is_started():
		worker.wait_to_finish()

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _option(parent: Node, items: Array, title := "") -> OptionButton:
	var option := OptionButton.new()
	option.clip_text = true
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item: String in items:
		option.add_item(item)
	if not title.is_empty():
		# Labelled rows use the dock's label column, like 类型.
		var row := HBoxContainer.new()
		parent.add_child(row)
		var label := Label.new()
		label.text = title
		label.custom_minimum_size.x = host.LABEL_WIDTH * EditorInterface.get_editor_scale()
		row.add_child(label)
		parent = row
	parent.add_child(option)
	option.get_popup().max_size.y = 280
	return option

func _spin(parent: Node, title: String, low: float, high: float, value: float) -> SpinBox:
	var group := VBoxContainer.new()
	parent.add_child(group)
	_label(group, title)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = 0.05 if high < 100 else 1
	spin.value = value
	group.add_child(spin)
	return spin

func _image_view(parent: Node, title: String) -> TextureRect:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	_label(column, title)
	var view := TextureRect.new()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.custom_minimum_size = Vector2(90, 125) * EditorInterface.get_editor_scale()
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#687482")
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", background)
	column.add_child(panel)
	panel.add_child(view)
	return view
