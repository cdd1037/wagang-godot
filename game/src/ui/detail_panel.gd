class_name DetailPanel
extends DlgPanel
## Item detail (dialog 167, fill 0x40c843) and strategy detail (dialog 285, fill 0x46fa85), opened from the
## 武将情报 window's 装备 and 策略 pages. Also the item effect texts those pages share (0x462005 / 0x461ef3).

## 可装备的部队 labels 1472..1497 (one per class family 0..25), from the dialog template.
const FAMILIES := ["英雄类", "刀兵类", "枪兵类", "轻骑兵类", "弓兵类", "间谍类", "格斗兵类", "重骑兵类", "僧兵类",
	"谋士类", "道士类", "双刃骑兵类", "锤骑兵类", "燕山骑兵类", "贼兵类", "弓骑兵类", "雄师类", "统军类", "国师类",
	"力士类", "蛮骑兵类", "战车类", "辎重兵类", "箭车类", "玄骑兵类", "倭兵类"]

var kind := 0           # 0 item, 1 strategy
var iid := -1
var lvl := 0
var xp := 0
var sid := -1


static func show_item(ui: Node, item_id: int, level: int, exp: int) -> void:
	var d := DetailPanel.new()
	d.dlu = Vector2(251, 145)
	d.kind = 0
	d.iid = item_id
	d.lvl = level
	d.xp = exp
	await DlgPanel.run(ui, d)


static func show_strategy(ui: Node, strategy_id: int) -> void:
	var d := DetailPanel.new()
	d.dlu = Vector2(175, 144)
	d.kind = 1
	d.sid = strategy_id
	await DlgPanel.run(ui, d)


# ------------------------------------------------------------------ texts (verified against wagan.wa)
static func _levelable(it: Dictionary) -> bool:
	return Person.slot_of(it) < 2                       # 0x40c74c: weapon or armour


static func _treasure(it: Dictionary) -> bool:
	return _levelable(it) and int(it.get("type", 0)) & 1 == 1   # 0x40c76e


## Exp needed for the next item level (mod 0x4e0021 / 0x4d3d08): 100, treasures 150, and +100 at Lv 9.
static func exp_max(it: Dictionary, level: int) -> int:
	var m := 150 if _treasure(it) else 100
	if level == 9:
		m += 100
	return m


## Value at a level (0x40c674): base value, plus the growth per level above 1 for weapons and armour.
static func _value_at(it: Dictionary, level: int) -> int:
	return Person.item_value_at(it, level) if _levelable(it) else int(it.get("value", 0))


## Effect name of code (0x4072d3): table 0x48bc50, codes from 0x3f on in table 0x410f50.
static func _effect_name(code: int) -> String:
	if code < 0x3c:
		return Mem.str_ptr(0x48bc50, code)
	return Mem.str_ptr(0x410f50, code - 0x3f)


## Main effect line (0x462005): "攻击/防御/精神 +N" for those item kinds (0x40681a), else the effect text.
static func item_effect(item_id: int, level: int) -> String:
	if item_id < 0:
		return ""
	var it := Game.item(item_id)
	var t := int(it.get("type", 0))
	var k := 0xff
	if t < 10 or t == 0x18:
		k = 0
	elif t < 0xe or t == 0x19:
		k = 2
	elif t < 0x12 or t == 0x1a:
		k = 1
	match k:
		0: return "攻击 +%d" % _value_at(it, level)
		1: return "防御 +%d" % _value_at(it, level)
		2: return "精神 +%d" % _value_at(it, level)
	return effect_text(item_id, level)


## A treasure's special effect line (0x462174), "" for other items.
static func item_special(item_id: int, level: int) -> String:
	if item_id < 0 or not _treasure(Game.item(item_id)):
		return ""
	return effect_text(item_id, level)


static func effect_name(code: int) -> String:
	return _effect_name(code)


## 0x461ef3 with the value and suffix of 0x4621bb.
static func effect_text(item_id: int, level: int) -> String:
	var r := _effect_parts(item_id, level)
	if r.is_empty():
		return ""
	var code: int = r[0]
	var v: int = r[1]
	var suffix: String = r[2]
	if v == 0:
		return _effect_name(code)
	if v & 0xff == 0xff:
		return "%s (%s)" % [Mem.str_ptr(0x48bc50, code), suffix]
	return "%s %s" % [_effect_name(code), suffix]


