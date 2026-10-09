class_name BattleAI
extends RefCounted
## Unit AI (docs/rules.md §10.3–10.5, AIAct 0x43ad1c). AI codes (unit +0xe):
## 0 go for target person/point, 1 active, 2 hold, 3 passive, 4 follow/flee (never attacks), 7 player-controlled.

const HEAL_TERRAIN := [18, 19, 20, 21, 22]
const MAGIC_FAMILIES := [8, 9, 10, 18]

var st: BattleStage
var u: BUnit
var layer_a: Dictionary = {}     # cell -> attackable opposite unit
var layer_b: Dictionary = {}     # cell -> score
var best := 0
var dest := Vector2i(-1, -1)
var choice_strategy := -1
var choice_target: BUnit
var forbidden := Vector2i(-1, -1)
var retreat := false
var usable_strats: Array[int] = []


func _init(s: BattleStage) -> void:
	st = s


# ------------------------------------------------------------------ phase driver (§10.4)
func _compute_order(a: int, b: int) -> void:
	for i in range(a, b):
		st.units[i].order = 0xff
	var n := 0
	var passes := [
		func(x: BUnit) -> bool: return st.view.terrain_at(x.pos) in HEAL_TERRAIN,
		func(x: BUnit) -> bool: return _wounded(x),
		func(x: BUnit) -> bool: return x.family() in [8, 10, 18],
		func(x: BUnit) -> bool: return x.family() in Rules.RANGED_FAMILIES,
		func(x: BUnit) -> bool: return x.family() in [0, 3, 5, 7, 11, 12, 13, 15, 16, 17, 20, 24],
		func(_x: BUnit) -> bool: return true,
	]
	for p in passes:
		for i in range(a, b):
			var x := st.units[i]
			if x.state == BUnit.STATE_ON_MAP and x.order == 0xff and p.call(x):
				x.order = n
				n += 1


func run_phase(a: int, b: int) -> void:
	_compute_order(a, b)
	var guard := 0
	while guard < 200 and not st._battle_finished():
		guard += 1
		var pick: BUnit = null
		for i in range(a, b):
			var x := st.units[i]
			if not x.active() or x.mode == 7:
				continue
			if x.flags & (BUnit.F_MOVED | BUnit.F_ACTED):
				continue
			if pick == null or x.order < pick.order:
				pick = x
		if pick == null:
			break
		await act(pick)
		pick.flags |= BUnit.F_MOVED | BUnit.F_ACTED
		st.refresh_units()
		await st.checkpoint()


static func _wounded(x: BUnit) -> bool:
	if x.cls() == 0x31:
		return false
	if x.pid < 0x400:
		return x.hp * 5 <= x.max_hp() * 2
	return x.hp * 5 <= x.max_hp()


# ------------------------------------------------------------------ one unit
func act(unit: BUnit) -> void:
	u = unit
	if not u.active():
		return
	var mv := 0 if (u.status & BUnit.ST_PARALYSIS) else u.move_points()
	forbidden = Vector2i(-1, -1)
	var tslot := Mem.r8(u.addr + 8)
	if tslot != 0xff and (tslot >= 115 or not st.units[tslot].active()):
		Mem.w8(u.addr + 8, 0xff)
		if u.mode in [0, 3]:
			u.mode = 1
	if u.status & (BUnit.ST_CONFUSION | BUnit.ST_LOST):
		await _confused_act(mv)
		return
	_prepare()
	var reach: Dictionary = {}
	var parents := {}
	reach = st.actions.reachable(u, parents) if mv > 0 else {u.pos: 0}
	if retreat and u.slot != 35:
		var leader := st.units[0] if u.is_player_side() else st.units[35]
		if leader.active() and leader != u:
			_step_toward_bonus(leader.pos, mv)
		_evaluate(reach)
	else:
		match u.mode:
			0, 4:
				_go_target(reach, mv)
			1:
				_active(reach, mv)
			2:
				reach = {u.pos: 0}
				_evaluate(reach)
				if dest.x < 0:
					dest = u.pos
			3:
				if _attack_cell_reachable(reach):
					_evaluate(reach)
				else:
					dest = u.pos
			_:
				_active(reach, mv)
	if dest.x < 0 or not reach.has(dest):
		dest = u.pos
	# move
	if dest != u.pos:
		await st.view.ensure_visible(u.pos)
		var path := Grid.path_to(parents, u.pos, dest)
		await st.actions.move_unit(u, path)
	_arrival()
	# act
	if u.mode != 4 and u.active():
		if choice_strategy >= 0 and choice_target != null and choice_target.active():
			await st.actions.cast(u, choice_strategy, choice_target.pos)
		else:
			await _physical_attack()


