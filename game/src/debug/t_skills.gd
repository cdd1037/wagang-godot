extends Node
## The mod's character skills (docs/mod_patches.md group 3): 【技】 attack techniques, phase-start auras, 明镜, stat
## auras and 并蒂, 舍命 / 智将, 杜断, 房谋, 烈魔, 逐影随行咒, on-hit skills, terrain rules, 相马, 天运, 百宝, 统军,
## 锻造 / 波若, kill rewards, 宿痕. Prints "t_skills: PASS".

var _ok := true
var st: BattleStage


func _check(ok: bool, what: String) -> void:
	if not ok:
		_ok = false
		print("t_skills: FAIL ", what)


## A unit of person `pid` without equipment, with the five stat words at `stats` and level `lv`.
func _unit(slot: int, pid: int, pos: Vector2i, lv := 20, stats := 100, cls := -1) -> BUnit:
	var u := st.units[slot]
	u.clear(slot)
	u.pid = pid
	var p := u.person
	if cls >= 0:
		p.cls = cls
	p.level = lv
	p.weapon = -1
	p.armor = -1
	p.accessory = -1
	p.hp_base = 500
	p.mp_base = 50
	for i in 5:
		p.set_stat_word(i, stats)
		p.set_raw(i, 50)
	u.colour = 0 if slot < 15 else (1 if slot < 35 else 2)
	u.mode = 7 if slot < 15 else 1
	u.state = BUnit.STATE_ON_MAP
	u.pos = pos
	u.hp = u.max_hp()
	u.mp = u.max_mp()
	u.status = 0
	return u


func _clear() -> void:
	for u in st.units:
		u.clear(u.slot)
	for a in range(0x55ac1c, 0x55ac6c, 4):
		Mem.w32(a, 0)
	Mem.w8(BattleStage.PATH_LEN, 0)
	Mem.w8(BattleActions.STRIKE, 0)
	for k in 30:
		Mem.set_ev(Skills.DYN + k, 1024)
	st.refresh_units()


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
	st.vm = EexVM.new()
	st.vm.active = true
	st.vm.scene = 1
	st.vm.running = true
	for y in st.view.map_h:
		for x in st.view.map_w:
			st.view.set_terrain(Vector2i(x, y), 0)
	Mem.w32(Skills.MAP_NO, 5)
	_check(Skills.in_battle(), "battle mode")

	await _phase_start()
	_stat_auras()
	_damage_post()
	_strategies()
	await _strategy_casts()
	await _on_hit()
	_terrain()
	_person_skills()
	await _path_skills()
	_kill_rewards()
	await _techniques()

	Game.main = old_main
	print("t_skills: PASS" if _ok else "t_skills: FAILED")


