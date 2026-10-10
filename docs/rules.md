# wg2025 (兴唐传·瓦岗山异闻录, CCZ engine mod) — data tables & battle rules

Status: WORK IN PROGRESS (updated incrementally). Confidence tags: **[C]** confirmed from code,
**[D]** confirmed from data/descriptions only, **[G]** guess.
All addresses are VAs in `wg2025/wagan.wa` (ImageBase 0x400000). `.text2` (0x4d0000+) is the mod's
hand-written extension code; it hooks the original CCZ code with `jmp`/`call` patches (284 hook sites,
list in `extract/hooks.txt`). Many hooks are character-specific special skills ("绝招/技/术").

Tools: `tools/rd_trace.py VA` (follows jmp chains across .text/.text2 — essential, functions are split),
`tools/rd_findins.py REGEX [ctx]` (instruction grep over linear sweep), `tools/rd_ptrtabs.py lo hi`
(string pointer tables), `tools/conv_data.py` (data → JSON).

JSON output: `game/assets/data/` — persons, items, classes, class_families, terrain, strategies,
shops, names, texts.

---------------------------------------------------------------------------------------------------
## 1. data.wa (Ls12, 10 entries) — loaded by 0x41b639 → per-table loaders 0x41b666.. (string "Data.wa" 0x48bb60)

| entry | records x size | in-memory | parser | content |
|---|---|---|---|---|
| e0 | 1024 x 32 | 1024 x 0x48 at `*(0x4d0048)` (mod-relocated) | 0x408be3 (getter 0x407bb3: ecx = id*0x48+[0x4d0048]) | persons |
| e1 | 104 x 25 | 104 x 0x19 at 0x4a1140 | 0x40c537 | items |
| e2 | 128 x 36 (exe loads 0x3a=58) | 58 x 0x28 at 0x4aeb68 | 0x40dcce | shops (per battle) |
| e3 | 53 x 27 | 53 x 0x1b at 0x4abfa0 | 0x4093ef (raw copy) | classes 兵种 |
| e4 | 27 x 60 | 27 x 0x3c at 0x4ae4e0 | 0x40948a (raw copy) | class families 兵种系: terrain effect + move cost |
| e5 | 73 x 70 (exe loads 0x44=68; 68-72 are "空白" blanks) | 68 x 0x46 at 0x4af4c0 | 0x40ddaf | strategies 策略 |
| e6..e9 | 512x17, 104x17, 68x17, 58x21 | not loaded | — | all records = placeholder "终端" (unused) |

### 1.1 Person record (e0, 32 bytes) [C: parser 0x408be3]
| file off | size | mem off (0x48 struct) | meaning |
|---|---|---|---|
| 0x00 | 13 | +0x08 | name GBK (12 bytes copied; effectively ≤8 bytes because +0x11.. overlaps) |
| 0x0D | u16 | +0x04 (dword) | face/portrait id |
| 0x0F | 1 | +0x02 | map sprite id (R/S 形象) [G: graphics agent] |
| 0x10 | 1 | +0x26 | unknown (0..0x19) — raw |
| 0x11 | 1 | +0x2a | party-membership byte (0 = member, 0x41a190; all persons start with 0xff). Members get the random growth jitter (0x448b09) and the HP/MP catch-up penalty on level-up (see docs/mod_patches.md B2 §E) [C 0x4d039b] |
| 0x12..0x16 | 5x1 | words +0x11,+0x13,+0x15,+0x17,+0x19 **and** bytes +0x21..+0x25 | 武艺/统制/智谋/感知/胆魄. The *word* is the battle stat (攻击/防御/精神/反应(爆发)/士气) and grows on level-up; the *byte* is the raw ability (≤100, used for growth grade) |
| 0x17 | u16 | +0x1c dword | base max HP (clamped ≤500 at load; grows ≤9999) |
| 0x19 | 1 | +0x20 | base max MP (clamped ≤250; grows ≤255; value 1 = "no MP" unit, never grows) |
| 0x1a | 1 | +0x2b | class id (0..52) |
| 0x1b | 1 | +0x2c | level (0 → 1) |
| 0x1c | 1 | +0x2d | exp (0..99; set 0xff at level ≥70) |
| 0x1d | 1 | +0x2e,+0x2f,+0x30 | weapon id, weapon level (=1 if equipped else 0xff), weapon exp (0) |
| 0x1e | 1 | +0x31,+0x32,+0x33 | armor id, level, exp |
| 0x1f | 1 | +0x34 | accessory (aux item) id; +0x35,+0x36 = 0xff |
mem +0x00 u16 = id | 0x1000. +0x27..+0x29 zeroed.

Stat order everywhere (equip stat index `s`): 0 攻击(武艺) 1 防御(统制) 2 精神(智谋) 3 反应/爆发(感知) 4 士气(胆魄)
5 HP max, 6 MP max, 7 move, 8 exp gain. (The fruit descriptions name them 武艺/智谋/统制/感知/胆魄.)

### 1.2 Item record (e1, 25 bytes) [C: parser 0x40c537]
| file | mem | meaning |
|---|---|---|
| 0x00..0x10 | +0x00 | name (16 bytes + NUL) |
| 0x11 | +0x11 | type (see below) |
| 0x12 | +0x14 | special effect id for treasures (0xff none) (0x409520) |
| 0x13 | +0x12 | price (x? gold; 255 = not sold) [G] |
| 0x14 | +0x13 | icon index |
| 0x15 | +0x15 | base value (0x41dd70) |
| 0x16 | +0x16 | special-effect value (0x41ddb0) |
| 0x17 | +0x17 | growth per item level (0x41ddf0) |
| 0x18 | +0x18 | 1 for unique items [G] |

Item category (0x40c6ea): type<14 weapon, 14..17 armor, 18..62 accessory, 63..80 consumable, ≥81 accessory.
Weapon/armor kinds (types 0..17, odd = treasure version with special effect): 0/1 近战系 (sword/mace),
2/3 突刺系 (spear), 4/5 远射系 (arrows), 6/7 劈斫系 (axe/blade), 8/9 重击系 (hammer), 10/11 计略系 (fan),
12/13 法术系 (Taoist), 14/15 铠甲, 16/17 衣服. Class may equip type t iff class.equip_raw[t] != 0 (0x4095c0).

**Effect id space** (shared by accessory `type` and treasure `special`): id 18..76 → name table 0x48bc50[id-18]
(59 names: 每回合恢复HP … 兵种上升); ids 81..90 → mod names stored after it (吸血攻击 81, 再移动 82, 连续策略 83,
主动连击 84, 固定伤害 85, 辅助地形移动 86, 怀恨攻击 87, 步兵攻击 88, 冲锋攻击 89, 连续攻击 90) [D: matches every
item description]. `has_effect(person, id)` 0x407a09 = weapon/armor that is treasure (category≤1 and type odd,
0x40c76e) with special==id, or accessory with type==id. `effect_value(person,id)` 0x407af2: treasure →
`sval` (×(lvl+1) for ids 24/25/26 辅助攻击/精神/防御, ×(lvl+4) for id 85) (0x46938f/0x4d9303); accessory → base value.

Equipment level value (0x40c674): `v = base; repeat (lvl-1) times: v = min(v+growth, 255)` (only weapon/armor).
Equipment stat bonus for stat s (0x407c0e):
```
bonus = 0
for slot in (weapon, armor):
    if item: if stat_of_type(item.type)==s: bonus += value_at_level(item, lvl)
             if treasure and stat_of_special(item.special)==s: bonus += effect_value(...)
if accessory and stat_of_type(acc.type)==s: bonus += acc.base
```
stat_of_type (0x40681a): t≤9 or t==24 →0; 10..13 or 25 →2; 14..17 or 26 →1; 27→3; 28→4; 20 or 29→5 (HP);
30→6 (MP); 32→7 (move); 31→8 (exp). stat_of_special (0x40678e): 20→5, 24→0, 25→2, 26→1, 27→3, 28→4, 29→5, 30→6, 31→8, 32→7.

### 1.3 Class record (e3, 27 bytes) [C]
| off | meaning | evidence |
|---|---|---|
| 0 | move points | 0x40727b: move = min(class[0] + equip(7), 255) (+ mod hook 0x4dc895) |
| 1 | attack-range shape code | getter 0x44f9a0 used by unit fn 0x43f8f5 [range shapes: TODO] |
| 2..6 | growth grade attack/defense/spirit/agility/morale | 0x4095a0(i) in level-up |
| 7 | HP gained per level | level-up AddStat(5) |
| 8 | MP gained per level | level-up AddStat(6) |
| 9..26 | may-equip flags per item type 0..17 | 0x4095c0 |
Class family (0x4077d0): class ≤38 → class/3 (13 families of 3 tiers), 39..52 → class−26, ≥53 → 27 (none).

### 1.4 Class family record (e4, 60 bytes) [C]
bytes 0..29 = terrain effect per terrain type in units of 10% (10 = 100%) (0x43f84d via 0x4d39a3/0x443090);
bytes 30..59 = movement cost per terrain (0xff impassable) [G: confirm in pathfinder].
Terrain types 0..29: 平原 草原 树林 荒地 山地 岩山 山崖 雪原 桥梁 浅滩 沼泽 池塘 小河 大河 栅栏 城墙 城内 城门 城池 关隘
鹿砦 村庄 兵营 民居 宝物库 云梯 火 船 祭坛 地下 (names 0x48bd40[28..57]).
Map terrain lookup 0x435991(pos): grid at (map file buffer 0x4aeb38)+0x640+x+y*W, W=[0x4b422c], H=[0x4b422d]; OOB → 0xff.

### 1.5 Strategy record (e5, 70 bytes) [C parser 0x40ddaf]
| file | mem | meaning |
|---|---|---|
| 0x00..0x09 | +0x00 | name |
| 0x0b | +0x0f | effect type → names 0x48bd40[0..27]: 0 攻击(火) 1 攻击(水) 2 攻击(地) 3 攻击(风) 4 攻击 5 吸收HP 6 吸收MP 7 能力下降 8 防御下降 9 反应下降 10 士气下降 11 能力上升 12 防御上升 13 反应上升 14 士气上升 15 混乱 16 中毒 17 麻痹 18 穷计 19 恢复HP 20 恢复MP 21 恢复状态 22 再次行动 23 气候变化 24 谜 25 兵法 26 全部上升 27 机动上升 |
| 0x0c | +0x0b | target side: 0 enemy, 1 ally, 2 none (weather) [D] |
| 0x0d | +0x0c | cast range code [TODO] |
| 0x0e | +0x0d | effect area code [TODO] |
| 0x0f | +0x0e | MP cost [D] |
| 0x10 | +0x10 | animation/element group [G] |
| 0x11..0x45 | +0x11.. | learn level per class (0 = never) (0x409580) |

### 1.6 Shop record (e2, 36 bytes) [C parser 0x40dcce]
u16 a, u16 b (unknown, raw), 16 equipment ids, 16 consumable ids (0xff = end). 128 records in file, first 58 used.

### 1.7 Other files
* **Fhua.wa**: 1946 x 200-byte GBK records (reader 0x40bf56). Index ranges (wrappers 0x40bf82..): items 0..103,
  strategies 150+i (i<68), battle names 250+i (i<58), class descriptions 350+i (i<53), person bios 922+i (i<1024),
  0x28a(650)+i (i<0x31) and 0x2bc(700)+.. quotes/skill texts.
* **person.wa** (1024 bytes, loaded to 0x55a000 by 0x4d00f8): per-person custom battle-sprite selector
  (0x406a75): v=0 → class sprite; v=1..5 → 0x35+3(v-1) + class%3; v=6 → class<40 ? 0x44 : 0x45; v≥7 → v+0x3f.
  (for graphics agent)
* **Yoyo.wa**: 104 x 1024 = 32x32 8bpp item icons (graphics).
* exe name tables (pointer tables): item groups 0x48bc20[11], item effects 0x48bc50[59], strategy effects +
  terrain names 0x48bd40[58], class families 0x48be38[27], classes 0x48bea8[53].

---------------------------------------------------------------------------------------------------
## 2. Character growth

