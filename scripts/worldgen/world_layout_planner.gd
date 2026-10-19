@tool
class_name WorldLayoutPlanner
extends RefCounted

## Pack mandatory footprints before generating ecology. The input recipe and
## source resources stay unchanged; only the resulting world's bounds may grow.
const MAX_SIZE := 600

func plan(config: WorldGenConfig, sources: Array[Dictionary], stopped: Callable) -> Dictionary:
	var items: Array[Dictionary] = []
	var margin := maxi(2, ceili(config.prefab_gap / 2.0))
	for i in sources.size():
		var source := sources[i]
		if int(source.rule.get("minimum", 1)) > 0 \
				and source.rule.get("zone", "any") == "explore" and not source.collectibles.is_empty():
			return {"error": "必选地块「%s」的规则冲突：采集物必须在静止区，不能整图指定为探索战斗区。" % source.name}
		for copy in int(source.rule.get("minimum", 1)):
			var prefab: LevelPrefab = source.prefab
			var size := prefab.fragment.map_size
			# Leave room for biome fronts to meet outside the authored rectangle.
			var growth_margin := maxi(margin, clampi(ceili(mini(size.x, size.y) * 0.25), 6, 24))
			items.append({"source_index": i, "copy": copy, "size": prefab.fragment.map_size,
				"margin": growth_margin,
				"rotate": bool(source.rule.get("rotate", true)) and str(source.rotation_blocker).is_empty()})
	items.sort_custom(func(a: Dictionary, b: Dictionary):
		var area_a: int = a.size.x * a.size.y
		var area_b: int = b.size.x * b.size.y
		if area_a != area_b:
			return area_a > area_b
		if a.source_index != b.source_index:
			return a.source_index < b.source_index
		return a.copy < b.copy)
	var size := Vector2i(config.width, config.height)
	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed_value
	while true:
		if stopped.call():
			return {"error": "已取消"}
		var clearance := ceili(config.spawn_radius + 1)
		var spawns: Array[Vector2i] = [size / 2, Vector2i(clearance, clearance),
			Vector2i(size.x - clearance - 1, clearance),
			Vector2i(clearance, size.y - clearance - 1),
			size - Vector2i.ONE * (clearance + 1)]
		for spawn in spawns:
			var free: Array[Rect2i] = [Rect2i(Vector2i.ZERO, size)]
			free = _subtract(free, Rect2i(spawn - Vector2i.ONE * clearance,
				Vector2i.ONE * (clearance * 2 + 1)))
			var placements: Array[Dictionary] = []
			for item in items:
				if stopped.call():
					return {"error": "已取消"}
				var best := {}
				var best_short := MAX_SIZE + 1
				var best_long := MAX_SIZE + 1
				var ties := 0
				for space in free:
					for turns in (4 if item.rotate else 1):
						var footprint: Vector2i = item.size if turns % 2 == 0 \
							else Vector2i(item.size.y, item.size.x)
						var buffer: int = item.margin
						var padded := footprint + Vector2i.ONE * buffer * 2
						var left := space.size - padded
						if left.x < 0 or left.y < 0:
							continue
						var short_side := mini(left.x, left.y)
						var long_side := maxi(left.x, left.y)
						if short_side > best_short or (short_side == best_short and long_side > best_long):
							continue
						if short_side < best_short or long_side < best_long:
							ties = 0
						best_short = short_side
						best_long = long_side
						for corner in [Vector2i.ZERO, Vector2i(left.x, 0), Vector2i(0, left.y), left]:
							ties += 1
							if rng.randi_range(1, ties) == 1:
								best = {"source_index": item.source_index, "turns": turns,
									"growth_margin": buffer,
									"rect": Rect2i(space.position + corner + Vector2i.ONE * buffer, footprint)}
				if best.is_empty():
					break
				placements.append(best)
				free = _subtract(free, (best.rect as Rect2i).grow(int(best.growth_margin)))
			if placements.size() == items.size():
				return {"error": "", "size": size, "spawn": spawn, "placements": placements}
		if size == Vector2i.ONE * MAX_SIZE:
			var descriptions := PackedStringArray()
			for source in sources:
				var count := int(source.rule.get("minimum", 1))
				if count > 0:
					var footprint: Vector2i = source.prefab.fragment.map_size
					descriptions.append("%s %d×%d 格 ×%d" % [source.name, footprint.x, footprint.y, count])
			return {"error": "已自动扩图至上限 600×600 格，仍无法安排必选地块、出生净空和通路。\n%s\n请减小源地图尺寸、必选数量、出生半径或间距。" % "；".join(descriptions)}
		size = Vector2i(mini(MAX_SIZE, maxi(size.x + 1, ceili(size.x * 1.25))),
			mini(MAX_SIZE, maxi(size.y + 1, ceili(size.y * 1.25))))
	return {"error": "无法规划特殊地块"}

## Maximal empty rectangles may overlap each other, but never occupied slots.
## Split every intersecting rectangle, then discard redundant contained pieces.
func _subtract(spaces: Array[Rect2i], used: Rect2i) -> Array[Rect2i]:
	var pieces: Array[Rect2i] = []
	for space in spaces:
		if not space.intersects(used):
			pieces.append(space)
			continue
		if used.position.x > space.position.x:
			pieces.append(Rect2i(space.position, Vector2i(used.position.x - space.position.x, space.size.y)))
		if used.end.x < space.end.x:
			pieces.append(Rect2i(Vector2i(used.end.x, space.position.y),
				Vector2i(space.end.x - used.end.x, space.size.y)))
		if used.position.y > space.position.y:
			pieces.append(Rect2i(space.position, Vector2i(space.size.x, used.position.y - space.position.y)))
		if used.end.y < space.end.y:
			pieces.append(Rect2i(Vector2i(space.position.x, used.end.y),
				Vector2i(space.size.x, space.end.y - used.end.y)))
	var result: Array[Rect2i] = []
	for i in pieces.size():
		var contained := false
		for j in pieces.size():
			if i != j and pieces[j].encloses(pieces[i]) and (pieces[j] != pieces[i] or j < i):
				contained = true
				break
		if not contained:
			result.append(pieces[i])
	return result
