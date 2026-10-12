class_name EquipWindow
extends DlgPanel
## 装备 (dialog 328, init 0x46c43a), opened from the town toolbar: the warehouse (every bag slot in use, which
## only ever holds equipment) and the person panel shared with 买进. The pointer selects the row under it and
## previews the change; a click puts that piece on (SE 9) and the one it replaces goes to the warehouse; a click on
## a slot takes its piece off (SE 1); a right click shows the details (dialog 167). Rows the person cannot wear
## stay greyed with a red × and ignore clicks. Levels and experience move with the pieces byte for byte.

const TYPES := [ItemCols.NAME, ItemCols.KIND, ItemCols.LV, ItemCols.EXP, ItemCols.EFFECT, ItemCols.EQUIP]

var lv := DlgPanel.ListView.new()
var last := 0
var panel: PersonPanel
var _insert_at := -1          # [list+0x54]: where the next row returned to the warehouse goes (-1: the end)
var _busy := false


static func open(ui: CanvasLayer) -> void:
	var w := EquipWindow.new()
	w.dlu = Vector2(403, 225)
	w.dlu_scale = Vector2(1.55, 1.97)
	await DlgPanel.run(ui, w)


## The first free warehouse slot (0x40d79c), or -1.
static func free_slot() -> int:
	for i in Game.BAG_SLOTS:
		if Mem.r8(Game.BAG + 3 * i) == 0xff:
			return i
	return -1


## 0x468cdc: slot s's piece into the first free warehouse slot, the slot cleared. Returns the bag slot, -1 when
## the slot is empty, -2 when the warehouse is full (nothing moves).
static func take_off_to_bag(p: Person, s: int) -> int:
	var a := p.base + 0x2e + 3 * s
	var id := Mem.r8(a)
	if id == 0xff:
		return -1
	var b := free_slot()
	if b < 0:
		return -2
	for k in 3:
		Mem.w8(Game.BAG + 3 * b + k, Mem.r8(a + k))
	Mem.w8(a, 0xff)
	Mem.w8(a + 1, 0)
	Mem.w8(a + 2, 0)
	return b


## 0x468d7e: wear `id` with these level and experience bytes; what the slot held goes to the warehouse first.
static func put_on(p: Person, id: int, lvl: int, xp: int) -> int:
	var s := ItemCols.category(id)
	var b := take_off_to_bag(p, s)
	if b == -2:
		return b
	var a := p.base + 0x2e + 3 * s
	Mem.w8(a, id)
	Mem.w8(a + 1, lvl)
	Mem.w8(a + 2, xp)
	return b


func _ready() -> void:
	super._ready()
	lv.columns = ItemCols.columns(TYPES)
	lv.sortable = true
	panel = PersonPanel.new(self)
	panel.x0 = 1
	panel.on_change = _flags
	var data := []
	for i in Game.BAG_SLOTS:
		var a := Game.BAG + 3 * i
		if Mem.r8(a) != 0xff:
			data.append({"id": Mem.r8(a), "idx": i, "lvl": Mem.r8(a + 1), "exp": Mem.r8(a + 2), "flag": 0})
	for d in ItemCols.sort_rows(data, ItemCols.NAME):
		lv.rows.append({"data": d})
	_flags()


## 0x46bb6f: ○ / × = CanEquip for every row.
func _flags() -> void:
	var p := panel.person()
	for r in lv.rows:
		r["data"]["flag"] = 1 if p != null and p.can_equip(int(r["data"]["id"])) else 0
	_cells()


func _cells() -> void:
	for i in lv.rows.size():
		var r: Dictionary = lv.rows[i]
		var d: Dictionary = r["data"]
		var act := int(d["flag"]) != 0
		var cells := []
		var colors := []
		for ty in TYPES:
			var c := ItemCols.cell(ty, d, act, i == lv.sel)
			cells.append(c[0])
			colors.append(c[1])
		r["cells"] = cells
		r["colors"] = colors
		r["icon"] = ItemCols.icon(int(d["id"]))
		r["color"] = UIStyle.TEXT_COLOR if act else DIM
	queue_redraw()


