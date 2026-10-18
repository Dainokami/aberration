@tool
class_name EncounterConfig
extends Resource

@export var enabled := false
@export var seed_value := 20261018
@export var interval := 10.0
@export var count_min := 1
@export var count_max := 2
@export var radius_min := 9.0
@export var radius_max := 12.0
@export var use_source_personality := false
@export var monster_pool: Array[Dictionary] = []
@export var elite_one := "res://data/monsters/gorilla.tres"
@export var elite_two := "res://data/monsters/wolf.tres"
@export var elite_one_time := 300.0
@export var elite_two_time := 600.0
@export var elite_health_multiplier := 3.0
@export var elite_damage_multiplier := 1.5
@export var elite_one_ecosystems: PackedStringArray = []
@export var elite_two_ecosystems: PackedStringArray = []
@export var boss_early_time := 900.0
@export var boss_force_time := 1200.0
@export var safe_radius := 30.0
@export var fog_speed := 3.0
@export var fog_player_damage := 5.0
@export var fog_monster_damage := 100.0
@export var player_health := 100.0
@export_file("*.tscn") var boss_scene := ""

static func default_config() -> EncounterConfig:
	var config := EncounterConfig.new()
	for path in catalog_paths():
		var monster := load(path) as MonsterDefinition
		if monster != null:
			config.monster_pool.append({"path": path, "weight": 1.0,
				"enabled": monster.available()})
	return config

static func catalog_paths() -> PackedStringArray:
	var result := PackedStringArray()
	for file in DirAccess.get_files_at("res://data/monsters"):
		if file.ends_with(".tres"):
			result.append("res://data/monsters/" + file)
	result.sort()
	return result

func definition_for(path: String, rule: Dictionary = {}) -> MonsterDefinition:
	var source := load(path) as MonsterDefinition
	if source == null:
		return null
	var monster := source.duplicate(true) as MonsterDefinition
	for field in ["max_health", "damage", "speed", "attack_interval", "ecosystems"]:
		if rule.has(field):
			monster.set(field, rule[field])
	return monster

func elite_definition(index: int) -> MonsterDefinition:
	var ecosystems := elite_one_ecosystems if index == 0 else elite_two_ecosystems
	return definition_for(elite_one if index == 0 else elite_two,
		{} if ecosystems.is_empty() else {"ecosystems": ecosystems})

func ordinary_definition(rule: Dictionary) -> MonsterDefinition:
	var values := rule.duplicate(true)
	values.erase("ecosystems")
	return definition_for(str(rule.get("path", "")), values)

func snapshot() -> Dictionary:
	var result := {}
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant = get(property.name)
			result[property.name] = value.duplicate(true) if value is Array \
				or value is Dictionary else value
	return result

static func from_snapshot(values: Dictionary) -> EncounterConfig:
	var config := EncounterConfig.new()
	for field in values:
		config.set(field, values[field])
	return config

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	for value in [interval, radius_min, radius_max, elite_one_time, elite_two_time,
			elite_health_multiplier, elite_damage_multiplier, boss_early_time,
			boss_force_time, safe_radius, fog_speed, player_health]:
		if not is_finite(value) or value <= 0:
			result.append("刷新、时间、半径和生命配置必须为正有限数")
			break
	for value in [fog_player_damage, fog_monster_damage]:
		if not is_finite(value) or value < 0:
			result.append("浓雾伤害必须为非负有限数")
	if count_min < 1 or count_max < count_min or count_max > 20 or radius_max < radius_min:
		result.append("普通怪数量或生成圆环无效")
	if elite_two_time < elite_one_time or boss_early_time < elite_two_time \
			or boss_force_time < boss_early_time:
		result.append("时间节点顺序无效")
	if not boss_scene.is_empty() and (not ResourceLoader.exists(boss_scene)
			or not load(boss_scene) is PackedScene):
		result.append("Boss 目标场景不存在")
	var usable := 0
	for rule in monster_pool:
		if not bool(rule.get("enabled", true)):
			continue
		var weight := float(rule.get("weight", 1.0))
		if not is_finite(weight) or weight < 0:
			result.append("怪池权重无效")
			continue
		var path := str(rule.get("path", ""))
		var monster := ordinary_definition(rule) if ResourceLoader.exists(path) else null
		if monster == null:
			result.append("怪物定义缺失")
		else:
			result.append_array(monster.errors())
			if weight > 0 and monster.available():
				usable += 1
	if usable == 0:
		result.append("至少启用一种已有美术的普通怪")
	for i in 2:
		var path := elite_one if i == 0 else elite_two
		var monster := elite_definition(i) if ResourceLoader.exists(path) else null
		if monster == null:
			result.append("精英怪定义缺失：" + path)
		else:
			result.append_array(monster.errors())
	return result
