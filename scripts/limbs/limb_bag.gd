class_name LimbBag
extends Node

signal changed
signal note(message: String)

const CAPACITY := 16
const DISH_COUNT := 5
const UNLOCKED_DISHES := 4
const CULTURE_SECONDS := 6.0
const RecycleTable := preload("res://scripts/recycle_table.gd")

var slots: Array[String] = []
var equipped_upper := ""
var blood := 0
var equipped_lower := ""
var dishes: Array[Dictionary] = []


func _init() -> void:
	slots.resize(CAPACITY)
	for index in CAPACITY:
		slots[index] = ""
	for _dish in DISH_COUNT:
		dishes.append({"a": "", "b": "", "time": 0.0})


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	var finished := false
	for dish: Dictionary in dishes:
		var left := str(dish["a"])
		var right := str(dish["b"])
		if left.is_empty() or right.is_empty():
			continue
		if not LimbCatalog.can_culture(left) or not LimbCatalog.can_culture(right):
			continue
		dish["time"] = float(dish["time"]) + delta
		if float(dish["time"]) >= CULTURE_SECONDS:
			_finish_dish(dish)
			finished = true
	if finished:
		changed.emit()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("part_interact") and _collect_nearby():
		get_viewport().set_input_as_handled()


func stow_equipped(slot_name: String) -> void:
	var limb_id := _equipped(slot_name)
	if limb_id.is_empty():
		return
	var empty := _first_empty()
	if empty < 0:
		return
	slots[empty] = limb_id
	_set_equipped(slot_name, "")
	var assembly := get_parent().get_node_or_null("Assembly") as CharacterAssemblyController
	if assembly:
		if equipped_upper.is_empty() and equipped_lower.is_empty():
			assembly.clear_limb_drive()
		else:
			assembly.apply_limb_loadout(equipped_upper, equipped_lower)
	changed.emit()


func has_equipped() -> bool:
	return not equipped_upper.is_empty() or not equipped_lower.is_empty()


func report(message: String) -> void:
	note.emit(message)


func set_starting_loadout(upper_id: String, lower_id: String) -> void:
	equipped_upper = upper_id
	equipped_lower = lower_id


func stock_spares() -> void:
	# 当前穿戴不重复放入背包；缺省测试件仍可在场景拾取或用 Z/X 预览。
	# 至少留四格，保证两次快捷键卸装后仍有拾取和培养空间。
	var skip := PackedStringArray([
		equipped_upper, equipped_lower, "demon_dog_leg", "bat_wing", "goose_foot",
	])
	for part in PartCatalog.uppers():
		_stock_one(part.id, skip)
	for part in PartCatalog.lowers():
		_stock_one(part.id, skip)


func _stock_one(limb_id: String, skip: PackedStringArray) -> void:
	if skip.has(limb_id) or slots.has(limb_id):
		return
	var index := _first_empty()
	if index < 0:
		return
	slots[index] = limb_id


func try_add(limb_id: String) -> bool:
	var index := _first_empty()
	if index < 0:
		note.emit("背包满了")
		return false
	slots[index] = limb_id
	var limb := LimbCatalog.find(limb_id)
	note.emit("放进背包：" + (limb.display_name if limb else limb_id))
	changed.emit()
	return true



func cycle_slot(slot_name: String) -> bool:
	var owned: Array[String] = []
	var current := _equipped(slot_name)
	if not current.is_empty():
		owned.append(current)
	for limb_id in slots:
		var found := LimbCatalog.find(limb_id)
		if found != null and found.slot == slot_name and not owned.has(limb_id):
			owned.append(limb_id)
	if owned.is_empty():
		return false
	var index := owned.find(current)
	var next: String = owned[(index + 1) % owned.size()]
	var label := "上肢" if slot_name == "upper" else "下肢"
	if next == current:
		note.emit("只有这一件%s：%s" % [label, LimbCatalog.find(current).display_name])
		return true
	var bag_index := slots.find(next)
	# 直接与目标所在格交换，不依赖空格；换下来的肢体必定回到背包。
	slots[bag_index] = current
	_set_equipped(slot_name, next)
	_sync_body()
	note.emit("装上了" + LimbCatalog.find(next).display_name)
	changed.emit()
	return true


func move_bag_to_equip(index: int, slot_name: String) -> void:
	if not _bag_index(index):
		return
	var limb_id := slots[index]
	var limb := LimbCatalog.find(limb_id)
	if limb == null or limb.slot != slot_name:
		note.emit("这个肢体装不到这里")
		return
	var previous := _equipped(slot_name)
	slots[index] = previous
	_set_equipped(slot_name, limb_id)
	_sync_body()
	note.emit("装上了" + limb.display_name)
	changed.emit()


