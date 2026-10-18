extends CanvasLayer

# 属性页是角色和四条已装配肢体，培养页是背包和五个培养皿。
# 骨骼图层盖在底板上；能拖的格子再盖在骨骼上。

const CANVAS := Vector2(3840.0, 2160.0)
const RecycleTable := preload("res://scripts/recycle_table.gd")
const Playtest := preload("res://scripts/runtime/level_playtest.gd")
const RECYCLE_BIN := preload("res://art/ui/inventory/recycle_bin.png")
const DISH_LOCK := preload("res://art/ui/inventory/dish_lock.png")
const TEXTURES := {
	"sheet": {
		"board": preload("res://art/ui/sheet/board.png"),
		"skeleton": preload("res://art/ui/sheet/skeleton.png"),
	},
	"inventory": {
		"board": preload("res://art/ui/inventory/board.png"),
		"skeleton": preload("res://art/ui/inventory/skeleton.png"),
	},
}
const HOTSPOTS := {
	"sheet": [
		{"box": Rect2(2890, 0, 250, 380), "page": "inventory", "tip": "培养皿"},
		{"box": Rect2(3140, 0, 300, 400), "page": "inventory", "tip": "培养皿"},
	],
	"inventory": [
		{"box": Rect2(0, 150, 420, 280), "page": "sheet", "tip": "回到背包"},
		{"box": Rect2(16, 8, 280, 58), "action": "close", "tip": "回到主界面"},
	],
}
const SHEET_SOCKETS := [
	{"title": "左上肢", "slot": "upper", "center": 689.0},
	{"title": "右上肢", "slot": "upper", "center": 1019.0},
	{"title": "左下肢", "slot": "lower", "center": 1361.0},
	{"title": "右下肢", "slot": "lower", "center": 1705.0},
]
const SHEET_EQUIP := [
	{"box": Rect2(476, 812, 268, 240), "slot": "upper"},
	{"box": Rect2(1828, 812, 264, 236), "slot": "upper"},
	{"box": Rect2(480, 1416, 264, 240), "slot": "lower"},
	{"box": Rect2(1832, 1416, 264, 240), "slot": "lower"},
]
const PAGE_EQUIP := [
	{"box": Rect2(52, 720, 236, 216), "slot": "upper"},
	{"box": Rect2(48, 1024, 236, 216), "slot": "upper"},
	{"box": Rect2(48, 1336, 236, 212), "slot": "lower"},
	{"box": Rect2(48, 1644, 236, 212), "slot": "lower"},
]
const GRID_COLUMNS := [779, 1065, 1358, 1654, 1953, 2241, 2539, 2836]
const GRID_WIDTHS := [236, 236, 236, 236, 233, 236, 236, 235]
const GRID_ROWS := [Rect2(0, 1428, 0, 210), Rect2(0, 1714, 0, 214)]
const DISH_BOXES := [
	Rect2(592, 340, 220, 528),
	Rect2(1136, 340, 232, 528),
	Rect2(1700, 340, 204, 528),
	Rect2(2240, 340, 220, 528),
	Rect2(2784, 340, 220, 528),
]

var _stage: Control
var _pages: Dictionary = {}
var _page := "sheet"
var _open := false
var _bag: LimbBag
var _bag_slots: Array[LimbSlot] = []
var _equip_slots: Array[LimbSlot] = []
var _socket_labels: Array[Label] = []
var _socket_icons: Array[TextureRect] = []
var _dish_sides: Array[LimbSlot] = []
var _dish_bars: Array[ColorRect] = []
var _dish_captions: Array[Label] = []
var _note: Label
var _hover: ColorRect
var _hover_label: Label


func _ready() -> void:
	_build()
	_bag = get_parent().get_node("Player/LimbBag") as LimbBag
	_bag.changed.connect(_refresh_items)
	_bag.note.connect(_show_note)
	var player := get_parent().get_node_or_null("Player") as PlayerController
	if player != null and player.parts != null:
		player.parts.changed_loadout.connect(_refresh_items)
	_refresh_items()
	get_viewport().size_changed.connect(_fit)
	_fit()


