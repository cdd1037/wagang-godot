class_name ShopWindow
extends DlgPanel
## The town shops, opened from the toolbar: 买进 (dialog 327, init 0x46aa02) and 卖出 (dialog 329, init 0x46b7ce).
## Each has a 武器店 and a 道具店 tab. The goods are the shop record of the chapter (0x4790ae: record
## min(GS+7 >> 1, 57) of the 58 the exe loads from Data.wa entry 2: +8 sixteen equipment ids, +0x18 sixteen
## consumable ids). Equipment is bought for the person chosen on the right and worn at once; the old piece goes to
## the warehouse. The pointer selects the row under it (with the stat preview in 买进); a click buys or sells it,
## a right click shows its details (dialog 167). On touch a first tap selects, a second one acts.

## (SJIS "倉庫がいっぱいです。" left in the exe, 0x48e708 / 0x48e720; a Chinese Windows shows it this way.)
const FULL := "憅屔偑偄偭傁偄偱偡丅"
const BUY_TYPES := [[ItemCols.NAME, ItemCols.KIND, ItemCols.EQUIP, ItemCols.EFFECT, ItemCols.STOCK, ItemCols.TOTAL,
	ItemCols.PRICE], [ItemCols.NAME, ItemCols.USE, ItemCols.EFFECT, ItemCols.STOCK, ItemCols.PRICE]]
const SELL_TYPES := [[ItemCols.NAME, ItemCols.KIND, ItemCols.LV, ItemCols.EXP, ItemCols.EFFECT, ItemCols.SELL],
	[ItemCols.NAME, ItemCols.USE, ItemCols.EFFECT, ItemCols.STOCK, ItemCols.SELL]]
const TABS := ["武器店", "道具店"]

var selling := false
var tab := 0
var types: Array = []
var lists: Array[DlgPanel.ListView] = []
var last: Array[int] = [0, 0]
var panel: PersonPanel
var _busy := false
var incoming := {}            # the warehouse-full variant (0x46f034): the item that did not fit, as row 200

static var _shops: Array = []


## The shop record of this chapter (goods), clamped to the 58 loaded ones.
static func record() -> Dictionary:
	if _shops.is_empty():
		_shops = Assets.json("data/shops.json")
	return _shops[mini(Game.scenario >> 1, 57)]


## Record +4 (the merchant) and +0 (the speaker of "warehouse full") are read with the unclamped index
## (0x46dc1c, 0x468448); past the table the memory is zero.
static func merchant(full := false) -> int:
	if _shops.is_empty():
		_shops = Assets.json("data/shops.json")
	var i := Game.scenario >> 1
	if i >= 58:
		return 0
	return int(_shops[i]["unk_a" if full else "unk_b"])


static func _goods(off: int) -> Array[int]:
	var raw := (str(record()["raw"])).hex_decode()
	var out: Array[int] = []
	for k in 16:
		var b := raw[4 + off + k]
		if b != 0xff:
			out.append(b)
	return out


static func buy(ui: CanvasLayer) -> void:
	var w := ShopWindow.new()
	w.dlu = Vector2(404, 227)
	w.dlu_scale = Vector2(1.55, 1.95)
	w.selling = false
	await DlgPanel.run(ui, w)


## 0x46f034 → template 329 with the incoming item as row index 200 (drawn blue): selling one of the old pieces puts
## it into the freed slot, selling it gets its price instead; either ends the window. Closing it loses the item.
static func warehouse_full(ui: CanvasLayer, id: int, lvl: int, xp: int) -> void:
	if Game.autoplay:
		return
	var w := ShopWindow.new()
	w.dlu = Vector2(317, 227)
	w.dlu_scale = Vector2(1.95, 1.95)
	w.selling = true
	var equip := ItemCols.category(id) < 2
	w.incoming = {"id": id, "idx": 200, "lvl": lvl if equip else 0xff, "exp": xp if equip else 0xff, "flag": 1}
	await DlgPanel.run(ui, w)


static func sell(ui: CanvasLayer) -> void:
	var w := ShopWindow.new()
	w.dlu = Vector2(317, 227)
	w.dlu_scale = Vector2(1.95, 1.95)
	w.selling = true
	await DlgPanel.run(ui, w)


