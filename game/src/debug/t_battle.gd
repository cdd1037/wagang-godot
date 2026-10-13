extends Node
## Battle rules the scripts can see (docs/mod_patches.md group 1): EV[10] and the removal of fallen units after a
## command (0x44cc03), the 暗杀 countdown, fire (op 0x21) and its undo (op 0x58 alt ≠ 0), script attr 8, op 0x3b
## in a battle, the AI's score for the extra targets of an area attack (0x438d96), the default defeat (op 0x43,
## 0x44c74d), the 史录 write rules. Prints "t_battle: PASS".

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


func _ins(name: String, args: Array, op := 0x40) -> Dictionary:
	return {"op": op, "name": name, "args": args}


func _sec(title: String, conds: Array, body: Array) -> Dictionary:
	return {"title": title, "conditions": conds + [_ins("end", [], 0)], "body": body + [_ins("end", [], 0)]}


## 0x44c601: a checkpoint polls until every qualifying section has run; op 0x0c in a one-section scene keeps the
## scene (0x4105a8 status 8 → 5); 0x45965d: a battle line needs the speaker's unit on the map.
func _script_flow(st: BattleStage) -> void:
	var old_vm: EexVM = st.vm
	var vm := EexVM.new()
	vm.host = st
	vm.data = {"scenes": [{"sections": []}, {"sections": [
		_sec("A", [_ins("test_flags", [[], [901]])], [_ins("set_flag", [901, 1])]),
		_sec("B", [_ins("test_flags", [[], [902]])], [_ins("set_flag", [902, 1])]),
		_sec("C", [_ins("test_flags", [[903], []])], [_ins("set_flag", [904, 1])])]}]}
	vm.active = true
	vm.scene = 1
	st.vm = vm
	for f in [901, 902, 903, 904]:
		Mem.set_flag(f, false)
	await st.checkpoint()
	_check(Mem.flag(901) and Mem.flag(902) and not Mem.flag(904), "one checkpoint runs both qualifying sections")
	# exit_section in a one-section scene: the scene stays and the section runs again at the next poll
	var vm2 := EexVM.new()
	vm2.host = st
	vm2.data = {"scenes": [{"sections": [_sec("draw", [], [_ins("int_var_op", [2, 600, 0, 0, 1]),
			_ins("exit_section", [], 0x0c), _ins("set_flag", [905, 1])])]}, {"sections": [_sec("next", [], [])]}]}
	vm2.active = true
	vm2.scene = 0
	Mem.set_ev(600, 0)
	Mem.set_flag(905, false)
	await vm2.poll()
	_check(vm2.scene == 0 and Mem.ev(600) == 1 and not Mem.flag(905), "exit_section keeps a one-section scene (%d)" % vm2.scene)
	await vm2.poll()
	_check(vm2.scene == 0 and Mem.ev(600) == 2, "and the next poll runs it again")
	st.vm = old_vm
	# battle lines: only with the speaker's unit on the map
	var sp := _unit(42, 306, 2, Vector2i(8, 8))
	_check(st.speaks_now(306), "speaker on the map talks")
	sp.state = 3
	_check(not st.speaks_now(306), "a removed speaker is silent")
	_check(not st.speaks_now(307), "a speaker without a unit is silent")


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
	# the minimap is a window above the map and the HUD, under the dialogue, menus and message boxes
	st.minimap.open()
	_check(st.minimap.visible and st.minimap.get_index() > st.hud.get_index() and st.minimap.get_index() < ui.dialog.get_index()
			and st.minimap.get_index() < ui.menu.get_index(), "minimap layer %d (HUD %d, dialogue %d)" % [st.minimap.get_index(),
			st.hud.get_index(), ui.dialog.get_index()])
	st.minimap.open()
	_check(st.minimap.get_index() == ui.dialog.get_index() - 1, "opening it again keeps it under the dialogue")
	st.minimap.visible = false

	# ---- op 0x21: mode 0 sets fire (terrain 0x1a, mark 0), mode 1 puts it out
	var c := Vector2i(5, 5)
	var t0 := st.view.terrain_at(c)
	await st.field_ops.op_map_mark({"args": [c.x, c.y, 0, 0, 0]})
	_check(st.view.terrain_at(c) == 0x1a and st.view.marks.has(c), "op 0x21 mode 0 sets fire")
	await st.field_ops.op_map_mark({"args": [c.x, c.y, 1, 0, 0]})
	_check(st.view.terrain_at(c) == t0 and not st.view.marks.has(c), "op 0x21 mode 1 puts it out")
	_check(st.terrain_changes.is_empty(), "the record is freed")
	# ---- op 0x58 alt ≠ 0: undo of the recorded (x, y, patch) change; with scroll and no record the terrain stays
	var c2 := Vector2i(6, 6)
	var t2 := st.view.terrain_at(c2)
	await st.field_ops.op_op_58({"args": [2, 0, 0x1a, c2.x, c2.y, 0, 0]})
	_check(st.view.terrain_at(c2) == 0x1a, "op 0x58 alt 0 changes the terrain")
	await st.field_ops.op_op_58({"args": [2, 1, 0, c2.x, c2.y, 1, 1]})
	_check(st.view.terrain_at(c2) == t2 and not st.view.marks.has(c2), "op 0x58 alt 1 undoes it")
	var c3 := Vector2i(7, 7)
	await st.field_ops.op_op_58({"args": [2, 1, 3, c3.x, c3.y, 1, 1]})
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
	# op 0x78 writing field 33 (unit HP) runs 0x4d678c: HP 0 or less (signed) is a script kill, a read is not
	var f := _unit(39, 303, 2, Vector2i(4, 4))
	Mem.set_ev(10, 0)
	Mem.set_ev(500, 0)
	await st.op_data_transfer({"args": [500, 0, 303, 33]})
	_check(f.state == BUnit.STATE_ON_MAP and Mem.ev(10) == 0, "op 0x78 read of field 33 changes nothing")
	Mem.set_ev(500, 0)
	await st.op_data_transfer({"args": [500, 1, 303, 33]})
	_check(f.state == 3 and Mem.ev(10) == 1, "op 0x78 HP 0 write: removed, EV[10] = 1 (state %d)" % f.state)
	var f2 := _unit(40, 304, 2, Vector2i(5, 4))
	Mem.set_ev(10, 0)
	Mem.set_ev(500, -5)
	await st.op_data_transfer({"args": [500, 1, 304, 33]})
	_check(f2.state == 3 and Mem.ev(10) == 1, "op 0x78 negative HP write: removed")
	var f3 := _unit(41, 305, 2, Vector2i(6, 4))
	Mem.set_ev(10, 0)
	Mem.set_ev(500, 7)
	await st.op_data_transfer({"args": [500, 1, 305, 33]})
	_check(f3.state == BUnit.STATE_ON_MAP and f3.hp == 7 and Mem.ev(10) == 0, "op 0x78 HP 7 write: stays")
	await _script_flow(st)
	# AIAct resets EV[10] (0x43ad2b)
	await st.ai.act(_unit(37, 302, 2, Vector2i(9, 9)))
	_check(Mem.ev(10) == 0, "AIAct start resets EV[10]")

	# ---- 暗杀 countdown (0x40937f): two phase starts, then HP 1 and EV[10] = 1
	var tg := _unit(38, 303, 2, Vector2i(10, 2))
	Mem.w8(BattleStage.ASSASSIN_MARK + 38, 2)
	Mem.w8(BattleStage.ASSASSIN_LINK + 38, 0)
	Mem.set_ev(10, 0)
	await st.phase_fx._assassination_countdown(35, 115)
	_check(Mem.r8(BattleStage.ASSASSIN_MARK + 38) == 1 and tg.hp == tg.max_hp(), "first phase start: mark 1")
	await st.phase_fx._assassination_countdown(35, 115)
	_check(tg.hp == 1 and Mem.ev(10) == 1 and Mem.r8(BattleStage.ASSASSIN_LINK + 38) == 0xff, "second: HP 1, EV[10]")
	_check(tg.state == BUnit.STATE_ON_MAP, "the assassinated unit stays (the scripts retreat officers)")
	# the assassin leaving cancels its marks (0x4dbff3)
	var tg2 := _unit(39, 304, 2, Vector2i(11, 2))
	Mem.w8(BattleStage.ASSASSIN_MARK + 39, 1)
	Mem.w8(BattleStage.ASSASSIN_LINK + 39, 1)
	var killer := _unit(1, 1, 0, Vector2i(12, 2))
	await st.unit_ops.remove_unit(killer, true)
	_check(Mem.r8(BattleStage.ASSASSIN_LINK + 39) == 0xff, "assassin gone: mark cancelled")
	await st.phase_fx._assassination_countdown(35, 115)
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
	await _strat_scores(st)

	# ---- op 0x43 (0x44c74d): with 管毅 in unit 0, units 0..15 in state 1 / 2 count, whatever their HP
	for i in 115:
		BUnit.at(i).clear(i)
	BUnit.gen += 1
	st.field_ready = true
	st.turn_limit = 0
	st.leader_pid = -1
	var g := _unit(0, 0, 0, Vector2i(2, 2))
	g.state = 0                                # S_11 opens with our side not yet on the field
	var al := _unit(15, 474, 1, Vector2i(4, 2))
	_check(not st.op_test_event6({}), "an ally in slot 15 keeps the battle going")
	al.state = 0
	_check(st.op_test_event6({}), "nobody in units 0..15: lost")
	g.state = BUnit.STATE_HIDDEN
	g.hp = 0
	_check(not st.op_test_event6({}), "a hidden unit counts, whatever its HP")
	al.state = 3
	st.leader_pid = 474
	_check(st.op_test_event6({}), "the protected leader in state 3: lost")
	st.leader_pid = -1
	g.pid = 2                                  # unit 0 is not 管毅: colour-0 units on the map count
	_check(st.op_test_event6({}), "no colour-0 unit on the map: lost")
	_unit(40, 5, 0, Vector2i(6, 2))
	_check(not st.op_test_event6({}), "a colour-0 unit in any slot keeps it going")
	# op 0x42 (0x44c658): the boss among units 35..115 in state 3 / 4, or no enemy colour on the map
	var en := _unit(36, 310, 2, Vector2i(8, 2))
	st.boss_pid = 311
	_check(not st.op_test_event5({}), "a boss not on the field is no victory")
	var bo := _unit(37, 311, 2, Vector2i(9, 2))
	bo.hp = 0
	_check(not st.op_test_event5({}), "a boss at HP 0 still on the map is no victory yet")
	bo.state = 3
	_check(st.op_test_event5({}), "the boss removed: victory")
	st.boss_pid = -1
	en.state = BUnit.STATE_HIDDEN
	_check(st.op_test_event5({}), "only hidden enemies left: victory")
	for i in 115:
		BUnit.at(i).clear(i)
	BUnit.gen += 1

	# ---- a battle save restored: the cell → unit caches see the units where the save has them
	var ru := _unit(0, 0, 0, Vector2i(4, 4))
	var snap := Mem.snapshot()
	ru.pos = Vector2i(8, 8)
	_check(Skills.unit_in_cell(Vector2i(8, 8)) != null and st.unit_at(Vector2i(8, 8)) != null, "the caches see the move")
	Mem.restore(snap)
	if st.vm == null:
		st.vm = EexVM.new()
	ui.meter.visible = true            # a battle save loaded from a town: the town's resource meter goes
	st.restore_state({"kind": "battle", "scene": 1, "turn": 1, "field_ready": true, "map": st.map_id})
	st._apply_restore()
	_check(not ui.meter.visible, "a restored battle hides the town's resource meter")
	_check(Skills.unit_in_cell(Vector2i(8, 8)) == null and Skills.unit_in_cell(Vector2i(4, 4)) != null,
			"Skills.unit_in_cell after a restore")
	_check(st.unit_at(Vector2i(8, 8)) == null and st.unit_at(Vector2i(4, 4)) != null, "unit_at after a restore")
	for i in 115:
		BUnit.at(i).clear(i)
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


