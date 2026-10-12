class_name MerchantBox
extends Control
## The shops' merchant window (template 345, setup 0x46d749, paint 0x46d43a + mod 0x4d4606, entry 0x46d9a4):
## 456×120 at (16, 56), the speaker's 120×120 portrait, the mark.wa frame pieces 2 and 3, the speaker's name and up
## to three '\n'-separated lines. With it: the 确认 box (template 346, 是 / 否) and the count box 输入数值 (template
## 320, 0x46dc1c / 0x46dfa0), both centred below the window. A message waits for a mouse button.
## The speaker is a shop record's merchant (Shops.merchant).

signal done

const AT := Vector2(16, 56)
const SIZE := Vector2(456, 120)
const LINE_Y := [51, 71, 91]
const TEXT_X := 152.0          # text column 0x13 [G: 8 px a column]
const DLU := Vector2(1.5, 1.625)

var pid := 0
var lines: PackedStringArray = []
var mode := 0                 # 0 message, 1 是/否, 2 count
var _hits: Array = []
var _hover: Variant = null
var _result := 0
# count box
var item := -1
var buy := true
var maxn := 0
var n := 0
var _pressed := false         # a button went down on this window (the release of the click that opened it is not one)


## In a battle the plain boxes stand in for the merchant window (0x46d9a4: 0x40b922).
static func _plain() -> bool:
	return Mem.r8(Addr.SCENE_MODE) == 3


static func _make(ui: CanvasLayer, who: int, text: String) -> MerchantBox:
	var m := MerchantBox.new()
	m.pid = who
	m.set_text(text)
	ui.add_child(m)
	return m


## Mode 0 (0x46d4d7): the message, then any mouse button closes it.
static func say(ui: CanvasLayer, who: int, text: String) -> void:
	if Game.autoplay:
		return
	if _plain():
		await MsgBox.ok(ui, text)
		return
	var m := _make(ui, who, text)
	m.mode = 0
	await m.done
	m.queue_free()


## Modes 1 / 2: the message and the 确认 box; 是 (0x46dd05) waits 100 ms and plays SE 9 (buying) or 10 (selling).
static func ask(ui: CanvasLayer, who: int, text: String, selling: bool) -> bool:
	if Game.autoplay:
		return true
	if _plain():
		var ok := await MsgBox.yes_no(ui, text, "卖出" if selling else "买进")
		if ok:
			await ui.get_tree().create_timer(0.1).timeout
			Audio.se(10 if selling else 9)
		return ok
	var m := _make(ui, who, text)
	m.mode = 1
	await m.done
	var yes := m._result == 1
	var tree := m.get_tree()
	m.queue_free()
	if yes:
		await tree.create_timer(0.1).timeout
		Audio.se(10 if selling else 9)
	return yes


## 输入数值 (0x46dd57): how many of `id`, 1..maxn (buying stops at 99 in the warehouse). Returns 0 for 取消.
static func count(ui: CanvasLayer, who: int, id: int, most: int, buying: bool) -> int:
	var name := str(Game.item(id).get("name", "?"))
	if buying and Game.stack_count(id) >= 99:
		await say(ui, who, "仓库里还有很多%s。\n没有必要再买。" % name)
		return 0
	if Game.autoplay:
		return mini(1, most)
	var m := _make(ui, who, "")
	m.mode = 2
	m.item = id
	m.buy = buying
	m.maxn = most
	m._set_count(mini(most, 1))
	await m.done
	var r := m._result
	var tree := m.get_tree()
	m.queue_free()
	if r > 0 and not buying:
		await tree.create_timer(0.1).timeout
		Audio.se(10)
	return r


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_text(t: String) -> void:
	lines = t.split("\n")
	queue_redraw()


func _unit_price() -> int:
	return ItemCols.buy_price(item) if buy else ItemCols.sell_price(item, 0)


## 0x46e1ac: the count and the merchant's line for it.
func _set_count(v: int) -> void:
	n = clampi(v, 0, maxn)
	var name := str(Game.item(item).get("name", "?"))
	if n < 1:
		set_text(("%s一个%d。\n要买多少？" if buy else "%s一个%d。\n要卖多少？") % [name, _unit_price()])
	else:
		set_text(("%d个%s需要%d。\n要买进吗？" if buy else "%d个%s可卖%d。\n要卖掉吗？") % [n, name, n * _unit_price()])


## Typing a digit: the value is kept modulo 10^digits of the maximum, then brought down under it a leading
## digit at a time (0x46e1ac, e.g. max 45, "78" → 38).
func _type_digit(d: int) -> void:
	var digits := str(maxn).length()
	var p := int(pow(10, digits))
	var v := (n * 10 + d) % p
	while v > maxn:
		v -= p / 10
	_set_count(v)


func _box2() -> Rect2:
	var sz := (Vector2(140, 53) if mode == 2 else Vector2(122, 28)) * DLU
	return Rect2(Vector2((640 - sz.x) / 2, AT.y + SIZE.y + 8).floor(), sz)


