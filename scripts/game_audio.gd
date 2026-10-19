class_name GameAudio
extends RefCounted

## 播放 art/音效整理包 里已经对上现有动作的音效。音量走 Master，暂停面板的滑杆仍然管得到。

const ROOT := "res://art/音效整理包/整理后的音效/"

const _PATHS := {
	"player_attack": ROOT + "01_主角/攻击音效.mp3",
	"player_hurt": ROOT + "01_主角/受击音效.mp3",
	"player_death": ROOT + "01_主角/死亡音效.mp3",
	"step_grass": ROOT + "01_主角/草地行走音效.mp3",
	"step_rock": ROOT + "01_主角/岩石行走音效.mp3",
	"step_sand": ROOT + "01_主角/沙地行走音效.mp3",
	"step_water": ROOT + "01_主角/海洋行走音效.mp3",
	"bag": ROOT + "02_交互物/打开背包音效.mp3",
	"chest": ROOT + "02_交互物/打开宝箱音效.mp3",
	"rock_break": ROOT + "02_交互物/风化岩石碎裂音效.mp3",
	"throw": ROOT + "02_交互物/扔石头音效.mp3",
	"culture": ROOT + "04_UI交互/培养皿开始合成.mp3",
	"recycle": ROOT + "04_UI交互/肢体回收音效.mp3",
	"bgm": ROOT + "03_游戏背景音/大地图探索背景音.mp3",
	"monster_death": ROOT + "05_小怪/统一死亡音效.mp3",
	"voice_gibbon": ROOT + "05_小怪/长臂猿和狒狒攻击声.mp3",
	"voice_gorilla": ROOT + "05_小怪/长臂猿和狒狒攻击声.mp3",
	"voice_albatross": ROOT + "05_小怪/信天翁和老鹰攻击声.mp3",
	"voice_eagle": ROOT + "05_小怪/信天翁和老鹰攻击声.mp3",
	"voice_gerbil": ROOT + "05_小怪/啮齿类动物声音.mp3",
	"voice_goose": ROOT + "05_小怪/鹅攻击音.mp3",
}

static var _host: Node
static var _cache: Dictionary = {}
static var _bgm: AudioStreamPlayer
static var _step_wait := 0.0


static func play(key: String, volume_db := 0.0) -> void:
	var host := _ensure_host()
	var stream := _stream(key)
	if host == null or stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = stream
	player.volume_db = volume_db
	player.bus = "Master"
	player.finished.connect(player.queue_free)
	_start(host, player)


static func monster_voice(monster_id: String) -> void:
	play("voice_" + monster_id)


static func start_explore() -> void:
	if _bgm != null and is_instance_valid(_bgm):
		return
	var host := _ensure_host()
	var stream := _stream("bgm")
	if host == null or stream == null:
		return
	var looped := stream.duplicate() as AudioStream
	if looped == null:
		return
	looped.set("loop", true)
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "Explore"
	_bgm.process_mode = Node.PROCESS_MODE_PAUSABLE
	_bgm.stream = looped
	_bgm.volume_db = -12.0
	_bgm.bus = "Master"
	_start(host, _bgm)


static func tick_step(delta: float, body: CharacterBody3D) -> void:
	_step_wait = maxf(_step_wait - delta, 0.0)
	if body == null or not body.is_on_floor():
		return
	var flat := Vector2(body.velocity.x, body.velocity.z)
	if flat.length() < 1.1 or _step_wait > 0.0:
		return
	_step_wait = 0.42
	play(_step_key(body.global_position), -6.0)


static func _step_key(at: Vector3) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return "step_grass"
	var builder := tree.current_scene.get("builder") as Node
	var data := (builder.get("level_data") if builder != null else null) as LevelData
	if data == null:
		return "step_grass"
	var tile := data.tile_id(data.world_to_cell(at))
	if tile == "sand":
		return "step_sand"
	if tile == "rock":
		return "step_rock"
	if tile == "water":
		return "step_water"
	return "step_grass"


static func _stream(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key] as AudioStream
	var path := str(_PATHS.get(key, ""))
	var stream: AudioStream = null
	if not path.is_empty() and ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	_cache[key] = stream
	return stream


static func _start(host: Node, player: AudioStreamPlayer) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var parent := host if host != null and host.is_inside_tree() else tree.root if tree != null else null
	if parent == null:
		return
	parent.add_child(player)
	if player.is_inside_tree():
		player.play()
	else:
		player.tree_entered.connect(player.play, CONNECT_ONE_SHOT)


static func _ensure_host() -> Node:
	if _host != null and is_instance_valid(_host):
		return _host
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	_host = Node.new()
	_host.name = "GameAudio"
	_host.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(_host)
	return _host