# ------------------------------------------------------------------ phase start (B1 F1, B3 F9, B4 §H)
func _phase_start() -> void:
	_clear()
	var lu := _unit(0, 29, Vector2i(5, 5), 10)
	var a := _unit(1, 2, Vector2i(6, 5))
	var b := _unit(2, 3, Vector2i(5, 6))
	var far := _unit(3, 4, Vector2i(8, 8))
	var e := _unit(35, 300, Vector2i(4, 5))
	a.hp -= 200
	b.hp -= 10
	far.hp -= 100
	e.hp -= 100
	lu.hp -= 100
	await st._phase_skills(lu)
	_check(a.hp == a.max_hp() - 140, "云袖 heals Lv + 50")
	_check(b.hp == b.max_hp(), "云袖 up to the maximum")
	_check(far.hp == far.max_hp() - 100 and e.hp == e.max_hp() - 100 and lu.hp == lu.max_hp() - 100, "云袖 only around, own side, not herself")
	# 仙乐: MP + Lv / 4 + 1
	_clear()
	var liu := _unit(0, 31, Vector2i(5, 5), 8)
	var c := _unit(1, 2, Vector2i(6, 6))
	c.mp = 0
	await st._phase_skills(liu)
	_check(c.mp == 3, "仙乐 MP")
	# 神将 and 雄师
	_clear()
	var sh := _unit(35, 42, Vector2i(5, 5))
	var x := _unit(36, 301, Vector2i(5, 4))
	var y := _unit(0, 2, Vector2i(6, 5))
	await st._phase_skills(sh)
	_check(x.buff(0) == 6 and y.buff(0) == 3, "神将: own side's 攻击")
	_clear()
	var xs := _unit(0, 3, Vector2i(5, 5), 20, 100, 42)
	var z := _unit(1, 2, Vector2i(4, 4))
	await st._phase_skills(xs)
	_check(Game.family_of(42) == 16 and z.buff(4) == 6, "雄师: 士气")
	# 魔功 ([0x55ac44] = 杨素): poisons the other side around him
	_clear()
	Mem.w32(0x55ac44, 100)
	var ys := _unit(35, 100, Vector2i(5, 5))
	var p1 := _unit(0, 2, Vector2i(6, 5))
	var e2 := _unit(36, 301, Vector2i(4, 5))
	await st._phase_skills(ys)
	_check((p1.status & BUnit.ST_POISON) and not (e2.status & BUnit.ST_POISON), "魔功 poisons the other side")
	Mem.w32(0x55ac44, 0x4000)
	# 明镜: 魏征 next to an ally with a status cures it at once
	_clear()
	_unit(0, 23, Vector2i(5, 5))
	var sick := _unit(1, 2, Vector2i(6, 6))
	sick.status = BUnit.ST_POISON | BUnit.ST_PARALYSIS | 1
	sick.person.set_raw(4, 0)
	var sick2 := _unit(2, 3, Vector2i(8, 8))
	sick2.status = BUnit.ST_POISON
	sick2.person.set_raw(4, 0)
	var foe := _unit(35, 301, Vector2i(4, 4))
	foe.status = BUnit.ST_POISON
	foe.person.set_raw(4, 0)
	await st._status_recovery(sick)
	await st._status_recovery(sick2)
	await st._status_recovery(foe)
	_check(sick.status == 1, "明镜 cures all, bit 0 stays")
	_check(sick2.status == BUnit.ST_POISON and foe.status == BUnit.ST_POISON, "明镜: not far away, not the other side")


# ------------------------------------------------------------------ getters (B2 §A, §B, §D)
func _stat_auras() -> void:
	_clear()
	Mem.set_ev(3970, 12)
	var lmx := _unit(0, 12, Vector2i(5, 5))
	var gy := _unit(1, 0, Vector2i(6, 5))
	_check(lmx.person.stat(0) == 120, "连理: +25 % next to 管毅 → 120")
	gy.pos = Vector2i(5, 9)
	_check(lmx.person.stat(0) == 105, "连理 at distance 4")
	gy.pos = Vector2i(5, 10)
	_check(lmx.person.stat(0) == 100, "连理 out of reach")
	# 士气 of slot 0 near 鲁明月 (29); 反应 of slot 1 near 鲁明星 (12)
	var lmy := _unit(2, 29, Vector2i(5, 6))
	_check(lmx.person.stat(4) == 120 and lmx.person.stat(1) == 100, "连理 士气 near 鲁明月")
	Mem.set_ev(3971, 29)
	_check(lmy.person.stat(3) == 120, "云袖 连理 反应 near 鲁明星")
	gy.pos = Vector2i(6, 6)
	_check(lmy.person.stat(1) == 120, "云袖 连理 防御 near 管毅")
	Mem.w32(Skills.MAP_NO, 0xffff)
	_check(lmx.person.stat(0) == 100, "no aura in towns")
	Mem.w32(Skills.MAP_NO, 5)
	# 并蒂
	Mem.set_ev(3972, 2)
	var wjk := _unit(3, 2, Vector2i(9, 9))
	Mem.w8(0x55ee02, 3)
	_check(wjk.person.stat(0) == 124, "并蒂 +8 % per hit on 管毅")
	Mem.w32(0x55ee04, 0)
	st.actions._bingdi_count(gy)
	st.actions._bingdi_count(wjk)
	_check(Mem.r8(0x55ee06) == 1 and Mem.r8(0x55ee04) == 1, "并蒂 counters")
	Mem.w32(Skills.MAP_NO, 0xffff)
	wjk.person.stat(0)
	_check(Mem.r32(0x55ee04) == 0, "the town getter clears them")
	Mem.w32(Skills.MAP_NO, 5)
	# 宿痕 (story mode): 秦琼's attack with 瓦面金装锏
	var q := Game.person(8)
	q.weapon = 0x18
	q.weapon_lvl = 3
	q.set_stat_word(0, 150)
	Mem.w32(Mem.EV + 4 * 3181, 1)
	Mem.set_ev(3401, 50)
	Mem.set_ev(3201, 10)
	var bonus := q.equip_bonus(0)
	Mem.w32(Skills.MAP_NO, 0xffff)
	_check(q.stat(0) == mini((150 - 50) * 130 / 100 + 50 + bonus, 9999), "宿痕 秦琼")
	Mem.w32(Skills.MAP_NO, 5)
	_check(q.stat(0) == mini(150 + bonus, 9999), "宿痕 only in towns")
	Mem.w32(Mem.EV + 4 * 3181, 0)
	# 相马 (dynamic slot 7): mounts move one more while the holder is in the party
	var jr := Game.person(20)
	var rider := Game.person(5)
	jr.fixed_growth_flag = 0
	rider.fixed_growth_flag = 0
	rider.accessory = 0x3d
	var mv := rider.move_points()
	Mem.set_ev(3977, 20)
	_check(rider.move_points() == mv + 1, "相马 +1")
	rider.accessory = -1
	Mem.set_ev(3977, 1024)