func _draw_dialog() -> void:
	group(r(7, 3, 228, 199), "仓库列表")
	list_view(r(10, 13, 221, 187), lv, "list")
	text(r(16, 210, 58, 10), "仓库装备现存量", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	text(r(74, 210, 32, 10), "%d/200" % ShopWindow.used_slots(), HORIZONTAL_ALIGNMENT_CENTER)
	button(r(187, 208, 41, 15), "结束", ["end", 0])
	panel.draw()


# ------------------------------------------------------------------ input
func _on_hover(key: Variant) -> void:
	if _busy:
		return
	panel.on_hover(key)
	if Game.touch:
		return
	_select(int(key[1]) if key is Array and key[0] == "list" and int(key[1]) >= 0 else -1)


func _select(row: int) -> void:
	if row == lv.sel:
		return
	lv.sel = row
	if row >= 0:
		var d: Dictionary = lv.rows[row]["data"]
		panel.preview(int(d["id"]), int(d["lvl"]))
	elif panel.hover_slot >= 3:
		panel.clear_preview()
	_cells()


func _on_tap(key: Variant) -> void:
	if key is Array and key[0] == "list" and int(key[1]) >= 0 and int(key[1]) != lv.sel:
		_select(int(key[1]))
		return
	if key is Array and key[0] == "pp_slot" and panel.hover_slot != int(key[1]):
		panel.on_hover(key)         # touch: the first tap shows what taking it off changes
		return
	_on_hit(key)


func _on_hit(key: Variant) -> void:
	if _busy or not (key is Array):
		return
	if panel.on_hit(key):
		_cells()
		return
	if list_scroll_hit(key, lv, "list"):
		return
	var col := header_hit(key, "list")
	if col >= 0:
		last = ItemCols.header_click(lv, TYPES, col, last)
		lv.sel = -1
		_cells()
		return
	var k: Array = key
	match k[0]:
		"end":
			close()
		"list":
			_equip(int(k[1]))
		"pp_slot":
			_busy = true
			await _take_off(int(k[1]))
			_busy = false


## 0x46bc8d: wear the clicked row's piece.
func _equip(i: int) -> void:
	var p := panel.person()
	var d: Dictionary = lv.rows[i]["data"]
	var id := int(d["id"])
	if p == null or not p.can_equip(id):
		return
	var slot := int(d["idx"])
	for k in 3:
		Mem.w8(Game.BAG + 3 * slot + k, 0xff)
	_insert_at = i
	Audio.se(9)
	var b := put_on(p, id, int(d["lvl"]), int(d["exp"]))
	lv.rows.remove_at(i)
	if b >= 0:
		_add_row(b)
	lv.sel = -1
	panel.clear_preview()
	_cells()


## The piece now in bag slot b as a row: at [list+0x54] (then -1), else at the end; flagged ○ until the next
## person change (0x46ba91).
func _add_row(b: int) -> void:
	var a := Game.BAG + 3 * b
	var row := {"data": {"id": Mem.r8(a), "idx": b, "lvl": Mem.r8(a + 1), "exp": Mem.r8(a + 2), "flag": 1}}
	if _insert_at >= 0 and _insert_at <= lv.rows.size():
		lv.rows.insert(_insert_at, row)
	else:
		lv.rows.append(row)
	_insert_at = -1


## 0x46befb: take slot s's piece off into the warehouse.
func _take_off(s: int) -> void:
	var p := panel.person()
	if p == null or s > 2 or Mem.r8(p.base + 0x2e + 3 * s) == 0xff:
		return
	if ShopWindow.used_slots() >= Game.BAG_SLOTS:
		Audio.se(0)
		await MerchantBox.say(get_parent(), ShopWindow.merchant(true), ShopWindow.FULL)
		return
	var b := take_off_to_bag(p, s)
	if b >= 0:
		_add_row(b)
	Audio.se(1)
	panel.clear_preview()
	_cells()


func _on_right(key: Variant) -> bool:
	if _busy:
		return true
	if key is Array and key[0] == "list" and int(key[1]) >= 0:
		var d: Dictionary = lv.rows[int(key[1])]["data"]
		await DetailPanel.show_item(get_parent(), int(d["id"]), int(d["lvl"]), int(d["exp"]))
		return true
	if key is Array and key[0] == "pp_slot":
		var p := panel.person()
		var s := int(key[1])
		var id := Mem.r8(p.base + 0x2e + 3 * s)
		if id != 0xff:
			await DetailPanel.show_item(get_parent(), id, Mem.r8(p.base + 0x2f + 3 * s), Mem.r8(p.base + 0x30 + 3 * s))
		return true
	return false


func _on_key(ev: InputEvent) -> bool:
	if _busy:
		return true
	if ev.is_action_pressed("ui_up"):
		if not lv.rows.is_empty():       # (an empty warehouse has no row 0)
			_select(maxi(lv.sel - 1, 0))
			lv.select(lv.sel)
	elif ev.is_action_pressed("ui_down"):
		_select(mini(lv.sel + 1, lv.rows.size() - 1))
		lv.select(lv.sel)
	elif ev.is_action_pressed("ui_accept") and lv.sel >= 0:
		_equip(lv.sel)
	elif ev.is_action_pressed("ui_page_up") or (ev is InputEventKey and ev.keycode == KEY_Q):
		panel.step(-1)
	elif ev.is_action_pressed("ui_page_down") or (ev is InputEventKey and ev.keycode == KEY_E):
		panel.step(1)
	else:
		return false
	return true
