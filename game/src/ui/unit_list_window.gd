class_name UnitListWindow
extends DlgPanel
## 部队情报一览 (menu 105 武将一览 → 0x47af8a, dialog 186, rows 0x479d12, cells 0x47a64f): in a battle the units on
## the map of one side, 我军 (slots 0..34, 友军 included; the default) or 敌军 (35..114); in a town the party
## members. Rows by person id; a header click sorts that column (again: reversed). A click (left or right) on a row
## shows its 武将情报 and, in a battle, puts the map on the unit; the list stays open.

const HEADERS := ["武将名", "部队属性", "Lv", "Exp", "HP", "MP", "攻击", "防御", "精神", "反应", "士气"]
const ALIGN := [0, 1, 2, 2, 1, 1, 2, 2, 2, 2, 2]
const SAMPLES := [["最多武将数", 12], ["部队属性", 12], ["Lv", 12], ["MAX", 10], ["999/999", 10], ["999/999", 10],
	["攻击", 12], ["攻击", 12], ["攻击", 12], ["攻击", 12], ["攻击", 12]]
## 0x486408: the family order of the 部队属性 sort.
const FAMILY_ORDER := [0, 16, 17, 11, 13, 12, 7, 3, 15, 24, 21, 1, 2, 4, 19, 6, 5, 18, 9, 8, 10, 20, 25, 23, 14, 22, 26]
const BLUE := Color(0.55, 0.75, 1.0)    # RGB(0,0,255) in the original

var st: BattleStage
var side := 1                    # 1 我军, 0 敌军
var lv := DlgPanel.ListView.new()
var last := 0


static func open(ui: CanvasLayer, stage: BattleStage) -> void:
	var w := UnitListWindow.new()
	w.dlu = Vector2(387, 177)
	w.dlu_scale = Vector2(1.6, 2.4)
	w.st = stage
	Audio.se(0)
	await DlgPanel.run(ui, w)


func _ready() -> void:
	super._ready()
	var f := Assets.font()
	for i in HEADERS.size():
		lv.columns.append([HEADERS[i], f.get_string_size(SAMPLES[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + int(SAMPLES[i][1]), ALIGN[i]])
	lv.sortable = true
	_fill()
	lv.rows = _sorted(0, false)


func _fill() -> void:
	lv.rows.clear()
	var pids: Array[int] = []
	if st == null:
		pids = Game.party_ids()
	else:
		for i in (range(0, 35) if side == 1 else range(35, 115)):
			var u := st.units[i]
			if u.state == BUnit.STATE_ON_MAP and u.pid >= 0:
				pids.append(u.pid)
		pids.sort()
	for pid in pids:
		lv.rows.append({"data": pid})
	_cells()


func _unit(pid: int) -> BUnit:
	return InfoWindow.unit_of(pid) if st != null else null


func _cells() -> void:
	for i in lv.rows.size():
		var r: Dictionary = lv.rows[i]
		var pid := int(r["data"])
		var p := Game.person(pid)
		var u := _unit(pid)
		var hp := "%3d/%3d" % ([u.hp, u.max_hp()] if u else [p.max_hp(), p.max_hp()])
		var mp := "%3d/%3d" % ([u.mp & 0xff, u.max_mp()] if u else [p.max_mp(), p.max_mp()])
		var cells := [InfoWindow.display_name(p), p.class_name_str(), "%d" % p.level, "MAX" if p.exp == 0xff else "%d" % p.exp, hp, mp]
		var colors := [null, ItemCols.RED if PersonPanel.promotable(p) else null, null, null,
			ItemCols.RED if u and u.status & BUnit.ST_POISON else null, ItemCols.RED if u and u.status & BUnit.ST_SEAL else null]
		for s in 5:
			cells.append("%d" % (u.stat(s) if u else p.stat(s)))
			var b := u.buff(s) if u else 3
			colors.append(ItemCols.RED if b < 3 else (BLUE if b > 3 else null))
		if i == lv.sel:
			colors = []                  # the colours are not used on the highlighted row
		r["cells"] = cells
		r["colors"] = colors
	queue_redraw()


## Sort keys (0x479f91): column 0 by person id, the others high values first.
func _key(col: int, pid: int) -> int:
	var p := Game.person(pid)
	var u := _unit(pid)
	match col:
		0:
			return pid
		1:
			var fam := p.family()
			var idx := FAMILY_ORDER.find(fam) if fam < 27 else 27
			if idx < 0:
				idx = 27
			return -((27 - idx) * 3 + (p.cls % 3 if p.cls <= 38 else 0))
		2:
			return -p.level
		3:
			return -p.exp
		4:
			return -(u.hp if u else p.max_hp())
		5:
			return -((u.mp & 0xff) if u else p.max_mp())
	var s := col - 6
	return -(u.stat(s) if u else p.stat(s))


func _sorted(col: int, reverse: bool) -> Array:
	return DlgPanel.sorted_by(lv.rows, func(r: Dictionary) -> int: return _key(col, int(r["data"])), reverse)


func _draw_dialog() -> void:
	list_view(r(4, 2, 379, 153), lv, "list")
	if st != null:
		for c in [[1, "我军", 13], [0, "敌军", 53]]:
			var rr := r(c[2], 162, 36, 12)
			var cc := rr.position + Vector2(6, rr.size.y / 2)
			draw_circle(cc, 6, Color(0, 0, 0.05, 0.6))
			draw_arc(cc, 6, 0, TAU, 20, UIStyle.BORDER_IN, 1.0)
			if side == int(c[0]):
				draw_circle(cc, 3, UIStyle.NAME_COLOR)
			if hovered(["side", c[0]]):
				draw_rect(rr, HOVER)
			text(Rect2(rr.position + Vector2(15, 0), rr.size), str(c[1]))
			hit(rr, ["side", c[0]])
	button(r(338, 160, 45, 13), "确定", ["ok", 0])


func _on_hover(key: Variant) -> void:
	var row := int(key[1]) if key is Array and key[0] == "list" and int(key[1]) >= 0 else -1
	if row != lv.sel and not Game.touch:
		lv.sel = row
		_cells()


func _on_hit(key: Variant) -> void:
	if not (key is Array):
		return
	if list_scroll_hit(key, lv, "list"):
		return
	var col := header_hit(key, "list")
	if col >= 0:
		var reverse := col == last
		lv.rows = _sorted(col, reverse)
		last = -1 if reverse else col
		lv.sel = -1
		_cells()
		return
	match key[0]:
		"ok":
			close()
		"side":
			# 0x47ae51: SE 0, refill, then the stored sort column again
			if int(key[1]) != side:
				Audio.se(0)
				side = int(key[1])
				lv.top = 0
				_fill()
				if last >= 0:
					lv.rows = _sorted(last, false)
				_cells()
		"list":
			await _show(int(key[1]))


func _on_right(key: Variant) -> bool:
	if key is Array and key[0] == "list" and int(key[1]) >= 0:
		await _show(int(key[1]))
		return true
	return false


## 0x47ade4: 武将情报 for the row; in a battle the map goes to the unit first.
func _show(i: int) -> void:
	var pid := int(lv.rows[i]["data"])
	if st == null:
		await InfoWindow.open_party(get_parent(), pid)
		return
	var u := _unit(pid)
	if u:
		await st.view.center_on(u.pos)
		st.view.cursor_cell = u.pos
		st.hud.set_hover(u.pos)
		await InfoWindow.open_unit(get_parent(), st, u)
	_cells()
