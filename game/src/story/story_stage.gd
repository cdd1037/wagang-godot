class_name StoryStage
extends ScriptHost
## Story (R_xx) scene runner: 640x400 scene view at y=40 of the 640x480 screen,
## isometric actors, portraits, captions, and point-and-click interaction.

signal clicked_actor(pid: int)

const VIEW_Y := 40
const TOOLBAR := ["卖出", "买进", "装备", "出征"]
const TOOLBAR_FLAGS := [0xf3, 0xf2, 0xf1]

var root2d: Node2D
var bg: Sprite2D
var actor_layer: Node2D
var portrait_layer: Node2D
var actors: Dictionary = {}       # pid -> RpgActor
var portraits: Dictionary = {}    # pid -> Sprite2D
var interactive := false
var click_pid := -1
var in_click := false
var scene_kind := -1
var scene_image := -1
var _waiting_click := false
var _pending_click := -1        # an actor clicked while a section ran: the next poll sees it (as a delay's message pump does)
var sortie_enabled := false
var _bar_menu: Button
var _bar_tools: Array[Button] = []    # the town toolbar: 卖出 买进 装备 出征


func _ready() -> void:
	super._ready()
	root2d = Node2D.new()
	add_child(root2d)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.size = Vector2(640, 480)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root2d.add_child(black)
	bg = Sprite2D.new()
	bg.centered = false
	bg.position = Vector2(0, VIEW_Y)
	root2d.add_child(bg)
	# the scene view (640x400 at y=40) clips actors like the original blitter
	var clip := Control.new()
	clip.position = Vector2(0, VIEW_Y)
	clip.size = Vector2(640, 400)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root2d.add_child(clip)
	actor_layer = Node2D.new()
	actor_layer.position = Vector2(0, -VIEW_Y)
	clip.add_child(actor_layer)
	portrait_layer = Node2D.new()
	portrait_layer.z_index = 2000     # above the actors, whose z_index is their screen y
	root2d.add_child(portrait_layer)
	# the original's town toolbar sits outside the scene view; here: buttons in the top black bar,
	# shown while the scene waits for the player (same as right click / Esc)
	_bar_menu = _bar_button("菜单", Vector2(572, 8))
	_bar_menu.pressed.connect(func() -> void:
		if menu_ready():
			_system_menu())
	for i in TOOLBAR.size():
		var b := _bar_button(TOOLBAR[i], Vector2(504, 8))
		b.pressed.connect(_tool.bind(i))
		_bar_tools.append(b)


## The town's menu, toolbar and clicks on actors work while the scene waits for the player and GS+2 (op 0x08) is
## not 0 (0x426ba3, 0x429b81).
func menu_ready() -> bool:
	return _waiting_click and town_on()


func town_on() -> bool:
	return Mem.r16(Mem.GS + 2) != 0


func open_menu() -> void:
	if menu_ready():
		_system_menu()


func _bar_button(text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(60, 26)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Assets.font())
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", UIStyle.NAME_COLOR)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	var n := UIStyle.panel_box()
	n.set_content_margin_all(2)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = UIStyle.BG2
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.visible = false
	root2d.add_child(b)
	return b


func _process(_d: float) -> void:
	if _bar_menu == null:
		return
	var show := menu_ready() and not Game.autoplay and not Game.demo
	_bar_menu.visible = show
	var x := 504.0
	for i in _bar_tools.size():
		var b := _bar_tools[i]
		b.visible = show and tool_shown(i)
		if b.visible:
			b.position.x = x
			x -= 68
	# the toolbar's buttons reach under the meter (x 290..502): while they show, they sit at the bar's bottom
	# and the meter goes above them
	var tools := x < 504.0
	for b in [_bar_menu] + _bar_tools:
		b.position.y = 12 if tools else 8
		b.size.y = 24 if tools else 26
	if ui and ui.meter:
		ui.meter.position.y = 2 if tools else 25


## The town toolbar (0x419d22) is shown with 出征 (op 0x06); story flags 0xf3 / 0xf2 / 0xf1 move 卖出 / 买进 / 装备
## off it (0x419f22), and the others close up from the right.
func tool_shown(i: int) -> bool:
	return sortie_enabled and (i >= TOOLBAR_FLAGS.size() or not Mem.flag(TOOLBAR_FLAGS[i]))


