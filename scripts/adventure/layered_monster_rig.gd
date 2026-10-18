class_name LayeredMonsterRig
extends Node3D

# The artist's 1080 px layer canvases share one coordinate system. Their white
# backgrounds are keyed by the shader at draw time; the source art is untouched.
const ART_ROOT := "res://assets/source_art/new_monsters_20261018/"
const WHITE_KEY := preload("res://assets/derived_art/new_monsters_20261018/white_key.gdshader")
const RIGS := {
	"gerbil": {
		"scale": 0.0022, "height": 1.12,
		"front": [
			["foot", "gerbil/8c03448fa084bb5b6e3c418e18a60afe.jpg", Vector2(650, 890), 0],
			["body", "gerbil/c3e10404635450ad7bb76c6d78cd3ac2.jpg", Vector2(535, 555), 1],
			["left_arm", "gerbil/8e2637d6cd5fdd4bbe275a68fb818d19.png", Vector2(275, 530), 2],
			["right_arm", "gerbil/036be1e1881a1bc079fd156becb3dcdf.jpg", Vector2(600, 535), 3],
		],
	},
	"wolf": {
		"scale": 0.00235, "height": 1.1,
		"front": [
			["rear_left", "wolf/42e726c39693536bf877a47c308d06ac.jpg", Vector2(660, 480), 0],
			["rear_right", "wolf/后前肢.jpg", Vector2(745, 570), 1],
			["body", "wolf/躯干.jpg", Vector2(500, 520), 2],
			["front_left", "wolf/c76abfb77c849d90b8e2afbfebd21f1a.jpg", Vector2(470, 520), 3],
			["front_right", "wolf/e43b66567ac9a048ae83aa0c59a0bf34.jpg", Vector2(425, 600), 4],
		],
	},
	"gorilla": {
		"scale": 0.0027, "height": 1.35,
		"front": [
			["rear_left", "gorilla_front/430a2a64e2962fa98d709b3c8e37e79b.jpg", Vector2(790, 645), 0],
			["rear_right", "gorilla_front/ac4dcb40c885acfb5abc895b7d73f574.jpg", Vector2(425, 650), 0],
			["body", "gorilla_front/af206cd00a7d9ad85018b59865bda150.jpg", Vector2(540, 480), 2],
			["left_arm", "gorilla_front/7349235d8e11f0ad0fe4408e55606868.jpg", Vector2(275, 350), 3],
			["right_arm", "gorilla_front/16b8d76bc056d777d4b4ec8565fd4004.jpg", Vector2(680, 350), 4],
		],
		"side": [
			["rear_left", "gorilla_side/1e34198eeff691a43d660be069ccb0dc.png", Vector2(800, 540), 0],
			["rear_right", "gorilla_side/a15d87529ac7cdcfc553b57d7d1c1358.png", Vector2(530, 625), 0],
			["body", "gorilla_side/d1f66be7f69771f2eba175cf4365f2ad.jpg", Vector2(485, 455), 2],
			["left_arm", "gorilla_side/7349235d8e11f0ad0fe4408e55606868.jpg", Vector2(250, 360), 3],
			["right_arm", "gorilla_side/0627eea721a81218768b01507188cc58.jpg", Vector2(675, 250), 4],
		],
	},
	"gibbon": {
		"scale": 0.0025, "height": 1.18,
		"front": [
			["rear_left", "gibbon/b010e99c5501550588824fac1a5958a7.jpg", Vector2(515, 655), 0],
			["rear_right", "gibbon/90d5218a4c0e18474f740dc3710cf313.jpg", Vector2(665, 640), 0],
			["body", "gibbon/34e7eab1487586ca8666036e7de4ea14.jpg", Vector2(480, 480), 2],
			["left_arm", "gibbon/26c2944ff580e42163cce6b23301c923.jpg", Vector2(400, 350), 3],
			["right_arm", "gibbon/fc9ab77c3960b968e2c9e96c6713951d.png", Vector2(520, 360), 4],
		],
	},
	"ostrich": {
		"scale": 0.00255, "height": 1.37,
		"front": [
			["rear_left", "ostrich/1cfa74ddeedf505f10e316e65a8df9a6.jpg", Vector2(555, 505), 0],
			["rear_right", "ostrich/198dc734924bd283051ff91fc9677299.jpg", Vector2(645, 500), 1],
			["body", "ostrich/845a3a7e2d4644996da7b18ba6c721db.jpg", Vector2(555, 485), 2],
		],
	},
}

