class_name TerrainWindow
extends DlgPanel
## 地形情报一览 (menu 40150 → dialog 335, init 0x46c53b, cells 0x46c7a0 / 0x46cc75 / 0x46cd90): the twelve terrains
## of the mod's table 0x4d5fbc, each with its picture, name and the element strategies castable there, against the
## 27 class families (header strings: mod table 0x558100). Tab 地形效果: the terrain effect (8 … 12, "--" where the
## family cannot enter); tab 消耗机动力: the move cost. The table is wider than the window and scrolls sideways.
## A header click sorts (地形 by terrain; the families high values first; again: reversed).

const TERRAINS := [0, 1, 2, 3, 4, 7, 8, 9, 10, 13, 16, 23]
## [element, icon (strategy +0x10)] in drawing order: 火 水 地 风.
const ELEMENTS := [[0, 0], [1, 1], [3, 3], [2, 2]]
const TABS := ["地形效果", "消耗机动力"]
const RH := 48.0
const HEAD := 22.0
const FIRST_W := 105.0
const COL_W := 36.0
## The value colours (palette 0x75, 0x3d, 0x5b, 0x26, 0x24 and 0x1e), lightened for the dark panel.
const C_8 := Color(0.78, 0.55, 0.92)
const C_9 := Color(0.5, 0.65, 1.0)
const C_10 := Color(0.45, 0.9, 0.45)
const C_11 := Color(1.0, 0.55, 0.25)
const C_12 := Color(1.0, 0.76, 0.35)
const C_NONE := Color(0.6, 0.6, 0.66)

var tab := 0
var rows: Array = [[], []]     # terrain order per tab (each list keeps its own sort)
var last: Array[int] = [0, 0]  # the first click on 地形 sorts descending (0x46cb68)
var top := 0
var left := 0.0
var _fam: Array = []
var _heads: Array[String] = []
var _area := Rect2()


static func open(ui: CanvasLayer) -> void:
	var w := TerrainWindow.new()
	w.dlu = Vector2(393, 253)
	w.dlu_scale = Vector2(1.6, 1.85)
	Audio.se(0)
	await DlgPanel.run(ui, w)


func _ready() -> void:
	super._ready()
	_fam = Assets.json("data/class_families.json")
	for i in 28:
		_heads.append(Mem.str_at(0x558100 + 5 * i, 5))
	rows = [TERRAINS.duplicate(), TERRAINS.duplicate()]


func _cost(f: int, t: int) -> int:
	var v: Variant = (_fam[f]["move_cost"] as Array)[t]
	return 0xff if v == null else int(v)


## 0x46cc12 / 0x46cd5e.
func _value(f: int, t: int) -> int:
	if tab == 0:
		return 0 if _cost(f, t) == 0xff else int((_fam[f]["terrain_effect"] as Array)[t])
	return _cost(f, t)


func _cell(f: int, t: int) -> Array:
	var v := _value(f, t)
	if tab == 0:
		if v <= 0:
			return ["--", C_NONE]
		if v <= 8:
			return ["8", C_8]
		if v >= 12:
			return ["12", C_12]
		return [str(v), [C_9, C_10, C_11][v - 9]]
	if v == 0xff:
		return ["--", C_NONE]
	return [str(v), {1: C_9, 2: C_10, 3: C_11}.get(v, C_NONE)]


func _table_w() -> float:
	return FIRST_W + COL_W * 27


