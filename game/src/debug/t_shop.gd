extends Node
## Town shops and the warehouse: 买进 / 卖出 (ShopWindow, dialogs 327 / 329), 装备 (EquipWindow, 328) and the
## shared pieces (ItemCols prices and columns, PersonPanel preview, MerchantBox count rule). Runs with
## Game.autoplay so the merchant's questions answer themselves. With OUT=dir it saves pictures of the windows.
## Prints "t_shop: PASS".

var _ok := true


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("t_shop: FAIL ", what)
		_ok = false


func _bag(id: int, lvl: int, xp: int) -> int:
	var i := EquipWindow.free_slot()
	Mem.w8(Game.BAG + 3 * i, id)
	Mem.w8(Game.BAG + 3 * i + 1, lvl)
	Mem.w8(Game.BAG + 3 * i + 2, xp)
	return i


func _shot(w: Node, name: String) -> void:
	var out := OS.get_environment("OUT")
	if out == "":
		return
	for k in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func run() -> void:
	Game.new_game_state()
	Game.autoplay = OS.get_environment("OUT") == ""
	var ui := GameUI.new()
	add_child(ui)
	Game.scenario = 4                       # R_02: shop record 2
	for pid in [0, 8, 11]:
		Game.join_party(pid, 1)
	_prices()
	_goods()
	_panel()
	await _equip_window(ui)
	await _buy(ui)
	await _sell(ui)
	await _empty_lists(ui)
	print("t_shop: PASS" if _ok else "t_shop: FAILED")


func _prices() -> void:
	# 熟铜锏: price byte 5
	_check(ItemCols.buy_price(0) == 500, "buy price %d" % ItemCols.buy_price(0))
	Game.join_party(20, 1)                  # 贾润甫 in the party: 八折
	_check(ItemCols.buy_price(0) == 400, "八折 %d" % ItemCols.buy_price(0))
	Game.join_party(20, 0xff)
	_check(ItemCols.sell_price(0, 1) == 375 and ItemCols.sell_price(0, 2) == 562 and ItemCols.sell_price(0, 3) == 750,
		"sell price by level")
	_check(ItemCols.sell_price(0x57, 0) == 75, "馒头 sells for 75")
	var tr := -1
	for it in Game.items_db:
		if bool(it.get("treasure", false)):
			tr = int(it["id"])
			break
	_check(ItemCols.sell_price(tr, 1) == 0xffff, "treasures cannot be sold")
	_check(ShopWindow.bonus_fruit(0, 3) == 0x67 and ShopWindow.bonus_fruit(0, 2) == -1, "锏 at Lv 3 gives 仙人果")
	_check(ShopWindow.bonus_fruit(3, 3) == 0x62, "枪 at Lv 3 gives 精强果")


func _goods() -> void:
	var ge := ShopWindow._goods(0)
	var gi := ShopWindow._goods(16)
	_check(ge == [0, 3, 6, 15, 38, 41], "record 2 武器店 %s" % [ge])
	_check(gi == [87], "record 2 道具店 %s" % [gi])
	_check(ShopWindow.merchant() == 0, "merchant of record 2")
	Game.scenario = 26
	_check(ShopWindow.merchant() == 23, "record 13's merchant is 魏征")
	Game.scenario = 4


func _panel() -> void:
	var w := DlgPanel.new()
	var pp := PersonPanel.new(w)
	_check(pp.pids == [0, 8, 11], "members in table order %s" % [pp.pids])
	var p := pp.person()
	p.weapon = 0
	p.weapon_lvl = 1
	pp.preview(3, 1)                        # 精铁枪 instead of 熟铜锏
	var want := Person.item_value_at(Game.item(3), 1) - Person.item_value_at(Game.item(0), 1)
	_check(pp._diff[2] == (want if p.can_equip(3) else 0), "attack preview %d" % pp._diff[2])
	w.free()


func _equip_window(ui: GameUI) -> void:
	var p := Game.person(0)
	p.weapon = 0
	p.weapon_lvl = 2
	p.weapon_exp = 40
	var s1 := _bag(3, 3, 0xff)
	var s2 := _bag(0x40, 7, 9)              # an accessory keeps its bytes
	var w := EquipWindow.new()
	w.dlu = Vector2(403, 225)
	w.dlu_scale = Vector2(1.55, 1.97)
	ui.add_child(w)
	await get_tree().process_frame
	_check(w.lv.rows.size() == ShopWindow.used_slots(), "a row per used bag slot")
	var i := -1
	for k in w.lv.rows.size():
		if int(w.lv.rows[k]["data"]["id"]) == 3:
			i = k
	var can := p.can_equip(3)
	w._equip(i)
	if can:
		_check(p.weapon == 3 and p.weapon_lvl == 3 and p.weapon_exp == 0xff, "equipped with its bytes")
		_check(Mem.r8(Game.BAG + 3 * s1) == 0 and Mem.r8(Game.BAG + 3 * s1 + 1) == 2 and Mem.r8(Game.BAG + 3 * s1 + 2) == 40,
			"the old weapon went to the freed slot")
		_check(int(w.lv.rows[i]["data"]["id"]) == 0, "the old weapon took the clicked row")
	await _shot(w, "equip")
	await w._take_off(0)
	_check(p.weapon == -1, "taken off")
	w.close()
	w.queue_free()
	Mem.w8(Game.BAG + 3 * s2, 0xff)