### 2.1 Level up (0x4073b9 LevelUp(n, show); patched heavily) [C]
```
n = min(n, 255 - level)
bonus_stat = rand(5)                                  # mod: only used for person id 10 (盛彦师)
for i in 0..6:
    g = class.growth[i]                               # e3[2+i]
    if i <= 4:
        if person.fixed_growth_flag == 0 and bonus_counter == 0: g = jitter(g)   # 0x448b09
        grade = ability_grade(raw_ability[i])          # 0x4072fc: ≥100→5, ≥90→4, ≥80→3, ≥70→2, ≥60→1, else 0
        if bonus_counter > 0: bonus_counter -= 1; grade += 1      # [0x4cf2b8], set to 5 by 仙人果-like events
        g = (grade + g) >> 1
    else if person.fixed_growth_flag == 0 and person.mp_base != 1:
        g -= catchup_penalty(i)                        # 0x4d806a (only for fixed_growth_flag==0; unused by data)
    repeat n times:
        if person.id == 10 and i <= 4 and bonus_stat == i: g += 1; bonus_stat = 5
        if i <= 4 and g == 0: g = 1
        AddStat(i, g)                                  # 0x406e17
unit.hp = min(unit.hp + class.growth[5], MaxHP); unit.mp = min(unit.mp + class.growth[6], MaxMP)   # 0x4e0100
level += n; if level >= 70: exp = 0xff
```
jitter(g) (0x448b09): `if chance(50): g += 1; if chance(50): g -= 2` (unsigned byte arithmetic).
AddStat (0x406e17): i 0..4 → stat_word[i] = min(+g, 9999); 5 → hp_base = max(1, min(+g, 9999));
6 → mp_base = max(1, min(+g, 255)) unless mp_base == 1; 7/8 → mod 0x4d67d0; 10..14 → raw byte = min(+g, 120).

### 2.2 Derived stats [C]
* Person stat s (0..4): `GetStat_s = min(stat_word[s] + equip_bonus(s), 9999)` (0x407126 atk, 0x407157 def,
  0x407188 spirit, 0x4071b9 agility, 0x4071ea morale), followed by many mod per-character hooks
  (e.g. 0x4db5fd: person 8 with weapon 24 equipped… ; aura of person 0 within distance <5: ×(100+(5-d)*5)/100 for
  enemy-side units, 0x4db574) — see §9.
* MaxHP = min(hp_base + equip_bonus(5), 9999) (0x40721b); MaxMP = min(mp_base + equip_bonus(6), 255) (0x40724a).
* Move = min(class.move + equip_bonus(7), 255) (0x40727b).
* Battle-unit stat (0x43f4fe.. on unit struct) applies buff level byte unit[0x18+s] (s=0..4):
  level ≥4 → ×120/100, level ≤2 → ×80/100, 3 = normal (0x43f54c; 120/80 overridable by globals
  [0x55dee4]/[0x55deec]), clamp 9999.
* Fruits (types 70..74, 0x41d120): stat_word += value (≤9999), raw ability += value (≤100).

### 2.3 RNG [C]
`rand(n)` 0x47fb13: MSVC rand() % n (n<2 → 0). `chance(p)` 0x47fb32: rand(100) < p.
(Alternative deterministic mode when [0x55ad00]≠0: LCG s=(s*0x204fb+0x392)%0x2e7.)

---------------------------------------------------------------------------------------------------
## 3. Battle units [C]
Unit array 0x4b2c50, 0x73 (115) units × 0x24 bytes: indices 0..14 player, 15..34 friendly, 35..114 enemy
(0x44d158 compares with 0x4b2e6c/0x4b313c; 0x406710: unit[4] < 35 → player/friend side).
Fields: +0 person id (0xffff empty), +4 unit index, +6 pos (x byte, y byte), +0xc side/state, +0x10 HP,
+0x14 MP, +0x18..+0x1c buff levels (atk, def, spirit, agility, morale; 3 = neutral).

---------------------------------------------------------------------------------------------------
## 4. Physical attack (0x405e03 → CalcDamage 0x43bc4b) [C, partial]
```
CalcDamage(att_unit, def_person, real, mode):
  tA = terrain_effect(att) ; tD = terrain_effect(def)        # e4[family][terrain], 0x43f84d
      # (effect 86 辅助地形移动: tX = max(tX,10); person 6 on terrain 9/10/13: 11)
  A = Atk(att) * tA / 10        # Atk = 0x4d98eb: BU::Atk (effect 54 能力校准: max(atk,spirit));
                                #   classes 46/47: +15% per adjacent same-family ally
  D = Def(def) * tD / 10        # 0x4d98a2: BU::Def; classes 39/46: +15% per adjacent same-family ally
  if real and not can_attack(att, def): return 0
  if has_effect(att, 85 固定伤害): dmg = effect_value(att, 85)
  else:
      dmg = level(att) + 35
      if A >= D: dmg += (A - D) >> 1
      else:      dmg = max(dmg - ((D - A) >> 1), 1)
      dmg = class_matchup(att_family, def_family, dmg)     # jump table 0x4d2140 [TODO]
      ... effect 45 骑兵攻击 / 88 步兵攻击 bonuses (+effect_value %) vs table 0x43f4ac[def_family] ==0 / ==2
      if has_effect(att, 89 冲锋攻击): dmg = 0x4d8d95(dmg, att, def)        [TODO]
      if mode == 0: dmg = dmg * (10 + (has_effect(att,87 怀恨攻击) ? grudge[att] : 0)) / 10
      else:
          if mode != 2: dmg = dmg*3 >> 2          # counter-attack
          dmg = max(dmg,1)
          if mode != 1: dmg = max(dmg >> 1, 1)    # secondary (splash/penetrate) target
      if real: r = rand(7); dmg = r > 2 ? dmg + r - 2 : max(dmg - r, 1)
  dmg = min(dmg, def.HP)
  (mod post 0x4dc9e0: person with effect-like flag 10 and HP<60% → ×1.3; person 0x13 adds 15% of X)
```
mode = (counter ? 1 : 0) + (not first target ? 2 : 0) (0x405e78..0x405ea7).
Critical (0x405ef8): `if chance(crit_rate(att)) : dmg = dmg*3/2` (0x405f38), crit_rate = 0x405d69 [TODO];
if target has effect 57 化解攻击效果 the critical damage becomes 0.

### 4.1 Class matchup (兵种相克) — mod jump table 0x4d2140[attacker_family] (applied to dmg after base) [C]
| attacker family | vs defender family | factor |
|---|---|---|
| 0 英雄 | 16 雄师, 17 统军 | ×5/4 |
| 1 刀兵 | 4 弓兵 ×3/2 ; 3 轻骑兵 ×3/4 | |
| 2 枪兵 | 4 弓兵 | ×5/4 |
| 3 轻骑兵 | 1 刀兵 | ×2 |
| 4 弓兵 (ranged) | 3 轻骑兵, 7 重骑兵, 13 燕山骑兵, 20 狄骑兵, 24 玄骑兵 | ×3/2 |
| 5 间谍 (ranged) | 9 谋士, 10 道士, 18 国师 | ×5/4 |
| 6 格斗兵 | 5 间谍, 21 战车 | ×5/4 |
| 7 重骑兵 | 2 枪兵 | ×3/2 |
| 8 僧兵 | 6 格斗兵, 19 力士 | ×3/2 |
| 12 锤骑兵 | 16, 17 | ×1 (patched out) |
| 15 弓骑兵 (ranged) | 3, 7, 13, 16, 17, 20, 24 | ×3/2 |
| 20 狄骑兵 | 1 刀兵, 2 枪兵 | ×3/2 |
| 21 战车 | 6 格斗兵 | ×3/4 |
| others | — | ×1 |
All multiplications are `dmg*k >> n` on unsigned ints. For ranged attacker families (4 弓兵, 5 间谍, 15 弓骑兵,
23 箭车 — table 0x44007a) the defender's effect 61 减轻远距损伤 (护背旗/护心镜) then applies:
`dmg -= dmg * value / 100` (0x43bddf).
Then (0x43be8a) movement-class table 0x43f4ac[def_family] (0 = cavalry: 英雄 轻骑 重骑 双刃 锤骑 燕山 弓骑 雄师 统军 狄骑 玄骑;
2 = infantry; 1 = vehicles 战车 辎重 箭车): cavalry target & attacker effect 45 骑兵攻击 → `dmg += dmg*val/100`;
infantry target & effect 88 步兵攻击 → same. Effect 89 冲锋攻击 (0x4d8d95): `d = max(|dx|,|dy|)` between
current position and the position at the start of the move ([0x4cfc00]); repeat d times `dmg = dmg*110/100`.

### 4.2 Physical hit rate (0x43b4b0 kind=1 → chance(HitRate) ; HitRate 0x43b50d) [C]
```
if attack_is_ranged(att_family) and has_effect(def, 56 防御远距攻击): return 0      # 0x44005d / table 0x44007a
if def.status & 8 (混乱/confused): return 100
a = Agi(att); d = Agi(def)          # 0x4d9818 = BU::Agi (+15%/adjacent same-family ally for classes 18/19/20)
if   a >= 2*d: h = 100
elif a >= d:   h = (a-d)*10/d + 90
elif a >= d/2: h = (a - d/2)*30/(d/2) + 60
else:          h = sat_sub(a, d/3)*30/(d/3) + 30          # sat_sub(x,y) = x>y ? x-y : 0   (0x47fa9e)
if has_effect(att, 39 辅助攻击命中): h = min(h + val, 100)
if has_effect(def, 53 辅助攻击防御 shield): h = sat_sub(h, val)
if has_effect(def, 55 辅助全防御):        h = sat_sub(h, val)
if [0x55ac54]==1 (one-shot mod flag): h = h > 26 ? h-26 : 1
```
(Mod: while a 绝招 runs ([0x4cf314], set by 0x4d3007): hit 100 except person 1 → 50 + weapon bonus; see docs/mod_patches.md.)

### 4.3 Critical hit (rate 0x405d69, applied 0x405ef8) [C]
```
m = Morale(att); n = Morale(def)                      # BU::Morale 0x43f67f
if has_effect(att, 41 致命一击攻击): rate = 100
elif m >= 3n: 100
elif m >= 2n: (m - 2n)*80/n + 20
elif m >= n:  (m - n)*18/n + 2
else: 1
crit: dmg = dmg*3/2 ; (first target crit → all secondary targets crit too, ctx+0x604)
target with effect 57 化解攻击效果 takes 0 from a critical (and from the 2nd strike of a double attack)
```

