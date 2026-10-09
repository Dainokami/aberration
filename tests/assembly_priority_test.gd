extends SceneTree


func _initialize() -> void:
	var assembly := CharacterAssemblyController.new()
	root.add_child(assembly)
	assembly.set_process_unhandled_input(false)

	assembly.arm_count = 0
	assembly.lower_body = CharacterAssemblyController.LowerBody.NONE
	_assert_equal(assembly.resolve_locomotion(), CharacterAssemblyController.LocomotionMode.HEAD_ROLL, "head fallback")

	assembly.arm_count = 1
	_assert_equal(assembly.resolve_locomotion(), CharacterAssemblyController.LocomotionMode.SINGLE_ARM_HOP, "single arm")

	assembly.arm_count = 2
	_assert_equal(assembly.resolve_locomotion(), CharacterAssemblyController.LocomotionMode.DOUBLE_ARM_WALK, "double arm")

	assembly.lower_body = CharacterAssemblyController.LowerBody.BIPED
	_assert_equal(assembly.resolve_locomotion(), CharacterAssemblyController.LocomotionMode.BIPED_WALK, "biped overrides arms")

	assembly.lower_body = CharacterAssemblyController.LowerBody.QUADRUPED
	_assert_equal(assembly.resolve_locomotion(), CharacterAssemblyController.LocomotionMode.QUADRUPED_WALK, "quadruped overrides arms")

	assembly.lower_body = CharacterAssemblyController.LowerBody.SNAKE
	_assert_equal(assembly.resolve_locomotion(), CharacterAssemblyController.LocomotionMode.SNAKE_SLITHER, "snake overrides arms")
	_assert_true(assembly.get_acceleration_multiplier() < 1.0, "snake has low acceleration and sliding inertia")
	assembly.lower_body = CharacterAssemblyController.LowerBody.NONE
	assembly.arm_count = 0
	_assert_equal(assembly.get_collision_height(), 1.02, "head roll collision height")
	assembly.lower_body = CharacterAssemblyController.LowerBody.BIPED
	_assert_equal(assembly.get_collision_height(), 2.12, "biped collision height")
	var mode_before_wings := assembly.resolve_locomotion()
	assembly.wings_equipped = true
	_assert_equal(assembly.resolve_locomotion(), mode_before_wings, "wings do not replace ground locomotion")

	var arm_locomotion := CharacterAssemblyController.new()
	root.add_child(arm_locomotion)
	arm_locomotion.set_process_unhandled_input(false)
	arm_locomotion.arm_count = 1
	arm_locomotion.lower_body = CharacterAssemblyController.LowerBody.NONE
	arm_locomotion.request_attack()
	_assert_true(arm_locomotion.is_movement_locked(), "arm locomotion attack must lock movement")

	var leg_locomotion := CharacterAssemblyController.new()
	root.add_child(leg_locomotion)
	leg_locomotion.set_process_unhandled_input(false)
	leg_locomotion.arm_count = 2
	leg_locomotion.lower_body = CharacterAssemblyController.LowerBody.BIPED
	leg_locomotion.request_attack()
	_assert_true(not leg_locomotion.is_movement_locked(), "free arms may attack while legs move")

	var file := FileAccess.open("res://tests/.assembly_result.txt", FileAccess.WRITE)
	if file:
		file.store_line("PASS: locomotion priority and attack limb arbitration")
	print("ASSEMBLY_PRIORITY_TEST: PASS")
	quit(0)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		push_error("ASSEMBLY_PRIORITY_TEST: %s expected %s, got %s" % [label, expected, actual])
		quit(1)


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		push_error("ASSEMBLY_PRIORITY_TEST: " + label)
		quit(1)
