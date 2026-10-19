class_name LevelTransitionHUD
extends Control

var countdown_label: Label

func setup(controller: LevelTransitionController, font: Font) -> void:
	name = "LevelTransitionHUD"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	countdown_label = Label.new()
	countdown_label.name = "PortalCountdown"
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_override("font", font)
	countdown_label.add_theme_font_size_override("font_size", 24)
	countdown_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	countdown_label.add_theme_constant_override("shadow_offset_x", 2)
	countdown_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(countdown_label)
	countdown_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	countdown_label.offset_top = 12
	countdown_label.offset_bottom = 48
	controller.status_changed.connect(_update_status)
	_update_status(controller.remaining, controller.state)

func _update_status(remaining: float, state: int) -> void:
	visible = state != LevelTransitionController.State.DISABLED
	match state:
		LevelTransitionController.State.COUNTDOWN:
			var seconds := ceili(remaining)
			countdown_label.text = "传送门开启倒计时 %02d:%02d" % [seconds / 60, seconds % 60]
		LevelTransitionController.State.WAITING:
			countdown_label.text = "00:00 · 正在寻找传送门位置"
		LevelTransitionController.State.OPEN:
			countdown_label.text = "传送门已开启 · 靠近后按 E 进入下一关"
		LevelTransitionController.State.TRANSITIONING:
			countdown_label.text = "正在进入下一关…"
		LevelTransitionController.State.STOPPED:
			countdown_label.text = "传送已停止 · 重新试玩开启新一轮"