@export_enum("gerbil", "wolf", "gorilla", "gibbon", "ostrich") var kind := "gerbil"
var moving := false
var attack_time := 0.0
var dead := false
var clock := 0.0
var side_view := false
var facing_left := false
var groups: Dictionary = {}
var puffs: Array[MeshInstance3D] = []


func configure(monster_kind: String) -> void:
	kind = monster_kind


func _ready() -> void:
	var data: Dictionary = RIGS[kind]
	for orientation in ["front", "side"]:
		if not data.has(orientation):
			continue
		var holder := Node3D.new()
		holder.name = orientation.capitalize()
		add_child(holder)
		var motion_root := Node3D.new()
		motion_root.name = "BodyMotion"
		holder.add_child(motion_root)
		var part_nodes: Dictionary = {}
		for part_data in data[orientation]:
			var part_name: String = part_data[0]
			var image_path: String = part_data[1]
			var pivot_pixels: Vector2 = part_data[2]
			var layer: int = part_data[3]
			var joint := Node3D.new()
			joint.name = part_name
			joint.position = Vector3((pivot_pixels.x - 540.0) * float(data["scale"]),
				(540.0 - pivot_pixels.y) * float(data["scale"]), layer * 0.008)
			motion_root.add_child(joint)
			var sprite := Sprite3D.new()
			sprite.texture = load(ART_ROOT + image_path) as Texture2D
			sprite.pixel_size = float(data["scale"])
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.shaded = false
			sprite.position = Vector3(-joint.position.x, -joint.position.y, 0)
			if kind == "gorilla":
				if orientation == "side" and part_name == "rear_left":
					sprite.position.x -= 0.13
				elif part_name == "left_arm":
					sprite.position.x += 0.045
				elif part_name == "right_arm":
					sprite.position.x -= 0.055
			var key_material := ShaderMaterial.new()
			key_material.shader = WHITE_KEY
			key_material.set_shader_parameter("source_texture", sprite.texture)
			sprite.material_override = key_material
			joint.add_child(sprite)
			part_nodes[part_name] = joint
		groups[orientation] = {"holder": holder, "motion_root": motion_root, "parts": part_nodes}
	position.y = float(data["height"])
	_update_visibility()
	_build_smoke()

func set_movement(world_velocity: Vector3) -> void:
	moving = Vector2(world_velocity.x, world_velocity.z).length() > 0.3
	if absf(world_velocity.x) > 0.12:
		facing_left = world_velocity.x < 0.0
	if kind == "gorilla" and moving:
		var new_side := absf(world_velocity.x) > absf(world_velocity.z)
		if new_side != side_view:
			side_view = new_side
			_update_visibility()


func play_attack() -> void:
	attack_time = 0.4


func play_death() -> void:
	dead = true
	for key in groups:
		(groups[key]["holder"] as Node3D).visible = false
	for puff in puffs:
		puff.visible = true