func move_equip_to_bag(slot_name: String, index: int) -> void:
	if not _bag_index(index):
		return
	var limb_id := _equipped(slot_name)
	if limb_id.is_empty():
		return
	var occupant := slots[index]
	if not occupant.is_empty():
		var other := LimbCatalog.find(occupant)
		if other == null or other.slot != slot_name:
			note.emit("这个格子里的肢体类型不对")
			return
	_set_equipped(slot_name, occupant)
	slots[index] = limb_id
	_sync_body()
	changed.emit()


func move_bag_to_dish(index: int, dish_index: int) -> void:
	if not _bag_index(index) or not _dish_index(dish_index):
		return
	if not _dish_unlocked(dish_index):
		note.emit("这个培养皿还锁着")
		return
	var dish := dishes[dish_index]
	if not str(dish["a"]).is_empty() and not str(dish["b"]).is_empty():
		note.emit("这个培养皿已经有两件了")
		return
	var limb_id := slots[index]
	if limb_id.is_empty():
		return
	if not _dish_accepts(dish, limb_id):
		return
	slots[index] = ""
	if str(dish["a"]).is_empty():
		dish["a"] = limb_id
	else:
		dish["b"] = limb_id
	if not str(dish["a"]).is_empty() and not str(dish["b"]).is_empty():
		dish["time"] = 0.0
		note.emit("两件都放进去了，开始培养")
	else:
		note.emit("放进培养皿")
	changed.emit()


func move_dish_to_bag(dish_index: int, side: String, index: int) -> void:
	if not _dish_index(dish_index) or not _bag_index(index) or not _dish_side(side):
		return
	var dish := dishes[dish_index]
	var limb_id := str(dish[side])
	if limb_id.is_empty():
		return
	var occupant := slots[index]
	if not occupant.is_empty() and not LimbCatalog.can_culture(occupant):
		note.emit("这个产物不能放回培养皿，请先找一个空背包格")
		return
	slots[index] = limb_id
	dish[side] = occupant
	dish["time"] = 0.0
	changed.emit()


func move_equip_to_dish(slot_name: String, dish_index: int) -> void:
	if not _dish_index(dish_index):
		return
	if not _dish_unlocked(dish_index):
		note.emit("这个培养皿还锁着")
		return
	var limb_id := _equipped(slot_name)
	if limb_id.is_empty():
		return
	var dish := dishes[dish_index]
	if not str(dish["a"]).is_empty() and not str(dish["b"]).is_empty():
		note.emit("这个培养皿已经有两件了")
		return
	if not _dish_accepts(dish, limb_id):
		return
	_set_equipped(slot_name, "")
	if str(dish["a"]).is_empty():
		dish["a"] = limb_id
	else:
		dish["b"] = limb_id
	if not str(dish["a"]).is_empty() and not str(dish["b"]).is_empty():
		dish["time"] = 0.0
	_sync_body()
	changed.emit()


func move_dish_to_dish(from_index: int, side: String, to_index: int) -> void:
	if from_index == to_index or not _dish_index(from_index) or not _dish_index(to_index) or not _dish_side(side):
		return
	var source: Dictionary = dishes[from_index]
	var limb_id := str(source[side])
	if limb_id.is_empty():
		return
	if not _dish_unlocked(to_index):
		note.emit("这个培养皿还锁着")
		return
	var dest: Dictionary = dishes[to_index]
	if not str(dest["a"]).is_empty() and not str(dest["b"]).is_empty():
		note.emit("这个培养皿已经有两件了")
		return
	if not _dish_accepts(dest, limb_id):
		return
	source[side] = ""
	source["time"] = 0.0
	if str(dest["a"]).is_empty():
		dest["a"] = limb_id
	else:
		dest["b"] = limb_id
	if not str(dest["a"]).is_empty() and not str(dest["b"]).is_empty():
		dest["time"] = 0.0
	changed.emit()


func move_dish_to_equip(dish_index: int, side: String, slot_name: String) -> void:
	if not _dish_index(dish_index) or not _dish_side(side):
		return
	var dish := dishes[dish_index]
	var limb_id := str(dish[side])
	var limb := LimbCatalog.find(limb_id)
	if limb == null or limb.slot != slot_name:
		note.emit("这个肢体装不到这里")
		return
	var previous := _equipped(slot_name)
	if not previous.is_empty() and _first_empty() < 0:
		note.emit("背包满了，换下来的肢体没有位置")
		return
	dish[side] = ""
	dish["time"] = 0.0
	if not previous.is_empty():
		slots[_first_empty()] = previous
	_set_equipped(slot_name, limb_id)
	_sync_body()
	note.emit("装上了" + limb.display_name)
	changed.emit()


