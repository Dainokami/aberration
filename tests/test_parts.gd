extends SceneTree

var _main: Node


func _initialize() -> void:
	var uppers := PartCatalog.uppers()
	var lowers := PartCatalog.lowers()
	if uppers.size() != 8 or lowers.size() != 9:
		_fail("catalog size %d %d" % [uppers.size(), lowers.size()])
		return
	var loadout := PartLoadout.new()
	root.add_child(loadout)
	loadout.equip("wolf_leg", "fish_tail")
	# equip 参数是上肢、下肢。狼腿是下肢，这里故意对调应落回 0。
	loadout.equip("gorilla_arm", "wolf_leg")
	if loadout.speed_on(PackedStringArray(["hard"])) != PartDefinition.speed_value(PartDefinition.Band.NORMAL):
		_fail("wolf should be medium on hard")
		return
	if loadout.speed_on(PackedStringArray(["fluid"])) != 0.0:
		_fail("wolf should not move in fluid")
		return
	loadout.equip("goose_wing", "fish_tail")
	if loadout.speed_on(PackedStringArray(["hard"])) != 0.0:
		_fail("fish should stop on hard ground")
		return
	if loadout.speed_on(PackedStringArray(["fluid"])) != PartDefinition.speed_value(PartDefinition.Band.HIGH):
		_fail("fish should be fast in fluid")
		return
	loadout.equip("octopus_arm", "wolf_leg")
	if loadout.can_stick_on(PackedStringArray(["desert", "hard"])):
		_fail("octopus arm should refuse desert")
		return
	if not loadout.can_stick_on(PackedStringArray(["hard"])):
		_fail("octopus arm should stick to hard ground")
		return
	loadout.equip("gorilla_arm", "kangaroo_leg")
	if loadout.jump_count() != 1:
		_fail("kangaroo basic jump")
		return
	loadout.breakthrough = true
	if loadout.jump_count() != 2 or not loadout.current_lower().has_ability("smash_near", true):
		_fail("kangaroo breakthrough")
		return
	loadout.breakthrough = false
	loadout.equip("eagle_wing", "demon_dog_leg")
	if loadout.current_upper().air_mode != "flight":
		_fail("eagle should replace jump with flight")
		return
	if loadout.current_upper().has_ability("dive", false):
		_fail("dive is breakthrough only")
		return
	if not is_equal_approx(loadout.speed_on(PackedStringArray(["hard"])), PartDefinition.speed_value(PartDefinition.Band.HIGH)):
		_fail("demon dog should sprint on grass")
		return
	if loadout.current_upper().has_ability("dive", true) == false:
		_fail("dive should exist once breakthrough is on")
		return
	var zone := SurfaceZone.new()
	zone.position = Vector3(3, 1, 0)
	zone.setup(Vector3(2, 2, 2), PackedStringArray(["fluid"]), Color(1, 1, 1, 0.2))
	if not zone.covers(Vector3(3, 1, 0)) or zone.covers(Vector3(8, 1, 0)):
		_fail("surface zone bounds")
		return
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	process_frame.connect(_finish, CONNECT_ONE_SHOT)


func _finish() -> void:
	var player := _main.get_node("Player") as PlayerController
	if player.parts == null or player.parts.current_upper().id != "gorilla_arm":
		_fail("player did not start with the gorilla arm")
		return
	var fluid := SceneProbe.tags_at(Vector3(-7.0, 1.15, 11.2))
	if not fluid.has("fluid"):
		_fail("play range fluid tag %s" % [str(fluid)])
		return
	if not SceneProbe.tags_at(player.global_position).has("hard"):
		_fail("open ground should stay hard")
		return
	print("PARTS_TEST: PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("PARTS_TEST: " + message)
	print("PARTS_TEST: FAIL " + message)
	quit(1)
