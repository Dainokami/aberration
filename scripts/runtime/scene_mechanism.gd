@tool
class_name SceneMechanism
extends GameplayProp

var level_data: LevelData
var collected := false
var _damage_clock := 0.0
var _fruit_ready := true

func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		set_physics_process(false)
		return
	super._ready()
	add_to_group("scene_mechanisms")
	if definition.mechanism == "vine":
		add_to_group("climb_surfaces")

func interaction_text() -> String:
	if collected:
		return ""
	match definition.mechanism:
		"remains", "resource":
			return "E / G 拾取"
		"fruit_tree":
			return "E / G 摇树"
		"vine":
			return "E 攀爬 · Space 跳离"
		"chest":
			return "E / G 打开宝箱" if state == "closed" else "已打开"
	return ""

func interact(actor: Node3D) -> bool:
	if Engine.is_editor_hint() or collected or actor == null:
		return false
	match definition.mechanism:
		"remains", "resource":
			if not store_item(actor, definition.mechanism):
				notify(actor, "背包已满，无法拾取")
				return false
			collected = true
			visible = false
			for shape in find_children("*", "CollisionShape3D", true, false):
				shape.set_deferred("disabled", true)
			notify(actor, "已拾取")
			return true
		"chest":
			if state != "closed":
				return false
			set_state("open")
			var lid := get_node_or_null("ChestLid") as Node3D
			if lid != null:
				var initial := lid.rotation.x
				create_tween().tween_property(lid, "rotation:x", initial - 1.0, 0.35)
			drop_items("treasure", 3)
			opened.emit(self, actor)
			return true
		"fruit_tree":
			if not _fruit_ready:
				return false
			_fruit_ready = false
			shake()
			drop_items("food", 2)
			reveal_vine()
			return true
	return false

static func store_item(actor: Node3D, item: String) -> bool:
	var inventory: Array = actor.get_meta("scene_inventory", [])
	var capacity := int(actor.get_meta("scene_inventory_capacity", 20))
	if inventory.size() >= capacity:
		return false
	inventory = inventory.duplicate()
	inventory.append(item)
	actor.set_meta("scene_inventory", inventory)
	return true

static func notify(actor: Node3D, text: String) -> void:
	actor.set_meta("scene_feedback", text)
	var parts := actor.get_node_or_null("PartLoadout")
	if parts != null:
		parts.note.emit(text)

func shake() -> void:
	var art := get_node_or_null("Art") as Node3D
	if art == null:
		return
	var tween := create_tween()
	tween.tween_property(art, "rotation:z", -0.10, 0.08)
	tween.tween_property(art, "rotation:z", 0.10, 0.12)
	tween.tween_property(art, "rotation:z", 0.0, 0.12)

func drop_items(item: String, count: int) -> void:
	for index in count:
		var pickup := RigidBody3D.new()
		pickup.set_script(load("res://scripts/runtime/scene_pickup.gd"))
		pickup.set("item_id", item)
		pickup.name = "Dropped_" + item
		pickup.collision_layer = 8
		pickup.collision_mask = 1
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.14
		shape.shape = sphere
		pickup.add_child(shape)
		var visual := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.14
		mesh.height = 0.28
		visual.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#da8352") if item == "food" else Color("#edcf71")
		visual.material_override = material
		pickup.add_child(visual)
		get_parent().add_child(pickup)
		pickup.global_position = global_position + Vector3.UP * 1.0
		var angle := TAU * index / count
		pickup.linear_velocity = Vector3(cos(angle) * 2.5, 4.0, sin(angle) * 2.5)

func reveal_vine() -> void:
	if level_data == null or has_meta("vine_revealed"):
		return
	var cell := level_data.world_to_cell(position)
	var layer := level_data.layer_at_surface(position)
	for direction in 4:
		if level_data.has_terrain_volume(cell + LevelData.DIRS[direction], layer):
			continue
		var path := "res://assets/generated/scene1016_vine_1x1/definition.tres"
		if not ResourceLoader.exists(path):
			return
		var vine := AssetFactory.instantiate_asset(load(path))
		if vine is SceneMechanism:
			vine.level_data = level_data
		get_parent().add_child(vine)
		vine.global_position = global_position + ObjectRules.wall_normal(direction) \
			* LevelData.CELL_SIZE * 0.5 - Vector3.UP * LevelData.ELEVATION_STEP
		vine.rotation.y = atan2(ObjectRules.wall_normal(direction).x, ObjectRules.wall_normal(direction).z)
		var marker := AffordanceProp.new()
		marker.configure_host(vine, "climbable", 1)
		marker.ledge_height = global_position.y
		marker.ledge_point = global_position + Vector3.UP * 0.08
		get_parent().add_child(marker)
		marker.global_position = vine.global_position
		set_meta("vine_revealed", true)
		return

func clip_bubbles(surface_y: float) -> void:
	if definition.mechanism != "bubbles":
		return
	for node in find_children("*", "MeshInstance3D", true, false):
		var material := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D art : source_color;
uniform float surface_y;
varying float world_y;
void vertex() { world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y; }
void fragment() {
	vec4 pixel = texture(art, UV);
	if (world_y > surface_y || pixel.a < 0.15) { discard; }
	ALBEDO = pixel.rgb;
}
"""
		material.shader = shader
		material.set_shader_parameter("art", load(definition.source_image))
		material.set_shader_parameter("surface_y", surface_y)
		node.material_override = material

func covers(point: Vector3) -> bool:
	if collected or not is_inside_tree():
		return false
	var local := to_local(point)
	for offset in definition.spatial_cells:
		var relative: Vector3 = local - offset
		if absf(relative.x) <= definition.cell_size.x * 0.5 \
				and absf(relative.z) <= definition.cell_size.z * 0.5 \
				and relative.y >= -0.05 and relative.y <= definition.cell_size.y:
			return true
	return false

static func effects_at(point: Vector3) -> Dictionary:
	var result := {"speed_multiplier": 1.0, "drift": Vector3.ZERO, "oxygen": 0.0}
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return result
	for node in tree.get_nodes_in_group("scene_mechanisms"):
		if not node is SceneMechanism or not node.covers(point):
			continue
		var parameters: Dictionary = node.definition.mechanism_parameters
		match node.definition.mechanism:
			"thorns":
				result.speed_multiplier = minf(result.speed_multiplier,
					float(parameters.get("speed_multiplier", 0.5)))
			"quicksand":
				var toward: Vector3 = node.global_position - point
				toward.y = 0
				result.drift += toward.normalized() * minf(toward.length(),
					float(parameters.get("pull_speed_mps", 1.0)))
			"bubbles":
				if SceneProbe.tags_at(point).has("ocean"):
					result.drift += Vector3.UP * float(parameters.get("rise_speed_mps", 1.5))
					result.oxygen += float(parameters.get("oxygen_per_second", 10.0))
	return result

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or definition == null or definition.mechanism != "thorns":
		return
	_damage_clock += delta
	if _damage_clock < 1.0:
		return
	_damage_clock -= 1.0
	for group in ["player", "level_player", "enemies"]:
		for actor in get_tree().get_nodes_in_group(group):
			if not actor is Node3D or not covers(actor.global_position):
				continue
			var damage := float(definition.mechanism_parameters.get("damage_per_second", 1.0))
			if actor.has_method("take_damage"):
				actor.take_damage(damage)
			else:
				actor.set_meta("scene_health", float(actor.get_meta("scene_health", 100.0)) - damage)