func swap_slots(left: int, right: int) -> void:
	if left == right or not _bag_index(left) or not _bag_index(right):
		return
	var held := slots[left]
	slots[left] = slots[right]
	slots[right] = held
	changed.emit()


func recycle_bag(index: int) -> void:
	if not _bag_index(index) or slots[index].is_empty():
		return
	_recycle(slots[index])
	slots[index] = ""
	changed.emit()


func recycle_equip(slot_name: String) -> void:
	var limb_id := _equipped(slot_name)
	if limb_id.is_empty():
		return
	_set_equipped(slot_name, "")
	_recycle(limb_id)
	_sync_body()
	changed.emit()


func recycle_dish(dish_index: int, side: String) -> void:
	if not _dish_index(dish_index):
		return
	var dish := dishes[dish_index]
	var limb_id := str(dish[side])
	if limb_id.is_empty():
		return
	dish[side] = ""
	dish["time"] = 0.0
	_recycle(limb_id)
	changed.emit()


func _finish_dish(dish: Dictionary) -> void:
	var left := str(dish["a"])
	var right := str(dish["b"])
	var result_id := LimbCatalog.combine(left, right)
	if result_id.is_empty():
		dish["time"] = 0.0
		note.emit("这两件不是有效的培养原料")
		return
	dish["a"] = ""
	dish["b"] = ""
	dish["time"] = 0.0
	var result := LimbCatalog.find(result_id)
	var result_name := result.display_name if result else result_id
	if _first_empty() < 0:
		dish["a"] = result_id
		note.emit("背包满了，%s先留在培养皿里" % result_name)
		return
	slots[_first_empty()] = result_id
	if result != null and result.rare:
		note.emit("培养出稀有肢体：" + result_name)
	elif result_id == "scrap":
		note.emit("培养出了畸变废肢")
	else:
		note.emit("培养完成：" + result_name)


func _dish_accepts(dish: Dictionary, limb_id: String) -> bool:
	if not LimbCatalog.can_culture(limb_id):
		note.emit("只有能力表中的17种基础部件可以投入培养皿")
		return false
	for side in ["a", "b"]:
		var existing := str(dish[side])
		if not existing.is_empty() and not LimbCatalog.can_culture(existing):
			note.emit("请先取出培养皿里的不可合成产物")
			return false
	return true


func _collect_nearby() -> bool:
	var body := get_parent() as Node3D
	if body == null:
		return false
	var best: Node = null
	# 拾取只在脚边触发，避免测试区肢体抢走对岩石、抓点等场景物的 G 交互。
	var best_distance := 0.85
	for node in get_tree().get_nodes_in_group("limb_pickup"):
		var pickup := node as Node3D
		if pickup == null:
			continue
		var distance := body.global_position.distance_to(pickup.global_position)
		if distance < best_distance:
			best = pickup
			best_distance = distance
	if best == null:
		return false
	best.call("collect", self)
	return true


func _recycle(limb_id: String) -> void:
	var limb := LimbCatalog.find(limb_id)
	var name := limb.display_name if limb else limb_id
	var amount := RecycleTable.amount(limb_id)
	if amount > 0:
		blood += amount
		note.emit("肢解了%s，获得 %d 血液" % [name, amount])
	else:
		note.emit("回收了" + name)


func _sync_body() -> void:
	var assembly := get_parent().get_node_or_null("Assembly") as CharacterAssemblyController
	if assembly == null:
		return
	if equipped_upper.is_empty() and equipped_lower.is_empty():
		assembly.clear_limb_drive()
	else:
		assembly.apply_limb_loadout(equipped_upper, equipped_lower)


func _equipped(slot_name: String) -> String:
	return equipped_upper if slot_name == "upper" else equipped_lower


func _set_equipped(slot_name: String, limb_id: String) -> void:
	if slot_name == "upper":
		equipped_upper = limb_id
	else:
		equipped_lower = limb_id


func _first_empty() -> int:
	return slots.find("")


func _bag_index(index: int) -> bool:
	return index >= 0 and index < slots.size()


func _dish_index(index: int) -> bool:
	return index >= 0 and index < dishes.size()


func _dish_unlocked(index: int) -> bool:
	return index >= 0 and index < UNLOCKED_DISHES


func _dish_side(side: String) -> bool:
	return side == "a" or side == "b"
