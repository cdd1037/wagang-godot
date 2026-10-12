class_name BattleCommands
extends RefCounted
## The battle commands the mod adds (docs/mod_patches.md B5 F1-F3): 绝招, 围攻 and 交给, and ChangeUnit.

var st: BattleStage


func _init(s: BattleStage) -> void:
	st = s


# ------------------------------------------------------------------ ChangeUnit
const STAT_NAMES := ["攻击", "防御", "精神", "爆发", "士气", "移动"]
## Xben effect of 0x43e69f for a buff going [down, up].
const BUFF_FX := [[0x27, 0x22], [0x28, 0x23], [0x27, 0x22], [0x29, 0x24], [0x2a, 0x25], [0x2f, 0x2e]]


## ChangeUnit (0x45aa5c), what 0..6: buff `what` (0 攻击 1 防御 2 精神 3 爆发 4 士气 5 移动) = value, or (6) the
## status bits in value set, cleared when value & 0x80. The unit must be on the map; `anim` shows 0x43e69f first.
func change_unit(u: BUnit, what: int, value: int, anim := true) -> void:
	if u == null or not u.exists() or u.state != BUnit.STATE_ON_MAP:
		return
	if anim:
		await _change_fx(u, what, value)
	if what < 6:
		u.set_buff(what, value)
	elif value & 0x80:
		u.status = u.status & ~value & 0x7f
	else:
		u.status = u.status | value
	st.refresh_units()


## 0x43e69f: the effect for a buff going up or down (none when it stays), a cure, or the status set.
func _change_fx(u: BUnit, what: int, value: int) -> void:
	var fx := -1
	var text := ""
	if what < 6:
		var cur := u.buff(what)
		if value != cur:
			fx = BUFF_FX[what][1 if value > cur else 0]
			text = STAT_NAMES[what] + ("↑" if value > cur else "↓")
	elif value & 0x80:
		fx = 0x2c
	else:
		for b in [[2, 0x32], [4, 0x33], [8, 0x30], [0x10, 0x31]]:
			if value & b[0]:
				fx = b[1]
	if fx < 0 or Game.autoplay:
		return
	await st.view.ensure_visible(u.pos)
	if text != "":
		st.hud.popup_number(text, u.pos, Color(1, 0.9, 0.4) if text.ends_with("↑") else Color(0.7, 0.6, 1))
	var e := EffectPlayer.create("xben", fx)
	if e:
		e.position = st.view.cell_center(u.pos)
		e.z_index = 10
		st.view.fx_layer.add_child(e)
		await e.done


# ------------------------------------------------------------------ helpers
## Cells beside u in its facing direction etc.: unit dir 0 up, 1 right, 2 down, 3 left.
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


## 0x4401a8: u could stand on c — nobody there (in the occupancy grid, which keeps fallen units until they are
## removed) and the terrain passable for it.
func can_stand(u: BUnit, c: Vector2i) -> bool:
	if not st.view.in_bounds(c):
		return false
	var o := st.unit_on(c)
	if o != null and o != u:
		return false
	return Rules.move_cost(u, st.view.terrain_at(c)) < 255


## 0x4d3581: one blow of a 绝招 — the map darkened, then a single strike (0x4d2f1e → 0x4335a0).
func _blow(u: BUnit, t: BUnit) -> void:
	await st.view.set_dim(true)
	await st.actions.strikes(u, t)


func _banner(name: String) -> void:
	await st.view.set_dim(true)
	await st.ui.skill_banner(name)


# ------------------------------------------------------------------ 绝招 (B5 F1)
## The 绝招 entry is enabled for the commanded person (0x4d5444 on [0x4cf310]); MP is tested when it is used.
func special_enabled() -> bool:
	var pid := Mem.r32(BattleStage.CMD_PID)
	match pid:
		0, 7, 8:
			return true
		1:
			# 三板斧: once R_11 taught it ([0x55ac04]), while [0x55ac05] and [0x55ac06] are clear
			return Mem.r8(0x55ac04) != 0 and Mem.r8(0x55ac05) == 0 and Mem.r8(0x55ac06) == 0
		5:
			var u5 := st.unit_by_pid(5)
			return u5 != null and not (u5.status & BUnit.ST_PARALYSIS)
	if pid == Mem.ev(3974):
		return true             # 夺面鞭: the person in dynamic skill slot 4 (尉迟恭)
	return pid in [17, 19, 26]


