class_name MonsterDrop
extends Node3D

var item_id := ""
var texture_path := ""

func _ready() -> void:
	add_to_group("monster_drop")
	var sprite := Sprite3D.new()
	sprite.texture = load(texture_path) as Texture2D
	sprite.pixel_size = 0.001
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.position.y = 0.35
	add_child(sprite)

func collect(player: Node3D) -> String:
	var inventory: Array = player.get_meta("scene_inventory", [])
	if inventory.size() >= int(player.get_meta("scene_inventory_capacity", 20)):
		return "背包已满"
	inventory.append(item_id)
	player.set_meta("scene_inventory", inventory)
	queue_free()
	return "拾取：" + item_id
