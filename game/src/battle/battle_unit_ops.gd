class_name BattleUnitOps
extends RefCounted
## The battle scripts' unit ops (docs/rules.md §10.6.1, eex.md): units appearing, moving, changing, leaving, their
## animations, and the misc unit ops found in Ghidra.

var st: BattleStage


func _init(s: BattleStage) -> void:
	st = s


# ------------------------------------------------------------------ unit ops (§10.6.1)
## op 0x4c (0x414f42 → 0x4570ee), in a battle only: a hidden unit (state 1) appears at its deployment entry —
## mode 0 the first unit of the person and the entry with that person (none → nothing), mode 1 player slot `slot`
## and entry `slot`. It is placed on the nearest free cell (0x43f040), the map centres on it, SE 15, then a 4-tick
## hold. Its HP stays. (The wipe-in with SE 42 is dead code in this exe: its check 0x4573c1 never holds.)
func op_unit_op_4c(ins: Dictionary) -> void:
	if not st.in_battle():
		return
	var mode := st.arg(ins, 0)
	if mode == 0xffff:
		mode = 0
	var u: BUnit = null
	var d := {}
	if mode == 0:
		var pid := st.arg(ins, 1)
		for x in st.units:
			if x.exists() and x.pid == pid and x.state != 0:
				u = x
				break
		if u:
			d = _entry_of(u)
	elif mode == 1:
		var sl := st.arg(ins, 2)
		if sl < 15:
			u = st.units[sl]
			if sl < st.deploy.size():
				d = st.deploy[sl]
	if u == null or not u.exists() or u.state != BUnit.STATE_HIDDEN or d.is_empty():
		return
	await _appear(u, Vector2i(int(d.get("x", u.pos.x)), int(d.get("y", u.pos.y))))


## 0x4570ee's live branch: place on the nearest free cell (state 2), centre, SE 15, hold 4 ticks.
func _appear(u: BUnit, c: Vector2i) -> void:
	u.pos = st.deployment.nearest_free(c, u)
	u.state = BUnit.STATE_ON_MAP
	st.refresh_units()
	await st.view.center_on(u.pos)
	Audio.play_se("se15")
	await st.wait(0.2)


func _entry_of(u: BUnit) -> Dictionary:
	for d in st.deploy:
		if int(d.get("person", 0xffff)) == u.pid:
			return d
	return {}


func _targets_mode(mode: int, pid: int, slot: int, x1: int, y1: int, x2: int, y2: int, side: int) -> Array[BUnit]:
	var out: Array[BUnit] = []
	match mode:
		0:
			var u := st.unit_by_pid(pid)
			if u and u.state == BUnit.STATE_ON_MAP:
				out.append(u)
		1:
			if slot < 15 and st.units[slot].state == BUnit.STATE_ON_MAP:
				out.append(st.units[slot])
		_:
			if side == 0xffff:
				side = 6
			for u in st.units:
				if u.active() and st.side_match(u, side) and u.pos.x >= mini(x1, x2) and u.pos.x <= maxi(x1, x2) and u.pos.y >= mini(y1, y2) and u.pos.y <= maxi(y1, y2):
					out.append(u)
	return out


## op 0x4d (0x4150e7 → 0x45aa5c per unit): change buffs/status/HP/MP of units. HP and MP drop by the amount but
## never by more than they have; HP left at 1 or less becomes 0, MP keeps at least 1 (MP takes a byte amount).
func op_unit_op_4d(ins: Dictionary) -> void:
	var tg := _targets_mode(st.arg(ins, 0), st.arg(ins, 1), st.arg(ins, 2), st.arg(ins, 3), st.arg(ins, 4), st.arg(ins, 5), st.arg(ins, 6), st.arg(ins, 7))
	var bi := st.arg(ins, 8)
	var bl := st.arg(ins, 9)
	var stv := st.arg(ins, 10)
	var hpd := st.arg(ins, 11)
	var mpd := st.arg(ins, 12)
	for u in tg:
		if bi != 0xffff and bi < 6:
			u.set_buff(bi, {0: 0, 1: 3, 2: 6}.get(bl, 3))
		if stv != 0xffff:
			if stv & 0x80:
				u.status = u.status & ~stv & 0x7f
			else:
				u.status = u.status | stv
		if hpd != 0 and hpd != 0xffff:
			var nh := u.hp - mini(u.hp, hpd & 0xffff)
			if nh <= 1:
				nh = 0
			u.hp = nh
			if nh <= 0:
				u.extra["dying"] = true
			if not Game.instant:
				st.hud.popup_number(str(hpd & 0xffff), u.pos)
			if nh <= 0:
				await st.actions.unit_defeated(u)
		if mpd != 0 and mpd != 0xffff:
			u.mp = maxi(u.mp - (mpd & 0xff), 1)
	st.refresh_units()


