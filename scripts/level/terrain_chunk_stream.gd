@tool
class_name TerrainChunkStream
extends RefCounted

## LevelData remains complete. Only the scene representation has a working set.
const CHUNK_SIZE := 8
const CELL_MARGIN := 4
const PLAYER_RADIUS := 20.0
const FRAME_BUDGET_USEC := 4000
const MAX_BUILDS_PER_FRAME := 2

var view_margin_cells := CELL_MARGIN
var wanted: Dictionary = {}
var retained: Dictionary = {}
var pending: Array[Vector2i] = []
var camera: Camera3D
var actor: Node3D
var focus := Vector3.ZERO
var max_height := 2.0
var chunk_heights := {}
var last_transform := Transform3D()
var last_projection := ""
var update_left := 0.0
var revision := 0
var last_build_usec := 0
var peak_build_usec := 0
var peak_total_usec := 0
var loaded_total := 0
var unloaded_total := 0
var anchors: Array[Vector3] = []
var _last_anchors: Array[Vector3] = []
var job_root: Node3D
var job_chunk := Vector2i.ZERO
var job_row := 0
var job_stage := 0

func cancel_job(builder: TerrainBuilder) -> void:
	if not is_instance_valid(job_root):
		return
	job_root.free()
	job_root = null
	builder._chunk_nodes.erase(job_chunk)
	for key: Vector3i in builder._blend_resources.keys():
		if key.x == job_chunk.x and key.z == job_chunk.y:
			builder._blend_resources.erase(key)
	if wanted.has(job_chunk) and job_chunk not in pending:
		pending.push_front(job_chunk)
	builder._collision_batch = null
	builder._bottom_meshes.clear()
	builder._bottom_groups.clear()
	builder._zone_groups.clear()

static func chunk_for(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK_SIZE), floori(float(cell.y) / CHUNK_SIZE))

static func chunk_region(data: LevelData, chunk: Vector2i) -> Rect2i:
	return Rect2i(chunk * CHUNK_SIZE, Vector2i.ONE * CHUNK_SIZE).intersection(data.map_bounds())

func reset(data: LevelData) -> void:
	wanted.clear()
	retained.clear()
	pending.clear()
	anchors.clear()
	max_height = 2.0
	chunk_heights.clear()
	for i in data.columns.size():
		var height := (data.columns[i].get("layers", []) as Array).size() * LevelData.ELEVATION_STEP
		if height <= 0:
			continue
		var cell := data.map_origin + Vector2i(i % data.map_size.x, i / data.map_size.x)
		var chunk := chunk_for(cell)
		chunk_heights[chunk] = maxf(chunk_heights.get(chunk, 0.0), height)
		max_height = maxf(max_height, height)
	focus = data.world_center(data.spawn_cell if data.in_bounds(data.spawn_cell)
		else data.map_origin + data.map_size / 2, maxi(0, data.spawn_layer))
	update_left = 0.0
	revision += 1
	last_projection = ""

func select(builder: TerrainBuilder, force := false) -> bool:
	var data := builder.level_data
	var actor_valid := is_instance_valid(actor) and actor.is_inside_tree()
	var camera_valid := is_instance_valid(camera) and camera.is_inside_tree()
	if actor_valid:
		focus = builder.to_local(actor.global_position)
	elif camera_valid:
		var ray := camera.project_ray_normal(camera.get_viewport().get_visible_rect().size * 0.5)
		var start := camera.project_ray_origin(camera.get_viewport().get_visible_rect().size * 0.5)
		var ground: Variant = Plane(Vector3.UP, builder.global_position.y + focus.y).intersects_ray(start, ray)
		if ground != null:
			focus = builder.to_local(ground)
	var projection := str([camera.projection, camera.fov, camera.size,
		camera.get_viewport().get_visible_rect().size]) if camera_valid else ""
	if not force and camera_valid and last_projection == projection \
			and last_transform == camera.global_transform and not actor_valid and anchors == _last_anchors:
		return false
	_last_anchors = anchors.duplicate()
	last_projection = projection
	if camera_valid:
		last_transform = camera.global_transform
	var desired := {}
	# Test real frustum planes against each chunk, with a prefetch border.
	# Cheap boxes only: this does not instantiate or read individual cells.
	if camera_valid:
		var planes := camera.get_frustum()
		for chunk: Vector2i in chunk_heights:
			var region := chunk_region(data, chunk)
			if not region.has_area():
				continue
			var corner := data.world_layer_center(region.position, 0) \
				- Vector3(LevelData.CELL_SIZE * 0.5, LevelData.ELEVATION_STEP * 0.5,
					LevelData.CELL_SIZE * 0.5)
			var box := AABB(corner, Vector3(region.size.x * LevelData.CELL_SIZE,
				chunk_heights[chunk], region.size.y * LevelData.CELL_SIZE)).grow(
					view_margin_cells * LevelData.CELL_SIZE)
			box = builder.global_transform * box
			var inside := true
			for plane: Plane in planes:
				var extent := box.size * 0.5
				if plane.distance_to(box.get_center()) > absf(plane.normal.x) * extent.x \
						+ absf(plane.normal.y) * extent.y + absf(plane.normal.z) * extent.z:
					inside = false
					break
			if inside:
				desired[chunk] = true
	add_radius(data, desired, focus, PLAYER_RADIUS)
	for anchor in anchors:
		add_radius(data, desired, anchor, 4.0)
	if desired == wanted and not force:
		return false
	wanted = desired
	retained = wanted.duplicate()
	for chunk: Vector2i in wanted:
		for y in range(-1, 2):
			for x in range(-1, 2):
				var neighbor := chunk + Vector2i(x, y)
				if chunk_region(data, neighbor).has_area():
					retained[neighbor] = true
	pending.clear()
	for chunk: Vector2i in wanted:
		if not builder._chunk_nodes.has(chunk):
			pending.append(chunk)
	pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var cell := data.world_to_cell(focus)
		return (a * CHUNK_SIZE + Vector2i(4, 4)).distance_squared_to(cell) \
			< (b * CHUNK_SIZE + Vector2i(4, 4)).distance_squared_to(cell))
	revision += 1
	return true

