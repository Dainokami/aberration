extends SceneTree

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("GROWTH CHECK ", value, " ", label)
	if not value:
		failures.append(label)

func sites_for_test() -> Array[Dictionary]:
	var sites: Array[Dictionary] = [{"rect": Rect2i(48, 42, 32, 22), "terrain": 2, "lead": 104}]
	for cell in [Vector2i(8, 8), Vector2i(64, 4), Vector2i(119, 8), Vector2i(123, 56),
			Vector2i(119, 103), Vector2i(64, 107), Vector2i(8, 103), Vector2i(4, 56)]:
		sites.append({"rect": Rect2i(cell, Vector2i.ONE), "terrain": 0, "locked": false})
	return sites

func measure(owners: PackedInt32Array, size: Vector2i, owner: int) -> Dictionary:
	var minimum := size
	var maximum := Vector2i.ZERO
	var area := 0
	var rows := {}
	var first := -1
	for y in size.y:
		for x in size.x:
			var index := y * size.x + x
			if owners[index] != owner:
				continue
			if first < 0:
				first = index
			area += 1
			minimum = minimum.min(Vector2i(x, y))
			maximum = maximum.max(Vector2i(x, y))
			rows[y] = int(rows.get(y, 0)) + 1
	var visited := PackedByteArray()
	visited.resize(owners.size())
	var queue: Array[int] = [first]
	visited[first] = 1
	var cursor := 0
	while cursor < queue.size():
		var index := queue[cursor]
		cursor += 1
		var cell := Vector2i(index % size.x, index / size.x)
		for delta: Vector2i in LevelData.DIRS:
			var next := cell + delta
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
				continue
			var next_index := next.y * size.x + next.x
			if owners[next_index] == owner and visited[next_index] == 0:
				visited[next_index] = 1
				queue.append(next_index)
	var widths := {}
	for width: int in rows.values():
		widths[width] = true
	var bounds := Rect2i(minimum, maximum - minimum + Vector2i.ONE)
	return {"area": area, "fill": float(area) / bounds.get_area(),
		"widths": widths.size(), "connected": cursor == area, "bounds": bounds}

func run() -> void:
	var size := Vector2i(128, 112)
	var sites := sites_for_test()
	var before := sites.duplicate(true)
	var stop := func(): return false
	var original := PackedInt32Array()
	for seed_value in [0, 1, 42, 4242, 2147483647]:
		var owners := BiomeGrowth.new().build(size, sites, seed_value, 0.8, stop)
		check(owners.size() == size.x * size.y and owners.count(-1) == 0,
			"whole map grows without gaps seed %d" % seed_value)
		var continuous := true
		var expanded: Rect2i = sites[0].rect.grow(3)
		for y in range(expanded.position.y, expanded.end.y):
			for x in range(expanded.position.x, expanded.end.x):
				continuous = continuous and owners[y * size.x + x] == 0
		check(continuous, "chosen biome continues beyond every source edge seed %d" % seed_value)
		var stats := measure(owners, size, 0)
		print("GROWTH SHAPE seed ", seed_value, " ", stats)
		check(stats.area > sites[0].rect.get_area() * 2 and stats.fill < 0.9 and stats.widths >= 8,
			"grown region has varying contours, not a rectangular patch seed %d" % seed_value)
		check(stats.connected, "grown source region remains connected seed %d" % seed_value)
		if seed_value == 42:
			original = owners
			check(BiomeGrowth.new().build(size, sites, seed_value, 0.8, stop) == owners,
				"same inputs reproduce every grown cell")
	check(sites == before, "growth leaves input footprints and settings unchanged")
	var smooth := BiomeGrowth.new().build(size, sites, 42, 0.0, stop)
	check(smooth != original and measure(smooth, size, 0).fill < 0.9,
		"noise controls contour variation; zero noise still does not draw a rectangular base")

	var tall: Array[Dictionary] = [{"rect": Rect2i(18, 18, 16, 48), "terrain": 1, "lead": 100},
		{"rect": Rect2i(60, 20, 44, 20), "terrain": 2, "lead": 100},
		{"rect": Rect2i(58, 73, 32, 24), "terrain": 3, "lead": 100}]
	var owners := BiomeGrowth.new().build(size, tall, 123, 1.0, stop)
	var intact := true
	for i in tall.size():
		var rect: Rect2i = tall[i].rect
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				intact = intact and owners[y * size.x + x] == i
	check(intact, "neighbouring different biomes never invade each other's required footprint")

	var polls := [0]
	owners = BiomeGrowth.new().build(size, sites, 42, 1.0, func():
		polls[0] += 1
		return polls[0] > 150)
	check(owners.is_empty(), "cancelling active growth returns no partially grown map")

	var large_sites: Array[Dictionary] = [{"rect": Rect2i(100, 100, 77, 77), "lead": 220},
		{"rect": Rect2i(400, 400, 44, 57), "lead": 160},
		{"rect": Rect2i(40, 500, 28, 28), "lead": 116},
		{"rect": Rect2i(550, 50, 1, 1), "locked": false}]
	var started := Time.get_ticks_msec()
	owners = BiomeGrowth.new().build(Vector2i(600, 600), large_sites, 42, 1.0, stop)
	var elapsed := Time.get_ticks_msec() - started
	print("GROWTH 600x600 ms ", elapsed)
	check(owners.size() == 360000 and owners.count(-1) == 0 and elapsed < 15000,
		"600x600 growth completes in bounded time")
	print("GROWTH CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures.is_empty() else 1)
