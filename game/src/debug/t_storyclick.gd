extends Node
## R_00 played by hand (run windowed): the opening advanced with ui_accept presses (WG_ACCEPT_SPAM), then mouse
## clicks on the training 单挑's buttons as a player makes them. The opening's captions must be gone by then (every
## scene change repaints the view, 0x40bc37). The script only lets 防御 start (flag 21: the teacher's "以守为攻"),
## so a click on 攻击 (actor 616) runs nothing and one on 防御 (617) runs its section. With OUT=dir it saves pictures
## of the opening's captions and of the 单挑 screen.
## WG_START=0 WG_NOVIDEO=1 WG_ACCEPT_SPAM=1 TEST=res://src/debug/t_storyclick.gd godot --path . res://src/debug/test_runner.tscn
## Prints "t_storyclick: PASS".

var _ok := true


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("t_storyclick: FAIL ", what)
		_ok = false


func run() -> void:
	var main: Node = load("res://src/main.tscn").instantiate()
	add_child(main)
	var ui: GameUI = main.ui
	var out := OS.get_environment("OUT")
	var st: StoryStage = null
	var caps := 0              # the most caption lines seen at once, and on a darkened strip
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 900000:
		await get_tree().create_timer(0.2).timeout
		var n := ui._caption_lines.size()
		if n > caps and ui._band and ui._band.color.a > 0.2:
			caps = n
			if n == 3 and out != "":
				await _shot("captions")
		st = main.get("stage") as StoryStage
		if st and st.actors.has(616) and st._waiting_click:
			break
	_check(caps >= 3, "the opening's captions build up on the darkened strip (%d)" % caps)
	_check(st != null and st.actors.has(616) and st._waiting_click, "the 单挑 waits for a click")
	if not _ok:
		print("t_storyclick: FAILED")
		return
	await get_tree().create_timer(1.0).timeout
	if out != "":
		await _shot("duel")
	_check(ui._caption_lines.is_empty() and ui._band.color.a == 0.0,
			"the opening's captions are gone (%d left)" % ui._caption_lines.size())
	print("  town_on %s" % st.town_on())
	Game.set_meta("bot_owns_input", true)      # no more ui_accept presses
	var ran := st._ran_secs.size()
	await _click(st, 616)
	_check(st._waiting_click and st._ran_secs.size() == ran, "攻击 runs nothing yet")
	await _click(st, 617)
	_check(not st._waiting_click or st._ran_secs.has("1.6"), "防御 runs its section")
	print("t_storyclick: PASS" if _ok else "t_storyclick: FAILED")


func _shot(name: String) -> void:
	DisplayServer.window_move_to_foreground()
	for k in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT").path_join(name + ".png"))


func _click(st: StoryStage, pid: int) -> void:
	var p := (st.actors[pid] as RpgActor).screen_rect().get_center()
	_check(st.actor_at(p) == pid, "actor %d is under its button" % pid)
	var sp := get_viewport().get_screen_transform() * p
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = sp
		ev.global_position = sp
		Input.parse_input_event(ev)
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