func _draw() -> void:
	_hits.clear()
	var r := Rect2(AT, SIZE)
	UIStyle.draw_panel(self, r)
	var face := Game.person_face(pid)
	if face:
		draw_texture_rect(face, Rect2(AT, Vector2(120, 120)), false)
	for k in [[2, 136], [3, 448]]:
		var t := Assets.tex("gfx/ui/mark/%d.png" % k[0])
		if t:
			draw_texture(t, AT + Vector2(k[1], 29))
	var f := Assets.font()
	var p := Game.person(pid)
	_line(Vector2(TEXT_X, 31), InfoWindow.display_name(p), UIStyle.NAME_COLOR)
	for i in mini(lines.size(), 3):
		_line(Vector2(TEXT_X, LINE_Y[i]), lines[i], UIStyle.TEXT_COLOR)
	if mode == 1:
		var b := _box2()
		UIStyle.draw_dialog(self, b, Settings.skin())
		_button(Rect2(b.position + Vector2(7, 7) * DLU, Vector2(50, 14) * DLU), "是", 1)
		_button(Rect2(b.position + Vector2(64, 7) * DLU, Vector2(50, 14) * DLU), "否", 0)
	elif mode == 2:
		var b := _box2()
		UIStyle.draw_dialog(self, b, Settings.skin())
		var lab := ("买进数(%d - %d)∶" if buy else "卖出数(%d - %d)∶") % [mini(maxn, 1), maxn]
		UIStyle.draw_text(self, b.position + Vector2(11, 11) * DLU + Vector2(0, 14), lab, UIStyle.TEXT_COLOR, 14)
		var e := Rect2(b.position + Vector2(82, 7) * DLU, Vector2(29, 16) * DLU)
		draw_rect(e, Color(0, 0, 0.05, 0.7))
		draw_rect(e, UIStyle.BORDER_IN, false, 1.0)
		var s := "" if n < 1 else str(n)
		draw_string(f, Vector2(e.end.x - 4 - f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, e.position.y + e.size.y / 2 + 6), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIStyle.TEXT_COLOR)
		var sp := Rect2(b.position + Vector2(112, 7) * DLU, Vector2(14, 16) * DLU)
		_button(Rect2(sp.position, Vector2(sp.size.x, sp.size.y / 2)), "▲", "up")
		_button(Rect2(sp.position + Vector2(0, sp.size.y / 2), Vector2(sp.size.x, sp.size.y / 2)), "▼", "dn")
		_button(Rect2(b.position + Vector2(15, 32) * DLU, Vector2(50, 14) * DLU), "买进" if buy else "卖出", "ok", n >= 1)
		_button(Rect2(b.position + Vector2(73, 32) * DLU, Vector2(50, 14) * DLU), "取消", "cancel")


func _line(pos: Vector2, s: String, c: Color) -> void:
	UIStyle.draw_text(self, AT + pos + Vector2(0, 15), s, c, 16)


func _button(rect: Rect2, label: String, key: Variant, enabled := true) -> void:
	draw_rect(rect, Color(0.12, 0.18, 0.36, 0.9) if enabled else Color(0.1, 0.1, 0.16, 0.7))
	if enabled and _hover != null and typeof(_hover) == typeof(key) and _hover == key:
		draw_rect(rect, Color(1.0, 0.85, 0.4, 0.22))
	draw_rect(rect, UIStyle.BORDER_IN if enabled else Color(0.6, 0.6, 0.66), false, 1.0)
	var f := Assets.font()
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	UIStyle.draw_text(self, rect.position + Vector2((rect.size.x - w) / 2, rect.size.y / 2 + 5), label,
		UIStyle.TEXT_COLOR if enabled else Color(0.6, 0.6, 0.66), 14)
	if enabled:
		_hits.append([rect, key])


func _hit_at(p: Vector2) -> Variant:
	for h in _hits:
		if (h[0] as Rect2).has_point(p):
			return h[1]
	return null


func _finish(r: int) -> void:
	_result = r
	done.emit()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var k: Variant = _hit_at(ev.position)
		if typeof(k) != typeof(_hover) or k != _hover:
			_hover = k
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_pressed = true
	elif ev is InputEventMouseButton and not ev.pressed and ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if not _pressed:
			pass
		elif mode == 0:
			_finish(0)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			_finish(0)                     # a right click is 否 / 取消
		else:
			_on_hit(_hit_at(ev.position))
	accept_event()


func _on_hit(k: Variant) -> void:
	match k:
		1:
			_finish(1)
		0, "cancel":
			_finish(0)
		"ok":
			if n >= 1:
				_finish(n)
		"up":
			_set_count(n + 1 if n < maxn else n)
		"dn":
			_set_count(n - 1 if n > 0 else 0)


func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey or ev is InputEventAction or ev is InputEventJoypadButton):
		return
	get_viewport().set_input_as_handled()
	if not ev.is_pressed():
		return
	if mode == 0:
		if ev.is_action_pressed("ui_accept") or ev.is_action_pressed("ui_cancel"):
			_finish(0)
	elif ev.is_action_pressed("ui_cancel"):
		_finish(0)
	elif ev.is_action_pressed("ui_accept"):
		_on_hit(1 if mode == 1 else "ok")
	elif mode == 2:
		if ev.is_action_pressed("ui_up"):
			_on_hit("up")
		elif ev.is_action_pressed("ui_down"):
			_on_hit("dn")
		elif ev is InputEventKey and ev.unicode >= 48 and ev.unicode <= 57:
			_type_digit(ev.unicode - 48)
		elif ev is InputEventKey and ev.keycode == KEY_BACKSPACE:
			_set_count(n / 10)
	queue_redraw()
