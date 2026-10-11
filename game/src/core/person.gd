class_name Person
extends RefCounted
## View of one character (武将) record in emulated memory (0x48-byte struct at [0x4d0048] + id*0x48).
## Stat index order everywhere: 0 攻击(武艺) 1 防御(统制) 2 精神(智谋) 3 爆发/反应(感知) 4 士气(胆魄)
## 5 HP max, 6 MP max, 7 move, 8 exp gain.

const STAT_KEYS := ["attack", "defense", "spirit", "agility", "morale"]
const NONE := 0xff

var id := 0
var name := ""

var base: int:
	get: return Mem.person_addr(id)

var face: int:
	get: return Mem.r32(base + 0x04)
	set(v): Mem.w32(base + 0x04, v)
var sprite: int:
	get: return Mem.r8(base + 0x02)
	set(v): Mem.w8(base + 0x02, v)
var cls: int:
	get: return Mem.r8(base + 0x2b)
	set(v): Mem.w8(base + 0x2b, v)
var level: int:
	get: return Mem.r8(base + 0x2c)
	set(v): Mem.w8(base + 0x2c, v)
var exp: int:
	get: return Mem.r8(base + 0x2d)
	set(v): Mem.w8(base + 0x2d, v)
var hp_base: int:
	get: return Mem.r32(base + 0x1c)
	set(v): Mem.w32(base + 0x1c, v)
var mp_base: int:
	get: return Mem.r8(base + 0x20)
	set(v): Mem.w8(base + 0x20, v)
var fixed_growth_flag: int:
	get: return Mem.r8(base + 0x2a)
	set(v): Mem.w8(base + 0x2a, v)
var weapon: int:
	get: return _item_slot(0x2e)
	set(v): Mem.w8(base + 0x2e, NONE if v < 0 else v)
var weapon_lvl: int:
	get: return Mem.r8(base + 0x2f)
	set(v): Mem.w8(base + 0x2f, v)
var weapon_exp: int:
	get: return Mem.r8(base + 0x30)
	set(v): Mem.w8(base + 0x30, v)
var armor: int:
	get: return _item_slot(0x31)
	set(v): Mem.w8(base + 0x31, NONE if v < 0 else v)
var armor_lvl: int:
	get: return Mem.r8(base + 0x32)
	set(v): Mem.w8(base + 0x32, v)
var armor_exp: int:
	get: return Mem.r8(base + 0x33)
	set(v): Mem.w8(base + 0x33, v)
var accessory: int:
	get: return _item_slot(0x34)
	set(v): Mem.w8(base + 0x34, NONE if v < 0 else v)
## [0x4cf2b8], one count for everyone: the next level-ups' +1 grade, one per stat (set to 5 by 仙人果 and by the
## mod's SetExp option).
var bonus_counter: int:
	get: return Mem.r8(0x4cf2b8)
	set(v): Mem.w8(0x4cf2b8, v)


func _item_slot(off: int) -> int:
	var v := Mem.r8(base + off)
	return -1 if v == NONE else v


func get_stat_word(i: int) -> int:
	return Mem.r16(base + 0x11 + 2 * i)


func set_stat_word(i: int, v: int) -> void:
	Mem.w16(base + 0x11 + 2 * i, v)


func get_raw(i: int) -> int:
	return Mem.r8(base + 0x21 + i)


func set_raw(i: int, v: int) -> void:
	Mem.w8(base + 0x21 + i, v)


## Initialise the memory record from a data.wa person record (parser 0x408be3).
static func init_record(r: Dictionary) -> Person:
	var p := Person.new()
	p.id = int(r["id"])
	p.name = str(r["name"])
	var b := p.base
	Mem.fill(b, Mem.PERSON_SIZE, 0)
	Mem.w16(b, p.id | 0x1000)
	p.face = int(r["face"])
	p.sprite = int(r["sprite"])
	Mem.w8(b + 0x26, int(r.get("unk_10", 0)))
	p.fixed_growth_flag = int(r.get("fixed_growth_flag", 255))
	for i in 5:
		var v := int(r[STAT_KEYS[i]])
		p.set_stat_word(i, v)
		p.set_raw(i, v)
	p.hp_base = mini(int(r["hp"]), 500)
	p.mp_base = mini(int(r["mp"]), 250)
	p.cls = int(r["class"])
	p.level = maxi(1, int(r["level"]))
	p.exp = int(r["exp"])
	p.weapon = -1 if r["weapon"] == null else int(r["weapon"])
	p.weapon_lvl = NONE if r["weapon"] == null else 1
	p.weapon_exp = 0
	p.armor = -1 if r["armor"] == null else int(r["armor"])
	p.armor_lvl = NONE if r["armor"] == null else 1
	p.armor_exp = 0
	p.accessory = -1 if r["accessory"] == null else int(r["accessory"])
	Mem.w8(b + 0x35, NONE)
	Mem.w8(b + 0x36, NONE)
	if p.level >= 70:
		p.exp = 0xff
	return p


