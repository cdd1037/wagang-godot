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
var skin := -1                        # 对话框花色 to draw with (-1: the setting)
var _hits: Array = []                 # [Rect2, key]
var _hover: Variant = null
var _done := false
var _lists: Array = []                # the ListViews drawn this frame (for the wheel)


## A report-style list view (SysListView32): a header, rows of cells and a selection. A row is
## {"cells": [String…], "icon": Texture2D (before the first cell, optional), "color": Color (optional),
## "colors": [Color…] per cell (optional), "data": anything}.
class ListView:
	extends RefCounted
	var columns: Array = []       # [header, width weight, alignment]: the widths share out the list's width
	var rows: Array = []
	var top := 0
	var sel := -1
	var page := 1                 # rows that fit (set when drawn)
	var rect := Rect2()
	var row_h := 0.0              # a row's height (set when drawn)
	var sortable := false         # header cells are hits [key, -100 - column]
	var header := true            # false: no header row

	func scroll(d: int) -> void:
		top = clampi(top + d, 0, maxi(rows.size() - page, 0))

	## Select row i and scroll it into view.
	func select(i: int) -> void:
		sel = clampi(i, -1, rows.size() - 1)
		if sel >= 0:
			if sel < top:
				top = sel
			elif sel >= top + page:
				top = sel - page + 1


## The list views' sort (0x464e1f): stable, by key.call(item) ascending, or descending when `reverse`.
static func sorted_by(items: Array, key: Callable, reverse := false) -> Array:
	var dec := []
	for i in items.size():
		dec.append([key.call(items[i]) * (-1 if reverse else 1), i, items[i]])
	dec.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return dec.map(func(d: Array) -> Variant: return d[2])


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
	_lists.clear()
	UIStyle.draw_dialog(self, Rect2(origin, dlu * dlu_scale).grow(6), skin if skin >= 0 else Settings.skin())
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