## 绝招 (0x4d3007). The MP bar must be full, unless the person has 无限绝技 (effect 58) or a maximum of 1. The
## move then takes all MP. [0x4cf314] is set throughout, which changes ranges, hit, critical and defence.
## Returns true when the unit's action ended.
func special(u: BUnit) -> bool:
	if not special_enabled():
		await st.ui.message("无绝招")
		return false
	var mx := u.max_mp()
	if not u.has_effect(58) and mx != 1 and (u.mp & 0xff) != mx:
		await st.ui.message("MP未满")
		return false
	Mem.w32(BattleStage.SPECIAL_RUNNING, 1)
	var done := await _special_run(u)
	await st.view.set_dim(false)
	Mem.w32(BattleStage.SPECIAL_RUNNING, 0)
	return done


func _special_run(u: BUnit) -> bool:
	var pid := u.pid
	if pid == 7:
		return await _wei_zhen_ba_huang(u)
	# the attack picker with the 绝招 ranges (0x45533d mode 1); a cancel spends nothing
	var t := await st.input.pick_unit(st.actions.attack_cells(u, u.pos), func(x: BUnit) -> bool: return x.is_enemy_of(u) and x.active(), 1, u)
	if t == null:
		return false
	u.mp = 0
	if pid == 0:
		await _cang_long(u, t)
	elif pid == Mem.ev(3974):
		await _duo_mian_bian(u, t)
	elif pid == 1:
		await _san_ban_fu(u, t)
	elif pid == 5:
		await _ta_po_lian_ying(u, t)
	elif pid == 26:
		await _heng_sao(u, t)
	elif pid == 8:
		await _sha_shou_jian(u, t)
	elif pid == 17:
		await _jin_ming(u, t)
	elif pid == 19:
		await _hui_ma_qiang(u, t)
	return true


## 苍龙过阵枪 (管毅): a blow, then 攻击 up for him and down for the target; the switches the scripts set add
## 防御 ([0x55ac08], 盘手拨云枪), 爆发 ([0x55ac0c]), 精神 ([0x55ac10]) and 士气 ([0x55ac14]) pairs.
func _cang_long(u: BUnit, t: BUnit) -> void:
	await _banner("苍龙过阵枪")
	await _blow(u, t)
	await st.view.set_dim(false)
	await change_unit(u, 0, 6)
	await change_unit(t, 0, 0)
	for p in [[0x55ac08, 1], [0x55ac0c, 3], [0x55ac10, 2], [0x55ac14, 4]]:
		if Mem.r32(p[0]) == 1:
			await change_unit(u, p[1], 6)
			await change_unit(t, p[1], 0)


## 夺面鞭 (the person in dynamic slot 4): 攻击 and 防御 up, then a blow.
func _duo_mian_bian(u: BUnit, t: BUnit) -> void:
	await _banner("夺面鞭")
	await change_unit(u, 0, 6)
	await change_unit(u, 1, 6)
	await _blow(u, t)


## 三板斧 (程咬金): up to three blows, each announced, while the target stands; each rolls his hit chance.
func _san_ban_fu(u: BUnit, t: BUnit) -> void:
	st.actions.face(u, t.pos)
	await _banner("三板斧")
	for line in ["劈脑袋！", "掏耳朵！", "小鬼剔牙！"]:
		await st.unit_say(u.pid, line)
		await _blow(u, t)
		if t.hp <= 0:
			break


