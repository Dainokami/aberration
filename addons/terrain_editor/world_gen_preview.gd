@tool
extends Control

const COLORS := [Color("#719965"), Color("#92929e"), Color("#ceae78"), Color("#447eab")]
var data: LevelData
var mode := 0
var _texture: ImageTexture
var point_editor

func show_map(value: LevelData, selected_mode := 0) -> void:
	data = value
	mode = selected_mode
	if data == null:
		_texture = null
		queue_redraw()
		return
	var image := Image.create(data.map_size.x, data.map_size.y, false, Image.FORMAT_RGB8)
	var zones: PackedByteArray = data.generation.get("zones", PackedByteArray())
	for y in data.map_size.y:
		for x in data.map_size.x:
			var cell := Vector2i(x, y)
			var tile := data.tile_id(cell)
			var index := WorldGenerator.TILES.find(tile)
			var color: Color = COLORS[index] if index >= 0 else Color("#43414c")
			if mode == 1:
				color = Color("#4eada5") if zones[data.index(cell)] == 1 else Color("#b57b61")
			elif mode == 2:
				color = color.darkened(0.55)
			image.set_pixel(x, y, color)
	_texture = ImageTexture.create_from_image(image)
	queue_redraw()

func _map_rect() -> Rect2:
	if data == null:
		return Rect2()
	var scale_value := minf((size.x - 28) / data.map_size.x, (size.y - 28) / data.map_size.y)
	var draw_size := Vector2(data.map_size) * scale_value
	return Rect2((size - draw_size) * 0.5, draw_size)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#202731"))
	if _texture == null:
		draw_string(get_theme_font("font", "Label"), Vector2(24, 40), "设置参数后点击「生成预览」",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#bec9d7"))
		return
	var rect := _map_rect()
	var scale_value := rect.size.x / data.map_size.x
	draw_texture_rect(_texture, rect, false)
	for cell: Vector2i in data.generation.get("roads", []):
		draw_rect(Rect2(rect.position + Vector2(cell) * scale_value,
			Vector2.ONE * maxf(scale_value, 1.0)), Color("#e7d98b"))
	for placement: Dictionary in data.generation.get("placements", []):
		var area: Rect2i = placement.rect
		draw_rect(Rect2(rect.position + Vector2(area.position) * scale_value,
			Vector2(area.size) * scale_value), Color("#f0edf7"), false, 2)
		draw_circle(rect.position + (Vector2(placement.entry) + Vector2.ONE * 0.5) * scale_value,
			3.5, Color("#eac273"))
	var spawn := rect.position + (Vector2(data.spawn_cell) + Vector2.ONE * 0.5) * scale_value
	draw_circle(spawn, 5, Color("#ffffff"))
	draw_arc(spawn, float(data.generation.recipe.spawn_radius) * scale_value,
		0, TAU, 60, Color("#ffffff88"), 1.5)
	for point in data.monster_spawn_points:
		var color := Color("#ffc44a") if point_editor != null and str(point.id) == point_editor.selected_id \
			else Color("#bd80ff")
		for cell: Vector3i in point.cells:
			var area := Rect2(rect.position + Vector2(cell.x, cell.z) * scale_value,
				Vector2.ONE * scale_value)
			draw_rect(area, color)
			draw_rect(area, color.lightened(0.4), false, 1)
		if point_editor != null and str(point.id) == point_editor.selected_id:
			var center := MonsterSpawnPoints.center(data, point)
			var cell_position := Vector2(center.x - data.grid_world_origin.x,
				center.z - data.grid_world_origin.y) / LevelData.CELL_SIZE
			var radius := MonsterSpawnPoints.radius(data, point,
				data.world_center(data.spawn_cell, data.spawn_layer))
			draw_arc(rect.position + cell_position * scale_value,
				radius / LevelData.CELL_SIZE * scale_value, 0, TAU, 96, color, 1.5)

func _gui_input(event: InputEvent) -> void:
	if point_editor != null and data != null and point_editor.data == data:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				point_editor.begin_stroke()
				_paint_point(event.position)
			else:
				point_editor.finish_stroke()
			accept_event()
		elif event is InputEventMouseMotion and point_editor.drawing:
			_paint_point(event.position)
			accept_event()
	if event is InputEventMouseMotion and data != null:
		var rect := _map_rect()
		if rect.has_point(event.position):
			var cell := Vector2i((event.position - rect.position) / rect.size * Vector2(data.map_size))
			var zones: PackedByteArray = data.generation.zones
			tooltip_text = "(%d, %d) · %s · %s" % [cell.x, cell.y,
				data.tile_id(cell), "时间静止区" if zones[data.index(cell)] else "探索战斗区"]
			for placement: Dictionary in data.generation.placements:
				if (placement.rect as Rect2i).has_point(cell):
					tooltip_text += "\n特殊地块：" + str(placement.name)
		else:
			tooltip_text = ""

func _paint_point(position: Vector2) -> void:
	var rect := _map_rect()
	if not rect.has_point(position):
		return
	var cell := Vector2i((position - rect.position) / rect.size * Vector2(data.map_size))
	cell += data.map_origin
	var layer := data.top_layer(cell)
	# The 2D preview picks the upper surface; 3D editing can target lower tunnels.
	point_editor.paint(Vector3i(cell.x, layer, cell.y))
	queue_redraw()
