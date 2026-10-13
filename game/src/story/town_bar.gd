class_name TownBar
extends Node2D
## The town's toolbar (0x419d22) and 菜单, as buttons in the top black bar: the original's sit outside the scene
## view. They show while the scene waits for the player (StoryStage.menu_ready), as right click / Esc work then.

const TOOLBAR := ["卖出", "买进", "装备", "出征"]
const TOOLBAR_FLAGS := [0xf3, 0xf2, 0xf1]

var st: StoryStage
var menu: Button
var tools: Array[Button] = []    # 卖出 买进 装备 出征


func _init(stage: StoryStage) -> void:
	st = stage


func _ready() -> void:
	menu = _button("菜单", Vector2(572, 8))
	menu.pressed.connect(st.open_menu)
	for i in TOOLBAR.size():
		var b := _button(TOOLBAR[i], Vector2(504, 8))
		b.pressed.connect(_tool.bind(i))
		tools.append(b)


func _button(text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(60, 26)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Assets.font())
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", UIStyle.NAME_COLOR)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	var n := UIStyle.panel_box()
	n.set_content_margin_all(2)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = UIStyle.BG2
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.visible = false
	add_child(b)
	return b


func _process(_d: float) -> void:
	var show := st.menu_ready() and not Game.auto_input
	menu.visible = show
	var x := 504.0
	for i in tools.size():
		var b := tools[i]
		b.visible = show and shown(i)
		if b.visible:
			b.position.x = x
			x -= 68
	# the toolbar's buttons reach under the meter (x 290..502): while they show, they sit at the bar's bottom
	# and the meter goes above them
	var low := x < 504.0
	for b in [menu] + tools:
		b.position.y = 12 if low else 8
		b.size.y = 24 if low else 26
	if st.ui and st.ui.meter:
		st.ui.meter.position.y = 2 if low else 25


## The toolbar is shown with 出征 (op 0x06); story flags 0xf3 / 0xf2 / 0xf1 move 卖出 / 买进 / 装备 off it (0x419f22),
## and the others close up from the right.
func shown(i: int) -> bool:
	return st.sortie_enabled and (i >= TOOLBAR_FLAGS.size() or not Mem.flag(TOOLBAR_FLAGS[i]))


## A toolbar button (0x41973c): 0 卖出 (dialog 329), 1 买进 (327), 2 装备 (328), 3 出征.
func _tool(i: int) -> void:
	if not st.menu_ready() or not shown(i):
		return
	if i == 3:
		st.menu_sortie()
		return
	st._waiting_click = false
	match i:
		0:
			await ShopWindow.sell(st.ui)
		1:
			await ShopWindow.buy(st.ui)
		2:
			await EquipWindow.open(st.ui)
	st._waiting_click = true