## One line of text vertically centred in rect. With `ellipsis` a string wider than rect ends in "…" (the list views'
## cells, DrawTextExA with DT_END_ELLIPSIS: 0x464d62 → 0x47130c, formats 0x8024 / 0x8025 / 0x8026).
func text(rect: Rect2, s: String, align := HORIZONTAL_ALIGNMENT_LEFT, color := UIStyle.TEXT_COLOR, size := TEXT_SIZE,
		ellipsis := false) -> void:
	var f := Assets.font()
	var p := Vector2(rect.position.x, _baseline(rect, size))
	var w := rect.size.x
	if ellipsis:
		s = clipped(s, w, size)
	if align == HORIZONTAL_ALIGNMENT_LEFT:
		w = maxf(w, f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	draw_string(f, p + Vector2(1, 1), s, align, w, size, UIStyle.SHADOW)
	draw_string(f, p, s, align, w, size, color)


## `s` as it fits in `w` pixels: whole, or cut with "…" at its end (DT_END_ELLIPSIS).
static func clipped(s: String, w: float, size: int) -> String:
	var f := Assets.font()
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= w:
		return s
	while s.length() > 0 and f.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > w:
		s = s.substr(0, s.length() - 1)
	return s + "…"


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


func button(rect: Rect2, label: String, key: Variant, enabled := true, size := TEXT_SIZE) -> void:
	draw_rect(rect, UIStyle.BUTTON if enabled else UIStyle.BUTTON_OFF)
	if enabled and hovered(key):
		draw_rect(rect, HOVER)
	draw_rect(rect, UIStyle.BORDER_IN if enabled else DIM, false, 1.0)
	text(rect, label, HORIZONTAL_ALIGNMENT_CENTER, UIStyle.TEXT_COLOR if enabled else DIM, size)
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
	draw_rect(rect, UIStyle.BUTTON_EDGE, false, 1.0)
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
			_on_hover(k)
			queue_redraw()
		if _press_at != null and (ev.position - _press_at).length() > 10:
			_drag_at = _press_at       # a drag, not a tap or a long press: it scrolls
			_drag_last = _press_at
			_press_at = null
		if _drag_at != null:
			_drag_d += ev.position - _drag_last
			_drag_last = ev.position
			_drag_d -= _on_drag(_drag_d, _drag_at)
			queue_redraw()
	elif ev is InputEventMouseButton and Game.touch and ev.button_index == MOUSE_BUTTON_LEFT:
		# touch: a tap acts on release; holding 0.5 s acts as a right click; a drag scrolls
		_drag_at = null
		_drag_d = Vector2.ZERO
		if ev.pressed:
			_press_at = ev.position
			_press_gen += 1
			var g := _press_gen
			var at: Vector2 = ev.position
			# a timer that calls back only while this panel exists (a tap that closes it frees it)
			get_tree().create_timer(GameUI.LONG_PRESS).timeout.connect(func() -> void: _long_press(g, at))
		elif _press_at != null:
			_press_at = null
			var k: Variant = _hit_at(ev.position)
			if k != null:
				_on_tap(k)
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			_right_click(_hit_at(ev.position))
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			var k: Variant = _hit_at(ev.position)
			if k != null:
				if not (ev.double_click and _on_double(k)):
					_on_hit(k)
				queue_redraw()
		elif ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_on_wheel(-1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1, ev.position)
	accept_event()


var _press_at: Variant = null         # touch: where the finger went down (null once it moved or acted)
var _press_gen := 0
var _drag_at: Variant = null          # touch: where a dragging finger went down (null: no drag)
var _drag_last := Vector2.ZERO
var _drag_d := Vector2.ZERO           # its travel not yet turned into scrolling


func _long_press(gen: int, at: Vector2) -> void:
	if gen != _press_gen or _press_at == null or _done:
		return
	_press_at = null
	await _on_right(_hit_at(at))
	queue_redraw()


## A right click on `key`: the window closes unless _on_right handles it (which may first open another window).
func _right_click(key: Variant) -> void:
	if not await _on_right(key) and not _holds():
		close()
	queue_redraw()


## True while an answer is being carried out (the original's short waits after 是 / 决定 pump messages, but no dialog
## keyboard turns Esc into 取消 then): Esc, 返回 and a right click do not close the window meanwhile.
var busy := false


func _holds() -> bool:
	return busy


## The pointer moved onto `key` (null: off every hit).
func _on_hover(_key: Variant) -> void:
	pass


## Touch: a tap on `key`; by default the same as a click.
func _on_tap(key: Variant) -> void:
	_on_hit(key)


## Touch: a finger that went down at `at` has moved `d` (px) not yet used; return the part used. A list under it
## scrolls a row per row height (finger down = earlier rows); windows that scroll otherwise override this.
func _on_drag(d: Vector2, at: Vector2) -> Vector2:
	for lv: ListView in _lists:
		if lv.rect.has_point(at) and lv.row_h > 0:
			var n := int(d.y / lv.row_h)
			lv.scroll(-n)
			return Vector2(d.x, n * lv.row_h)
	return d


func _on_wheel(d: int, p: Vector2) -> void:
	for lv in _lists:
		if (lv as ListView).rect.has_point(p):
			(lv as ListView).scroll(d)
			queue_redraw()


## A right click on `key` (null: none); return true when handled, else the window closes. A coroutine, as the
## overrides that open a detail window are, so that callers await one kind of function (see TestHooks).
func _on_right(_key: Variant) -> bool:
	if false:
		await get_tree().process_frame
	return false


## The second press of a double click on `key`; return true when handled, else it counts as a click.
func _on_double(_key: Variant) -> bool:
	return false


## Keys go to the window on top only (the menu or map underneath must not move).
func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey or ev is InputEventAction or ev is InputEventJoypadButton):
		return
	get_viewport().set_input_as_handled()
	if not ev.is_pressed():
		return
	if ev.is_action_pressed("ui_cancel"):
		if not _holds():
			close()
	elif _on_key(ev):
		queue_redraw()


