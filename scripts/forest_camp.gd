extends Node3D
## Reference reconstruction: geometry owns height/collision; cutouts own decoration.
const CELL_SIZE := 2.0
const STEP_HEIGHT := CELL_SIZE
const SPAWN := Vector3(0, 0.85, 7)
const ART := "res://assets/source_art/"
var camera: Camera3D
var player: CharacterBody3D
var status: Label
var decoration: Node3D
var rng := RandomNumberGenerator.new()
var testing := false
var test_direction := Vector3.ZERO
var elapsed := 0.0
var water_material: ShaderMaterial

func _ready() -> void:
	rng.seed = 20261008
	testing = "--test-camp" in OS.get_cmdline_user_args()
	environment_setup()
	terrain_setup()
	landmarks()
	player_setup()
	ui_setup()
	if testing:
		run_checks.call_deferred()
	if "--capture-camp" in OS.get_cmdline_user_args():
		capture.call_deferred()

func environment_setup() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24.0
	add_child(camera)
	camera.position = Vector3(4, 26, 33)
	camera.look_at(Vector3(0, 0, 0))
	camera.current = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#111323")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#aaa7ce")
	env.ambient_light_energy = 0.7
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, -25, 0)
	sun.light_color = Color("#bcb9ea")
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	add_child(sun)
	decoration = Node3D.new()
	decoration.name = "Decoration"
	add_child(decoration)

func paint(color: Color, terrain: bool = false) -> Material:
	if not terrain:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 1.0
		return m
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 base : source_color;
varying vec3 pos;
void vertex(){ pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
	float brush=sin(pos.x*6.0+sin(pos.z*4.0))*sin(pos.z*9.0+pos.x*2.0);
	float macro=sin(pos.x*0.65)*cos(pos.z*0.53);
	ALBEDO=base.rgb*(0.95+0.07*brush+0.09*macro);
	ROUGHNESS=1.0;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("base", color)
	return m

func triangles(points: PackedVector3Array, material: Material, solid: bool = true) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in points:
		st.add_vertex(p)
	st.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = material
	add_child(instance)
	if solid:
		instance.create_trimesh_collision()
	return instance

func platform(label: String, polygon: PackedVector2Array, height: float) -> void:
	var indices := Geometry2D.triangulate_polygon(polygon)
	var top := PackedVector3Array()
	for index in indices:
		var p := polygon[index]
		top.append(Vector3(p.x, height, p.y))
	var ground := triangles(top, paint(Color("#536049"), true))
	ground.name = label
	var sides := PackedVector3Array()
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		sides.append_array(PackedVector3Array([
			Vector3(a.x,height,a.y), Vector3(a.x,-2,a.y), Vector3(b.x,-2,b.y),
			Vector3(a.x,height,a.y), Vector3(b.x,-2,b.y), Vector3(b.x,height,b.y)]))
		# Tall irregular rock ribs, strictly outside walkable top.
		var n := int(a.distance_to(b) / 0.7)
		for j in range(n):
			var p := a.lerp(b, (float(j) + 0.5) / maxf(n, 1))
			box(Vector3(p.x, (height-2)*0.5-0.15, p.y),
				Vector3(0.45, height+1.6, 0.4), paint(Color("#44364f").lightened(rng.randf()*0.12)), false)
	triangles(sides, paint(Color("#44384d"), true))
	# A narrow grassy lip delineates the cliff, but has no blocking collision.
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		beam(Vector3(a.x,height+0.015,a.y), Vector3(b.x,height+0.015,b.y), 0.08, Color("#75805a"), false)

func rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0,z0),Vector2(x1,z0),Vector2(x1,z1),Vector2(x0,z1)])

