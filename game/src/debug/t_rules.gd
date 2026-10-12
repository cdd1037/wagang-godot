extends Node
## General battle rules (docs/mod_patches.md group 4): 反应 / 士气 equipment as a percentage, 组阵, effect 37, 笼屉,
## 怀恨攻击, 太保令, the level-up penalty and report, SetExp past 70, 引导攻击, 策略模仿, 狂澜 against the commander,
## per-phase equipment experience, the combat object of a counterattack. Prints "t_rules: PASS".

var _ok := true
var st: BattleStage


func _check(ok: bool, what: String) -> void:
	if not ok:
		_ok = false
		print("t_rules: FAIL ", what)


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
	Mem.w32(BattleStage.SPECIAL_RUNNING, 0)
	Mem.fill(BUnit.GRUDGE, 115, 0)
	for k in 30:
		Mem.set_ev(Skills.DYN + k, 1024)
	st.boss_pid = -1
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

	_equip_percent()
	_formation()
	_effect37()
	await _bun()
	await _grudge()
	await _taibao()
	await _level_up()
	_guided()
	_imitation()
	_kuanglan()
	await _regen_exp()
	_exe_tables()

	Game.main = old_main
	print("t_rules: PASS" if _ok else "t_rules: FAILED")


# ------------------------------------------------------------------ 反应 / 士气 equipment (B2 §C)
func _equip_percent() -> void:
	_clear()
	var u := _unit(0, 1, Vector2i(5, 5))
	var p := u.person
	p.set_stat_word(3, 200)
	p.weapon = 25                     # 八卦宣花斧: 反应 +25 %
	p.weapon_lvl = 1
	_check(p.stat(3) == 250, "反应 +25 %% of 200: %d" % p.stat(3))
	p.weapon = 24                     # 瓦面金装锏: 士气 +20 %
	p.set_stat_word(4, 120)
	_check(p.stat(4) == 144, "士气 +20 %% of 120: %d" % p.stat(4))
	_check(p.stat(3) == 200, "no 反应 bonus without the axe")


# ------------------------------------------------------------------ 组阵 (B4 §C, B1 F10)
func _formation() -> void:
	_clear()
	var a := _unit(0, 2, Vector2i(5, 5), 20, 100, 18)        # 武师
	var n1 := _unit(1, 3, Vector2i(6, 5), 20, 100, 19)       # 教头, same family
	var n2 := _unit(2, 4, Vector2i(4, 4), 20, 100, 20)       # 团练, diagonal
	_unit(35, 300, Vector2i(5, 6), 20, 100, 18)              # an enemy 武师 does not count
	_unit(3, 5, Vector2i(5, 4), 20, 100, 0)                  # another family does not count
	_check(a.formation_count() == 2, "two formation neighbours: %d" % a.formation_count())
	_check(a.formation_agi() == 130, "武师 agility +30 %%: %d" % a.formation_agi())
	_check(a.formation_atk() == a.atk() and a.formation_def() == a.def(), "武师: only agility")
	n2.status = BUnit.ST_CONFUSION
	_check(a.formation_count() == 1, "a confused neighbour does not count")
	n2.status = BUnit.ST_LOST
	_check(a.formation_count() == 1, "a lost one neither")
	n2.status = 0
	# the double-attack curve sees it (a 130 vs d 100: (30·18 / 100) + 2 = 7)
	var d := _unit(36, 301, Vector2i(9, 9), 20, 100, 0)
	_check(Rules.double_rate(a, d, false) == 7, "double rate with 组阵: %d" % Rules.double_rate(a, d, false))
	n1.state = BUnit.STATE_NONE
	n2.state = BUnit.STATE_NONE
	_check(Rules.double_rate(a, d, false) == 2, "double rate alone: %d" % Rules.double_rate(a, d, false))
	# 狄骑 (46): attack and defence; 战车 (47): attack; 燕云骑 (39): defence
	_clear()
	var di := _unit(0, 2, Vector2i(5, 5), 20, 100, 46)
	_unit(1, 3, Vector2i(5, 6), 20, 100, 46)
	_check(di.formation_atk() == 115 and di.formation_def() == 115 and di.formation_agi() == di.agi(), "狄骑 +15 %% attack and defence")
	var t := _unit(35, 300, Vector2i(5, 4), 20, 100, 0)
	var with := Rules.calc_damage(di, t, 0, 0, false, 0)
	st.units[1].state = BUnit.STATE_NONE
	var without := Rules.calc_damage(di, t, 0, 0, false, 0)
	_check(with > without, "CalcDamage takes the formation attack: %d vs %d" % [with, without])
	_clear()
	var ch := _unit(0, 2, Vector2i(5, 5), 20, 100, 47)
	_unit(1, 3, Vector2i(6, 6), 20, 100, 47)
	_check(ch.formation_atk() == 115 and ch.formation_def() == ch.def(), "战车: attack only")
	var yy := _unit(2, 4, Vector2i(9, 9), 20, 100, 39)
	_unit(3, 5, Vector2i(9, 8), 20, 100, 39)
	_check(yy.formation_def() == 115 and yy.formation_atk() == yy.atk(), "燕云骑: defence only")


