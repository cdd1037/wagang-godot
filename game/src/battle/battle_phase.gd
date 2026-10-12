class_name BattlePhase
extends RefCounted
## The work at the start of each side's phase (docs/rules.md §9; 0x44ed93 / 0x44e851): the 暗杀 countdown, the
## phase-start skills and auras, status recovery, buff decay, regeneration.

var st: BattleStage


func _init(s: BattleStage) -> void:
	st = s


# ------------------------------------------------------------------ per-phase effects (§9)
## Phase start of side a..b (0x44ed93 / 0x44e851, after the event poll): status recovery and buff decay, the
## other side's 怀恨攻击 counters cleared (0x4d0d0e), 战备 reset, the 暗杀 countdown of the other side, poison,
## regeneration.
func _phase_start_effects(a: int, b: int) -> void:
	for i in range(a, b):
		var u := st.units[i]
		if not u.active():
			continue
		await _phase_skills(u)
		await _status_recovery(u)
		_buff_decay(u)
		Mem.w32(0x55ee00, Mem.r32(0x55ee04))       # 并蒂: the hit counts of the last phase (0x4d1e21)
	if a == 0:
		Mem.fill(BUnit.GRUDGE + 35, 80, 0)          # 0x44ee15
	else:
		Mem.fill(BUnit.GRUDGE, 35, 0)               # 0x44e914
	Mem.fill(Rules.ZHANBEI_USED + a, b - a, 0)     # 战备 may be cast again (0x44ed93 / 0x44e851)
	if a == 0:
		await _assassination_countdown(35, 115)    # 0x4364c6
	else:
		await _assassination_countdown(0, 35)      # 0x4364b6
	for i in range(a, b):
		var u := st.units[i]
		if u.active() and (u.status & BUnit.ST_POISON):
			var dmg := u.max_hp() / (10 if (i >= 35 and u.pid < 210) else 5)
			u.hp = maxi(u.hp - maxi(dmg, 1), 1)
	for i in range(a, b):
		var u := st.units[i]
		if u.active():
			await _regen(u)
	st.refresh_units()


## 暗杀 countdown (0x4364d6 → 0x40937f) for the on-map units of slots a..b: a mark counts down; when it reaches
## 0 while its assassin is still set, the unit drops to 1 HP, EV[10] = 1 and "%s被暗杀了！！" is shown. The
## scripts' "合并所有HP0撤退" sections then make officers retreat; anyone else stays at 1 HP.
func _assassination_countdown(a: int, b: int) -> void:
	for i in range(a, b):
		var u := st.units[i]
		if not u.exists() or u.state != BUnit.STATE_ON_MAP:
			continue
		var m := Mem.r8(BattleStage.ASSASSIN_MARK + i)
		if m == 0:
			continue
		m -= 1
		Mem.w8(BattleStage.ASSASSIN_MARK + i, m)
		if m == 0 and Mem.r8(BattleStage.ASSASSIN_LINK + i) != 0xff:
			u.hp = 1
			Mem.set_ev(10, 1)
			st.refresh_units()
			if not Game.autoplay:
				await st.view.ensure_visible(u.pos)
			await st.ui.message("%s被暗杀了！！" % u.person.name)
			Mem.w8(BattleStage.ASSASSIN_LINK + i, 0xff)


## The phase-start skills of a unit (0x401118, before its status recovery): 鲁明月's 云袖 (29), 柳周臣's 仙乐 (31),
## 天魔 (the person in [0x55ac40]; no script sets it), 魔功 (the person in [0x55ac44]: 杨素 from R_13), 尚师徒's
## 神将 (42) and every 雄师 (class family 16), on the units of the 3×3 around it (0x4011a9).
func _phase_skills(u: BUnit) -> void:
	var p := u.pid
	if p == 29:
		await _aura(u, false, 10, 0, func(t: BUnit) -> String:
			var h := mini(u.level() + 50, t.max_hp() - t.hp)   # 0x4d4966
			t.hp += h
			return "+%d" % h)
	if p == 31:
		await _aura(u, false, 11, 0, func(t: BUnit) -> String:
			var m := mini(u.level() / 4 + 1, t.max_mp() - t.mp)    # 0x4d4928
			t.mp += maxi(m, 0)
			return "策略 +%d" % m)
	if p == Mem.r32(0x55ac40):
		for t in _aura_units(u, false):
			for c in [0x31, 0x33, 0x35, 0x37]:
				st.actions._stat_code(t, c)       # code 0xaf through 0x4224a8
	if p == Mem.r32(0x55ac44):
		for t in _aura_units(u, true):
			await st.commands.change_unit(t, 6, BUnit.ST_POISON)    # code 0x70 through 0x4224a8
	if p == 42:
		await _aura(u, false, 0x11, 0x22, func(t: BUnit) -> String:
			t.set_buff(0, 6)
			return "攻击↑")
	if u.family() == 16:
		await _aura(u, false, 0x10, 0x25, func(t: BUnit) -> String:
			t.set_buff(4, 6)
			return "士气↑")


## 0x4011a9: the units on the map in the 3×3 around `owner` (not itself), row by row, of its side by colour (0 and 1
## together, 2 and 3 together; `opposite` for 魔功).
func _aura_units(owner: BUnit, opposite: bool) -> Array[BUnit]:
	var out: Array[BUnit] = []
	var mine := owner.colour >= 2
	for y in range(maxi(owner.pos.y - 1, 0), owner.pos.y + 2):
		for x in range(maxi(owner.pos.x - 1, 0), owner.pos.x + 2):
			var t := st.unit_on(Vector2i(x, y))
			if t == null or t == owner or t.state != BUnit.STATE_ON_MAP:
				continue
			if ((t.colour >= 2) == mine) != opposite:
				out.append(t)
	return out


