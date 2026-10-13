class_name InputBot
extends Node
## Debug: drives the player phase through real input events (mouse clicks / ui_accept) and saves
## screenshots, to exercise BattleInput exactly as a human would. Enabled with WG_INPUTBOT=dir.

var st: BattleStage
var shot_dir := ""
var shots := 0


func _init(stage: BattleStage, dir: String) -> void:
	st = stage
	shot_dir = dir
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)


func shot(tag: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	shots += 1
	img.save_png("%s/%03d_%s.png" % [shot_dir, shots, tag])


func _click_cell(c: Vector2i, button := MOUSE_BUTTON_LEFT) -> void:
	await st.view.center_on(c, false)
	await get_tree().process_frame
	var vp := st.view.cell_center(c) - st.view.camera.position
	# synthetic events are in window coordinates: apply the viewport → window (stretch) transform
	var sp := get_viewport().get_screen_transform() * vp
	var mv := InputEventMouseMotion.new()
	mv.position = sp
	Input.parse_input_event(mv)
	await get_tree().process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = sp
		ev.global_position = sp
		Input.parse_input_event(ev)
		await get_tree().process_frame


## Tap a point of the 640x480 game screen like a finger: press and release, no hover before.
func _tap(p: Vector2) -> void:
	var sp := get_viewport().get_screen_transform() * p
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = sp
		ev.global_position = sp
		Input.parse_input_event(ev)
		await get_tree().process_frame


## A screen point off `box` whose map cell is none of `cells` (an Array of cells or a Dictionary keyed by cell):
## somewhere to tap "nothing".
func _empty_point(box: Rect2, cells: Variant) -> Vector2:
	for p in [Vector2(30, 100), Vector2(610, 100), Vector2(30, 250), Vector2(610, 250), Vector2(320, 90)]:
		if not box.has_point(p) and not cells.has(st.view.cell_at(st.view.camera.position + p)):
			return p
	return Vector2(30, 100)


## A real Esc key press (the map takes key events only, not synthetic actions): the system menu.
func _esc() -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = KEY_ESCAPE
		k.physical_keycode = KEY_ESCAPE
		k.pressed = pressed
		Input.parse_input_event(k)
		for f in 3:
			await get_tree().process_frame


func _key(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	for k in 4:
		await get_tree().process_frame
	ev = InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)
	await get_tree().process_frame


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func fx_test(ids: PackedStringArray) -> void:
	await _wait(0.6)
	var u := st.input._player_units()[0]
	var headless := DisplayServer.get_name() == "headless" or shot_dir == ""
	for sid in ids:
		var s := int(sid)
		var target: BUnit = null
		for e in st.units:
			if e.active() and e.is_enemy_of(u):
				target = e
				break
		if target == null:
			return
		u.mp = 255
		# what each target had before (printed with the outcome)
		var before := {}
		for t in st.actions.strategy_targets(u, s, target.pos):
			before[t.slot] = [t.hp, t.status, [t.buff(0), t.buff(1), t.buff(2), t.buff(3), t.buff(4)]]
		var done := [false]      # lambdas capture locals by value: share a reference instead
		var cast := func() -> void:
			await st.actions.cast(u, s, target.pos)
			done[0] = true
		cast.call()
		if not headless:
			for k in 6:
				await _wait(0.25)
				await shot("fx%d_%d" % [s, k])
		while not done[0]:
			await _wait(0.3)
			await _key("ui_accept")
		for slot in before:
			var t := st.units[slot]
			print("FXTEST s=%d slot %d %s: hp %d→%d status %d→%d buffs %s→%s" % [s, slot, "enemy" if t.is_enemy_of(u) else "own", before[slot][0], t.hp, before[slot][1], t.status, before[slot][2], [t.buff(0), t.buff(1), t.buff(2), t.buff(3), t.buff(4)]])
	st.get_tree().quit()


## WG_BOTMODE=touchcancel (run in the touch shell): taps on empty places cancel — outside the command menu (undoes
## the move), outside the attack range, outside the move range, outside the system menu (opened by 菜单).
## Prints "TOUCHCANCEL: PASS", and writes the lines to touchcancel.txt in the bot's folder (an iOS app's prints
## don't reach a log).
func touch_cancel_test() -> void:
	Game.set_meta("bot_owns_input", true)      # stops WG_ACCEPT_SPAM, which would pick menu entries
	await _wait(1.0)
	var ok := [true]
	var lines: Array[String] = []
	var expect := func(cond: bool, what: String) -> void:
		lines.append("TOUCHCANCEL %s: %s" % ["ok" if cond else "FAIL", what])
		print(lines[-1])
		ok[0] = ok[0] and cond
	var u: BUnit = null
	for x in st.input._player_units():
		if x.active() and not x.acted:
			u = x
			break
	expect.call(u != null and st.input.idle, "player phase at its top level")
	if u == null:
		st.get_tree().quit()
		return
	var orig := u.pos
	var reach := st.actions.reachable(u)
	# move next to the nearest enemy if possible (so 攻击 is available), like run_phase
	var dest := orig
	var best := 1 << 30
	for e in st.units:
		if e.active() and e.is_enemy_of(u):
			for c in reach:
				var d := Grid.manhattan(c, e.pos)
				if d >= 1 and d < best and c != orig:
					best = d
					dest = c
	await _click_cell(orig)
	await _wait(0.4)
	await _click_cell(dest)
	await _wait(0.9)
	expect.call(st.ui.menu._active, "command menu open after moving")
	await _tap(_empty_point(st.ui.menu._rect, []))
	await _wait(0.5)
	expect.call(not st.ui.menu._active and u.pos == orig, "a tap outside the command menu undoes the move")
	await _click_cell(dest)
	await _wait(0.9)
	if not st.actions.attackable_targets(u, u.pos).is_empty():
		await _key("ui_accept")
		await _wait(0.4)
		var cells: Array = st.actions.attack_cells(u, u.pos)
		cells.append(u.pos)
		await _tap(_empty_point(Rect2(), cells))
		await _wait(0.5)
		expect.call(st.ui.menu._active, "a tap outside the attack range goes back to the command menu")
	else:
		print("TOUCHCANCEL: no enemy in reach, attack-range check skipped")
	await _tap(_empty_point(st.ui.menu._rect, []))
	await _wait(0.5)
	expect.call(u.pos == orig and not st.input.idle, "undone again, unit still selected")
	await _tap(_empty_point(Rect2(), reach))
	await _wait(0.5)
	expect.call(st.input.idle, "a tap outside the move range drops the selection")
	Game.shell._activate(TouchShell.MENU)
	await _wait(0.5)
	expect.call(st.ui.menu._active, "菜单 opens the system menu")
	await _tap(_empty_point(st.ui.menu._rect, []))
	await _wait(0.5)
	expect.call(not st.ui.menu._active and st.input.idle, "a tap outside the system menu closes it")
	lines.append("TOUCHCANCEL: PASS" if ok[0] else "TOUCHCANCEL: FAILED")
	print(lines[-1])
	var f := FileAccess.open(shot_dir.path_join("touchcancel.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	st.get_tree().quit()


## Hold a finger (the left button) on a point of the 640x480 game screen for t seconds.
func _hold(p: Vector2, t: float) -> void:
	var sp := get_viewport().get_screen_transform() * p
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.position = sp
		ev.global_position = sp
		Input.parse_input_event(ev)
		if pressed:
			await _wait(t)
		await get_tree().process_frame


func _info_window() -> InfoWindow:
	for c in st.ui.get_children():
		if c is InfoWindow and not c.is_queued_for_deletion():
			return c
	return null


## WG_BOTMODE=info: 武将情报 in a battle. A right click on an own unit and on an enemy (a long press in the touch
## shell) opens it with that group's list; its tabs and 下一武将 work; Esc closes it; Esc on the map and a right
## click on an empty cell open the system menu instead. Prints "INFOBOT: PASS" (also infobot.txt in the bot folder).
func info_test() -> void:
	Game.set_meta("bot_owns_input", true)
	await _wait(1.0)
	var ok := [true]
	var lines: Array[String] = []
	var expect := func(cond: bool, what: String) -> void:
		lines.append("INFOBOT %s: %s" % ["ok" if cond else "FAIL", what])
		print(lines[-1])
		ok[0] = ok[0] and cond
	var own: BUnit = st.input._player_units()[0] if not st.input._player_units().is_empty() else null
	var foe: BUnit = null
	for e in st.units:
		if e.active() and own and e.is_enemy_of(own):
			foe = e
			break
	expect.call(own != null and foe != null and st.input.idle, "player phase with an own unit and an enemy")
	if own == null or foe == null:
		st.get_tree().quit()
		return
	for u in [own, foe]:
		if Game.touch:
			await st.view.center_on(u.pos, false)
			await get_tree().process_frame
			await _hold(st.view.cell_center(u.pos) - st.view.camera.position, GameUI.LONG_PRESS + 0.3)
		else:
			await _click_cell(u.pos, MOUSE_BUTTON_RIGHT)
		await _wait(0.5)
		var w := _info_window()
		var who := "own unit" if u == own else "enemy"
		expect.call(w != null and w.pids[w.idx] == u.pid, "%s: 武将情报 shows %s" % [who, u.person.name])
		if w == null:
			continue
		var group: Array = InfoWindow.battle_list(st, u)
		expect.call(w.pids == group, "%s: the list is its group (%d)" % [who, group.size()])
		await shot("info_%s" % ("own" if u == own else "enemy"))
		for t in [3, 1]:
			for h in w._hits:
				if typeof(h[1]) == TYPE_STRING and h[1] == "tab%d" % t:
					await _tap((h[0] as Rect2).get_center())
			await _wait(0.3)
			expect.call(InfoWindow.tab == t, "%s: tab %d by a tap" % [who, t])
		await shot("info_%s_tab" % ("own" if u == own else "enemy"))
		await _key("ui_cancel")
		await _wait(0.4)
		expect.call(_info_window() == null and st.input.idle, "%s: Esc closes it" % who)
	await _esc()
	await _wait(0.4)
	expect.call(st.ui.menu._active and _info_window() == null, "Esc on the map opens the system menu")
	await _key("ui_cancel")
	await _wait(0.4)
	if not Game.touch:
		var empty := own.pos
		for c in st.actions.reachable(own):
			if st.unit_at(c) == null:
				empty = c
				break
		await _click_cell(empty, MOUSE_BUTTON_RIGHT)
		await _wait(0.4)
		expect.call(st.ui.menu._active and _info_window() == null, "a right click on an empty cell opens the system menu")
		await _key("ui_cancel")
		await _wait(0.4)
	expect.call(st.input.idle and not st.ui.menu._active, "back at the top level")
	lines.append("INFOBOT: PASS" if ok[0] else "INFOBOT: FAILED")
	print(lines[-1])
	var f := FileAccess.open(shot_dir.path_join("infobot.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	st.get_tree().quit()


## WG_BOTMODE=victory: open the system menu, pick 胜利条件 and screenshot the window.
func victory_test() -> void:
	Game.set_meta("bot_owns_input", true)      # stops WG_ACCEPT_SPAM
	await _wait(1.0)
	await _esc()      # Esc opens the system menu (a right click on a unit opens 武将情报)
	await _wait(0.4)
	for k in SystemMenu.labels(true).find("胜利条件"):
		await _key("ui_down")
	await _key("ui_accept")
	await _wait(2.0)                           # let the text type out
	await shot("victory")
	print("== bot: victory window shown")
	st.get_tree().quit()


## WG_BOTMODE=duel: run a scripted 单挑 between the first player unit and the first enemy, with screenshots.
func duel_test() -> void:
	await _wait(0.6)
	var a: BUnit = st.input._player_units()[0]
	var b: BUnit = null
	for e in st.units:
		if e.active() and e.is_enemy_of(a):
			b = e
			break
	var d := st._duel()
	await d.setup(b.pid, a.pid, 5)
	await shot("duel_setup")
	await d.open()
	await d.appear_say(0, "来者何人！", 0)
	await shot("duel_say")
	await d.appear_say(1, "敌将报上名来！\n太爷手下不死无名之鬼！", 0)
	await shot("duel_both")
	await d.action(1, 3)
	await d.exchange(0, 1, 0)
	await shot("duel_exchange")
	await d.result(0)
	await shot("duel_result")
	st.get_tree().quit()


## WG_BOTMODE=special: 管毅, with a full MP bar, walks next to an enemy and uses his 绝招 from the command menu
## (screenshots of the menu, the banner over the darkened field and the result). Prints "SPECIALBOT: PASS".
func special_test() -> void:
	Game.set_meta("bot_owns_input", true)      # stops WG_ACCEPT_SPAM
	await _wait(1.0)
	var u := st.unit_by_pid(0)
	u.mp = u.max_mp()
	var reach := st.actions.reachable(u)
	var dest := Vector2i(-1, -1)
	var target: BUnit = null
	for e in st.units:
		if e.active() and e.is_enemy_of(u):
			for d in Grid.DIRS:
				if reach.has(e.pos + d) and dest.x < 0:
					dest = e.pos + d
					target = e
	if target == null:
		print("SPECIALBOT: FAIL no enemy in reach")
		st.get_tree().quit()
		return
	var hp0 := target.hp
	await _click_cell(u.pos)
	await _wait(0.4)
	await _click_cell(dest)
	await _wait(0.9)
	await shot("menu")
	await _key("ui_down")                      # 攻击 → 绝招
	await _key("ui_accept")
	await _wait(0.4)
	await shot("pick")
	await _click_cell(target.pos)
	for k in 8:
		await _wait(0.2)
		await shot("special_%d" % k)
	while not u.acted:
		await _wait(0.3)
		await _key("ui_accept")                # click through the shout
	await _wait(0.5)
	await shot("after")
	var ok := u.mp == 0 and target.hp < hp0 and u.buff(0) == 6
	print("SPECIALBOT: %s (MP %d, target HP %d → %d, 攻击 buff %d)" % ["PASS" if ok else "FAIL", u.mp, hp0, target.hp, u.buff(0)])
	st.get_tree().quit()


## WG_BOTMODE=load: open the system menu, pick 读取进度 and load slot WG_BOTSLOT (default 9),
## exercising an in-game load from inside the running battle.
func load_test() -> void:
	await _wait(0.6)
	await _esc()      # Esc opens the system menu (a right click on a unit opens 武将情报)
	await _wait(0.4)
	await shot("sysmenu")
	for k in SystemMenu.labels(true).find("读取进度"):
		await _key("ui_down")
	await _key("ui_accept")
	await _wait(0.4)
	var slot := int(OS.get_environment("WG_BOTSLOT")) if OS.get_environment("WG_BOTSLOT") != "" else 9
	for k in slot:
		await _key("ui_down")
	await shot("loadmenu")
	print("== bot: loading slot %d" % slot)
	await _key("ui_accept")


func run_phase() -> void:
	var fx := OS.get_environment("WG_FXTEST")
	if fx != "":
		await fx_test(fx.split(","))
		return
	if OS.get_environment("WG_BOTMODE") == "load":
		await load_test()
		return
	if OS.get_environment("WG_BOTMODE") == "duel":
		await duel_test()
		return
	if OS.get_environment("WG_BOTMODE") == "touchcancel":
		await touch_cancel_test()
		return
	if OS.get_environment("WG_BOTMODE") == "victory":
		await victory_test()
		return
	if OS.get_environment("WG_BOTMODE") == "info":
		await info_test()
		return
	if OS.get_environment("WG_BOTMODE") == "special":
		await special_test()
		return
	await _wait(0.6)
	for u in st.input._player_units():
		if not u.active() or u.acted:
			continue
		await _click_cell(u.pos)
		await _wait(0.4)
		await shot("select_%s" % u.person.name)
		# choose destination: the reachable cell closest to the nearest enemy
		var reach := st.actions.reachable(u)
		var target: BUnit = null
		var bd := 1 << 30
		for e in st.units:
			if e.active() and e.is_enemy_of(u):
				var d := Grid.manhattan(e.pos, u.pos)
				if d < bd:
					bd = d
					target = e
		var dest := u.pos
		if target:
			var best := 1 << 30
			for c in reach:
				var d2 := Grid.manhattan(c, target.pos)
				if d2 >= 1 and d2 < best:
					best = d2
					dest = c
		await _click_cell(dest)
		await _wait(0.9)
		await shot("menu_%s" % u.person.name)
		# first enabled menu entry: 攻击 if possible, else 待命 (via ui_down skipping disabled ones)
		var can_attack := not st.actions.attackable_targets(u, u.pos).is_empty()
		if can_attack:
			await _key("ui_accept")
			await _wait(0.4)
			await shot("attackrange_%s" % u.person.name)
			var tg := st.actions.attackable_targets(u, u.pos)
			await _click_cell(tg[0].pos)
			await _wait(4.0)
			await shot("attacked_%s" % u.person.name)
		else:
			# menu starts on the first enabled item; one step up wraps to 待命 (last)
			await _key("ui_up")
			await _key("ui_accept")
			await _wait(0.4)
	# end turn via system menu (opened by Esc, or in the touch shell by its 菜单 button)
	if Game.shell:
		await _wait(0.2)                  # the shell sees the top level on its next frame
		Game.shell._activate(TouchShell.MENU)
	else:
		await _esc()
	await _wait(0.5)
	await shot("sysmenu")
	await _key("ui_accept")       # 结束回合
	await _wait(0.4)
	await _key("ui_accept")       # 是 to "结束所有部队的命令吗？"
