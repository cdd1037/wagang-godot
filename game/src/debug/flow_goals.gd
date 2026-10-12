class_name FlowGoals
extends RefCounted
## Flow-test harness (WG_AUTOSAVE, docs/DEVELOPMENT.md): steer the autoplayed player units by the battle script's
## position tests, which the AI that plays them knows nothing about. Not game logic.
##
## Each section of the battle scene whose other conditions hold now is read for its position tests (0x25 unit at,
## 0x26 unit in area, 0x41 count in area). Phase (0x40) and turn (0x3f) tests count as true; a section with any op
## besides those and the pure tests 0x05 / 0x36 / 0x79 / 0x2e is left out, so nothing runs.
## * A defeat section (its body sets story flag 1) that waits for an enemy on a cell: the nearest player unit goes
##   there and holds it, so no enemy can stand on it (S_02's 山寨被占领). An enemy closing in on such a cell (a
##   shorter walk there than at an earlier turn), within four of its moves, is the first target of every unit that
##   can hit it this turn (S_08's cavalry, sent for 鹿砦); not a duel foe or a spared side.
## * A defeat section that waits for player units in an area: those units never end a move there (S_04's
##   友军提前攻城: the battle is lost if anyone comes near the town before the ambush is drawn out). The same for a
##   section titled as a trap (机关, 陷阱, 中计: S_43's 机关第五区 hurts 管毅; S_36's 挖宝04中计 is no treasure),
##   unless it is about finding the mechanism (找到: S_36's 我军找到吊桥机关 lowers the bridge out of the maze), or it
##   sets a flag an objective waits for (S_36's 究极陷阱 has to go off before that mechanism works). Units walk round
##   these areas when there is a way round (BattleAI._flow_walk).
## * A section whose title names an objective (到达, 占领, 攻破, …; see GOAL_WORDS), or whose cells lie in the area
##   the map marks as 指定地点 (op 0x5b), and that waits for player units on a cell or in an area: those units walk
##   there (到达指定地点). Other position sections are mostly enemy triggers (伏兵起动, 我军过于南进 …) that would
##   only pull our units off what they defend. Sections without dialogue (treasure: 挖宝, 秘藏) come after the
##   others, and are dropped when they lie in the area of such a trigger or of a defeat section (S_45: 挖宝 inside
##   妖风1's area, where 罡岚万仞 takes 罗成's HP, and his fall loses the battle; S_04: 秘藏1 inside the town).
## * Sparing: a defeat section that counts an enemy side on the whole map ("fewer than n", S_03's 绿林军死伤过重) makes our
##   units leave that side alone, except the target 胜利条件 names ("★·击退盛彦师"; else the persons a section waits
##   for at HP 0, test_attr p 7 = 0). Those are every unit's goal, and the god-mode clear after turn 12 is skipped.
## * Duels: a section titled "…VS…" that waits for our unit next to someone (0x2e, S_13's 管毅VS杨素) sends that
##   unit there, and nobody hits that person meanwhile (a duel lowers his HP by script and keeps him on the map,
##   which the follow-up sections need). The god-mode clear after turn 12 still takes him (S_28, S_39). Duels come
##   after the objectives (S_08: the race to 鹿砦 before the duels with 宇文成都).
## Sections that wait for different units on the same cells are one goal, for the nearest of those units (S_31).
## "Nearest" is the cheapest walk by the unit's move costs; a unit that cannot get there is passed over, and a unit
## already sent to a single cell keeps it unless another is much nearer.
## WG_GOALS=0 turns it off, to compare.

const PURE := [5, 0x36, 0x79, 0x2e]
const POS := [0x25, 0x26, 0x41]
const FREE := [2, 0x40, 0x3f]
const MAX_GUARD_CELLS := 4      # a defeat area larger than this cannot be held
const FOUND := "找到"      # finding the mechanism is the objective (S_36's 我军找到吊桥机关, 我军找到城门机关1)
const GOAL_WORDS := ["到达", "占领", "攻破", "突破", "打开", "逃离", "撤离", "挖宝", "秘藏", "我军逃", FOUND]
const TRAP_WORDS := ["伏", "敌军"]
const SNARE_WORDS := ["机关", "陷阱", "中计"]     # a trap that springs on our units (S_43's 机关第五区, S_36's 挖宝04中计), unless FOUND

