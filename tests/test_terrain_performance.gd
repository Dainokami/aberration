extends SceneTree

## CPU timings for the actual edit pipeline; no synthetic delays or mocked nodes.
class MeasuredBuilder extends TerrainBuilder:
	var stages := {}

	func elapsed(key: String, start: int) -> void:
		stages[key] = float(stages.get(key, 0.0)) + (Time.get_ticks_usec() - start) / 1000.0

	func _build_chunk(chunk: Vector2i) -> void:
		var start := Time.get_ticks_usec()
		super._build_chunk(chunk)
		elapsed("chunks_ms", start)

	func _build_objects() -> void:
		var start := Time.get_ticks_usec()
		super._build_objects()
		elapsed("objects_ms", start)

	func rebuild_details() -> void:
		var start := Time.get_ticks_usec()
		super.rebuild_details()
		elapsed("details_ms", start)

	func _apply_slice_visibility() -> void:
		var start := Time.get_ticks_usec()
		super._apply_slice_visibility()
		elapsed("slice_ms", start)

var failures: Array[String] = []
var reports: Array[Dictionary] = []

func _init() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	print("PERFORMANCE CHECK ", message, " ", condition)
	if not condition:
		failures.append(message)

func run() -> void:
	var sample := ResourceLoader.load("res://data/levels/objects_acceptance.tres", "",
		ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	sample.ensure_layout()
	await measure("current_map", sample)
	for size in [128, 600]:
		var data := LevelData.new()
		data.setup_blank(Vector2i(size, size))
		for y in 64:
			for x in 64:
				data.set_layer(Vector2i(x, y), 0, {"tile_id": "painted_grass"})
		for i in 32:
			var cell := Vector2i(4 + (i % 8) * 3, 4 + (i / 8) * 3)
			data.objects.append(ObjectRules.anchor_record(data, {"id": "bench_%d" % i,
				"definition": "res://assets/generated/demo_rock/definition.tres",
				"position": data.world_center(cell), "scale": 1.0, "yaw": 0.0}))
		await measure(str(size) + "_bounds_64_filled", data)
	var output := FileAccess.open("/tmp/aberration-performance-current.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(reports, "\t"))
	print("PERFORMANCE RESULTS ", JSON.stringify(reports))
	print("PERFORMANCE FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func measure(label: String, data: LevelData) -> void:
	var builder := MeasuredBuilder.new()
	builder.level_data = data
	builder.show_grid = true
	var start := Time.get_ticks_usec()
	root.add_child(builder)
	reports.append({"scenario": label, "operation": "initial",
		"total_ms": (Time.get_ticks_usec() - start) / 1000.0,
		"stages": builder.stages.duplicate(), "chunks": builder._chunk_nodes.size()})
	await process_frame
	var cell := Vector2i(12, 12)
	var layer := data.top_layer(cell) + 1
	for operation in ["place", "erase"]:
		var timings := {}
		var unchanged: Dictionary = builder._object_nodes.duplicate()
		start = Time.get_ticks_usec()
		var candidate := data.fork_for_edit()
		timings["fork_ms"] = (Time.get_ticks_usec() - start) / 1000.0
		start = Time.get_ticks_usec()
		if operation == "place":
			candidate.set_layer(cell, layer, {"tile_id": "painted_grass"})
			DetailRules.prune_invalid(candidate)
			candidate.validate_content(false)
		else:
			ObjectRules.remove_terrain_support(candidate, cell, layer)
			candidate.remove_layer(cell, layer)
			DetailRules.prune_invalid(candidate)
		timings["change_validate_ms"] = (Time.get_ticks_usec() - start) / 1000.0
		start = Time.get_ticks_usec()
		data.set_columns({cell: candidate.column_snapshot(cell)})
		data.objects = candidate.objects
		data.details = candidate.details
		timings["apply_ms"] = (Time.get_ticks_usec() - start) / 1000.0
		start = Time.get_ticks_usec()
		builder.stages.clear()
		var changed: Array[Vector2i] = [cell]
		builder.rebuild_cells(changed)
		timings["rebuild_ms"] = (Time.get_ticks_usec() - start) / 1000.0
		timings.merge(builder.stages)
		reports.append({"scenario": label, "operation": operation, "stages": timings})
		var retained := true
		for id: String in unchanged:
			if builder._object_nodes.has(id):
				retained = retained and is_instance_valid(unchanged[id]) \
					and builder._object_nodes[id] == unchanged[id]
		check(retained, label + " " + operation + " preserves unaffected objects")
		check(float(timings["rebuild_ms"]) < 150.0,
			label + " " + operation + " local rebuild under 150ms")
		await process_frame
	var terrain := builder.generated
	var chunks := builder._chunk_nodes.duplicate()
	start = Time.get_ticks_usec()
	var before := data.objects.duplicate(true)
	ObjectRules.remove_with_dependents(data, [str(data.objects.back()["id"])])
	var after := data.objects.duplicate(true)
	builder.refresh_objects()
	var delete_ms := (Time.get_ticks_usec() - start) / 1000.0
	reports.append({"scenario": label, "operation": "object_delete", "total_ms": delete_ms})
	check(delete_ms < 50.0 and builder.generated == terrain and chunks == builder._chunk_nodes,
		label + " object deletion retains terrain and completes under 50ms")
	data.objects = before
	builder.refresh_objects()
	check(data.objects.size() == after.size() + 1, label + " object restore keeps all records")
	builder.free()
	await process_frame
