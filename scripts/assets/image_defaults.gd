@tool
class_name ImageDefaults
extends RefCounted

## Measures pixels only. Never infers semantic type, real height or depth.
static func analyze(image: Image, pixels_per_meter := 256.0) -> Dictionary:
	if image == null or image.is_empty() or pixels_per_meter <= 0:
		return {"error": "图片为空或像素密度无效"}
	if image.is_compressed():
		image = image.duplicate()
		var error := image.decompress()
		if error != OK:
			return {"error": "无法解压图片像素，不能分析透明范围"}
	var width := image.get_width()
	var height := image.get_height()
	var minimum := Vector2i(width, height)
	var maximum := Vector2i(-1, -1)
	for y in height:
		for x in width:
			if image.get_pixel(x, y).a >= 0.15:
				minimum = minimum.min(Vector2i(x, y))
				maximum = maximum.max(Vector2i(x, y))
	if maximum.x < 0:
		return {"error": "图片完全透明，无法生成物件"}
	var rect := Rect2i(minimum, maximum - minimum + Vector2i.ONE)
	var sum_x := 0.0
	var count := 0
	var band := maxi(1, ceili(rect.size.y * 0.05))
	for y in range(maximum.y - band + 1, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			if image.get_pixel(x, y).a >= 0.15:
				sum_x += x + 0.5
				count += 1
	var pivot := Vector2(sum_x / maxf(count, 1) / width, float(maximum.y + 1) / height)
	var visible := Vector2(rect.size) / pixels_per_meter
	return {"error": "", "bounds": rect, "pixels": Vector2i(width, height),
		"image_size": Vector2(width, height) / pixels_per_meter, "pivot": pivot,
		# Generic adjustable proxy, explicitly not a measured 3D volume.
		"proxy": Vector3(maxf(visible.x * 0.5, 0.1), maxf(visible.y * 0.5, 0.1),
			maxf(visible.x * 0.25, 0.1))}

static func available_id(filename: String, directory := "res://assets/generated") -> String:
	var base := ""
	for character in filename.get_file().get_basename().to_lower():
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_":
			base += character
		else:
			base += "_"
	base = base.strip_edges().trim_prefix("_")
	if base.is_empty() or base.replace("_", "").is_empty():
		base = "art"
	if base[0] in "0123456789":
		base = "art_" + base
	var result := base
	var number := 2
	while DirAccess.dir_exists_absolute(directory.path_join(result)):
		result = base + "_%02d" % number
		number += 1
	return result
