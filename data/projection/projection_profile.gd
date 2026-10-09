class_name ProjectionProfile
extends Resource

@export var camera_position := Vector3(14.0, 16.0, 20.0)
@export var camera_target := Vector3(0.0, 1.8, -0.5)
@export_range(4.0, 40.0, 0.1) var orthographic_size := 17.0
@export var design_resolution := Vector2i(1280, 720)
@export_range(0.5, 8.0, 0.5) var cell_size := 2.0
@export_range(0.5, 8.0, 0.5) var elevation_step := 2.0