func _confused_act(mv: int) -> void:
	# Confused/lost units wander one step and hit anything adjacent (simplified 10.5.4).
	var opts: Array[Vector2i] = []
	for d in Grid.DIRS:
		var c := u.pos + d
		if st.view.in_bounds(c) and st.unit_at(c) == null and Rules.move_cost(u, st.view.terrain_at(c)) <= mv:
			opts.append(c)
	if not opts.is_empty() and Rules.chance(50):
		var path: Array[Vector2i] = [opts[Rules.rand(opts.size())]]
		await st.actions.move_unit(u, path)
	var near: Array[BUnit] = []
	for c in st.actions.attack_cells(u, u.pos):
		var t := st.unit_at(c)
		if t and t != u:
			near.append(t)
	if not near.is_empty():
		await st.actions.attack(u, near[Rules.rand(near.size())])


func _prepare() -> void:
	layer_a.clear()
	layer_b.clear()
	best = 0
	dest = Vector2i(-1, -1)
	choice_strategy = -1
	choice_target = null
	retreat = false
	var code := st.actions.attack_range_code(u)
	for t in st.units:
		if t.active() and t.is_enemy_of(u):
			for c in Shapes.range_cells(code, t.pos, st.view.map_w, st.view.map_h):
				layer_a[c] = t
	if _wounded(u) and not (u.mode in [2, 4]):
		retreat = true
		for y in st.view.map_h:
			for x in st.view.map_w:
				var c := Vector2i(x, y)
				if st.view.terrain_at(c) in HEAL_TERRAIN:
					layer_b[c] = int(layer_b.get(c, 0)) + 50
	usable_strats.clear()
	if not (u.status & BUnit.ST_SEAL):
		for s in st.actions.known_strategies(u):
			if st.actions.strategy_mp(s) <= u.mp:
				usable_strats.append(s)


func _attack_cell_reachable(reach: Dictionary) -> bool:
	for c in reach:
		if layer_a.has(c):
			return true
	return false


## Cells in discovery order: start first, then by cost (mp spent), row-major.
func _ordered(reach: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for c in reach:
		cells.append(c)
	var start := u.pos
	var mp := u.move_points()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a == start: return true
		if b == start: return false
		var ca: int = mp - int(reach[a])
		var cb: int = mp - int(reach[b])
		if ca != cb: return ca < cb
		if a.y != b.y: return a.y < b.y
		return a.x < b.x)
	return cells


func _evaluate(reach: Dictionary) -> void:
	for c in _ordered(reach):
		_cell_score(c)


func _cell_score(c: Vector2i) -> void:
	var occ := st.unit_at(c, u)
	if occ != null:
		return
	var atk := 0
	var stv := 0
	var phys_t: BUnit = null
	var strat := -1
	var strat_t: BUnit = null
	var v := int(layer_b.get(c, 0))
	if u.mode != 4:
		if layer_a.has(c) or c == u.pos:
			var r := _best_physical(c)
			atk = r[0]
			phys_t = r[1]
		if not (u.status & BUnit.ST_SEAL):
			var r2 := _best_strategy(c)
			stv = r2[0]
			strat = r2[1]
			strat_t = r2[2]
		v += maxi(atk, stv)
	v = mini(255, v + _terrain_score(c))
	if c == u.pos and atk == 0:
		v = mini(255, v + 1)
	if c == forbidden:
		v = 0
	layer_b[c] = v
	if v > best:
		best = v
		dest = c
		if stv > atk:
			choice_strategy = strat
			choice_target = strat_t
		else:
			choice_strategy = -1
			choice_target = phys_t


