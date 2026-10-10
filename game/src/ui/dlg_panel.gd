class_name DlgPanel
extends Control
## Base of the windows that follow one of the original's Win32 dialog templates (wagan.wa RT_DIALOG): control
## rects are given in dialog units (DLU) as in the template and scaled into the 640x480 screen, drawn in the
## port's panel style. Subclasses draw in `_draw_dialog()` and register clickable areas with `hit()`; a click on
## one calls `_on_hit(key)`. A right click, Esc or the touch 返回 closes the window (`close()`).

signal closed

const TEXT_SIZE := 14
const SMALL_SIZE := 12
const FRAME := Color(0.95, 0.85, 0.55, 0.75)
const CAPTION := UIStyle.NAME_COLOR
const DIM := Color(0.6, 0.6, 0.66)
const HOVER := Color(1.0, 0.85, 0.4, 0.22)
const BAR_BG := Color(0, 0, 0, 0.45)

## Bar styles of the original painter 0x46146f: [main Kao.wa tile, second tile (-1 none)]. 1 HP, 2/4 HP or MP with
## a status (poison / 穷计), 3 MP, 5 Exp, 6 a stat, 7 a lowered stat (red under), 8 a raised stat (cyan under).
const BAR_TILES := {1: [0x80, -1], 2: [0x140, -1], 3: [0x40, -1], 4: [0x140, -1], 5: [0x140, -1],
	6: [0xc0, -1], 7: [0xc0, 0x00], 8: [0xc0, 0x100]}

var dlu := Vector2(100, 100)          # the template's client size
var dlu_scale := Vector2(1.98, 1.8)   # pixels per dialog unit
var origin := Vector2.ZERO
var _hits: Array = []                 # [Rect2, key]
var _hover: Variant = null
var _done := false


static func run(ui: CanvasLayer, panel: DlgPanel) -> void:
	ui.add_child(panel)
	await panel.closed
	panel.queue_free()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var sz := dlu * dlu_scale
	origin = ((get_viewport_rect().size - sz) / 2).floor()


## A template rect (dialog units) in pixels.
func r(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(origin + Vector2(x, y) * dlu_scale, Vector2(w, h) * dlu_scale)


func close() -> void:
	if not _done:
		_done = true
		closed.emit()


func _draw() -> void:
	_hits.clear()
	UIStyle.draw_panel(self, Rect2(origin, dlu * dlu_scale).grow(6))
	_draw_dialog()


func _draw_dialog() -> void:
	pass


func _on_hit(_key: Variant) -> void:
	pass


## Keys other than Esc; return true when handled.
func _on_key(_ev: InputEvent) -> bool:
	return false


# ------------------------------------------------------------------ drawing helpers
func hit(rect: Rect2, key: Variant) -> void:
	_hits.append([rect, key])


func hovered(key: Variant) -> bool:
	return _hover != null and typeof(_hover) == typeof(key) and _hover == key


func _baseline(rect: Rect2, size: int) -> float:
	var f := Assets.font()
	return rect.position.y + (rect.size.y + f.get_ascent(size) - f.get_descent(size)) / 2.0


## One line of text vertically centred in rect.
func text(rect: Rect2, s: String, align := HORIZONTAL_ALIGNMENT_LEFT, color := UIStyle.TEXT_COLOR, size := TEXT_SIZE) -> void:
	var f := Assets.font()
	var p := Vector2(rect.position.x, _baseline(rect, size))
	var w := rect.size.x
	if align == HORIZONTAL_ALIGNMENT_LEFT:
		w = maxf(w, f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	draw_string(f, p + Vector2(1, 1), s, align, w, size, UIStyle.SHADOW)
	draw_string(f, p, s, align, w, size, color)


## Wrapped text from the top of rect; the font shrinks (down to 10 px) until it fits.
func paragraph(rect: Rect2, s: String, color := UIStyle.TEXT_COLOR, size := TEXT_SIZE) -> void:
	s = s.replace("\r\n", "\n").replace("\r", "\n").strip_edges()
	if s == "":
		return
	var f := Assets.font()
	var sz := size
	while sz > 10 and f.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, sz).y > rect.size.y:
		sz -= 1
	var lines := maxi(int(rect.size.y / f.get_height(sz)), 1)
	var p := rect.position + Vector2(0, f.get_ascent(sz))
	draw_multiline_string(f, p + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, sz, lines, UIStyle.SHADOW)
	draw_multiline_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, sz, lines, color)