## AI StratScore (0x4395ae) and BestStrategy (0x4391dc): +10 on U's own AI target, the extra terms only for a target
## the strategy does not kill, 陷阱 adjacent on 8 neighbours (0x45afca), 开导 12 with person effect 0x40 (0x407a09).
func _strat_scores(st: BattleStage) -> void:
	for i in 115:
		BUnit.at(i).clear(i)
	BUnit.gen += 1
	var c0 := Vector2i(5, 5)
	var ub := _unit(40, 306, 2, c0)
	ub.mp = ub.max_mp()
	st.ai.u = ub
	var cells := Shapes.range_cells(int(Game.strategy(33).get("range", 0)), c0, st.view.map_w, st.view.map_h)
	var tp := _unit(5, 50, 0, cells[0])
	st.ai.usable_strats = [33] as Array[int]
	Mem.w8(ub.addr + 8, 0xff)
	var sc := mini(st.ai._strat_score(tp, 33, c0), 255)
	var r0: Array = st.ai._best_strategy(c0)
	_check(sc > 0 and r0[0] == sc and r0[1] == 33 and r0[2] != null and r0[2].slot == tp.slot,
			"BestStrategy scores the target (%s, %d)" % [r0, sc])
	Mem.w8(ub.addr + 8, tp.slot)
	var r1: Array = st.ai._best_strategy(c0)
	_check(r1[0] == sc + 10, "BestStrategy: +10 on U's own AI target (%s, %d)" % [r1, sc])
	Mem.w8(ub.addr + 8, 0xff)
	# 暗算 (20): +5 / +10 for a hurt U, but not on a kill
	ub.hp = 1
	tp.hp = 1
	_check(st.ai._strat_score(tp, 20, c0) == 76, "a kill scores 76 without 暗算's terms (%d)" % st.ai._strat_score(tp, 20, c0))
	tp.hp = tp.max_hp()
	var mh := tp.max_hp()
	var d20 := Rules.strat_damage(ub, tp, 20, true)
	if d20 < tp.hp:
		var b20 := 30 if d20 * 10 / mh >= 3 else (10 if d20 * 10 / mh >= 1 else 1)
		_check(st.ai._strat_score(tp, 20, c0) == b20 + 15, "暗算 by a wounded U: +5 +10 (%d)" % st.ai._strat_score(tp, 20, c0))
	ub.hp = ub.max_hp()
	# 陷阱 (35): +10 unless the target stands on one of U's 8 neighbours
	for off in [Vector2i(1, 1), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)]:
		tp.pos = c0 + off
		var d35 := Rules.strat_damage(ub, tp, 35, true)
		var want := 76
		if d35 < tp.hp:
			want = (30 if d35 * 10 / mh >= 3 else (10 if d35 * 10 / mh >= 1 else 1)) + (0 if maxi(absi(off.x), absi(off.y)) == 1 else 10)
		_check(st.ai._strat_score(tp, 35, c0) == want, "陷阱 with the target at %s: %d, want %d" % [off, st.ai._strat_score(tp, 35, c0), want])
	# 开导 (44) on a target low on MP: family 9 → 1, a magic family or person effect 0x40 → 12, family 0 → 6
	var p := Game.person(50)
	var fam := tp.family()
	tp.mp = 0
	for pid in range(300, 500):            # a caster with MP enough for 开导
		ub.pid = pid
		if ub.max_mp() >= st.actions.strategy_mp(44):
			break
	ub.mp = ub.max_mp()
	var acc := p.accessory
	p.accessory = -1
	var plain := 1 if fam == 9 else (12 if fam in BattleAI.MAGIC_FAMILIES else (6 if fam == 0 else 0))
	_check(st.ai._strat_score(tp, 44, c0) == plain, "开导 without effect 0x40: %d" % st.ai._strat_score(tp, 44, c0))
	p.accessory = 90                        # 补气酒: item type 0x40
	_check(st.ai._strat_score(tp, 44, c0) == (1 if fam == 9 else 12), "开导 with person effect 0x40 scores 12")
	p.accessory = acc
	for i in 115:
		BUnit.at(i).clear(i)
	BUnit.gen += 1