## op 0x4e: change AI (mode 0: one person; else every unit of `side` in the rectangle).
func op_unit_op_4e(ins: Dictionary) -> void:
	var mode := st.arg(ins, 0)
	var ai_mode := st.arg(ins, 7)
	var tg: Array[BUnit] = []
	if mode == 0 or mode == 0xffff:
		var u := st.unit_by_pid(st.arg(ins, 1))
		if u:
			tg.append(u)
	else:
		tg = _targets_mode(2, 0, 0, st.arg(ins, 2), st.arg(ins, 3), st.arg(ins, 4), st.arg(ins, 5), st.arg(ins, 6))
	for u in tg:
		st.deployment._set_ai(u, ai_mode, st.arg(ins, 8), st.arg(ins, 9), st.arg(ins, 10))


## op 0x4f (0x415f65 → 0x457428): p1's unit (the first with that person, on the map) turns to `dir` (p2 = 0xffff)
## or toward p2's unit (also on the map; 0x4351da: vertical when |dx| < |dy|, else horizontal). Only when that changes
## its facing: with scroll (0xffff → 1) the map centres on it and 8 ticks pass, SE 6, the turn, then with wait
## (0xffff → 1) 8 more ticks. Otherwise nothing at all.
func op_unit_op_4f(ins: Dictionary) -> void:
	var p1 := st.arg(ins, 0)
	if p1 >= 0x400:
		return
	var u := st.unit_by_pid(p1)
	if u == null or u.state != BUnit.STATE_ON_MAP:
		return
	var d := st.arg(ins, 2) & 3
	var p2 := st.arg(ins, 1)
	if p2 != 0xffff:
		var t2 := st.unit_by_pid(p2)
		if t2 == null or t2.state != BUnit.STATE_ON_MAP:
			return
		var dd := t2.pos - u.pos
		if absi(dd.x) < absi(dd.y):
			d = 0 if dd.y < 0 else 2
		else:
			d = 3 if dd.x < 0 else 1
	if d == u.dir:
		return
	var scroll := st.arg(ins, 4)
	var wt := st.arg(ins, 5)
	if scroll == 1 or scroll == 0xffff:
		await st.view.center_on(u.pos)
		await st.wait(0.4)
	Audio.play_se("se06")
	u.dir = d
	if u.node:
		u.node.dir = d
		u.node.queue_redraw()
	if wt == 1 or wt == 0xffff:
		await st.wait(0.4)