## A toolbar button (0x41973c): 0 卖出 (dialog 329), 1 买进 (327), 2 装备 (328), 3 出征.
func _tool(i: int) -> void:
	if not menu_ready() or not tool_shown(i):
		return
	if i == 3:
		_menu_sortie()
		return
	_waiting_click = false
	match i:
		0:
			await ShopWindow.sell(ui)
		1:
			await ShopWindow.buy(ui)
		2:
			await EquipWindow.open(ui)
	_waiting_click = true


var _restore: Dictionary = {}


## Run a story script file until it finishes.
func run_file(file: String) -> void:
	vm = EexVM.new()
	vm.host = self
	vm.handlers = op_handlers()
	if not vm.load_script(file):
		return
	Mem.w32(Skills.MAP_NO, 0xffff)   # towns load their pictures through 0x426c6a, which marks "no battle map"
	if not _restore.is_empty():
		_apply_restore()
	_ran_secs.clear()
	ui.meter.visible = true      # resource 2 (op 0x3a kind 2), the status window's third pane
	var busy := 0
	while vm.active and is_inside_tree():
		var sc := vm.scene
		if _pending_click < 0 and busy >= 3 and Game.autoplay and OS.get_environment("WG_AUTOSAVE") != "":
			# flow-test: sections keep running without a pause for the player (R_16's 张千, who must be clicked the
			# moment he appears): click an actor whose click would run a section now
			_pending_click = await _live_click()
		if _pending_click >= 0:
			var cp := _pending_click
			_pending_click = -1
			click_pid = cp
			in_click = true
			Mem.w16(Mem.GS, Mem.r16(Mem.GS) | 0x20)
			var hit: bool = await vm.poll()
			if hit:
				_ran_secs["%d.%d" % [sc, vm.last_section]] = true
			Mem.w16(Mem.GS, Mem.r16(Mem.GS) & ~0x20)
			in_click = false
			click_pid = -1
			if hit:
				busy = 0
				continue
		var ran: bool = await vm.poll()
		if ran:
			_ran_secs["%d.%d" % [sc, vm.last_section]] = true
			busy += 1
		else:
			busy = 0
		if not vm.active:
			break
		if not ran:
			# Nothing qualifies: wait for the player to click an actor (event-loop scenes).
			var pid := await _wait_for_click()
			if pid == -2:
				continue
			click_pid = pid
			in_click = true
			Mem.w16(Mem.GS, Mem.r16(Mem.GS) | 0x20)
			sc = vm.scene
			if await vm.poll():
				_ran_secs["%d.%d" % [sc, vm.last_section]] = true
			Mem.w16(Mem.GS, Mem.r16(Mem.GS) & ~0x20)
			in_click = false
			click_pid = -1
	SoundMap.stop_loop()


var _auto_i := 0
var _auto_idle := 0
var _ran_secs := {}     # the sections of this file that have run ("scene.section"), for the autoplay clicks


func _wait_for_click() -> int:
	if Game.autoplay or Game.demo:
		if Game.demo:
			await get_tree().create_timer(1.0).timeout
		await get_tree().process_frame
		var keys := click_candidates()
		if keys.is_empty():
			_auto_idle += 1
			if Game.hooks.story_leave(self, _auto_idle, _auto_i):     # the flow-test harness's idle exit
				vm.active = false
			await get_tree().create_timer(0.2).timeout
			return -2
		_auto_idle = 0
		_auto_i += 1
		if Game.hooks.story_leave(self, 0, _auto_i):                  # its click cap
			vm.active = false
			return -2
		var sp := OS.get_environment("WG_SORTIE_P")
		if sortie_enabled and Rules.chance(int(sp) if sp != "" else 12):
			if await do_sortie():
				return -2
		return await auto_pick(keys)
	_waiting_click = true
	var r: int = await clicked_actor
	_waiting_click = false
	return r


## Actors a player could click now: visible, not hidden via action 18, and inside the scene view (scripts park
## actors off-screen, e.g. at (90, 90), instead of removing them).
func click_candidates() -> Array:
	var view := Rect2(0, VIEW_Y, 640, 400)
	return actors.keys().filter(func(k: int) -> bool:
		var a: RpgActor = actors[k]
		return a.visible and a.action != 18 and view.intersects(a.screen_rect().grow(-4)))


