extends RefCounted

## 小怪配表。改 data/monsters.json，不要在脚本里再写一套血量和移速。
const PATH := "res://data/monsters.json"
static var _data: Dictionary = {}
static var _loaded := false


static func monster(monster_id: String) -> Dictionary:
	_ensure()
	for entry in _list():
		if str(entry.get("id", "")) == monster_id:
			return _resolved(entry)
	return {}


static func ids() -> PackedStringArray:
	_ensure()
	var names := PackedStringArray()
	for entry in _list():
		names.append(str(entry.get("id", "")))
	return names


static func band(group: String, rank: String) -> float:
	_ensure()
	var bands: Variant = _data.get("bands", {})
	if not bands is Dictionary:
		return 0.0
	var row: Variant = (bands as Dictionary).get(group, {})
	if row is Dictionary and (row as Dictionary).has(rank):
		return float((row as Dictionary)[rank])
	return 0.0


static func _list() -> Array:
	var rows: Variant = _data.get("monsters", [])
	return rows if rows is Array else []


static func _resolved(entry: Dictionary) -> Dictionary:
	var copy := entry.duplicate()
	copy["health"] = int(band("health", str(entry.get("health", "mid"))))
	copy["damage"] = int(band("damage", str(entry.get("damage", "mid"))))
	copy["speed"] = band("speed", str(entry.get("speed", "mid")))
	copy["attack_cooldown"] = band("attack_cooldown", str(entry.get("attack_rate", "mid")))
	copy["pack"] = int(entry.get("pack", 1))
	copy["aggressive"] = bool(entry.get("aggressive", false))
	copy["boss"] = bool(entry.get("boss", false))
	return copy


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_error("缺少小怪配表：" + PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("小怪配表不是对象：" + PATH)