### 4.4 Attack sequence, double attack & counterattack [C]
Attack(att, def) 0x4064f1 (context object, +0x608 = strike counter):
```
setup targets (0x4061fc)  — target list ctx[0x10..] (first = def, more for area/penetrate weapons)
for strike in 0..1:
    compute damage for all targets (0x405e03: hit check, CalcDamage, crit) ; apply (0x405889 → effects §6)
    second = DoubleCheck()       # 0x406181
    if not second: break
Counter (0x40639a)
```
DoubleCheck: only after the first strike; `chance(DoubleRate)` (or forced by mod flags [0x55ac68]/[0x55ac54]==2).
DoubleRate (0x405ce6): `a = Agi(att), d = Agi(def)`; effect 84 主动连击 → 100 (the mod also lets it double in a
counterattack: 0x40761e skips DoubleCheck's counter test); during a counterattack → 0;
`a >= 3d → 100; a >= 2d → (a-2d)*80/d + 20; a >= d → (a-d)*18/d + 2; else 1`.
Counter (0x40639a), depth = [0x492e04]:
```
if depth > 1: stop
if depth == 1 and not has_effect(original attacker, 40 反击后反击): stop
counter if def.HP > 0 and not (def.status & 8 confused) and not has_effect(att, 44 无反击攻击)
           and att.pos in attack_range(def)        # 0x436586 with def's class range code (0x43f8be)
then depth += 1; Attack(def, att)                    # damage mode has counter bit → ×3/4, no double
```

---------------------------------------------------------------------------------------------------
## 5. Strategies (策略)

### 5.1 Dispatcher (0x425627, switch on strategy id via byte table 0x425a3f / jump table 0x4259c3) [C]
| ids | handler | notes (ctx+0x254 = display code) |
|---|---|---|
| 0-13, 15-21, 65 | 0x42313e damage | fire/water/wind/earth, 暗算 (吸收HP), 暗杀, 朱雀 |
| 22 暗鬼 | 0x42313e (code 0x50) | MP damage (capped by target MP) |
| 14 飓风 | 0x42423a | special wind |
| 23-30 | 0x42335b(0) | debuffs: 0x62 反应↓ (23,24), 0x64 士气↓ (25,26), 0x60 能力↓ (27,28), 0x61 防御↓ (29,30) |
| 31-37 | 0x423549(0) | status: 0x71 混乱 (31,32), 0x70 中毒 (33,34), 0x72 麻痹 (35,36), 0x74 穷计/封 (37) |
| 38 八阵 | 0x423edc | |
| 39-43 / 44-45 | 0x42378d | heal HP (0x80) / MP (0x90) |
| 46-47 | 0x423549(1) | cure status (0xbf) |
| 48-56 | 0x42335b(1) | buffs: 0xa8 机动 (48), 0xa2 反应 (49,50), 0xa4 士气 (51,52), 0xa0 能力 (53,54), 0xa1 防御 (55,56) |
| 57 战备 | 0x423960 | re-act |
| 58-60 | 0x423b2f | weather (阴雨/晴明/叆叇) |
| 61 聚气, 63 豪气 | 0x423cc0 | |
| 62 暝思 | 0x423d6c | |
| 64 青龙 | 0x424e9e | 66 玄武 0x424810, 67 白虎 0x424513 |

### 5.2 Strategy damage (0x43bfaa(caster, target, s, preview)) [C]
"Damage strategy" set (0x449bac/0x449c36): ids 0-20, 22, 33-36, 38, 64, 65.
```
if not preview and not chance(StratHit(caster,target,s)): return 0
if not 0x420422(s, caster, target): return 0                  # usability, §5.6
I = Spirit(caster); J = Spirit(target)          # 0x4e2171 = 0x4db078(1): BU::Int (effect 54 能力校准 → max(atk,int))
dmg = level(caster) + 45
if I >= J: dmg += (I - J)/3 else dmg = sat_sub(dmg, (J - I)/3)
dmg = dmg * power[s] / 100                       # table 0x43c35c (below)
target class 39 燕云骑 ×9/10; 42 雄师, 43 统军, 49 箭车, 50 玄术骑 ×11/10; 45 力士 ×13/10   (0x43c412)
if s == 20 and family(caster) == 12: dmg *= 2
if effect_type(s) == 0 (fire) and has_effect(caster, 47 辅助火类策略): dmg += dmg*val/100
if effect_type(s) == 3 (wind) and has_effect(caster, 48 辅助风类策略): dmg += dmg*val/100
if caster.person == 22 (徐茂功) and 20 <= s <= 37: dmg += dmg*50/100
if has_effect(target, 59 减轻策略损伤): dmg -= dmg*val/100
if not preview: r = rand(7); dmg = r > 2 ? dmg + r - 2 : sat_sub(dmg, r)
dmg = max(dmg, 1); dmg = min(dmg, s == 22 ? target.MP : target.HP)
```
暗杀 (21): no damage; on hit marks target for instant defeat ([0x569f00+idx] = 2).
power[s] (%): 焦热75 烈焰90 炎雷50 炼狱70 赤链100 浊流75 惊涛90 潮汐50 海啸70 狂澜100 烟尘50 飞沙75 萧瑟40 龙挂60 飓风20
落石70 塌方100 碎岩60 地裂90 移山120 暗算70 暗鬼20 毒烟70 瘴雾50 陷阱60 濠壑40 八阵120 青龙70 朱雀100 (others 0).

### 5.3 Strategy hit rate (0x43b4b0 kind≠1 → chance(0x43b73f)) [C]
```
if target.person == 0x89: 0
if s == 21 暗杀 and target.unit[5] != 0 and target.person < 0xd2: 0
if not 0x420422(s, caster, target): 0        # full usability check, §5.6 (AI casters: e.g. 伪书 on a confused target)
if target.status & 8 and s not in (9, 21): 100
A = Spirit(caster) + Morale(caster); B = Spirit(target) + Morale(target)
h = same 4-band curve as physical hit (A vs B): 100 / (A-B)*10/B+90 / (A-B/2)*30/(B/2)+60 / sat_sub(A,B/3)*30/(B/3)+30
per-strategy factor (table 0x43bc07 → 0x43bb6b):
   ×1   : 焦热 浊流 烟尘 萧瑟 落石 碎岩 移山 阴雨 晴明 叆叇 聚气 暝思 豪气 青龙 朱雀 玄武
   ×9/10: 烈焰 炎雷 惊涛 潮汐 飞沙 龙挂 飓风 塌方 暗鬼 流言 说词 毒烟
   ×4/5 : 炼狱 海啸 地裂 谎报 乡歌 大喝 骂阵 伪书 瘴雾 陷阱 封印
   ×3/5 : 赤链 暗算 威慑 挑拨 濠壑          ×1/2: 伪令
   狂澜 : 0 vs unit index 0 or the army leader, else ×1/3
   =100 (no further modifiers): 暗杀 八阵 all heals/cures/buffs 战备 白虎
if s == 20 and family(caster) == 12: h = h*3/2
if has_effect(caster, 52 辅助策略命中): h = min(h + val, 100)
if mod check 0x4d4a60(0xb9, target): h = min(h + 20, 100)
if has_effect(target, 54): h = sat_sub(h, val)      # id 54 was 辅助策略防御 in CCZ; mod renamed it 能力校准 (阵谱) but this check remains
if has_effect(target, 55 辅助全防御): h = sat_sub(h, val)
h = min(h, 100)
```

### 5.4 Strategy result application (0x4224a8; per-target code byte ctx+0x255+i, table 0x422e14/0x422dc8) [C]
Buff/debuff ops go through 0x420cb2(op, unit) → BuffStep(stat, up) 0x43f98e; status ops through 0x420e25(op, unit).
| code | strategies | effect |
|---|---|---|
| 0x60 | 大喝 威慑 (能力下降) | BuffStep(atk, down) — or spirit instead if target family ∈ "magic" set (0x43ffed: families 8..20 table 0x440050) |
| 0x61 | 骂阵 挑拨 | BuffStep(def, down) |
| 0x62 | 流言 谎报 | BuffStep(agility, down) |
| 0x64 | 说词 乡歌 | BuffStep(morale, down) |
| 0x6f | (unused id) | all four down |
| 0x70 | 毒烟 瘴雾 | status |= 0x10 中毒 (only if target survives the damage) |
| 0x71 | 伪书 伪令 | status |= 0x08 混乱 |
| 0x72 | 陷阱 濠壑 | status |= 0x02 麻痹 (only if survives) |
| 0x74 | 封印 | status |= 0x04 穷计/封 (cannot use strategies) |
| 0xa0 | 激励 点兵 (能力上升) | BuffStep(atk & spirit, up) for class 50 or classes 24..26 (mod 0x4d8985), else spirit if magic family else atk |
| 0xa1 | 顽强 团结 | BuffStep(def, up) |
| 0xa2 | 教练 军训 | BuffStep(agility, up) |
| 0xa4 | 祈祷 礼赞 | BuffStep(morale, up) |
| 0xa8 | 急行 | BuffStep(move, up) (unit[0x1d]) |
| 0xaf | 豪气 | agility, morale, atk, def up |
| 0xb8 | 战备 | unit[0xd] &= ~6 (clears "moved/acted" flags → may act again) |
| 0xbf | 棒喝 超脱 | status &= ~0x7e (cure all) |
BuffStep(i, up) on level byte b = unit[0x18+i] (i: 0 atk 1 def 2 spirit 3 agility 4 morale 5 move):
`b > 3: b = up ? 6 : 3 ; b == 3: b = up ? 6 : 0 ; b < 3: b = up ? 3 : 0`. Levels ≥4 → ×1.2, ≤2 → ×0.8 (§2.2);
the level drifts back toward 3 each turn [G: decay at turn start, see §7].
Status bits unit[0x1e]: 0x02 麻痹 (paralysed: cannot move), 0x04 封/穷计 (no strategies), 0x08 混乱 (confused:
auto-hit by physical & most strategies, no counter), 0x10 中毒 (poison), 0x20/0x40 other (0x40 set by class-38 震天骑
attacks, 60%), 0x01 ?.
Physical-attack on-hit effects (0x405889, after damage, if target alive): effect 35 混乱攻击 → 混乱 60%;
class 50 (玄术骑) attacker → 混乱 60%; effect 36 中毒攻击 → 中毒 100%; class 45 (力士) → 麻痹 60%; effect 37
随机属性攻击 → random status (0x4d0c6e); class 38 (震天骑) → 0x40 60%; effect 34 恶移麻痹 → 麻痹 60%;
effect 38 封杀策略 → 封 100%; person 204 (0xcc) special → 中毒.

### 5.5 Heal strategies (0x42378d → amount 0x43c548(target; s, caster, preview)) [C]
```
39 医疗, 41 补给:            h = Spirit(caster)/8 + 60
40 痊愈, 42 犒劳, 43 救护, 67 白虎: h = Spirit(caster)/2 + 100
   (both: if not preview and Morale(target) > rand(200): h += rand(6) + 5)
38 八阵, 66 玄武:             h = MaxHP - HP   (full; used by their random "heal" outcome, see below)
44 开导, 45 诫谕 (MP):        h = strategy.mp_cost  (field +0xe)
h = min(h, MaxMP - MP) for 44/45, else min(h, MaxHP - HP)
```
Targets/area come from 0x45533d(caster, ctx+0x2c9, kind, s) (kind 2 = enemies, 3 = allies) [range/area tables TODO].

### 5.5a 八阵 (38, 0x423edc) and 玄武 (66, 0x424810) [C]
No hit roll of their own. 八阵's targets are the opposite units in its area; 玄武's are **all units on the map**, either
side (its loop over units 0..114 with state 2 only asks 0x42097a, which passes every strategy ≥ 0x14). Each target
draws one outcome (rand 0x47fb13 → mod 0x4d966f):
| 八阵 rand(8) | 玄武 rand(7) | outcome |
|---|---|---|
| 0 | — | damage StratDamage(caster, target, 八阵) (power 120, includes its own hit roll, 100 for 八阵) |
| 1 | 0 | 混乱 (code 0x71) |
| 2 | 1 | 麻痹 (0x72) |
| 3 | 2 | 封 (0x74) |
| 4 | 3 | 中毒 (0x70); 八阵 also deals StratDamage as 毒烟 (33, its hit roll may miss → 0) |
| 5 | 4 | 0x6f: 0x420cb2(0x17 爆发↓, 0x19 士气↓, 0x1b 攻击↓/精神↓ for caster families, 0x1d 防御↓) |
| 6 | 5 | 0xaf: 0x420cb2(0x31 爆发↑, 0x33 士气↑, 0x35, 0x37 防御↑) — same as 豪气 |
| 7 | 6 | 兵力 to full (0x43c548: MaxHP − HP) |
八阵 applies through 0x4224a8: a status only sticks when the stored damage is below the target's HP. 0x35 is the mod
routine 0x4d8985: classes 24–26 and 50 raise both 攻击 and 精神, others 精神 for caster families, else 攻击 (also used by
聚气 61 = code 0xa0 and 豪气 63 = 0xaf, which target the caster itself, 0x423cc0).
EXP per target (0x420efb, strategy kind byte +0xb = 0): 八阵 is in the damage set (0x449bac), so the kill formula applies
when the stored amount (damage, or the negated heal as an unsigned number) is not below the target's HP; 玄武 gets the
small formula. The caster gains the largest value × EXP multiplier.

### 5.6 Strategy usability (0x420422(s, caster, target, show_msg)) and castability (0x41fec9) [C]
0x420422: strategies ≥ 0x3e are always usable; otherwise the category table 0x42093c[s] picks a case of the jump table
0x4208f4. "AI" below means the caster's AI code ≠ 7 (a unit the player does not command); for a player-commanded
caster only the terrain checks and the self check apply.
| cat | strategies | fails when |
|---|---|---|
| 0–3 | fire 0-4, water 5-9, wind 10-14, earth 15-19 | the target's terrain does not fit (0x420ab6 / 0x420b17 / 0x420b42 / 0x420b98), unless the caster has effect 50 (左思兵法). Message 不能在这里使用。 |
| 4 | 暗算 20 | AI and caster HP == MaxHP |
| 5 | 暗鬼 22 | AI and caster MP (low byte, 0x472840) == MaxMP |
| 6 | debuffs 23-30 | AI and the target's level of that stat (0x420bbd: 爆发, 士气, 攻击/精神 by family, 防御) is exactly 2 |
| 7 | 伪书 伪令 31-32 | AI and the target is confused (0x08) |
| 8 | 毒烟 瘴雾 33-34 | AI and the target is poisoned (0x10) |
| 9 | 陷阱 濠壑 35-36 | AI and the target is paralysed (0x02) |
| 10 | 封印 37 | AI and the target is sealed (0x04) |
| 11 | heals 39-43 | AI and the target's HP == MaxHP |
| 12 | (none) | AI and the target's MP (low byte) == MaxMP |
| 13 | 棒喝 超脱 46-47 | AI and the target has no status |
| 14 | buffs 49-56 | AI and the target's level of that stat is ≥ 4 |
| 15 | 开导 诫谕 44-45, 战备 57 | the target is the caster (不能对自己使用。); AI: the target has neither moved nor acted, or its colour is 0 |
| 16 | 聚气 61 | AI and the target's 攻击/精神 level is ≥ 4 |
| 17 | 暗杀 21, 八阵 38, 急行 48, weather 58-60 | mod 0x4dbf8a compares the category (not s) with 0x15, so it never fails |
Callers: the AI's Usable (0x4390ef = 0x41fec9 && 0x420422 && side test); every strategy handler for the unit on the
target cell (if it fails nothing happens; other units in the area only pass the element terrain filter 0x42097a of
0x425349); StratHitRate 0x43b73f (unusable → 0 %) and StratDamage 0x43bfaa (→ 0) for each target. Heals (0x42378d)
roll no hit.
0x41fec9(s, caster, show) (AI Usable and the cast dispatcher 0x425627): fire 0-4 fails when the weather (0x44a1d4,
table 0x48e100) is > 1 (雨 暴雨 雪) unless the caster has effect 50 (在恶劣天气时无法使用。); 战备 fails when byte
0x55af00[caster] is set (不能再用了！) — 0x423960 sets it on a cast, the side's phase start clears it (0x44ed93 for
units 0..34, 0x44e851 for 35..114); 暝思 62 fails when the caster's HP < 3 (ＨＰ不足。).

