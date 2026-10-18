extends SceneTree

const EXPECTED := {
	"wolf_leg": PartDefinition.Slot.LOWER,
	"ostrich_leg": PartDefinition.Slot.LOWER,
	"gerbil_leg": PartDefinition.Slot.LOWER,
	"kangaroo_leg": PartDefinition.Slot.LOWER,
	"fish_tail": PartDefinition.Slot.LOWER,
	"bat_wing": PartDefinition.Slot.UPPER,
	"albatross_wing": PartDefinition.Slot.UPPER,
	"eagle_wing": PartDefinition.Slot.UPPER,
}


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	for part_id in EXPECTED:
		var part := PartCatalog.find(part_id)
		if part == null or part.slot != EXPECTED[part_id] or part.texture_path.is_empty():
			_fail("catalog mapping: " + part_id)
			return
		var texture := PartCatalog.texture_for(part_id)
		if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
			_fail("texture import: " + part_id)
			return
	var piranha := MonsterDefinition.new()
	piranha.monster_id = "piranha"
	piranha.drops = PackedStringArray(["piranha_limb"])
	if piranha.drop_items() != PackedStringArray(["fish_tail"]):
		_fail("piranha drop ID")
		return
	var drop := MonsterDrop.new()
	drop.item_id = "eagle_wing"
	root.add_child(drop)
	var sprite := drop.get_child(0) as Sprite3D
	if sprite == null or sprite.texture == null or sprite.texture.resource_path != PartCatalog.find("eagle_wing").texture_path:
		_fail("monster pickup displays the mapped limb art")
		return
	drop.free()
	if PartCatalog.find("pangolin_claw") != null:
		_fail("unimplemented pangolin mechanic registered")
		return
	print("LIMB_ART_20261018: PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("LIMB_ART_20261018: " + message)
	quit(1)
