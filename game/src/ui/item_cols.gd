class_name ItemCols
extends RefCounted
## The item list views of the shop and warehouse windows (generic list 0x463xxx..0x4678xx): column types with their
## header (0x466548), alignment, natural width (0x466eaf: the width of a sample text plus padding; 0x4640cd then
## shares the list's width out in proportion), cell text (0x46776a) and sort order (0x4671a5).
## A row is {"id", "idx" (shop position / bag slot / stack), "lvl", "exp", "flag" (can equip), "owner" (-1 仓库)}.

enum { NAME, LV, EXP, KIND, USE, EFFECT, PRICE, TOTAL, EQUIP, SELL, SPECIAL, STOCK, OWNER }

const HEADERS := ["名称", "Lv", "Exp", "属性", "功效", "效果", "价格", "总数", "装备", "卖价", "特殊效果", "库存", "持有者"]
const ALIGN := [0, 2, 2, 1, 1, 2, 2, 2, 1, 2, 1, 2, 1]
## Width samples and padding (0x466eaf).
const SAMPLES := [["道具名文字数", 23], ["Lv", 12], ["MAX", 10], ["属性", 12], ["兵种上升", 12], ["效果", 12],
	["价格", 12], ["总数", 12], ["装备", 12], ["价格", 12], ["特殊效果", 12], ["库存", 12], ["持有者", 12]]
## Dark red (RGB 128,0,0) in the original; lighter here on the dark panels.
const RED := Color(1.0, 0.45, 0.4)


