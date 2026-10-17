@tool
class_name TerrainStyleProfile
extends Resource

@export var irregular_mask_directory := "res://assets/source_art/terrain_handoff_v02/masks/irregular"
@export var irregular_seed := 20261012
@export var use_soft_rims := true
@export var use_shore_foam := true
@export_range(8, 64, 1) var blend_pixels_per_cell := 24
@export_range(2, 12, 1) var corner_segments := 5
@export_range(2, 12, 1) var rim_segments := 6
@export var top_surface_offset_m := 0.006
@export var rim_surface_offset_m := 0.012
@export var foam_surface_offset_m := 0.008

func irregular_mask_path(kind: String, canonical_bits: int, variant: int) -> String:
	return irregular_mask_directory.path_join(
		"%s_blob_%03d_v%d.png" % [kind, canonical_bits, variant])