func terrain_setup() -> void:
	platform("CentralCourtyard", PackedVector2Array([
		Vector2(-10,-2),Vector2(7,-2),Vector2(8,1),Vector2(8,9),
		Vector2(5,11),Vector2(-4,11),Vector2(-10,8)]), 0)
	# Notch for the stairs; the remainder of the cliff directly borders the court.
	platform("RearTerrace", PackedVector2Array([
		Vector2(-7,-11),Vector2(10,-11),Vector2(10,-2),
		Vector2(-0.6,-2),Vector2(-0.6,-6),Vector2(-3.4,-6),
		Vector2(-3.4,-2),Vector2(-7,-2)]), STEP_HEIGHT)
	platform("LeftBridgeLanding", rect(-15,-11,-10,-6), STEP_HEIGHT)
	platform("FarRiverBank", rect(12,-1,15,11), 0)
	staircase()
	bridge(Vector3(-8.5,STEP_HEIGHT,-8), 3.4, 2.1, "UpperLeftBridge")
	bridge(Vector3(10,0,7), 4.4, 2.2, "LowerRightBridge")
	water_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 p;
void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
	float rip=pow(0.5+0.5*sin(p.z*12.0+sin(p.x*6.0)-TIME*2.0),18.0);
	ALBEDO=mix(vec3(0.055,0.15,0.24),vec3(0.27,0.43,0.61),rip*0.6);
}
"""
	water_material.shader = shader
	water_surface(rect(8,-2,12,13), -1.2)
	water_surface(rect(-10,-13,-7,-6), 1.92)
	water_surface(rect(-10,-6,-7,-2), -1.2)
	waterfall(-8.5,-6,STEP_HEIGHT,-1.2,2.2)
	waterfall(9,-2,STEP_HEIGHT,-1.2,1.8)
	# River banks are real gaps, not blue quads hidden below solid ground.
	# Walk-off recovery is intentional for this non-swimming prototype.

func water_surface(polygon: PackedVector2Array, y: float) -> void:
	var vertices := PackedVector3Array()
	for i in Geometry2D.triangulate_polygon(polygon):
		vertices.append(Vector3(polygon[i].x,y,polygon[i].y))
	triangles(vertices, water_material, false)

func waterfall(x: float, z: float, high: float, low: float, width: float) -> void:
	var sheet := paint(Color("#7484c5"))
	triangles(PackedVector3Array([
		Vector3(x-width/2,high,z-0.02),Vector3(x-width/2,low,z+0.22),Vector3(x+width/2,low,z+0.22),
		Vector3(x-width/2,high,z-0.02),Vector3(x+width/2,low,z+0.22),Vector3(x+width/2,high,z-0.02)]),sheet,false)
	for i in 8:
		var xx := x-width/2+width*float(i)/8.0
		beam(Vector3(xx,high-0.15,z),Vector3(xx,low+0.15,z+0.24),0.035,Color("#afbbe6"),false)
	for i in 12:
		box(Vector3(x+rng.randf_range(-width/2,width/2),low+0.025,z+rng.randf_range(0,0.65)),
			Vector3(0.2,0.04,0.08),paint(Color("#b9c3e3")),false)

func staircase() -> void:
	# Visible 20cm treads; ONE continuous hidden wedge collision, no step snag.
	for i in 10:
		var h := STEP_HEIGHT * float(i+1)/10.0
		box(Vector3(-2,h-0.12,-2.2-float(i)*0.4), Vector3(2.8,0.24,0.41),
			paint(Color("#776879").lightened(float(i%3)*0.035)),false)
	var wedge := ConvexPolygonShape3D.new()
	wedge.points = PackedVector3Array([
		Vector3(-3.4,0,-2),Vector3(-0.6,0,-2),Vector3(-3.4,0,-6),Vector3(-0.6,0,-6),
		Vector3(-3.4,STEP_HEIGHT,-6),Vector3(-0.6,STEP_HEIGHT,-6)])
	var body := StaticBody3D.new()
	body.name = "StairRampCollision"
	var shape := CollisionShape3D.new()
	shape.shape = wedge
	body.add_child(shape)
	add_child(body)
	for x in [-3.6,-0.4]:
		beam(Vector3(x,0.65,-2),Vector3(x,2.65,-6),0.1,Color("#50352f"),true)

func bridge(center: Vector3, length: float, width: float, label: String) -> void:
	var deck := box(center-Vector3(0,0.1,0),Vector3(length,0.2,width),paint(Color("#473032")),true)
	deck.name = label
	for i in int(length/0.32):
		box(center+Vector3(-length/2+0.16+float(i)*0.32,0.018,0),
			Vector3(0.30,0.035,width),paint(Color("#80564c").darkened(rng.randf()*0.2)),false)
	for side in [-1,1]:
		var z := center.z+float(side)*width*0.5
		for i in 4:
			var x := center.x-length/2+float(i)*length/3
			box(Vector3(x,center.y+0.55,z),Vector3(0.17,1.1,0.17),paint(Color("#533830")),true)
		beam(Vector3(center.x-length/2,center.y+0.65,z),Vector3(center.x+length/2,center.y+0.65,z),0.085,Color("#9d7050"),true)

func box(pos: Vector3, size: Vector3, material: Material, solid: bool) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	add_child(instance)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		instance.add_child(body)
	return instance

func beam(a: Vector3,b: Vector3,radius: float,color: Color,solid: bool) -> void:
	var stick := box((a+b)*0.5,Vector3(radius,radius,a.distance_to(b)),paint(color),solid)
	stick.look_at(b)

func art(file: String, foot: Vector3, height: float, obstacle: Vector3 = Vector3.ZERO) -> void:
	var texture: Texture2D = load(ART+file+".png")
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.pixel_size = height / float(texture.get_height())
	# Images include bottom padding; anchor visible bottom rather than image center.
	sprite.position = foot + camera.global_basis.y * height * 0.41
	sprite.basis = camera.global_basis
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.no_depth_test = false
	sprite.shaded = false
	decoration.add_child(sprite)
	if obstacle != Vector3.ZERO:
		var collider := box(foot+Vector3(0,obstacle.y/2,0),obstacle,paint(Color("#282230")),true)
		collider.visible = false

func landmarks() -> void:
	# Central shrine, rear tent and two landmark trees reflect the image layout.
	art("camp_shrine",Vector3(0,0,1),4.6,Vector3(2.5,2,1.6))
	art("camp_tent",Vector3(4,2,-9),4.3,Vector3(3,2.8,2))
	art("test_tree",Vector3(-8,0,0),6.0,Vector3(0.9,3,0.9))
	art("test_tree",Vector3(8,2,-9),6.0,Vector3(0.9,3,0.9))
	for p in [Vector3(-5,0,3),Vector3(3,0,2),Vector3(-5,2,-6.4),Vector3(9,2,-3.5)]:
		art("camp_banner",p,2.7,Vector3(0.2,2,0.2))
	for p in [Vector3(-11.5,2,-8.8),Vector3(-6,2,-8.8),Vector3(7.8,0,8.5),Vector3(12.5,0,8.5)]:
		art("camp_lantern",p,2.5)
		warm_light(p+Vector3(0,1.5,0))
	warm_light(Vector3(0,1.5,2))
	warm_light(Vector3(4,3,-8))
	# Paths are shallow top overlays, never obstacles.
	for z in range(4,11):
		box(Vector3(0,0.008,z),Vector3(3.5,0.01,1.05),paint(Color("#80604f"),true),false)
	for i in 18:
		var angle := TAU*float(i)/18
		var pos := Vector3(cos(angle)*3.4,0,sin(angle)*2.8+1)
		if pos.z < -1.2 or pos.z > 3.5:
			continue
		art("test_bush",pos,1.6)
	# Seeded perimeter vegetation leaves the circulation route unobstructed.
	for i in 50:
		var x := rng.randf_range(-9,7)
		var z := rng.randf_range(-1.5,10)
		if absf(x)<5 and z<8:
			continue
		art("camp_reeds" if i%3==0 else "test_bush",Vector3(x,0,z),rng.randf_range(1.1,2.0))
	for i in 25:
		var x := rng.randf_range(-6.5,9.5)
		var z := rng.randf_range(-10.8,-10)
		art("test_bush",Vector3(x,2,z),rng.randf_range(1.4,2.3))
	# Stepping stones and flowers provide scale without changing collision.
	for i in 65:
		var x := rng.randf_range(-7,6)
		var z := rng.randf_range(-1.6,9)
		box(Vector3(x,0.028,z),Vector3(rng.randf_range(0.1,0.4),0.04,0.15),
			paint(Color("#9f8a83") if i%4 else Color("#cca385")),false)

func warm_light(pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = Color("#ff9f57")
	light.light_energy = 2.5
	light.omni_range = 5
	add_child(light)

func player_setup() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = SPAWN
	player.floor_snap_length = 0.35
	player.floor_max_angle = deg_to_rad(48)
	add_child(player)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.6
	capsule.radius = 0.32
	shape.shape = capsule
	player.add_child(shape)
	var visible_body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.height = 1.6
	mesh.radius = 0.32
	visible_body.mesh = mesh
	visible_body.material_override = paint(Color("#ffcc7c"))
	player.add_child(visible_body)

func ui_setup() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18,18)
	layer.add_child(panel)
	status = Label.new()
	# Use Godot/macOS font fallback; the previous local ArialUnicode copy is not redistributed.
	status.add_theme_font_size_override("font_size",17)
	panel.add_child(status)

func _physics_process(delta: float) -> void:
	elapsed += delta
	var axis := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	var forward := camera.global_basis.z
	forward.y = 0
	var right := camera.global_basis.x
	right.y = 0
	var direction := (right.normalized()*axis.x+forward.normalized()*axis.y).limit_length()
	if testing:
		direction = test_direction
	player.velocity.x = direction.x*4.2
	player.velocity.z = direction.z*4.2
	if player.is_on_floor():
		player.velocity.y = -0.1
	else:
		player.velocity.y -= 20*delta
	player.move_and_slide()
	if player.position.y < -4 or Input.is_physical_key_pressed(KEY_R):
		player.position = SPAWN
		player.velocity = Vector3.ZERO
	decoration.visible = not Input.is_physical_key_pressed(KEY_TAB)
	status.text = "  林间营地 · 地形重建  \n  WASD / 方向键移动 · R 重置 · 按住 Tab 看地形  \n  脚下高度 %.2fm · 中央石阶通往 +2m 后台  " % (player.position.y-0.8)

func capture() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/private/tmp/forest_camp.png")

func run_checks() -> void:
	await get_tree().physics_frame
	var failures: Array[String] = []
	# Use actual CharacterBody movement, not teleport-only surface checks.
	for spec in [
		["stairs_up",Vector3(-2,0.85,-1),Vector3(0,0,-1),100,2.0],
		["stairs_down",Vector3(-2,2.85,-7),Vector3(0,0,1),100,0.0],
		["left_bridge",Vector3(-11,2.85,-8),Vector3(1,0,0),75,2.0],
		["right_bridge",Vector3(7,0.85,7),Vector3(1,0,0),100,0.0]]:
		player.position = spec[1]
		player.velocity = Vector3.ZERO
		test_direction = spec[2]
		for frame in spec[3]:
			await get_tree().physics_frame
		var foot := player.position.y-0.8
		var distance := Vector2(player.position.x-spec[1].x,player.position.z-spec[1].z).length()
		var passed := absf(foot-float(spec[4]))<0.2 and distance>4.0
		print("CHECK ",spec[0]," ",passed," foot=",foot," distance=",distance)
		if not passed:
			failures.append(spec[0])
	test_direction = Vector3.ZERO
	player.position = Vector3(3,0.85,-1)
	player.velocity = Vector3.ZERO
	test_direction = Vector3(0,0,-1)
	for frame in 100:
		await get_tree().physics_frame
	var blocked := player.position.z > -5.8 and player.position.y < 1.1
	print("CHECK cliff_wall ",blocked)
	if not blocked:
		failures.append("cliff_wall")
	print("CAMP TEST FAILURES: ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