## 0x4d47af + 0x4d485d: apply `fx` to each own-side unit around `owner`, then Xben effect `e1` (and `e2`) on them
## with the camera on the first. 云袖 first plays 鲁明月's poses 12 and 1 (0x43d108), even with no one around.
func _aura(owner: BUnit, opposite: bool, e1: int, e2: int, fx: Callable) -> void:
	var ts := _aura_units(owner, opposite)
	if owner.pid == 29:
		await st.unit_ops.op_unit_status({"args": [29, 12, 1, 0]})
		await st.unit_ops.op_unit_status({"args": [29, 1, 0, 0]})
	var texts := []
	for t in ts:
		texts.append(fx.call(t))
	st.refresh_units()
	if ts.is_empty() or Game.autoplay:
		return
	await st.view.ensure_visible(ts[0].pos)
	for e in [e1, e2]:
		if e == 0:
			continue
		var last: EffectPlayer = null
		for t in ts:
			var fxp := EffectPlayer.create("xben", e)
			if fxp:
				fxp.position = st.view.cell_center(t.pos)
				fxp.z_index = 10
				st.view.fx_layer.add_child(fxp)
				last = fxp
		if last:
			await last.done
	for k in ts.size():
		st.hud.popup_number(texts[k], ts[k].pos, Color(0.4, 1, 0.4))


## StatusRecovery (0x43c7d6). 魏征 (23, 【术】明镜, mod 0x43c80a): a unit with a status that he stands next to, on
## its side, is cured of all of them at once, without the usual rolls.
func _status_recovery(u: BUnit) -> void:
	if u.status == 0:
		return
	if Skills.beside(23, u):
		await st.commands.change_unit(u, 6, 0xfe)
		return
	var r := 100 if u.has_effect(20) else u.person.get_raw(4)
	var s := u.status
	for bit in [BUnit.ST_PARALYSIS, BUnit.ST_SEAL, BUnit.ST_POISON]:
		if s & bit and Rules.chance(r):
			s &= ~bit
	for bit in [BUnit.ST_FEAR, BUnit.ST_LOST]:
		if s & bit and (r == 100 or Rules.chance(r - r / 10)):
			s &= ~bit
	if s & BUnit.ST_CONFUSION and (r == 100 or Rules.chance(maxi(Rules.sat_sub(r, 15), 10))):
		s &= ~BUnit.ST_CONFUSION
	u.status = s


func _buff_decay(u: BUnit) -> void:
	var raw4 := u.person.get_raw(4)
	var q := 10 if raw4 > 50 else Rules.sat_sub(60, raw4)
	var r := 100 if u.has_effect(20) else raw4
	for i in 6:
		var b := u.buff(i)
		if b >= 5:
			b -= 1
		elif b <= 1:
			b += 1
		elif b == 4 and Rules.chance(q):
			b = 3
		elif b == 2 and Rules.chance(r):
			b = 3
		u.set_buff(i, b)


## Regen (0x43cddd): terrain and effect-18 HP, effect-19 MP (with effect 82's drain), at most what is missing.
## A red unit (0x43ff54) also gets experience each phase: effect 64 for the person, 轩辕宝鉴 (22) for the weapon
## and 天闻录 (23) for the armour, each its value × ((100 + EXP bonus) mod 256) / 100 (0x4072bd), through SetExp
## and 0x4082d6.
func _regen(u: BUnit) -> void:
	var heal := 0
	var t := st.view.terrain_at(u.pos)
	var pct := {18: 25, 19: 20, 20: 20, 21: 15, 22: 20}
	if pct.has(t):
		heal = u.max_hp() * int(pct[t]) / 100
	if u.has_effect(18):
		heal += u.max_hp() / maxi(u.effect_value(18), 1)
	heal = mini(heal, u.max_hp() - u.hp)
	if heal > 0:
		u.hp += heal
	var mp := u.effect_value(19) if u.has_effect(19) else 0
	if u.has_effect(82):
		mp += _drain_mp(u, u.effect_value(82))
	mp = mini(mp, u.max_mp() - u.mp)
	if mp > 0:
		u.mp += mp
	if u.colour != 0:
		return
	var p := u.person
	var mult := (100 + (p.equip_bonus(8) & 0xff)) & 0xff
	var e := (p.effect_value(64) & 0xff) * mult / 100 if p.has_effect(64) else 0
	Mem.w32(0x55ee04, 0)               # 并蒂's counters start again (0x43cf75 → 0x4d1dff)
	var we := (p.effect_value(22) & 0xff) * mult / 100 if p.has_effect(22) else 0
	var ae := (p.effect_value(23) & 0xff) * mult / 100 if p.has_effect(23) else 0
	if e > 0:
		await st.actions.gain_exp(u, e)
	if we > 0:
		await st.actions.add_equip_exp(p, true, we)
	if ae > 0:
		await st.actions.add_equip_exp(p, false, ae)


## Effect 82 in the MP regeneration (0x4d7efa): up to its value of MP from each unit of the other side in the 3×3
## around u, added to u's. The only effect-82 item (六军镜·阴阳) has the value 0.
func _drain_mp(u: BUnit, v: int) -> int:
	var total := 0
	for y in range(u.pos.y - 1, u.pos.y + 2):
		for x in range(u.pos.x - 1, u.pos.x + 2):
			var e := st.unit_on(Vector2i(x, y))
			if e == null or e == u or e.state != BUnit.STATE_ON_MAP or (e.slot < 35) == (u.slot < 35):
				continue
			var take := mini(e.mp, v)
			e.mp -= take
			total += take
	return total