# ------------------------------------------------------------------ CalcDamage post (B4 §F)
func _damage_post() -> void:
	_clear()
	Mem.set_ev(3980, 13)
	var wbd := _unit(0, 13, Vector2i(5, 5))
	var t := _unit(35, 300, Vector2i(6, 5))
	_check(Rules.damage_post(wbd, t, 100) == 100, "舍命 not at full HP")
	wbd.hp = wbd.max_hp() * 59 / 100
	_check(Rules.damage_post(wbd, t, 100) == 130, "舍命 below 60 %")
	var lc := _unit(1, 19, Vector2i(5, 6))
	_check(Rules.damage_post(lc, t, 0) == lc.spirit() * 15 / 100, "智将 even on a miss")
	_check(Rules.damage_post(lc, t, 9999) == t.hp, "智将 at most the HP")


# ------------------------------------------------------------------ strategies (B3, B4 §D, B6 F5)
func _strategies() -> void:
	_clear()
	var c := _unit(0, 2, Vector2i(5, 5), 20, 50)
	var t := _unit(35, 300, Vector2i(5, 7), 20, 100)
	var h := Rules.strat_hit(c, t, 0, 0, 0)
	_check(h == 60, "curve 60 (%d)" % h)
	var dr := _unit(1, 185, Vector2i(5, 4))
	_check(Rules.strat_hit(c, t, 0, 0, 0) == 60, "杜断: the real roll looks at the target")
	_check(Rules.strat_hit(c, t, 0, 0, 0, true) == 80, "杜断 in the forecast: the caster")
	dr.clear(1)
	var de := _unit(36, 185, Vector2i(5, 8))
	_check(Rules.strat_hit(c, t, 0, 0, 0) == 80, "杜断 next to the target on its side")
	de.clear(36)
	# 房谋 and 节约MP
	var s := 41
	var base := int(Game.strategy(s).get("mp", 0))
	_check(st.actions.strategy_cost(c, s) == base, "plain cost")
	_unit(2, 179, Vector2i(6, 6))
	_check(st.actions.strategy_cost(c, s) == base >> 1, "房谋 halves")
	c.person.armor = 51          # 孔明鹤氅: 节约MP 50 %
	c.person.armor_lvl = 1
	_check(st.actions.strategy_cost(c, s) == maxi((base - base * 50 / 100) >> 1, 1), "节约MP, then 房谋")
	c.person.armor = -1
	# 逐影随行咒 and 烈魔
	var sl := _unit(37, 35, Vector2i(10, 10))
	_check(st.actions.strategy_cast_cells(sl, 0).size() == Shapes.range_cells(13, sl.pos, st.view.map_w, st.view.map_h).size(), "逐影随行咒: range 13")
	_check(st.actions.strategy_area(sl, 0, Vector2i(10, 12)).size() == 1, "no 烈魔 yet")
	Mem.set_ev(3985, 35)
	_check(st.actions.strategy_area(sl, 0, Vector2i(10, 12)).size() == 5, "烈魔: area 0 → 1")
	Mem.set_ev(3985, 1024)
	# 秦琼 as 统军 learns 补给 and 救护
	var qq := _unit(3, 8, Vector2i(1, 1), 40, 100, 43)
	var known := st.actions.known_strategies(qq)
	_check(41 in known and 43 in known and 61 in known, "统军 秦琼: 补给 救护")
	var other := _unit(4, 9, Vector2i(1, 2), 40, 100, 43)
	_check(not (41 in st.actions.known_strategies(other)), "other 统军 do not")


