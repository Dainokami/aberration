extends SceneTree

## 在真场景里跑部件：位移、跳跃、飞行、攻击和交互，不只查表。


func _initialize() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var runner := Runner.new()
	runner.main = main
	root.add_child(runner)


class Runner extends Node:
	var main: Node
	var player: PlayerController
	var parts: PartLoadout
	var notes: Array[String] = []
	var fails: PackedStringArray = PackedStringArray()
	var step := -1
	var t := 0.0
	var mark := Vector3.ZERO
	var wolf_travel := 0.0
	var marked := false
	var taps := 0

	func _physics_process(delta: float) -> void:
		if player == null:
			t += delta
			if t < 0.35:
				return
			player = main.get_node("Player") as PlayerController
			parts = player.parts
			parts.note.connect(_on_note)
			t = 0.0
			step = 0
			_begin()
			return
		t += delta
		_run(delta)
		if t < _limit():
			return
		_judge()
		_release()
		step += 1
		t = 0.0
		marked = false
		if step > 23:
			_finish()
			return
		_begin()

	func _on_note(message: String) -> void:
		notes.append(message)

	func _begin() -> void:
		notes.clear()
		parts.breakthrough = false
		taps = 0
		_release()
		match step:
			0:
				_place(Vector3(2.0, 0.4, 10.0))
				parts.equip("gorilla_arm", "wolf_leg")
			1:
				_place(Vector3(-6.1, 0.45, 11.2))
				parts.equip("gorilla_arm", "wolf_leg")
			2:
				_place(Vector3(2.0, 0.4, 10.0))
				parts.equip("gorilla_arm", "ostrich_leg")
			3:
				_place(Vector3(2.0, 0.4, 10.0))
				parts.equip("goose_wing", "fish_tail")
			4:
				_place(Vector3(-6.1, 0.8, 11.2))
				parts.equip("goose_wing", "fish_tail")
			5:
				_place(Vector3(-6.1, 0.8, 11.2))
				parts.equip("goose_wing", "water_snake")
			6:
				_place(Vector3(2.0, 0.4, 10.0))
				parts.equip("goose_wing", "kangaroo_leg")
			7:
				_place(Vector3(2.0, 0.4, 10.0))
				parts.equip("goose_wing", "gerbil_leg")
			8:
				_revive(_find("enemy_small"))
				_place(_find("enemy_small").global_position + Vector3(0.0, 0.4, 1.6))
				parts.equip("goose_wing", "wolf_leg")
			9:
				_revive(_find("enemy_small"))
				_place(_find("enemy_small").global_position + Vector3(0.0, 0.4, -1.6))
				parts.equip("goose_wing", "wolf_leg")
			10:
				_revive(_find("enemy_small"))
				_place(_find("enemy_small").global_position + Vector3(0.0, 0.4, -1.6))
				parts.equip("octopus_arm", "wolf_leg")
			11:
				_revive(_find("destructible_hard"))
				_place(_find("destructible_hard").global_position + Vector3(0.9, 0.4, 0.0))
				parts.equip("gorilla_arm", "wolf_leg")
			12:
				_revive(_find("destructible_soft"))
				_place(_find("destructible_soft").global_position + Vector3(0.8, 0.5, 0.0))
				parts.equip("gerbil_paw", "wolf_leg")
			13:
				_place(_find("pushable").global_position + Vector3(0.0, 0.4, 1.15))
				parts.equip("gorilla_arm", "wolf_leg")
			14:
				_place(_find("climbable").global_position + Vector3(1.0, 0.4, 0.0))
				parts.equip("gibbon_arm", "wolf_leg")
			15:
				_revive(_find("enemy_small"))
				_place(_find("enemy_small").global_position + Vector3(0.0, 0.4, 1.2))
				parts.equip("octopus_arm", "wolf_leg")
			16:
				_place(Vector3(7.2, 0.5, 6.4))
				parts.equip("octopus_arm", "wolf_leg")
			17:
				_place(Vector3(2.0, 0.4, 10.0))
				parts.equip("octopus_arm", "wolf_leg")
			18:
				_place(Vector3(2.0, 0.4, 10.0))
				parts.equip("eagle_wing", "wolf_leg")
			19:
				_place(Vector3(2.0, 4.0, 10.0))
				player.velocity = Vector3.ZERO
				parts.equip("bat_wing", "wolf_leg")
			20:
				_place(Vector3(2.0, 0.4, 10.0))
				parts.equip("goose_wing", "kangaroo_leg")
				parts.breakthrough = true
			21:
				_place(Vector3(2.0, 4.0, 10.0))
				player.velocity = Vector3.ZERO
				parts.equip("albatross_wing", "wolf_leg")
			22:
				_revive(_find("pushable"))
				_find("pushable").global_position = Vector3(-6.2, 0.0, 6.2)
				_place(Vector3(-6.2, 0.4, 7.3))
				parts.equip("gorilla_arm", "kangaroo_leg")
			23:
				_revive(_find("enemy_small"))
				var enemy := _find("enemy_small")
				enemy.global_position = Vector3(2.0, 0.0, 8.0)
				_place(Vector3(2.0, 5.0, 8.0))
				player.velocity = Vector3.ZERO
				parts.equip("gorilla_arm", "wolf_leg")
				parts.breakthrough = true

	func _run(_delta: float) -> void:
		match step:
			0, 2:
				if t > 0.2:
					Input.action_press("move_forward")
				if t > 0.2 and not marked:
					mark = player.global_position
					marked = true
			1, 3:
				if t > 0.25:
					Input.action_press("move_forward")
				if t > 0.25 and not marked:
					mark = player.global_position
					marked = true
			4:
				if t > 0.2:
					Input.action_press("move_right")
				if t > 0.2 and not marked:
					mark = player.global_position
					marked = true
			5:
				pass
			6:
				_once("air_action", 0.25)
			7:
				pass
			8, 9, 10:
				_once("attack", 0.3)
			11, 12:
				_once("part_interact", 0.3)
			13:
				_once("part_interact", 0.25)
				if t > 0.45:
					Input.action_press("move_forward")
			14:
				_once("part_interact", 0.25)
				if t > 0.45:
					Input.action_press("move_forward")
			15:
				_once("part_interact", 0.25)
				_once("part_interact", 0.7)
			16, 17:
				_once("part_interact", 0.3)
			18:
				_once("air_action", 0.25)
				if t > 0.25:
					Input.action_press("air_action")
			19:
				pass
			20:
				_once("air_action", 0.2)
				if t > 0.3 and t < 0.48:
					Input.action_release("air_action")
				_once("air_action", 0.5)
			21:
				pass
			22:
				_once("part_interact", 0.3)
				_once("air_action", 0.6)
			23:
				pass

	func _limit() -> float:
		match step:
			0, 2:
				return 0.85
			1, 3:
				return 0.8
			4:
				return 0.48
			5:
				return 0.7
			6, 7, 8, 9, 10:
				return 0.55
			11:
				return 1.3
			12:
				return 1.0
			13, 14:
				return 1.05
			15:
				return 1.15
			16, 17:
				return 0.6
			18:
				return 0.9
			19:
				return 0.45
			20:
				return 0.62
			21:
				return 0.5
			22:
				return 0.95
			23:
				return 1.35
		return 0.5

	func _judge() -> void:
		var moved := 0.0
		if marked:
			moved = Vector2(player.global_position.x - mark.x, player.global_position.z - mark.z).length()
		match step:
			0:
				wolf_travel = moved
				_expect(moved > 1.4, "狼腿在硬地面应往前走，实际 %.2f" % moved)
			1:
				_expect(moved < 0.35, "狼腿在流体里不该移动，实际 %.2f" % moved)
			2:
				_expect(moved > wolf_travel + 0.6, "鸵鸟腿应比狼腿更快，狼 %.2f 鸵鸟 %.2f" % [wolf_travel, moved])
			3:
				_expect(moved < 0.35, "鱼尾在硬地面不该移动，实际 %.2f" % moved)
			4:
				var fish_moved := player.global_position.x - mark.x if marked else player.global_position.x + 6.1
				_expect(fish_moved > 0.7, "鱼尾在流体里应游起来，位移 %.2f" % fish_moved)
				_expect(player.global_position.y > 0.35, "鱼尾在流体里应悬浮，高度 %.2f" % player.global_position.y)
			5:
				_expect(player.global_position.y < 0.35, "水蛇静止时应下沉，高度 %.2f" % player.global_position.y)
			6:
				_expect(player.global_position.y > 0.7, "袋鼠腿应按空格跳起来，高度 %.2f" % player.global_position.y)
			7:
				var capsule := player.collision.shape as CapsuleShape3D
				_expect(parts.is_burrowed(), "沙鼠腿在硬表面应处于遁地")
				_expect(capsule != null and capsule.height <= 1.05, "遁地碰撞应变矮，高度 %.2f" % (capsule.height if capsule else -1.0))
			8:
				_expect(_find("enemy_small").health < 20, "朝向攻击应打到面前的小怪，剩余 %d" % _find("enemy_small").health)
			9:
				_expect(_find("enemy_small").health < 20, "360度锁定应打到范围内身后的可见目标，剩余 %d" % _find("enemy_small").health)
			10:
				_expect(_find("enemy_small").health < 20, "触手周围攻击应打到身后，剩余 %d" % _find("enemy_small").health)
			11:
				_expect(_find("destructible_hard").spent, "猩猩臂应按 G 砸碎硬物件")
			12:
				_expect(_find("destructible_soft").spent, "沙鼠前肢在流体里应按 G 挖开软物件")
			13:
				var box := _find("pushable")
				var carried := box.global_position.distance_to(Vector3(-6.2, 0.0, 6.2))
				_expect(carried > 0.7, "推拉后箱子应跟着走，移动 %.2f，备注 %s" % [carried, ", ".join(notes)])
			14:
				_expect(player.global_position.y > 1.0, "长臂猿抓住后应向上爬，高度 %.2f，备注 %s" % [player.global_position.y, ", ".join(notes)])
			15:
				_expect(_find("enemy_small").ballistic, "触手应把小怪抛出去")
			16:
				_expect(not parts._stuck, "沙漠上章鱼触手不该吸附住")
				var refused := false
				for message in notes:
					if message.contains("吸不住"):
						refused = true
				_expect(refused, "沙漠上应提示吸不住，实际 %s" % [", ".join(notes)])
			17:
				_expect(parts._stuck, "硬表面上章鱼触手应按 G 吸附，备注 %s" % [", ".join(notes)])
			18:
				_expect(player.global_position.y > 1.6, "鹰翅膀应按住空格飞起来，高度 %.2f" % player.global_position.y)
			19:
				_expect(player.global_position.y > 3.1, "蝙蝠翅膀离地后应短滑行而不是直掉，高度 %.2f" % player.global_position.y)
			20:
				_expect(player.velocity.y > 3.0, "突破后袋鼠腿应能二段跳，竖直速度 %.2f" % player.velocity.y)
			21:
				_expect(player.global_position.y > 3.4, "信天翁翅膀离地后应悬停，高度 %.2f" % player.global_position.y)
			22:
				_expect(_find("pushable").global_position.y > 0.7, "举起后跳跃，箱子高度 %.2f" % _find("pushable").global_position.y)
			23:
				_expect(_find("enemy_small").health < 20, "高处落地应砸到下面的小怪，剩余 %d，备注 %s" % [_find("enemy_small").health, ", ".join(notes)])

	func _place(at: Vector3) -> void:
		player.global_position = at
		player.velocity = Vector3.ZERO

	func _once(action: String, at: float) -> void:
		if t < at:
			return
		var slot := int(at * 10.0)
		if taps >= slot:
			return
		taps = slot
		_tap(action)


	func _tap(action: String) -> void:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = true
		Input.parse_input_event(event)

	func _release() -> void:
		for action in ["move_forward", "move_back", "move_left", "move_right", "air_action", "part_interact", "attack"]:
			Input.action_release(action)

	func _find(kind: String) -> AffordanceProp:
		for node in get_tree().get_nodes_in_group("affordance"):
			var prop := node as AffordanceProp
			if prop != null and prop.kind == kind:
				return prop
		return null

	func _revive(prop: AffordanceProp) -> void:
		prop.spent = false
		prop.visible = true
		prop.health = prop.max_health
		prop.collision_layer = 1
		prop.ballistic = false
		prop.throw_velocity = Vector3.ZERO

	func _expect(ok: bool, message: String) -> void:
		print(("OK  " if ok else "FAIL ") + message)
		if not ok:
			fails.append(message)

	func _finish() -> void:
		print("PLAYTEST %d failed" % fails.size())
		if fails.is_empty():
			print("PART_PLAYTEST: PASS")
			get_tree().quit(0)
		else:
			print("PART_PLAYTEST: FAIL")
			get_tree().quit(1)