## Unit action (0x45778f(pid, kind, pre, post)), also the engine's own (level up, items, equipment). pre / post ≠ 0
## add 8 ticks before / after, except for kinds 0 and 11. Kinds: 0 normal; 1 cheer, 2 defend (by facing), 3 hurt,
## 4 weak, 5 the first attack frame (each with SE 8); 6 one quick swing, 7 two swings then normal (SE 7 per swing);
## 8 turning on the spot (right, left, then up, down; SE 6 twice); 9 six weak beats of 8 ticks (SE 8); 10 a start:
## hurt frame 4 px up for 3 ticks, then normal (SE 8); 11 two turns, then cheer; 12 one turn.
func op_unit_status(ins: Dictionary) -> void:
	if st.arg(ins, 1) == 0xffff:
		return                     # 0x416129: kind 0xffff does nothing
	var u := st.unit_by_pid(st.arg(ins, 0))
	if u == null or u.state != BUnit.STATE_ON_MAP or u.node == null:
		return
	var kind := st.arg(ins, 1) & 0xff
	var pre := st.arg(ins, 2)
	var post := st.arg(ins, 3)
	await st.view.center_on(u.pos)    # 0x45503f: the camera follows each animated unit
	if pre != 0 and kind != 0 and kind != 11:
		await st.wait(0.4)
	var n := u.node
	var d := u.dir
	var S := UnitSprite.Sheet
	var atk: int = [4, 8, 0, 8][d]
	match kind:
		0:
			n.set_pose(UnitSprite.Pose.STAND, d)
		1:
			n.show_frame(S.SPC, 4)
			Audio.se(8)
		2:
			n.show_frame(S.SPC, [1, 2, 0, 2][d], d == 1)
			Audio.se(8)
		3:
			n.show_frame(S.SPC, 3)
			Audio.se(8)
		4:
			n.show_frame(S.MOV, 9)
			Audio.se(8)
		5:
			n.show_frame(S.ATK, atk, d == 1)
			Audio.se(8)
		6:
			Audio.se(7)
			for f in 4:
				n.show_frame(S.ATK, atk + f, d == 1)
				await st.wait(0.05)
		7:
			for k in 2:
				Audio.se(7)
				for f in 4:
					n.show_frame(S.ATK, atk + f, d == 1)
					await st.wait(0.1)
			n.set_pose(UnitSprite.Pose.STAND, d)
		8:
			for half in [[[4, true], [4, false]], [[2, false], [0, false]]]:
				Audio.se(6)
				for i in 8:
					var h: Array = half[i >> 2]
					n.show_frame(S.MOV, int(h[0]) + (i & 1), bool(h[1]))
					await st.wait(0.1)
		9:
			Audio.se(8)
			for i in 6:
				n.show_frame(S.MOV, 9 + (i & 1))
				await st.wait(0.4)
		10:
			Audio.se(8)
			n.set_pose(UnitSprite.Pose.STAND, d)
			await st.wait(0.1)
			n.show_frame(S.SPC, 3, false, -4)
			await st.wait(0.15)
			n.set_pose(UnitSprite.Pose.STAND, d)
		11, 12:
			# stand down, left, up, right (0x9f00, 0xb100, 0xa800, mirrored 0xb100)
			var turn := [[6, false], [8, false], [7, false], [8, true]]
			for i in (9 if kind == 11 else 5):
				n.show_frame(S.MOV, int(turn[i & 3][0]), bool(turn[i & 3][1]))
				await st.wait(0.1)
			if kind == 11:
				n.show_frame(S.SPC, 4)
	if post != 0 and kind != 0 and kind != 11:
		await st.wait(0.4)


## op 0x32 in a battle: move a unit (story-op name) — select 1 = player slot, else person.
func op_actor_move(ins: Dictionary) -> void:
	var u: BUnit = null
	var sel := st.arg(ins, 0)
	if sel == 1 and st.arg(ins, 2) < 15:
		u = st.units[st.arg(ins, 2)]
	else:
		u = st.unit_by_pid(st.arg(ins, 1))
	if u == null or u.state != BUnit.STATE_ON_MAP:
		return
	await _script_move(u, Vector2i(st.arg(ins, 3), st.arg(ins, 4)), st.arg(ins, 5))


func _script_move(u: BUnit, goal: Vector2i, d: int) -> void:
	await st.view.ensure_visible(u.pos)
	# an occupied goal: stop at the nearest free cell instead of on top of the other unit
	if goal != u.pos and st.unit_at(goal, u) != null:
		goal = st.deployment.nearest_free(goal, u)
	# scripted moves ignore movement points; path by BFS over passable cells
	var parents := {}
	var cost := func(c: Vector2i) -> int: return mini(Rules.move_cost(u, st.view.terrain_at(c)), 1) if Rules.move_cost(u, st.view.terrain_at(c)) < 999 else 999
	var blocked := func(c: Vector2i) -> bool: return st.unit_at(c, u) != null
	Grid.reachable(u.pos, 200, st.view.map_w, st.view.map_h, cost, blocked, Callable(), parents)
	var path := Grid.path_to(parents, u.pos, goal)
	if path.is_empty() and goal != u.pos:
		u.pos = st.deployment.nearest_free(goal, u)
	else:
		await st.actions.move_unit(u, path)
	u.moved = false
	if d != 0xffff and d >= 0:
		u.dir = d & 3
	st.refresh_units()


