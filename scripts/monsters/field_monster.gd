extends CharacterBody3D

const MonsterTable := preload("res://scripts/monsters/monster_table.gd")
const PickupScript := preload("res://scripts/limbs/limb_pickup.gd")

var spec: Dictionary = {}
var _sprite: Sprite3D
var _affordance: AffordanceProp
var _ground: LevelData
var _home := Vector3.ZERO
var _idle := 0.0
var _attack_wait := 0.4
var _heading := Vector3.RIGHT
var _heading_time := 0.0
var _heading_blocked := false
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
var _nameplate: Node3D
var _name_label: Label3D
var _bar_fill: Sprite3D
var _bar_track: Sprite3D
var _bar_width := 1.2
var _alert := false
var _returning := false
var _flee := 0.0
var _pause := 0.0

const HOME_WANDER := 7.5
const HOME_RETURN := 9.0
const HOME_ARRIVE := 2.2
const HOME_CHASE_LIMIT := 12.0
const AGGRO_ENTER := 10.5
const AGGRO_EXIT := 14.5
const FLEE_ENTER := 3.4


func setup(monster_id: String, at: Vector3) -> void:
	spec = MonsterTable.monster(monster_id)
	position = at
	_home = at


func use_ground(level: LevelData) -> void:
	_ground = level


func _ready() -> void:
	add_to_group("field_monster")
	# 不跟玩家和其他怪挤，只踩地形，避免把彼此推出悬崖。
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.3
	floor_stop_on_slope = true
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42 if not spec.get("boss", false) else 0.7
	capsule.height = 1.35 if not spec.get("boss", false) else 2.2
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)
	_sprite = Sprite3D.new()
	_sprite.name = "Sprite3D"
	var drawn := _artwork()
	var pixel := _pixel_size(drawn)
	var world_height := float(drawn.get_height()) * pixel
	_sprite.texture = drawn
	_sprite.pixel_size = pixel
	_sprite.position.y = world_height * 0.5
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = 0.12
	_sprite.double_sided = true
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite)
	_build_nameplate(world_height)
	_affordance = AffordanceProp.new()
	_affordance.configure_host(self, "enemy_small", int(spec.get("health", 28)))
	add_child(_affordance)
	_affordance.set_physics_process(false)
	_health_mark = _affordance.health


func _physics_process(delta: float) -> void:
	if _affordance == null:
		return
	if _affordance.spent:
		_drop()
		return
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if global_position.y < _home.y - 1.2:
		global_position = _home
		velocity = Vector3.ZERO
	_idle -= delta
	if player != null and global_position.distance_squared_to(player.global_position) > 256.0 and is_on_floor():
		if _idle > 0.0:
			return
		_idle = 0.35
	_attack_wait = maxf(_attack_wait - delta, 0.0)
	_stun = maxf(_stun - delta, 0.0)
	_skill = maxf(_skill - delta, 0.0)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = 0.0
	var wish := Vector3.ZERO
	if _stun <= 0.0:
		var raw := _wish(player, delta)
		var speed := float(spec.get("speed", 3.0))
		var spaced := _separate(raw, speed)
		wish = _keep_on_ground(spaced)
		if wish.length_squared() < 0.0001:
			wish = _keep_on_ground(raw)
	velocity.x = wish.x
	velocity.z = wish.z
	move_and_slide()
	_face(wish)
	_tick_wind(player, delta)
	if _affordance.health < _health_mark:
		if _windup > 0.0:
			_windup = 0.0
			_stun = 0.55
			_sprite.modulate = Color.WHITE
		else:
			_stun = maxf(_stun, 0.16)
			if _sprite != null:
				_sprite.modulate = Color(1.0, 0.48, 0.42)
			if not bool(spec.get("aggressive", false)) and not bool(spec.get("boss", false)):
				_begin_flee(player)
	elif _stun <= 0.0 and _sprite != null and _sprite.modulate != Color.WHITE:
		_sprite.modulate = Color.WHITE
	if _affordance.health != _health_mark:
		_health_mark = _affordance.health
		_apply_health_bar()
	if spec.get("boss", false) and not _phase2 and _affordance.health * 2 <= int(spec.get("health", 1)):
		_enter_phase2(player)


func _process(_delta: float) -> void:
	_place_nameplate()


