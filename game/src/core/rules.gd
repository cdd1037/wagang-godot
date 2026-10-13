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


## EXP for felling a unit of level lt at level la (0x40379b, 0x420efb, and a won duel): La < Lt ?
## min((Lt − La)·8 + 32, 200) : max(32 − (La − Lt)·4, 10), saturating. The callers double it for the commander.
static func kill_exp(la: int, lt: int) -> int:
	return mini((lt - la) * 8 + 32, 200) if la < lt else maxi(sat_sub(32, (la - lt) * 4), 10)


## EXP for a strategy that fells nothing, or on an ally (0x420efb): La < Lt ? min((Lt − La)·4 + 10, 100) :
## max(10 − (La − Lt)/2, 5).
static func strategy_exp(la: int, lt: int) -> int:
	return mini((lt - la) * 4 + 10, 100) if la < lt else maxi(sat_sub(10, (la - lt) / 2), 5)


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
## TerrainEffect (0x43f84d): the family's table; 丁天庆 (6, 【术】水军) gets 110 % on 浅滩, 沼泽 and 大河 (mod
## 0x4d39b9); then 辅助地形移动 (effect 86) at least 100 %.
static func terrain_effect(u: BUnit, terrain: int) -> int:
	var fam := Game.family(u.family())
	if fam.is_empty() or terrain < 0:
		return 10
	var arr: Array = fam["terrain_effect"]
	var t := int(arr[terrain]) if terrain < arr.size() else 10
	if u.pid == 6 and terrain in [9, 10, 13]:
		t = 11
	if u.has_effect(86):   # 辅助地形移动
		t = maxi(t, 10)
	return t


## MoveCost (0x43f7cf) of a passable terrain: 1 with effect 34 (虎类豹), and for 单雄信 (4) riding 板角墨麒麟
## (accessory 0x2f) from EV[3190] ≥ 3 (mod 0x4db478); one less (not below 1) with 辅助地形移动 (effect 86) and for
## 张公瑾 (25) as 神羿骑 (41, 飞将军, mod 0x4dc035); 1 for 丁天庆 (6, 水军) on 浅滩, 沼泽 and 大河 (mod 0x4d39e1).
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
	if u.has_effect(34):
		return 1
	var p := u.person
	if u.pid == 4 and Mem.r8(Mem.EV + 4 * 3190) >= 3 and Mem.r8(p.base + 0x34) == 0x2f:
		return 1
	var n := int(c)
	if n > 1 and (u.has_effect(86) or (u.pid == 25 and u.cls() == 41)):
		n -= 1
	if u.pid == 6 and terrain in [9, 10, 13]:
		return 1
	return n


# ------------------------------------------------------------------ physical attack
const RANGED_FAMILIES := [4, 5, 15, 23]
# movement class per defender family: 0 cavalry, 1 vehicle, 2 infantry (table 0x43f4ac)
const CAVALRY_FAMILIES := [0, 3, 7, 11, 12, 13, 15, 16, 17, 20, 24]
const VEHICLE_FAMILIES := [21, 22, 23]


static func is_ranged(fam: int) -> bool:
	return fam in RANGED_FAMILIES


static func hit_rate(att: BUnit, def: BUnit) -> int:
	if special_running():
		# 绝招 (0x4d2f90): sure hits, except 程咬金's 三板斧: 50 %, plus 2 per weapon level with 八卦宣花斧 once
		# EV[3185] ≥ 1 (4 per level from 3); a confused target is always hit
		if att.pid != 1 or (def.status & BUnit.ST_CONFUSION):
			return _shuanglei(100)
		var p1 := Game.person(1)
		var h1 := 50
		if p1.weapon == 25 and Mem.r8(0x55e1c4) >= 1:
			h1 += p1.weapon_lvl * (4 if Mem.r8(0x55e1c4) >= 3 else 2)
		return _shuanglei(h1)
	if is_ranged(att.family()) and def.has_effect(56):
		return 0
	if def.status & BUnit.ST_CONFUSION:
		return 100
	var h := band_curve(att.formation_agi(), def.formation_agi())     # 组阵 agility (0x43b5f3 / 0x43b5fe)
	if att.has_effect(39):
		h = mini(h + att.effect_value(39), 100)
	if def.has_effect(53):
		h = sat_sub(h, def.effect_value(53))
	if def.has_effect(55):
		h = _shuanglei(sat_sub(h, def.effect_value(55)))
	return clampi(h, 0, 100)


