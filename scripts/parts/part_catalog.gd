class_name PartCatalog
extends RefCounted

# 显示名留给文案改。id 稳定，给存档和刷新表用。
# spawn_scenes 只是刷新元数据，不参与移动判断。


static var _uppers: Array[PartDefinition] = []
static var _lowers: Array[PartDefinition] = []


static func find(part_id: String) -> PartDefinition:
	for part in uppers():
		if part.id == part_id:
			return part
	for part in lowers():
		if part.id == part_id:
			return part
	return null


static func texture_for(part_id: String) -> Texture2D:
	var part := find(part_id)
	if part == null or part.texture_path.is_empty():
		return null
	return load(part.texture_path) as Texture2D


static func uppers() -> Array[PartDefinition]:
	if not _uppers.is_empty():
		return _uppers
	_uppers = [
		_part({
			"id": "gorilla_arm",
			"texture": "res://assets/derived_art/limbs_peipei_20261018/gorilla_arm/primary.png",
			"name": "类猩猩胳膊",
			"slot": PartDefinition.Slot.UPPER,
			"power": PartDefinition.Band.HIGH,
			"rate": PartDefinition.Band.LOW,
			"shape": PartDefinition.AttackShape.FACING,
			"rank": PartDefinition.Rank.R2,
			"scenes": ["岩石"],
			"blurb": "推拉、举起一起跳；靠近硬破坏物会砸碎",
			"abilities": ["push_pull", "lift_jump", "smash_hard"],
			"breakthrough": ["slam_end", "slam_fall"],
		}),
		_part({
			"id": "gibbon_arm",
			"name": "类长臂猿胳膊",
			"slot": PartDefinition.Slot.UPPER,
			"power": PartDefinition.Band.NORMAL,
			"rate": PartDefinition.Band.NORMAL,
			"shape": PartDefinition.AttackShape.FACING,
			"rank": PartDefinition.Rank.R1,
			"scenes": ["岩石", "草原"],
			"blurb": "靠近可爬面时抓住，W/S 上下",
			"abilities": ["grab_climb"],
		}),
		_part({
			"id": "goose_wing",
			"texture": "res://assets/derived_art/limbs_peipei_20261018/goose_wing/primary.png",
			"name": "类鹅翅膀",
			"slot": PartDefinition.Slot.UPPER,
			"power": PartDefinition.Band.LOW,
			"rate": PartDefinition.Band.NORMAL,
			"shape": PartDefinition.AttackShape.FACING,
			"rank": PartDefinition.Rank.R1,
			"scenes": ["草原"],
			"blurb": "表里只有朝向攻击，没有场景能力",
		}),
		_part({
			"id": "octopus_arm",
			"texture": "res://assets/derived_art/limbs_peipei_20261018/octopus_tentacle/primary.png",
			"name": "类章鱼触手",
			"slot": PartDefinition.Slot.UPPER,
			"power": PartDefinition.Band.NORMAL,
			"rate": PartDefinition.Band.NORMAL,
			"shape": PartDefinition.AttackShape.AROUND,
			"rank": PartDefinition.Rank.R2,
			"scenes": ["海洋", "海岸边"],
			"blurb": "原地抓起物件或小怪再抛出；可吸附，沙漠不行",
			"abilities": ["grab_throw"],
			"can_stick": true,
			"stick_blocked": ["desert"],
		}),
		_part({
			"id": "bat_wing",
			"texture": "res://assets/source_art/limbs_20261018/bat_wing/primary.png",
			"name": "类蝙蝠翅膀",
			"slot": PartDefinition.Slot.UPPER,
			"power": PartDefinition.Band.LOW,
			"rate": PartDefinition.Band.HIGH,
			"shape": PartDefinition.AttackShape.FACING,
			"rank": PartDefinition.Rank.R1,
			"scenes": ["岩石"],
			"blurb": "脚离地后短滑行",
			"air": "glide",
		}),
		_part({
			"id": "albatross_wing",
			"texture": "res://assets/source_art/limbs_20261018/albatross_wing/primary.png",
			"name": "类信天翁翅膀",
			"slot": PartDefinition.Slot.UPPER,
			"power": PartDefinition.Band.NORMAL,
			"rate": PartDefinition.Band.LOW,
			"shape": PartDefinition.AttackShape.FACING,
			"rank": PartDefinition.Rank.R2,
			"scenes": ["草原"],
			"blurb": "离地后悬停，按住空格滑向地面",
			"air": "hover",
			"breakthrough": ["hurricane"],
		}),
		_part({
			"id": "eagle_wing",
			"texture": "res://assets/source_art/limbs_20261018/eagle_wing/primary.png",
			"name": "类鹰翅膀",
			"slot": PartDefinition.Slot.UPPER,
			"power": PartDefinition.Band.HIGH,
			"rate": PartDefinition.Band.NORMAL,
			"shape": PartDefinition.AttackShape.FACING,
			"rank": PartDefinition.Rank.R3,
			"scenes": ["草原", "沙漠"],
			"blurb": "空格代替跳跃，自由飞行",
			"air": "flight",
			"breakthrough": ["dive"],
		}),
		_part({
			"id": "gerbil_paw",
			"name": "类沙鼠前肢",
			"slot": PartDefinition.Slot.UPPER,
			"power": PartDefinition.Band.LOW,
			"rate": PartDefinition.Band.HIGH,
			"shape": PartDefinition.AttackShape.FACING,
			"rank": PartDefinition.Rank.R2,
			"scenes": ["沙漠"],
			"blurb": "在流体里快速挖软破坏物",
			"abilities": ["dig_soft"],
			"breakthrough": ["burrow_ambush"],
		}),
	]
	return _uppers


