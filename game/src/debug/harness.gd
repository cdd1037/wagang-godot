extends TestHooks
## The test harness and bots behind Game.hooks (core/test_hooks.gd): the flow-test harness (WG_AUTOSAVE: battle
## objectives FlowGoals, story 单挑 DuelSim, click puzzles FlagPuzzle, skips, caps and the god mode's field clear),
## the input bot (WG_INPUTBOT, WG_FXTEST), the UI bot (WG_UIBOT), WG_SAVETEST and the battle traces. Loaded by Game
## when this folder is in the build; everything here is switched on by environment variables (DEVELOPMENT.md).

## The flow goal of the player unit autoplay is playing (FlowGoals.compute), else empty. The UI bot sets it too.
var goal: Dictionary = {}
var _bot: InputBot
var _skip_battle := -1      # flow test: this battle goes straight to its aftermath (a third loss in a row)
var _lost := -1             # flow test: the scenario of the last game over (which zeroes GS+7)
var _retries := {}          # flow test: tries per scenario


# ------------------------------------------------------------------ the run (main.gd)
## Flow-test autosave slot (WG_AUTOSLOT, default 19) so parallel runs don't share one. Slots 0-9 are the player's
## saves: boot refuses them.
static func autoslot() -> int:
	var s := OS.get_environment("WG_AUTOSLOT")
	return int(s) if s != "" else 19


func boot(main: Node) -> bool:
	if OS.get_environment("WG_SEED") != "":
		Rules.rng.seed = int(OS.get_environment("WG_SEED"))     # the same rolls on every run (comparing two builds)
	var autosave := OS.get_environment("WG_AUTOSAVE") != ""
	if autosave and autoslot() < main.SAVE_SLOTS:
		printerr("WG_AUTOSLOT=%d is one of the player's save slots 0-%d: use 11 or higher" % [autoslot(), main.SAVE_SLOTS - 1])
		main.get_tree().quit(2)
		return true
	if OS.get_environment("WG_UIBOT") != "":
		main.add_child(UiBot.new())       # plays through real input events (debug/ui_bot.gd)
	if OS.get_environment("WG_ACCEPT_SPAM") != "":
		_accept_spam(main)
	if OS.get_environment("WG_SHOTS") != "":
		_shots(main)
	var ls := OS.get_environment("WG_LOADSLOT")
	if ls != "":
		var extra: Variant = Game.load_game(int(ls))
		print("== loaded slot %s at scenario %d" % [ls, Game.scenario])
		main.start_flow(extra if extra is Dictionary else {})
		return true
	var start := OS.get_environment("WG_START")
	if start == "":
		return false
	# WG_START=<scenario number> jumps straight into a scenario
	Game.new_game_state()
	Game.scenario = int(start)
	for x in OS.get_environment("WG_PARTY").split(",", false):
		Game.join_party(int(x), 1)
	for fl in OS.get_environment("WG_SETFLAGS").split(",", false):
		Mem.set_flag(int(fl), true)          # story flags an earlier branch would have set
	if Game.scenario % 2 == 1:
		# starting at a battle: no story scene built the sortie list (u32[] @0x48b350, 0xffff end)
		var ids := Game.party_ids()
		var n := mini(ids.size(), 12)
		for i in n:
			Mem.w32(Addr.SORTIE + 4 * i, ids[i])
		Mem.w32(Addr.SORTIE + 4 * n, 0xffff)
	if autosave:
		Game.save_game(autoslot(), {})
	main.start_flow()
	return true


## WG_ACCEPT_SPAM: ui_accept every 0.6 s (advances dialogue, like a player mashing Enter) until a bot owns the input.
func _accept_spam(main: Node) -> void:
	var t := Timer.new()
	t.wait_time = 0.6
	t.autostart = true
	t.timeout.connect(func() -> void:
		if Game.has_meta("bot_owns_input"):
			return
		for pressed in [true, false]:
			var ev := InputEventAction.new()
			ev.action = "ui_accept"
			ev.pressed = pressed
			Input.parse_input_event(ev)
			for k in 2:
				await main.get_tree().process_frame)
	main.add_child(t)