func _ready() -> void:
	super._ready()
	types = SELL_TYPES if selling else BUY_TYPES
	for t in 2:
		var lv := DlgPanel.ListView.new()
		lv.columns = ItemCols.columns(types[t])
		lv.sortable = true
		lists.append(lv)
	if not selling:
		panel = PersonPanel.new(self)
		panel.on_change = _person_changed
	_fill()


# ------------------------------------------------------------------ rows
func _fill() -> void:
	var data: Array = [[], []]
	if selling:
		for i in Game.BAG_SLOTS:
			var a := Game.BAG + 3 * i
			if Mem.r8(a) != 0xff:
				data[0].append({"id": Mem.r8(a), "idx": i, "lvl": Mem.r8(a + 1), "exp": Mem.r8(a + 2), "flag": 1})
		if not incoming.is_empty():
			data[0].append(incoming.duplicate())
		data[0] = ItemCols.sort_rows(data[0], ItemCols.NAME)
		for id in range(Game.STACK_FIRST, Game.STACK_LAST + 1):
			if Game.stack_count(id) > 0:
				data[1].append({"id": id, "idx": id - Game.STACK_FIRST, "lvl": 0, "exp": 0, "flag": 1})
	else:
		var ge := _goods(0)
		for k in ge.size():
			data[0].append({"id": ge[k], "idx": k, "lvl": 1, "exp": 0, "flag": 0})
		var gi := _goods(16)
		for k in gi.size():
			data[1].append({"id": gi[k], "idx": k, "lvl": 0, "exp": 0, "flag": 1})
		for t in 2:
			data[t] = ItemCols.sort_rows(data[t], ItemCols.NAME)
	for t in 2:
		lists[t].rows.clear()
		for d in data[t]:
			lists[t].rows.append({"data": d})
	_flags()


## 0x46871c: 装备 ○/× = can the chosen person wear it.
func _flags() -> void:
	if selling or panel == null:
		_cells()
		return
	var p := panel.person()
	for r in lists[0].rows:
		r["data"]["flag"] = 1 if p != null and p.can_equip(int(r["data"]["id"])) else 0
	_cells()


func actionable(t: int, d: Dictionary) -> bool:
	var id := int(d["id"])
	if selling:
		return ItemCols.sell_price(id, int(d["lvl"])) != 0xffff
	if t == 0 and int(d["flag"]) == 0 and ItemCols.category(id) != 3:
		return false
	return ItemCols.buy_price(id) <= Game.gold


func _cells() -> void:
	for t in 2:
		var lv := lists[t]
		for i in lv.rows.size():
			var r: Dictionary = lv.rows[i]
			var d: Dictionary = r["data"]
			var act := actionable(t, d)
			var cells := []
			var colors := []
			for ty in types[t]:
				var c := ItemCols.cell(ty, d, act, i == lv.sel)
				cells.append(c[0])
				colors.append(c[1])
			r["cells"] = cells
			r["colors"] = colors
			r["icon"] = ItemCols.icon(int(d["id"]))
			r["color"] = UIStyle.TEXT_COLOR if act else DIM
			if int(d["idx"]) == 200 and i != lv.sel:
				r["color"] = Color(0.55, 0.75, 1.0)      # the incoming item (0x4670b5)
	queue_redraw()


func _person_changed() -> void:
	_flags()