# ------------------------------------------------------------------ effect 37 (B1 F5)
func _effect37() -> void:
	_clear()
	var a := _unit(0, 2, Vector2i(5, 5))
	var t := _unit(35, 300, Vector2i(5, 4))
	a.person.weapon = 28              # 八棱梅花锤
	a.person.weapon_lvl = 9
	var bits := [BUnit.ST_PARALYSIS, BUnit.ST_SEAL, BUnit.ST_CONFUSION, BUnit.ST_POISON, BUnit.ST_FEAR, BUnit.ST_LOST]
	var rates := [60, 40, 10, 15, 20, 30]
	for trial in 20:
		t.status = 0
		var s0 := Rules.rng.state
		st.actions._random_statuses(a, t)
		var got := t.status
		Rules.rng.state = s0
		var want := 0
		for k in 6:
			if Rules.chance(rates[k]):
				want |= bits[k]
		if got != want:
			_check(false, "effect 37 rolls: %x vs %x" % [got, want])
			return


# ------------------------------------------------------------------ 笼屉 (B1 F8, B3 F2)
func _bun() -> void:
	_clear()
	while Game.stack_count(BattleActions.BUN) > 0:
		Game.remove_item_id(BattleActions.BUN)
	var r := _unit(0, 2, Vector2i(5, 5))
	r.person.accessory = 81
	r.hp = r.max_hp() - 150
	await st.actions._strategy_bun(r, 10)
	_check(r.hp == r.max_hp() - 150, "a red unit without 馒头 in the bag eats nothing")
	Game.add_item(BattleActions.BUN)
	Game.add_item(BattleActions.BUN)
	await st.actions._strategy_bun(r, 10)
	_check(r.hp == r.max_hp() - 80 and Game.stack_count(BattleActions.BUN) == 1, "a red unit eats one from the bag")
	await st.actions._strategy_bun(r, 10)
	_check(r.hp == r.max_hp() - 80, "a red unit less than 100 down does not")
	var e := _unit(35, 300, Vector2i(9, 9))
	e.person.accessory = 81
	e.hp = e.max_hp() - 30
	await st.actions._strategy_bun(e, 30)
	_check(e.hp == e.max_hp() and Game.stack_count(BattleActions.BUN) == 1, "after a strategy any other unit eats one for free")
	# a physical strike: from 100 down for both sides, red from the bag
	e.person.set_stat_word(0, 400)
	r.hp = r.max_hp() - 120
	r.status = BUnit.ST_CONFUSION     # no counterattack
	Mem.w32(BattleStage.SPECIAL_RUNNING, 1)       # one sure strike
	var before := r.hp
	await st.actions.strikes(e, r)
	Mem.w32(BattleStage.SPECIAL_RUNNING, 0)
	_check(r.hp > 0 and Game.stack_count(BattleActions.BUN) == 0, "the struck red unit ate the last 馒头 (HP %d → %d)" % [before, r.hp])