func _strategy_casts() -> void:
	_clear()
	Mem.set_ev(3985, 35)
	var sl := _unit(37, 35, Vector2i(10, 10), 60, 400)
	var t := _unit(0, 2, Vector2i(10, 12), 20, 50)
	t.person.hp_base = 9999
	t.hp = t.max_hp()
	t.status = BUnit.ST_CONFUSION
	var one := Rules.strat_damage(sl, t, 0, true)
	var hp0 := t.hp
	await st.actions.cast(sl, 0, t.pos)
	_check(hp0 - t.hp > one + 4, "烈魔: the damage twice (%d, one %d)" % [hp0 - t.hp, one])
	Mem.set_ev(3985, 1024)
	# 暗鬼 gives the caster the MP it took
	_clear()
	var c := _unit(0, 2, Vector2i(5, 5), 60, 400)
	var e := _unit(35, 300, Vector2i(5, 6))
	e.status = BUnit.ST_CONFUSION
	c.mp = 20
	var cost := st.actions.strategy_cost(c, 22)
	var emp := e.mp
	await st.actions.cast(c, 22, e.pos)
	_check(c.mp == mini(20 - cost + (emp - e.mp), c.max_mp()), "暗鬼 MP to the caster")


# ------------------------------------------------------------------ on-hit skills (B1 F6/F7/F8)
func _on_hit() -> void:
	_clear()
	var lsm := _unit(0, 67, Vector2i(5, 5), 30)
	var t := _unit(35, 300, Vector2i(6, 5), 20)
	t.person.hp_base = 9999
	t.hp = t.max_hp()
	t.status = BUnit.ST_CONFUSION
	await st.actions.strikes(lsm, t)
	_check(t.status & BUnit.ST_LOST, "梦魇")
	var hi := _unit(36, 301, Vector2i(5, 6), 40)
	hi.person.hp_base = 9999
	hi.hp = hi.max_hp()
	hi.status = BUnit.ST_CONFUSION
	await st.actions.strikes(lsm, hi)
	_check(not (hi.status & BUnit.ST_LOST), "梦魇 not on a higher level")
	# 张善相 poisons on maps up to 34, hit or not
	_clear()
	var zs := _unit(35, 204, Vector2i(5, 5))
	var p := _unit(0, 2, Vector2i(5, 6))
	p.person.hp_base = 9999
	p.hp = p.max_hp()
	await st.actions.strikes(zs, p)
	_check(p.status & BUnit.ST_POISON, "张善相 poison")
	p.status = 0
	Mem.w32(Skills.MAP_NO, 35)
	await st.actions.strikes(zs, p)
	_check(not (p.status & BUnit.ST_POISON), "not on map 35")
	Mem.w32(Skills.MAP_NO, 5)
	# 谢映登's 贯石: damage also from MP
	_clear()
	var a := _unit(35, 300, Vector2i(5, 5), 50, 300)
	var x := _unit(0, 24, Vector2i(5, 6))
	x.person.hp_base = 9999
	x.hp = x.max_hp()
	x.status = BUnit.ST_CONFUSION
	x.mp = 200
	Mem.w32(Mem.EV + 4 * 3223, 3)
	var hp0 := x.hp
	await st.actions.strikes(a, x)
	_check(x.mp == maxi(200 - (hp0 - x.hp), 0) or (hp0 - x.hp) > 200, "贯石 MP loss")
	Mem.w32(Mem.EV + 4 * 3223, 0)


