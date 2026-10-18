class_name LimbField
extends RefCounted

# 正式关卡在出生点前摆完整玩法肢体；旧白盒仍保留蛇身/螳螂骨骼样例，
# 但它们不属于培养矩阵原料。


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
	var layout: Array = []
	var upper_ids := [
		"gorilla_arm", "gibbon_arm", "goose_wing", "octopus_arm",
		"bat_wing", "albatross_wing", "eagle_wing", "gerbil_paw",
	]
	var lower_ids := [
		"wolf_leg", "ostrich_leg", "gerbil_leg", "kangaroo_leg", "demon_dog_leg",
		"octopus_leg", "goose_foot", "water_snake", "fish_tail",
	]
	for index in upper_ids.size():
		layout.append([upper_ids[index], Vector3(-7.0 + index * 2.0, 0.15, -1.8)])
	for index in lower_ids.size():
		layout.append([lower_ids[index], Vector3(-7.0 + index * 2.0, 0.15, -5.4)])
	# 留下两组旧骨骼测试件；培养系统只接受上面的 17 个基础部件。
	layout.append(["snake_body", Vector3(-2.0, 0.15, -7.2)])
	layout.append(["snake_body", Vector3(-0.4, 0.15, -7.2)])
	layout.append(["mantis_arm", Vector3(1.2, 0.15, -7.2)])
	layout.append(["mantis_arm", Vector3(2.8, 0.15, -7.2)])
	_place(parent, origin, layout)


static func _place(parent: Node, origin: Vector3, layout: Array) -> void:
	var pickup_script: Script = load("res://scripts/limbs/limb_pickup.gd")
	for entry: Array in layout:
		var pickup := pickup_script.new() as Node3D
		var offset: Vector3 = entry[1]
		pickup.position = origin + offset
		pickup.call("setup", entry[0])
		parent.add_child(pickup)
