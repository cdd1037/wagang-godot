class_name StoryAutoplay
extends RefCounted
## Autoplay in story scenes (Game.autoplay / Game.demo): which actor to click when the scene waits for the player.
## Mostly actors whose click runs a section that has not run yet in this file, else ones some section tests for,
## as a player would; the harness (Game.hooks.story_pick) may choose first. The UI bot clicks the same actors with
## the mouse.

## The moves of the story-scene 单挑 (sections run round after round): never counted as new.
const DUEL_MOVES := ["攻击", "防御", "绝招", "回避"]

var st: StoryStage
var clicks := 0             # autoplay clicks in this file
var idle := 0               # polls in a row with nothing to click


func _init(stage: StoryStage) -> void:
	st = stage


## The scene waits for a click: the actor to click, or −2 to poll again (nothing to click yet, a sortie, or the
## harness ended the file).
func next_click() -> int:
	if Game.demo:
		await st.get_tree().create_timer(1.0).timeout
	await st.get_tree().process_frame
	var keys := candidates()
	if keys.is_empty():
		idle += 1
		if Game.hooks.story_leave(st, idle, clicks):     # the flow-test harness's idle exit
			st.vm.active = false
		await st.get_tree().create_timer(0.2).timeout
		return -2
	idle = 0
	clicks += 1
	if Game.hooks.story_leave(st, 0, clicks):           # its click cap
		st.vm.active = false
		return -2
	var sp := OS.get_environment("WG_SORTIE_P")
	if st.sortie_enabled and Rules.chance(int(sp) if sp != "" else 12):
		if await st.do_sortie():
			return -2
	return await pick(keys)


## Actors a player could click now: visible, not hidden via action 18, and inside the scene view (scripts park
## actors off-screen, e.g. at (90, 90), instead of removing them).
func candidates() -> Array:
	var view := Rect2(0, StoryStage.VIEW_Y, 640, 400)
	return st.actors.keys().filter(func(k: int) -> bool:
		var a: RpgActor = st.actors[k]
		return a.visible and a.action != 18 and view.intersects(a.screen_rect().grow(-4)))


## The actor to click among `keys` (candidates(), not empty).
func pick(keys: Array) -> int:
	# the harness's picks: guided clicks (WG_CLICKS), story 单挑 (DuelSim), click puzzles (FlagPuzzle)
	var h: int = await Game.hooks.story_pick(st, keys)
	if h >= 0:
		return h
	# mostly click actors whose click runs a section that has not run yet, else actors that some section of
	# this scene tests for (like a player would)
	var unrun: Array = await fresh(keys) if Rules.chance(85) else []
	var hot := clickable().filter(func(x: int) -> bool: return keys.has(x))
	if not unrun.is_empty():
		keys = unrun
	elif not hot.is_empty() and Rules.chance(85):
		# a click that runs nothing now is wasted: prefer actors whose click runs a section ("click him while he
		# is there" mini-games such as R_16's 张千)
		var live := []
		for x in hot:
			if await section_for(x) >= 0:
				live.append(x)
		keys = live if not live.is_empty() else hot
	var pid: int = keys[Rules.rand(keys.size())] if OS.get_environment("WG_RANDOM") != "" else keys[clicks % keys.size()]
	if OS.get_environment("WG_TRACE_TEXT") != "":
		print("  [click] ", pid)
	return pid


## A visible actor some section tests for whose click would run a section now, or −1.
func live_click() -> int:
	var view := Rect2(0, StoryStage.VIEW_Y, 640, 400)
	for pid in clickable():
		if not st.actors.has(pid):
			continue
		var a: RpgActor = st.actors[pid]
		if a.visible and a.action != 18 and view.intersects(a.screen_rect().grow(-4)) and await section_for(pid) >= 0:
			if OS.get_environment("WG_TRACE_TEXT") != "":
				print("  [click] ", pid, " (while sections run)")
			return pid
	return -1


## The actors among `keys` whose click would run (as vm.poll picks: the last section that qualifies) a section that
## has not run yet in this file, 单挑 moves aside.
func fresh(keys: Array) -> Array:
	var out := []
	var vm := st.vm
	var secs := vm.sections(vm.scene)
	for pid in keys:
		var k := await section_for(pid)
		if k >= 0 and not st.ran_secs.has("%d.%d" % [vm.scene, k]) and not str(secs[k].get("title", "")).strip_edges() in DUEL_MOVES:
			out.append(pid)
	return out


## The section a click on `pid` would run now (−1 none): the conditions are tried as during a click.
func section_for(pid: int) -> int:
	var vm := st.vm
	var secs := vm.sections(vm.scene)
	st.click_pid = pid
	st.in_click = true
	Mem.w16(Mem.GS, Mem.r16(Mem.GS) | 0x20)
	var chosen := -1
	for k in secs.size():
		if await vm.check_conditions(secs[k]):
			chosen = k
	Mem.w16(Mem.GS, Mem.r16(Mem.GS) & ~0x20)
	st.in_click = false
	st.click_pid = -1
	return chosen


## Person ids named by test_clicked conditions in the current scene.
func clickable() -> Array:
	var out := []
	for sec in st.vm.sections(st.vm.scene):
		for c in sec.get("conditions", []):
			if str(c.get("name", "")) == "test_clicked" and not c["args"].is_empty() and c["args"][0] is float:
				var v := int(c["args"][0])
				if not out.has(v):
					out.append(v)
	return out


## The story flags that are set, as "a-b,c,…" ranges (flow-test diagnostics).
static func flags_set() -> String:
	var out := []
	var i := 0
	while i < 2048:
		if Mem.flag(i):
			var j := i
			while j + 1 < 2048 and Mem.flag(j + 1):
				j += 1
			out.append(str(i) if j == i else "%d-%d" % [i, j])
			i = j
		i += 1
	return ",".join(out)
