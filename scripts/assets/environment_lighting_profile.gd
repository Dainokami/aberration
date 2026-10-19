@tool
class_name EnvironmentLightingProfile
extends Resource

## Lighting changes the runtime presentation; source art and map tints stay intact.
@export var ambient_color := Color("#d4deec")
@export_range(0.0, 2.0, 0.01) var ambient_energy := 0.62
@export var sun_color := Color("#fff0d8")
@export_range(0.0, 2.0, 0.01) var sun_energy := 0.78
@export var sun_rotation_degrees := Vector3(-55, 135, 0)
@export_range(0.0, 5.0, 0.05) var sun_angular_distance := 1.0
@export_range(16.0, 120.0, 1.0) var shadow_distance := 80.0
@export_range(0.0, 1.0, 0.01) var shadow_opacity := 0.85
@export_range(0.0, 0.2, 0.001) var shadow_bias := 0.02
@export_range(0.0, 2.0, 0.01) var shadow_normal_bias := 0.35
@export var contact_occlusion := true
@export_range(0.1, 4.0, 0.05) var occlusion_radius := 1.0
@export_range(0.0, 3.0, 0.05) var occlusion_intensity := 0.8

func apply_environment(environment: Environment) -> void:
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = ambient_color
	environment.ambient_light_energy = ambient_energy
	environment.ssao_enabled = contact_occlusion
	environment.ssao_radius = occlusion_radius
	environment.ssao_intensity = occlusion_intensity
	environment.ssao_light_affect = 0.2
	environment.ssao_detail = 0.3

func apply_sun(sun: DirectionalLight3D) -> void:
	sun.rotation_degrees = sun_rotation_degrees
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.light_angular_distance = sun_angular_distance
	sun.light_specular = 0.0
	sun.shadow_enabled = true
	sun.shadow_opacity = shadow_opacity
	sun.shadow_bias = shadow_bias
	sun.shadow_normal_bias = shadow_normal_bias
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = shadow_distance
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_split_1 = 0.15
	sun.directional_shadow_split_2 = 0.35
	sun.directional_shadow_split_3 = 0.65
	sun.directional_shadow_fade_start = 0.85