static func view(pid: int, pname: String) -> Person:
	var p := Person.new()
	p.id = pid
	p.name = pname
	return p


# ------------------------------------------------------------------ equipment math
func _item(i: int) -> Dictionary:
	return Game.item(i)


## Value of a weapon/armor at an equipment level: base + growth per extra level, capped 255.
static func item_value_at(it: Dictionary, lvl: int) -> int:
	var v := int(it.get("value", 0))
	for k in range(clampi(lvl, 1, 255) - 1):
		v = mini(v + int(it.get("growth", 0)), 255)
	return v


static func stat_of_type(t: int) -> int:
	if t <= 9 or t == 24: return 0
	if (t >= 10 and t <= 13) or t == 25: return 2
	if (t >= 14 and t <= 17) or t == 26: return 1
	match t:
		27: return 3
		28: return 4
		20, 29: return 5
		30: return 6
		32: return 7
		31: return 8
	return -1


static func stat_of_special(s: int) -> int:
	match s:
		20, 29: return 5
		24: return 0
		25: return 2
		26: return 1
		27: return 3
		28: return 4
		30: return 6
		31: return 8
		32: return 7
	return -1


func equip_bonus(s: int) -> int:
	var b := 0
	for slot in [[weapon, weapon_lvl], [armor, armor_lvl]]:
		var iid: int = slot[0]
		if iid < 0:
			continue
		var it := _item(iid)
		if it.is_empty():
			continue
		if stat_of_type(int(it["type"])) == s:
			b += item_value_at(it, slot[1])
		if it.get("treasure", false) and it.get("special") != null and stat_of_special(int(it["special"])) == s:
			b += treasure_effect_value(it, slot[1])
	if accessory >= 0:
		var a := _item(accessory)
		if not a.is_empty() and stat_of_type(int(a["type"])) == s:
			b += int(a.get("value", 0))
	return b


## Value of a treasure's special effect at an equipment level (0x46938f / 0x4d9303).
static func treasure_effect_value(it: Dictionary, lvl: int) -> int:
	var sp := int(it.get("special", -1))
	var v := int(it.get("special_value", 0))
	if sp in [24, 25, 26]:
		v *= (lvl + 1)
	elif sp == 85:
		v *= (lvl + 4)
	return v


## Does this person have item effect `eid` (weapon/armor treasure special or accessory type)?
func has_effect(eid: int) -> bool:
	for iid in [weapon, armor]:
		if iid >= 0:
			var it := _item(iid)
			if it.get("treasure", false) and it.get("special") != null and int(it["special"]) == eid:
				return true
	if accessory >= 0:
		var a := _item(accessory)
		if not a.is_empty() and int(a["type"]) == eid:
			return true
	return false


func effect_value(eid: int) -> int:
	for slot in [[weapon, weapon_lvl], [armor, armor_lvl]]:
		var iid: int = slot[0]
		if iid >= 0:
			var it := _item(iid)
			if it.get("treasure", false) and it.get("special") != null and int(it["special"]) == eid:
				return treasure_effect_value(it, slot[1])
	if accessory >= 0:
		var a := _item(accessory)
		if not a.is_empty() and int(a["type"]) == eid:
			return int(a.get("value", 0))
	return 0


# ------------------------------------------------------------------ equipping
## Slot of an item (0x40c6ea): 0 weapon, 1 armour, 2 accessory, 3 consumable.
static func slot_of(it: Dictionary) -> int:
	var t := int(it.get("type", 0xff))
	if t < 0xe: return 0
	if t < 0x12: return 1
	if t < 0x3f or t > 0x50: return 2
	return 3


