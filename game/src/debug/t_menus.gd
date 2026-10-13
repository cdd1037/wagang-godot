extends Node
## The menu windows of mod_patches.md group 5: 环境设定 (SettingsWindow, applying to GS / [0x4dbe25] without
## writing Niuniu.wa), 历史情报 line order (HistoryWindow), 选择武将 rules and sorting (SortieScreen) and the
## candidate builder, 部队情报一览 / 持有道具一览 / 地形情报一览 / 出战位置 / MsgBox drawing, the town gate GS+2, and
## the boxes under WG_DEMO.
## With OUT=dir it saves pictures of the windows. Prints "t_menus: PASS".

var _ok := true


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("t_menus: FAIL ", what)
		_ok = false


func _shot(name: String) -> void:
	var out := OS.get_environment("OUT")
	if out == "":
		for k in 2:
			await get_tree().process_frame
		return
	for c in find_children("*", "CanvasItem", true, false):
		(c as CanvasItem).queue_redraw()
	for k in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func run() -> void:
	Game.new_game_state()
	var ui := GameUI.new()
	add_child(ui)
	var gs := GDScript.new()                    # stand-in for main.gd (ScriptHost reads Game.main.ui)
	gs.source_code = "extends Node\nvar ui\nvar stage\n"
	gs.reload()
	var m := Node.new()
	m.set_script(gs)
	Game.main = m
	add_child(m)
	m.set("ui", ui)
	for pid in [0, 8, 3, 1, 19, 11, 20]:
		Game.join_party(pid, 1)
	await _settings(ui)
	await _history(ui)
	await _sortie(ui)
	await _windows(ui)
	_icons(ui)
	await _demo(ui)
	await _save_questions(ui)
	print("t_menus: PASS" if _ok else "t_menus: FAILED")


func _msg_box(ui: GameUI) -> MsgBox:
	for k in 30:
		await get_tree().process_frame
		for c in ui.find_children("*", "", true, false):
			if c is MsgBox and c.visible:
				return c
	return null


## 保存 / 读取 (0x41b16a, 0x41ad06): the slot's 是/否 question first, "保存完毕。" after a save; 回到标题 (0x474ba7) asks
## "结束「瓦岗山异闻录」么？". Saves go to a folder of this check's own, never the player's slots.
func _save_questions(ui: GameUI) -> void:
	var was := [Game.auto_input, Game.instant, Game.save_dir]
	Game.auto_input = false
	Game.instant = false
	Game.save_dir = "user://test/menus_q/"
	DirAccess.make_dir_recursive_absolute(Game.save_dir)
	for i in 3:
		Game.delete_save(i)
	var main: Node = load("res://src/main.gd").new()      # outside the tree: only its save and load menus run
	main.set("ui", ui)
	Mem.w32(Addr.SAVE_ALLOWED, 1)
	var state := {"done": false}
	var run_save := func() -> void:
		await main.save_menu()
		state["done"] = true
	run_save.call()
	await get_tree().process_frame
	ui.menu._finish(2)
	var q := await _msg_box(ui)
	_check(q != null and q.title == "保存" and Array(q.lines) == ["进度No. 3: 未使用保存进度，", "可以保存吗？"],
			"save question %s %s" % [q.title if q else "-", q.lines if q else []])
	if q:
		q._on_hit(["btn", 0])           # 否
	for k in 10:
		await get_tree().process_frame
	_check(state["done"] and Game.save_info(2).is_empty(), "否 saves nothing")
	state["done"] = false
	run_save.call()
	await get_tree().process_frame
	ui.menu._finish(2)
	q = await _msg_box(ui)
	if q:
		q._on_hit(["btn", 1])           # 是
	var okb := await _msg_box(ui)
	_check(okb != null and Array(okb.lines) == ["保存完毕。"], "保存完毕 box %s" % [okb.lines if okb else []])
	if okb:
		okb._on_hit(["btn", 1])
	for k in 10:
		await get_tree().process_frame
	_check(state["done"] and not Game.save_info(2).is_empty(), "是 saves")
	# 读取: the question, 否 loads nothing
	var res := {"r": null}
	var run_load := func() -> void:
		res["r"] = await main.load_menu()
	run_load.call()
	await get_tree().process_frame
	ui.menu._finish(2)
	q = await _msg_box(ui)
	_check(q != null and q.title == "读取" and q.lines.size() == 2 and q.lines[0].begins_with("进度No. 3: ")
			and q.lines[1] == "可以读取吗？", "load question %s" % [q.lines if q else []])
	if q:
		q._on_hit(["btn", 0])
	for k in 10:
		await get_tree().process_frame
	_check(res["r"] == false, "否 loads nothing")
	# after a battle ended by op 0x49: "保存进度吗？", 是 opens the save list even while the scripts forbid saving
	Mem.w32(Addr.SAVE_ALLOWED, 0)
	state["done"] = false
	var run_after := func() -> void:
		await main._after_battle_save()
		state["done"] = true
	run_after.call()
	q = await _msg_box(ui)
	_check(q != null and Array(q.lines) == ["保存进度吗？"] and q.title == "瓦岗山异闻录", "after-battle question %s" % [q.lines if q else []])
	if q:
		q._on_hit(["btn", 1])
	for k in 5:
		await get_tree().process_frame
	_check(ui.menu.visible and ui.menu.title == "存储进度", "是 opens the save list (%s)" % ui.menu.title)
	ui.menu._finish(-1)
	for k in 5:
		await get_tree().process_frame
	_check(state["done"], "a cancel ends it")
	Mem.w32(Addr.SAVE_ALLOWED, 1)
	# 回到标题 asks first
	var titles := {"n": 0}
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar ui\nvar stage\nvar titles = 0\nfunc to_title():\n\ttitles += 1\n"
	gs.reload()
	var m2 := Node.new()
	m2.set_script(gs)
	m2.set("ui", ui)
	var old_main = Game.main
	Game.main = m2
	add_child(m2)
	SystemMenu.open(ui)
	await get_tree().process_frame
	ui.menu._finish(SystemMenu.labels(false).find("回到标题"))
	q = await _msg_box(ui)
	_check(q != null and Array(q.lines) == ["结束「瓦岗山异闻录」么？"], "quit question %s" % [q.lines if q else []])
	if q:
		q._on_hit(["btn", 0])
	for k in 10:
		await get_tree().process_frame
	_check(m2.get("titles") == 0, "否 stays")
	Game.main = old_main
	m2.queue_free()
	for i in 3:
		Game.delete_save(i)
	main.free()
	Game.auto_input = was[0]
	Game.instant = was[1]
	Game.save_dir = was[2]