## The value part alone (0x4621bb), as the list views' 效果 column shows it: "ALL", "+N", "--", "+N%", "-N%".
static func effect_suffix(item_id: int, level: int) -> String:
	var r := _effect_parts(item_id, level)
	return "" if r.is_empty() else str(r[2])


## [effect code, value, suffix] of an item's effect (0x4621bb), [] for plain weapons and armour.
static func _effect_parts(item_id: int, level: int) -> Array:
	var it := Game.item(item_id)
	var t := int(it.get("type", 0))
	var tr := _treasure(it)
	if not tr and t <= 0x11:
		return []
	var code := (int(it.get("special", 0x12)) if tr else t) - 0x12
	var v := Person.treasure_effect_value(it, level) if tr else int(it.get("value", 0))
	var suffix := ""
	if code in [0, 1, 3, 4, 5, 0xf, 0x10, 0x11, 0x12, 0x13, 0x14, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1c, 0x1d, 0x1e, 0x1f,
			0x20, 0x21, 0x24, 0x26, 0x27, 0x28, 0x2a, 0x2c, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x39, 0x3a, 0x3b, 0x3c, 0x3d,
			0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x47]:
		v = 0
		suffix = "--"
	elif code in [2, 6, 7, 8, 0xb, 0xc, 0xe, 0x2d, 0x2e, 0x34, 0x35, 0x36, 0x37, 0x38, 0x48, 0x49]:
		suffix = "ALL" if v == 0xff else ("--" if v == 0 else "+%d" % v)
	elif code in [9, 10, 0xd, 0x15, 0x1b, 0x22, 0x23, 0x25, 0x46]:
		suffix = "+%d%%" % v
	elif code in [0x29, 0x2b]:
		suffix = "-%d%%" % v
	return [code, v, suffix]


## MP cost (0x425ad0), doubled for the second cast of 连续策略 ([0x4d0d61]).
static func strategy_mp(s: int) -> int:
	var mp := int(Game.strategy(s).get("mp", 0))
	return mp * 2 if Mem.r8(0x4d0d61) != 0 else mp


# ------------------------------------------------------------------ drawing
func _draw_dialog() -> void:
	if kind == 0:
		_draw_item()
	else:
		_draw_strategy()


