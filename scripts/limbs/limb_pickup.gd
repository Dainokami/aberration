extends Node3D

var limb_id := ""
var _base_y := 0.2


func setup(id: String) -> void:
	limb_id = id
	add_to_group("limb_pickup")
	var sprite := Sprite3D.new()
	sprite.texture = LimbCatalog.texture_for(id)
	sprite.pixel_size = 0.0024
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.position = Vector3(0.0, 0.85, 0.0)
	sprite.modulate = LimbCatalog.find(id).tint if LimbCatalog.find(id) else Color.WHITE
	add_child(sprite)


func _ready() -> void:
	_base_y = position.y


func collect(bag: LimbBag) -> bool:
	if not bag.try_add(limb_id):
		return false
	queue_free()
	return true


func _process(_delta: float) -> void:
	position.y = _base_y + sin(Time.get_ticks_msec() * 0.004) * 0.08
