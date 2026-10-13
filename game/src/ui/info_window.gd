class_name InfoWindow
extends DlgPanel
## 武将情报: the character / unit information window (dialog 166 of wagan.wa, procs 0x479164 / refresh 0x478688),
## with the tab pages 能力 (178), 装备 (179), 策略 (200) and 兵种 (284). It shows a person; in battle the person's
## unit (0x477adc: the first unit slot whose state ≠ 0 holds the person) adds its current HP/MP, status, buffs and
## side. 上一武将 / 下一武将 step through the list it was opened with, stopping at the ends. The original window is
## modeless and follows the hovered unit; this one is modal.

const TABS := ["能力", "装备", "策略", "兵种"]           # 0x48ec4c
const SIDES := ["[ 我军 ]", "[ 友军 ]", "[ 敌军 ]", "[ 敌军 ]"]   # by unit +5 (jump table 0x4789ff)
const GRADES := "EDCBASX"                               # 0x555470
const PAGE := Vector2(93, 22)                           # page dialogs inside the tab control (91,3,100,191)
const STRAT_ROWS := 14
## 状态 line parts (0x478a0f + mod 0x4d6140): status bits, then buff words.
const STATUS_PARTS := [[0x08, "混乱"], [0x02, "麻痹"], [0x40, "迷失"], [0x20, "怯力"], [0x10, "中毒"], [0x04, "穷计"]]

static var tab := 0     # [0x48e9a8]: the page shown last, kept between openings

var pids: Array[int] = []
var idx := 0
var _p: Person
var _u: BUnit
var _skill := ["", ""]
var _strats: Array[int] = []
var _strat_top := 0
var _strat_rh := 0.0          # a strategy row's height (set when drawn)


## Show the window for list[index] (0x479728). Outside battle it opens only for party members (0x407060).
static func open(ui: CanvasLayer, list: Array, index: int) -> void:
	if list.is_empty():
		return
	index = clampi(index, 0, list.size() - 1)
	if not in_battle() and not Game.is_member(int(list[index])):
		return
	var w := InfoWindow.new()
	w.dlu = Vector2(313, 256)
	w.pids.assign(list)
	w.idx = index
	Audio.play_se("se00")
	await DlgPanel.run(ui, w)


static func in_battle() -> bool:
	return Game.main != null and Game.main.stage is BattleStage


## The person's unit in battle (0x477adc), or null.
static func unit_of(pid: int) -> BUnit:
	if not in_battle():
		return null
	for u in (Game.main.stage as BattleStage).units:
		if u.state != BUnit.STATE_NONE and u.pid == pid:
			return u
	return null


## 上一/下一 list for a battle unit (0x479795 → 0x47980d): the on-map units of its group (slots 0..34 or
## 35..114), by person id.
static func battle_list(st: BattleStage, u: BUnit) -> Array[int]:
	var lo := 0 if u.slot < 35 else 35
	var hi := 35 if u.slot < 35 else 115
	var out: Array[int] = []
	for i in range(lo, hi):
		var v := st.units[i]
		if v.state == BUnit.STATE_ON_MAP and v.pid >= 0:
			out.append(v.pid)
	out.sort()
	return out


## Open for a battle unit with its group's list.
static func open_unit(ui: CanvasLayer, st: BattleStage, u: BUnit) -> void:
	var lst := battle_list(st, u)
	var i := lst.find(u.pid)
	if i < 0:
		lst = [u.pid]
		i = 0
	await open(ui, lst, i)


## Open for a party member with the party list (0x4768c0), or alone if not in it (0x479954).
static func open_party(ui: CanvasLayer, pid: int) -> void:
	var lst := Game.party_ids()
	var i := lst.find(pid)
	if i < 0:
		lst = [pid]
		i = 0
	await open(ui, lst, i)


func _ready() -> void:
	super._ready()
	_refresh()


func _refresh() -> void:
	_p = Game.person(pids[idx])
	_u = unit_of(pids[idx])
	_skill = skill_info(_p)
	_strats = strategies_of(_p.cls, _p.level)
	_strat_top = 0
	queue_redraw()


# ------------------------------------------------------------------ data (verified against wagan.wa)
## Name with ASCII digits removed (0x407757).
static func display_name(p: Person) -> String:
	var s := ""
	for ch in p.name:
		if ch < "0" or ch > "9":
			s += ch
	return s