# ------------------------------------------------------------------ terrain (B5 F10)
func _terrain() -> void:
	_clear()
	var sx := _unit(0, 4, Vector2i(1, 1), 20, 100, 0)       # family 0: 山地 (4) costs 2
	_check(Rules.move_cost(sx, 4) == 2, "plain cost")
	sx.person.accessory = 0x2f
	Mem.w32(Mem.EV + 4 * 3190, 3)
	_check(Rules.move_cost(sx, 4) == 1, "单雄信 on 板角墨麒麟")
	Mem.w32(Mem.EV + 4 * 3190, 2)
	_check(Rules.move_cost(sx, 4) == 2, "only from EV[3190] 3")
	var zg := _unit(1, 25, Vector2i(1, 2), 20, 100, 41)      # family 15: 山地 costs 3
	_check(Rules.move_cost(zg, 4) == 2 and Rules.move_cost(zg, 0) == 1, "飞将军: one less, not below 1")
	var dt := _unit(2, 6, Vector2i(1, 3), 20, 100, 0)
	_check(Rules.move_cost(dt, 9) == 1 and Rules.move_cost(dt, 10) == 1 and Rules.terrain_effect(dt, 13) == 11, "水军")
	var hb := _unit(3, 2, Vector2i(1, 4), 20, 100, 41)
	hb.person.accessory = 61    # 黄骠马: 辅助地形移动
	_check(Rules.move_cost(hb, 4) == 2, "effect 86: one less")
	hb.person.accessory = 62    # 虎类豹: effect 34
	_check(Rules.move_cost(hb, 4) == 1, "effect 34: 1")


# ------------------------------------------------------------------ persons (B2 §E, §I)
func _person_skills() -> void:
	var y := Game.person(9)
	var bow := -1
	Mem.set_ev(3979, 1024)
	for it in Game.items_db:
		var i := int(it["id"])
		if Person.slot_of(it) == 0 and not y.can_equip(i):
			bow = i
			break
	Mem.set_ev(3979, 9)
	_check(bow >= 0 and y.can_equip(bow), "百宝: any weapon")
	Mem.set_ev(3979, 1024)
	var fh := Game.person(11)
	var acc := -1
	for it in Game.items_db:
		if Person.slot_of(it) == 2 and int(it.get("growth", 0)) == 0xff:
			acc = int(it["id"])
			break
	_check(acc >= 0 and not fh.can_equip(acc) and Game.person(2).can_equip(acc), "樊虎 wears no accessory")
	# 天运: one stat grows one more per level-up
	var sy := Game.person(10)
	var ref := Game.person(15)
	for pp in [sy, ref]:
		pp.cls = 0
		pp.level = 10
		pp.fixed_growth_flag = 1
		pp.bonus_counter = 0
		for i in 5:
			pp.set_stat_word(i, 100)
			pp.set_raw(i, 80)
	var g1: Array = sy.level_up(1)
	var g2: Array = ref.level_up(1)
	var d := 0
	for i in 5:
		d += int(g1[i]) - int(g2[i])
	_check(d == 1, "天运 +1 (%d)" % d)


# ------------------------------------------------------------------ 锻造 / 波若 (B5 F7)
func _path_skills() -> void:
	_clear()
	var qg := _unit(0, 16, Vector2i(4, 2))
	var ally := _unit(1, 2, Vector2i(3, 2))
	ally.person.weapon = 0
	ally.person.weapon_lvl = 1
	ally.person.weapon_exp = 5
	ally.person.armor = 0x26
	ally.person.armor_lvl = 1
	ally.person.armor_exp = 7
	Mem.w32(BattleStage.CMD_PID, 16)
	Mem.w8(0x55ac60, 16)
	st.record_path(Vector2i(2, 2), [Vector2i(3, 2), Vector2i(4, 2)] as Array[Vector2i])
	await st.actions.end_action(qg)
	_check(ally.person.weapon_exp + ally.person.armor_exp == 13, "锻造: one experience point")
	Mem.w8(0x55ac60, 0)
	# 波若
	_clear()
	var lsx := _unit(0, 15, Vector2i(4, 2))
	var b := _unit(1, 2, Vector2i(3, 2))
	Mem.w32(BattleStage.CMD_PID, 15)
	Mem.w8(0x55ac48, 15)
	st.record_path(Vector2i(2, 2), [Vector2i(3, 2), Vector2i(4, 2)] as Array[Vector2i])
	await st.actions.end_action(lsx)
	var strong := 0
	for i in 5:
		if b.buff(i) == 6:
			strong += 1
	_check(strong == 1, "波若: a strong buff")
	Mem.w8(0x55ac48, 0)
	Mem.w8(BattleStage.PATH_LEN, 0)