func _draw_item() -> void:
	var it := Game.item(iid)
	icon(r(10, 5, 20, 20), Assets.tex("gfx/icons/items/large/%03d.png" % int(it.get("icon", 0))))
	text(r(40, 5, 100, 8), str(it.get("name", "?")), HORIZONTAL_ALIGNMENT_LEFT, UIStyle.NAME_COLOR)
	if _levelable(it):
		if lvl != 0xff:
			text(r(44, 17, 12, 8), "Lv", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
			text(r(56, 17, 14, 8), str(lvl))
		text(r(72, 17, 14, 8), "Exp", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
		var xm := exp_max(it, lvl)
		bar(r(87, 17, 40, 8), xp, xm, xm, 5)
	_frame(r(8, 32, 50, 31))
	text(r(11, 38, 22, 8), "属性∶", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	var t := int(it.get("type", 0))
	var grp := (t >> 1) if t < 0x12 else (10 if t >= 0x3f and t <= 0x50 else 9)   # 0x40c63a
	text(r(31, 38, 26, 8), Mem.str_ptr(Addr.WEAPON_KIND_NAMES, grp), HORIZONTAL_ALIGNMENT_LEFT, UIStyle.TEXT_COLOR, SMALL_SIZE)
	text(r(11, 50, 22, 8), "价格∶", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	var price := int(it.get("price", 0xff))
	text(r(31, 50, 25, 8), "---" if price == 0xff else str(price * 100), HORIZONTAL_ALIGNMENT_RIGHT, UIStyle.TEXT_COLOR, SMALL_SIZE)
	group(r(62, 28, 76, 35), "效果")
	text(r(66, 38, 70, 8), item_effect(iid, lvl), HORIZONTAL_ALIGNMENT_LEFT, UIStyle.TEXT_COLOR, SMALL_SIZE)
	text(r(66, 50, 70, 8), item_special(iid, lvl), HORIZONTAL_ALIGNMENT_LEFT, UIStyle.TEXT_COLOR, SMALL_SIZE)
	_frame(r(8, 68, 129, 56))
	paragraph(r(10, 70, 125, 52), str(it.get("description", "")), UIStyle.TEXT_COLOR, 13)
	group(r(147, 5, 101, 119), "可装备的部队")
	var ok := _families_ok(it)
	for f in FAMILIES.size():
		var x := 150 if f < 13 else 200
		text(r(x, 16 + 8 * (f % 13), 46, 8), FAMILIES[f], HORIZONTAL_ALIGNMENT_CENTER,
			UIStyle.TEXT_COLOR if ok[f] else Color(0.45, 0.45, 0.5), SMALL_SIZE)
	button(r(152, 128, 45, 13), "确认", "ok")


## Which class families may equip the item (0x40c843 / 0x40cb16 / mod 0x4da200): weapons and armour by the
## family's first class's equip table, accessories by their family byte (+0x17, 0xff = all; item 0x4c also
## families 8, 9, 18, 24), consumables none.
func _families_ok(it: Dictionary) -> Array:
	var t := int(it.get("type", 0))
	var ok := []
	ok.resize(FAMILIES.size())
	ok.fill(false)
	var last := -1
	for c in 0x34:
		var f := Game.family_of(c)
		if f == last or f >= FAMILIES.size():
			continue
		last = f
		if t < 0x12:
			var eq: Array = Game.cls(c).get("equip_raw", [])
			ok[f] = eq.size() > t and int(eq[t]) != 0
		elif t >= 0x3f and t <= 0x50:
			ok[f] = false
		else:
			var restr := int(it.get("growth", 0xff))
			var fam := restr
			if iid == 0x4c and f in [8, 9, 0x12, 0x18]:
				fam = f
			ok[f] = fam == f or restr == 0xff
	return ok


func _draw_strategy() -> void:
	var s := Game.strategy(sid)
	icon(r(12, 6, 20, 20), Assets.tex("gfx/icons/strategies/large/%03d.png" % int(s.get("anim", 0))))
	text(r(39, 12, 80, 8), str(s.get("name", "?")), HORIZONTAL_ALIGNMENT_LEFT, UIStyle.NAME_COLOR)
	_frame(r(4, 32, 89, 31))
	text(r(10, 38, 30, 8), "效果", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	text(r(41, 38, 6, 8), ":", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	text(r(48, 38, 44, 8), Mem.str_ptr(Addr.EFFECT_NAMES, int(s.get("effect", 0))), HORIZONTAL_ALIGNMENT_LEFT, UIStyle.TEXT_COLOR, SMALL_SIZE)
	text(r(10, 50, 33, 8), "消耗ＭＰ", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	text(r(41, 49, 6, 8), ":", HORIZONTAL_ALIGNMENT_LEFT, CAPTION, SMALL_SIZE)
	text(r(60, 50, 23, 8), str(strategy_mp(sid)), HORIZONTAL_ALIGNMENT_RIGHT, UIStyle.TEXT_COLOR, SMALL_SIZE)
	group(r(126, 4, 45, 58), "可能范围")
	var rg := int(s.get("range", 0xff))
	_diagram(r(131, 14, 36, 43), "attack", 0x10 if rg == 0xff else rg)        # Jiqi.wa (0x46fc40)
	group(r(126, 66, 45, 58), "影响范围")
	var ar := int(s.get("area", 0xff))
	_diagram(r(131, 76, 36, 43), "strategy", 1 if ar == 0xff else ar)         # Drink.wa (0x46fd6f)
	_frame(r(4, 68, 118, 56))
	paragraph(r(6, 70, 114, 52), str(s.get("description", "")), UIStyle.TEXT_COLOR, 13)
	button(r(126, 127, 45, 13), "确认", "ok")


func _diagram(rect: Rect2, set_name: String, i: int) -> void:
	var t := Assets.tex("gfx/effects/ranges/%s/%02d.png" % [set_name, i])
	if t:
		draw_texture_rect(t, Rect2(rect.get_center() - Vector2(32, 32), Vector2(64, 64)), false)


func _frame(rect: Rect2) -> void:
	draw_rect(rect, Color(0, 0, 0.05, 0.3))
	draw_rect(rect, FRAME, false, 1.0)


func _on_hit(key: Variant) -> void:
	if str(key) == "ok":
		close()


func _on_key(ev: InputEvent) -> bool:
	if ev.is_action_pressed("ui_accept"):
		close()
		return true
	return false