## Strategies 0..0x43 the class learns by this level (list 0x4658c0; learn level class byte ≠ 0 and ≤ level).
static func strategies_of(c: int, level: int) -> Array[int]:
	var out: Array[int] = []
	var key := str(c)
	for s in Game.strategies_db:
		if int(s["id"]) >= 0x44:
			break
		var lv: Dictionary = s.get("learn_level_by_class", {})
		if lv.has(key) and int(lv[key]) > 0 and int(lv[key]) <= level:
			out.append(int(s["id"]))
	return out


## [caption, text] of the 技能 box. Caption: mod chain 0x4d3bd3 (it also rewrites the skill-code table
## 0x4dc100 the text is chosen by, as the original does); text: Fhua[450 + code] when the skill is active
## (0x4dc5c5), only for pid < 210.
static func skill_info(p: Person) -> Array:
	var pid := p.id
	var codes := 0x4dc100
	var cap := ""
	for g in [[Addr.SANBANFU, 0x555700], [Addr.TIANMO, 0x5558c0], [Addr.BORUO, 0x555860], [Addr.MOGONG, 0x555870], [Addr.DUANZAO, 0x555900]]:
		if pid == Mem.r32(g[0]):
			cap = Mem.str_at(g[1])
			break
	if cap == "":
		for a in range(codes, codes + 0x400):           # 0x4d5509: codes ≥ 0x36 → 0xff
			if Mem.r8(a) >= 0x36 and Mem.r8(a) != 0xff:
				Mem.w8(a, 0xff)
		for i in 30:                                    # 0x4d54d2: dynamic list EV[3970..3999]
			if pid == Mem.r32(0x55ee08 + 4 * i):
				Mem.w8(codes + pid, 0x27 + i)
				cap = Mem.str_at(0x5559a0 + 32 * i)
				break
	if cap == "" and pid == 25:                         # 0x4d562a
		if p.cls == 0x29:
			Mem.w8(codes + pid, 0x24)
			cap = Mem.str_at(0x555970)
		else:
			Mem.w8(codes + pid, 0xff)
	elif cap == "" and pid == 24:
		if Mem.r8(0x55e25c) >= 3:
			Mem.w8(codes + pid, 0xf)
			cap = Mem.str_at(0x555840)
		else:
			Mem.w8(codes + pid, 0xff)
	if cap == "":
		for k in 0x28:                                  # static table 0x4d3c4c → names 0x4d8260
			if pid == Mem.r16(0x4d3c4c + 2 * k):
				cap = Mem.str_ptr(0x4d8260, k)
				break
	if cap == "":
		cap = Mem.str_at(0x555791)                      # 无
	var txt := ""
	if pid < 210:
		var code := Mem.r8(codes + pid)
		txt = Game.text(450 + code) if skill_active(p, code) else Game.text(598)
	return [cap, txt]


static func skill_active(p: Person, code: int) -> bool:
	if code >= 0xae:
		return false
	match code:
		0: return Mem.r32(Addr.SANBANFU) == 1
		1: return Mem.r32(Addr.DUANZAO) == 16
		2: return Mem.r32(Addr.BORUO) == 15
		0x24: return p.cls == 0x29
	return true


## 状态 line (0x478a0f / 0x4d6140).
static func status_text(u: BUnit) -> String:
	if u == null:
		return "正常"
	var s := ""
	for part in STATUS_PARTS:
		if u.status & int(part[0]):
			s += part[1] + " "
	s += _buff_word(u.buff(0), "攻击")
	if Mem.r8(BattleStage.ASSASSIN_MARK + u.slot) != 0:
		s += "暗杀 "
	s += _buff_word(u.buff(2), "精神") + _buff_word(u.buff(1), "防御") + _buff_word(u.buff(3), "反应") + _buff_word(u.buff(4), "士气")
	if s == "":
		s = "正常"
	if u.acted:
		s += " 行动完毕"
	return s


static func _buff_word(b: int, w: String) -> String:
	if b >= 4:
		return w + "增加 "
	if b <= 2:
		return w + "减少 "
	return ""


