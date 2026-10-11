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


## 0x43e4d6: the first unit slot (0..114) whose person is `pid`, or -1.
static func unit_slot(pid: int) -> int:
	if pid < 0:
		return -1
	for s in 115:
		if Mem.r32(Mem.UNITS + s * Mem.UNIT_SIZE) == pid:
			return s
	return -1


## The unit of person `pid` if it is on the map (state 2), else null.
static func unit_on_map(pid: int) -> BUnit:
	var s := unit_slot(pid)
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