---------------------------------------------------------------------------------------------------
## 6. Range and area shapes [C — obtained by emulating the exe code with tools/rd_emu.py]
### 6.1 Range codes (attack range = class byte 1 via 0x43f8be; strategy cast range = strategy byte 0x0d → ctx+0x2c9)
Builder 0x436586(pos, code, flags, mode) — switch 0x4379c4 (16 codes); flag bit1 adds the origin (used for
ally-targeting strategies, 0x45540d). Exported as `shapes.json["range"]`.
| code | cells (relative to attacker) |
|---|---|
| 0 | manhattan 1 (4) | 
| 1 | chebyshev 1 (8) |
| 2 | manhattan = 2 (8) |
| 3 | manhattan 2..3 (20) |
| 4 | manhattan 2..4 (36) |
| 5 | straight lines of length 1..2 (8) |
| 6 | manhattan 1..2 (12) |
| 7 | manhattan 3..4 (28) |
| 8 | manhattan 3..5 (48) |
| 9 | manhattan = 3 (12) |
| 10 | whole map |
| 11 | none (cannot attack); strategies with 11 are self-cast |
| 12 | manhattan 1..3 (24) |
| 13 | manhattan 1..4 (40) |
| 14 | (±3, -1..1) and (-1..1, ±3) (12) |
| 15 | chebyshev-3 ring minus the 4 corners (20) |
Unit attack-range overrides (0x43f8be): status bit 0x20 → 11 (cannot attack); while a 绝招 runs ([0x4cf314]): persons
5,14,19,26 → 0, person 8 → 6; otherwise person 0xcc → 12 and person 25 with class 41 → 4; effect 42 远距攻击 → code = effect value
(金纂提炉枪 → 6, 铉铁枪头 → 1); effect 21 强化间谍 with class 15/16/17 → 7/8/8; else class.attack_range.

### 6.2 Area codes (strategy byte 0x0e → ctx+0x2ca; 0x435d6c switch 0x436388). Origin = target (always affected).
0 target only · 1 +adjacent 4 · 2 +8 surrounding · 3 +8 surrounding · 4/6/5/12 a line continuing beyond the target
directly away from the caster of length 1/2/5/to-map-edge · 7 +8 surrounding · 8 9x9 square · 9 5x5 square ·
10 "sweep": only if target is 8-adjacent to caster, adds the 2 cells next to the target perpendicular to the
caster→target direction (for a diagonal: the 2 cells adjacent to both) · 11 the 8 cells around the caster.
Units are filtered by side (0 = opposite side to the caster, 1 = same side, 2 = any).
Mod (0x528200): if the caster is one of 4 special persons ([0x55ee44..50]) area 0→1, 1→2, 2→3, others→6.
MP cost getter 0x425ad0: `mp = strategy.mp; if [0x4d0d61] (second cast of 连续策略) mp *= 2`.

---------------------------------------------------------------------------------------------------
## 7. Movement [C]
### 7.1 Move cost per terrain (unit method 0x43f7cf(terrain))
```
fam = family(unit); if fam >= 27: impassable
c = families[fam].move_cost[terrain]        # e4 bytes 30..59; 0xff = impassable
if c == 0xff: impassable
if has_effect(person, 34 恶移麻痹 (虎类豹)): return 1        # "走山川如覆平地"
(mod: option [0x55e1d8] >= 3 and person 4 with accessory 47 → 1)
if c > 1 and (has_effect(person, 86 辅助地形移动 黄骠马) or (person 25 and class 41)): c -= 1
if person 6 and terrain in (9 浅滩, 10 沼泽, 13 大河): c = 1
```
### 7.2 Reachable cells (0x438308(start, move_points, flags, ..., zoc)) — uniform-cost flood fill
```
cost[start] = 0; frontier level L = 0
repeat while something changed:
  for every cell with cost == L:
     if cell != start and zoc_enabled and InZOC(cell): continue      # may enter a ZOC cell but not leave it
     for the 4 orthogonal neighbours nb (inside map) with cost[nb] unset:
        mc = MoveCost(terrain(nb)); if impassable or L + mc > move_points: skip
        if nb holds a unit of the other side (player+friend vs enemy): skip
            (exception: unit flag 0x80 in unit[0xd] and zoc disabled)
        cost[nb] = L + mc            # allied units can be passed through (not stopped on)
  L = smallest cost > L
```
InZOC(cell) (0x437d59): false if mover has effect 33 突击移动 (万里烟云兽); else true iff one of the 4 orthogonal
neighbours holds a unit of the opposite side. Move points = class.move + equip(7) (+ buff: unit[0x1d] move buff
level from 急行 [G: +1 when ≥4? see 0x40727b mod hook 0x4dc895]). Paralysed units (status 0x02) cannot move [G].

---------------------------------------------------------------------------------------------------
## 8. Experience & equipment levels [C]
exp_mult(person) = 100 + equip_bonus(8) (0x4072bd; 金鈚令 → 150). La = actor level, Lt = target level.
### 8.1 Physical attack (0x40379b per target; only if ctx+0x600 set [G: actor is player-controlled])
```
if damage >= target.HP (kill):
    e = La < Lt ? min((Lt-La)*8 + 32, 200) : max(sat_sub(32, (La-Lt)*4), 10)
    if target is the enemy commander (0x492f90.leader): e *= 2
else:
    e = La < Lt ? min((Lt-La)*2 + 8, 100) : max(sat_sub(8, La-Lt), 1)
e = e * exp_mult / 100
```
The attack sequence awards max(e over all targets & strikes) once (ctx+0x428), applied after the sequence (0x405c6c).
### 8.2 Strategies (0x420efb; ctx+0x4a8 must be set)
```
target side enemy & damage strategy (not 22): kill → as 8.1 kill formula (×2 vs commander);
                                            no kill → La<Lt ? min((Lt-La)*4+10,100) : max(sat_sub(10,(La-Lt)/2),5)
enemy non-damage / ally target: La<Lt ? min((Lt-La)*4+10,100) : max(sat_sub(10,(La-Lt)/2),5)
weather (target side 2): 20
e = e * exp_mult / 100 ; awarded = max over targets
```
### 8.3 Level up (SetExp 0x408950(total))
`if level >= 70: no gain. while total >= 100: LevelUp(1) (§2.1); total -= 100. exp = level >= 70 ? 0xff : total.`
(mod option [0x55e1c0]==4 gives the +1 grade bonus counter (=5) on every level-up.)
### 8.4 Weapon / armor exp
Weapon (0x40397d, attacker): `(damage>0 ? (La > Lt ? 2 : 3) : 1) * exp_mult/100`; armor (0x403a85, defender, only
player-side units 0x43ff54): `(damage>0 ? (La < Lt ? 3 : 4) : 1) * exp_mult(defender)/100`; mod: if the item is already
level ≥ 9 the gain is 1. Item level-up (0x4082d6(slot, gain)):
```
threshold = 100 (+50 if treasure (odd weapon/armor type)) (+100 more if treasure at level 9)
max_level = treasure ? 10 : 3
total = item_exp + gain
while total >= threshold and level < max_level: level += 1; total -= threshold   # "武器等级上升！"
item_exp = level >= max_level ? 0xff : total
```
Item value at level L: base + growth*(L-1) (≤255) (§1.2). Treasure special-effect value: sval×(L+1) for ids 24-26, ×(L+4) for id 85.
### 8.5 吸血攻击 (effect 81, 0x4d7e01): after the attack sequence, attacker HP = min(HP + total_damage/2, MaxHP).

---------------------------------------------------------------------------------------------------
## 9. Turn structure, status ailments and per-turn effects [C]
### 9.1 Phase order (0x44ed93 player phase → 0x44e851 friend & enemy phases)
```
round n:
  PLAYER PHASE (ctx[0x10]=0): turn-start events (0x44ac28(turn), 0x44c601)
      for units 0..34 (player 0-14 AND friendly 15-34): StatusRecovery (0x43c7d6), BuffDecay (0x43c975)
      Poison(side 0) (0x44df61); Regen (0x43cddd) for units 0..34
      player input loop (0x44e0d9)
  FRIEND PHASE (ctx[0x10]=1): events; AI-controlled units among 0..34 act (0x43ad1c)
  ENEMY PHASE (ctx[0x10]=2): events; for units 35..114: StatusRecovery, BuffDecay; Poison(side 1); Regen;
      enemy AI units act
```
AI acting order (0x44e9ce..): outer counter k = 0..114; each unit (on map, unit[0xc]==2) whose byte unit[0xb] == k,
whose unit[0xe] != 7 and with neither flag 4 nor flag 2 in unit[0xd] (already acted) acts; after any action the scan
restarts at k = 0. [G: unit[0xb] = action-order/AI group byte set by the scenario script].
Unit flag byte unit[0xd]: bit 2 / bit 4 = has moved / has acted (cleared by 战备, §5.4), bit 0x80 = may pass enemies.

### 9.2 Status ailments (unit[0x1e])
| bit | name | effect | cured by item |
|---|---|---|---|
| 0x02 | 麻 paralysis | cannot move: MovePoints 0 (0x43f74f); attack still allowed | 活血解毒膏 (clears 0x12) |
| 0x04 | 穷/封 seal | cannot use strategies | 宁神镇气散 (clears 0x24) |
| 0x08 | 乱 confusion | physical & most strategy hits auto-hit it (100%), it cannot counter, AI-controlled [G] | 安魂醒脑丸 (clears 0x48) |
| 0x10 | 毒 poison | phase start: HP -= MaxHP/5 (player/friend units and generic enemies with person id ≥ 210) or MaxHP/10 (named enemies, id < 210); min 1; never kills (leaves 1 HP) | 活血解毒膏 |
| 0x20 | 怯 fear | attack range becomes 11 (cannot attack) | 宁神镇气散 |
| 0x40 | 迷 lost | ("正处于迷失状态") [G: random/limited control] | 安魂醒脑丸 |
灵宝万能丹 / 棒喝 / 超脱 clear 0x7e (all).
Recovery at own phase start (0x43c7d6), r = 100 if has_effect(20 每回合恢复状态 夜明盔) else the person's raw 胆魄 byte:
`麻, 穷, 毒: chance(r)`; `怯, 迷: r==100 or chance(r - r/10)`; `乱: r==100 or chance(max(sat_sub(r,15), 10))`.
(mod: units with skill check 0x4d4a60(0x17) are cured of everything.)
### 9.3 Buff decay (0x43c975) for each of the 6 buff bytes (atk, def, spirit, agility, morale, move)
`b >= 5: b -= 1 ; b <= 1: b += 1 ; b == 4: if chance(q): b = 3 ; b == 2: if chance(r): b = 3`
with q = (raw 胆魄 > 50 ? 10 : sat_sub(60, 胆魄)) and r as in 9.2. So a buff lasts ≥2 turns, a debuff ≥2 turns.
### 9.4 Regeneration (0x43cddd, at own phase start, alive units)
```
heal = 0
if terrain in {城池 25%, 关隘 20%, 鹿砦 20%, 村庄 15%, 兵营 20%}: heal = MaxHP * pct / 100   (0x4351c0/0x43d0b1)
if has_effect(18 每回合恢复HP): heal += MaxHP / value          (紫霞神绶 value 5 → +20%)
heal = min(heal, MaxHP - HP)
mp = (has_effect(19 每回合恢复MP) ? value : 0) + mod 0x4d7eb1 (effect 82)  ; mp = min(mp, MaxMP - MP)
player-side only (0x43ff54): effect 64 → +value*exp_mult/100 character exp; effect 22 → weapon exp; effect 23 → armor exp
```


---------------------------------------------------------------------------------------------------
## 10. Battle script ops & AI [C unless marked G]
Notation: `R` = script reader object @0x492f90; `ctx` = battle object 0x4b3d08 (`this` of the battle module);
`U[i]` = battle unit i (0x24 B @0x4b2c50); `P[p]` = person record p (0x48 B @ *(0x4d0048) + p*0x48, mod-relocated).
`rand(n)` = 0x47fb13(n) ∈ [0,n) ; `chance(p)` = 0x47fb32(p).

