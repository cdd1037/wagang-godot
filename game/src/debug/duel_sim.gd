class_name DuelSim
extends RefCounted
## Flow-test harness (WG_AUTOSAVE, docs/DEVELOPMENT.md): plays the story-scene 单挑 mini-game. Not game logic.
##
## A click on a move actor runs one of the sections 攻击 / 防御 / 绝招 / 回避 (also with a suffix such as
## "攻击（宇文成都）"); the enemy's answer is rolled inside it (test_random), and the bars are story flags. Those
## sections and the ones they goto test only flags and random rolls, and change only flags, so a dry run of their
## control flow on a copy of the flags plays a round exactly (the rest is presentation). A path through the comment
## "R剧本单挑失败" loses the duel, one into the section "R剧本单挑胜利" wins it.
## best_move() enumerates every outcome of a round with its probability (each test_random both ways) and picks the
## move with the best chance to win, looking DEPTH rounds ahead (expectimax over the flag states, memoised; an
## undecided end counts 0.5). The game's random stream is not touched. WG_DUELSIM=0 turns it off.

const WIN := "R剧本单挑胜利"
const LOSE := "R剧本单挑失败"
const MOVES := ["攻击", "防御", "绝招", "回避"]
const DEPTH := 5
const MAX_STEPS := 60000
const MAX_PATHS := 512

static var enabled := OS.get_environment("WG_AUTOSAVE") != "" and OS.get_environment("WG_DUELSIM") != "0"
static var _memo := {}           # "depth|state" → value
static var _scene_key := ""      # file/scene the memos and _flags belong to
static var _flags: Array = []    # the flags the scene's sections test: a state is their values
static var _check: Array = []    # WG_DUELSIM_CHECK: [flags before, predicted outcomes] of the last move played
static var _outs := {}           # "section|state" → outcomes


## The move sections of the current scene: clicked pid → [section indices with that test_clicked], in order.
static func move_sections(vm: EexVM) -> Dictionary:
	var out := {}
	var secs := vm.sections(vm.scene)
	for k in secs.size():
		var title := str(secs[k].get("title", "")).strip_edges()
		if not MOVES.any(func(m: String) -> bool: return title.begins_with(m)):
			continue
		for c in secs[k].get("conditions", []):
			if int(c["op"]) == 0x2d:
				var pid := int(c["args"][0]) & 0xfff
				if not out.has(pid):
					out[pid] = []
				out[pid].append(k)
	return out


## The section a click on `pid` runs with the flags `over` (the last one whose other conditions hold), or −1.
static func section_for(vm: EexVM, moves: Dictionary, pid: int, over: Dictionary) -> int:
	var secs := vm.sections(vm.scene)
	var chosen := -1
	for k in moves.get(pid, []):
		var ok := true
		for c in secs[k].get("conditions", []):
			var op := int(c["op"])
			if op == 0:
				break
			if op == 5 and not _flags_ok(c["args"], over):
				ok = false
				break
			if not op in [2, 5, 0x2d]:
				ok = false        # not a duel move after all
				break
		if ok:
			chosen = k
	return chosen


## The move to click among `pids` (actors on screen whose click runs a move section), or −1.
static func best_move(vm: EexVM, pids: Array) -> int:
	var moves := move_sections(vm)
	if OS.get_environment("WG_DUELSIM_CHECK") != "" and not _check.is_empty():
		_check_round()
	# a state is the values of the flags the scene's sections test, so the memos last through the scene's duels
	var sk := "%s/%d" % [vm.name, vm.scene]
	if sk != _scene_key or _memo.size() > 300000:
		_scene_key = sk
		_memo.clear()
		_outs.clear()
		_flags = _tested_flags(vm)
	var best := -1
	var best_v := -1.0
	var notes := []
	var t0 := Time.get_ticks_msec()
	for pid in pids:
		var k := section_for(vm, moves, pid, {})
		if k < 0:
			continue
		var v := _move_value(vm, moves, k, {}, DEPTH)
		notes.append("%s %.2f" % [str(vm.sections(vm.scene)[k].get("title", "")).strip_edges(), v])
		if v > best_v:
			best_v = v
			best = pid
	if OS.get_environment("WG_DUELSIM_CHECK") != "" and best >= 0:
		var outs := outcomes(vm, section_for(vm, moves, best, {}), {})
		var before := {}
		for o in outs:
			for f in o[1]:
				before[f] = Mem.flag(int(f))
		_check = [before, outs]
	if OS.get_environment("WG_TRACE_TEXT") != "" and best >= 0:
		print("  [duel] %s (%d ms)" % [", ".join(notes), Time.get_ticks_msec() - t0])
	return best


## The chance to win after playing move section `k` from the flags `over`, then the best moves for `d` − 1 rounds.
static func _move_value(vm: EexVM, moves: Dictionary, k: int, over: Dictionary, d: int) -> float:
	var v := 0.0
	for o in outcomes(vm, k, over):
		var res: int = o[2]
		v += float(o[0]) * (1.0 if res > 0 else (0.0 if res < 0 else _state_value(vm, moves, o[1], d - 1)))
	return v


static func _state_value(vm: EexVM, moves: Dictionary, over: Dictionary, d: int) -> float:
	if d <= 0:
		return 0.5
	var key := "%d|%s" % [d, _key(over)]
	if _memo.has(key):
		return _memo[key]
	var best := -1.0
	var seen := {}
	for pid in moves:
		var k := section_for(vm, moves, pid, over)
		if k < 0 or seen.has(k):
			continue
		seen[k] = true
		best = maxf(best, _move_value(vm, moves, k, over, d))
	if best < 0.0:
		best = 0.5
	_memo[key] = best
	return best


