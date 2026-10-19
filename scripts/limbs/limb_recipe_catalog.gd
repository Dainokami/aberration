class_name LimbRecipeCatalog
extends RefCounted

# 飞书肢体能力表中的 17 个基础原料。索引顺序与策划矩阵的表头一致。
const INGREDIENT_IDS := [
	"gorilla_arm",
	"gibbon_arm",
	"goose_wing",
	"octopus_arm",
	"bat_wing",
	"albatross_wing",
	"eagle_wing",
	"gerbil_paw",
	"wolf_leg",
	"ostrich_leg",
	"gerbil_leg",
	"kangaroo_leg",
	"demon_dog_leg",
	"octopus_leg",
	"goose_foot",
	"water_snake",
	"fish_tail",
]

# 组合无序，因此只保存矩阵上三角。第 i 行第 j 项对应
# INGREDIENT_IDS[i] + INGREDIENT_IDS[i + j]，共 153 项。
# 用户提供的完整矩阵有三处镜像冲突；这里统一以上三角为准，详见 CULTURE_MATRIX.md。
const RESULT_ROWS := [
	[
		"albino_gorilla_arm", "octopus_arm", "scrap", "gibbon_arm", "scrap",
		"bat_wing", "bat_wing", "pangolin_dig_claw", "kangaroo_leg",
		"kangaroo_hind_limb", "pangolin_dig_claw", "albino_gorilla_arm",
		"kangaroo_leg", "octopus_arm", "scrap", "octopus_arm", "scrap",
	],
	[
		"gorilla_arm", "bat_wing", "gorilla_arm", "flying_squirrel_membrane",
		"flying_squirrel_membrane", "bat_wing", "gorilla_arm", "antelope_hind_limb",
		"antelope_hind_limb", "kangaroo_leg", "ostrich_leg", "kangaroo_leg",
		"octopus_arm", "octopus_arm", "octopus_arm", "scrap",
	],
	[
		"bat_wing", "scrap", "albatross_wing", "albino_albatross_wing",
		"albatross_wing", "bat_wing", "bat_wing", "bat_wing", "scrap",
		"bat_wing", "bat_wing", "goose_foot", "water_snake", "goose_foot", "goose_foot",
	],
	[
		"gibbon_arm", "albatross_wing", "scrap", "bat_wing", "gorilla_arm",
		"octopus_leg", "octopus_leg", "octopus_leg", "octopus_leg", "scrap",
		"jellyfish_tentacle_wing", "jellyfish_tentacle_wing", "octopus_leg", "octopus_leg",
	],
	[
		"albatross_wing", "eagle_wing", "albatross_wing", "goose_wing",
		"flying_squirrel_membrane", "flying_squirrel_membrane", "goose_wing",
		"goose_wing", "goose_wing", "goose_foot", "scrap", "goose_foot", "goose_foot",
	],
	[
		"albino_albatross_wing", "bat_wing", "bat_wing", "bat_wing", "bat_wing",
		"scrap", "bat_wing", "bat_wing", "goose_foot", "water_snake", "goose_foot", "goose_foot",
	],
	[
		"albino_eagle_wing", "bat_wing", "bat_wing", "albino_eagle_wing", "scrap",
		"bat_wing", "scrap", "goose_foot", "scrap", "goose_foot", "goose_foot",
	],
	[
		"albino_gerbil_paw", "pangolin_dig_claw", "gerbil_leg", "albino_gerbil_paw",
		"gerbil_leg", "scrap", "gerbil_leg", "scrap", "gerbil_leg", "scrap",
	],
	[
		"ostrich_leg", "antelope_hind_limb", "ostrich_leg", "antelope_hind_limb",
		"ostrich_leg", "water_snake", "octopus_leg", "octopus_leg", "scrap",
	],
	[
		"wolf_leg", "wolf_leg", "kangaroo_leg", "wolf_leg", "water_snake",
		"octopus_leg", "octopus_leg", "scrap",
	],
	[
		"ostrich_leg", "albino_kangaroo_leg", "ostrich_leg", "water_snake",
		"octopus_leg", "octopus_leg", "scrap",
	],
	[
		"albino_kangaroo_leg", "kangaroo_leg", "water_snake", "octopus_leg", "octopus_leg", "scrap",
	],
	[
		"ostrich_leg", "scrap", "scrap", "octopus_leg", "scrap",
	],
	[
		"albino_octopus_lower", "water_snake", "albino_octopus_lower", "water_snake",
	],
	[
		"octopus_leg", "octopus_leg", "octopus_leg",
	],
	[
		"octopus_leg", "octopus_leg",
	],
	[
		"octopus_leg",
	],
]

