class_name MonsterActor
extends CharacterBody3D

signal defeated(actor: MonsterActor, cause: String)
var definition: MonsterDefinition
var target: Node3D
var navigation: EncounterNavigation
var health: CombatHealth
var visual: MonsterVisual
var elite_index := -1
var passive := false
var provoked := false
var path := PackedVector3Array()
var path_index := 0
var cooldown := 0.0
var windup_left := -1.0
var hurt_left := 0.0
var attack_damage := 14.0
var hp_label: Label3D
var adapter: EnemyAffordance

func setup(monster: MonsterDefinition, player: Node3D, nav: EncounterNavigation,
		elite: int, config: EncounterConfig) -> void:
	definition = monster
	target = player
	navigation = nav
	elite_index = elite
	passive = config.use_source_personality and not monster.source_aggressive
	attack_damage = monster.damage * (config.elite_damage_multiplier if elite >= 0 else 1.0)
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.6
	var shape_node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = monster.body_radius
	shape.height = maxf(monster.body_height, shape.radius * 2)
	shape_node.shape = shape
	shape_node.position.y = shape.height * 0.5
	add_child(shape_node)
	health = CombatHealth.new()
	health.name = "CombatHealth"
	add_child(health)
	health.setup(monster.max_health * (config.elite_health_multiplier if elite >= 0 else 1.0))
	health.died.connect(_die)
	visual = MonsterVisual.new()
	visual.name = "Art"
	add_child(visual)
	visual.setup(monster)
	hp_label = Label3D.new()
	hp_label.name = "HealthLabel"
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.font = load("res://scripts/runtime/level_playtest.gd").runtime_font()
	hp_label.font_size = 40
	hp_label.pixel_size = 0.007
	hp_label.position.y = monster.image_height + 0.3
	add_child(hp_label)
	health.changed.connect(func(_current: float, _maximum: float): _update_label())
	_update_label()
	adapter = EnemyAffordance.new()
	adapter.configure_host(self, "enemy_elite" if elite >= 0 else "enemy_small", ceili(health.maximum))
	add_child(adapter)
	add_to_group("enemies")

func _update_label() -> void:
	if hp_label != null:
		hp_label.text = "%s%s  %d/%d" % [definition.display_name,
			"·精英%d" % (elite_index + 1) if elite_index >= 0 else "",
			ceili(health.current), ceili(health.maximum)]

func repath() -> void:
	if health.dead or not is_instance_valid(target):
		return
	path = navigation.path(global_position, target.global_position)
	path_index = 1 if path.size() > 1 else 0

func take_damage(amount: float, cause := "environment") -> void:
	provoked = provoked or cause == "player"
	hurt_left = 0.15
	health.damage(amount, cause)

func _die(cause: String) -> void:
	collision_layer = 0
	adapter.spent = true
	defeated.emit(self, cause)
	queue_free()

func _physics_process(delta: float) -> void:
	if health == null or health.dead or not is_instance_valid(target):
		return
	hurt_left = maxf(0, hurt_left - delta)
	cooldown = maxf(0, cooldown - delta)
	var difference := target.global_position - global_position
	var in_reach := Vector2(difference.x, difference.z).length() <= definition.attack_reach \
		and absf(difference.y) < definition.body_height + 1
	var chase := not passive or provoked
	if windup_left >= 0:
		windup_left -= delta
		velocity.x = 0
		velocity.z = 0
		if windup_left <= 0:
			windup_left = -1
			if in_reach and _line_clear():
				if definition.attack == "stone":
					_throw_stone()
				else:
					CombatHealth.hurt(target, attack_damage, "monster")
			cooldown = definition.attack_interval
	elif chase and in_reach and cooldown <= 0 and _line_clear():
		windup_left = definition.windup
		velocity.x = 0
		velocity.z = 0
	elif chase and path_index < path.size():
		var point := path[path_index]
		var offset := point - global_position
		if Vector2(offset.x, offset.z).length() < 0.16:
			path_index += 1
		else:
			var remaining := Vector2(offset.x, offset.z).length()
			var flat := Vector3(offset.x, 0, offset.z).normalized() \
				* minf(definition.speed, remaining / maxf(delta, 0.0001))
			velocity.x = flat.x
			velocity.z = flat.z
			if definition.movement in ["air", "amphibious", "aquatic"]:
				velocity.y = clampf(offset.y * 8, -definition.speed, definition.speed)
			else:
				velocity.y = clampf(offset.y * 8, -8, 6)
	else:
		velocity.x = 0
		velocity.z = 0
		if definition.movement == "land":
			velocity.y = -2.0
	move_and_slide()
	var camera := get_viewport().get_camera_3d()
	if camera != null and absf(camera.global_basis.x.dot(velocity)) > 0.05:
		visual.facing_left = camera.global_basis.x.dot(velocity) < 0
	visual.animate(delta, velocity.length_squared() > 0.1,
		1.0 - windup_left / definition.windup if windup_left >= 0 else 0.0, hurt_left > 0)

func _line_clear() -> bool:
	var origin := global_position + Vector3.UP * definition.body_height * 0.65
	var query := PhysicsRayQueryParameters3D.create(origin, target.global_position, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _throw_stone() -> void:
	var projectile := MonsterProjectile.new()
	projectile.position = global_position + Vector3.UP
	projectile.target = target
	projectile.damage = attack_damage
	projectile.direction = (target.global_position - projectile.position).normalized()
	get_parent().add_child(projectile)
