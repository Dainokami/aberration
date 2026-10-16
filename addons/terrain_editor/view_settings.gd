@tool
extends VBoxContainer

var host: EditorPlugin
var fov: HSlider
var pitch: HSlider
var distance: HSlider
var target_height: HSlider
var fov_value: Label
var pitch_value: Label
var distance_value: Label
var target_value: Label
var applying := false

func setup(plugin: EditorPlugin) -> void:
	host = plugin
	add_theme_constant_override("separation", 10)
	_section("透视")
	fov_value = _slider("视野角 FOV", 20, 70, 1, _profile().field_of_view, "°")
	fov = fov_value.get_meta("slider")
	fov.tooltip_text = "控制取景范围。数值越大看到的范围越宽，画面边缘变形越明显。"
	pitch_value = _slider("俯视角度", 5, 55, 1, _profile().pitch_degrees, "°")
	pitch = pitch_value.get_meta("slider")
	pitch.tooltip_text = "角度越小越接近正面，越大越能看见地面。"
	distance_value = _slider("透视距离", 12, 80, 0.5, _profile().camera_distance, "m")
	distance = distance_value.get_meta("slider")
	distance.tooltip_text = "控制近大远小。距离越近，前后物体的大小差异越明显；同时地图在画面中更大。"
	target_value = _slider("观察高度", -4, 12, 0.25, _profile().target_height, "m")
	target_height = target_value.get_meta("slider")
	target_height.tooltip_text = "移动相机观察中心，不改变地形和物件位置。"
	for slider in [fov, pitch, distance, target_height]:
		slider.value_changed.connect(_changed)
	var reset := Button.new()
	reset.text = "恢复默认"
	reset.pressed.connect(_defaults)
	add_child(reset)
	var save := Button.new()
	save.text = "保存视角配置"
	save.pressed.connect(save_profile)
	add_child(save)

func _section(title: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.modulate = Color(1, 1, 1, 0.65)
	row.add_child(label)
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line)
	add_child(row)

func _slider(title: String, minimum: float, maximum: float, step: float,
		value: float, suffix: String) -> Label:
	var title_row := HBoxContainer.new()
	add_child(title_row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(label)
	var output := Label.new()
	output.text = _format(value, suffix)
	title_row.add_child(output)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(slider)
	output.set_meta("slider", slider)
	output.set_meta("suffix", suffix)
	return output

func _changed(_value: float) -> void:
	if applying:
		return
	_update_values()
	host.apply_view_parameters(fov.value, pitch.value, distance.value, target_height.value)

func _update_values() -> void:
	fov_value.text = _format(fov.value, "°")
	pitch_value.text = _format(pitch.value, "°")
	distance_value.text = _format(distance.value, "m")
	target_value.text = _format(target_height.value, "m")

func _format(value: float, suffix: String) -> String:
	return ("%.1f" % value).trim_suffix(".0") + suffix

func _defaults() -> void:
	applying = true
	fov.value = 38
	pitch.value = 22
	distance.value = 36.8
	target_height.value = 0
	applying = false
	_update_values()
	host.apply_view_parameters(fov.value, pitch.value, distance.value, target_height.value)

func save_profile() -> void:
	var profile := _profile()
	profile.field_of_view = fov.value
	profile.pitch_degrees = pitch.value
	profile.camera_distance = distance.value
	profile.target_height = target_height.value
	var error := ResourceSaver.save(profile, "res://data/art_profile.tres")
	host._set_status("视角配置已保存" if error == OK else "保存视角配置失败：" + error_string(error))

func set_distance_from_viewport(value: float) -> void:
	applying = true
	distance.value = value
	applying = false
	_update_values()

func _profile() -> ArtProfile:
	return load("res://data/art_profile.tres") as ArtProfile