## 0x407907: weapons and armour by the class's equip table, accessories by the family in the item's
## +0x17 byte (0xff = anyone; the mod lets families 8, 9, 18 and 24 wear item 0x4c, 0x4da23b). Mod: 樊虎 (11)
## wears no accessory (0x4d9a91); the holder of dynamic slot 9 (尤俊达, 【术】百宝) any weapon or armour (0x4dc8fc).
func can_equip(iid: int) -> bool:
	var it := _item(iid)
	if it.is_empty():
		return false
	if id == 11 and slot_of(it) == 2:
		return false
	match slot_of(it):
		0, 1:
			if id == Skills.dyn(9):
				return true
			var eq: Array = Game.cls(cls).get("equip_raw", [])
			var t := int(it["type"])
			return t < eq.size() and int(eq[t]) != 0
		2:
			var fam := int(it.get("growth", 0xff))
			if fam == 0xff or fam == family():
				return true
			return iid == 0x4c and family() in [8, 9, 0x12, 0x18]
	return false


## Level an item gets when none is given (0x407dec / 0x4143c2), from a character level: normal items
## (level mod 18) / 6 + 1 below 48, else 3; treasures level / 7 + 1, at most 10.
static func auto_level_at(it: Dictionary, lv: int) -> int:
	if bool(it.get("treasure", false)):
		return mini(lv / 7 + 1, 10)
	return (lv % 18) / 6 + 1 if lv < 48 else 3


func auto_item_level(it: Dictionary) -> int:
	return auto_level_at(it, level)


func _set_slot(slot: int, iid: int, lvl: int, xp: int) -> void:
	Mem.w8(base + 0x2e + 3 * slot, NONE if iid < 0 else iid)
	Mem.w8(base + 0x2f + 3 * slot, lvl)
	if slot < 2:
		Mem.w8(base + 0x30 + 3 * slot, xp)


## Equipment code of ops 0x3e / 0x48 for one slot (0x4429f9): 0 = the default for the class and level,
## 1 = take it off, otherwise item code − 2 (weapon), code + 0x24 (armour) or code + 0x33 (accessory).
## `lvl` 0 = automatic.
func equip_code(slot: int, code: int, lvl: int) -> void:
	if code == 0:
		default_equip(slot)
	elif code == 1:
		_set_slot(slot, -1, NONE, NONE)
	else:
		equip_item(slot, code + [-2, 0x24, 0x33][slot], lvl)


## 0x407fe7: the first weapon (armour) kind the class can use, tier by level (0-17, 18-35, 36+).
func default_equip(slot: int) -> void:
	if slot > 1:
		return
	var eq: Array = Game.cls(cls).get("equip_raw", [])
	var tier := mini(level / 18, 2)
	var lvl := (level % 18) / 6 + 1 if level < 48 else 3
	var kinds := range(0, 14) if slot == 0 else range(14, 18)
	for t in kinds:
		if t < eq.size() and int(eq[t]) != 0:
			var iid: int = tier + (t / 2) * 3 if slot == 0 else 0x26 + tier + ((t - 14) / 2) * 3
			_set_slot(slot, iid, lvl, 0 if lvl < 3 else NONE)
			return


## 0x407dec: put item `iid` into `slot` if it is that kind of item and this person can use it.
## The level is capped at the item's maximum (3, treasures 10); a maxed item has no experience to gain.
func equip_item(slot: int, iid: int, lvl: int) -> void:
	var it := _item(iid)
	if it.is_empty() or slot_of(it) != slot or not can_equip(iid):
		return
	var maxl := 10 if bool(it.get("treasure", false)) else 3
	if lvl == 0:
		lvl = auto_item_level(it)
	elif lvl != NONE:
		lvl = mini(lvl, maxl)
	var xp := 0 if lvl < maxl else NONE
	_set_slot(slot, iid, NONE if slot == 2 else lvl, xp)


# ------------------------------------------------------------------ derived stats
## Stat getters (0x407120..0x40720d) = min(stat word + equipment, 9999), with the mod's hooks: outside battles
## the 宿痕 rules replace the stat word (_scar); in battles the 连理 auras and 王君珂's 并蒂 scale the result.
## 反应 and 士气 equipment is a percentage (mod 0x469341, table 0x46235d): word · bonus / 100 of the plain stat
## word, as the items' "+%d%%" says.
func stat(s: int) -> int:
	var b := equip_bonus(s)
	if s == 3 or s == 4:
		b = get_stat_word(s) * b / 100
	if not Skills.in_battle():
		if s == 0:
			Mem.w32(0x55ee04, 0)       # the attack getter clears 并蒂's hit counters in towns (0x4dbcf6)
		return maxi(_min_add(_scar(s, get_stat_word(s)), b, 9999), 0)
	var v := mini(get_stat_word(s) + b, 9999)
	match s:
		0:
			var d := _aura_distance(0, 0)
			if d >= 0:
				return v * (100 + 5 * (5 - d)) / 100 if d < 5 else v
			if id == (Skills.dyn(2) & 0xffff):
				return v * (100 + 8 * Mem.r8(0x55ee02)) / 100      # 并蒂 (0x4dbd2c)
		1, 3, 4:
			var d := _aura_distance([0, 1, 0, 1, 0][s], [0, 0, 0, 12, 29][s])
			if d >= 0 and d < 5:
				return v * (100 + 5 * (5 - d)) / 100
	return v


