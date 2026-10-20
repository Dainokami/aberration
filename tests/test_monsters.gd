extends SceneTree

const MonsterTable := preload("res://scripts/monsters/monster_table.gd")
const FieldMonster := preload("res://scripts/monsters/field_monster.gd")


func _initialize() -> void:
	if not is_equal_approx(MonsterTable.band("speed", "mid"), 6.0):
		_fail("mid speed should match the player")
		return
	var wolf := MonsterTable.monster("prairie_wolf")
	var ostrich := MonsterTable.monster("ostrich")
	var boss := MonsterTable.monster("bird_demon")
	var hero := MonsterTable.player()
	if wolf.is_empty() or not wolf.aggressive or wolf.drop != "wolf_leg" or int(wolf.health) != 40 or int(wolf.damage) != 14 or not is_equal_approx(float(wolf.windup), 0.35):
		_fail("wolf row")
		return
	if int(MonsterTable.monster("eagle").health) != 40 or int(MonsterTable.monster("eagle").damage) != 22:
		_fail("eagle combat")
		return
	if int(MonsterTable.monster("gorilla").health) != 80 or not is_equal_approx(float(MonsterTable.monster("albatross").speed), 5.6):
		_fail("gorilla or albatross combat")
		return
	if int(MonsterTable.monster("gerbil").health) != 20 or int(MonsterTable.monster("gerbil").damage) != 8:
		_fail("gerbil combat")
		return
	if int(hero.get("health", 0)) != 100 or not is_equal_approx(float(hero.get("speed", 0.0)), 5.0) or not is_equal_approx(float(hero.get("attack_cooldown", 0.0)), 0.62):
		_fail("player combat")
		return
	if ostrich.aggressive or not is_equal_approx(float(ostrich.speed), 8.4):
		_fail("ostrich should be passive and fast")
		return
	if int(MonsterTable.monster("gerbil").pack) != 3 or int(MonsterTable.monster("demon_dog").health) != 16:
		_fail("pack or demon dog health")
		return
	if not boss.boss or int(boss.damage) != 16:
		_fail("bird demon")
		return
	var field := MonsterTable.field_ids()
	if field.has("kangaroo") or field.has("bird_demon") or field.has("bat") or field.has("prairie_wolf") or field.has("ibex") or not field.has("ostrich") or not field.has("gorilla"):
		_fail("field roster %s" % field)
		return
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	floor_shape.shape = box
	floor_shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as PlayerController
	player.position = Vector3(0, 1, 0)
	root.add_child(player)
	player.set_physics_process(false)
	var wolf_node := FieldMonster.new() as CharacterBody3D
	wolf_node.call("setup", "prairie_wolf", Vector3(1.2, 1, 0))
	root.add_child(wolf_node)
	var bird := FieldMonster.new() as CharacterBody3D
	bird.call("setup", "ostrich", Vector3(-6, 1, 0))
	root.add_child(bird)
	var before := player.health
	for _step in 90:
		await physics_frame
	if player.health >= before:
		_fail("wolf did not bite, health %s" % player.health)
		return
	var affordance := wolf_node.get_node_or_null("AffordanceProp") as AffordanceProp
	if affordance == null:
		for child in wolf_node.get_children():
			if child is AffordanceProp:
				affordance = child
	if affordance == null:
		_fail("wolf has no affordance")
		return
	affordance.health = 1
	affordance.take_hit(5)
	for _step in 8:
		await physics_frame
	var after_wolf := player.health
	for _step in 20:
		await physics_frame
	if player.health != after_wolf and player.health != player.max_health:
		_fail("ostrich should not attack")
		return
	var dropped := false
	for node in root.get_children():
		if node.is_in_group("limb_pickup") and node.get("limb_id") == "wolf_leg":
			dropped = true
	if not dropped:
		_fail("wolf should drop its leg")
		return
	var sprite := bird.get_node_or_null("Sprite3D") as Sprite3D
	if sprite == null or sprite.hframes != 8 or sprite.texture == null or not sprite.texture.resource_path.ends_with("ostrich/walk.png"):
		_fail("ostrich is not using the mechanical walk sheet")
		return
	if sprite == null:
		for child in bird.get_children():
			if child is Sprite3D:
				sprite = child
	bird.velocity = Vector3(-4, 0, 0)
	bird.call("_face", Vector3(-4, 0, 0))
	if sprite == null or sprite.flip_h:
		_fail("walking screen-left should keep the side-view head forward")
		return
	bird.call("_face", Vector3(4, 0, 0))
	if not sprite.flip_h:
		_fail("walking screen-right should mirror")
		return
	print("MONSTERS PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print("MONSTERS FAIL: " + message)
	quit(1)