## The actor autoplay clicks among `keys` (click_candidates(), not empty); the UI bot (debug/ui_bot.gd) clicks
## the same one with the mouse.
func auto_pick(keys: Array) -> int:
	# the harness's picks: guided clicks (WG_CLICKS), story 单挑 (DuelSim), click puzzles (FlagPuzzle)
	var h: int = await Game.hooks.story_pick(self, keys)
	if h >= 0:
		return h
	# mostly click actors whose click runs a section that has not run yet, else actors that some section of
	# this scene tests for (like a player would)
	var fresh: Array = await _fresh_click_pids(keys) if Rules.chance(85) else []
	var hot := _clickable_pids().filter(func(x: int) -> bool: return keys.has(x))
	if not fresh.is_empty():
		keys = fresh
	elif not hot.is_empty() and Rules.chance(85):
		# a click that runs nothing now is wasted: prefer actors whose click runs a section ("click him while he
		# is there" mini-games such as R_16's 张千)
		var live := []
		for x in hot:
			if await _section_for(x) >= 0:
				live.append(x)
		keys = live if not live.is_empty() else hot
	var pid: int = keys[Rules.rand(keys.size())] if OS.get_environment("WG_RANDOM") != "" else keys[_auto_i % keys.size()]
	if OS.get_environment("WG_TRACE_TEXT") != "":
		print("  [click] ", pid)
	return pid


## Autoplay helper: a visible actor some section tests for whose click would run a section now, or −1.
func _live_click() -> int:
	var view := Rect2(0, VIEW_Y, 640, 400)
	for pid in _clickable_pids():
		if not actors.has(pid):
			continue
		var a: RpgActor = actors[pid]
		if a.visible and a.action != 18 and view.intersects(a.screen_rect().grow(-4)) and await _section_for(pid) >= 0:
			if OS.get_environment("WG_TRACE_TEXT") != "":
				print("  [click] ", pid, " (while sections run)")
			return pid
	return -1


## The story flags that are set, as "a-b,c,…" ranges (flow-test diagnostics).
func _flags_set() -> String:
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


## Autoplay helper: the actors among `keys` whose click would run (as vm.poll picks: the last section that
## qualifies) a section that has not run yet in this file. The moves of the story-scene 单挑 (sections 攻击 防御
## 绝招 回避, run round after round) never count as new.
const DUEL_MOVES := ["攻击", "防御", "绝招", "回避"]


func _fresh_click_pids(keys: Array) -> Array:
	var out := []
	var secs := vm.sections(vm.scene)
	for pid in keys:
		var k := await _section_for(pid)
		if k >= 0 and not _ran_secs.has("%d.%d" % [vm.scene, k]) and not str(secs[k].get("title", "")).strip_edges() in DUEL_MOVES:
			out.append(pid)
	return out


## Autoplay helper: the section a click on `pid` would run now (−1 none).
func _section_for(pid: int) -> int:
	var secs := vm.sections(vm.scene)
	click_pid = pid
	in_click = true
	Mem.w16(Mem.GS, Mem.r16(Mem.GS) | 0x20)
	var chosen := -1
	for k in secs.size():
		if await vm.check_conditions(secs[k]):
			chosen = k
	Mem.w16(Mem.GS, Mem.r16(Mem.GS) & ~0x20)
	in_click = false
	click_pid = -1
	return chosen


## Autoplay helper: person ids named by test_clicked conditions in the current scene.
func _clickable_pids() -> Array:
	var out := []
	for sec in vm.sections(vm.scene):
		for c in sec.get("conditions", []):
			if str(c.get("name", "")) == "test_clicked" and not c["args"].is_empty() and c["args"][0] is float:
				var v := int(c["args"][0])
				if not out.has(v):
					out.append(v)
	return out


## Touch: a press on an actor, not yet released ([pid, press counter]); the click happens on release, so a long
## press can open 武将情报 instead.
var _press := [-1, 0]


func _unhandled_input(ev: InputEvent) -> void:
	if not _waiting_click and vm and vm.running and ev is InputEventMouseButton and ev.pressed \
			and ev.button_index == MOUSE_BUTTON_LEFT and actor_at(ev.position) >= 0:
		# a click on an actor while a section runs (during its waits) counts for the next poll
		_pending_click = actor_at(ev.position)
		get_viewport().set_input_as_handled()
		return
	if not _waiting_click or not town_on():
		_press[0] = -1
		return
	if ev is InputEventMouseButton and Game.touch and ev.button_index == MOUSE_BUTTON_LEFT:
		var pid := actor_at(ev.position)
		if ev.pressed:
			_press = [pid, _press[1] + 1]
			if pid >= 0:
				get_viewport().set_input_as_handled()
				var g: int = _press[1]
				get_tree().create_timer(BattleView.LONG_PRESS).timeout.connect(func() -> void: _long_press(g))
		elif _press[0] >= 0:
			var was: int = _press[0]
			_press[0] = -1
			get_viewport().set_input_as_handled()
			if pid == was:
				clicked_actor.emit(pid)
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			var pid := actor_at(ev.position)
			if pid >= 0:
				get_viewport().set_input_as_handled()
				clicked_actor.emit(pid)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			var pid := actor_at(ev.position)
			if _info_ok(pid):
				await _show_info(pid)
			else:
				_system_menu()
	elif ev.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_system_menu()