## The 连理 auras (0x4db4c5 and its copies): 攻击 of the person in dynamic slot 0 (鲁明星) and 防御 of slot 1
## (鲁明月) near 管毅, 反应 of slot 1 near 鲁明星 (12), 士气 of slot 0 near 鲁明月 (29): +5 % per cell closer than 5.
## Returns the distance |dx| + |dy| when this person holds slot k and both units are on the map, else -1.
func _aura_distance(k: int, partner: int) -> int:
	if id != Skills.dyn(k):
		return -1
	var me := Skills.unit_on_map(id)
	var p := Skills.unit_on_map(partner)
	if me == null or p == null:
		return -1
	return Skills.distance(me.pos, p.pos)


## 0x47fa89: a + b, at most `mx` (a signed compare on 32 bits).
static func _min_add(a: int, b: int, mx: int) -> int:
	var r := (a + b) & 0xffffffff
	if r >= 0x80000000:
		r -= 0x100000000
	return mx if r > mx else r


## 宿痕 (0x4db5fd and its copies): outside battles, once a script has set the person's flag, a stat word w is
## scaled by the level of his signature weapon (or armour): f(w) = (w − e)·(100 + level·k) / 100 + e, with the
## base e and the factor k in EV, on 32 bits as the original computes. 谢映登's attack derives from his MP once
## EV[3223] ≥ 3 (贯石).
func _scar(s: int, w: int) -> int:
	var wl := weapon_lvl
	match s:
		0:
			if id == 8 and Mem.r8(Mem.EV + 4 * 3181) >= 1 and weapon == 0x18:
				return _scaled(w, Mem.ev(3401), wl, Mem.ev(3201))
			if id == 0 and Mem.r8(Mem.EV + 4 * 3184) >= 1 and weapon == 0x17:
				return _scaled(w, Mem.ev(3416), wl, Mem.ev(3204))
			if id == 24 and Mem.ev(3223) >= 3:
				var m := mp_base + (15 if accessory == 0x43 else 30 if accessory == 0x44 else 0)
				return ((m * Mem.ev(3257) & 0xffffffff) / 100 + w - Mem.ev(3451)) & 0xffffffff
		1:
			if id == 1 and Mem.r8(Mem.EV + 4 * 3185) >= 1 and weapon == 0x19:
				return _scaled(w, Mem.ev(3422), wl, Mem.ev(3205))
			if id == 0 and Mem.r8(Mem.EV + 4 * 3184) >= 1 and weapon == 0x17:
				return _scaled(w, Mem.ev(3417), wl, Mem.ev(3204))
		2:
			if id == 21 and Mem.r8(Mem.EV + 4 * 3186) >= 1 and weapon == 0x23:
				return _scaled(w, 0, wl, Mem.ev(3206))
			if id == 0 and Mem.r8(Mem.EV + 4 * 3184) >= 1 and weapon == 0x17:
				return _scaled(w, Mem.ev(3418), wl, Mem.ev(3204))
		3:
			if id == 19 and Mem.r8(Mem.EV + 4 * 3189) >= 1 and weapon == 0x1a:
				return _scaled(w, 0, wl, Mem.ev(3209))
			if id == 0 and Mem.r8(Mem.EV + 4 * 3184) >= 1 and weapon == 0x17:
				return _scaled(w, Mem.ev(3419), wl, Mem.ev(3204))
		4:
			if id == 13 and Mem.r8(Mem.EV + 4 * 3182) >= 1 and armor == 0x2e:
				return _scaled(w, 0, armor_lvl, Mem.ev(3202))
			if id == 0 and Mem.r8(Mem.EV + 4 * 3184) >= 1 and weapon == 0x17:
				return _scaled(w, Mem.ev(3420), wl, Mem.ev(3204))
	return w


