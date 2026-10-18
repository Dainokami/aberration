@tool
extends RefCounted

const Picker := preload("res://addons/terrain_editor/surface_picker.gd")
var host: EditorPlugin
var page: VBoxContainer
var config: EncounterConfig
var controls := {}
var pool_rows: VBoxContainer
var region_mode: OptionButton
var brush: OptionButton
var overlay_toggle: CheckButton
var paint_toggle: CheckButton
var selected_monster: OptionButton
var artwork: TextureRect
var description: Label
var overlay: Node3D
var drawing := false
var before_regions := {}
var touched := {}
var syncing := false
var observed_data: LevelData
var observed_config: EncounterConfig

func setup(plugin: EditorPlugin, tabs: TabContainer) -> void:
	host = plugin
	var scroll := ScrollContainer.new()
	scroll.name = "怪物"
	tabs.add_child(scroll)
	page = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", host.ui_px(8))
	scroll.add_child(page)
	var enabled := CheckButton.new()
	enabled.name = "EncounterEnabled"
	enabled.text = "启用本地图怪物刷新"
	enabled.toggled.connect(func(value: bool): _change("enabled", value))
	page.add_child(enabled)
	controls.enabled = enabled
	_label("有效探索时间驱动刷新；静止区只暂停刷新计时，已生成怪物仍行动。")
	_number("seed_value", "刷新种子", 0, 2147483647, 1)
	_number("interval", "普通怪间隔 / 秒", 0.1, 600, 0.1)
	_number("count_min", "每次最少", 1, 20, 1)
	_number("count_max", "每次最多", 1, 20, 1)
	_number("radius_min", "圆环内半径 / 米", 0.5, 100, 0.5)
	_number("radius_max", "圆环外半径 / 米", 0.5, 100, 0.5)
	var personality := CheckButton.new()
	personality.name = "UseSourcePersonality"
	personality.text = "按设计表性格（否则全部主动追踪）"
	personality.toggled.connect(func(value: bool): _change("use_source_personality", value))
	page.add_child(personality)
	controls.use_source_personality = personality
	_label("区域画笔")
	paint_toggle = CheckButton.new()
	paint_toggle.name = "PaintEncounterRegions"
	paint_toggle.text = "绘制区域 · 左键拖动"
	page.add_child(paint_toggle)
	region_mode = OptionButton.new()
	region_mode.name = "EncounterRegionMode"
	for text in ["探索战斗区", "时间静止区", "禁止生成", "恢复默认", "清除禁刷"]:
		region_mode.add_item(text)
	page.add_child(region_mode)
	brush = OptionButton.new()
	brush.name = "EncounterBrush"
	brush.add_item("1×1")
	brush.add_item("3×3")
	page.add_child(brush)
	overlay_toggle = CheckButton.new()
	overlay_toggle.name = "ShowEncounterRegions"
	overlay_toggle.text = "显示区域覆盖"
	overlay_toggle.toggled.connect(func(_value: bool): refresh_overlay())
	page.add_child(overlay_toggle)
	_label("普通怪池 · 缺美术的物种默认不可选")
	selected_monster = OptionButton.new()
	selected_monster.name = "MonsterPreviewChoice"
	for path in EncounterConfig.catalog_paths():
		var monster := load(path) as MonsterDefinition
		selected_monster.add_item(monster.display_name)
		selected_monster.set_item_metadata(selected_monster.item_count-1, path)
	selected_monster.item_selected.connect(func(_index: int): _preview_monster())
	page.add_child(selected_monster)
	artwork = TextureRect.new()
	artwork.custom_minimum_size = Vector2(180, 180)
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	page.add_child(artwork)
	description = _label("")
	var preview := Button.new()
	preview.name = "PreviewEncounterRing"
	preview.text = "检查出生点 9～12m 候选圆环"
	preview.pressed.connect(_preview_ring)
	page.add_child(preview)
	pool_rows = VBoxContainer.new()
	page.add_child(pool_rows)
	_choice("elite_one", "精英1")
	_number("elite_one_time", "精英1出现 / 秒", 1, 7200, 1)
	_ecosystem_choice("elite_one_ecosystems")
	_choice("elite_two", "精英2")
	_number("elite_two_time", "精英2出现 / 秒", 1, 7200, 1)
	_ecosystem_choice("elite_two_ecosystems")
	_number("elite_health_multiplier", "精英生命倍率", 0.1, 20, 0.1)
	_number("elite_damage_multiplier", "精英伤害倍率", 0.1, 20, 0.1)
	_number("boss_early_time", "击杀两精英后 Boss / 秒", 1, 7200, 1)
	_number("boss_force_time", "强制 Boss / 秒", 1, 7200, 1)
	_number("safe_radius", "最终安全半径 / 米", 1, 1000, 1)
	_number("fog_speed", "浓雾收缩 / 米每秒", 0.1, 50, 0.1)
	_number("fog_player_damage", "玩家雾伤害 / 秒", 0, 500, 1)
	_number("fog_monster_damage", "怪物雾伤害 / 秒", 0, 1000, 1)
	_number("player_health", "玩家生命", 1, 10000, 1)
	_label("Boss 目标场景（空白仅验证门和浓雾）")
	var scene := LineEdit.new()
	scene.name = "BossTargetScene"
	scene.placeholder_text = "res://scenes/..."
	scene.text_submitted.connect(func(value: String): _change("boss_scene", value))
	page.add_child(scene)
	controls.boss_scene = scene
	var check := Button.new()
	check.name = "ValidateEncounter"
	check.text = "检查刷新配置"
	check.pressed.connect(func():
		var errors := config.errors()
		host._set_status("刷新配置有效" if errors.is_empty() else "\n".join(errors)))
	page.add_child(check)
	tabs.tab_changed.connect(func(_index: int): finish_stroke(); refresh_overlay())
	sync()