# ------------------------------------------------------------------ kill rewards (B5 F8)
func _kill_rewards() -> void:
	_clear()
	var yc := _unit(0, 3, Vector2i(1, 1))
	yc.mp = 0
	Mem.set_ev(3183, 4)
	for slot in [35, 36]:
		var e := _unit(slot, 300 + slot if slot == 35 else 17, Vector2i(slot - 30, 5))
		e.hp = 0
	var before := Mem.ev(3007) + Mem.ev(3008) + Mem.ev(3009)
	st.actions.kill_rewards()
	var got := Mem.ev(3007) + Mem.ev(3008) + Mem.ev(3009) - before
	_check(got >= 0 and got <= 11, "辰屑 (%d)" % got)
	_check(yc.mp == mini(10, Game.person(3).mp_base), "尉迟恭 +5 MP per fallen enemy")
	Mem.set_ev(3183, 0)


# ------------------------------------------------------------------ 【技】 techniques (B3 F10, B1 F3 / F15-F17)
## Attacker `pid` (morale 9999, so the technique always triggers) against a sturdy, confused target.
func _duel(apid: int, aslot: int, dpid: int, dslot: int, dpos := Vector2i(6, 5)) -> Array:
	_clear()
	var a := _unit(aslot, apid, Vector2i(5, 5), 30, 300)
	a.person.set_stat_word(4, 9999)
	var d := _unit(dslot, dpid, dpos, 30, 100, 0)     # 游侠: strikes the four adjacent cells
	d.person.hp_base = 9999
	d.hp = d.max_hp()
	return [a, d]


