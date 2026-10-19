class_name EncounterHUD
extends Control

var director: EncounterDirector
var text_label: Label
var health: CombatHealth

func setup(value: EncounterDirector, component: CombatHealth, font: Font,
		text_offset := 0.0) -> void:
	director = value
	health = component
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text_label = Label.new()
	text_label.position = Vector2(18, 205 + text_offset)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.add_theme_font_override("font", font)
	add_child(text_label)
	var scale_select := OptionButton.new()
	scale_select.name = "EncounterTimeScale"
	scale_select.position = Vector2(18, 350 + text_offset)
	scale_select.add_theme_font_override("font", font)
	for option in ["刷新计时 1×", "刷新计时 10×", "刷新计时 60×"]:
		scale_select.add_item(option)
	scale_select.item_selected.connect(func(index: int): director.time_scale = [1, 10, 60][index])
	add_child(scale_select)
	var hint := Label.new()
	hint.position = Vector2(18, 390 + text_offset)
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
	if director == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	if not is_instance_valid(director.gate):
		_draw_spawn_cues(camera)
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

func _draw_spawn_cues(camera: Camera3D) -> void:
	var screen := Rect2(Vector2.ZERO, size).grow(-55)
	var shown := 0
	for point in director.data.monster_spawn_points:
		if not director.point_active(point) or director.point_alive(str(point.id)) == 0:
			continue
		var target := MonsterSpawnPoints.center(director.data, point)
		if not camera.is_position_behind(target) and screen.has_point(camera.unproject_position(target)):
			continue
		var difference := target - director.player.global_position
		var direction := Vector2(camera.global_basis.x.dot(difference), -camera.global_basis.y.dot(difference)).normalized()
		if direction.length_squared() < 0.01:
			continue
		var half := screen.size * 0.5
		var reach := minf(half.x / maxf(absf(direction.x), 0.001),
			half.y / maxf(absf(direction.y), 0.001))
		var center := size * 0.5 + direction * (reach - 15)
		var tangent := Vector2(-direction.y, direction.x)
		draw_colored_polygon(PackedVector2Array([center + direction * 14,
			center - direction * 6 + tangent * 6, center - direction * 6 - tangent * 6]),
			Color("#c795f5"))
		var label_at := center - direction * 32 - Vector2(28, 0)
		draw_string(text_label.get_theme_font("font"), label_at, "怪物动静",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#d9bbf7"))
		shown += 1
		if shown >= 3:
			break
