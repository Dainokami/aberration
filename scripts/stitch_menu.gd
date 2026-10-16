extends CanvasLayer

# 属性页是背包和装配，培养页是同一份背包和五个培养皿。
# 骨骼图层盖在底板上；能拖的格子再盖在骨骼上。

const CANVAS := Vector2(3840.0, 2160.0)
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
		{"box": Rect2(2890, 0, 230, 360), "page": "inventory"},
	],
	"inventory": [
		{"box": Rect2(0, 376, 360, 210), "page": "sheet"},
	],
}
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
var _sheet_bag_slots: Array[LimbSlot] = []
var _equip_slots: Array[LimbSlot] = []
var _dish_sides: Array[LimbSlot] = []
var _dish_bars: Array[ColorRect] = []
var _attributes: Label
var _note: Label


func _ready() -> void:
	_build()
	_bag = get_parent().get_node("Player/LimbBag") as LimbBag
	_bag.changed.connect(_refresh_items)
	_bag.note.connect(_show_note)
	_refresh_items()
	get_viewport().size_changed.connect(_fit)
	_fit()


func _process(_delta: float) -> void:
	if not _open or _bag == null:
		return
	for index in _bag.dishes.size():
		var dish: Dictionary = _bag.dishes[index]
		var running := not str(dish["a"]).is_empty() and not str(dish["b"]).is_empty()
		var bar := _dish_bars[index]
		bar.visible = running
		if running:
			bar.size.x = DISH_BOXES[index].size.x * clampf(float(dish["time"]) / LimbBag.CULTURE_SECONDS, 0.0, 1.0)


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
		button.modulate = Color(1, 1, 1, 0)
		button.position = hotspot["box"].position
		button.size = hotspot["box"].size
		button.tooltip_text = "培养皿" if hotspot["page"] == "inventory" else "属性"
		var target: String = hotspot["page"]
		button.pressed.connect(_show_page.bind(target))
		page.add_child(button)
	if page_name == "sheet":
		_build_sheet(page)
	else:
		_build_culture(page)
	return page


func _build_sheet(page: Control) -> void:
	_attributes = _make_label(page, Rect2(2460, 470, 1120, 280), 46)
	for spec: Dictionary in SHEET_EQUIP:
		_equip_slots.append(_bind_equip(page, spec["box"], spec["slot"]))
	for index in LimbBag.CAPACITY:
		var column := index % 4
		var row := index / 4
		var box := Rect2(2500 + column * 220, 780 + row * 230, 200, 210)
		_sheet_bag_slots.append(_bind_bag(page, box, index))


func _build_culture(page: Control) -> void:
	for spec: Dictionary in PAGE_EQUIP:
		_equip_slots.append(_bind_equip(page, spec["box"], spec["slot"]))
	for index in DISH_BOXES.size():
		var box: Rect2 = DISH_BOXES[index]
		var top := _bind_dish(page, Rect2(box.position.x, box.position.y, box.size.x, box.size.y * 0.46), index)
		var bottom := _bind_dish(page, Rect2(box.position.x, box.position.y + box.size.y * 0.48, box.size.x, box.size.y * 0.42), index)
		_dish_sides.append(top)
		_dish_sides.append(bottom)
		var bar := ColorRect.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.color = Color(0.86, 0.16, 0.12, 0.9)
		bar.position = box.position + Vector2(0, box.size.y - 18)
		bar.size = Vector2(0, 16)
		page.add_child(bar)
		_dish_bars.append(bar)
	for index in GRID_COLUMNS.size():
		for row in GRID_ROWS.size():
			var band: Rect2 = GRID_ROWS[row]
			var box := Rect2(GRID_COLUMNS[index], band.position.y, GRID_WIDTHS[index], band.size.y)
			_bag_slots.append(_bind_bag(page, box, row * GRID_COLUMNS.size() + index))
	var recycle := _add_slot(page, Rect2(3160, 1080, 500, 250))
	recycle.item_dropped.connect(_drop_on_recycle)
	var recycle_label := _make_label(page, Rect2(3160, 1160, 500, 80), 42)
	recycle_label.text = "拖到这里回收"
	recycle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_make_label(page, Rect2(760, 1968, 2200, 70), 40).text = "两个肢体放进同一个培养皿。相近的会变强，小概率出稀有；不相干会变成残肢。"


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
	return slot


func _refresh_items() -> void:
	if _bag == null:
		return
	for slot in _bag_slots:
		_show_bag_slot(slot)
	for slot in _sheet_bag_slots:
		_show_bag_slot(slot)
	for slot in _equip_slots:
		var slot_name := str(slot.get_meta("equip_slot"))
		var limb_id := _bag.equipped_upper if slot_name == "upper" else _bag.equipped_lower
		_show_limb(slot, limb_id, {"kind": "equip", "slot": slot_name, "id": limb_id})
	for index in _bag.DISH_COUNT:
		var dish: Dictionary = _bag.dishes[index]
		_show_limb(_dish_sides[index * 2], str(dish["a"]), {"kind": "dish", "dish": index, "side": "a", "id": dish["a"]})
		_show_limb(_dish_sides[index * 2 + 1], str(dish["b"]), {"kind": "dish", "dish": index, "side": "b", "id": dish["b"]})
	_attributes.text = _attribute_text()


func _attribute_text() -> String:
	return "上肢  %s\n下肢  %s\n\n把背包里的肢体拖到骨框上装配。\n右键可以回收。" % [
		_limb_line(_bag.equipped_upper), _limb_line(_bag.equipped_lower)
	]


func _limb_line(limb_id: String) -> String:
	var limb := LimbCatalog.find(limb_id)
	if limb == null:
		return "空"
	var mark := "稀有  " if limb.rare else ""
	return "%s%s  %s" % [mark, limb.display_name, limb.blurb]


func _show_bag_slot(slot: LimbSlot) -> void:
	var index := int(slot.get_meta("bag_index"))
	_show_limb(slot, _bag.slots[index], {"kind": "bag", "index": index, "id": _bag.slots[index]})


func _show_limb(slot: LimbSlot, limb_id: String, data: Dictionary) -> void:
	slot.drag_data = data
	var limb := LimbCatalog.find(limb_id)
	slot.icon.texture = LimbCatalog.texture_for(limb_id) if limb else null
	slot.icon.modulate = limb.tint if limb else Color.WHITE
	slot.tooltip_text = limb.display_name if limb else ""


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
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.96, 0.9, 0.78))
	parent.add_child(label)
	return label


func _bounds(box: Array) -> Rect2:
	return Rect2(box[0], box[1], box[2] - box[0], box[3] - box[1])


func _show_page(page_name: String) -> void:
	_page = page_name
	for name: String in _pages:
		(_pages[name] as Control).visible = name == page_name


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