# ------------------------------------------------------------------ 怀恨攻击 (B4 §E, B5 F12) and the combat object
func _grudge() -> void:
	_clear()
	var a := _unit(35, 300, Vector2i(5, 4))
	var d := _unit(0, 2, Vector2i(5, 5), 20, 100)
	d.status = BUnit.ST_CONFUSION
	Mem.w32(BattleStage.SPECIAL_RUNNING, 1)
	Mem.w32(Rules.PREV_TARGET, 0)
	await st.actions.strikes(a, d)
	Mem.w32(BattleStage.SPECIAL_RUNNING, 0)
	_check(Mem.r8(BUnit.GRUDGE + 0) == 1 and Mem.r8(BUnit.GRUDGE + 35) == 0, "a hit counts for the target: %d" % Mem.r8(BUnit.GRUDGE))
	# the counter multiplies the attacker's own damage, ×(10 + n) / 10
	d.status = 0
	d.person.armor = 46               # 天玉玲珑铠
	d.person.armor_lvl = 1
	Mem.w8(BUnit.GRUDGE + 0, 0)
	var d0 := Rules.calc_damage(d, a, 0, 0, false, 0)
	Mem.w8(BUnit.GRUDGE + 0, 5)
	var d5 := Rules.calc_damage(d, a, 0, 0, false, 0)
	_check(d5 == d0 * 15 / 10, "怀恨攻击 ×1.5 with 5 hits: %d vs %d" % [d5, d0])
	_check(Rules.calc_damage(d, a, 0, 0, false, 1) == Rules.calc_damage(d, a, 0, 0, false, 1), "not in a counterattack")
	Mem.w8(BUnit.GRUDGE + 0xff, 0)
	Mem.w8(BUnit.GRUDGE + 40, 4)
	await st.phase_fx._phase_start_effects(0, 35)
	_check(Mem.r8(BUnit.GRUDGE + 40) == 0 and Mem.r8(BUnit.GRUDGE + 0) == 5, "the player phase clears the enemy counters")
	await st.phase_fx._phase_start_effects(35, 115)
	_check(Mem.r8(BUnit.GRUDGE + 0) == 0, "the enemy phase clears the player-side counters")
	# a counterattack rewrites the combat object (0x40639a → 0x4064f1 → 0x4061fc)
	_clear()
	var x := _unit(35, 300, Vector2i(5, 4))
	var y := _unit(0, 2, Vector2i(5, 5))
	y.hp = 9999
	y.person.hp_base = 9999
	y.hp = y.max_hp()
	await st.actions.attack(x, y)
	_check(Mem.r8(0x4927f0) == y.slot and Mem.r8(0x4927f1) == x.slot, "after the counterattack: %d / %d" % [Mem.r8(0x4927f0), Mem.r8(0x4927f1)])


# ------------------------------------------------------------------ 太保令 (B2 §Q)
func _taibao() -> void:
	_clear()
	var u := _unit(0, 2, Vector2i(5, 5), 20, 100)
	u.person.set_stat_word(4, 9998)
	u.person.set_raw(2, 99)
	await st.actions.use_item(u, {"id": 96, "slot": -1}, u)
	var p := u.person
	_check(p.get_stat_word(0) == 102 and p.get_stat_word(4) == 9999, "stat words +2, at most 9999")
	_check(p.get_raw(0) == 52 and p.get_raw(2) == 100, "abilities +2, at most 100")
	var buffs := true
	for i in 5:
		buffs = buffs and u.buff(i) == 3
	_check(buffs, "no buff")