## WG_DEMO (Game.auto_input without Game.instant): the boxes that wait for the player answer themselves, as under
## WG_AUTO, instead of waiting for a click nobody makes.
func _demo(ui: GameUI) -> void:
	var was := [Game.auto_input, Game.instant]
	Game.auto_input = true
	Game.instant = false
	var got := {}
	var boxes := {
		"MsgBox.ok": func() -> Variant: return await MsgBox.ok(ui, "t_menus"),
		"MsgBox.yes_no": func() -> Variant: return await MsgBox.yes_no(ui, "t_menus"),
		"MerchantBox.say": func() -> Variant: return await MerchantBox.say(ui, 0, "t_menus"),
		"MerchantBox.ask": func() -> Variant: return await MerchantBox.ask(ui, 0, "t_menus", false),
		"MerchantBox.count": func() -> Variant: return await MerchantBox.count(ui, 0, 1, 5, false),
		"ShopWindow.warehouse_full": func() -> Variant: return await ShopWindow.warehouse_full(ui, 1, 0, 0),
		"SortieScreen.choose": func() -> Variant:
			return await SortieScreen.choose(ui, self, 2, [0, 8, 3] as Array[int], 1),
	}
	for k: String in boxes:
		var run := func() -> void:
			got[k] = await boxes[k].call()
		run.call()
	for i in 3:
		await get_tree().process_frame
	for k: String in boxes:
		_check(got.has(k), "demo: %s answers without a click" % k)
	_check(got.get("MsgBox.yes_no") == true and got.get("MerchantBox.ask") == true and got.get("MerchantBox.count") == 1,
			"demo: 是 and one piece")
	_check(got.get("SortieScreen.choose") == [0, 8], "demo: the sortie list takes the first two")
	Game.auto_input = was[0]
	Game.instant = was[1]


