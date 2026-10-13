extends Node
## Boot + top-level flow: title screen, scenario loop (R_xx story / S_xx battle files),
## save/load, game over and ending.

const SAVE_SLOTS := 10

## A scenario's stage is about to be built (after the old one is gone): the UI bot checks for leftovers here.
signal stage_starting(n: int)

var ui: GameUI
var stage: ScriptHost
var _title_bg: Sprite2D
var _abort_flow := false
var _flow_running := false
var _flow_gen := 0          # bumped to orphan a running scenario loop (load / title / retry)
var _pending_load: Dictionary = {}


func _enter_tree() -> void:
	Game.main = self


func _unhandled_key_input(ev: InputEvent) -> void:
	# Cmd+F / F11 / Alt+Enter toggles full screen
	if Game.shell:
		return
	if ev is InputEventKey and ev.pressed and (ev.keycode == KEY_F11 or (ev.keycode == KEY_F and ev.meta_pressed) or (ev.keycode == KEY_ENTER and ev.alt_pressed)):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()


func _process(_d: float) -> void:
	# hold Space / Ctrl (touch: the 快进 toggle) to fast-forward animations (like the original patch's Space fast-click)
	var fast := (Input.is_key_pressed(KEY_SPACE) or Game.skip_held()) and not ui.video.visible
	Engine.time_scale = 4.0 if fast else 1.0
	_autosave_watch()


func _notification(what: int) -> void:
	# iOS may kill a backgrounded app without notice: write the autosave on the way out (~5 s budget there).
	# get_tree().quit() (结束游戏, 否 after a game over) sends no close request, but the tree still exits.
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST,
			NOTIFICATION_EXIT_TREE]:
		_autosave_flush()


func _fit_window() -> void:
	if DisplayServer.get_name() == "headless" or Game.shell:
		return
	var w := get_window()
	if w.mode != Window.MODE_WINDOWED:
		return
	var usable := DisplayServer.screen_get_usable_rect(w.current_screen)
	var scale := 1.0
	for s in [3.0, 2.5, 2.0, 1.5, 1.0]:
		if 640 * s <= usable.size.x * 0.92 and 480 * s <= usable.size.y * 0.9:
			scale = s
			break
	var size := Vector2i(int(640 * scale), int(480 * scale))
	_set_window_size(size)
	w.position = usable.position + (usable.size - size) / 2


# The picture keeps the game's 4:3 shape, so a window resized by one edge only gets black bars and the picture
# does not grow. Once the user stops resizing, snap the window back to 4:3 around the dimension they changed.
var _settled_size := Vector2i.ZERO
var _snapping := false
var _snap_timer: Timer


func _set_window_size(size: Vector2i) -> void:
	_snapping = true
	get_window().size = size
	_settled_size = get_window().size
	_snapping = false


func _on_window_resized() -> void:
	if not _snapping:
		_snap_timer.start()    # restarted on every step of a drag; fires once it has stopped


func _snap_aspect() -> void:
	var w := get_window()
	if w.mode != Window.MODE_WINDOWED:
		return
	var s := w.size
	var target: Vector2i
	if absi(s.x - _settled_size.x) * 3 >= absi(s.y - _settled_size.y) * 4:
		target = Vector2i(s.x, roundi(s.x * 0.75))
	else:
		target = Vector2i(roundi(s.y * 4.0 / 3.0), s.y)
	var usable := DisplayServer.screen_get_usable_rect(w.current_screen)
	var fit := minf(1.0, minf(float(usable.size.x) / target.x, float(usable.size.y) / target.y))
	target = Vector2i(roundi(target.x * fit), roundi(target.y * fit))
	if target != s:
		_set_window_size(target)
		# keep the grown window on screen
		w.position = Vector2i(clampi(w.position.x, usable.position.x, maxi(usable.position.x, usable.end.x - target.x)),
				clampi(w.position.y, usable.position.y, maxi(usable.position.y, usable.end.y - target.y)))
	_settled_size = w.size


