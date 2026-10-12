class_name UiBot
extends Node
## Debug (WG_UIBOT=dir, started by main.gd): plays the game as a player does, through real input events only, with
## the game in its normal mode (none of autoplay's short-cuts): mouse clicks on dialogue boxes, menu rows, window
## buttons, story actors, the town toolbar and battle cells, the wheel on long lists, Esc for the battle's system
## menu, and Enter where something waits with nothing to click (captions, banners). It decides like autoplay: story
## clicks from StoryStage.auto_pick (DuelSim, FlagPuzzle), each player unit's move from the battle AI's decision
## (BattleAI.decide, with the bytes and the random state it touches put back), the first enabled menu row.
## It checks what autoplay skips:
## * every click reaches its handler: a dialogue box that waits advances, a menu row is chosen, a window's 确定 /
##   结束 / 取消 closes it, a story actor is clicked, a map cell is clicked (each within 3 s);
## * a new stage starts with no dialogue, menu, window or popup left over from the last one;
## * once per town (a story file with the toolbar): every window of the system menu and the toolbar opens and
##   closes, and a save to slot 1 and its load bring back the same scenario, gold and party (saves go to
##   user://uibot/, Game.save_dir, never the player's slots);
## * the game never sits WG_UIBOT_STALL seconds (default 90) with nothing changing and nothing to do.
## Each failure prints "UIBOT: FAIL …" (with a window, also a screenshot in dir). The run ends at WG_STOP, at a game
## over, or after WG_UIBOT_TIME seconds (default 3600), with "UIBOT: PASS" or "UIBOT: FAILED (n)".
## WG_UIBOT_GALLERY=n (with a window): also a picture of each window, menu, dialogue page and move range the bot is
## about to act on, up to n of each kind per scenario (the README's screenshots).
## Example: WG_UIBOT=../extract/uibot WG_STOP=3 WG_GOD=1 godot --path game   (tools/uitest.sh)

const TICK := 0.15
const SYS_MENU := ["武将一览", "持有道具一览", "地形情报一览", "历史情报", "环境设定", "版本情报"]
## Window buttons that close a window, in the order they are tried (环境设定's 取消 keeps the player's settings).
const CLOSE_KEYS := [["cancel", 0], ["ok", 0], "ok", ["end", 0], ["btn", 1], ["btn", 0]]

var dir := OS.get_environment("WG_UIBOT")
var fails := 0
var _failed := {}          # failure text → how often
var main: Node
var ui: GameUI
var _rng := RandomNumberGenerator.new()      # the bot's own choices (the sortie button), not the game's
var _start_ms := 0
var _still_ms := 0         # when the fingerprint last changed or the bot last acted
var _enter_ms := 0
var _fp := ""
var _busy := false
var _checks: Array = []    # [deadline_ms, Callable → bool, what]
var _want: Array = []      # menu rows to pick next (by label prefix), in order
var _tour: Array = []      # town tour steps left
var _toured := {}          # scenario → true once its town tour started
var _saved := {}           # the state saved by the tour, to compare after loading
var _plan := {}            # battle: the decision being carried out for one unit
var _skip_units := {}      # battle: unit slots whose command was cancelled this turn
var _turn := -1
var _clicks_here := 0      # story clicks in this scenario
var _shots := 0
var _gallery := int(OS.get_environment("WG_UIBOT_GALLERY"))
var _gallery_seen := {}    # "scenario|kind" → pictures taken
var _counts := {"dialog": 0, "chosen": 0, "actor": 0, "cell": 0}
var _stop := int(OS.get_environment("WG_STOP")) if OS.get_environment("WG_STOP") != "" else -1
var _done := false


func _ready() -> void:
	main = get_parent()
	ui = main.ui
	_rng.seed = int(OS.get_environment("WG_UIBOT_SEED")) if OS.get_environment("WG_UIBOT_SEED") != "" else 1
	_start_ms = Time.get_ticks_msec()
	_still_ms = _start_ms
	Game.set_meta("bot_owns_input", true)          # no WG_ACCEPT_SPAM presses
	if _shots_on():
		DirAccess.make_dir_recursive_absolute(dir)
	main.stage_starting.connect(_on_stage_starting)
	ui.dialog.advanced.connect(func() -> void: _counts["dialog"] += 1)
	ui.menu.chosen.connect(func(_i: int) -> void: _counts["chosen"] += 1)
	Game.delete_save(0)              # the tour's slot 1: only this run's save is loaded back
	print("UIBOT: start (saves in %s)" % Game.save_dir)
	_loop()


