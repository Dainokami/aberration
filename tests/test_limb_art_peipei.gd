extends SceneTree

const EXPECTED := {
	"goose_wing": "goose_wing/primary.png",
	"goose_foot": "goose_foot/primary.png",
	"gorilla_arm": "gorilla_arm/primary.png",
	"octopus_arm": "octopus_tentacle/primary.png",
	"octopus_leg": "octopus_tentacle/primary.png",
	"demon_dog_leg": "demon_dog_leg/full_body_primary.png",
}
const BASE := "res://assets/derived_art/limbs_peipei_20261018/"


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	for part_id in EXPECTED:
		var part := PartCatalog.find(part_id)
		var path: String = BASE + EXPECTED[part_id]
		if part == null or part.texture_path != path:
			_fail("catalog mapping: " + part_id)
			return
		var texture := PartCatalog.texture_for(part_id)
		if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
			_fail("texture import: " + part_id)
			return
		var image := texture.get_image()
		if image == null or image.get_pixel(0, 0).a > 0.01:
			_fail("transparent crop: " + part_id)
			return
	var drop := MonsterDrop.new()
	drop.item_id = "goose_foot"
	root.add_child(drop)
	var sprite := drop.get_child(0) as Sprite3D
	if sprite == null or sprite.texture == null or sprite.texture.resource_path != BASE + EXPECTED["goose_foot"]:
		_fail("goose foot drop image")
		return
	drop.free()
	print("LIMB_ART_PEIPEI: PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("LIMB_ART_PEIPEI: " + message)
	quit(1)
