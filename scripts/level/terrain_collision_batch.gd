@tool
extends RefCounted

## Bodies are shared within one chunk and support layer. Each shape retains
## its original cell, so physical ray queries still identify the exact support.
var parent: Node3D
var bodies := {}

func _init(target: Node3D) -> void:
	parent = target

func add_shape(cell: Vector2i, layer: int, shape: Shape3D,
		xform := Transform3D.IDENTITY, slice_cap := false) -> void:
	var body: StaticBody3D = bodies.get(layer)
	if body == null:
		body = StaticBody3D.new()
		body.name = "TerrainCollision_%d_%d_%d" % [cell.x, layer, cell.y]
		body.set_meta("terrain_collision_batch", true)
		body.set_meta("terrain_layer", layer)
		body.set_meta("slice_cap", slice_cap)
		parent.add_child(body)
		bodies[layer] = body
	var node := CollisionShape3D.new()
	node.name = "Cell_%d_%d_%d" % [cell.x, cell.y, body.get_child_count()]
	node.shape = shape
	node.transform = xform
	node.set_meta("terrain_cell", cell)
	node.set_meta("terrain_layer", layer)
	node.set_meta("slice_cap", slice_cap)
	body.add_child(node)

static func hit_metadata(body: CollisionObject3D, shape_index: int) -> Dictionary:
	var owner_id := body.shape_find_owner(shape_index)
	var owner := body.shape_owner_get_owner(owner_id) as Node
	if owner == null or not owner.has_meta("terrain_cell"):
		return {}
	return {"cell": owner.get_meta("terrain_cell"), "layer": owner.get_meta("terrain_layer"),
		"slice_cap": owner.get_meta("slice_cap", false)}