## 0x429b81: a right click on an actor shows 武将情报 for its person (pid < 0xff), which outside battle opens for
## party members only (0x407060).
func _info_ok(pid: int) -> bool:
	return pid >= 0 and (pid & 0xfff) < 0xff and Game.is_member(pid & 0xfff)


func _show_info(pid: int) -> void:
	_waiting_click = false
	await InfoWindow.open_party(ui, pid & 0xfff)
	_waiting_click = true


func _long_press(g: int) -> void:
	if g != _press[1] or _press[0] < 0 or not _waiting_click or not _info_ok(_press[0]):
		return
	var pid: int = _press[0]
	_press[0] = -1             # its release is no tap
	await _show_info(pid)


func actor_at(p: Vector2) -> int:
	if p.y < VIEW_Y or p.y >= VIEW_Y + 400:
		return -1      # outside the scene view, where actors are clipped
	var best := -1
	var best_y := -INF
	for pid in actors:
		var a: RpgActor = actors[pid]
		if not a.visible or a.action == 18:
			continue
		var r := a.screen_rect().grow(-4)
		if r.has_point(p) and a.position.y > best_y:
			best = pid
			best_y = a.position.y
	return best


## The menu bar (0x474c59) as one list; outside battles 检索未执行部队, 结束回合, 胜利条件 and 战场缩小图 are greyed
## (0x4759bc), so they are left out. 装备, 买进 and 卖出 are on the toolbar.
const MENU := ["武将一览", "持有道具一览", "地形情报一览", "历史情报", "环境设定", "存储进度", "读取进度", "版本情报", "回到标题"]


func _system_menu() -> void:
	_waiting_click = false
	var i := await ui.menu.choose(MENU, Vector2(-1, -1), true)
	match MENU[i] if i >= 0 else "":
		"武将一览":
			await UnitListWindow.open(ui, null)
		"持有道具一览":
			await ItemListWindow.open(ui)
		"地形情报一览":
			await TerrainWindow.open(ui)
		"历史情报":
			await HistoryWindow.open(ui)
		"环境设定":
			await SettingsWindow.open(ui)
		"存储进度":
			await Game.main.save_menu()
		"读取进度":
			await Game.main.load_menu()
		"版本情报":
			await MsgBox.version(ui)
		"回到标题":
			Game.main.to_title()
	_waiting_click = true


func _menu_sortie() -> void:
	_waiting_click = false
	if await do_sortie():
		clicked_actor.emit(-2)
		return
	_waiting_click = true


# ------------------------------------------------------------------ dialog placement
func _dialog_top(pid: int) -> bool:
	if actors.has(pid):
		return (actors[pid] as RpgActor).position.y > 300
	return false


# ------------------------------------------------------------------ scene
## op 0x27 (0x413d13): mode 0 = CG (Giji 0..39), 1 = scene 114+, 2 = room 40+, 3 = battle map. The story actors stay
## (only op 0x2f, op 0x11, battle init and loading clear them, 0x426bd5). Every mode repaints the scene view
## (0x42c223 → 0x40bc37), which wipes the captions; the portraits and the caption position and band are reset only
## on entering mode 1 (0x433310 → 0x43327a).
func op_change_scene(ins: Dictionary) -> void:
	var mode := arg(ins, 0)
	var val := 0
	match mode:
		0: val = arg(ins, 1)
		1: val = arg(ins, 2)
		2: val = arg(ins, 3)
		3: val = arg(ins, 4)
	if val == 0xffff:
		val = 0
	if Mem.r32(0x55bfe4) == 1:
		val += 0x100
	scene_kind = mode
	scene_image = val
	Mem.w8(Addr.SCENE_MODE, mode)
	Mem.w16(0x4ac63d, val)
	ui.wipe_captions()
	var entry := val + ({0: 0, 1: 114, 2: 40}.get(mode, 0) as int)
	if mode == 3:
		bg.texture = null
		return
	bg.texture = Assets.tex("gfx/backgrounds/%03d.png" % entry)
	if mode == 1:
		_clear_portraits()
		ui.reset_caption_band()


