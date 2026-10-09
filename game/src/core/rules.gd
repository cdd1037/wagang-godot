class_name Rules
extends RefCounted
## Battle formulas reverse-engineered from the original executable (see docs/rules.md).
## Integer arithmetic mirrors the original (truncating division).

static var rng := RandomNumberGenerator.new()


static func rand(n: int) -> int:
	if n < 2:
		return 0
	return rng.randi() % n


static func chance(p: int) -> bool:
	return rand(100) < p


static func sat_sub(x: int, y: int) -> int:
	return x - y if x > y else 0


## 4-band curve shared by physical hit and strategy hit (a = attacker value, d = defender value).
static func band_curve(a: int, d: int) -> int:
	d = maxi(d, 1)
	if a >= 2 * d:
		return 100
	if a >= d:
		return (a - d) * 10 / d + 90
	var h2 := maxi(d / 2, 1)
	if a >= d / 2:
		return (a - d / 2) * 30 / h2 + 60
	var h3 := maxi(d / 3, 1)
	return sat_sub(a, d / 3) * 30 / h3 + 30


# ------------------------------------------------------------------ terrain
static func terrain_effect(u: BUnit, terrain: int) -> int:
	var fam := Game.family(u.family())
	if fam.is_empty() or terrain < 0:
		return 10
	var arr: Array = fam["terrain_effect"]
	var t := int(arr[terrain]) if terrain < arr.size() else 10
	if u.has_effect(86):   # 辅助地形移动
		t = maxi(t, 10)
	return t


static func move_cost(u: BUnit, terrain: int) -> int:
	var fam := Game.family(u.family())
	if fam.is_empty() or terrain < 0:
		return 999
	var arr: Array = fam["move_cost"]
	if terrain >= arr.size():
		return 999
	var c: Variant = arr[terrain]
	if c == null:
		return 999
	if u.has_effect(86):
		return 1
	return int(c)


# ------------------------------------------------------------------ physical attack
const RANGED_FAMILIES := [4, 5, 15, 23]
# movement class per defender family: 0 cavalry, 1 vehicle, 2 infantry (table 0x43f4ac)
const CAVALRY_FAMILIES := [0, 3, 7, 11, 12, 13, 15, 16, 17, 20, 24]
const VEHICLE_FAMILIES := [21, 22, 23]


static func is_ranged(fam: int) -> bool:
	return fam in RANGED_FAMILIES


static func hit_rate(att: BUnit, def: BUnit) -> int:
	if is_ranged(att.family()) and def.has_effect(56):
		return 0
	if def.status & BUnit.ST_CONFUSION:
		return 100
	var h := band_curve(att.agi(), def.agi())
	if att.has_effect(39):
		h = mini(h + att.effect_value(39), 100)
	if def.has_effect(53):
		h = sat_sub(h, def.effect_value(53))
	if def.has_effect(55):
		h = sat_sub(h, def.effect_value(55))
	return clampi(h, 0, 100)


static func crit_rate(att: BUnit, def: BUnit) -> int:
	if att.has_effect(41):
		return 100
	var m := att.morale()
	var n := maxi(def.morale(), 1)
	if m >= 3 * n:
		return 100
	if m >= 2 * n:
		return (m - 2 * n) * 80 / n + 20
	if m >= n:
		return (m - n) * 18 / n + 2
	return 1


static func double_rate(att: BUnit, def: BUnit, counter: bool) -> int:
	if counter:
		return 0
	if att.has_effect(84):
		return 100
	var a := att.agi()
	var d := maxi(def.agi(), 1)
	if a >= 3 * d:
		return 100
	if a >= 2 * d:
		return (a - 2 * d) * 80 / d + 20
	if a >= d:
		return (a - d) * 18 / d + 2
	return 1


