class_name LimbField
extends RefCounted

# 出生点前摆两排，方便先捡蛇身和螳螂臂。


static func scatter(parent: Node) -> void:
	_place(parent, Vector3.ZERO, [
		["snake_body", Vector3(-3.2, 0.2, 7.4)],
		["snake_body", Vector3(-1.2, 0.2, 6.6)],
		["snake_body", Vector3(0.8, 0.2, 6.2)],
		["mantis_arm", Vector3(2.6, 0.2, 6.6)],
		["mantis_arm", Vector3(4.4, 0.2, 7.4)],
		["mantis_arm", Vector3(5.6, 0.2, 8.6)],
	])


static func scatter_ahead(parent: Node, origin: Vector3) -> void:
	_place(parent, origin, [
		["snake_body", Vector3(-2.4, 0.15, -2.8)],
		["snake_body", Vector3(-0.4, 0.15, -3.6)],
		["snake_body", Vector3(1.6, 0.15, -2.8)],
		["mantis_arm", Vector3(-2.4, 0.15, -4.6)],
		["mantis_arm", Vector3(0.6, 0.15, -4.8)],
		["mantis_arm", Vector3(2.6, 0.15, -3.8)],
	])


static func _place(parent: Node, origin: Vector3, layout: Array) -> void:
	var pickup_script: Script = load("res://scripts/limbs/limb_pickup.gd")
	for entry: Array in layout:
		var pickup := pickup_script.new() as Node3D
		var offset: Vector3 = entry[1]
		pickup.position = origin + offset
		parent.add_child(pickup)
		pickup.call("setup", entry[0])