# ------------------------------------------------------------------ drawing
func _draw_dialog() -> void:
	var p := _p
	var u := _u
	var face := p.face_tex()
	if face:
		var fr := r(3, 3, 80, 80)
		draw_texture_rect(face, Rect2(fr.get_center() - Vector2(60, 60), Vector2(120, 120)), false)
	text(r(3, 85, 44, 8), display_name(p), HORIZONTAL_ALIGNMENT_LEFT, UIStyle.NAME_COLOR)
	if u:
		text(r(47, 85, 36, 8), SIDES[u.colour & 3], HORIZONTAL_ALIGNMENT_LEFT, _side_color(u.colour))
	group(r(3, 96, 80, 41), "部队属性")
	text(r(6, 108, 74, 8), p.class_name_str())
	text(r(6, 122, 8, 8), "Lv", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	text(r(15, 122, 13, 8), str(p.level))
	text(r(31, 122, 12, 8), "Exp", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	bar(r(45, 122, 34, 8), p.exp, 100, 100, 5)
	group(r(3, 139, 80, 55), "状态")
	var mhp := p.max_hp()
	var mmp := p.max_mp()
	text(r(7, 153, 14, 8), "HP", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	bar(r(22, 153, 57, 8), u.hp if u else mhp, mhp, mhp, 2 if u and u.status & BUnit.ST_POISON else 1)
	text(r(7, 166, 14, 8), "MP", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	bar(r(22, 166, 57, 8), (u.mp & 0xff) if u else mmp, mmp, mmp, 4 if u and u.status & BUnit.ST_SEAL else 3)
	_sunken(r(3, 199, 187, 28))
	paragraph(r(5, 201, 183, 25), status_text(u))
	if p.id == 0:
		group(r(3, 231, 34, 24), "现金")
		text(r(5, 241, 30, 8), str(Game.gold), HORIZONTAL_ALIGNMENT_RIGHT, UIStyle.TEXT_COLOR, SMALL_SIZE)
	# 基本能力 (raw ability bytes +0x21..0x25, 0x4783c1)
	group(r(200, 1, 110, 45), "基本能力")
	var ab := [["武艺", 0, 215, 12], ["统制", 1, 215, 23], ["智谋", 2, 215, 34], ["感知", 3, 265, 12], ["胆魄", 4, 265, 23]]
	for a in ab:
		text(r(a[2], a[3], 17, 8), a[0], HORIZONTAL_ALIGNMENT_LEFT, CAPTION)
		text(r(a[2] + 18, a[3], 16, 8), str(p.get_raw(a[1])), HORIZONTAL_ALIGNMENT_RIGHT)
	_sunken(r(200, 49, 110, 68))
	if p.id < 210:
		paragraph(r(202, 51, 106, 64), Game.text(922 + p.id), UIStyle.TEXT_COLOR, 13)
	group(r(200, 121, 111, 107), _skill[0])
	paragraph(r(207, 133, 99, 89), _skill[1], UIStyle.TEXT_COLOR, 13)
	if Game.is_member(p.id):
		text(r(202, 241, 106, 9), "出阵数 %2d  撤退数 %2d" % [Mem.r8(p.base + 0x27), Mem.r8(p.base + 0x29)],
			HORIZONTAL_ALIGNMENT_CENTER, UIStyle.TEXT_COLOR, SMALL_SIZE)
	button(r(45, 240, 40, 13), "上一武将", "prev", idx > 0)
	button(r(90, 240, 40, 13), "下一武将", "next", idx + 1 < pids.size())
	button(r(140, 240, 45, 13), "确定", "ok")
	_draw_tabs()


func _side_color(c: int) -> Color:
	match c:
		0: return Color(1.0, 0.55, 0.5)
		1: return Color(0.55, 1.0, 0.55)
	return Color(0.55, 0.75, 1.0)


func _sunken(rect: Rect2) -> void:
	draw_rect(rect, Color(0, 0, 0.05, 0.35))
	draw_rect(rect, Color(0, 0, 0, 0.55), false, 1.0)


func pr(x: float, y: float, w: float, h: float) -> Rect2:
	return r(PAGE.x + x, PAGE.y + y, w, h)


func _draw_tabs() -> void:
	var area := r(91, 3, 100, 191)
	var th := 13 * dlu_scale.y
	var body := Rect2(area.position + Vector2(0, th), area.size - Vector2(0, th))
	draw_rect(body, Color(0, 0, 0.08, 0.25))
	draw_rect(body, FRAME, false, 1.0)
	var tw := area.size.x / TABS.size()
	for i in TABS.size():
		var tr := Rect2(area.position.x + i * tw, area.position.y + (0 if i == tab else 2), tw, th - (0 if i == tab else 2))
		draw_rect(tr, Color(0.16, 0.24, 0.46, 0.95) if i == tab else Color(0.08, 0.1, 0.2, 0.85))
		if i != tab and hovered("tab%d" % i):
			draw_rect(tr, HOVER)
		draw_rect(tr, FRAME, false, 1.0)
		text(tr, TABS[i], HORIZONTAL_ALIGNMENT_CENTER, UIStyle.NAME_COLOR if i == tab else UIStyle.TEXT_COLOR)
		hit(tr, "tab%d" % i)
	match tab:
		0: _page_ability()
		1: _page_equip()
		2: _page_strategy()
		3: _page_class()


## 能力 (178, bars 0x476b85): stats with equipment, bars to 800; in battle the buffed value against the base.
func _page_ability() -> void:
	var rows := [["攻击", 0], ["防御", 1], ["精神", 2], ["反应", 3], ["士气", 4]]
	for k in rows.size():
		var y := 5 + 24 * k
		var s: int = rows[k][1]
		group(pr(8, y, 79, 22), rows[k][0])
		var base := _p.stat(s)
		var b := _u.buff(s) if _u else 3
		if b >= 4:
			bar(pr(16, y + 10, 63, 8), base, _u.stat(s), 800, 8)
		elif b <= 2:
			bar(pr(16, y + 10, 63, 8), _u.stat(s), base, 800, 7)
		else:
			bar(pr(16, y + 10, 63, 8), base, 0, 800, 6)
	group(pr(8, 125, 79, 22), "机动")
	text(pr(42, 135, 35, 8), _move_text(), HORIZONTAL_ALIGNMENT_RIGHT)


## 0x476987: "%u ( +%d )" / "%u ( -%d )" with the move buff (paralysis is not shown).
func _move_text() -> String:
	var m := _p.move_points()
	if _u:
		var b := _u.buff(5)
		if b >= 4:
			return "%d ( +2 )" % (m + 2)
		if b <= 2:
			return "%d ( -2 )" % ((m - 2) & 0xffffffff)
	return str(m)


## 装备 (179, fill 0x476eb4 + mod 0x4d0e6a).
func _page_equip() -> void:
	var slots := [["武器∶ %s", _p.weapon, _p.weapon_lvl, _p.weapon_exp, 0], ["护具∶ %s", _p.armor, _p.armor_lvl, _p.armor_exp, 50],
		["辅助∶ %s", _p.accessory, 0, 0, 100]]
	for k in 3:
		var sl: Array = slots[k]
		var y0: int = sl[4]
		var iid: int = sl[1]
		var it := Game.item(iid) if iid >= 0 else {}
		var area := pr(4, y0 + 2, 88, 46 if k < 2 else 48)
		if iid >= 0 and hovered("eq%d" % k):
			draw_rect(area, HOVER)
		var lab_col := UIStyle.NAME_COLOR
		if k == 2 and _p.id == 11:
			lab_col = DIM                     # the mod disables this label for pid 11 (0x4d0e6a)
		text(pr(11, y0 + 4, 80, 8), sl[0] % (str(it.get("name", "?")) if iid >= 0 else "无"), HORIZONTAL_ALIGNMENT_LEFT, lab_col)
		if iid >= 0:
			icon(pr(11, y0 + 15, 20, 20), Assets.tex("gfx/icons/items/large/%03d.png" % int(it.get("icon", 0))))
			if k < 2:
				text(pr(37, y0 + 16, 14, 8), "Lv", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
				text(pr(52, y0 + 16, 12, 8), str(sl[2]))
				text(pr(37, y0 + 26, 14, 8), "Exp", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
				var xm := DetailPanel.exp_max(it, sl[2])
				bar(pr(52, y0 + 26, 33, 8), sl[3], xm, xm, 5)    # 0x4e0021 → 0x477723
			text(pr(13 if k < 2 else 12, y0 + 39 if k < 2 else 140, 76, 8),
				DetailPanel.item_effect(iid, sl[2] if k < 2 else 0), HORIZONTAL_ALIGNMENT_LEFT, UIStyle.TEXT_COLOR, 13)
			hit(area, "eq%d" % k)
		if k < 2:
			draw_line(pr(2, y0 + 49, 92, 0).position, pr(94, y0 + 49, 0, 0).position, FRAME)


## 策略 (200, list 0x4658c0): icon + name, MP. A click shows the strategy (dialog 285).
func _page_strategy() -> void:
	var box := pr(4, 1, 88, 152)
	_sunken(box)
	var rh := box.size.y / (STRAT_ROWS + 1)
	_strat_rh = rh
	var sb := 16.0 if _strats.size() > STRAT_ROWS else 0.0      # scroll buttons' column
	var head := Rect2(box.position, Vector2(box.size.x, rh))
	draw_rect(head, Color(0.16, 0.24, 0.46, 0.9))
	text(Rect2(head.position + Vector2(4, 0), head.size), "策略名", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	text(Rect2(head.position, head.size - Vector2(6 + sb, 0)), "MP", HORIZONTAL_ALIGNMENT_RIGHT, CAPTION, SMALL_SIZE)
	if _strats.is_empty():
		return
	_strat_top = clampi(_strat_top, 0, maxi(_strats.size() - STRAT_ROWS, 0))
	for k in range(_strat_top, mini(_strat_top + STRAT_ROWS, _strats.size())):
		var s := _strats[k]
		var row := Rect2(box.position.x, box.position.y + rh * (k - _strat_top + 1), box.size.x - sb, rh)
		if hovered("st%d" % s):
			draw_rect(row, HOVER)
		var sd := Game.strategy(s)
		icon(Rect2(row.position + Vector2(3, 1), Vector2(rh - 2, rh - 2)), Assets.tex("gfx/icons/strategies/small/%03d.png" % int(sd.get("anim", 0))))
		text(Rect2(row.position + Vector2(rh + 4, 0), row.size), str(sd.get("name", "?")), HORIZONTAL_ALIGNMENT_LEFT, UIStyle.TEXT_COLOR, 13)
		text(Rect2(row.position, row.size - Vector2(6, 0)), str(DetailPanel.strategy_mp(s)), HORIZONTAL_ALIGNMENT_RIGHT, UIStyle.TEXT_COLOR, 13)
		hit(row, "st%d" % s)
	if sb > 0:
		var up := Rect2(box.end.x - sb, head.end.y, sb, rh * 2)
		var dn := Rect2(box.end.x - sb, box.end.y - rh * 2, sb, rh * 2)
		button(up, "▲", "sup", _strat_top > 0)
		button(dn, "▼", "sdn", _strat_top + STRAT_ROWS < _strats.size())


## 兵种 (284, fill 0x477b62): class, weapon / armour kinds, growth grades, move, attack range, description.
func _page_class() -> void:
	var c := Game.cls(_p.cls)
	_draw_sprite(pr(8, 1, 28, 36))
	text(pr(41, 3, 50, 8), str(c.get("name", "?")), HORIZONTAL_ALIGNMENT_LEFT, UIStyle.NAME_COLOR)
	var eq: Array = c.get("equip_raw", [])
	var wk := "--"
	for i in 7:
		if eq.size() > 2 * i and int(eq[2 * i]) != 0:
			wk = Mem.str_ptr(Addr.WEAPON_KIND_NAMES, i)
			break
	var ak := "--"
	if eq.size() > 16:
		if int(eq[14]) != 0:
			ak = Mem.str_ptr(Addr.WEAPON_KIND_NAMES, 7)
		elif int(eq[16]) != 0:
			ak = Mem.str_ptr(Addr.WEAPON_KIND_NAMES, 8)
	text(pr(41, 15, 22, 8), "武器:", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	text(pr(63, 15, 30, 8), wk, HORIZONTAL_ALIGNMENT_LEFT, UIStyle.TEXT_COLOR, SMALL_SIZE)
	text(pr(41, 25, 22, 8), "护具:", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	text(pr(63, 25, 30, 8), ak, HORIZONTAL_ALIGNMENT_LEFT, UIStyle.TEXT_COLOR, SMALL_SIZE)
	var g: Dictionary = c.get("growth", {})
	var rows := [["攻击", "attack"], ["防御", "defense"], ["精神", "spirit"], ["反应", "agility"], ["士气", "morale"]]
	for k in rows.size():
		text(pr(8, 40 + 10 * k, 24, 8), rows[k][0], HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
		var gi := int(g.get(rows[k][1], 0))
		text(pr(32, 40 + 10 * k, 12, 8), GRADES[gi] if gi >= 0 and gi < GRADES.length() else "?", HORIZONTAL_ALIGNMENT_CENTER)
	text(pr(8, 90, 24, 8), "机动", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	text(pr(32, 90, 12, 8), str(int(c.get("move", 0))), HORIZONTAL_ALIGNMENT_CENTER)
	text(pr(46, 41, 40, 8), "攻击范围", HORIZONTAL_ALIGNMENT_CENTER, CAPTION, SMALL_SIZE)
	var rt := pr(50, 51, 39, 45)
	var t := Assets.tex("gfx/effects/ranges/attack/%02d.png" % int(c.get("attack_range", 0)))
	if t:
		draw_texture_rect(t, Rect2(rt.get_center() - Vector2(32, 32), Vector2(64, 64)), false)
	_sunken(pr(7, 102, 82, 50))
	paragraph(pr(8, 103, 80, 48), str(c.get("description", "")), UIStyle.TEXT_COLOR, 12)


## The unit's map sprite (0x43e572): in battle its frame (kneeling below 40% HP, standing once it moved or
## acted, else walking), else the standing-down frame.
func _draw_sprite(rect: Rect2) -> void:
	var entry := _u.sprite_entry() if _u else _p.sprite_entry(0)
	var t := Assets.tex("gfx/units/mov/%03d.png" % entry)
	if t == null:
		return
	var idx := 6
	var mirror := false
	if _u:
		var d := _u.dir
		var di: int = [1, 2, 0, 2][d]
		mirror = d == 1
		if _u.hp * 5 < _u.max_hp() * 2:
			idx = 9
			mirror = false
		elif _u.flags & (BUnit.F_ACTED | BUnit.F_MOVED):
			idx = 6 + di
		else:
			idx = di * 2
	var dst := Rect2(rect.get_center() - Vector2(24, 24), Vector2(48, 48))
	var src := Rect2(0, idx * 48, 48, 48)
	if mirror:
		draw_set_transform(dst.position + Vector2(48, 0), 0, Vector2(-1, 1))
		draw_texture_rect_region(t, Rect2(Vector2.ZERO, dst.size), src)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		draw_texture_rect_region(t, dst, src)


# ------------------------------------------------------------------ input
func _on_hit(key: Variant) -> void:
	var k := str(key)
	if k.begins_with("tab"):
		_set_tab(int(k.substr(3)))
	elif k == "prev":
		_step(-1)
	elif k == "next":
		_step(1)
	elif k == "ok":
		close()
	elif k == "sup":
		_strat_top -= 1
	elif k == "sdn":
		_strat_top += 1
	elif k.begins_with("eq"):
		var s := int(k.substr(2))
		var iid: int = [_p.weapon, _p.armor, _p.accessory][s]
		if iid >= 0 and iid < 0x68:
			await DetailPanel.show_item(get_parent(), iid, [_p.weapon_lvl, _p.armor_lvl, 0][s], [_p.weapon_exp, _p.armor_exp, 0][s])
	elif k.begins_with("st"):
		await DetailPanel.show_strategy(get_parent(), int(k.substr(2)))


## 0x4790da: SE 0 and the new page.
func _set_tab(t: int) -> void:
	if t == tab:
		return
	tab = t
	Audio.play_se("se00")
	queue_redraw()


func _step(d: int) -> void:
	var n := idx + d
	if n < 0 or n >= pids.size():
		return
	idx = n
	_refresh()


func _on_wheel(d: int, _p2: Vector2) -> void:
	if tab == 2:
		_strat_top += d
		queue_redraw()


func _on_drag(d: Vector2, _at: Vector2) -> Vector2:
	if tab != 2 or _strat_rh <= 0:
		return d
	var n := int(d.y / _strat_rh)
	_strat_top -= n                 # clamped when drawn
	return Vector2(d.x, n * _strat_rh)


func _on_key(ev: InputEvent) -> bool:
	if ev.is_action_pressed("ui_accept"):
		close()
	elif ev.is_action_pressed("ui_left"):
		_set_tab((tab + 3) % 4)
	elif ev.is_action_pressed("ui_right"):
		_set_tab((tab + 1) % 4)
	elif ev.is_action_pressed("ui_page_up") or (ev is InputEventKey and ev.keycode == KEY_Q):
		_step(-1)
	elif ev.is_action_pressed("ui_page_down") or (ev is InputEventKey and ev.keycode == KEY_E):
		_step(1)
	elif tab == 2 and ev.is_action_pressed("ui_up"):
		_strat_top -= 1
	elif tab == 2 and ev.is_action_pressed("ui_down"):
		_strat_top += 1
	else:
		return false
	return true
