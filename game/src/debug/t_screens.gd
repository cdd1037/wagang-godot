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
	for k in 3:
		await get_tree().process_frame
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

	Game.main = old_main
	print("t_screens: PASS" if _ok else "t_screens: FAILED")
