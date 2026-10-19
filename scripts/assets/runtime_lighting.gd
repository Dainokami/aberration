class_name RuntimeLighting
extends RefCounted

## Only shader programs are cached. Materials, textures and meshes live with their
## streamed nodes, so visiting more chunks cannot retain the entire map here.
var _shaders := {}

func apply(node: Node, cast_shadows := true) -> void:
	if node.has_meta("water_volume") or node.has_meta("terrain_grid"):
		return
	if node is GeometryInstance3D and not node.has_meta("runtime_lighting"):
		if node is Sprite3D:
			# Alpha discard participates in the depth/shadow passes. The original
			# billboard, pivot, texture and animation remain the visual source.
			# Painted characters have baked facial shading; keep them readable
			# under the back/side key light while casting a real silhouette.
			node.shaded = false
			node.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			node.alpha_scissor_threshold = 0.15
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED \
				if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif node is MeshInstance3D or node is MultiMeshInstance3D:
			var mesh: Mesh = node.mesh if node is MeshInstance3D else node.multimesh.mesh
			if mesh != null:
				var corrected := _with_normals(mesh)
				if corrected != mesh:
					if node is MeshInstance3D:
						node.mesh = corrected
					else:
						node.multimesh.mesh = corrected
				if node.material_override != null:
					node.material_override = _material(node.material_override)
				elif node is MeshInstance3D:
					for i in mesh.get_surface_count():
						var material: Material = node.get_active_material(i)
						if material != null:
							node.set_surface_override_material(i, _material(material))
				var transparent_effect := node.name == "ShoreFoam" or node.has_meta("terrain_overlay")
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED \
					if cast_shadows and not transparent_effect else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.set_meta("lighting_cast_shadow", cast_shadows and not transparent_effect)
		node.set_meta("runtime_lighting", true)
	for child in node.get_children():
		apply(child, cast_shadows)

func _material(source: Material) -> Material:
	var material := source.duplicate() as Material
	if material is StandardMaterial3D:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		material.roughness = 1.0
	elif material is ShaderMaterial and material.shader != null:
		var code: String = material.shader.code
		if "unshaded" in code:
			if not _shaders.has(code):
				var shader := Shader.new()
				shader.code = code.replace("unshaded", "diffuse_lambert, specular_disabled")
				_shaders[code] = shader
			material.shader = _shaders[code]
	return material

static func add_fade_shadow(visual: MeshInstance3D) -> void:
	if visual.get_node_or_null("LightingShadow") != null \
			or not visual.material_override is StandardMaterial3D \
			or not bool(visual.get_meta("lighting_cast_shadow", true)):
		return
	var material := visual.material_override.duplicate() as StandardMaterial3D
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.15
	material.albedo_color.a = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var caster := MeshInstance3D.new()
	caster.name = "LightingShadow"
	caster.mesh = visual.mesh
	caster.material_override = material
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	caster.set_meta("runtime_lighting", true)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Parent visibility/transform and streamed lifetime apply to the caster too.
	visual.add_child(caster)

static func _with_normals(source: Mesh) -> Mesh:
	if not source is ArrayMesh:
		return source
	var missing := false
	for i in source.get_surface_count():
		if source.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			return source
		missing = missing or not bool(source.surface_get_format(i) & Mesh.ARRAY_FORMAT_NORMAL)
	if not missing:
		return source
	var result := ArrayMesh.new()
	for i in source.get_surface_count():
		var tool := SurfaceTool.new()
		tool.create_from(source, i)
		if not bool(source.surface_get_format(i) & Mesh.ARRAY_FORMAT_NORMAL):
			tool.generate_normals()
		tool.commit(result)
	return result