## 踏破连营 (伍云召), on an orthogonally adjacent target: the blow also hits the enemies lined up beyond it
## ([0x55ac64] → area code 12, at half damage). Then, unless paralysed, he charges through the enemies in a row
## to the first free cell he can enter (not past a unit of his own side or the map edge) and gains 机动, 防御 and
## 爆发.
func _ta_po_lian_ying(u: BUnit, t: BUnit) -> void:
	var d := Vector2i(0, -1 if t.pos.y < u.pos.y else 1) if u.pos.x == t.pos.x else Vector2i(-1 if t.pos.x < u.pos.x else 1, 0)
	await _banner("踏破连营")
	Mem.w32(0x55ac64, 1)
	await _blow(u, t)
	if not (u.status & BUnit.ST_PARALYSIS):
		var c := u.pos
		var path: Array[Vector2i] = []
		while true:
			c += d
			# 0x4d4d5e tests only x (0..width; its y is the top byte of the return address, 0), but an off-map
			# cell has no unit and terrain 0xff, whose cost (0x443070 reads family + 4's 城墙 cost) is 0xff:
			# the charge stops at every edge, as here
			if not st.view.in_bounds(c):
				break
			path.append(c)
			var x := st.unit_on(c)
			if x == null:
				if Rules.move_cost(u, st.view.terrain_at(c)) < 255:
					await st.actions.move_unit(u, path)
					await change_unit(u, 5, 6)
					await change_unit(u, 1, 6)
					await change_unit(u, 3, 6)
				break
			if x.slot < 35:
				break
		await st.view.set_dim(false)
	Mem.w32(0x55ac64, 0)


## 横扫千军 (雄阔海), on an orthogonally adjacent target: the five cells across his line of attack centred on it.
## He strikes every enemy there, the target last, then pushes each one cell on (0x4d8e67), curing 乱/麻/迷.
func _heng_sao(u: BUnit, t: BUnit) -> void:
	var cells: Array[Vector2i] = [t.pos]
	var a := Vector2i(1, 0) if u.pos.x == t.pos.x else Vector2i(0, 1)
	cells.append_array([t.pos - a, t.pos - 2 * a, t.pos + a, t.pos + 2 * a])
	st.actions.face(u, t.pos)
	if u.node and not Game.autoplay:
		await u.node.play_attack(u.dir)
	await st.unit_say(u.pid, "滚开,滚开!")
	await _banner("横扫千军")
	for i in [4, 3, 2, 1, 0]:
		var x := st.unit_on(cells[i])
		if x and x.slot >= 35:
			await _blow(u, x)
	var step: Vector2i = DIRS[u.dir]
	for c in cells:
		var x := st.unit_on(c)
		if x and x.slot >= 35 and can_stand(x, c + step):
			x.status = x.status & ~0x4a
			await st.actions.move_unit(x, [c + step] as Array[Vector2i])
			x.moved = false
	await st.view.set_dim(false)


## 杀手锏 (秦琼, range 1-2): a blow, then 攻击 and 防御 down on the target. With 回旋杀手锏 (dynamic slot 11 =
## 秦琼) his classes' area code becomes 4 for the blow (the cell behind the target too, in full), and the unit
## there is weakened as well.
func _sha_shou_jian(u: BUnit, t: BUnit) -> void:
	var spin := Mem.ev(3981) == 8
	await _banner("回旋杀手锏" if spin else "杀手锏")
	var saved_a := Mem.r32(0x4091b2)
	var saved_b := Mem.r8(0x4091bc)
	if spin:
		Mem.w32(0x4091b2, 0x40404)       # area codes of classes 33-36 (0x409191 + 33)
		Mem.w8(0x4091bc, 4)              # and of class 43
	await _blow(u, t)
	await st.view.set_dim(false)
	await change_unit(t, 0, 0)
	await change_unit(t, 1, 0)
	if spin:
		Mem.w32(0x4091b2, saved_a)
		Mem.w8(0x4091bc, saved_b)
		var s2 := Mem.r8(0x492801)       # the strike's second target (combat object +0x11)
		if s2 < 115:
			await change_unit(st.units[s2], 0, 0)
			await change_unit(st.units[s2], 1, 0)


## 尽命三锤 (裴元庆): one blow with the three-hammer animation, ignoring defence (Rules.calc_damage).
func _jin_ming(u: BUnit, t: BUnit) -> void:
	st.actions.face(u, t.pos)
	await _banner("尽命三锤")
	Mem.w8(BattleActions.TRIPLE_STRIKE, 1)  # the strikes take animation table 0x42bf08 (0x4d355e)
	await _blow(u, t)
	Mem.w8(BattleActions.TRIPLE_STRIKE, 0)