static var enabled := OS.get_environment("WG_AUTOSAVE") != "" and OS.get_environment("WG_GOALS") != "0"
static var _last := {}          # slot → goal text last traced
static var _traced := ""        # battle whose units were traced
static var sparing: Array = []  # sides not to thin out (see above), from the last compute
static var no_hit: Array = []   # persons a pending duel section waits for, from the last compute
static var no_go := {}          # slot → {cell: true} a defeat or trap section waits for that unit in (last compute)
static var threats: Array = []  # enemies closing in on a guarded cell, the nearest (in its moves) first (see above)
static var _approach := {}      # "battle/slot/cell" → [turn, its walk cost then, the cost at an earlier turn]
static var _holder := {}        # "battle/cell" → slot of the unit last sent to that single cell
const THREAT_MOVES := 4         # …that could get there within this many of their moves


## slot → {"cells": Array[Vector2i] (the nearest one counts), "hold": bool, "why": String}
static func compute(st: BattleStage) -> Dictionary:
	var out := {}
	threats = []
	var vm: EexVM = st.vm
	if vm == null or not vm.active:
		return out
	var ours: Array[BUnit] = []
	for u in st.units:
		if u.active() and u.mode == 7 and u.slot < 35:
			ours.append(u)
	if ours.is_empty():
		return out
	if OS.get_environment("WG_TRACE_SEC") != "" and _traced != vm.name:
		_traced = vm.name
		print("  [goal] our units: %s" % ", ".join(ours.map(func(x: BUnit) -> String: return x.person.name)))
	var guards: Array = []       # [cells, why]
	var reach: Array = []        # [units, cells, why]
	var minor: Array = []        # the same, sections without dialogue
	var duels: Array = []        # the same, "VS" sections (optional: after the objectives)
	var traps: Array = []        # areas of the other position sections that hold now (enemy triggers)
	var spare: Array = []        # sides a defeat section counts on the whole map
	var duel_pids: Array = []    # persons a "VS" section waits for next to one of ours
	var wanted: Array = []       # persons a section waits for at HP 0
	var avoid := {}              # slot → cells of defeat sections that wait for that unit
	var mark := _marked()
	var secs := vm.sections(vm.scene)
	var wanted_flags := _objective_flags(secs)
	for k in secs.size():
		var sec: Dictionary = secs[k]
		var pos: Array = []
		var ok := true
		for ins in sec.get("conditions", []):
			var op := int(ins["op"])
			if op == 0:
				break
			if op in POS:
				pos.append(ins)
			elif op == 0x2e and "VS" in str(sec.get("title", "")):
				pos.append(ins)      # a duel trigger: be next to the person
			elif op == 0x36 and _hp_zero(ins):
				pass                 # a person's HP 0: what the sparing rule looks for, counts as true
			elif op in PURE:
				if await vm._test(ins) == 0:
					ok = false
					break
			elif not op in FREE:
				ok = false
				break
		if not ok:
			continue
		var lost := _sets_lost(sec)
		for ins in sec.get("conditions", []):
			var a: Array = ins.get("args", [])
			if int(ins["op"]) == 0x41 and lost and int(a[3]) != 1 and int(a[2]) == 1 and int(a[1]) > 0 \
					and int(a[0]) in [2, 3, 5]:
				spare.append(int(a[0]))      # an enemy side (S_08's count of our own side is 我方有人撤退)
			elif int(ins["op"]) == 0x36 and not lost and int(a[1]) == 7 and int(a[2]) == 0 and int(a[3]) == 2:
				wanted.append(int(a[0]))
		if pos.is_empty():
			continue
		var why := "%d.%d %s" % [vm.scene, k, str(sec.get("title", "")).strip_edges()]
		var talk := _talks(sec)
		var title := str(sec.get("title", ""))
		var named := (GOAL_WORDS.any(func(w: String) -> bool: return w in title) or "VS" in title) \
				and not TRAP_WORDS.any(func(w: String) -> bool: return w in title)
		for ins in pos:
			var op := int(ins["op"])
			var a: Array = ins["args"]
			var cells: Array[Vector2i] = []
			var who: Array[BUnit] = []
			if op == 0x2e:
				var foe := st.unit_by_pid(int(a[1]))
				if foe == null or not foe.active():
					continue
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if dx != 0 or dy != 0:
							cells.append(foe.pos + Vector2i(dx, dy))
				who = _ours_of(st, int(a[0]), ours)
				if not who.is_empty():
					duel_pids.append(int(a[1]))
			elif op == 0x25:
				cells = [Vector2i(int(a[1]), int(a[2]))]
				who = _ours_of(st, int(a[0]), ours)
			elif op == 0x26:
				cells = _rect(int(a[1]), int(a[2]), int(a[3]), int(a[4]))
				who = _ours_of(st, int(a[0]), ours)
			else:
				# 0x41 side n cmp rect_flag x0 y0 x1 y1: only "at least n" / "exactly n > 0" inside a rectangle
				if int(a[3]) != 1 or int(a[1]) <= 0 or int(a[2]) == 1:
					continue
				cells = _rect(int(a[4]), int(a[5]), int(a[6]), int(a[7]))
				for u in ours:
					if st.side_match(u, int(a[0])):
						who.append(u)
			var goal := named or (not mark.is_empty() and cells.all(func(c: Vector2i) -> bool: return c in mark))
			if SNARE_WORDS.any(func(w: String) -> bool: return w in title) and not FOUND in title \
					and not _sets_any(secs, k, wanted_flags):
				for u in who:
					avoid[u.slot] = avoid.get(u.slot, []) + cells
				continue
			if lost:
				if who.is_empty() and cells.size() <= MAX_GUARD_CELLS:
					guards.append([cells, why])
				for u in who:
					avoid[u.slot] = avoid.get(u.slot, []) + cells
			elif goal and not who.is_empty():
				(duels if op == 0x2e else (reach if talk else minor)).append([who, cells, why])
			elif not goal and not who.is_empty() and cells.size() > 1:
				traps.append(cells)
	sparing = spare
	no_hit = duel_pids
	no_go = {}
	for slot in avoid:
		var set := {}
		for c in avoid[slot]:
			set[c] = true
		no_go[slot] = set
	if OS.get_environment("WG_TRACE_SEC") != "" and _last.get(-2, "") != str(avoid.keys()):
		_last[-2] = str(avoid.keys())
		if not avoid.is_empty():
			print("  [goal] keep out of defeat and trap areas: %s" % ", ".join(avoid.keys().map(
					func(k: int) -> String: return st.units[k].person.name)))
	if not spare.is_empty():
		# the target named by 胜利条件 ("★·击退盛彦师"), else every person a section waits for at HP 0
		var named: Array = []
		var win := st.victory_text.split("失败条件")[0]
		for x in st.units:
			if x.active() and x.person.name != "" and ("击退" + x.person.name) in win:
				named.append(x.pid)
		if not named.is_empty():
			wanted = named
		var targets: Array = []
		for pid in wanted:
			var w := st.unit_by_pid(pid)
			if w and w.active():
				targets.append(w)
		for u in ours:
			var cells: Array[Vector2i] = []
			for w in targets:
				for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					cells.append(w.pos + d)
			var g := {"cells": cells, "hold": true, "why": "spare side %s, go for %s" % [spare, wanted], "spare": spare,
					"wanted": wanted}
			if cells.is_empty():
				g["cells"] = [u.pos]
			out[u.slot] = g
		if OS.get_environment("WG_TRACE_SEC") != "" and _last.get(-1, "") != str(wanted):
			print("  [goal] sparing side %s, going for %s" % [spare, wanted])
			_last[-1] = str(wanted)
		return out
	# guards first: each cell to the nearest free unit, one whose arrival a reach goal on that cell waits for if
	# there is one (S_08's 鹿砦: the defeat waits for an enemy there, the objective for one of four persons)
	var held: Array[Vector2i] = []
	for g in guards:
		for c in g[0]:
			var pool: Array = []
			for r in reach:
				if r[1].size() == 1 and r[1][0] == c:
					pool += r[0]
			var race := not pool.is_empty()
			if pool.is_empty():
				pool = ours
			var best := _nearest(st, pool, c, out)
			if best:
				out[best.slot] = {"cells": [c], "hold": true, "why": "guard " + str(g[1])}
				held.append(c)
			if race:
				# an objective the enemy also makes for: everyone it waits for races there (S_08's 鹿砦, behind
				# the enemy's line; one of them gets through)
				for u in pool:
					if not out.has(u.slot):
						out[u.slot] = {"cells": [c], "hold": true, "why": "race " + str(g[1])}
	# an enemy closing in on a guarded cell (its walk there shorter than at an earlier turn) and within THREAT_MOVES
	# of its moves is everyone's first target (S_08: the cavalry that 内郭军方针变更 sends for 鹿砦 rides through
	# the gate's guards, who block our way to it; the guards beside 鹿砦 never step on it)
	var near := {}       # threat → its moves from the cell, the nearest first
	var to_cell := {}    # "cell/family" → walk costs to the cell (one search per movement family)
	for c in held:
		for x in st.units:
			if not x.active() or not x.is_enemy_of(ours[0]) or x.pid in duel_pids:
				continue
			var fk := "%s/%d" % [c, x.family()]
			if not to_cell.has(fk):
				to_cell[fk] = _costs_to(st, x, c)
			var k := int(to_cell[fk].get(x.pos, 1 << 30))
			var key := "%s/%d/%s" % [vm.name, x.slot, c]
			var e: Array = _approach.get(key, [st.turn, k, -1])
			if int(e[0]) > st.turn:
				e = [st.turn, k, -1]          # the battle again (a retry)
			elif int(e[0]) < st.turn:
				e = [st.turn, k, int(e[1])]
			_approach[key] = e
			if int(e[2]) >= 0 and k < int(e[2]) and k <= THREAT_MOVES * x.move_points():
				near[x] = minf(float(near.get(x, INF)), float(k) / maxi(x.move_points(), 1))
	threats = near.keys()
	threats.sort_custom(func(a: BUnit, b: BUnit) -> bool: return near[a] < near[b])
	if OS.get_environment("WG_TRACE_SEC") != "" and _last.get(-3, "") != str(threats.map(func(x: BUnit) -> int: return x.slot)):
		_last[-3] = str(threats.map(func(x: BUnit) -> int: return x.slot))
		if not threats.is_empty():
			print("  [goal] threats to the guarded cells: %s" % ", ".join(threats.map(func(x: BUnit) -> String: return x.person.name)))
	# then the reach goals, the duels, the treasure
	for cells in avoid.values():
		traps.append(cells)
	minor = minor.filter(func(r: Array) -> bool:
		return not traps.any(func(a: Array) -> bool: return r[1].all(func(c: Vector2i) -> bool: return c in a)))
	_assign(st, _merged(reach) + _merged(duels) + _merged(minor), out, held, avoid)
	if OS.get_environment("WG_TRACE_SEC") != "":
		for slot in out:
			var t := "%s → %s" % [out[slot]["why"], out[slot]["cells"][0]]
			if _last.get(slot, "") != t:
				print("  [goal] %s: %s" % [st.units[slot].person.name, t])
				_last[slot] = t
	return out


