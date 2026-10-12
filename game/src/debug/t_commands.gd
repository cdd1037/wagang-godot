extends Node
## The mod's battle commands (docs/mod_patches.md group 2): the command menu's enable tests, 绝招 (several
## characters), multi-target strikes, 围攻, 交给, 连续策略, the move-path record. Prints "t_commands: PASS".

var _ok := true
var st: BattleStage


func _check(ok: bool, what: String) -> void:
	if not ok:
		_ok = false
		print("t_commands: FAIL ", what)


func _unit(slot: int, pid: int, pos: Vector2i, cls := -1) -> BUnit:
	var u := st.units[slot]
	u.clear(slot)
	u.pid = pid
	if cls >= 0:
		u.person.cls = cls
	u.colour = 0 if slot < 15 else 2
	u.mode = 7 if slot < 15 else 1
	u.state = BUnit.STATE_ON_MAP
	u.pos = pos
	u.hp = u.max_hp()
	u.mp = u.max_mp()
	u.status = 0
	return u


## Clear the field: every unit off the map.
func _clear() -> void:
	for u in st.units:
		u.clear(u.slot)
	Mem.w8(BattleStage.PATH_LEN, 0)
	st.refresh_units()


## A click on `cell` a frame from now (for the pickers, which wait for the map's click signal).
func _click_soon(cell: Vector2i, button := MOUSE_BUTTON_LEFT) -> void:
	await get_tree().process_frame
	st.view.cell_clicked.emit(cell, button)


## A click on `cell` once a picker shows its cells (after an attack has played out, for instance).
func _click_when_picking(cell: Vector2i, button := MOUSE_BUTTON_LEFT) -> void:
	for k in 600:
		await get_tree().process_frame
		if not st.view._hl_attack.is_empty() or not st.view._hl_move.is_empty():
			st.view.cell_clicked.emit(cell, button)
			return


func _passable(u: BUnit, c: Vector2i) -> bool:
	return Rules.move_cost(u, st.view.terrain_at(c)) < 255