## WG_SHOTS=dir: a screenshot every WG_SHOT_EVERY seconds (default 3).
func _shots(main: Node) -> void:
	var t := Timer.new()
	t.wait_time = float(OS.get_environment("WG_SHOT_EVERY")) if OS.get_environment("WG_SHOT_EVERY") != "" else 3.0
	t.autostart = true
	var n := [0]
	t.timeout.connect(func() -> void:
		n[0] += 1
		main.get_viewport().get_texture().get_image().save_png("%s/%03d.png" % [OS.get_environment("WG_SHOTS"), n[0]]))
	main.add_child(t)


## Flow test: back at the title after a loss or an ending, retry from the last autosave instead.
func title(main: Node) -> bool:
	if Game.autoplay and OS.get_environment("WG_AUTOSAVE") != "" and not Game.save_info(autoslot()).is_empty():
		_retry.call_deferred(main)
		return true
	return false


func _retry(main: Node) -> void:
	# the scenario that just ended in game over (which zeroes it, GS+7) or an ending
	var failed := _lost if _lost >= 0 else Game.scenario
	_lost = -1
	var was_ending := Game.ending_reached
	Game.ending_reached = false
	if was_ending and failed >= 106:
		# the endgame (R_53 / R_54 hub) ends the game: the playthrough is complete
		print("== flow-test: reached an ending in %s" % main.scenario_file(failed))
		main.get_tree().quit()
		return
	main.stop_flow()
	await main.get_tree().process_frame
	var saved: Variant = Game.load_game(autoslot())
	var pending: Dictionary = saved if saved is Dictionary else {}
	var tries := int(_retries.get(failed, 0)) + 1
	_retries[failed] = tries
	# a battle random play keeps losing (scripted objective): jump to its aftermath on the next try
	if failed % 2 == 1 and tries >= 3:
		_skip_battle = failed            # cleared by the battle when it is used
	print("== retry from autosave at scenario %d (scenario %d failed, try %d)" % [Game.scenario, failed, tries])
	if failed % 2 == 0 and tries >= 30 and Game.scenario == failed:
		# a story scene random play keeps losing (chained 单挑 mini-games) — move on
		print("== flow-test: skipping story %s" % main.scenario_file(failed))
		pending = {}
		Game.scenario += 1
		Game.save_game(autoslot(), {})      # don't come back to it on the next retry
	main.start_flow(pending)


## WG_STOP=n: the run ends when scenario n starts.
func scenario_start(n: int) -> bool:
	var stop := OS.get_environment("WG_STOP")
	if stop != "" and n >= int(stop):
		Engine.get_main_loop().quit()
		return true
	return false


## Flow test (WG_AUTOSAVE): the autosave slot holds the start of each scenario.
func scenario_end() -> void:
	if OS.get_environment("WG_AUTOSAVE") != "":
		Game.save_game(autoslot(), {})


func game_end() -> bool:
	if Game.autoplay and OS.get_environment("WG_AUTOSAVE") != "":
		print("== flow-test: reached the end of the game")
		Engine.get_main_loop().quit()
		return true
	return false


func game_over(n: int) -> void:
	_lost = n


# ------------------------------------------------------------------ battles
func skip_battle(st: BattleStage) -> bool:
	if Game.autoplay and _skip_battle == Game.scenario:
		print("== flow-test: skipping battle %s" % st.vm.name)
		_skip_battle = -1
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
	if not _guided.is_empty() and keys.has(_guided[0]) and await st.autoplay.section_for(_guided[0]) >= 0:
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
		var pz := FlagPuzzle.best_click(st.vm, keys, st.ran_secs)
		if pz >= 0:
			if trace:
				print("  [click] ", pz, " (puzzle)")
			return pz
	return -1


## Flow test: R_16's 张千 has to be clicked the moment he appears, while sections keep running.
func story_busy(st: StoryStage) -> int:
	if Game.autoplay and OS.get_environment("WG_AUTOSAVE") != "":
		return await st.autoplay.live_click()
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
		print("== flow-test: click cap, leaving %s; story flags set: %s" % [st.vm.name, StoryAutoplay.flags_set()])
		return true
	return false