## The command menu's icons (0x45bd05, mod 0x4d034d) and the tabs' (0x472281), from CmdIcon.dll.
func _icons(ui: GameUI) -> void:
	var ic := BattleInput.command_icons()
	_check(ic.size() == BattleInput.COMMANDS.size() and ic.all(func(t: Variant) -> bool: return t is Texture2D),
			"a CmdIcon picture per command")
	_check(ic[0] == ic[1] and ic[1] == ic[2] and ic[3] != ic[0] and ic[4] != ic[5] and ic[6] != ic[5], "sword ×3, scroll, hand-over, pouch, tent")
	_check(UIStyle.tab_icons()[0] == ic[0] and UIStyle.tab_icons()[1] == ic[5], "tabs: sword and pouch")
	var menu := ui.menu
	var auto := Game.autoplay
	Game.autoplay = true
	menu.choose(BattleInput.COMMANDS, Vector2(-1, -1), true, "", [], 60, 0, Callable(), ic)
	_check(menu.icons.size() == 7 and menu._text_dx() > 0, "the menu keeps them and moves the text right")
	menu.choose(["a", "b"])
	_check(menu.icons.is_empty() and menu._text_dx() == 0, "a plain menu has none")
	Game.autoplay = auto


func _settings(ui: GameUI) -> void:
	var gs := Mem.r16(Mem.GS)
	var w := SettingsWindow.new()
	w.dlu = Vector2(163, 232)
	w.dlu_scale = Vector2(2.2, 1.85)
	ui.add_child(w)
	await get_tree().process_frame
	w._on_hit(["bit", Settings.BGM])
	w._on_hit(["msg", 2])
	w._on_hit(["move", 0])
	w._on_hit(["level", 0])
	var level := Mem.r8(Settings.LEVEL_DETAIL)
	w._apply()
	_check(Settings.on(Settings.BGM) != (gs & Settings.BGM != 0), "BGM bit toggled")
	_check(Settings.message_speed() == 2 and Settings.move_speed() == 0, "speeds applied")
	_check(Mem.r8(Settings.LEVEL_DETAIL) == (0 if level != 0 else 1), "升级显示能力成长 applied")
	_check(Settings.dialogue_hold() == (-1.0 if Settings.on(Settings.NO_AUTO_CLOSE) else 2.0), "dialogue hold at 慢")
	_check(is_equal_approx(Settings.cell_time(0), 0.05) and is_equal_approx(Settings.cell_time(1), 0.05), "快 moves a cell a tick")
	w._on_hit(["combo", -1])
	w._on_hit(["skin", 1])
	_check(w.skin == 1, "skin preview")
	await _shot("settings")
	w._saved = true                 # no Niuniu.wa write from the test
	w.close()
	w.queue_free()
	Settings.apply()                # back to the file's options
	_check(Mem.r16(Mem.GS) & 0xf800 == gs & 0xf800, "options restored from the file")


func _history(ui: GameUI) -> void:
	Game.history.clear()
	Game.add_history(3, "12绝招一")
	Game.add_history(1, "5第一章\n第二行")
	Game.add_history(2, "7得到药材")
	Mem.set_ev(4093, 1)
	var w := HistoryWindow.new()
	w._build()
	var t: Array = w.lines.map(func(l: Array) -> String: return str(l[0]))
	_check(t == ["绝招一", "第一章", "第二行", "得到药材"], "按顺序显示 in buffer order %s" % [t])
	Mem.set_ev(4093, 0)
	w._build()
	t = w.lines.map(func(l: Array) -> String: return str(l[0]))
	_check(t == ["第一章", "第二行", "", "得到药材", "", "绝招一", ""], "by category with blank lines %s" % [t])
	w.free()
	Mem.set_ev(4093, 1)
	Game.history.clear()
	for k in 30:
		Game.add_history(1 + k % 4, "%d第%d条记录：历史情报的一行文字" % [k, k])
	var hw := HistoryWindow.new()
	hw.dlu_scale = Vector2.ONE
	hw.dlu = Vector2(376, 408)
	ui.add_child(hw)
	await _shot("history")
	hw.close()
	hw.queue_free()


