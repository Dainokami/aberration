extends SceneTree


func _initialize() -> void:
	if LimbCatalog.combine("snake_body", "snake_body", 0.5) != "python_body":
		_fail("two snakes should become a python")
		return
	if LimbCatalog.combine("snake_body", "snake_body", 0.0) != "crowned_snake":
		_fail("two snakes should rarely become a crowned snake")
		return
	if LimbCatalog.combine("mantis_arm", "mantis_arm", 0.5) != "mantis_blade":
		_fail("two mantis arms should become a greater scythe")
		return
	if LimbCatalog.combine("mantis_arm", "mantis_arm", 0.0) != "mantis_king":
		_fail("two mantis arms should rarely become a king arm")
		return
	if LimbCatalog.combine("snake_body", "mantis_arm", 0.0) != "scrap":
		_fail("unrelated limbs should become scrap")
		return
	if LimbCatalog.combine("python_body", "python_body", 0.5) != "python_body":
		_fail("two pythons stay pythons unless the rare roll hits")
		return
	if LimbCatalog.combine("python_body", "python_body", 0.0) != "crowned_snake":
		_fail("two pythons can still roll the rare snake")
		return
	if LimbCatalog.combine("scrap", "snake_body", 0.5) != "scrap":
		_fail("scrap stays scrap")
		return
	for limb_id in ["gorilla_arm", "eagle_wing", "octopus_leg", "fish_tail"]:
		if LimbCatalog.find(limb_id) == null:
			_fail("playable part is missing from pickup catalog: %s" % limb_id)
			return

	var bag := LimbBag.new()
	root.add_child(bag)
	bag.slots[0] = "snake_body"
	bag.slots[1] = "snake_body"
	bag.rare_roll = 0.5
	bag.move_bag_to_dish(0, 0)
	bag.move_bag_to_dish(1, 0)
	bag.dishes[0]["time"] = LimbBag.CULTURE_SECONDS - 0.1
	bag._process(0.2)
	if bag.slots[0] != "python_body":
		_fail("culture should put the python in the bag, got %s" % bag.slots[0])
		return
	bag.move_bag_to_equip(0, "lower")
	if bag.equipped_lower != "python_body" or bag.slots[0] != "":
		_fail("python should equip into the lower slot")
		return
	bag.slots[2] = "scrap"
	bag.move_bag_to_equip(2, "upper")
	if bag.equipped_upper != "":
		_fail("scrap must not equip")
		return
	bag.recycle_bag(2)
	if bag.slots[2] != "":
		_fail("recycle should clear the slot")
		return
	bag.slots[3] = "snake_body"
	bag.slots[4] = "mantis_arm"
	bag.move_bag_to_dish(3, 1)
	bag.move_bag_to_dish(4, 1)
	bag.dishes[1]["time"] = LimbBag.CULTURE_SECONDS
	bag._process(0.1)
	if not bag.slots.has("scrap"):
		_fail("snake plus mantis should culture into scrap")
		return
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	process_frame.connect(_check_scene)


var _main: Node
var _frames := 0


func _check_scene() -> void:
	_frames += 1
	if _frames < 3:
		return
	process_frame.disconnect(_check_scene)
	var player := _main.get_node("Player") as PlayerController
	var bag := player.get_node("LimbBag") as LimbBag
	var rig := player.get_node("ArtRoot/PartSockets") as ModularCharacterRig
	var pickups := get_nodes_in_group("limb_pickup")
	if pickups.size() != 6:
		_fail("expected 6 pickups, got %d" % pickups.size())
		return
	var snake: Node3D = null
	var mantis: Node3D = null
	for node in pickups:
		if str(node.get("limb_id")) == "snake_body" and snake == null:
			snake = node as Node3D
		elif str(node.get("limb_id")) == "mantis_arm" and mantis == null:
			mantis = node as Node3D
	player.global_position = snake.global_position
	if not bag._collect_nearby() or not bag.slots.has("snake_body"):
		_fail("standing on a snake did not collect it")
		return
	player.global_position = mantis.global_position
	if not bag._collect_nearby() or not bag.slots.has("mantis_arm"):
		_fail("standing on a mantis arm did not collect it")
		return
	bag.move_bag_to_equip(bag.slots.find("snake_body"), "lower")
	if player.assembly.resolve_locomotion() != CharacterAssemblyController.LocomotionMode.SNAKE_SLITHER:
		_fail("snake equip did not switch locomotion")
		return
	if not rig._attachments["AnimTail"].visible or rig._attachments["AnimScytheBlade"].visible:
		_fail("snake equip should show the tail and hide the scythe")
		return
	bag.move_bag_to_equip(bag.slots.find("mantis_arm"), "upper")
	if player.parts.current_upper().id != "mantis_arm" or player.parts.current_lower().id != "snake_body":
		_fail("equipped limbs did not become the active gameplay definitions")
		return
	if player.parts.current_upper().has_ability("smash_hard", false):
		_fail("mantis arm inherited the previous gorilla ability")
		return
	if not rig._attachments["AnimScytheGrip"].visible or not rig._attachments["AnimScytheBlade"].visible:
		_fail("mantis equip should show the scythe")
		return
	if rig._attachments["AnimArmUpper"].visible:
		_fail("mantis equip should not show the gorilla arm")
		return
	bag.try_add("octopus_leg")
	bag.move_bag_to_equip(bag.slots.find("octopus_leg"), "lower")
	if player.parts.current_lower().id != "octopus_leg" \
			or player.assembly.resolve_locomotion() != CharacterAssemblyController.LocomotionMode.TENTACLE_CRAWL:
		_fail("picked octopus lower limb did not retain its gameplay gait")
		return
	bag.try_add("eagle_wing")
	bag.move_bag_to_equip(bag.slots.find("eagle_wing"), "upper")
	if player.parts.current_upper().id != "eagle_wing" or not player.assembly.can_fly():
		_fail("picked eagle wing did not retain its flight ability")
		return
	var menu := _main.get_node("StitchMenu")
	bag.try_add("snake_body")
	bag.try_add("mantis_arm")
	menu._drop_on_dish({"kind": "bag", "index": bag.slots.find("snake_body")}, 0)
	menu._drop_on_dish({"kind": "bag", "index": bag.slots.find("mantis_arm")}, 0)
	if str(bag.dishes[0]["a"]) == "" or str(bag.dishes[0]["b"]) == "":
		_fail("menu drop did not fill a petri dish")
		return
	if menu._bag_slots.size() != 16 or menu._equip_slots.size() != 8 or menu._dish_sides.size() != 10:
		_fail("menu slots %d %d %d" % [menu._bag_slots.size(), menu._equip_slots.size(), menu._dish_sides.size()])
		return
	print("LIMBS_TEST: PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("LIMBS_TEST: " + message)
	print("LIMBS_TEST: FAIL " + message)
	quit(1)
