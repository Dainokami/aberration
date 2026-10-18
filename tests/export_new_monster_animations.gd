extends SceneTree

# Rebuild with: godot --path PROJECT --script res://tests/export_new_monster_animations.gd
# Requires a renderer; do not use --headless.
const OUTPUT := "res://assets/animations/new_monsters/sprite_frames/"
const RIGS := "res://assets/animations/new_monsters/rigs/"
const FRAME_SIZE := 320
const VARIANTS := ["gerbil", "wolf", "gorilla_front", "gorilla_side", "gibbon", "ostrich"]
const CLIPS := {"walk": [10, 0.057, 10.0, true], "attack": [8, 0.05, 20.0, false], "death": [8, 0.075, 13.0, false]}


func _initialize() -> void:
	call_deferred("_export_all")


func _export_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var viewport := SubViewport.new()
	viewport.name = "AnimationExportViewport"
	viewport.size = Vector2i(FRAME_SIZE, FRAME_SIZE)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.world_3d = World3D.new()
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.7
	camera.position = Vector3(0, 3.2, 8.0)
	camera.current = true
	stage.add_child(camera)
	camera.look_at(Vector3(0, 1.15, 0), Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	stage.add_child(light)
	await process_frame
	for variant in VARIANTS:
		for clip in CLIPS:
			var setup: Array = CLIPS[clip]
			var sheet := Image.create(FRAME_SIZE * int(setup[0]), FRAME_SIZE, false, Image.FORMAT_RGBA8)
			sheet.fill(Color.TRANSPARENT)
			var kind: String = variant.trim_suffix("_front").trim_suffix("_side")
			var rig := (load(RIGS + kind + "_rig.tscn") as PackedScene).instantiate() as LayeredMonsterRig
			stage.add_child(rig)
			rig.set_process(false)
			if variant == "gorilla_side":
				rig.set_movement(Vector3(1, 0, 0))
			else:
				rig.set_movement(Vector3(0, 0, 1))
			if clip == "attack":
				rig.set_movement(Vector3.ZERO)
				rig.play_attack()
			elif clip == "death":
				rig.set_movement(Vector3.ZERO)
				rig.play_death()
			for index in int(setup[0]):
				rig._process(float(setup[1]))
				await RenderingServer.frame_post_draw
				var frame := viewport.get_texture().get_image()
				frame.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(frame, Rect2i(0, 0, FRAME_SIZE, FRAME_SIZE), Vector2i(index * FRAME_SIZE, 0))
			var png_path: String = OUTPUT + variant + "_" + clip + ".png"
			var error := sheet.save_png(ProjectSettings.globalize_path(png_path))
			if error != OK:
				push_error("Could not save " + png_path + ": " + str(error))
			stage.remove_child(rig)
			rig.free()
		_write_sprite_frames(variant)
		print("EXPORTED_MONSTER_ANIMATIONS " + variant)
	viewport.queue_free()
	quit()


func _write_sprite_frames(variant: String) -> void:
	var lines: PackedStringArray = ["[gd_resource type=\"SpriteFrames\" format=3]", ""]
	var clip_names := ["attack", "death", "walk"]
	for clip in clip_names:
		lines.append("[ext_resource type=\"Texture2D\" path=\"" + OUTPUT + variant + "_" + clip + ".png\" id=\"" + clip + "\"]")
	lines.append("")
	for clip in clip_names:
		for index in int(CLIPS[clip][0]):
			lines.append("[sub_resource type=\"AtlasTexture\" id=\"" + clip + "_" + str(index) + "\"]")
			lines.append("atlas = ExtResource(\"" + clip + "\")")
			lines.append("region = Rect2(" + str(index * FRAME_SIZE) + ", 0, " + str(FRAME_SIZE) + ", " + str(FRAME_SIZE) + ")")
			lines.append("")
	lines.append("[resource]")
	lines.append("animations = [")
	for clip_index in clip_names.size():
		var clip: String = clip_names[clip_index]
		lines.append("{")
		lines.append("\"frames\": [")
		for index in int(CLIPS[clip][0]):
			lines.append("{\"duration\": 1.0, \"texture\": SubResource(\"" + clip + "_" + str(index) + "\")}" + ("," if index < int(CLIPS[clip][0]) - 1 else ""))
		lines.append("],")
		lines.append("\"loop\": " + ("true" if bool(CLIPS[clip][3]) else "false") + ",")
		lines.append("\"name\": &\"" + clip + "\",")
		lines.append("\"speed\": " + str(CLIPS[clip][2]))
		lines.append("}" + ("," if clip_index < clip_names.size() - 1 else ""))
	lines.append("]")
	var file := FileAccess.open(ProjectSettings.globalize_path(OUTPUT + variant + ".tres"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write SpriteFrames: " + variant)
		return
	file.store_string("\n".join(lines) + "\n")