## RemoveUnit (0x441744 → 0x4419b6): the unit leaves the map (state 3).
## * silent (op 0x31; op 0x53 over an area with a7 ≠ 0): SE 6, MOV frame 6 for 4 ticks, SE 17, then the first image
##   of the special sheet drawn 4 px shorter each tick for 12 ticks. No retreat line, no 撤退数.
## * otherwise a player unit (colour 0, person < 49) with its retreat-line flag (U+0x20) speaks its line (text
##   #650+pid) first. With `variant` ≠ 0, or for 管毅 (person 0), the camera centres on it and the defeat
##   animation plays: MOV frame 9 blinking 4 × (3, 3) and 6 × (1, 1) ticks, SE 22, 16 ticks to white, 16 to nothing
##   (about 3.4 s). Else SE 16 and two blinks of 3 ticks. A party member's 撤退数 (+0x29) counts up.
## It does not change the current unit.
func remove_unit(u: BUnit, silent: bool, variant := 0) -> void:
	if u.state != BUnit.STATE_ON_MAP:
		return
	if not silent and Mem.r8(u.addr + 0x20) != 0 and u.colour == 0 and u.pid < 49:
		var line := Game.text(650 + u.pid)
		if line != "":
			await st.view.ensure_visible(u.pos)
			await st.ui.dialog.talk(Game.person_face(u.pid), u.person.name, line, st._dialog_top(u.pid))
	if u.node and not Game.instant:
		await _removal_animation(u, silent, variant)
	u.state = 3
	u.status = 0
	u.extra.erase("dying")
	# mod 0x4dbff3: the unit's own 暗杀 mark goes, and so does every mark it placed as the assassin
	for k in 116:
		if Mem.r8(BattleStage.ASSASSIN_LINK + k) == u.slot:
			Mem.w8(BattleStage.ASSASSIN_LINK + k, 0xff)
	Mem.w8(BattleStage.ASSASSIN_MARK + u.slot, 0)
	Mem.w8(BattleStage.ASSASSIN_LINK + u.slot, 0xff)
	if not silent and Game.is_member(u.pid):
		var pb := u.person.base
		Mem.w8(pb + 0x29, mini(Mem.r8(pb + 0x29) + 1, 255))
	for o in st.units:
		if o.exists() and Mem.r8(o.addr + 8) == u.slot and o.mode in [0, 4]:
			o.mode = 1
			Mem.w8(o.addr + 8, 0xff)
	st.refresh_units()


func _removal_animation(u: BUnit, silent: bool, variant: int) -> void:
	var n := u.node
	const T := 0.05
	if silent:
		await st.view.ensure_visible(u.pos)
		Audio.play_se("se06")
		n.show_frame(UnitSprite.Sheet.MOV, 6, false)
		await st.wait(4 * T)
		Audio.play_se("se17")
		n.show_frame(UnitSprite.Sheet.SPC, 0, false)
		for k in 12:
			n.clip_h = 48 - 4 * k
			n.queue_redraw()
			await st.wait(T)
	elif variant != 0 or u.pid == 0:
		await st.view.center_on(u.pos)
		n.show_frame(UnitSprite.Sheet.MOV, 9, false)
		for r in [[4, 3], [6, 1]]:
			for i in int(r[0]):
				n.visible = false
				await st.wait(int(r[1]) * T)
				n.visible = true
				await st.wait(int(r[1]) * T)
		Audio.play_se("se22")
		n.flash_color = Color.WHITE
		for k in 16:
			n.flash = (k / 2 + 1) / 8.0
			await st.wait(T)
		for k in 16:
			n.fade = 1.0 - (k + 1) / 16.0
			await st.wait(T)
	else:
		await st.view.ensure_visible(u.pos)
		Audio.play_se("se16")
		for i in 2:
			n.visible = false
			await st.wait(3 * T)
			n.visible = true
			await st.wait(3 * T)
	n.visible = false


## op 0x31 (battle): mode 0 → remove person's unit silently; else every unit of `side` in the rectangle.
func op_actor_select(ins: Dictionary) -> void:
	var mode := st.arg(ins, 0)
	var tg := _targets_mode(0 if mode == 0 else 2, st.arg(ins, 1), 0, st.arg(ins, 2), st.arg(ins, 3), st.arg(ins, 4), st.arg(ins, 5), st.arg(ins, 6))
	for u in tg:
		await remove_unit(u, true)