func _terrain_score(c: Vector2i) -> int:
	var t := st.view.terrain_at(c)
	if t in HEAL_TERRAIN:
		return 8
	var e := Rules.terrain_effect(u, st.view.terrain_at(u.pos))
	return maxi(e - 10, 0)


func _best_physical(c: Vector2i) -> Array:
	var bestv := 0
	var bt: BUnit = null
	for cell in st.actions.attack_cells(u, c):
		var t := st.unit_at(cell)
		if t == null or t == u or not t.active() or not t.is_enemy_of(u):
			continue
		var s := _phys_score(t, c)
		if s > bestv:
			bestv = s
			bt = t
	return [bestv, bt]


func _phys_score(t: BUnit, c: Vector2i) -> int:
	var s := 0
	var d := Rules.calc_damage(u, t, st.view.terrain_at(u.pos), st.view.terrain_at(t.pos), false, 0)
	var mh := maxi(t.max_hp(), 1)
	if d >= t.hp:
		s = 80
	elif d * 10 / mh >= 1:
		s = 16
	elif t.hp * 100 / mh <= 40:
		s = 16
	elif u.mode == 1:
		s = 10
	else:
		s = 2
	if t.status & BUnit.ST_CONFUSION:
		s += 8
	if s > 0 and t.pid < 0x400:
		s += 8 if (t.pid == st.boss_pid or t.slot == 35) else 4
	if s < 75 and u.family() in MAGIC_FAMILIES:
		return 0
	if s > 1 and st.actions.can_attack(t, u, t.pos) and Shapes.range_cells(st.actions.attack_range_code(t), t.pos, st.view.map_w, st.view.map_h).has(c):
		s -= 1
	return s


func _best_strategy(c: Vector2i) -> Array:
	var bestv := 0
	var bs := -1
	var bt: BUnit = null
	for s in usable_strats:
		var sd := Game.strategy(s)
		var side_opp := s <= 38 or s >= 64
		var cast := Shapes.range_cells(int(sd.get("range", 0)), c, st.view.map_w, st.view.map_h, not side_opp)
		for cell in cast:
			var t := st.unit_at(cell)
			if t == null or not t.active():
				continue
			if t == u and side_opp:
				continue
			if side_opp != t.is_enemy_of(u) and t != u:
				continue
			if not side_opp and t.is_enemy_of(u):
				continue
			if not st.actions.usable_on(u, s, t):
				continue
			var v := mini(_strat_score(t, s, c), 255)
			if v <= 0:
				continue
			if int(sd.get("area", 0)) != 0:
				v = _area_adjust(s, cell, v, side_opp)
			if v > bestv:
				bestv = v
				bs = s
				bt = t
	return [bestv, bs, bt]


