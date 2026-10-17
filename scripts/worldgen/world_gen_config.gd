@tool
class_name WorldGenConfig
extends Resource

const ALGORITHM_VERSION := 1
const FIELDS := ["seed_value", "width", "height", "region_count", "boundary_noise",
	"grass_weight", "rock_weight", "sand_weight", "water_weight",
	"spawn_radius", "static_count", "static_radius", "falloff",
	"prefab_budget", "prefab_gap", "resource_density", "environment_density",
	"cluster_gap", "item_gap", "prefabs"]

@export var seed_value := 20261018
@export var width := 64
@export var height := 64
@export var region_count := 12
@export var boundary_noise := 0.22
@export var grass_weight := 4.0
@export var rock_weight := 3.0
@export var sand_weight := 2.0
@export var water_weight := 1.0
## Distances are in cells (2 m).
@export var spawn_radius := 6.0
@export var static_count := 3
@export var static_radius := 9.0
@export var falloff := 8.0
@export var prefab_budget := 6
@export var prefab_gap := 3
## Target instances per 1000 map cells, subject to support and spacing.
@export var resource_density := 6.0
@export var environment_density := 3.0
@export var cluster_gap := 9.0
@export var item_gap := 2.0
## path, minimum, maximum, weight, zone (any/explore/static), rotate.
@export var prefabs: Array[Dictionary] = []

func snapshot() -> Dictionary:
	var result := {"algorithm_version": ALGORITHM_VERSION}
	for field in FIELDS:
		var value: Variant = get(field)
		result[field] = value.duplicate(true) if value is Array else value
	return result

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if width < 16 or height < 16 or width > 600 or height > 600:
		result.append("宽高须为 16～600 格（每格 2m）")
	if region_count < 1 or region_count > 64:
		result.append("生态区域数须为 1～64")
	var total := 0.0
	for weight in [grass_weight, rock_weight, sand_weight, water_weight]:
		if not is_finite(weight) or weight < 0:
			result.append("生态权重必须是非负有限数")
		total += weight
	if total <= 0:
		result.append("至少启用一种生态")
	for value in [boundary_noise, spawn_radius, static_radius, falloff,
			resource_density, environment_density, cluster_gap, item_gap]:
		if not is_finite(value) or value < 0:
			result.append("半径、密度和间距必须是非负有限数")
	if boundary_noise > 1 or static_count < 0 or static_count > 16:
		result.append("边界起伏须为 0～1，静止核心数须为 0～16")
	if spawn_radius < 2 or spawn_radius >= minf(width, height) * 0.5 - 1:
		result.append("出生核心半径须至少 2 格且小于短边的一半减 1")
	if prefab_budget < 0 or prefab_budget > 32 or prefab_gap < 1:
		result.append("特殊地块预算须为 0～32，间距至少 1 格")
	if resource_density > 50 or environment_density > 50 or item_gap < 1:
		result.append("密度须不超过 50 件/千格，物件间距至少 1 格")
	var required := 0
	for rule in prefabs:
		var minimum := int(rule.get("minimum", 1))
		var maximum := int(rule.get("maximum", 1))
		required += minimum
		if minimum < 0 or maximum < minimum or maximum > 32:
			result.append("特殊地块最少/最多次数无效：" + str(rule.get("path", "")))
		if float(rule.get("weight", 1.0)) < 0 or not is_finite(float(rule.get("weight", 1.0))):
			result.append("特殊地块权重无效")
		if str(rule.get("zone", "any")) not in ["any", "explore", "static"]:
			result.append("特殊地块区域约束无效")
	if required > prefab_budget:
		result.append("必选特殊地块共 %d 件，超过预算 %d" % [required, prefab_budget])
	return result