func run() -> void:
	Game.new_game_state()
	Game.autoplay = true
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
	st = BattleStage.new()
	m.set("stage", st)
	add_child(st)
	await get_tree().process_frame
	await st.op_change_scene({"args": [3, 0xffff, 0xffff, 0xffff, 0]})
	# an event scene that is always busy: the battle runs on and the polls do nothing
	st.vm = EexVM.new()
	st.vm.active = true
	st.vm.scene = 1
	st.vm.running = true
	# a plain grass field, so every unit can stand anywhere
	for y in st.view.map_h:
		for x in st.view.map_w:
			st.view.set_terrain(Vector2i(x, y), 0)

	# ---- the move-path record (0x4d8f1f / 0x409120) and 冲锋
	_clear()
	st.record_path(Vector2i(2, 2), [Vector2i(3, 2), Vector2i(4, 2)] as Array[Vector2i])
	_check(Mem.r8(BattleStage.PATH_LEN) == 2 and str(st.move_path()) == str([Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)]), "path record")
	_check(Mem.r16(BattleStage.PATH + 6) == 0xffff, "path terminator")

	# ---- 绝招 enable (0x4d5444 on [0x4cf310])
	_clear()
	for pid in [0, 7, 8, 17, 19, 26]:
		Mem.w32(BattleStage.CMD_PID, pid)
		_check(st.commands.special_enabled(), "绝招 enabled for %d" % pid)
	Mem.w32(BattleStage.CMD_PID, 1)
	_check(not st.commands.special_enabled(), "程咬金 needs 三板斧 learned")
	Mem.w32(0x55ac04, 1)
	_check(st.commands.special_enabled(), "程咬金 after R_11")
	Mem.w32(0x55ac04, 0)
	var wu := _unit(5, 5, Vector2i(1, 1))
	Mem.w32(BattleStage.CMD_PID, 5)
	_check(st.commands.special_enabled(), "伍云召")
	wu.status = BUnit.ST_PARALYSIS
	_check(not st.commands.special_enabled(), "伍云召 paralysed")
	Mem.w32(BattleStage.CMD_PID, 3)
	_check(not st.commands.special_enabled(), "尉迟恭 without the slot")
	Mem.set_ev(3974, 3)
	_check(st.commands.special_enabled(), "尉迟恭 with dynamic slot 4")
	Mem.set_ev(3974, 1024)

	# ---- 绝招 rules: hit, critical, defence, ranges
	_clear()
	var a := _unit(0, 0, Vector2i(5, 5))
	var e := _unit(35, 300, Vector2i(6, 5))
	Mem.w32(BattleStage.SPECIAL_RUNNING, 1)
	e.status = 0
	_check(Rules.hit_rate(a, e) == 100 and Rules.crit_rate(a, e) == 100, "绝招: sure hit and critical")
	var cy := _unit(1, 1, Vector2i(4, 4))
	_check(Rules.hit_rate(cy, e) == 50, "三板斧 50 %")
	e.status = BUnit.ST_CONFUSION
	_check(Rules.hit_rate(cy, e) == 100, "三板斧 on a confused target")
	e.status = 0
	var wt := _unit(2, 7, Vector2i(3, 3))
	_check(Rules.crit_rate(wt, e) == 0, "伍天锡 never crits in a 绝招")
	var qq := _unit(3, 8, Vector2i(3, 4))
	_check(st.actions.attack_range_code(qq) == 6, "秦琼's 绝招 range")
	Mem.w32(BattleStage.SPECIAL_RUNNING, 0)
	_check(st.actions.attack_range_code(qq) != 6 or Game.cls(qq.cls()).get("attack_range", 0) == 6, "秦琼's normal range")

	# ---- 苍龙过阵枪 (管毅): MP未满, then the move
	_clear()
	a = _unit(0, 0, Vector2i(5, 5))
	e = _unit(35, 300, Vector2i(6, 5))
	e.hp = 9999 if e.max_hp() > 9999 else e.max_hp()
	a.mp = a.max_mp() - 1 if a.max_mp() > 1 else a.mp
	if a.max_mp() > 1:
		Mem.w32(BattleStage.CMD_PID, a.pid)
		var r0 := await st.commands.special(a)
		_check(not r0 and a.mp == a.max_mp() - 1, "MP未满: nothing happens")
	a.mp = a.max_mp()
	var hp0 := e.hp
	_click_soon(e.pos)
	Mem.w32(BattleStage.CMD_PID, a.pid)
	var r1 := await st.commands.special(a)
	_check(r1 and a.mp == 0, "绝招 spends all MP")
	_check(e.hp < hp0, "苍龙过阵枪 hits")
	_check(a.buff(0) == 6 and e.buff(0) == 0, "苍龙过阵枪 攻击 up / down")
	_check(Mem.r32(BattleStage.SPECIAL_RUNNING) == 0, "flag cleared")
	# a cancelled picker spends nothing
	a.mp = a.max_mp()
	_click_soon(e.pos, MOUSE_BUTTON_RIGHT)
	Mem.w32(BattleStage.CMD_PID, a.pid)
	var r2 := await st.commands.special(a)
	_check(not r2 and a.mp == a.max_mp(), "cancelled 绝招")

	# ---- 威震八荒 (伍天锡): no enemy around, then two
	_clear()
	wt = _unit(2, 7, Vector2i(8, 8))
	Mem.w32(BattleStage.CMD_PID, wt.pid)
	var r3 := await st.commands.special(wt)
	_check(not r3 and wt.mp == wt.max_mp(), "威震八荒 without enemies")
	var e1 := _unit(35, 300, Vector2i(8, 7))
	var e2 := _unit(36, 301, Vector2i(9, 8))
	var e3 := _unit(37, 302, Vector2i(9, 9))       # diagonal: only for a range other than the four cells
	var h1 := e1.hp
	var h2 := e2.hp
	var h3 := e3.hp
	Mem.w32(BattleStage.CMD_PID, wt.pid)
	var r4 := await st.commands.special(wt)
	_check(r4 and wt.mp == 0 and e1.hp < h1 and e2.hp < h2, "威震八荒 strikes the adjacent enemies")
	_check((e3.hp < h3) == (st.actions.attack_range_code(wt) != 0), "威震八荒 diagonals by range")

	# ---- 横扫千军 (雄阔海): five cells across, then a push
	_clear()
	var xk := _unit(4, 26, Vector2i(10, 10))
	var t0 := _unit(35, 300, Vector2i(10, 9))
	var t1 := _unit(36, 301, Vector2i(9, 9))
	var t2 := _unit(37, 302, Vector2i(12, 9))
	t0.hp = 9999
	t1.hp = 9999
	t2.hp = 9999
	t1.status = BUnit.ST_CONFUSION
	_click_soon(t0.pos)
	Mem.w32(BattleStage.CMD_PID, xk.pid)
	var r5 := await st.commands.special(xk)
	_check(r5 and t0.hp < 9999 and t1.hp < 9999 and t2.hp < 9999, "横扫千军 hits the row")
	_check(t0.pos == Vector2i(10, 8) and t1.pos == Vector2i(9, 8) and t2.pos == Vector2i(12, 8), "横扫千军 pushes")
	_check(not (t1.status & BUnit.ST_CONFUSION), "the push cures 乱")

	# ---- 踏破连营 (伍云召): the line beyond the target, then the charge
	_clear()
	wu = _unit(5, 5, Vector2i(10, 10))
	var l0 := _unit(35, 300, Vector2i(11, 10))
	var l1 := _unit(36, 301, Vector2i(12, 10))
	var far := _unit(37, 302, Vector2i(14, 10))      # after a gap: not hit
	l0.hp = 9999
	l1.hp = 9999
	far.hp = 9999
	_click_soon(l0.pos)
	Mem.w32(BattleStage.CMD_PID, wu.pid)
	var r6 := await st.commands.special(wu)
	_check(r6 and l0.hp < 9999 and l1.hp < 9999 and far.hp == 9999, "踏破连营 hits the line up to a gap")
	_check(wu.pos == Vector2i(13, 10), "踏破连营 charges through to the free cell")
	_check(wu.buff(5) == 6 and wu.buff(1) == 6 and wu.buff(3) == 6, "踏破连营 buffs")
	_check(Mem.r32(0x55ac64) == 0, "踏破连营 flag cleared")

	# ---- 回马枪 (罗成): back along his trail, the target follows
	_clear()
	var lc := _unit(6, 19, Vector2i(5, 10))
	var lt := _unit(35, 300, Vector2i(6, 10))
	lt.hp = 9999
	st.record_path(Vector2i(5, 8), [Vector2i(5, 9), Vector2i(5, 10)] as Array[Vector2i])
	_click_soon(lt.pos)
	Mem.w32(BattleStage.CMD_PID, lc.pid)
	var r7 := await st.commands.special(lc)
	_check(r7 and lc.pos == Vector2i(5, 8), "回马枪: 罗成 rides back")
	_check(lt.pos == Vector2i(5, 9) and lt.hp < 9999 and lt.buff(5) == 0, "回马枪: lured, hit, 机动 down")

	# an ally on the trail: the target is lured beside it
	_clear()
	lc = _unit(6, 19, Vector2i(5, 10))
	lt = _unit(35, 300, Vector2i(6, 10))
	_unit(7, 2, Vector2i(5, 9))
	lt.hp = 9999
	st.record_path(Vector2i(5, 8), [Vector2i(5, 9), Vector2i(5, 10)] as Array[Vector2i])
	Mem.w32(BattleStage.CMD_PID, lc.pid)
	_click_soon(lt.pos)
	await st.commands.special(lc)
	_check(lc.pos == Vector2i(5, 8) and lt.pos == Vector2i(6, 8), "回马枪: lured beside the trail")

	# ---- 杀手锏 / 回旋杀手锏 (秦琼)
	_clear()
	qq = _unit(3, 8, Vector2i(10, 10), 33)
	var q0 := _unit(35, 300, Vector2i(11, 10))
	var q1 := _unit(36, 301, Vector2i(12, 10))
	q0.hp = 9999
	q1.hp = 9999
	Mem.set_ev(3981, 8)
	var tab := Mem.r32(0x4091b2)
	_click_soon(q0.pos)
	Mem.w32(BattleStage.CMD_PID, qq.pid)
	var r8 := await st.commands.special(qq)
	_check(r8 and q1.hp < 9999 and q1.buff(0) == 0 and q1.buff(1) == 0 and q0.buff(1) == 0, "回旋杀手锏 pierces and weakens both")
	_check(Mem.r32(0x4091b2) == tab, "the class table is restored")
	Mem.set_ev(3981, 1024)

	# ---- multi-target attacks: 长矛手 (area 4, full) and 无影剑 (area 1, half)
	_clear()
	var sp := _unit(0, 40, Vector2i(5, 5), 6)
	var s0 := _unit(35, 300, Vector2i(6, 5))
	var s1 := _unit(36, 301, Vector2i(7, 5))
	_check(st.actions.area_code(sp) == 4, "长矛手 area code")
	_check(st.actions.secondary_targets(sp, s0, 4) == ([s1] as Array[BUnit]), "the unit behind")
	sp.person.cls = 17
	_check(st.actions.area_code(sp) == 1 and st.actions._halved(sp, 1) and not st.actions._halved(sp, 4), "无影剑 area 1, halved")

	# ---- the attack animation's step table (0x42beae) and swing sound (0x4400a2)
	var steps := func(a: int) -> Array:
		var out := []
		for i in 22:
			out.append(Mem.r8(a + i))
		return out
	_check(steps.call(BattleActions.ANIM_TABLE) == [0, 9, 1, 10, 9, 9, 9, 2, 9, 9, 9, 3, 4, 5, 6, 9, 7, 9, 9, 9, 9, 8]
		and steps.call(BattleActions.ANIM_TABLE_WINDUP) == [0, 9, 1, 10, 3, 1, 3, 2, 9, 9, 9, 3, 4, 5, 6, 9, 7, 9, 9, 9, 9, 8]
		and steps.call(BattleActions.ANIM_TABLE_TRIPLE) == [0, 1, 10, 9, 9, 3, 4, 5, 6, 3, 4, 5, 6, 3, 4, 5, 6, 7, 9, 9, 9, 8],
		"the three step tables")
	var gy := _unit(1, 0, Vector2i(2, 2))
	var zs := _unit(2, 204, Vector2i(2, 3))
	_check(BattleActions.anim_table(gy) == BattleActions.ANIM_TABLE_WINDUP and BattleActions.anim_table(zs) == BattleActions.ANIM_TABLE_WINDUP
		and BattleActions.anim_table(sp) == BattleActions.ANIM_TABLE, "管毅 and 张善相 wind up, others not")
	Mem.w8(BattleActions.TRIPLE_STRIKE, 1)
	_check(BattleActions.anim_table(sp) == BattleActions.ANIM_TABLE_TRIPLE and BattleActions.anim_table(gy) == BattleActions.ANIM_TABLE_WINDUP,
		"尽命三锤's table, after the pid test")
	Mem.w8(BattleActions.TRIPLE_STRIKE, 0)
	sp.person.cls = 12                      # 弓兵 (family 4): SE 37
	_check(sp.family() == 4 and BattleActions.swing_kind(sp) == 0 and BattleActions.swing_kind(gy) > 0, "archers swing with SE 37")

	# ---- 围攻
	_clear()
	var ga := _unit(0, 0, Vector2i(5, 5))
	var gh := _unit(1, 2, Vector2i(7, 5))
	var gt := _unit(35, 300, Vector2i(6, 5))
	gt.hp = 9999
	Mem.w32(BattleStage.CMD_PID, 0)
	_check(st.commands.helpers(ga, gt) == ([gh] as Array[BUnit]), "helpers")
	_check(st.commands.siege_enabled(ga), "围攻 enabled")
	gh.acted = true
	_check(not st.commands.siege_enabled(ga), "a finished helper does not count")
	for k in 5:                             # both strikes can miss: try again a few times
		gh.acted = false
		ga.hp = ga.max_hp()
		gt.hp = 9999
		await st.commands.siege(ga, gt, [gh] as Array[BUnit])
		if gt.hp < 9999:
			break
	_check(gt.hp < 9999 and gh.acted, "围攻: both strike, the helper is done")
	# the target's counter is answered once more when the leader has effect 40 (0x40639a tests the defender of the
	# counter), whoever started the last attack before
	var gw := Game.person(0).weapon
	Game.person(0).weapon = 32              # 水火虬龙棒: 反击后反击
	ga.hp = 9999
	gt.hp = 9999
	await st.actions.attack(gt, gh)         # an attack started by someone without effect 40
	gh.acted = false
	gh.hp = gh.max_hp()
	st.actions.tracing = true
	st.actions.trace.clear()
	await st.commands.siege(ga, gt, [gh] as Array[BUnit])
	st.actions.tracing = false
	var again := false
	for ent in st.actions.trace:
		if ent[0] == ga.slot and ent[1] == gt.slot:
			again = true
	_check(again, "围攻: the leader with effect 40 answers the counter: %s" % [st.actions.trace])
	Game.person(0).weapon = gw

	# ---- 交给
	_clear()
	var gv := _unit(0, 0, Vector2i(5, 5))
	var rc := _unit(1, 2, Vector2i(5, 6))
	var acc := 0x35
	gv.person.accessory = acc
	rc.person.accessory = -1
	Mem.w32(BattleStage.CMD_PID, 0)
	_check(st.commands.give_enabled(gv), "交给 enabled with an accessory")
	if rc.person.can_equip(acc):
		_click_soon(rc.pos)
		var r9 := await st.commands.give_command(gv)
		_check(r9 and rc.person.accessory == acc and gv.person.accessory == -1, "交给 hands it over")
	Mem.w32(BattleStage.CMD_PID, 11)
	Game.init_bag()
	_check(not st.commands.give_enabled(gv), "樊虎 with an empty bag")
	Game.add_item(0x36)
	_check(st.commands.give_enabled(gv), "樊虎 with an accessory in the bag")

	# ---- 连续攻击 (六军镜·形势, effect 90): a second target after the first attack
	_clear()
	var ca := _unit(0, 0, Vector2i(5, 5))
	ca.person.accessory = 83
	var c1 := _unit(35, 300, Vector2i(6, 5))
	var c2 := _unit(36, 301, Vector2i(5, 6))
	c1.hp = 9999
	c2.hp = 9999
	c1.status = BUnit.ST_CONFUSION      # sure hits (and no counter), so the test does not depend on the rolls
	c2.status = BUnit.ST_CONFUSION
	_click_soon(c1.pos)
	var picks := func() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		await _click_when_picking(c2.pos)
	picks.call()
	var rr := await st.input._do_attack(ca)
	_check(rr and c1.hp < 9999 and c2.hp < 9999, "连续攻击 attacks twice")
	ca.person.accessory = -1

	# ---- 再移动 (六军镜·阴阳, effect 82): another move after the action
	_clear()
	var mv := _unit(0, 0, Vector2i(5, 5))
	mv.person.accessory = 85
	mv.flags = 6
	_click_when_picking(Vector2i(5, 7))
	await st.input._move_again(mv)
	_check(mv.pos == Vector2i(5, 7) and mv.acted and mv.moved, "再移动 moves again and ends")
	_check(Mem.r8(BattleStage.PATH_LEN) == 2, "再移动 records its walk")
	mv.person.accessory = -1

	# ---- 连续策略: the second cast costs double
	_clear()
	var cu := _unit(0, 0, Vector2i(5, 5))
	var mp1 := st.actions.strategy_mp(0)
	_check(not st.actions.second_cast(cu) and Mem.r8(BattleStage.SECOND_CAST) == 0, "no 连续策略 without effect 83")
	Mem.w8(BattleStage.SECOND_CAST, 1)
	_check(st.actions.strategy_mp(0) == 2 * mp1, "double MP on the second cast")
	_check(not st.actions.second_cast(cu) and Mem.r8(BattleStage.SECOND_CAST) == 0, "the flag clears")

	# ---- the target pickers' forecast (0x4404bd, its line 0x440e89)
	_clear()
	var fa := _unit(0, 0, Vector2i(5, 5))
	var fe := _unit(35, 300, Vector2i(6, 5))
	var ff := _unit(1, 2, Vector2i(5, 6))
	ff.hp = 1
	var fd := Rules.calc_damage(fa, fe, st.view.terrain_at(fa.pos), st.view.terrain_at(fe.pos), false, 0)
	var f1 := BattleHUD.forecast_for(st, {"kind": 1, "actor": fa, "param": -1}, fe)
	_check(f1["hp"] == fe.hp - fd and f1["mp"] == -1, "attack forecast: HP after the damage")
	_check(f1["line"] == "损伤 %3d  命中 %3d%%" % [fd, Rules.hit_rate(fa, fe)], "attack forecast line: " + str(f1["line"]))
	var fh := Rules.heal_amount(fa, ff, 39, true)
	var f3 := BattleHUD.forecast_for(st, {"kind": 3, "actor": fa, "param": 39}, ff)
	_check(f3["hp"] == 1 + fh and str(f3["line"]).begins_with("恢复HP %3d" % fh) and "效果" in str(f3["line"]),
			"医疗 forecast: " + str(f3["line"]))
	var f22 := BattleHUD.forecast_for(st, {"kind": 2, "actor": fa, "param": 22}, fe)
	_check(f22["hp"] == -1 and f22["mp"] == fe.mp - Rules.strat_damage(fa, fe, 22, true), "暗鬼 forecast takes MP")
	var f23 := BattleHUD.forecast_for(st, {"kind": 2, "actor": fa, "param": 23}, fe)
	_check(str(f23["line"]).begins_with(Mem.str_ptr(0x48bd40, 9)) and "命中" in str(f23["line"]), "流言 forecast names the effect")
	var f48 := BattleHUD.forecast_for(st, {"kind": 3, "actor": fa, "param": 48}, ff)
	_check(str(f48["line"]).begins_with("机动上升") and f48["hp"] == -1, "急行 forecast: " + str(f48["line"]))
	var f87 := BattleHUD.forecast_for(st, {"kind": 4, "actor": fa, "param": 87}, ff)
	_check(f87["hp"] == 1 + st.actions.heal_value(87, ff) and f87["line"] == "恢复HP %3d" % st.actions.heal_value(87, ff),
			"馒头 forecast: " + str(f87["line"]))
	var f90 := BattleHUD.forecast_for(st, {"kind": 4, "actor": fa, "param": 90}, ff)
	_check(f90["mp"] >= 0 and f90["hp"] == -1 and str(f90["line"]).begins_with("恢复MP"), "补气酒 forecast")
	_check(BattleHUD.forecast_for(st, {"kind": 4, "actor": fa, "param": 98}, ff)["line"] == "武艺上升 %3d" % 2, "精强果: its value")
	_check(BattleHUD.forecast_for(st, {"kind": 4, "actor": fa, "param": 103}, ff)["line"] == "等级上升 %3d" % 1, "仙人果: value / 100")
	# 交给 a mod accessory: types above 0x51 are named from 0x410f50 (mod 0x4412c9 → 0x4d23a8)
	_check(BattleHUD.forecast_for(st, {"kind": 4, "actor": fa, "param": 85}, ff)["line"] == "再移动", "六军镜·阴阳 (0x52)")
	_check(BattleHUD.forecast_for(st, {"kind": 4, "actor": fa, "param": 83}, ff)["line"] == "连续攻击", "六军镜·形势 (0x5a)")
	_check(BattleHUD.forecast_for(st, {"kind": 4, "actor": fa, "param": 53}, ff)["line"] == Mem.str_ptr(0x48bc08, 0x35), "an original accessory")
	# shown for a unit of the right side on a picker cell only (0x4541a9)
	st.hud.forecast = {"kind": 1, "actor": fa, "param": -1, "cells": [fe.pos, ff.pos]}
	st.hud.hover_cell = fe.pos
	_check(st.hud._forecast_on(fe), "an enemy in reach gets the attack forecast")
	st.hud.hover_cell = ff.pos
	_check(not st.hud._forecast_on(ff), "an ally does not")
	st.hud.forecast["kind"] = 4
	_check(st.hud._forecast_on(ff), "an ally gets the item forecast")
	st.hud.hover_cell = Vector2i(9, 9)
	_check(not st.hud._forecast_on(ff), "off the picker's cells: none")
	st.hud.forecast = {}

	Game.main = old_main
	print("t_commands: PASS" if _ok else "t_commands: FAILED")
