class_name FlowGoals
extends RefCounted
## Flow-test harness (WG_AUTOSAVE, docs/DEVELOPMENT.md): steer the autoplayed player units by the battle script's
## position tests, which the AI that plays them knows nothing about. Not game logic.
##
## Each section of the battle scene whose other conditions hold now is read for its position tests (0x25 unit at,
## 0x26 unit in area, 0x41 count in area). Phase (0x40) and turn (0x3f) tests count as true; a section with any op
## besides those and the pure tests 0x05 / 0x36 / 0x79 / 0x2e is left out, so nothing runs.
## * A defeat section (its body sets story flag 1) that waits for an enemy on a cell: the nearest player unit goes
##   there and holds it, so no enemy can stand on it (S_02's 山寨被占领).
## * A defeat section that waits for player units in an area: those units never end a move there (S_04's
##   友军提前攻城: the battle is lost if anyone comes near the town before the ambush is drawn out).
## * A section whose title names an objective (到达, 占领, 攻破, …; see GOAL_WORDS), or whose cells lie in the area
##   the map marks as 指定地点 (op 0x5b), and that waits for player units on a cell or in an area: those units walk
##   there (到达指定地点). Other position sections are mostly enemy triggers (伏兵起动, 我军过于南进 …) that would
##   only pull our units off what they defend. Sections without dialogue (treasure: 挖宝, 秘藏) come after the
##   others, and are dropped when they lie in the area of such a trigger or of a defeat section (S_45: 挖宝 inside
##   妖风1's area, where 罡岚万仞 takes 罗成's HP, and his fall loses the battle; S_04: 秘藏1 inside the town).
## * Sparing: a defeat section that counts a side on the whole map ("fewer than n", S_03's 绿林军死伤过重) makes our
##   units leave that side alone, except the target 胜利条件 names ("★·击退盛彦师"; else the persons a section waits
##   for at HP 0, test_attr p 7 = 0). Those are every unit's goal, and the god-mode clear after turn 12 is skipped.
## * Duels: a section titled "…VS…" that waits for our unit next to someone (0x2e, S_13's 管毅VS杨素) sends that
##   unit there, and nobody hits that person meanwhile (a duel lowers his HP by script and keeps him on the map,
##   which the follow-up sections need). The god-mode clear after turn 12 still takes him (S_28, S_39).
## Sections that wait for different units on the same cells are one goal, for the nearest of those units (S_31).
## WG_GOALS=0 turns it off, to compare.

const PURE := [5, 0x36, 0x79, 0x2e]
const POS := [0x25, 0x26, 0x41]
const FREE := [2, 0x40, 0x3f]
const MAX_GUARD_CELLS := 4      # a defeat area larger than this cannot be held
const GOAL_WORDS := ["到达", "占领", "攻破", "突破", "打开", "逃离", "撤离", "挖宝", "秘藏"]
const TRAP_WORDS := ["伏", "敌军"]

static var enabled := OS.get_environment("WG_AUTOSAVE") != "" and OS.get_environment("WG_GOALS") != "0"
static var _last := {}          # slot → goal text last traced
static var _traced := ""        # battle whose units were traced
static var sparing: Array = []  # sides not to thin out (see above), from the last compute
static var no_hit: Array = []   # persons a pending duel section waits for, from the last compute
static var no_go := {}          # slot → cells a defeat section waits for that unit in, from the last compute


## slot → {"cells": Array[Vector2i] (the nearest one counts), "hold": bool, "why": String}
static func compute(st: BattleStage) -> Dictionary:
	var out := {}
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
	var traps: Array = []        # areas of the other position sections that hold now (enemy triggers)
	var spare: Array = []        # sides a defeat section counts on the whole map
	var duel_pids: Array = []    # persons a "VS" section waits for next to one of ours
	var wanted: Array = []       # persons a section waits for at HP 0
	var avoid := {}              # slot → cells of defeat sections that wait for that unit
	var mark := _marked()
	var secs := vm.sections(vm.scene)
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
			if int(ins["op"]) == 0x41 and lost and int(a[3]) != 1 and int(a[2]) == 1 and int(a[1]) > 0:
				spare.append(int(a[0]))
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
			if lost:
				if who.is_empty() and cells.size() <= MAX_GUARD_CELLS:
					guards.append([cells, why])
				for u in who:
					avoid[u.slot] = avoid.get(u.slot, []) + cells
			elif goal and not who.is_empty():
				(reach if talk else minor).append([who, cells, why])
			elif not goal and not who.is_empty() and cells.size() > 1:
				traps.append(cells)
	sparing = spare
	no_hit = duel_pids
	no_go = avoid
	if OS.get_environment("WG_TRACE_SEC") != "" and _last.get(-2, "") != str(avoid.keys()):
		_last[-2] = str(avoid.keys())
		if not avoid.is_empty():
			print("  [goal] keep out of defeat areas: %s" % ", ".join(avoid.keys().map(
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
	# guards first: each cell to the nearest free unit
	for g in guards:
		for c in g[0]:
			var best: BUnit = null
			for u in ours:
				if out.has(u.slot):
					continue
				if best == null or _dist(u.pos, c) < _dist(best.pos, c):
					best = u
			if best:
				out[best.slot] = {"cells": [c], "hold": true, "why": "guard " + str(g[1])}
	# then the reach goals; a single cell needs only one unit (the nearest)
	for cells in avoid.values():
		traps.append(cells)
	minor = minor.filter(func(r: Array) -> bool:
		return not traps.any(func(a: Array) -> bool: return r[1].all(func(c: Vector2i) -> bool: return c in a)))
	for r in _merged(reach) + _merged(minor):
		var who: Array = r[0].filter(func(u: BUnit) -> bool:
			return not r[1].all(func(c: Vector2i) -> bool: return c in avoid.get(u.slot, [])))
		var cells: Array = r[1]
		if cells.size() == 1:
			var best: BUnit = null
			for u in who:
				if not out.has(u.slot) and (best == null or _dist(u.pos, cells[0]) < _dist(best.pos, cells[0])):
					best = u
			who = [best] if best else []
		for u in who:
			if not out.has(u.slot):
				out[u.slot] = {"cells": cells, "hold": true, "why": "reach " + str(r[2])}
	if OS.get_environment("WG_TRACE_SEC") != "":
		for slot in out:
			var t := "%s → %s" % [out[slot]["why"], out[slot]["cells"][0]]
			if _last.get(slot, "") != t:
				print("  [goal] %s: %s" % [st.units[slot].person.name, t])
				_last[slot] = t
	return out


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
	return enabled and c in no_go.get(u.slot, [])


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


static func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


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