# ------------------------------------------------------------------ drawing
func _draw_dialog() -> void:
	if selling:
		group(r(2, 2, 312, 204), "仓库列表")
		var body := tabs(r(6, 11, 304, 192), TABS, tab, "tab", UIStyle.tab_icons())
		list_view(body.grow(-3), lists[tab], "list")
		text(r(108, 212, 25, 10), "现金", HORIZONTAL_ALIGNMENT_LEFT, CAPTION)
		text(r(135, 212, 40, 10), "%d" % Game.gold)
		text(r(7, 212, 60, 10), "仓库装备现存量", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
		text(r(68, 212, 32, 10), "%d/200" % used_slots(), HORIZONTAL_ALIGNMENT_CENTER)
		button(r(267, 209, 41, 15), "结束", ["end", 0])
	else:
		group(r(2, 3, 235, 204), "商品列表")
		var body := tabs(r(6, 12, 226, 192), TABS, tab, "tab", UIStyle.tab_icons())
		list_view(body.grow(-3), lists[tab], "list")
		text(r(129, 213, 24, 10), "现金", HORIZONTAL_ALIGNMENT_LEFT, CAPTION)
		text(r(150, 213, 38, 10), "%d" % Game.gold, HORIZONTAL_ALIGNMENT_RIGHT)
		button(r(191, 210, 41, 15), "结束", ["end", 0])
		panel.draw()


## 0x4db000: bag slots in use (consumable stacks are not counted).
static func used_slots() -> int:
	var n := 0
	for i in Game.BAG_SLOTS:
		if Mem.r8(Game.BAG + 3 * i) != 0xff:
			n += 1
	return n


# ------------------------------------------------------------------ input
func _on_hover(key: Variant) -> void:
	if _busy:
		return
	var row := -1
	if key is Array and key[0] == "list" and int(key[1]) >= 0:
		row = int(key[1])
	if panel:
		panel.on_hover(key)
	if Game.touch:
		return
	_select(row)


func _select(row: int) -> void:
	var lv := lists[tab]
	if row == lv.sel:
		return
	lv.sel = row
	if panel and tab == 0:
		if row >= 0:
			var d: Dictionary = lv.rows[row]["data"]
			panel.preview(int(d["id"]), int(d["lvl"]))
		elif panel.hover_slot >= 3:
			panel.clear_preview()
	_cells()


func _on_tap(key: Variant) -> void:
	if key is Array and key[0] == "list" and int(key[1]) >= 0 and int(key[1]) != lists[tab].sel:
		_select(int(key[1]))        # touch: the first tap selects (and previews), the second acts
		return
	_on_hit(key)


func _on_hit(key: Variant) -> void:
	if _busy or not (key is Array):
		return
	if panel and panel.on_hit(key):
		_cells()
		return
	var k: Array = key
	if list_scroll_hit(key, lists[tab], "list"):
		return
	var col := header_hit(key, "list")
	if col >= 0:
		last[tab] = ItemCols.header_click(lists[tab], types[tab], col, last[tab])
		lists[tab].sel = -1
		_cells()
		return
	match k[0]:
		"tab":
			if int(k[1]) != tab:
				Audio.se(0)
				lists[tab].sel = -1
				tab = int(k[1])
				if panel:
					panel.enabled = tab == 0
					panel.clear_preview()
				_cells()
		"end":
			close()
		"list":
			var i := int(k[1])
			var d: Dictionary = lists[tab].rows[i]["data"]
			if not actionable(tab, d):
				return
			_busy = true
			if selling and tab == 0:
				await _sell_equip(i)
			elif selling:
				await _sell_item(i)
			elif tab == 0:
				await _buy_equip(d)
			else:
				await _buy_item(d)
			_busy = false
			_cells()


func _on_right(key: Variant) -> bool:
	if _busy:
		return true
	if key is Array and key[0] == "list" and int(key[1]) >= 0:
		var d: Dictionary = lists[tab].rows[int(key[1])]["data"]
		await DetailPanel.show_item(get_parent(), int(d["id"]), int(d["lvl"]), int(d["exp"]))
		return true
	if key is Array and key[0] == "pp_slot" and panel:
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
	if ev.is_action_pressed("ui_left") or ev.is_action_pressed("ui_right"):
		_on_hit(["tab", 1 - tab])
	elif ev.is_action_pressed("ui_up"):
		_select(maxi(lists[tab].sel - 1, 0))
		lists[tab].select(lists[tab].sel)
	elif ev.is_action_pressed("ui_down"):
		_select(mini(lists[tab].sel + 1, lists[tab].rows.size() - 1))
		lists[tab].select(lists[tab].sel)
	elif ev.is_action_pressed("ui_accept") and lists[tab].sel >= 0:
		_on_hit(["list", lists[tab].sel])
	elif panel and (ev.is_action_pressed("ui_page_up") or (ev is InputEventKey and ev.keycode == KEY_Q)):
		panel.step(-1)
	elif panel and (ev.is_action_pressed("ui_page_down") or (ev is InputEventKey and ev.keycode == KEY_E)):
		panel.step(1)
	else:
		return false
	return true


# ------------------------------------------------------------------ buying (0x4684cc / 0x4688eb)
func _buy_equip(d: Dictionary) -> void:
	var p := panel.person()
	var id := int(d["id"])
	if p == null or int(d["flag"]) == 0:
		return
	Audio.se(0)
	var cat := ItemCols.category(id)
	if Mem.r8(p.base + 0x2e + 3 * cat) != 0xff and used_slots() >= Game.BAG_SLOTS:
		await MerchantBox.say(get_parent(), merchant(true), FULL)
		return
	var price := ItemCols.buy_price(id)
	var name := str(Game.item(id).get("name", "?"))
	if not await MerchantBox.ask(get_parent(), merchant(), "%s的价格是%d。\n要买进吗？" % [name, price], false):
		return
	Game.gold = Game.gold - price
	EquipWindow.put_on(p, id, 1, 0)
	panel.preview(int(d["id"]), 1)


func _buy_item(d: Dictionary) -> void:
	var id := int(d["id"])
	Audio.se(0)
	var unit := ItemCols.buy_price(id)
	var most := 99 - Game.stack_count(id)
	if unit * most > Game.gold:
		most = Game.gold / unit
	var n := await MerchantBox.count(get_parent(), merchant(), id, most, true)
	if n < 1:
		return
	Mem.w8(Game.STACKS + id - Game.STACK_FIRST, Game.stack_count(id) + n)
	Game.gold = Game.gold - unit * n


# ------------------------------------------------------------------ selling (0x46b043 / 0x46b671)
func _sell_equip(i: int) -> void:
	var d: Dictionary = lists[0].rows[i]["data"]
	var id := int(d["id"])
	var lvl := int(d["lvl"])
	Audio.se(0)
	var price := ItemCols.sell_price(id, lvl)
	var name := str(Game.item(id).get("name", "?"))
	var q := ("%s的价格为%d。\n要卖掉吗？" % [name, price]) if ItemCols.category(id) >= 2 \
		else ("Lv.%2d的%s可卖%d。\n要卖掉吗？" % [lvl, name, price])
	if not await MerchantBox.ask(get_parent(), merchant(), q, true):
		return
	lists[0].rows.remove_at(i)
	lists[0].sel = -1
	Game.gold = mini(Game.gold + price, 9999999)
	var slot := int(d["idx"])
	if slot >= 200:
		close()                      # the incoming item itself was sold
		return
	var fruit := bonus_fruit(id, lvl)
	Mem.w8(Game.BAG + 3 * slot, 0xff)
	Mem.w8(Game.BAG + 3 * slot + 1, 0xff)
	Mem.w8(Game.BAG + 3 * slot + 2, 0xff)
	if fruit >= 0:
		await MerchantBox.say(get_parent(), merchant(), "商人好像对Lv.%2d的\n%s非常中意，所以\n又给了我们一个%s。" % [lvl, name,
			str(Game.item(fruit).get("name", "?"))])
		var c := Game.stack_count(fruit)
		if c < 255:
			Mem.w8(Game.STACKS + fruit - Game.STACK_FIRST, c + 1)
			if c + 1 == 1:
				lists[1].rows.append({"data": {"id": fruit, "idx": fruit - Game.STACK_FIRST, "lvl": 0, "exp": 0, "flag": 1}})
		else:
			Game.gold = mini(Game.gold + ItemCols.sell_price(fruit, 0), 9999999)
	if not incoming.is_empty():
		# the incoming item takes the freed slot and the window ends
		Mem.w8(Game.BAG + 3 * slot, int(incoming["id"]))
		Mem.w8(Game.BAG + 3 * slot + 1, int(incoming["lvl"]))
		Mem.w8(Game.BAG + 3 * slot + 2, int(incoming["exp"]))
		close()


## 0x40d51b: selling a weapon or armour that is not a treasure at level 3 gives a fruit by its kind.
static func bonus_fruit(id: int, lvl: int) -> int:
	var it := Game.item(id)
	if Person.slot_of(it) >= 2 or ItemCols.treasure(id) or lvl != 3:
		return -1
	match int(it.get("type", 0)):
		0: return 0x67
		2, 8: return 0x62
		4, 6: return 0x66
		10, 12: return 0x63
		14: return 0x64
		16: return 0x65
	return -1


func _sell_item(i: int) -> void:
	var d: Dictionary = lists[1].rows[i]["data"]
	var id := int(d["id"])
	Audio.se(0)
	var n := await MerchantBox.count(get_parent(), merchant(), id, Game.stack_count(id), false)
	if n < 1:
		return
	var left := Game.stack_count(id) - n
	Mem.w8(Game.STACKS + id - Game.STACK_FIRST, left)
	if left <= 0:
		lists[1].rows.remove_at(i)
		lists[1].sel = -1
	Game.gold = mini(Game.gold + ItemCols.sell_price(id, 0) * n, 9999999)