func active() -> bool:
	return host.tabs.get_current_tab_control().name == "怪物"

func sync() -> void:
	if drawing:
		return
	observed_data = host.data
	observed_config = host.data.encounter if host.data != null else null
	config = observed_config if observed_config != null else EncounterConfig.default_config()
	syncing = true
	for field in controls:
		var control: Control = controls[field]
		if control is SpinBox:
			control.value = config.get(field)
		elif control is CheckButton:
			control.set_pressed_no_signal(bool(config.get(field)))
		elif control is LineEdit:
			control.text = ",".join(config.get(field)) if field.ends_with("_ecosystems") \
				else str(config.get(field))
		elif control is OptionButton:
			for i in control.item_count:
				if control.get_item_metadata(i) == config.get(field):
					control.select(i)
	for child in pool_rows.get_children():
		pool_rows.remove_child(child)
		child.queue_free()
	for i in config.monster_pool.size():
		var rule := config.monster_pool[i]
		var monster := config.definition_for(str(rule.path), rule)
		var row := VBoxContainer.new()
		var enabled := CheckBox.new()
		enabled.name = monster.monster_id + "_enabled"
		enabled.text = monster.display_name + ("" if monster.available() else " · 缺美术")
		enabled.disabled = not monster.available()
		enabled.button_pressed = bool(rule.get("enabled", true)) and monster.available()
		enabled.toggled.connect(func(value: bool): _pool_change(i, "enabled", value))
		row.add_child(enabled)
		var weight := SpinBox.new()
		weight.min_value = 0
		weight.max_value = 100
		weight.value = float(rule.get("weight", 1))
		weight.prefix = "权重 "
		weight.value_changed.connect(func(value: float): _pool_change(i, "weight", value))
		row.add_child(weight)
		var ecology := LineEdit.new()
		ecology.name = monster.monster_id + "_ecosystems"
		ecology.text = ",".join(monster.ecosystems)
		ecology.placeholder_text = "grass,rock,desert,ocean"
		ecology.tooltip_text = "本地图允许生成生态；逗号分隔"
		ecology.text_submitted.connect(func(value: String):
			_pool_change(i, "ecosystems", _parse_ecosystems(value)))
		row.add_child(ecology)
		for field in ["max_health", "damage", "speed", "attack_interval"]:
			var spin := SpinBox.new()
			spin.name = monster.monster_id + "_" + field
			spin.min_value = 0.01
			spin.max_value = 10000 if field == "max_health" else 1000
			spin.step = 0.01
			spin.prefix = {"max_health":"生命 ", "damage":"伤害 ", "speed":"移速 ",
				"attack_interval":"攻击间隔 "}[field]
			spin.value = monster.get(field)
			spin.value_changed.connect(func(value: float): _pool_change(i, field, value))
			row.add_child(spin)
		pool_rows.add_child(row)
	syncing = false
	_preview_monster()
	refresh_overlay()

