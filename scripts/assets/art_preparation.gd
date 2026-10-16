@tool
class_name ArtPreparation
extends RefCounted

## Image-only routines; safe to run in a worker thread. No scene/resource writes.
## Exact-black art touching exact-black background cannot be inferred losslessly.
## Optional artist masks override inferred background, retaining intended holes.
static func process(source: Image, options: Dictionary) -> Dictionary:
	if source == null or source.is_empty():
		return {"error": "图片为空"}
	var image := source.duplicate() as Image
	if image.is_compressed() and image.decompress() != OK:
		return {"error": "无法解压图片"}
	image.convert(Image.FORMAT_RGBA8)
	if options.get("black_background", false):
		image = remove_background(image, int(options.get("threshold", 8)))
	var mask: Image = options.get("mask")
	if mask != null:
		mask = mask.duplicate()
		mask.resize(image.get_width(), image.get_height(), Image.INTERPOLATE_BILINEAR)
		for y in image.get_height():
			for x in image.get_width():
				var color := image.get_pixel(x, y)
				color.a = mask.get_pixel(x, y).r
				image.set_pixel(x, y, color)
	var quad: PackedVector2Array = options.get("quad", PackedVector2Array())
	if not quad.is_empty():
		if quad.size() != 4:
			return {"error": "面片必须提供四个角点"}
		image = rectify(image, quad, int(options.get("max_size", 1024)))
	var crop := Rect2i(Vector2i.ZERO, image.get_size())
	if options.get("trim", true) and quad.is_empty():
		crop = image.get_used_rect()
		if crop.size == Vector2i.ZERO:
			return {"error": "处理后没有可见内容；请降低阈值或提供遮罩"}
		var trimmed := image.get_region(crop)
		image = Image.create(crop.size.x + 8, crop.size.y + 8, false, Image.FORMAT_RGBA8)
		image.blit_rect(trimmed, Rect2i(Vector2i.ZERO, crop.size), Vector2i(4, 4))
	var maximum := maxi(16, int(options.get("max_size", 1024)))
	if maxi(image.get_width(), image.get_height()) > maximum:
		var factor := float(maximum) / maxi(image.get_width(), image.get_height())
		image.resize(maxi(1, roundi(image.get_width() * factor)),
			maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	return {"error": "", "image": image, "crop": crop, "quad": quad}

static func remove_background(image: Image, threshold := 8) -> Image:
	var size := image.get_size()
	var bytes := image.get_data()
	var total := size.x * size.y
	var visited := PackedByteArray()
	visited.resize(total)
	var queue := PackedInt32Array()
	queue.resize(total)
	var tail := 0
	for y in size.y:
		for x in size.x:
			if x != 0 and y != 0 and x != size.x - 1 and y != size.y - 1:
				continue
			var i := y * size.x + x
			if visited[i] == 0 and _is_black(bytes, i, threshold):
				visited[i] = 1
				queue[tail] = i
				tail += 1
	var head := 0
	while head < tail:
		var i := queue[head]
		head += 1
		bytes[i * 4 + 3] = 0
		var x := i % size.x
		for n in [i - size.x, i + size.x, i - 1 if x > 0 else -1,
				i + 1 if x < size.x - 1 else -1]:
			if n < 0 or n >= total or visited[n] != 0 or not _is_black(bytes, n, threshold):
				continue
			visited[n] = 1
			queue[tail] = n
			tail += 1
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)

static func _is_black(bytes: PackedByteArray, i: int, threshold: int) -> bool:
	return maxi(bytes[i * 4], maxi(bytes[i * 4 + 1], bytes[i * 4 + 2])) <= threshold

static func estimate_quad(source: Image) -> PackedVector2Array:
	var image := source.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	var width := image.get_width()
	var height := image.get_height()
	var points := PackedVector2Array()
	var stride := maxi(1, maxi(width, height) / 512)
	for y in range(0, height, stride):
		var first := -1
		var last := -1
		for x in range(0, width, stride):
			if image.get_pixel(x, y).a > 0.6:
				if first < 0:
					first = x
				last = x
		if first >= 0:
			points.append(Vector2(first, y))
			points.append(Vector2(last, y))
	if points.size() < 4:
		return PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	var hull := Geometry2D.convex_hull(points)
	hull.remove_at(hull.size() - 1)
	while hull.size() > 4:
		var least := INF
		var remove := 0
		for i in hull.size():
			var a := hull[posmod(i - 1, hull.size())]
			var area := absf((hull[i] - a).cross(hull[(i + 1) % hull.size()] - a))
			if area < least:
				least = area
				remove = i
		hull.remove_at(remove)
	if hull.size() != 4:
		return PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	var start := 0
	for i in 4:
		hull[i] /= Vector2(width, height)
		if hull[i].x + hull[i].y < hull[start].x + hull[start].y:
			start = i
	var quad := PackedVector2Array()
	for i in 4:
		quad.append(hull[(start + i) % 4])
	if quad[1].x < quad[3].x:
		quad = PackedVector2Array([quad[0], quad[3], quad[2], quad[1]])
	return quad

static func rectify(source: Image, quad: PackedVector2Array, size := 1024) -> Image:
	var result := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var bounds := Vector2(source.get_size() - Vector2i.ONE)
	for y in size:
		var v := (float(y) + 0.5) / size
		var left := quad[0].lerp(quad[3], v) * bounds
		var right := quad[1].lerp(quad[2], v) * bounds
		for x in size:
			var p := left.lerp(right, (float(x) + 0.5) / size).clamp(Vector2.ZERO, bounds)
			var a := Vector2i(p.floor())
			var b := (a + Vector2i.ONE).min(source.get_size() - Vector2i.ONE)
			var c := source.get_pixel(a.x, a.y).lerp(source.get_pixel(b.x, a.y), p.x - a.x)
			var d := source.get_pixel(a.x, b.y).lerp(source.get_pixel(b.x, b.y), p.x - a.x)
			var color := c.lerp(d, p.y - a.y)
			# Face silhouettes define full solid geometry, not alpha holes.
			color.a = 1.0
			result.set_pixel(x, y, color)
	return result

static func build_atlas(images: Array[Image], maximum := 2048) -> Dictionary:
	var atlas := Image.create(maximum, maximum, false, Image.FORMAT_RGBA8)
	var rectangles: Array[Rect2i] = []
	var cursor := Vector2i.ZERO
	var row_height := 0
	for source in images:
		if source == null or source.is_empty():
			return {"error": "图集包含空图片"}
		var image := source.duplicate() as Image
		if image.is_compressed():
			image.decompress()
		if maxi(image.get_width(), image.get_height()) > 512:
			var factor := 512.0 / maxi(image.get_width(), image.get_height())
			image.resize(roundi(image.get_width() * factor), roundi(image.get_height() * factor))
		var padded := image.get_size() + Vector2i(16, 16)
		if cursor.x + padded.x > maximum:
			cursor = Vector2i(0, cursor.y + row_height)
			row_height = 0
		if cursor.y + padded.y > maximum:
			return {"error": "图集已满，请分成两个细节套件"}
		var rectangle := Rect2i(cursor + Vector2i(8, 8), image.get_size())
		atlas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), rectangle.position)
		rectangles.append(rectangle)
		cursor.x += padded.x
		row_height = maxi(row_height, padded.y)
	return {"error": "", "image": atlas, "rects": rectangles}
