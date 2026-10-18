class_name LimbCatalog
extends RefCounted

# 培养结果由 17×17 策划矩阵唯一决定；随机数不再参与产物选择。
const RecipeCatalog := preload("res://scripts/limbs/limb_recipe_catalog.gd")

static var _defs: Dictionary = {}


static func find(limb_id: String) -> LimbDef:
	_ensure()
	return _defs.get(limb_id) as LimbDef


static func texture_for(limb_id: String) -> Texture2D:
	var limb := find(limb_id)
	if limb == null or limb.texture_path.is_empty():
		return null
	return load(limb.texture_path) as Texture2D


static func can_culture(limb_id: String) -> bool:
	var limb := find(limb_id)
	return limb != null and limb.culture_ingredient and RecipeCatalog.is_ingredient(limb_id)


static func combine(left_id: String, right_id: String, _unused_roll := -1.0) -> String:
	if not can_culture(left_id) or not can_culture(right_id):
		return ""
	return RecipeCatalog.combine(left_id, right_id)


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	# 旧白盒肢体继续保留给移动/骨骼验证，但不属于 17 个培养原料。
	_add("snake_body", "蛇身", "lower", "serpent", 1, false, "python_body", "crowned_snake", "res://art/characters/anim/tail.png", "tail", 1.0, Color.WHITE, "旧白盒蛇身，不可投入培养皿", 1.0)
	_add("python_body", "巨蟒身", "lower", "serpent", 2, false, "", "crowned_snake", "res://art/characters/anim/tail.png", "tail", 1.18, Color(0.78, 0.95, 0.62), "旧白盒加强蛇身，不可投入培养皿", 1.22)
	_add("crowned_snake", "冠蛇", "lower", "serpent", 3, true, "", "", "res://art/characters/anim/tail.png", "tail", 1.24, Color(1.0, 0.82, 0.28), "旧白盒稀有蛇身，不可投入培养皿", 1.4)
	_add("mantis_arm", "螳螂臂", "upper", "mantis", 1, false, "mantis_blade", "mantis_king", "res://art/characters/anim/scythe_blade.png", "scythe", 1.0, Color.WHITE, "旧白盒螳螂臂，不可投入培养皿", 1.0)
	_add("mantis_blade", "巨镰螳臂", "upper", "mantis", 2, false, "", "mantis_king", "res://art/characters/anim/scythe_blade.png", "scythe", 1.16, Color(0.95, 0.55, 0.45), "旧白盒加强螳臂，不可投入培养皿", 1.0)
	_add("mantis_king", "王螳臂", "upper", "mantis", 3, true, "", "", "res://art/characters/anim/scythe_blade.png", "scythe", 1.28, Color(1.0, 0.84, 0.32), "旧白盒稀有螳臂，不可投入培养皿", 1.0)
	_add("scrap", "畸变废肢", "none", "scrap", 0, false, "", "", "res://art/characters/proxy/arm.svg", "", 1.0, Color(0.55, 0.5, 0.48), "培养失败产生的废肢，只能回收", 1.0, false, true, "scrap")
	_add_playable_parts()
	_add_matrix_results()


static func _add_matrix_results() -> void:
	# 尚未收到独立美术的结果统一使用现有代理图或最接近的基础部件作占位。
	_add_placeholder("pangolin_dig_claw", "类穿山甲掘爪", "upper", "res://art/characters/proxy/arm.svg", "hop", Color(0.58, 0.48, 0.34), "original")
	_add_placeholder("kangaroo_hind_limb", "袋鼠后肢", "lower", "res://art/characters/proxy/leg.svg", "leg", Color(0.64, 0.46, 0.3), "original")
	_add_placeholder("antelope_hind_limb", "类羚羊后肢", "lower", "res://art/characters/proxy/leg.svg", "leg", Color(0.76, 0.62, 0.4), "original")
	_add_placeholder("flying_squirrel_membrane", "类飞鼠翼膜", "upper", "res://art/characters/proxy/wing.svg", "wing", Color(0.55, 0.42, 0.34), "original")
	_add_placeholder("jellyfish_tentacle_wing", "类水母触翼", "upper", "res://art/characters/proxy/wing.svg", "crawl", Color(0.72, 0.62, 0.92), "original")
	_add_placeholder("albino_gorilla_arm", "白化的类猩猩胳膊", "upper", "res://art/characters/anim/arm_upper.png", "arm", Color(1.0, 0.94, 0.91), "albino")
	_add_placeholder("albino_albatross_wing", "白化的类信天翁翅膀", "upper", "res://art/characters/psd/wing_left.png", "wing", Color(1.0, 0.96, 0.92), "albino")
	_add_placeholder("albino_eagle_wing", "白化的类鹰翅膀", "upper", "res://art/characters/psd/wing_left.png", "wing", Color(1.0, 0.9, 0.82), "albino")
	_add_placeholder("albino_gerbil_paw", "白化的类沙鼠前肢", "upper", "res://art/characters/psd/arm_hop.png", "hop", Color(1.0, 0.94, 0.88), "albino")
	_add_placeholder("albino_kangaroo_leg", "白化的类袋鼠腿", "lower", "res://art/characters/psd/leg_left.png", "leg", Color(1.0, 0.93, 0.86), "albino")
	_add_placeholder("albino_octopus_lower", "白化的类章鱼触手（下肢）", "lower", "res://art/characters/psd/leg_left.png", "leg", Color(0.92, 0.9, 1.0), "albino")


static func _add_placeholder(
	limb_id: String,
	display_name: String,
	slot_name: String,
	texture_path: String,
	visual: String,
	tint: Color,
	result_kind: String
) -> void:
	_add(limb_id, display_name, slot_name, "matrix_result", 3, true, "", "", texture_path,
		visual, 1.0, tint, "合成结果；当前使用程序占位美术，不可再次合成", 1.0,
		false, true, result_kind)


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
		style["scale"], style["tint"], part.blurb, 1.0, true, false, "ordinary")


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
	speed_scale: float,
	culture_ingredient := false,
	placeholder_art := false,
	result_kind := "legacy"
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
	limb.culture_ingredient = culture_ingredient
	limb.placeholder_art = placeholder_art
	limb.result_kind = result_kind
	_defs[limb_id] = limb
