class_name PersonPanel
extends RefCounted
## The person side of 买进 (327) and 装备 (328), panel class 0x487278 (init 0x469c60, person change 0x469ecb, stats
## 0x468ebe, slots 0x46942a): the person box (combobox 1098, members of the fixed table 0x4dbdb0 in its order, mod
## 0x4dbd90), Lv, portrait (sge 301 + face), the stat rows with the preview of an equipment change, the three
## equipment slots and 上一武将 / 下一武将. It draws into its window (a DlgPanel with this template's coordinates)
## and takes the window's hits whose key starts with "pp".

## 0x4dbdb0: the persons the shop and warehouse windows offer, in this order (party members only).
const TABLE := [0, 8, 3, 1, 19, 17, 14, 26, 7, 5, 43, 4, 9, 2, 24, 13, 10, 6, 16, 18, 12, 11, 28, 25, 15, 23, 22, 21,
	29, 20, 31, 27]
## Stat rows (label, value, diff at x 248 / 279 / 303; y = 114 + 14k): 0x4698af / 0x4693cd.
const ROWS := ["HP", "MP", "攻击", "防御", "精神", "反应", "士气", "机动"]
const SLOT_Y := [24, 88, 151]
const TITLES := ["武器∶ %s", "护具∶ %s", "辅助∶ %s"]

var w: DlgPanel
var x0 := 0.0                  # 买进's template is 1 DLU left of 装备's for the person box
var pids: Array[int] = []
var idx := 0
var enabled := true            # 买进's 道具店 tab disables the panel (0x4698dd(0))
var hover_slot := 3            # [panel+0x28]: the slot frame under the pointer, 3 = none
var _diff: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var _combo := false
var _combo_lv := DlgPanel.ListView.new()
var on_change := Callable()    # the person changed (the window recomputes its list flags)


func _init(window: DlgPanel) -> void:
	w = window
	for pid in TABLE:
		if Game.is_member(pid):
			pids.append(pid)
	_combo_lv.header = false
	_combo_lv.columns = [["", 1, HORIZONTAL_ALIGNMENT_CENTER], ["", 1, HORIZONTAL_ALIGNMENT_CENTER]]
	for pid in pids:
		var p := Game.person(pid)
		_combo_lv.rows.append({"cells": [InfoWindow.display_name(p), p.class_name_str()], "data": pid,
			"colors": [null, ItemCols.RED if promotable(p) else null]})


func person() -> Person:
	return Game.person(pids[idx]) if idx < pids.size() else null


## 0x468c7d: the class shows in red when the person could be promoted.
static func promotable(p: Person) -> bool:
	return p.cls < 0x27 and p.cls % 3 < 2 and p.level >= (p.cls % 3 + 1) * 20


func select(i: int, from_box := false) -> void:
	if pids.is_empty():
		return
	i = clampi(i, 0, pids.size() - 1)
	if i == idx:
		return
	if from_box:
		Audio.se(0)
	idx = i
	clear_preview()
	if on_change.is_valid():
		on_change.call()


# ------------------------------------------------------------------ preview (0x468ebe / 0x4692fd)
## b (0x461e1b): an item's part of stat k (0 攻击 … 4 士气, 5 HP, 6 MP, 7 机动).
static func item_part(id: int, lvl: int, k: int) -> int:
	if id < 0 or id == 0xff:
		return 0
	var it := Game.item(id)
	var v := 0
	if Person.stat_of_type(int(it.get("type", 0))) == k:
		v += Person.item_value_at(it, lvl) if Person.slot_of(it) < 2 else int(it.get("value", 0))
	if ItemCols.treasure(id) and it.get("special") != null and Person.stat_of_special(int(it["special"])) == k:
		v += Person.treasure_effect_value(it, lvl)
	return v


## The changes if `new_id` (level new_lvl) replaced the item in its slot; new_id -1: what taking off the item in
## the hovered slot would change.
func preview(new_id: int, new_lvl: int) -> void:
	clear_preview()
	var p := person()
	if p == null:
		return
	var old_id := -1
	var old_lvl := 0
	if new_id >= 0:
		if not p.can_equip(new_id):
			return
		var cat := ItemCols.category(new_id)
		old_id = Mem.r8(p.base + 0x2e + 3 * cat)
		old_lvl = Mem.r8(p.base + 0x2f + 3 * cat)
	elif hover_slot < 3:
		old_id = Mem.r8(p.base + 0x2e + 3 * hover_slot)
		old_lvl = Mem.r8(p.base + 0x2f + 3 * hover_slot)
	else:
		return
	# rows: HP MP 攻击 防御 精神 反应 士气 机动 ← kinds 5 6 0 1 2 3 4 7
	var kinds := [5, 6, 0, 1, 2, 3, 4, 7]
	for r in 8:
		var k: int = kinds[r]
		var a := item_part(new_id, new_lvl, k)
		var b := item_part(old_id, old_lvl, k)
		if k == 3 or k == 4:
			var word := p.get_stat_word(k)
			a = word * a / 100
			b = word * b / 100
		_diff[r] = a - b


