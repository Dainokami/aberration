extends Control

const ROOT := "res://assets/derived_art/small_monsters/"
const MONSTERS := [
    ["octopus", "章鱼"], ["bat", "蝙蝠"], ["demon_dog", "恶魔犬"],
    ["goose", "大鹅"], ["kangaroo_side", "袋鼠·侧面"],
    ["kangaroo_front", "袋鼠·正面"],
]
var actors: Array[AnimatedSprite2D] = []


func _ready() -> void:
    var background := ColorRect.new()
    background.color = Color("625864")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(background)
    var title := Label.new()
    title.text = "小怪动画 · W 移动 / A 攻击 / D 死亡 / R 重置"
    title.position = Vector2(30, 18)
    title.add_theme_font_size_override("font_size", 24)
    add_child(title)
    for index in range(MONSTERS.size()):
        var item: Array = MONSTERS[index]
        var col := index % 3
        var row := index / 3
        var scene := load(ROOT + "scenes/" + item[0] + ".tscn") as PackedScene
        var actor := scene.instantiate() as AnimatedSprite2D
        actor.position = Vector2(205 + col*420, 285 + row*300)
        actor.scale = Vector2(.55, .55)
        add_child(actor)
        actors.append(actor)
        var label := Label.new()
        label.text = item[1]
        label.position = Vector2(150 + col*420, 335 + row*300)
        label.add_theme_font_size_override("font_size", 20)
        add_child(label)


func _unhandled_key_input(event: InputEvent) -> void:
    var key := event as InputEventKey
    if key == null or not key.pressed or key.echo:
        return
    for actor in actors:
        match key.keycode:
            KEY_W: actor.play_walk()
            KEY_A: actor.play_attack()
            KEY_D: actor.play_death()
            KEY_R: actor.reset_to_idle()