## 回马枪 (罗成), on an orthogonally adjacent target. If he moved this turn he rides back to where he started,
## the target follows his trail to a cell he lured it to (0x4d9e68) and only then takes the blow and loses 机动;
## a confused, paralysed or lost target is shaken out of it first. Without a move: a plain blow.
func _hui_ma_qiang(u: BUnit, t: BUnit) -> void:
	_face_each_other(u, t)
	var path := st.move_path()
	if path.is_empty():
		await _blow(u, t)
		return
	var lure := _lure_cell(u, t, path)
	if t.status & (BUnit.ST_CONFUSION | BUnit.ST_PARALYSIS | BUnit.ST_LOST):
		await _change_fx(t, 6, 0x88)
		t.status = t.status & ~0x4a
	# 罗成 rides back along his trail to path[0]
	var back: Array[Vector2i] = []
	for i in range(path.size() - 2, -1, -1):
		back.append(path[i])
	await st.actions.move_unit(u, back)
	await st.unit_say(t.pid, "哪里逃？")
	# 0x4da000: the target walks the trail backwards from his end cell, onto each cell it can stand on, down to
	# where the search stopped; then to the lure cell when that lies beside the trail
	var walk: Array[Vector2i] = []
	var last_ok := -1
	for k in range(path.size() - 1, 0, -1):
		walk.append(path[k])
		if can_stand(t, path[k]):
			last_ok = walk.size() - 1
		if path[k] == lure[1]:
			break
	if lure[0] != lure[1]:
		walk.append(lure[0])
	else:
		walk.resize(last_ok + 1)
	await st.actions.move_unit(t, walk)
	t.moved = false
	_face_each_other(u, t)
	await _banner("回马枪")
	await _blow(u, t)
	await st.view.set_dim(false)
	await change_unit(t, 5, 0)


## 0x4d9e68 with 罗成 put back on path[0]: along his trail from path[1], the first cell the target can stand on,
## or for a step that cell's side neighbours (a vertical step: x+1 then x-1 beside the cell left and beside the
## cell entered; a horizontal one: y+1, y-1). Without one, his end cell. Returns [cell, trail cell it stopped at].
func _lure_cell(u: BUnit, t: BUnit, path: Array[Vector2i]) -> Array[Vector2i]:
	var keep := u.pos
	u.pos = path[0]
	var n := path.size() - 1
	var out: Array[Vector2i] = [path[n], path[n]]
	for i in range(1, n):
		var c := path[i]
		if can_stand(t, c):
			out = [c, c]
			break
		var p := path[i - 1]
		var side := [Vector2i(1, 0), Vector2i(-1, 0)] if p.x == c.x else [Vector2i(0, 1), Vector2i(0, -1)]
		var found := false
		for base in [p, c]:
			for o in side:
				var s: Vector2i = base + o
				if s == t.pos or can_stand(t, s):
					out = [s, c]
					found = true
					break
			if found:
				break
		if found:
			break
	u.pos = keep
	return out


## 威震八荒 (伍天锡): no target to pick; every enemy on the four adjacent cells (and on the diagonals unless his
## attack range is the four adjacent cells) takes a strike in turn. With none, "范围内没有敌军部队。" and nothing
## is spent.
func _wei_zhen_ba_huang(u: BUnit) -> bool:
	var cells: Array[Vector2i] = []
	if st.actions.attack_range_code(u) != 0:
		cells.append_array([u.pos + Vector2i(-1, -1), u.pos + Vector2i(-1, 1), u.pos + Vector2i(1, -1), u.pos + Vector2i(1, 1)])
	cells.append_array([u.pos + Vector2i(0, -1), u.pos + Vector2i(-1, 0), u.pos + Vector2i(0, 1), u.pos + Vector2i(1, 0)])
	var targets: Array[BUnit] = []
	for c in cells:
		var x := st.unit_on(c)
		if x and x.slot >= 35:
			targets.append(x)
	if targets.is_empty():
		await st.ui.message("范围内没有敌军部队。")
		return false
	await _banner("威震八荒")
	u.mp = 0
	await st.view.set_dim(false)
	for x in targets:
		await st.actions.strikes(u, x)
		if u.hp <= 0:
			break
	return true


