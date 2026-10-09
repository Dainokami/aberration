@tool
extends VBoxContainer

signal generated(path: String)
var fields: Dictionary = {}
var image_dialog: EditorFileDialog
var target_field := "source"
var viewport: SubViewport
var preview_root: Node3D
var message: Label
var carrier: OptionButton
var collision: OptionButton
var foreground_fade: CheckBox
var advanced: VBoxContainer
var build_parent: VBoxContainer
var density: SpinBox
var display_width: SpinBox
var blocking: CheckBox
var analysis_label: Label
var analysis: Dictionary = {}
var updating := false
var refresh_pending := false
var preview_camera: Camera3D
var preset_dialog: EditorFileDialog
var import_timer: Timer
var import_attempts := 0
var original_filename := ""

func _ready() -> void:
	var help := Label.new()
	help.text = "任意透明图片均可导入，无需物件模板。\n自动值是起点；真实尺寸、纵深和碰撞需你确认。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	build_parent = self
	_line("source", "主图片", "")
	_button("选择图片（项目内或外部）", _choose_image.bind("source"))
	_line("name", "显示名称", "新物件")
	carrier = _option("图片怎么摆？", ["立在场景里（固定相机卡片）", "铺在地面上", "贴到盒体上（高级）", "贴到坡体上（高级）"])
	_numbers("display_width", "画布显示宽度(m) · 自动保持原图比例", [1.0], 0.01, 1024)
	display_width = fields["display_width"][0]
	blocking = CheckBox.new()
	blocking.text = "阻挡角色（默认不阻挡）"
	add_child(blocking)
	analysis_label = Label.new()
	analysis_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(analysis_label)
	var advanced_toggle := CheckBox.new()
	advanced_toggle.text = "高级设置：尺寸依据 / 落点 / 碰撞 / 分层"
	add_child(advanced_toggle)
	advanced = VBoxContainer.new()
	add_child(advanced)
	advanced.hide()
	advanced_toggle.toggled.connect(advanced.set_visible)
	build_parent = advanced
	_line("id", "英文资源 ID（自动生成）", "new_asset")
	_numbers("density", "像素密度 px/m（只用于重新计算）", [256.0], 1, 4096)
	density = fields["density"][0]
	_button("重新计算默认值（重置尺寸、落点与代理形状）", _calculate_defaults)
	_line("foreground", "可选前景层", "")
	_button("选择前景（须与主图同画布/支点）", _choose_image.bind("foreground"))
	collision = _option("代理形状（勾选阻挡角色时生效）", ["无", "盒体", "圆柱"])
	_numbers("image", "画布宽 / 高(m) · 比例锁定", [1.0, 1.0], 0.001, 4096)
	_numbers("pivot", "接地点 U / V", [0.5, 1.0], 0, 1)
	_numbers("volume", "包裹宽 / 高 / 深", [2.0, 3.0, 2.0], 0.1, 32)
	_numbers("collision", "碰撞宽 / 高 / 深", [1.0, 2.0, 1.0], 0.1, 32)
	_numbers("offset", "碰撞偏移 X/Y/Z", [0.0, 0.0, 0.0], -16, 16)
	foreground_fade = CheckBox.new()
	foreground_fade.text = "运行时前景遮挡角色时淡出（需独立前景图）"
	advanced.add_child(foreground_fade)
	_button("保存当前配置为自定义预设", _preset_save)
	_button("应用自定义预设", _preset_open)
	build_parent = self
	_button("更新预览 · 点击画面可修正落点", _refresh_preview)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(280, 210)
	container.stretch = true
	add_child(container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, 240)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	viewport.gui_disable_input = true
	container.gui_input.connect(_preview_input.bind(container))
	_button("生成并加入物件库", _generate)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)
	image_dialog = EditorFileDialog.new()
	image_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	image_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	image_dialog.filters = PackedStringArray(["*.png,*.webp ; Transparent art"])
	image_dialog.file_selected.connect(_image_selected)
	add_child(image_dialog)
	preset_dialog = EditorFileDialog.new()
	preset_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	preset_dialog.add_filter("*.json", "通用导入配置")
	preset_dialog.file_selected.connect(_preset_selected)
	add_child(preset_dialog)
	import_timer = Timer.new()
	import_timer.wait_time = 0.3
	import_timer.timeout.connect(_wait_for_import)
	add_child(import_timer)
	fields["source"].text_submitted.connect(func(path: String): _accept_source(path))
	display_width.value_changed.connect(_width_changed)
	fields["image"][0].value_changed.connect(_width_changed)
	fields["image"][1].value_changed.connect(_height_changed)
	for key in ["pivot", "volume", "collision", "offset"]:
		for spin in fields[key]:
			spin.value_changed.connect(func(_value: float): _schedule_preview())
	carrier.item_selected.connect(func(_index: int): _schedule_preview())
	collision.item_selected.connect(func(index: int):
		blocking.set_pressed_no_signal(index != 0)
		_schedule_preview())
	blocking.toggled.connect(func(enabled: bool):
		if enabled and collision.selected == 0:
			collision.selected = 1
		elif not enabled:
			collision.selected = 0
		_schedule_preview())
	foreground_fade.toggled.connect(func(_enabled: bool): _schedule_preview())
	fields["foreground"].text_submitted.connect(func(_text: String): _schedule_preview())

