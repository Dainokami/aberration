extends Node3D

const RIG_SCENES := "res://assets/animations/new_monsters/rigs/"
const MONSTERS := [
	["gerbil", "沙鼠", false],
	["wolf", "狼", false],
	["gorilla", "猩猩·正", false],
	["gorilla", "猩猩·侧", true],
	["gibbon", "长臂猿", false],
	["ostrich", "鸵鸟", false],
]

var rigs: Array[LayeredMonsterRig] = []
var timer := 0.0
var last_attack_cycle := -1
var last_death_cycle := -1
var walk_enabled := true


func _ready() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16.5
	camera.current = true
	camera.position = Vector3(0, 9, 18)
	add_child(camera)
	camera.look_at(Vector3(0, 1.1, 0), Vector3.UP)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#d8d3c5")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	add_child(light)
	for index in MONSTERS.size():
		var ground := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.65
		disc.bottom_radius = 0.65
		disc.height = 0.02
		ground.mesh = disc
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#8c8278")
		ground.material_override = material
		ground.position = Vector3((index - 2.5) * 2.5, -0.05, 0)
		add_child(ground)
		var title := Label3D.new()
		title.text = str(MONSTERS[index][1])
		title.font_size = 48
		title.pixel_size = 0.006
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		title.modulate = Color("#312b2e")
		title.position = Vector3((index - 2.5) * 2.5, -0.55, 0)
		add_child(title)
	_spawn_rigs()
	var ui := CanvasLayer.new()
	add_child(ui)
	var hint := Label.new()
	hint.text = "新小怪分层动画预览    W：行走/停止    空格：攻击    D：烟雾死亡    R：重置"
	hint.position = Vector2(30, 20)
	hint.add_theme_font_size_override("font_size", 21)
	hint.add_theme_color_override("font_color", Color("#2a2530"))
	ui.add_child(hint)


func _spawn_rigs() -> void:
	for rig in rigs:
		if is_instance_valid(rig):
			rig.queue_free()
	rigs.clear()
	for index in MONSTERS.size():
		var rig := (load(RIG_SCENES + str(MONSTERS[index][0]) + "_rig.tscn") as PackedScene).instantiate() as LayeredMonsterRig
		rig.position.x = (index - 2.5) * 2.5
		add_child(rig)
		rig.set_movement(Vector3(1, 0, 0) if bool(MONSTERS[index][2]) else Vector3(0, 0, 1))
		rigs.append(rig)


func _process(delta: float) -> void:
	timer += delta
	var cycle := floori(timer / 7.0)
	var phase := fmod(timer, 7.0)
	if phase < 5.0:
		for index in rigs.size():
			rigs[index].set_movement((Vector3(1, 0, 0) if bool(MONSTERS[index][2]) else Vector3(0, 0, 1)) if walk_enabled else Vector3.ZERO)
		if phase > 2.4 and last_attack_cycle != cycle:
			last_attack_cycle = cycle
			for rig in rigs:
				rig.play_attack()
	elif last_death_cycle != cycle:
		last_death_cycle = cycle
		for rig in rigs:
			rig.play_death()
	if cycle > 0 and phase < delta:
		_spawn_rigs()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_W:
			walk_enabled = not walk_enabled
		KEY_SPACE:
			for rig in rigs:
				rig.play_attack()
		KEY_D:
			for rig in rigs:
				rig.play_death()
		KEY_R:
			_spawn_rigs()
