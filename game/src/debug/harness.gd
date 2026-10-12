extends TestHooks
## The test harness and bots behind Game.hooks (core/test_hooks.gd): the flow-test harness (WG_AUTOSAVE: battle
## objectives FlowGoals, story 单挑 DuelSim, click puzzles FlagPuzzle, skips, caps and the god mode's field clear),
## the input bot (WG_INPUTBOT, WG_FXTEST), the UI bot (WG_UIBOT), WG_SAVETEST and the battle traces. Loaded by Game
## when this folder is in the build; everything here is switched on by environment variables (DEVELOPMENT.md).

## The flow goal of the player unit autoplay is playing (FlowGoals.compute), else empty. The UI bot sets it too.
var goal: Dictionary = {}
var _bot: InputBot


func boot(main: Node) -> void:
	if OS.get_environment("WG_UIBOT") != "":
		main.add_child(UiBot.new())       # plays through real input events (debug/ui_bot.gd)


# ------------------------------------------------------------------ battles
func skip_battle(st: BattleStage) -> bool:
	if Game.autoplay and Game.skip_battle_scenario == Game.scenario:
		print("== flow-test: skipping battle %s" % st.vm.name)
		Game.skip_battle_scenario = -1
		return true
	return false


func battle_start(st: BattleStage) -> void:
	if OS.get_environment("WG_INPUTBOT") != "":
		Game.autoplay = false
	if OS.get_environment("WG_TRACE_BATTLE") != "":
		for u in st.units:
			if u.exists() and u.slot < 35:
				print("  start: slot %d %s state %d pos %s hp %d" % [u.slot, u.person.name, u.state, u.pos, u.hp])
	if OS.get_environment("WG_SAVETEST") != "" and st.turn >= 2:
		var alive := 0
		for u in st.units:
			if u.active(): alive += 1
		print("SAVETEST resumed turn %d, %d active units, hero hp %d" % [st.turn, alive, st.units[0].hp])


func round_end(st: BattleStage) -> bool:
	var turn := st.turn
	if OS.get_environment("WG_SAVETEST") != "" and turn == 2:
		Game.save_game(18, st.save_state())     # not one of the player's slots 0-9
		var alive := 0
		for u in st.units:
			if u.active(): alive += 1
		print("SAVETEST saved turn %d, %d active units, hero hp %d" % [turn, alive, st.units[0].hp])
		st.get_tree().quit()
		return true
	var tp := OS.get_environment("WG_TRACE_PID")
	if turn == 2 and OS.get_environment("WG_TRACE_MAP") != "":
		# the battle map's terrain codes, one row per line (hex)
		for y in st.view.map_h:
			var row := ""
			for x in st.view.map_w:
				row += "%02x" % (st.view.terrain_at(Vector2i(x, y)) & 0xff)
			print("    [map %2d] %s" % [y, row])
	if tp == "all":
		# every unit on the map at each round start, by colour
		var rows := {}
		for x in st.units:
			if x.active():
				rows[x.colour] = rows.get(x.colour, []) + ["%s(%d,%d)%d" % [x.person.name, x.pos.x, x.pos.y, x.hp]]
		for k in rows:
			print("    [units %d] turn %d: %s" % [k, turn, " ".join(rows[k])])
	elif tp != "":
		# where person tp's unit is at each round start
		var x := st.unit_by_pid(int(tp))
		print("    [pid %s] turn %d: %s" % [tp, turn, "no unit" if x == null else "slot %d state %d hp %d/%d at %s" % [
				x.slot, x.state, x.hp, x.max_hp(), x.pos]])
	if Game.god and Game.autoplay and turn > 12 and FlowGoals.sparing.is_empty():
		# flow-test cheat: clear the field so scripted victory can trigger. Units on the map fall as in combat (HP 0,
		# EV[10]), and as after a fall in combat the scene is polled while they are still on the map, once per
		# fallen unit (a poll runs one section), so every kill section gets its turn (S_13's 杨素第一次死 restores
		# 杨素, who has to reach HP 0 three times); hidden ones just go. A pending duel's foe goes too: the duels are
		# optional, and S_28 / S_39 need every enemy gone.
		var fell := 0
		for e in range(35, 115):
			if st.units[e].active():
				await st.actions.unit_fell(st.units[e])
				fell += 1
			elif st.units[e].exists() and st.units[e].state == BUnit.STATE_HIDDEN:
				st.units[e].hp = 0
				st.units[e].state = 3
		st.refresh_units()
		for k in fell:
			if st._battle_finished():
				break
			await st.checkpoint()
	if Game.god and Game.autoplay and turn > 60:
		# flow-test: the victory needs a scripted move the autoplay AI never makes (e.g. a duel that only starts
		# when the hero reaches a certain enemy) — go to the aftermath
		print("== flow-test: turn cap, skipping to aftermath of %s" % st.vm.name)
		st.vm.scene = mini(2, st.vm.scene_count() - 1)
		return true
	return false


