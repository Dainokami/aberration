extends CanvasLayer

const LAYOUT_PATH := "res://art/ui/hud/layout.json"
const ART := "res://art/ui/hud/"

var _stage: Control
var _player: PlayerController
var _hearts: Array[TextureRect] = []
var _bar_fill: ColorRect
var _bar_width := 1.0
var _slot_icons: Array[TextureRect] = []
var _pause: Control
var _knobs: Array[ColorRect] = []
var _slider_drag := -1
var _shown_health := -1
var _shown_upper := ""
var _shown_lower := ""
var notice_origin := Vector2(1460, 40)
var notice_size := Vector2(420, 220)


func setup(player: PlayerController) -> void:
	_player = player


func _ready() -> void:
	layer = 12
	var backdrop := Control.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(_stage)
	_build()
	_fit()
	get_viewport().size_changed.connect(_fit)


func is_pause_open() -> bool:
	return _pause != null and _pause.visible


func close_pause() -> void:
	if _pause != null:
		_pause.visible = false
	_slider_drag = -1


func open_pause() -> void:
	if _pause != null:
		_pause.visible = true


func take_prompts(interaction: Label, feedback: Label) -> void:
	if _stage == null:
		return
	for prompt in [interaction, feedback]:
		if prompt == null:
			continue
		prompt.reparent(_stage)
		prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		prompt.add_theme_font_size_override("font_size", 28)
		prompt.add_theme_color_override("font_color", Color(0.2, 0.14, 0.12))
	if interaction != null:
		interaction.position = notice_origin + Vector2(28, 28)
		interaction.size = Vector2(notice_size.x - 56, 80)
		interaction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if feedback != null:
		feedback.position = notice_origin + Vector2(28, 120)
		feedback.size = Vector2(notice_size.x - 56, 70)
		feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _process(_delta: float) -> void:
	if _player == null:
		return
	if _player.health != _shown_health:
		_shown_health = _player.health
		_refresh_health()
	var bag := _player.get_node_or_null("LimbBag") as LimbBag
	if bag == null:
		return
	if bag.equipped_upper != _shown_upper or bag.equipped_lower != _shown_lower:
		_shown_upper = bag.equipped_upper
		_shown_lower = bag.equipped_lower
		_refresh_slots()


func _build() -> void:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if not parsed is Dictionary:
		return
	var layout: Dictionary = parsed
	for key in ["portrait_frame", "portrait", "bar_track", "bar_cap", "notice", "notice_corners"]:
		_place(layout, key)
	if layout.has("notice"):
		var notice: Dictionary = layout["notice"]
		notice_origin = Vector2(float(notice["x"]), float(notice["y"]))
		notice_size = Vector2(float(notice["w"]), float(notice["h"]))
	_build_hearts(layout)
	_build_bar(layout)
	_build_slots(layout)
	_build_side(layout)
	_build_pause(layout)


func _build_hearts(layout: Dictionary) -> void:
	if not layout.has("hearts") or not layout.has("heart"):
		return
	var strip: Dictionary = layout["hearts"]
	var heart: Dictionary = layout["heart"]
	var texture := _texture("heart")
	var heart_w := float(heart["w"])
	var span := float(strip["w"])
	var step := heart_w if span <= heart_w else (span - heart_w) / 4.0
	for index in 5:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(float(strip["x"]) + step * float(index), float(strip["y"]))
		icon.size = Vector2(heart_w, float(heart["h"]))
		_stage.add_child(icon)
		_hearts.append(icon)


func _build_bar(layout: Dictionary) -> void:
	if not layout.has("bar_track"):
		return
	var track: Dictionary = layout["bar_track"]
	var inset := 10.0
	_bar_fill = ColorRect.new()
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_fill.color = Color(0.55, 0.84, 0.8, 0.92)
	_bar_width = maxf(float(track["w"]) - inset * 2.0, 1.0)
	if layout.has("bar_cap"):
		var cap_x := float(layout["bar_cap"]["x"])
		_bar_width = minf(_bar_width, cap_x - float(track["x"]) - inset)
	_bar_width = maxf(_bar_width, 1.0)
	_bar_fill.position = Vector2(float(track["x"]) + inset, float(track["y"]) + inset * 0.7)
	_bar_fill.size = Vector2(maxf(_bar_width, 1.0), maxf(float(track["h"]) - inset * 1.4, 1.0))
	_stage.add_child(_bar_fill)
	var cap := _stage.get_node_or_null("bar_cap")
	if cap != null:
		_stage.move_child(cap, -1)


func _build_slots(layout: Dictionary) -> void:
	for index in 3:
		var key := "slot_%d" % index
		if not layout.has(key):
			continue
		var spec: Dictionary = layout[key]
		_place(layout, key)
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var pad := 18.0
		icon.position = Vector2(float(spec["x"]) + pad, float(spec["y"]) + pad)
		icon.size = Vector2(float(spec["w"]) - pad * 2.0, float(spec["h"]) - pad * 2.0)
		_stage.add_child(icon)
		_slot_icons.append(icon)
	_slot_icons.sort_custom(func(a: TextureRect, b: TextureRect) -> bool: return a.position.x < b.position.x)


