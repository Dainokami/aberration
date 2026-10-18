@tool
class_name WorldGenerator
extends RefCounted

const TILES := ["grass", "rock", "sand", "water"]
const COLLECTIBLES := ["resource", "fruit_tree", "remains"]
var _mutex := Mutex.new()
var _cancelled := false
var _stage := "准备"
var _rng := RandomNumberGenerator.new()
var _config: WorldGenConfig
var _data: LevelData
var _zones := PackedByteArray()
var _reserved := {}
var _roads := {}
var _placements: Array[Dictionary] = []
var _warnings := PackedStringArray()
var _sources: Array[Dictionary] = []
var _definitions: Array[PlaceableDefinition] = []

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func status() -> String:
	_mutex.lock()
	var value := _stage
	_mutex.unlock()
	return value

func _set_stage(value: String) -> void:
	_mutex.lock()
	_stage = value
	_mutex.unlock()

func _stopped() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value

## Run on the main thread before starting the worker. Sources are private copies.
func prepare(config: WorldGenConfig) -> String:
	_config = config.duplicate(true) as WorldGenConfig
	var errors := _config.errors()
	if not errors.is_empty():
		return "\n".join(errors)
	TileRegistry.all_tiles()
	_sources.clear()
	_definitions.clear()
	_cancelled = false
	for rule in _config.prefabs:
		var path := str(rule.get("path", ""))
		if not path.begins_with("res://") or not ResourceLoader.exists(path):
			return "特殊地块资源不存在：" + path
		var resource := load(path)
		var original: LevelData
		var title := path.get_file().get_basename()
		if resource is LevelPrefab:
			original = resource.fragment
			title = resource.display_name
		elif resource is LevelData:
			original = resource
		if original == null:
			return "请选择 LevelData 地图或 LevelPrefab：" + path
		var prefab := LevelPrefab.new()
		prefab.display_name = title
		prefab.fragment = LevelData.new()
		prefab.fragment.restore_data(original.clone_data())
		prefab.fragment.spawn_cell = Vector2i(-1, -1)
		prefab.fragment.spawn_layer = -1
		var source_errors := prefab.fragment.validate()
		source_errors.erase("缺少有效的玩家出生点")
		if not source_errors.is_empty():
			return title + " 数据无效：\n" + "\n".join(source_errors)
		var resource_cells: Array[Vector2i] = []
		var blocked := {}
		for record in prefab.fragment.objects:
			var definition := ObjectRules.definition(record)
			_definitions.append(definition)
			for cell in ObjectRules.covered_cells(prefab.fragment, record):
				blocked[cell - prefab.fragment.map_origin] = true
				if definition.mechanism in COLLECTIBLES:
					resource_cells.append(cell - prefab.fragment.map_origin)
		var padding := _exterior_padding(prefab.fragment) if bool(rule.get("blend_edges", true)) else {}
		var entries := _source_entries(prefab.fragment, padding, blocked)
		var height_offset := 0
		if bool(rule.get("align_height", true)) and not entries.is_empty():
			# Use the prevalent perimeter ground, not a randomly chosen hilltop.
			var counts := {}
			for entry in entries:
				var layer := int(entry.layer)
				counts[layer] = int(counts.get(layer, 0)) + 1
			var baseline := -1
			var count := 0
			for layer: int in counts:
				if int(counts[layer]) > count or (int(counts[layer]) == count and layer < baseline):
					baseline = layer
					count = int(counts[layer])
			height_offset = 1 - baseline
			entries = entries.filter(func(entry: Dictionary): return int(entry.layer) == baseline)
			var shifted := _shift_prefab(prefab, height_offset)
			if not str(shifted.error).is_empty():
				return title + " 无法对齐世界地面：\n" + str(shifted.error)
		if entries.is_empty():
			return title + " 没有可接入边缘：需要无物件/阶梯阻挡的 0～2 层实体顶面"
		_sources.append({"prefab": prefab, "rule": rule, "entries": entries,
			"padding": padding, "height_offset": height_offset,
			"collectibles": resource_cells, "name": title,
			"digest": var_to_str(prefab.fragment.clone_data()).sha256_text()})
	for folder in DirAccess.get_directories_at("res://assets/generated"):
		if not folder.begins_with("scene1016_"):
			continue
		var path := "res://assets/generated/%s/definition.tres" % folder
		if not ResourceLoader.exists(path):
			continue
		var definition := load(path) as PlaceableDefinition
		if definition != null and definition.carrier != PlaceableDefinition.Carrier.WALL \
				and definition.validate_asset().is_empty() and ResourceLoader.exists(definition.scene_path):
			_definitions.append(definition)
	_definitions.sort_custom(func(a: PlaceableDefinition, b: PlaceableDefinition):
		return a.resource_path < b.resource_path)
	return ""

