extends CharacterBody3D

const MonsterTable := preload("res://scripts/monsters/monster_table.gd")
const PickupScript := preload("res://scripts/limbs/limb_pickup.gd")

var spec: Dictionary = {}
var _sprite: Sprite3D
var _affordance: AffordanceProp
var _home := Vector3.ZERO
var _attack_wait := 0.4
var _wander := 0.0
var _wander_dir := Vector3.RIGHT
var _dropped := false
var _windup := 0.0
var _lunge := 0.0
var _lunge_dir := Vector3.ZERO
var _stun := 0.0
var _wind := 0.0
var _wind_at := Vector3.ZERO
var _wind_tick := 0.0
var _phase2 := false
var _skill := 0.0
var _health_mark := 0


func setup(monster_id: String, at: Vector3) -> void:
	spec = MonsterTable.monster(monster_id)
	position = at
	_home = at


func _ready() -> void:
	add_to_group("field_monster")
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42 if not spec.get("boss", false) else 0.7
	capsule.height = 1.35 if not spec.get("boss", false) else 2.2
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)
	_sprite = Sprite3D.new()
	_sprite.position.y = 0.95
	_sprite.pixel_size = 0.0022
	_sprite.double_sided = true
	var drawn := _texture()
	if drawn == null:
		drawn = _placeholder()
		_sprite.modulate = Color.WHITE
	else:
		_sprite.modulate = Color.WHITE
		_sprite.material_override = _cutout(drawn)
	_sprite.texture = drawn
	add_child(_sprite)
	var label := Label3D.new()
	label.text = str(spec.get("name", ""))
	label.position = Vector3(0.0, 2.05, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 42
	label.pixel_size = 0.004
	label.outline_size = 8
	label.no_depth_test = true
	add_child(label)
	_affordance = AffordanceProp.new()
	_affordance.configure_host(self, "enemy_elite" if spec.get("boss", false) else "enemy_small", int(spec.get("health", 28)))
	add_child(_affordance)
	_health_mark = _affordance.health


func _physics_process(delta: float) -> void:
	if _affordance == null:
		return
	if _affordance.spent:
		_drop()
		return
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	_attack_wait = maxf(_attack_wait - delta, 0.0)
	_stun = maxf(_stun - delta, 0.0)
	_skill = maxf(_skill - delta, 0.0)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = 0.0
	var wish := Vector3.ZERO
	if _stun <= 0.0:
		wish = _wish(player, delta)
	velocity.x = wish.x
	velocity.z = wish.z
	move_and_slide()
	_face(wish)
	_tick_wind(player, delta)
	if _affordance.health < _health_mark and _windup > 0.0:
		_windup = 0.0
		_stun = 0.55
		_sprite.modulate = Color.WHITE
	_health_mark = _affordance.health
	if spec.get("boss", false) and not _phase2 and _affordance.health * 2 <= int(spec.get("health", 1)):
		_enter_phase2(player)


func _wish(player: PlayerController, delta: float) -> Vector3:
	if spec.get("boss", false):
		return _boss_wish(player, delta)
	if player != null and bool(spec.get("aggressive", false)):
		var to := player.global_position - global_position
		to.y = 0.0
		var reach := 1.25
		if str(spec.get("attack", "")) == "lunge":
			reach = 1.7
		if to.length() < 9.0:
			if to.length() <= reach and _attack_wait <= 0.0:
				_strike(player)
			elif to.length() > reach * 0.7:
				return to.normalized() * float(spec.get("speed", 3.0))
			return Vector3.ZERO
	_wander -= delta
	if _wander <= 0.0:
		_wander = randf_range(0.8, 1.8)
		var angle := randf() * TAU
		_wander_dir = Vector3(cos(angle), 0.0, sin(angle))
	var home_delta := _home - global_position
	home_delta.y = 0.0
	if home_delta.length() > 4.5:
		return home_delta.normalized() * float(spec.get("speed", 3.0)) * 0.65
	return _wander_dir * float(spec.get("speed", 3.0)) * 0.45


func _boss_wish(player: PlayerController, delta: float) -> Vector3:
	if player == null:
		return Vector3.ZERO
	if _lunge > 0.0:
		_lunge -= delta
		if _lunge <= 0.0:
			_stun = 0.45
		elif global_position.distance_to(player.global_position) < 1.5:
			_strike(player)
		return _lunge_dir * 11.0
	if _windup > 0.0:
		_windup -= delta
		_sprite.modulate = Color(1.0, 0.35, 0.3)
		if _windup <= 0.0:
			var to := player.global_position - global_position
			to.y = 0.0
			_lunge_dir = to.normalized() if to.length_squared() > 0.01 else Vector3.FORWARD
			_lunge = 0.38
			_sprite.modulate = Color.WHITE
		return Vector3.ZERO
	if _skill <= 0.0:
		_skill = 4.5
		if randf() < 0.5:
			_windup = 0.55
			_health_mark = _affordance.health
			return Vector3.ZERO
		_wind = 2.6
		_wind_at = player.global_position
		_wind_tick = 0.0
	var chase := player.global_position - global_position
	chase.y = 0.0
	if chase.length() > 2.4:
		return chase.normalized() * float(spec.get("speed", 6.0))
	if _attack_wait <= 0.0:
		_strike(player)
	return Vector3.ZERO


func _strike(player: PlayerController) -> void:
	_attack_wait = float(spec.get("attack_cooldown", 0.6))
	player.take_hit(int(spec.get("damage", 0)))
	if str(spec.get("attack", "")) == "lunge":
		var bump := player.global_position - global_position
		bump.y = 0.0
		if bump.length_squared() > 0.01:
			player.velocity += bump.normalized() * 3.5


func _tick_wind(player: PlayerController, delta: float) -> void:
	if _wind <= 0.0 or player == null:
		return
	_wind -= delta
	_wind_tick -= delta
	if player.global_position.distance_to(_wind_at) > 2.4:
		return
	player.apply_slow(0.25, 0.45)
	if _wind_tick <= 0.0:
		_wind_tick = 0.45
		player.take_hit(4)


func _enter_phase2(player: PlayerController) -> void:
	_phase2 = true
	if player != null:
		player.invert_move(10.0)
	if get_parent() == null:
		return
	for index in 2:
		var bat := (get_script() as GDScript).new() as CharacterBody3D
		bat.call("setup", "bat", global_position + Vector3(-1.5 + float(index) * 3.0, 0.0, 1.5))
		get_parent().add_child(bat)


func _face(wish: Vector3) -> void:
	if _sprite == null or wish.length_squared() < 0.04:
		return
	var right := Vector3.RIGHT
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.get_parent() is FollowCameraRig:
		right = (camera.get_parent() as FollowCameraRig).get_planar_axes()[0]
	var screen := right.dot(wish.normalized())
	if absf(screen) > 0.12:
		# 现有侧面图头部在画面左侧，往右走时镜像，脸才朝向行进方向。
		_sprite.flip_h = screen > 0.0


func _drop() -> void:
	if _dropped:
		return
	_dropped = true
	var drop_id := str(spec.get("drop", ""))
	if not drop_id.is_empty() and get_parent() != null:
		var pickup := Node3D.new()
		pickup.set_script(PickupScript)
		pickup.position = global_position
		get_parent().add_child(pickup)
		pickup.call("setup", drop_id)
	queue_free()


func _texture() -> Texture2D:
	var path := str(spec.get("sprite", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _placeholder() -> Texture2D:
	var image := Image.create(48, 72, false, Image.FORMAT_RGBA8)
	var hue := float(absi(str(spec.get("id", "")).hash()) % 360) / 360.0
	image.fill(Color.from_hsv(hue, 0.5, 0.82))
	return ImageTexture.create_from_image(image)


func _cutout(drawn: Texture2D) -> Material:
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nuniform sampler2D tex : source_color;\nvoid fragment() {\n\tvec4 color = texture(tex, UV);\n\tif (color.r > 0.94 && color.g > 0.94 && color.b > 0.94) {\n\t\tdiscard;\n\t}\n\tALBEDO = color.rgb;\n}\n"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tex", drawn)
	return material