# ------------------------------------------------------------------ level-up (B2 §E / §F)
func _level_up() -> void:
	_clear()
	_unit(0, 3, Vector2i(1, 1), 10)
	_unit(1, 4, Vector2i(2, 1), 10)
	var u := _unit(2, 5, Vector2i(3, 1), 30, 100, 0)
	var p := u.person
	var growth: Dictionary = Game.cls(0)["growth"]
	p.fixed_growth_flag = 0
	u.hp = u.max_hp() - 100
	var hp_before := u.hp
	var g := p.level_up(1)
	# average ceil(50 / 3) = 17: 13 less; q = 520 / 500 = 1 for HP, 30 / 50 = 0 for MP
	_check(g[5] == int(growth["hp"]) - 13, "HP growth less the penalty: %d" % g[5])
	_check(g[6] == int(growth["mp"]) - 13, "MP growth less the penalty: %d" % g[6])
	_check(u.hp == mini(hp_before + int(growth["hp"]), u.max_hp()), "the unit gets the class's HP growth")
	p.fixed_growth_flag = 0xff
	var g2 := p.level_up(1)
	_check(g2[5] == int(growth["hp"]), "no penalty for others")
	# the report: by default only the level line, then the strategies learnt at the new level
	p.fixed_growth_flag = 0xff
	p.level = 14
	var g3 := p.level_up(1)
	Mem.w8(0x4dbe25, 0)
	var texts := p.level_up_texts(g3)
	_check(texts[0] == "%s升为15级。" % p.name, "level line: %s" % texts[0])
	_check("学会了策略「焦热」！" in texts, "learnt 焦热 at 15: %s" % [texts])
	Mem.w8(0x4dbe25, 1)
	g3[5] = -4
	var detail := p.level_up_texts(g3)[0]
	_check(detail.begins_with("%s升为15级。\n\n攻击增加了 " % p.name) and "HP MAX减少了 4。" in detail, "detailed: %s" % detail)
	Mem.w8(0x4dbe25, 0)
	# SetExp keeps going past 70 while the rest is 100 or more
	p.level = 69
	p.exp = 50
	await st.actions.set_exp(p, 300)
	_check(p.level == 72 and p.exp == 0xff, "SetExp 69 + 300 → %d, exp %d" % [p.level, p.exp])
	# the grade bonus is one count for everyone
	p.bonus_counter = 5
	_check(Game.person(3).bonus_counter == 5, "bonus counter is global")
	p.bonus_counter = 0


# ------------------------------------------------------------------ 引导攻击 (B5 0x43db51)
func _guided() -> void:
	_clear()
	var a := _unit(0, 2, Vector2i(5, 5))
	var e1 := _unit(35, 300, Vector2i(5, 4))
	var e2 := _unit(36, 301, Vector2i(6, 5))
	_unit(1, 3, Vector2i(4, 5))       # own side: never
	var last: BUnit = null
	var first: BUnit = null
	for c in st.actions.attack_cells(a, a.pos):
		var x := st.unit_on(c)
		if x != null and x.slot >= 35:
			if first == null:
				first = x
			last = x
	Mem.w8(BattleActions.PREFERRED, 0xff)
	_check(st.actions.guided_target(a) == last, "the last of the range")
	Mem.w8(BattleActions.PREFERRED, first.slot)
	_check(st.actions.guided_target(a) == first, "the preferred one")
	e1.hp = 0
	e2.hp = 0
	_check(st.actions.guided_target(a) == null, "fallen units are not taken")


# ------------------------------------------------------------------ 策略模仿 (B6 F5)
func _imitation() -> void:
	_clear()
	var c := _unit(0, 2, Vector2i(5, 5), 1, 100, 0)
	var nb := _unit(35, 300, Vector2i(5, 4), 40, 100, 29)
	_unit(1, 3, Vector2i(6, 6), 40, 100, 50)      # diagonal: not copied
	c.person.accessory = 76           # 孙子兵法
	var known := st.actions.known_strategies(c)
	_check(9 in known and 10 in known, "copies the neighbour's strategies: %s" % [known])
	_check(not (9 in st.actions.learned_strategies(c)), "the AI list does not")
	c.person.accessory = -1
	_check(not (9 in st.actions.known_strategies(c)), "only with 策略模仿")
	nb.state = BUnit.STATE_NONE


