extends Node
## Loads every script under res://src so parse errors show up, and checks that every opcode the story (R_xx) and
## battle (S_xx) scripts use has a handler on that kind of stage (EexVM.handler) or is one the VM runs itself.
## Prints "t_parse: PASS" (N scripts, M opcodes).

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
	print("t_parse: %s (%d scripts, %d opcodes in use, %d bad)" % ["PASS" if bad == 0 else "FAILED", files.size(), n, bad])
