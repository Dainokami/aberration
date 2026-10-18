extends AnimatedSprite2D
## Named small-monster scene; SpriteFrames are stored in this asset directory.

@export_enum("octopus", "bat", "demon_dog", "goose", "kangaroo_side", "kangaroo_front")
var monster_id: String = "octopus"
@export var autoplay_idle: bool = true

const FRAMES_ROOT := "res://assets/derived_art/small_monsters/sprite_frames/"


func _ready() -> void:
    animation_finished.connect(_on_animation_finished)
    if autoplay_idle:
        play("idle")


func play_walk() -> void:
    play("walk")


func play_attack() -> void:
    play("attack")


func play_death() -> void:
    play("death")


func reset_to_idle() -> void:
    play("idle")


func set_move_direction(direction: Vector2) -> void:
    if monster_id == "kangaroo_side" or monster_id == "kangaroo_front":
        var horizontal := absf(direction.x) > absf(direction.y)
        var target := "kangaroo_side" if horizontal else "kangaroo_front"
        if target != monster_id:
            monster_id = target
            sprite_frames = load(FRAMES_ROOT + target + ".tres") as SpriteFrames
        flip_h = horizontal and direction.x < 0.0
    elif direction.x != 0.0:
        flip_h = direction.x < 0.0


func play_walk_direction(direction: Vector2) -> void:
    set_move_direction(direction)
    play_walk()


func _on_animation_finished() -> void:
    if animation == "attack":
        play("idle")
