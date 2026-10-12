class_name FlagPuzzle
extends RefCounted
## Flow-test harness (WG_AUTOSAVE, docs/DEVELOPMENT.md): solves a story scene's click puzzle whose answer is a set
## of story flags. Not game logic.
##
## R_14's verses: 管德昭解图赴东郡 runs once flags 111, 122, …, 188 are all set; clicking verse v (actor 608, 620, …)
## selects it (flag 2v), and then clicking slot s (actors 600/601, 602/603, …) places it there (flag 1vs).
## The target is a section of the current scene that has not run, whose conditions are flag tests only, and that
## needs at least MIN_FLAGS flags which click sections of the scene set. For each visible actor the section its
## click would run is dry-run on the flags (DuelSim's flag-only interpreter), then every follow-up click from there:
## the click whose best two-click outcome sets the most target flags is taken, and never one that clears a target
## flag already set (R_14's 第一句撤 takes a verse back) or that changes no flag. Ties go to the click that gains at
## once. No gain at all, or PATIENCE puzzle clicks without a new target flag (R_31, whose last pieces the dry runs
## get wrong): the usual clicking. WG_PUZZLE=0 turns it off.

const MIN_FLAGS := 4
const PATIENCE := 30     # puzzle clicks without a new target flag before the scene goes back to the usual clicking

static var enabled := (OS.get_environment("WG_AUTOSAVE") != "" or OS.get_environment("WG_UIBOT") != "") and OS.get_environment("WG_PUZZLE") != "0"
static var _progress := {}   # "file/scene" → [most target flags seen, puzzle clicks since]


## The actor to click among `pids` (on screen), or −1 when no click gains anything. `ran`: the sections that have
## run in this file ("scene.section").
static func best_click(vm: EexVM, pids: Array, ran: Dictionary) -> int:
	var clicks := _clicks(vm)
	if clicks.is_empty():
		return -1
	var goal := target(vm, ran, clicks)
	if goal.is_empty():
		return -1
	var now := _score(goal, {})
	var pk := "%s/%d" % [vm.name, vm.scene]
	var pr: Array = _progress.get(pk, [-1, 0])
	if now > int(pr[0]):
		pr = [now, 0]
	elif int(pr[1]) >= PATIENCE:
		return -1            # the dry runs and the scene disagree (R_31): click as usual
	_progress[pk] = pr
	var best := -1
	var best_v := now
	var best_first := -1
	for a in pids:
		var ka := _section_for(vm, clicks, int(a), {})
		if ka < 0:
			continue
		var o1 := _after(vm, ka, {})
		if not o1.keys().any(func(f: Variant) -> bool: return bool(o1[f]) != Mem.flag(int(f))):
			continue         # changes no flag (R_31's 秦琼 only talks)
		var v1 := _score(goal, o1)
		if v1 < 0:
			continue
		var v := v1
		for b in pids:       # the follow-up among the actors on screen now
			var kb := _section_for(vm, clicks, int(b), o1)
			if kb >= 0:
				v = maxi(v, _score(goal, _after(vm, kb, o1)))
		if v > best_v or (v == best_v and best >= 0 and v1 > best_first):
			best = int(a)
			best_v = v
			best_first = v1
	if best >= 0:
		pr[1] = int(pr[1]) + 1
		if OS.get_environment("WG_TRACE_TEXT") != "":
			print("  [puzzle] %d of %d flags, aiming at %d" % [now, goal["set"].size(), best_v])
	return best


## {"set": flags that must be set, "clear": flags that must stay clear} of the target section, or {}.
static func target(vm: EexVM, ran: Dictionary, clicks: Dictionary) -> Dictionary:
	var secs := vm.sections(vm.scene)
	var setters := {}
	for pid in clicks:
		for k in clicks[pid]:
			for ins in secs[k].get("body", []):
				if int(ins.get("op", -1)) == 0x0b and int(ins["args"][1]) != 0:
					setters[int(ins["args"][0])] = true
	var out := {}
	for k in secs.size():
		if ran.has("%d.%d" % [vm.scene, k]):
			continue
		var need: Array = []
		var keep: Array = []
		var ok := true
		for c in secs[k].get("conditions", []):
			var op := int(c["op"])
			if op == 0:
				break
			if op == 5:
				need += c["args"][0]
				keep += c["args"][1]
			elif op != 2:
				ok = false
				break
		if not ok:
			continue
		var n := need.filter(func(f: Variant) -> bool: return setters.has(int(f))).size()
		if n >= MIN_FLAGS and n > out.get("set", []).size():
			out = {"set": need, "clear": keep}
	return out


## Click sections of the current scene: clicked pid → section indices with that test_clicked, in order.
static func _clicks(vm: EexVM) -> Dictionary:
	var out := {}
	var secs := vm.sections(vm.scene)
	for k in secs.size():
		for c in secs[k].get("conditions", []):
			if int(c["op"]) == 0x2d:
				var pid := int(c["args"][0]) & 0xfff
				if not out.has(pid):
					out[pid] = []
				out[pid].append(k)
	return out


## The section a click on `pid` runs with the flags `over` (as a poll picks: the last that qualifies), or −1; a
## section with other tests than flags is not planned with.
static func _section_for(vm: EexVM, clicks: Dictionary, pid: int, over: Dictionary) -> int:
	var secs := vm.sections(vm.scene)
	var chosen := -1
	for k in clicks.get(pid, []):
		var ok := true
		for c in secs[k].get("conditions", []):
			var op := int(c["op"])
			if op == 0:
				break
			if op == 0x2d:
				ok = ok and (int(c["args"][0]) & 0xfff) == pid
			elif op == 5:
				ok = ok and DuelSim._flags_ok(c["args"], over)
			elif op != 2:
				ok = false
			if not ok:
				break
		if ok:
			chosen = k
	return chosen


## The flags after a dry run of section `k` from `over` (only those that differ from the story flags count).
static func _after(vm: EexVM, k: int, over: Dictionary) -> Dictionary:
	var s := [k, 0, 0, [1], over.duplicate(), 1.0]
	DuelSim._run(vm, vm.scene, s, [])
	return s[4]


## How many of the target's flags hold with `over`; −1 when one that holds now would be lost.
static func _score(goal: Dictionary, over: Dictionary) -> int:
	var n := 0
	for f in goal["set"]:
		var was := Mem.flag(int(f))
		var is_set := DuelSim._flag(int(f), over)
		if was and not is_set:
			return -1
		if is_set:
			n += 1
	for f in goal["clear"]:
		if not Mem.flag(int(f)) and DuelSim._flag(int(f), over):
			return -1
	return n
