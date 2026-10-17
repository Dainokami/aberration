extends Node3D

var limb_id := ""
var _base_y := 0.2


func setup(id: String) -> void:
	limb_id = id
	add_to_group("limb_pickup")
	var definition := LimbCatalog.find(id)
	var sprite := Sprite3D.new()
	sprite.texture = LimbCatalog.texture_for(id)
	sprite.pixel_size = 0.0028
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.position = Vector3(0.0, 0.72, 0.0)
	sprite.modulate = definition.tint if definition else Color.WHITE
	add_child(sprite)

	var pedestal := MeshInstance3D.new()
	var pedestal_mesh := BoxMesh.new()
	pedestal_mesh.size = Vector3(0.9, 0.1, 0.9)
	pedestal.mesh = pedestal_mesh
	pedestal.position.y = 0.05
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.24, 0.68, 1.0, 0.72) if definition != null and definition.slot == "upper" else Color(0.42, 0.92, 0.52, 0.72)
	pedestal.material_override = material
	add_child(pedestal)

	var label := Label3D.new()
	label.text = ("上肢" if definition != null and definition.slot == "upper" else "下肢") + " · " + (definition.display_name if definition else id)
	label.position = Vector3(0.0, 1.5, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 30
	label.outline_size = 6
	label.pixel_size = 0.0025
	label.no_depth_test = true
	add_child(label)


func _ready() -> void:
	_base_y = position.y


func collect(bag: LimbBag) -> bool:
	if not bag.try_add(limb_id):
		return false
	queue_free()
	return true


func _process(_delta: float) -> void:
	position.y = _base_y + sin(Time.get_ticks_msec() * 0.004) * 0.08
