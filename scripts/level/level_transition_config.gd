@tool
class_name LevelTransitionConfig
extends Resource

const DEFAULT_TARGET := "res://data/levels/portal_destination_demo.tres"

@export var enabled := true
@export_range(0.1, 7200.0, 0.1) var countdown_seconds := 60.0
@export_file("*.tres") var target_level := DEFAULT_TARGET
@export_range(2.0, 32.0, 0.5) var radius_min := 4.0
@export_range(2.0, 32.0, 0.5) var radius_max := 8.0

func snapshot() -> Dictionary:
	return {"enabled": enabled, "countdown_seconds": countdown_seconds,
		"target_level": target_level, "radius_min": radius_min, "radius_max": radius_max}

static func from_snapshot(values: Dictionary) -> LevelTransitionConfig:
	var result := LevelTransitionConfig.new()
	for field in result.snapshot():
		if values.has(field):
			result.set(field, values[field])
	return result

func errors(check_target := true) -> PackedStringArray:
	var result := PackedStringArray()
	if not enabled:
		return result
	if not is_finite(countdown_seconds) or countdown_seconds < 0.1 or countdown_seconds > 7200:
		result.append("传送门倒计时必须为 0.1–7200 秒")
	if not is_finite(radius_min) or not is_finite(radius_max) \
			or radius_min < 2 or radius_max > 32 or radius_max < radius_min:
		result.append("传送门生成距离须满足 2 ≤ 最近距离 ≤ 最远距离 ≤ 32 米")
	if check_target:
		if target_level.is_empty() or not ResourceLoader.exists(target_level):
			result.append("传送门目标地图不存在")
		elif not ResourceLoader.load(target_level) is LevelData:
			result.append("传送门目标必须是 LevelData 地图")
	return result
