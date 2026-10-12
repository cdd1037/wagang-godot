extends Node
## Loads every script under res://src so parse errors show up; checks that every opcode the story (R_xx) and battle
## (S_xx) scripts use has a handler on that kind of stage (EexVM.handler) or is one the VM runs itself, and that no
## script outside src/debug names a class of src/debug in its code (the game reaches the harness only through
## Game.hooks, so a build can leave src/debug out). Prints "t_parse: PASS" (N scripts, M opcodes).

func _scan(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)


func _ops(list: Array, out: Dictionary) -> void:
	for ins: Dictionary in list:
		out[str(ins["name"])] = true
		if ins.has("cond"):
			out[str(ins["cond"]["name"])] = true


func run() -> void:
	var files: Array = []
	_scan("res://src", files)
	var bad := 0
	for f in files:
		var s: GDScript = load(f)
		if s == null or not s.can_instantiate():
			print("t_parse: cannot load ", f)
			bad += 1
	# opcode coverage: the stage each kind of file runs on
	var hosts := {"R": StoryStage.new(), "S": BattleStage.new()}
	var used := {"R": {}, "S": {}}
	for f in DirAccess.get_files_at("res://assets/scripts"):
		if not f.ends_with(".json") or not (f.begins_with("R_") or f.begins_with("S_")):
			continue
		var d: Variant = Assets.json("scripts/" + f, false)
		for sc: Dictionary in d["scenes"]:
			for sec: Dictionary in sc["sections"]:
				_ops(sec["conditions"], used[f.substr(0, 1)])
				_ops(sec["body"], used[f.substr(0, 1)])
	var n := 0
	for kind in ["R", "S"]:
		var vm := EexVM.new()
		vm.host = hosts[kind]
		vm.handlers = hosts[kind].op_handlers()
		for op: String in used[kind]:
			n += 1
			if not (op in EexVM.VM_OPS) and not vm.handler(op).is_valid():
				print("t_parse: no handler for op %s in the %s scripts" % [op, "story" if kind == "R" else "battle"])
				bad += 1
		hosts[kind].free()
	bad += _debug_names(files)
	bad += _hook_coroutines()
	print("t_parse: %s (%d scripts, %d opcodes in use, %d bad)" % ["PASS" if bad == 0 else "FAILED", files.size(), n, bad])


## Scripts outside src/debug whose code (comments aside) names a class_name declared in src/debug.
func _debug_names(files: Array) -> int:
	var names: Array[String] = []
	for f: String in files:
		if f.begins_with("res://src/debug/"):
			var m := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)").search(FileAccess.get_file_as_string(f))
			if m:
				names.append(m.get_string(1))
	var word := RegEx.create_from_string("\\b(" + "|".join(names) + ")\\b")
	var bad := 0
	for f: String in files:
		if f.begins_with("res://src/debug/"):
			continue
		var k := 0
		for line in FileAccess.get_file_as_string(f).split("\n"):
			k += 1
			var code := line
			var h := code.find("#")
			if h >= 0:
				code = code.substr(0, h)
			var m := word.search(code)
			if m:
				print("t_parse: %s:%d names the debug class %s" % [f, k, m.get_string(1)])
				bad += 1
	return bad


## Every hook the harness awaits in awaits in TestHooks too (see core/test_hooks.gd).
func _hook_coroutines() -> int:
	var base := _awaiting_funcs(FileAccess.get_file_as_string("res://src/core/test_hooks.gd"))
	var harness := _awaiting_funcs(FileAccess.get_file_as_string(Game.HARNESS))
	var bad := 0
	for f: String in harness:
		if harness[f] and base.has(f) and not base[f]:
			print("t_parse: TestHooks.%s must be a coroutine: the harness's awaits" % f)
			bad += 1
	return bad


## func name → whether its body has an await.
func _awaiting_funcs(src: String) -> Dictionary:
	var out := {}
	var name := ""
	for line in src.split("\n"):
		if line.begins_with("func "):
			name = line.substr(5, line.find("(") - 5)
			out[name] = false
		elif name != "" and (line.begins_with("\t") or line == "") and "await " in line:
			out[name] = true
		elif not line.begins_with("\t") and line != "" and not line.begins_with("func "):
			name = ""
	return out
