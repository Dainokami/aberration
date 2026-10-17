@tool
class_name AssetFactory
extends RefCounted

static func make_asset(definition: PlaceableDefinition) -> Node3D:
	var root := Node3D.new()
	if not definition.mechanism.is_empty():
		root.set_script(load("res://scripts/runtime/scene_mechanism.gd"))
		root.set("definition", definition)
	elif definition.behaviour != PlaceableDefinition.Behaviour.DECORATION:
		root.set_script(load("res://scripts/runtime/gameplay_prop.gd"))
		root.set("definition", definition)
	root.name = definition.asset_id
	if definition.mechanism == "chest":
		root.add_child(_chest_slice(definition, 0.0, 0.52, true))
		root.add_child(_chest_slice(definition, 0.52, 1.0, false))
	elif definition.carrier == PlaceableDefinition.Carrier.MULTI_FACE:
		var visual := _multi_face(definition)
		visual.name = "Art"
		root.add_child(visual)
	elif not definition.state_images.is_empty():
		for state: String in definition.state_images:
			var visual := _visual(definition, definition.state_images[state],
				definition.state_pivots.get(state, definition.pivot))
			visual.name = "State_" + state
			visual.visible = state == "closed"
			root.add_child(visual)
	else:
		var visual := _visual(definition, definition.source_image)
		visual.name = "Art"
		if not definition.spatial_cells.is_empty() and definition.mechanism != "fruit_tree" \
				and definition.carrier != PlaceableDefinition.Carrier.WALL:
			visual.position += Vector3(definition.collision_offset.x, 0, definition.collision_offset.z)
		root.add_child(visual)
	if not definition.foreground_image.is_empty():
		var front := _visual(definition, definition.foreground_image)
		front.name = "Foreground"
		front.position += definition.profile.camera_basis().z * 0.015
		root.add_child(front)
		if definition.fade_foreground:
			front.set_script(load("res://scripts/assets/foreground_fade.gd"))
	if definition.collision != PlaceableDefinition.Collision.NONE and definition.spatial_cells.is_empty():
		var body := StaticBody3D.new()
		body.name = "ProxyCollision"
		var shape_node := CollisionShape3D.new()
		# Saved scenes keep explicit names; auto names like @CollisionShape3D@9 are unstable.
		shape_node.name = "Shape"
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
	if not definition.spatial_cells.is_empty():
		for index in definition.spatial_cells.size():
			var body: CollisionObject3D = StaticBody3D.new() \
				if definition.collision != PlaceableDefinition.Collision.NONE else Area3D.new()
			body.name = "SpatialCell_%d" % index
			body.collision_layer = 1 if body is StaticBody3D else 4
			body.collision_mask = 0
			var shape_node := CollisionShape3D.new()
			shape_node.name = "Shape"
			var shape := BoxShape3D.new()
			shape.size = definition.cell_size
			shape_node.shape = shape
			shape_node.position = definition.spatial_cells[index] + Vector3.UP * shape.size.y * 0.5
			body.add_child(shape_node)
			root.add_child(body)
	if definition.behaviour in [PlaceableDefinition.Behaviour.CHEST,
			PlaceableDefinition.Behaviour.BREAKABLE, PlaceableDefinition.Behaviour.CLIMBABLE] \
			or not definition.mechanism.is_empty():
		var area := Area3D.new()
		area.name = "InteractionArea"
		area.collision_layer = 4
		area.collision_mask = 0
		var shape_node := CollisionShape3D.new()
		shape_node.name = "Shape"
		var shape := BoxShape3D.new()
		shape.size = definition.collision_size
		if definition.carrier == PlaceableDefinition.Carrier.WALL:
			shape.size = Vector3(definition.image_size.x, definition.image_size.y, 0.16)
		shape_node.shape = shape
		shape_node.position = definition.collision_offset + Vector3(0, shape.size.y * 0.5, 0)
		area.add_child(shape_node)
		root.add_child(area)
	_set_owners(root, root)
	return root

## Preserve scripts, child components and state nodes from generated/custom scenes.
## Creation uses make_asset; normal map loading uses the saved scene.
static func instantiate_asset(definition: PlaceableDefinition) -> Node3D:
	if not definition.scene_path.is_empty() and ResourceLoader.exists(definition.scene_path):
		var packed := load(definition.scene_path) as PackedScene
		if packed != null:
			var root := packed.instantiate() as Node3D
			if root != null:
				return root
	return make_asset(definition)