func _clear_portraits() -> void:
	for pid in portraits:
		(portraits[pid] as Node).queue_free()
	portraits.clear()


func _clear_actors() -> void:
	for pid in actors:
		(actors[pid] as Node).queue_free()
	actors.clear()


func _sprite_for(pid: int) -> int:
	if pid >= 0 and pid < 1024:
		return Mem.r16(DataTransfer.PERSON_EXT_TABLE + pid * 2)
	return pid & 0x3ff


func op_actor_appear(ins: Dictionary) -> void:
	var pid := arg(ins, 0) & 0xfff
	if actors.has(pid):
		(actors[pid] as Node).queue_free()
	var a := RpgActor.new()
	actor_layer.add_child(a)
	a.setup(pid, _sprite_for(pid), arg(ins, 1), arg(ins, 2), arg(ins, 3), arg(ins, 4))
	actors[pid] = a


## op 0x31 in story mode removes the actor (0x428b22).
func op_actor_select(ins: Dictionary) -> void:
	var pid := arg(ins, 1) & 0xfff
	if actors.has(pid):
		(actors[pid] as Node).queue_free()
		actors.erase(pid)


## op 0x32 (0x4132d4): when the next instruction is another move it returns at once, so a run of moves
## walks in parallel; the last one yields until no actor is walking.
func op_actor_move(ins: Dictionary) -> void:
	var pid := arg(ins, 1) & 0xfff
	if actors.has(pid):
		var a: RpgActor = actors[pid]
		if vm and vm.next_op == 0x32:
			a.walk_to(arg(ins, 3), arg(ins, 4), arg(ins, 5), fast or Game.autoplay)
			return
		await a.walk_to(arg(ins, 3), arg(ins, 4), arg(ins, 5), fast or Game.autoplay)
	elif vm and vm.next_op == 0x32:
		return
	await _actors_idle()


## op 0x1e: the RPG driver resumes only once no actor is walking (0x4182a4).
func op_wait_frame(_ins: Dictionary) -> void:
	await get_tree().process_frame
	await _actors_idle()


func _actors_idle() -> void:
	while is_inside_tree() and not (vm and vm.abort):
		var busy := false
		for pid in actors:
			var a: Variant = actors[pid]
			if is_instance_valid(a) and (a as RpgActor).walking:
				busy = true
				break
		if not busy:
			return
		await get_tree().process_frame


## op 0x33 (0x428b87): set action and facing; 0xFFFF keeps the current one.
func op_actor_face(ins: Dictionary) -> void:
	var pid := arg(ins, 0) & 0xfff
	if actors.has(pid):
		var a: RpgActor = actors[pid]
		if arg(ins, 2) != 0xffff:
			a.dir = arg(ins, 2) & 3
		a.set_action(a.action if arg(ins, 1) == 0xffff else arg(ins, 1))


func op_actor_action(ins: Dictionary) -> void:
	var pid := arg(ins, 0) & 0xfff
	if actors.has(pid):
		(actors[pid] as RpgActor).set_action(arg(ins, 1))


func op_actor_state(_ins: Dictionary) -> void:
	pass


## op 0x2f (0x426c32): reset the actor list.
func op_op_2f(_ins: Dictionary) -> void:
	_clear_actors()


func op_test_clicked(ins: Dictionary) -> bool:
	return in_click and click_pid == (arg(ins, 0) & 0xfff)


## op 0x28: 1 = enable player interaction (town toolbar without 出征), 0 = disable.
func op_op_28(ins: Dictionary) -> void:
	interactive = arg(ins, 0) != 0
	sortie_enabled = false
	Mem.w8(0x55ac02, 0)


## op 0x06 (0x415b45): store sortie parameters; flag != 0 also enables the toolbar with 出征.
func op_battle_select_units(ins: Dictionary) -> void:
	super.op_battle_select_units(ins)
	if arg(ins, 0) != 0:
		interactive = true
		sortie_enabled = true
		Mem.w8(0x55ac02, 1)
	else:
		sortie_enabled = false


## Toolbar 出征 (0x41973c case 3): build the sortie; on success advance to the next scene and set
## the pending flag that the "出战" section tests with op 0x07.
func do_sortie() -> bool:
	if not await build_sortie():
		return false
	# toolbar 出征 (0x41973c case 3): sortie list built, toolbar hidden, pending flag set; the next
	# poll runs the scene's own test_pending section (出战), which leaves the scene / jumps scenario
	sortie_enabled = false
	Mem.w32(Addr.SORTIE_CHOSEN, 1)
	return true


