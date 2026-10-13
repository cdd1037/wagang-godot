class_name ItemListWindow
extends DlgPanel
## 持有道具一览 (menu command 40147 → dialog 325, proc 0x4680e7): 武具一览, the warehouse sorted by id followed by
## what the party wears (all weapons by person, then armour, then accessories, unsorted), and 道具一览, the
## consumables held. A click (left or right) on a row shows its details (dialog 167); a header click sorts.
## Nothing can be used or moved here. The 仓库装备现存量 count is taken when the window opens.

const TYPES := [[ItemCols.NAME, ItemCols.OWNER, ItemCols.KIND, ItemCols.EFFECT, ItemCols.LV, ItemCols.EXP,
	ItemCols.SPECIAL], [ItemCols.NAME, ItemCols.STOCK, ItemCols.USE, ItemCols.EFFECT]]
const TABS := ["武具一览", "道具一览"]

var tab := 0
var lists: Array[DlgPanel.ListView] = []
var last: Array[int] = [0, 0]
var _count := 0


static func open(ui: CanvasLayer) -> void:
	var w := ItemListWindow.new()
	w.dlu = Vector2(318, 209)
	w.dlu_scale = Vector2(1.95, 2.0)
	Audio.se(0)
	await DlgPanel.run(ui, w)


func _ready() -> void:
	super._ready()
	_count = ShopWindow.used_slots()
	for t in 2:
		var lv := DlgPanel.ListView.new()
		lv.columns = ItemCols.columns(TYPES[t])
		lv.sortable = true
		lists.append(lv)
	var bag := []
	for i in Game.BAG_SLOTS:
		var a := Game.BAG + 3 * i
		if Mem.r8(a) != 0xff:
			bag.append({"id": Mem.r8(a), "idx": i, "lvl": Mem.r8(a + 1), "exp": Mem.r8(a + 2), "flag": 1, "owner": -1})
	bag = ItemCols.sort_rows(bag, ItemCols.NAME)
	for s in 3:
		for p in Game.persons:
			var a := p.base + 0x2e + 3 * s
			if Mem.r8(p.base + 0x2a) == 0 and Mem.r8(a) != 0xff:
				bag.append({"id": Mem.r8(a), "idx": s, "lvl": Mem.r8(a + 1), "exp": Mem.r8(a + 2), "flag": 1, "owner": p.id})
	for d in bag:
		lists[0].rows.append({"data": d})
	for id in range(Game.STACK_FIRST, Game.STACK_LAST + 1):
		if Game.stack_count(id) > 0:
			lists[1].rows.append({"data": {"id": id, "idx": id - Game.STACK_FIRST, "lvl": 0, "exp": 0, "flag": 1}})
	_cells()


func _cells() -> void:
	for t in 2:
		var lv := lists[t]
		for i in lv.rows.size():
			var r: Dictionary = lv.rows[i]
			var cells := []
			var colors := []
			for ty in TYPES[t]:
				var c := ItemCols.cell(ty, r["data"], true, i == lv.sel)
				cells.append(c[0])
				colors.append(c[1])
			r["cells"] = cells
			r["colors"] = colors
			r["icon"] = ItemCols.icon(int(r["data"]["id"]))
	queue_redraw()


func _draw_dialog() -> void:
	var body := tabs(r(1, 1, 316, 190), TABS, tab, "tab", UIStyle.tab_icons())
	list_view(body.grow(-3), lists[tab], "list")
	text(r(5, 197, 58, 10), "仓库装备现存量", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	text(r(62, 197, 32, 10), "%d/200" % _count, HORIZONTAL_ALIGNMENT_CENTER)
	button(r(267, 193, 50, 14), "确定", ["ok", 0])


func _on_hover(key: Variant) -> void:
	if Game.touch:
		return
	var row := int(key[1]) if key is Array and key[0] == "list" and int(key[1]) >= 0 else -1
	if row != lists[tab].sel:
		lists[tab].sel = row
		_cells()


func _on_hit(key: Variant) -> void:
	if not (key is Array):
		return
	if list_scroll_hit(key, lists[tab], "list"):
		return
	var col := header_hit(key, "list")
	if col >= 0:
		last[tab] = ItemCols.header_click(lists[tab], TYPES[tab], col, last[tab])
		_cells()
		return
	match key[0]:
		"tab":
			if int(key[1]) != tab:
				Audio.se(0)
				lists[tab].sel = -1
				tab = int(key[1])
				_cells()
		"ok":
			close()
		"list":
			await _detail(int(key[1]))


func _on_right(key: Variant) -> bool:
	if key is Array and key[0] == "list" and int(key[1]) >= 0:
		await _detail(int(key[1]))
		return true
	return false


func _detail(i: int) -> void:
	var d: Dictionary = lists[tab].rows[i]["data"]
	await DetailPanel.show_item(get_parent(), int(d["id"]), int(d["lvl"]), int(d["exp"]))


## Dialog 325's tab stops: 确定 2, the shown list (1457 / 1003) and the tab control 1029. Here each is its own
## group, so Left / Right switch the tab wherever the focus is (on the tab control as in the original).
func focus_stops() -> Array:
	return [{"key": ["ok", 0], "kind": "button", "group": 0}, {"key": "list", "kind": "list", "group": 1, "lv": lists[tab]},
		{"key": ["tab", tab], "kind": "tabctl", "group": 2}]


func _on_list_key(_stop: Dictionary) -> void:
	_cells()


func _on_key(ev: InputEvent) -> bool:
	if ev.is_action_pressed("ui_left") or ev.is_action_pressed("ui_right"):
		_on_hit(["tab", 1 - tab])
	elif ev.is_action_pressed("ui_accept"):
		close()
	else:
		return false
	return true