static func _chest_slice(d: PlaceableDefinition, first: float, last: float, lid: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "ChestLid" if lid else "Art"
	var cut := 0.52
	var origin_y := (d.pivot.y - cut) * d.image_size.y
	node.basis = d.profile.camera_basis()
	node.position = node.basis * Vector3(0, origin_y, 0)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for uv in [Vector2(0,first),Vector2(0,last),Vector2(1,last),Vector2(1,first)]:
		vertices.append(Vector3((uv.x - d.pivot.x) * d.image_size.x,
			(cut - uv.y) * d.image_size.y, 0))
		uvs.append(uv)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(d.source_image)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.15
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func _multi_face(d: PlaceableDefinition) -> Node3D:
	var root := Node3D.new()
	var x := d.volume_size.x * 0.5
	var y := d.volume_size.y
	var z := d.volume_size.z * 0.5
	# UV order: top-left, bottom-left, bottom-right, top-right.
	var faces := {
		"front": [Vector3(-x,y,z),Vector3(-x,0,z),Vector3(x,0,z),Vector3(x,y,z)],
		"back": [Vector3(x,y,-z),Vector3(x,0,-z),Vector3(-x,0,-z),Vector3(-x,y,-z)],
		"left": [Vector3(-x,y,-z),Vector3(-x,0,-z),Vector3(-x,0,z),Vector3(-x,y,z)],
		"right": [Vector3(x,y,z),Vector3(x,0,z),Vector3(x,0,-z),Vector3(x,y,-z)],
		"top": [Vector3(-x,y,-z),Vector3(-x,y,z),Vector3(x,y,z),Vector3(x,y,-z)],
		"bottom": [Vector3(-x,0,z),Vector3(-x,0,-z),Vector3(x,0,-z),Vector3(x,0,z)],
	}
	for face: String in faces:
		var path := str(d.face_images.get(face, d.face_images.get("front", "")))
		var mesh := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(faces[face])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(1,0)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var instance := MeshInstance3D.new()
		instance.name = face.capitalize()
		instance.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_texture = load(path) as Texture2D
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		material.texture_repeat = false
		instance.material_override = material
		root.add_child(instance)
	return root

static func _set_owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_set_owners(child, root)

static func _visual(d: PlaceableDefinition, image_path: String, pivot_override := Vector2(-1, -1)) -> MeshInstance3D:
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
	var pivot := d.pivot if pivot_override.x < 0 else pivot_override
	if d.carrier <= PlaceableDefinition.Carrier.GROUND or d.carrier == PlaceableDefinition.Carrier.WALL:
		var points := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
		for uv: Vector2 in points:
			var p := Vector2((uv.x - pivot.x) * d.image_size.x, (pivot.y - uv.y) * d.image_size.y)
			if d.carrier == PlaceableDefinition.Carrier.GROUND:
				vertices.append(Vector3(p.x, 0.035, -p.y))
			elif d.carrier == PlaceableDefinition.Carrier.WALL:
				vertices.append(Vector3(p.x, p.y, 0.025))
			else:
				vertices.append(basis * Vector3(p.x, p.y, 0))
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
			uvs.append(d.profile.project_art(p, d.image_size, pivot))
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
		var image := (load(d.source_image) as Texture2D).get_image().duplicate() as Image
		if image.is_compressed():
			image.decompress()
		var ratio := minf(128.0 / image.get_width(), 128.0 / image.get_height())
		image.resize(maxi(1, roundi(image.get_width() * ratio)),
			maxi(1, roundi(image.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
		var thumbnail := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		thumbnail.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()),
			(Vector2i(128, 128) - image.get_size()) / 2)
		err = thumbnail.save_png(d.thumbnail_path)
	if err == OK:
		err = ResourceSaver.save(d, directory.path_join("definition.tres"))
	if err != OK:
		for file in ["asset.tscn", "thumbnail.png", "definition.tres"]:
			DirAccess.remove_absolute(directory.path_join(file))
		DirAccess.remove_absolute(directory)
		return "生成失败：%s，源图未修改" % err
	return ""
