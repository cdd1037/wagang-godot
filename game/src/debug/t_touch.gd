extends Node
## Touch controls (Game.touch): BattleView taps / drag-pans and ChoiceMenu taps / drag-scrolls, fed through the
## viewport like real (emulated-from-touch) mouse events. Prints "t_touch: PASS".

var _ok := true


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("t_touch: FAIL ", what)
		_ok = false


func _push(ev: InputEvent) -> void:
	get_viewport().push_input(ev, true)
	await get_tree().process_frame


func _button(p: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = p
	ev.global_position = p
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	await _push(ev)


func _motion(from: Vector2, to: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.global_position = to
	ev.relative = to - from
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	await _push(ev)


func _cancel() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	await _push(ev)


func run() -> void:
	Game.new_game_state()
	await _menu_tests()
	await _map_tests()
	Game.touch = false
	print("t_touch: PASS" if _ok else "t_touch: FAILED")


func _menu_tests() -> void:
	var m := ChoiceMenu.new()
	add_child(m)
	var res := [-2]                   # lambdas capture locals by value: share a reference instead
	var open := func(items: Array, can_cancel := true) -> void:
		res[0] = -2
		res[0] = await m.choose(items, Vector2(-1, -1), can_cancel)
	var long := []
	for i in 30:
		long.append("项目%d" % i)
	# desktop: a press picks at once
	Game.touch = false
	open.call(long)
	await get_tree().process_frame
	await _button(m._row_rect(1).get_center(), true)
	_check(res[0] == 1, "desktop press picks row 1 (got %d)" % res[0])
	await _button(m._row_rect(1).get_center(), false)
	Game.touch = true
	# a tap picks on release
	open.call(long)
	await get_tree().process_frame
	var p2 := m._row_rect(2).get_center()
	await _button(p2, true)
	_check(res[0] == -2, "touch press alone picks nothing")
	await _button(p2, false)
	_check(res[0] == 2, "touch tap picks row 2 (got %d)" % res[0])
	# dragging a long list up scrolls it and picks nothing
	open.call(long)
	await get_tree().process_frame
	var p := m._row_rect(5).get_center()
	await _button(p, true)
	var q := p
	for k in 15:
		await _motion(q, q + Vector2(0, -6))
		q += Vector2(0, -6)
	await _button(q, false)
	_check(res[0] == -2, "drag picks nothing (got %d)" % res[0])
	_check(m._top == 3, "drag of 90 px scrolls 3 rows (top %d)" % m._top)
	await _cancel()
	_check(res[0] == -1, "cancel after the drag")
	# a release whose press closed something else is ignored
	open.call(long)
	await get_tree().process_frame
	await _button(m._row_rect(4).get_center(), false)
	_check(res[0] == -2, "orphan release picks nothing")
	# short list: the finger slides onto another row, the release picks that one
	await _button(m._row_rect(0).get_center(), true)
	await _cancel()
	open.call(["甲", "乙", "丙", "丁"])
	await get_tree().process_frame
	var a := m._row_rect(0).get_center()
	var b := m._row_rect(2).get_center()
	await _button(a, true)
	await _motion(a, b)
	await _button(b, false)
	_check(res[0] == 2, "slide to row 2 on a short list (got %d)" % res[0])
	# a tap outside the box cancels a menu that can be cancelled …
	var outside := Vector2(4, 4)
	open.call(["甲", "乙", "丙", "丁"])
	await get_tree().process_frame
	_check(not m._rect.has_point(outside), "test point is outside the menu")
	await _button(outside, true)
	await _button(outside, false)
	_check(res[0] == -1, "tap outside cancels (got %d)" % res[0])
	# … but not one that can't (the title menu)
	open.call(["甲", "乙", "丙", "丁"], false)
	await get_tree().process_frame
	await _button(outside, true)
	await _button(outside, false)
	_check(res[0] == -2, "tap outside a menu that can't be cancelled does nothing (got %d)" % res[0])
	# a press on a row dragged out of the box picks nothing and cancels nothing
	var r1 := m._row_rect(1).get_center()
	await _button(r1, true)
	await _motion(r1, outside)
	await _button(outside, false)
	_check(res[0] == -2, "drag from a row to outside does nothing (got %d)" % res[0])
	await _button(r1, true)
	await _button(r1, false)
	_check(res[0] == 1, "then a tap picks row 1 (got %d)" % res[0])
	# picking a target: a tap outside the highlighted cells cancels (touch only), a right click always
	var bi := BattleInput.new(null)
	var cells: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3)]
	_check(bi._cancels([Vector2i(9, 9), MOUSE_BUTTON_LEFT], cells), "target pick: tap outside the range cancels")
	_check(not bi._cancels([Vector2i(4, 3), MOUSE_BUTTON_LEFT], cells), "target pick: tap inside does not")
	_check(bi._cancels([Vector2i(4, 3), MOUSE_BUTTON_RIGHT], cells), "target pick: right click cancels")
	Game.touch = false
	_check(not bi._cancels([Vector2i(9, 9), MOUSE_BUTTON_LEFT], cells), "target pick with a mouse: a click outside is ignored")
	Game.touch = true
	m.queue_free()
	await get_tree().process_frame