func _process(delta: float) -> void:
	clock += delta * (11.0 if moving else 2.0)
	attack_time = maxf(0.0, attack_time - delta)
	if dead:
		_animate_smoke(delta)
		return
	var orientation := "side" if side_view and groups.has("side") else "front"
	var parts: Dictionary = groups[orientation]["parts"]
	var amount := 1.0 if moving else 0.08
	var strike := sin((1.0 - attack_time / 0.4) * PI) if attack_time > 0.0 else 0.0
	var walk_angle := 0.11
	if kind == "gorilla":
		walk_angle = 0.07
	elif kind in ["gibbon", "gerbil", "ostrich"]:
		walk_angle = 0.09
	var motion_root: Node3D = groups[orientation]["motion_root"]
	var torso_turn := 0.02 * sin(clock * 0.5)
	if kind == "ostrich":
		torso_turn += 0.14 * strike
	elif kind == "gerbil":
		torso_turn += 0.12 * strike
	else:
		torso_turn += 0.08 * strike
	motion_root.rotation.z = lerpf(motion_root.rotation.z, torso_turn, minf(1.0, delta * 16.0))
	var lunge := -0.18 if kind == "ostrich" else (-0.12 if kind == "wolf" else 0.0)
	motion_root.position.x = lerpf(motion_root.position.x, lunge * strike, minf(1.0, delta * 16.0))
	motion_root.position.y = lerpf(motion_root.position.y, -0.08 * strike if kind == "ostrich" else 0.0, minf(1.0, delta * 16.0))
	for part_name in parts:
		var pivot: Node3D = parts[part_name]
		var target := 0.0
		var part_walk_angle := walk_angle
		if kind == "gorilla" and orientation == "side" and part_name == "rear_left":
			part_walk_angle = 0.0
		elif kind == "gorilla" and part_name.begins_with("rear_"):
			part_walk_angle = 0.04
		if part_name in ["front_left", "rear_left", "left_arm"]:
			target = sin(clock) * part_walk_angle * amount
		elif part_name in ["front_right", "rear_right", "right_arm"]:
			target = -sin(clock) * part_walk_angle * amount
		elif part_name == "foot":
			target = sin(clock) * 0.09 * amount
		if strike > 0.0:
			if kind != "gerbil" and part_name in ["front_left", "front_right", "left_arm", "right_arm"]:
				var hit_angle := 0.15
				if kind == "gorilla":
					hit_angle = 0.11
				elif kind == "gibbon":
					hit_angle = 0.14
				if kind == "gorilla" and orientation == "side" and part_name == "right_arm":
					hit_angle = 0.06
				target += (hit_angle if part_name.ends_with("left") or part_name == "left_arm" else -hit_angle) * strike
		pivot.rotation.z = lerpf(pivot.rotation.z, target, minf(1.0, delta * 16.0))
	position.y = float(RIGS[kind]["height"]) + sin(clock * 2.0) * (0.055 if moving else 0.012)
	for key in groups:
		var holder: Node3D = groups[key]["holder"]
		holder.scale.x = -1.0 if facing_left else 1.0


func _update_visibility() -> void:
	for key in groups:
		(groups[key]["holder"] as Node3D).visible = not dead and key == ("side" if side_view and groups.has("side") else "front")


func _build_smoke() -> void:
	for index in 6:
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.32
		sphere.height = 0.64
		puff.mesh = sphere
		var smoke_material := StandardMaterial3D.new()
		smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke_material.albedo_color = Color(0.76, 0.71, 0.75, 0.46)
		puff.material_override = smoke_material
		puff.position = Vector3(cos(TAU * index / 6.0) * 0.26, -0.25, sin(TAU * index / 6.0) * 0.16)
		puff.visible = false
		add_child(puff)
		puffs.append(puff)


func _animate_smoke(delta: float) -> void:
	for index in puffs.size():
		var puff := puffs[index]
		puff.position += Vector3(cos(float(index)) * 0.23, 0.65, sin(float(index)) * 0.23) * delta
		puff.scale += Vector3.ONE * delta * 0.65
		var material: StandardMaterial3D = puff.material_override
		var color := material.albedo_color
		color.a = maxf(0.0, color.a - delta * 0.56)
		material.albedo_color = color