### 10.1 Deployment table (R+0x2044, 115 entries × 64 B; entry(i) = 0x418dd0(i)), filled by ops 0x44/0x46/0x47/0x4b/0x48
| off | size | meaning | written by |
|---|---|---|---|
| +0x00 | u32 | person id (0xffff = empty slot) | 0x44 (players = sortie list), 0x46/0x47 |
| +0x04/+0x05 | u8,u8 | x, y | 0x46/0x47/0x4b |
| +0x08 | u32 | flags: bit0 enemy, bit1 friend-or-"enemy kind 3", bit2 hidden (伏兵: created but not placed), dir bit 0x20=dir0 0x08=dir1 0x40=dir2 0x10=dir3 (0x449b27) | 0x46/0x47 |
| +0x0c | u8 | AI mode 0..6 (tag 0x07, default 1) | 0x46/0x47 |
| +0x0e | u16 / u8,u8 | AI target: person (modes 3,5) or point x,y (modes 4,6) | 0x46/0x47 |
| +0x10 | u8 | auto-promotion mode (tag 0x45, default 2) | 0x46/0x47 |
| +0x11 | u8 | level | 0x46/0x47 |
| +0x14/+0x18/+0x1c | u32 | weapon / armor / accessory code: 0 = default for class and level (0x407fe7), 1 = none, ≥ 2 = item code−2 / code+0x24 / code+0x33 (eex.md op 0x48) | 0x48 (0 by 0x46/0x47) |
| +0x20/+0x21 | u8 | weapon level / armor level (1 by 0x46/0x47) | 0x48 |

**Equipment at battle start** (0x44cc85, generated ally/enemy units after reload and promotion): per slot
0x4429f9(code, level). Default equipment (code 0, 0x407fe7): the first weapon kind k = 0..13 the class may use
(class byte +9+k) gives weapon id `min(L/18, 2) + (k/2)*3`; armour kinds 14..17 give `0x26 + min(L/18, 2) +
((k-14)/2)*3`; level `(L mod 18)/6 + 1` for L < 48 else 3, exp 0 below level 3 else 0xFF; accessories are not
touched. An explicit item (0x407dec) must be of the slot's kind (0x40c6ea) and usable by the person (0x407907: class
equip table for weapons/armour; accessories by the family in item byte +0x17, 0xFF = anyone); its level 0 means
automatic (as above for normal items, treasures L/7+1 ≤ 10) and is capped at 3 (treasures 10).
Ops 0x46/0x47 start every entry with codes 0 and levels 1 (0x4129a4 / 0x4125c5), so a unit without op 0x48 gets the
class default for all three slots.

**Battle start** (0x44d427): every unit record is reset (0x442613: person 0xffff, index, x = y = target unit = 0xff,
AI code 0, state 0, flags 0, +0x20 = 1; the target point [9],[0xa], order, buffs etc. keep what the slot's previous
unit left). Then 0x44cc85 goes through the 115 entries: players (flags & 3 == 0) get UnitInit only; allies that are
party members (person +0x2a == 0, 0x41a190) get UnitInit and the refused SetAI; other allies and enemies are reloaded
(0x41b606), initialised, promoted (0x442890), equipped (0x4429f9 ×3), get full HP/MP and SetAI. Afterwards flag
0x80 and status bits 0x1e are cleared on every unit, and units 0..34 on the map with colour 0 get code 7. A party
member deployed as an ally therefore keeps code 0 with no target unit and its slot's old target point, and acts in
the ally phase (GoTarget toward that point; 3 = passive once there, 0x440252).
UnitInit (0x44274c): state 1, person, colour (0x449b7b), facing (0x449ae8), then (unless hidden) state 2 at the
nearest free cell (0x442b03 → 0x43f040), full HP/MP, buffs 3, status 0; party members: person +0x27 += 1 (not when
re-entering with the fade-in, 0x459417), others: person +0x27..+0x29 = 0. It leaves [8]..[0xb], [0xd], [0xe] alone.

**op 0x44 battle_init** (0x412230): clear flags 0..255; 0x426c32(); u32 @0x55e9d4 = 0; for all 115 entries:
person = 0xffff, flags = 0, mod byte @0x55a500[i] = 0; then entry[k].person = sortie_list[k] for the sortie list
u32[] @0x48b350 (terminated by 0xffff; the persons chosen in the 出场 screen / op 0x4a) → player entries 0..14
(flags 0 = player unit).

**op 0x45 battle_settings** (0x4122f1) args `a0..a9` (tags 26 26 04 3e 32 02 32 02 47 22), S_00: `0 0 20 52 0 -1 1 0 2 1`:
| arg | stored | meaning |
|---|---|---|
| a0 (bool) | u16 R+0x2040 | (a0≠0) — no reader found [?] |
| a1 (bool) | u8 R+0x3d0f | no reader found [?] |
| a2 (u32) | u8 R+0x3d0e → ctx+3 at battle start | **turn limit** (S_00: 20) |
| a3 | s8 @0x496e23 (R+0x3e93) | **level offset**: a3 ≤ 50 → +a3, a3 > 50 → −(a3−50); 0xffff→0 |
| a4, a6 (tag 0x32) | — | read and ignored (editor-only labels for victory/defeat condition types) |
| a5 (person) | R+0x3d04 = (a5≠0xffff), u16 R+0x3d06 = a5 | **boss**: victory when this enemy is defeated (op 0x42) |
| a7 (person) | R+0x3d08 = (a7≠0xffff), u16 R+0x3d0a = a7 | **protected leader**: defeat when this unit falls (op 0x43) |
| a8 (0xffff→0) | u8 R+0x3e91 → ctx+0x11 | **climate** (weather table row, 0..4) |
| a9 (0xffff→1) | u8 R+0x3e92 → ctx+4 | **initial weather level** 0..5 |

Weather (0x44a1d4): shown weather = table 0x48e100[climate*6 + level], weather ids 0 晴 1 阴 2 雨 3 暴雨 4 雪:
```
climate 0: 0 0 0 1 2 3     climate 1: 0 0 0 0 1 2     climate 2: 0 1 2 2 3 3
climate 3: 0 0 1 1 4 4     climate 4: 0 1 4 4 4 4
```
Update 0x449f91(w): `if w < 6: level = w` (weather strategies 58-60 via 0x423c30) else random walk:
`c = level+1; r = rand(8); if c > r: c -= 1 elif c < r: c += 1; level = (c==0) ? 5 : (c==7) ? 0 : c-1`.
Random update is called at the start of every round except the first (0x44efd9, while ctx+1 == 0). If the shown
weather changed, the weather panel (Xthree.wa image 0x34+weather) is animated.

**Level of generated units** (0x46/0x47): `base = max(1, trimmed_mean_level + s8@0x496e23)` where
trimmed_mean_level (0x41885a) = levels of the sortie-list persons sorted descending, drop the top n/4 and bottom n/4
(n = list length, integer division), average the rest (integer division). Slot arg `lv` (tag 0x3e):
`lv ≤ 50: level = min(base + lv, 70)` ; `lv > 50: level = max(base − (lv−50), 0) → 0 becomes 1`.

**op 0x46 battle_allies** (0x4125c5) — 20 slots (unit indices 15..34), each 11 args (tags 02 26 04 04 2b 3e 45 07 02 04 04):
`person, hidden, x, y, dir, lv, promo, ai_mode, ai_person, ai_x, ai_y` → flags = 2 | (hidden?4:0) | dirbit(dir).
**op 0x47 battle_enemies** (0x4129a4) — 80 slots (35..114), 12 args (tags 02 26 26 04 04 2b 3e 45 07 02 04 04):
`person, kind3, hidden, x, y, dir, lv, promo, ai_mode, ai_person, ai_x, ai_y` → flags = 1 | (kind3?2:0) | (hidden?4:0) | dirbit.
Defaults: bools 0xffff→0, ai_mode 0xffff→1, promo 0xffff→2, lv 0xffff→0. person 0xffff → slot skipped (entry untouched).
ai_mode 3/5 store ai_person at +0x0e (u16); 4/6 store ai_x,ai_y at +0x0e/+0x0f; 0,1,2 store nothing.
Example S_00 slot 35 `59 -1 -1 13 7 2 4 -1 2 -1 0 0` = person 59 at (13,7) facing 2, level base+4, promo 2, AI mode 2.

### 10.2 Unit creation at battle start (0x44cc85) and the 0x24-byte unit struct
For each entry i in 0..114 with person ≠ 0xffff, by flags: `flags&3 == 0` → next player unit index (0,1,..),
`flags&1` → next enemy index (35,36,..), `flags&2 && !(flags&1)` → next friend index (15,..). (Indices are assigned
consecutively in entry order, not equal to the slot number.)
```
player:  UnitInit(U[k], person, flags, x, y)
friend:  if P[person] is a party member (0x41a190: P+0x2a == 0):  UnitInit only (keeps the person's real data)
         else: reload person base data from data.wa (0x41b606), UnitInit, Promote(promo, level),
               Equip(0, weapon, wlv), Equip(1, armor, alv), Equip(2, accessory, 0xff), HP=MaxHP, MP=MaxMP
         SetAI(person, ai_mode, ai_person, ai_x, ai_y)   (0x4b5df0.0x459d8b)
enemy:   reload base data, UnitInit, Promote, Equip ×3, HP/MP full, SetAI(...)
```
Mod hook 0x4d3197 is called before Promote/Equip for friends (not analysed). Also byte array @0x569f00[0..114] is cleared.
UnitInit (0x44274c(person, flags, x, y)): U.state(+0xc)=1; U.person=person; U.kind(+5)=0x449b7b(flags);
U.dir(+0xf) from dir bits (default 2); Place(x, y, flags&8, hidden=flags&4); HP=MaxHP; MP=MaxMP;
buffs +0x18..+0x1d = 3; status +0x1e = 0. Party members: P+0x27 = min(P+0x27+1, 255) (battles fought counter [G]);
other persons: P+0x27 = P+0x28 = P+0x29 = 0.
Place (0x442b03): hidden → stays state 1 (off-map). state 1 → state 2, (x,y) replaced by the nearest free cell usable
by the unit's movement type (0x43f040), occupancy map updated (0x435900(&pos, index)); state 2 (already on map) →
moved to exactly (x,y). Promote (0x442890(promo, level)): `promo 0: none; 1: if class ≤ 38 and level ≥ 20: class+1;
2: if class ≤ 38: level ≥ 40 → class+2, level ≥ 20 → class+1` (persons ≥ 0x400 always use promo 2 when GS+6 ≤ 3);
then SetLevel(level) (0x40e010) and recompute the 7 stats (0x406e17(i, 0x4089cb(i))).