## op 0x53 (0x41557b): mode 0 → RemoveUnit(person's unit on the map; 0x400..0x402 the current unit, 0x45602b) with
## the animation variant a7; else 0x45a80f: the units of `side` in the rectangle, cell by cell (y1..y2, then
## x1..x2, as given and clipped to the map; state 2, whatever the HP), RemoveUnit silent when a7 ≠ 0.
func op_unit_op_53(ins: Dictionary) -> void:
	var a7 := st.arg(ins, 7)
	if a7 == 0xffff:
		a7 = 0
	if st.arg(ins, 0) == 0:
		var pid := st.arg(ins, 1)
		var u: BUnit = null
		if pid >= 0x400 and pid <= 0x402:
			u = st.current_unit if st.current_unit and st.current_unit.active() else null
		else:
			u = st.unit_by_pid(pid)
		if u and u.state == BUnit.STATE_ON_MAP:
			await remove_unit(u, false, a7)
		return
	var side := st.arg(ins, 6)
	if side == 0xffff:
		side = 6
	var at := {}
	for o in st.units:
		if o.state == BUnit.STATE_ON_MAP and not at.has(o.pos):
			at[o.pos] = o
	var tg: Array[BUnit] = []
	for y in range(st.arg(ins, 3), mini(st.arg(ins, 5), st.view.map_h - 1) + 1):
		for x in range(st.arg(ins, 2), mini(st.arg(ins, 4), st.view.map_w - 1) + 1):
			var o: BUnit = at.get(Vector2i(x, y))
			if o and st.side_match(o, side):
				tg.append(o)
	for u in tg:
		await remove_unit(u, a7 != 0)


## op 0x1b: retreat-line flag of the person's unit.
func op_op_1b(ins: Dictionary) -> void:
	var u := st.unit_by_pid(st.arg(ins, 0))
	if u:
		Mem.w8(u.addr + 0x20, 1 if st.arg(ins, 1) != 0 else 0)


## op 0x55 (0x41591c → 0x4591a1): a retreated unit (state 3) re-enters at (x, y) with full HP/MP: SE 15, then the
## map centres on it. (The appear animation check 0x4573c1 never holds in this exe, so there is no wipe-in.)
func op_unit_move(ins: Dictionary) -> void:
	var mode := st.arg(ins, 0)
	if mode == 0xffff:
		mode = 0
	var u: BUnit = null
	if mode == 0:
		var pid := st.arg(ins, 1)
		for x in st.units:
			if x.exists() and x.pid == pid:
				u = x
				break
	elif st.arg(ins, 2) < 15:
		u = st.units[st.arg(ins, 2)]
	if u == null or u.state != 3:
		return
	var d := st.arg(ins, 5)
	st.deployment._unit_reenter(u, st.arg(ins, 3), st.arg(ins, 4), 2 if d == 0xffff else d)
	st.refresh_units()
	Audio.play_se("se15")
	await st.view.center_on(u.pos)

var _mcall_loaded := -1        # op 0x6b: the MCALL animation loaded for the next effect 109


## op 0x6b (0x41405b): effect 0xffff does nothing. A scroll argument ≠ 0 (0xffff too) centres the map on the cell.
## The rest only when the cell's centre is on screen: an effect < 100 plays Xben[effect] there; 109 plays the MCALL
## animation loaded before (0x421879) and holds 4 ticks; any other ≥ 100 only loads MCALL{effect % 100} (0x4217ff),
## drawing nothing (S_41's 199 × "104 1" only scroll).
func op_op_6b(ins: Dictionary) -> void:
	var c := Vector2i(st.arg(ins, 0), st.arg(ins, 1))
	var eff := st.arg(ins, 2)
	if eff == 0xffff:
		return
	if st.arg(ins, 3) != 0:
		await st.view.center_on(c)
	var p := st.view.cell_center(c) - st.view.camera.position
	var vs := st.view.view_size()
	if p.x < 0 or p.y < 0 or p.x >= vs.x or p.y >= vs.y:
		return
	if eff >= 100 and eff != 109:
		_mcall_loaded = eff % 100
		return
	var e: EffectPlayer = null
	if eff < 100:
		e = EffectPlayer.create("xben", eff)
	elif _mcall_loaded >= 0:
		e = EffectPlayer.create("mcall", _mcall_loaded)
		_mcall_loaded = -1
	if e == null or Game.instant:
		return
	e.position = st.view.cell_center(c)
	st.view.fx_layer.add_child(e)
	await e.done
	if eff == 109:
		await st.wait(0.2)


## op 0x30 in a battle (0x413010 → 0x4570ee(person)): the person's hidden unit (state 1) appears at its deployment
## entry, as op 0x4c mode 0 (the script's x, y are for story scenes only); a unit not hidden, or a person without
## an entry, does nothing.
func op_actor_appear(ins: Dictionary) -> void:
	var u := st.unit_by_pid(st.arg(ins, 0) & 0xfff)
	if u == null or u.state != BUnit.STATE_HIDDEN:
		return
	var d := _entry_of(u)
	if d.is_empty():
		return
	await _appear(u, Vector2i(int(d.get("x", u.pos.x)), int(d.get("y", u.pos.y))))