static func add_radius(data: LevelData, target: Dictionary, center: Vector3, radius: float) -> void:
	var cell := data.world_to_cell(center)
	var reach := ceili(radius / LevelData.CELL_SIZE)
	var first := chunk_for(cell - Vector2i.ONE * reach)
	var last := chunk_for(cell + Vector2i.ONE * reach)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var chunk := Vector2i(x, y)
			if chunk_region(data, chunk).has_area():
				target[chunk] = true

func step(builder: TerrainBuilder, delta: float) -> void:
	update_left -= delta
	var changed := false
	if update_left <= 0:
		changed = select(builder)
		update_left = 0.15
	var start := Time.get_ticks_usec()
	if is_instance_valid(job_root) and not wanted.has(job_chunk):
		cancel_job(builder)
	var count := 0
	while (is_instance_valid(job_root) or not pending.is_empty()) and count < MAX_BUILDS_PER_FRAME:
		var real_generated := builder.generated
		if not is_instance_valid(job_root):
			job_chunk = pending.pop_front()
			if not wanted.has(job_chunk) or builder._chunk_nodes.has(job_chunk):
				continue
			job_root = Node3D.new()
			builder.generated = job_root
			builder._begin_chunk(job_chunk)
			job_row = builder._build_region.position.y
			job_stage = 0
		else:
			builder.generated = job_root
		if job_stage == 0:
			builder._build_chunk_row(job_row)
			job_row += 1
			if job_row >= builder._build_region.end.y:
				job_stage = 1
		elif job_stage == 1:
			builder._finish_chunk_geometry()
			job_stage = 2
		elif job_stage == 2:
			builder._finish_chunk_edges()
			job_stage = 3
		else:
			builder._publish_chunk_metadata()
			for node in job_root.get_children():
				job_root.remove_child(node)
				real_generated.add_child(node)
			job_root.free()
			job_root = null
			loaded_total += 1
			count += 1
			changed = true
		builder.generated = real_generated
		if Time.get_ticks_usec() - start >= FRAME_BUDGET_USEC:
			break
	last_build_usec = Time.get_ticks_usec() - start
	peak_build_usec = maxi(peak_build_usec, last_build_usec)
	# Limit disposal too; releasing a whole scene on one frame can also stutter.
	var disposed := 0
	for chunk: Vector2i in builder._chunk_nodes.keys():
		if retained.has(chunk):
			continue
		builder._unload_chunk(chunk)
		unloaded_total += 1
		changed = true
		disposed += 1
		if disposed >= 2:
			break
	if changed:
		builder._stream_content_changed()
	peak_total_usec = maxi(peak_total_usec, Time.get_ticks_usec() - start)

func ensure_position(builder: TerrainBuilder, position: Vector3, radius := 4.0) -> void:
	var needed := {}
	var changed := false
	add_radius(builder.level_data, needed, position, radius)
	for chunk: Vector2i in needed:
		wanted[chunk] = true
		retained[chunk] = true
		if not builder._chunk_nodes.has(chunk):
			cancel_job(builder)
			builder._build_chunk(chunk)
			loaded_total += 1
			changed = true
		pending.erase(chunk)
	if changed:
		builder._stream_content_changed()

func ensure_wanted(builder: TerrainBuilder) -> int:
	cancel_job(builder)
	var chunks: Array[Vector2i] = []
	for chunk: Vector2i in pending:
		if wanted.has(chunk) and not builder._chunk_nodes.has(chunk):
			chunks.append(chunk)
	for chunk: Vector2i in wanted:
		if not builder._chunk_nodes.has(chunk) and chunk not in chunks:
			chunks.append(chunk)
	var loaded := 0
	for chunk in chunks:
		builder._build_chunk(chunk)
		loaded_total += 1
		loaded += 1
	pending.clear()
	if loaded > 0:
		builder._stream_content_changed()
	return loaded