static func _scaled(w: int, e: int, lvl: int, k: int) -> int:
	var t := ((w - e) & 0xffffffff) * ((100 + lvl * k) & 0xffffffff) & 0xffffffff
	return (t / 100 + e) & 0xffffffff


func max_hp() -> int:
	return mini(hp_base + equip_bonus(5), 9999)


func max_mp() -> int:
	return mini(mp_base + equip_bonus(6), 255)


## MovePoints (0x40729b), with 贾润甫's 【术】市侩 相马 (mod 0x4dc895): while the holder of dynamic slot 7 is a party
## member, every party member riding a mount (accessory 0x2f, 0x3b..0x3f) moves one more (on a byte).
func move_points() -> int:
	var m := mini(int(Game.cls(cls).get("move", 4)) + equip_bonus(7), 255)
	var h := Skills.dyn(7)
	if h != 0x400 and h < 1024 and Game.person(h).fixed_growth_flag == 0 and fixed_growth_flag == 0 \
			and Mem.r8(base + 0x34) in [0x3d, 0x3e, 0x3f, 0x2f, 0x3b, 0x3c]:
		m = (m + 1) & 0xff
	return m


func family() -> int:
	return Game.family_of(cls)


func class_name_str() -> String:
	return str(Game.cls(cls).get("name", "?"))


## Battle sprite graphic id (0x406a75). Override table = person.wa bytes at 0x55a000.
func graphic_id() -> int:
	var v := Mem.r8(Mem.BYTEVARS + id) if id < 1024 else 0
	var tier := cls % 3
	if v == 0:
		var t: Array = Game.unit_index["entry_index"]["class_to_graphic"]
		return int(t[cls]) if cls < t.size() else 0x45
	if v <= 5:
		return 0x35 + 3 * (v - 1) + tier
	if v == 6:
		return 0x44 if cls < 0x28 else 0x45
	return v + 0x3f


## Sprite sheet entry for a colour variant (0 red, 1 green, 2 blue) (0x43fc48).
func sprite_entry(colour: int) -> int:
	var g := graphic_id()
	if g < 43:
		return g * 3 + mini(colour, 2)
	return g + 86


func face_tex(small := false) -> Texture2D:
	return Game.person_face(id, small)


# ------------------------------------------------------------------ growth
static func ability_grade(r: int) -> int:
	if r >= 100: return 5
	if r >= 90: return 4
	if r >= 80: return 3
	if r >= 70: return 2
	if r >= 60: return 1
	return 0


## LevelUp (0x4073b8) by n levels, as the mod patches it. Returns what each stat [atk, def, spi, agi, mor, hp, mp]
## changed by on the last repetition (0x407497: new − old, 0 when the new value is 0). The HP and MP growth of a
## party member drops by the catch-up penalty; their jitter rolls are drawn but not used (0x433510: they go to a
## register only the five stats keep). Then the person's unit gets the class's HP and MP growth (0x4e0100).
func level_up(n := 1) -> Array:
	n = mini(n, 255 - level)
	var gains := [0, 0, 0, 0, 0, 0, 0]
	if n <= 0:
		return gains
	var growth: Dictionary = Game.cls(cls).get("growth", {})
	var gkeys := ["attack", "defense", "spirit", "agility", "morale", "hp", "mp"]
	# 盛彦师 (10) 【术】天运 (mod 0x4dbde3 / 0x4dbdfb): one random stat of the five grows one more, once per call
	var lucky := Rules.rand(5)
	for i in 7:
		var g := int(growth.get(gkeys[i], 0))
		var jittered := g
		if fixed_growth_flag == 0 and bonus_counter == 0:
			jittered = _jitter(g)
		if i <= 4:
			var grade := ability_grade(get_raw(i))
			if bonus_counter > 0:
				bonus_counter -= 1
				grade += 1
			g = (grade + jittered) >> 1
		elif fixed_growth_flag == 0 and mp_base != 1:
			g -= _catchup_penalty(i)     # mod 0x4d65f5
		for k in n:
			if id == 10 and i <= 4 and i == lucky:
				g += 1
				lucky = 5
			if i <= 4 and g == 0:
				g = 1
			var old := _stat_value(i)
			var nv := _add_stat(i, g)
			gains[i] = nv - old if nv != 0 else 0
	# the unit of the person (0x43e4d6; without one the loop leaves the last slot's record): HP and MP + the class
	# growth, at most the new maximum, MP on its low byte
	var s := Skills.unit_slot(id)
	var ua := Mem.unit_addr(s if s >= 0 else 114)
	var h := Mem.r32(ua + 0x10) + int(growth.get("hp", 0))
	Mem.w32(ua + 0x10, mini(h, max_hp()))
	var m := (Mem.r16(ua + 0x14) + int(growth.get("mp", 0)))
	Mem.w8(ua + 0x14, (max_mp() if m > max_mp() else m) & 0xff)
	level = level + n
	if level >= 70:
		exp = 0xff
	return gains