func player_phase(input: BattleInput) -> bool:
	var st := input.st
	if _bot and (not is_instance_valid(_bot) or _bot.get_parent() != st):
		_bot = null                     # a new battle gets a new bot
	var botdir := OS.get_environment("WG_INPUTBOT")
	if botdir != "":
		if _bot == null:
			_bot = InputBot.new(st, botdir)
			st.add_child(_bot)
		if st.turn > int(OS.get_environment("WG_BOTTURNS") if OS.get_environment("WG_BOTTURNS") != "" else "2"):
			st.get_tree().quit()
			return true
		_bot.run_phase()                # drives the player phase below through input events
		return false
	var fx := OS.get_environment("WG_FXTEST")
	if (Game.autoplay or Game.demo) and fx != "":
		# cast these strategies with autoplay (dialogue skipped) and print each target's outcome
		if _bot == null:
			_bot = InputBot.new(st, "")
			st.add_child(_bot)
		await _bot.fx_test(fx.split(","))
		return true
	return false


func before_auto_unit(st: BattleStage, u: BUnit) -> void:
	if FlowGoals.enabled:
		goal = (await FlowGoals.compute(st)).get(u.slot, {})


func after_auto_unit() -> void:
	goal = {}


func may_hit(_u: BUnit, t: BUnit) -> bool:
	return FlowGoals.may_hit(goal, t)


func avoids(u: BUnit, c: Vector2i) -> bool:
	return FlowGoals.avoids(u, c)


func spared(t: BUnit) -> bool:
	return FlowGoals.spared(t)


## Flow-test harness only (FlowGoals, not the original AI): walk to the reachable cell nearest the goal cells by
## U's move costs (other units ignored, round the areas U keeps out of when it can), or hold a goal cell already
## reached; then attack whatever is in range. A threat to a guarded cell that U can hit this turn comes first.
func player_walk(ai: BattleAI, mv: int) -> bool:
	if goal.is_empty():
		return false
	var u := ai.u
	var st := ai.st
	var cells: Array = goal["cells"]
	if u.pos in cells and goal["hold"]:
		ai._flood4(u.pos, 0)
		ai.dest = u.pos
		return true
	# the walk round the areas U keeps out of (FlowGoals.avoids), else straight through them
	var far := _goal_distances(ai, cells, true)
	if not far.has(u.pos):
		far = _goal_distances(ai, cells, false)
	if not far.has(u.pos):
		ai._active(mv)
		return true
	ai._flood(u.pos, mv, true, func(_n: Vector2i) -> bool: return false)
	ai.dest = u.pos
	# an enemy that threatens a guarded cell (FlowGoals.threats, the nearest to it first): hit the first one U can,
	# from the cell nearest the goal
	for x: BUnit in FlowGoals.threats:
		if not x.active() or not FlowGoals.may_hit(goal, x):
			continue
		var hit := false
		for c in ai.grid:
			if (c != u.pos and st.unit_at(c, u) != null) or FlowGoals.avoids(u, c) or not st.actions.can_attack(u, x, c):
				continue
			if not hit or int(far.get(c, 1 << 30)) < int(far.get(ai.dest, 1 << 30)):
				hit = true
				ai.dest = c
		if hit:
			ai.choice_target = x
			return true
	for c in ai.grid:
		if (c != u.pos and st.unit_at(c, u) != null) or FlowGoals.avoids(u, c):
			continue
		if int(far.get(c, 1 << 30)) < int(far.get(ai.dest, 1 << 30)):
			ai.dest = c
	return true