func _strat_score(t: BUnit, s: int, _c: Vector2i) -> int:
	var hpp := t.hp * 100 / maxi(t.max_hp(), 1)
	if s in [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 15, 16, 17, 18, 19, 20, 33, 34, 35, 36]:
		if not Rules.strat_terrain_ok(s, u, st.view.terrain_at(t.pos), st.weather()) and s <= 19:
			return 0
		var d := Rules.strat_damage(u, t, s, true)
		var mh := maxi(t.max_hp(), 1)
		var v := 1
		if d >= t.hp: v = 76
		elif d * 10 / mh >= 3: v = 30
		elif d * 10 / mh >= 1: v = 10
		if s == 20:
			if u.hp < u.max_hp(): v += 5
			if _wounded(u): v += 10
		if s in [33, 34] and hpp >= 40: v += 8
		if s in [35, 36] and Grid.manhattan(t.pos, u.pos) != 1: v += 10
		return v
	match s:
		21, 31, 32:
			var h := Rules.strat_hit(u, t, s, st.view.terrain_at(t.pos), st.weather())
			if h >= 35:
				return 15 + (15 if hpp >= 80 else 0)
			return 0
		22:
			return 20 if (u.mp <= u.max_mp() / 5 and t.mp >= 30) else 0
		37:
			if t.family() in [8, 9, 10, 11, 18, 19, 20] and Rules.strat_hit(u, t, s, st.view.terrain_at(t.pos), st.weather()) >= 60:
				return 15 + (7 if hpp >= 80 else 0)
			return 0
		39, 40, 43:
			return (50 + (5 if s == 40 else (10 if s == 43 else 0))) if _wounded(t) else 0
		41, 42:
			return 50 if _wounded(t) else 0
		44, 45, 62:
			if t.mp <= t.max_mp() / 5 and u.mp >= st.actions.strategy_mp(s):
				if t.family() == 9: return 1
				if t.family() in MAGIC_FAMILIES: return 12
				if t.family() == 0: return 6
			return 0
		46, 47:
			var v2 := 5
			if t.status == BUnit.ST_PARALYSIS and not (t.mode in [2, 3]): v2 += 25
			elif t.status == BUnit.ST_SEAL and t.family() in MAGIC_FAMILIES: v2 += 30
			elif t.status == BUnit.ST_CONFUSION: v2 += 35
			return v2 if t.status != 0 else 0
		57:
			if t.mode in [2, 3] or t.family() == 9: return 0
			if t.family() in [0, 19]: return 15
			if t.family() == 5: return 10 + Rules.rand(4)
			if t.family() == 8: return 10
			return Rules.rand(5)
	return 0


func _area_adjust(s: int, center: Vector2i, v: int, side_opp: bool) -> int:
	var hits: Array[BUnit] = []
	for cell in Shapes.area_cells(int(Game.strategy(s).get("area", 0)), u.pos, center, st.view.map_w, st.view.map_h):
		if cell == center:
			continue
		var t := st.unit_at(cell)
		if t and t.active() and (t.is_enemy_of(u) == side_opp):
			hits.append(t)
	if hits.is_empty():
		return v - 4 if v > 4 else 0
	for t in hits:
		if not st.actions.usable_on(u, s, t):
			continue
		if side_opp:
			v += 3
		elif s >= 39 and s <= 45:
			if t.hp * 100 / maxi(t.max_hp(), 1) < 60:
				v += 5
		elif s in [46, 47]:
			if t.status != 0:
				v += 3
		else:
			v += 3
	return maxi(v, 0)


# ------------------------------------------------------------------ movement helpers (§10.5.2)
func _goal_bonus(cell: Vector2i, v: int, seen: Dictionary = {}) -> void:
	if v < 9 or not st.view.in_bounds(cell) or seen.has(cell):
		return
	seen[cell] = true
	var occ := st.unit_at(cell, u)
	if int(layer_b.get(cell, 0)) == 0 and Rules.move_cost(u, st.view.terrain_at(cell)) < 999 and occ == null:
		layer_b[cell] = v
	if u.cls() in [15, 16]:
		return
	for d in Grid.DIRS:
		_goal_bonus(cell + d, v - 10 if v > 10 else v - 1, seen)