func _ready() -> void:
	_snap_timer = Timer.new()
	_snap_timer.one_shot = true
	_snap_timer.wait_time = 0.3
	_snap_timer.timeout.connect(_snap_aspect)
	add_child(_snap_timer)
	if not Game.shell:        # the touch shell lays out the window itself
		get_window().size_changed.connect(_on_window_resized)
	_fit_window.call_deferred()
	ui = GameUI.new()
	add_child(ui)
	_boot.call_deferred()


func _boot() -> void:
	if Game.hooks.boot(self):       # the harness started a run itself (WG_START, WG_LOADSLOT; debug/harness.gd)
		return
	if OS.get_environment("WG_NOVIDEO") == "":
		await ui.video.play("pre")
	to_title()


# ------------------------------------------------------------------ title
func to_title() -> void:
	stop_flow()
	if Game.hooks.title(self):      # a flow test retries from its autosave instead
		return
	_title_screen.call_deferred()


## Start the scenario loop at Game.scenario, its stage restored from `extra` (a save's stage state) when given.
func start_flow(extra: Dictionary = {}) -> void:
	_pending_load = extra
	_run_flow()


## Abandon the running scenario loop and its stage. The loop may be suspended inside the stage
## (often the very call chain that asked for this), so it is orphaned via _flow_gen instead of
## being waited for; anything of it that still resumes sees the stale generation and returns.
func stop_flow() -> void:
	_autosave_flush()      # 回到标题, game over, loading a slot: the last checkpoint is what 继续游戏 resumes
	_flow_gen += 1
	_abort_flow = true
	_flow_running = false
	if stage:
		if stage.vm:
			stage.vm.abort = true
			stage.vm.active = false
		stage.queue_free()
		stage = null
	SoundMap.stop_loop()


func _title_screen() -> void:
	await get_tree().process_frame
	_abort_flow = false
	# title loop 0x41bf67: the 环境设定 options from Niuniu.wa (0x4e20ff), then CD track 18 (0x4092e8)
	Settings.load_file()
	Audio.play_bgm(18)
	ui.clear_strips()
	ui.wipe_captions()
	ui.meter.visible = false
	if _title_bg == null:
		_title_bg = Sprite2D.new()
		_title_bg.centered = false
		_title_bg.position = Vector2(0, 40)
		add_child(_title_bg)
	# 0x42bd90: title picture 0, or 12 + Niuniu.wa[0] (13..15) once an ending has been recorded
	var nb := SpecialFuncs.read_niuniu()
	var v := nb[0]
	_title_bg.texture = Assets.tex("gfx/screens/%02d.png" % (12 + v if v >= 1 and v <= 3 else 0))
	_title_bg.visible = true
	_show_version()
	ui.set_black(false)
	while true:
		# dialog 193: 新游戏 读取进度 环境设定 结束游戏 (the port adds 继续游戏)
		var items: Array = ["新游戏", "读取进度", "环境设定"]
		if _autosave_enabled() and not Game.save_info(Game.AUTO_SLOT).is_empty():
			items.push_front("继续游戏")
		if not OS.has_feature("mobile"):
			items.append("结束游戏")      # phone apps don't quit themselves
		# the bottom row stays where the original's three-item menu ends, inside the title picture
		var i := await ui.menu.choose(items, Vector2(250, 330 - 24 * (items.size() - 3)), false, "", [], 140)
		match items[i]:
			"继续游戏":
				if await _load_slot(Game.AUTO_SLOT):
					return
			"环境设定":
				await SettingsWindow.open(ui)
			"新游戏":
				_title_bg.visible = false
				Game.new_game_state()
				Game.scenario = 0
				_run_flow()
				return
			"读取进度":
				if await load_menu():
					return
			_:
				get_tree().quit()
				return