func _buy(ui: GameUI) -> void:
	Game.gold = 10000
	var p := Game.person(8)
	var w := ShopWindow.new()
	w.dlu = Vector2(404, 227)
	w.dlu_scale = Vector2(1.55, 1.95)
	ui.add_child(w)
	await get_tree().process_frame
	w.panel.select(1)                       # 秦琼
	_check(w.panel.person() == p, "person by 下一武将")
	var row: Dictionary = {}
	for r in w.lists[0].rows:
		if p.can_equip(int(r["data"]["id"])):
			row = r["data"]
			break
	if not row.is_empty() and Game.autoplay:
		var old := p.weapon if ItemCols.category(int(row["id"])) == 0 else p.armor
		await w._buy_equip(row)
		var cat := ItemCols.category(int(row["id"]))
		_check(Mem.r8(p.base + 0x2e + 3 * cat) == int(row["id"]) and Mem.r8(p.base + 0x2f + 3 * cat) == 1, "bought and worn at Lv 1")
		_check(Game.gold == 10000 - ItemCols.buy_price(int(row["id"])), "paid")
		_check(old < 0 or ItemCols.stock(old) >= 1, "the old piece is in the warehouse")
	var g := Game.gold
	if Game.autoplay:
		await w._buy_item({"id": 87, "idx": 0, "lvl": 0, "exp": 0, "flag": 1})
		_check(Game.stack_count(87) == 1 and Game.gold == g - ItemCols.buy_price(87), "one 馒头 bought")
	w.panel._combo = false
	await _shot(w, "buy")
	w.tab = 1
	w.panel.enabled = false
	await _shot(w, "buy_items")
	w.close()
	w.queue_free()


func _sell(ui: GameUI) -> void:
	var s := _bag(0, 3, 0)
	Game.gold = 100
	var w := ShopWindow.new()
	w.dlu = Vector2(317, 227)
	w.dlu_scale = Vector2(1.95, 1.95)
	w.selling = true
	ui.add_child(w)
	await get_tree().process_frame
	var i := -1
	for k in w.lists[0].rows.size():
		if int(w.lists[0].rows[k]["data"]["idx"]) == s:
			i = k
	_check(i >= 0, "the bag piece is listed")
	await _shot(w, "sell")
	if Game.autoplay:
		var fruits := Game.stack_count(0x67)
		await w._sell_equip(i)
		_check(Game.gold == 100 + 750, "sold for 750")
		_check(Mem.r8(Game.BAG + 3 * s) == 0xff and Mem.r8(Game.BAG + 3 * s + 1) == 0xff, "slot freed as ff ff ff")
		_check(Game.stack_count(0x67) == fruits + 1, "仙人果 given")
	w.close()
	w.queue_free()


## Up on an empty list (an empty warehouse; a shop that sells no equipment) selects nothing.
func _empty_lists(ui: GameUI) -> void:
	Mem.fill(Game.BAG, 3 * Game.BAG_SLOTS, 0xff)
	var up := InputEventAction.new()
	up.action = "ui_up"
	up.pressed = true
	var w := EquipWindow.new()
	w.dlu = Vector2(403, 225)
	w.dlu_scale = Vector2(1.55, 1.97)
	ui.add_child(w)
	await get_tree().process_frame
	w._on_key(up)
	_check(w.lv.rows.is_empty() and w.lv.sel == -1, "装备: Up on an empty warehouse selects nothing")
	w.close()
	w.queue_free()
	var sw := ShopWindow.new()
	sw.dlu = Vector2(317, 227)
	sw.dlu_scale = Vector2(1.95, 1.95)
	sw.selling = true
	ui.add_child(sw)
	await get_tree().process_frame
	sw._on_key(up)
	_check(sw.lists[0].rows.is_empty() and sw.lists[0].sel == -1, "卖出: Up on an empty list selects nothing")
	sw.close()
	sw.queue_free()