func _line(key: String, title: String, text: String) -> void:
	var row := HBoxContainer.new()
	build_parent.add_child(row)
	var label := Label.new()
	label.text = title
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = text
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	fields[key] = edit

func _numbers(key: String, title: String, values: Array, low: float, high: float) -> void:
	var label := Label.new()
	label.text = title
	build_parent.add_child(label)
	var row := HBoxContainer.new()
	build_parent.add_child(row)
	var controls: Array[SpinBox] = []
	for value in values:
		var spin := SpinBox.new()
		spin.min_value = low
		spin.max_value = high
		spin.step = 0.001
		spin.value = value
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spin)
		controls.append(spin)
	fields[key] = controls

func _button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	build_parent.add_child(button)

func _option(title: String, options: Array[String]) -> OptionButton:
	var label := Label.new()
	label.text = title
	build_parent.add_child(label)
	var select := OptionButton.new()
	for option in options:
		select.add_item(option)
	build_parent.add_child(select)
	return select

func _choose_image(key: String) -> void:
	target_field = key
	image_dialog.popup_centered_ratio(0.7)

func _image_selected(path: String) -> void:
	var local := ProjectSettings.localize_path(path)
	if not local.begins_with("res://"):
		# Copy bytes unchanged, never edit/delete the user's original image.
		var folder := "res://assets/source_art/imported"
		DirAccess.make_dir_recursive_absolute(folder)
		local = folder.path_join(ObjectRules.new_id().left(12) + "." + path.get_extension().to_lower())
		var error := DirAccess.copy_absolute(path, ProjectSettings.globalize_path(local))
		if error != OK:
			message.text = "复制源图失败：" + str(error)
			return
		EditorInterface.get_resource_filesystem().scan()
	fields[target_field].text = local
	if target_field == "source":
		original_filename = path.get_file()
		_accept_source(local)
	else:
		_start_import_wait()

func _accept_source(path: String) -> void:
	fields["source"].text = path
	var filename := original_filename if not original_filename.is_empty() else path.get_file()
	fields["id"].text = ImageDefaults.available_id(filename)
	fields["name"].text = filename.get_basename()
	original_filename = ""
	# A new source is a new asset: never silently carry over an unrelated layer.
	fields["foreground"].text = ""
	foreground_fade.button_pressed = false
	if ResourceLoader.exists(path):
		_calculate_defaults()
	else:
		analysis_label.text = "正在等待 Godot 导入图片……"
		_start_import_wait()

func _start_import_wait() -> void:
	import_attempts = 0
	import_timer.start()

func _wait_for_import() -> void:
	import_attempts += 1
	var ready := ResourceLoader.exists(fields["source"].text)
	var front: String = fields["foreground"].text
	ready = ready and (front.is_empty() or ResourceLoader.exists(front))
	if ready:
		import_timer.stop()
		if analysis.is_empty() or not analysis.get("error", "").is_empty():
			_calculate_defaults()
		else:
			_schedule_preview()
	elif import_attempts >= 100:
		import_timer.stop()
		message.text = "图片尚未完成导入或路径无效，请检查路径后点击更新预览。"

func _calculate_defaults() -> void:
	var image := _source_image()
	analysis = ImageDefaults.analyze(image, density.value)
	if not analysis["error"].is_empty():
		analysis_label.text = analysis["error"]
		if is_instance_valid(preview_root):
			preview_root.queue_free()
		return
	updating = true
	var size: Vector2 = analysis["image_size"]
	fields["image"][0].value = size.x
	fields["image"][1].value = size.y
	display_width.value = size.x
	for axis in 2:
		fields["pivot"][axis].value = analysis["pivot"][axis]
	for axis in 3:
		fields["collision"][axis].value = analysis["proxy"][axis]
		fields["volume"][axis].value = analysis["proxy"][axis]
		fields["offset"][axis].value = 0
	updating = false
	var rect: Rect2i = analysis["bounds"]
	analysis_label.text = "画布 %s px；有效内容 %s px\n尺寸依据：%.1f px/m，保持原图比例。\n落点由底部像素估算；碰撞深度只是通用初值，不是真实测量。" % [
		analysis["pixels"], rect.size, density.value]
	_schedule_preview()