static func lowers() -> Array[PartDefinition]:
	if not _lowers.is_empty():
		return _lowers
	_lowers = [
		_part({
			"id": "wolf_leg",
			"texture": "res://assets/source_art/limbs_20261018/wolf_leg/body.png",
			"name": "类草原狼腿",
			"slot": PartDefinition.Slot.LOWER,
			"rank": PartDefinition.Rank.R1,
			"scenes": ["草原"],
			"blurb": "只在硬表面上中速移动",
			"speed": PartDefinition.Band.NORMAL,
			"surfaces": ["hard"],
		}),
		_part({
			"id": "ostrich_leg",
			"texture": "res://assets/source_art/limbs_20261018/ostrich_leg/body.png",
			"name": "类鸵鸟腿",
			"slot": PartDefinition.Slot.LOWER,
			"rank": PartDefinition.Rank.R1,
			"scenes": ["沙漠"],
			"blurb": "只在硬表面上高速移动",
			"speed": PartDefinition.Band.HIGH,
			"surfaces": ["hard"],
		}),
		_part({
			"id": "gerbil_leg",
			"texture": "res://assets/source_art/limbs_20261018/gerbil_leg/body.png",
			"name": "类沙鼠腿",
			"slot": PartDefinition.Slot.LOWER,
			"rank": PartDefinition.Rank.R2,
			"scenes": ["沙漠"],
			"blurb": "只在硬表面上遁地，中速",
			"speed": PartDefinition.Band.NORMAL,
			"surfaces": ["hard"],
			"burrow": true,
		}),
		_part({
			"id": "kangaroo_leg",
			"texture": "res://assets/source_art/limbs_20261018/kangaroo_leg/body.png",
			"name": "类袋鼠腿",
			"slot": PartDefinition.Slot.LOWER,
			"rank": PartDefinition.Rank.R2,
			"scenes": ["沙漠"],
			"blurb": "硬表面高速，一段跳",
			"speed": PartDefinition.Band.HIGH,
			"surfaces": ["hard"],
			"jumps": 1,
			"breakthrough_jumps": 2,
			"breakthrough": ["smash_near"],
		}),
		_part({
			"id": "demon_dog_leg",
			"texture": "res://assets/derived_art/limbs_peipei_20261018/demon_dog_leg/full_body_primary.png",
			"name": "类恶魔犬腿",
			"slot": PartDefinition.Slot.LOWER,
			"rank": PartDefinition.Rank.R2,
			"scenes": ["草原", "岩石"],
			"blurb": "表里没写移动，暂时慢速占位",
		}),
		_part({
			"id": "octopus_leg",
			"texture": "res://assets/derived_art/limbs_peipei_20261018/octopus_tentacle/primary.png",
			"name": "类章鱼触手",
			"slot": PartDefinition.Slot.LOWER,
			"rank": PartDefinition.Rank.R2,
			"scenes": ["海洋", "海岸边"],
			"blurb": "流体和硬表面都能中速移动",
			"speed": PartDefinition.Band.NORMAL,
			"swim": "fluid_and_hard",
			"breakthrough_stick_any": true,
		}),
		_part({
			"id": "goose_foot",
			"texture": "res://assets/derived_art/limbs_peipei_20261018/goose_foot/primary.png",
			"name": "类鹅蹼",
			"slot": PartDefinition.Slot.LOWER,
			"rank": PartDefinition.Rank.R1,
			"scenes": ["海岸边"],
			"blurb": "流体表面高速或停住，硬表面慢",
			"swim": "skim",
		}),
		_part({
			"id": "water_snake",
			"name": "类水蛇尾",
			"slot": PartDefinition.Slot.LOWER,
			"rank": PartDefinition.Rank.R1,
			"scenes": ["海洋", "海岸边"],
			"blurb": "流体里停住会沉，硬表面中速",
			"swim": "sink",
		}),
		_part({
			"id": "fish_tail",
			"texture": "res://assets/source_art/limbs_20261018/fish_tail/primary.png",
			"name": "类鱼尾",
			"slot": PartDefinition.Slot.LOWER,
			"rank": PartDefinition.Rank.R1,
			"scenes": ["海洋"],
			"blurb": "只在流体里高速游，或停住悬浮",
			"swim": "hover_fast",
		}),
	]
	return _lowers


static func _part(data: Dictionary) -> PartDefinition:
	var part := PartDefinition.new()
	part.id = data["id"]
	part.display_name = data["name"]
	part.slot = data.get("slot", PartDefinition.Slot.UPPER)
	part.attack_power = data.get("power", PartDefinition.Band.NONE)
	part.attack_rate = data.get("rate", PartDefinition.Band.NONE)
	part.attack_shape = data.get("shape", PartDefinition.AttackShape.NONE)
	part.rank = data.get("rank", PartDefinition.Rank.R1)
	part.spawn_scenes = PackedStringArray(data.get("scenes", PackedStringArray()))
	part.blurb = data.get("blurb", "")
	part.texture_path = data.get("texture", "")
	part.speed_band = data.get("speed", PartDefinition.Band.NONE)
	part.allowed_surfaces = PackedStringArray(data.get("surfaces", PackedStringArray()))
	part.jump_count = data.get("jumps", 0)
	part.breakthrough_jump_count = data.get("breakthrough_jumps", 0)
	part.air_mode = data.get("air", "")
	part.burrow = data.get("burrow", false)
	part.swim = data.get("swim", "")
	part.can_stick = data.get("can_stick", false)
	part.stick_blocked_tags = PackedStringArray(data.get("stick_blocked", PackedStringArray()))
	part.breakthrough_stick_any = data.get("breakthrough_stick_any", false)
	part.abilities = PackedStringArray(data.get("abilities", PackedStringArray()))
	part.breakthrough = PackedStringArray(data.get("breakthrough", PackedStringArray()))
	return part