func _draw_dialog() -> void:
	var body := tabs(r(4, 2, 387, 233), TABS, tab)
	_area = body.grow(-4)
	draw_rect(_area, Color(0, 0, 0.05, 0.35))
	var sbh := 16.0
	var inner := Rect2(_area.position, _area.size - Vector2(16, sbh))
	var page := maxi(int((inner.size.y - HEAD) / RH), 1)
	top = clampi(top, 0, maxi(rows[tab].size() - page, 0))
	left = clampf(left, 0, maxf(_table_w() - inner.size.x, 0))
	var f := Assets.font()
	var x0 := inner.position.x - left
	# header
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, HEAD)), Color(0.16, 0.24, 0.46, 0.9))
	for c in 28:
		var cx := x0 + (0.0 if c == 0 else FIRST_W + COL_W * (c - 1))
		var cw := FIRST_W if c == 0 else COL_W
		if cx + cw < inner.position.x or cx > inner.end.x:
			continue
		var hr := Rect2(cx, inner.position.y, cw, HEAD).intersection(Rect2(inner.position, Vector2(inner.size.x, HEAD)))
		if hovered(["head", c]):
			draw_rect(hr, HOVER)
		_clip_text(Rect2(cx + 3, inner.position.y, cw - 6, HEAD), _heads[c], HORIZONTAL_ALIGNMENT_LEFT if c == 0 else HORIZONTAL_ALIGNMENT_CENTER,
			CAPTION, SMALL_SIZE, inner)
		hit(hr, ["head", c])
	# rows
	for k in range(top, mini(top + page, rows[tab].size())):
		var t: int = rows[tab][k]
		var y := inner.position.y + HEAD + RH * (k - top)
		var rr := Rect2(inner.position.x, y, inner.size.x, RH)
		if k % 2 == 1:
			draw_rect(rr, Color(1, 1, 1, 0.04))
		if hovered(["row", k]):
			draw_rect(rr, HOVER)
		hit(rr, ["row", k])
		if x0 + FIRST_W > inner.position.x:
			var pic := Assets.tex("gfx/terrain/%02d.png" % t)
			var pr := Rect2(x0 + 1, y, 48, 48)
			if pic and pr.position.x >= inner.position.x:
				draw_texture_rect(pic, pr, false)
			_clip_text(Rect2(x0 + 53, y, FIRST_W - 58, 30), Mem.str_ptr(0x48bdb0, t), HORIZONTAL_ALIGNMENT_LEFT,
				UIStyle.TEXT_COLOR, TEXT_SIZE, inner)
			var ix := x0 + 50
			for e in ELEMENTS:
				if Rules.element_ok(int(e[0]), t):
					var ic := Assets.tex("gfx/icons/strategies/small/%03d.png" % int(e[1]))
					if ic and ix >= inner.position.x and ix + 16 <= inner.end.x:
						draw_texture_rect(ic, Rect2(ix, y + 32, 16, 16), false)
					ix += 17
		for fi in 27:
			var cx := x0 + FIRST_W + COL_W * fi
			if cx + COL_W < inner.position.x or cx > inner.end.x:
				continue
			var c := _cell(fi, t)
			_clip_text(Rect2(cx, y, COL_W, RH), str(c[0]), HORIZONTAL_ALIGNMENT_CENTER, c[1], TEXT_SIZE, inner, true)
	# scroll bars
	var vs := Rect2(inner.end.x, inner.position.y, 16, inner.size.y)
	button(Rect2(vs.position, Vector2(16, 24)), "▲", "up", top > 0, SMALL_SIZE)
	button(Rect2(vs.end - Vector2(16, 24), Vector2(16, 24)), "▼", "dn", top + page < rows[tab].size(), SMALL_SIZE)
	var hs := Rect2(inner.position.x, inner.end.y, inner.size.x, sbh)
	draw_rect(hs, Color(0, 0, 0, 0.35))
	button(Rect2(hs.position, Vector2(24, sbh)), "◀", "lt", left > 0, SMALL_SIZE)
	button(Rect2(hs.end - Vector2(24, sbh), Vector2(24, sbh)), "▶", "rt", left < _table_w() - inner.size.x, SMALL_SIZE)
	var track := Rect2(hs.position + Vector2(24, 0), hs.size - Vector2(48, 0))
	var tw := track.size.x * minf(inner.size.x / _table_w(), 1.0)
	var tx := track.position.x + (track.size.x - tw) * (left / maxf(_table_w() - inner.size.x, 1.0))
	draw_rect(Rect2(tx, track.position.y + 3, tw, sbh - 6), Color(0.6, 0.65, 0.8, 0.8))
	hit(Rect2(track.position, Vector2(tx - track.position.x, sbh)), "pglt")
	hit(Rect2(Vector2(tx + tw, track.position.y), Vector2(track.end.x - tx - tw, sbh)), "pgrt")
	button(r(345, 237, 44, 14), "确定", ["ok", 0])


## Text clipped to the table area (cells that are partly scrolled out are left out).
func _clip_text(rect: Rect2, s: String, align: int, c: Color, size: int, clip: Rect2, bold := false) -> void:
	if rect.position.x < clip.position.x - 1 or rect.end.x > clip.end.x + 1:
		return
	text(rect, s, align, c, size)
	if bold:
		text(Rect2(rect.position + Vector2(1, 0), rect.size), s, align, c, size)


func _on_hit(key: Variant) -> void:
	match key:
		"up":
			top -= 1
		"dn":
			top += 1
		"lt":
			left -= COL_W
		"rt":
			left += COL_W
		"pglt":
			left -= _area.size.x - 16
		"pgrt":
			left += _area.size.x - 16
	if key is Array:
		match key[0]:
			"ok":
				close()
			"tab":
				if int(key[1]) != tab:
					Audio.se(0)
					tab = int(key[1])
					top = 0
			"head":
				_sort(int(key[1]))


## 0x464e1f with the compare 0x46cb68.
func _sort(c: int) -> void:
	var reverse := c == last[tab]
	var dec := []
	var list: Array = rows[tab]
	for i in list.size():
		var t: int = list[i]
		var k := t if c == 0 else -_value(c - 1, t)
		dec.append([k * (-1 if reverse else 1), i, t])
	dec.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	rows[tab] = dec.map(func(d: Array) -> int: return d[2])
	last[tab] = -1 if reverse else c


func _on_wheel(d: int, _p: Vector2) -> void:
	top += d
	queue_redraw()


func _on_key(ev: InputEvent) -> bool:
	if ev.is_action_pressed("ui_left"):
		left -= COL_W
	elif ev.is_action_pressed("ui_right"):
		left += COL_W
	elif ev.is_action_pressed("ui_up"):
		top -= 1
	elif ev.is_action_pressed("ui_down"):
		top += 1
	elif ev.is_action_pressed("ui_accept"):
		close()
	else:
		return false
	return true