func _process(_delta: float) -> void:
	if not _open or _bag == null:
		return
	for index in _bag.dishes.size():
		var dish: Dictionary = _bag.dishes[index]
		var box: Rect2 = DISH_BOXES[index]
		var running := index < LimbBag.UNLOCKED_DISHES and not str(dish["a"]).is_empty() and not str(dish["b"]).is_empty()
		var bar := _dish_bars[index]
		var caption := _dish_captions[index]
		bar.visible = running
		caption.visible = running
		if not running:
			continue
		var ratio := clampf(float(dish["time"]) / LimbBag.CULTURE_SECONDS, 0.0, 1.0)
		var height := (box.size.y - 28.0) * ratio
		bar.position = box.position + Vector2(12.0, box.size.y - 14.0 - height)
		bar.size = Vector2(box.size.x - 24.0, height)
		caption.text = "正在合成\n%s" % _clock(LimbBag.CULTURE_SECONDS - float(dish["time"]))


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_TAB:
		_set_open(not _open)
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if key.keycode == KEY_ESCAPE:
		_set_open(false)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_1:
		_show_page("sheet")
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_2:
		_show_page("inventory")
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	var tree := get_tree()
	if _open and tree != null:
		tree.paused = false


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.04, 0.045, 0.05)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.size = CANVAS
	backdrop.add_child(_stage)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/ui/layout.json"))
	var pages: Dictionary = layout["pages"]
	for page_name: String in ["sheet", "inventory"]:
		var page := _make_page(page_name, pages[page_name])
		_stage.add_child(page)
		_pages[page_name] = page
	_note = _make_label(_stage, Rect2(640, 2048, 2560, 90), 48)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover = ColorRect.new()
	_hover.name = "Hover"
	_hover.visible = false
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.color = Color(0.08, 0.045, 0.04, 0.94)
	_hover.size = Vector2(620, 190)
	_hover.z_index = 40
	_stage.add_child(_hover)
	_hover_label = _make_label(_hover, Rect2(24, 16, 572, 158), 44)
	_show_page(_page)


func _make_page(page_name: String, spec: Dictionary) -> Control:
	var page := Control.new()
	page.name = page_name.capitalize()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.size = CANVAS
	var textures: Dictionary = TEXTURES[page_name]
	_add_art(page, textures["board"], _bounds(spec["board"]))
	_add_art(page, textures["skeleton"], _bounds(spec["skeleton"]))
	for hotspot: Dictionary in HOTSPOTS[page_name]:
		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.position = hotspot["box"].position
		button.size = hotspot["box"].size
		button.tooltip_text = str(hotspot.get("tip", ""))
		button.add_theme_font_override("font", Playtest.runtime_font())
		button.add_theme_font_size_override("font_size", 32)
		button.add_theme_color_override("font_color", Color(0.96, 0.9, 0.78))
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		if str(hotspot.get("action", "")) == "close":
			var plate := StyleBoxFlat.new()
			plate.bg_color = Color(0.16, 0.05, 0.05, 0.92)
			plate.set_corner_radius_all(10)
			plate.content_margin_left = 12
			plate.content_margin_right = 12
			button.add_theme_stylebox_override("normal", plate)
			button.add_theme_stylebox_override("hover", plate)
			button.add_theme_stylebox_override("pressed", plate)
			button.flat = false
			button.text = "回到主界面"
			button.pressed.connect(_set_open.bind(false))
		else:
			button.modulate = Color(1, 1, 1, 0)
			button.pressed.connect(_show_page.bind(str(hotspot["page"])))
		page.add_child(button)
	if page_name == "sheet":
		_build_sheet(page)
	else:
		_build_culture(page)
	return page