static func class_matchup(af: int, df: int, dmg: int) -> int:
	match af:
		0:
			if df in [16, 17]: return dmg * 5 >> 2
		1:
			if df == 4: return dmg * 3 >> 1
			if df == 3: return dmg * 3 >> 2
		2:
			if df == 4: return dmg * 5 >> 2
		3:
			if df == 1: return dmg * 2
		4:
			if df in [3, 7, 13, 20, 24]: return dmg * 3 >> 1
		5:
			if df in [9, 10, 18]: return dmg * 5 >> 2
		6:
			if df in [5, 21]: return dmg * 5 >> 2
		7:
			if df == 2: return dmg * 3 >> 1
		8:
			if df in [6, 19]: return dmg * 3 >> 1
		15:
			if df in [3, 7, 13, 16, 17, 20, 24]: return dmg * 3 >> 1
		20:
			if df in [1, 2]: return dmg * 3 >> 1
		21:
			if df == 6: return dmg * 3 >> 2
	return dmg


## mode bit0 = counterattack, bit1 = secondary target.
static func calc_damage(att: BUnit, def: BUnit, t_att: int, t_def: int, real: bool, mode: int) -> int:
	var ta := terrain_effect(att, t_att)
	var td := terrain_effect(def, t_def)
	var A := att.atk() * ta / 10
	var D := def.def() * td / 10
	var dmg: int
	if att.has_effect(85):
		dmg = att.effect_value(85)
	else:
		dmg = att.level() + 35
		if A >= D:
			dmg += (A - D) >> 1
		else:
			dmg = maxi(dmg - ((D - A) >> 1), 1)
		var af := att.family()
		var df := def.family()
		dmg = class_matchup(af, df, dmg)
		if is_ranged(af) and def.has_effect(61):
			dmg -= dmg * def.effect_value(61) / 100
		if df in CAVALRY_FAMILIES and att.has_effect(45):
			dmg += dmg * att.effect_value(45) / 100
		elif not (df in CAVALRY_FAMILIES) and not (df in VEHICLE_FAMILIES) and att.has_effect(88):
			dmg += dmg * att.effect_value(88) / 100
		if att.has_effect(89):
			var d := maxi(absi(att.pos.x - BUnit.move_origin.x), absi(att.pos.y - BUnit.move_origin.y))
			for k in d:
				dmg = dmg * 110 / 100
		if mode == 0:
			var g := att.grudge if att.has_effect(87) else 0
			dmg = dmg * (10 + g) / 10
		else:
			if mode != 2:
				dmg = dmg * 3 >> 2
			dmg = maxi(dmg, 1)
			if mode != 1:
				dmg = maxi(dmg >> 1, 1)
		if real:
			var r := rand(7)
			dmg = dmg + r - 2 if r > 2 else maxi(dmg - r, 1)
	if Game.god:
		if def.slot < 35:
			return 0
		if att.slot < 35:
			dmg *= 20
	return mini(dmg, def.hp)


# ------------------------------------------------------------------ strategies
const STRAT_POWER := {
	0: 75, 1: 90, 2: 50, 3: 70, 4: 100,      # 焦热 烈焰 炎雷 炼狱 赤链
	5: 75, 6: 90, 7: 50, 8: 70, 9: 100,      # 浊流 惊涛 潮汐 海啸 狂澜
	10: 50, 11: 75, 12: 40, 13: 60, 14: 20,  # 烟尘 飞沙 萧瑟 龙挂 飓风
	15: 70, 16: 100, 17: 60, 18: 90, 19: 120, # 落石 塌方 碎岩 地裂 移山
	20: 70, 22: 20, 33: 70, 34: 50, 35: 60, 36: 40, 38: 120, 64: 70, 65: 100,
}
const DAMAGE_STRATS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 33, 34, 35, 36, 38, 64, 65]
# hit factor numerator/denominator per strategy (table 0x43bc07)
const STRAT_HIT_9_10 := [1, 2, 6, 7, 11, 13, 14, 16, 22, 23, 25, 33]
const STRAT_HIT_4_5 := [3, 8, 18, 24, 26, 27, 29, 31, 34, 35, 37]
const STRAT_HIT_3_5 := [4, 20, 28, 30, 36]
const STRAT_HIT_1_2 := [32]
const STRAT_HIT_ALWAYS := [21, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 67]


static func strat_element(s: int) -> int:
	var e := int(Game.strategy(s).get("effect", -1))
	return e


