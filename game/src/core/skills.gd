class_name Skills
extends RefCounted
## Lookups the mod's character skills share (docs/mod_patches.md group 3): the dynamic skill slots, the battle-map
## number that tells battles from towns, and the "an ally of this side stands next to U" test.

## Number of the loaded battle map (set by 0x44c2e3 when a battlefield is created). 0xff / 0xffff outside battles:
## LoadGame writes 0xff, and the story picture cache (0x426c6a) 0xffff.
const MAP_NO := 0x48baec
## Dynamic skill slot k is EV[3970 + k] (u32 at 0x55ee08 + 4k): the person who has that skill, 1024 = nobody.
const DYN := 3970


## Battle mode for the person getters: byte [0x48baec] != 0xff.
static func in_battle() -> bool:
	return Mem.r8(MAP_NO) != 0xff


static func dyn(k: int) -> int:
	return Mem.ev(DYN + k)


## 0x4dc761: person `pid` holds dynamic skill k.
static func has_dyn(pid: int, k: int) -> bool:
	return k < 30 and pid >= 0 and pid == dyn(k)


## The unit of person `pid` if it is on the map (state 2), else null.
static func unit_on_map(pid: int) -> BUnit:
	var s := BUnit.slot_of(pid)
	if s < 0:
		return null
	var u := BUnit.at(s)
	return u if u.state == BUnit.STATE_ON_MAP else null


## 0x4d4a60(pid, U): person `pid` has a unit on the map, on U's side group (slots < 35 or >= 35 both), and
## 0x45afca(U's person, pid, loose) holds: both units on the map with HP > 0 and `pid`'s unit on one of the 8
## cells around U's. (0x45afca finds U's unit again by its person, as the original does.)
static func beside(pid: int, u: BUnit) -> bool:
	var o := unit_on_map(pid)
	if o == null or (o.slot < 35) != (u.slot < 35):
		return false
	var a := unit_on_map(u.pid)
	if a == null or a.hp <= 0 or o.hp <= 0:
		return false
	var d := o.pos - a.pos
	return absi(d.x) <= 1 and absi(d.y) <= 1 and d != Vector2i.ZERO


## |dx| + |dy| as 0x4db541 computes it (on bytes).
static func distance(a: Vector2i, b: Vector2i) -> int:
	return (absi(a.x - b.x) + absi(a.y - b.y)) & 0xff


static var _cells := {}
static var _cells_gen := -1


## 0x435884: the unit on cell c in the battlefield's occupancy grid (state 2, a fallen one too until it is
## removed; the lowest slot if several), or null. Cells outside the map ([0x4b422c] / [0x4b422d]) hold none.
## The cell → slot table is rebuilt only when BUnit.gen says who stands where may have changed.
static func unit_in_cell(c: Vector2i) -> BUnit:
	if c.x < 0 or c.y < 0 or c.x >= Mem.r8(Mem.MAP_WH) or c.y >= Mem.r8(Mem.MAP_WH + 1):
		return null
	if _cells_gen != BUnit.gen:
		_cells.clear()
		for s in range(114, -1, -1):
			var a := Mem.UNITS + s * Mem.UNIT_SIZE
			if Mem.r16(a) != 0xffff and Mem.r8(a + 0xc) == BUnit.STATE_ON_MAP:
				_cells[Vector2i(Mem.r8(a + 6), Mem.r8(a + 7))] = s
		_cells_gen = BUnit.gen
	var s: int = _cells.get(c, -1)
	return null if s < 0 else BUnit.at(s)


## 0x477adc: in a battle (scene mode 3, 0x40b922), the first unit slot whose state is not 0 that holds person
## `pid`, else null.
static func battle_unit(pid: int) -> BUnit:
	if Mem.r8(Addr.SCENE_MODE) != 3 or pid < 0:
		return null
	for s in 115:
		var a := Mem.UNITS + s * Mem.UNIT_SIZE
		if Mem.r8(a + 0xc) != 0 and Mem.r32(a) == pid:
			return BUnit.at(s)
	return null
