class_name MonsterVisual
extends Node3D

signal death_finished

var sprites: Array[Sprite3D] = []
var phase := 0.0
var facing_left := false
var animation: StringName = &"idle"
var frame := 0
var _definition: MonsterDefinition
var _idle_texture: Texture2D
var _frames: SpriteFrames
var _elapsed := 0.0
var _attack_windup := 0.35
var _just_started := false

func setup(definition: MonsterDefinition) -> void:
	_definition = definition
	_frames = definition.sprite_frames
	_idle_texture = load(definition.image_path) as Texture2D
	facing_left = definition.image_faces_left
	set_process(false)
	var paths: Array[Dictionary] = definition.parts
	if paths.is_empty() or _frames != null:
		paths = [{"path": definition.image_path}]
	var pixel_size := definition.image_height / maxf(1, _idle_texture.get_height())
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
	if not definition.procedural_motion:
		_show_idle()

func animate(delta: float, moving: bool, attack_amount: float, hurt: bool) -> void:
	if animation == &"death":
		return
	if _frames != null:
		if animation == &"attack":
			_advance(delta)
		else:
			var desired: StringName = &"walk" if moving or _definition.movement == "air" else &"idle"
			if desired != animation:
				animation = desired
				_elapsed = 0.0
			if animation == &"walk":
				_advance(delta)
			else:
				_show_idle()
	phase += delta * 10
	for i in sprites.size():
		var sprite := sprites[i]
		sprite.flip_h = facing_left != _definition.image_faces_left
		if _definition.procedural_motion and _frames == null:
			sprite.rotation.z = sin(phase + i * 0.7) * (0.025 if moving else 0.0) \
				+ sin(attack_amount * PI) * 0.12
		sprite.modulate = Color("#ff7777") if hurt else Color.WHITE

func play_attack(windup: float) -> void:
	if _frames == null or animation == &"death":
		return
	animation = &"attack"
	_attack_windup = maxf(windup, 0.001)
	_elapsed = 0.0
	_just_started = true
	_show_frame(0)

func cancel_attack() -> void:
	if animation == &"attack":
		animation = &"idle"
		_elapsed = 0.0
		_show_idle()

func play_death() -> bool:
	if _frames == null:
		return false
	animation = &"death"
	_elapsed = 0.0
	_just_started = false
	sprites[0].modulate = Color.WHITE
	_show_frame(0)
	# Live animation is driven by actor physics (and sleeps with streamed actors).
	# Only the short death effect ticks after combat has stopped.
	set_process(true)
	return true

func _process(delta: float) -> void:
	_advance(delta)

func _advance(delta: float) -> void:
	if _just_started:
		_just_started = false
	else:
		_elapsed += delta
	var count := _frames.get_frame_count(animation)
	var fps := _frames.get_animation_speed(animation)
	var index := int(_elapsed * fps)
	if animation == &"attack":
		# The package's impact is frame 4. Fit its anticipation to gameplay's
		# existing windup, then play recovery at the supplied 12 fps.
		var impact := count / 2
		index = int(_elapsed / _attack_windup * impact) if _elapsed < _attack_windup \
			else impact + int((_elapsed - _attack_windup) * fps)
	if animation == &"walk":
		index %= count
	elif index >= count:
		if animation == &"death":
			_show_frame(count - 1)
			set_process(false)
			death_finished.emit()
		else:
			animation = &"idle"
			_elapsed = 0.0
			_show_idle()
		return
	_show_frame(index)

func _show_frame(index: int) -> void:
	frame = index
	var sprite := sprites[0]
	sprite.texture = _frames.get_frame_texture(animation, index)
	sprite.pixel_size = _definition.image_height / _definition.animation_height_pixels
	sprite.position = Vector3.ZERO
	sprite.offset = Vector2(0, _definition.animation_anchor_y - sprite.texture.get_height() * 0.5)

func _show_idle() -> void:
	frame = 0
	var sprite := sprites[0]
	sprite.texture = _idle_texture
	sprite.pixel_size = _definition.image_height / _idle_texture.get_height()
	sprite.position = Vector3.ZERO
	sprite.offset = Vector2(0, _idle_texture.get_height() * 0.5)