## op 0x6a: GAME OVER (0x42c0a2): stop audio, show GHAI #7, back to the title.
func op_op_6a(_ins: Dictionary) -> void:
	Audio.stop_bgm()
	SoundMap.stop_loop()
	await Game.main.game_over()
	vm.abort = true
	vm.active = false


# ------------------------------------------------------------------ portraits (ops 0x29/0x2a/0x2b)
## op 0x29 (0x4331be): the person's classic 64×80 face (Nao.wa, 0x432ed9) at screen (x, y + 40), fading in over 15
## ticks (at once while the screen is black). Persons 0x400 and above are ignored.
func op_op_29(ins: Dictionary) -> void:
	if arg(ins, 0) >= 0x400:
		return
	var pid := arg(ins, 0) & 0xfff
	if portraits.has(pid):
		(portraits[pid] as Node).queue_free()
	var s := Sprite2D.new()
	s.centered = false
	var face := Game.resolved_face(pid)
	s.texture = Assets.tex("gfx/portraits/classic/%03d.png" % face) if face >= 0 else null
	s.position = Vector2(arg(ins, 1), arg(ins, 2) + VIEW_Y)
	portrait_layer.add_child(s)
	portraits[pid] = s
	if ui.fade_rect.color.a >= 1.0 or Game.autoplay:
		return
	s.modulate.a = 0
	var tw := create_tween()
	tw.tween_property(s, "modulate:a", 1.0, 0.75)
	await tw.finished


## op 0x2a (0x432af4): the portrait moves to (x, y + 40) at 4 px a tick along the longer axis.
func op_op_2a(ins: Dictionary) -> void:
	var pid := arg(ins, 0) & 0xfff
	if not portraits.has(pid):
		return
	var s: Sprite2D = portraits[pid]
	var to := Vector2(arg(ins, 1), arg(ins, 2) + VIEW_Y)
	var d := maxf(absf(to.x - s.position.x), absf(to.y - s.position.y))
	if Game.autoplay or d < 1:
		s.position = to
		return
	var tw := create_tween()
	tw.tween_property(s, "position", to, d / 4.0 * 0.05)
	await tw.finished


## op 0x2b (0x433070): the portrait fades out over 16 ticks and its slot is cleared.
func op_op_2b(ins: Dictionary) -> void:
	var pid := arg(ins, 0) & 0xfff
	if not portraits.has(pid):
		return
	var s: Sprite2D = portraits[pid]
	portraits.erase(pid)
	if not Game.autoplay:
		var tw := create_tween()
		tw.tween_property(s, "modulate:a", 0.0, 0.8)
		await tw.finished
	s.queue_free()


func on_field_written(field: int, id: int) -> void:
	# sprite (field 0) changed: refresh an on-screen actor
	if field == 0 and actors.has(id):
		(actors[id] as RpgActor).set_sprite(_sprite_for(id))


# ------------------------------------------------------------------ save / restore
func save_state() -> Dictionary:
	var acts := []
	for pid in actors:
		var a: RpgActor = actors[pid]
		acts.append([pid, a.sprite_id, a.gx, a.gy, a.dir, a.action])
	return {"kind": "story", "scene": vm.scene if vm else 0, "scene_kind": scene_kind, "scene_image": scene_image,
		"actors": acts, "bgm": Audio.current_track, "interactive": interactive, "sortie_enabled": sortie_enabled}


func restore_state(d: Dictionary) -> void:
	_restore = d


func _apply_restore() -> void:
	var d := _restore
	_restore = {}
	if d.get("kind", "") != "story":
		return
	vm.scene = int(d.get("scene", 0))
	var mode := int(d.get("scene_kind", -1))
	if mode >= 0 and mode != 3:
		scene_kind = mode
		scene_image = int(d.get("scene_image", 0))
		var entry := scene_image + ({0: 0, 1: 114, 2: 40}.get(mode, 0) as int)
		bg.texture = Assets.tex("gfx/backgrounds/%03d.png" % entry)
	for e in d.get("actors", []):
		var a := RpgActor.new()
		actor_layer.add_child(a)
		a.setup(int(e[0]), int(e[1]), int(e[2]), int(e[3]), int(e[4]), int(e[5]))
		actors[int(e[0])] = a
	interactive = bool(d.get("interactive", false))
	sortie_enabled = bool(d.get("sortie_enabled", false))
	if int(d.get("bgm", -1)) >= 0:
		Audio.play_bgm(int(d["bgm"]))
	ui.set_black(false)
