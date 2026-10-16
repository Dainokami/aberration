extends SceneTree

var _root: Node
var _frames := 0
var _step := 0
var _player: PlayerController
var _rig: ModularCharacterRig


func _initialize() -> void:
	_root = (load("res://scenes/level_playtest.tscn") as PackedScene).instantiate()
	root.add_child(_root)
	process_frame.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames < 4:
		return
	if _player == null:
		_player = _root.get_node("Player") as PlayerController
		_rig = _player.get_node("ArtRoot/PartSockets") as ModularCharacterRig
	match _step:
		0:
			_expect_upper("gorilla_arm")
			if _step < 0:
				return
			_expect_lower("wolf_leg")
			if _step < 0:
				return
			_step = 1
			_tap("cycle_upper_part")
		1:
			_expect_upper("gibbon_arm")
			_step = 2
			_tap("cycle_upper_part")
		2:
			_expect_upper("goose_wing")
			_step = 3
			_tap("cycle_upper_part")
		3:
			_expect_upper("octopus_arm")
			_step = 4
			_tap("cycle_upper_part")
		4:
			_expect_upper("bat_wing")
			_step = 5
			_tap("cycle_upper_part")
		5:
			_expect_upper("albatross_wing")
			_step = 6
			_tap("cycle_upper_part")
		6:
			_expect_upper("eagle_wing")
			_step = 7
			_tap("cycle_upper_part")
		7:
			_expect_upper("gerbil_paw")
			_step = 8
			_tap("cycle_upper_part")
		8:
			_expect_upper("gorilla_arm")
			_step = 9
			_tap("cycle_lower_part")
		9:
			_expect_lower("ostrich_leg")
			_step = 10
			_tap("cycle_lower_part")
		10:
			_expect_lower("gerbil_leg")
			_step = 11
			_tap("cycle_lower_part")
		11:
			_expect_lower("kangaroo_leg")
			_step = 12
			_tap("cycle_lower_part")
		12:
			_expect_lower("demon_dog_leg")
			_step = 13
			_tap("cycle_lower_part")
		13:
			_expect_lower("octopus_leg")
			_step = 14
			_tap("cycle_lower_part")
		14:
			_expect_lower("goose_foot")
			_step = 15
			_tap("cycle_lower_part")
		15:
			_expect_lower("water_snake")
			_step = 16
			_tap("cycle_lower_part")
		16:
			_expect_lower("fish_tail")
			_step = 17
			_tap("cycle_lower_part")
		17:
			_expect_lower("wolf_leg")
			_step = 18
			var bag := _player.get_node("LimbBag") as LimbBag
			bag.try_add("mantis_arm")
			bag.move_bag_to_equip(bag.slots.find("mantis_arm"), "upper")
			if not _on("AnimScytheBlade") or _on("AnimArmUpper"):
				_fail("installed mantis should show the scythe before the key")
				return
			_tap("cycle_upper_part")
		18:
			if _player.parts.current_upper().id != "gibbon_arm":
				_fail("key after mantis should select gibbon, got %s" % _player.parts.current_upper().id)
				return
			if _on("AnimScytheBlade") or not _on("HopArmSocket") or _on("AnimArmUpper"):
				_fail("key after mantis still shows the wrong upper limb")
				return
			var bag := _player.get_node("LimbBag") as LimbBag
			if bag.equipped_upper != "" or not bag.slots.has("mantis_arm"):
				_fail("the key should put the installed mantis back in the bag")
				return
			print("LIMB_SWITCH: PASS")
			quit(0)


func _tap(action: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _expect_upper(part_id: String) -> void:
	if _player.parts.current_upper().id != part_id:
		_fail("upper id %s, expected %s" % [_player.parts.current_upper().id, part_id])
		return
	var ok := true
	match part_id:
		"gorilla_arm":
			ok = _on("AnimArmUpper") and _on("AnimArmFore") and not _on("HopArmSocket") and not _on("LeftWingSocket") and not _on("AnimScytheBlade") and not _on("CrawlLeftSocket")
		"gibbon_arm":
			ok = _on("HopArmSocket") and not _on("AnimArmUpper") and not _on("LeftWingSocket") and is_equal_approx(_scale("HopArmSocket"), 1.0)
		"gerbil_paw":
			ok = _on("HopArmSocket") and not _on("AnimArmUpper") and is_equal_approx(_scale("HopArmSocket"), 0.55)
		"octopus_arm":
			ok = _on("CrawlLeftSocket") and _on("CrawlRightSocket") and not _on("AnimArmUpper") and not _on("HopArmSocket") and not _on("LeftWingSocket")
		"goose_wing", "bat_wing", "albatross_wing", "eagle_wing":
			ok = _on("LeftWingSocket") and _on("RightWingSocket") and not _on("AnimArmUpper") and not _on("HopArmSocket")
	if part_id == "goose_wing" and not _tint("LeftWingSocket").is_equal_approx(Color(0.92, 0.92, 0.9)):
		ok = false
	if part_id == "bat_wing" and not _tint("LeftWingSocket").is_equal_approx(Color(0.35, 0.32, 0.4)):
		ok = false
	if part_id == "eagle_wing" and not _tint("LeftWingSocket").is_equal_approx(Color(0.62, 0.42, 0.22)):
		ok = false
	if not ok:
		_fail("upper %s drew the wrong sockets" % part_id)


func _expect_lower(part_id: String) -> void:
	if _player.parts.current_lower().id != part_id:
		_fail("lower id %s, expected %s" % [_player.parts.current_lower().id, part_id])
		return
	var ok := true
	match part_id:
		"wolf_leg":
			ok = _on("LeftLegSocket") and _on("RightLegSocket") and not _on("AnimTail") and is_equal_approx(_scale("LeftLegSocket"), 1.0)
		"ostrich_leg":
			ok = _on("LeftLegSocket") and not _on("AnimTail") and is_equal_approx(_scale("LeftLegSocket"), 1.25)
		"gerbil_leg":
			ok = _on("LeftLegSocket") and is_equal_approx(_scale("LeftLegSocket"), 0.62)
		"kangaroo_leg":
			ok = _on("LeftLegSocket") and is_equal_approx(_scale("LeftLegSocket"), 1.15)
		"demon_dog_leg":
			ok = _on("LeftLegSocket") and not _on("AnimTail") and _tint("LeftLegSocket").is_equal_approx(Color(0.45, 0.18, 0.18))
		"octopus_leg":
			ok = _on("LeftLegSocket") and _tint("LeftLegSocket").is_equal_approx(Color(0.4, 0.48, 0.78))
		"goose_foot":
			ok = _on("LeftLegSocket") and not _on("AnimTail") and is_equal_approx(_scale("LeftLegSocket"), 1.35)
		"water_snake":
			ok = _on("AnimTail") and not _on("LeftLegSocket") and _tint("AnimTail").is_equal_approx(Color.WHITE)
		"fish_tail":
			ok = _on("AnimTail") and not _on("LeftLegSocket") and _tint("AnimTail").is_equal_approx(Color(0.35, 0.75, 0.95))
	if not ok:
		_fail("lower %s drew the wrong sockets" % part_id)


func _on(socket_name: String) -> bool:
	return _rig._attachments[socket_name].visible


func _scale(socket_name: String) -> float:
	return _rig._sprites[socket_name].scale.x


func _tint(socket_name: String) -> Color:
	return _rig._sprites[socket_name].modulate


func _fail(message: String) -> void:
	push_error("LIMB_SWITCH: " + message)
	print("LIMB_SWITCH: FAIL " + message)
	_step = -1
	quit(1)
