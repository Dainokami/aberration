class_name LimbSlot
extends Control

signal item_dropped(data: Dictionary)
signal recycle_requested

var drag_data: Dictionary = {}
var icon: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	icon = TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 10
	icon.offset_top = 10
	icon.offset_right = -10
	icon.offset_bottom = -10
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(icon)


func _get_drag_data(at: Vector2) -> Variant:
	if str(drag_data.get("id", "")).is_empty():
		return null
	var preview := TextureRect.new()
	preview.texture = icon.texture
	var preview_size := Vector2(120, 120)
	preview.custom_minimum_size = preview_size
	preview.size = preview_size
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = icon.modulate
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 拖拽预览属于 Viewport，不继承 3840×2160 舞台的缩放。按抓取点比例
	# 把预览移到鼠标下，否则在不同分辨率下图标会固定偏到鼠标右下方。
	preview.position = drag_preview_offset(at, size, preview_size)
	set_drag_preview(preview)
	return drag_data


static func drag_preview_offset(grab_at: Vector2, source_size: Vector2, preview_size: Vector2) -> Vector2:
	var ratio := Vector2(
		clampf(grab_at.x / maxf(source_size.x, 1.0), 0.0, 1.0),
		clampf(grab_at.y / maxf(source_size.y, 1.0), 0.0, 1.0)
	)
	return -preview_size * ratio


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary


func _drop_data(_at: Vector2, data: Variant) -> void:
	item_dropped.emit(data)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT and not str(drag_data.get("id", "")).is_empty():
			recycle_requested.emit()
			accept_event()