## Hand out reach entries [units, cells, why] to units not yet in `out`; a single cell needs only one unit (the
## nearest), and none when a guard already holds it.
static func _assign(st: BattleStage, list: Array, out: Dictionary, held: Array, avoid: Dictionary) -> void:
	for r in list:
		var who: Array = r[0].filter(func(u: BUnit) -> bool:
			return not r[1].all(func(c: Vector2i) -> bool: return c in avoid.get(u.slot, [])))
		var cells: Array = r[1]
		if cells.size() == 1 and cells[0] in held:
			continue
		if cells.size() == 1:
			var best := _nearest(st, who, cells[0], out)
			who = [best] if best else []
		for u in who:
			if not out.has(u.slot):
				out[u.slot] = {"cells": cells, "hold": true, "why": "reach " + str(r[2])}


## Reach entries with the same cells as one, with all their units (S_31's corners: one section per 主攻手 each), so
## a single cell gets the nearest of them and the others are free for the next.
static func _merged(list: Array) -> Array:
	var out: Array = []
	var at := {}
	for r in list:
		var key := str(r[1])
		if at.has(key):
			var e: Array = out[at[key]]
			for u in r[0]:
				if not u in e[0]:
					e[0].append(u)
		else:
			at[key] = out.size()
			out.append([r[0].duplicate(), r[1], r[2]])
	return out