func _sortie(ui: GameUI) -> void:
	# the builder: max 4, nobody forced (the flag dwords are 0xffff), table[4] = 罗成 first, 管毅 never offered
	Mem.w8(ScriptHost.SORTIE_MAX, 4)
	for k in 5:
		Mem.w32(ScriptHost.SORTIE_FORCED + 4 * k, 0xffff)
	for k in 5:
		Mem.w32(ScriptHost.SORTIE_FLAGS + 4 * k, 0xffff)
	Mem.w32(ScriptHost.SORTIE_FLAGS + 4 * 4, 3)        # arg 11: 尉迟恭 left out
	var host := ScriptHost.new()
	add_child(host)
	Game.autoplay = true
	await host.build_sortie()
	Game.autoplay = false
	var got: Array[int] = []
	for k in 16:
		var v := Mem.r32(0x48b350 + 4 * k)
		if v == 0xffff:
			break
		got.append(v)
	# all nine flag dwords are non-zero (0x4b0a14 = 3), so 管毅 is forced first; then 罗成 (table[4]), 秦琼, 程咬金
	_check(got == [0, 19, 8, 1], "sortie list %s" % [got])
	host.queue_free()
	var cands: Array[int] = [0, 8, 3, 1, 19, 11, 20]
	var w := SortieScreen.new()
	w.cands = cands
	w.forced = 1
	w.most = 5
	w.dlu_scale = Vector2.ONE
	w.dlu = Vector2(626, 466)
	ui.add_child(w)
	await get_tree().process_frame
	_check(not w._can_go(), "决定 needs ⌊2M/3⌋ = 3 chosen")
	w._toggle(1)
	w._toggle(2)
	_check(w._can_go(), "3 chosen is enough")
	w._toggle(0)
	_check(w.slots.has(0), "forced stays")
	w._toggle(1)
	_check(not w.slots.has(1), "a second click takes it out")
	var before := w.order.duplicate()
	w._on_hit(["sort", 1])
	_check(SortieScreen.sort_key == 2, "等级 order")
	w._on_hit(["sort", 1])
	_check(SortieScreen.button_keys[1] == 3 and SortieScreen.sort_key == 3, "the second button cycles to 攻击")
	w._on_hit(["sort", 0])
	_check(SortieScreen.sort_key == 1, "back to 部队属性")
	w._toggle(1)
	w.hover = 1
	await _shot("sortie")
	w.close()
	w.queue_free()
	SortieScreen.sort_key = 1
	SortieScreen.button_keys = [1, 2]
	_check(before.size() == cands.size(), "every candidate has a cell")