## A group box (BS_GROUPBOX): a frame whose top line is broken by the caption.
func group(rect: Rect2, caption := "", caption_color := CAPTION) -> void:
	var f := Assets.font()
	var cw := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x if caption != "" else 0.0
	var top := rect.position.y + 4 * dlu_scale.y
	var l := rect.position.x
	var rr := rect.end.x
	var b := rect.end.y
	var cx0 := l + 8
	var cx1: float = cx0 + (cw + 6.0 if cw > 0 else 0.0)
	draw_line(Vector2(l, top), Vector2(cx0, top), FRAME)
	draw_line(Vector2(cx1, top), Vector2(rr, top), FRAME)
	draw_line(Vector2(l, top), Vector2(l, b), FRAME)
	draw_line(Vector2(rr, top), Vector2(rr, b), FRAME)
	draw_line(Vector2(l, b), Vector2(rr, b), FRAME)
	if caption != "":
		text(Rect2(cx0 + 3, rect.position.y, cw, 8 * dlu_scale.y), caption, HORIZONTAL_ALIGNMENT_LEFT, caption_color)


func button(rect: Rect2, label: String, key: Variant, enabled := true) -> void:
	draw_rect(rect, Color(0.12, 0.18, 0.36, 0.9) if enabled else Color(0.1, 0.1, 0.16, 0.7))
	if enabled and hovered(key):
		draw_rect(rect, HOVER)
	draw_rect(rect, UIStyle.BORDER_IN if enabled else DIM, false, 1.0)
	text(rect, label, HORIZONTAL_ALIGNMENT_CENTER, UIStyle.TEXT_COLOR if enabled else DIM)
	if enabled:
		hit(rect, key)


func icon(rect: Rect2, t: Texture2D) -> void:
	if t:
		var s := minf(rect.size.x, rect.size.y)
		draw_texture_rect(t, Rect2(rect.position + (rect.size - Vector2(s, s)) / 2, Vector2(s, s)), false)


## Bar painter 0x46146f. The second tile runs to v2/maxv, the main one to v/maxv (to v/v2 of the second's length
## when v2 ≠ 0). The text is "v/v2" ("v2/v" for style 8), "v" when v2 is 0, "MAX" for an Exp of 0xff (style 5).
func bar(rect: Rect2, v: int, v2: int, maxv: int, style: int, label := "") -> void:
	var tiles: Array = BAR_TILES.get(style, [0xc0, -1])
	draw_rect(rect, BAR_BG)
	var w := rect.size.x
	var sec_end := rect.end.x if maxv == 0 else rect.position.x + w * v2 / maxv
	var main_end: float
	if v2 == 0:
		main_end = rect.end.x if maxv == 0 else rect.position.x + w * v / maxv
	else:
		main_end = rect.position.x + (sec_end - rect.position.x) * v / v2
	sec_end = clampf(sec_end, rect.position.x, rect.end.x)
	main_end = clampf(main_end, rect.position.x, rect.end.x)
	if int(tiles[1]) >= 0:
		_tile(int(tiles[1]), Rect2(rect.position, Vector2(sec_end - rect.position.x, rect.size.y)))
	_tile(int(tiles[0]), Rect2(rect.position, Vector2(main_end - rect.position.x, rect.size.y)))
	draw_rect(rect, Color(0, 0, 0, 0.6), false, 1.0)
	if label == "":
		if style == 5 and v == 0xff:
			label = "MAX"
		elif style == 8:
			label = "%d/%d" % [v2, v]
		elif v2 != 0:
			label = "%d/%d" % [v, v2]
		else:
			label = "%d" % v
	text(Rect2(rect.position, rect.size - Vector2(3, 0)), label, HORIZONTAL_ALIGNMENT_RIGHT, UIStyle.TEXT_COLOR, SMALL_SIZE)


func _tile(off: int, rect: Rect2) -> void:
	if rect.size.x <= 0:
		return
	var t := Assets.tex("gfx/effects/kao/%05x_8x8.png" % off)
	if t:
		draw_texture_rect(t, rect, false)
	else:
		draw_rect(rect, Color(0.3, 0.5, 1.0))


# ------------------------------------------------------------------ input
func _hit_at(p: Vector2) -> Variant:
	for i in range(_hits.size() - 1, -1, -1):
		if (_hits[i][0] as Rect2).has_point(p):
			return _hits[i][1]
	return null


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var k: Variant = _hit_at(ev.position)
		if typeof(k) != typeof(_hover) or k != _hover:
			_hover = k
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			close()
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			var k: Variant = _hit_at(ev.position)
			if k != null:
				_on_hit(k)
				queue_redraw()
		elif ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_on_wheel(-1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1, ev.position)
	accept_event()


func _on_wheel(_d: int, _p: Vector2) -> void:
	pass


## Keys go to the window on top only (the menu or map underneath must not move).
func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey or ev is InputEventAction or ev is InputEventJoypadButton):
		return
	get_viewport().set_input_as_handled()
	if not ev.is_pressed():
		return
	if ev.is_action_pressed("ui_cancel"):
		close()
	elif _on_key(ev):
		queue_redraw()
