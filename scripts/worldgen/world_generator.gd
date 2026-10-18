@tool
class_name WorldGenerator
extends RefCounted

const TILES := ["grass", "rock", "sand", "water"]
const COLLECTIBLES := ["resource", "fruit_tree", "remains"]
const MAX_STAMP_ATTEMPTS := 128
var _mutex := Mutex.new()
var _cancelled := false
var _stage := "准备"
var _rng := RandomNumberGenerator.new()
var _config: WorldGenConfig
var _data: LevelData
var _zones := PackedByteArray()
var _biomes := PackedByteArray()
var _reserved := {}
var _roads := {}
var _placements: Array[Dictionary] = []
var _warnings := PackedStringArray()
var _sources: Array[Dictionary] = []
var _definitions: Array[PlaceableDefinition] = []
var _placement_prefixes := {}
var _last_placement_report := {}
var _point_base: Array[Dictionary] = []

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
		var rotation_blocker := LevelPrefab.fixed_view_rotation_blocker(prefab.fragment)
		_sources.append({"prefab": prefab, "rule": rule, "entries": entries,
			"padding": padding, "height_offset": height_offset,
			"collectibles": resource_cells, "name": title,
			"rotation_blocker": rotation_blocker,
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
	var shifted_regions := {}
	for index: Vector3i in snapshot.get("encounter_regions", {}):
		var layer := index.y + height_offset
		if layer >= 0 and layer < LevelData.MAX_LAYERS:
			shifted_regions[Vector3i(index.x, layer, index.z)] = snapshot.encounter_regions[index]
	snapshot.encounter_regions = shifted_regions
	for point: Dictionary in snapshot.monster_spawn_points:
		point.cells = point.cells.map(func(cell: Vector3i):
			return Vector3i(cell.x, cell.y + height_offset, cell.z))
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
	_placement_prefixes.clear()
	_last_placement_report.clear()
	for source in _sources:
		if bool(source.rule.get("rotate", true)) and not str(source.rotation_blocker).is_empty():
			_warnings.append("特殊地块「%s」包含固定视角物件「%s」，已保持原方向" % [
				source.name, source.rotation_blocker])
	_data = LevelData.new()
	_data.setup_blank(Vector2i(_config.width, _config.height))
	_data.encounter = EncounterConfig.from_snapshot(_config.encounter_settings) \
		if not _config.encounter_settings.is_empty() else EncounterConfig.default_config()
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
	for i in _data.monster_spawn_points.size():
		_data.monster_spawn_points[i].id = "wg_%d_p_%d" % [_config.seed_value, i]
	_point_base = _data.monster_spawn_points.duplicate(true)
	for edit in _config.spawn_point_edits:
		for i in range(_data.monster_spawn_points.size() - 1, -1, -1):
			if str(_data.monster_spawn_points[i].id) == str(edit.id):
				_data.monster_spawn_points.remove_at(i)
		if not bool(edit.get("deleted", false)):
			_data.monster_spawn_points.append(edit.duplicate(true))
	if not _data.monster_spawn_points.is_empty() and _config.encounter_settings.is_empty():
		_data.encounter.enabled = true
	var point_errors := MonsterSpawnPoints.errors(_data)
	if not point_errors.is_empty():
		return {"error": "配方中的刷新点与当前地形不符，请恢复原参数或清除刷新点修改：\n" + "\n".join(point_errors)}
	for point in _data.monster_spawn_points:
		for cell: Vector3i in point.cells:
			_reserved[Vector2i(cell.x, cell.z)] = true
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
	for point in _data.monster_spawn_points:
		var names := MonsterSpawnPoints.species(_data, point, _data.encounter)
		if names.is_empty():
			_warnings.append("刷新点「%s」当前无可用物种，请检查设计表地形、怪池或禁刷。" % point.get("name", "刷新点"))
	var road_cells: Array[Vector2i] = []
	road_cells.assign(_roads.keys())
	_data.generation = {"algorithm_version": WorldGenConfig.ALGORITHM_VERSION,
		"recipe": _config.snapshot(), "zone_origin": _data.map_origin,
		"zone_size": _data.map_size, "zones": _zones,
		"placements": _placements.duplicate(true), "roads": road_cells,
		"sources": provenance, "warnings": _warnings, "biome_counts": counts}
	_data.generation.spawn_point_base = _point_base.duplicate(true)
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
	_biomes.resize(_config.width * _config.height)
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
			_biomes[_data.index(cell)] = selected
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
				if _stopped():
					return "已取消"
				return "必选地块「%s」第 %d 件无法投放（放置地形：%s）。\n%s" % [
					_sources[i].name, repeat + 1, _terrain_label(_sources[i].rule),
					_placement_failure_description(_sources[i])]
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
			_warnings.append("可选地块「%s」未找到更多合法位置（放置地形：%s），已放置 %d 件。\n%s" % [
				_sources[index].name, _terrain_label(_sources[index].rule), counts[index],
				_placement_failure_description(_sources[index])])
	return ""

func _terrain_label(rule: Dictionary) -> String:
	return WorldGenConfig.TERRAIN_LABELS[WorldGenConfig.TERRAIN_IDS.find(str(rule.get("terrain", "any")))]

## Match the generated world before stamping, never infer from the source map.
## Include padding and a one-cell border, so the footprint cannot straddle biomes.
func _terrain_matches(rect: Rect2i, terrain: String) -> bool:
	if terrain == "any":
		return true
	var selected := TILES.find(terrain)
	var area := rect.grow(1)
	if selected < 0 or not _data.map_bounds().encloses(area):
		return false
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if _biomes[_data.index(Vector2i(x, y))] != selected:
				return false
	return true

func _try_place(source_index: int) -> bool:
	var source: Dictionary = _sources[source_index]
	var prefab: LevelPrefab = source.prefab
	var rule: Dictionary = source.rule
	_last_placement_report = {"checked": 0, "rejected": {}, "stamp_errors": [],
		"stamp_attempts": 0, "limited": false, "seen": {}}
	var rotations: Array[int] = []
	var can_rotate := bool(rule.get("rotate", true)) and str(source.rotation_blocker).is_empty()
	for turns in (4 if can_rotate else 1):
		var size := prefab.rotated_size(turns)
		if size.x + 4 <= _config.width and size.y + 4 <= _config.height:
			rotations.append(turns)
	if rotations.is_empty():
		_reject_placement("size")
		return false
	# Preserve the fast seeded sampler, but only sample orientations that fit.
	for attempt in 100:
		if _stopped():
			return false
		var turns := rotations[_rng.randi_range(0, rotations.size() - 1)] if can_rotate else 0
		var size := prefab.rotated_size(turns)
		var anchor := Vector2i(_rng.randi_range(2, _config.width - size.x - 2),
			_rng.randi_range(2, _config.height - size.y - 2))
		if _try_prefab_candidate(source, anchor, turns):
			return true
		if bool(_last_placement_report.limited):
			return false
	# Rare legal footprints must not depend on luck. Prefix sums make each full
	# rectangle/biome/zone check O(1), even when inspecting a 600x600 world.
	for turns in rotations:
		var size := prefab.rotated_size(turns)
		var width := _config.width - size.x - 3
		var height := _config.height - size.y - 3
		var total := width * height
		var start := _rng.randi_range(0, total - 1)
		for step in total:
			if step % 256 == 0 and _stopped():
				return false
			var index := (start + step) % total
			var anchor := Vector2i(2 + index % width, 2 + index / width)
			if _try_prefab_candidate(source, anchor, turns):
				return true
			if bool(_last_placement_report.limited):
				return false
	return false

func _try_prefab_candidate(source: Dictionary, anchor: Vector2i, turns: int) -> bool:
	var key := Vector3i(anchor.x, turns, anchor.y)
	if _last_placement_report.seen.has(key):
		return false
	_last_placement_report.seen[key] = true
	_last_placement_report.checked += 1
	var prefab: LevelPrefab = source.prefab
	var rect := Rect2i(anchor, prefab.rotated_size(turns))
	var rule: Dictionary = source.rule
	var terrain := str(rule.get("terrain", "any"))
	if terrain != "any" and _placement_sum("terrain:" + terrain, rect.grow(1)) > 0:
		return _reject_placement("terrain")
	if Rect2(rect).grow(_config.spawn_radius + 1).has_point(_data.spawn_cell):
		return _reject_placement("spawn")
	for placement in _placements:
		if rect.grow(_config.prefab_gap).intersects(placement.rect):
			return _reject_placement("spacing")
	var zone := str(rule.get("zone", "any"))
	if zone != "any" and _placement_sum("zone:" + zone, rect) > 0:
		return _reject_placement("zone")
	for cell: Vector2i in source.collectibles:
		if _zones[_data.index(anchor + prefab.rotate_cell(cell, turns))] != 1:
			return _reject_placement("collectibles")
	if _stopped():
		return false
	# Full LevelData copies and validation are costly. Bound this work separately
	# from cheap footprint search, and state that limit if all candidates fail it.
	if int(_last_placement_report.stamp_attempts) >= MAX_STAMP_ATTEMPTS:
		_last_placement_report.limited = true
		return false
	_last_placement_report.stamp_attempts += 1
	var height_offset := int(source.height_offset)
	var result := _stamp_prefab(prefab, anchor, turns, source.padding, height_offset)
	var error := str(result.get("error", ""))
	if not error.is_empty():
		if not _last_placement_report.stamp_errors.has(error):
			_last_placement_report.stamp_errors.append(error)
		return _reject_placement("content")
	var candidate := LevelData.new()
	candidate.restore_data(result.snapshot)
	var blocked := {}
	for record in candidate.objects:
		for cell in ObjectRules.covered_cells(candidate, record):
			blocked[cell] = true
	var entries: Array = source.entries
	var entry: Dictionary = {}
	var inside := Vector2i.ZERO
	var outside := Vector2i.ZERO
	if not entries.is_empty():
		var start := _rng.randi_range(0, entries.size() - 1)
		for step in entries.size():
			var possible: Dictionary = entries[(start + step) % entries.size()]
			var point := anchor + prefab.rotate_cell(possible.cell, turns)
			var direction := posmod(int(possible.direction) + turns, 4)
			var approach: Vector2i = point + LevelData.DIRS[direction]
			if not candidate.in_bounds(approach) or _reserved.has(approach) \
					or blocked.has(point) or blocked.has(approach):
				continue
			entry = possible
			inside = point
			outside = approach
			break
	if entry.is_empty():
		return _reject_placement("entry")
	_data.restore_data(result.snapshot)
	for y in prefab.fragment.map_size.y:
		for x in prefab.fragment.map_size.x:
			var local := Vector2i(x, y)
			if not source.padding.has(local):
				_reserved[anchor + prefab.rotate_cell(local, turns)] = true
	_placements.append({"name": source.name, "source": rule.path,
		"terrain": rule.get("terrain", "any"),
		"rect": rect, "turns": turns, "entry": inside,
		"outside": outside, "layer": int(entry.layer) + height_offset,
		"source_layer": entry.layer, "height_offset": height_offset,
		"blended_cells": source.padding.size()})
	return true

func _reject_placement(reason: String) -> bool:
	var counts: Dictionary = _last_placement_report.rejected
	counts[reason] = int(counts.get(reason, 0)) + 1
	return false

## Cached counts of cells violating the immutable generated biome/zone rule.
func _placement_sum(key: String, rect: Rect2i) -> int:
	if not _data.map_bounds().encloses(rect):
		return 1
	var stride := _config.width + 1
	if not _placement_prefixes.has(key):
		var prefix := PackedInt32Array()
		prefix.resize(stride * (_config.height + 1))
		var terrain := key.begins_with("terrain:")
		var expected := TILES.find(key.trim_prefix("terrain:")) if terrain \
			else (1 if key == "zone:static" else 0)
		for y in _config.height:
			if y % 64 == 0 and _stopped():
				return 1
			var row := 0
			for x in _config.width:
				var value := _biomes[y * _config.width + x] if terrain else _zones[y * _config.width + x]
				row += 1 if value != expected else 0
				prefix[(y + 1) * stride + x + 1] = prefix[y * stride + x + 1] + row
		_placement_prefixes[key] = prefix
	var prefix: PackedInt32Array = _placement_prefixes[key]
	return prefix[rect.end.y * stride + rect.end.x] - prefix[rect.position.y * stride + rect.end.x] \
		- prefix[rect.end.y * stride + rect.position.x] + prefix[rect.position.y * stride + rect.position.x]

func _placement_failure_description(source: Dictionary) -> String:
	var prefab: LevelPrefab = source.prefab
	var size := prefab.fragment.map_size
	var summary := "源地图 %d×%d 格，生成地图 %d×%d 格；出生净空 %.1f 格，地块间距 %d 格。" % [
		size.x, size.y, _config.width, _config.height, _config.spawn_radius, _config.prefab_gap]
	var counts: Dictionary = _last_placement_report.rejected
	if counts.has("size"):
		return summary + "\n所有允许的朝向都放不下源地图及两格边缘留白，请增大生成地图。"
	var labels := {"terrain": "指定地形或外侧一格不连续", "spawn": "侵入出生净空",
		"spacing": "与已放地块间距不足", "zone": "整张地图不符合所选功能区域",
		"collectibles": "食物/材料/遗骸占地未全部落在静止区",
		"content": "投放后的地形/物件校验失败", "entry": "入口或接近入口被占用"}
	var reasons := PackedStringArray()
	for key: String in labels:
		if counts.has(key):
			reasons.append("%s：%d 个候选" % [labels[key], counts[key]])
	summary += "\n筛选结果：" + "；".join(reasons) + "。"
	if not _last_placement_report.stamp_errors.is_empty():
		summary += "\n地图校验原因：" + str(_last_placement_report.stamp_errors[0]).left(400)
	if bool(_last_placement_report.limited):
		summary += "\n投放校验达到上限（%d 个通过区域筛选的位置），仍未找到合法内容和入口；为控制开销停止继续尝试。" % MAX_STAMP_ATTEMPTS
	else:
		summary += "\n已检查所有允许的朝向和位置；请按上述具体限制调整地形、静止区、尺寸或间距。"
	return summary

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
		var tile := _data.tile_id(outside)
		_data.columns[_data.index(outside)] = _column("rock" if tile == "water" else tile)
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
		var yaw := -_rng.randi_range(0, 3) * PI * 0.5 \
			if definition.supports_quarter_turns() else 0.0
		var record := {"id": "scatter_%d" % _data.objects.size(),
			"definition": definition.resource_path, "anchor_kind": "top",
			"anchor_cell": cell, "anchor_layer": layer,
			"position": _data.world_center(cell, layer),
			"yaw": yaw, "scale": 1.0}
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
