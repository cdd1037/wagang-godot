class_name PersonAttrs
extends RefCounted
## Person attribute ids (0x406d87 / 0x406f54) used by ops 0x36/0x38 outside battles:
## 0-4 stat words, 5 base MaxHP, 6 base MaxMP, 9 level, 10-14 raw abilities, 15 item stack count.

static func get_attr(pid: int, attr: int) -> int:
	if attr == 15:
		return Game.stack_count(pid)
	var p := Game.person(pid)
	if p == null:
		return 0
	match attr:
		0, 1, 2, 3, 4: return p.get_stat_word(attr)
		5: return p.hp_base
		6: return p.mp_base
		9: return p.level
		10, 11, 12, 13, 14: return p.get_raw(attr - 10)
	return 0


## op 0x38 on a person (0x412006): op 0 SetStat (0x406f54), op 1 AddStat (0x406e17), op 2 SetStat(max(cur − v, 0)).
## SetStat: stat words capped at 9999, 5 (base MaxHP) at 0xffff, 6 (base MaxMP) at 255, abilities at 120; 9 (level)
## and 15 do nothing. AddStat is Person.add_stat for 0..6 (signed sums, 0x47fa89); abilities read a dword (0x406e5c:
## this byte and the next three), so min(dword + v, 120) is 120 whenever those bytes are not all 0, and the low byte
## is stored (the scripts' 单挑经验 rewards in R_00 / R_04 / R_06 thus set the ability to 120).
static func set_attr(pid: int, attr: int, op: int, v: int) -> void:
	var p := Game.person(pid)
	if p == null or attr > 15:
		return
	if op == 1:
		match attr:
			0, 1, 2, 3, 4, 5, 6: p.add_stat(attr, v)
			10, 11, 12, 13, 14: p.set_raw(attr - 10, Person._min_add(Mem.r32(p.base + 0x21 + attr - 10), v, 120) & 0xff)
		return
	var nv := v if op == 0 else maxi(get_attr(pid, attr) - v, 0)
	if op != 0 and op != 2:
		return
	match attr:
		0, 1, 2, 3, 4: p.set_stat_word(attr, mini(nv, 9999))
		5: p.hp_base = mini(nv, 0xffff)
		6: p.mp_base = mini(nv, 255)
		10, 11, 12, 13, 14: p.set_raw(attr - 10, mini(nv, 120))
