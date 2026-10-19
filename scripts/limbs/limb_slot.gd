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
	# 预览挂到未缩放的根控件上，尺寸用图标的屏幕大小，避免按 3840 舞台放大。
	var preview_size := icon.get_global_rect().size
	if preview_size.x < 8.0 or preview_size.y < 8.0:
		var view := get_viewport().get_visible_rect().size
		var fitted := minf(view.x / 3840.0, view.y / 2160.0)
		preview_size = icon.size * fitted
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = preview_size
	preview.size = preview_size
	preview.texture = icon.texture
	preview.size = preview_size
	preview.modulate = icon.modulate
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Viewport 每帧把预览根节点放到鼠标位置，抓取点偏移必须留在子节点上。
	preview.position = drag_preview_offset(at, size, preview_size)
	holder.add_child(preview)
	set_drag_preview(holder)
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