## 双雷引's hit penalty (cave 0x40762a): while [0x55ac54] == 1, 26 less, at least 1. The mod jumps to it only from
## the effect-55 branch of HitRate and from the 绝招 rates, so other hits keep their rate.
static func _shuanglei(h: int) -> int:
	if Mem.r32(BattleActions.T_SHUANGLEI) == 1:
		return h - 26 if h > 26 else 1
	return h


## A 绝招 is running ([0x4cf314], set by 0x4d3007).
static func special_running() -> bool:
	return Mem.r32(BattleStage.SPECIAL_RUNNING) == 1


static func crit_rate(att: BUnit, def: BUnit) -> int:
	if special_running():
		return 0 if att.pid in [7, 26] else 100    # 0x4d34c9: 伍天锡 and 雄阔海 never, the others always
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


## DoubleRate (0x405ce6 with the mod's caves 0x407bc8 / 0x4334f8 / 0x4075e0): 100 with effect 84, also in a
## counterattack; else none in a counterattack; 100 in 双雷引's second phase ([0x55ac54] == 2); else the curve of
## both units' 组阵 agility.
static func double_rate(att: BUnit, def: BUnit, counter: bool) -> int:
	if att.has_effect(84):
		return 100
	if counter:
		return 0
	if Mem.r32(BattleActions.T_SHUANGLEI) == 2:
		return 100
	var a := att.formation_agi()
	var d := maxi(def.formation_agi(), 1)
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


## CalcDamage (0x43bc4b). mode bit0 = counterattack, bit1 = secondary target. A and D are the 组阵 attack and
## defence (0x4d98eb, 0x4d98a2). `real` = the strike's own calculation, made after its hit roll passed: it counts
## the hit for 怀恨攻击 first.
static func calc_damage(att: BUnit, def: BUnit, t_att: int, t_def: int, real: bool, mode: int) -> int:
	if real:
		_count_hit()
	var ta := terrain_effect(att, t_att)
	var td := terrain_effect(def, t_def)
	var A := att.formation_atk() * ta / 10
	var D := def.formation_def() * td / 10
	if special_running() and att.pid == 17:
		D = 0       # 裴元庆's 尽命三锤 ignores defence (0x4d3501)
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
		if att.has_effect(89) and Mem.r8(BattleStage.PATH_LEN) != 0:
			# 冲锋 (0x4d8d95): +10 % per cell from where the player's last move started
			var w := Mem.r16(BattleStage.PATH)
			var d := maxi(absi(att.pos.x - (w & 0xff)), absi(att.pos.y - (w >> 8)))
			for k in d:
				dmg = dmg * 110 / 100
		if mode == 0:
			# 怀恨攻击 (mod 0x4d0d2e): ×(10 + the attacker's own hit counter) / 10
			var g := Mem.r8(BUnit.GRUDGE + att.slot) if att.has_effect(87) else 0
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
	if Game.god and att.slot < 35 and def.slot >= 35 and not Game.hooks.spared(def):
		dmg *= 20
	dmg = damage_post(att, def, mini(dmg, def.hp))
	if Game.god and def.slot < 35:
		return 0
	return dmg


## The index of the target the strike's loop (0x405e03) processed last ([0x55a6cc], set at 0x406173 after each).
const PREV_TARGET := 0x55a6cc


## 怀恨攻击's hit count (mod 0x4d3389 → 0x4d0cf5): +1, at most 0xff, for the slot at entry [0x55a6cc] of the
## combat object's target list. That is the previous target of the loop: the target itself on a one-target strike,
## the one before it (or the last of the previous strike, for the first) on an area strike.
static func _count_hit() -> void:
	var s := Mem.r8(Addr.TARGETS + (Mem.r32(PREV_TARGET) & 0xff))
	var c := Mem.r8(BUnit.GRUDGE + s)
	if c != 0xff:
		Mem.w8(BUnit.GRUDGE + s, c + 1)


## CalcDamage's last step (mod 0x4dc9e0), on every result, a missed hit's 0 included: 【术】舍命 (the person in
## dynamic slot 10, 王伯当) below 60 % HP deals 130 %; else 罗成 (19, 【术】智将) adds 15 % of his 精神. Both at
## most the target's HP.
static func damage_post(att: BUnit, def: BUnit, dmg: int) -> int:
	if att.pid == Skills.dyn(10) and (att.hp & 0xffff) < att.max_hp() * 60 / 100:
		return mini(dmg * 130 / 100, def.hp)
	if att.pid == 19:
		return mini(att.spirit() * 15 / 100 + dmg, def.hp)
	return dmg