# ------------------------------------------------------------------ misc battle ops (Ghidra)
## op 0x15 (0x413911 → 0x459777), in a battle only and not with p2 = 0xffff: a line in the portrait window, as op
## 0x14's unit lines (the text ends at "\n&"). It is p1's when p1's unit (any state) is on the map, else p2's,
## pointing at p2's unit when that one is on the map; the map centres on the unit.
func op_unit_say(ins: Dictionary) -> void:
	if not st.in_battle() or st.arg(ins, 1) == 0xffff:
		return
	var text := st.sarg(ins, 2)
	var cut := text.find("\n&")
	if cut >= 0:
		text = text.substr(0, cut)
	var speaker := st.arg(ins, 0)
	var u := st.unit_by_pid(speaker)
	if u == null or u.state != BUnit.STATE_ON_MAP:
		speaker = st.arg(ins, 1)
		u = st.unit_by_pid(speaker)
	if u and u.state == BUnit.STATE_ON_MAP:
		await st.view.center_on(u.pos)
	await st.unit_say(speaker, text)


## op 0x51 (0x41626a): battle won — every unit on the map (whatever its HP) gets full HP, its moved / acted flags
## cleared (drawn in colour again) and its statuses but bits 0 and 7 cleared (0x418da0). MP and buffs stay (the
## stores at 0x4162e7 are NOPped).
func op_op_51(_ins: Dictionary) -> void:
	for u in st.units:
		if u.exists() and u.state == BUnit.STATE_ON_MAP:
			u.flags = u.flags & ~(BUnit.F_MOVED | BUnit.F_ACTED)
			u.status = u.status & ~0x7e
			u.hp = u.max_hp()
			if u.node:
				u.node.greyed = false
	st.refresh_units()


## op 0x59 (0x41688b): gold base, three (item, level) pairs, final flag. gold = party level (0x40c14f) × 100 + 700 +
## base. The reward screen first (BattleHUD.reward_screen); then the gold (capped) and the items go in silently
## (0x45991b without its message). A weapon or armour without a level gets one from person 0's level: treasures
## min(L / 7 + 1, 10), others 3 from 48 on, else (L mod 18) / 6 + 1.
func op_op_59(ins: Dictionary) -> void:
	var gold := Game.party_avg_level() * 100 + 700 + st.arg(ins, 0)
	var items := []
	var lvls := []
	for k in 3:
		var iid := st.arg(ins, 1 + 2 * k)
		items.append(0xff if iid == 0xffff or iid > 0x67 else iid)
		var l := st.arg(ins, 2 + 2 * k)
		lvls.append(0 if l == 0xffff else l)
	var final := st.arg(ins, 7) != 0 and st.arg(ins, 7) != 0xffff
	await st.hud.reward_screen(gold, items, final)
	Game.gold = mini(Game.gold + gold, 9999999)
	var lead := Game.person(0).level
	for k in 3:
		var iid: int = items[k]
		if iid == 0xff:
			continue
		var it := Game.item(iid)
		var lvl: int = lvls[k]
		var xp := 0
		if Person.slot_of(it) < 2:
			var maxl := 10 if bool(it.get("treasure", false)) else 3
			if lvl == 0:
				lvl = Person.auto_level_at(it, lead)
			if lvl >= maxl:
				lvl = maxl
				xp = 0xff
		await st.receive_item(iid, maxi(lvl, 1), xp)
		if int(it.get("unk_18", 0)) != 0:
			SpecialFuncs.write_niuniu(iid + 3, 1)


## op 0x5c (0x416e17): blink the person's unit three times (camera centred).
func op_op_5c(ins: Dictionary) -> bool:
	var u := st.unit_by_pid(st.arg(ins, 0))
	if u == null or not u.active():
		return false
	await st.view.center_on(u.pos)
	if u.node and not Game.instant:
		for k in 3:
			u.node.flash = 0.8
			await st.wait(0.5)
			u.node.flash = 0.0
			await st.wait(0.5)
	return true


## op 0x5d (0x417068): turn limit — mode 0 set (refused when turn + 1 >= v, 0x4170ef), 1 add.
func op_op_5d(ins: Dictionary) -> bool:
	var mode := st.arg(ins, 0)
	var v := st.arg(ins, 1) & 0xff
	if mode == 0:
		if v <= st.turn + 1:
			return false
		st.turn_limit = v
	elif mode == 1:
		st.turn_limit += v
	else:
		return false
	st.hud.queue_redraw()
	return true