## Build number in the title screen's corner (application/config/version, set by the release workflow), and how many
## mods are loaded.
func _show_version() -> void:
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	var parts: Array[String] = []
	if ver != "":
		parts.append("版本 " + ver)
	if not Assets.mods.is_empty():
		parts.append("模组 %d" % Assets.mods.size())
	if parts.is_empty() or _title_bg.has_node("Version"):
		return
	var l := UIStyle.label("  ".join(parts), 12, Color(1, 1, 1, 0.75))
	l.name = "Version"
	l.position = Vector2(436, 380)
	l.size = Vector2(200, 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_title_bg.add_child(l)


# ------------------------------------------------------------------ scenario loop
func scenario_file(n: int) -> String:
	return ("R_%02d" if n % 2 == 0 else "S_%02d") % (n / 2)


func _run_flow() -> void:
	if _flow_running:
		return
	_flow_running = true
	_abort_flow = false
	_flow_gen += 1
	var gen := _flow_gen
	while not _abort_flow:
		var n := Game.scenario
		var file := scenario_file(n)
		if not Assets.exists("scripts/%s.json" % file):
			if not Game.hooks.game_end():
				await ending()
			return
		# a new game, the next scenario or a loaded save: the start of this stage is a checkpoint
		_autosave_checkpoint(_pending_load, true)
		print("== scenario %d: %s" % [n, file])
		if Game.hooks.scenario_start(n):
			return
		ui.wipe_captions()        # a new stage paints its own view
		stage_starting.emit(n)
		if n % 2 == 0:
			stage = StoryStage.new()
		else:
			stage = BattleStage.new()
		stage.name = "Stage"
		add_child(stage)
		move_child(stage, 0)
		if not _pending_load.is_empty():
			stage.restore_state(_pending_load)
			_pending_load = {}
		var st := stage
		await st.run_file(file)
		if gen != _flow_gen:
			return
		if _abort_flow or stage == null:
			break
		stage.queue_free()
		stage = null
		Game.scenario = (Game.scenario + 1) & 0xff
		Game.hooks.scenario_end()
	if gen == _flow_gen:
		_flow_running = false


## Game over (0x42c0a2): GS+7 = 0, SE 40, GHAI #7 at (0, 40) fading in from black, 2.5 s, then "再玩一次吗？". The
## original exits either way (yes asks its launcher to start the game again); here yes goes to the title, no quits
## (on phones, which should not quit themselves, also the title).
func game_over() -> void:
	Game.hooks.game_over(Game.scenario)
	Mem.w8(Mem.GS + 7, 0)
	Audio.stop_bgm()
	Audio.se(40)
	ui.set_black(true)
	var s := Sprite2D.new()
	s.centered = false
	s.position = Vector2(0, 40)
	s.texture = Assets.tex("gfx/screens/07.png")
	s.z_index = 50
	ui.add_child(s)
	await ui.fade_from_black()
	if Game.instant:
		s.queue_free()
		to_title()
		return
	await get_tree().create_timer(2.5).timeout
	var again := await ui.menu.choose(["是", "否"], Vector2(-1, -1), false, "再玩一次吗？")
	s.queue_free()
	if again == 1 and not OS.has_feature("mobile"):
		get_tree().quit()
		return
	to_title()


func ending() -> void:
	# the game is finished: nothing to continue (a test run's ending leaves the player's autosave alone)
	_autosave = {}
	if _autosave_enabled():
		Game.delete_save(Game.AUTO_SLOT)
	await ui.video.play("end")
	to_title()


# ------------------------------------------------------------------ save / load
func _slot_labels() -> Array:
	var out := []
	for i in SAVE_SLOTS:
		var info := Game.save_info(i)
		if info.is_empty():
			out.append("%2d：——空——" % (i + 1))
		else:
			out.append("%2d：%s" % [i + 1, _slot_text(i)])
	return out


## What slot i holds, for its row and for the questions (an empty one is "未使用保存进度", 0x48b528).
func _slot_text(i: int) -> String:
	var info := Game.save_info(i)
	if info.is_empty():
		return "未使用保存进度"
	return "%s  %s" % [str(info.get("chapter_title", "")), str(info.get("time", "")).substr(0, 16)]


func save_menu() -> void:
	# 保存 (0x474c90 → mod 0x4d009f): refused while the scripts forbid saving (op 0x74 → u32 [0x4ce004] = 0)
	if Mem.r32(Addr.SAVE_ALLOWED) == 0:
		await ui.message("目前不可存盘。")
		return
	var i := await ui.menu.choose(_slot_labels(), Vector2(-1, -1), true, "存储进度")
	if i < 0:
		return
	# 0x41b16a: the 是/否 question (0x474b0f, caption 保存), then "保存完毕。" (0x41b4d9 → 0x474b78)
	if not await MsgBox.yes_no(ui, "进度No.%2d: %s，\n可以保存吗？" % [i + 1, _slot_text(i)], "保存"):
		return
	var extra := {}
	if stage and stage.has_method("save_state"):
		extra = stage.save_state()
	if Game.save_game(i, extra):
		await MsgBox.ok(ui, "保存完毕。", "瓦岗山异闻录")
	else:
		await ui.popup("进度保存失败。", 1.2)


func load_menu() -> bool:
	var i := await ui.menu.choose(_slot_labels(), Vector2(-1, -1), true, "读取进度")
	if i < 0 or Game.save_info(i).is_empty():
		return false
	# 0x41ad06: the 是/否 question (caption 读取) before the load
	if not await MsgBox.yes_no(ui, "进度No.%2d: %s，\n可以读取吗？" % [i + 1, _slot_text(i)], "读取"):
		return false
	return await _load_slot(i)


func _load_slot(i: int) -> bool:
	if Game.read_save(i) == null:
		await ui.popup("无法读取这个进度。", 1.2)
		return false
	stop_flow()
	var extra: Variant = Game.load_game(i)
	if extra == null:
		extra = {}
	if _title_bg:
		_title_bg.visible = false
	ui.clear_strips()           # the loaded stage puts up the save's texts (StoryStage._apply_restore)
	_pending_load = extra
	# start after the caller's chain (possibly inside the old stage) has unwound
	_run_flow.call_deferred()
	return true


# ------------------------------------------------------------------ autosave (继续游戏)
# A running script lives in await chains and cannot be saved, so the autosave holds the last checkpoint: a
# stage start, or the stage waiting at its top level (story click / player phase), where 存储进度 works too.
# It is taken in memory there and written when the app goes to the background or closes (plus once a minute).
const AUTOSAVE_EVERY_MS := 60000

var _autosave: Dictionary = {}         # capture_save() of the last checkpoint
var _autosave_dirty := false
var _autosave_written_ms := 0
var _was_menu_ready := false


## Flow tests and bots must not overwrite the player's autosave.
func _autosave_enabled() -> bool:
	return not Game.test_run


func _autosave_watch() -> void:
	var ready := stage != null and stage.menu_ready()
	if ready and not _was_menu_ready:
		_autosave_checkpoint(stage.save_state())
	_was_menu_ready = ready


func _autosave_checkpoint(extra: Dictionary, write_now := false) -> void:
	if not _autosave_enabled():
		return
	_autosave = Game.capture_save(extra)
	_autosave_dirty = true
	if write_now or Time.get_ticks_msec() - _autosave_written_ms >= AUTOSAVE_EVERY_MS:
		_autosave_flush()


func _autosave_flush() -> void:
	if not _autosave_dirty or _autosave.is_empty():
		return
	_autosave_dirty = false
	_autosave_written_ms = Time.get_ticks_msec()
	if not Game.write_capture(Game.AUTO_SLOT, _autosave):
		push_warning("autosave could not be written")