const ORIGINAL_RESULT_IDS := [
	"pangolin_dig_claw",
	"kangaroo_hind_limb",
	"antelope_hind_limb",
	"flying_squirrel_membrane",
	"jellyfish_tentacle_wing",
]

const ALBINO_RESULT_IDS := [
	"albino_gorilla_arm",
	"albino_albatross_wing",
	"albino_eagle_wing",
	"albino_gerbil_paw",
	"albino_kangaroo_leg",
	"albino_octopus_lower",
]


static func is_ingredient(limb_id: String) -> bool:
	return INGREDIENT_IDS.has(limb_id)


static func combine(left_id: String, right_id: String) -> String:
	var left_index := INGREDIENT_IDS.find(left_id)
	var right_index := INGREDIENT_IDS.find(right_id)
	if left_index < 0 or right_index < 0:
		return ""
	var row := mini(left_index, right_index)
	var column := maxi(left_index, right_index)
	return RESULT_ROWS[row][column - row]


static func recipe_count() -> int:
	var count := 0
	for row: Array in RESULT_ROWS:
		count += row.size()
	return count


static func result_counts() -> Dictionary:
	var counts := {"ordinary": 0, "original": 0, "albino": 0, "scrap": 0, "rare": 0}
	for row: Array in RESULT_ROWS:
		for result_id in row:
			if result_id == "scrap":
				counts["scrap"] += 1
			elif ORIGINAL_RESULT_IDS.has(result_id):
				counts["original"] += 1
				counts["rare"] += 1
			elif ALBINO_RESULT_IDS.has(result_id):
				counts["albino"] += 1
				counts["rare"] += 1
			else:
				counts["ordinary"] += 1
	return counts


static func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if INGREDIENT_IDS.size() != 17:
		errors.append("ingredient count is %d, expected 17" % INGREDIENT_IDS.size())
	if RESULT_ROWS.size() != INGREDIENT_IDS.size():
		errors.append("matrix row count does not match ingredient count")
	for row_index in RESULT_ROWS.size():
		var expected := INGREDIENT_IDS.size() - row_index
		if RESULT_ROWS[row_index].size() != expected:
			errors.append("row %d has %d results, expected %d" % [row_index, RESULT_ROWS[row_index].size(), expected])
		for result_id in RESULT_ROWS[row_index]:
			if LimbCatalog.find(result_id) == null:
				errors.append("missing result definition: " + result_id)
	for left_id in INGREDIENT_IDS:
		for right_id in INGREDIENT_IDS:
			if combine(left_id, right_id) != combine(right_id, left_id):
				errors.append("order changed result: %s + %s" % [left_id, right_id])
	for result_id in ORIGINAL_RESULT_IDS + ALBINO_RESULT_IDS + ["scrap"]:
		var result := LimbCatalog.find(result_id)
		if result == null:
			continue
		if result.culture_ingredient:
			errors.append("restricted result is still an ingredient: " + result_id)
		var delivered: bool = result_id in PackedStringArray(["pangolin_dig_claw", "albino_albatross_wing", "albino_eagle_wing"])
		if delivered and result.placeholder_art:
			errors.append("delivered art is still marked as placeholder: " + result_id)
		elif not delivered and not result.placeholder_art:
			errors.append("missing-art result is not marked as placeholder: " + result_id)
		if LimbCatalog.texture_for(result_id) == null:
			errors.append("placeholder texture cannot be loaded: " + result_id)
	return errors