func _build_sheet(page: Control) -> void:
	for spec: Dictionary in SHEET_EQUIP:
		_equip_slots.append(_bind_equip(page, spec["box"], spec["slot"]))
	for spec: Dictionary in SHEET_SOCKETS:
		var center := float(spec["center"])
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(2590, center - 70.0)
		icon.size = Vector2(140, 140)
		page.add_child(icon)
		_socket_icons.append(icon)
		var label := _make_label(page, Rect2(2760, center - 110.0, 900, 240), 34)
		_socket_labels.append(label)


func _build_culture(page: Control) -> void:
	for spec: Dictionary in PAGE_EQUIP:
		_equip_slots.append(_bind_equip(page, spec["box"], spec["slot"]))
	for index in DISH_BOXES.size():
		var box: Rect2 = DISH_BOXES[index]
		var bar := ColorRect.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.color = Color(0.72, 0.08, 0.07, 0.94)
		bar.visible = false
		bar.z_index = 1
		page.add_child(bar)
		_dish_bars.append(bar)
		var top := _bind_dish(page, Rect2(box.position.x, box.position.y, box.size.x, box.size.y * 0.46), index)
		var bottom := _bind_dish(page, Rect2(box.position.x, box.position.y + box.size.y * 0.48, box.size.x, box.size.y * 0.42), index)
		top.z_index = 2
		bottom.z_index = 2
		if index >= LimbBag.UNLOCKED_DISHES:
			top.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dish_sides.append(top)
		_dish_sides.append(bottom)
		var caption := _make_label(page, Rect2(box.position.x + 4.0, box.position.y + 18.0, box.size.x - 8.0, 160.0), 34)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_constant_override("outline_size", 6)
		caption.add_theme_color_override("font_outline_color", Color(0.2, 0.02, 0.02))
		caption.visible = false
		caption.z_index = 5
		_dish_captions.append(caption)
	var locked: Rect2 = DISH_BOXES[LimbBag.UNLOCKED_DISHES]
	var lock := TextureRect.new()
	lock.texture = DISH_LOCK
	lock.mouse_filter = Control.MOUSE_FILTER_STOP
	lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lock.position = locked.position
	lock.size = locked.size
	lock.z_index = 6
	page.add_child(lock)
	for index in GRID_COLUMNS.size():
		for row in GRID_ROWS.size():
			var band: Rect2 = GRID_ROWS[row]
			var box := Rect2(GRID_COLUMNS[index], band.position.y, GRID_WIDTHS[index], band.size.y)
			_bag_slots.append(_bind_bag(page, box, row * GRID_COLUMNS.size() + index))
	_add_art(page, RECYCLE_BIN, Rect2(3432, 360, 408, 1400))
	var recycle := _add_slot(page, Rect2(3460, 860, 360, 820))
	recycle.item_dropped.connect(_drop_on_recycle)


func _bind_bag(page: Control, box: Rect2, index: int) -> LimbSlot:
	var slot := _add_slot(page, box)
	slot.set_meta("bag_index", index)
	slot.item_dropped.connect(_drop_on_bag.bind(index))
	slot.recycle_requested.connect(_recycle_from.bind(slot))
	return slot


func _bind_equip(page: Control, box: Rect2, slot_name: String) -> LimbSlot:
	var slot := _add_slot(page, box)
	slot.set_meta("equip_slot", slot_name)
	slot.item_dropped.connect(_drop_on_equip.bind(slot_name))
	slot.recycle_requested.connect(_recycle_from.bind(slot))
	return slot


func _bind_dish(page: Control, box: Rect2, dish_index: int) -> LimbSlot:
	var slot := _add_slot(page, box)
	slot.item_dropped.connect(_drop_on_dish.bind(dish_index))
	slot.recycle_requested.connect(_recycle_from.bind(slot))
	return slot


func _add_slot(page: Control, box: Rect2) -> LimbSlot:
	var slot := LimbSlot.new()
	slot.position = box.position
	slot.size = box.size
	page.add_child(slot)
	slot.mouse_entered.connect(_on_slot_hover.bind(slot))
	slot.mouse_exited.connect(_on_slot_unhover.bind(slot))
	return slot