## The mod's catch-up penalty on a party member's HP (i = 5) or MP (6) growth (0x4d806a): with the average level
## of the player units on the map (slots 0..14 up to the first empty one, rounded up) below this person's level L,
## the gap divided by q, rounded up, where q = (L + 490) / HP base or L / MP base; the gap itself when q is 0.
func _catchup_penalty(i: int) -> int:
	var L := level
	var q := (L + 490) / maxi(hp_base, 1) if i == 5 else L / maxi(mp_base, 1)
	var count := 0
	var sum := 0
	for slot in 15:
		var a := Mem.unit_addr(slot)
		var pid := Mem.r32(a)
		if pid >= 0xffff:
			break
		if Mem.r8(a + 0xc) == BUnit.STATE_ON_MAP:
			count += 1
			sum += Mem.r8(Mem.person_addr(pid) + 0x2c)
	if count == 0:
		return 0
	var avg := (sum + count - 1) / count
	if avg >= L:
		return 0
	return L - avg if q == 0 else (L - avg + q - 1) / q


## LevelUp's report when it is called with `show`, as SetExp is in battles (0x4074cf, mod 0x4dbe29): "X升为N级。";
## with the 环境设定 option 升级显示能力成长 (byte [0x4dbe25]) also the seven changes `g` (0x43efc3); then
## "学会了策略「…」！" for each strategy whose learn level for the class is the new level (0x407525).
func level_up_texts(g: Array) -> Array[String]:
	var out: Array[String] = []
	var head := "%s升为%d级。" % [name, level]
	if Mem.r8(0x4dbe25) != 0:
		var names := ["攻击", "防御", "精神", "反应", "士气", "HP MAX", "MP MAX"]
		var t := head + "\n"
		for i in 7:
			var down: bool = i >= 5 and g[i] < 0
			t += "\n%s%s了 %d。" % [names[i], "减少" if down else "增加", -g[i] if down else g[i]]
		out.append(t)
	else:
		out.append(head)
	for sd in Game.strategies_db:
		if not sd.get("loaded_by_exe", true):
			continue
		var lv: Dictionary = sd.get("learn_level_by_class", {})
		if int(lv.get(str(cls), 0)) == level:
			out.append("学会了策略「%s」！" % sd.get("name", "?"))
	return out


## The value AddStat changes (0x42706b): a stat word, the HP base or the MP base.
func _stat_value(i: int) -> int:
	if i <= 4:
		return get_stat_word(i)
	return hp_base if i == 5 else mp_base


func _jitter(g: int) -> int:
	if Rules.chance(50):
		g += 1
	if Rules.chance(50):
		g = (g - 2) & 0xff
	return g


## AddStat (0x406e17) for i 0..6, returning the new value: a stat word at most 9999, the HP base at most 9999 and
## the MP base at most 255, on the signed sums of 0x47fa89 (a base that comes to 0 is 1). An MP base of 1 does not
## change, and g comes back. A lower maximum also lowers the battle unit's HP / MP (mod 0x4d6710).
func _add_stat(i: int, g: int) -> int:
	if i <= 4:
		var r := _min_add(get_stat_word(i), g, 9999)
		set_stat_word(i, r & 0xffff)
		return r
	if i == 5:
		var v := _min_add(hp_base, g, 9999)
		if v == 0:
			v = 1
		hp_base = v & 0xffffffff
		var u := Skills.battle_unit(id)
		if u != null and u.hp > max_hp():
			Mem.w32(u.addr + 0x10, max_hp())
		return v
	if mp_base == 1:
		return g
	var w := _min_add(mp_base, g, 255)
	if w == 0:
		w = 1
	mp_base = w & 0xff
	var bu := Skills.battle_unit(id)
	if bu != null and bu.mp > max_mp():
		Mem.w32(bu.addr + 0x14, max_mp())
	return w