# ------------------------------------------------------------------ 狂澜 (B4 notes)
func _kuanglan() -> void:
	_clear()
	var c := _unit(0, 2, Vector2i(5, 5), 40, 100, 29)
	var boss := _unit(36, 301, Vector2i(5, 3))
	var other := _unit(37, 302, Vector2i(6, 3))
	st.boss_pid = 301
	_check(Rules.strat_hit(c, boss, 9, 7, 0) == 0, "狂澜 cannot hit the commander")
	c.person.weapon = 36              # 七星法剑: effect 52, +40
	c.person.weapon_lvl = 1
	_check(Rules.strat_hit(c, boss, 9, 7, 0) == 40, "but the modifiers after it still add: %d" % Rules.strat_hit(c, boss, 9, 7, 0))
	_check(Rules.strat_hit(c, other, 9, 7, 0) > 40, "others: a third of the curve + 40")
	st.boss_pid = -1


# ------------------------------------------------------------------ per-phase equipment experience (0x43cf26)
func _regen_exp() -> void:
	_clear()
	var u := _unit(0, 2, Vector2i(5, 5))
	var p := u.person
	p.weapon = 0
	p.weapon_lvl = 1
	p.weapon_exp = 0
	p.armor = 38                      # 乌油甲
	p.armor_lvl = 1
	p.armor_exp = 0
	p.accessory = 79                  # 轩辕宝鉴: weapon +3 a phase
	await st.phase_fx._regen(u)
	_check(p.weapon_exp == 3 and p.armor_exp == 0, "轩辕宝鉴: weapon %d armour %d" % [p.weapon_exp, p.armor_exp])
	p.accessory = 80                  # 天闻录: armour
	await st.phase_fx._regen(u)
	_check(p.weapon_exp == 3 and p.armor_exp == 3, "天闻录: armour %d" % p.armor_exp)
	u.colour = 1
	await st.phase_fx._regen(u)
	_check(p.armor_exp == 3, "red units only")


## The tables Rules reads from the program image (0x43c35c power, 0x42093c category, 0x43ffc4 mounted families)
## give what the hard-coded copies they replaced did, and a patched byte (a mod's exe_image.bin) changes them.
func _exe_tables() -> void:
	var power := {0: 75, 1: 90, 2: 50, 3: 70, 4: 100, 5: 75, 6: 90, 7: 50, 8: 70, 9: 100, 10: 50, 11: 75, 12: 40,
		13: 60, 14: 20, 15: 70, 16: 100, 17: 60, 18: 90, 19: 120, 20: 70, 22: 20, 33: 70, 34: 50, 35: 60, 36: 40,
		38: 120, 64: 70, 65: 100}
	var cat := [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 4, 17, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 7, 8,
		8, 9, 9, 10, 17, 11, 11, 11, 11, 11, 15, 15, 13, 13, 17, 14, 14, 14, 14, 14, 14, 14, 14, 15, 17, 17, 17, 16]
	for s in 0x48:
		_check(Rules.strat_power(s) == int(power.get(s, 0)), "strategy %d power %d" % [s, Rules.strat_power(s)])
		_check(Rules.strat_category(s) == (cat[s] if s < cat.size() else -1), "strategy %d category" % s)
	for f in 32:
		_check(Rules.mounted_family(f) == (f in [0, 3, 5, 7, 11, 12, 13, 15, 16, 17, 20, 24]), "family %d mounted" % f)
	Mem.w8(Rules.STRAT_POWER_TABLE, 150)
	_check(Rules.strat_power(0) == 150, "a patched power byte is read")
	Mem.w8(Rules.STRAT_POWER_TABLE, 75)