func _refresh_items() -> void:
	if _bag == null:
		return
	for slot in _bag_slots:
		_show_bag_slot(slot)
	for slot in _equip_slots:
		var slot_name := str(slot.get_meta("equip_slot"))
		var equipped := _bag.equipped_upper if slot_name == "upper" else _bag.equipped_lower
		var worn := _worn_id(slot_name)
		# Z/X 产生的目录预览可以显示，但它不是背包实物，不能从装备框拖出。
		_show_limb(slot, worn, {"kind": "equip", "slot": slot_name, "id": equipped})
	for index in _bag.DISH_COUNT:
		var dish: Dictionary = _bag.dishes[index]
		_show_limb(_dish_sides[index * 2], str(dish["a"]), {"kind": "dish", "dish": index, "side": "a", "id": dish["a"]})
		_show_limb(_dish_sides[index * 2 + 1], str(dish["b"]), {"kind": "dish", "dish": index, "side": "b", "id": dish["b"]})
	for index in SHEET_SOCKETS.size():
		var spec: Dictionary = SHEET_SOCKETS[index]
		var limb_id := _worn_id(str(spec["slot"]))
		var limb := LimbCatalog.find(limb_id)
		_socket_labels[index].text = _socket_text(str(spec["title"]), limb_id)
		_socket_icons[index].texture = LimbCatalog.texture_for(limb_id) if limb != null else null
		_socket_icons[index].modulate = limb.tint if limb != null else Color.WHITE


func _worn_id(slot_name: String) -> String:
	var equipped := _bag.equipped_upper if slot_name == "upper" else _bag.equipped_lower
	if not equipped.is_empty():
		return equipped
	var player := get_parent().get_node_or_null("Player") as PlayerController
	if player == null or player.parts == null:
		return ""
	var part := player.parts.current_upper() if slot_name == "upper" else player.parts.current_lower()
	return part.id if part != null else ""


func _socket_text(title: String, limb_id: String) -> String:
	var limb := LimbCatalog.find(limb_id)
	var part := PartCatalog.find(limb_id)
	if limb == null or part == null:
		return "%s\n空" % title
	var lines := PackedStringArray()
	lines.append("%s  %s  %s" % [title, limb.display_name, part.rank_label()])
	lines.append(part.attack_text())
	var move := _move_line(part)
	if not move.is_empty():
		lines.append(move)
	if not part.blurb.is_empty():
		lines.append(part.blurb)
	return "\n".join(lines)


func _move_line(part: PartDefinition) -> String:
	var bits := PackedStringArray()
	if part.speed_band != PartDefinition.Band.NONE:
		bits.append("移速" + ["无", "慢", "中", "快"][part.speed_band])
	if part.jump_count > 0:
		bits.append("%d段跳" % part.jump_count)
	if part.burrow:
		bits.append("遁地")
	if not part.swim.is_empty():
		bits.append("游动")
	if not part.air_mode.is_empty():
		bits.append("空中")
	if part.can_stick:
		bits.append("吸附")
	return "  ".join(bits)


func _show_bag_slot(slot: LimbSlot) -> void:
	var index := int(slot.get_meta("bag_index"))
	_show_limb(slot, _bag.slots[index], {"kind": "bag", "index": index, "id": _bag.slots[index]})


func _show_limb(slot: LimbSlot, limb_id: String, data: Dictionary) -> void:
	slot.drag_data = data
	var limb := LimbCatalog.find(limb_id)
	slot.icon.texture = LimbCatalog.texture_for(limb_id) if limb else null
	slot.icon.modulate = limb.tint if limb else Color.WHITE
	if limb == null:
		slot.tooltip_text = ""
	else:
		slot.tooltip_text = "%s\n可回收为%d血液" % [limb.display_name, RecycleTable.amount(limb_id)]


