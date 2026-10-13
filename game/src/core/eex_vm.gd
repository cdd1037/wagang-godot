class_name EexVM
extends RefCounted
## Interpreter for EEX scenario scripts (JSON produced by tools/eex.py), following the original
## execution model (docs/eex.md §4):
##  * poll(): when no body is running, evaluate every section of the current scene; the LAST section
##    whose condition list is all-true runs. A scene with exactly one section is linear: when its body
##    ends the next scene starts. Multi-section scenes are event loops left via next_scene/goto_scenario.
##  * Bodies are flat lists; nesting is tracked at runtime (IF pushes a level, END pops one, a goto at
##    depth > 0 pops one level and continues at the target — possibly in another section).
## Opcodes are dispatched to `op_<name>(ins)` of the host, or of the objects in `handlers` (searched after it, in
## order: a stage can keep groups of opcodes in objects of their own); tests return bool; handlers may await. The
## ops the VM runs itself are VM_OPS.

signal file_finished

## Ops the VM runs itself (end, if, comment, else, goto): they need no handler.
const VM_OPS := ["end", "if", "comment", "else", "goto"]
## Ops that only read or write the emulated memory: no random roll, nothing shown, played or waited for. A run that
## executes only these and leaves memory as it was would do the same again (BattleStage.checkpoint stops there).
const PURE_OPS := ["int_var_op", "data_transfer", "set_flag", "set_byte_var", "copy_person_byte", "set_4ce004",
		"test_int_var", "test_flags", "test_attr", "test_side", "test_turn", "test_unit_at", "test_unit_in_area",
		"test_units_in_area", "test_adjacent", "test_event5", "test_event6"]

var data: Dictionary
var host: Object
var handlers: Array[Object] = []
var _dispatch: Dictionary = {}   # op name → Callable (invalid: no handler), filled on first use
var name := ""
var scene := 0
var running := false
var active := false          # false once the file has finished
var next_scene_pending := false
var end_file_pending := false
var abort := false
var trace := false
var last_section := -1
var next_op := -1            # opcode after the one being executed (-1 at the end of a body)
var impure := 0              # handlers called that are not PURE_OPS (BattleStage.checkpoint resets and reads it)
static var executed := 0     # instructions run by every VM so far (the UI bot's sign of progress)
var _warned: Dictionary = {}


func load_script(file: String) -> bool:
	var d: Variant = Assets.json("scripts/%s.json" % file, false)
	if d == null:
		push_error("script not found: " + file)
		return false
	data = d
	name = file
	trace = OS.get_environment("WG_TRACE_OPS") != ""
	scene = 0
	active = true
	running = false
	return true


func scene_count() -> int:
	return data.get("scenes", []).size()


func sections(sc: int) -> Array:
	var scs: Array = data.get("scenes", [])
	if sc < 0 or sc >= scs.size():
		return []
	return scs[sc]["sections"]


## The handler of op `n`: op_<n> of the host or of the first object in `handlers` that has it (an invalid
## Callable if none does).
func handler(n: String) -> Callable:
	var c: Variant = _dispatch.get(n)
	if c == null:
		c = Callable()
		var m := "op_" + n
		for o: Object in [host] + handlers:
			if o and o.has_method(m):
				c = Callable(o, m)
				break
		_dispatch[n] = c
	return c


func _call(ins: Dictionary) -> Variant:
	var n: String = ins["name"]
	if not n in PURE_OPS and not n in VM_OPS:
		impure += 1
	var c := handler(n)
	if c.is_valid():
		return await c.call(ins)
	if not _warned.has(n):
		_warned[n] = true
		push_warning("EEX unimplemented op %s (0x%02x) args=%s in %s" % [n, int(ins["op"]), ins["args"], name])
	return null


func _test(ins: Dictionary) -> int:
	# returns 1 true, 0 false (comments count as true)
	var op := int(ins["op"])
	if op == 2:
		return 1
	var r: Variant = await _call(ins)
	if r == null:
		# non-test handlers return 1 ("ok") in the original, so as IF conditions they count as true
		return 1
	return 1 if bool(r) else 0


## Condition list: qualifies if every instruction that returns a test result is true.
func check_conditions(sec: Dictionary) -> bool:
	for ins in sec.get("conditions", []):
		if int(ins["op"]) == 0:
			break
		var r := await _test(ins)
		if r == 0:
			return false
	return true


## One poll of the current scene. Returns true if a body ran.
func poll() -> bool:
	if not active or running:
		return false
	var secs := sections(scene)
	if secs.is_empty():
		_advance_scene()
		return false
	var chosen := -1
	for k in secs.size():
		if await check_conditions(secs[k]):
			chosen = k
	if chosen < 0:
		return false
	await run_section(chosen)
	return true