func _number(field: String, label: String, minimum: float, maximum: float, step: float) -> void:
	_label(label)
	var spin := SpinBox.new()
	spin.name = field
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value_changed.connect(func(value: float):
		_change(field, int(value) if field in ["seed_value", "count_min", "count_max"] else value))
	page.add_child(spin)
	controls[field] = spin

func _choice(field: String, title: String) -> void:
	_label(title)
	var choice := OptionButton.new()
	choice.name = field
	for path in EncounterConfig.catalog_paths():
		var monster := load(path) as MonsterDefinition
		if monster.available():
			choice.add_item(monster.display_name)
			choice.set_item_metadata(choice.item_count-1, path)
	choice.item_selected.connect(func(index: int): _change(field, choice.get_item_metadata(index)))
	page.add_child(choice)
	controls[field] = choice

func _ecosystem_choice(field: String) -> void:
	_label("允许生态（空白沿用物种；grass,rock,desert,ocean）")
	var edit := LineEdit.new()
	edit.name = field
	edit.text_submitted.connect(func(value: String): _change(field, _parse_ecosystems(value)))
	page.add_child(edit)
	controls[field] = edit

func _parse_ecosystems(value: String) -> PackedStringArray:
	var result := PackedStringArray()
	for item in value.split(",", false):
		result.append(item.strip_edges())
	return result

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(label)
	return label

func _change(field: String, value: Variant) -> void:
	if syncing or host.data == null:
		return
	var next := config.duplicate(true) as EncounterConfig
	next.set(field, value)
	_commit(next, "设置怪物刷新")

func _pool_change(index: int, field: String, value: Variant) -> void:
	if syncing or host.data == null:
		return
	var next := config.duplicate(true) as EncounterConfig
	next.monster_pool[index][field] = value
	_commit(next, "设置普通怪池")

func _commit(next: EncounterConfig, label: String) -> void:
	var target: LevelData = host.data
	var undo := host.get_undo_redo()
	undo.create_action(label, UndoRedo.MERGE_DISABLE, target)
	undo.add_do_method(self, "_apply_config", target, next)
	undo.add_undo_method(self, "_apply_config", target, target.encounter)
	undo.commit_action()

func _apply_config(target: LevelData, value: EncounterConfig) -> void:
	target.encounter = value
	target.emit_changed()
	if target == host.data:
		host._set_dirty(true)
		sync.call_deferred()

func _preview_monster() -> void:
	if selected_monster.item_count == 0:
		return
	var monster := load(str(selected_monster.get_selected_metadata())) as MonsterDefinition
	artwork.texture = load(monster.image_path) if monster.available() else null
	description.text = "%s · %s\nHP %.0f · 伤害 %.0f · 移速 %.1fm/s\n%s" % [
		monster.display_name, " / ".join(monster.ecosystems), monster.max_health,
		monster.damage, monster.speed, "缺少对应美术" if not monster.available() else monster.attack]