func _build_nameplate(world_height: float) -> void:
	_nameplate = Node3D.new()
	_nameplate.name = "Nameplate"
	_nameplate.position = Vector3(0.0, world_height + 0.16, 0.0)
	add_child(_nameplate)
	_bar_track = _bar_sprite(Color(0.1, 0.07, 0.06, 0.88), 0)
	_bar_fill = _bar_sprite(Color.WHITE, 1)
	_name_label = Label3D.new()
	_name_label.text = str(spec.get("name", ""))
	_name_label.font = _ui_font()
	_name_label.position = Vector3(0.0, 0.38, 0.0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.font_size = 42
	_name_label.pixel_size = 0.011
	_name_label.outline_size = 10
	_name_label.modulate = Color(1.0, 0.96, 0.88)
	_name_label.outline_modulate = Color(0.1, 0.06, 0.05, 0.95)
	_name_label.no_depth_test = true
	_name_label.render_priority = 3
	_name_label.double_sided = true
	_nameplate.add_child(_name_label)
	_apply_health_bar()


func _bar_sprite(color: Color, priority: int) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = _bar_texture()
	sprite.pixel_size = _bar_width / 48.0
	sprite.position = Vector3(0.0, 0.08, 0.0)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.no_depth_test = true
	sprite.render_priority = priority
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.modulate = color
	_nameplate.add_child(sprite)
	return sprite


func _apply_health_bar() -> void:
	if _bar_fill == null:
		return
	var max_health := maxi(int(spec.get("health", 1)), 1)
	var health := _affordance.health if _affordance != null else max_health
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	_bar_fill.scale = Vector3(maxf(ratio, 0.04), 1.0, 1.0)
	_bar_fill.position.x = -_bar_width * (1.0 - ratio) * 0.5
	var tint := Color(0.86, 0.32, 0.24) if ratio <= 0.35 else Color(0.55, 0.84, 0.8)
	tint.a = _bar_fill.modulate.a
	_bar_fill.modulate = tint


func _place_nameplate() -> void:
	if _nameplate == null or _affordance == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var distance_squared := 9999.0
	if player != null:
		distance_squared = global_position.distance_squared_to(player.global_position)
	var max_health := maxi(int(spec.get("health", 1)), 1)
	var hurt := _affordance.health < max_health
	var limit := 256.0 if hurt else 100.0
	_nameplate.visible = distance_squared <= limit
	if not _nameplate.visible:
		return
	var solid := 144.0 if hurt else 49.0
	var alpha := 1.0
	if distance_squared > solid:
		alpha = clampf((limit - distance_squared) / (limit - solid), 0.0, 1.0)
	var ink := _name_label.modulate
	ink.a = alpha
	_name_label.modulate = ink
	var track := _bar_track.modulate
	track.a = alpha * 0.88
	_bar_track.modulate = track
	var fill := _bar_fill.modulate
	fill.a = alpha
	_bar_fill.modulate = fill


func _wish(player: PlayerController, delta: float) -> Vector3:
	if spec.get("boss", false):
		return _boss_wish(player, delta)
	var speed := float(spec.get("speed", 3.0))
	var home_delta := _home - global_position
	home_delta.y = 0.0
	if bool(spec.get("aggressive", false)):
		var chase := _chase_wish(player, home_delta.length(), speed)
		if _alert:
			return chase
	elif _passive_flee(player, delta):
		return _steer(_heading) * speed
	if _returning:
		if home_delta.length() <= HOME_ARRIVE:
			_returning = false
			_heading_time = 0.0
		else:
			_heading = home_delta.normalized()
			return _steer(_heading) * speed * 0.75
	elif home_delta.length() > HOME_RETURN:
		_returning = true
		_heading_blocked = false
		_pause = 0.0
		_heading = home_delta.normalized()
		return _steer(_heading) * speed * 0.75
	if _pause > 0.0:
		_pause -= delta
		return Vector3.ZERO
	if _heading_time <= 0.0:
		if randf() < 0.35:
			_pause = randf_range(0.6, 1.2)
			_heading = Vector3.ZERO
			return Vector3.ZERO
		_choose_heading()
	_heading_time -= delta
	if _heading.length_squared() < 0.01:
		return Vector3.ZERO
	var step := _steer(_heading)
	if step.length_squared() < 0.01:
		if not _heading_blocked:
			_heading_blocked = true
			_choose_heading()
			step = _steer(_heading)
		if step.length_squared() < 0.01:
			return Vector3.ZERO
	_heading_blocked = false
	return step * speed * 0.5


func _chase_wish(player: PlayerController, from_home: float, speed: float) -> Vector3:
	if player == null:
		_alert = false
		return Vector3.ZERO
	var to := player.global_position - global_position
	to.y = 0.0
	var distance := to.length()
	if _alert:
		if from_home > HOME_CHASE_LIMIT + 2.5 or distance > AGGRO_EXIT:
			_alert = false
	elif from_home < HOME_CHASE_LIMIT and distance < AGGRO_ENTER:
		_alert = true
		_alert_pack()
	if not _alert:
		return Vector3.ZERO
	_returning = false
	_pause = 0.0
	var reach := 1.7 if str(spec.get("attack", "")) == "lunge" else 1.25
	var hold := maxf(reach * 0.82, 1.05)
	if distance <= reach and _attack_wait <= 0.0:
		_strike(player)
		return Vector3.ZERO
	if distance <= hold:
		return Vector3.ZERO
	var aim := to
	if distance > hold + 0.45:
		var side := Vector3(-to.z, 0.0, to.x)
		if side.length_squared() > 0.01:
			var slot := 0.55 if int(get_instance_id()) % 2 == 0 else -0.55
			aim = to + side.normalized() * slot
	if aim.length_squared() < 0.01:
		return Vector3.ZERO
	return _steer(aim) * speed


func _passive_flee(player: PlayerController, delta: float) -> bool:
	if player != null and _flee <= 0.0:
		var near := player.global_position - global_position
		near.y = 0.0
		if near.length() < FLEE_ENTER:
			_begin_flee(player)
	if _flee <= 0.0:
		return false
	_flee -= delta
	_returning = false
	_pause = 0.0
	if _steer(_heading).length_squared() < 0.01:
		_heading = _heading.rotated(Vector3.UP, 0.9)
	return true


func _begin_flee(player: PlayerController) -> void:
	_flee = randf_range(1.3, 2.0)
	GameAudio.monster_voice(str(spec.get("id", "")))
	_returning = false
	_pause = 0.0
	_heading_blocked = false
	var away := Vector3.ZERO
	if player != null:
		away = global_position - player.global_position
		away.y = 0.0
	if away.length_squared() < 0.04:
		var angle := randf() * TAU
		away = Vector3(cos(angle), 0.0, sin(angle))
	_heading = away.normalized()
	_heading_time = _flee


func _alert_pack() -> void:
	var monster_id := str(spec.get("id", ""))
	for node in get_tree().get_nodes_in_group("field_monster"):
		if node == self or not bool(spec.get("aggressive", false)):
			continue
		var other := node as Node3D
		if other == null or global_position.distance_squared_to(other.global_position) > 36.0:
			continue
		var other_spec: Dictionary = node.get("spec")
		if str(other_spec.get("id", "")) != monster_id or not bool(other_spec.get("aggressive", false)):
			continue
		node.set("_alert", true)


func _choose_heading() -> void:
	_heading_time = randf_range(4.0, 7.0)
	var start := randf() * TAU
	var fallback := Vector3.ZERO
	for step in 8:
		var angle := start + float(step) * TAU / 8.0
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var ahead := global_position + dir * 2.4
		if _ground != null and not _stands(ahead):
			continue
		var from_home := ahead - _home
		from_home.y = 0.0
		if from_home.length() > HOME_WANDER:
			if fallback.length_squared() < 0.01:
				fallback = dir
			continue
		_heading = dir
		return
	_heading = fallback
	if fallback.length_squared() < 0.01:
		_heading_time = 1.2


func _steer(dir: Vector3) -> Vector3:
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	dir = dir.normalized()
	if _ground == null or _stands(global_position + dir * 0.7):
		return dir
	var side := Vector3(-dir.z, 0.0, dir.x)
	if _stands(global_position + side * 0.7):
		return side
	if _stands(global_position - side * 0.7):
		return -side
	return Vector3.ZERO


func _separate(wish: Vector3, speed: float) -> Vector3:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("field_monster"):
		if node == self:
			continue
		var other := node as Node3D
		if other == null:
			continue
		var gap := global_position - other.global_position
		gap.y = 0.0
		var distance_squared := gap.length_squared()
		if distance_squared > 2.25 or distance_squared < 0.0001:
			continue
		push += gap.normalized() * (1.5 - sqrt(distance_squared))
	if push.length_squared() < 0.04:
		return wish
	if wish.length_squared() < 0.0001:
		var shove := _steer(push)
		return shove * speed * 0.35
	return wish + push.normalized() * speed * 0.35


func _keep_on_ground(wish: Vector3) -> Vector3:
	if _ground == null or wish.length_squared() < 0.0001:
		return wish
	if _stands(global_position + wish.normalized() * 0.65):
		return wish
	return Vector3.ZERO


func _stands(at: Vector3) -> bool:
	var cell := _ground.world_to_cell(at)
	if not _ground.cell_exists(cell):
		return false
	var here := _ground.world_to_cell(global_position)
	if not _ground.cell_exists(here):
		return false
	return absi(_ground.elevation(here) - _ground.elevation(cell)) <= 1


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
	GameAudio.monster_voice(str(spec.get("id", "")))
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
	GameAudio.play("monster_death")
	var drop_id := str(spec.get("drop", ""))
	if not drop_id.is_empty() and get_parent() != null:
		var pickup := Node3D.new()
		pickup.set_script(PickupScript)
		pickup.position = global_position
		get_parent().add_child(pickup)
		pickup.call("setup", drop_id)
	queue_free()


static var _font: Font


func _artwork() -> Texture2D:
	var path := str(spec.get("sprite", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var loaded := load(path) as Texture2D
		if loaded != null:
			return loaded
	return _silhouette()


func _pixel_size(drawn: Texture2D) -> float:
	var target_height := 3.1 if spec.get("boss", false) else 1.85
	var max_width := 3.4 if spec.get("boss", false) else 2.6
	var height := maxf(float(drawn.get_height()), 1.0)
	var width := maxf(float(drawn.get_width()), 1.0)
	var pixel := target_height / height
	if width * pixel > max_width:
		pixel = max_width / width
	return pixel


func _silhouette() -> Texture2D:
	var boss := bool(spec.get("boss", false))
	var width := 148 if boss else 96
	var height := 196 if boss else 132
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var hue := float(absi(str(spec.get("id", "")).hash()) % 360) / 360.0
	var body := Color.from_hsv(hue, 0.46, 0.8)
	var ink := Color(0.16, 0.11, 0.09)
	_oval(image, int(width * 0.36), int(height * 0.9), int(width * 0.1), int(height * 0.045), ink)
	_oval(image, int(width * 0.64), int(height * 0.9), int(width * 0.1), int(height * 0.045), ink)
	_oval(image, int(width * 0.5), int(height * 0.62), int(width * 0.26), int(height * 0.2), body)
	_oval(image, int(width * 0.32), int(height * 0.32), int(width * 0.16), int(height * 0.12), body.lightened(0.1))
	_oval(image, int(width * 0.24), int(height * 0.3), 4, 4, ink)
	return ImageTexture.create_from_image(image)


func _oval(image: Image, center_x: int, center_y: int, radius_x: int, radius_y: int, color: Color) -> void:
	var rx := maxi(radius_x, 1)
	var ry := maxi(radius_y, 1)
	for y in range(center_y - ry, center_y + ry + 1):
		for x in range(center_x - rx, center_x + rx + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var nx := float(x - center_x) / float(rx)
			var ny := float(y - center_y) / float(ry)
			if nx * nx + ny * ny <= 1.0:
				image.set_pixel(x, y, color)


static var _bar_tex: Texture2D


static func _bar_texture() -> Texture2D:
	if _bar_tex != null:
		return _bar_tex
	var image := Image.create(48, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_bar_tex = ImageTexture.create_from_image(image)
	return _bar_tex


static func _ui_font() -> Font:
	if _font != null:
		return _font
	var play := load("res://scripts/runtime/level_playtest.gd") as GDScript
	if play != null:
		var shared: Font = play.runtime_font()
		if shared != null and shared.has_char("狼".unicode_at(0)):
			_font = shared
			return _font
	_font = ThemeDB.fallback_font
	return _font