## Only wholly empty columns connected to the map boundary are unpainted margins.
## Enclosed holes, water and air slots within an authored column remain authored.
func _exterior_padding(fragment: LevelData) -> Dictionary:
	var empty := {}
	var padding := {}
	var queue: Array[Vector2i] = []
	for y in fragment.map_size.y:
		for x in fragment.map_size.x:
			var local := Vector2i(x, y)
			if fragment.top_layer(fragment.map_origin + local) >= 0:
				continue
			empty[local] = true
			if x == 0 or y == 0 or x == fragment.map_size.x - 1 or y == fragment.map_size.y - 1:
				padding[local] = true
				queue.append(local)
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		for offset: Vector2i in LevelData.DIRS:
			var next := cell + offset
			if empty.has(next) and not padding.has(next):
				padding[next] = true
				queue.append(next)
	return padding

func _source_entries(fragment: LevelData, padding: Dictionary, blocked: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var bounds := Rect2i(Vector2i.ZERO, fragment.map_size)
	for y in fragment.map_size.y:
		for x in fragment.map_size.x:
			var local := Vector2i(x, y)
			var cell := local + fragment.map_origin
			var layer := fragment.top_layer(cell)
			if layer < 0 or layer > 2 or blocked.has(local) \
					or not fragment.is_solid_layer(cell, layer) or fragment.stair_at(cell) >= 0:
				continue
			for direction in 4:
				var outside: Vector2i = local + LevelData.DIRS[direction]
				if (bounds.has_point(outside) and not padding.has(outside)) or blocked.has(outside):
					continue
				entries.append({"cell": local, "direction": direction, "layer": layer})
	return entries

## Translate the whole private fragment, including stable air slots and content.
## A downward translation may remove only empty slots; never clip authored blocks.
func _shift_prefab(prefab: LevelPrefab, height_offset: int) -> Dictionary:
	if height_offset == 0:
		return {"error": "", "prefab": prefab}
	var snapshot := prefab.fragment.clone_data()
	for column: Dictionary in snapshot.columns:
		var layers: Array = column.layers
		if layers.is_empty():
			continue
		if height_offset > 0:
			if layers.size() + height_offset > LevelData.MAX_LAYERS:
				return {"error": "整体抬升后超过最大层级"}
			for i in height_offset:
				layers.push_front({})
		else:
			for i in -height_offset:
				if not layers.is_empty() and not layers[0].is_empty():
					return {"error": "整体下降会裁掉原有地形，请关闭「地面齐平」或调整源地图"}
				if not layers.is_empty():
					layers.pop_front()
	for stair: Dictionary in snapshot.stairs:
		stair.layer = int(stair.layer) + height_offset
	for record: Dictionary in snapshot.objects + snapshot.details:
		record.anchor_layer = int(record.anchor_layer) + height_offset
		record.position += Vector3.UP * height_offset * LevelData.ELEVATION_STEP
	# Prefabs never transfer a player spawn.
	snapshot.spawn_cell = Vector2i(-1, -1)
	snapshot.spawn_layer = -1
	var shifted := LevelPrefab.new()
	shifted.display_name = prefab.display_name
	shifted.fragment = LevelData.new()
	shifted.fragment.restore_data(snapshot)
	var errors := shifted.fragment.validate()
	errors.erase("缺少有效的玩家出生点")
	return {"error": "\n".join(errors), "prefab": shifted}

## Keep the normal prefab tool's exact-copy semantics; blending belongs to worldgen.
func _stamp_prefab(prefab: LevelPrefab, anchor: Vector2i, turns: int, padding: Dictionary,
		height_offset := 0) -> Dictionary:
	var shifted := _shift_prefab(prefab, height_offset)
	if not str(shifted.error).is_empty():
		return {"error": shifted.error}
	var result := (shifted.prefab as LevelPrefab).stamp(_data, anchor, turns)
	if not str(result.get("error", "")).is_empty():
		return result
	# For an uplift, retain world substrate below the translated authored layers.
	# Air within the source column and enclosed empty columns remain untouched.
	if height_offset > 0:
		for y in prefab.fragment.map_size.y:
			for x in prefab.fragment.map_size.x:
				var local := Vector2i(x, y)
				if prefab.fragment.layer_count(prefab.fragment.map_origin + local) == 0:
					continue
				var cell := anchor + prefab.rotate_cell(local, turns)
				var layers: Array = result.snapshot.columns[_data.index(cell)].layers
				for layer in height_offset:
					layers[layer] = _data.get_layer(cell, layer).duplicate(true)
	for local: Vector2i in padding:
		var cell := anchor + prefab.rotate_cell(local, turns)
		result.snapshot.columns[_data.index(cell)] = _data.column_snapshot(cell)
	var candidate := LevelData.new()
	candidate.restore_data(result.snapshot)
	var errors := candidate.validate()
	errors.erase("缺少有效的玩家出生点")
	if not errors.is_empty():
		return {"error": "\n".join(errors)}
	return result

## No scene tree or editor access in the worker.
func generate() -> Dictionary:
	if _config == null:
		return {"error": "生成器尚未准备"}
	_rng.seed = _config.seed_value
	_reserved.clear()
	_roads.clear()
	_placements.clear()
	_warnings.clear()
	_data = LevelData.new()
	_data.setup_blank(Vector2i(_config.width, _config.height))
	_data.spawn_cell = _data.map_size / 2
	_data.spawn_layer = 1
	_set_stage("生成生态与功能区")
	_build_terrain()
	if _stopped():
		return {"error": "已取消"}
	_set_stage("投放特殊地块")
	var error := _place_prefabs()
	if not error.is_empty():
		return {"error": error}
	if _stopped():
		return {"error": "已取消"}
	_set_stage("连接特殊地块入口")
	error = _connect()
	if not error.is_empty():
		return {"error": error}
	_set_stage("散布资源与环境物件")
	_scatter(true, _config.resource_density)
	_scatter(false, _config.environment_density)
	if _stopped():
		return {"error": "已取消"}
	_stable_ids()
	_set_stage("校验地图与可达性")
	var errors := _data.validate()
	if not errors.is_empty():
		return {"error": "生成结果未通过校验：\n" + "\n".join(errors)}
	error = _check_reachability()
	if not error.is_empty():
		return {"error": error}
	var counts := [0, 0, 0, 0]
	for y in _data.map_size.y:
		for x in _data.map_size.x:
			var tile := _data.tile_id(Vector2i(x, y))
			var index := TILES.find(tile)
			if index >= 0:
				counts[index] += 1
	var provenance: Array[Dictionary] = []
	for source in _sources:
		provenance.append({"path": source.rule.path, "sha256": source.digest})
	var road_cells: Array[Vector2i] = []
	road_cells.assign(_roads.keys())
	_data.generation = {"algorithm_version": WorldGenConfig.ALGORITHM_VERSION,
		"recipe": _config.snapshot(), "zone_origin": _data.map_origin,
		"zone_size": _data.map_size, "zones": _zones,
		"placements": _placements.duplicate(true), "roads": road_cells,
		"sources": provenance, "warnings": _warnings, "biome_counts": counts}
	_set_stage("完成")
	return {"error": "", "data": _data, "warnings": _warnings}

func _random_cell(margin := 0) -> Vector2i:
	return Vector2i(_rng.randi_range(margin, _config.width - 1 - margin),
		_rng.randi_range(margin, _config.height - 1 - margin))

func _weighted(weights: Array) -> int:
	var total := 0.0
	for value in weights:
		total += float(value)
	if total <= 0:
		return -1
	var roll := _rng.randf() * total
	for i in weights.size():
		roll -= float(weights[i])
		if roll < 0:
			return i
	return weights.size() - 1

func _build_terrain() -> void:
	var centers: Array[Vector2i] = []
	var biomes: Array[int] = []
	var weights := [_config.grass_weight, _config.rock_weight,
		_config.sand_weight, _config.water_weight]
	for i in _config.region_count:
		var best := _random_cell()
		var best_distance := -1.0
		for attempt in 16:
			var candidate := _random_cell()
			var distance := INF
			for center in centers:
				distance = minf(distance, Vector2(candidate).distance_squared_to(center))
			if distance > best_distance:
				best = candidate
				best_distance = distance
		centers.append(best)
		biomes.append(_weighted(weights))
	var static_centers: Array[Vector2i] = []
	for i in _config.static_count:
		var best := _random_cell(2)
		var best_score := -INF
		for attempt in 48:
			var candidate := _random_cell(2)
			var score := Vector2(candidate).distance_to(_data.spawn_cell) - _config.spawn_radius
			for center in static_centers:
				score = minf(score, Vector2(candidate).distance_to(center))
			if score > best_score:
				best_score = score
				best = candidate
		static_centers.append(best)
	var noise := FastNoiseLite.new()
	noise.seed = int(_rng.randi())
	noise.frequency = 2.5 / minf(_config.width, _config.height)
	var amplitude := minf(_config.width, _config.height) * _config.boundary_noise * 0.35
	_zones.resize(_config.width * _config.height)
	for y in _config.height:
		if _stopped():
			return
		for x in _config.width:
			var cell := Vector2i(x, y)
			var warped := Vector2(cell) + Vector2(noise.get_noise_2d(x, y),
				noise.get_noise_2d(x + 901, y - 513)) * amplitude
			var distance := INF
			var selected := 0
			for i in centers.size():
				var d := warped.distance_squared_to(centers[i])
				if d < distance:
					distance = d
					selected = biomes[i]
			var from_spawn := Vector2(cell).distance_to(_data.spawn_cell)
			if from_spawn <= _config.spawn_radius:
				selected = 0
			_data.columns[_data.index(cell)] = _column(TILES[selected])
			var static_influence := 0.0
			for center in static_centers:
				var d := Vector2(cell).distance_to(center)
				static_influence = maxf(static_influence, 1.0 - smoothstep(
					_config.static_radius, _config.static_radius + maxf(0.01, _config.falloff), d))
			var exploration := 1.0 - smoothstep(_config.spawn_radius,
				_config.spawn_radius + maxf(0.01, _config.falloff), from_spawn)
			var is_static := static_influence * (1.0 - exploration) \
				> 0.5 + noise.get_noise_2d(x - 420, y + 601) * 0.15
			_zones[_data.index(cell)] = 1 if is_static else 0

func _column(tile: String) -> Dictionary:
	return {"layers": [{"tile_id": "rock" if tile == "water" else tile, "rotation": 0},
		{"tile_id": tile, "rotation": 0}]}

func _place_prefabs() -> String:
	var counts: Array[int] = []
	counts.resize(_sources.size())
	var total := 0
	for i in _sources.size():
		for repeat in int(_sources[i].rule.get("minimum", 1)):
			if not _try_place(i):
				return "必选地块「%s」第 %d 件无法投放。\n请增大地图/静止区，减小间距或调整区域约束。" % [
					_sources[i].name, repeat + 1]
			counts[i] += 1
			total += 1
	var exhausted := {}
	while total < _config.prefab_budget and not _stopped():
		var weights: Array[float] = []
		for i in _sources.size():
			var rule: Dictionary = _sources[i].rule
			weights.append(float(rule.get("weight", 1.0)) if not exhausted.has(i)
				and counts[i] < int(rule.get("maximum", 1)) else 0.0)
		var index := _weighted(weights)
		if index < 0:
			break
		if _try_place(index):
			counts[index] += 1
			total += 1
		else:
			exhausted[index] = true
			_warnings.append("可选地块「%s」无更多合法位置，已放置 %d 件" % [
				_sources[index].name, counts[index]])
	return ""

func _try_place(source_index: int) -> bool:
	var source: Dictionary = _sources[source_index]
	var prefab: LevelPrefab = source.prefab
	var rule: Dictionary = source.rule
	for attempt in 100:
		if _stopped():
			return false
		var turns := _rng.randi_range(0, 3) if bool(rule.get("rotate", true)) else 0
		var size := prefab.rotated_size(turns)
		if size.x + 4 > _config.width or size.y + 4 > _config.height:
			return false
		var anchor := Vector2i(_rng.randi_range(2, _config.width - size.x - 2),
			_rng.randi_range(2, _config.height - size.y - 2))
		var rect := Rect2i(anchor, size)
		if Rect2(rect).grow(_config.spawn_radius + 1).has_point(_data.spawn_cell):
			continue
		var valid := true
		for placement in _placements:
			if rect.grow(_config.prefab_gap).intersects(placement.rect):
				valid = false
				break
		if not valid:
			continue
		var zone := str(rule.get("zone", "any"))
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var value := _zones[_data.index(Vector2i(x, y))]
				if (zone == "static" and value != 1) or (zone == "explore" and value != 0):
					valid = false
		for cell: Vector2i in source.collectibles:
			if _zones[_data.index(anchor + prefab.rotate_cell(cell, turns))] != 1:
				valid = false
		if not valid:
			continue
		var entries: Array = source.entries
		var entry: Dictionary = entries[_rng.randi_range(0, entries.size() - 1)]
		var inside := anchor + prefab.rotate_cell(entry.cell, turns)
		var direction := posmod(int(entry.direction) + turns, 4)
		var outside: Vector2i = inside + LevelData.DIRS[direction]
		var padding: Dictionary = source.padding
		var height_offset := int(source.height_offset)
		var result := _stamp_prefab(prefab, anchor, turns, padding, height_offset)
		if not str(result.get("error", "")).is_empty():
			continue
		_data.restore_data(result.snapshot)
		for y in prefab.fragment.map_size.y:
			for x in prefab.fragment.map_size.x:
				var local := Vector2i(x, y)
				if not padding.has(local):
					_reserved[anchor + prefab.rotate_cell(local, turns)] = true
		_placements.append({"name": source.name, "source": rule.path,
			"rect": rect, "turns": turns, "entry": inside,
			"outside": outside, "layer": int(entry.layer) + height_offset,
			"source_layer": entry.layer, "height_offset": height_offset,
			"blended_cells": padding.size()})
		return true
	return false

func _connect() -> String:
	var grid := AStarGrid2D.new()
	grid.region = _data.map_bounds()
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for cell: Vector2i in _reserved:
		grid.set_point_solid(cell)
	var points: Array[Vector2i] = [_data.spawn_cell]
	for placement in _placements:
		points.append(placement.outside)
	var connected: Array[int] = [0]
	while connected.size() < points.size():
		if _stopped():
			return "已取消"
		var best_from := -1
		var best_to := -1
		var best := INF
		for from in connected:
			for to in points.size():
				if to in connected:
					continue
				var distance := Vector2(points[from]).distance_squared_to(points[to])
				if distance < best:
					best = distance
					best_from = from
					best_to = to
		var path := grid.get_id_path(points[best_from], points[best_to])
		if path.is_empty():
			return "特殊地块包围了通路，入口无法连接；请增大间距或更换种子"
		for cell in path:
			_roads[cell] = true
			var tile := _data.tile_id(cell)
			_data.columns[_data.index(cell)] = _column("rock" if tile == "water" else tile)
		connected.append(best_to)
	for placement in _placements:
		var inside: Vector2i = placement.entry
		var outside: Vector2i = placement.outside
		# Keep both sides clear, including the approach to a one-layer stair.
		_roads[inside] = true
		_roads[outside] = true
		_data.columns[_data.index(outside)] = _column("rock")
		var layer := int(placement.layer)
		if layer != 1:
			var low := inside if layer == 0 else outside
			var high := outside if layer == 0 else inside
			var direction := LevelData.DIRS.find(high - low)
			var error := _data.can_place_stair(low, direction, mini(1, layer))
			if not error.is_empty():
				return "无法接入「%s」：%s" % [placement.name, error]
			_data.stairs.append({"cell": low, "direction": direction, "layer": mini(1, layer)})
	return ""

func _scatter(collectible: bool, density: float) -> void:
	var pool: Array[PlaceableDefinition] = []
	var seen := {}
	for definition in _definitions:
		if definition.mechanism.is_empty() or seen.has(definition.resource_path):
			continue
		if (definition.mechanism in COLLECTIBLES) == collectible:
			pool.append(definition)
			seen[definition.resource_path] = true
	var wanted := roundi(_config.width * _config.height * density / 1000.0)
	if wanted == 0:
		return
	if pool.is_empty():
		_warnings.append("未找到可散布的%s资源" % ("采集物" if collectible else "环境物件"))
		return
	var target := mini(wanted, 160)
	if target < wanted:
		_warnings.append("本轮%s目标 %d 件已限制为 160 件，以控制编辑器物件校验开销" % [
			"采集物" if collectible else "环境物件", wanted])
	var clusters: Array[Vector2i] = []
	var positions: Array[Vector2i] = []
	var placed := 0
	for attempt in target * 60:
		if placed >= target or _stopped():
			break
		var center := _random_cell(2)
		if attempt % 4 != 0 and not clusters.is_empty():
			center = clusters[_rng.randi_range(0, clusters.size() - 1)]
		else:
			var separated := true
			for previous in clusters:
				if Vector2(center).distance_to(previous) < _config.cluster_gap:
					separated = false
					break
			if not separated:
				continue
			clusters.append(center)
		var cell := center + Vector2i(_rng.randi_range(-3, 3), _rng.randi_range(-3, 3))
		if not _data.in_bounds(cell) or _reserved.has(cell) or _roads.has(cell):
			continue
		if Vector2(cell).distance_to(_data.spawn_cell) < _config.spawn_radius + 1:
			continue
		var definition := pool[_rng.randi_range(0, pool.size() - 1)]
		var layer := 0 if _data.is_water_layer(cell, 1) else 1
		var record := {"id": "scatter_%d" % _data.objects.size(),
			"definition": definition.resource_path, "anchor_kind": "top",
			"anchor_cell": cell, "anchor_layer": layer,
			"position": _data.world_center(cell, layer),
			"yaw": -_rng.randi_range(0, 3) * PI * 0.5, "scale": 1.0}
		var valid := true
		for previous in positions:
			if Vector2(cell).distance_to(previous) < _config.item_gap:
				valid = false
				break
		for covered in ObjectRules.covered_cells(_data, record):
			if not _data.in_bounds(covered) or _reserved.has(covered) or _roads.has(covered):
				valid = false
				break
			if collectible and _zones[_data.index(covered)] != 1:
				valid = false
				break
			if Vector2(covered).distance_to(_data.spawn_cell) < _config.spawn_radius + 1:
				valid = false
				break
			if not definition.ecosystems.is_empty() and ObjectRules.ecosystem_at(
					_data, covered, layer) not in definition.ecosystems:
				valid = false
				break
		if not valid or not ObjectRules.validate_record(_data, record, "", {}, false).is_empty():
			continue
		_data.objects.append(record)
		positions.append(cell)
		placed += 1
	if placed < target:
		_warnings.append("%s实际 %d / 目标 %d 件：生态、功能区或间距限制" % [
			"采集物" if collectible else "环境物件", placed, target])

func _stable_ids() -> void:
	var ids := {}
	for i in _data.objects.size():
		ids[str(_data.objects[i].id)] = "wg_%d_o_%d" % [_config.seed_value, i]
	for record in _data.objects:
		record.id = ids[str(record.id)]
		if record.has("support_id"):
			record.support_id = ids.get(str(record.support_id), "")
	for i in _data.details.size():
		_data.details[i].id = "wg_%d_d_%d" % [_config.seed_value, i]

## Independent flood over real surface heights, stairs and object footprints.
func _check_reachability() -> String:
	var blocked := {}
	for record in _data.objects:
		for cell in ObjectRules.covered_cells(_data, record):
			blocked[cell] = true
	var edges := {}
	for stair in _data.stairs:
		var a: Vector2i = stair.cell
		var b: Vector2i = a + LevelData.DIRS[int(stair.direction)]
		edges[Vector4i(a.x, a.y, b.x, b.y)] = true
		edges[Vector4i(b.x, b.y, a.x, a.y)] = true
	var visited := {_data.spawn_cell: true}
	var queue: Array[Vector2i] = [_data.spawn_cell]
	var cursor := 0
	while cursor < queue.size():
		if cursor % 1024 == 0 and _stopped():
			return "已取消"
		var cell := queue[cursor]
		cursor += 1
		var height := _data.top_layer(cell)
		for direction: Vector2i in LevelData.DIRS:
			var next := cell + direction
			if not _data.in_bounds(next) or visited.has(next) or blocked.has(next):
				continue
			var next_height := _data.top_layer(next)
			if not _data.is_solid_layer(next, next_height):
				continue
			if next_height != height and not edges.has(Vector4i(cell.x, cell.y, next.x, next.y)):
				continue
			visited[next] = true
			queue.append(next)
	for placement in _placements:
		if not visited.has(placement.entry):
			return "入口可达性验证失败：" + str(placement.name)
	return ""
