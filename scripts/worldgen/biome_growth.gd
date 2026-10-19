@tool
class_name BiomeGrowth
extends RefCounted

## Multi-source, eight-neighbour geodesic growth. The sources are authored
## footprints and free-world seed points, not a previously generated biome map.
## A footprint starts with radial arrival times, so its growth front is curved
## rather than a simultaneous rectangular front. Positive, smooth travel costs
## bend the front further before neighbouring regions meet.
const DIRECTIONS := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
const UNREACHED := 2147483647
var owners := PackedInt32Array()
var _distance := PackedInt32Array()
var _cost := PackedInt32Array()
var _locked := PackedInt32Array()
var _heap: Array[int] = []
var _count := 0

## Sites contain rect and optional lead, radius and locked. Required rectangles
## are interior constraints only; every cell outside them is assigned by growth.
func build(size: Vector2i, sites: Array[Dictionary], seed_value: int,
		boundary_noise: float, stopped: Callable) -> PackedInt32Array:
	_count = size.x * size.y
	owners.resize(_count)
	owners.fill(-1)
	_distance.resize(_count)
	_distance.fill(UNREACHED)
	_locked.resize(_count)
	_locked.fill(-1)
	_cost.resize(_count)
	_heap.clear()
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	for y in size.y:
		if stopped.call():
			return PackedInt32Array()
		for x in size.x:
			_cost[y * size.x + x] = 16 + roundi(noise.get_noise_2d(x, y) * boundary_noise * 12)
	for i in sites.size():
		if not bool(sites[i].get("locked", true)):
			continue
		var rect: Rect2i = sites[i].rect
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if _inside_seed(sites[i], Vector2i(x, y)):
					_locked[y * size.x + x] = i
	for i in sites.size():
		var rect: Rect2i = sites[i].rect
		var center := Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) * 0.5
		# Normalize the radial field for long, narrow maps. An unscaled circular
		# field would let their long axis push neighbouring cores against a wall.
		var half_extent := Vector2(rect.size - Vector2i.ONE) * 0.5
		var axes := half_extent.max(Vector2.ONE * 0.5)
		var short_axis := minf(axes.x, axes.y)
		var radial_scale := Vector2(short_axis / axes.x, short_axis / axes.y)
		if sites[i].has("radius"):
			radial_scale = Vector2.ONE
		var radius := float(sites[i].get("radius", (half_extent * radial_scale).length()))
		var lead := radius * 16.0 + float(sites[i].get("lead", 0))
		for y in range(rect.position.y, rect.end.y):
			if stopped.call():
				return PackedInt32Array()
			for x in range(rect.position.x, rect.end.x):
				if not _inside_seed(sites[i], Vector2i(x, y)):
					continue
				var index := y * size.x + x
				var arrival := roundi(((Vector2(x, y) - center) * radial_scale).length() * 16.0 - lead)
				_distance[index] = arrival
				owners[index] = i
				_push(arrival * _count + index)
	var steps := 0
	while not _heap.is_empty():
		if steps % 1024 == 0 and stopped.call():
			return PackedInt32Array()
		steps += 1
		var key := _pop()
		var index := posmod(key, _count)
		var arrival: int = (key - index) / _count
		if arrival != _distance[index]:
			continue
		var cell := Vector2i(index % size.x, index / size.x)
		var owner := owners[index]
		for direction: Vector2i in DIRECTIONS:
			var next := cell + direction
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
				continue
			var target := next.y * size.x + next.x
			if _locked[target] >= 0 and _locked[target] != owner:
				continue
			var diagonal := direction.x != 0 and direction.y != 0
			var travel: int = (_cost[index] + _cost[target]) * (14 if diagonal else 10) / 20
			var candidate := arrival + travel
			if candidate >= _distance[target]:
				continue
			_distance[target] = candidate
			owners[target] = owner
			_push(candidate * _count + target)
	return owners

func _inside_seed(site: Dictionary, cell: Vector2i) -> bool:
	if not site.has("radius"):
		return true
	var rect: Rect2i = site.rect
	var center := Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) * 0.5
	return Vector2(cell).distance_to(center) <= float(site.radius)

func _push(key: int) -> void:
	var index := _heap.size()
	_heap.append(key)
	while index > 0:
		var parent: int = (index - 1) / 2
		if _heap[parent] <= key:
			break
		_heap[index] = _heap[parent]
		index = parent
	_heap[index] = key

func _pop() -> int:
	var first := _heap[0]
	var last: int = _heap.pop_back()
	if _heap.is_empty():
		return first
	var index := 0
	while index * 2 + 1 < _heap.size():
		var child := index * 2 + 1
		if child + 1 < _heap.size() and _heap[child + 1] < _heap[child]:
			child += 1
		if _heap[child] >= last:
			break
		_heap[index] = _heap[child]
		index = child
	_heap[index] = last
	return first
