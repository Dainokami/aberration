extends SceneTree

const ROOT := "res://assets/animations/new_monsters/"
const VARIANTS := ["gerbil", "wolf", "gorilla_front", "gorilla_side", "gibbon", "ostrich"]


func _initialize() -> void:
	for variant in VARIANTS:
		var frames := load(ROOT + "sprite_frames/" + variant + ".tres") as SpriteFrames
		assert(frames != null, variant + " SpriteFrames failed to load")
		for clip in ["walk", "attack", "death"]:
			assert(frames.has_animation(clip), variant + " missing " + clip)
			assert(frames.get_frame_count(clip) >= 8, variant + " too few " + clip + " frames")
			var image := (load(ROOT + "sprite_frames/" + variant + "_" + clip + ".png") as Texture2D).get_image()
			assert(image != null and image.get_width() >= 2560, variant + " sheet failed to load")
			assert(image.get_pixel(0, 0).a < 0.01, variant + " sheet lost transparency")
		var kind: String = variant.trim_suffix("_front").trim_suffix("_side")
		assert(load(ROOT + "rigs/" + kind + "_rig.tscn") is PackedScene, kind + " rig failed to load")
	print("NEW_MONSTER_ASSETS_READY")
	quit()