# ------------------------------------------------------------------ list view and tab control
## Draw lv into rect with rows of rh pixels. Hits: [key, i] for row i, [key, -1] / [key, -2] for the scroll buttons
## (scroll them with ListView.scroll); the wheel scrolls the list under the pointer.
func list_view(rect: Rect2, lv: ListView, key: String, rh := 0.0, size := 13) -> void:
	if rh <= 0:
		rh = 11 * dlu_scale.y
	lv.rect = rect
	lv.row_h = rh
	_lists.append(lv)
	draw_rect(rect, UIStyle.SUNKEN)
	draw_rect(rect, UIStyle.SUNKEN_EDGE, false, 1.0)
	var hh := rh if lv.header else 0.0
	lv.page = maxi(int((rect.size.y - hh) / rh), 1)
	lv.top = clampi(lv.top, 0, maxi(lv.rows.size() - lv.page, 0))
	var sb := 16.0 if lv.rows.size() > lv.page else 0.0
	var head := Rect2(rect.position, Vector2(rect.size.x, hh))
	if lv.header:
		draw_rect(head, UIStyle.HEADER)
	var xs: Array[float] = []
	var x := rect.position.x
	var total := 0.0
	for c in lv.columns:
		total += float(c[1])
	var avail := rect.size.x - sb
	for c in lv.columns:
		xs.append(x)
		x += float(c[1]) * avail / maxf(total, 1.0)
	xs.append(rect.end.x - sb)
	for ci in lv.columns.size() if lv.header else 0:
		var c: Array = lv.columns[ci]
		var cr := Rect2(xs[ci] + 3, head.position.y, minf(xs[ci + 1], rect.end.x - sb) - xs[ci] - 6, rh)
		text(cr, str(c[0]), int(c[2]) if c.size() > 2 else HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE, true)
		if lv.sortable:
			var hr := Rect2(xs[ci], head.position.y, xs[ci + 1] - xs[ci], rh)
			if hovered([key, -100 - ci]):
				draw_rect(hr, HOVER)
			hit(hr, [key, -100 - ci])
		if ci > 0:
			draw_line(Vector2(xs[ci], head.position.y + 2), Vector2(xs[ci], head.end.y - 2), UIStyle.HEADER_RULE)
	for k in range(lv.top, mini(lv.top + lv.page, lv.rows.size())):
		var row: Dictionary = lv.rows[k]
		var rr := Rect2(rect.position.x, rect.position.y + hh + rh * (k - lv.top), rect.size.x - sb, rh)
		if k == lv.sel:
			draw_rect(rr, UIStyle.HILITE)
		if hovered([key, k]):
			draw_rect(rr, HOVER)
		var cells: Array = row.get("cells", [])
		var colors: Array = row.get("colors", [])
		var base: Color = row.get("color", UIStyle.TEXT_COLOR)
		for ci in mini(cells.size(), lv.columns.size()):
			var x0 := xs[ci] + 3
			if ci == 0 and row.get("icon") != null:
				icon(Rect2(Vector2(x0, rr.position.y + 1), Vector2(rh - 2, rh - 2)), row["icon"])
				x0 += rh
			var cr := Rect2(x0, rr.position.y, minf(xs[ci + 1], rr.end.x) - x0 - 3, rh)
			var col: Color = colors[ci] if ci < colors.size() and colors[ci] != null else base
			var al: int = int(lv.columns[ci][2]) if (lv.columns[ci] as Array).size() > 2 else HORIZONTAL_ALIGNMENT_LEFT
			text(cr, str(cells[ci]), al, col, size, true)
		hit(rr, [key, k])
	if sb > 0:
		button(Rect2(rect.end.x - sb, head.end.y, sb, rh * 2), "▲", [key, -1], lv.top > 0)
		button(Rect2(rect.end.x - sb, rect.end.y - rh * 2, sb, rh * 2), "▼", [key, -2], lv.top + lv.page < lv.rows.size())


## The column of a list view's header hit, or -1.
static func header_hit(key: Variant, name: String) -> int:
	if key is Array and (key as Array).size() == 2 and key[0] == name and int(key[1]) <= -100:
		return -100 - int(key[1])
	return -1


## Handle a list view's scroll-button hit; true when `key` was one.
func list_scroll_hit(key: Variant, lv: ListView, name: String) -> bool:
	if key is Array and (key as Array).size() == 2 and key[0] == name and int(key[1]) in [-1, -2]:
		lv.scroll(-1 if int(key[1]) == -1 else 1)
		return true
	return false


## A tab control (SysTabControl32): the labels along the top of rect; returns the page area under them.
## `icons`: a 16×16 picture before each label (0x472281 gives the item lists' and shops' two tabs the CmdIcon.dll
## sword and pouch). Hits: [key, i].
func tabs(rect: Rect2, labels: Array, cur: int, key := "tab", icons: Array = []) -> Rect2:
	var th := 13 * dlu_scale.y
	var body := Rect2(rect.position + Vector2(0, th), rect.size - Vector2(0, th))
	draw_rect(body, UIStyle.TAB_BODY)
	draw_rect(body, FRAME, false, 1.0)
	var f := Assets.font()
	var x := rect.position.x
	for i in labels.size():
		var ic: Texture2D = icons[i] if i < icons.size() else null
		var iw := 20.0 if ic else 0.0
		var tw := f.get_string_size(str(labels[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x + 20 + iw
		var tr := Rect2(x, rect.position.y + (0.0 if i == cur else 2.0), tw, th - (0.0 if i == cur else 2.0))
		draw_rect(tr, UIStyle.TAB_ON if i == cur else UIStyle.TAB_OFF)
		if i != cur and hovered([key, i]):
			draw_rect(tr, HOVER)
		draw_rect(tr, FRAME, false, 1.0)
		if ic:
			draw_texture_rect(ic, Rect2(tr.position + Vector2(8, (tr.size.y - 16) / 2), Vector2(16, 16)), false)
		var lr := Rect2(tr.position + Vector2(iw, 0), tr.size - Vector2(iw, 0))
		text(lr, str(labels[i]), HORIZONTAL_ALIGNMENT_CENTER, UIStyle.NAME_COLOR if i == cur else UIStyle.TEXT_COLOR)
		hit(tr, [key, i])
		x += tw
	return body
