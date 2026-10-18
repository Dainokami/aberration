extends RefCounted

## 肢体主动回收的血液。改 data/recycle.json，悬浮提示和回收入账都读这张表。
const PATH := "res://data/recycle.json"
static var _data: Dictionary = {}
static var _loaded := false


static func amount(limb_id: String) -> int:
	_ensure()
	var value: Variant = _data.get(limb_id, 0)
	if value is Dictionary:
		return int((value as Dictionary).get("blood", 0))
	if value is float or value is int:
		return int(value)
	return 0


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_warning("缺少回收配表：" + PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("回收配表不是对象：" + PATH)
