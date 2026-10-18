class_name ContractingFog
extends Node3D

var center := Vector3.ZERO
var radius := 30.0
var final_radius := 30.0
var speed := 3.0
var player_damage := 5.0
var monster_damage := 100.0
var player: Node3D
var active := false
var material: ShaderMaterial

func setup(data: LevelData, gate_position: Vector3, config: EncounterConfig, actor: Node3D) -> void:
	center = gate_position
	final_radius = config.safe_radius
	speed = config.fog_speed
	player_damage = config.fog_player_damage
	monster_damage = config.fog_monster_damage
	player = actor
	var origin := data.map_world_origin()
	var size := Vector2(data.map_size) * LevelData.CELL_SIZE
	radius = final_radius
	for corner in [origin, origin + Vector2(size.x, 0), origin + size, origin + Vector2(0, size.y)]:
		radius = maxf(radius, corner.distance_to(Vector2(center.x, center.z)))
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	mesh.mesh = quad
	# The shader covers the screen; avoid frustum culling of the local quad.
	mesh.custom_aabb = AABB(Vector3.ONE * -10000, Vector3.ONE * 20000)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec2 center;
uniform float radius;
void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz / view.w, 1.0)).xyz;
	float distance_to_gate = distance(world.xz, center);
	float edge = smoothstep(radius, radius + 0.7, distance_to_gate);
	float mist = 0.78 + 0.12 * sin(world.x * 0.6 + TIME) * cos(world.z * 0.5 - TIME);
	ALBEDO = vec3(0.28, 0.30, 0.38);
	ALPHA = edge * mist * step(0.00001, depth);
}
"""
	material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("center", Vector2(center.x, center.z))
	material.set_shader_parameter("radius", radius)
	mesh.material_override = material
	add_child(mesh)
	active = true

func covered(point: Vector3) -> bool:
	return Vector2(point.x - center.x, point.z - center.z).length() > radius

func step(delta: float) -> void:
	if not active:
		return
	radius = maxf(final_radius, radius - speed * delta)
	if material != null:
		material.set_shader_parameter("radius", radius)
	if is_instance_valid(player) and covered(player.global_position):
		CombatHealth.hurt(player, player_damage * delta, "fog")
	for actor in get_tree().get_nodes_in_group("enemies"):
		if actor is Node3D and covered(actor.global_position):
			CombatHealth.hurt(actor, monster_damage * delta, "fog")