## Keep polling until the scene loop is idle (no section qualifies) or the file ends.
func poll_all(max_rounds := 1000) -> void:
	var n := 0
	while active and n < max_rounds:
		var ran := await poll()
		if not ran:
			break
		n += 1


func run_section(k: int) -> void:
	var secs := sections(scene)
	var single := secs.size() == 1
	running = true
	last_section = k
	if OS.get_environment("WG_TRACE_SEC") != "":
		var t := ""
		if host.has_method("trace_info"):
			t = host.trace_info()
		print("  [sec %s %d.%d] %s %s" % [name, scene, k, secs[k].get("title", ""), t])
	next_scene_pending = false
	end_file_pending = false
	abort = false
	var exited := await _run(secs[k]["body"], scene, k, 0)
	running = false
	if exited:
		# op 0x0c (0x4143a4 → status 8): run_block 0x4105a8 returns 5 at once; the scene and the file move on only
		# at an END (status 3), so the next poll picks from the same scene again (a story 单挑's draw replays it)
		return
	if end_file_pending:
		_finish_file()
	elif next_scene_pending or single:
		_advance_scene()


func _advance_scene() -> void:
	scene += 1
	if scene >= scene_count():
		_finish_file()


func _finish_file() -> void:
	active = false
	file_finished.emit()


func _body_of(sc: int, sec: int) -> Array:
	var secs := sections(sc)
	if sec < 0 or sec >= secs.size():
		return []
	return secs[sec]["body"]


## Runs a body; true when op 0x0c (exit_section) left it.
func _run(body: Array, sc: int, sec: int, start: int) -> bool:
	var pc := start
	var depth := 0
	var last: Array[int] = [1]        # per-level result of the most recent IF test
	var steps := 0
	while true:
		if abort or host == null:
			return false
		if pc >= body.size():
			return false
		var ins: Dictionary = body[pc]
		var op := int(ins["op"])
		steps += 1
		executed += 1
		if steps % 4000 == 0:
			await host.get_tree().process_frame
			if abort or not is_instance_valid(host):      # the stage went while the VM let a frame pass
				return false
		if trace:
			print("[%s %d.%d #%d d%d] %s %s" % [name, sc, sec, pc, depth, ins["name"], ins["args"]])
		match op:
			0:    # END of the innermost running level
				if next_scene_pending or end_file_pending:
					return false
				if depth == 0:
					return false
				depth -= 1
				last.pop_back()
				pc += 1
				continue
			1:    # IF <cond> {block}
				var c: Dictionary = ins["cond"]
				var take := false
				if int(c["op"]) == 3:
					take = last[depth] == 0
				elif int(c["op"]) == 0x76:
					# goto as an IF condition: treat as a jump
					var r0 := _goto_target(c)
					if r0.is_empty():
						pc += 1
						continue
					if depth > 0:
						depth -= 1
						last.pop_back()
					if int(r0["scene"]) != sc or int(r0["section"]) != sec:
						body = _body_of(int(r0["scene"]), int(r0["section"]))
						sc = int(r0["scene"])
						sec = int(r0["section"])
					pc = int(r0["index"])
					continue
				else:
					var r := await _test(c)
					if r == 0:
						last[depth] = 0
					elif r == 1:
						last[depth] = 1
					take = r != 0
				if take:
					depth += 1
					last.append(1)
					pc += 1
				else:
					pc = int(ins["end"])
				continue
			3:    # ELSE outside IF: abort block
				return false
			0x0c: # exit_section
				await _call(ins)
				return true
			0x0d: # next_scene: finishes after the current block's END
				await _call(ins)
				next_scene_pending = true
				pc += 1
				continue
			0x11: # goto_scenario
				await _call(ins)
				end_file_pending = true
				pc += 1
				continue
			0x76: # goto
				var t := _goto_target(ins)
				if t.is_empty():
					pc += 1
					continue
				if depth > 0:
					depth -= 1
					last.pop_back()
				if int(t["scene"]) != sc or int(t["section"]) != sec:
					body = _body_of(int(t["scene"]), int(t["section"]))
					sc = int(t["scene"])
					sec = int(t["section"])
				pc = int(t["index"])
				continue
		next_op = int(body[pc + 1]["op"]) if pc + 1 < body.size() else -1
		await _call(ins)
		pc += 1
	return false


func _goto_target(ins: Dictionary) -> Dictionary:
	return ins.get("target", {})