func _exit_tree() -> void:
	if _done:
		return
	_done = true
	if _stop >= 0 and Game.scenario < _stop:
		_fail("the run ended at scenario %d, before WG_STOP %d" % [Game.scenario, _stop])
	for what in _failed:
		if _failed[what] > 1:
			print("UIBOT: FAIL ×%d %s" % [_failed[what], what])
	print("UIBOT: %s; %.0f s, clicks taken: %s" % ["PASS" if fails == 0 else "FAILED (%d)" % fails,
			(_now() - _start_ms) / 1000.0, _counts])


func _shots_on() -> bool:
	return dir != "" and dir != "1" and DisplayServer.get_name() != "headless"


## A failure is printed once; repeats are counted (in the summary), and the run stops after 20 failures.
func _fail(what: String) -> void:
	fails += 1
	_failed[what] = int(_failed.get(what, 0)) + 1
	if fails == 20:
		print("UIBOT: FAIL 20 failures, stopping")
		get_tree().quit()
	if _failed[what] > 1:
		return
	print("UIBOT: FAIL %s [%s, %.0f s]" % [what, main.scenario_file(Game.scenario), (Time.get_ticks_msec() - _start_ms) / 1000.0])
	if _shots_on():
		_shots += 1
		var img := get_viewport().get_texture().get_image()
		if img:
			img.save_png(dir.path_join("fail_%02d.png" % _shots))


func _trace(s: String) -> void:
	if OS.get_environment("WG_TRACE_TEXT") != "":
		print("  [bot] ", s)


func _now() -> int:
	return Time.get_ticks_msec()


## Expect `cond` to hold within `secs`, else fail with `what`.
func _expect(cond: Callable, what: String, secs := 3.0) -> void:
	_checks.append([_now() + int(secs * 1000), cond, what])


func _run_checks() -> void:
	var left: Array = []
	for c in _checks:
		if c[1].call():
			continue
		if _now() > c[0]:
			_fail(c[2])
		else:
			left.append(c)
	_checks = left


# ------------------------------------------------------------------ main loop
func _loop() -> void:
	var limit := int(OS.get_environment("WG_UIBOT_TIME")) if OS.get_environment("WG_UIBOT_TIME") != "" else 3600
	var stall := int(OS.get_environment("WG_UIBOT_STALL")) if OS.get_environment("WG_UIBOT_STALL") != "" else 90
	while is_inside_tree():
		await get_tree().create_timer(TICK).timeout
		_run_checks()
		if _now() - _start_ms > limit * 1000:
			_fail("time limit of %d s" % limit)
			get_tree().quit()
			return
		var fp := _fingerprint()
		if fp != _fp:
			_fp = fp
			_still_ms = _now()
		if _busy:
			continue
		_busy = true
		var acted: bool = await _step()
		_busy = false
		if acted:
			_still_ms = _now()
		elif _now() - _still_ms > stall * 1000:
			_fail("stalled for %d s: %s" % [stall, _describe()])
			get_tree().quit()
			return


## What changes while the game moves on: the scenario, the scripts' progress, the UI on screen, the battle.
func _fingerprint() -> String:
	var s := "%d|%d|%s|%s|%s|%s" % [Game.scenario, EexVM.executed, ui.dialog.visible, ui.dialog._waiting,
			ui.menu.visible, _top_panel()]
	var st: Node = main.stage
	if st is BattleStage:
		var acted := 0
		for u in st.units:
			if u.active():
				acted += int(u.acted) + u.hp + u.pos.x * 7 + u.pos.y * 13
		s += "|%d|%d" % [st.turn, acted]
	return s


func _describe() -> String:
	var st: Node = main.stage
	var s := "%s; dialog %s, menu %s %s, window %s" % [main.scenario_file(Game.scenario), ui.dialog.visible,
			ui.menu.visible, ui.menu.items, _top_panel()]
	if st is StoryStage:
		s += ", story waits %s, town %s, actors %s" % [st._waiting_click, st.town_on(), st.click_candidates()]
	elif st is BattleStage:
		s += ", battle turn %d, input idle %s, waits for a cell %s, plan %s" % [st.turn, st.input.idle,
				st.input.waiting_cell, _plan.get("stage", "")]
	return s


