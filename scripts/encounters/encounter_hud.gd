class_name EncounterHUD
extends Control

var director: EncounterDirector
var text_label: Label
var health: CombatHealth

func setup(value: EncounterDirector, component: CombatHealth, font: Font) -> void:
	director = value
	health = component
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text_label = Label.new()
	text_label.position = Vector2(18, 205)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.add_theme_font_override("font", font)
	add_child(text_label)
	var scale_select := OptionButton.new()
	scale_select.name = "EncounterTimeScale"
	scale_select.position = Vector2(18, 350)
	scale_select.add_theme_font_override("font", font)
	for option in ["刷新计时 1×", "刷新计时 10×", "刷新计时 60×"]:
		scale_select.add_item(option)
	scale_select.item_selected.connect(func(index: int): director.time_scale = [1, 10, 60][index])
	add_child(scale_select)
	var hint := Label.new()
	hint.position = Vector2(18, 390)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.text = "K 攻击怪物 · E 拾取/进入Boss门"
	hint.add_theme_font_override("font", font)
	add_child(hint)

func _process(_delta: float) -> void:
	if director == null:
		return
	text_label.text = "生命 %d/%d · %s\n%s" % [
		ceili(health.current), ceili(health.maximum),
		"战斗结束" if health.dead else director.summary(), director.diagnostics]
	queue_redraw()

func _draw() -> void:
	if director == null or not is_instance_valid(director.gate):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var from := camera.unproject_position(director.player.global_position)
	var difference := director.gate.global_position - director.player.global_position
	var direction := Vector2(camera.global_basis.x.dot(difference), -camera.global_basis.y.dot(difference))
	if direction.length() < 0.01:
		return
	direction = direction.normalized()
	var center := from + Vector2(0, -55)
	var tip := center + direction * 28
	var tangent := Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([tip, center - direction * 8 + tangent * 9,
		center - direction * 8 - tangent * 9]), Color("#e8c878"))