func _source_image() -> Image:
	var texture := load(fields["source"].text) as Texture2D
	if texture == null:
		return null
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	return image

func _width_changed(value: float) -> void:
	if updating:
		return
	updating = true
	var ratio := 1.0
	if analysis.has("pixels"):
		var pixels: Vector2i = analysis["pixels"]
		ratio = float(pixels.y) / pixels.x
	fields["image"][0].value = value
	fields["image"][1].value = value * ratio
	display_width.value = value
	updating = false
	_schedule_preview()

func _height_changed(value: float) -> void:
	if updating:
		return
	var ratio := 1.0
	if analysis.has("pixels"):
		var pixels: Vector2i = analysis["pixels"]
		ratio = float(pixels.x) / pixels.y
	_width_changed(value * ratio)

func _schedule_preview() -> void:
	if updating or refresh_pending:
		return
	refresh_pending = true
	_auto_preview.call_deferred()

func _auto_preview() -> void:
	refresh_pending = false
	if ResourceLoader.exists(fields["source"].text):
		_refresh_preview()

func _vector(key: String) -> Vector3:
	return Vector3(fields[key][0].value, fields[key][1].value, fields[key][2].value)

func make_definition() -> PlaceableDefinition:
	var d := PlaceableDefinition.new()
	d.asset_id = fields["id"].text.strip_edges()
	d.display_name = fields["name"].text.strip_edges()
	d.category = "通用"
	d.source_image = fields["source"].text.strip_edges()
	d.foreground_image = fields["foreground"].text.strip_edges()
	d.carrier = carrier.selected
	d.collision = collision.selected if blocking.button_pressed else 0
	d.image_size = Vector2(fields["image"][0].value, fields["image"][1].value)
	d.pivot = Vector2(fields["pivot"][0].value, fields["pivot"][1].value)
	d.volume_size = _vector("volume")
	d.collision_size = _vector("collision")
	d.collision_offset = _vector("offset")
	d.fade_foreground = foreground_fade.button_pressed
	d.profile = load("res://data/art_profile.tres") as ArtProfile
	return d

func _refresh_preview() -> void:
	var d := make_definition()
	var errors := d.validate_asset()
	if not errors.is_empty():
		message.text = "\n".join(errors)
		return
	if is_instance_valid(preview_root):
		viewport.remove_child(preview_root)
		preview_root.queue_free()
	preview_root = Node3D.new()
	viewport.add_child(preview_root)
	preview_root.add_child(AssetFactory.make_asset(d))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(d.image_size.x, d.image_size.y) * 1.5
	var center := d.profile.camera_basis().y * d.image_size.y * (d.pivot.y - 0.5)
	preview_root.add_child(camera)
	camera.position = center + d.profile.camera_offset
	camera.look_at(center)
	camera.current = true
	preview_camera = camera
	_add_ground_reference()
	if d.collision != PlaceableDefinition.Collision.NONE:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = d.collision_size
		box.mesh = mesh
		box.position = d.collision_offset + Vector3(0, d.collision_size.y * 0.5, 0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.2, 0.8, 1, 0.3)
		box.material_override = mat
		preview_root.add_child(box)
	message.text = "固定相机预览；黄点=落点，地面线间隔2m。\n点击图片修正落点；蓝框是可调整的代理碰撞。\n修改显示尺寸不会自动改碰撞；需重算时点击高级设置里的按钮。"

func _add_ground_reference() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.48, 0.5)
	for index in range(-3, 4):
		for axis in 2:
			var node := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(12, 0.008, 0.012) if axis == 0 else Vector3(0.012, 0.008, 12)
			node.mesh = mesh
			node.position = Vector3(0, -0.04, index * 2) if axis == 0 else Vector3(index * 2, -0.04, 0)
			node.material_override = mat
			preview_root.add_child(node)
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.045
	sphere.height = 0.09
	marker.mesh = sphere
	var yellow := StandardMaterial3D.new()
	yellow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	yellow.no_depth_test = true
	yellow.albedo_color = Color.YELLOW
	marker.material_override = yellow
	preview_root.add_child(marker)

func _preview_input(event: InputEvent, container: Control) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not is_instance_valid(preview_camera):
		return
	if carrier.selected >= 2:
		message.text = "投影包裹模式请通过高级设置 U/V 调整落点；卡片/贴地模式支持直接点击。"
		return
	var mouse: Vector2 = event.position * Vector2(viewport.size) / container.size
	var origin := preview_camera.project_ray_origin(mouse)
	var ray := preview_camera.project_ray_normal(mouse)
	var d := make_definition()
	var normal := Vector3.UP if carrier.selected == 1 else d.profile.camera_basis().z
	var hit: Variant = Plane(normal, 0).intersects_ray(origin, ray)
	if hit == null:
		return
	var point: Vector3 = hit
	var screen := d.profile.camera_basis().inverse() * point
	if carrier.selected == 1:
		screen = Vector3(point.x, -point.z, 0)
	var pivot := Vector2(screen.x / d.image_size.x + d.pivot.x,
		d.pivot.y - screen.y / d.image_size.y)
	if pivot.x < 0 or pivot.x > 1 or pivot.y < 0 or pivot.y > 1:
		return
	updating = true
	fields["pivot"][0].value = pivot.x
	fields["pivot"][1].value = pivot.y
	updating = false
	_schedule_preview()

