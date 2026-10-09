@tool
class_name AssetFactory
extends RefCounted

static func make_asset(definition: PlaceableDefinition) -> Node3D:
	var root := Node3D.new()
	root.name = definition.asset_id
	var visual := _visual(definition, definition.source_image)
	visual.name = "Art"
	root.add_child(visual)
	if not definition.foreground_image.is_empty():
		var front := _visual(definition, definition.foreground_image)
		front.name = "Foreground"
		front.position += definition.profile.camera_basis().z * 0.015
		root.add_child(front)
		if definition.fade_foreground:
			front.set_script(load("res://scripts/assets/foreground_fade.gd"))
	if definition.collision != PlaceableDefinition.Collision.NONE:
		var body := StaticBody3D.new()
		body.name = "ProxyCollision"
		var shape_node := CollisionShape3D.new()
		if definition.collision == PlaceableDefinition.Collision.BOX:
			var shape := BoxShape3D.new()
			shape.size = definition.collision_size
			shape_node.shape = shape
		else:
			var shape := CylinderShape3D.new()
			shape.radius = maxf(definition.collision_size.x, definition.collision_size.z) * 0.5
			shape.height = definition.collision_size.y
			shape_node.shape = shape
		shape_node.position = definition.collision_offset + Vector3(0, definition.collision_size.y * 0.5, 0)
		body.add_child(shape_node)
		root.add_child(body)
	_set_owners(root, root)
	return root

static func _set_owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_set_owners(child, root)

static func _visual(d: PlaceableDefinition, image_path: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(image_path) as Texture2D
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.15
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var basis := d.profile.camera_basis()
	if d.carrier <= PlaceableDefinition.Carrier.GROUND:
		var points := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
		for uv: Vector2 in points:
			var p := Vector2((uv.x - d.pivot.x) * d.image_size.x, (d.pivot.y - uv.y) * d.image_size.y)
			vertices.append(Vector3(p.x, 0.035, -p.y) if d.carrier == PlaceableDefinition.Carrier.GROUND else basis * Vector3(p.x, p.y, 0))
			uvs.append(uv)
		indices = PackedInt32Array([0, 1, 2, 0, 2, 3])
	else:
		# User-supplied proxy dimensions, not depth inferred from a single image.
		var box := BoxMesh.new()
		box.size = d.volume_size
		var arrays := box.get_mesh_arrays()
		vertices = arrays[Mesh.ARRAY_VERTEX]
		indices = arrays[Mesh.ARRAY_INDEX]
		for i in vertices.size():
			var p := vertices[i] + Vector3(0, d.volume_size.y * 0.5, 0)
			if d.carrier == PlaceableDefinition.Carrier.PROJECTED_WEDGE and p.y > d.volume_size.y * 0.5:
				p.x *= 0.05
			vertices[i] = p
			# Orthographic projection into the source image; anchor stays at ground.
			var screen := basis.inverse() * p
			uvs.append(Vector2(screen.x / d.image_size.x + d.pivot.x, d.pivot.y - screen.y / d.image_size.y))
		mat.texture_repeat = false
	var output := []
	output.resize(Mesh.ARRAY_MAX)
	output[Mesh.ARRAY_VERTEX] = vertices
	output[Mesh.ARRAY_TEX_UV] = uvs
	output[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output)
	node.mesh = mesh
	return node

## Generation never overwrites source art or an existing asset directory.
static func generate(d: PlaceableDefinition, directory: String) -> String:
	var errors := d.validate_asset()
	if not errors.is_empty():
		return "\n".join(errors)
	if DirAccess.dir_exists_absolute(directory):
		return "目标目录已存在，请更换资源 ID（不会覆盖现有资产）"
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK:
		return "无法创建输出目录：%s" % err
	d.scene_path = directory.path_join("asset.tscn")
	d.thumbnail_path = directory.path_join("thumbnail.png")
	var root := make_asset(d)
	var packed := PackedScene.new()
	err = packed.pack(root)
	root.free()
	if err == OK:
		err = ResourceSaver.save(packed, d.scene_path)
	if err == OK:
		var image := (load(d.source_image) as Texture2D).get_image()
		image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		err = image.save_png(d.thumbnail_path)
	if err == OK:
		err = ResourceSaver.save(d, directory.path_join("definition.tres"))
	if err != OK:
		for file in ["asset.tscn", "thumbnail.png", "definition.tres"]:
			DirAccess.remove_absolute(directory.path_join(file))
		DirAccess.remove_absolute(directory)
		return "生成失败：%s，源图未修改" % err
	return ""
