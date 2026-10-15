extends SceneTree

var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	print("CAMERA CHECK ", label, " ", condition)
	if not condition:
		failures.append(label)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/level_playtest.tscn") as PackedScene
	var playtest = packed.instantiate()
	# Independent of the last editor playtest request stored in user://.
	playtest.level_override = "res://data/levels/acceptance_map.tres"
	root.add_child(playtest)
	await process_frame
	var profile := load("res://data/art_profile.tres") as ArtProfile
	var expected_offset := profile.camera_direction() * profile.camera_distance
	var rig: FollowCameraRig = playtest.camera_rig
	var player: CharacterBody3D = playtest.player
	var camera: Camera3D = playtest.camera
	check(player.name == "Player" and rig.target == player,
		"real playtest camera binds to the runtime player")
	check(rig.offset.is_equal_approx(expected_offset)
		and rig.focus_offset.is_equal_approx(Vector3.UP * profile.target_height),
		"runtime rig reads distance pitch and target height from art profile")
	check(camera.projection == (
			Camera3D.PROJECTION_PERSPECTIVE if profile.perspective
			else Camera3D.PROJECTION_ORTHOGONAL)
		and is_equal_approx(camera.fov, profile.field_of_view),
		"runtime camera reads projection and FOV from art profile")
	check(rig.global_position.distance_to(player.global_position + expected_offset) < 0.25,
		"runtime camera starts centered on player")
	var previous_position := rig.global_position
	player.position += Vector3(6.0, 0.0, -4.0)
	rig._process(0.2)
	var desired := player.global_position + expected_offset
	check(rig.global_position != previous_position
		and rig.global_position.distance_to(desired)
			< previous_position.distance_to(desired),
		"runtime camera follows player smoothly")
	var labels := playtest.find_children("*", "Label", true, false)
	var runtime_font: Font = labels[0].get_theme_font("font") if not labels.is_empty() \
		else null
	check(runtime_font != null
		and runtime_font.has_char("地".unicode_at(0))
		and runtime_font.has_char("玩".unicode_at(0)),
		"runtime UI font covers Chinese playtest text")
	playtest.queue_free()
	await process_frame
	print("CAMERA TEST FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)