static func columns(types: Array) -> Array:
	var f := Assets.font()
	var out := []
	for t in types:
		var w := f.get_string_size(SAMPLES[t][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + int(SAMPLES[t][1])
		out.append([HEADERS[t], w, ALIGN[t]])
	return out


static func category(id: int) -> int:
	return Person.slot_of(Game.item(id))


static func treasure(id: int) -> bool:
	var it := Game.item(id)
	return Person.slot_of(it) < 2 and int(it.get("type", 0)) & 1 == 1


## Buy price (0x426ff4): price byte × 100, × 4/5 while 贾润甫 (20) is in the party (the mod's 【术】市侩).
static func buy_price(id: int) -> int:
	var p := int(Game.item(id).get("price", 0)) * 100
	if Mem.r8(Game.person(20).base + 0x2a) != 0xff:
		p = p * 4 / 5
	return p


## Sell price (0x40c7a9): price byte × 300 >> 2, × (lvl + 1) >> 1 for weapons and armour; 0xff → 0xffff, unsellable.
static func sell_price(id: int, lvl: int) -> int:
	var b := int(Game.item(id).get("price", 0))
	if b == 0xff:
		return 0xffff
	var p := b * 300 >> 2
	if category(id) < 2:
		p = p * (lvl + 1) >> 1
	return p


## Bag slots holding id (0x40d73b); stacks for consumables.
static func stock(id: int) -> int:
	if Game.is_stack_item(id):
		return Game.stack_count(id)
	var n := 0
	for i in Game.BAG_SLOTS:
		if Mem.r8(Game.BAG + 3 * i) == id:
			n += 1
	return n


## 总数: the stock plus party members wearing it in its slot (0x467676).
static func total(id: int) -> int:
	var n := stock(id)
	if Game.is_stack_item(id):
		return n
	var slot := category(id)
	if slot > 2:
		return n
	for p in Game.persons:
		if Mem.r8(p.base + 0x2a) == 0 and Mem.r8(p.base + 0x2e + 3 * slot) == id:
			n += 1
	return n


## The value part of 0x4620ff / 0x4621bb.
static func effect_value_text(id: int, lvl: int) -> String:
	if id < 0 or id == 0xff:
		return "--"
	var it := Game.item(id)
	if Person.slot_of(it) < 2:
		return "+%d" % Person.item_value_at(it, lvl)
	return DetailPanel.effect_suffix(id, lvl)


## Cell text and colour (null = the row's) of column type t.
static func cell(t: int, row: Dictionary, actionable: bool, selected: bool) -> Array:
	var id := int(row["id"])
	var it := Game.item(id)
	var cat := Person.slot_of(it)
	match t:
		NAME:
			return [str(it.get("name", "?")), null]
		LV:
			return ["--" if cat >= 2 else "%d" % int(row["lvl"]), null]
		EXP:
			if cat >= 2:
				return ["--", null]
			return ["MAX" if int(row["exp"]) == 0xff else "%d" % int(row["exp"]), null]
		KIND:
			var ty := int(it.get("type", 0))
			if ty < 0x12:
				return [Mem.str_ptr(Addr.WEAPON_KIND_NAMES, ty >> 1), null]
			return [Mem.str_ptr(Addr.WEAPON_KIND_NAMES, 10 if cat == 3 else 9), null]
		USE:
			var code := (int(it.get("special", 0x12)) if cat < 2 else int(it.get("type", 0))) - 0x12
			return [DetailPanel.effect_name(code) if code >= 0 else "", null]
		EFFECT:
			return [effect_value_text(id, int(row["lvl"])), null]
		PRICE:
			var p := buy_price(id)
			return ["%d" % p, RED if not actionable and Game.gold < p else null]
		TOTAL:
			return ["%d" % total(id), null]
		EQUIP:
			if int(row.get("flag", 0)) != 0:
				return ["○", null]
			return ["×", RED if not actionable else null]
		SELL:
			var s := sell_price(id, int(row["lvl"]))
			if s == 0xffff:
				return ["---", RED if not actionable else null]
			return ["%d" % s, null]
		SPECIAL:
			return ["有", RED if not selected else null] if treasure(id) else ["无", null]
		STOCK:
			return ["%d" % stock(id), null]
		OWNER:
			var o := int(row.get("owner", -1))
			if o < 0:
				return ["仓库", RED if not selected else null]
			return [InfoWindow.display_name(Game.person(o)), null]
	return ["", null]


## Sort key of column type t: ascending keys give the column's natural order (0x4671a5).
static func sort_key(t: int, row: Dictionary) -> int:
	var id := int(row["id"])
	var it := Game.item(id)
	var cat := Person.slot_of(it)
	match t:
		NAME:
			return id
		LV:
			return -(int(row["lvl"]) if cat < 2 else -1)
		EXP:
			return -(int(row["exp"]) if cat < 2 else -1)
		KIND, USE:
			return int(it.get("type", 0))
		EFFECT:
			if cat < 2:
				return -Person.item_value_at(it, int(row["lvl"]))
			return -int(it.get("value", 0))
		PRICE:
			return int(it.get("price", 0)) * 100
		TOTAL:
			return -total(id)
		EQUIP:
			return -int(row.get("flag", 0))
		SELL:
			return sell_price(id, int(row["lvl"]))
		SPECIAL:
			return -1 if treasure(id) else 0
		STOCK:
			return -stock(id)
		OWNER:
			return int(row.get("owner", -1))
	return 0


## A stable sort of rows (list-view rows when `wrapped`: the row is in "data") by column type t.
static func sort_rows(rows: Array, t: int, reverse := false, wrapped := false) -> Array:
	var dec := []
	for i in rows.size():
		var d: Dictionary = rows[i]["data"] if wrapped else rows[i]
		dec.append([sort_key(t, d) * (-1 if reverse else 1), i, rows[i]])
	dec.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out := []
	for d in dec:
		out.append(d[2])
	return out


## Header click (0x464e1f): the column sorted last sorts reversed (and nothing counts as sorted last); another
## sorts in its natural order and becomes the last. Returns the new "last".
static func header_click(lv: DlgPanel.ListView, types: Array, col: int, last: int) -> int:
	var reverse := col == last
	lv.rows = sort_rows(lv.rows, types[col], reverse, true)
	return -1 if reverse else col


## Small icon for a row's first cell.
static func icon(id: int) -> Texture2D:
	return Assets.tex("gfx/icons/items/small/%03d.png" % int(Game.item(id).get("icon", 0)))
