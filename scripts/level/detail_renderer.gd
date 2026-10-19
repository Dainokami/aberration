@tool
class_name DetailRenderer
extends Node3D

const CHUNK_SIZE := 8
var groups := {}
var signatures := {}
var slice_layer := -1

static func instance_transform(set: DetailSet, record: Dictionary, profile: ArtProfile) -> Transform3D:
	var variant: Dictionary = set.variants[set.variant_index(str(record["variant"]))]
	var size: Vector2 = variant["size"] * float(record.get("scale", 1.0))
	var pivot: Vector2 = variant.get("pivot", Vector2(0.5, 1.0))
	var orientation := Basis(Vector3.UP, float(record.get("yaw", 0.0)))
	var offset := Vector3(-pivot.x * size.x, 0, -pivot.y * size.y)
	var scale_vector := Vector3(size.x, 1, size.y)
	if set.orientation == DetailSet.DetailOrientation.CARD:
		orientation = profile.camera_basis()
		scale_vector = Vector3(size.x, size.y, 1)
		offset = Vector3(-pivot.x * size.x, pivot.y * size.y, 0)
	if bool(record.get("flip", false)):
		scale_vector.x *= -1
		offset.x *= -1
	return Transform3D(orientation * Basis.from_scale(scale_vector),
		record["position"] + Vector3.UP * 0.045 + orientation * offset)

static func unit_mesh(orientation: DetailSet.DetailOrientation) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)])
	for uv in uvs:
		vertices.append(Vector3(uv.x, 0, uv.y) if orientation == DetailSet.DetailOrientation.GROUND
			else Vector3(uv.x, -uv.y, 0))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func atlas_material(set: DetailSet) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
varying vec4 atlas_region;
void vertex() { atlas_region = INSTANCE_CUSTOM; }
void fragment() {
	vec4 color = texture(atlas, atlas_region.xy + UV * atlas_region.zw);
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.15;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("atlas", load(set.atlas_path))
	return material

## Only changed (chunk, set, layer) batches are replaced, even during a long brush stroke.
func refresh(data: LevelData, selected_records: Variant = null) -> void:
	var batches := {}
	var sets := {}
	if selected_records == null:
		selected_records = data.details
	for record in selected_records:
		var path := str(record["set"])
		if not sets.has(path):
			sets[path] = DetailRules.definition(record)
		if DetailRules.is_hidden(data, record, sets[path]):
			continue
		var cell: Vector2i = record["anchor_cell"]
		var chunk := Vector2i(floori(float(cell.x) / CHUNK_SIZE), floori(float(cell.y) / CHUNK_SIZE))
		var key := "%d,%d|%s|%d" % [chunk.x, chunk.y, record["set"], record["anchor_layer"]]
		if not batches.has(key):
			batches[key] = []
		batches[key].append(record)
	for key in groups.keys():
		if not batches.has(key):
			groups[key].free()
			groups.erase(key)
			signatures.erase(key)
	var profile := load("res://data/art_profile.tres") as ArtProfile
	for key: String in batches:
		var records: Array = batches[key]
		var signature := hash(records)
		if signatures.get(key) == signature:
			continue
		if groups.has(key):
			groups[key].free()
			groups.erase(key)
		var set := DetailRules.definition(records[0])
		if set == null or not set.validate_asset().is_empty():
			continue
		var valid: Array[Dictionary] = []
		for record: Dictionary in records:
			if set.variant_index(str(record.get("variant", ""))) >= 0:
				valid.append(record)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = unit_mesh(set.orientation)
		multimesh.instance_count = valid.size()
		var atlas := load(set.atlas_path) as Texture2D
		var atlas_size := atlas.get_size()
		for i in valid.size():
			var record := valid[i]
			var rect := Rect2(set.variants[set.variant_index(str(record["variant"]))]["rect"])
			multimesh.set_instance_transform(i, instance_transform(set, record, profile))
			# Half-pixel inset protects each Atlas island under minification.
			var uv := (rect.position + Vector2.ONE * 0.5) / atlas_size
			var span := (rect.size - Vector2.ONE) / atlas_size
			multimesh.set_instance_custom_data(i, Color(uv.x, uv.y, span.x, span.y))
		var instance := MultiMeshInstance3D.new()
		instance.name = "Details_" + str(groups.size())
		instance.multimesh = multimesh
		instance.material_override = atlas_material(set)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.set_meta("terrain_layer", int(records[0]["anchor_layer"]))
		add_child(instance)
		groups[key] = instance
		signatures[key] = signature
	set_slice_layer(slice_layer)

func set_slice_layer(layer: int) -> void:
	slice_layer = layer
	for child in get_children():
		child.visible = layer < 0 or int(child.get_meta("terrain_layer", -1)) <= layer
