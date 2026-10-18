extends SceneTree

const RecipeCatalog := preload("res://scripts/limbs/limb_recipe_catalog.gd")


func _initialize() -> void:
	var matrix_errors := RecipeCatalog.validate()
	if not matrix_errors.is_empty():
		_fail("matrix validation failed: %s" % ", ".join(matrix_errors))
		return
	if RecipeCatalog.recipe_count() != 153:
		_fail("matrix should contain 153 unordered recipes")
		return
	var counts := RecipeCatalog.result_counts()
	if counts != {"ordinary": 103, "original": 14, "albino": 12, "scrap": 24, "rare": 26}:
		_fail("matrix audit changed: %s" % counts)
		return
	for left_id in RecipeCatalog.INGREDIENT_IDS:
		for right_id in RecipeCatalog.INGREDIENT_IDS:
			var forward := LimbCatalog.combine(left_id, right_id)
			var reverse := LimbCatalog.combine(right_id, left_id)
			if forward.is_empty() or forward != reverse:
				_fail("recipe order changed for %s + %s" % [left_id, right_id])
				return
	if LimbCatalog.combine("gorilla_arm", "gorilla_arm") != "albino_gorilla_arm":
		_fail("gorilla self recipe should produce the albino arm")
		return
	if LimbCatalog.combine("gorilla_arm", "gibbon_arm") != "octopus_arm":
		_fail("gorilla plus gibbon recipe is wrong")
		return
	if LimbCatalog.combine("octopus_arm", "octopus_leg") != "jellyfish_tentacle_wing":
		_fail("upper/lower octopus ingredients were not kept distinct")
		return
	if not LimbCatalog.combine("snake_body", "gorilla_arm").is_empty():
		_fail("legacy limbs must not be accepted as matrix ingredients")
		return
	for result_id in ["albino_gorilla_arm", "pangolin_dig_claw", "scrap"]:
		if LimbCatalog.can_culture(result_id):
			_fail("matrix result can be reused as an ingredient: %s" % result_id)
			return
	for limb_id in ["gorilla_arm", "eagle_wing", "octopus_leg", "fish_tail"]:
		if LimbCatalog.find(limb_id) == null:
			_fail("playable part is missing from pickup catalog: %s" % limb_id)
			return

	var bag := LimbBag.new()
	root.add_child(bag)
	bag.slots[0] = "gorilla_arm"
	bag.slots[1] = "gibbon_arm"
	bag.move_bag_to_dish(0, 0)
	bag.move_bag_to_dish(1, 0)
	bag.dishes[0]["time"] = LimbBag.CULTURE_SECONDS - 0.1
	bag._process(0.2)
	if bag.slots[0] != "octopus_arm":
		_fail("culture should put the matrix result in the bag, got %s" % bag.slots[0])
		return
	bag.move_bag_to_equip(0, "upper")
	if bag.equipped_upper != "octopus_arm" or bag.slots[0] != "":
		_fail("matrix result should equip into its declared slot")
		return
	bag.slots[2] = "scrap"
	bag.move_bag_to_equip(2, "upper")
	if bag.equipped_upper != "octopus_arm":
		_fail("scrap must not equip")
		return
	bag.move_bag_to_dish(2, 1)
	if bag.slots[2] != "scrap" or not str(bag.dishes[1]["a"]).is_empty():
		_fail("scrap must not enter a dish")
		return
	bag.recycle_bag(2)
	if bag.slots[2] != "":
		_fail("recycle should clear the slot")
		return
	bag.slots[3] = "gorilla_arm"
	bag.slots[4] = "goose_wing"
	bag.move_bag_to_dish(3, 1)
	bag.move_bag_to_dish(4, 1)
	bag.dishes[1]["time"] = LimbBag.CULTURE_SECONDS
	bag._process(0.1)
	if not bag.slots.has("scrap"):
		_fail("gorilla plus goose wing should culture into scrap")
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
	if bag.equipped_upper != "gorilla_arm" or bag.equipped_lower != "wolf_leg":
		_fail("starting limbs must be registered as equipped")
		return
	var gibbon_index := bag.slots.find("gibbon_arm")
	bag.move_bag_to_equip(gibbon_index, "upper")
	if bag.equipped_upper != "gibbon_arm" or bag.slots[gibbon_index] != "gorilla_arm":
		_fail("replaced upper limb did not return to its source bag slot")
		return
	bag.move_bag_to_equip(gibbon_index, "upper")
	if bag.equipped_upper != "gorilla_arm" or bag.slots[gibbon_index] != "gibbon_arm":
		_fail("swapping the starting upper limb back failed")
		return
	var offset := LimbSlot.drag_preview_offset(Vector2(50, 25), Vector2(200, 100), Vector2(120, 120))
	if not offset.is_equal_approx(Vector2(-30, -30)):
		_fail("drag preview no longer follows the source grab point: %s" % offset)
		return
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
	if not bag.slots.has("wolf_leg"):
		_fail("replaced starting lower limb did not return to the bag")
		return
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
	for equip_slot: LimbSlot in menu._equip_slots:
		var slot_name := str(equip_slot.get_meta("equip_slot"))
		var expected := bag.equipped_upper if slot_name == "upper" else bag.equipped_lower
		if str(equip_slot.drag_data.get("id", "")) != expected:
			_fail("equipment UI did not refresh %s to %s" % [slot_name, expected])
			return
	var first_ingredient := bag.slots.find("gorilla_arm")
	var second_ingredient := bag.slots.find("gibbon_arm")
	if first_ingredient < 0 or second_ingredient < 0:
		_fail("expected base ingredients in the bag for the UI dish test")
		return
	menu._drop_on_dish({"kind": "bag", "index": first_ingredient}, 0)
	menu._drop_on_dish({"kind": "bag", "index": second_ingredient}, 0)
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
