class_name InputBot
extends Node
## Debug: drives the player phase through real input events (mouse clicks / ui_accept) and saves
## screenshots, to exercise BattleInput exactly as a human would. Enabled with WG_INPUTBOT=dir.

var st: BattleStage
var shot_dir := ""
var shots := 0


func _init(stage: BattleStage, dir: String) -> void:
	st = stage
	shot_dir = dir


func shot(tag: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	shots += 1
	img.save_png("%s/%03d_%s.png" % [shot_dir, shots, tag])


func _click_cell(c: Vector2i, button := MOUSE_BUTTON_LEFT) -> void:
	await st.view.center_on(c, false)
	await get_tree().process_frame
	var vp := st.view.cell_center(c) - st.view.camera.position
	# synthetic events are in window coordinates: apply the viewport → window (stretch) transform
	var sp := get_viewport().get_screen_transform() * vp
	var mv := InputEventMouseMotion.new()
	mv.position = sp
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


func _key(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	for k in 4:
		await get_tree().process_frame
	ev = InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)
	await get_tree().process_frame


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func fx_test(ids: PackedStringArray) -> void:
	await _wait(0.6)
	var u := st.input._player_units()[0]
	for sid in ids:
		var s := int(sid)
		var target: BUnit = null
		for e in st.units:
			if e.active() and e.is_enemy_of(u):
				target = e
				break
		if target == null:
			return
		u.mp = 255
		var done := false
		var cast := func() -> void:
			await st.actions.cast(u, s, target.pos)
			done = true
		cast.call()
		for k in 6:
			await _wait(0.25)
			await shot("fx%d_%d" % [s, k])
		while not done:
			await _wait(0.3)
			await _key("ui_accept")
	st.get_tree().quit()


## WG_BOTMODE=load: open the system menu, pick 读取进度 and load slot WG_BOTSLOT (default 9),
## exercising an in-game load from inside the running battle.
func load_test() -> void:
	await _wait(0.6)
	await _click_cell(st.view.cursor_cell, MOUSE_BUTTON_RIGHT)
	await _wait(0.4)
	await shot("sysmenu")
	for k in 4:
		await _key("ui_down")
	await _key("ui_accept")
	await _wait(0.4)
	var slot := int(OS.get_environment("WG_BOTSLOT")) if OS.get_environment("WG_BOTSLOT") != "" else 9
	for k in slot:
		await _key("ui_down")
	await shot("loadmenu")
	print("== bot: loading slot %d" % slot)
	await _key("ui_accept")


func run_phase() -> void:
	var fx := OS.get_environment("WG_FXTEST")
	if fx != "":
		await fx_test(fx.split(","))
		return
	if OS.get_environment("WG_BOTMODE") == "load":
		await load_test()
		return
	await _wait(0.6)
	for u in st.input._player_units():
		if not u.active() or u.acted:
			continue
		await _click_cell(u.pos)
		await _wait(0.4)
		await shot("select_%s" % u.person.name)
		# choose destination: the reachable cell closest to the nearest enemy
		var reach := st.actions.reachable(u)
		var target: BUnit = null
		var bd := 1 << 30
		for e in st.units:
			if e.active() and e.is_enemy_of(u):
				var d := Grid.manhattan(e.pos, u.pos)
				if d < bd:
					bd = d
					target = e
		var dest := u.pos
		if target:
			var best := 1 << 30
			for c in reach:
				var d2 := Grid.manhattan(c, target.pos)
				if d2 >= 1 and d2 < best:
					best = d2
					dest = c
		await _click_cell(dest)
		await _wait(0.9)
		await shot("menu_%s" % u.person.name)
		# first enabled menu entry: 攻击 if possible, else 待命 (via ui_down skipping disabled ones)
		var can_attack := not st.actions.attackable_targets(u, u.pos).is_empty()
		if can_attack:
			await _key("ui_accept")
			await _wait(0.4)
			await shot("attackrange_%s" % u.person.name)
			var tg := st.actions.attackable_targets(u, u.pos)
			await _click_cell(tg[0].pos)
			await _wait(4.0)
			await shot("attacked_%s" % u.person.name)
		else:
			# menu starts on the first enabled item; move to 待命 (last)
			for k in 4:
				await _key("ui_down")
			await _key("ui_accept")
			await _wait(0.4)
	# end turn via system menu
	await _click_cell(st.units[0].pos if st.units[0].active() else Vector2i(0, 0), MOUSE_BUTTON_RIGHT)
	await _wait(0.5)
	await shot("sysmenu")
	await _key("ui_accept")