Unit struct U (0x24 bytes):
| off | type | meaning |
|---|---|---|
| +0x00 | u32 | person id |
| +0x04 | u8 | own unit index |
| +0x05 | u8 | kind: 0 player, 1 friend, 2 enemy, 3 enemy with the "kind3" slot flag (0x449b7b) |
| +0x06/+0x07 | u8 | x, y |
| +0x08 | u8 | AI target unit index (0xff = target is a point / none) |
| +0x09/+0x0a | u8 | AI target point x, y |
| +0x0b | u8 | action order in its phase (0xff = unassigned), see 10.4 |
| +0x0c | u8 | state: 0 none, 1 created but off-map (hidden/伏兵 or not yet appeared), 2 on map, 3/4 defeated/retreated |
| +0x0d | u8 | flags: 0x02 moved, 0x04 acted, 0x80 cleared by SetAI (AI-has-goal [G]) |
| +0x0e | u8 | AI code (see 10.3); 7 = controlled by the player (set at battle start for colour-0 units 0..34, and by 0x45a46e when a person joins the player's army mid-battle) |
| +0x0f | u8 | facing 0..3 |
| +0x10 | u32 | HP |
| +0x14 | u32 | MP |
| +0x18..+0x1d | u8×6 | buff levels atk, def, spirit, agility, morale, move (3 = neutral) |
| +0x1e | u8 | status ailment bits (§9.2) |
| +0x20 | u32 | 1 after the battle-start reset (0x442613); copied by 0x45b700 |

### 10.3 AI modes and AI codes
Slot `ai_mode` (0..6) → AI code unit[+0xe] via table 0x48e380 (SetAI 0x459d8b; refused for party members — person
byte +0x2a == 0, 0x41a190 — wherever their unit stands; modes ≥ 7 change nothing; a target person without a unit
(0x45a751) or a point off the map (0x45a6bf) leaves the old target). When a person changes army during a battle
(0x45a46e) the unit moves to a free slot of the new side (copy 0x45b700: code 7 if the new slot is player-side and the
person is a party member, else 3) and gets code 7 when it joins the player. The player can command a unit whose
colour is 0 or whose code is 7 (0x43d5f8 / 0x43ff54):
| ai_mode | code | meaning (CCZ editor names) [names G] | target |
|---|---|---|---|
| 0 | 3 | 被动出击 passive: acts only if it can reach a cell from which an opposite unit is attackable | — |
| 1 | 1 | 主动出击 active: always advances toward / attacks opposite units | — |
| 2 | 2 | 坚守原地 hold: never moves (move points 0), attacks/casts from its cell | — |
| 3 | 0 | 攻击武将 go for target person (unit[8] = its unit index) | person |
| 4 | 0 | 到达地点 go to target point (unit[8] = 0xff, unit[9],[0xa] = x,y) | point |
| 5 | 4 | 跟随武将 move toward target person, never attacks/casts | person |
| 6 | 4 | 逃至地点 move toward target point, never attacks/casts | point |
SetAI also clears unit flag 0x80. If the target person's unit is not on the map when the unit acts, the unit falls back
to code 1 (active) with target 0xff (0x43ad1c start). Op 0x4f/0x52/… change these at run time (10.6).

### 10.4 Action order (0x44da7a(side): side 1 → units 0..34, side 0 → 35..114), computed at phase start
All units of the side get order 0xff; then a counter n=0 is handed out in 6 passes over the units on the map
(state 2) in index order, each unit only once:
1. standing on a healing terrain (0x4351c0 ≠ 0: 城池 关隘 鹿砦 村庄 兵营);
2. "wounded" (0x43a1f4): HP ≤ MaxHP·2/5 (person < 0x400) or HP ≤ MaxHP/5 (generic person ≥ 0x400; never for class 0x31);
3. support casters: family ∈ {8 僧兵, 10 道士, 18 国师} (magic set {8,9,10,18} minus 9 谋士);
4. ranged families {4 弓兵, 5 间谍, 15 弓骑兵, 23 箭车} (table 0x44007a);
5. mobile families (table 0x43ffc4 == 0): {0,3,5,7,11,12,13,15,16,17,20,24};
6. everybody else (pass 6 pre-increments: first order value used is n+1 — harmless).
The phase loop (§9.1, 0x44e9ce) then lets units act in increasing order value, re-scanning from 0 after each action.

### 10.5 AI turn of one unit (AIAct 0x43ad1c)
Decision globals ("choice" @0x4b2c1c): +4 dest pos (0x4b2c20), 0x4b2c24 bit0 = retreat mode, 0x4b2c28 target unit,
0x4b2c44 strategy (0xff = physical attack), 0x4b2c4c best score, 0x4b2c38 forbidden cell (0xff none),
0x4b2c30 best physical target, 0x4b2c40/0x4b2c2c best strategy / its target.
```
AIAct(U):
  mv = (U.flags & 0x80) ? 100 : MovePoints(U)      # 0x43f74f: class+equip move; 麻 → 0; move buff ≥4 → +2 (≤ 255), <3 → sat −2
  choice.forbidden = 0xff
  if U.target != 0xff and U[U.target].state != 2: U.target = 0xff; U.ai = 1      # whatever the code was
  if U.state != 2 or U.flags & 2 (moved) or U.status & 0x08 (乱) or U.status & 0x40 (迷): return   # see 10.5.4
  Prepare(U)                                       # 0x43a28a, below
  if choice.retreat and !(U.flags & 0x80) and U.index != 35:
      goal = U is player-side ? U[0].pos : (U[35].state == 2 ? U[35].pos : none)   # fall back toward own leader
      if goal: Approach(goal) [0x438178/0x438308(mode 2)/0x437e2e, 10.5.2] then Flood(U.pos, mv, mode 4)
      else Active(mv)
  else switch U.ai:
      0, 4: GoTarget(mv)                           # 0x43afd4, 10.5.2
      1:    Active(mv)                             # 0x43a7c9
      2:    Flood(U.pos, 0, mode 4); choice.dest = U.pos         # hold: evaluate only the own cell
      3:    if Flood(U.pos, mv, mode 8) != 0xff: Flood(U.pos, mv, mode 4)   # some attack cell reachable
            else choice.dest = U.pos
  Finalize(U) (0x43a956); MoveTo(choice.dest) (0x440252)
  if !(U.flags & 0x80) and U.ai != 4:
      if choice.strategy == 0xff: PhysicalAttack(U) (0x43aafb)          # does nothing if no target [G]
      else: CastStrategy(2, choice.target, choice.strategy) (0x441488); 0x43dc99(strategy);
            if strategy == 0x39: dword 0x4b420c = 1
  if !(U.flags & 0x80) and (U.flags & 4): 0x442718(2)                   # end of action
```
Prepare (0x43a28a): `layerA[cell] = 0xff` for all cells; for each opposite-side unit j on the map, mark with j every
cell from which U (with U's attack range code 0x43f8be) could attack j (0x436586 on j). `layerB[cell] = 0`; if U is
wounded (10.4 pass 2) and U.ai ∉ {2,4}: layerB[c] += 50 for every healing-terrain cell and choice.retreat = 1.
Choice is reset (dest/target/strategy = 0xff, best = 0).

Flood(start, mp, mode, tx, ty, zoc) = 0x438308 (§7.2 flood; cells discovered in order: start, then by increasing cost
level, row-major (y, then x) over cells of the current level, each expanding its 4 neighbours in 0x4359f5 order:
up, right, down, left — table 0x48df68). A cell at level L opens its neighbours only if it is the start, or zoc == 0,
or it is not in an enemy zone of control (0x437d59: an opposite unit 4-adjacent; effect 33 exempts). A neighbour is
taken if unvisited, its move cost ≠ 0xff and L + cost ≤ mp; its cost is L + cost. The mode-8/2/4 checks see only
newly taken cells, never the start.
Opposite-side units block (unless zoc==0 and U.flags&0x80); same-side units can be passed.
mode bits: **4** = evaluate every reachable cell with CellScore (start first, if !(U.flags&0x80)) and also resets the
choice and builds the usable-strategy list @0x4ac7ac (strategies 0..67 whose learn level for U's class
(strategy+0x46*s via 0x409580) is non-zero and ≤ U's level, and whose MP cost ≤ U.MP); **8** = return layerA[cell]
(an attackable unit) for the first reached cell that has one; **2** = return 1 as soon as (tx,ty) is reached.
Returns 0xff if start == (tx,ty) or the start terrain is impassable for U.

CellScore(c) (0x43a529), score accumulates in layerB[c]:
```
  if cell c occupied by another unit: return
  atk = st = 0
  if !(U.flags & 0x80):
     if U.ai != 4:
        if layerA[c] != 0xff or c == U.pos: atk = BestPhysical(c)        # 0x438965 → choice.bestPhys
        if !(U.status & 0x04 穷): st = BestStrategy(c)                   # 0x4391dc → bestStrat, bestStratTarget
        layerB[c] += max(atk, st)
     layerB[c] = min(255, layerB[c] + TerrainScore(c))
     if c == U.pos and atk == 0: layerB[c] = min(255, layerB[c] + 1)
  if c == choice.forbidden: layerB[c] = 0
  if layerB[c] > choice.best:                       # strict: earlier-discovered cells win ties
     choice.best = layerB[c]; choice.dest = c
     if st > atk: choice.strategy = bestStrat; choice.target = bestStratTarget
     else:        choice.strategy = 0xff;      choice.target = bestPhys
```
TerrainScore (0x43a4bf): terrain(c) ∈ 18..22 (城池 关隘 鹿砦 村庄 兵营) → 8; else e = terrain effect (×10%) of U's
family on U's **current** cell (0x43f84d reads U.pos, not c — original quirk) → max(e − 10, 0).

BestPhysical(c) (0x438965): targets = opposite units within U's attack range from c (0x436586(c, range, 0x80));
returns the max PhysScore(t, c) (strict >, first wins) and sets choice.bestPhys.
PhysScore(t, c) (0x438a20):
```
  s = 0
  if t is on the opposite side:
     d = CalcDamage preview (0x43bc4b(U, P[t.person], 0, 0))
     if d >= t.HP: s = 80
     elif d*10 / MaxHP(t) >= 1: s = 16              # ≥ 10 % of max HP
     elif t.HP*100 / MaxHP(t) <= 40: s = 16
     elif U.ai == 1: s = 10
     else: s = 2
  if t.status & 0x08 (乱): s += 8
  if s > 0 and t.person < 0x400: s += (t.person == boss (R+0x3d06) or t.index == 35) ? 8 : 4
  if s < 75 and U's family ∈ {8,9,10,18}: return 0                    # casters only melee for kills
  a = area-attack code of U's class (0x407818, table 0x409191 + mod hooks); if a ∉ {0, 0xff}:
     hits = units hit by the area attack aimed at t (0x435aad);
     s = (hits empty ? max(s-4, 0) : s) + Σ_{u in hits} (CalcDamage(U,u) >= u.HP ? 10 : dmg*10/MaxHP(u) >= 1 ? 4 : 0)
  if s > 0 and c lies inside t's own attack range from t's position (counterattack possible) and s > 1: s -= 1
  return s
```

BestStrategy(c) (0x4391dc): for every s in the usable-strategy list, with Usable(U,t,s) (0x4390ef) =
`0x41fec9(s,U) (can cast: MP, 穷…) and StrategyTerrainOK(s,U,t) (0x420422, §5.6) and side test (strategy byte +0xb:
0 → t must be on the other side, 1 → same side, else any)`:
```
  if strategy s has no cast range (range code 0xff, self-centred area):
      v = Σ over units u in the area around c (0x435b3e; side: s 39..57 → own side, else opposite) of StratScore(u,s,c)
          (+10 once the running sum is > 0 and u == U.target)          → candidate (s, target 0xff)
  else: for every unit t in cast range from c (0x436586(c, range|0x80, side|0x80)):
          v = min(StratScore(t,s,c), 255); if v > 0 and t == U.target: v += 10      → candidate (s, t)
  keep the strictly best v (first wins) → bestStrat / bestStratTarget; return best v
```
side(s) (0x439576): s ≤ 38 → opposite side, 39..63 → own side, ≥ 64 → opposite.
StratScore(t, s, c) (0x4395ae) — `hp% = t.HP*100/MaxHP(t)`; every case returns 0 unless Usable(U,t,s):
| strategies | score |
|---|---|
| damage 0-8, 10-13, 15-20, 33-36 | d = StratDamage preview (0x43bfaa(U,t,s,0)); `d ≥ t.HP → 76; d*10/MaxHP ≥ 3 → 30; ≥ 1 → 10; else 1`; then 20 暗算: +5 if U.HP < U.MaxHP, +10 if U wounded; 33/34 毒: +8 if hp% ≥ 40; 35/36 麻: +10 if t is NOT adjacent to U (0x45afca(U.person, t.person, 1)) |
| 21 暗杀, 31 伪书, 32 伪令 | hit = StratHitRate (0x43b73f); hit ≥ 35 → 15 (+15 if hp% ≥ 80) else 0 |
| 22 暗鬼 (MP drain) | 20 if U.MP ≤ U.MaxMP/5 and t.MP ≥ 30, else 0 |
| 37 封印 | t's family ∈ {8,9,10,11,18,19,20} and hit ≥ 60 → 15 (+7 if hp% ≥ 80); else 0 |
| 39 医疗, 40 痊愈, 43 救护 | t wounded (0x43a1f4) → 50 (+5 for 40, +10 for 43); else 0 |
| 41 补给, 42 犒劳 | t wounded → 50 else 0 |
| 44 开导, 45 诫谕, 62 暝思 (MP) | if t.MP ≤ t.MaxMP/5 and U.MP ≥ cost(s): family(t)==9 → 1; t magic family or person effect 0x40 → 12; family(t)==0 → 6; else 0 |
| 46 棒喝, 47 超脱 (cure) | 5, + (t.status == 0x02 and t.ai ∉ {2,3} → 25; == 0x04 and t magic family → 30; == 0x08 → 35) |
| 57 战备 | t.ai ∈ {2,3} or family 9 → 0; family 0 or 19 → 15; family 5 → 10+rand(4); family 8 → 10; else rand(5) |
| 9, 14, 23-30, 38, 48-56, 58-61, ≥ 63 | 0 (never chosen by the AI) |
Then, if the strategy has an area (area code ≠ 0), AreaAdjust(hits around t, v, kind, U, s) (0x438d96):
`hits empty → v = (v > 4) ? v-4 : 0`; for each hit u with Usable(U,u,s): kind 0 (damage/status) +3 (+3 more if
u == U.target); kind 1 (heal) +5 if u's hp% < 60; kind 2 +3 if buff 0x41df90(u) < 4; kind 3/4 +3 if 0x41dfb0(u) < 4;
kind 5 (cure) +3 if u.status ≠ 0; physical (s = 0xff) +10 if the hit kills, else +4 if ≥ 10 % MaxHP. Result max(·, 0).

#### 10.5.2 Movement helpers
GoalBonus(cell, v, i) (0x438178), recursive: `if v < 9: return; if layerB[cell] == 0 and terrain effect of U[i] (on its
current cell) ≠ 0xff and (cell empty or cell == U[i].pos): layerB[cell] += v; unless U[i].class ∈ {15,16}: for each of
the 4 neighbours nb: GoalBonus(nb, v > 10 ? v-10 : v-1, i)`. I.e. v=10 → goal +10, its neighbours +9; v=20 → goal
+20, distance 1 +10, distance 2 +9 (first assignment wins).
StepToward(goal, from, mv, bonus) (0x437e2e): needs the cost grid of a preceding Flood(goal, …, mode 2) (distance to
goal). Greedy walk from `from`: among the 4 neighbours (skipping cells in an enemy ZOC unless it is the goal or U has
flag 0x80) take the one with the smallest goal-distance strictly below the current cell's whose move cost ≤ remaining
mv; subtract its cost; stop at the goal or when no step is possible. If stopped short and bonus==1:
GoalBonus(end, end occupied (incl. by U itself) ? 20 : 10, U). Returns the path (directions, buffer 0x4aeb38+0x1900).
Active(mv) (0x43a7c9, code 1): `if Flood(U.pos, mv, mode 8) != 0xff: Flood(U.pos, mv, 4)` (an attack position is
reachable now: evaluate normally); else `j = Flood(U.pos, 255, 8)` (nearest attackable opposite unit by path cost,
ignoring the move limit); if j: `goal = U[j].pos; if Flood(goal,255,mode 2,U.pos,zoc=1)==1 or Flood(…, zoc=0) reaches:
StepToward(goal, U.pos, mv, 1); Flood(U.pos, mv, 4)`; if no j at all: dest = U.pos.
GoTarget(mv) (0x43afd4, codes 0 and 4): goal = target unit's position (unit[8] ≠ 0xff; if that unit itself has code 0/4,
its own target point becomes choice.forbidden) else the target point (unit[9],[0xa]).
```
  if !(U.flags & 0x80):
     r = Flood(U.pos, mv, mode 8)
     if U.target != 0xff and r == U.target: GoalBonus(goal, 20, U); Flood(U.pos, mv, 4)    # target attackable now
     else: GoalBonus(goal, 10, U)
           if goal reachable (Flood(goal,255,mode 2,U.pos) with zoc, else without): StepToward(goal, U.pos, mv, 1); Flood(U.pos, mv, 4)
           else: Active(mv)
  else (scripted move, mv = 100): dest = goal if a path exists (with ZOC, else without); otherwise dest = U.pos and
       the target point is reset to U.pos
```
Code 4 units score cells only by GoalBonus/TerrainScore (CellScore skips atk/strategy for code 4) and never attack.
MoveAlongPath (0x43a956 → mod 0x4d3a2d): if dest ≠ 0xff and ≠ U.pos: path = StepToward(goal U.pos, from dest, 255, 0)
on the last flood's grid (greedy descent from dest, reversed);
walk it step by step (0x44201b(dir) animation; camera follows when flag 0x80); then U.flags |= 4 (moved) unless 0x80.
Arrival (0x440252): if U.target == 0xff and U.pos == target point and U.ai ∈ {0,4}: U.ai = 3 (becomes passive).
PhysicalAttack (0x43aafb): skipped if flag 0x80, code 4, flag 2, or the person's weapon cannot attack (0x407907);
target = choice.target if it is in U's attack range from the new cell (else the last unit found in range — quirk);
face it (0x435829), attack (0x441488(1, target, 0xff) → §4 sequence; mod hook 0x4d6b80/0x4d7808). If the target died
and U has effect 46 引导攻击: pick a unit in range the same way and attack again. Finally U.flags |= 2|4.
Unit flags (unit[+0xd]): 0x04 = moved, 0x02 = action finished (the phase loop skips units with either; §9.1 had them
swapped), 0x80 = scripted move (go to the target ignoring enemies, never attacks; set by op 0x55 [G]).

#### 10.5.4 Phase loop (0x44e851) and units that skip AIAct
```
for k in (0 friend phase: ctx+0x10 = 1, units 0..34;  1 enemy phase: ctx+0x10 = 2, units 35..114):
   phase-start work (§9.1; enemy phase: turn events 0x44ac28(turn+1,1,0), script poll 0x44c601, recovery/decay,
   mod 0x4d0d0e(35,0), clear bytes 0x55af00[35..114], poison, regen)
   ActionOrder(k == 0)                                     # 10.4
   for o in 0..114:
      i = first unit of the side with state 2, order == o, ai != 7 and no flag 4/2 (if none: next o)
      AIAct(U[i]); if U[i].flags & 2: 0x4b5df0.0x45b5fe(i)
      0x44cc03(i) (death/aftermath checks); if battle not over and flags & 2: scroll (0x43fcc9), script poll 0x44c601
      if ctx+0x504 (set when units appear/change during events): recompute ActionOrder, o restarts at 0
   stop as soon as ctx+1 (battle result) ≠ 0
```
Units with status 乱 (0x08) or 迷 (0x40) return immediately from AIAct, i.e. AI units under 乱/迷 lose their turn
(§9.2's "AI-controlled" note for 乱 is wrong for AI units); they get no flags. Code 7 units never act automatically.
A unit the player commands (0x43d544 → 0x43ee5e): under 乱 or 迷 its move range is shown and the next click on the map
only brings up "正处于混乱状态。" (0x48dff8) / the 迷失 message (mod string 0x5556e0); it cannot act. After each player
action the phase ends (after a prompt) when no unit 0..34 on the map with code 7, no flag 2 and no 乱 is left (0x44e0d9).

### 10.6 Battle-time script ops
Common conventions: **person selectors** in unit tests (UnitAt 0x45b371, InRect 0x45b4a5): 0x400 = any unit,
0x401 = a player-side unit (index < 35: player or friend), 0x402 = an enemy unit, else a person id; only units with
state 2 and HP > 0 count. In 0x36/0x38 a selector 0x400..0x402 is replaced by the "current unit" person
(0x4b5df0.0x45602b — the unit that triggered the event / is acting [G]). **Side codes** (CountUnits 0x44c8e6,
op 0x4d): 0 player, 1 friend, 2 enemy, 3 enemy-kind3, 4 player+friend (kind ≤ 1), 5 all enemies (kind 2/3), 6 all
(0xffff → 6). **Compare mode** (tag 0x24) in 0x3f/0x41/0x36: 0 → value ≥ arg, 1 → value < arg, other → ==.
All tests return false outside battle (screen mode 0x4ac63c ≠ 3, 0x40b922).
| op | args | semantics |
|---|---|---|
| 0x3f test_turn (0x411652) | n, mode | turn = ctx+2 (0-based round counter) + 1; compare(turn, n, mode) |
| 0x40 test_side (0x4116ee) | phase | ctx+0x10 == phase (0 player phase, 1 friend phase, 2 enemy phase) |
| 0x25 test_unit_at (0x411b50) | person, x, y | UnitAt(person, x, y); person must be ≤ 0x200 or a selector |
| 0x26 test_unit_in_area (0x411c36) | person, x1, y1, x2, y2 | some matching unit in the inclusive rectangle |
| 0x41 test_units_in_area (0x41149d) | side, n, mode, rect_flag, x1, y1, x2, y2 | c = number of units of `side` (rect_flag 1 → inside the rectangle, else on the whole map); compare(c, n, mode) |
| 0x2e test_adjacent (0x411a54 → 0x45afca) | p1, p2, loose | units of p1 and p2 on the map, alive, p2's unit in one of the 8 cells around p1's. loose=0 additionally needs each to be able to attack the other from there (0x45b2a8: target in attacker's attack range; families 2/4/5 use range 1). If p2 ≥ 0x200 it is a selector: any matching unit in the 8 cells. |
| 0x36 test_attr (0x4112e9) | person, attr, value, mode | attr 0..4 battle stat words (攻击 防御 精神 反应 士气, person +0x11..), 5 base MaxHP (+0x1c), 6 base MaxMP (+0x20) via 0x406d87; 7 = the person's battle-unit HP; 15 = stack count of consumable `person` (item 0x57..0x67) [G]; compare(attr, value, mode) |
| 0x38 set_attr (0x412006) | person, attr ≤ 15, op, value | op 0 set (0x406f54), 1 add (AddStat 0x406e17), 2 subtract (saturating). attr 7 = battle-unit HP (op 2: HP = max(HP−v,0)); if the unit's HP ends ≤ 0 it is killed (0x4121b0); else the person's display is refreshed (0x479a01). Person attr ids for 0x406d87/0x406f54: 0-4 stat words, 5 HP base, 6 MP base, 9 level, 10-14 raw abilities 武艺 统制 智谋 感知 胆魄 |
| 0x73 test_sum (0x411207) | — | unused by all scripts |
| 0x42 / 0x43 | — | see eex.md (victory/defeat flags, boss R+0x3d06 / leader R+0x3d0a from op 0x45) |

#### 10.6.1 Unit ops
"Unit of person p" = first unit index i in 0..114 with U[i].person == p (0x456079 requires state ≠ 0).
| op | args | semantics |
|---|---|---|
| 0x4c unit_appear (0x414f42) | mode (0xffff→0), person, slot | mode 0: 0x4b5df0.0x4570ee(person): if the person's unit is in state 1 (off-map), take its deployment entry's (x,y), Place it (nearest free cell, state 2) with an appear animation (wipe-in, SE 0x2a; SE 0xf when the cell is off-screen [G]), camera centred. mode 1: player slot `slot` < 15 in state 1 → Place at its entry position, SE 0xf, camera, short delay. Used to reveal 伏兵 (hidden) units and reinforcements. |
| 0x4d unit_change (0x4150e7) | mode, person, slot, x1, y1, x2, y2, side, buff_idx, buff_lvl, status, hp_dmg, mp_dmg | target = mode 0: unit of person; 1: unit in player slot `slot` (state 2); 2: all units of `side` (0xffff→6) in the rectangle (0x45ade5). Then via ChangeUnit(person, what, value, anim=1) (0x45aa5c): if buff_idx ≠ 0xffff: buff[buff_idx] (0 atk,1 def,2 spirit,3 agility,4 morale,5 move) = {0→0, 1→3, 2→6, other→3}[buff_lvl]; if status ≠ 0xffff: value & 0x80 → status &= ~value, else status \|= value; if hp_dmg ≠ 0: HP −= min(HP, hp_dmg & 0xffff) and a result ≤ 1 becomes 0 (death via 0x4121ca); if mp_dmg ≠ 0: MP = max(MP − mp_dmg, 1) (result ≤ 1 → 1). what ≤ 6 shows the buff/status animation (0x43e69f); the unit's status panel is refreshed. |
| 0x4e change_ai (0x4146d4) | mode, person, x1, y1, x2, y2, side, ai_mode, ai_person, ai_x, ai_y | mode 0: SetAI(person, …) (10.3; no effect on party members); else 0x459e79: SetAI for every unit of `side` in the rectangle. |
| 0x4f unit_turn (0x415f65 → 0x457428) | p1, p2, dir, b1 (0xffff→0), scroll (→1), wait (→1) | p1's unit (state 2) turns: if p2 == 0xffff to `dir` (nothing if already facing it), else toward p2's unit (direction from 0x4351da). scroll → centre camera + 8-tick delay before; SE 6; wait → 8-tick delay after. b1 [?]. Units that already finished their action keep the greyed look. |
| 0x50 unit_status (0x416129 → 0x45778f) | person, action 0..12, pre_wait (→1), post_wait (→1) | Plays a battle-sprite animation on the person's unit (camera centred). Sheets: action 0 = back to normal pose (no sheet); 1,2,3,10 use Unit_spc (~kvr.db: defend/hurt/cheer); 4,8,9,11,12 use Unit_mov (~zl1g.dat: walk/stand/weak); 5,6,7 use Unit_atk (~gtl.dll). pre/post_wait = 8-tick delay (skipped for actions 0 and 11). [Exact frame sequences per action: TODO] |
| 0x52 change_class (0x414d15) | person, class | person (selector → current unit) gets class `class` (0x40dff0); each equipped item the new class cannot use (0x407907) is unequipped (0x407dc4); in battle the unit sprite is reloaded (0x43fe2c). (Story files use it too.) |
| 0x31 actor_remove, battle mode (0x41311c) | mode, person, x1, y1, x2, y2, side | mode 0: RemoveUnit(person, silent=1); else every unit of `side` in the rectangle (0x45a80f). See RemoveUnit below. |
| 0x53 unit_retreat (0x41557b) | mode, person, x1, y1, x2, y2, side, anim (0xffff→0) | like 0x31 but RemoveUnit(silent=0, anim): the unit "retreats" with its 撤退 line and animation. |
| 0x1b set_retreat_line (0x413c56) | person, bool | U(person)+0x20 = (bool ≠ 0): whether the unit speaks its retreat line when it leaves (default 1, set by the unit reset). |
| 0x55 unit_reenter (0x41591c → 0x4591a1) | mode (0xffff→0), person, slot, x, y, dir (0xffff→2) | (eex.md's "unit_move" is a misnomer.) mode 0: person; mode 1: the person of player slot `slot` < 15 whose unit is in state 3. A unit in state 3 (retreated) is re-initialised with UnitInit(person, entry flags with new dir, x, y) — full HP/MP, buffs reset — and appears with the wipe-in animation (SE 0x2a). |
| 0x5b target_area (0x416cbb) | x1, y1, x2, y2, flag (0xffff→0) | Stores the destination area rectangle in ctx+0xc..+0xf and ctx+8 = (flag == 0), then 0x4b5df0.0x45a0ce(flag) clamps it to the map and shows it (camera to its centre, area highlighted [G]). Used with "到达指定地点" goals. |
| 0x58 terrain_change (0x4166eb) | patch, alt, terrain, x, y, scroll (0xffff→0), silent (0xffff→0) | alt == 0 → ChangeTerrain 0x4b5df0.0x456140(x, y, terrain, patch, scroll, silent, EV[0]&0xff): record (x, y, new, old, patch) in a 250 × 5-byte table at ctx+0x19 (0x4b3d21, for saves); terrain grid (0x4aeb38+0x640)[x,y] = terrain; scroll → camera to (x,y). patch < 4: overlay mark written to layer 0x4aeb38+0x1f40 (patch 0/2 play SE 0x13 — fire [G]); patch ≥ 4: Nima.wa entry 2·patch−8 (a 3×3-cell 144×144 image) is pasted into the map bitmap centred on (x,y) (skipped when the last arg is 1); SE for new terrain 12 小河 / 15 城墙 / 17 城门; the 3×3 area is redrawn. alt ≠ 0 → mod routine 0x4d7dc5(x, y, patch, scroll) [not analysed]. |
| 0x6b map_effect (0x41405b) | x, y, effect, scroll | Plays an effect animation centred on cell (x,y) (camera scrolls there first if scroll): effect < 100 → Xben.wa[effect]; 100..108 → MCALL(effect−100) full-screen (0x497af8.0x4217ff); 109 → special 0x421879; only if the cell is on screen. |

RemoveUnit (0x441744(silent, anim), on a unit in state 2): silent → vanish animation (0x4419b6(1)); otherwise, if
U+0x20 ≠ 0 and the unit is a player unit (kind 0), the retreat line text #(650 + person) is shown for persons < 49
(0x44197b → 0x40c00d, dialog 0x45965d); then if anim ≠ 0 or person == 0: camera to the unit + animation 2, else SE 0x10
+ animation 0. The unit leaves the map (0x442ae4) and party members get P+0x29 = min(P+0x29+1, 255) (retreat
counter [G]). Common tail: state = 3, status = 0, mod hook 0x4dbff3, panels refreshed, and every unit whose AI
target was this unit and whose code is 0 or 4 switches to code 1 (active) with target 0xff.

---------------------------------------------------------------------------------------------------
## 11. 武将情报 window (dialog 166) and its details (dialogs 167, 285) [C]

Port: `game/src/ui/info_window.gd`, `detail_panel.gd`, `dlg_panel.gd` (layout from the dialog templates).

**The window.** Created once at startup, hidden (0x479b59 `CreateDialogParamA(166, proc 0x479164)`); shown by
0x479728(pid) (SE 0, only if battle or party member: gate 0x407060), modeless; 确定 hides it. It takes a **person
id**; 0x477adc finds the person's unit only in battle (first slot 0..114 with state ≠ 0 holding the pid), else
there is none and base values show (full HP/MP, no buffs, 正常, no side label).

| Opened by | 上一/下一 list (u32 0x4b6cf0, ended by 0xffff; index 0x4b7504) |
|---|---|
| Battle player phase (0x44e0d9): right button on **any** unit, acted or not (0x44e526) | 0x47980d: on-map (state 2) units of its group, slots 0..34 or 35..114, by pid |
| 部队情报一览 (186) row (0x47ade4; also centres the map on it) | the list 我军/敌军 last built |
| 选择武将 (236) right click on an entry (0x45d7af) | sortie candidates (0x45c119) |
| Story scene: right click on an actor, pid < 0xff (0x429b81 → 0x4799b0) | party members by pid (0x4768c0), or just that person (0x479954) |

A right button while picking a move or target only cancels; on no unit in the player phase it asks to end the
turn (state 6). The original has no right-click menu (menu bar APPMENU + toolbar). While open the window follows the
hovered unit (0x44e313) and refreshes after actions (0x479a01). 上一武将 / 下一武将 stop at the ends and are disabled
there. The port's window is modal; a right click on an empty cell, Esc and 菜单 open the port's system menu.

**Main area** (refresh 0x478688; P = person, U = unit):
* Portrait (sge.wa 301+face via mod 0x4d40f8); name with ASCII digits removed (0x407757); side "[ 我军 ]" /
  "[ 友军 ]" / "[ 敌军 ]" by U+5 (0 / 1 / 2, 3); class name 0x48bea8[P+0x2b]; Lv P+0x2c; Exp bar P+0x2d of 100
  ("MAX" at 0xff).
* HP bar: U+0x10 (else MaxHP) of MaxHP, green, magenta when poisoned (0x10); MP bar U+0x14 & 0xff (else MaxMP) of
  MaxMP, yellow, magenta under 穷计 (0x04) (0x4794a2).
* 状态 line (0x478a0f + mod 0x4d6140): no unit → 正常; else each part followed by a space: 混乱 0x08, 麻痹 0x02,
  迷失 0x40, 怯力 0x20, 中毒 0x10, 穷计 0x04, 攻击增加/减少 (U+0x18 ≥ 4 / ≤ 2), 暗杀 (byte 0x569f00[slot] ≠ 0),
  精神 +0x1a, 防御 +0x19, 反应 +0x1b, 士气 +0x1c 增加/减少; empty → 正常; then " 行动完毕" if U+0xd & 2.
* 现金 (gold, GS+0xc) only for pid 0. 基本能力 武艺 统制 智谋 感知 胆魄 = raw P+0x21..0x25. Biography
  Fhua[922+pid] (pid < 210). "出阵数 %2d  撤退数 %2d" = P+0x27, P+0x29 for party members.
* 技能 caption (mod chain 0x4d3bd3), first match: pid == [0x55ac04] 【招】三板斧 (0x555700), [0x55ac40] 【术】天魔,
  [0x55ac48] 【术】波若, [0x55ac44] 【术】魔功, [0x55ac60] 【术】锻造; else every code ≥ 0x36 in the per-person code
  table 0x4dc100[1024] becomes 0xff (0x4d5509); pid in the list 0x55ee08[30] (= EV[3970..3999]) → code[pid] = 0x27+i,
  name 0x5559a0+32i; pid 25 with class 41 → code 0x24, 【术】飞将军, else code[25] = 0xff; pid 24 with byte
  [0x55e25c] ≥ 3 → code 0xf, 【术】贯石, else code[24] = 0xff; pid in the word table 0x4d3c4c (36 pids) → name
  pointer 0x4d8260[k] (pid 0 → 【招】苍龙过阵枪); else 无 (0x555791). R_00 fills EV[3970..3999] with 1024 (nobody)
  at the start of a new game; later scenarios assign pids (e.g. R_02 EV[3980] = 13 → 王伯当 【术】舍命, R_17
  EV[3972] = 2 → 王君珂 【术】并蒂, R_06 EV[3983] = 19 → 罗成 【术】智将).
* 技能 text: Fhua[450+code[pid]] when active (0x4dc5c5: code < 0xae; code 0 needs [0x55ac04] == 1, 1 needs
  [0x55ac60] == 16, 2 needs [0x55ac48] == 15, 0x24 needs class 41), else Fhua[598] (empty); pid < 210 only.
* Button 100 技能说明 (mod 0x4dc720: toggles page 284's text to the biography) lies mostly outside the client area
  (template rect 300,252,54,10 in a 313×256 dialog: only a 13×4 DLU corner shows, but it is clickable); the port
  leaves it out (spec: docs/mod_patches.md B6 F7).

**Pages** (0x478f7b; labels 0x48ec4c; the selected page 0x48e9a8 is kept between openings; SE 0 on a change):
* 能力 (178, bars 0x476b85): 攻击 防御 精神 反应 士气 = person stats with equipment (0x407126..), bar scale 800.
  Buff 3 or no unit: blue bar, "%3d". Buff ≥ 4: (v base, v2 battle) cyan under, text "battle/base". Buff ≤ 2:
  (v battle, v2 base) red under, text "battle/base". 机动 (0x476987) = MovePoints (0x40727b); with a unit, move buff
  ≥ 4 → "%u ( +%d )" (move+2, 2), ≤ 2 → "%u ( -%d )" (move−2, 2); paralysis is not applied.
* 装备 (179, 0x476eb4 + mod 0x4d0e6a): "武器∶ %s" / "护具∶ %s" / "辅助∶ %s" (or 无), icon item+0x13, Lv, Exp bar
  (exp, max, max) with max 100, treasures 150, +100 at Lv 9 (mod 0x4e0021), effect line 0x462005. The mod
  disables the 辅助 label for pid 11. Clicking a slot opens dialog 167.
* 策略 (200, list 0x4658c0): strategies 0..0x43 whose learn level for the class (strategy+0x11+class) is ≠ 0 and ≤
  the level, by id; columns icon (Mgcicon, strategy+0x10) + 策略名, MP (strategy+0xe, ×2 while [0x4d0d61], the
  second cast of 连续策略). Clicking a row opens dialog 285. (Header-click sorting 0x464e1f is not ported.)
* 兵种 (284, 0x477b62): map sprite (in battle the unit's frame 0x43e572: 9 kneeling, 6+dir after moving/acting,
  2·dir walking; else frame 6), class name, 武器 = item group 0x48bc20[i] for the first i in 0..6 with
  class.equip[2i] ≠ 0 (else "--"), 护具 = 铠甲 (equip[14]) / 衣服 (equip[16]) / "--", grades "EDCBASX"[class bytes
  2..6] (0x555470) for 攻击 防御 精神 反应 士气, 机动 = class byte 0, 攻击范围 = Jiqi.wa[class byte 1], description
  Fhua[350+class].

Bar painter 0x46146f(v, v2, max, style): second tile to left + W·v2/max, main tile to left + (that)·v/v2 (W·v/max
when v2 = 0); text "%3d/%3d " (v, v2), "%3d " when v2 = 0, style 8 prints (v2, v), style 5 "MAX" for 0xff; tiles
Kao.wa 8×8 at 0x00 red, 0x40 yellow, 0x80 green, 0xc0 blue, 0x100 cyan, 0x140 magenta. Styles: 1 green, 2/4/5
magenta, 3 yellow, 6 blue, 7 blue over red, 8 blue over cyan.

**Item detail** (dialog 167, 0x40bef7 → 0x4700c4(item < 0x68, level, exp) → fill 0x40c843): icon, name; Lv (if a
weapon/armour and level ≠ 0xff) and Exp bar (max as above, 0x4d3d08); 属性 = 0x48bc20[type < 0x12 ? type>>1 :
consumable 0x3f..0x50 ? 10 : 9]; 价格 = byte +0x12 × 100, "---" for 0xff; 效果 line 1 = 0x462005, line 2 = 0x462174
(a treasure's special effect, else empty); description (200-byte records, item id); 可装备的部队: one label per
class family 0..25, enabled for weapons/armour when the family's first class may equip the type (class+9+type),
for accessories when byte +0x17 is 0xff or the family (item 0x4c also families 8, 9, 18, 24: mod 0x4da200), never
for consumables.

Effect line 0x462005(item, level): kind 0x40681a(type): type < 10 or 0x18 → "攻击 +%u", < 0xe or 0x19 → "精神 +%u",
< 0x12 or 0x1a → "防御 +%u" with the value at the level (0x40c674: base +0x15, + growth +0x17 per level above 1 for
weapons/armour, capped 255); otherwise 0x461ef3: for a treasure or type > 0x11, code = (treasure ? special +0x14 :
type) − 0x12, value v = treasure ? 0x46938f(special value, level) : +0x15; suffix by code (0x4621bb): codes 0 1 3 4
5 0xf..0x14 0x16..0x1a 0x1c..0x21 0x24 0x26..0x28 0x2a 0x2c 0x2f..0x33 0x39..0x45 0x47 → v = 0 ("--"); 2 6 7 8 0xb
0xc 0xe 0x2d 0x2e 0x34..0x38 0x48 0x49 → "+%d" ("ALL" for 0xff, "--" for 0); 9 10 0xd 0x15 0x1b 0x22 0x23 0x25 0x46
→ "+%d%%"; 0x29 0x2b → "-%d%%". Text: v = 0 → the effect name (0x4072d3: 0x48bc50[code], codes ≥ 0x3f from
0x410f50[code−0x3f]); v & 0xff = 0xff → "%s (%s)" with 0x48bc50[code]; else "%s %s".

**Strategy detail** (dialog 285, 0x47008d(id < 0x44) → fill 0x46fa85): icon (+0x10), name, 效果 =
0x48bd40[+0xf], 消耗ＭＰ (0x425ad0), 可能范围 = Jiqi.wa[+0xc] (0xff → 0x10), 影响范围 = Drink.wa[+0xd] (0xff → 1),
description Fhua[150+id]. The original places both details at the mouse (0x46f9ba); the port centres them.
