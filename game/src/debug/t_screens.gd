extends Node
## Screens of the script-op audit (docs/eex.md): 开始作战 (op 0x5a), 胜利条件 (op 0x1a), the chapter title cards
## (op 0x67), the resource meter (op 0x3a kind 2). With OUT=dir it saves a picture of each mid-way (run it
## windowed). Prints "t_screens: PASS".

var _ok := true


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("t_screens: FAIL ", what)
		_ok = false


func _shot(name: String) -> void:
	var out := OS.get_environment("OUT")
	if out != "":
		DisplayServer.window_move_to_foreground()
	for k in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	if out != "":
		get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func run() -> void:
	Game.new_game_state()
	Game.autoplay = false
	var ui := GameUI.new()
	var gs := GDScript.new()      # stand-in for main.gd (ScriptHost reads Game.main.ui)
	gs.source_code = "extends Node\nvar ui\nvar stage\n"
	gs.reload()
	var m := Node.new()
	m.set_script(gs)
	var old_main = Game.main
	Game.main = m
	add_child(m)
	m.set("ui", ui)
	add_child(ui)
	var st := BattleStage.new()
	m.set("stage", st)
	add_child(st)
	await get_tree().process_frame

	# 开始作战: the map darkens, then the words
	st.hud.start_banner()
	await get_tree().create_timer(0.6).timeout
	_check(not st.hud._seq.is_empty() and st.hud._seq["lines"].size() == 1, "开始作战 shown")
	await _shot("start_banner")
	await get_tree().create_timer(1.0).timeout
	_check(st.hud._seq.is_empty(), "开始作战 gone after 1 s")

	# 胜利条件: heading, the lines, the turn limit
	st.hud.goal_sequence("击退盛彦师！\n管毅不可败退", 30)
	await get_tree().create_timer(4.6).timeout
	_check(st.hud._seq["lines"].size() == 4, "heading, two lines and the turn limit (%d)" % st.hud._seq["lines"].size())
	await _shot("goal_sequence")
	await get_tree().create_timer(2.5).timeout

	# chapter 0: the part name card first
	ui.chapter_title(0, "群雄并起")
	await get_tree().create_timer(1.0).timeout
	await _shot("chapter_part")
	await get_tree().create_timer(3.2).timeout
	await _shot("chapter_title")
	await get_tree().create_timer(5.5).timeout

	# the resource meter in a town (story) scene
	Mem.w8(Mem.GS + 0x12, 40)
	ui.meter.visible = true
	await _shot("meter")
	ui.meter.visible = false

	# a battle field: the command menu's icons (0x45bd05) and an attack's forecast in the hover panel (0x4404bd)
	await st.op_change_scene({"args": [3, 0xffff, 0xffff, 0xffff, 0]})
	var clear := 0
	for k in 600:      # the title cards (the chapter's two, the battle's part name): until none for a second
		clear = clear + 1 if ui._title_root.get_child_count() == 0 else 0
		if clear >= 20:
			break
		await get_tree().create_timer(0.05).timeout
	ui.fade_rect.color.a = 0.0         # the script's fade_in would lift the black
	st.hud._seq = {}                   # the 胜利条件 screen above waits for a click
	for u in st.units:
		u.clear(u.slot)
	var a: BUnit = st.units[0]
	var e: BUnit = st.units[35]
	for x in [[a, 0, Vector2i(5, 5), 0], [e, 300, Vector2i(6, 5), 2]]:
		var u: BUnit = x[0]
		u.pid = x[1]
		u.pos = x[2]
		u.colour = x[3]
		u.mode = 7 if u == a else 1
		u.state = BUnit.STATE_ON_MAP
		u.hp = u.max_hp()
		u.mp = u.max_mp()
	st.refresh_units()
	st.field_ready = true
	st.turn = 1
	var sp := st.view.cell_pos(a.pos) - st.view.camera.position + Vector2(56, -10)
	ui.menu.choose(BattleInput.COMMANDS, sp, true, "", [true, false, false, true, false, true, true], 60, 0, Callable(),
			BattleInput.command_icons())
	await get_tree().create_timer(0.5).timeout
	await _shot("command_menu")
	_check(ui.menu.icons.size() == 7, "the command menu has its icons")
	ui.menu._finish(-1)
	st.input.show_forecast(1, a, -1, st.actions.attack_cells(a, a.pos))
	st.hud.set_hover(e.pos)
	_check(st.hud._forecast_on(e), "the enemy in reach gets the forecast")
	await _shot("forecast")
	st.input.show_forecast(0)

	Game.main = old_main
	print("t_screens: PASS" if _ok else "t_screens: FAILED")