# ------------------------------------------------------------------ strategies
## Strategy power in % (byte table 0x43c35c of the program image, read by 0x43bfaa at 0x43c0d0; 0 for strategies
## without damage): 焦热 75 烈焰 90 炎雷 50 炼狱 70 赤链 100, the water / wind / earth series alike, 暗算 70 暗鬼 20
## 毒烟 70 瘴雾 50 陷阱 60 濠壑 40 八阵 120 青龙 70 朱雀 100. Read from Mem, so a mod's exe_image.bin changes it.
const STRAT_POWER_TABLE := 0x43c35c


static func strat_power(s: int) -> int:
	return Mem.r8(STRAT_POWER_TABLE + s) if s >= 0 and s <= 0x41 else 0


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


## Terrain usability of element strategies (0x420422 categories 0-3; also the area filter 0x42097a).
static func strat_terrain_ok(s: int, caster: BUnit, target_terrain: int, _weather := 0) -> bool:
	if s >= 20:
		return true
	if caster.has_effect(50):
		return true
	return element_ok(s / 5, target_terrain)


## The element tests by terrain: 0 火 (0x420ab6), 1 水 (0x420b17), 2 风 (0x420b42), 3 地 (0x420b98).
static func element_ok(e: int, t: int) -> bool:
	match e:
		0:
			return t in [0, 1, 2, 8, 16, 18, 19, 20, 21, 22, 23, 24]
		1:
			return t in [7, 8, 9, 10, 13]
		2:
			return t in [0, 1, 3, 4, 7, 8, 9, 10, 13]
	return t in [3, 4]


## Strategy category per id 0..0x3d (byte table 0x42093c of the program image, the index of 0x420422's switch), which
## picks the usability check; -1 for ids ≥ 0x3e (always usable).
const STRAT_CATEGORY_TABLE := 0x42093c


static func strat_category(s: int) -> int:
	return Mem.r8(STRAT_CATEGORY_TABLE + s) if s >= 0 and s < 0x3e else -1


## A mounted family (0x43ff6e: its switch's index table 0x43ffc4 has 0 for families 0..0x18 that are), which walks
## faster (0x44201b) and acts in the AI's fifth order pass (0x44da7a).
static func mounted_family(f: int) -> bool:
	return f >= 0 and f <= 0x18 and Mem.r8(0x43ffc4 + f) == 0


## Can `caster` use strategy s on `target` (0x420422)? Element strategies (categories 0-3) need a fitting target
## terrain unless the caster has effect 50. Most other checks only bind casters the player does not command
## (AI code ≠ 7): 暗算 not at full HP, 暗鬼 not at full MP (low byte), debuffs not on a level-2 stat, 伪书/伪令
## not on a confused target, 毒烟/瘴雾 not on a poisoned one, 陷阱/濠壑 not on a paralysed one, 封印 not on a
## sealed one, heals not at full HP, 棒喝/超脱 not without a status, buffs and 聚气 not on a stat at level >= 4.
## Category 15 (开导, 诫谕, 战备): never on oneself; AI casters only on units that have moved or acted and are not
## of the player's colour. Category 17 (暗杀, 八阵, 急行, weather) goes to the mod's 0x4dbf8a, which compares the
## category with 0x15 and so always allows.
static func strat_usable(s: int, caster: BUnit, target: BUnit, target_terrain: int) -> bool:
	var cat := strat_category(s)
	if cat < 0:
		return true
	if cat <= 3:
		return strat_terrain_ok(s, caster, target_terrain)
	var ai := caster.mode != 7
	match cat:
		4: return not ai or caster.hp != caster.max_hp()
		5: return not ai or (caster.mp & 0xff) != caster.max_mp()
		6: return not ai or _code_level(s, target) != 2
		7: return not ai or not (target.status & BUnit.ST_CONFUSION)
		8: return not ai or not (target.status & BUnit.ST_POISON)
		9: return not ai or not (target.status & BUnit.ST_PARALYSIS)
		10: return not ai or not (target.status & BUnit.ST_SEAL)
		11: return not ai or target.hp != target.max_hp()
		12: return not ai or (target.mp & 0xff) != target.max_mp()
		13: return not ai or target.status != 0
		14: return not ai or _code_level(s, target) < 4
		15:
			if caster.slot == target.slot:
				return false
			if ai and not (target.flags & BUnit.F_MOVED) and not (target.flags & BUnit.F_ACTED):
				return false
			return not (ai and target.colour == 0)
		16: return not ai or _code_level(0x35, target) < 4
	return true