func _face_each_other(a: BUnit, b: BUnit) -> void:
	st.actions.face(a, b.pos)
	st.actions.face(b, a.pos)


# ------------------------------------------------------------------ 围攻 (B5 F2, B3 F11)
## The units that join an attack by `a` on `t` (0x4d698e): on the 8 cells around t (the four adjacent ones first,
## then the diagonals), units of a's side other than a that have not finished and are not confused, whose attack
## range code is 0 or 5 (adjacent cells only) or 1, 6, 10, 12 or 13.
func helpers(a: BUnit, t: BUnit) -> Array[BUnit]:
	var out: Array[BUnit] = []
	var offs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]
	for k in 8:
		var h := st.unit_at(t.pos + offs[k])
		if h == null or h == a or (h.slot < 35) != (a.slot < 35) or h.acted or (h.status & BUnit.ST_CONFUSION):
			continue
		var r := st.actions.attack_range_code(h)
		if r in [1, 6, 10, 12, 13] or (r in [0, 5] and k < 4):
			out.append(h)
	return out


## 围攻 is enabled (0x4d7196) when an enemy next to the commanded unit has helpers: on the four adjacent cells for
## the range codes 0 and 5, also on the diagonals (looked at first) for 1, 6, 10, 12 and 13.
func siege_enabled(a: BUnit) -> bool:
	var r := st.actions.attack_range_code(a)
	var cells: Array[Vector2i] = []
	if r in [1, 6, 10, 12, 13]:
		cells.append_array([a.pos + Vector2i(1, 1), a.pos + Vector2i(1, -1), a.pos + Vector2i(-1, -1), a.pos + Vector2i(-1, 1)])
	elif not (r in [0, 5]):
		return false
	cells.append_array([a.pos + Vector2i(1, 0), a.pos + Vector2i(-1, 0), a.pos + Vector2i(0, 1), a.pos + Vector2i(0, -1)])
	for c in cells:
		var t := st.unit_on(c)
		if t and t.slot >= 35 and not helpers(a, t).is_empty():
			return true
	return false


## The 围攻 command (0x4d6d00): pick a target in attack range; one without helpers gives "无法围攻该部队".
## Returns true when the action ended.
func siege_command(a: BUnit) -> bool:
	while true:
		var t := await st.input.pick_unit(st.actions.attack_cells(a, a.pos), func(x: BUnit) -> bool: return x.is_enemy_of(a) and x.active(), 1, a)
		if t == null:
			return false
		var hs := helpers(a, t)
		if hs.is_empty():
			await st.ui.message("无法围攻该部队")
			continue
		await siege(a, t, hs)
		return true
	return false


## 围攻 (0x4d6d87), also the AI's (0x4d6b80): a defender that strikes first (siege_break) attacks `a` instead;
## otherwise "围攻", `a` strikes, each helper strikes and loses its turn, and the defender counters `a` once.
func siege(a: BUnit, t: BUnit, hs: Array[BUnit]) -> void:
	Audio.play_se("se05")
	var no_counter := false
	var broken := false
	if _siege_break(t, a):
		no_counter = true                       # [0x4d002c]
		var m: int = {14: 2, 101: 1, 136: 1}.get(t.pid, 0)    # 0x4d7b90: 抽屉枪 / 双雷引
		if m != 0:
			Mem.w32(0x55ac24, m)
			await st.actions.attack(t, a)
			broken = true
	if not broken:
		await st.ui.message("围攻")
		await st.actions.strikes(a, t)
		for h in hs:
			if not t.active():
				break
			await st.actions.strikes(h, t)
			h.flags = h.flags | 6           # 0x43ef91: finished, without the end-of-action skills
	if not no_counter:
		await st.actions.counter_attack(a, t)
	st.refresh_units()