func _step() -> bool:
	if ui.video.visible:
		await _click(Vector2(320, 240))
		return true
	var p := _top_panel()
	if p:
		if not p._hits.is_empty():
			await _gallery_shot("msg" if p is MsgBox else str(p.get_script().get_global_name()))
		return await _panel(p)
	if ui.menu.visible and ui.menu._active:
		await _gallery_shot("menu_" + (ui.menu.title if ui.menu.title != "" else ui.menu.items[0]))
		return await _choice(ui.menu)
	if ui.dialog.visible:
		if ui.dialog._waiting and not ui.dialog._typing:
			await _gallery_shot("dialog")
		return await _dialog()
	if ui._popup_box.visible:
		await _click(ui._popup_box.get_global_rect().get_center())
		return true
	var st: Node = main.stage
	if st is StoryStage and st._waiting_click:
		return await _story(st)
	if st is BattleStage and st.input and st.input.waiting_cell:
		return await _battle(st)
	# something waits with nothing to click (captions, banners, the reward screen): Enter now and then
	if _now() - _still_ms > 2500 and _now() - _enter_ms > 2500:
		_enter_ms = _now()
		await _key(KEY_ENTER)
	return false


# ------------------------------------------------------------------ input events
## A left (or right) click at `p` in the game's 640×480 view, with the pointer moved there first.
func _click(p: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var sp := get_viewport().get_screen_transform() * p
	var mv := InputEventMouseMotion.new()
	mv.position = sp
	mv.global_position = sp
	Input.parse_input_event(mv)
	await get_tree().process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = sp
		ev.global_position = sp
		Input.parse_input_event(ev)
		await get_tree().process_frame


func _wheel(p: Vector2, down: bool) -> void:
	var sp := get_viewport().get_screen_transform() * p
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	ev.position = sp
	ev.global_position = sp
	Input.parse_input_event(ev)
	await get_tree().process_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		Input.parse_input_event(k)
		for f in 2:
			await get_tree().process_frame


## The point of a control's local `p` in the view.
static func _in_view(c: CanvasItem, p: Vector2) -> Vector2:
	return c.get_global_transform_with_canvas() * p


# ------------------------------------------------------------------ dialogue, menus, windows
func _dialog() -> bool:
	var d := ui.dialog
	var at := _in_view(d, d._box.get_center())
	if d._typing:
		await _click(at)
		_expect(func() -> bool: return not d.visible or not d._typing, "a click shows the rest of a dialogue page", 0.6)
	elif d._waiting:
		# with 会话窗口不自动关闭 off a page also closes by itself after its hold: the check ends before that
		var rem := 99.0 if d._hold < 0 else d._hold - d._held
		if rem < 0.9:
			return false
		var n: int = _counts["dialog"]
		await _click(at)
		_expect(func() -> bool: return _counts["dialog"] > n, "a click on a dialogue box that waits closes the page (%s)" % d.speaker,
				minf(3.0, rem - 0.4))
	else:
		return false
	return true


## The row to pick: a wanted label, the save slot, the battle plan's command, else the first enabled row.
func _choose_index(m: ChoiceMenu) -> int:
	var items := m.items
	if not _want.is_empty():
		for i in items.size():
			if m._is_enabled(i) and items[i].begins_with(str(_want[0])):
				_want.pop_front()
				return i
	if m.title in ["存储进度", "读取进度"]:
		return 0                                  # slot 1, in the bot's own save folder
	if m.title == "再玩一次吗？":
		_fail("game over")
		get_tree().quit()
		return -1
	var st: Node = main.stage
	if st is BattleStage and not _plan.is_empty():
		var i := _battle_choice(st, m)
		if i >= -1:
			return i
	for i in items.size():
		if m._is_enabled(i):
			return i
	return -1


func _choice(m: ChoiceMenu) -> bool:
	var i := _choose_index(m)
	if not is_inside_tree():
		return false
	var n: int = _counts["chosen"]
	if i < 0:
		if not m.cancellable:
			return false
		await _click(Vector2(620, 460), MOUSE_BUTTON_RIGHT)
	else:
		var tries := 0
		while not m._visible(i) and tries < 200:
			await _wheel(_in_view(m, m._rect.get_center()), i > m._top)
			tries += 1
		await _click(_in_view(m, m._row_rect(i).get_center()))
	var what := m.items[i] if i >= 0 and i < m.items.size() else "cancel"
	_expect(func() -> bool: return _counts["chosen"] > n, "a click on the menu row %s picks it" % what)
	return true


func _top_panel() -> DlgPanel:
	for k in range(ui.get_child_count() - 1, -1, -1):
		var c := ui.get_child(k)
		if c is DlgPanel and not c._done and c.is_inside_tree() and c.visible:
			return c
	return null


func _panel(p: DlgPanel) -> bool:
	if p._hits.is_empty():
		return false                    # not drawn yet
	if p is SortieScreen:
		return await _sortie(p)
	if p is MsgBox:
		var text := "\n".join(p.lines)
		var want := int(p.buttons[0][1])
		if p.buttons.size() > 1 and not _want.is_empty() and str(_want[0]) in ["是", "否"]:
			want = 1 if str(_want.pop_front()) == "是" else 0
		return await _press(p, ["btn", want], "the message box \"%s\"" % text.substr(0, 20))
	for key in CLOSE_KEYS:
		if _hit_rect(p, key).size != Vector2.ZERO:
			return await _press(p, key, p.get_class() if p.get_script() == null else p.get_script().get_global_name())
	# no button known: a right click closes a window (DlgPanel)
	var closed := [false]
	p.closed.connect(func() -> void: closed[0] = true)
	var pid := p.get_instance_id()
	var name := str(p.get_script().get_global_name())
	await _click(Vector2(620, 470), MOUSE_BUTTON_RIGHT)
	_expect(func() -> bool: return closed[0] or not is_instance_id_valid(pid), "a right click closes the window %s" % name)
	return true


func _hit_rect(p: DlgPanel, key: Variant) -> Rect2:
	for h in p._hits:
		if typeof(h[1]) == typeof(key) and h[1] == key:
			return h[0]
	return Rect2()


## Click the button `key` of window `p` and expect the window to close.
func _press(p: DlgPanel, key: Variant, what: String) -> bool:
	var r := _hit_rect(p, key)
	if r.size == Vector2.ZERO:
		return false
	var closed := [false]
	p.closed.connect(func() -> void: closed[0] = true)
	var pid := p.get_instance_id()
	await _click(_in_view(p, r.get_center()))
	_expect(func() -> bool: return closed[0] or not is_instance_id_valid(pid), "%s closes on %s" % [what, str(key)])
	return true


## 选择武将: the candidates in order until the strip is full (autoplay takes the first M), then 决定.
func _sortie(p: SortieScreen) -> bool:
	if p.slots.size() < p.most:
		for ci in p.cands.size():
			if not p.slots.has(ci):
				for h in p._hits:
					if h[1] is Array and h[1][0] == "cand" and int(h[1][1]) == ci:
						var before := p.slots.size()
						var pid := p.get_instance_id()
						await _click(_in_view(p, h[0].get_center()))
						_expect(func() -> bool:
							var w := instance_from_id(pid) as SortieScreen
							return w == null or w.slots.size() > before, "a click on a sortie candidate adds it")
						return true
	return await _press(p, ["ok", 0], "选择武将")


# ------------------------------------------------------------------ story scenes
func _story(st: StoryStage) -> bool:
	if not _tour.is_empty() or (st.town_on() and st.menu_ready() and not _toured.has(Game.scenario) and st.sortie_enabled):
		if not _toured.has(Game.scenario):
			_toured[Game.scenario] = true
			_tour = _tour_steps(st)
			print("UIBOT: town tour in %s: %s" % [main.scenario_file(Game.scenario), _tour])
			await _gallery_shot("toolbar")
		if st.menu_ready():
			return await _tour_step(st)
	var keys := st.click_candidates()
	if keys.is_empty():
		return false
	await _gallery_shot("town" if st.town_on() else "story")
	# like autoplay, now and then the toolbar's 出征 (WG_SORTIE_P, default 12 %)
	var sp := OS.get_environment("WG_SORTIE_P")
	if st.sortie_enabled and st.menu_ready() and st.tool_shown(3) and _rng.randi_range(0, 99) < (int(sp) if sp != "" else 12):
		await _click(_in_view(st._bar_tools[3], st._bar_tools[3].size / 2))
		var sid := st.get_instance_id()
		_expect(func() -> bool:
			var s := instance_from_id(sid) as StoryStage
			return s == null or not s.menu_ready() or _top_panel() != null, "the toolbar's 出征 opens the sortie")
		return true
	_clicks_here += 1
	if _clicks_here > 3000:
		_fail("3000 story clicks without leaving %s" % main.scenario_file(Game.scenario))
		get_tree().quit()
		return false
	st._auto_i += 1
	var pid: int = await st.auto_pick(keys)
	if not st._waiting_click or not st.actors.has(pid):
		return true
	var p: Vector2 = (st.actors[pid] as RpgActor).screen_rect().grow(-4).get_center()
	if st.actor_at(p) != pid:
		# another actor drawn over this one's middle: any point of its rect that hits it
		var r: Rect2 = (st.actors[pid] as RpgActor).screen_rect().grow(-4)
		for fy in [0.25, 0.75, 0.5]:
			for fx in [0.5, 0.25, 0.75]:
				var q := r.position + r.size * Vector2(fx, fy)
				if st.actor_at(q) == pid:
					p = q
		if st.actor_at(p) != pid:
			return false
	var n: int = _counts["actor"]
	if not st.clicked_actor.is_connected(_on_actor):
		st.clicked_actor.connect(_on_actor)
	var sid := st.get_instance_id()
	await _click(p)
	_expect(func() -> bool: return _counts["actor"] > n or not is_instance_id_valid(sid), "a click on actor %d is taken" % pid)
	return true


func _on_actor(_pid: int) -> void:
	_counts["actor"] += 1


## The town tour: each window of the system menu and the toolbar, 武将情报 of a member, a save and its load.
func _tour_steps(st: StoryStage) -> Array:
	var steps: Array = []
	for w in SYS_MENU:
		steps.append(["menu", w])
	for i in 3:
		if st.tool_shown(i):
			steps.append(["tool", i])
	steps.append(["info"])
	steps.append(["save"])
	steps.append(["load"])
	steps.append(["compare"])
	return steps


func _tour_step(st: StoryStage) -> bool:
	var s: Array = _tour.pop_front()
	_trace("tour: %s" % [s])
	match s[0]:
		"menu", "save", "load":
			if s[0] == "load" and Game.save_info(0).is_empty():
				print("UIBOT: no save was written in %s (saving not allowed here), no load" % main.scenario_file(Game.scenario))
				_tour.erase(["compare"])
				return false
			var row: String = s[1] if s[0] == "menu" else ("存储进度" if s[0] == "save" else "读取进度")
			_want = [row]
			if s[0] == "save":
				_saved = _state()
			var at := _empty_point(st)
			await _click(at, MOUSE_BUTTON_RIGHT)
			_expect(func() -> bool: return ui.menu.visible or _top_panel() != null, "a right click on an empty spot of a town opens the system menu")
			if s[0] == "menu":
				var opened := [false]
				_expect(func() -> bool:
					opened[0] = opened[0] or _top_panel() != null
					return opened[0], "the system menu's %s opens its window" % row, 6.0)
		"tool":
			var b: Button = st._bar_tools[s[1]]
			await _click(_in_view(b, b.size / 2))
			_expect(func() -> bool: return _top_panel() != null, "the toolbar's %s opens its window" % b.text, 4.0)
		"info":
			for pid in st.click_candidates():
				if st._info_ok(pid):
					var r: Rect2 = (st.actors[pid] as RpgActor).screen_rect().grow(-4)
					if st.actor_at(r.get_center()) == pid:
						await _click(r.get_center(), MOUSE_BUTTON_RIGHT)
						_expect(func() -> bool: return _top_panel() is InfoWindow, "a right click on %s opens 武将情报" % Game.person(pid & 0xfff).name, 4.0)
						return true
			return await _tour_step(st) if not _tour.is_empty() else false
		"compare":
			var now := _state()
			if now != _saved:
				_fail("loading the tour's save brings back %s, saved %s" % [now, _saved])
			print("UIBOT: town tour done in %s" % main.scenario_file(Game.scenario))
			return false
	return true


func _state() -> Dictionary:
	return {"scenario": Game.scenario, "gold": Game.gold, "party": Game.party.duplicate()}


## A point of the scene view with no actor on it (where a right click opens the system menu).
func _empty_point(st: StoryStage) -> Vector2:
	for y in [380, 120, 250, 60, 420]:
		for x in [600, 40, 320, 500, 140]:
			var p := Vector2(x, y)
			if st.actor_at(p) < 0:
				return p
	return Vector2(620, 420)


func _on_stage_starting(n: int) -> void:
	_clicks_here = 0
	_plan = {}
	_skip_units = {}
	var left := []
	if ui.dialog.visible:
		left.append("a dialogue box (%s)" % ui.dialog.speaker)
	if ui.menu.visible:
		left.append("a menu %s" % ui.menu.items)
	if _top_panel():
		left.append("a window %s" % _top_panel().get_script().get_global_name())
	if ui._popup_box.visible:
		left.append("a popup \"%s\"" % ui._popup_label.text)
	if not ui._caption_lines.is_empty():
		left.append("%d caption lines" % ui._caption_lines.size())
	if not left.is_empty():
		_fail("%s starts with %s left over" % [main.scenario_file(n), ", ".join(left)])
	print("UIBOT: %s (%.0f s)" % [main.scenario_file(n), (_now() - _start_ms) / 1000.0])
	if _shots_on():
		_shot.call_deferred("start_%s" % main.scenario_file(n))


## WG_UIBOT_GALLERY: the whole screen (in the touch shell with its side buttons) as NNN_<scenario>_<kind>.png.
func _gallery_shot(kind: String) -> void:
	var k := "%d|%s" % [Game.scenario, kind]
	if _gallery <= 0 or not _shots_on() or int(_gallery_seen.get(k, 0)) >= _gallery:
		return
	_gallery_seen[k] = int(_gallery_seen.get(k, 0)) + 1
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	_shots += 1
	get_tree().root.get_texture().get_image().save_png(dir.path_join("%03d_%s_%s.png" % [_shots,
			main.scenario_file(Game.scenario), kind.validate_filename()]))


func _shot(tag: String) -> void:
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(dir.path_join("%s.png" % tag))


# ------------------------------------------------------------------ battles
## A map cell click: the map is scrolled to it first (as a player scrolls), then clicked.
func _click_cell(st: BattleStage, c: Vector2i, button := MOUSE_BUTTON_LEFT) -> void:
	await st.view.center_on(c, false)
	await get_tree().process_frame
	var n: int = _counts["cell"]
	if not st.view.cell_clicked.is_connected(_on_cell):
		st.view.cell_clicked.connect(_on_cell)
	var sid := st.get_instance_id()
	await _click(st.view.cell_center(c) - st.view.camera.position, button)
	_expect(func() -> bool: return _counts["cell"] > n or not is_instance_id_valid(sid), "a click on map cell %s is taken" % c)


func _on_cell(_c: Vector2i, _b: int) -> void:
	_counts["cell"] += 1


func _battle(st: BattleStage) -> bool:
	if st.turn != _turn:
		_turn = st.turn
		_skip_units = {}
	var inp: BattleInput = st.input
	if inp.idle:
		if not _plan.is_empty():
			# back at the top level: the planned unit has acted, or its command was cancelled
			var pu: BUnit = _plan["unit"]
			if not pu.acted:
				_skip_units[pu.slot] = true
			_plan = {}
		var units := inp._player_units().filter(func(u: BUnit) -> bool:
			return u.active() and not u.acted and not (u.status & (BUnit.ST_CONFUSION | BUnit.ST_LOST)) \
					and not _skip_units.has(u.slot))
		if units.is_empty():
			_want = ["结束回合", "是"]
			var sid := st.get_instance_id()
			await _key(KEY_ESCAPE)
			_expect(func() -> bool:
				var s := instance_from_id(sid) as BattleStage
				return ui.menu.visible or s == null or not s.input.idle, "Esc opens the battle's system menu")
			return true
		var u: BUnit = units[0]
		_plan = await _decide(st, u)
		_plan["stage"] = "move"
		_trace("turn %d: %s at %s → %s, strategy %d, target %s" % [st.turn, u.person.name, u.pos, _plan["dest"],
				_plan["strategy"], _plan["target"].person.name if _plan["target"] else "-"])
		await _click_cell(st, u.pos)
		return true
	match str(_plan.get("stage", "")):
		"move":
			var u: BUnit = _plan["unit"]
			var dest: Vector2i = _plan["dest"]
			if not st.actions.reachable(u).has(dest):
				dest = u.pos
			await _gallery_shot("move")
			_plan["stage"] = "menu"
			await _click_cell(st, dest)
		"target", "strat_target":
			var t: BUnit = _plan.get("target")
			var u: BUnit = _plan["unit"]
			var c := Vector2i(-1, -1)
			if _plan["stage"] == "target":
				var cells := st.actions.attack_cells(u, u.pos)
				if t and t.active() and cells.has(t.pos) and t.is_enemy_of(u):
					c = t.pos
				else:
					for x in cells:
						var o := st.unit_at(x)
						if o and o.active() and o.is_enemy_of(u):
							c = x
							break
			elif t and t.active():
				c = t.pos
			_plan["stage"] = "after"
			if c.x < 0:
				await _click_cell(st, u.pos, MOUSE_BUTTON_RIGHT)
			else:
				await _click_cell(st, c)
		_:
			# anything else that asks for a cell (再移动, a second 连续攻击 target): decline with a right click
			var u: BUnit = _plan.get("unit") if not _plan.is_empty() else null
			await _click_cell(st, u.pos if u else st.view.cursor_cell, MOUSE_BUTTON_RIGHT)
	return true


## The command menu, the strategy list and the cast's confirmation for the planned unit; −2 = not a battle menu.
func _battle_choice(_st: BattleStage, m: ChoiceMenu) -> int:
	var items := m.items
	if Array(items) == BattleInput.COMMANDS:
		_plan["menus"] = int(_plan.get("menus", 0)) + 1
		if _plan["menus"] > 3:
			_plan["stage"] = "after"          # its commands keep being cancelled: 待命
			return 6
		var s := int(_plan.get("strategy", -1))
		var t: BUnit = _plan.get("target")
		if s >= 0 and t and t.active() and m._is_enabled(3):
			_plan["stage"] = "strat_list"
			return 3
		if m._is_enabled(0):
			_plan["stage"] = "target"
			return 0
		_plan["stage"] = "after"
		return 6
	if m.title.begins_with("策略") and _plan.get("stage") == "strat_list":
		var name := str(Game.strategy(int(_plan["strategy"])).get("name", "?"))
		for i in items.size():
			if items[i].begins_with(name + "　") and m._is_enabled(i):
				_plan["stage"] = "strat_target"
				return i
		_plan["stage"] = "after"
		return -1
	if items.size() == 2 and items[0].begins_with("执行"):
		return 0
	return -2


## The battle AI's decision for player unit `u`, taken without leaving a trace: EV[10], the preferred target
## byte, the unit's target slot and AI code, the current unit and the random state are put back.
func _decide(st: BattleStage, u: BUnit) -> Dictionary:
	var ev10 := Mem.ev(10)
	var pref := Mem.r8(BattleActions.PREFERRED)
	var tslot := Mem.r8(u.addr + 8)
	var mode := u.mode
	var cu := st.current_unit
	var rs := Rules.rng.state
	if FlowGoals.enabled:
		st.ai.flow_goal = (await FlowGoals.compute(st)).get(u.slot, {})
	var ok := st.ai.decide(u)
	var plan := {"unit": u, "dest": st.ai.dest if ok and st.ai.dest.x >= 0 else u.pos,
			"strategy": st.ai.choice_strategy if ok else -1, "target": st.ai.choice_target if ok else null}
	st.ai.flow_goal = {}
	Mem.set_ev(10, ev10)
	Mem.w8(BattleActions.PREFERRED, pref)
	Mem.w8(u.addr + 8, tslot)
	u.mode = mode
	st.current_unit = cu
	Rules.rng.state = rs
	return plan
