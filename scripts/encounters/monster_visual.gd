class_name MonsterVisual
extends Node3D

var sprites: Array[Sprite3D] = []
var phase := 0.0
var facing_left := false

func setup(definition: MonsterDefinition) -> void:
	var paths: Array[Dictionary] = definition.parts
	if paths.is_empty():
		paths = [{"path": definition.image_path}]
	var texture := load(definition.image_path) as Texture2D
	var pixel_size := definition.image_height / maxf(1, texture.get_height())
	for part in paths:
		var sprite := Sprite3D.new()
		sprite.texture = load(str(part.path)) as Texture2D
		sprite.pixel_size = pixel_size
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.position = Vector3(0, definition.image_height * 0.5, sprites.size() * 0.0005)
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sprite)
		sprites.append(sprite)

func animate(delta: float, moving: bool, attack_amount: float, hurt: bool) -> void:
	phase += delta * 10
	for i in sprites.size():
		var sprite := sprites[i]
		sprite.flip_h = facing_left
		sprite.rotation.z = sin(phase + i * 0.7) * (0.025 if moving else 0.0) \
			+ sin(attack_amount * PI) * 0.12
		sprite.modulate = Color("#ff7777") if hurt else Color.WHITE
