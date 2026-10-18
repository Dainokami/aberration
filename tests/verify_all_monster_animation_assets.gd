extends SceneTree

const OLD_ROOT := "res://assets/derived_art/small_monsters/sprite_frames/"
const NEW_ROOT := "res://assets/animations/new_monsters/sprite_frames/"
const OLD_VIEWS := ["octopus", "bat", "demon_dog", "goose", "kangaroo_front", "kangaroo_side"]
const NEW_VIEWS := ["gerbil", "wolf", "gorilla_front", "gorilla_side", "gibbon", "ostrich"]


func _initialize() -> void:
	for root_path in [OLD_ROOT, NEW_ROOT]:
		var views: Array = OLD_VIEWS if root_path == OLD_ROOT else NEW_VIEWS
		for view in views:
			var sprite_frames := load(root_path + view + ".tres") as SpriteFrames
			assert(sprite_frames != null, view + " failed to load")
			for action in ["walk", "attack", "death"]:
				assert(sprite_frames.has_animation(action), view + " missing " + action)
				assert(sprite_frames.get_frame_count(action) >= 8, view + " has too few " + action + " frames")
	print("ALL_TEN_MONSTER_ANIMATIONS_READY")
	quit()