## The cells of the 指定地点 marker (op 0x5b) while the map shows it, else [].
static func _marked() -> Array[Vector2i]:
	if Mem.r32(BattleStage.GOAL_FLAG) == 0:
		return []
	var a := BattleStage.GOAL_AREA
	return _rect(Mem.r8(a), Mem.r8(a + 1), Mem.r8(a + 2), Mem.r8(a + 3))


## Unit `u` (autoplayed) must not end a move on `c` (a defeat section's area, see above).
static func avoids(u: BUnit, c: Vector2i) -> bool:
	return enabled and no_go.has(u.slot) and no_go[u.slot].has(c)


## test_attr p 7 0 2: person p's battle-unit HP is 0.
static func _hp_zero(ins: Dictionary) -> bool:
	var a: Array = ins["args"]
	return int(a[1]) == 7 and int(a[2]) == 0 and int(a[3]) == 2


## Our units may hit `x` (sparing: not a spared side, unless it is a wanted person).
static func may_hit(goal: Dictionary, x: BUnit) -> bool:
	if x.pid in no_hit:
		return false
	if not goal.has("spare") or x.pid in goal["wanted"]:
		return true
	for s in goal["spare"]:
		if x.colour == s or (s == 5 and x.colour >= 2) or (s == 4 and x.colour <= 1) or s == 6:
			return false
	return true


