extends Node
## Battle rules the scripts can see (docs/mod_patches.md group 1): EV[10] and the removal of fallen units after a
## command (0x44cc03), the 暗杀 countdown, fire (op 0x21) and its undo (op 0x58 alt ≠ 0), script attr 8, op 0x3b
## in a battle, the AI's score for the extra targets of an area attack (0x438d96), the 史录 write rules. Prints
## "t_battle: PASS".

var _ok := true


func _check(ok: bool, what: String) -> void:
	if not ok:
		_ok = false
		print("t_battle: FAIL ", what)


func _unit(slot: int, pid: int, colour: int, pos: Vector2i) -> BUnit:
	var u := BUnit.at(slot)
	u.clear(slot)
	u.pid = pid
	u.colour = colour
	u.mode = 7 if slot < 15 else 1
	u.state = BUnit.STATE_ON_MAP
	u.pos = pos
	u.hp = u.max_hp()
	u.mp = u.max_mp()
	return u


func run() -> void:
	Game.new_game_state()
	Game.autoplay = true          # no waiting for clicks or animations
	var ui := GameUI.new()
	var gs := GDScript.new()      # stand-in for main.gd (ScriptHost reads Game.main.ui)
	gs.source_code = "extends Node\nvar ui\nvar stage\n"
	gs.reload()
	var m := Node.new()
	m.set_script(gs)
	var old_main = Game.main
	Game.main = m
	add_child(m)
	m.set("ui", ui)
	add_child(ui)
	var st := BattleStage.new()
	m.set("stage", st)
	add_child(st)
	await get_tree().process_frame

	# ---- scene mode: a battle file counts as a battle only from change_scene 3 on (0x40b922)
	Mem.w8(0x4ac63c, 2)
	_check(not st.in_battle(), "story mode before the battlefield")
	Mem.set_ev(10, 15)
	await st.op_change_scene({"args": [3, 0xffff, 0xffff, 0xffff, 0]})
	_check(st.in_battle(), "battle mode after change_scene 3")
	_check(Mem.ev(10) == 0, "EV[10] = 0 at battle start (0x44ccc8)")

	# ---- op 0x21: mode 0 sets fire (terrain 0x1a, mark 0), mode 1 puts it out
	var c := Vector2i(5, 5)
	var t0 := st.view.terrain_at(c)
	await st.op_map_mark({"args": [c.x, c.y, 0, 0, 0]})
	_check(st.view.terrain_at(c) == 0x1a and st.view.marks.has(c), "op 0x21 mode 0 sets fire")
	await st.op_map_mark({"args": [c.x, c.y, 1, 0, 0]})
	_check(st.view.terrain_at(c) == t0 and not st.view.marks.has(c), "op 0x21 mode 1 puts it out")
	_check(st.terrain_changes.is_empty(), "the record is freed")
	# ---- op 0x58 alt ≠ 0: undo of the recorded (x, y, patch) change; with scroll and no record the terrain stays
	var c2 := Vector2i(6, 6)
	var t2 := st.view.terrain_at(c2)
	await st.op_op_58({"args": [2, 0, 0x1a, c2.x, c2.y, 0, 0]})
	_check(st.view.terrain_at(c2) == 0x1a, "op 0x58 alt 0 changes the terrain")
	await st.op_op_58({"args": [2, 1, 0, c2.x, c2.y, 1, 1]})
	_check(st.view.terrain_at(c2) == t2 and not st.view.marks.has(c2), "op 0x58 alt 1 undoes it")
	var c3 := Vector2i(7, 7)
	await st.op_op_58({"args": [2, 1, 3, c3.x, c3.y, 1, 1]})
	_check(st.view.terrain_at(c3) == 3, "op 0x58 alt 1 with nothing recorded keeps the written terrain")

	# ---- a unit that falls in a command stays at HP 0 until remove_dead (0x44cc03); EV[10] = 1
	var a := _unit(0, 0, 0, Vector2i(2, 2))
	var d := _unit(35, 300, 2, Vector2i(3, 2))
	Mem.set_ev(10, 0)
	await st.actions.unit_fell(d)
	_check(Mem.ev(10) == 1, "EV[10] = 1 when a unit falls")
	_check(d.state == BUnit.STATE_ON_MAP and d.hp == 0 and not d.active(), "fallen unit waits on the map")
	await st.remove_dead()
	_check(d.state == 3, "remove_dead takes it off the map")
	# a script kill (0x4121b0) removes at once
	var e := _unit(36, 301, 2, Vector2i(4, 2))
	Mem.set_ev(10, 0)
	await st.actions.unit_defeated(e)
	_check(e.state == 3 and Mem.ev(10) == 1, "script kill: removed at once, EV[10] = 1")
	# AIAct resets EV[10] (0x43ad2b)
	await st.ai.act(_unit(37, 302, 2, Vector2i(9, 9)))
	_check(Mem.ev(10) == 0, "AIAct start resets EV[10]")

	# ---- 暗杀 countdown (0x40937f): two phase starts, then HP 1 and EV[10] = 1
	var tg := _unit(38, 303, 2, Vector2i(10, 2))
	Mem.w8(BattleStage.ASSASSIN_MARK + 38, 2)
	Mem.w8(BattleStage.ASSASSIN_LINK + 38, 0)
	Mem.set_ev(10, 0)
	await st._assassination_countdown(35, 115)
	_check(Mem.r8(BattleStage.ASSASSIN_MARK + 38) == 1 and tg.hp == tg.max_hp(), "first phase start: mark 1")
	await st._assassination_countdown(35, 115)
	_check(tg.hp == 1 and Mem.ev(10) == 1 and Mem.r8(BattleStage.ASSASSIN_LINK + 38) == 0xff, "second: HP 1, EV[10]")
	_check(tg.state == BUnit.STATE_ON_MAP, "the assassinated unit stays (the scripts retreat officers)")
	# the assassin leaving cancels its marks (0x4dbff3)
	var tg2 := _unit(39, 304, 2, Vector2i(11, 2))
	Mem.w8(BattleStage.ASSASSIN_MARK + 39, 1)
	Mem.w8(BattleStage.ASSASSIN_LINK + 39, 1)
	var killer := _unit(1, 1, 0, Vector2i(12, 2))
	await st.remove_unit(killer, true)
	_check(Mem.r8(BattleStage.ASSASSIN_LINK + 39) == 0xff, "assassin gone: mark cancelled")
	await st._assassination_countdown(35, 115)
	_check(tg2.hp == tg2.max_hp(), "a cancelled mark does nothing")

	# ---- script attr 8 = battle-unit MP (mod 0x406f01 / 0x406fc0)
	var mu := _unit(2, 2, 0, Vector2i(13, 2))
	await BattleAttrs.set_attr(st, 2, 8, 0, 3)
	_check(mu.mp == mini(3, mu.max_mp()), "attr 8 op 0 sets MP")
	await BattleAttrs.set_attr(st, 2, 8, 1, 500)
	_check(mu.mp == mu.max_mp(), "attr 8 op 1 adds, capped")
	await BattleAttrs.set_attr(st, 2, 8, 2, 1)
	_check(mu.mp == 0 and BattleAttrs.get_attr(st, 2, 8) == 0, "attr 8 op 2 → 0, reads as 0")

	# ---- op 0x3b does nothing in a battle (0x4149be)
	var pid := 140
	Mem.w8(Game.person(pid).base + 0x2a, 0xff)
	await st.op_join({"args": [pid, 1, 0]})
	_check(not Game.is_member(pid), "join ignored in a battle")
	Mem.w8(0x4ac63c, 2)
	await st.op_join({"args": [pid, 1, 0]})
	_check(Game.is_member(pid), "join works outside the battlefield")
	Mem.w8(0x4ac63c, 3)

	# ---- AI PhysScore (0x438a20 → 0x438d96): an area attack adds 10 / 4 per other unit hit, −4 when none
	var base := Vector2i(3, st.view.map_h - 4)
	Game.person(50).cls = 0                # 游侠: counters only on the 4 cells beside it
	var at := _unit(5, 50, 0, base)
	var nb := _unit(6, 51, 0, base + Vector2i(0, 1))
	var ua: BUnit = null
	Game.person(306).cls = 17              # 无影剑: range 3..5, area code 1 (the target's 4 neighbours)
	for off in [Vector2i(-3, 0), Vector2i(0, -3), Vector2i(3, 0)]:
		var cand := _unit(40, 306, 2, base + off)
		if st.actions.can_attack(cand, at) and not st.actions.can_attack(at, cand, at.pos):
			ua = cand
			break
	_check(ua != null, "a cell to attack from without a counter")
	if ua:
		st.ai.u = ua
		_check(st.actions.area_code(ua) == 1, "class 17 has area code 1")
		var code := Mem.r8(0x409191 + 17)
		Mem.w8(0x409191 + 17, 0)
		var s0 := st.ai._phys_score(at, ua.pos)
		Mem.w8(0x409191 + 17, code)
		var dn := Rules.calc_damage(ua, nb, st.view.terrain_at(ua.pos), st.view.terrain_at(nb.pos), false, 0)
		var bonus := 10 if dn >= nb.hp else (4 if dn * 10 / maxi(nb.max_hp(), 1) >= 1 else 0)
		_check(st.ai._phys_score(at, ua.pos) == s0 + bonus, "the neighbour adds %d" % bonus)
		nb.state = 0
		BUnit.gen += 1
		_check(st.ai._phys_score(at, ua.pos) == (s0 - 4 if s0 > 4 else 0), "nobody else hit: −4")
		ua.state = 0
	at.state = 0
	BUnit.gen += 1

	# ---- 史录 (0x413adc / 0x4d1679)
	Game.history.clear()
	Game.add_history(1, "12甲")
	Game.add_history(1, "12甲")
	_check(Game.history.size() == 2, "appends are not de-duplicated")
	Game.add_history(0xff, "12乙")
	_check(str(Game.history[0]["text"]) == "乙" and int(Game.history[0]["cat"]) == 1, "0xff replaces the first match")
	Game.add_history(0xff, "13丙")
	_check(Game.history.size() == 2, "0xff without a match adds nothing")
	Game.add_history(0xff, "12")
	_check(Game.history.size() == 1 and str(Game.history[0]["text"]) == "甲", "0xff with only the number deletes")

	Game.main = old_main
	print("t_battle: PASS" if _ok else "t_battle: FAILED")
