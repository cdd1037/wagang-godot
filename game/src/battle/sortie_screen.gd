class_name SortieScreen
extends DlgPanel
## 选择武将 (dialog 236, 0x45e6b3; grid 0x45f201, strip 0x45f427, panel 0x45c697): the candidates as a 7×4 grid of
## standing sprites with "Lv. N" and the name, the chosen ones in a strip of 15 slots below, and the hovered
## candidate's portrait and stats on the right. A click adds a candidate (SE 15) or takes it out again (SE 1);
## forced ones stay. 决定 needs at least ⌊2M/3⌋ chosen (and one); 取消 gives up the sortie. Two sort buttons:
## 部队属性顺 and a cycling 等级 / 攻击 / 精神 / 防御. 战场位置 shows the start positions on the coming map.
## A right click shows a candidate's 武将情报.

## 0x486408: the family order of 部队属性顺.
const FAMILY_ORDER := [0, 16, 17, 11, 13, 12, 7, 3, 15, 24, 21, 1, 2, 4, 19, 6, 5, 18, 9, 8, 10, 20, 25, 23, 14, 22, 26]
const KEY_NAMES := ["", "部队属性", "等级", "攻击", "精神", "防御"]
const GRID := Rect2(4, 4, 400, 296)
const STRIP := Rect2(4, 324, 400, 128)
const PANEL_X := 412.0

## [0x48e3a8] the sort key in use, [0x48e3b0] the two buttons' keys (session-wide).
static var sort_key := 1
static var button_keys: Array[int] = [1, 2]

var cands: Array[int] = []      # L: forced first, then the offered ones (builder order)
var forced := 0                 # F
var most := 0                   # M = min(max, N)
var order: Array[int] = []      # display position → candidate index
var slots: Array[int] = []      # chosen candidates, in click order
var hover := 0                  # candidate shown in the panel (+8)
var _hover_cell := -1
var _result: Array[int] = []
var _stage: Node


## 0x45e6b3: run the dialog for candidates L (the first F forced) and the stored maximum.
static func choose(ui: CanvasLayer, stage: Node, maxn: int, lst: Array[int], f: int) -> Array[int]:
	var w := SortieScreen.new()
	w.cands = lst
	w.forced = f
	w.most = mini(maxn, lst.size())
	w._stage = stage
	w.dlu_scale = Vector2.ONE
	w.dlu = Vector2(626, 466)
	if Game.autoplay:
		var out: Array[int] = []
		for i in mini(w.most, lst.size()):
			out.append(lst[i])
		return out
	await DlgPanel.run(ui, w)
	return w._result


func _ready() -> void:
	super._ready()
	for i in forced:
		slots.append(i)
	for i in cands.size():
		order.append(i)
	_sort(button_keys[1])
	if sort_key != button_keys[1]:
		_sort(sort_key)


# ------------------------------------------------------------------ sorting (0x45bdc3, stable)
func _key(k: int, pid: int) -> int:
	var p := Game.person(pid)
	match k:
		1:
			var fam := p.family()
			var idx := FAMILY_ORDER.find(fam)
			if idx < 0:
				idx = 27
			return (27 - idx) * 3 + (p.cls % 3 if p.cls < 39 else 0)
		2:
			return p.level
		3:
			return p.stat(0)
		4:
			return p.stat(2)
		5:
			return p.stat(1)
	return -pid


func _sort(k: int) -> void:
	var dec := []
	for i in order.size():
		dec.append([-_key(k, cands[order[i]]), i, order[i]])
	dec.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	order.clear()
	for d in dec:
		order.append(int(d[2]))


func _button_label(b: int) -> String:
	if b == 0:
		return "部队属性顺"
	return "< %s >顺" % KEY_NAMES[button_keys[1]]


func _can_go() -> bool:
	return slots.size() >= 1 and slots.size() >= most * 2 / 3


# ------------------------------------------------------------------ drawing
func _sprite(pid: int, at: Vector2, mod := Color(1, 1, 1)) -> void:
	var t := Assets.tex("gfx/units/mov/%03d.png" % Game.person(pid).sprite_entry(0))
	if t:
		draw_texture_rect_region(t, Rect2(at, Vector2(48, 48)), Rect2(0, 6 * 48, 48, 48), mod)


