class_name LimbCatalog
extends RefCounted

# 同一族两件合成下一档。roll 低于 RARE_CHANCE 时改出该族稀有肢体。
# 不同族，或残肢参与，结果是更弱的残肢。
const RARE_CHANCE := 0.12

static var _defs: Dictionary = {}


static func find(limb_id: String) -> LimbDef:
	_ensure()
	return _defs.get(limb_id) as LimbDef


static func texture_for(limb_id: String) -> Texture2D:
	var limb := find(limb_id)
	if limb == null or limb.texture_path.is_empty():
		return null
	return load(limb.texture_path) as Texture2D


static func combine(left_id: String, right_id: String, roll: float) -> String:
	var left := find(left_id)
	var right := find(right_id)
	if left == null or right == null:
		return "scrap"
	if left.family.is_empty() or left.family != right.family or left.family == "scrap":
		return "scrap"
	var rare_id := left.rare_id if not left.rare_id.is_empty() else right.rare_id
	if not rare_id.is_empty() and roll < RARE_CHANCE and not (left.rare and right.rare):
		return rare_id
	if left.rare and right.rare:
		return left.id
	if left.tier >= 2 and right.tier >= 2:
		return left.id if left.tier >= right.tier else right.id
	if left.tier <= right.tier and not left.upgrade_id.is_empty():
		return left.upgrade_id
	if not right.upgrade_id.is_empty():
		return right.upgrade_id
	return left.id if left.tier >= right.tier else right.id


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	_add("snake_body", "蛇身", "lower", "serpent", 1, false, "python_body", "crowned_snake", "res://art/characters/anim/tail.png", "tail", 1.0, Color.WHITE, "贴地蠕动", 1.0)
	_add("python_body", "巨蟒身", "lower", "serpent", 2, false, "", "crowned_snake", "res://art/characters/anim/tail.png", "tail", 1.18, Color(0.78, 0.95, 0.62), "两条蛇身养成的加强蛇身", 1.22)
	_add("crowned_snake", "冠蛇", "lower", "serpent", 3, true, "", "", "res://art/characters/anim/tail.png", "tail", 1.24, Color(1.0, 0.82, 0.28), "稀有蛇身", 1.4)
	_add("mantis_arm", "螳螂臂", "upper", "mantis", 1, false, "mantis_blade", "mantis_king", "res://art/characters/anim/scythe_blade.png", "scythe", 1.0, Color.WHITE, "镰状前臂", 1.0)
	_add("mantis_blade", "巨镰螳臂", "upper", "mantis", 2, false, "", "mantis_king", "res://art/characters/anim/scythe_blade.png", "scythe", 1.16, Color(0.95, 0.55, 0.45), "两条螳螂臂养成的加强臂", 1.0)
	_add("mantis_king", "王螳臂", "upper", "mantis", 3, true, "", "", "res://art/characters/anim/scythe_blade.png", "scythe", 1.28, Color(1.0, 0.84, 0.32), "稀有螳螂臂", 1.0)
	_add("scrap", "残肢", "none", "scrap", 0, false, "", "", "res://art/characters/psd/arm_hop.png", "", 1.0, Color(0.55, 0.5, 0.48), "对不上的肢体养成的废物，只能回收", 1.0)
	_add_playable_parts()


static func _add_playable_parts() -> void:
	for part in PartCatalog.uppers():
		_add_playable(part, "upper")
	for part in PartCatalog.lowers():
		_add_playable(part, "lower")


static func _add_playable(part: PartDefinition, slot_name: String) -> void:
	if _defs.has(part.id):
		return
	var style := _pickup_style(part.id, slot_name)
	_add(part.id, part.display_name, slot_name, "play_" + part.id,
		int(part.rank) + 1, false, "", "", style["texture"], style["visual"],
		style["scale"], style["tint"], part.blurb, 1.0)


static func _pickup_style(limb_id: String, slot_name: String) -> Dictionary:
	if limb_id in ["goose_wing", "bat_wing", "albatross_wing", "eagle_wing"]:
		var wing_tints := {
			"goose_wing": Color(0.92, 0.92, 0.9),
			"bat_wing": Color(0.35, 0.32, 0.4),
			"albatross_wing": Color(0.75, 0.86, 0.95),
			"eagle_wing": Color(0.62, 0.42, 0.22),
		}
		return {"texture": "res://art/characters/psd/wing_left.png", "visual": "wing", "scale": 0.78, "tint": wing_tints[limb_id]}
	if limb_id == "octopus_arm":
		return {"texture": "res://art/characters/psd/arm_crawl_gorilla.png", "visual": "crawl", "scale": 0.8, "tint": Color(0.45, 0.55, 0.85)}
	if limb_id in ["gibbon_arm", "gerbil_paw"]:
		return {"texture": "res://art/characters/psd/arm_hop.png", "visual": "hop", "scale": 0.75, "tint": Color(0.72, 0.55, 0.36) if limb_id == "gerbil_paw" else Color.WHITE}
	if slot_name == "upper":
		return {"texture": "res://art/characters/anim/arm_upper.png", "visual": "arm", "scale": 0.75, "tint": Color.WHITE}
	if limb_id in ["water_snake", "fish_tail"]:
		return {"texture": "res://art/characters/anim/tail.png", "visual": "tail", "scale": 0.68, "tint": Color(0.35, 0.75, 0.95) if limb_id == "fish_tail" else Color.WHITE}
	var leg_tints := {
		"wolf_leg": Color(0.55, 0.55, 0.58),
		"ostrich_leg": Color(0.86, 0.72, 0.48),
		"gerbil_leg": Color(0.72, 0.58, 0.4),
		"kangaroo_leg": Color(0.62, 0.45, 0.32),
		"demon_dog_leg": Color(0.45, 0.18, 0.18),
		"octopus_leg": Color(0.4, 0.48, 0.78),
		"goose_foot": Color(0.95, 0.72, 0.28),
	}
	return {"texture": "res://art/characters/psd/leg_left.png", "visual": "leg", "scale": 0.72, "tint": leg_tints.get(limb_id, Color.WHITE)}


static func _add(
	limb_id: String,
	display_name: String,
	slot: String,
	family: String,
	tier: int,
	rare: bool,
	upgrade_id: String,
	rare_id: String,
	texture_path: String,
	visual: String,
	visual_scale: float,
	tint: Color,
	blurb: String,
	speed_scale: float
) -> void:
	var limb := LimbDef.new()
	limb.id = limb_id
	limb.display_name = display_name
	limb.slot = slot
	limb.family = family
	limb.tier = tier
	limb.rare = rare
	limb.upgrade_id = upgrade_id
	limb.rare_id = rare_id
	limb.texture_path = texture_path
	limb.visual = visual
	limb.visual_scale = visual_scale
	limb.tint = tint
	limb.blurb = blurb
	limb.speed_scale = speed_scale
	_defs[limb_id] = limb