## Every outcome of playing section `k` of the current scene on the flags `over`: [[probability, flags after
## (only those that differ from the story flags), result 1 won / −1 lost / 0 neither], …].
static func outcomes(vm: EexVM, k: int, over: Dictionary) -> Array:
	var okey := "%d|%s" % [k, _key(over)]
	if _outs.has(okey):
		return _outs[okey]
	var out := []
	var sc := vm.scene
	var stack := [[k, 0, 0, [1], over.duplicate(), 1.0]]
	while not stack.is_empty() and out.size() < MAX_PATHS:
		var s: Array = stack.pop_back()
		var r := _run(vm, sc, s, stack)
		var after: Dictionary = s[4]
		for f in after.keys():
			if bool(after[f]) == Mem.flag(int(f)):
				after.erase(f)
		out.append([s[5], after, r])
	_outs[okey] = out
	return out


## Run one path from state [section, pc, depth, last, flags, probability] (changed in place) to its end. At a
## random roll it continues one way and pushes the other onto `stack`.
static func _run(vm: EexVM, sc: int, s: Array, stack: Array) -> int:
	var sec: int = s[0]
	var pc: int = s[1]
	var depth: int = s[2]
	var last: Array = s[3]
	var over: Dictionary = s[4]
	var body: Array = vm.sections(sc)[sec]["body"]
	for step in MAX_STEPS:
		if pc >= body.size():
			return 0
		var ins: Dictionary = body[pc]
		match int(ins["op"]):
			0:
				if depth == 0:
					return 0
				depth -= 1
				last.pop_back()
				pc += 1
			1:
				var c: Dictionary = ins["cond"]
				var cop := int(c["op"])
				var take := true
				if cop == 3:
					take = int(last[depth]) == 0
				elif cop == 0x76:
					var t: Dictionary = c.get("target", {})
					if t.is_empty():
						pc += 1
						continue
					if depth > 0:
						depth -= 1
						last.pop_back()
					if int(t["scene"]) != sc:
						return 0
					sec = int(t["section"])
					body = vm.sections(sc)[sec]["body"]
					if str(vm.sections(sc)[sec].get("title", "")).strip_edges() == WIN:
						return 1
					pc = int(t["index"])
					continue
				else:
					var r := true
					if cop == 2:
						if str(c["args"][0]).strip_edges() == LOSE:
							return -1
					elif cop == 5:
						r = _flags_ok(c["args"], over)
					elif cop == 0x6e:
						var q := clampf(mini(int(c["args"][0]), 100) / 100.0, 0.0, 1.0)
						if q > 0.0 and q < 1.0:
							# the other way: not taken, with 1 − q of this path's probability
							var l2 := last.duplicate()
							l2[depth] = 0
							stack.append([sec, int(ins["end"]), depth, l2, over.duplicate(), float(s[5]) * (1.0 - q)])
							s[5] = float(s[5]) * q
						r = q > 0.0
					else:
						return 0         # another test: not a duel round
					last[depth] = 1 if r else 0
					take = r
				if take:
					depth += 1
					last.append(1)
					pc += 1
				else:
					pc = int(ins["end"])
			3, 0x0c, 0x0d, 0x11:
				return 0
			0x76:
				var t: Dictionary = ins.get("target", {})
				if t.is_empty():
					pc += 1
					continue
				if depth > 0:
					depth -= 1
					last.pop_back()
				if int(t["scene"]) != sc:
					return 0
				sec = int(t["section"])
				body = vm.sections(sc)[sec]["body"]
				if str(vm.sections(sc)[sec].get("title", "")).strip_edges() == WIN:
					return 1
				pc = int(t["index"])
			0x0b:
				over[int(ins["args"][0])] = int(ins["args"][1]) != 0
				pc += 1
			_:
				pc += 1
	return 0


## WG_DUELSIM_CHECK: did the round that was played end in one of the predicted outcomes (on the flags they touch)?
static func _check_round() -> void:
	var before: Dictionary = _check[0]
	var hit := false
	for o in _check[1]:
		var same := true
		for f in before:
			var want: bool = o[1][f] if o[1].has(f) else before[f]
			if Mem.flag(int(f)) != want:
				same = false
				break
		if same:
			hit = true
			break
	print("  [duel-check] %s (%d outcomes, %d flags)" % ["ok" if hit else "MISMATCH", _check[1].size(), before.size()])
	_check = []


## The state: the values of the tested flags (story flags with `over` on top).
static func _key(over: Dictionary) -> String:
	var b := PackedByteArray()
	b.resize((_flags.size() + 7) / 8)
	for i in _flags.size():
		if _flag(int(_flags[i]), over):
			b[i >> 3] |= 1 << (i & 7)
	return b.hex_encode()


static func _tested_flags(vm: EexVM) -> Array:
	var seen := {}
	for sec in vm.sections(vm.scene):
		for ins in sec.get("conditions", []) + sec.get("body", []):
			var c: Dictionary = ins.get("cond", ins)
			if int(c.get("op", -1)) == 5:
				for f in c["args"][0] + c["args"][1]:
					seen[int(f)] = true
	var out := seen.keys()
	out.sort()
	return out


static func _flag(f: int, over: Dictionary) -> bool:
	return bool(over[f]) if over.has(f) else Mem.flag(f)


static func _flags_ok(a: Array, over: Dictionary) -> bool:
	for f in a[0]:
		if not _flag(int(f), over):
			return false
	for f in a[1]:
		if _flag(int(f), over):
			return false
	return true
