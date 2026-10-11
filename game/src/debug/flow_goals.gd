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
## * A section whose title names an objective (到达, 占领, 攻破, …; see GOAL_WORDS) and that waits for player units
##   on a cell or in an area: those units walk there (到达指定地点). Other position sections are mostly enemy
##   triggers (伏兵起动, 我军过于南进 …) that would only pull our units off what they defend. Sections without
##   dialogue (treasure: 挖宝, 秘藏) come after the others, and are dropped when they lie in the area of such a
##   trigger (S_45: 挖宝 inside 妖风1's area, where 罡岚万仞 takes 罗成's HP, and his fall loses the battle).
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
			elif op in PURE:
				if await vm._test(ins) == 0:
					ok = false
					break
			elif not op in FREE:
				ok = false
				break
		if not ok or pos.is_empty():
			continue
		var why := "%d.%d %s" % [vm.scene, k, str(sec.get("title", "")).strip_edges()]
		var lost := _sets_lost(sec)
		var talk := _talks(sec)
		var title := str(sec.get("title", ""))
		var goal := GOAL_WORDS.any(func(w: String) -> bool: return w in title) \
				and not TRAP_WORDS.any(func(w: String) -> bool: return w in title)
		for ins in pos:
			var op := int(ins["op"])
			var a: Array = ins["args"]
			var cells: Array[Vector2i] = []
			var who: Array[BUnit] = []
			if op == 0x25:
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
			if lost:
				if who.is_empty() and cells.size() <= MAX_GUARD_CELLS:
					guards.append([cells, why])
			elif goal and not who.is_empty():
				(reach if talk else minor).append([who, cells, why])
			elif not goal and not who.is_empty() and cells.size() > 1:
				traps.append(cells)
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
	minor = minor.filter(func(r: Array) -> bool:
		return not traps.any(func(a: Array) -> bool: return r[1].all(func(c: Vector2i) -> bool: return c in a)))
	for r in reach + minor:
		var who: Array = r[0]
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
