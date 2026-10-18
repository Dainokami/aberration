class_name EnemyAffordance
extends AffordanceProp

func take_hit(amount: int) -> bool:
	if spent or not is_instance_valid(host):
		return false
	host.call("take_damage", float(amount), "player")
	health = ceili(host.health.current)
	spent = host.health.dead
	return spent

func _physics_process(_delta: float) -> void:
	if is_instance_valid(host):
		global_position = host.global_position
