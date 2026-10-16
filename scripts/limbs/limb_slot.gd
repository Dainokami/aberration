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


func _get_drag_data(_at: Vector2) -> Variant:
	if str(drag_data.get("id", "")).is_empty():
		return null
	var preview := TextureRect.new()
	preview.texture = icon.texture
	preview.custom_minimum_size = Vector2(120, 120)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = icon.modulate
	set_drag_preview(preview)
	return drag_data


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