func _draw_dialog() -> void:
	var g := Rect2(origin + GRID.position, GRID.size)
	var bg := Assets.tex("gfx/effects/qusi/03.png")
	if bg:
		draw_texture_rect(bg, g, false)
	for p in mini(order.size(), 28):
		var ci := order[p]
		var pid := cands[ci]
		var cell := g.position + Vector2((p % 7) * 56 + 8, (p / 7) * 72 + 8)
		var chosen := slots.has(ci)
		var mod := Color(1, 1, 1)
		if ci < forced:
			mod = Color(0.62, 0.62, 0.62)       # forced: darkened once (palette −6)
		if chosen:
			mod.a = 0.45                         # chosen: blended with the background
		_sprite(pid, cell, mod)
		var lv_col := Color(0.55, 0.75, 1.0) if not chosen else (Color(1.0, 0.5, 0.45) if ci < forced else Color(0.75, 0.75, 0.75))
		UIStyle.draw_text(self, cell + Vector2(0, 44), "Lv. %2d" % Game.person(pid).level, lv_col, 12)
		var name := InfoWindow.display_name(Game.person(pid))
		var nw := Assets.font().get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var hov := _hover_cell == p and ci >= forced
		UIStyle.draw_text(self, cell + Vector2(24 - nw / 2, 62), name, Color(1, 0.55, 0.5) if hov else Color(1, 1, 1), 12)
		hit(Rect2(cell, Vector2(56, 72)), ["cand", ci, p])
	# sort buttons (inside the grid window)
	for b in 2:
		var br := Rect2(g.position + Vector2(300, 244 + 22 * b), Vector2(88, 16))
		var active := sort_key == button_keys[b]
		draw_rect(br, Color(0.05, 0.08, 0.18, 0.85))
		draw_rect(br, UIStyle.BORDER_IN if active else DIM, false, 1.0)
		if hovered(["sort", b]):
			draw_rect(br, HOVER)
		text(br, _button_label(b), HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1) if active else DIM, SMALL_SIZE)
		hit(br, ["sort", b])
	text(Rect2(origin + Vector2(24, 302), Vector2(200, 20)), "出阵武将  - %2d/%2d" % [slots.size(), most])
	# the strip of chosen units
	var s := Rect2(origin + STRIP.position, STRIP.size)
	var sbg := Assets.tex("gfx/effects/qusi/04.png")
	if sbg:
		draw_texture_rect(sbg, s, false)
	for k in 15:
		if k >= most:
			break
		var at := s.position + Vector2((k % 8) * 50, (k / 8) * 64 + 13)
		var fr := 2 if k < forced else (1 if k < most * 2 / 3 else 0)
		var ft := Assets.tex("gfx/effects/qusi/%02d.png" % fr)
		if ft:
			draw_texture_rect(ft, Rect2(at, Vector2(50, 50)), false)
		if k < slots.size():
			_sprite(cands[slots[k]], s.position + Vector2((k % 8) * 50 + 1, (k / 8) * 64 + 1))
			hit(Rect2(at, Vector2(50, 50)), ["slot", slots[k]])
	_draw_panel()
	button(Rect2(origin + Vector2(PANEL_X + 4, 432), Vector2(66, 26)), "决定", ["ok", 0], _can_go())
	button(Rect2(origin + Vector2(PANEL_X + 74, 432), Vector2(66, 26)), "取消", ["cancel", 0])
	button(Rect2(origin + Vector2(PANEL_X + 144, 432), Vector2(66, 26)), "战场位置", ["map", 0], true, SMALL_SIZE)