## Distance-to-goal grid (Dijkstra over U's move costs), then greedy walk from U.pos within mv.
func _step_toward_bonus(goal: Vector2i, mv: int) -> bool:
	var w := st.view.map_w
	var h := st.view.map_h
	var dist := {goal: 0}
	var open: Array = [[0, goal]]
	while not open.is_empty():
		var bi := 0
		for i in range(1, open.size()):
			if open[i][0] < open[bi][0]:
				bi = i
		var cur = open[bi]
		open.remove_at(bi)
		var c: Vector2i = cur[1]
		if dist.get(c, 1 << 30) < cur[0]:
			continue
		for d in Grid.DIRS:
			var n := c + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			var mc := Rules.move_cost(u, st.view.terrain_at(c))
			if mc >= 999:
				continue
			var o := st.unit_at(n, u)
			if o and o.is_enemy_of(u):
				continue
			var nd: int = cur[0] + mc
			if nd < dist.get(n, 1 << 30):
				dist[n] = nd
				open.append([nd, n])
	if not dist.has(u.pos):
		return false
	var p := u.pos
	var rem := mv
	var guard := 0
	while p != goal and guard < 200:
		guard += 1
		var bestn := Vector2i(-1, -1)
		var bestd: int = dist[p]
		for d in Grid.DIRS:
			var n := p + d
			if not dist.has(n):
				continue
			if n != goal and st.actions.in_zoc(u, n) and not (u.flags & BUnit.F_PASS):
				continue
			var mc := Rules.move_cost(u, st.view.terrain_at(n))
			if dist[n] < bestd and mc <= rem:
				bestd = dist[n]
				bestn = n
		if bestn.x < 0:
			break
		rem -= Rules.move_cost(u, st.view.terrain_at(bestn))
		p = bestn
	if p != goal:
		_goal_bonus(p, 20 if st.unit_at(p) != null else 10)
	return true


func _active(reach: Dictionary, mv: int) -> void:
	if _attack_cell_reachable(reach):
		_evaluate(reach)
		return
	# nearest attackable opposite unit (by straight path distance)
	var tgt: BUnit = null
	var bd := 1 << 30
	for t in st.units:
		if t.active() and t.is_enemy_of(u):
			var dd := Grid.manhattan(t.pos, u.pos)
			if dd < bd:
				bd = dd
				tgt = t
	if tgt == null:
		dest = u.pos
		return
	if _step_toward_bonus(tgt.pos, mv):
		_evaluate(reach)
	else:
		dest = u.pos


func _go_target(reach: Dictionary, mv: int) -> void:
	var tslot := Mem.r8(u.addr + 8)
	var goal: Vector2i
	if tslot != 0xff and tslot < 115:
		var tu := st.units[tslot]
		goal = tu.pos
		if tu.mode in [0, 4] and Mem.r8(tu.addr + 8) == 0xff:
			forbidden = Vector2i(Mem.r8(tu.addr + 9), Mem.r8(tu.addr + 10))
	else:
		goal = Vector2i(Mem.r8(u.addr + 9), Mem.r8(u.addr + 10))
	if u.flags & BUnit.F_PASS:
		dest = goal if reach.has(goal) else u.pos
		return
	if tslot != 0xff and _attack_cell_reachable(reach) and _target_attackable(reach, tslot):
		_goal_bonus(goal, 20)
		_evaluate(reach)
		return
	_goal_bonus(goal, 10)
	if _step_toward_bonus(goal, mv):
		_evaluate(reach)
	else:
		_active(reach, mv)


func _target_attackable(reach: Dictionary, tslot: int) -> bool:
	for c in reach:
		if layer_a.get(c) == st.units[tslot]:
			return true
	return false


func _arrival() -> void:
	if Mem.r8(u.addr + 8) == 0xff and u.mode in [0, 4]:
		var tp := Vector2i(Mem.r8(u.addr + 9), Mem.r8(u.addr + 10))
		if u.pos == tp:
			u.mode = 3


func _physical_attack() -> void:
	if u.mode == 4 or (u.flags & BUnit.F_PASS):
		return
	var t := choice_target
	if t == null or not t.active() or not st.actions.can_attack(u, t):
		t = null
		for c in st.actions.attack_cells(u, u.pos):
			var x := st.unit_at(c)
			if x and x.active() and x.is_enemy_of(u):
				t = x
	if t == null:
		return
	await st.actions.attack(u, t)
	if not t.active() and u.active() and u.has_effect(46):
		for c in st.actions.attack_cells(u, u.pos):
			var x := st.unit_at(c)
			if x and x.active() and x.is_enemy_of(u):
				await st.actions.attack(u, x)
				break
