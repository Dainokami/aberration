@tool
class_name ColorGradeProfile
extends Resource

## Scene-wide finishing pass. Terrain source art and base colors remain neutral.
@export var enabled := false
@export_range(0.25, 4.0, 0.01) var brightness := 1.0
@export_range(0.25, 4.0, 0.01) var contrast := 1.0
@export_range(0.0, 4.0, 0.01) var saturation := 1.0
@export var color_correction: Texture3D

func apply(environment: Environment) -> void:
	environment.adjustment_enabled = enabled
	environment.adjustment_brightness = brightness
	environment.adjustment_contrast = contrast
	environment.adjustment_saturation = saturation
	environment.adjustment_color_correction = color_correction
