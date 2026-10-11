class_name BattleAttrs
extends RefCounted
## Attribute ids of EEX op 0x36 test_attr / 0x38 set_attr (0x4112e9 / 0x412006, person attr 0x406d87/0x406f54):
## 0-4 battle stat words (攻击 防御 精神 爆发 士气, person +0x11..), 5 base MaxHP (+0x1c), 6 base MaxMP (+0x20),
## 7 battle-unit HP, 8 battle-unit MP (mod 0x406f01 / 0x406fc0: settable, reads as 0), 9 level, 10-14 raw abilities
## (武艺 统制 智谋 感知 胆魄), 15 stack count of item `person`.
## Person selectors 0x400..0x402 mean the current (event-triggering / acting) unit.

static func _pid(st: BattleStage, pid: int) -> int:
	if pid >= 0x400 and pid <= 0x402:
		# 0x45602b: the current unit's person, none (0xffff) when it is off the map or at HP 0
		return st.current_unit.pid if st.current_unit and st.current_unit.active() else 0xffff
	return pid


static func get_attr(st: BattleStage, pid: int, attr: int) -> int:
	pid = _pid(st, pid)
	if pid == 0xffff or pid > 0x400:
		return -1
	if attr == 15:
		return Game.stack_count(pid)
	if attr == 7:
		# the person's battle-unit HP (hidden/not-yet-appeared units keep full HP)
		# 0x4112e9: unit index lookup; no unit → the value is the index 0xff (255), not 0
		var u := st.unit_by_pid(pid)
		return u.hp if u else 0xff
	var p := Game.person(pid)
	if p == null:
		return 0
	match attr:
		0, 1, 2, 3, 4: return p.get_stat_word(attr)
		5: return p.hp_base
		6: return p.mp_base
		9: return p.level
		10, 11, 12, 13, 14: return p.get_raw([0, 1, 2, 3, 4][attr - 10])
	return 0


static func set_attr(st: BattleStage, pid: int, attr: int, op: int, v: int) -> void:
	pid = _pid(st, pid)
	if pid == 0xffff or pid > 0x400 or attr > 15:
		return
	if attr == 8:
		# mod 0x4d67d0 / 0x406fc0: the person's battle-unit MP (no unit → nothing). Op 2 goes through SetStat
		# with max(GetStat(8) − v, 0) = 0, GetStat(8) being 0.
		var mu := st.unit_by_pid(pid)
		if mu == null:
			return
		match op:
			0: mu.mp = mini(v, mu.max_mp())
			1: mu.mp = mini(mu.mp + v, mu.max_mp())
			2: mu.mp = 0
		st.refresh_units()
		return
	if attr == 7:
		var u := st.unit_by_pid(pid)
		if u == null:
			return
		match op:
			0: u.hp = mini(v, u.max_hp())
			1: u.hp = mini(u.hp + v, u.max_hp())
			2: u.hp = maxi(u.hp - v, 0)
		if u.hp <= 0 and u.state == BUnit.STATE_ON_MAP:
			u.extra["dying"] = true
		st.refresh_units()
		if u.hp <= 0 and u.state == BUnit.STATE_ON_MAP:
			await st.actions.unit_defeated(u)
		return
	PersonAttrs.set_attr(pid, attr, op, v)
	st.refresh_units()