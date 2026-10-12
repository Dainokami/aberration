extends Node3D

# 这些方块只是给部件探针用的标签和种类，不接入地形编辑或关卡数据。


func _ready() -> void:
	_zone(Vector3(-7.0, 1.15, 11.2), Vector3(4.2, 2.3, 3.4), PackedStringArray(["fluid"]), Color(0.93, 0.96, 1.0, 0.33))
	_zone(Vector3(7.2, 1.15, 6.4), Vector3(4.4, 2.3, 4.0), PackedStringArray(["desert", "hard"]), Color(0.98, 0.94, 0.86, 0.3))
	_prop(Vector3(-6.2, 0.0, 6.2), Vector3(1.0, 1.0, 1.0), "pushable", 9)
	_prop(Vector3(-3.4, 0.0, 7.4), Vector3(0.55, 3.1, 0.55), "climbable", 9)
	_prop(Vector3(-5.2, 0.0, 4.6), Vector3(1.15, 1.15, 1.15), "destructible_hard", 28)
	_prop(Vector3(-7.0, 0.0, 11.2), Vector3(1.3, 0.35, 1.3), "destructible_soft", 22)
	_prop(Vector3(-4.0, 0.0, 5.6), Vector3(0.55, 0.7, 0.55), "enemy_small", 20)
	_prop(Vector3(-8.0, 0.0, 7.6), Vector3(0.85, 1.55, 0.85), "enemy_elite", 40)


func _zone(at: Vector3, size: Vector3, tags: PackedStringArray, tint: Color) -> void:
	var zone := SurfaceZone.new()
	zone.position = at
	add_child(zone)
	zone.setup(size, tags, tint)


func _prop(at: Vector3, size: Vector3, kind: String, health: int) -> void:
	var prop := AffordanceProp.new()
	prop.kind = kind
	prop.box_size = size
	prop.max_health = health
	prop.position = at
	add_child(prop)