## 0x4d74e4: the defender, not confused and standing, strikes first — with 先手攻击 (effect 60), as 定彦平,
## 东方伯 or 姜松 (101, 136, 14) on chance(min(50·士气 / attacker's 士气, 100)) (姜松 then doubles, [0x55ac68]),
## or while 双雷引 is on ([0x55ac54] == 1) — provided the attacker is in its range.
func _siege_break(t: BUnit, a: BUnit) -> bool:
	var ok := false
	if not (t.status & BUnit.ST_CONFUSION) and t.hp > 0:
		if t.has_effect(60):
			ok = true
		elif t.pid in [101, 136, 14]:
			ok = Rules.chance(mini(t.morale() * 50 / maxi(a.morale(), 1), 100))
			if ok and t.pid == 14:
				Mem.w8(0x55ac68, 1)
		elif Mem.r32(0x55ac54) == 1:
			ok = true
	if ok and st.actions.can_attack(t, a):
		_face_each_other(t, a)
		return true
	Mem.w8(0x55ac68, 0)
	return false


# ------------------------------------------------------------------ 交给 (B5 F3, B6 F6)
## 交给 is enabled (0x4d9cc9) for 樊虎 (11) when the bag holds an accessory (id ≥ 0x35), for anyone else when an
## accessory is equipped.
func give_enabled(u: BUnit) -> bool:
	if Mem.r32(BattleStage.CMD_PID) & 0xff == 11:
		for i in Game.BAG_SLOTS:
			var id := Mem.r8(Game.BAG + 3 * i)
			if id != 0xff and id >= 0x35:
				return true
		return false
	return u.person.accessory >= 0


## The 交给 command (0x4d287e). 樊虎's 行囊 hands out accessories from the bag (one list row per item id in 0x2f
## and 0x35..0x56 present there); the others give their own accessory. Returns true when the action ended.
func give_command(u: BUnit) -> bool:
	if u.pid != 11:
		return await give(u, u.person.accessory)
	while not u.acted:
		var ids: Array[int] = []
		var labels := []
		for id in [0x2f] + range(0x35, 0x57):
			for i in Game.BAG_SLOTS:
				if Mem.r8(Game.BAG + 3 * i) == id:
					ids.append(id)
					labels.append(str(Game.item(id).get("name", "?")))
					break
		var k := await st.ui.menu.choose(labels, Vector2(-1, -1), true, "交给", [], 160)
		if k < 0:
			return false
		if await give(u, ids[k]):
			for i in Game.BAG_SLOTS:          # 0x4d9d4b: the first bag slot with that id
				if Mem.r8(Game.BAG + 3 * i) == ids[k]:
					Mem.w8(Game.BAG + 3 * i, 0xff)
					break
			return true
	return true


## Give (0x4d28f0): pick a receiver on the 8 cells around (an ally; the giver himself is ignored). 樊虎 puts it in
## the bag; anyone else must have the accessory slot free and be able to wear it. The giver's accessory slot is
## then emptied and his action ends.
func give(u: BUnit, item: int) -> bool:
	var cells := Shapes.range_cells(1, u.pos, st.view.map_w, st.view.map_h, true)
	while true:
		var r := await st.input.pick_unit(cells, func(x: BUnit) -> bool: return not x.is_enemy_of(u), 4, u, item)
		if r == null:
			return false
		if r == u:
			continue
		var rp := r.person
		if r.pid == 11:
			for i in Game.BAG_SLOTS:          # 0x4d9c85: the first free bag slot
				if Mem.r8(Game.BAG + 3 * i) == 0xff:
					Mem.w8(Game.BAG + 3 * i, item)
					break
		elif rp.accessory >= 0:
			await st.ui.message("该武将辅助装备不为空")
			continue
		elif not rp.can_equip(item):
			await st.ui.message("该武将不能装备该辅助")
			continue
		else:
			rp.equip_item(2, item, 0xff)
		u.person.accessory = -1
		await _give_fx(u, r, item)
		return true
	return false


## 0x4d9bfd: the giver hands it over, the item's icon rises from him and settles on the receiver (SE 14), then
## "交出…".
func _give_fx(u: BUnit, r: BUnit, item: int) -> void:
	if not Game.autoplay:
		if u.node:
			u.node.set_pose(UnitSprite.Pose.DEFEND, u.dir)
		await st.actions.wait(0.3)
		if u.node:
			u.node.set_pose(UnitSprite.Pose.STAND, u.dir)
		Audio.play_se("se14")
		await st.actions.wait(0.3)
	await st.ui.message("交出%s" % str(Game.item(item).get("name", "?")))