## The buff level a stat code looks at (0x420bbd): 0x17/0x31 爆发, 0x19/0x33 士气, 0x1b/0x35 攻击 (精神 for caster
## families), 0x1d/0x37 防御, 0x30 移动 (and the code + 1 of each pair).
static func _code_level(code: int, t: BUnit) -> int:
	match code:
		0x17, 0x18, 0x31, 0x32: return t.buff(3)
		0x19, 0x1a, 0x33, 0x34: return t.buff(4)
		0x1b, 0x1c, 0x35, 0x36: return t.buff(2 if t.family() in [8, 9, 10, 18] else 0)
		0x1d, 0x1e, 0x37, 0x38: return t.buff(1)
		0x30: return t.buff(5)
	return 3


## Can `caster` cast s at all right now (0x41fec9)? "" if so, else the original's message: fire strategies not
## in rain, heavy rain or snow (weather > 1) unless the caster has effect 50; 战备 once per turn (byte
## 0x55af00[caster], cleared at the side's phase start); 暝思 needs 兵力 >= 3.
static func strat_castable(s: int, caster: BUnit, weather: int) -> String:
	if s <= 4 and not caster.has_effect(50) and weather > 1:
		return "在恶劣天气时无法使用。"
	if s == 57 and Mem.r8(ZHANBEI_USED + caster.slot) != 0:
		return "不能再用了！"
	if s == 62 and caster.hp < 3:
		return "ＨＰ不足。"
	return ""


const ZHANBEI_USED := 0x55af00


## StratHitRate (0x43b73f). 杜如晦 (185, 【术】杜断, mod 0x4d4abc): +20 (at most 100) on the curve when he stands next
## to U on its side, where U is the target in the real roll and the AI's evaluation, and the caster in the
## player's forecast (`forecast`, 0x4404bd). 狂澜 against slot 0 or the enemy commander (BattleStage.BOSS) starts
## from 0 but still takes the modifiers after it, so it can end above 0.
static func strat_hit(caster: BUnit, target: BUnit, s: int, target_terrain: int, _weather: int, forecast := false) -> int:
	if target.pid == 0x89:
		return 0
	if s == 21 and target.colour != 0 and target.pid < 0xd2:
		return 0      # 暗杀: named officers that are not red units are immune
	if not strat_usable(s, caster, target, target_terrain):
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
		h = 0 if target.slot == 0 or target.pid == Mem.r16(BattleStage.BOSS) else h / 3
	if s == 20 and caster.family() == 12:
		h = h * 3 / 2
	if caster.has_effect(52):
		h = mini(h + caster.effect_value(52), 100)
	if Skills.beside(185, caster if forecast else target):
		h = mini(h + 20, 100)
	if target.has_effect(54):
		h = sat_sub(h, target.effect_value(54))
	if target.has_effect(55):
		h = sat_sub(h, target.effect_value(55))
	return clampi(h, 0, 100)


## The forecast's (0x4404bd) strategy kinds: HP damage (0x449bac, a table over 0..0x41), MP damage (0x449c36: 暗鬼),
## HP heal (0x449c55: 0x27-0x2b) and MP heal (0x449c7a: 0x2c-0x2d).
const STRAT_HP_DAMAGE := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 33, 34, 35, 36, 38, 64, 65]


static func strat_hp_damage(s: int) -> bool:
	return s in STRAT_HP_DAMAGE


static func strat_mp_damage(s: int) -> bool:
	return s == 22


static func strat_hp_heal(s: int) -> bool:
	return s >= 39 and s <= 43


static func strat_mp_heal(s: int) -> bool:
	return s == 44 or s == 45


static func strat_damage(caster: BUnit, target: BUnit, s: int, preview: bool) -> int:
	var I := caster.spirit()
	var J := target.spirit()
	var dmg := caster.level() + 45
	if I >= J:
		dmg += (I - J) / 3
	else:
		dmg = sat_sub(dmg, (J - I) / 3)
	dmg = dmg * strat_power(s) / 100
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
		if caster.slot < 35 and not Game.hooks.spared(target):
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