## Presets contain only reusable settings, never image paths, IDs or names.
func preset_values() -> Dictionary:
	return {"version": 1, "carrier": carrier.selected,
		"blocking": blocking.button_pressed, "collision": collision.selected,
		"density": density.value, "width": display_width.value,
		"pivot": [fields["pivot"][0].value, fields["pivot"][1].value],
		"volume": [_vector("volume").x, _vector("volume").y, _vector("volume").z],
		"proxy": [_vector("collision").x, _vector("collision").y, _vector("collision").z],
		"offset": [_vector("offset").x, _vector("offset").y, _vector("offset").z]}

func apply_preset(values: Dictionary) -> String:
	if values.get("version") != 1:
		return "不支持的预设版本"
	for key in ["carrier", "collision", "density", "width"]:
		if not values.get(key) is float and not values.get(key) is int:
			return "预设缺少数字：" + key
	if not values.get("blocking") is bool:
		return "预设缺少阻挡设置"
	if values["carrier"] not in [0, 1, 2, 3] or values["collision"] not in [0, 1, 2]:
		return "预设载体或碰撞类型无效"
	if not is_finite(float(values["width"])) or values["width"] < 0.01 or values["width"] > 1024:
		return "预设宽度超范围"
	if not is_finite(float(values["density"])) or values["density"] < 1 or values["density"] > 4096:
		return "预设像素密度超范围"
	for key in ["pivot", "volume", "proxy", "offset"]:
		var array: Variant = values.get(key)
		if not array is Array or array.size() != (2 if key == "pivot" else 3):
			return "预设参数格式错误：" + key
		for value in array:
			if (not value is float and not value is int) or not is_finite(float(value)):
				return "预设参数非有限数值"
			if key == "pivot" and (value < 0 or value > 1):
				return "预设落点越界"
			if key in ["volume", "proxy"] and (value < 0.1 or value > 32):
				return "预设体积超范围"
			if key == "offset" and absf(value) > 16:
				return "预设偏移超范围"
	updating = true
	carrier.selected = int(values["carrier"])
	collision.selected = int(values["collision"])
	blocking.set_pressed_no_signal(values["blocking"])
	density.value = values["density"]
	for pair in [["pivot", "pivot"], ["volume", "volume"], ["proxy", "collision"], ["offset", "offset"]]:
		for axis in values[pair[0]].size():
			fields[pair[1]][axis].value = values[pair[0]][axis]
	updating = false
	_width_changed(values["width"])
	return ""

func _preset_save() -> void:
	preset_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	preset_dialog.current_path = "res://data/my_import_preset.json"
	preset_dialog.popup_centered_ratio(0.6)

func _preset_open() -> void:
	preset_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	preset_dialog.popup_centered_ratio(0.6)

func _preset_selected(path: String) -> void:
	if preset_dialog.file_mode == EditorFileDialog.FILE_MODE_SAVE_FILE:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			message.text = "预设保存失败：" + str(FileAccess.get_open_error())
			return
		file.store_string(JSON.stringify(preset_values(), "\t"))
		file.flush()
		var error := file.get_error()
		file.close()
		message.text = "配置预设已保存，不包含图片/资源ID。" if error == OK else "预设写入失败"
		EditorInterface.get_resource_filesystem().scan()
	else:
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not value is Dictionary:
			message.text = "不是有效的配置预设"
			return
		var error := apply_preset(value)
		message.text = "已应用配置；保持当前图片比例，请确认碰撞和落点。" if error.is_empty() else error

func _generate() -> void:
	var image := _source_image()
	var measured := ImageDefaults.analyze(image, density.value)
	if not measured["error"].is_empty():
		message.text = measured["error"]
		return
	var d := make_definition()
	if not d.asset_id.is_valid_identifier():
		message.text = "请输入合法英文资源 ID"
		return
	var directory := "res://assets/generated".path_join(d.asset_id)
	var error := AssetFactory.generate(d, directory)
	if not error.is_empty():
		message.text = error
		return
	EditorInterface.get_resource_filesystem().scan()
	message.text = "已生成：" + directory + "\n源图与参数已保留。需要改版时用新 ID 生成，不覆盖已有物件。"
	generated.emit(directory.path_join("definition.tres"))
