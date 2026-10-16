@tool
extends HBoxContainer

signal item_selected(value: int)

var buttons: Dictionary = {}
var group := ButtonGroup.new()
var selected := 0:
	set(value):
		if selected == value:
			return
		selected = value
		_sync()
		item_selected.emit(value)

func add_mode(title: String, value: int) -> void:
	var button := Button.new()
	button.text = title
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func(): selected = value)
	buttons[value] = button
	add_child(button)
	_sync()

func _sync() -> void:
	for value in buttons:
		buttons[value].set_pressed_no_signal(value == selected)