func _map_tests() -> void:
	var v := BattleView.new()
	add_child(v)
	var idx: Dictionary = Assets.json("gfx/maps/index.json")
	v.load_map(int(idx["maps"][0]["id"]))
	v.camera.position = Vector2.ZERO
	for k in 3:
		await get_tree().process_frame
	var clicks := []
	var hovers := []
	v.cell_clicked.connect(func(c: Vector2i, btn: int) -> void: clicks.append([c, btn]))
	v.cell_hovered.connect(func(c: Vector2i) -> void: hovers.append(c))
	# tap: hover + left click on release
	await _button(Vector2(100, 100), true)
	_check(clicks.is_empty(), "map press alone does not click")
	await _button(Vector2(100, 100), false)
	_check(clicks.size() == 1 and clicks[0] == [Vector2i(2, 2), MOUSE_BUTTON_LEFT], "tap clicks cell (2,2): %s" % [clicks])
	_check(hovers.size() >= 1 and hovers[-1] == Vector2i(2, 2), "tap shows the cell's info: %s" % [hovers])
	# drag: pans with the finger (slop included), no click
	clicks.clear()
	var p0 := Vector2(300, 300)
	await _button(p0, true)
	await _motion(p0, Vector2(288, 292))
	await _motion(Vector2(288, 292), Vector2(250, 260))
	await _button(Vector2(250, 260), false)
	_check(clicks.is_empty(), "drag does not click: %s" % [clicks])
	_check(v.camera.position.is_equal_approx(Vector2(50, 40)), "drag pans by the finger travel: %s" % v.camera.position)
	# orphan release, then right click (desktop testing) still cancels
	await _button(Vector2(100, 100), false)
	_check(clicks.is_empty(), "orphan release on the map is ignored")
	await _button(Vector2(100, 100), true, MOUSE_BUTTON_RIGHT)
	_check(clicks.size() == 1 and clicks[0][1] == MOUSE_BUTTON_RIGHT, "right click cancels: %s" % [clicks])
	# Esc (the shell's 返回) reaches the map as a right click
	clicks.clear()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	await _push(esc)
	_check(clicks.size() == 1 and clicks[0][1] == MOUSE_BUTTON_RIGHT, "Esc cancels: %s" % [clicks])
	await _scroll_stop_tests(v)
	await _popup_tap_test(v, clicks)
	v.queue_free()


## A drag or a cursor key that stops a camera scroll lets whoever awaits the scroll go on (the enemy phase
## following a unit): a killed Tween never emits `finished`, and the battle froze.
func _scroll_stop_tests(v: BattleView) -> void:
	var done := [false]
	var follow := func() -> void:
		await v.center_on(Vector2i(v.map_w - 1, v.map_h - 1))
		done[0] = true
	v.camera.position = Vector2.ZERO
	follow.call()
	_check(not done[0], "the follow scroll animates")
	await get_tree().process_frame
	var p0 := Vector2(300, 300)
	await _button(p0, true)
	await _motion(p0, Vector2(280, 280))
	await _button(Vector2(280, 280), false)
	for k in 3:
		await get_tree().process_frame
	_check(done[0], "a drag that stops the camera scroll lets its awaiter go on")
	done[0] = false
	v.camera.position = Vector2.ZERO
	follow.call()
	await get_tree().process_frame
	v.cursor_cell = Vector2i(1, 1)
	var up := InputEventKey.new()
	up.keycode = KEY_UP
	up.physical_keycode = KEY_UP
	up.pressed = true
	await _push(up)
	for k in 3:
		await get_tree().process_frame
	_check(done[0], "a cursor key that scrolls the camera lets the earlier scroll's awaiter go on")


## A tap that closes a message box is not also a tap on the map under it (with a mouse the map gets only the
## press, which nothing waits for then).
func _popup_tap_test(v: BattleView, clicks: Array) -> void:
	var ui := GameUI.new()
	add_child(ui)
	var gs := GDScript.new()      # stand-in for main.gd (the view asks Game.main.ui about click waits)
	gs.source_code = "extends Node\nvar ui\n"
	gs.reload()
	var m := Node.new()
	m.set_script(gs)
	m.set("ui", ui)
	add_child(m)
	var old_main = Game.main
	Game.main = m
	var shown := [true]
	var box := func() -> void:
		await ui.popup("不在范围之内。")
		shown[0] = false
	box.call()
	await get_tree().process_frame
	clicks.clear()
	await _button(Vector2(100, 100), true)
	await _button(Vector2(100, 100), false)
	for k in 3:
		await get_tree().process_frame
	_check(not shown[0], "the tap closes the message box")
	_check(clicks.is_empty(), "the tap that closed the message box is no tap on the map: %s" % [clicks])
	await _button(Vector2(100, 100), true)
	await _button(Vector2(100, 100), false)
	_check(clicks.size() == 1, "the next tap clicks the map: %s" % [clicks])
	Game.main = old_main
	m.queue_free()
	ui.queue_free()