## The cost of U's cheapest walk from each cell to the nearest of `cells` by its move costs, other units ignored;
## with `around`, through no cell U keeps out of (but its own).
func _goal_distances(ai: BattleAI, cells: Array, around: bool) -> Dictionary:
	var u := ai.u
	var st := ai.st
	var far := {}
	var buckets := {0: []}
	for c in cells:
		if st.view.in_bounds(c) and Rules.move_cost(u, st.view.terrain_at(c)) < 255:
			far[c] = 0
			buckets[0].append(c)
	var level := 0
	while not buckets.is_empty():
		if not buckets.has(level):
			level += 1
			continue
		for c in buckets[level]:
			if int(far[c]) != level:
				continue
			var step := Rules.move_cost(u, st.view.terrain_at(c))
			for d in BattleAI.FDIRS:
				var n: Vector2i = c + d
				if not st.view.in_bounds(n) or Rules.move_cost(u, st.view.terrain_at(n)) >= 255:
					continue
				if around and n != u.pos and FlowGoals.avoids(u, n):
					continue
				if not far.has(n) or int(far[n]) > level + step:
					far[n] = level + step
					if not buckets.has(level + step):
						buckets[level + step] = []
					buckets[level + step].append(n)
		buckets.erase(level)
		level += 1
	return far


## Flow test started past the opening (WG_START > 0): the party lacks those that earlier files recruited. A run
## from scenario 0 recruits them itself, and a forced person who is not a member yet then is not one in the original
## either (R_08 forces 雄阔海, who joins only during S_08).
func recruit_forced(_pid: int) -> bool:
	return int(OS.get_environment("WG_START")) > 0 and OS.get_environment("WG_AUTOSAVE") != ""


# ------------------------------------------------------------------ story scenes
## WG_CLICKS=a,b,…: these actors first, in order, each as soon as its click would run a section (guided runs).
static var _guided: Array = Array(OS.get_environment("WG_CLICKS").split(",", false)).map(func(x: String) -> int: return int(x))


func story_pick(st: StoryStage, keys: Array) -> int:
	var trace := OS.get_environment("WG_TRACE_TEXT") != ""
	if not _guided.is_empty() and keys.has(_guided[0]) and await st._section_for(_guided[0]) >= 0:
		var g: int = _guided.pop_front()
		if trace:
			print("  [click] ", g, " (guided)")
		return g
	# a story 单挑 move is chosen by dry runs of the rounds (DuelSim)
	if DuelSim.enabled:
		var vm := st.vm
		var mv := DuelSim.move_sections(vm)
		var duel := keys.filter(func(k: int) -> bool: return mv.has(k) and DuelSim.section_for(vm, mv, k, {}) >= 0)
		if not duel.is_empty():
			var dp := DuelSim.best_move(vm, duel)
			if dp >= 0:
				if trace:
					print("  [click] ", dp, " (duel)")
				return dp
	# a click puzzle whose answer is a set of story flags (R_14's verses) is solved by dry runs
	if FlagPuzzle.enabled:
		var pz := FlagPuzzle.best_click(st.vm, keys, st._ran_secs)
		if pz >= 0:
			if trace:
				print("  [click] ", pz, " (puzzle)")
			return pz
	return -1


func story_leave(st: StoryStage, idle: int, clicks: int) -> bool:
	if OS.get_environment("WG_AUTOSAVE") == "":
		return false
	if idle > 300:
		# a minute with nothing to click and no section to run, e.g. a jump start that lacks the previous file's
		# story flags (R_10 needs flag 755 from R_09) — end the file
		print("== flow-test: idle scene, leaving %s (missing flags from the previous file? see WG_SETFLAGS)" % st.vm.name)
		return true
	var cap := OS.get_environment("WG_CLICKCAP")
	if idle == 0 and clicks > (int(cap) if cap != "" else 2500):
		# random clicking is not solving this scene (puzzles, hubs) — end the file
		print("== flow-test: click cap, leaving %s; story flags set: %s" % [st.vm.name, st._flags_set()])
		return true
	return false
