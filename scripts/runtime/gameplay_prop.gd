class_name GameplayProp
extends Node3D

signal state_changed(value: String)
signal broken(prop: Node3D)
signal opened(prop: Node3D, actor: Node3D)

@export var definition: Resource
var state := "closed"
var health := 1
var instance_id := ""

func _ready() -> void:
	if definition == null or Engine.is_editor_hint():
		return
	health = definition.max_health
	add_to_group("gameplay_props")
	if definition.behaviour == PlaceableDefinition.Behaviour.CLIMBABLE:
		add_to_group("climb_surfaces")
	set_state(state)

func interaction_text() -> String:
	if state == "broken":
		return ""
	match definition.behaviour:
		PlaceableDefinition.Behaviour.CHEST:
			return "E 打开宝箱" if state == "closed" else "已打开"
		PlaceableDefinition.Behaviour.BREAKABLE:
			return "J 破坏岩石（%d/%d）" % [health, definition.max_health]
		PlaceableDefinition.Behaviour.CLIMBABLE:
			return "E 攀爬 · 需要攀爬能力"
	return ""

func interact(actor: Node3D) -> bool:
	if definition.behaviour == PlaceableDefinition.Behaviour.CHEST and state == "closed":
		set_state("open")
		opened.emit(self, actor)
		return true
	return false

func apply_damage(amount: int) -> bool:
	if definition.behaviour != PlaceableDefinition.Behaviour.BREAKABLE or state == "broken" or amount <= 0:
		return false
	health = maxi(0, health - amount)
	if health == 0:
		set_state("broken")
		broken.emit(self)
	return true

func set_state(value: String) -> void:
	state = value
	for child in get_children():
		if child is Node3D and str(child.name).begins_with("State_"):
			child.visible = str(child.name) == "State_" + state
	if state == "broken":
		for child in get_children():
			if child is Node3D:
				child.visible = false
		for shape: CollisionShape3D in find_children("*", "CollisionShape3D", true, false):
			shape.set_deferred("disabled", true)
	state_changed.emit(state)