func clear_preview() -> void:
	_diff = [0, 0, 0, 0, 0, 0, 0, 0]


# ------------------------------------------------------------------ drawing
func draw() -> void:
	var p := person()
	var dim := not enabled or p == null
	w.draw_line(w.r(241, 2, 1, 223).position, w.r(241, 2, 1, 223).position + Vector2(0, 223 * w.dlu_scale.y), DlgPanel.FRAME)
	# person box and level
	var box := w.r(253 + x0, 6, 100, 12)
	w.draw_rect(box, Color(0, 0, 0.05, 0.6))
	w.draw_rect(box, UIStyle.BORDER_IN if not dim else DlgPanel.DIM, false, 1.0)
	if p:
		var half := box.size.x / 2
		w.text(Rect2(box.position, Vector2(half, box.size.y)), InfoWindow.display_name(p), HORIZONTAL_ALIGNMENT_CENTER,
			UIStyle.TEXT_COLOR if not dim else DlgPanel.DIM, DlgPanel.SMALL_SIZE)
		w.draw_line(box.position + Vector2(half, 2), box.position + Vector2(half, box.size.y - 2), DlgPanel.FRAME)
		w.text(Rect2(box.position + Vector2(half, 0), Vector2(half - 12, box.size.y)), p.class_name_str(),
			HORIZONTAL_ALIGNMENT_CENTER, ItemCols.RED if promotable(p) and not dim else (UIStyle.TEXT_COLOR if not dim else DlgPanel.DIM), DlgPanel.SMALL_SIZE)
		w.text(Rect2(box.position, box.size - Vector2(3, 0)), "▼", HORIZONTAL_ALIGNMENT_RIGHT, UIStyle.TEXT_COLOR, 10)
		w.text(w.r(360, 6, 12, 10), "Lv", HORIZONTAL_ALIGNMENT_LEFT, DlgPanel.CAPTION, DlgPanel.SMALL_SIZE)
		w.text(w.r(372, 6, 14, 10), "%d" % p.level, HORIZONTAL_ALIGNMENT_LEFT, UIStyle.TEXT_COLOR, DlgPanel.SMALL_SIZE)
	if enabled:
		w.hit(box, ["pp", "box"])
	# portrait (120×120 in the 80×80-DLU frame)
	var pr := w.r(244, 25, 80, 80)
	if p and enabled:
		var face := Game.person_face(p.id)
		var fs := minf(120.0, minf(pr.size.x, pr.size.y))
		var fr := Rect2(pr.position + (pr.size - Vector2(fs, fs)) / 2, Vector2(fs, fs))
		w.draw_rect(fr.grow(1), UIStyle.BORDER_OUT, false, 1.0)
		if face:
			w.draw_texture_rect(face, fr, false)
	# stats
	if p:
		var vals := [p.max_hp(), p.max_mp(), p.stat(0), p.stat(1), p.stat(2), p.stat(3), p.stat(4), p.move_points() & 0xff]
		for r in 8:
			var y := 114 + 14 * r
			var c := UIStyle.TEXT_COLOR if not dim else DlgPanel.DIM
			w.text(w.r(248, y - 1, 30, 10), ROWS[r], HORIZONTAL_ALIGNMENT_LEFT, DlgPanel.CAPTION if not dim else DlgPanel.DIM, DlgPanel.SMALL_SIZE)
			w.text(w.r(272, y - 1, 25, 10), "%d" % (int(vals[r]) + _diff[r]), HORIZONTAL_ALIGNMENT_RIGHT, c, DlgPanel.SMALL_SIZE)
			var d := _diff[r]
			var dt := "" if d == 0 else ("+%d" % d if d > 0 else "%d" % d)
			w.text(w.r(300, y - 1, 22, 10), dt, HORIZONTAL_ALIGNMENT_RIGHT,
				Color(0.55, 1.0, 0.55) if d > 0 else ItemCols.RED, DlgPanel.SMALL_SIZE)
	# equipment slots
	for s in 3:
		_draw_slot(s, p, dim)
	w.button(w.r(326, 209, 35, 14), "上一武将", ["pp", "prev"], enabled and idx > 0, DlgPanel.SMALL_SIZE)
	w.button(w.r(363, 209, 37, 14), "下一武将", ["pp", "next"], enabled and idx < pids.size() - 1, DlgPanel.SMALL_SIZE)
	if _combo:
		var n := mini(pids.size(), 12)
		var lr := Rect2(box.position + Vector2(0, box.size.y), Vector2(box.size.x, 11 * w.dlu_scale.y * n))
		w.draw_rect(lr, Color(0.05, 0.07, 0.16, 0.98))
		w.draw_rect(lr, UIStyle.BORDER_IN, false, 1.0)
		_combo_lv.sel = idx
		w.list_view(lr, _combo_lv, "pp_combo", 11 * w.dlu_scale.y, DlgPanel.SMALL_SIZE)


