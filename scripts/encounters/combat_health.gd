class_name CombatHealth
extends Node

signal changed(current: float, maximum: float)
signal died(cause: String)
var maximum := 100.0
var current := 100.0
var dead := false

func setup(value: float) -> void:
	maximum = value
	current = value
	dead = false
	if get_parent() != null:
		get_parent().set_meta("scene_health", current)
	changed.emit(current, maximum)

func damage(amount: float, cause := "environment") -> void:
	if dead or amount <= 0 or not is_finite(amount):
		return
	current = maxf(0, current - amount)
	get_parent().set_meta("scene_health", current)
	changed.emit(current, maximum)
	if current <= 0:
		dead = true
		died.emit(cause)

static func hurt(actor: Node, amount: float, cause := "environment") -> void:
	if not is_instance_valid(actor):
		return
	if actor.has_method("take_damage"):
		actor.call("take_damage", amount, cause)
		return
	var component := actor.get_node_or_null("CombatHealth") as CombatHealth
	if component != null:
		component.damage(amount, cause)
	else:
		actor.set_meta("scene_health", float(actor.get_meta("scene_health", 100.0)) - amount)