func _windows(ui: GameUI) -> void:
	var u := UnitListWindow.new()
	u.dlu = Vector2(387, 177)
	u.dlu_scale = Vector2(1.6, 2.4)
	ui.add_child(u)
	await get_tree().process_frame
	_check(u.lv.rows.size() == Game.party_ids().size(), "town 武将一览 lists the party")
	u._on_hit(["list", -100 - 2])
	var lvl := [] as Array
	for r in u.lv.rows:
		lvl.append(Game.person(int(r["data"])).level)
	var desc := lvl.duplicate()
	desc.sort()
	desc.reverse()
	_check(lvl == desc, "Lv sorts high first")
	await _shot("unitlist")
	u.close()
	u.queue_free()
	Game.add_item(0, 2, 10)
	Game.add_item(0x58, 0, 0)
	var il := ItemListWindow.new()
	il.dlu = Vector2(318, 209)
	il.dlu_scale = Vector2(1.95, 2.0)
	ui.add_child(il)
	await get_tree().process_frame
	_check(il.lists[1].rows.size() >= 1, "consumables tab")
	var rows: Array = [{"id": 3}, {"id": 1}, {"id": 2}, {"id": 1}]
	_check(DlgPanel.sorted_by(rows, func(r: Dictionary) -> int: return int(r["id"])) == [rows[1], rows[3], rows[2], rows[0]],
			"the list sort is stable")
	_check(DlgPanel.sorted_by(rows, func(r: Dictionary) -> int: return int(r["id"]), true) == [rows[0], rows[2], rows[1], rows[3]],
			"reversed too")
	await _shot("itemlist")
	il.close()
	il.queue_free()
	var tw := TerrainWindow.new()
	tw.dlu = Vector2(393, 253)
	tw.dlu_scale = Vector2(1.6, 1.85)
	ui.add_child(tw)
	await get_tree().process_frame
	_check(tw._heads[0] == "地形" and tw._heads[1] == "英雄", "family headers from 0x558100 (%s %s)" % [tw._heads[0], tw._heads[1]])
	_check(tw._cell(0, 0)[0] == "10", "英雄 on 平原: 10")
	# a header click sorts by that column (high first), stably; the same column again reverses it (0x464e1f)
	var before: Array = tw.rows[0].duplicate()
	tw._sort(2)
	var vals: Array = tw.rows[0].map(func(t: int) -> int: return tw._value(1, t))
	var hi := vals.duplicate()
	hi.sort()
	hi.reverse()
	_check(vals == hi and tw.rows[0].size() == before.size(), "terrain: a column sorts high first (%s)" % [vals])
	var ties: Array = tw.rows[0].filter(func(t: int) -> bool: return tw._value(1, t) == vals[0])
	_check(ties == before.filter(func(t: int) -> bool: return ties.has(t)), "terrain: equal values keep their order")
	tw._sort(2)
	vals = tw.rows[0].map(func(t: int) -> int: return tw._value(1, t))
	hi.reverse()
	_check(vals == hi, "terrain: the same column again sorts low first (%s)" % [vals])
	tw._sort(0)
	_check(tw.rows[0] == before, "terrain: the first column restores the terrain order")
	await _shot("terrain")
	tw._on_hit(["tab", 1])
	await _shot("terrain_cost")
	tw.close()
	tw.queue_free()
	Game.scenario = 4
	for k in 15:
		Mem.w8(0x55e9d8 + 3 * k, 2 + k)
		Mem.w8(0x55e9d8 + 3 * k + 1, 10)
		Mem.w8(0x55e9d8 + 3 * k + 2, k % 2)
	SortieMap.open(ui)
	await _shot("sortiemap")
	for c in ui.get_children():
		if c is SortieMap:
			c.close()
	MsgBox.yes_no(ui, "结束所有部队的命令吗？")
	await _shot("msgbox")
	for c in ui.get_children():
		if c is MsgBox:
			c.close()
	# the town takes clicks only while GS+2 ≠ 0 (op 0x08)
	var st := StoryStage.new()
	add_child(st)
	st._waiting_click = true
	Mem.w16(Mem.GS + 2, 0)
	_check(not st.menu_ready(), "GS+2 = 0: no menu")
	Mem.w16(Mem.GS + 2, 1)
	_check(st.menu_ready(), "GS+2 = 1: menu")
	await _panes(ui, st)
	st.queue_free()
	# the menu bar (0x474c59): a town greys the four battle commands (0x4759bc), so they are left out there
	_check(SystemMenu.labels(true) == ["结束回合", "检索未执行部队", "武将一览", "持有道具一览", "地形情报一览", "历史情报",
			"胜利条件", "战场缩小图", "环境设定", "存储进度", "读取进度", "版本情报", "回到标题"], "the battle's menu bar")
	_check(SystemMenu.labels(false) == ["武将一览", "持有道具一览", "地形情报一览", "历史情报", "环境设定", "存储进度",
			"读取进度", "版本情报", "回到标题"], "the town's menu bar")


## The status panes: ops 0x18 / 0x17 keep their texts in memory (0x40bb48 / 0x40bb78), which saves carry (0x41b240)
## and a load puts up again (0x41adc6, 0x42a054); a scene change outside the battle blanks the place pane (0x476882).
func _panes(ui: GameUI, st: StoryStage) -> void:
	var auto := Game.autoplay
	Game.autoplay = true                        # no timed boxes
	st.vm = EexVM.new()
	await st.op_title_text({"args": ["第一章  瓦岗聚义"]})
	await st.op_place_name({"args": ["浮云洲往登州途中  船上\n&x"]})
	_check(ui._strips[0].text == "第一章  瓦岗聚义" and ui._strips[1].text == "浮云洲往登州途中  船上", "panes: the texts show")
	var snap := Mem.snapshot()
	st.op_change_scene({"args": [2, 0, 0, 5, 0]})
	_check(ui._strips[0].text == "第一章  瓦岗聚义" and ui._strips[1].text == "", "panes: a scene change blanks the place")
	Mem.reset()
	ui.clear_strips()
	Mem.restore(snap)
	st.restore_state({"kind": "story", "scene_kind": 2, "scene_image": 5})
	st._apply_restore()
	_check(ui._strips[0].text == "第一章  瓦岗聚义" and ui._strips[1].text == "浮云洲往登州途中  船上",
			"panes: a town save puts both up again")
	st.restore_state({"kind": "story", "scene_kind": 1, "scene_image": 5})
	st._apply_restore()
	_check(ui._strips[0].text == "第一章  瓦岗聚义" and ui._strips[1].text == "", "panes: a scene save only the title")
	Game.autoplay = auto