## The god-mode cheat leaves `x` at its normal damage (sparing).
static func spared(x: BUnit) -> bool:
	return x.pid in no_hit or (not sparing.is_empty() and not may_hit({"spare": sparing, "wanted": []}, x))


static func _ours_of(st: BattleStage, pid: int, ours: Array[BUnit]) -> Array[BUnit]:
	var out: Array[BUnit] = []
	for u in st.units_for(pid):
		if u in ours:
			out.append(u)
	return out


static func _rect(x0: int, y0: int, x1: int, y1: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			out.append(Vector2i(x, y))
	return out


## The unit of `pool` not yet in `out` with the cheapest walk to `c` by its own move costs (other units ignored);
## one that cannot get there at all is left out (S_08's 齐国远, shut in at (0, 0)).
static func _nearest(st: BattleStage, pool: Array, c: Vector2i, out: Dictionary) -> BUnit:
	var best: BUnit = null
	var best_cost := 1 << 30
	var key := "%s/%s" % [st.vm.name if st.vm else "", c]
	var had: Variant = _holder.get(key)
	var had_cost := 1 << 30
	for u in pool:
		if out.has(u.slot):
			continue
		var k := _walk_cost(st, u, c)
		if u.slot == had:
			had_cost = k
		if k < best_cost:
			best = u
			best_cost = k
	# keep the unit already on its way (else two units swap two goals at every move) unless one is much nearer
	# (S_36's mechanism, when 究极陷阱 walls the way its first pick had)
	if had_cost < (1 << 30) and had_cost <= best_cost * 3 / 2 + 4:
		best = st.units[int(had)]
	if best:
		_holder[key] = best.slot
	return best


## The cost of `u`'s cheapest walk from its cell to `c` over its move costs (cost buckets, as BattleAI._flow_walk);
## 1 << 30 when `c` cannot be reached.
static func _walk_cost(st: BattleStage, u: BUnit, c: Vector2i) -> int:
	var far := {u.pos: 0}
	var buckets := {0: [u.pos]}
	var level := 0
	var top := 0
	while level <= top:
		for p in buckets.get(level, []):
			if int(far[p]) != level:
				continue
			if p == c:
				return level
			for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				var n: Vector2i = p + d
				if not st.view.in_bounds(n):
					continue
				var step := Rules.move_cost(u, st.view.terrain_at(n))
				if step >= 255:
					continue
				var k := level + step
				if not far.has(n) or k < int(far[n]):
					far[n] = k
					if not buckets.has(k):
						buckets[k] = []
					buckets[k].append(n)
					top = maxi(top, k)
		buckets.erase(level)
		level += 1
	return 1 << 30


## The flags that objective sections (titles with GOAL_WORDS) need set.
static func _objective_flags(secs: Array) -> Dictionary:
	var out := {}
	for sec in secs:
		var title := str(sec.get("title", ""))
		if not GOAL_WORDS.any(func(w: String) -> bool: return w in title):
			continue
		for c in sec.get("conditions", []):
			if int(c["op"]) == 5:
				for f in c["args"][0]:
					out[int(f)] = true
	return out


## Section k sets one of `flags` (following its gotos within the scene): a trap that an objective needs sprung
## (S_36's 究极陷阱发动1/2 set flag 16, which 我军找到吊桥机关 waits for), so not one to keep out of.
static func _sets_any(secs: Array, k: int, flags: Dictionary, depth := 0) -> bool:
	if flags.is_empty() or depth > 3:
		return false
	for ins in secs[k].get("body", []):
		var op := int(ins.get("op", -1))
		if op == 0x0b and int(ins["args"][1]) != 0 and flags.has(int(ins["args"][0])):
			return true
		if op == 0x76:
			var t: Dictionary = ins.get("target", {})
			if not t.is_empty() and int(t.get("section", -1)) >= 0 and int(t["section"]) < secs.size() \
					and _sets_any(secs, int(t["section"]), flags, depth + 1):
				return true
	return false


## The cost of the cheapest walk to `c` from every cell, by the move costs of `u`'s family (as `_walk_cost`, searched
## from `c` backwards: a step costs what entering its cell costs).
static func _costs_to(st: BattleStage, u: BUnit, c: Vector2i) -> Dictionary:
	var far := {c: 0}
	var buckets := {0: [c]}
	var level := 0
	var top := 0
	while level <= top:
		for p in buckets.get(level, []):
			if int(far[p]) != level:
				continue
			var step := Rules.move_cost(u, st.view.terrain_at(p))
			if step >= 255:
				continue
			for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				var n: Vector2i = p + d
				if not st.view.in_bounds(n) or Rules.move_cost(u, st.view.terrain_at(n)) >= 255:
					continue
				var k := level + step
				if not far.has(n) or k < int(far[n]):
					far[n] = k
					if not buckets.has(k):
						buckets[k] = []
					buckets[k].append(n)
					top = maxi(top, k)
		buckets.erase(level)
		level += 1
	return far


static func _talks(sec: Dictionary) -> bool:
	for ins in sec.get("body", []):
		if str(ins.get("name", "")) in ["dialog", "info"]:
			return true
	return false


## The body sets story flag 1 ("战斗失败": the scripts' lost-battle flag).
static func _sets_lost(sec: Dictionary) -> bool:
	for ins in sec.get("body", []):
		if int(ins["op"]) == 0x0b and int(ins["args"][0]) == 1 and int(ins["args"][1]) == 1:
			return true
	return false
