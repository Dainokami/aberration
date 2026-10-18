@tool
class_name MonsterDefinition
extends Resource

@export var monster_id := ""
@export var display_name := ""
@export var ecosystems: PackedStringArray = ["grass"]
@export_enum("land", "amphibious", "air", "aquatic") var movement := "land"
@export var source_aggressive := true
@export var group_living := false
@export_enum("bite", "pounce", "peck", "kick", "swing", "tentacle", "stone") var attack := "bite"
@export var max_health := 40.0
@export var damage := 14.0
@export var speed := 5.6
@export var attack_interval := 0.62
@export var windup := 0.35
@export var attack_reach := 1.5
@export var body_radius := 0.35
@export var body_height := 1.5
@export var image_height := 1.8
@export var image_path := ""
@export var parts: Array[Dictionary] = []
@export var drops: PackedStringArray = []
@export var source_row := 0
@export var source_manifest := ""

func available() -> bool:
	return not image_path.is_empty() and ResourceLoader.exists(image_path)

func drop_items() -> PackedStringArray:
	# Imported source labels map to the stable IDs in the existing part catalog.
	if drops != PackedStringArray([monster_id + "_limb"]):
		return drops
	return PackedStringArray({
		"wolf":["wolf_leg"], "ostrich":["ostrich_leg"], "gerbil":["gerbil_leg"],
		"gibbon":["gibbon_arm"], "gorilla":["gorilla_arm"], "kangaroo":["kangaroo_leg"],
		"demon_dog":["demon_dog_leg"], "goose":["goose_foot","goose_wing"],
		"octopus":["octopus_leg"], "bat":["bat_wing"], "albatross":["albatross_wing"],
		"eagle":["eagle_wing"], "piranha":["piranha_gill"], "water_snake":["water_snake"]
	}.get(monster_id, []))

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	for value in [max_health, damage, speed, attack_interval, windup, attack_reach,
			body_radius, body_height, image_height]:
		if not is_finite(value) or value <= 0:
			result.append("怪物数值必须是正有限数：" + display_name)
			break
	if monster_id.is_empty() or movement not in ["land", "amphibious", "air", "aquatic"]:
		result.append("怪物 ID 或移动类型无效")
	if ecosystems.is_empty():
		result.append("怪物至少需要一种允许生态：" + display_name)
	for ecosystem in ecosystems:
		if ecosystem not in ["grass", "rock", "desert", "ocean"]:
			result.append("怪物生态无效：" + ecosystem)
	if not available():
		result.append("缺少怪物美术：" + display_name)
	return result