func handle(camera: Camera3D, event: InputEvent) -> int:
	if not active() or not paint_toggle.button_pressed or host.data == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			drawing = true
			before_regions = host.data.encounter_regions.duplicate(true)
			touched.clear()
			_paint_at(camera, event.position)
		else:
			finish_stroke()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and drawing:
		_paint_at(camera, event.position)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _paint_at(camera: Camera3D, position: Vector2) -> void:
	var surface := Picker.pick(host.builder, camera, position)
	if surface.get("kind", "") != "terrain" or not surface.has("cell") \
			or Vector3(surface.get("normal", Vector3.ZERO)).y < 0.7:
		host._set_status("区域只能绘制在真实外露顶面")
		return
	var cell: Vector2i = surface.cell
	var layer := int(surface.layer)
	var half := 1 if brush.selected == 1 else 0
	for y in range(-half, half+1):
		for x in range(-half, half+1):
			var target := cell + Vector2i(x, y)
			var key := EncounterRegions.key(target, layer)
			if touched.has(key) or not host.data.is_surface_exposed(target, layer):
				continue
			touched[key] = true
			EncounterRegions.paint(host.data, target, layer, region_mode.selected)
	refresh_overlay()

func finish_stroke() -> void:
	if not drawing:
		return
	drawing = false
	if host.data == null or before_regions == host.data.encounter_regions:
		return
	var target: LevelData = host.data
	var undo := host.get_undo_redo()
	undo.create_action("绘制怪物区域", UndoRedo.MERGE_DISABLE, target)
	undo.add_do_method(self, "_apply_regions", target, target.encounter_regions.duplicate(true))
	undo.add_undo_method(self, "_apply_regions", target, before_regions.duplicate(true))
	undo.commit_action(false)
	host._set_dirty(true)

func _apply_regions(target: LevelData, values: Dictionary) -> void:
	target.encounter_regions = values.duplicate(true)
	target.emit_changed()
	if target == host.data:
		refresh_overlay()
		host._set_dirty(true)

func refresh_overlay() -> void:
	reset_overlay()
	if host.data == null or not is_instance_valid(host.builder) or not active() \
			or not overlay_toggle.button_pressed:
		return
	overlay = Node3D.new()
	overlay.name = "EncounterRegionOverlay"
	host.builder.add_child(overlay)
	var batches := [[], [], []]
	var level: LevelData = host.data
	for y in level.map_size.y:
		for x in level.map_size.x:
			var cell := level.map_origin + Vector2i(x, y)
			for layer in level.layer_count(cell):
				if not level.is_surface_exposed(cell, layer):
					continue
				if host.builder.slice_layer_limit >= 0 and layer > host.builder.slice_layer_limit:
					continue
				var kind := 2 if EncounterRegions.forbidden(level, cell, layer) \
					else EncounterRegions.zone(level, cell, layer)
				batches[kind].append(level.world_center(cell, layer) + Vector3.UP * 0.08)
	for kind in 3:
		_batch(batches[kind], [Color(0.85, 0.43, 0.33, 0.25),
			Color(0.2, 0.8, 0.7, 0.4), Color(1, 0.1, 0.2, 0.6)][kind])

func _batch(points: Array, color: Color) -> void:
	if points.is_empty():
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * LevelData.CELL_SIZE * 0.95
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = plane
	multi.instance_count = points.size()
	for i in points.size():
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	node.material_override = material
	overlay.add_child(node)

func _preview_ring() -> void:
	if host.data == null:
		return
	var monster := load(str(selected_monster.get_selected_metadata())) as MonsterDefinition
	var nav := EncounterNavigation.new()
	nav.build(host.data, monster)
	var center: Vector3 = host.data.world_center(host.data.spawn_cell, host.data.spawn_layer)
	var candidates := nav.candidates(center, config.radius_min, config.radius_max, monster)
	overlay_toggle.set_pressed_no_signal(true)
	refresh_overlay()
	if overlay == null:
		return
	var points: Array = []
	for id in candidates:
		points.append(nav.graph.get_point_position(id) + Vector3.UP * 0.12)
	_batch(points, Color(0.4, 1, 0.2, 0.7))
	host._set_status("%s · 圆环合法候选 %d；已检查生态、区域、净空、障碍和可达性" % [
		monster.display_name, candidates.size()])

func reset_overlay() -> void:
	if is_instance_valid(overlay):
		overlay.free()
	overlay = null