func _drop_on_bag(data: Dictionary, index: int) -> void:
	match str(data.get("kind", "")):
		"bag":
			_bag.swap_slots(int(data["index"]), index)
		"equip":
			_bag.move_equip_to_bag(str(data["slot"]), index)
		"dish":
			_bag.move_dish_to_bag(int(data["dish"]), str(data["side"]), index)


func _drop_on_equip(data: Dictionary, slot_name: String) -> void:
	match str(data.get("kind", "")):
		"bag":
			_bag.move_bag_to_equip(int(data["index"]), slot_name)
		"dish":
			_bag.move_dish_to_equip(int(data["dish"]), str(data["side"]), slot_name)


func _drop_on_dish(data: Dictionary, dish_index: int) -> void:
	match str(data.get("kind", "")):
		"bag":
			_bag.move_bag_to_dish(int(data["index"]), dish_index)
		"equip":
			_bag.move_equip_to_dish(str(data["slot"]), dish_index)
		"dish":
			_bag.move_dish_to_dish(int(data["dish"]), str(data["side"]), dish_index)


func _drop_on_recycle(data: Dictionary) -> void:
	_recycle_data(data)


func _recycle_from(slot: LimbSlot) -> void:
	_recycle_data(slot.drag_data)


func _recycle_data(data: Dictionary) -> void:
	match str(data.get("kind", "")):
		"bag":
			_bag.recycle_bag(int(data["index"]))
		"equip":
			_bag.recycle_equip(str(data["slot"]))
		"dish":
			_bag.recycle_dish(int(data["dish"]), str(data["side"]))


func _show_note(message: String) -> void:
	if _note:
		_note.text = message


func _add_art(parent: Control, texture: Texture2D, bounds: Rect2) -> void:
	var art := TextureRect.new()
	art.texture = texture
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.position = bounds.position
	art.size = bounds.size
	parent.add_child(art)


func _make_label(parent: Control, box: Rect2, font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = box.position
	label.size = box.size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", Playtest.runtime_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.96, 0.9, 0.78))
	parent.add_child(label)
	return label


func _bounds(box: Array) -> Rect2:
	return Rect2(box[0], box[1], box[2] - box[0], box[3] - box[1])


func _show_page(page_name: String) -> void:
	_page = page_name
	if _hover != null:
		_hover.visible = false
	for name: String in _pages:
		(_pages[name] as Control).visible = name == page_name


func _on_slot_hover(slot: LimbSlot) -> void:
	if _hover == null:
		return
	var limb_id := str(slot.drag_data.get("id", ""))
	var limb := LimbCatalog.find(limb_id)
	if limb == null:
		_hover.visible = false
		return
	_hover_label.text = "%s\n可回收为%d血液" % [limb.display_name, RecycleTable.amount(limb_id)]
	var origin: Vector2 = _stage.get_global_transform().affine_inverse() * slot.global_position
	var place := origin + Vector2(slot.size.x + 16.0, 8.0)
	if place.x + _hover.size.x > CANVAS.x - 24.0:
		place.x = origin.x - _hover.size.x - 16.0
	place.y = clampf(place.y, 24.0, CANVAS.y - _hover.size.y - 24.0)
	_hover.position = place
	_hover.visible = true


func _on_slot_unhover(_slot: LimbSlot) -> void:
	if _hover != null:
		_hover.visible = false


func _clock(seconds: float) -> String:
	var total := maxi(int(ceil(seconds)), 0)
	return "%d:%02d" % [int(total / 60.0), total % 60]


func _set_open(should_open: bool) -> void:
	_open = should_open
	visible = should_open
	get_tree().paused = should_open
	if should_open:
		_fit()
		_refresh_items()


func _fit() -> void:
	if _stage == null:
		return
	var view := get_viewport().get_visible_rect().size
	if view.x < 1.0 or view.y < 1.0:
		return
	var fitted := minf(view.x / CANVAS.x, view.y / CANVAS.y)
	_stage.scale = Vector2.ONE * fitted
	_stage.position = (view - CANVAS * fitted) * 0.5
