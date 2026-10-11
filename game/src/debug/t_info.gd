extends Node
## 武将情报 window (InfoWindow, dialog 166) and its entry points: the data shown (status line, 技能 box, strategy
## list, item effect texts), tab switching, 上一武将 / 下一武将, closing, the battle map's pointer right click and
## touch long press, and ChoiceMenu's row info callback. Prints "t_info: PASS".

var _ok := true


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("t_info: FAIL ", what)
		_ok = false


func _push(ev: InputEvent) -> void:
	get_viewport().push_input(ev, true)
	await get_tree().process_frame


func _button(p: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = p
	ev.global_position = p
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	await _push(ev)


func _click(p: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	await _button(p, true, button)
	await _button(p, false, button)


func _action(a: String) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = true
	await _push(ev)
	ev = InputEventAction.new()
	ev.action = a
	ev.pressed = false
	await _push(ev)


func _hit_rect(w: DlgPanel, key: String) -> Rect2:
	for h in w._hits:
		if typeof(h[1]) == TYPE_STRING and h[1] == key:
			return h[0]
	return Rect2()


func run() -> void:
	Game.new_game_state()
	_data_tests()
	await _window_tests()
	await _long_press_tests()
	await _menu_info_tests()
	await _story_tests()
	print("t_info: PASS" if _ok else "t_info: FAILED")


func _data_tests() -> void:
	var p0 := Game.person(0)
	# 技能 box (0x4d3bd3): the mod's list EV[3970..3999] is checked before the static table. R_00 fills it with
	# 1024 (nobody); in zeroed memory its entries would match person 0
	for i in 30:
		Mem.w32(0x55ee08 + 4 * i, 0)
	var s := InfoWindow.skill_info(p0)
	_check(s[0] == "【术】连理" and s[1] == Game.text(450 + 0x27), "pid 0 with a zeroed list: %s" % [s])
	for i in 30:
		Mem.w32(0x55ee08 + 4 * i, 1024)
	Mem.w8(0x4dc100, 3)
	s = InfoWindow.skill_info(p0)
	_check(s[0] == "【招】苍龙过阵枪" and s[1] == Game.text(453), "pid 0 from the static table: %s" % [s])
	Mem.w32(0x55ee08 + 4 * 2, 5)
	s = InfoWindow.skill_info(Game.person(5))
	_check(s[0] == Mem.str_at(0x5559a0 + 64) and Mem.r8(0x4dc100 + 5) == 0x29, "dynamic list entry 2: %s" % [s])
	for i in 30:
		Mem.w32(0x55ee08 + 4 * i, 0)
	Mem.w32(0x55ee08, 0xffff)                          # (entry 0 would match pid 0 only)
	s = InfoWindow.skill_info(Game.person(17))
	_check(s[0] == "【招】尽命三锤" and s[1] == Game.text(450 + Mem.r8(0x4dc100 + 17)), "pid 17: %s" % [s])
	Mem.w32(0x55ee08, 0)
	_check(InfoWindow.skill_info(Game.person(300))[0] == "无", "pid 300 has no skill")
	_check(not InfoWindow.skill_active(p0, 0), "code 0 needs [0x55ac04] == 1")
	# 状态 line (0x478a0f)
	_check(InfoWindow.status_text(null) == "正常", "no unit: 正常")
	var u := BUnit.at(3)
	u.reset(3)
	u.pid = 0
	u.state = BUnit.STATE_ON_MAP
	for b in 6:
		u.set_buff(b, 3)
	_check(InfoWindow.status_text(u) == "正常", "plain unit: 正常 (got %s)" % InfoWindow.status_text(u))
	u.status = BUnit.ST_CONFUSION | BUnit.ST_POISON
	u.set_buff(0, 4)
	u.set_buff(1, 2)
	u.acted = true
	var st := InfoWindow.status_text(u)
	_check(st == "混乱 中毒 攻击增加 防御减少  行动完毕", "status line: '%s'" % st)
	u.status = 0
	u.set_buff(0, 3)
	u.set_buff(1, 3)
	u.acted = false
	Mem.w8(0x569f00 + 3, 2)
	_check(InfoWindow.status_text(u) == "暗杀 ", "暗杀 flag: '%s'" % InfoWindow.status_text(u))
	Mem.w8(0x569f00 + 3, 0)
	# names lose their ASCII digits (0x407757)
	var pp := Person.view(5, "间谍3")
	_check(InfoWindow.display_name(pp) == "间谍", "digits stripped: %s" % InfoWindow.display_name(pp))
	# strategies: the same rule as the AI's list (learned_strategies)
	var acts := BattleActions.new(null)
	for pid in range(0, 40):
		var p := Game.person(pid)
		if p == null:
			continue
		var bu := BUnit.at(4)
		bu.reset(4)
		bu.pid = pid
		var a := InfoWindow.strategies_of(p.cls, p.level)
		var b := acts.learned_strategies(bu)
		if a != b:
			_check(false, "strategies of pid %d: %s vs %s" % [pid, a, b])
			break
	u.pid = -1
	# item texts (0x462005 / 0x461ef3)
	_check(DetailPanel.item_effect(0, 1) == "攻击 +%d" % int(Game.item(0)["value"]), "weapon 0 effect: %s" % DetailPanel.item_effect(0, 1))
	var w2 := Game.item(0)
	_check(DetailPanel.item_effect(0, 3) == "攻击 +%d" % mini(int(w2["value"]) + 2 * int(w2["growth"]), 255), "weapon 0 at Lv3")
	for iid in Game.items_db.size():
		var it: Dictionary = Game.items_db[iid]
		var e := DetailPanel.item_effect(iid, 1)
		if String(it.get("category", "")) in ["weapon", "armor"] and not e.contains("+"):
			_check(false, "item %d effect '%s'" % [iid, e])
		if bool(it.get("treasure", false)) and DetailPanel.item_special(iid, 1) == "":
			_check(false, "treasure %d has no special text" % iid)
	_check(DetailPanel.exp_max(Game.item(0), 1) == 100, "exp max of a normal weapon")


func _window_tests() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	for pid in [0, 1, 2]:
		Mem.w8(Game.person(pid).base + 0x2a, 0)          # party members
	var done := [false]
	var open := func() -> void:
		await InfoWindow.open(ui, [0, 1, 2], 0)
		done[0] = true
	InfoWindow.tab = 0
	open.call()
	await get_tree().process_frame
	await get_tree().process_frame
	var w: InfoWindow = null
	for c in ui.get_children():
		if c is InfoWindow:
			w = c
	_check(w != null, "window opened")
	if w == null:
		return
	_check(Rect2(Vector2.ZERO, Vector2(640, 480)).encloses(Rect2(w.origin, w.dlu * w.dlu_scale).grow(6)), "window fits 640x480")
	_check(_hit_rect(w, "prev") == Rect2(), "上一武将 disabled at the first entry")
	await _click(_hit_rect(w, "next").get_center())
	_check(w.idx == 1, "下一武将 → entry 1 (idx %d)" % w.idx)
	await _action("ui_page_down")
	_check(w.idx == 2, "PageDown → entry 2")
	await get_tree().process_frame
	_check(_hit_rect(w, "next") == Rect2(), "下一武将 disabled at the last entry")
	await _action("ui_page_down")
	_check(w.idx == 2, "no wrap at the end")
	for t in 4:
		await _click(_hit_rect(w, "tab%d" % t).get_center())
		_check(InfoWindow.tab == t, "tab %d by click" % t)
		var out := OS.get_environment("OUT")
		if out != "":
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.replace(".png", "_%d.png" % t))
	await _action("ui_right")
	_check(InfoWindow.tab == 0, "→ wraps to tab 0")
	await _action("ui_left")
	_check(InfoWindow.tab == 3, "← goes to tab 3")
	# a unit's values: buffs show battle/base, HP/MP the unit's
	var u := BUnit.at(0)
	u.reset(0)
	u.pid = 2
	u.state = BUnit.STATE_ON_MAP
	for b in 6:
		u.set_buff(b, 3)
	u.set_buff(5, 4)
	w._u = u
	_check(w._move_text() == "%d ( +2 )" % (Game.person(2).move_points() + 2), "move with a raised move buff: %s" % w._move_text())
	u.pid = -1
	w._u = null
	# the strategy page opens a detail on a row click; the detail closes on 确认
	InfoWindow.tab = 2
	w._p = Game.person(2)
	w._strats = [0, 1]
	w.queue_redraw()
	await get_tree().process_frame
	var row := _hit_rect(w, "st0")
	_check(row != Rect2(), "strategy row hit area")
	if row != Rect2():
		await _click(row.get_center())
		await get_tree().process_frame
		var d: DetailPanel = null
		for c in ui.get_children():
			if c is DetailPanel:
				d = c
		_check(d != null and d.kind == 1 and d.sid == 0, "strategy detail opened")
		if d:
			await get_tree().process_frame
			await _click(_hit_rect(d, "ok").get_center())
			await get_tree().process_frame
			_check(not is_instance_valid(d) or d.is_queued_for_deletion(), "detail closed by 确认")
	if OS.get_environment("OUT") != "":
		await _shots(ui, w, OS.get_environment("OUT"))
	# a right click closes the window
	await _click(Vector2(320, 240), MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	_check(done[0], "right click closes the window")
	# outside battle it opens for party members only (0x407060)
	Mem.w8(Game.person(7).base + 0x2a, 0xff)
	done[0] = false
	var open2 := func() -> void:
		await InfoWindow.open(ui, [7], 0)
		done[0] = true
	open2.call()
	await get_tree().process_frame
	_check(done[0], "not opened for a non-member outside battle")
	ui.queue_free()
	await get_tree().process_frame


func _shot(out: String, tag: String) -> void:
	for c in find_children("*", "DlgPanel", true, false):
		c.queue_redraw()
	for k in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.replace(".png", "_%s.png" % tag))


## OUT=file.png (with a window): screenshots of equipment, a strategist's list, a buffed unit and the details.
func _shots(ui: CanvasLayer, w: InfoWindow, out: String) -> void:
	var p := Game.person(2)
	var armor := -1
	for it in Game.items_db:
		if String(it.get("category", "")) == "armor":
			armor = int(it["id"])
			break
	p._set_slot(0, 22, 5, 30)          # 九凤朝阳刀 (a treasure) Lv5
	p._set_slot(1, armor, 2, 40)
	p._set_slot(2, 55, 0xff, 0)        # 阵谱
	w._p = p
	InfoWindow.tab = 1
	await _shot(out, "equip")
	var u := BUnit.at(0)
	u.reset(0)
	u.pid = 2
	u.state = BUnit.STATE_ON_MAP
	for b in 6:
		u.set_buff(b, 3)
	u.set_buff(0, 4)
	u.set_buff(1, 2)
	u.set_buff(5, 4)
	u.status = BUnit.ST_POISON | BUnit.ST_SEAL
	u.hp = p.max_hp() / 3
	u.mp = 2
	u.acted = true
	w._u = u
	InfoWindow.tab = 0
	await _shot(out, "unit")
	InfoWindow.tab = 3
	await _shot(out, "unit_class")
	u.pid = -1
	w._u = null
	var q := Game.person(3)
	q.cls = 29
	q.level = 40
	w._p = q
	w._strats = InfoWindow.strategies_of(q.cls, q.level)
	InfoWindow.tab = 2
	await _shot(out, "strat")
	DetailPanel.show_item(ui, 22, 5, 30)
	await _shot(out, "item")
	ui.get_child(ui.get_child_count() - 1).close()
	DetailPanel.show_item(ui, 55, 0xff, 0)
	await _shot(out, "item_acc")
	ui.get_child(ui.get_child_count() - 1).close()
	DetailPanel.show_strategy(ui, 0)
	await _shot(out, "sdetail")
	ui.get_child(ui.get_child_count() - 1).close()
	await get_tree().process_frame
	w._p = Game.person(w.pids[w.idx])
	w.queue_redraw()


func _long_press_tests() -> void:
	Game.touch = true
	var v := BattleView.new()
	add_child(v)
	var idx: Dictionary = Assets.json("gfx/maps/index.json")
	v.load_map(int(idx["maps"][0]["id"]))
	v.camera.position = Vector2.ZERO
	for k in 3:
		await get_tree().process_frame
	var clicks := []
	v.cell_clicked.connect(func(c: Vector2i, btn: int) -> void: clicks.append([c, btn, v.right_from_pointer]))
	v.long_press_ok = func(c: Vector2i) -> bool: return c == Vector2i(2, 2)
	# a long press on a unit's cell is a pointer right click there; its release clicks nothing
	await _button(Vector2(100, 100), true)
	await get_tree().create_timer(BattleView.LONG_PRESS + 0.15).timeout
	_check(clicks == [[Vector2i(2, 2), MOUSE_BUTTON_RIGHT, true]], "long press → right click on (2,2): %s" % [clicks])
	await _button(Vector2(100, 100), false)
	_check(clicks.size() == 1, "its release is no tap: %s" % [clicks])
	# a short tap is a left click
	clicks.clear()
	await _button(Vector2(100, 100), true)
	await _button(Vector2(100, 100), false)
	await get_tree().create_timer(BattleView.LONG_PRESS + 0.15).timeout
	_check(clicks == [[Vector2i(2, 2), MOUSE_BUTTON_LEFT, clicks[0][2] if clicks.size() > 0 else false]], "tap → left click: %s" % [clicks])
	# a long press elsewhere (no unit) does nothing
	clicks.clear()
	await _button(Vector2(300, 300), true)
	await get_tree().create_timer(BattleView.LONG_PRESS + 0.15).timeout
	_check(clicks.is_empty(), "long press on an empty cell does nothing: %s" % [clicks])
	await _button(Vector2(300, 300), false)
	# Esc is a right click, but not from the pointer
	clicks.clear()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	await _push(esc)
	_check(clicks.size() == 1 and clicks[0][1] == MOUSE_BUTTON_RIGHT and not clicks[0][2], "Esc: %s" % [clicks])
	Game.touch = false
	# a mouse right click is from the pointer at the clicked cell
	clicks.clear()
	await _button(Vector2(160, 160), true, MOUSE_BUTTON_RIGHT)
	_check(clicks.size() == 1 and clicks[0] == [Vector2i(3, 3), MOUSE_BUTTON_RIGHT, true], "mouse right click: %s" % [clicks])
	v.queue_free()
	await get_tree().process_frame


## A story stage whose actor under the pointer is `fake`.
class FakeStory extends StoryStage:
	var fake := -1

	func actor_at(_p: Vector2) -> int:
		return fake


func _story_tests() -> void:
	var ui := GameUI.new()
	var gs := GDScript.new()                    # stand-in for main.gd (ScriptHost reads Game.main.ui)
	gs.source_code = "extends Node\nvar ui\nvar stage\n"
	gs.reload()
	var m := Node.new()
	m.set_script(gs)
	var old_main = Game.main
	Game.main = m
	add_child(m)
	m.set("ui", ui)
	var st := FakeStory.new()
	add_child(st)
	add_child(ui)
	await get_tree().process_frame
	var clicked := []
	st.clicked_actor.connect(func(pid: int) -> void: clicked.append(pid))
	var find_info := func() -> InfoWindow:
		for c in ui.get_children():
			if c is InfoWindow and not c.is_queued_for_deletion():
				return c
		return null
	Mem.w8(Game.person(0).base + 0x2a, 0)
	Mem.w8(Game.person(7).base + 0x2a, 0xff)
	var ev := InputEventMouseButton.new()
	ev.position = Vector2(300, 200)
	# a right click on a party member shows 武将情报 (0x429b81), and the scene waits again afterwards
	Game.touch = false
	st._waiting_click = true
	st.fake = 0
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	st._unhandled_input(ev)
	await get_tree().process_frame
	var w: InfoWindow = find_info.call()
	_check(w != null and w.pids[w.idx] == 0 and not st._waiting_click, "story: right click on a member opens 武将情报")
	if w:
		w.close()
	await get_tree().process_frame
	_check(st._waiting_click and clicked.is_empty(), "story: waiting for a click again afterwards")
	# on anyone else it opens the menu, as before
	st.fake = 7
	st._unhandled_input(ev)
	await get_tree().process_frame
	_check(find_info.call() == null and ui.menu._active, "story: right click on a non-member opens the menu")
	ui.menu._finish(-1)
	for k in 3:
		await get_tree().process_frame
	# touch: a long press on a member shows it, its release talks to nobody; a tap still clicks the actor
	Game.touch = true
	st._waiting_click = true
	st.fake = 0
	ev = InputEventMouseButton.new()
	ev.position = Vector2(300, 200)
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	st._unhandled_input(ev)
	await get_tree().create_timer(BattleView.LONG_PRESS + 0.15).timeout
	w = find_info.call()
	_check(w != null and clicked.is_empty(), "story: long press opens 武将情报")
	var up := ev.duplicate()
	up.pressed = false
	if w:
		w.close()
	await get_tree().process_frame
	st._unhandled_input(up)
	_check(clicked.is_empty(), "story: the long press's release clicks nothing")
	st._unhandled_input(ev)
	st._unhandled_input(up)
	_check(clicked == [0], "story: a tap clicks the actor (%s)" % [clicked])
	Game.touch = false
	Game.main = old_main
	st.queue_free()
	ui.queue_free()
	m.queue_free()
	await get_tree().process_frame


func _menu_info_tests() -> void:
	var m := ChoiceMenu.new()
	add_child(m)
	var res := [-2]
	var infos := []
	var cb := func(k: int) -> void:
		infos.append(k)
		await get_tree().process_frame
	var open := func() -> void:
		res[0] = await m.choose(["甲", "乙", "丙"], Vector2(-1, -1), true, "", [], 0, 0, cb)
	Game.touch = false
	open.call()
	await get_tree().process_frame
	await _button(m._row_rect(1).get_center(), true, MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	_check(infos == [1] and res[0] == -2, "right click on row 1 shows info, keeps the menu: %s %d" % [infos, res[0]])
	Game.touch = true
	await _button(m._row_rect(2).get_center(), true)
	await get_tree().create_timer(BattleView.LONG_PRESS + 0.15).timeout
	await _button(m._row_rect(2).get_center(), false)
	_check(infos == [1, 2] and res[0] == -2, "long press on row 2 shows info, picks nothing: %s %d" % [infos, res[0]])
	await _button(m._row_rect(0).get_center(), true)
	await _button(m._row_rect(0).get_center(), false)
	_check(res[0] == 0, "then a tap picks row 0 (%d)" % res[0])
	Game.touch = false
	m.queue_free()
	await get_tree().process_frame