func _techniques() -> void:
	st.actions.tracing = true
	# 龙吟: one level off the weapon or the armour
	var u := _duel(32, 35, 2, 0)
	var d: BUnit = u[1]
	d.status = BUnit.ST_CONFUSION
	d.person.weapon = 0
	d.person.weapon_lvl = 3
	d.person.armor = 0x26
	d.person.armor_lvl = 3
	await st.actions.attack_cmd(u[0], d)
	_check(d.person.weapon_lvl + d.person.armor_lvl == 5, "龙吟 −1 level")
	_check(Mem.r32(BattleActions.T_LONGYIN) == 0, "flags cleared")
	# 鬼门刀
	u = _duel(43, 35, 2, 0)
	d = u[1]
	d.status = BUnit.ST_CONFUSION
	await st.actions.attack_cmd(u[0], d)
	_check(d.buff(5) == 0 and (d.status & BUnit.ST_FEAR), "鬼门刀: 移动 0 and 怯")
	# 怒目
	u = _duel(4, 0, 300, 35)
	d = u[1]
	d.status = BUnit.ST_CONFUSION
	await st.actions.attack_cmd(u[0], d)
	_check(d.mp == 0, "怒目 drains the MP")
	# 盖马三锤: blows around 李元霸, then 怯 + 穷 within 4, no counter
	u = _duel(34, 35, 2, 0)
	var a: BUnit = u[0]
	d = u[1]
	var near := _unit(1, 3, Vector2i(5, 8))
	var hp0 := a.hp
	st.actions.trace.clear()
	await st.actions.attack_cmd(a, d)
	_check(a.hp == hp0, "盖马三锤: no counter")
	_check((d.status & 0x24) == 0x24 and (near.status & 0x24) == 0x24, "盖马三锤: 怯 and 穷 around")
	_check(Mem.r32(BattleActions.T_GAIMA) == 0, "盖马三锤 flag cleared")
	# 凤舞九天: area 2, the units around the target hit as well
	u = _duel(33, 35, 2, 0)
	d = u[1]
	d.status = BUnit.ST_CONFUSION
	var side := _unit(1, 3, Vector2i(7, 5))
	side.person.hp_base = 9999
	side.hp = side.max_hp()
	side.status = BUnit.ST_CONFUSION
	await st.actions.attack_cmd(u[0], d)
	_check(side.hp < side.max_hp(), "凤舞九天 splash")
	# 煞: three attacks while the target counters
	u = _duel(3, 0, 300, 35)
	a = u[0]
	d = u[1]
	a.person.hp_base = 9999
	a.hp = a.max_hp()
	d.person.set_stat_word(3, 1)       # slow: no doubles either way
	a.person.set_stat_word(3, 9999)
	st.actions.trace.clear()
	await st.actions.attack_cmd(a, d)
	var mine := 0
	for t in st.actions.trace:
		if t[0] == a.slot:
			mine += 1
	_check(mine == 3, "煞: three attacks (%d)" % mine)
	_check(Mem.r32(BattleActions.T_SHA) == 0, "煞 flag cleared")
	# ... but one when the target does not counter
	u = _duel(3, 0, 300, 35)
	u[1].status = BUnit.ST_CONFUSION
	st.actions.trace.clear()
	await st.actions.attack_cmd(u[0], u[1])
	_check(st.actions.trace.size() == 1, "煞 stops without a counter")
	# after a strike sequence that ended on a second strike, no technique (the AI's calls)
	u = _duel(3, 0, 300, 35)
	Mem.w8(BattleActions.STRIKE, 1)
	st.actions.trace.clear()
	await st.actions.attack_cmd(u[0], u[1])
	mine = 0
	for t in st.actions.trace:
		if t[0] == 0:
			mine += 1
	_check(mine == 1, "no technique while the strike counter is set")
	# 双雷引 (定彦平 attacking): the target strikes first, then his counter strikes twice
	u = _duel(101, 35, 2, 0)
	a = u[0]
	d = u[1]
	a.person.hp_base = 9999
	a.hp = a.max_hp()
	d.person.set_stat_word(3, 1)
	a.person.set_stat_word(3, 1)
	st.actions.trace.clear()
	await st.actions.attack_cmd(a, d)
	var tr := st.actions.trace
	_check(tr.size() == 2 and tr[0][0] == d.slot and tr[1][0] == a.slot and tr[1][2] == 2, "双雷引 %s" % str(tr))
	_check(Mem.r32(BattleActions.T_SHUANGLEI) == 0, "双雷引 flag cleared")
	# 抽屉枪 (姜松 attacked): he strikes first, twice
	u = _duel(2, 0, 14, 35)
	a = u[0]
	d = u[1]
	a.person.set_stat_word(4, 1)
	d.person.set_stat_word(4, 9999)
	a.person.hp_base = 9999
	a.hp = a.max_hp()
	a.person.set_stat_word(3, 9999)
	d.person.set_stat_word(3, 1)
	st.actions.trace.clear()
	await st.actions.attack_cmd(a, d)
	tr = st.actions.trace
	_check(tr.size() >= 1 and tr[0][0] == d.slot and tr[0][2] == 2, "抽屉枪 %s" % str(tr))
	# the 双雷引 hit penalty only against effect 55 (轩辕神枪)
	_clear()
	var h1 := _unit(0, 2, Vector2i(5, 5), 20, 100)
	var h2 := _unit(35, 300, Vector2i(6, 5), 20, 100)
	var base := Rules.hit_rate(h1, h2)
	Mem.w32(BattleActions.T_SHUANGLEI, 1)
	_check(Rules.hit_rate(h1, h2) == base, "no penalty without effect 55")
	h2.person.weapon = 23
	h2.person.weapon_lvl = 1
	var with55 := Rules.hit_rate(h1, h2)
	Mem.w32(BattleActions.T_SHUANGLEI, 0)
	var without := Rules.hit_rate(h1, h2)
	_check(with55 == (without - 26 if without > 26 else 1), "双雷引 penalty with effect 55")
	# effect 84 doubles in a counter too
	h1.person.weapon = 30
	h1.person.weapon_lvl = 1
	_check(Rules.double_rate(h1, h2, true) == 100, "effect 84 in a counter")
	st.actions.tracing = false