## Terrain/weather usability of element strategies (0x420422 category part).
static func strat_terrain_ok(s: int, caster: BUnit, target_terrain: int, weather: int) -> bool:
	if s >= 20:
		return true
	if caster.has_effect(50):
		return true
	if s <= 4:
		if weather in [1, 2]:   # rain / snow
			return false
		return target_terrain in [0, 1, 2, 8, 16, 18, 19, 20, 21, 22, 23, 24]
	if s <= 9:
		return target_terrain in [7, 8, 9, 10, 13]
	if s <= 14:
		return target_terrain in [0, 1, 3, 4, 7, 8, 9, 10, 13]
	return target_terrain in [3, 4]


static func strat_hit(caster: BUnit, target: BUnit, s: int, target_terrain: int, weather: int, leader_slot := 0) -> int:
	if target.pid == 0x89:
		return 0
	if s == 21 and target.colour != 0 and target.pid < 0xd2:
		return 0      # 暗杀: named officers that are not red units are immune
	if not strat_terrain_ok(s, caster, target_terrain, weather):
		return 0
	if s in STRAT_HIT_ALWAYS:
		return 100
	if (target.status & BUnit.ST_CONFUSION) and s != 9 and s != 21:
		return 100
	var h := band_curve(caster.spirit() + caster.morale(), target.spirit() + target.morale())
	if s in STRAT_HIT_9_10:
		h = h * 9 / 10
	elif s in STRAT_HIT_4_5:
		h = h * 4 / 5
	elif s in STRAT_HIT_3_5:
		h = h * 3 / 5
	elif s in STRAT_HIT_1_2:
		h = h / 2
	elif s == 9:
		if target.slot == 0 or target.slot == leader_slot:
			return 0
		h = h / 3
	if s == 20 and caster.family() == 12:
		h = h * 3 / 2
	if caster.has_effect(52):
		h = mini(h + caster.effect_value(52), 100)
	if target.has_effect(54):
		h = sat_sub(h, target.effect_value(54))
	if target.has_effect(55):
		h = sat_sub(h, target.effect_value(55))
	return clampi(h, 0, 100)


static func strat_damage(caster: BUnit, target: BUnit, s: int, preview: bool) -> int:
	var I := caster.spirit()
	var J := target.spirit()
	var dmg := caster.level() + 45
	if I >= J:
		dmg += (I - J) / 3
	else:
		dmg = sat_sub(dmg, (J - I) / 3)
	dmg = dmg * int(STRAT_POWER.get(s, 0)) / 100
	match target.cls():
		39: dmg = dmg * 9 / 10
		42, 43, 49, 50: dmg = dmg * 11 / 10
		45: dmg = dmg * 13 / 10
	if s == 20 and caster.family() == 12:
		dmg *= 2
	var el := strat_element(s)
	if el == 0 and caster.has_effect(47):
		dmg += dmg * caster.effect_value(47) / 100
	if el == 3 and caster.has_effect(48):
		dmg += dmg * caster.effect_value(48) / 100
	if caster.pid == 22 and s >= 20 and s <= 37:
		dmg += dmg * 50 / 100
	if target.has_effect(59):
		dmg -= dmg * target.effect_value(59) / 100
	if not preview:
		var r := rand(7)
		dmg = dmg + r - 2 if r > 2 else sat_sub(dmg, r)
	dmg = maxi(dmg, 1)
	if Game.god:
		if target.slot < 35:
			return 0
		if caster.slot < 35:
			dmg *= 20
	return mini(dmg, target.mp if s == 22 else target.hp)


static func heal_amount(caster: BUnit, target: BUnit, s: int, preview: bool) -> int:
	var h := 0
	match s:
		39, 41:
			h = caster.spirit() / 8 + 60
		40, 42, 43, 67:
			h = caster.spirit() / 2 + 100
		38, 66:
			h = target.max_hp() - target.hp
		44, 45:
			h = int(Game.strategy(s).get("mp", 0))
	if s in [39, 40, 41, 42, 43, 67] and not preview and target.morale() > rand(200):
		h += rand(6) + 5
	if s in [44, 45]:
		return mini(h, target.max_mp() - target.mp)
	return mini(h, target.max_hp() - target.hp)


## BuffStep on level byte (0x43f98e).
static func buff_step(b: int, up: bool) -> int:
	if b > 3:
		return 6 if up else 3
	if b == 3:
		return 6 if up else 0
	return 3 if up else 0