func _draw_slot(s: int, p: Person, dim: bool) -> void:
	var y0: int = SLOT_Y[s]
	var fr := w.r(326, y0, 75, 63 if s < 2 else 53)
	w.draw_rect(fr, Color(0, 0, 0, 0.18))
	w.draw_rect(fr, DlgPanel.FRAME, false, 1.0)
	if p == null:
		return
	var id := Mem.r8(p.base + 0x2e + 3 * s)
	var lvl := Mem.r8(p.base + 0x2f + 3 * s)
	var xp := Mem.r8(p.base + 0x30 + 3 * s)
	var it: Dictionary = {} if id == 0xff else Game.item(id)
	var title := w.r(332, y0 + 3, 66, 9)
	if hover_slot == s and enabled:
		w.draw_rect(title, UIStyle.HILITE)
	# 樊虎 (11) has no 辅助: the label is greyed (mod 0x4d0eb4), the slot still answers
	var tc := UIStyle.TEXT_COLOR if not dim and not (s == 2 and Skills.holds("fanhu", p.id)) else DlgPanel.DIM
	w.text(title, TITLES[s] % (str(it.get("name", "?")) if id != 0xff else "无"), HORIZONTAL_ALIGNMENT_LEFT, tc, DlgPanel.SMALL_SIZE)
	if id != 0xff:
		w.icon(w.r(332, y0 + 15, 23, 23), Assets.tex("gfx/icons/items/large/%03d.png" % int(it.get("icon", 0))))
		if s < 2:
			w.text(w.r(356, y0 + 16, 12, 9), "Lv", HORIZONTAL_ALIGNMENT_LEFT, DlgPanel.CAPTION, DlgPanel.SMALL_SIZE)
			w.text(w.r(369, y0 + 16, 20, 9), "%d" % lvl, HORIZONTAL_ALIGNMENT_LEFT, UIStyle.TEXT_COLOR, DlgPanel.SMALL_SIZE)
			w.text(w.r(354, y0 + 26, 14, 9), "Exp", HORIZONTAL_ALIGNMENT_LEFT, DlgPanel.CAPTION, DlgPanel.SMALL_SIZE)
			# Exp bar maximum (mod 0x4d3d5a): 100, treasures 150, treasures at Lv 9 250
			var mx := (250 if lvl == 9 else 150) if ItemCols.treasure(id) else 100
			w.bar(w.r(368, y0 + 27, 31, 8), xp, 0, mx, 5)
			w.text(w.r(332, y0 + 51, 66, 9), DetailPanel.item_special(id, lvl), HORIZONTAL_ALIGNMENT_LEFT, UIStyle.TEXT_COLOR, DlgPanel.SMALL_SIZE)
		w.text(w.r(332, y0 + (41 if s < 2 else 40), 66, 9), DetailPanel.item_effect(id, lvl if s < 2 else 1),
			HORIZONTAL_ALIGNMENT_LEFT, UIStyle.TEXT_COLOR, DlgPanel.SMALL_SIZE)
	if enabled:
		w.hit(fr, ["pp_slot", s])


# ------------------------------------------------------------------ input
## The window's hover: a slot frame previews taking its item off (0x46be3b).
func on_hover(key: Variant) -> void:
	var s := 3
	if key is Array and key[0] == "pp_slot":
		s = int(key[1])
	if s != hover_slot:
		hover_slot = s
		if s < 3:
			preview(-1, 0)
		else:
			clear_preview()


## A click on one of the panel's hits; true when it was one.
func on_hit(key: Variant) -> bool:
	if not (key is Array):
		return false
	var k: Array = key
	if _combo:
		_combo = false
		if k[0] == "pp_combo" and int(k[1]) >= 0:
			select(int(k[1]), true)
			return true
		if k[0] == "pp_combo":
			w.list_scroll_hit(key, _combo_lv, "pp_combo")
			_combo = true
			return true
		Audio.se(1)          # CBN_SELENDCANCEL
		return true
	if k[0] != "pp":
		return false
	match k[1]:
		"box":
			_combo = true
			Audio.se(0)      # CBN_DROPDOWN
			_combo_lv.select(idx)
		"prev":
			select(idx - 1)
		"next":
			select(idx + 1)
	return true


func step(d: int) -> void:
	select(idx + d)