func _build_side(layout: Dictionary) -> void:
	var keys: Array[String] = []
	for key in layout.keys():
		if str(key).begins_with("side_"):
			keys.append(str(key))
	keys.sort_custom(func(a: String, b: String) -> bool:
		return float(layout[a]["y"]) < float(layout[b]["y"])
	)
	for index in keys.size():
		var key := keys[index]
		var button := TextureButton.new()
		var spec: Dictionary = layout[key]
		button.texture_normal = _texture(key)
		button.position = Vector2(float(spec["x"]), float(spec["y"]))
		button.size = Vector2(float(spec["w"]), float(spec["h"]))
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		var midpoint := (float(layout[keys[0]]["y"]) + float(layout[keys[keys.size() - 1]]["y"])) * 0.5
		if float(spec["y"]) >= midpoint:
			button.pressed.connect(open_pause)
		_stage.add_child(button)


func _build_pause(layout: Dictionary) -> void:
	_pause = Control.new()
	_pause.name = "Pause"
	_pause.visible = false
	_pause.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause.size = Vector2(1920, 1080)
	_stage.add_child(_pause)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.02, 0.35)
	dim.size = Vector2(1920, 1080)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause.add_child(dim)
	for key in ["pause_panel", "sliders", "pause_buttons"]:
		if not layout.has(key):
			continue
		var art := _sprite(key)
		_pause.add_child(art)
	if layout.has("sliders"):
		_build_slider(layout["sliders"], 0)
		_build_slider(layout["sliders"], 1)
	if layout.has("pause_buttons"):
		var buttons: Dictionary = layout["pause_buttons"]
		_text_button(buttons, 0, "继续", close_pause)
		_text_button(buttons, 1, "按键", func() -> void:
			close_pause()
			var help := _key_help()
			if help != null:
				help.visible = true
		)


func _build_slider(spec: Dictionary, index: int) -> void:
	var area := Control.new()
	var width := float(spec["w"])
	var height := float(spec["h"]) * 0.42
	area.position = Vector2(float(spec["x"]), float(spec["y"]) + height * float(index) + 8.0)
	area.size = Vector2(width, height)
	area.gui_input.connect(_slider_input.bind(area, index))
	_pause.add_child(area)
	var knob := ColorRect.new()
	knob.color = Color(0.93, 0.9, 0.84)
	knob.size = Vector2(14, height * 0.55)
	knob.position = Vector2(width * 0.55, height * 0.22)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(knob)
	_knobs.append(knob)


func _slider_input(event: InputEvent, area: Control, index: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_slider_drag = index if (event as InputEventMouseButton).pressed else -1
		if (event as InputEventMouseButton).pressed:
			_set_slider(area, index, (event as InputEventMouseButton).position.x)
	elif event is InputEventMouseMotion and _slider_drag == index:
		_set_slider(area, index, (event as InputEventMouseMotion).position.x)


func _set_slider(area: Control, index: int, local_x: float) -> void:
	var ratio := clampf((local_x - 28.0) / maxf(area.size.x - 56.0, 1.0), 0.0, 1.0)
	if index < _knobs.size():
		_knobs[index].position.x = lerpf(20.0, area.size.x - 34.0, ratio)
	var volume := linear_to_db(lerpf(0.001, 1.0, ratio))
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, volume)


func _text_button(spec: Dictionary, index: int, caption: String, action: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.flat = true
	button.position = Vector2(float(spec["x"]), float(spec["y"]) + float(spec["h"]) * 0.5 * float(index))
	button.size = Vector2(float(spec["w"]), float(spec["h"]) * 0.48)
	button.add_theme_font_size_override("font_size", 32)
	button.add_theme_color_override("font_color", Color(0.96, 0.9, 0.84))
	button.add_theme_color_override("font_hover_color", Color(1, 0.97, 0.9))
	var font: Font = load("res://scripts/runtime/level_playtest.gd").runtime_font()
	if font != null:
		button.add_theme_font_override("font", font)
	button.pressed.connect(action)
	_pause.add_child(button)


func _refresh_health() -> void:
	var max_health := maxi(_player.max_health, 1)
	var ratio := clampf(float(_player.health) / float(max_health), 0.0, 1.0)
	if _bar_fill != null:
		_bar_fill.size.x = _bar_width * ratio
	var filled := int(ceil(ratio * 5.0))
	if ratio <= 0.0:
		filled = 0
	for index in _hearts.size():
		_hearts[index].modulate = Color(1, 1, 1, 1) if index < filled else Color(1, 1, 1, 0.22)


func _refresh_slots() -> void:
	var ids := [_shown_upper, _shown_lower, ""]
	for index in mini(_slot_icons.size(), ids.size()):
		var texture := LimbCatalog.texture_for(ids[index]) if not ids[index].is_empty() else null
		_slot_icons[index].texture = texture


func _place(layout: Dictionary, key: String) -> void:
	if not layout.has(key):
		return
	var art := _sprite(key)
	_stage.add_child(art)


func _sprite(key: String) -> TextureRect:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	var spec: Dictionary = (parsed as Dictionary)[key]
	var art := TextureRect.new()
	art.name = key
	art.texture = _texture(key)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.position = Vector2(float(spec["x"]), float(spec["y"]))
	art.size = Vector2(float(spec["w"]), float(spec["h"]))
	return art


func _texture(key: String) -> Texture2D:
	var path := ART + key + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _key_help() -> CanvasItem:
	var layer := get_parent().get_node_or_null("PlayUI")
	if layer == null:
		return null
	return layer.get_node_or_null("KeyHelp")


func _fit() -> void:
	if _stage == null:
		return
	var view := get_viewport().get_visible_rect().size
	if view.x < 1.0 or view.y < 1.0:
		return
	var fitted := minf(view.x / 1920.0, view.y / 1080.0)
	_stage.scale = Vector2(fitted, fitted)
	_stage.position = (view - Vector2(1920, 1080) * fitted) * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if _slider_drag < 0:
		return
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		_slider_drag = -1
