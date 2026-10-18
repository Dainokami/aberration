class_name MovementTable
extends RefCounted

## 玩家移动手感的唯一配表。改 data/movement.json，不要在脚本里另写一套速度。
const PATH := "res://data/movement.json"
static var _data: Dictionary = {}
static var _loaded := false


static func number(section: String, key: String, fallback: float) -> float:
	_ensure()
	var group: Variant = _data.get(section, {})
	if group is Dictionary and (group as Dictionary).has(key):
		return float((group as Dictionary)[key])
	return fallback


static func band(name: String, fallback: float) -> float:
	return number("speed_bands", name, fallback)


static func gait(mode: String, key: String, fallback: float) -> float:
	_ensure()
	var gaits: Variant = _data.get("gaits", {})
	if not gaits is Dictionary:
		return fallback
	var entry: Variant = (gaits as Dictionary).get(mode, {})
	if entry is Dictionary and (entry as Dictionary).has(key):
		return float((entry as Dictionary)[key])
	return fallback


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_warning("缺少移动配表，3C 将使用脚本内默认值：" + PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("移动配表不是对象：" + PATH)