## The 武将情报 group (0x45c6fd): the hovered candidate.
func _draw_panel() -> void:
	var pr := Rect2(origin + Vector2(PANEL_X, 0), Vector2(dlu.x - PANEL_X, 428))
	group(pr, "武将情报")
	if hover < 0 or hover >= cands.size():
		return
	var p := Game.person(cands[hover])
	var face := Game.person_face(p.id)
	var fr := Rect2(pr.position + Vector2(8, 22), Vector2(120, 120))
	if face:
		draw_texture_rect(face, fr, false)
	var x := pr.position.x + 134
	text(Rect2(x, pr.position.y + 26, 76, 18), InfoWindow.display_name(p), HORIZONTAL_ALIGNMENT_LEFT, UIStyle.NAME_COLOR)
	text(Rect2(x, pr.position.y + 46, 76, 18), p.class_name_str())
	text(Rect2(x, pr.position.y + 66, 76, 18), "Lv %d" % p.level)
	var ab := ["武艺", "统制", "智谋", "感知", "胆魄"]
	for i in 5:
		text(Rect2(x + (i % 2) * 40, pr.position.y + 88 + (i / 2) * 18, 40, 18), "%s%d" % [ab[i], p.get_raw(i)], HORIZONTAL_ALIGNMENT_LEFT, UIStyle.TEXT_COLOR, 11)
	var rows := [["HP", p.max_hp(), 1000, 1], ["MP", p.max_mp(), 255, 3], ["Exp", p.exp, 100, 5], ["攻击", p.stat(0), 800, 6],
		["防御", p.stat(1), 800, 6], ["精神", p.stat(2), 800, 6], ["反应", p.stat(3), 800, 6], ["士气", p.stat(4), 800, 6]]
	for k in rows.size():
		var y := pr.position.y + 150 + 26 * k
		text(Rect2(pr.position.x + 8, y, 40, 18), str(rows[k][0]), HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
		var v: int = rows[k][1]
		if int(rows[k][3]) == 5 and v == 0xff:
			bar(Rect2(pr.position.x + 50, y + 2, 150, 14), 100, 0, 100, 5, "MAX")
		else:
			bar(Rect2(pr.position.x + 50, y + 2, 150, 14), v, 0, int(rows[k][2]), int(rows[k][3]))
	text(Rect2(pr.position.x + 8, pr.position.y + 150 + 26 * 8, 40, 18), "机动", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	text(Rect2(pr.position.x + 50, pr.position.y + 150 + 26 * 8, 40, 18), "%d" % (p.move_points() & 0xff))


# ------------------------------------------------------------------ input
func _on_hover(key: Variant) -> void:
	if key is Array and (key[0] == "cand" or key[0] == "slot"):
		hover = int(key[1])
		_hover_cell = int(key[2]) if key[0] == "cand" else -1
	else:
		_hover_cell = -1


func _on_tap(key: Variant) -> void:
	_on_hover(key)
	_on_hit(key)


func _on_hit(key: Variant) -> void:
	if not (key is Array):
		return
	match key[0]:
		"cand", "slot":
			_toggle(int(key[1]))
		"sort":
			Audio.se(0)
			var b := int(key[1])
			if b == 1 and sort_key == button_keys[1]:
				button_keys[1] = 2 if button_keys[1] >= 5 else button_keys[1] + 1
			sort_key = button_keys[b]
			_sort(sort_key)
		"ok":
			if _can_go():
				await get_tree().create_timer(0.1).timeout
				Audio.se(5)
				for i in slots:
					_result.append(cands[i])
				close()
		"cancel":
			_result.clear()
			close()
		"map":
			await SortieMap.open(get_parent())


## 0x45d85d: forced candidates cannot be taken out.
func _toggle(ci: int) -> void:
	hover = ci
	if ci < forced:
		return
	var k := slots.find(ci)
	if k >= 0:
		Audio.se(1)
		slots.remove_at(k)
	elif slots.size() < most:
		Audio.se(15)
		slots.append(ci)


func _on_right(key: Variant) -> bool:
	if key is Array and (key[0] == "cand" or key[0] == "slot"):
		var pid := cands[int(key[1])]
		if _stage is BattleStage:
			var u := InfoWindow.unit_of(pid)
			if u:
				await InfoWindow.open_unit(get_parent(), _stage, u)
		else:
			await InfoWindow.open(get_parent(), cands, int(key[1]))
	return true          # a right click elsewhere does nothing (Esc is 取消)
