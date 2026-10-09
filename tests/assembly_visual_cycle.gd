extends SceneTree

var _assembly: CharacterAssemblyController
var _frame := 0


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_assembly = main.get_node("Player/Assembly")
	_assembly.set_process_unhandled_input(false)
	process_frame.connect(_on_process_frame)


func _on_process_frame() -> void:
	_frame += 1
	if _frame in [4, 8, 12, 16, 20, 24]:
		_assembly.cycle_loadout()
	if _frame >= 28:
		quit(0)
