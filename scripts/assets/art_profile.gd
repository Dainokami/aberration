@tool
class_name ArtProfile
extends Resource

## Camera orientation is part of the art contract, not inferred from PNG pixels.
@export var camera_offset := Vector3(19, 22, 25)
@export var orthographic_size := 25.0
@export var version := 1

func camera_basis() -> Basis:
	return Basis.looking_at(-camera_offset.normalized(), Vector3.UP)
