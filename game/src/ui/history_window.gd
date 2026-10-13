class_name HistoryWindow
extends DlgPanel
## 历史情报 (menu command 40151 → mod 0x4d184c; dialog 341 with the text panel 347, paint 0x4d1385): the chronicle
## as plain scrolling text, one line per '\n'-separated line of each entry, coloured by category (1 chronicle,
## 2 items, 3 skills, 4 battles). 按顺序显示 (EV[4093], checked from R_00 on) lists the entries in the order they
## were written; unchecked it lists category 1, 2, 3, then 4, a blank line after each group. Entry numbers are
## hidden unless EV[4092] (never set). The original draws black / red / blue / magenta on the light skin pattern;
## here lighter shades on the dark panel.

const COLORS := {1: Color(1, 1, 1), 2: Color(1.0, 0.5, 0.45), 3: Color(0.55, 0.75, 1.0)}
const OTHER := Color(0.95, 0.55, 0.95)
const PANEL := Vector2(376, 374)
const LH := 16.0
const VISIBLE := 22                    # (374 − 8) / 16

var lines: Array = []                  # [text, category]
var top := 0


static func open(ui: CanvasLayer) -> void:
	if Game.history.is_empty():
		await MsgBox.ok(ui, "目前无记录")
		return
	if Settings.skin() >= 4:
		await MsgBox.ok(ui, "需要设置对话框花色")
		return
	var w := HistoryWindow.new()
	w.dlu_scale = Vector2.ONE
	w.dlu = Vector2(PANEL.x, PANEL.y + 34)
	await DlgPanel.run(ui, w)


func _ready() -> void:
	super._ready()
	_build()


## Line generation (0x4d1385 with the tokenizer 0x4d15bf).
func _build() -> void:
	lines.clear()
	var ordered := Mem.ev(4093) != 0
	var numbers := Mem.ev(4092) != 0
	for cat in ([0] if ordered else [1, 2, 3, 4]):
		for e: Dictionary in Game.history:
			if not ordered and int(e["cat"]) != cat:
				continue
			var t := str(e["text"])
			if numbers and int(e["id"]) >= 0:
				t = "%d%s" % [int(e["id"]), t]
			for l in t.split("\n"):
				lines.append([l, int(e["cat"])])
		lines.append(["", 0])
	lines.pop_back()                    # the last pass's blank line is not counted
	top = clampi(top, 0, maxi(lines.size() - VISIBLE, 0))


func _draw_dialog() -> void:
	var pr := r(0, 0, PANEL.x, PANEL.y)
	draw_rect(pr, Color(0, 0, 0.05, 0.3))
	var f := Assets.font()
	var tw := PANEL.x - 20
	for k in range(top, mini(top + VISIBLE, lines.size())):
		var l: Array = lines[k]
		var p := pr.position + Vector2(4, 4 + (k - top) * LH + f.get_ascent(14))
		var c: Color = COLORS.get(int(l[1]), OTHER)
		draw_string(f, p + Vector2(1, 1), str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, tw, 14, UIStyle.SHADOW)
		draw_string(f, p, str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, tw, 14, c)
	# the vertical scroll bar (page 23, range 0..total)
	var sb := Rect2(pr.end.x - 16, pr.position.y, 16, pr.size.y)
	draw_rect(sb, Color(0, 0, 0, 0.35))
	button(Rect2(sb.position, Vector2(16, 16)), "▲", "up", top > 0, SMALL_SIZE)
	button(Rect2(sb.end - Vector2(16, 16), Vector2(16, 16)), "▼", "dn", top < lines.size() - VISIBLE, SMALL_SIZE)
	var track := Rect2(sb.position + Vector2(0, 16), Vector2(16, sb.size.y - 32))
	var total := maxf(lines.size(), 1.0)
	var th := maxf(track.size.y * minf(23.0 / total, 1.0), 10.0)
	var ty := track.position.y + (track.size.y - th) * (float(top) / maxf(lines.size() - VISIBLE, 1))
	draw_rect(Rect2(track.position.x + 2, ty, 12, th), Color(0.6, 0.65, 0.8, 0.8))
	hit(Rect2(track.position, Vector2(16, ty - track.position.y)), "pgup")
	hit(Rect2(Vector2(track.position.x, ty + th), Vector2(16, track.end.y - ty - th)), "pgdn")
	# 按顺序显示 (1031)
	var cb := r(6, PANEL.y + 8, 140, 20)
	var box := Rect2(cb.position + Vector2(0, 3), Vector2(13, 13))
	draw_rect(box, Color(0, 0, 0.05, 0.6))
	draw_rect(box, UIStyle.BORDER_IN, false, 1.0)
	if Mem.ev(4093) != 0:
		draw_polyline(PackedVector2Array([box.position + Vector2(3, 7), box.position + Vector2(6, 10), box.position + Vector2(11, 3)]), UIStyle.NAME_COLOR, 2.0)
	if hovered("order"):
		draw_rect(cb, HOVER)
	text(Rect2(cb.position + Vector2(19, 0), cb.size), "按顺序显示")
	hit(cb, "order")


func _scroll(d: int) -> void:
	top = clampi(top + d, 0, maxi(lines.size() - VISIBLE, 0))
	queue_redraw()


func _on_hit(key: Variant) -> void:
	match key:
		"up":
			_scroll(-1)
		"dn":
			_scroll(1)
		"pgup":
			_scroll(-VISIBLE)
		"pgdn":
			_scroll(VISIBLE)
		"order":
			# 0x4d18e1: EV[4093] = the box, back to the top
			Mem.set_ev(4093, 0 if Mem.ev(4093) != 0 else 1)
			top = 0
			_build()


func _on_wheel(d: int, _p: Vector2) -> void:
	_scroll(d * 3)


func _on_drag(d: Vector2, _at: Vector2) -> Vector2:
	var n := int(d.y / LH)
	_scroll(-n)
	return Vector2(d.x, n * LH)
