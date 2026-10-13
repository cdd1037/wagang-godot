# Mod patch audit: what wagan.wa's mod code changes, and what the port has

wagan.wa is Koei's 三国志曹操传 engine plus the mod's hand-written code in `.text2` (0x4d0000+), wired into the
original code by `call`/`jmp` patches and by direct references to mod data. This document lists every such patch
site, says what it changes, and whether the Godot port (`game/src`) reproduces it. It is the to-do list for
feature parity: [Missing and partial features](#missing-and-partial-features) is the summary, and the
[batch reports](#batch-reports) hold the per-site tables and an implementable spec for each gap.

Audit of 2026-10-11, against commit 8c00d22. Tags as in [rules.md](rules.md): **[C]** confirmed from code,
**[G]** guess.

## Method

* **Inventory: 316 sites.**
  * 284 rel32 `call`/`jmp` instructions from `.text` into `.text2`, found by `tools/hooks.py` and listed in
    `extract/hooks.txt`.
  * 32 instructions in `.text` that reference mod data or code directly (e.g. `0x4d0d61`, `0x4d0da8`).
  * Sites were grouped by their containing function into six address ranges, B1..B6.
* **What was checked for each site:**
  * The original instructions around the site.
  * The mod code it reaches, followed until it returns (`tools/rd_trace.py`, `tools/disx.py`, Ghidra headless).
  * The port, searched for the behaviour itself, not only for addresses.
* **Statuses:**

  | Status | Meaning |
  |---|---|
  | PORTED | the port has the behaviour |
  | PARTIAL | the port has part of it |
  | MISSING | the port lacks it; a spec is given |
  | N/A | Win32/platform plumbing the port replaces wholesale, or code with no visible effect |
  | FALSE | not a real patch (bytes inside another instruction, or unreachable code) |
* **Limits:** mod code also runs from places that are not rel32 branches into `.text2`, so a feature reached only
  that way could still be missing from this list. The reports cover the ones met on the way:
  * code placed in gaps of `.text`: 0x401118.., 0x406b4f, 0x407600, 0x407bc8, 0x40913d, 0x427025, 0x42beae,
    0x433359..0x433418, 0x4364b6.., 0x43d108;
  * re-pointed jump-table entries: 0x45bcc8 → 绝招, the class-matchup table 0x4d2140;
  * patched data operands, e.g. the terrain rows 0x4d5fbc.

  [Coverage of the mod code](#coverage-of-the-mod-code) checks this limit: no mod code is reached any other way.

## Results

| Batch | Original code | Sites | PORTED | PARTIAL | MISSING | N/A | FALSE |
|---|---|---|---|---|---|---|---|
| [B1](#b1--attack-sequence-and-damage-0x4010000x406fff) | attack sequence, damage, phase-start skills | 51 | 36 | 0 | 0 | 15 | 0 |
| [B2](#b2--persons-level-up-script-ops-toolbar-saves-0x4070000x41ffff) | persons, level-up, script ops, toolbar, saves | 65 | 48 | 1 | 0 | 9 | 7 |
| [B3](#b3--strategies-story-scenes-ai-attack-0x4200000x43afff) | strategies, story scenes, AI attack | 63 | 38 | 0 | 0 | 25 | 0 |
| [B4](#b4--hit-rates-damage-healing-regeneration-0x43b0000x43cfff) | hit rates, damage, healing, regeneration | 30 | 30 | 0 | 0 | 0 | 0 |
| [B5](#b5--units-movement-turns-command-menu-0x43d0000x45ffff) | unit commands, movement, turns, command menu | 52 | 36 | 1 | 0 | 13 | 2 |
| [B6](#b6--dialogs-info-window-runtime-0x4600000x486000) | dialogs, info window, runtime | 55 | 29 | 0 | 7 | 17 | 2 |
| **Total** | | **316** | **217** | **2** | **7** | **79** | **11** |

Counts rechecked against the port on 2026-10-12 (at the audit: 66 / 22 / 136 / 81 / 11); each batch report gives its
own. What is left: the 7 sites of the 武将情报 技能说明 button (B6 F7, left out on purpose, group 5 item 40); the 2
PARTIAL rows are deliberate differences (the autosave, skippable videos). The last two MISSING rows of B5, the target
pickers' forecast with 交给's preview line (0x4412c9) and the command menu's icons (0x45bd35), are ported since.

**Answer to "has the port reached feature parity?": yes, for everything this audit found.** The story scripts, the
map, the base CCZ battle rules, the mod's formula changes, its battle commands (group 2), its character skills
(group 3), the general battle rules (group 4) and the shops, menus, windows and settings (group 5) are ported. Left:
the deliberate differences below. The audit also covers all of the mod's live code: every byte of `.text2` that
no audited entry point reaches is either data that live code reads or dead code
([Coverage of the mod code](#coverage-of-the-mod-code)).

## Coverage of the mod code

Can mod code run from somewhere other than the 316 sites, and so be missing from this audit? Checked on 2026-10-12
with `tools/ghidra/modcov.sh`, which writes `extract/modcov.txt`. **No.** Deadness is **[C]**; the "what it was"
column below is **[G]**, from a quick read of each range.

* **Entry points:**
  * the 274 rel32 hooks (284 minus 10 FALSE sites);
  * the handlers of script ops 0x17, 0x72 and 0x74..0x79 in the op table 0x410a3e;
  * the gap code in `.text`;
  * the jump-table entry 0x45bcc8;
  * the class-matchup table 0x4d2140, indexed at 0x43bdac.
* **Two independent traces from them:**
  * Ghidra's reference graph (`tools/ghidra/ModCoverage.java`), with the seeds disassembled first and raw dword
    pointers added;
  * a capstone descent (`tools/modcov.py`) that follows `jmp/call [reg*4 + T]` tables and pushed function or vtable
    addresses.
* **Indirect transfers in live mod code:** seven, all through tables whose entries are plain dwords:
  * the op 0x78 tables 0x4d0683, 0x4d0692 / 0x4d06aa and 0x4d0a97;
  * the 历史情报 painter's table 0x4d0f83;
  * the table 0x4db0cd;
  * two `call [eax+0x18]` vtable calls.
* **The search for what neither trace reaches:** every byte of the file was checked for references into it:
  * rel8 / rel32 branches;
  * dwords pointing into the range, or up to 0x40 below it (base + index).

| `.text2`, non-padding bytes | |
|---|---|
| total | 36,403 |
| reached as instructions (either trace) | 31,501 |
| data that live code reads (tables, strings, variables) | 1,793 in 23 ranges |
| dead code and data | 3,112 in 69 ranges |

No live instruction branches into a dead range, and no pointer in the file points at one. The only branch from
`.text` is 0x409ead, a FALSE site.

Four ranges match only by coincidence:
* 0x4d1060: its only references are live code reading the 0x4d1050 block in front of it;
* 0x4d2220: a table entry that points below it and jumps away first;
* 0x4d8186: the match is the bytes of the `call` at 0x407964;
* 0x4d8923: the match is the bytes of the `jnc` at 0x484646.

The dead ranges are mostly earlier versions of a hook, left behind when the author re-pointed it. Many end in a
`jmp` back to `.text`.

| Dead ranges | What it was [G] | Live version |
|---|---|---|
| 0x4d1060 (with its window procedure's remnants 0x4d120c, 0x4d1227, 0x4d1264 and title 0x4d0f7a "历史情报"), 0x4d1af7 | modeless 历史情报 window: class PPHHDB, 380×397 beside the map, 按顺序显示 (control 0x407) into [0x55eff4]. The original code still hides its HWND [0x4d1050] (ShowWindow 0x4298dd, 0x479c31), which stays 0 | the dialog with handler table 0x4d17f0 (B6 F3) |
| 0x4d014c, 0x4d0208 | save-path hook; a load setting [0x4ce004] = 1 | 0x4d009f, 0x4d0c29 (B6 F4) |
| 0x4d02cc, 0x4d030d | level-up grade count [0x4cf2b8]; 仙人果 count 0x55a400 | LevelUp 0x4e0100, item use (group 4 item 32) |
| 0x4d21bc, 0x4d2220 | class-matchup conditions (classes 7 / 13 / 20 / 24 × 1.5) before the entry was re-pointed to 0x4d2312 | table 0x4d2140 (B4) |
| 0x4d23c4 | 连续攻击 (effect 90) test | gap code 0x406b4f (B1 F18) |
| 0x4d2f60, 0x4d2fcd, 0x4d768e, 0x4d77fa, 0x4d8186 (+ 0x4d83c2), 0x4d6e77 (+ 0x4d6e58) | strike steps; the technique-flag reset [0x55ac1c..0x55ac50]; a "target strikes first" wrapper (0x4d74e4, [0x4d002c]) | strike step 0x433373 and the attack wrapper (group 3) |
| 0x4d385f, 0x4d3b9f, 0x4d3c39, 0x4d3ca2, 0x4d3ce4, 0x4d801e, 0x4d831c | technique banners picked by pid in code (【术】连理, 【术】锻造, 【术】枪母子, 【术】魔功, 【技】双雷引 …) | pid table 0x4d3c4c → banner table 0x4d8260, read at 0x4d3c25 |
| 0x4d48e3, 0x4d3e4d, 0x4d9029 | phase-start aura helper (0x43ff54, then 0x4011a9 on 0x497b04); unit actions 0x45778f(…, 7, …) | phase-start skills (B1 F1) |
| 0x4d6637 | catch-up divisor from the party's average level | LevelUp 0x4e0100 (group 4 item 32) |
| 0x4d9863 | 组阵 defence: families 39 / 46, +15 % per neighbour | formation getters (B4 §C) |
| 0x4d62e5 | on-hit status rolls (effect test, then random 75) | B1 F4 / F5 |
| 0x4d49ec, 0x4d4b03, 0x4d72ae | hit / damage hooks (back to 0x43c2cb, 0x43beb7) | B4 |
| 0x4d35a2 | area-code override (class 0x21 → 2) | 0x40783f (B2 §H) |
| 0x4d33b1 | move-record fragment ([0x4cfbfc]) | group 2 item 13 |
| 0x4d43fa, 0x4d4598, 0x4d4723 | redraw and GDI helpers (InvalidateRect 0x4d41a6, SelectObject, DeleteDC) | 0x47c8b6 → 0x4d418e (B6) |
| 0x4d503a (+ 0x4d7418), 0x4d525e (+ 0x4d5292) | membership tail with a scan of 0x4b0783; a three-line message box (strings 0x555718 / 0x555724 / 0x55570c) | — |
| 0x4d534c, 0x4d5408, 0x4d878f, 0x4d8923 (+ 0x4d895b), 0x4d8c13, 0x4d9331, 0x4e00c5, 0x4e01c5, 0x4e2184 | other hook bodies: info-window text colour; [0x4cf307] / [0x4cf310]; a target list via 0x4d8879; class tests (back to 0x420d3a); a person compare (back to 0x43d500 / 0x43d22e); a stat of person 20; "≥ 9" tests (back to 0x42139f / 0x4214b9); effect 50 (to 0x43f54c) | — |
| 0x4d31ad, 0x4dc696, 0x4d0ce9 | `eax / n`; [0x4dc0ff] = 0 (the 技能说明 state); a 12-byte table after a `ret` | — |
| 0x4d3210, 0x4d3368, 0x4d46da, 0x4d6874, 0x4d67b2, 0x4dbedf, 0x4dc550, 0x526061, and 2–3 byte remnants at 0x4d2979, 0x4d785b, 0x4d95fd, 0x4dc889 | stubs and leftovers | — |

## Skill owners

The table 0x4d3c4c is `u16[row] = pid`; the name is `str_ptr(0x4d8260, row)`. Static skills:

| pid | person | skill | pid | person | skill |
|---|---|---|---|---|---|
| 0 | 管毅 | 【招】苍龙过阵枪 | 22 | 徐茂功 | 【术】秘计 |
| 17 | 裴元庆 | 【招】尽命三锤 | 179 | 房玄龄 | 【术】房谋 |
| 5 | 伍云召 | 【招】踏破连营 | 185 | 杜如晦 | 【术】杜断 |
| 26 | 雄阔海 | 【招】横扫千军 | 137 | 杜伏威 | 【术】金刚 |
| 8 | 秦琼 | 【招】杀手锏 | 20 | 贾润甫 | 【术】市侩 |
| 14 | 姜松 | 【技】抽屉枪 | 3 | 尉迟恭 | 【技】血战 |
| 7 | 伍天锡 | 【招】威震八荒 | 4 | 单雄信 | 【技】怒目 |
| 19 | 罗成 | 【招】回马枪 | 136 | 东方伯 | 【技】双雷引 |
| 33 | 宇文成都 | 【技】凤舞九天 | 204 | 张善相 | 【术】枪母子 |
| 32 | 杨林 | 【技】龙吟 | 42 | 尚师徒 | 【术】神将 |
| 101 | 定彦平 | 【技】双雷引 | 11 | 樊虎 | 【术】行囊 |
| 34 | 李元霸 | 【技】盖马三锤 | 6 | 丁天庆 | 【术】水军 |
| 43 | 魏文通 | 【技】鬼门刀 | 10 | 盛彦师 | 【术】天运 |
| 44 | 新文礼 | 【技】横推八马倒 | 178 | 文士弘 | 【术】长缨奔破 |
| 67 | 李世民 | 【术】梦魇 | 50 | 弥天道人 | 【术】妖风 |
| 29 | 鲁明月 | 【术】贯石 (shown until R_12 gives her 云袖) | 122 | 马赛飞 | 【术】玄女神刀 |
| 31 | 柳周臣 | 【术】仙乐 | 91 | 盖雄 | 【术】血手飞钹 |
| 23 | 魏征 | 【术】明镜 | 35 | 苏烈 | 【术】逐影随行咒 |

**Runtime skills.**
* Script switches:
  * [0x55ac04] 【招】三板斧 (程咬金; R_11 sets it);
  * [0x55ac44] 【术】魔功 (R_13 sets 100 = 杨素);
  * [0x55ac48] 【术】波若 (罗士信 15);
  * [0x55ac60] 【术】锻造 (齐国远 16);
  * [0x55ac40] 【术】天魔 (never set).
* Fixed rules: pid 25 张公瑾 with class 41 → 【术】飞将军; pid 24 谢映登 with EV[3223] ≥ 3 → 【术】贯石.

**Dynamic skill slots.** Slot i is EV[3970+i] (u32 at 0x55ee08 + 4i), and its name is at 0x5559a0 + 32i. R_00
sets every slot to 1024 (nobody); later scenarios assign holders:

| slot | EV | skill | holder (script) | used by code |
|---|---|---|---|---|
| 0 | 3970 | 【术】连理 | 12 鲁明星 (R_21) | stat aura (B2 §B) |
| 1 | 3971 | 【术】云袖 连理 | 29 鲁明月 (R_23) | stat aura (B2 §B) |
| 2 | 3972 | 【术】并蒂 | 2 王君珂 (R_17) | attack bonus, sure crit (B2 §B, B1 F11/F12, B4 §G) |
| 3 | 3973 | 【术】天眼开 | 18 侯君集 (R_13) | no code or script reads it: label only |
| 4 | 3974 | 【技】煞 / 【招】夺面鞭 | 3 尉迟恭 (R_44) | 绝招 夺面鞭 (B5 F1) |
| 5 | 3975 | 【术】云袖 | 29 鲁明月 (R_12, cleared R_23) | label (the heal aura is hard-coded to pid 29, B1 F1a) |
| 6 | 3976 | 【技】煞 | 3 尉迟恭 (R_42..R_44) | label (the trigger is hard-coded to pid 3, B2 §G) |
| 7 | 3977 | 【术】市侩 相马 | 20 贾润甫 (R_20) | mounts +1 move (B2 §D) |
| 8 | 3978 | 【术】市侩 | 20 贾润甫 (R_03, R_13) | the slot itself is not read, but the buy price 0x426ff4 was rewritten in place (no jump into the mod sections): × 4 / 5 while pid 20 is in the party — the "八折" (rules.md §13.2) [C] |
| 9 | 3979 | 【术】百宝 | 9 尤俊达 (R_18) | equip any weapon/armour (B2 §I) |
| 10 | 3980 | 【术】舍命 | 13 王伯当 (R_02) | damage +30 % (B4 §F) |
| 11 | 3981 | 【招】回旋杀手锏 | 8 秦琼 (R_27) | 杀手锏 variant (B5 F1) |
| 12 | 3982 | 【招】杀手锏 | 8 秦琼 (R_03) | label (杀手锏 is hard-coded to pid 8) |
| 13 | 3983 | 【术】智将 / 【招】回马枪 | 19 罗成 (R_06…R_51) | label (智将 is hard-coded to pid 19, B4 §F) |
| 14 | 3984 | 【术】逐影随行咒 | — | (苏烈's range rule is hard-coded to pid 35, B3 F6) |
| 15–18 | 3985–3988 | 【术】烈魔 | 35 苏烈, 166 梁廷方 (R_49); 168 杜明方, 169 蔡建方 (R_50) | area + double cast (B3 F5) |
| 19–20 | 3989–3990 | 【术】弱杀 | never assigned | dormant (B3 F4) |

**Skills that need no engine work** (the code and the scripts were checked):
* Already ported: 金刚 (杜伏威 is immune to strategies; rules.gd `strat_hit`) and 秘计 (徐茂功's damage strategies
  +50 %; rules.gd `strat_damage`).
* Run by the battle scripts themselves, so they work through the ported script ops (not play-tested):
  * the enemy skills 妖风 (弥天道人; S_27, S_45);
  * 玄女神刀 (马赛飞; section "玄女飞刀" in S_41, S_42, S_44, S_45);
  * 血手飞钹 (盖雄; S_41, S_44).

## Missing and partial features

Grouped by area, roughly in the order they should be done. "→" points to the spec in the batch reports.

### 1. Script-visible battle state (story correctness; do first) — done

All of group 1 is ported (2026-10-11), with `t_battle` as its test; the spec moved into rules.md §9.1 and §10.6.
Doing it turned up one more gap in original code:
* **op 0x21 map_mark (1346 uses) sets and puts out fires.** The port treated it as "undo a terrain change".
  * Mode 0 is really ChangeTerrain to 0x1a 火 with overlay mark 0, e.g. S_02 "烧掉西边的桥".
  * Mode 1 undoes that change.
  * So burnt bridges and fire-blocked cells never appeared in the port.
* The phase start was also put into the original order: poll, then remove fallen units, then recovery and the rest.

1. **EV[10] "a unit's HP reached 0".**
   * The engine sets EV[10] to 1 on every kill: physical, strategy, script, and 暗杀.
   * It clears it at battle start, before each player command, and at the start of every AI action.
   * 27 battle scripts (S_23..S_57) have a "合并所有HP0撤退" section gated by `EV[10] ≥ 1`, which handles:
     * retreat lines and defeat conditions (e.g. 秦王战死, 李密被害, 管毅 → game over);
     * kill counters (EV[322..326]);
     * item rewards (S_23: get_item 91/89);
     * 程咬金's return.
   * The port never sets EV[10] and removes HP-0 units at once, so none of this runs.
   * Also, the pre-battle loop leaves EV[10] = 15 in the port.
   * → B1 F9, B2 §L, B3 F1, B5 F9. **Done:** `BattleActions.unit_fell`, `BattleStage.remove_dead`,
     `BattleInput.after_command`.
2. **暗杀 is a delayed defeat.**
   * A successful hit does 0 damage and marks the target.
   * Two phase-starts later the target drops to HP 1, with "%s被暗杀了！！" and EV[10] = 1.
   * The mark is cancelled if the assassin leaves the map.
   * The port defeats the target at once and gives kill EXP.
   * → B2 §K, B3 F7, B5 F11. **Done:** `BattleStage._assassination_countdown`.
   * The usability hook 0x4dbf8a never blocks: it compares the category, not the strategy, with 0x15. B5's
     guess that pending marks forbid a second cast was checked and is wrong.
3. **op 0x58 with alt ≠ 0 reverts a recorded map change** (puts out fires): 344 uses, 188 of them in S_15. The port
   does nothing. → B2 §O. **Done.**
4. **op 0x3b join is ignored in battles.** The port runs it, so e.g. 雄阔海 leaves mid-battle in S_36. → B2 §N.
   **Done:** "in a battle" now means scene mode 3 (0x40b922: from change_scene 3 on). So S_29's joins right
   after its change_scene 3 are ignored too.
5. **Saving is refused while [0x4ce004] == 0**, with "目前不可存盘。". op 0x74 sets this flag 473 times. → B6 F4.
   **Done.** A load sets the flag to 1 (0x4d0c29). The port's autosave is not gated.
6. **Script attr 8 = battle-unit MP**: `set_attr p 8 …` is used 11 times in S_17 and S_36. → B1 F19. **Done.**
7. **史录 write rules:**
   * no de-duplication of appended entries;
   * a category-0xff replace with no match adds nothing.
   * → B2 §M. **Done.**

### 2. Battle commands — done

All of group 2 is ported (2026-10-11), with `t_commands` as its test, in `battle/battle_commands.gd` (绝招, 围攻, 交给,
ChangeUnit) and `battle/battle_input.gd` (menu, 连续攻击, 连续策略, 再移动, the move record). Done with it, because
the 绝招 moves need them:
* **multi-target physical attacks** (item 28): `BattleActions.area_code` / `secondary_targets`;
* **critical shouts** (item 33);
* the **张善相 / 张公瑾 attack ranges** of item 23 (张公瑾's terrain cost came with group 3).

Corrections to the batch reports, found while porting:
* **再移动** (B5 F6) is offered after *every* finished command, not only after a move: each command ends with
  0x442718(6), which sets the "moved" flag too. The port skips it for a unit that fell in its own attack (the
  original would let it move).
* **围攻 siege break** (B5 F2): only 定彦平, 东方伯 and 姜松 (0x4d7b90 ≠ 0) strike first. A defender with 先手攻击 but
  another pid lets the siege run and only loses the final counter ([0x4d002c] stays 1).
* **踏破连营's charge** tests only x against the map width, and lets x == width through; the y test (0x4d4d5e) reads
  the top byte of the return address, 0. An off-map cell still ends the charge without moving: it has no unit and
  terrain 0xff, and the cost read 0x43f7cf → 0x443070 then takes family + 4's cost of terrain 15 城墙, which is 0xff
  for families 0..22 (伍云召 is 统军, 17 → 21; 23..26 would read past the table). So the charge stops at every edge, as the port's does.
* **The critical roll does not wait for a hit:** CalcDamage (0x43bc4b) makes the hit roll itself, and 0x405e03 then
  rolls the first target's critical whenever its HP > 0, so a miss can come with a critical (and its shout). The port
  rolled only on a hit.
* **冲锋** (0x43bee8 row) reads the player's recorded move, which is cleared after each command. The port's
  `move_origin` also gave AI moves and counters the bonus.
* **The 绝招 / op 0x69 banner** (0x4d6366) plays no sound and is shown over the darkened field (0x4d64ea … 0x4d6576).
  The port's banner played SE 37 and did not darken.

8. **绝招**, the mod's signature command. It needs a full MP bar and spends it all.
   * Users: 管毅, 程咬金 (三板斧, once learned), 伍云召, 雄阔海, 秦琼 (also 回旋杀手锏), 伍天锡, 罗成, 裴元庆,
     尉迟恭 (夺面鞭).
   * Each has its own moves, targets and rules: 100 % hit, forced crit, no double, no counter.
   * The battle also shows a name banner, critical shouts and longer strike animations.
   * → B5 F1, B4 §B, B1 F2/F14, B3 F12/F13. **Done**; B3 F13's wind-up frames of 管毅 and 张善相 came later, with
     the whole map attack animation (engine_notes.md).
9. **围攻** (player command and AI behaviour): adjacent melee allies join the attack and lose their turn; the
   defender counters once. Defenders with 先手攻击, 双雷引 or 抽屉枪 break the siege; 并蒂 always crits in 管毅's
   siege. → B5 F2, B3 F11, B1 F12. **Done.** The technique flags it sets for 双雷引 / 抽屉枪 ([0x55ac24],
   [0x55ac68]) work since group 3.
10. **交给**: hand your accessory to an adjacent ally. 樊虎's 行囊 hands out accessories from the warehouse instead.
    → B5 F3, B6 F6. **Done.**
11. **Command-menu layout:** 攻击 绝招 围攻 策略 交给 道具 待命, with the enable tests and icons. → B5 F4. **Done**
    (the port's menu has no icons). 策略 is now enabled under 穷计 and answers "正处于穷计状态。", as in the
    original (0x43dc21).
12. **Extra actions from item effects:**
    * 连续攻击 (effect 90): one extra attack;
    * 连续策略 (effect 83): a second cast at double MP;
    * 再移动 (effect 82): move again after acting.
    * → B5 F5/F6, B1 F18, B3 F8. **Done.**
13. **Full move-path record.** 回马枪, 锻造 and 波若 need it; the port keeps only the start cell. → B5 PARTIAL details.
    **Done** (`BattleStage.record_path` / `move_path`, in memory at [0x4cfbfc] / 0x4cfc00).

### 3. Character skills — done

All of group 3 is ported (2026-10-11), with `t_skills` as its test:
* `core/skills.gd` (the dynamic skill slots, the battle-map number, the "ally next to U" test);
* `core/person.gd` (宿痕, the 连理 auras, 并蒂, 相马, 天运, 百宝 / 樊虎);
* `core/rules.gd` (terrain, 双雷引's hit penalty, DoubleRate, 舍命 / 智将, 杜断);
* `battle/battle_actions.gd` (the attack wrapper and the techniques, on-hit skills, 并蒂's counters, 房谋, 烈魔,
  逐影随行咒, 统军, 锻造 / 波若, kill rewards);
* `battle/battle_stage.gd` (the phase-start skills, 明镜, effect 82's drain).

Done with it, because they sit in the same code: from item 31, effect 57 blocking the on-hit statuses, effect 84 in
counters, and the effect 34 / 86 move costs; from item 20, 节约MP (effect 49).

Corrections to the batch reports, found while porting:
* **双雷引** (定彦平, 东方伯 attacking) does not strike first. With [0x55ac54] = 1 the wrapper asks 0x4d74e4 whether
  the *target* strikes first, and it does whenever 定彦平 is in its range. 定彦平's counter is then forced to a
  double ([0x55ac54] = 2 after the first strike step). [0x55ac24] = 1 / 2 only picks the banner.
* **双雷引's −26 hit penalty** (cave 0x40762a) is reached only from HitRate's effect-55 branch (0x43b72f) and from
  the 绝招 rates (0x4d2f90). Other hits keep their rate. Only 轩辕神枪 has effect 55.
* **煞** repeats only while the target counters: the counter routine clears [0x55ac50] when there is no counter
  (0x4064b3 → 0x433610).
* **The wrapper skips the techniques**, and the "target strikes first" test, while the combat object's strike
  counter (+0x608) is still 1 from a strike sequence that ended on a second strike. Only the player's 攻击 resets it
  (0x407651), so the AI's techniques skip after such an attack.
* **盖马三锤** strikes three random units of the other side on the 8 cells around 李元霸 himself. It then puts 怯
  and 穷 on every unit of the other side within 4 cells, except those with effect 57 (0x4d8632). There is no
  counter. 0x4d8632 collects into a 15-entry stack list, the cells on the axes twice, and overruns it when more
  units are around; the port stops at 15.
* **怒目** sets the MP damage on a miss too, and that also lets the on-hit statuses through (the block runs when the
  HP or the MP damage is ≠ 0).
* **波若** computes 400 − w on the double word that starts at the stat word. Between 301 and 400 the chance
  overflows, so the stat always grows.
* **The phase-start auras** pick sides by colour (U+5: 0 and 1 against 2 and 3), not by slot. **魔功** always
  poisons: 0x4251e1 zeroes the context's damage, so code 0x70 never fails.
* **Kill rewards** also run after a cancelled menu. 尉迟恭's MP is capped at base MP (+15 逍遥巾 / +30 诸葛巾) even
  when nobody fell, which can lower MP that came from other equipment.
* **[0x48baec]** is 0xffff in towns, written by the picture cache 0x426c6a, and the port did not track it. It is now
  the battle map's number from `create_battlefield` on, and 0xffff when a story file starts.
* Original code found on the way: 暗鬼 (22) gives the caster the MP it took (0x423017). The MP is paid after the
  strategy's effect (0x422f0d).
* The blocks 0x4d768e and 0x4d81e0 are dead code (no branch reaches them). The live strike step is 0x433373.

14. **【技】 attack techniques.**
    * Trigger chance: min(50·morale(att)/morale(def), 100) % at the start of an attack, for the attacker's pid.
    * The technique's banner is shown at the strike.
    * Techniques:
      * 龙吟 (杨林): −1 weapon or armour level;
      * 鬼门刀 (魏文通): move buff 0 + 怯;
      * 怒目 (单雄信): drains all MP;
      * 盖马三锤 (李元霸): 3 blows at the enemies around him, then 怯 + 穷 within 4 cells, no counter;
      * 凤舞九天 (宇文成都): full-damage splash;
      * 横推八马倒 (新文礼): area code 0xa;
      * 煞 / 血战 (尉迟恭): up to 3 attacks while the target counters;
      * 双雷引 (定彦平, 东方伯): the target strikes first, then a forced double counter (−26 hit against effect 55);
      * 抽屉枪 (姜松): pre-emptive forced double.
    * → B2 §G, B3 F10, B1 F3/F15/F16/F17, B4 (0x43b72f). **Done** (`BattleActions.attack_cmd`).
15. **Phase-start auras** (3×3 around the owner, own side unless noted):
    * 云袖 (鲁明月): HP +min(Lv+50, missing);
    * 仙乐 (柳周臣): MP;
    * 神将 (尚师徒): attack buff 6;
    * 雄师 class 42 (尉迟恭, 杨林, 杨素, …): morale buff 6, own side (resolved in this audit);
    * 魔功 (杨素): poisons adjacent enemies;
    * 天魔: dormant.
    * → B1 F1, B3 F9. **Done** (`BattleStage._phase_skills`).
16. **明镜 (魏征):** adjacent allies with an ailment are fully cured at their phase start. → B4 §H. **Done.**
17. **Stat auras and 并蒂:**
    * 连理 / 云袖 连理: +25 % … +5 % to attack/defence/agility/morale near the partner;
    * 并蒂 (王君珂): +8 % attack per hit 管毅 took in the enemy turn, with counters at 0x55ee00..07.
    * → B2 §B, B4 §G, B1 F11. **Done** (`Person.stat`, `BattleActions._bingdi_count`).
18. **舍命 (王伯当):** +30 % damage below 60 % HP. **智将 (罗成):** +15 % of 精神 to every damage value, even on a
    miss. → B4 §F. **Done** (`Rules.damage_post`).
19. **杜断 (杜如晦):** +20 strategy hit. The real roll tests the target's side; the forecast tests the caster's.
    → B4 §D. **Done.**
20. **房谋 (房玄龄):** half MP next to him. Also missing: the original 节约MP (effect 49). → B3 F3, B6 F5.
    **Done** (`BattleActions.strategy_cost`), with 节约MP.
21. **Strategy skills:**
    * 烈魔: bigger area, and damage/status strategies run twice;
    * 逐影随行咒 (苏烈): every range becomes 13.
    * → B3 F5/F6. **Done.**
22. **On-hit skills:**
    * 梦魇 (李世民): 迷失 on targets of his level or lower;
    * 张善相: poisons on every attack, on maps ≤ 34;
    * 贯石 (谢映登): MP lost with damage taken, and attack derived from MP.
    * → B1 F6/F7/F8, B2 §A. **Done.**
23. **Terrain and range rules per character:**
    * 单雄信 + 板角墨麒麟: all terrain costs 1;
    * 飞将军 (张公瑾): cost −1 and range 4 (the range is done);
    * 水军 (丁天庆): water costs 1 and gives 110 %;
    * 枪母子 (张善相): range 12 (done).
    * → B5 F10. **Done.**
24. **Other skills and items:**
    * 相马 (贾润甫): mounts +1 move → B2 §D;
    * 天运 (盛彦师): +1 to a random stat per level → B2 §E;
    * 锻造 (齐国远) / 波若 (罗士信): effects on allies the unit passes through → B5 F7;
    * 百宝 (尤俊达): any weapon or armour, and 樊虎 may not equip accessories → B2 §I;
    * 秦琼 as 统军 gets 补给 and 救护 → B6 F5.
    * **Done.**
25. **Kill rewards:** 辰屑 drops into EV[3007..3009] (crafting materials used by the scripts), and 尉迟恭 gains MP
    per kill. → B5 F8. **Done** (`BattleActions.kill_rewards`).
26. **宿痕 weapon scaling of town stats** (秦琼, 管毅, 程咬金, 柴绍, 罗成, and 王伯当's armour), gated by EV[3181..3189].
    → B2 §A. **Done** (`Person._scar`).
27. **Dormant in the shipped game** (implement for fidelity only):
    * 轩辕神枪 paralysis (EV[2700] is never written) → B4 §A;
    * 弱杀 → B3 F4;
    * 天魔 → B1 F1e;
    * effect-82 MP drain (value 0) → B4 §I;
    * enemy-slot units with AI code 7 commandable → B5.
    * **Done**, all five.

### 4. General battle rules

28. **Multi-target physical attacks.**
    * Area/penetrating weapons apply to classes 6–8, 10, 11, 17, effect 43, and the skill overrides including 文士弘 长缨奔破.
    * Secondary targets take ½ damage for area codes 1–3 and 12, and full damage for line codes.
    * The port only ever hits one target.
    * → B1 F13, B2 §H. **Done with group 2.** The AI's target score counts them too (0x438d96, rules.md §10):
      +10 per other unit the strike would fell, +4 per one it takes ≥ 10 % of, −4 when it hits nobody else.
29. **反应/士气 equipment bonus is a percentage of the stat, not a flat add.** This affects hit, double and crit
    rates. → B2 §C. **Done** (`Person.stat`; the bonus is a percentage of the plain stat word).
30. **组阵 formation bonuses:** +15 % per adjacent same-family ally. Attack for classes 46/47, defence for 39/46,
    agility for 18–20. → B4 §C, B1 F10. **Done** (`BUnit.formation_*`, used by CalcDamage, HitRate and
    DoubleRate only).
31. **Item-effect rules:**
    * effect 57 blocks every on-hit status → B1 F4 (**done with group 3**);
    * effect 37 uses six independent rolls → B1 F5 (**done**; the on-hit statuses now roll in the original's
      order, effect 34 after 震天骑);
    * 笼屉 (effect 62) eats a 馒头 after ≥ 100 damage → B1 F8, B3 F2 (**done**: physical hits from 100 down for
      both sides; after a strategy a red unit from 100 down, any other at once; red units eat from the bag, others
      free);
    * 怀恨攻击 (effect 87) hit counters → B4 §E, B5 F12 (**done**, in Mem 0x55a500; the count goes to the entry
      [0x55a6cc] of the target list, so on an area strike to the previous target);
    * effect 84 doubles in counters too → B1 F16 (**done with group 3**);
    * effect 86 cost −1 and effect 34 cost 1 → B5 F10 (**done with group 3**);
    * 太保令 permanent +2 → B2 §Q (**done**).
32. **Level-up:**
    * HP/MP catch-up penalty for party members above the average level;
    * the default message is only "X升为N级。" (details behind the 升级显示能力成长 option);
    * "学会了策略「…」！" messages.
    * → B2 §E/§F. **Done**, with the unit's HP / MP growth inside LevelUp (0x4e0100), the unit capped when a
      maximum drops (0x4d6710), the HP / MP jitter rolls that are drawn and thrown away, gains as new − old, and the
      grade bonus as the one global count [0x4cf2b8]. The option itself is group 5's 环境设定; the port reads
      byte [0x4dbe25] (0 by default).
33. **Original-code gaps found on the way:**
    * critical-hit shouts → B1 F2 (**done with group 2**);
    * 引导攻击 (effect 46) for player attacks → B5 row 0x43db51 (**done**: the player's attack chains while the
      target falls, the AI's attacks once more; both take 0x436586's pick, the last unit of the range or the one in
      [0x4b2c28]);
    * 策略模仿 (effect 51) → B6 F5 (**done**, in the 策略 menu list; the AI's list and the 武将情报 page keep the
      plain class list, as the original's do);
    * 狂澜 against the army leader keeps applying modifiers, and no caller passes `leader_slot` → B4 extra notes
      (**done**: the commander is R+0x3d06, kept in Mem 0x496c96);
    * SetExp keeps levelling past 70 → B2 notes (**done**);
    * the empty-cell terrain popup → B5 row 0x4559ba (**moved to group 5**: a window that needs the strategy
      element icons, as 地形情报一览 does);
    * per-phase experience in Regen (0x43cf26, red units only): effect 64 for the person, 轩辕宝鉴 (22) for the
      weapon, 天闻录 (23) for the armour, each value × ((100 + EXP bonus) mod 256) / 100 (**done**).
    * Also: a counterattack rewrites the combat object 0x4927f0 (0x4064f1 → 0x4061fc), as eex.md says; the port
      kept the first attacker there. 恢复HP / 恢复MP items of value 0xff fill up (0x43c42e): 鸡腿 healed at most 255.
      仙人果 gives its value as experience through SetExp and counts in 0x55a400.

### 5. Shops, menus and windows — done

All of group 5 is ported (2026-10-11), with `t_shop` and `t_menus` as its tests; the spec is rules.md §13.

34. **Shops** (toolbar 卖出 / 买进 / 装备 with the flags 0xf3 / 0xf2 / 0xf1): 买进 327 with 输入数值 320, 卖出 329 and
    the merchant window; 装备 328 with the person table 0x4dbdb0, the stat preview and "仓库装备现存量 N/200". → B6 F1.
    **Done** (`ShopWindow`, `EquipWindow`, `PersonPanel`, `MerchantBox`, `ItemCols`). Found on the way: equipment is
    bought for the chosen person and worn at once; the 八折 of 贾润甫 is real (see the skill table above); the bonus
    fruit is certain; the "warehouse full" text is the exe's Shift-JIS string, shown as it reads on a Chinese system.
    The port's own out-of-battle 道具 menu and its menu 装备 had no original and are gone.
35. **持有道具一览 (325)** and **地形情报一览 (335)**. → B6 F1a, F2. **Done** (`ItemListWindow`, `TerrainWindow`).
36. **历史情报** (order, colours, 按顺序显示, also in battle). → B6 F3. **Done** (`HistoryWindow`).
37. **环境设定** on the title and in the menu, kept in Niuniu.wa bytes 1..5 and 0x6b. → B2 §J, B6 F8. **Done**
    (`Settings`, `SettingsWindow`): BGM / SE switches, message speed (typewriter, dialogue holds, timed boxes,
    captions), 会话窗口不自动关闭, move speed (battle steps by family, story frame period), 升级显示能力成长, skins, the
    minimap at battle start. The save loader 0x40cc65 skips GS+0 / +8 / +0x10 (three NOPed stores at 0x40cd30, 0x40cdc4,
    0x40cdd8), so the options are global. The title is 新游戏 / 读取进度 / 环境设定 / 结束游戏 with CD track 18.
38. **Sortie**: the 32-pid table with the j = 0 quirk and the exclusion slot; dialog 236 with the 战场位置 preview 333.
    → B2 §P, B5 F13. **Done** (`ScriptHost.build_sortie`, `SortieScreen`, `SortieMap`).
39. **Menu commands without a patch**: 战场缩小图, 检索未执行部队, 版本情报, 部队情报一览 with the 我军 / 敌军 switch.
    **Done** (`Minimap`, `BattleInput.find_unit`, `MsgBox.version`, `UnitListWindow`). Also from the menu audit:
    结束回合 and an all-done phase ask "结束所有部队的命令吗？"; 胜利条件 shows the text op 0x19 stored (op 0x19 itself
    shows nothing) and blinks op 0x5b's area again; op 0x5b blinks its area instead of keeping it drawn; op 0x08
    设定结果 is GS+2, which gates the town menu, toolbar and clicks.
40. **Cosmetic**: the empty-cell terrain popup, the choice-box portrait with "1."–"3.", SE 2 on 不能对自己使用, the
    cursor "(x:y) terrain" readout. **Done.** (技能说明 stays out on purpose, B6 F7.)
41. **Found while doing this group** (original code, rules.md §13.5–§13.7):
    * captions op 0x2c: a1 = 0 clears, a2 starts a line, a3 pauses — the port had a2 / a3 as "wait" / "clear";
    * timed boxes (style 2) for the original's messages; ops 0x17 / 0x18 show a timed box (and the pane text in towns);
    * unit actions 0x45778f: the port's kind numbers were wrong (1 is cheer, 2 defend, 3 hurt, 11 / 12 turns);
    * battle items: the use animation, the fruit / 仙人果 / 印绶 refusals and effects, the picker messages;
    * weapon / armour level notice per level with its panel; get_item's order, the 255 stack limit and its warning,
      the warehouse-full 卖出 window; the op 0x59 reward screen (no "得到了" boxes, a missing level from person 0's);
    * terrain changes: the sounds by new terrain, the holds with SE on, op 0x58 arg 6 as "quiet", EV[0] as "no patch";
    * battle steps play their sound (0x43f38b).

### 6. Found in the 2026-10-14 review

Differences the review of 2026-10-14 found by reading the decompile; each is ported with a check.

42. **Op 0x78 writing a unit's HP** (field 33) runs 0x4d678c (0x4d0653): HP 0 or less (signed) is a script kill
    0x4121b0, EV[10] = 1 and RemoveUnit at once. **Done** (`ScriptHost.unit_hp_written`, `t_battle`).
43. **Buff and debuff percentages from EV[3000..3003]**: mod code in a .text gap at 0x44d158, not in the site table;
    see rules.md §2.2. **Done** (`BUnit._buffed`, `t_rules`).
44. **Grade of a level-up without the jitter, and Promote**: 0x4072fc's ≥ 70 test reads a stale class pointer, so
    abilities below 80 grade 2 in Promote (0x4089cb) and in LevelUp without the jitter (rules.md §2). Promote also adds
    to the class with no tier cap and grows by 0x4089cb's sum instead of LevelUp. **Done** (`Person.stale_grade`,
    `promote_growth`, `BattleDeploy._promote`, `t_rules`).
45. **Experience for every target of a strike**: a miss gives the attacker the no-kill experience; the weapon's is
    judged per target; the armour of each red target gains at every strike, 3 only when the attacker is the lower
    (rules.md §8.1, §8.4). **Done** (`BattleActions.strikes`, `_weapon_gain`, `_armor_gain`, `t_rules`).
46. **Range visiting order**: the AI's ties, its fallback target and 引导攻击's next target follow 0x436586's order
    (up, right, down, left first), with the origin first for own-side searches; a unit on terrain it cannot stand on
    does not move (0x438308). **Done** (`shapes.json` from `conv_data.py`, `Shapes.range_seq`, `t_rules`).
47. **Questions and refusals of the original's UI**:
    * 保存 / 读取 ask "进度No.%2d: %s，\n可以保存吗？" / "…可以读取吗？" (0x41b16a, 0x41ad06; 是/否 boxes captioned 保存 /
      读取), a save ends with "保存完毕。" (0x41b4d9); the mod's autosave skips both only around its own call (0x4d4f80).
      结束游戏 asks "结束「瓦岗山异闻录」么？" (0x474ba7).
    * Strategies are cast as soon as the target is picked (0x42335b: picker, 0x420422, cast); the port's
      "执行（成功率 N%）/ 取消" question had no original.
    * The picker 0x45533d: nobody of the wanted side in range → "范围内没有敌军部队。" / "范围内没有我军部队。" and SE 1;
      outside the range SE 2 + "不在范围之内。"; the wrong side SE 2 + "不能攻击我军部队。" / "这是敌军部队。"; a cancel SE 1.
      Used by 攻击, 绝招, 围攻, 交给, items and the strategy handlers that pick a unit.
    * The move pick (0x43d671): SE 2 + "因为有其他部队，所以不能移动。" or "不是移动范围。", and it stays open. A unit
      that is not commanded now shows its ranges, then a click gives SE 2 + "这是非受控部队" (any unit without code
      7 or with flag 0x80; "这是敌军部队。" needs a slot ≥ 115 since the mod), "已经行动完毕。", "正处于混乱状态。" or
      "正处于迷失状态。", a cancel SE 1.
    **Done** (`main.gd`, `SystemMenu`, `BattleInput`; `t_menus`, `t_commands`). The original keeps 100 save slots
    ("No. 0" … "No.99", 0x41a518); the port keeps 10.

### Deliberate differences (port design, keep unless asked)

* **Autosave:** the original saves silently into slots 0..4 in rotation after every player phase; the port keeps
  its own autosave file instead. → B5 row 0x44e1c9.
* **Story videos:** 001.wmv and later cannot be skipped in the original (B2 §R). The port lets every video be skipped.
* **Move pick:** a click on another unit that can be commanded now takes that unit up; the original answers it as
  an occupied cell. With touch controls a tap outside the highlighted cells cancels a pick or a range view
  instead of bringing the original's refusal message.
* **Windows:** the port uses modal windows, one list for the menu bar and text buttons in the top bar for the
  toolbar. A right click on an empty battle cell opens that list (the original asks to end the phase; the list's
  first item does). 战斗时，窗口自动最大化 is shown but has nothing to size.
* **Looks:** the dialogs are drawn in the port's style; the skin tints their background, and the original's dark
  red / black list texts are lighter on the dark panels. The Win32 merchant and 武将情报 windows that the original
  keeps open beside the map are modal here.
* **Deterministic RNG mode** (0x47fb14): dead in the original, since its checkbox does not exist.
* **Ending and game over:** the original exits the program after the credits (op 0x0f) and after the game-over
  question (op 0x6a; 是 asks its launcher to start the game again). The port goes to the title; 否 quits on desktop.
* **Resource meter:** op 0x3a's kind-2 pane sits at (290, 25), left of the port's 菜单 button, and above the
  buttons (y 2) while the town toolbar shows, not at (342, 25).

## Doc corrections made with this audit

* rules.md §11: the dynamic skill list is EV[3970..3999], and the scripts fill it. The old text said EV[898..927]
  and "never written", and wrongly concluded that 管毅 shows 【术】连理.
* rules.md §4.2 and §6.1: [0x4cf314] is the "绝招 running" flag (set by 0x4d3007), not a duel mode.
  * The 张善相 / 张公瑾 range overrides apply outside a 绝招.
* rules.md §4.4: effect 84 also doubles in counterattacks.
* rules.md §1.1: person byte +0x2a is the membership flag.
* rules.md §11: the 技能说明 button is mostly, not wholly, outside the window.
* eex.md op 0x12: arg1 is the portrait person.
* shapes.json area 11 is `caster_ring`, which shapes.gd called `caster8`; it now reads the data's name and keeps the
  target, as 0x4362e7 does (the target, then the caster's 8 neighbours besides it). No strategy uses area 11.

## Batch reports

The six reports as written by the audit, lightly edited. Port paths are relative to `game/src/` unless they are
given in full.

### B1 — Attack sequence and damage (0x401000..0x406fff)
Source: wg2025/wagan.wa. The Godot port is in game/src. All 51 B1 sites were checked against the disassembly (rd_trace/disx) and the port.
Skill owners as in [Skill owners](#skill-owners). Dynamic skill slots EV[3970+k] (0x55ee08+4k) are filled by the scripts:
3970=12 鲁明星, 3971=29 鲁明月, **3972=2 王君珂 (并蒂)**, 3973=18, 3974=3, 3975=29, 3976=3, 3977/3978=20, 3979=9, 3980=13, 3981/3982=8,
3983=19, 3985=35, 3986..3988=166/168/169 (from `int_var_op 2 39xx 2 0 pid` in extract/eex_txt).

Notation: U = 0x24-byte battle unit, P = person record, ctx = attack context 0x4927f0 (ctx+0 = attacker slot, +1 = current target,
+4 = attacker pid, +8 = attacker P, +0xc = attacker U, +0x10.. = target list (0xff end), +0x84[i] = HP damage, +0x254[i] = MP damage,
+0x424 = area-attack code, +0x604 = crit flag, +0x608 = strike counter). [0x492e04] = counterattack depth. "Mor/Agi" = battle-unit
morale/agility with buffs (0x43f67f / 0x43f631). [C] = confirmed from code, [G] = guess.

Much of the mod's code also sits in gaps inside .text (0x401118..0x40133b, 0x406b16.., 0x407600, 0x407bc8, 0x40913d, 0x427025,
0x433359..0x433418, 0x43d108). Those `jmp`s are not in the inventory (target in .text), but they run as part of the features below.

#### B1.1 Site table

| site | original function (what it does) | mod change | feature | status | port evidence or missing spec |
|---|---|---|---|---|---|
| 0x401141 | 0x401118: mod-written function in .text. StatusRecovery 0x43c7d6 calls it (0x43c7ec) for each on-map unit at the start of its side's phase, before that unit's status recovery. It sets up the strategy ctx 0x497af8 for the unit (0x418c99 → 0x4251e1), then dispatches by pid/family | pid 29 → 0x4d3dc5: heals the own-side units in the 8 surrounding cells by min(Lv+50, MaxHP−HP) | 鲁明月 【术】云袖 (每回合恢复相邻我部HP), F1 | PORTED | battle_stage.gd `_phase_skills` (云袖), run per unit in `_phase_start_effects` before `_status_recovery`. Spec F1a |
| 0x40114f | same | pid 31 → 0x4d4dba: MP += min(Lv/4+1, MaxMP−MP) for the own-side units in the 8 surrounding cells | 柳周臣 【术】仙乐, F1 | PORTED | battle_stage.gd `_phase_skills` (仙乐). Spec F1b |
| 0x40115f | same | `inc byte [0x4d4397]` around the 天魔 call | (flag only) | N/A | 0x4d4397 is only inc/dec'd here, never read (raw xrefs 0x401161/0x40116f only) [C] |
| 0x401168 | same | pid == [0x55ac40] → 0x4d4398: code 0xaf (豪气: 爆发/士气/攻击(精神)/防御 up) on adjacent own-side units via 0x4224a8 | 【术】天魔, F1 | PORTED (dormant) | battle_stage.gd `_phase_skills` (codes 0x31/0x33/0x35/0x37 through `_stat_code`). No script writes 0x55ac40 (initial 0x4000 matches no pid), so it never fires in the shipped game. Spec F1e |
| 0x40116d | same | `dec byte [0x4d4397]` | (flag only) | N/A | as 0x40115f |
| 0x401181 | same | pid == [0x55ac44] → 0x4d4992: code 0x70 poison on the opposite-side units in the 8 surrounding cells (via 0x4224a8) | 【术】魔功 (R_13 #154 sets [0x55ac44]=100 杨素), F1 | PORTED | battle_stage.gd `_phase_skills` (中毒 through `change_unit`). Spec F1d |
| 0x40118f | same | pid 42 → 0x4d4e38: attack buff byte U+0x18 = 6 on adjacent own-side units | 尚师徒 【术】神将, F1 | PORTED | battle_stage.gd `_phase_skills` (神将 and 雄师). Spec F1c. The same function also does family 16 (class 42 雄师) → 0x401197 → in-.text 0x427025 → 0x4d3f88: U+0x1c (morale) = 6 on adjacent own-side units (spec F1f) |
| 0x4011c8 | 0x4011a9: mod-written helper in .text, "gather the units in the 3×3 around a unit" (ecx = ctx+0xc out list) | 0x4d4e1c: start x−1, y−1 clamped at 0 | helper of F1 | PORTED | battle_stage.gd `_aura_units` (area definition) |
| 0x401240 | 0x4011a9 | 0x4d3197 = unit index → U pointer | helper of F1 | PORTED | part of F1 (`_aura_units` returns the units) |
| 0x4012f7 | 0x4011a9, mode 1 | 0x4d4b2c → 0x4d4966(U, Lv(owner)+50) = min(amount, MaxHP−HP), stored negated in ctx+0x84[n] | helper of F1a (云袖) | PORTED | `_phase_skills` (云袖's callback) |
| 0x401300 | 0x4011a9, mode 3 | 0x4d4b41 → 0x4d4928(U, Lv(owner)/4+1): MP += min(amount, MaxMP−MP) applied at once | helper of F1b (仙乐) | PORTED | `_phase_skills` (仙乐's callback) |
| 0x4016b7 | 0x4016ab: reset of the Xben effect-animation player 0x4917b0 | 0x4d3e6c: memsets +0xb4/+0x154/+0x1f4 (0xa0 each), +0x294 = 0 (return value unused) | anim plumbing | N/A | engine plumbing. The port has its own effect player |
| 0x403181 | 0x403179: static constructor of the global 0x4917b0 (Xben animation player) | 0x4d3ed4: base ctor 0x4033b0 + zeroing fields | anim plumbing | N/A | C++ global ctor (the original ctor code area 0x401000.. was overwritten by the mod) |
| 0x403a79 | 0x40397d WeaponExp(target i) | 0x4e00a5: gain = 1 if weapon level P+0x2f ≥ 9 | equipment-exp tweak | PORTED | battle_actions.gd `_equip_exp` (`if lvl >= 9: gain = 1`) |
| 0x403b84 | 0x403a85 ArmorExp | 0x4e01a5: gain = 1 if the defender's armour level P+0x32 ≥ 9 ([ebp+0x20] = caller 0x405e03's target P) | equipment-exp tweak | PORTED | battle_actions.gd `_equip_exp` |
| 0x40582c | 0x405744: attack presentation. On a critical (ctx+0x604) with chance(25), the attacker shouts its critical line (0x40c02f → 0x45965d dialog) | 0x4d3481: while a 绝招 runs ([0x4cf314]≠0): pid 1 程咬金 never shouts, everybody else always shouts | critical-hit shout (+绝招 variant), F2 | PORTED | battle_actions.gd `_crit_shout`, called from `strikes` on a critical. Spec F2 |
| 0x4058cb | 0x405889: per-target on-hit effects + HP/MP application, loop head | 0x4d72e0: loop end; then, unless ctx+1 has effect 57: [0x55ac1c]==1 → 龙吟; elif [0x55ac38]==1 → 鬼门刀. This runs before the hit/damage test, so it also works on a miss | 杨林 【技】龙吟 / 魏文通 【技】鬼门刀, F3 | PORTED | battle_actions.gd `_technique_hit` at the head of the apply loop in `strikes`; triggers in `attack_cmd` / `_trigger`. Spec F3 |
| 0x405915 | 0x405889 | 0x4d724c: a target with effect 57 (化解攻击效果) gets none of the on-hit statuses | effect 57 blocks on-hit statuses, F4 | PORTED | battle_actions.gd `strikes` calls `_on_hit_effects` only for targets without effect 57 (张善相's poison stays outside) |
| 0x40591d | 0x405889 | 0x4d62c1: effect 35 混乱攻击 → 混乱 only with chance(60) | effect 35 | PORTED | battle_actions.gd `_on_hit_effects` |
| 0x4059f1 | 0x405889 | 0x4d0c6e: effect 37 随机属性攻击 = six independent rolls scaled by the attacker's weapon level | effect 37 (八棱梅花锤), F5 | PORTED | battle_actions.gd `_random_statuses` (six rolls). Spec F5 |
| 0x4059f9 | 0x405889 | 0x4d8caf: attacker pid 67 → 迷失 (0x40) on targets whose level ≤ the attacker's level | 李世民 【术】梦魇, F6 | PORTED | battle_actions.gd `_on_hit_effects` (pid 67). Spec F6 |
| 0x405a6a | 0x405889 (end of one target's effects; also the target of the miss and effect-57 skips) | 0x4d568d: attacker pid 204 and battle map [0x48baec] ≤ 34 → poison | 张善相 poison, F7 | PORTED | battle_actions.gd `strikes` (pid 204, `Skills.MAP_NO` ≤ 34, hit or miss). Spec F7 |
| 0x405ae4 | 0x405889, HP application | 0x4d7e61: adds the damage to target index 0 to the accumulator [0x4abfb2] (both strikes) | 吸血攻击 (effect 81) accumulator | PORTED | battle_actions.gd `strikes` (`total_damage`: the first target, both strikes) |
| 0x405ba2 | 0x405889, after HP/MP and armour exp: branch on HP==0 | `call 0x4d3197` (unit pointer, code compaction that makes room for the two hooks below) | — | N/A | same behaviour as the inline imul/add |
| 0x405bb0 | 0x405889, target alive and damage > 0 → original effect 62 使用馒头 (auto-eat item 0x57 馒头) | 0x4d681c: (a) target pid 24 with [0x55e25c] ≥ 3 → MP −= damage (min 0); (b) effect 62 now needs HP+100 ≤ MaxHP | 谢映登 【术】贯石 MP loss; 笼屉 auto-馒头 (also missing in base), F8 | PORTED | battle_actions.gd `strikes` (贯石's MP loss; 笼屉 → `eat_bun`). Spec F8 |
| 0x405bb7 | 0x405889, target HP == 0 | 0x4d67b8(1): EV[10] = 1 | kill flag for the scripts' "合并所有HP0撤退" sections, F9 | PORTED | battle_actions.gd `unit_fell` sets EV[10] = 1; cleared at battle start (battle_stage.gd), in `BattleAI.act` and at the player's command (battle_input.gd). Spec F9 |
| 0x405c75 | 0x405c6c: end of the attack (HP display for the attacker, EXP, weapon exp) | 0x4d7e01: effect 81 → attacker HP = min(HP + acc/2, MaxHP); also "recoil" [0x4d0d5d] | 吸血攻击 | PORTED | battle_actions.gd `strikes` (effect 81 after the strikes). [0x4d0d5d] is only ever written with 0 (0x406b51, 0x4d0d64), so the recoil branch is dead [C] |
| 0x405cda | 0x405c6c | `mov byte [0x4d0d5c], 0` (reset of the AI steps-moved counter written at 0x43aac3) | (vestigial 冲锋) | N/A | its only reader, 0x409102 (dmg += steps·30), is not referenced by any jmp/call (raw rel32/jcc scan). Effect 89 now uses 0x4d8d95, which the port has |
| 0x405cf2 | 0x405ce6 DoubleRate: a = Agi(att) | `call 0x4d9818` = Agi with formation bonus | 格斗兵 formation agility, F10 | PORTED | rules.gd `double_rate` uses bunit.gd `formation_agi`. Spec F10 |
| 0x405d0a | 0x405ce6: d = Agi(def) | `call 0x4d9818` | F10 | PORTED | as above |
| 0x405d93 | 0x405d69 CritRate: m = Mor(att), n = Mor(def) | 0x4d1d30: n = Mor(def) as before, plus side effects: 并蒂 hit counters, deferred 轩辕神枪 paralysis, EV[3210] = m·15/n (write-only) | 王君珂 【术】并蒂 bookkeeping; 管毅 轩辕神枪 counter-paralysis, F11 | PORTED | battle_actions.gd `_crit_rate` → `_bingdi_count`, `_xuanyuan`; EV[3210] (write-only) is left out. Spec F11 |
| 0x405daa | 0x405d69: effect 41 → 100 | 0x4dc7fd: else if the counter depth ≠ 1, the attacker holds dyn skill 2 (EV[3972]=王君珂) and the last player-selected unit [0x4dc7dd] is 管毅 → 100 | effect 41 (ported) + 并蒂 sure crit in 管毅's 围攻, F12 | PORTED | rules.gd `crit_rate` (effect 41); 并蒂 in battle_actions.gd `_crit_rate` (`st.range_unit` = [0x4dc7dd], set in battle_input.gd). Spec F12 |
| 0x405e97 | 0x405e03 per-target damage: mode = counter + (secondary target ? 2 : 0) | 0x4d93e5: secondary targets get the halving (+2) only for area code 1..3 or 12; codes 0, 4..11, 13+ do full damage | multi-target physical attacks, F13 | PORTED | battle_actions.gd `area_code`, `secondary_targets`, `_halved`; `strikes` adds mode 2. Spec F13 |
| 0x405ea0 | 0x405e03 | 0x4d93af: attacker pid 33 → +2 only when area code == 1, so 凤舞九天 (area 2) splashes at full damage | 宇文成都 【技】凤舞九天, F13 | PORTED | battle_actions.gd `_halved` (pid 33). Spec F13 |
| 0x405efb | 0x405e03: crit roll if target HP > 0 (even after a miss) | 0x4d34c9: while a 绝招 runs: pid 7 / 26 → never crit; everybody else → forced crit ×3/2 that skips the effect-57 nullification | 绝招 crit override, F14 | PORTED | rules.gd `crit_rate` (绝招 branch); battle_actions.gd `strikes` keeps a 绝招's critical against effect 57. Spec F14 |
| 0x405fa6 | 0x405e03: original target effect 0x40 (MP takes the damage) check | 0x4d8150: [0x55ac4c]==1 → MP damage ctx+0x254[i] = target's whole MP; HP damage unchanged | 单雄信 【技】怒目, F15 | PORTED | battle_actions.gd `strikes` (`mps` while T_NUMU is set). Spec F15 |
| 0x4061df | 0x406181 DoubleCheck: failed chance(DoubleRate) → no 2nd strike | 0x4d88df: [0x55ac68]==1 forces the 2nd strike; flag cleared | 姜松 【技】抽屉枪 pre-emptive double; plus in-.text 0x407600 (双雷引 forced double, counter-depth check dropped), F16 | PORTED | battle_actions.gd `_double_check`, rules.gd `double_rate` (effect 84 also in counters); 抽屉枪's flag set in battle_commands.gd `_siege_break`. Spec F16 |
| 0x4064d7 | 0x40639a Counter: just before the counter Attack | 0x4d7a11: [0x55ac54]==2 → full-screen banner "双雷引" (0x4d64ea/0x4d6366/0x4d6576) | 定彦平/东方伯 【技】双雷引 banner, F17 | PORTED | battle_actions.gd `counter_attack` (`_banner("双雷引")` over the darkened field). Spec F17 |
| 0x47f081 | WM_PAINT handler of the window proc (Ghidra puts the fragment under 0x406b16) | 0x4d4074: custom painting of specific child windows (0x4d401a bitmaps), EndPaint | Win32 painting | N/A | the port draws its own UI |
| 0x406b51 | mod stub in .text (0x406b4f), reached from the player attack command 0x43dbfb when the attacker has effect 90 (连续攻击), it is the first repeat, and 0x4d2a47 is true (alive, not 乱/怯/迷) | `[0x4d0d5d] = 0` | 六军镜·形势 effect 90 连续攻击, F18 | PORTED | battle_input.gd `_do_attack`. The write itself is a no-op (the value is never set); the stub it belongs to is the repeat path. Spec F18 |
| 0x406b5b | same stub | 0x4d2ab2: script poll 0x44c601 + remove HP-0 units 0x44cc03, then `[ebp-0x10]++` and back to target selection 0x43daf2 | F18 | PORTED | battle_input.gd `_do_attack` (`checkpoint`, `remove_dead`, then one more pick). Spec F18 |
| 0x406b8a | stub in .text (from 0x475315): CreateCompatibleDC, LoadLibraryA("Mark.wa") | 0x4d4144: LoadImageA bitmap 1 of Mark.wa → 0x4cf2d8 | GDI resource load | N/A | Win32 plumbing (Mark.wa bitmaps are extracted to extract/dll_mark) |
| 0x406ce6 | .text stub after 0x443653 (from 0x449089) | 0x4d41a6: GetClientRect + InvalidateRect(main window) | repaint | N/A | Win32 repaint |
| 0x406d00 | .text stub (from 0x41767c) | 0x4d41a6 | repaint | N/A | Win32 repaint |
| 0x406d17 | .text stub after 0x41e5f6 (from 0x448af7) | 0x4d41a6 | repaint | N/A | Win32 repaint |
| 0x406d2f | .text stub after 0x443534 (from 0x406c92) | 0x4d41a6 | repaint | N/A | Win32 repaint |
| 0x406d46 | .text stub after 0x41e5f6 (from 0x406ccb) | 0x4d41a6 | repaint | N/A | Win32 repaint |
| 0x406ea7 | 0x406e17 AddStat(i=5): hp_base = max(1, min(+g, 9999)) | 0x4d6710(0): if the person has a unit, U.HP = min(U.HP, MaxHP) | clamp after a base change | N/A | no observable effect: AddStat(5) is only reached with g ≥ 0 (op 0x38 add, level-up; the catch-up penalty needs fixed_growth_flag 0, which no person has), so the clamp never triggers |
| 0x406eee | 0x406e17 AddStat(i=6) | 0x4d6710(1): U.MP = min(U.MP, MaxMP) | clamp | N/A | as above |
| 0x406f01 | 0x406e17 AddStat(i=7/8) (op 0x38 op 1) | 0x4d67d0: i=7 → U.HP = SetHP(U.HP+g) (clamped to MaxHP); i=8 → U.MP = SetMP(U.MP+g) (clamped to MaxMP); only if the person has a unit (0x477adc) | script attrs 7/8 = battle-unit HP/MP, F19 | PORTED | battle_attrs.gd `set_attr` (attrs 7 and 8; `get_attr` gives 0 for 8). S_17/S_36 use `set_attr p 8 1 500/300` (11 calls). Spec F19 |
| 0x406fc0 | 0x406f54 SetStat(i=7/8) (op 0x38 op 0/2) | mod case: unit lookup 0x477adc + `call 0x4d3197`; 7 → U.HP = min(v, MaxHP); 8 → U.MP = min(v, MaxMP) | F19 | PORTED | battle_attrs.gd `set_attr` (attrs 7 and 8) |

Counts: PORTED 36, PARTIAL 0, MISSING 0, N/A 15, FALSE 0 (51 rows).

#### B1.2 Missing / partial features

##### B1 F1. Phase-start skill auras (0x401118; rows 0x401141, 0x40114f, 0x401168, 0x401181, 0x40118f, 0x4011c8, 0x401240, 0x4012f7, 0x401300) — PORTED [C]
When: in the side's phase-start loop (player phase: units 0..34; enemy phase: 35..114), for each unit in index order whose state
is 2, **before** that unit's StatusRecovery/BuffDecay (0x43c7d6 → 0x401118 at 0x43c7ec). Port: battle_stage.gd `_phase_skills`
(area `_aura_units`, presentation `_aura`), called per unit in `_phase_start_effects` before its `_status_recovery` and
`_buff_decay`, as in the original.
Dispatch order inside 0x401118 (all independent `if`s, by unit pid / family): pid 29 → F1a; pid 31 → F1b; pid == [0x55ac40] → F1e;
pid == [0x55ac44] → F1d; pid 42 → F1c; family(class) == 16 → F1f.

Area ("gather" 0x4011a9): the 3×3 square around the owner, clamped to x,y ≥ 0; off-map cells skipped (0x435884). The owner is
excluded ([0x4cfbec] is never set). Only state-2 units count (HP is not checked). Side filter: an owner of kind 0/1 (player/friend)
selects kinds 0 and 1; an owner of kind 2/3 selects kinds 2 and 3. F1d uses the opposite side. Targets in row-major order (y outer, x inner).
"Lv" means the owner's level (P+0x2c).
- **F1a 鲁明月 (pid 29) 【术】云袖**: each target gets HP += min(Lv+50, MaxHP−HP) (0x4d4966, applied in 0x4d47af mode 1). Presentation:
  0x43d108 always plays unit animation `unit_status(29, action 12, pre_wait 1)` then `(29, action 1)` (even with no targets);
  then, if there are targets: camera to the first target, Xben effect 10 on all targets, HP-change display (code 0xbf is display only [G]).
- **F1b 柳周臣 (pid 31) 【术】仙乐**: each target gets MP += min(Lv/4+1, MaxMP−MP) (0x4d4928). No HP change (b==0xb skips it). Xben effect 11.
- **F1c 尚师徒 (pid 42) 【术】神将**: each target gets buff byte U+0x18 (攻击) = 6. Xben 0x11, then 0x22.
- **F1d [0x55ac44] 【术】魔功** (R_13 sets it to 100 杨素): each **opposite-side** target in the 3×3 gets code 0x70 through 0x4224a8, i.e.
  status |= 0x10 中毒 (the stored damage is 0, so it always sticks on living units), with 0x4224a8's normal per-target animation.
- **F1e [0x55ac40] 【术】天魔**: own-side targets get code 0xaf (= 豪气: 0x420cb2 codes 0x31 爆发↑, 0x33 士气↑, 0x35 攻击/精神↑ (mod
  0x4d8985), 0x37 防御↑). Dormant: no script sets 0x55ac40.
- **F1f class 42 雄师 (family 16)** (in-.text 0x427025 → 0x4d3f88): own-side targets get buff byte U+0x1c (士气) = 6. Xben 0x10, then 0x25.
  Holders: 尉迟恭 (pid 3, party), 杨林, 杨素, 定彦平, 张善相, and anyone whose class becomes 42.
- Side effect [G-minor]: 0x418c99 sets the strategy ctx caster and the "current unit" pid (0x4b5df0+4) for every processed unit, so after
  the phase start the selector 0x400..0x402 "current unit" is the last on-map unit of that side. Not reproduced: `_phase_skills`
  leaves `current_unit` alone.

##### B1 F2. Critical-hit shout (0x40582c) — PORTED [C] (battle_actions.gd `_crit_shout`)
Original (CCZ): after a strike whose first target got a critical (ctx+0x604), if chance(25), the attacker says its critical line:
pid in table 0x48b230 (21 pids: 0,1,2,5,7,8,9,13,14,15,16,17,19,22,24,32,33,34,67,86,116) at index k → Fhua[700+k]; otherwise
Fhua[700+21+3·g+rand(3)] with g = 0x40dfd0(person) (class group [G]); shown as a battle dialog (0x45965d). Mod: while a 绝招 runs
([0x4cf314]≠0) the 25% roll is skipped: pid 1 程咬金 never shouts, everybody else always shouts.

##### B1 F3. 龙吟 / 鬼门刀 on-hit effects (0x4058cb → 0x4d72e0) — PORTED [C] (battle_actions.gd `_trigger`, `_technique_hit`)
Triggers are rolled once when a non-counter attack starts (0x4d7808 → 0x4d76d0, attack strike 0): attacker pid 32 杨林 → [0x55ac1c];
pid 43 魏文通 → [0x55ac38], each with chance(min(Mor(att)·50 / Mor(def), 100)) (0x4d75d2). The flags are cleared after strike 0's
effects (0x433373), so they act on the first strike only. In the per-target loop of 0x405889, **before** the hit/damage test
(so also on a miss), and only if the unit at ctx+1 lacks effect 57:
- 龙吟: 50%: weapon level P+0x2f −1 if > 0 (and if weapon exp P+0x30 == 0xff, set it to 0); other 50%: armour level P+0x32 −1 if > 0
  (exp P+0x33 0xff → 0).
- else 鬼门刀: ChangeUnit(pid, what 5, value 0, anim) → move buff U+0x1d = 0 (with the stat animation), and status |= 0x20 怯 (unconditional once triggered).
Quirk: ctx+1 is read before the loop updates it, so at iteration i it is target i−1 (i = 0: the first target, set by 0x405744). For
single-target attacks it is the defender.

##### B1 F4. Effect 57 化解攻击效果 blocks on-hit statuses (0x405915 → 0x4d724c) — PORTED [C]
If target i has effect 57, none of 0x405889's on-hit statuses are applied (effects 35/36/37/34/38, classes 50/45/38, 梦魇, effect 38 seal).
The 张善相 poison (F7) still runs. Port: battle_actions.gd `strikes` calls `_on_hit_effects` only without effect 57; F7 is outside it.

##### B1 F5. Effect 37 随机属性攻击 formula (0x4059f1 → 0x4d0c6e) — PORTED [C] (battle_actions.gd `_random_statuses`)
L = attacker's weapon level (P+0x2f). Six independent rolls, each `chance((L·a + b) & 0xff)` ORs the bit into the status:
麻痹 0x02: 5L+15 · 穷 0x04: 4L+4 · 乱 0x08: L+1 · 毒 0x10: L+6 · 怯 0x20: 2L+2 · 迷 0x40: 3L+3 (tables 0x4d0b60/68/70).
Applied on hit (damage or MP damage ≠ 0), target without effect 57. Item: 八棱梅花锤 (id 28, special 37).

##### B1 F6. 李世民 【术】梦魇 (0x4059f9 → 0x4d8caf) — PORTED [C] (battle_actions.gd `_on_hit_effects`)
If attacker pid == 67: walk the target list in order; while target.level ≤ attacker.level, status |= 0x40 迷失; stop at the first
higher-level target. It is called inside the per-target on-hit block, so it needs target i hit and without effect 57. (The skill text
says "even if blocked", but the code does not do that.)

##### B1 F7. 张善相 poison (0x405a6a → 0x4d568d) — PORTED [C] (battle_actions.gd `strikes`)
At the end of each target's on-hit block, reached on hits, misses and effect-57 targets alike: if attacker P+0 == 0x10cc (pid 204) and
the battle map number [0x48baec] (HM file id) ≤ 34, target status |= 0x10 中毒.

##### B1 F8. 谢映登 贯石 MP loss + 笼屉 auto-馒头 (0x405bb0 → 0x4d681c) — PORTED [C] (battle_actions.gd `strikes`, `eat_bun`)
After HP −= damage, if damage > 0 and the target survives:
1. target pid 24 and byte [0x55e25c] (EV[3223]) ≥ 3: MP low byte = max(MP − damage, 0) (the 【术】贯石 cost).
2. Original effect 62 使用馒头 (accessory 笼屉, id 81), gated by the mod: only if HP + 100 ≤ MaxHP. Then: player unit (kind 0) and the bag has
   item 0x57 馒头 (0x40db3e count > 0) → use 馒头 from the bag on it (0x41dc43(0x57, slot, 0, 0)); non-player unit → use it free (…, 1).

##### B1 F9. EV[10] "a unit dropped to 0 HP" flag (0x405bb7 → 0x4d67b8) — PORTED [C], high impact
0x4d67b8(v) writes EV[10] (0x55b028). Writers: physical kill (0x405bb7, v=1), strategy kill (0x422c87, 1), script HP→0 (0x4121b5, 1),
0x4093c3 (1, after HP := 1); cleared (0) at AIAct start (0x43ad2b), at player unit selection (0x43e16b) and at battle start (0x44ccc8).
27 battle scripts have a section `WHEN EV[10] >= 1` "合并所有HP0撤退" (e.g. S_23 line 7559) that handles each HP-0 unit: retreat
lines (unit_op_53), defeat conditions (e.g. "李密被隋军杀害，战斗失败了" in S_23 1.35), kill counters (EV[322]/EV[324]), drops
(e.g. get_item 91 when 宇文化及 falls), story flags. These sections then reset EV[10]=0. Port: battle_actions.gd `unit_fell`
(physical, strategy; script HP→0 through `unit_defeated`), battle_stage.gd `_assassination_countdown` (0x4093c3); cleared in
`BattleAI.act`, at the player's command (battle_input.gd) and at battle start (battle_stage.gd).

##### B1 F10. 格斗兵 formation agility (0x405cf2, 0x405d0a → 0x4d9818) — PORTED [C] (bunit.gd `formation_agi`)
Agi'(U) = Agi(U) (buffed, ≤ 9999); if class(U) ∈ {18 武师, 19 教头, 20 团练}: Agi' += Agi·15·n/100, where n = number of the 8 surrounding
cells holding a unit with the same side group (slot < 35 vs ≥ 35), the same class family (6), and without status 乱 0x08 or 迷 0x40.
Used for both a and d in DoubleRate (and, per rules.md §4.2, in HitRate, which is another batch).

##### B1 F11. CritRate side effects (0x405d93 → 0x4d1d30) — PORTED [C] (battle_actions.gd `_crit_rate`, `_bingdi_count`, `_xuanyuan`)
They run every time the crit roll happens, i.e. for the first target whenever target HP > 0, even after a miss (CalcDamage returns 0 on a miss).
1. 并蒂 counters: P = person EV[3972] (王君珂), G = pid 0 管毅; both units state 2 (distance ≤ 153, always true). If P's unit is the
   current defender ([0x4927f1]) → byte [0x55ee04]++; else if G's unit is the defender → byte [0x55ee06]++. Snapshot dword
   [0x55ee04] → EV[3968] in the recovery hook 0x43c74f; cleared in regen 0x43cf75. Consumed by the 并蒂 attack bonus (other batch).
2. Deferred 轩辕神枪 paralysis: when [0x4dca4f]==1, U[[0x4dc9c9]].status |= 0x02. The flag is set by the hit-check hook 0x43b504 → 0x4dc924:
   the target is 管毅 (pid 0), the attacker is Chebyshev-adjacent, the attack **missed**, EV[3184] ≠ 0, chance(EV[2700] ×2 if
   EV[3184] ≥ 3), and 管毅's weapon is id 23 轩辕神枪 → [0x4dc9c9] = the attacker. It is cleared at every hit check, so in practice
   "an adjacent attacker that misses 管毅 is paralysed".
3. EV[3210] = Mor(att)·15/Mor(def): written only, never read → ignore.

##### B1 F12. 王君珂 【术】并蒂 sure critical (0x405daa → 0x4dc7fd) — PORTED [C] (battle_actions.gd `_crit_rate`)
CritRate = 100 if effect 41 (ported); else if counter depth ≠ 1 and the attacker's pid == EV[3972] and the pid of the unit last
selected by the player ([0x4dc7dd], set at 0x43d5f3 when a unit's move range is shown) == 0 管毅 → 100 (and [0x4dc7f1]++, write-only);
else the normal curve. In practice: 王君珂 crits when it attacks as a participant of a 围攻 started by 管毅 (battle_commands.gd `siege_command`).

##### B1 F13. Multi-target physical attacks and secondary-target damage (0x405e97, 0x405ea0) — PORTED [C]
Port: battle_actions.gd `area_code`, `secondary_targets`, `_halved`, used by `strikes`.
The original builds a target list from the area-attack code ctx+0x424 = 0x407818(attacker)
(class table 0x409191, effect 43 穿透攻击 value, effect 21 for classes 15–17, mod overrides: 凤舞九天 → 2, 横推八马倒 → 0xa,
[0x55ac64] → 0xc, pid 178 文士弘 → 6) via 0x43652e. Damage mode for target i > 0 (mod):
- attacker pid 33 宇文成都: +2 (half) only if the area code == 1, else full (his triggered 凤舞九天, area 2, splashes the 8 cells at full damage);
- others: +2 (half) for area codes 1, 2, 3, 12; full damage for 4..11 and 13+ (lines/penetration/sweeps).
Mode bit 0 = counter (×3/4). Base CCZ: all secondaries are halved. Secondary targets crit iff the first target critted (in-.text 0x433418, [G]).

##### B1 F14. 绝招 crit override (0x405efb → 0x4d34c9) — PORTED [C] (rules.gd `crit_rate`; 绝招 in battle_commands.gd `special`)
While [0x4cf314] (绝招 running): attacker pid 7 伍天锡 or 26 雄阔海 → no critical; everybody else → automatic critical: damage ×3/2,
crit marks set, **not** zeroed by effect 57 (the 2nd-strike effect-57 rule still applies).

##### B1 F15. 单雄信 【技】怒目 (0x405fa6 → 0x4d8150) — PORTED [C] (battle_actions.gd `strikes`)
Trigger [0x55ac4c]: attacker pid 4, chance(min(50·Mor_a/Mor_d, 100)) at attack start, first strike only (see F3). For every target of
that strike: MP damage = the target's whole current MP (MP → 0 when applied), HP damage unchanged (capped at HP). The code does not
check the hit, so it also drains on a miss (the skill text says "hit").

##### B1 F16. Forced / changed second strikes (0x4061df → 0x4d88df, with in-.text 0x407600 / 0x407bc8) — PORTED [C]
DoubleCheck as patched:
1. [0x55ac54]==2 (双雷引 phase) and strike counter < 1 → 2nd strike (forced);
2. the original "counter depth > 0 → no 2nd strike" check is bypassed (0x40761e jumps past it);
3. strike counter > 0 → none; else chance(DoubleRate) → 2nd strike; else if byte [0x55ac68]==1 → 2nd strike (forced); [0x55ac68] = 0.
DoubleRate (0x405ce6 + 0x407bc8): effect 84 → 100 (**also during counterattacks**); else counter depth > 0 → 0; else [0x55ac54]==2 → 100;
else curve(Agi', F10). [0x55ac68] is set by the pre-emptive-strike routine 0x4d74f0..0x4d7590 (defender not 乱, alive). The defender
strikes first if it has effect 60 先手攻击 (always), or if it is pid 101/136/14 and wins chance(min(50·Mor_def/Mor_att, 100)) (0x4d8895 →
0x4d75d2). Then the attacker must be in its range. Only for pid 14 姜松 (【技】抽屉枪: "抢先予以对方双击") is [0x55ac68] = 1 set, which
forces its double. The pre-emptive strike itself belongs to another batch. Port: battle_actions.gd `_double_check`, rules.gd
`double_rate` (effect 84 before the counter test), the flag in battle_commands.gd `_siege_break`.

##### B1 F17. 双雷引 banner (0x4064d7 → 0x4d7a11) — PORTED [C] (battle_actions.gd `counter_attack`)
Just before a counterattack, if [0x55ac54]==2 (定彦平 pid 101 / 东方伯 pid 136 双雷引 triggered: 0x4d820e, chance as F3): screen effect
0x4d64ea, centred caption "双雷引" (0x4d6366, string 0x555826), restore 0x4d6576. (The 双雷引 logic itself is in other batches.)

##### B1 F18. Effect 90 连续攻击 (六军镜·形势, id 83) (0x406b51, 0x406b5b) — PORTED [C] (battle_input.gd `_do_attack`)
Player attack command (0x43dada): after the attack (and after the effect 46 引导攻击 follow-up), if this is the first repeat
([ebp−0x10]==0), the attacker has effect 90, and 0x4d2a47 holds (HP > 0, not 乱 0x08 / 怯 0x20 / 迷 0x40): run the script poll and the
HP-0 removal (0x4d2ab2 = 0x44c601 + 0x44cc03), then let the player pick a target again in attack range (0x45533d). A cancel ends the
action. At most one extra attack.

##### B1 F19. Script attr 8 = battle-unit MP (0x406f01, 0x406fc0) — PORTED [C]
op 0x38 set_attr attr 8: op 0 → U.MP = min(v, MaxMP); op 1 → U.MP = min(U.MP + v, MaxMP); op 2 → SetStat(8, max(0 − v, 0)) = 0
(GetStat(8) returns 0). Only when the person has a unit (0x477adc; outside battle nothing). Used by S_17/S_36 (`set_attr p 8 1 500/300`,
11 calls). Port: battle_attrs.gd `set_attr`; `get_attr(8)` returns 0.

##### Notes for the docs (found while auditing)
- docs/rules.md §4.2 / §6.1 call [0x4cf314] a "duel mode"; it is the "绝招 running" flag (0x4d307a/0x4d3092).
- docs/rules.md §4.4 says effect 84 gives no double in counters; the mod's code gives it (F16).
- docs/rules.md §11 says the dynamic list is EV[898..927]; it is EV[3970..3999] (filled by the scripts).

### B2 — Persons, level-up, script ops, toolbar, saves (0x407000..0x41ffff)
All addresses are wagan.wa VAs. Port paths are relative to `game/src/`. Confidence: [C] confirmed
from code, [G] guess. Person names from `game/assets/data/persons.json` (pid 0 管毅, 1 程咬金, 2 王君珂, 8 秦琼,
9 尤俊达, 10 盛彦师, 11 樊虎, 12 鲁明星, 13 王伯当, 19 罗成, 20 贾润甫, 21 柴绍, 24 谢映登, 29 鲁明月, 178 文士弘);
skill owners as in [Skill owners](#skill-owners).

Notation used below:
* `[0x48baec]` = number of the loaded battle map (set by 0x44c2e3 at battle start); it is 0xff/0xffff in story/town
  mode (0x41b0f4, 0x41b124, 0x426ca7). "story mode" = `byte [0x48baec] == 0xff`, "battle mode" otherwise.
* `0x47fa89(a, b, c)` = min(a + b, c) (signed); `0x43e4d6(pid)` = slot of the person's unit (≥ 0x73 = none);
  `0x4db541(p, q)` = |dx| + |dy| of two unit positions; unit "on map" = unit byte +0xc == 2.
* Dynamic skill list `dyn[i]` = u32 0x55ee08 + 4i = EV[3970 + i]. R_00 sets all 30 to 1024 (nobody); scripts then
  assign: dyn0 【术】连理 = 12 鲁明星 (R_21), dyn1 【术】云袖 连理 = 29 鲁明月 (R_23), dyn2 【术】并蒂 = 2 王君珂
  (R_17), dyn7 【术】市侩 相马 = 20 贾润甫 (R_20), dyn9 【术】百宝 = 9 尤俊达 (R_18), …
  **Doc error found (fixed):** docs/rules.md §11 said the list was EV[898..927] and that no script writes it; it is
  EV[3970..3999] and the scripts above do write it.
* EV[k] lives at 0x55b000 + 4k. Story-mode "灵物" variables used below: EV[3181] (0x55e1b4), EV[3182] (0x55e1b8),
  EV[3184] (0x55e1c0), EV[3185] (0x55e1c4), EV[3186] (0x55e1c8), EV[3189] (0x55e1d4), EV[3201..3209]
  (0x55e204..0x55e224), EV[3223] (0x55e25c), EV[3257] (0x55e2e4), EV[3401] (0x55e524), EV[3416..3422]
  (0x55e560..0x55e578), EV[3451] (0x55e5ec); all are maintained by the R_16+ scripts ("全部人无灵物重算",
  "消除瓦面金装锏效果" …, popup "解锁「宿痕」能力！").

#### B2.1 Site table

| site | original function (what it does) | mod change | feature | status | port evidence or missing spec |
|---|---|---|---|---|---|
| 0x407141 | 0x407126 GetAtk(person) = min(word+0x11 + EquipBonus(0), 9999) | jmp 4db5fd: in story mode replaces the stat word w for 3 persons before the min: pid 8 with weapon 0x18 瓦面金装锏 and byte EV[3181] ≥ 1 → (w−EV[3401])·(100+wlvl·EV[3201])/100+EV[3401]; pid 0 with weapon 0x17 轩辕神枪 and byte EV[3184] ≥ 1 → (w−EV[3416])·(100+wlvl·EV[3204])/100+EV[3416]; pid 24 with EV[3223] ≥ 3 → (mp_base + (acc 0x43 ? 15 : acc 0x44 ? 30 : 0))·EV[3257]/100 + (w − EV[3451]). Otherwise → 0x407146 | 秦琼/管毅 宿痕 weapon scaling; 谢映登 【术】贯石 attack from MP | PORTED | core/person.gd `stat` → `_scar` (宿痕 of 秦琼 / 管毅, 谢映登's 贯石), outside battles |
| 0x407146 | (same function, 2nd hop) | jmp 4db4c5: battle mode: if this person's unit and pid 0's unit are both on map, this unit's person == dyn0 and d = dist < 5 → v = min(w+bonus,9999)·(100 + 5·(5−d))/100 and return (skips 0x40714b) | 【术】连理 (dyn0 鲁明星 near 管毅) attack aura | PORTED | person.gd `stat` / `_aura_distance` (BUnit.stat goes through it) |
| 0x40714b | (same function, tail) | jmp 4dbcf6: after the min: story mode → u32 [0x55ee04] (EV[3969]) = 0; battle mode → if pid == u16 dyn2 → v·(100 + 8·byte[0x55ee02])/100 | 【术】并蒂 (dyn2 王君珂) attack bonus | PORTED | person.gd `stat` (clears [0x55ee04] outside battles; 并蒂 × (100 + 8·[0x55ee02]) / 100); the counters in battle_actions.gd `_bingdi_count` and the phase start (`BattleStage._phase_start_effects`) |
| 0x407172 | 0x407157 GetDef(person) | jmp 4db68c: story mode: pid 1 程咬金 + weapon 0x19 八卦宣花斧 + byte EV[3185] ≥ 1 → (w−EV[3422])·(100+wlvl·EV[3205])/100+EV[3422]; pid 0 + 0x17 + EV[3184] → (w−EV[3417])·(100+wlvl·EV[3204])/100+EV[3417] | 宿痕 weapon scaling (def) | PORTED | person.gd `_scar` |
| 0x407177 | (2nd hop) | jmp 4dbad6: battle mode: unit == dyn1, pid 0's unit on map, d < 5 → ×(100+5(5−d))/100 | 【术】云袖 连理 (dyn1 鲁明月 near 管毅) defence aura | PORTED | person.gd `stat` |
| 0x4071a3 | 0x407188 GetSpirit(person) | jmp 4db71b: story mode: pid 21 柴绍 + weapon 0x23 凤羽灵虚扇 + byte EV[3186] ≥ 1 → w·(100+wlvl·EV[3206])/100; pid 0 + 0x17 + EV[3184] → (w−EV[3418])·(100+wlvl·EV[3204])/100+EV[3418]. No battle part | 宿痕 weapon scaling (spirit) | PORTED | person.gd `_scar` |
| 0x4071d7 | 0x4071b9 GetAgility(person); bonus = 0x469341(3, EquipBonus(3)) (a .text cave: for stats 3/4 the equipment bonus is a **percentage** of the stat word) | jmp 4db7aa: story mode: pid 19 罗成 + weapon 0x1a 丈八滚云枪 + byte EV[3189] ≥ 1 → w·(100+wlvl·EV[3209])/100; pid 0 + 0x17 + EV[3184] → (w−EV[3419])·(100+wlvl·EV[3204])/100+EV[3419] | 宿痕 weapon scaling (agility) + percent equipment bonus | PORTED | person.gd `_scar`; the percentage bonus in `stat` (s = 3, 4) |
| 0x4071dc | (2nd hop) | jmp 4dbbef: battle mode: unit == dyn1 and pid **12**'s unit on map, d < 5 → ×(100+5(5−d))/100 | 【术】连理 (鲁明月 near 鲁明星) agility aura | PORTED | person.gd `stat` |
| 0x407208 | 0x4071ea GetMorale(person); bonus = 0x469341(4, …) (percentage, see above) | jmp 4db839: story mode: pid 13 王伯当 + **armour** 0x2e 天玉玲珑铠 + byte EV[3182] ≥ 1 → w·(100+armour_lvl·EV[3202])/100; pid 0 + 0x17 + EV[3184] → (w−EV[3420])·(100+wlvl·EV[3204])/100+EV[3420] | 宿痕 armour scaling (morale) + percent equipment bonus | PORTED | person.gd `_scar`; the percentage bonus in `stat` |
| 0x40720d | (2nd hop) | jmp 4db9bd: battle mode: unit == dyn0 and pid **29**'s unit on map, d < 5 → ×(100+5(5−d))/100 | 【术】连理 (鲁明星 near 鲁明月) morale aura | PORTED | person.gd `stat` |
| 0x4072b6 | 0x40727b MovePoints(person) = min(class.move + EquipBonus(7), 255) | jmp 4dc895: +1 if person[dyn7].+0x2a == 0 (dyn7 is a party member), this person is a party member, dyn7 ≠ 0x400 and accessory ∈ {0x3d 黄骠马, 0x3e 虎类豹, 0x3f 大肚子蝈蝈红, 0x2f 板角墨麒麟, 0x3b 小乖, 0x3c 万里烟云兽} | 【术】市侩 相马 (dyn7 贾润甫): mounts +1 move for the party | PORTED | person.gd `move_points` (BUnit.move_points builds on it) |
| 0x4073c9 | 0x4073b8 LevelUp(n, show) prologue | jmp 4dbde3: stores pid in [ebp−0xc], bonus_stat = rand(5) (byte 0x4dbe23) — rand called for every LevelUp | 【术】天运 (盛彦师 pid 10) | PORTED | person.gd `level_up` (`Rules.rand(5)` once per call) |
| 0x407471 | LevelUp: per-stat growth g | jmp 4d65f5: for i = 5 (HP), 6 (MP): if person+0x2a == 0 (party member) and mp_base ≠ 1 → g −= 0x4d806a(i) (catch-up penalty) | level-up HP/MP catch-up penalty | PORTED | person.gd `level_up` / `_catchup_penalty` |
| 0x407492 | LevelUp inner loop (n repetitions per stat) | jmp 4dbdfb: if pid == 10, i ≤ 4 and i == bonus_stat → g += 1 (kept for the rest of this call) and bonus_stat = 5; then (.text caves 0x42704a/0x433430) gains[i] = new − old and "g == 0 → 1" for i ≤ 4 | 【术】天运; exact gain display | PORTED | person.gd `level_up` (天运, g == 0 → 1, gains = new − old) |
| 0x4074ae | LevelUp epilogue (level += n) | jmp 4e0100: the person's unit HP += class byte 7, MP (byte) += class byte 8, each capped at the new MaxHP/MaxMP — once per LevelUp call (no unit → writes unit slot 114, harmless quirk) | unit HP/MP gain on level-up | PORTED | person.gd `level_up`, at its end (class growth, capped at the new maximum, MP on its low byte; slot 114 without a unit) |
| 0x407519 | LevelUp message ("%s升为%u级。" + learned strategies "学会了策略「%s」！", 0x407525..) | jmp 4dbe29: if byte [0x4dbe25] == 0 (default) → only "%s升为%u级。\n\n" (style 2); else the detailed text built by the .text cave 0x43efc3 (style 0): 7 lines 攻击/防御/精神/反应/士气/HP MAX/MP MAX + "增加了 %d。\n" (negative: "减少了 %d。\n") | level-up report (option 升级显示能力成长) | PORTED | person.gd `level_up_texts`, battle_actions.gd `_show_level_up` (the option is 环境设定's, ui/settings_window.gd) |
| 0x407658 | cave inside GetFace 0x4075a7, reached from the AI attack 0x43db49 (combat object 0x4927f0) | call 4d7808: mod attack wrapper: per-attacker 【技】 triggers with chance min(Morale(att)·50/Morale(def), 100)% (0x4d75d2): pid 44 新文礼 → [0x55ac2c], 34 李元霸 → [0x55ac30], 33 宇文成都 → [0x55ac20], 32 杨林 → [0x55ac1c], 43 魏文通 → [0x55ac38], 4 单雄信 → [0x55ac4c], 3 尉迟恭 → [0x55ac50] (extra strikes, up to 2 more while both alive), 101 定彦平 / 136 东方伯 → [0x55ac54]=1 (双雷引); 0x4d74e4 围攻 check; 0x4d7b90 → [0x55ac24] | AI-side 【技】 techniques (双雷引, 盖马三锤, 凤舞九天, 龙吟, 鬼门刀, 怒目, 血战, 横推八马倒) | PORTED | battle_actions.gd `attack_cmd` / `_trigger`; the AI's attacks go through it (`BattleAI._physical_attack`) |
| 0x40783f | 0x407818 AreaAttackCode(person) = table 0x409191[class] (+ effects 21/43) | jmp 4dbebb: [0x55ac2c]==1 → code 0xa; else [0x55ac64]==1 → 0xc; then (0x4d8901) pid 178 文士弘 → code 6 | 【技】 area overrides (横推八马倒 0xa, 凤舞九天 via [0x55ac20] → 2 patched inline at 0x40782a, [0x55ac64] → 0xc) and 【术】长缨奔破 (文士弘 area 6) | PORTED | battle_actions.gd `area_code`; the extra targets in `secondary_targets` |
| 0x40790d | 0x407907 CanEquip(person, item) | jmp 4d9a91: pid 11 (樊虎) cannot equip any accessory (slot 2) | 樊虎 no accessories | PORTED | person.gd `can_equip` |
| 0x4079af | CanEquip, accessory family test | jmp 4da23b: item 0x4c 孙子兵法 also for families 8, 9, 18, 24 | 孙子兵法 wider families | PORTED | core/person.gd:250-251 |
| 0x4079ea | CanEquip, weapon/armour type test | jmp 4dc8fc: pid == dyn9 (EV[3979]) → may equip every weapon/armour type | 【术】百宝 (dyn9 尤俊达) | PORTED | person.gd `can_equip` (`Skills.dyn(9)`) |
| 0x40898a | 0x408950 SetExp(total): LevelUp(1) per 100 | jmp 4d0331: before each LevelUp: byte EV[3184] == 4 → [0x4cf2b8] = 5 (+1 grade on all 5 stats) | 管毅 宿痕 stage-4 growth bonus | PORTED | battle_actions.gd `set_exp` (compares the low byte, as the original) |
| 0x40910e | (data ref in a .text cave 0x409102 after the person parser) | `movzx ecx, [0x4d0d5c]` ×30 added to damage | — | FALSE | dead code: no jmp/call/pointer reaches 0x409102..0x40911b (raw rel32/rel8 and absolute scan); the live copy of this logic is 0x4d8d65 (CalcDamage, other batch) |
| 0x4092b6 | 0x4092a4 (mod-written cave): load portrait bitmap 301+face from module [0x4cf100] into a dialog bitmap, set [0x4cf2ba] = draw mode; called by 0x46d749 (dialog class vtable 0x487250) | call 4d4144 = DeleteObject + LoadImageA helper | portrait bitmap loading | N/A | Win32 bitmap plumbing; the port draws portraits itself (sge.wa 301+face) |
| 0x4092e3 | 0x4092da (cave) title start: 0x4e20ff + BGM 0x12 | call 4e20ff: load settings from Niuniu.wa bytes 1..5 → GS+0, GS+1, GS+8, GS+0x10 (original 环境设定 options) and [0x4dbe25] (升级显示能力成长) | 环境设定 persistence | PORTED | `Settings.load_file`, called by main.gd `_title_screen` |
| 0x4093b5 | 0x40937f (mod-rewritten .text function) 暗杀 countdown, called per slot at phase start (0x4364d6) | call 4d3197 (ecx = &units[cl] helper) inside the new function | 暗杀 countdown | PORTED | battle_stage.gd `_assassination_countdown` |
| 0x4093c3 | 0x40937f | call 4d67b8: EV[10] = 1 when the countdown fires | 暗杀 (strategy 21) delayed effect | PORTED | battle_stage.gd `_assassination_countdown` (HP 1, EV[10] = 1, "%s被暗杀了！！") |
| 0x409ead | 0x409d6e (palette/bitmap setup) | — | — | FALSE | bytes inside `mov ecx,[ebp-0x18]` at 0x409eab (8b 4d **e8** 83 79 0c 00) |
| 0x409ed5 | 0x409d6e | — | — | FALSE | bytes inside `mov edx,[ebp-0x18]` at 0x409ed3 |
| 0x40bbfb | 0x40bbd0 SetScene(mode, value) (scene object 0x4ac63c) | jmp 5260c0: story mode value += 0x100 when byte EV[1017] (0x55bfe4) == 1 | alternate (HD/second) scene picture set | PORTED | story/story_stage.gd:343-344 |
| 0x40cb10 | 0x40c843 item detail (dialog 167) 可装备的部队 | jmp 4da200: item 0x4c also lights families 8, 9, 18, 24 | 孙子兵法 family list | PORTED | ui/detail_panel.gd:167-189 |
| 0x411421 | 0x4112e9 op 0x36 test_attr, attr 7 (unit HP) | call 4d3197 (unit address helper, replaces imul/add) | test_attr attr 7 | PORTED | battle/battle_attrs.gd:21-26 (no unit → 0xff) |
| 0x41211b | 0x412006 op 0x38 set_attr, attr 7 op 2 (HP −= v saturating) | call 4d3197 (helper) | set_attr unit HP | PORTED | battle_attrs.gd:39-50 |
| 0x412170 | set_attr: after attr 7, unit HP ≤ 0 → kill 0x4121b0 | call 4d3197 (helper) | set_attr kill | PORTED | battle_attrs.gd:45-50 |
| 0x4121b5 | 0x4121b0 script kill helper (→ 0x441744(0,0)) | call 4d67b8: EV[10] = 1 before the kill | "a unit fell" signal for the S_23..S_57 sections "合并所有HP0撤退" | PORTED | battle_attrs.gd `set_attr`, battle_unit_ops.gd op 0x4d and op 0x78 field 33 (`ScriptHost.unit_hp_written`, 0x4d0653 → 0x4d678c, signed HP ≤ 0) → battle_actions.gd `unit_defeated`: EV[10] = 1, then RemoveUnit (no blinks or SE of its own) |
| 0x413a87 | 0x413a57 op 0x16 info | data ref: chronicle buffer object 0x4d1050 (+0xc buffer, length EV[4094]) | 史录 chronicle | PORTED | core/script_host.gd:283-290, core/game.gd `add_history`, ui/history_window.gd |
| 0x413aa1 | op 0x16, category byte EV[4095] == 0xff | call 4d1679: replace the chronicle entry whose leading number equals the text's number; text that is only the number deletes the entry; **no entry → nothing added** | 史录 replace | PORTED | core/game.gd `add_history` (no match → nothing) |
| 0x413adc | op 0x16, category ≠ 0 | call 4d0f9b (strlen): append "&"+cat+text unconditionally (until 0x56b800), length += len+2 | 史录 append | PORTED | game.gd `add_history` (appends duplicates) |
| 0x4149e6 | 0x4148fe op 0x3b join | call 4d5000: mode 1 → 0x433450 (join as is; only if EV[4000] ≠ 0: level up to ⌊mean level of members⌋ with the +1 grade bonus each level — EV[4000] is never written, so inactive); other modes → original 0x40c28c | join mode 1 | PORTED | script_host.gd `op_join` returns while `in_battle()` (scene mode 3); mode 1 in game.gd `join_party` |
| 0x415c2c | 0x415b45 op 0x06 (arg0 ≠ 0 branch) | jmp 4d0bc9: byte [0x55ac02] = 1 then show toolbar 0x419d22(0) | toolbar 出征 state remembered for re-show after loading (0x42a2a3 → 0x4d0bf1) | PORTED | story/story_stage.gd:466-473 (+ saved `sortie_enabled`, :549/:574) |
| 0x415e1e | 0x415d92 op 0x4a battle_prepare | jmp 4d53ae: the 5th tag-0x39 argument is stored at 0x4b0a04[9] (loop only writes [0..3]) | sortie exclusion list layout | PORTED | battle/battle_stage.gd:355-361 (`SORTIE_FLAGS + 4*9`) |
| 0x41687d | 0x4166eb op 0x58 terrain change, alt ≠ 0 branch | call 4d7dc5(x, y, patch, scroll, terrain): if scroll ≠ 0 write terrain byte at (x,y); then 0x4567c1(x, y, patch, scroll) = **revert** the recorded change (x,y,patch) like op 0x21 | removing fire marks / undoing map changes from op 0x58 (344 uses, 188 in S_15) | PORTED | battle_stage.gd `op_op_58` → `_revert_terrain` |
| 0x416e08 | 0x416dfa op 0x6a game over | call 4d6290: when 0x42c0a2 returns nonzero: close video window, PostMessage 0x564, FreeLibrary sge module, delete DCs/bitmaps (0x406c11) | app exit cleanup | N/A | Win32 resource cleanup; port op_op_6a (story_stage.gd:487) returns to the title |
| 0x4174df | 0x4174a2 op 0x28 (arg ≠ 0) | jmp 4d0bdd: byte [0x55ac02] = 0, toolbar 0x419d22(1) | toolbar without 出征 | PORTED | story_stage.gd:459-462 (port also clears it for arg 0; harmless) |
| 0x4184a7 | 0x4183f7 READP | jmp 4d0b87: tags 2/0x38/0x39 with u16 0xEFFF..0xFFFE → EV[0xFFFE−v] | EV-indirect script args | PORTED | tools/eex.py:222 emits {"var"}, core/script_host.gd:30-38 |
| 0x4186e3 | 0x41856a sortie builder, candidate loop j = 0..31 | jmp 4dbdd4: candidate = byte table 0x4dbdb0[j] instead of pid j (quirk: on j = 0, edx still holds the max count, so table[max] is used instead of table[0] = 管毅) | sortie candidate order / pool | PORTED | script_host.gd `build_sortie` (table 0x4dbdb0 with the j = 0 quirk, exclusions 0x4b0a04[0..4]) |
| 0x418ff0 | 0x418f5c File::Open | jmp 4d251e: remember handles of Yueyue.wa, ~zl1g.dat, ~kvr.db, ~gtl.dll, Buha.wa, Giji.wa, Ghai.wa, Nao.wa; ~ files opened via 0x4d25c1 | archive container handling | N/A | file IO; port uses pre-extracted assets |
| 0x419211 | 0x4191af File::Seek | jmp 4d2600: for those handles, seek translated after a magic check (0x4d249d vs [0x555460]) | archive offsets | N/A | file IO |
| 0x419ddd | 0x419d22 toolbar create | — | — | FALSE | bytes inside `mov edx,[ebp-0x18]` at 0x419ddb |
| 0x419eb9 | 0x419d22 | — | — | FALSE | bytes inside `mov eax,[ebp-0x18]` at 0x419eb7 |
| 0x41adc1 | 0x41ad06 LoadGame(slot) | jmp 4d0c29: [0x4cf304] = 1, u32 [0x4ce004] = 1 (autosave-per-phase switch), load savedata\Sv0%db.WAs → 0x55a000..+0x12000 (all mod .data3 state) | mod state restored with a save | PORTED | core/mem.gd:241-265 snapshot/restore incl. 0x55a000.. and 0x4ce000..; a load sets [0x4ce004] = 1 (game.gd `load_game`). The mod autosave it drives is replaced by the port's own autosave ([Deliberate differences](#deliberate-differences-port-design-keep-unless-asked)) |
| 0x41b020 | (in LoadGame) | call 4e20ff after `jmp 0x41afec` | — | FALSE | dead bytes: the loop exit `jae 0x41b025` skips them, nothing jumps to 0x41b020 |
| 0x41b22e | 0x41b16a SaveGame(slot) | jmp 4d0135: write 0x55a000..+0x12000 to savedata\Sv0%db.WAs | mod state saved | PORTED | mem.gd:241-251 |
| 0x41b23b | SaveGame header | jmp 4dbee8: header byte 1 = in battle ? 0x4dbf0b() (⌈mean level of on-map player units 0..14⌉, ≥ 1) : 0x40c14f() (party level) | save-slot level shown in the save list [G] | N/A | port's own slot summary (game.gd:468-486) has no level field; file format replaced |
| 0x41bb79 | 0x41badd 环境设定 dialog (KANKYOU) WM_INITDIALOG | call 4d970c: original init + checkbox 0x3f0 "升级显示能力成长" = [0x4dbe25]; checkbox 0x3ef (does not exist in the template) from [0x55ac00] | 升级显示能力成长 option | PORTED | ui/settings_window.gd (checkbox 升级显示能力成长 → byte [0x4dbe25]) |
| 0x41bd38 | 环境设定 OK | call 4d978c: original apply + [0x55ad00] = checked(0x3ef) (always 0: no such control → the deterministic-RNG mode is unreachable), [0x55ad04] = 50 if set; [0x4dbe25] = checked(0x3f0) | 升级显示能力成长 option | PORTED | settings_window.gd `_apply`; [0x55ad00] stays 0 (the deterministic RNG mode, [Deliberate differences](#deliberate-differences-port-design-keep-unless-asked)) |
| 0x41c001 | 0x41bf67 title loop, menu item 2 环境设定 | call 4e2000: open 环境设定 then write GS+0, GS+1, GS+8, GS+0x10, [0x4dbe25] to Niuniu.wa bytes 1..5 | title 环境设定 + persistence | PORTED | main.gd `_title_screen` (新游戏 / 读取进度 / 环境设定 / 结束游戏) → `Settings.save_file` |
| 0x41c01f | title loop after a choice | jmp 4d03ae: once ([0x4cf304] == 0) load person.wa → 0x55a000 (1024 B), then original | per-person battle sprite table | PORTED | core/mem.gd:56-59 |
| 0x41d063 | 0x41cf61 battle item use for types 65..69 | call 4d2d5a for type 69 (太保令, item 96): the target person's 5 stat words += 2 (≤ 9999) and 5 raw abilities += 2 (≤ 100), unit effects 0x45778f(pid, 0xb, 0xff, 0xff) and (pid, 7, 0, 0) | 太保令 "全部能力都将有所成长" | PORTED | battle_actions.gd `use_item`, type 69 |
| 0x41d0e6 | 0x41d080 fruit use (types 70..74) | call 4d3197 (unit address helper) | — | N/A | equivalent helper, no behaviour change |
| 0x41d415 | 0x41d3d9 仙人果 use (type 75) | call 4d3197 (helper) | — | N/A | equivalent helper |
| 0x41f522 | 0x41f4bd PlayVideo(id) | call 4dd000(id): rewrite the first byte of LOG.avi/… to '0' and return the file name | video files de-obfuscation | N/A | file repair; port plays converted OGVs |
| 0x41f553 | 0x41f4bd | — | — | FALSE | bytes inside `mov eax,[ebp-0x18]` at 0x41f551 |
| 0x41f60c | PlayVideo loop: click (WM_LBUTTONDOWN → [0x497a90]) or key (0x4263c5) skips | jmp 4e0a00: the skip only takes effect when id < 4 (LOG.avi, OPE.avi, END.wmv, PRE.wmv); story videos 001.wmv… (id ≥ 4) cannot be skipped | unskippable story movies | PARTIAL | ui/video_layer.gd skips every video on click/Enter/Esc: kept on purpose, see [Deliberate differences](#deliberate-differences-port-design-keep-unless-asked). Spec §2.R [C] |
| 0x41fed9 | 0x41fec9 strategy castability | call 4d3197 (helper) | — | N/A | equivalent helper |

Status counts (65 rows), brought up to date with the port on 2026-10-12: PORTED 48, PARTIAL 1, MISSING 0, N/A 9,
FALSE 7 (at the audit: PORTED 16, PARTIAL 5, MISSING 28).

#### B2.2 Missing / partial features (implementable specs)

##### B2 A. 宿痕 weapon scaling of person stats in story mode — sites 0x407141, 0x407172, 0x4071a3, 0x4071d7, 0x407208 [C]
Only when `byte [0x48baec] == 0xff` (not in a battle). For the person getter of stat s, replace the stat word w by
f(w) **before** `min(f(w) + bonus_s, 9999)` (bonus_s is computed from the unchanged record, see C). Flags are the
low byte of the EV (`≥ 1`); wl = weapon level byte +0x2f; al = armour level +0x32. First matching rule wins:
| stat | person | equipment | flag | f(w) |
|---|---|---|---|---|
| 攻击 | 8 秦琼 | weapon 0x18 瓦面金装锏 | EV[3181] | (w − EV[3401])·(100 + wl·EV[3201]) / 100 + EV[3401] |
| 攻击 | 0 管毅 | weapon 0x17 轩辕神枪 | EV[3184] | (w − EV[3416])·(100 + wl·EV[3204]) / 100 + EV[3416] |
| 攻击 | 24 谢映登 | — | u32 EV[3223] ≥ 3 | (mp_base + (acc == 0x43 逍遥巾 ? 15 : acc == 0x44 诸葛巾 ? 30 : 0))·EV[3257] / 100 + (w − EV[3451]) |
| 防御 | 1 程咬金 | weapon 0x19 八卦宣花斧 | EV[3185] | (w − EV[3422])·(100 + wl·EV[3205]) / 100 + EV[3422] |
| 防御 | 0 管毅 | weapon 0x17 | EV[3184] | (w − EV[3417])·(100 + wl·EV[3204]) / 100 + EV[3417] |
| 精神 | 21 柴绍 | weapon 0x23 凤羽灵虚扇 | EV[3186] | w·(100 + wl·EV[3206]) / 100 |
| 精神 | 0 管毅 | weapon 0x17 | EV[3184] | (w − EV[3418])·(100 + wl·EV[3204]) / 100 + EV[3418] |
| 反应 | 19 罗成 | weapon 0x1a 丈八滚云枪 | EV[3189] | w·(100 + wl·EV[3209]) / 100 |
| 反应 | 0 管毅 | weapon 0x17 | EV[3184] | (w − EV[3419])·(100 + wl·EV[3204]) / 100 + EV[3419] |
| 士气 | 13 王伯当 | armour 0x2e 天玉玲珑铠 | EV[3182] | w·(100 + al·EV[3202]) / 100 |
| 士气 | 0 管毅 | weapon 0x17 | EV[3184] | (w − EV[3420])·(100 + wl·EV[3204]) / 100 + EV[3420] |
Arithmetic is 32-bit unsigned (`imul`, `div`). Person check is the record's u16 +0 == pid|0x1000. In battle these
formulas are not applied (the scripts bake/unbake the bonuses into the stat words around battles), so the visible
effect is the 武将情报/装备 numbers in towns and any story-mode use of the getters. Also in story mode the attack
getter clears u32 [0x55ee04] (= EV[3969]) on every call. Port: `Person._scar`.

##### B2 B. Battle stat auras 【术】连理 / 云袖 连理 and 【术】并蒂 — sites 0x407146, 0x40714b, 0x407177, 0x4071dc, 0x40720d [C]
Only when `byte [0x48baec] != 0xff`. v = min(f(w)+bonus, 9999) as usual, then:
* Aura: requires the person's unit (0x43e4d6) on map (+0xc == 2), the centre person's unit on map, the person's unit
  person id (u32 +0) == the dyn entry, d = |dx|+|dy| between the two units; if d < 5: v = v·(100 + 5·(5 − d)) / 100
  (+25 % adjacent … +5 % at distance 4). Pairs: 攻击: dyn0 (EV[3970]) near pid 0; 防御: dyn1 (EV[3971]) near pid 0;
  反应: dyn1 near pid 12; 士气: dyn0 near pid 29; 精神: none. (Scripts: dyn0 = 12 鲁明星, dyn1 = 29 鲁明月.)
* 并蒂 (attack only, only if the aura did not apply): if pid == u16 dyn2 (EV[3972], = 2 王君珂) →
  v = v·(100 + 8·byte[0x55ee02]) / 100. byte 0x55ee02 is a counter kept by batch-B1 hooks (0x4d1d30..0x4d1e27:
  counts attacks on 管毅/王君珂 while both are on the map, copied into 0x55ee00..03; [G] for the exact window).
These getters feed BU::Atk/Def/Agi/Morale (0x43f4fe.. → buff ×120/80), i.e. damage, hit, crit, double rates.
Port: `Person.stat` / `_aura_distance` (BUnit.stat applies the buffs after it).

##### B2 C. Percentage equipment bonus for 反应 and 士气 — functions of sites 0x4071d7, 0x407208 [C]
GetAgility/GetMorale call the .text cave 0x469341(s) with eax = EquipBonus(s): table 0x46235d = [1,1,1,5,5,1,1,5,3,4];
for s with entry 5 (s = 3, 4) the bonus becomes `stat_word[s] · EquipBonus(s) / 100`. So agility = min(w + w·B3/100,
9999), morale = min(w + w·B4/100, 9999) (matching the item text "+%d%%" for types 27/28). Port:
`Person.stat`.

##### B2 D. 【术】市侩 相马 move bonus — site 0x4072b6 [C]
MovePoints(person) = min(class.move + EquipBonus(7), 255) + 1 when: person[dyn7].byte+0x2a == 0 and this person's
+0x2a == 0 (both party members), dyn7 (u32 EV[3977]) ≠ 0x400, and this person's accessory (+0x34) ∈ {0x3d, 0x3e,
0x3f, 0x2f, 0x3b, 0x3c}. (Check dyn7 ≠ 0x400 before indexing person[dyn7].) Paralysis/move-buff handling of
0x43f74f applies on top as before. Port: `Person.move_points`.

##### B2 E. Level-up changes (0x4073b8) — sites 0x4073c9, 0x407471, 0x407492 [C]
Per LevelUp(n) call, in this order:
1. `bonus_stat = rand(5)` (MSVC rand % 5, drawn for every person — keeps RNG parity).
2. For i in 0..6: g = class growth; i ≤ 4: jitter for members (+0x2a == 0) when the bonus counter is 0, grade, counter
   (as the port does). i ∈ {5, 6}: if person+0x2a == 0 (party member) and mp_base ≠ 1:
   `g −= penalty(i)` (signed; may go negative and then lowers the base), where penalty (0x4d806a):
   ```
   L = level (before this level-up)
   q = (i == 5) ? (L + 490) / max(hp_base, 1) : L / max(mp_base, 1)          # unsigned ints
   scan player slots 0..14, stop at the first empty slot (+0 ≥ 0xffff); count units with state 2, sum their levels
   if count == 0: return 0
   avg = ceil(sum / count); if L <= avg: return 0
   return q == 0 ? L − avg : ceil((L − avg) / q)
   ```
3. Repeat n times: if pid == 10 (盛彦师) and i ≤ 4 and i == bonus_stat: g += 1 (stays for the remaining repetitions)
   and bonus_stat = 5; old = stat; if i ≤ 4 and g == 0: g = 1; AddStat(i, g) (HP base: max(1, min(hp+g, 9999)),
   signed min); gains[i] = new − old (last repetition only).
4. Unit HP += class byte 7, unit MP += class byte 8 (unpenalised, once per call; site 0x4074ae — already matched).
rules.md §1.1 is corrected: byte +0x2a is the membership flag, so the penalty is live for party members.
Port: `Person.level_up` / `_catchup_penalty`.

##### B2 F. Level-up report — site 0x407519 [C]
Default (byte [0x4dbe25] == 0, the 环境设定 option 升级显示能力成长 off): message box style 2 "%s升为%u级。" only.
Option on: style 0 text "%s升为%u级。\n\n" + for i = 0..6 the name (攻击, 防御, 精神, 反应, 士气, "HP MAX", "MP MAX")
followed by "增加了 %d。\n" (gains[i] ≥ 0; i ≥ 5 negative → "减少了 %d。\n"), all 7 lines even when 0. Then (original
code) for every strategy s in 0..0x43 whose learn level for the class == the new level: "学会了策略「name」！" (style 2).
Shown only when LevelUp's `show` argument is set (SetExp in battle); in a battle also the unit animation
0x45778f(pid, 0xb, 0, 0) and SE 11. Port: `Person.level_up_texts`, `BattleActions._show_level_up`.

##### B2 G. AI-side 【技】 technique triggers — site 0x407658 (same function hooked at 0x43acf5, batch B3) [C/G]
On an AI attack (0x43db49 → cave 0x407651 → 0x4d7808(att_slot, def_slot), combat object 0x4927f0, +0x608 strike
counter): [0x55ac24] = [0x55ac68] = 0; if this is not the first strike → plain attack 0x4064f1. Else the attacker
person decides a technique with chance `min(Morale(att)·50 / Morale(def), 100)` % (0x4d75d2, BU::Morale 0x43f67f):
attacker pid 44 → [0x55ac2c] = 1, 34 → [0x55ac30], 33 → [0x55ac20], 32 → [0x55ac1c], 43 → [0x55ac38], 4 → [0x55ac4c],
3 → [0x55ac50] (then up to 2 extra 0x4064f1 attacks while both units have HP > 0), 101/136 → [0x55ac54] = 1;
0x4d74e4 (围攻 adjacency check) and 0x4d7b90 (pid 0x400/0x65/0x88 → 1, 0xe → 2) set [0x55ac24]. All flags and
[0x55ac54] are cleared after the attack. The flags' effects live in other batches (area codes in H, hit −26 /
forced double in rules.md §4.2/§4.4, damage hooks). Port: `BattleActions.attack_cmd` / `_trigger`, for the
player's and the AI's attacks.

##### B2 H. Area attack code overrides — site 0x40783f (+ inline patch 0x40782a) [C]
AreaAttackCode(person) (0x407818; used by the attack target setup 0x4061fc and the AI 0x438c25/0x43f92c):
`if u32[0x55ac20] == 1: return 2` (inline at 0x40782a), else a = table 0x409191[class] (classes 6,7,8,10,11 → 4,
class 17 → 1, else 0); mod: `if byte[0x55ac2c] == 1: a = 0xa elif byte[0x55ac64] == 1: a = 0xc`; `if pid == 178
(文士弘): a = 6`; then original: if a < 4 and has_effect(21) and class ∈ {15, 16} → 1, class 17 → 2 (done); otherwise
if has_effect(43 穿透攻击): a = effect_value(43); return a. Port: `BattleActions.area_code`; the secondary targets
(mode bit 2: damage ×½, ≥ 1, rules.md §4) in `secondary_targets` (group 2).

##### B2 I. Equip permissions — sites 0x40790d, 0x4079ea [C]
CanEquip(person, item): first `if pid == 11 and slot_of(item) == 2 (accessory): return false` (樊虎); … for weapons
and armour: `if pid == u32 EV[3979] (dyn9, 尤俊达 【术】百宝): return true` before the class equip table.
Port: `Person.can_equip`.

##### B2 J. 环境设定 (title menu item 2 and system menu) with persistence — sites 0x4092e3, 0x41bb79, 0x41bd38, 0x41c001 [C]
Dialog KANKYOU (环境设定): 听背景音乐, 听音效, 战斗时窗口自动最大化, 战斗时自动显示战场缩小图, 会话窗口不自动关闭,
**升级显示能力成长 (mod, control 0x3f0 → byte [0x4dbe25])**, 讯息显示速度 快/普通/慢, 武将移动速度 慢/普通/快,
对话框花色. The mod persists GS+0, GS+1, GS+8, GS+0x10 and [0x4dbe25] to SAVEDATA\Niuniu.wa bytes 1..5 when the
title's 环境设定 closes (0x4e2000) and loads them at title start (0x4e20ff). The checkbox 0x3ef the mod also reads
does not exist in the template, so the deterministic RNG mode ([0x55ad00]) can never be switched on. Port:
`Settings`, `SettingsWindow` (all the options, group 5).

##### B2 K. 暗杀 (strategy 21) countdown — sites 0x4093b5, 0x4093c3 [C]
On a successful 暗杀 (0x43c058): byte 0x569f00[target slot] = 2, byte 0x569f73[target slot] = caster slot,
byte [0x569fe7] ^= 1; the target is **not** defeated. At the start of the enemy phase (0x44e92e → slots 0..34) and
of the player phase (0x44ee2c → slots 35..114), for every unit with state 2 (0x40937f): if counter > 0: counter −= 1;
when it reaches 0 and 0x569f73[slot] ≠ 0xff: unit HP = 1, EV[10] = 1, message box style 2 "%s被暗杀了！！" (person
name), 0x569f73[slot] = 0xff. The info window shows 暗杀 while the counter ≠ 0 (already ported). The battle scripts'
"HP < 2" checks (see L) then handle officers. Port: `BattleStage._assassination_countdown`.

##### B2 L. EV[10] "unit fell" signal — site 0x4121b5 (+ other batches) [C]
The engine writes EV[10]: = 1 when a unit is killed by a script (0x4121b0: set_attr attr 7 / data_transfer HP ≤ 0),
by the 暗杀 countdown, after a physical attack leaves a target at HP 0 (0x405bb5, B1) and after a strategy does
(0x422c85); = 0 at the start of every AI unit's action (0x43ad2b), at 0x43e16b and at battle start (0x44ccc8).
27 battles (S_23..S_57) have a section "合并所有HP0撤退" with condition `EV[10] ≥ 1` that gives officers at HP < 2
their defeat dialogue and retreat (op 0x53), e.g. S_43 刘武周/尉迟恭/宋金刚/魏刁儿/李世民 (秦王战死 → defeat).
Port: set in `BattleActions.unit_fell` and `BattleStage._assassination_countdown`; cleared in `BattleAI.act`,
`BattleStage.create_battlefield` and `BattleInput.command_menu`.

##### B2 M. 史录 chronicle write semantics — sites 0x413aa1, 0x413adc [C]
Category ≠ 0xff: always append ('&', cat, text), no duplicate check (buffer limit 0x56b800). Category 0xff: find the
entry with the same leading number; none → do nothing; text that is only the number → delete that entry; else
replace its text (category kept). Port: `Game.add_history`.

##### B2 N. op 0x3b join is ignored in battles — site 0x4149e6 (function 0x4148fe) [C]
Before calling 0x4d5000/0x40c28c the handler returns 1 without doing anything when 0x40b922() (scene object mode
== 3, i.e. a battle). Port: `ScriptHost.op_join` returns while `in_battle()`; the mod's mode-1 path is
`Game.join_party` (EV[4000] is never set).

##### B2 O. op 0x58 with alt ≠ 0 = revert a map change — site 0x41687d [C]
Args (patch a0, alt a1, terrain a2, x, y, scroll a5, silent a6). alt ≠ 0: if scroll ≠ 0, write terrain a2 & 0xff
into the grid at (x, y) (0x4d7d7c); then 0x4567c1(x, y, patch, scroll): find the recorded change with that x, y
and patch (table 0x4b3d21, 250 × 5 bytes); none → stop (the written terrain byte stays). Found: scroll ≠ 0 →
centre on (x,y); patch < 4 → clear the overlay mark; else redraw the 3×3 cells from the map bitmap (gate special
case: new terrain 0x11 → SE 18 and a pause when an adjacent cell is also a gate); grid(x,y) = recorded old terrain;
clear the record. 344 uses (S_15 188, S_36 27, S_00 10, …; typically `58 [2,1,0,x,y,1,1]` = put out fire). Port:
`BattleStage.op_op_58` → `_revert_terrain`.

##### B2 P. Sortie candidates — site 0x4186e3 (function 0x41856a) [C]
The selection pool after the forced persons: for j = 0..31, c = byte table 0x4dbdb0[j] = [0, 8, 3, 1, 19, 17, 14,
26, 7, 5, 43, 4, 9, 2, 24, 13, 10, 6, 16, 18, 12, 11, 28, 25, 15, 23, 22, 21, 29, 20, 31, 27] except that j = 0 uses
table[max count byte 0x4b09ec] (register quirk), so 管毅 is never offered unless forced; c is added when a party
member, not yet listed and not in the exclusion list u32 0x4b0a04[0..4]. Members outside the table (e.g. pid 30
and pids ≥ 32) are never offered. Order on screen = this order. Port: `ScriptHost.build_sortie`.

##### B2 Q. 太保令 (item 96, type 69) — site 0x41d063 [C]
Battle use: target person's stat words +0x11..+0x19 each += 2 (≤ 9999) and raw abilities +0x21..+0x25 each += 2
(≤ 100); unit effects 0x45778f(pid, 0xb, 0xff, 0xff) then (pid, 7, 0, 0) [G: level-up style flash]. No buff change.
Port: `BattleActions.use_item`.

##### B2 R. Story videos cannot be skipped — site 0x41f60c [C]
In PlayVideo a click or key press ends the video only for ids 0..3 (LOG.avi, OPE.avi, END.wmv, PRE.wmv); videos with
id ≥ 4 (001.wmv … from op 0x22) ignore input and play to the end. The port lets every video be skipped, on
purpose ([Deliberate differences](#deliberate-differences-port-design-keep-unless-asked)).

##### Also noted (not changes at my sites, found while verifying)
* rules.md §1.1: "+0x2a growth-fixed flag … unused by data" was wrong (membership byte; see E). Fixed with this audit.
* rules.md §11: dyn list is EV[3970..3999] (see header). Fixed with this audit.
* SetExp 0x408950 keeps levelling past 70 while the remainder is ≥ 100 — original code; ported
  (`BattleActions.set_exp`).

### B3 — Strategies, story scenes, AI attack (0x420000..0x43afff)
Port = `game/src` (GDScript). Exe = `wg2025/wagan.wa`. Person names as in [Skill owners](#skill-owners). EV[n] = u32 @0x55b000+4n. "Group" = slot < 35 (player+friend) vs slot ≥ 35 (enemy)
(0x406710; port `BUnit.is_enemy_of`). "Colour" = U+5 (0 = player colour; 0x43ff54 = colour==0).

Many rows are `call 0x4d3197`: that helper is `ecx = 0x4b2c50 + (ecx & 0xff)*0x24` (unit pointer), a 5-byte
replacement of the inline 15-byte sequence. It changes nothing by itself; the row is judged by what the freed
bytes were used for (stated in the row).

Status counts: PORTED 38 (incl. 2 dormant, 2 cosmetic) · PARTIAL 0 · MISSING 0 · N/A 25 · FALSE 0 (total 63).
Checked against the port after groups 1–5 (2026-10-12); the features below were specs and are now ported.

#### B3.1 Sites

| site | original function (what it does) | mod change | feature | status | port evidence / missing spec |
|---|---|---|---|---|---|
| 0x420433 | 0x420422 strategy usability (s, caster, target, show_msg) | `call 4d3197` compaction; freed space holds the new check at 0x420473: category ≤ 3 (element) and has_effect(caster, 50 左思兵法) → usable regardless of terrain (zero padding 0x420486..0x42049b) | 左思兵法 terrain exemption for element strategies | PORTED | `rules.gd strat_terrain_ok` (`has_effect(50)`), used by `strat_usable` |
| 0x420869 | 0x420422 case 15 (开导/诫谕/战备; Ghidra lost the function) | compaction of the `push 4 … 0x425af0` test; the freed bytes hold, at 0x420832, `0x4b69b0.0x47467a(2, 1)` (SE 2 = Se02.wav) + 6 nops before the message 不能对自己使用。 | error beep when the player targets himself with 开导/诫谕/战备 | PORTED | battle_input.gd `_do_strategy`: `Audio.se(2)`, then the message |
| 0x4209b7 | 0x42097a element area filter (other units of the area) | compaction (+4 nops); prologue rewritten to insert `has_effect(caster,50) → pass` at 0x420990 | 左思兵法 exemption also for the area | PORTED | battle_actions.gd `strategy_targets` → rules.gd `strat_terrain_ok` |
| 0x420d95 | 0x420cb2 buff/debuff op → BuffStep | `jmp 4d8985` for op 0x35: person class (P+0x2b) == 50 or 24..26 → 攻击↑ and 精神↑; else 0x43ffed family → 精神 or 攻击 | 激励/点兵/聚气/豪气 on 武僧/罗汉/活佛/玄术骑 | PORTED | battle_actions.gd `_stat_code` 0x35 |
| 0x422c87 | 0x4224a8 strategy result application, per target after HP/MP subtraction | when amount > 0 and the target's HP is now 0: `0x4d67b8(1)` → EV[10] (u32 0x55b028) = 1, then skip the 馒头 logic | HP-0 event flag EV[10] (drives the scripts' 合并所有HP0撤退 sections) | PORTED | battle_actions.gd `_apply_strategy` / `_apply_random_strategy`: a kill calls `unit_fell` (EV[10] = 1) instead of `_strategy_bun` |
| 0x422cf9 | 0x4224a8, damaged survivor with effect 62 (笼屉 使用馒头), player colour | `jmp 4dca83`: only if HP + 100 ≤ MaxHP (loss ≥ 100) continue to the original "if bag has 馒头 (0x57) use one" code at 0x422cfe, else skip | 笼屉 (item 81) auto-eat 馒头 after strategy damage, ≥100 loss threshold | PORTED | battle_actions.gd `_strategy_bun` → `eat_bun` |
| 0x422f77 | 0x422f0d strategy MP deduction | `jmp 4d4a05`: after the 节约MP reduction, if 0x4d4a60(179 房玄龄, caster) → cost >>= 1, min 1 | 房玄龄 【术】房谋: half MP cost next to him | PORTED | battle_actions.gd `strategy_cost` (节约MP, then `Skills.beside(179, u)` halves, min 1); paid in `cast` |
| 0x4231b8 | 0x42313e damage-strategy handler (ids 0-13,15-22,65), target collection | `call 528270` wraps 0x425349: if caster pid == EV[3989] or EV[3990] (dyn skills 19/20 【术】弱杀) add every on-map unit (any side) with a status bit 0x7e | 【术】弱杀 extra targets | PORTED (dormant) | battle_actions.gd `strategy_targets` (`Skills.dyn(19)` / `dyn(20)`, DAMAGE_HANDLER); no script assigns EV[3989]/EV[3990]: F4 |
| 0x42322d | 0x42313e per-target damage loop | compaction; freed bytes hold the check at 0x423253: if [0x569fe7]==1 (toggled by 暗杀's successful hit in 0x43bfaa) clear it and store the display code (hit) instead of 0 (miss) although the damage is 0 | 暗杀 success counted/shown as a hit | PORTED | battle_actions.gd `_apply_strategy` s == 21: damage 0, mark, toggle [0x569fe7], shown as a hit ("暗杀"), non-kill EXP |
| 0x42334a | 0x42313e tail (after 0x4214bf + 0x4224a8) | `jmp 528100` (replaces `mov [ctx+0x4ac],1`): caster pid ∈ EV[3985..3988] (【术】烈魔) → toggle [0x5280fe] and re-run the per-target loop once more; second time: reset toggle, ctx+0x4ac = 1 | 烈魔: damage strategies strike twice | PORTED | battle_actions.gd `cast`: second pass of `_apply_strategy` for `lie_mo(u)` and DAMAGE_HANDLER; MP paid once: F5 |
| 0x4235d6 | 0x423549 status / cure handler (31-37, 46-47), target collection | `call 528270` (as 0x4231b8) | 【术】弱杀 extra targets | PORTED (dormant) | battle_actions.gd `strategy_targets` (STATUS_HANDLER): F4 |
| 0x42377a | 0x423549 tail | `jmp 528160` (same as 0x528100) | 烈魔: status/cure strategies applied twice | PORTED | battle_actions.gd `cast` (STATUS_HANDLER; heals excluded): F5 |
| 0x425297 | 0x4251e1 strategy context init: cast range → ctx+0x2c9 | `call 5281c0` (replaces the store): range ≠ 10 and caster pid == 35 苏烈 → range code 13 (manhattan 1..4) | 苏烈 【术】逐影随行咒 range | PORTED | battle_actions.gd `strategy_cast_cells` (range ≠ 10 and pid 35 → 13) |
| 0x4252b5 | 0x4251e1: area code → ctx+0x2ca | `call 528200`: caster pid ∈ EV[3985..3988] → area 0→1, 1→2, 2→3, other→6 | 烈魔 area expansion | PORTED | battle_actions.gd `strategy_area` with `lie_mo` |
| 0x425ad7 | 0x425ad0 MP cost getter | inline: `if [0x4d0d61]: mp <<= 1` (+8 nops) | 连续策略 second cast costs double | PORTED | battle_actions.gd `strategy_mp` doubles while [0x4d0d61]; `second_cast` (0x4d0d71) sets/clears it; detail_panel.gd `strategy_mp` |
| 0x426c3c | 0x426c32 op 0x2f clear actors | arrays relocated to mod data: pid table u16[25] @0x4d0da8 | RPG actor-graphics cache (LRU, enlarged to 25 slots) | N/A | engine resource cache; port loads actor sprites on demand (story_stage.gd `op_op_2f`) |
| 0x426c4d | 0x426c32 | age table u8[25] @0x4d0dda | same | N/A | same |
| 0x426f10 | 0x426efe cache lookup | uses 0x4d0da8 | same | N/A | same |
| 0x426f39 | 0x426f22 cache touch (ages) | uses 0x4d0dda | same | N/A | same |
| 0x426f42 | 0x426f22 | uses 0x4d0da8 | same | N/A | same |
| 0x426f52 | 0x426f22 | uses 0x4d0dda | same | N/A | same |
| 0x426f5b | 0x426f22 | uses 0x4d0dda | same | N/A | same |
| 0x426f81 | 0x426f65 cache insert | uses 0x4d0da8 | same | N/A | same |
| 0x426fa1 | 0x426f8b oldest-slot search | uses 0x4d0da8 | same | N/A | same |
| 0x426fb1 | 0x426f8b | uses 0x4d0dda | same | N/A | same |
| 0x42702d | mod code in .text reached from 0x4011a0 (phase-start per-unit hook 0x401118 called by StatusRecovery 0x43c7ec) when family(unit) == 16 | `call 4d3f88`: ctx init (strategy 67), collect the 雄师's own-side units in the 3×3 around the unit, set their 士气 buff to 6, Xben effects 0x10 then 0x25 | 雄师 (class family 16) morale aura at phase start | PORTED | battle_stage.gd `_phase_skills` (family 16 → `_aura`: 士气 buff 6, Xben 0x10 then 0x25) |
| 0x4298dd | 0x4298b6 RPG input poll: on flag 8 hide windows | `ShowWindow([0x4d1050], SW_HIDE)` — the mod's text-log window — beside the 武将情报 window | hide mod log window | N/A | Win32 window management; port windows are modal |
| 0x42a2a3 | 0x42a054 restore an RPG scene from a save | `jmp 4d0bf1`: toolbar 0x496f38.0x419d22(arg) with arg = [0x55ac02] ? 0 (with 出征) : 1 (without) instead of always 1 | 出征 button survives a save load | PORTED | story_stage.gd saves and restores `sortie_enabled` |
| 0x42bed6 | mod code in .text (0x42beae) entered from the attack animation switch 0x40465d | step→case table: attacker person 0 管毅 or 204 张善相 → table 0x42bef2 (steps 4-6 play cases 3,1,3), [0x4d352e]==1 (set while a 绝招 runs, 0x4d355e) → table 0x42bf08 (cases 3-6 three times), else 0x40572e | per-person / 绝招 attack animation | PORTED (cosmetic) | battle_actions.gd `anim_table` / `_anim_strike` (0x42bef2, 0x42bf08 while [0x4d352e] = 1): F13 |
| 0x42d08b | 0x42cb6d portrait message window (called from 0x42d5f1) | `call 4d41de` → 0x47349c(x−0x40, y−0x55, 0x220, 0x100) | larger window geometry | N/A | dialog chrome; port draws its own box (dialog_box.gd) |
| 0x42d196 | 0x42cb6d | load mark.wa bitmap 5 (speech mark) | window decoration | N/A | same |
| 0x42d1bf | 0x42cb6d | load sge.wa bitmap 301 + face(0x4075a7) (120×120) | large portrait in dialogs | PORTED | game.gd `person_face` (large set) → dialog_box.gd |
| 0x42d2e3 | 0x42cb6d | load mark.wa bitmap 2 (side piece) | decoration | N/A | port panel style |
| 0x42d2f5 | 0x42cb6d | load mark.wa bitmap 3 (side piece) | decoration | N/A | same |
| 0x42d2fa | 0x42cb6d | `jmp 4d4740`: store portrait/window positions in 0x4cf2fc..0x4cf30c, InvalidateRect | layout/repaint | N/A | same |
| 0x42d936 | 0x42d5f1 dialog window (ops 0x14/0x16) | window geometry wrapper 0x4d41de | layout | N/A | same |
| 0x42d95f | 0x42d5f1 | sge.wa 301 + face | large portrait | PORTED | game.gd `person_face`, dialog_box.gd |
| 0x42da98 | 0x42d5f1 | mark.wa 2 | decoration | N/A | — |
| 0x42daaa | 0x42d5f1 | mark.wa 3 | decoration | N/A | — |
| 0x42db01 | 0x42d5f1 | `jmp 4d42ae`: portrait x by [0x48c81c] (side), y, repaint | layout | N/A | — |
| 0x42de96 | 0x42de12 choice window (op 0x12) | geometry 0x1e0×0x80 | layout | N/A | — |
| 0x42def9 | 0x42de12 | portrait = sge 301 + face of person **arg1** of op 0x12 (0xFFFF → 0 = 管毅) | portrait in the choice box | PORTED (cosmetic) | script_host.gd `op_choice` (`ui.menu.face`, 0xFFFF → 0; "1."–"3."): F14 |
| 0x42df23 | 0x42de12 | 0x4d41a6 GetClientRect+InvalidateRect | repaint | N/A | — |
| 0x43337a | mod code in .text 0x433373 = per-strike step of Attack (called 0x40653a) | `call 4d78e2`: if a 【技】 flag is set show its banner (map dim 0x4d64ea, 0x4d6366(name), 0x4d6576): [0x55ac1c] 龙吟, [0x55ac20] 凤舞九天, [0x55ac24]=1 双雷引, [0x55ac30] 盖马三锤, [0x55ac2c] 横推八马倒, [0x55ac38] 鬼门刀, [0x55ac4c] 怒目, [0x55ac50]=1 煞, [0x55ac24]=2 抽屉枪 | 【技】 technique banner at the strike | PORTED | battle_actions.gd `strikes` (step) → `_technique_banner` (BANNERS) over the dimmed map |
| 0x433401 | 0x433373 | [0x55ac30]==1 → `0x4d83fe(defender)` + 0x405c6c instead of the normal strike | 李元霸 【技】盖马三锤 knock-on | PORTED | battle_actions.gd `strikes` → `_gaima`, no counterattack |
| 0x433521 | mod code in .text (level-up stat loop, from 0x4073b9) | `je 4d02ec`: jitter 0x448b09 only if bonus counter [0x4cf2b8]==0 and 0x4d039b(person)==0 | level-up growth (jitter gate + bonus grade) | PORTED | person.gd `level_up` |
| 0x4335eb | 0x4335d0 op 0x69 popup | text "\|name": `0x4d64ea` dim map | special-technique banner | PORTED | battle_stage.gd `op_popup` (dim) → script_host.gd `op_popup` → game_ui.gd `skill_banner` |
| 0x4335fa | 0x4335d0 | `0x4b3d08.0x4d6366(name)` banner | same | PORTED | same |
| 0x4335ff | 0x4335d0 | `0x4d6576` restore | same | PORTED | same |
| 0x434fb2 | 0x434f84 (special-battle setup for persons 0/32/157) | compaction | — | N/A | function has no callers/pointers anywhere in the image (dead code) |
| 0x434fc7 | 0x434f84 | compaction (stores eax = index, not the pointer: would be a bug if reachable) | — | N/A | dead code |
| 0x435dee | 0x435d6c strategy area builder, case 1 | mod rewrite of the cases: side filter by group (0 opposite, 1 same, 2 any) | area + side filter | PORTED | shapes.gd `area_cells` + battle_actions.gd `strategy_targets` (`_side_ok`, `is_enemy_of` = group) |
| 0x435eda | 0x435d6c case 2 | same | same | PORTED | same |
| 0x435fc6 | 0x435d6c case 3 | same | same | PORTED | same |
| 0x436053 | 0x435d6c case 7 | same | same | PORTED | same |
| 0x436337 | 0x435d6c case 11 (8 cells around the caster, excl. the target) | same | same | PORTED | no strategy uses area 11; shapes.gd `caster_ring` (the target is the entry before the list, 0x4362e7, and is skipped) |
| 0x4364e1 | mod code in .text 0x4364d6 (loop over on-map units, calls 0x40937f); 0x4364b6 (units 0..34) from 0x44e92e enemy-phase start, 0x4364c6 (35..114) from 0x44ee2c player-phase start | the 暗杀 countdown | 暗杀 delayed effect | PORTED | battle_stage.gd `_assassination_countdown` (35..114 at the player phase start, 0..34 at the enemy's): F7 |
| 0x43a101 | 0x4395ae AI StratScore, 战备 case | compaction of the last family test; case: ai∈{2,3} or family 9 → 0; family 0/19 → 15; 5 → 10+rand(4); 8 → 10; else rand(5) | AI 战备 scoring | PORTED | battle_ai.gd `_strat_score` case 57 |
| 0x43a9be | 0x43a956 MoveAlongPath (AI walk) | `jmp 4d3a2d` after StepToward 0x437e2e: (a) byte [0x55a6d0]≠0 → 0x4d396a: path[0..n] = dir [0x55a6d1], clear; (b) [0x4cf314] (绝招 running) and person 5 → path[0] = path[1] = U.dir | 伍云召 【招】踏破连营 forced charge path | PORTED | normal path: battle_ai.gd `_path_from`; the charge walks its straight line in battle_commands.gd `_ta_po_lian_ying`: F12 |
| 0x43aac3 | 0x43a9c3 (rest of MoveAlongPath) | `[0x4d0d5c] = steps walked` | old 冲锋 step bonus | N/A | only reader 0x40910e (steps×30 damage) is orphaned; live 冲锋 (effect 89) is 0x43bee6→0x4d8d65 using [0x4cfc00], ported as bunit.gd:31 `move_origin` |
| 0x43ac3f | 0x43aafb AI PhysicalAttack, the Attack call | `jmp 4d6b80`: 围攻 if possible (0x4d698e / 0x4d6d87), else attack through the 【技】 wrapper 0x4d7808 | AI 围攻 + 【技】 triggers | PORTED | battle_ai.gd `_physical_attack`: `commands.siege` (F11), else `actions.attack_cmd` (F10) |
| 0x43acf5 | 0x43aafb, 引导攻击 (effect 46) follow-up attack | `call 4d7808` instead of 0x4064f1 | 【技】 triggers on the follow-up | PORTED | battle_ai.gd `_physical_attack`: the 引导攻击 attack also goes through `attack_cmd` |
| 0x43ad2b | 0x43ad1c AIAct start | `0x4d67b8(0)` → EV[10] = 0 | HP-0 event flag reset per AI action | PORTED | battle_ai.gd `act`: `Mem.set_ev(10, 0)` |

#### B3.2 Features (were missing / partial; all ported)

##### B3 F1. HP-0 event flag EV[10] (sites 0x422c87, 0x43ad2b; related elsewhere: 0x405bb7, 0x4093c3, 0x4121b5, 0x43e16b, 0x44ccc8) — PORTED [C]
* `0x4d67b8(n)`: u32 [0x55b028] = EV[10] = n.
* Set to 1: strategy result application 0x4224a8 — for each target with amount > 0, after subtracting HP, if HP == 0
  (0x422c87; the 馒头 check is skipped); also physical strike leaving HP 0 (0x405bb7), 暗杀 maturing (0x4093c3),
  script HP write (0x4121b5).
* Set to 0: at the start of every AIAct (0x43ad2b, before anything else), at battle start (0x44ccc8), 0x43e16b.
* Consumer: 27 battle scripts (S_23..S_57) have the section "合并所有HP0撤退" with condition `test_int_var EV[10] >= 1`;
  its body handles every named unit at HP 0 (custom lines, `unit_op_53` retreat, counters EV[322..326], flags,
  程咬金's return, 管毅 → "管毅败在隋军手下，惨遭杀害。" + game over) and jumps to "合并撤退·续·减好感", which sets
  EV[10] = 0.
* Port: set to 1 by battle_actions.gd `unit_fell` (attack, strategy; `unit_defeated` for scripts) and
  battle_stage.gd `_assassination_countdown`; set to 0 in battle_stage.gd `create_battlefield` (0x44ccc8),
  battle_ai.gd `act` (0x43ad2b) and battle_input.gd before each player command (0x43e16b). The pre-battle loop's
  15 is cleared at battle start.

##### B3 F2. 笼屉 (item 81, accessory type 62 使用馒头) auto-eat after strategy damage (0x422cf9) — PORTED [C]
In 0x4224a8 per target, after HP is reduced by `amount = min(stored, HP)` with amount > 0 and HP > 0, if
has_effect(target, 62):
* colour ≠ 0 (not player colour, 0x43ff54 false): `0x497750.0x41dc43(0x57, slot, 0, 1)` — use 馒头 (item 87,
  consumable 恢复HP, value 70) on it for free (param 4 = 1: no bag consumption).
* colour == 0: mod — only if `HP + 100 ≤ MaxHP` (loss ≥ 100); then if the bag count of 0x57 (`0x4b0770.0x40db3e(0x57)`)
  > 0 use one from the bag (`0x41dc43(0x57, slot, 0, 0)` → 0x40d955 removes it).
The physical path is 0x405bc1..0x405c44 (B1; there the mod's 0x4d681c applies the ≥100 threshold before the effect
check for both sides). Port: battle_actions.gd `_strategy_bun` → `eat_bun`; the physical path in `strikes`.

##### B3 F3. 房玄龄 【术】房谋 — half strategy MP (0x422f77) — PORTED [C]
MP deduction 0x422f0d (only if ctx+0x4ac): `cost = strategy.mp (×2 while [0x4d0d61]); if has_effect(caster, 49 节约MP):
cost -= cost*val/100;` mod: `if 0x4d4a60(179, caster): cost >>= 1; if cost == 0: cost = 1`; `MP = sat_sub(MP, cost)`.
0x4d4a60(pid, U) = pid's unit exists (0x43e4d6), state 2, same group as U (slot<35 both or ≥35 both), both HP > 0,
and pid's unit is in one of the 8 cells around U (0x45afca(U.person, pid, 1)). The caster himself never qualifies.
Port: battle_actions.gd `strategy_cost` (`strategy_mp` with the 连续策略 doubling, 节约MP, 房谋 via `Skills.beside`),
shown in the 策略 list and paid after the effect in `cast`.

##### B3 F4. 【术】弱杀 extra targets (0x4231b8, 0x4235d6) — PORTED, dormant [C]
`0x528270(kind)`: call 0x425349(kind) (normal target list ctx+0xd, 0xff-terminated); then if caster pid == EV[3989] or
EV[3990]: for every unit 0..114 with state 2 and (status & 0x7e) ≠ 0 (any side, the caster included if affected),
append it if not already in the list. Applies to damage strategies (0x42313e) and status/cure strategies (0x423549).
No shipped script writes EV[3989]/EV[3990] (R_00 sets EV[3970..3999] = 1024), so it never triggers today.
Port: battle_actions.gd `strategy_targets` (DAMAGE_HANDLER / STATUS_HANDLER only).

##### B3 F5. 【术】烈魔 — area expansion and double cast (0x4252b5, 0x42334a, 0x42377a) — PORTED [C]
Holders: pids in EV[3985..3988] (0x55ee44..50): R_49 sets 35 苏烈 and 166 梁廷方, R_50 sets 168 杜明方, 169 蔡建方.
* Area (context init 0x4251e1 → 0x528200): strategy area code 0→1, 1→2, 2→3, any other → 6 (line of 2 beyond the
  target) — for every strategy they cast.
* Double execution: damage handler 0x42313e and status/cure handler 0x423549 — after the first full application
  (0x4214bf, 0x4224a8), if the toggle [0x5280fe] == 0: set it to 1 and run the per-target loop again on the same
  target list (fresh hit/damage rolls, results applied and shown again; target collection and the main-target
  usability check are not repeated); after the second pass set the toggle to 0 and ctx+0x4ac = 1 (so MP is deducted
  once by 0x422f0d). Not applied to heals (0x42378d) and the other handlers.
Port: battle_actions.gd `lie_mo`, `strategy_area`, and the second pass in `cast`. That pass skips targets that
fell in the first; the original runs the whole list again (0x4231bd), which only shows them again (HP 0, amount 0).

##### B3 F6. 苏烈 【术】逐影随行咒 — strategy range (0x425297) — PORTED [C]
Context init: `range = strategy.range (byte +0xc); if range != 10 and caster pid == 35: range = 13` (manhattan 1..4,
40 cells), stored in ctx+0x2c9 (used by the target scan 0x45533d). Self-cast strategies (range 11) also become 13.
[G] whether the player's targeting highlight uses the same value (it reads the same context). Port:
battle_actions.gd `strategy_cast_cells`, used by the player's targeting.

##### B3 F7. 暗杀 delayed effect (0x4364e1; with 0x42322d, B1 0x40937f, B4 0x43c05f) — PORTED [C]
* On a successful 暗杀 (0x43bfaa): mark [0x569f00+t] = 2, assassin [0x569f73+t] = caster slot, toggle [0x569fe7];
  damage 0; the handler stores the hit display code (0x42322d) so it shows as a success; EXP = non-kill formula.
* Countdown 0x40937f(slot) for on-map units: at the **player** phase start for units 35..114 (0x44ee2c → 0x4364c6)
  and at the **enemy** phase start for units 0..34 (0x44e92e → 0x4364b6): if mark ≠ 0: mark −= 1; when it reaches 0
  and assassin ≠ 0xff: unit HP = 1, EV[10] = 1, message box style 2 "%s被暗杀了！！" (0x48c9e6, person name),
  assassin = 0xff. So an enemy hit in player turn n drops to 1 HP at the start of player turn n+2. The 武将情报
  状态 line shows 暗杀 while the mark is set (port has that, info_window.gd:194).
* Port: battle_actions.gd `_apply_strategy` (s == 21: mark, toggle, shown as a hit, non-kill EXP) and
  battle_stage.gd `_assassination_countdown` in the phase start; `remove_unit` cancels the marks of a leaving
  assassin.

##### B3 F8. 连续策略 second cast (0x425ad7) — PORTED [C]
0x425ad0: `mp = strategy.mp; if [0x4d0d61]: mp *= 2`. The flag is set by 0x4d0d71 after a cast by a unit with
effect 83 (连续策略) and the strategy menu reopens (0x43dc4e loop); cleared after the second cast (0x43dc87).
Port: battle_actions.gd `strategy_mp` doubles while [0x4d0d61]; `second_cast` (0x4d0d71) sets and clears it after
the player's casts (battle_input.gd `_do_strategy`) and the AI's (battle_ai.gd); detail_panel.gd `strategy_mp` for
the 武将情报 column.

##### B3 F9. 雄师 morale aura at phase start (0x42702d; chain 0x401118 is B1) — PORTED [C]
0x401118(unit) runs from StatusRecovery 0x43c7ec for each on-map unit of the phase's side. If family(unit) == 16
(雄师类 = class 42 雄师): `0x497af8.0x4251e1(67, unit)` (context, strategy 白虎), then 0x4d3f88: collect via
0x4011a9 the on-map units of the 雄师's own side in the 3×3 around the unit (gather mode 0 = kinds 0/1 for a player or
friend 雄师, 0x102 = kind 2 for an enemy one; resolved after the audit), excluding itself (unless [0x4cfbec]==1;
nothing writes that byte, so always), and 0x4d47af(0x25, 0x10, 0x506): each gets 士气 buff U+0x1c = 6, display code
0xbf, then 0x4d485d(0x10, 0x25) plays Xben 0x10, then 0x25, on them. Port: battle_stage.gd `_phase_skills` → `_aura`.

##### B3 F10. 【技】 attack techniques (0x43337a, 0x433401, 0x43ac3f, 0x43acf5) — PORTED [C trigger/banner, G details]
* Attack wrapper 0x4d7808(att, def) (AI attacks 0x43ac3f/0x43acf5; player path elsewhere): clear [0x55ac24],
  [0x55ac68]; if not in a counter (ctx+0x608 == 0): trigger 0x4d76d0 by attacker pid with chance
  `0x4d75d2 = chance(min(Morale(att)*50/Morale(def), 100))`: 44 新文礼 → [0x55ac2c] 横推八马倒, 34 李元霸 → [0x55ac30]
  盖马三锤, 33 宇文成都 → [0x55ac20] 凤舞九天, 32 杨林 → [0x55ac1c] 龙吟, 43 魏文通 → [0x55ac38] 鬼门刀, 4 单雄信 →
  [0x55ac4c] 怒目, 3 尉迟恭 → [0x55ac50] (banner 煞), 136 东方伯 / 101 定彦平 → [0x55ac54] = 1 (双雷引); otherwise
  0x4d74e4/0x4d7b90 may set [0x55ac24] = 1 双雷引 / 2 抽屉枪. Then Attack (0x4064f1); with [0x55ac50] the attack repeats
  while both alive, up to 3 attacks; flags 0x55ac50/54 cleared at the end.
* Strike step 0x433373: show the banner of the set flag (0x4d78e2: dim map, name, restore); then
  - 盖马三锤 ([0x55ac30]==1): 0x4d83fe(defender D): list the units in the 8 cells around D of D's group; 3 times pick a
    random one and run 0x4927f0.0x4d2f1e(D, picked) (D strikes it: target setup 0x4061fc + strikes 0x433540, no
    counter), then 0x4d8632 [G display], clear the flag; then 0x405c6c.
  - otherwise normal strike, then all flags cleared, 0x55ac50 1→2, DoubleCheck, 0x55ac54 1→2.
  The per-technique damage effects live in other hooks (B1/B4).
* Port: battle_actions.gd `attack_cmd` / `_trigger` (wrapper), `strikes` → `_technique_banner`, `_gaima`,
  `_technique_hit`; the AI calls `attack_cmd` (battle_ai.gd `_physical_attack`). Corrections from group 3 are in
  [Character skills](#3-character-skills--done).

##### B3 F11. AI 围攻 joint attack (0x43ac3f) — PORTED [C]
0x4d6b80 in AI PhysicalAttack (after the move, target in range): partners = 0x4d698e(att, def): units in the 8 cells
around the defender, ≠ attacker, same group as the attacker, flag 2 not set, not confused (0x08), whose attack range
code (0x43f8be) reaches the defender: orthogonal cells codes {0,1,5,6,10,12,13}, diagonal cells {1,6,10,12,13}
(list 0x4cf318). If ≥ 1 partner, the attacker is in the 3×3 around the defender, and its range code ∉ {2,3,4}:
0x4d6d87 — SE 5; attacker strikes (0x4d2f1e), every partner strikes in turn and gets flags 6 (moved+acted,
0x43ef91(6)); then the defender counters once (0x40639a) unless [0x4d002c]; attacker flags 6; no 引导攻击 follow-up.
Else the normal attack through 0x4d7808 (F10). The player's 围攻 command (0x50d) is the same routine (B5 F2).
Port: battle_ai.gd `_physical_attack` → battle_commands.gd `helpers` / `siege`.

##### B3 F12. 伍云召 【招】踏破连营 path override (0x43a9be) — PORTED [C code, G technique link]
After StepToward in MoveAlongPath: (a) if byte [0x55a6d0] (n) ≠ 0: path[0..n] = byte [0x55a6d1] (direction), then
the word is cleared — set by the charge routine 0x4d4c07..0x4d4cdf (n = enemy units in the line ahead, direction =
facing); (b) if [0x4cf314] (a 绝招 is running) and person == 5: path[0] = path[1] = U.dir (2 steps forward).
The port's AI walk (battle_ai.gd `_path_from`) needs neither: the charge builds its straight path itself
(battle_commands.gd `_ta_po_lian_ying`), and (b) changes nothing on that path.

##### B3 F13. Attack animation step tables (0x42bed6) — PORTED, cosmetic [C]
Attack animation switch 0x40465d (step 0..21 → case via table): attacker [ebp-0x1034]+0xc person 0 管毅 or 204
张善相 → table 0x42bef2 `0,9,1,10,3,1,3,2,9,9,9,3,4,5,6,9,7,9,9,9,9,8`; else while 尽命三锤 runs ([0x4d352e]==1, set
only around its blow, 0x4d355e / 0x4d3575) → 0x42bf08 `0,1,10,9,9,3,4,5,6,3,4,5,6,3,4,5,6,7,9,9,9,8`; default
0x40572e `0,9,1,10,9,9,9,2,9,9,9,3,4,5,6,9,7,9,9,9,9,8` (case 9 = idle). I.e. a wind-up shake for 管毅/张善相, three
strikes in 尽命三锤. The cases are in engine_notes.md; the port runs them in `BattleActions._anim_strike`
(`anim_table`; 尽命三锤 sets [0x4d352e] in battle_commands.gd).

##### B3 F14. Choice box portrait (0x42def9) — PORTED, cosmetic [C]
Op 0x12 choice: arg1 (0xFFFF → 0) is the person whose large portrait (sge 301 + face) is drawn in the choice window
(0x42de12; 673 of 680 uses → 管毅). Port: script_host.gd `op_choice` sets `ui.menu.face` (choice_menu.gd) and
numbers the options "1."–"3.".

##### B3 F15. Self-target beep (0x420869) — PORTED, cosmetic [C]
Category 15 (开导 诫谕 战备) on oneself with show_msg: play SE 2 (`0x47467a(2,1)`) then 不能对自己使用。. Port:
battle_input.gd `_do_strategy` (`Audio.se(2)`, then the message).

#### B3.3 Incidental findings (outside the B3 rows)
* docs/rules.md §11 said the dynamic skill list 0x55ee08 is EV[898..927] and that nothing writes it; it is
  EV[3970..3999] and R_00 initialises all to 1024, later scripts assign pids (R_21, R_49, R_50, …). Fixed.
* docs/rules.md called [0x4cf314] "special duel mode" (fixed); it is the "绝招 running" flag (set around 0x4d30a5, after the
  "MP未满" check).
* docs/eex.md op 0x12 arg1 "cancel/default option" is the portrait person (F14). Fixed.
* shapes.json area 11 is `"caster_ring"`, shapes.gd only knew `"caster8"` → area 11 would be target-only; no
  strategy uses area 11 today. Fixed.
* The port's 杜断 (+20 strategy hit next to 杜如晦 185, 0x4d4a60(0xb9,…) in StratHit) was absent from rules.gd
  strat_hit (B4 row); ported since with group 3.

### B4 — Hit rates, damage, healing, regeneration (0x43b000..0x43cfff)
Port files cited: `game/src/core/rules.gd` (R), `game/src/battle/bunit.gd` (BU), `game/src/battle/battle_actions.gd` (BA),
`game/src/battle/battle_stage.gd` (BS). EV[n] = u32 @0x55b000+4n (script int vars). All addresses verified by
disassembly (`disx.py` / `rd_trace.py`) unless marked [G].

**Corrections found while auditing (the doc ones are fixed):**
* The skill table 0x4d3c4c holds **pids** (word table). Owners used below: 0x89 = 杜伏威 【术】金刚 ("完全规避一切策略"),
  0xb9 = 杜如晦 【术】杜断, 0x17 = 魏征 【术】明镜, 0x16 = 徐茂功 【术】秘计, 0x11 = 裴元庆 【招】尽命三锤,
  0x13 = 罗成 【招】回马枪, 0x1 程咬金 = 【招】三板斧 (via [0x55ac04]).
* docs/rules.md §11: the dynamic skill list 0x55ee08[30] is **EV[3970..3999]**, not EV[898..927]. R_00 fills it with
  1024 (no pid) and later scripts assign pids: R_21 EV[3970]=12 鲁明星 (连理), R_17 EV[3972]=2 王君珂 (并蒂),
  R_02 EV[3980]=13 王伯当 (舍命), R_06/R_18/R_28/R_51 EV[3983]=19 罗成 (智将), etc. So the "all zero → 管毅 matches
  every dynamic skill" statement is wrong once R_00 has run. (The port's info window reads Mem 0x55ee08 directly,
  so only the doc is wrong.)
* docs/rules.md §4.2/§6.1 "special duel mode [0x4cf314]" is the **绝招-in-progress flag**: set to 1 around the 绝招
  attack by 0x4d3007 (refuses with 无绝招 / MP未满 unless 0x4d5444(pid) and (effect 58 or MP == MaxMP)), cleared after.
* EV[3183..3190] (bytes 0x55e1bc..) are per-hero 灵物/宿痕 unlock/供养 levels (1..4) set by R_48..R_58; EV[3184]
  (0x55e1c0) gates 管毅's 轩辕神枪 feature, EV[3185] (0x55e1c4) 程咬金's 八卦宣花斧 bonus.

#### B4.1 Site table

| site | original function (what it does) | mod change | feature | status | port evidence or missing spec |
|---|---|---|---|---|---|
| 0x43b504 | 0x43b4b0 HitCheck(att=this, def_unit, kind, s): `chance(kind==1 ? HitRate : StratHitRate)` | jmp 0x4dc924→0x4dca54: after the roll clears flag [0x4dca4f]; if def pid==0, Chebyshev(def,att)≤1, roll failed, byte EV[3184]≥1, chance(EV[2700]·(EV[3184]≥3?2:1)) and 管毅's weapon (person0+0x2e)==23 → flag=1, [0x4dc9c9]=attacker. Consumer 0x4d1e34 (in crit-rate hook 0x405d93→0x4d1d30, B1): attacker.status \|= 0x02 | 管毅 轩辕神枪: an adjacent attacker that misses him is paralysed (麻痹) | PORTED | BA `_crit_rate` → `_xuanyuan` (after a missed roll on the first target). Spec §2.A. Dormant in the shipped game: EV[2700] is never written by any script (initial 0) → chance(0). [C code, G "never written"] |
| 0x43b594 | 0x43b50d HitRate: resolves units, then person ptrs | jmp 0x4d2f90: `call 0x45f670` (relocated); if [0x4cf314] (绝招 in progress): attacker pid≠1 → 100; pid 1 → 100 vs confused, else 50 (+2·weapon_lvl, ×2 again at EV[3185]≥3, if person1 weapon==25 八卦宣花斧 and EV[3185]≥1); then 0x40762d ([0x55ac54] penalty). Not in 绝招 → unchanged | 绝招 hit rates (程咬金 【招】三板斧 50 %, every other 绝招 100 %) | PORTED | R.hit_rate (绝招 branch, then `_shuanglei`); 绝招 in battle_commands.gd `special`. Spec §2.B |
| 0x43b5f3 | HitRate: Agi(attacker) via 0x43f631 | call 0x4d9818 = Agi + 15 %·n for classes 18/19/20 (n = adjacent same-side same-family allies, not 乱/迷) | 组阵 formation bonus (格斗兵 武师/教头/团练 agility) | PORTED | R.hit_rate uses BU.formation_agi. Spec §2.C |
| 0x43b5fe | HitRate: Agi(defender) | call 0x4d9818 (same) | 组阵 formation agility (defender side) | PORTED | as above, §2.C |
| 0x43b79e | 0x43b73f StratHitRate: caster unit ptr from index | call 0x4d3197 (unit_ptr(idx)), code-compaction helper | makes room for inline 金刚/暗杀 checks at 0x43b7b9..0x43b7df | PORTED | behaviour-neutral helper; the inline checks it frees space for are in R.strat_hit 306-309 (pid 0x89 → 0; 暗杀 vs colour≠0 & pid<0xd2 → 0) |
| 0x43b7a6 | StratHitRate: caster person ptr | call 0x4d7ffa (person_of(unit)) helper | same | PORTED | same as above |
| 0x43b7b1 | StratHitRate: target unit ptr | call 0x4d3197 helper | same | PORTED | same |
| 0x43b7e1 | StratHitRate: target person ptr | call 0x4d7ffa helper | same | PORTED | same |
| 0x43b85a | StratHitRate: A = Int(caster) + Morale | call 0x4e2171 = Int with 能力校准 (effect 54 → max(Atk, Int)) | 能力校准 in strategy hit | PORTED | R.strat_hit 316 uses BU.spirit() 211-215 (effect 54 → max) |
| 0x43b871 | StratHitRate: B = Int(target) + Morale | call 0x4e2171 | 能力校准 | PORTED | same |
| 0x43bae4 | StratHitRate: after effect 52 (+val) | jmp 0x4d4abc: if 0x4d4a60(185, U) → h = min(h+20, 100) (U = [ebp+0xc]: the target in the real roll/AI, the caster in the UI forecast) | 杜如晦 【术】杜断 (+20 % strategy hit) | PORTED | R.strat_hit (`Skills.beside(185, …)`: the target, the caster with `forecast` from battle_input.gd). Spec §2.D |
| 0x43bb16 | StratHitRate: after effect 54 (−val) | jmp 0x4d4ae4: target pid 0x89 → h = 0 | 杜伏威 【术】金刚 (strategy immunity) | PORTED | redundant with the inline check at 0x43b7b9; R.strat_hit 306 returns 0 for pid 0x89 |
| 0x43bccb | 0x43bc4b CalcDamage: A = Atk(att)·tA/10 | call 0x4d98eb = (effect 54 ? max(Atk,Int) : Atk) + 15 %·n for classes 46/47 | 能力校准 + 组阵 attack (狄骑, 战车) | PORTED | R.calc_damage uses BU.formation_atk (BU.atk has 能力校准). Spec §2.C |
| 0x43bceb | CalcDamage: D = Def(def)·tD/10 | jmp 0x4d3501: D = Def + 15 %·n for classes 39/46 (0x4d98a2); if 绝招 in progress and attacker pid == 17 → D = 0 | 组阵 defence (燕云骑, 狄骑) + 裴元庆 【招】尽命三锤 ignores defence | PORTED | R.calc_damage: BU.formation_def, then D = 0 for pid 17 in a 绝招. Specs §2.C, §2.B |
| 0x43bd2c | CalcDamage: after the physical hit check passes (real) / always (preview) | jmp 0x4d3389: if real → 0x4d0cf5: u8 0x55a500[ctx 0x4927f0 target list[[0x55a6cc]]]++ (sat 0xff); then 0x4d7e77: effect 85 固定伤害 → dmg = effect_value(85), jump to the HP cap (skips everything else); else level+35 path | 怀恨攻击 hit counter (天玉玲珑铠) + 固定伤害 (墨阳剑) | PORTED | R.calc_damage: `_count_hit` (real calls, Mem 0x55a500 at entry [0x55a6cc]), then effect 85. Spec §2.E |
| 0x43bdac | CalcDamage: class matchup switch | DATA: jump table moved to 0x4d2140[att_family] (mod handlers) | 兵种相克 table | PORTED | R.class_matchup 120-148 + effect 61 at R 168; all 27 entries re-verified against 0x4d21c5..0x4d23a2 (families 4/5/15/23 route through 0x43bddf effect-61; 12 vs 16/17 ×1) |
| 0x43bee8 | CalcDamage: after the effect 45/88 bonus | jmp 0x4d8d65: if has_effect(89) → 0x4d8d95(dmg, att, def): if path length [0x4cfbfc]≠0, d = max(\|dx\|,\|dy\|) att.pos vs [0x4cfc00]; d× `dmg=dmg*110/100` | 冲锋攻击 (板角墨麒麟) | PORTED | R.calc_damage reads the recorded move (BattleStage.PATH_LEN / PATH = [0x4cfbfc] / 0x4cfc00) and skips it when none was recorded, as the original does |
| 0x43bef7 | CalcDamage mode 0 (primary, not counter) | call 0x4d0d2e(att): effect 87 怀恨攻击 → 10 + 0x55a500[att.slot], else 10 | 怀恨攻击 multiplier source | PORTED | R.calc_damage reads Mem 0x55a500 (BU.GRUDGE) for the attacker's slot. Spec §2.E |
| 0x43befc | CalcDamage mode 0 | jmp 0x4d0e20: dmg = dmg·mult/10 | 怀恨攻击 apply | PORTED | R.calc_damage `dmg * (10 + g) / 10` |
| 0x43bf10 | CalcDamage mode ≠ 0 (counter / secondary target) | jmp 0x4d93c0: (mode≠2 ? ×3>>2) ; max 1 ; mode≠1 → sar 1, max 1 | counter ×3/4, splash/penetrate ×1/2 | PORTED | R.calc_damage; BA `strikes` passes mode +2 for halved secondary targets (`_halved`) |
| 0x43bf90 | CalcDamage return (all exits incl. miss = 0, preview) | jmp 0x4dc9e0: if att pid == EV[3980] (舍命, 0x4dc761(10)) and att HP < MaxHP·60/100 → min(dmg·130/100, def HP); else if att pid == 19 → min(Int'(att)·15/100 + dmg, def HP) | 王伯当 【术】舍命 (+30 % below 60 % HP) and 罗成 【术】智将 (+15 % of 精神) | PORTED | R.damage_post, at the end of R.calc_damage and on a miss in BA `strikes`. Spec §2.F |
| 0x43c090 | 0x43bfaa StratDamage: I = Int(caster) | call 0x4e2171 | 能力校准 | PORTED | R.strat_damage 341 caster.spirit() |
| 0x43c09b | StratDamage: J = Int(target) | call 0x4e2171 | 能力校准 | PORTED | R.strat_damage 342 |
| 0x43c5ad | 0x43c548 HealAmount 医疗/补给: Int(caster)/8+60 | call 0x4e2171 | 能力校准 in heals | PORTED | R.heal_amount 380 |
| 0x43c60d | HealAmount 痊愈/犒劳/救护/白虎: Int(caster)/2+100 | call 0x4e2171 | 能力校准 | PORTED | R.heal_amount 382 |
| 0x43c74f | 0x43c738 recovery chance r(unit, 1) (called by StatusRecovery and BuffDecay for every on-map unit at its side's phase start) | jmp 0x4d1e21: dword [0x55ee00] = dword [0x55ee04] (snapshot of the two 并蒂 hit counters), then original | 王君珂 【术】并蒂 (counter snapshot) | PORTED | BS._phase_start_effects (per unit, after recovery and decay). Spec §2.G |
| 0x43c80a | 0x43c7d6 StatusRecovery(unit) | call 0x4d4a60(23, unit): if the unit has a status and 魏征 is adjacent on its side → 0x45aa5c(pid, 6, 0xfe, show) = status &= 0x01 (all ailments cured, with the on-map effect) and skip the normal recovery | 魏征 【术】明镜 | PORTED | BS._status_recovery (`Skills.beside(23, u)` → `change_unit(u, 6, 0xfe)`). Spec §2.H |
| 0x43cefe | 0x43cddd Regen: MP part | jmp 0x4d4af6: (dead `cmp [0x55ac48]` + unconditional jmp over a 波若 "+10 MP when HP ≤ MaxHP/3") → mp += 0x4d7eb1(unit): effect 82 → drain effect_value(82) MP from each enemy in the 8 cells around | effect 82 MP-drain aura (六军镜·阴阳) | PORTED | BS._regen → `_drain_mp`. Inert with shipped data: the only effect-82 item (85 六军镜·阴阳) has value 0. Spec §2.I |
| 0x43cf0c | Regen: MP cap `if MP+mp > MaxMP: mp = MaxMP−MP` | jmp 0x4d7ee7: the relocated `esi = MP + mp; MaxMP` instructions (room for 0x43cefe) | plumbing (MP regen cap) | PORTED | BS._regen 731 `mini(mp, max_mp − mp)` |
| 0x43cf75 | Regen, player-coloured units (0x43ff54: colour 0), after effect 64 | jmp 0x4d1dff: dword [0x55ee04] = 0 (reset both 并蒂 hit counters), then original effect 22 | 王君珂 【术】并蒂 (counter reset) | PORTED | BS._regen (colour-0 units). Spec §2.G |

Status counts: PORTED 30, PARTIAL 0, MISSING 0, N/A 0, FALSE 0 (30 rows).

**Patches inside 0x43b000..0x43cfff that are not in the inventory** (noticed, not fully analysed):
* 0x43b72f `jmp 0x40762a` (mod code in .text slack, HitRate tail): `if [0x55ac54]==1: h = h>26 ? h−26 : 1`. [0x55ac54] is
  双雷引's flag (group 3 corrections), and the cave is reached only from the effect-55 branch and the 绝招 rates. Ported:
  R.hit_rate → `_shuanglei`.
* 0x43bea6 `cmp [0x55ac2c],1` in the effect-45 branch: adds `dmg*0/100` → no-op.
* 0x43c7ec `call 0x401118` (StatusRecovery entry → the per-unit phase-start skill routine analysed in B1).
* 0x43ce38..0x43ce43: 12 NOP bytes in Regen before the terrain heal (original instructions unknown).
* Original-code discrepancy seen while reading 0x43b73f (not a mod hook): 狂澜 (9) vs the target in slot 0 or the army
  leader sets h = 0 at 0x43ba3a and then **continues** through the modifiers (0x43ba8e: effect 52 +val, 杜断 +20,
  effects 54/55), so it can end above 0. (Leader test is by pid: 0x45f670(target) == 0x406630(0x492f90).) Ported:
  R.strat_hit sets h = 0 for slot 0 or the commander (BattleStage.BOSS, Mem 0x496c96) and goes on. The per-strategy factor groups in R (STRAT_HIT_*) match table 0x43bc07/0x43bb6b exactly.
* Engine quirk (no port action): 0x4e2171 ends with `ret 4` but its callers push nothing, so each call shifts the
  caller's esp by 4; callers with `push esi … pop esi` (0x43b73f, 0x43c548) restore a wrong esi. No visible effect found.

#### B4.2 Missing / partial features (implementable specs)

##### B4 A. 管毅 轩辕神枪 — paralyse an adjacent attacker that misses him [C code; dormant in practice] — PORTED
Sites 0x43b504 (set), consumer 0x405d93→0x4d1d30→0x4d1e34 (B1).
* In every hit check 0x43b4b0 (physical and strategy), after the hit roll: flag = 0; then, in this order:
  def.pid == 0 (管毅) → |def.x−att.x| ≤ 1 and |def.y−att.y| ≤ 1 (0x4dc97d, includes diagonals) → roll failed →
  byte EV[3184] (0x55e1c0) ≥ 1 → `chance(EV[2700] (u32 0x55da30) × (EV[3184] ≥ 3 ? 2 : 1))` → person 0 weapon == 23
  (轩辕神枪) → flag = 1, remember attacker.
* The flag is consumed only in the crit-rate routine, which runs for the **primary** target of each physical strike
  (also on a miss, since the target is alive) and not during a 绝招: `if flag: attacker.status |= 0x02` (麻痹). No
  message. Strategy misses set the flag but the next hit check clears it, so strategies never paralyse.
* Port: BA `_crit_rate` → `_xuanyuan`, after a failed hit roll on the primary target.
* Practical effect today: EV[2700] is never written by any script (searched direct writes, data_transfer, pointer
  immediates), so the chance is 0 and the feature never fires. Ported for fidelity.

##### B4 B. 绝招 parts in the hit/damage formulas [C] — PORTED (R.hit_rate, R.calc_damage; 绝招 in battle_commands.gd `special`)
Flag [0x4cf314] = 1 only while 0x4d3007 runs the 绝招 attack (0x4d30a5).
* HitRate during 绝招 (0x43b594 → 0x4d2f90): attacker pid ≠ 1 → 100. Attacker pid 1 (程咬金, 【招】三板斧
  "每次命中率50%…对处于混乱状态的目标100%命中"): target confused (status & 8) → 100; else 50 + bonus, bonus =
  (person1.weapon == 25 八卦宣花斧 and byte EV[3185] ≥ 1) ? weapon_level × 2 × (EV[3185] ≥ 3 ? 2 : 1) : 0. Effects
  39/53/55/56 are skipped in this mode; the [0x55ac54]==1 penalty (−26, min 1) still applies.
* Defence during 绝招 (0x43bceb → 0x4d3501): attacker pid 17 (裴元庆 【招】尽命三锤 "无视对方防御") → D = 0
  (so dmg = level + 35 + A/2 before matchup etc.). The formation Def bonus (C) is computed first and discarded.
* Crit-rate is not computed during 绝招 (0x4d34c9 → 0x4d34df), see B1.

##### B4 C. 组阵 formation bonuses (Atk / Def / Agi) [C] — PORTED (BU.formation_atk / formation_def / formation_agi)
Getters 0x4d98eb (Atk), 0x4d98a2 (Def), 0x4d9818 (Agi); counter 0x4d995d/0x4d97a9.
* n(U) = number of the 8 cells around U (x±1, y±1, orthogonal and diagonal) holding a unit V (occupancy map, i.e. on
  the map) with side(V) == side(U) (slot < 35 vs ≥ 35, so player+friend count together), family(V) == family(U)
  (class→family), and V.status has neither 0x08 混乱 nor 0x40 迷失.
* bonus(v) = v + v·15·n/100 (u32, integer; no 9999 re-cap after it).
* Atk: base = effect 54 ? max(Atk, Int) : Atk (buffed); class ∈ {46 狄骑, 47 战车} → bonus. Used by CalcDamage (A).
* Def: base = Def (buffed); class ∈ {39 燕云骑, 46 狄骑} → bonus. Used by CalcDamage (D of the defender).
* Agi: base = Agi (buffed); class ∈ {18 武师, 19 教头, 20 团练} → bonus. Used by the physical HitRate for both
  units (0x43b5f3/0x43b5fe) and by the double-attack rate 0x405ce6 (0x405cf2/0x405d0a, B1).
* Class texts confirm: 燕云骑 "组阵作战时，防御力将会增加", 狄骑 "攻击力和防御力都将增加", 战车 "攻击力…增加".
* Port: BUnit.formation_count, used through the formation_* getters in Rules.calc_damage (A/D) and Rules.hit_rate /
  double_rate (agi) only; BUnit.atk()/def()/agi() stay plain (the info window, strategies and AI value functions use the
  plain getters in the original).

##### B4 D. 杜如晦 【术】杜断 — +20 strategy hit rate [C] — PORTED (R.strat_hit)
Site 0x43bae4 → 0x4d4abc, check 0x4d4a60(185, U).
* In StratHitRate, only for strategies that go through the curve (not the "always 100" set: 暗杀, 八阵, heals, cures,
  buffs, 战备, 白虎), after the ×factor, the 暗算 ×3/2 and effect 52: if cond(U) → h = min(h + 20, 100). Then
  effect 54 (−), 金刚 → 0, effect 55 (−), cap 100.
* cond(U): 杜如晦's (pid 185) unit exists, state 2, same side group as U (slot<35 test), and test_adjacent(U.pid,
  185, loose) — both alive on the map and 杜如晦 in one of the 8 cells around U.
* U is [ebp+0xc] of 0x43b73f: the **target** in the real roll (0x43b4b0 → flag 0) and in AI evaluation (0x439a3f,
  0x439e4e, flag 0); the **caster** in the hover forecast (0x4404bd → 0x4407e3/0x440899, flag 1). So the skill text
  ("相邻我部使用策略时命中率提高20%") matches only the forecast; the actual roll favours casters whose target
  stands next to an allied 杜如晦. Port: as the original (the target for the roll and the AI, the caster with
  `forecast` = true from the battle_input.gd forecast).

##### B4 E. 怀恨攻击 (天玉玲珑铠, effect 87) — hit counter [C] — PORTED (R.calc_damage, `_count_hit`)
Sites 0x43bd2c (increment), 0x43bef7/0x43befc (use); clears at 0x44e914/0x44ee15 (other batch) and op 0x44.
* Counter = u8 Mem 0x55a500[slot] (BU.GRUDGE; zeroed in BS.op_battle_init).
* Increment: in CalcDamage with real=1, after the hit check succeeds (before damage, also for 固定伤害 attackers,
  counterattacks and every strike): `c = 0x55a500[target_slot]; if c != 0xff: c += 1`. Exact target: entry
  [0x55a6cc] of the combat object's target list (0x4927f0+0x10), where [0x55a6cc] is the index of the previously
  processed target (0x406173) — equal to the current target for single-target attacks.
* Clear: at the enemy phase start slots 0..34 are cleared (0x4d0d0e(0x23, 0)); at the player phase start slots
  35..114 (0x4d0d0e(0x73, 0x23)). So a unit's count = hits it took since the start of the last enemy phase (for
  player units), i.e. the enemy turn's hits boost its own next turn ("在决定还击时一次性爆发").
* Use (mode 0 = primary target, not a counter): mult = has_effect(87) ? 10 + counter[att.slot] : 10;
  dmg = dmg·mult/10. Port: R.calc_damage (`_count_hit` on real calls, the use in mode 0); the clears in
  BS._phase_start_effects.

##### B4 F. 王伯当 【术】舍命 and 罗成 【术】智将 — CalcDamage post-processing 0x4dc9e0 [C] — PORTED (R.damage_post)
Applied to every CalcDamage result (after `min(dmg, target HP)`; also previews, counters, secondary targets, and the
0 returned for a failed hit check), before the caller's crit ×3/2 and effect 57:
1. If 0x4dc761(10): attacker pid == EV[3980] (u32 0x55ee30; R_02 sets 13 王伯当) and attacker HP (low word, signed)
   < MaxHP·60/100 → dmg = min(dmg·130/100, target HP); done.
2. Else if attacker pid == 19 (罗成, hard-coded, independent of EV[3983]) → dmg = min(Int'·15/100 + dmg, target HP),
   Int' = 0x4e2171 = buffed 精神 (effect 54 → max(攻击, 精神)).
3. Else unchanged.
Consequence of the order: a 罗成 attack whose hit roll fails still returns Int'·15/100 (> 0), so it is shown and
applied as a small hit (and can crit). Port: R.damage_post at the end of R.calc_damage, and on a miss in BA `strikes`;
the 舍命 pid is `Skills.dyn(10)` (Mem 0x55ee08 + 4·10).

##### B4 G. 王君珂 【术】并蒂 — counter bookkeeping [C for these sites; consumer in another batch] — PORTED
Skill text: "攻击力受管毅在敌方回合遭物理攻击的次数影响而有所加成…". Pid = EV[3972] (u32 0x55ee10; R_17 sets 2).
* Count (0x4d1d30, B1, in the crit-rate routine of each primary-target strike): if the units of EV[3972] and of pid 0
  are both on the map (state 2) and their Manhattan distance ≤ 0x99 (always): defender == 王君珂's unit → byte
  [0x55ee04]++; else defender == 管毅's unit → byte [0x55ee06]++.
* Snapshot (0x43c74f): every call of 0x43c738(1) — i.e. StatusRecovery and BuffDecay of each on-map unit of the side
  whose phase starts — copies dword [0x55ee04] → [0x55ee00] (so [0x55ee02] = 管毅's count).
* Reset (0x43cf75): Regen of each player-coloured (colour 0) unit at phase start sets dword [0x55ee04] = 0 (after the
  snapshot, since Regen runs after the StatusRecovery/BuffDecay loop). Also reset at 0x4dbd06 (other batch).
* Use (0x4dbd2c, other batch): for person == EV[3972] the stat being computed is ×(100 + 8·[0x55ee02])/100.
* Port: Mem 0x55ee00..07; count BA `_bingdi_count`, snapshot BS._phase_start_effects, reset BS._regen, use `Person.stat`.

##### B4 H. 魏征 【术】明镜 — cure adjacent allies each turn [C] — PORTED (BS._status_recovery)
Site 0x43c80a. In StatusRecovery(U) for an on-map unit, after the B1 per-unit routine 0x401118: if U.status != 0 and
魏征 (pid 23)'s unit is on the map, alive, on U's side group and in one of the 8 cells around U → status &= 0x01
(clears 麻 穷 乱 毒 怯 迷), shown with the unit-change effect (0x45aa5c show=1 → 0x43e69f), and the normal 胆魄
recovery rolls are skipped. 魏征 does not cure himself (not adjacent to himself). Port: at the top of
BS._status_recovery (`Skills.beside(23, u)`).

##### B4 I. Effect 82 MP-drain aura in Regen [C; inert with shipped data] — PORTED (BS._regen → `_drain_mp`)
Site 0x43cefe → 0x4d7eb1/0x4d7efa. If U has effect 82: v = effect_value(82); for each cell of the 3×3 square around U
(excluding U) holding an on-map unit E of the opposite side group: take = min(E.MP, v); E.MP −= take (no display);
total += take. U's MP regen += total (then capped at MaxMP−MP with the effect-19 amount). The only effect-82 item is
85 六军镜·阴阳 (再移动) with value 0, so nothing is drained in the shipped game. The 波若 ([0x55ac48]) branch at
0x4d4b03 (+10 MP when HP·3 ≤ MaxHP) is unreachable (unconditional jmp at 0x4d4b01).

### B5 — Units, movement, turns, command menu (0x43d000..0x45ffff)
Evidence: `wg2025/wagan.wa` disassembly (jmp chains followed until the return to .text) and Ghidra decompiles,
including a full trace of the 绝招 dispatcher. Port = `game/src`. Skill owners as in [Skill owners](#skill-owners).
Tags: [C] confirmed from code, [G] guess.

Status counts: **PORTED 36 · PARTIAL 1 · MISSING 0 · N/A 13 · FALSE 2** (52 rows; rechecked against the port
2026-10-12, before that PORTED 4 · PARTIAL 4 · MISSING 27 · N/A 15).

Corrections found on the way:
* 0x45bd35 → 0x4d034d does not map the clicked button to a command (an earlier note assumed so). 0x45bd05 is a vtable
  method (0x4867e8) that paints the buttons (0x471981 with a Cmdicon index). The hook gives the new buttons their
  icons: 绝招 and 围攻 get icon 0 (the sword, Cmdicon 100), 交给 gets icon 4 (Cmdicon 104), 策略 gets 1. The click
  mapping is 0x45bc55 → 0x4d029b (交给 → result 6, 围攻 → 7). 绝招 → result 5 comes from the patched jump-table
  entry 0x45bcc8 = 0x4d2800 (a DATA patch outside this batch). Results: 1 攻击, 2 策略, 3 道具, 4 待命, 5 绝招,
  6 交给, 7 围攻.
* docs/rules.md §4.2 and §6.1 called [0x4cf314] "special duel mode" (fixed). It is the "绝招 running" flag (set
  only by 0x4d3007).
* [0x4ce004] is the "saving allowed" flag. The menu's 存储进度 says 目前不可存盘。 when it is 0 (0x4d009f).
* EV[10] (0x55b028) is a script-visible "a unit's HP reached 0 during this action" flag (see feature F9).
* The per-character "rank" variables EV[3183] (尉迟恭), EV[3185] (程咬金) and EV[3190] (单雄信) are set to 1..4 by
  R_19 (`int_var_op 2 318x 2 0 n`). Dyn skill list: EV[3972] = 2 (王君珂 → 并蒂), EV[3974] = 3 (尉迟恭 → 夺面鞭),
  EV[3981] = 8 (秦琼 → 回旋杀手锏).

#### B5.1 Site table

| site | original function (what it does) | mod change | feature | status | port evidence / missing spec |
|---|---|---|---|---|---|
| 0x43d53e | 0x43d538 player move UI (show move range, wait for the destination click, walk) — prologue | jmp 0x4d2865: `[0x4cf310] = unit.pid` (the unit being commanded), then the replaced `mov [ebp-0x24],ecx` | infrastructure of 绝招/交给/围攻 enable tests (0x4d5444/0x4d9cc9/0x4d7196) and of the 锻造/波若 path skills (0x4d90bf) | PORTED | battle_input.gd `select_unit` / `_move_again` write [0x4cf310] (`BattleStage.CMD_PID`); read by battle_commands.gd `special_enabled` / `give_enabled` and battle_actions.gd `end_action`. [C] |
| 0x43d567 | same: "may this unit be commanded?" test | call 0x4d6268 (`unit.slot < 0x73`) replaces `call 0x406710` (`slot < 35`). Any unit with AI code 7 and no flag 0x80 (incl. enemy slots 35..114) becomes commandable. Others get view-only state 1, which behaves like the old state 0 | "enemy-slot units with code 7 are player-controlled" | PORTED (latent) | battle_input.gd:91 (`player_phase`) and :157 (`select_unit`) take code-7 units of any slot < 115. No shipped script gives code 7 to a slot ≥ 35 (checked every `data_transfer … 32` with value 7). [C] |
| 0x43d5f3 | same: `MovePoints(unit)` before the flood fill | jmp 0x4dc7e1: `[0x4dc7dd] = unit`, `[0x4dc7f1] = 0`, then MovePoints | 并蒂 (王君珂, dyn slot 2) always crits in 管毅's 围攻 | PORTED | Read by the crit-rate hook 0x405daa → 0x4dc7fd: if not a counterattack ([0x492e04] ≠ 1), the attacker's person is dyn slot 2 (0x4dc761(p,2)) and the commanded unit [0x4dc7dd] is pid 0 (管毅), then crit rate = 100 and [0x4dc7f1]++. Port: battle_input.gd `select_unit` (`st.range_unit`), battle_actions.gd `_crit_rate`. See F2. [C] |
| 0x43da45 | same: walk loop (`while pos != dest`, step along the path) | call 0x4d8f1f: `path[i] = pos` (0x4cfc00 + 2i), then the original compare 0x43b420. The count goes to [0x4cfbfc] at 0x409120 and is reset at 0x43e21c | recording of the player's move path, used by 冲锋 (eff. 89), 回马枪, 锻造, 波若 | PORTED | battle_input.gd `_walk` → battle_stage.gd `record_path`: path[0] = start … path[n] = end, n = steps (a byte at [0x4cfbfc]), path[n+1] = 0xffff; cleared after each command (battle_input.gd `select_unit`, 0x43e21c). Read by 冲锋 (rules.gd), 回马枪 (`move_path`) and 锻造/波若 (battle_actions.gd `end_action`). [C] |
| 0x43db51 | 0x43dada attack command (fragment 0x43db4e: after an attack, 引导攻击 eff. 46 re-attack if the target died) | call 0x4d3197 = `&units[idx]` (code compaction) | — | N/A | No behaviour change. Side note: the original's 引导攻击 for player-commanded attacks (not a mod feature) is in battle_input.gd `_do_attack` (with battle_actions.gd `guided_target`). [C] |
| 0x43dbf2 | 0x43dada attack command, end | call 0x4d2a47 | 连续攻击 (effect 90, 六军镜·形势) | PORTED | battle_input.gd `_do_attack`. See F5. [C] |
| 0x43dc08 | 0x43dada attack command exit | jmp 0x4d0d62: dword [0x4d0d5d] = 0, then end action (6) | reset of an accumulator read by 0x4d7fc5 | N/A | The only writers of [0x4d0d5d] store 0 (0x406b51, 0x4d0d64; byte-xref scan), so it is always 0 and has no visible effect. [C] |
| 0x43dc7d | 0x43dc21 strategy command loop | data ref 0x4d0d61: on cancel, if [0x4d0d61] == 1 → set it to 0 and end the action (6) | 连续策略 (effect 83) | PORTED | battle_input.gd `_do_strategy` (a cancel while [0x4d0d61] == 1 clears it and ends the action). See F5. [C] |
| 0x43dcb5 | 0x43dc99 cast strategy (player loop and AIAct) | call 0x4d0d71 decides whether the action ends after a successful cast | 连续策略 (effect 83) | PORTED | battle_actions.gd `second_cast`, called by battle_input.gd `_do_strategy` and battle_ai.gd `act`; ×2 cost in `strategy_mp`. See F5. [C] |
| 0x43e16b | 0x43dde3 unit command flow: after the command menu returned a command | call 0x4d67b8(0): EV[10] = 0 before the command runs | EV[10] "HP reached 0 during this action" flag | PORTED | battle_input.gd `command_menu` (`Mem.set_ev(10, 0)`). See F9. [C] |
| 0x43e17b | 0x43dde3: `switch(result−1)` over the 4 original commands | jmp 0x4d2819: index 4 → 0x4d3007 绝招, 5 → 0x4d287e 交给, 6 → 0x4d6d00 围攻; else the original table 0x43e263 | 绝招 / 交给 / 围攻 dispatch | PORTED | battle_input.gd `command_menu` → battle_commands.gd `special` / `give_command` / `siege_command`. See F1–F4. [C] |
| 0x43e1b9 | 0x43dde3 after any executed command | call 0x4d27a0 (eax = unit) | 再移动 (effect 82, 六军镜·阴阳) | PORTED | battle_input.gd `_move_again` (skipped for a unit that fell in its own attack; the original would let it move). See F6. [C] |
| 0x43e1be | 0x43dde3 exit (executed or cancelled command) | jmp 0x4dcb09 | kill rewards: 辰屑 drops and 尉迟恭's MP on kills | PORTED | battle_actions.gd `kill_rewards`, after each command and on a cancel (battle_input.gd `command_menu`). See F8. [C] |
| 0x43f81f | 0x43f7cf MoveCost(terrain): after `has_effect(34 恶移麻痹/虎类豹)` | jmp 0x4db478: effect 34 → 1 (original). Mod: else if EV byte [0x55e1d8] (EV[3190], 单雄信's rank) ≥ 3 and accessory (+0x34) == 47 (板角墨麒麟) and pid == 4 (单雄信) → 1 | 单雄信 + 板角墨麒麟: every passable terrain costs 1 | PORTED | rules.gd `move_cost` (both rules). See F10. [C] |
| 0x43f830 | 0x43f7cf: `if c > 1 and has_effect(86 辅助地形移动)` | jmp 0x4dc035: also true for pid 25 (张公瑾) with class 41 (神羿骑) → `c −= 1` | 飞将军 (张公瑾): terrain-assisted movement | PORTED | rules.gd `move_cost`: `c − 1` when c > 1 for effect 86 and for pid 25 with class 41. See F10. [C] |
| 0x43f83f | 0x43f7cf return | jmp 0x4d39e1: pid 6 (丁天庆) on terrain 9 浅滩 / 10 沼泽 / 13 大河 → 1 | 水军 (丁天庆) | PORTED | rules.gd `move_cost`. See F10. [C] |
| 0x43f890 | 0x43f84d TerrainEffect(unit) | call 0x4d39a3 = family record pointer (compaction) | — | N/A | No behaviour change. [C] |
| 0x43f8a3 | 0x43f84d after the table lookup | jmp 0x4d39b9: pid 6 on terrain 9/10/13 → 11 (110 %). Then effect 86 max(·,10) (0x407d4d) and 0xff → 0 | 水军 (丁天庆) terrain effect | PORTED | rules.gd `terrain_effect`. See F10. [C] |
| 0x43f8d1 | 0x43f8be AttackRangeCode(unit) | jmp 0x4d3417: 怯 (0x20) → 11; when not in a 绝招: pid 0xcc (张善相) → 12, pid 25 with class 41 → 4; during a 绝招: pid 8 → 6, pids 5/26/14/19 → 0; else the original effect 42 / effect 21 / class path | 枪母子 (张善相), 飞将军 range (张公瑾), 绝招 ranges | PORTED | battle_actions.gd `attack_range_code`: 怯 → 11, then 张善相 → 12 and 张公瑾 → 4 outside a 绝招, the 绝招 ranges inside one, then effect 42 / effect 21 / class. [C] |
| 0x4412c9 | 0x440e89 target-preview HUD line, kind 4 (item) | jmp 0x4d23a8: for item types > 0x51 take the effect name from 0x410f50[type−0x51]. Otherwise the original table 0x48bc08 | name of a mod accessory effect in the preview while picking a 交给 receiver | PORTED | battle_hud.gd `forecast_for` (kind 4: the type's name from 0x48bc08, above 0x51 from 0x410f50); the pickers set the forecast (battle_input.gd `pick_unit` / `show_forecast`, 交给 in battle_commands.gd `give`). The whole forecast window 0x4404bd is ported with it: rules.md §13.7. [C] |
| 0x441888 | 0x441744 RemoveUnit common tail | call 0x4dbff3: clear the leaving unit's 暗杀 mark (0x569f00[i] = 0, 0x569f73[i] = 0xff) and cancel every mark it placed (0x569f73[k] == i → 0xff) | 暗杀 delayed defeat (mod) | PORTED | battle_stage.gd `remove_unit` (mod 0x4dbff3 comment). The mark is set in battle_actions.gd `_apply_strategy` and counted down in battle_stage.gd `_assassination_countdown`. See F11. [C] |
| 0x44272c | 0x442718 SetActionFlags(unit, f) | call 0x4d90bf when f == 6 (action finished) | 锻造 (齐国远) / 波若 (罗士信) path skills | PORTED | battle_actions.gd `end_action` (`_boruo`, `_duanzao`). See F7. [C] |
| 0x443a44 | 0x443a0d duel portrait draw | jmp 0x4d4e8c: while [0x4cf608], load sge 2301+face (80×80) for side 0/1 at the original position −8/−10 px | duel portraits (mod) | PORTED | duel_layer.gd:13 (16,24)/(526,280) and :768-772 draw the 80×80 small face in colour (duel.md §3). [C] |
| 0x448a9f | 0x4486f4 duel setup | jmp 0x4d420c: [0x4cf608] = 1 (portrait overlay on) | duel portraits | PORTED | duel_layer.gd:221/228 `show_portrait`. [C] |
| 0x44c257 | 0x44c1cb map header loader (Yun.wa) | — | — | FALSE | Byte 0xe9 is the disp8 of `mov [ebp-0x17], al` at 0x44c255. Linear sweep artefact. [C] |
| 0x44ccc8 | 0x44cc85 battle unit creation | call 0x4d67b8(0): EV[10] = 0 at battle start | EV[10] flag | PORTED | battle_stage.gd `create_battlefield`. See F9. [C] |
| 0x44ce10 | 0x44cc85 (generated units: Promote) | call 0x4d3197 (compaction; frees bytes for the adjacent loop that clears 0x569f00[0..114]) | — | N/A | No behaviour change. The port clears 0x569f00 at battle start (battle_stage.gd `create_battlefield`). [C] |
| 0x44ce2d | 0x44cc85 (Equip weapon) | call 0x4d3197 (compaction) | — | N/A | Same as above. [C] |
| 0x44ce68 | 0x44cc85 (Equip armour) | call 0x4d3197 (compaction) | — | N/A | Same as above. [C] |
| 0x44da82 | 0x44da7a ActionOrder | — | — | FALSE | Byte 0xe8 is the disp8 of `mov [ebp-0x18], ecx` at 0x44da80. Linear sweep artefact. [C] |
| 0x44dff1 | 0x44df61 phase-start poison | jmp 0x4e0077: divisor 10 for enemies (slot ≥ 35) with pid < 0xd2, else 5. Then HP −= max(MaxHP/div, 1), leaving at least 1 HP | poison damage | PORTED | battle_stage.gd `_phase_start_effects`. [C] |
| 0x44e13d | 0x44e0d9 player phase: "any commandable unit?" loop | call 0x4d3197 (compaction) | — | N/A | [C] |
| 0x44e14e | same | call 0x4d3197 (compaction) | — | N/A | [C] |
| 0x44e165 | same | call 0x4d3197 (compaction) | — | N/A | [C] |
| 0x44e1c9 | 0x44e0d9 player phase, after the input loop (also when there was nothing to command) | `if [0x4ce004]: call 0x4d4f80`: silent save (0x41b16a with 0x41b1ac/0x41b4dd patched to skip the 进度No.%2d: …可以保存吗？ prompt and the done message) into slot [0x4f1000], cycling 0,1,2,3,4 (starts at 0 each run) | autosave at every player-phase end | PARTIAL | The port's own autosave (game.gd:437 `AUTO_SLOT`, `user://autosave.json`, written at checkpoints and on going to the background) replaces it. It never overwrites the numbered slots 0..4: kept out on purpose, see [Deliberate differences](#deliberate-differences-port-design-keep-unless-asked). [C] |
| 0x44e8fd | 0x44e851 enemy phase start: StatusRecovery/BuffDecay loop | call 0x4d3197 (compaction) | — | N/A | [C] |
| 0x44e914 | 0x44e851 enemy phase start | call 0x4d0d0e(hi 0x23, lo 0): clear 0x55a500[0..34] | 怀恨攻击 (eff. 87) hit counters of player-side units reset at the enemy phase start | PORTED | battle_stage.gd `_phase_start_effects` clears slots 0..34 of Mem 0x55a500 (`BUnit.GRUDGE`). See F12. [C] |
| 0x44edfe | 0x44ed93 player phase start loop | call 0x4d3197 (compaction) | — | N/A | [C] |
| 0x44ee15 | 0x44ed93 player phase start | call 0x4d0d0e(0x73, 0x23): clear 0x55a500[35..114] | 怀恨攻击 counters of enemy units | PORTED | battle_stage.gd `_phase_start_effects` (slots 35..114). See F12. [C] |
| 0x45019a | 0x450036 EXP popup (bars next to the unit) — weapon part | jmp 0x4d3d89: reads the weapon exp (0x409680) and id, and caps the *displayed* gain so exp+gain ≤ 100 (normal) / 250 (treasure, 0x40c76e) | display only | N/A | The port has no EXP popup bars (floating "经验 +N" in battle_actions.gd `gain_exp`). The real weapon exp is applied elsewhere. [C] |
| 0x4501ed | same — armour part | jmp 0x4d3da7: the same for the armour | display only | N/A | Same as above. [C] |
| 0x4525d4 | 0x45218f map redraw | call 0x4d1c10 (replaces ~17 bytes, now NOPs): when the cursor cell [0x4b4248] changed, print "(%2d:%2d) %s" = cursor x:y and terrain name (0x48bdb0[terrain]) in the top bar (text colour 0x12, box 0x47dbc3(0xfd,0,0x8e,0x10,2) [G: position]) | cursor coordinate + terrain readout | PORTED | battle_hud.gd `_draw_cursor_text`: "(%2d:%2d) terrain" for the hovered cell. [C] |
| 0x452737 | 0x45218f map redraw | jmp 0x4d4222: [0x4cf608] = 0, DeleteObject both portrait bitmaps | duel portraits off at duel close | PORTED | duel_layer.gd:212 `show_portrait = [false,false]`. [C] |
| 0x4559ba | 0x45576d terrain info popup (left click on an empty cell in the player phase) | jmp 0x4e0000: terrain id > 29 → 0 before indexing the name table 0x48bdb0 | bounds clamp | PORTED | battle_hud.gd `terrain_popup` (`t > 29 → 0`), opened by battle_input.gd `player_phase` on an empty-cell click. [C] |
| 0x45bb2b | 0x45badb command dialog 279 init (EnableWindow per button) | jmp 0x4d022b: enable 绝招 0x50a by 0x4d53d4, 交给 0x50c by 0x4d9cc9, 围攻 0x50d by 0x4d7196 | 绝招/交给/围攻 buttons | PORTED | battle_input.gd `command_menu` with battle_commands.gd `special_enabled` / `give_enabled` / `siege_enabled`. See F4. [C] |
| 0x45bc55 | 0x45bc23 dialog 279 WM_COMMAND (id−0x507 → jump table 0x45bcbc) | jmp 0x4d029b: index 5 (交给) → EndDialog result 6, index 6 (围攻) → 7, else the table (whose entry 3 = 绝招 was re-pointed to 0x4d2800 → result 5) | click → command code | PORTED | battle_input.gd `command_menu` maps the entry to the command directly. [C] |
| 0x45bd35 | 0x45bd05 dialog 279 button painting (icon index → 0x471981) | jmp 0x4d034d: icon index 0x50a → 0, 0x50c → 4, 0x508 → 1, 0x50d → 0 | icons of the new buttons | PORTED | battle_input.gd `COMMAND_ICONS` [0, 0, 0, 1, 4, 2, 3] for 攻击 绝招 围攻 策略 交给 道具 待命 (道具 2 and 待命 3 come from the original code at 0x45bd64 / 0x45bd6d, 取消 has none), drawn by ui/choice_menu.gd at the row's left (0x472403), greyed when the command is off; the CmdIcon.dll pictures are assets/gfx/icons/commands. The item lists' and shops' two tabs get icons 0 and 2 as well (0x472281; dlg_panel.gd `tabs`). [C] |
| 0x45c6f8 | 0x45c697 选择武将 dialog (236): details of the selected person (face, name, class, stats) | jmp 0x4d411e: load the 120×120 sge portrait 301+face into 0x4cf2c0 (instead of the 64×80 face) | big portrait in the sortie dialog | PORTED | sortie_screen.gd `_draw_panel` draws the hovered candidate's 120×120 portrait (`Game.person_face`, large). [C] |
| 0x45e91a | 0x45e87d 选择武将 dialog proc, WM_INITDIALOG | call 0x4db120: enable button 0x3e9 "战场位置", create the hidden modeless dialog 333 "出战位置" (proc 0x4db180) → [0x4db0da] | 战场位置 map preview | PORTED | sortie_screen.gd `_draw_dialog` (button, enabled) → battle/sortie_map.gd `SortieMap.open`. See F13. [C] |
| 0x45e984 | 0x45e87d WM_COMMAND id 0x3e9 | data ref [0x4db0da]: ShowWindow(dlg333, SW_SHOW) | 战场位置 | PORTED | sortie_screen.gd `_on_hit` ("map") → `SortieMap.open`. See F13. [C] |
| 0x45e990 | same | data ref [0x4db0da]: SetActiveWindow(dlg333) | 战场位置 | PORTED | Same; `SortieMap` opens on top. See F13. [C] |
| 0x45ea04 | 0x45e87d 决定/取消 | call 0x4db0e0: hide the map child window [0x4b5ff4], destroy dlg333, EndDialog | 战场位置 cleanup | PORTED | Plumbing: the port's `SortieMap` is a modal window that closes itself, so 决定/取消 have nothing to destroy. See F13. [C] |

#### B5.2 Missing / partial features (implementable specs)

Common terms. U = the unit acting. "Strike" = one damage application with the original hit roll, damage, crit and
EXP (0x405e03 → 0x405744 → 0x405889 → 0x405c6c). Buff level: 6 = strong up, 0 = strong down, decaying toward 3 per
rules.md §9.3. ChangeUnit(pid, what, value, anim) = 0x45aa5c: what 0..5 sets buff byte U+0x18+what to value and plays
the buff animation 0x43e69f; what 6 sets status bits (value & 0x80 clears them instead). "End action" =
0x442718(U, 6): flags |= moved|acted, which also runs the path skills of F7. The commanded unit = the one passed to
0x43d538. Its pid is [0x4cf310] (set at 0x43d53e).

Command dialog 279, top to bottom: 攻击 0x507, 绝招 0x50a, 围攻 0x50d, 策略 0x508, 交给 0x50c, 道具 0x509,
待命 0x50b, 取消 (55×14 du each). The menu result goes to 0x43dde3; result 0xff = cancel = undo the move. After an
executed command, F6 (再移动) and then F8 (kill rewards) run.

##### B5 F1. 绝招 (special-move command) — PORTED [C] unless marked
Port: battle_commands.gd `special_enabled`, `special` and one function per move (`_cang_long` … `_wei_zhen_ba_huang`);
the 绝招 ranges in battle_actions.gd `attack_range_code`, hit / crit / defence in rules.gd (`special_running`).

**Enable** (0x4d53d4 → 0x4d5444(pid of the commanded unit)). MP is not tested here:
* pid 0 管毅, 7 伍天锡, 8 秦琼, 17 裴元庆, 19 罗成, 26 雄阔海: always.
* pid 1 程咬金: byte [0x55ac04] ≠ 0 and bytes [0x55ac05], [0x55ac06] == 0. R_11 "学三板斧指令" writes dword
  [0x55ac04] = 1; op 0x0a clear_flags zeroes [0x55ac06].
* pid 5 伍云召: his unit (first slot holding pid 5, 0x456079) is not paralysed (status & 0x02 == 0).
* the person in dyn slot 4 (pid == EV[3974]; the scripts set it to 3 = 尉迟恭): 夺面鞭.
* everyone else: disabled. (A 0x4d321d jump for pid 14 lands mid-instruction, but pid 14 never passes the
  enable test.)

**On click** (result 5 → 0x4d3007):
1. If the person lacks effect 58 无限绝技 (六军镜·技巧) and MaxMP ≠ 1 and U.MP (low byte) ≠ MaxMP → popup
   "MP未满", nothing happens (the unit stays moved but has not acted).
2. [0x4cf314] = 1 for the whole run (reset to 0 at the end), then dispatch on pid (0x4d30a5).

**Rules while [0x4cf314] = 1:**
* Target picker = the attack picker (0x45533d mode 1, enemy units in range; a right click returns without spending
  anything). Range code (0x4d3417): 怯 → 11; pid 8 → 6 (manhattan 1–2); pids 5, 19, 26 (and 14) → 0 (4
  orthogonal cells); others the normal range (effect 42 / effect 21 / class). The 张善相/张公瑾 overrides do not
  apply.
* After a target is chosen: U.MP byte (+0x14) = 0, i.e. all MP is spent.
* Each blow (0x4d3581) = screen darkening wipe (0x4d64ea) + one strike (0x4335a0): no second strike (double) and
  no counterattack.
* Hit (0x43b594 → 0x4d2f90): 100 for everyone except 程咬金 (pid 1). For him: 100 if the target is confused, else
  50, or 50 + 2·weapon level if he wields item 25 八卦宣花斧 and EV[3185] (byte 0x55e1c4) ≥ 1, or 50 + 4·level if
  EV[3185] ≥ 3.
* Critical (0x405efb → 0x4d34c9): always ×3/2, except attackers 伍天锡 (7) and 雄阔海 (26), who never crit during a
  绝招. Effect 57 still cancels crit damage (original rule).
* 裴元庆 (17): the defender's Def counts as 0 (0x43bceb → 0x4d3501).
* Scripted moves during a 绝招 (0x459487 → AI walk) are not blocked by units of the other side (flood fill
  0x438787).
* Name banner 0x4d6366: the skill name in big bold text (cell 0x40 if the view is ≥ 720 px wide, else 0x30),
  drawn as shadow layers then a main layer (drawing state 0x47d239(4, 0x12, 0) → white [G: colours]), centred on
  the window, held 20 ticks (1 s), then the map is redrawn. No SE.
* At the end: end action (6).

**Per character** (after picking target T, MP = 0):
* **苍龙过阵枪** 管毅 (pid 0): banner, strike, then ChangeUnit(self, 0 攻击, 6) and ChangeUnit(T, 0, 0). Extra
  pairs (self 6 / T 0) when the script switches are set: dword [0x55ac08] == 1 (盘手拨云枪 learned) → 防御 (1);
  [0x55ac0c] == 1 → 爆发 (3); [0x55ac10] == 1 → 精神 (2); [0x55ac14] == 1 → 士气 (4).
* **三板斧** 程咬金 (1): U faces T, banner, floating text "劈脑袋！" + strike. If T.HP > 0: "掏耳朵！" + strike. If
  still > 0: "小鬼剔牙！" + strike. Each strike rolls the 程咬金 hit chance above.
* **踏破连营** 伍云召 (5), T orthogonally adjacent: d = unit step U→T (vertical if the x are equal, else
  horizontal). The strike runs with [0x55ac64] = 1, which makes the class area code 12 (0x40783f → 0x4dbebb): every
  enemy on the straight line beyond T up to the map edge is also hit at half damage (secondary-target rule; they
  crit when T crits). Then, if 伍云召 is not paralysed, walk from U along d over consecutive enemy units. Stop with
  no move at the map edge or at a player-side unit (slot < 35). At the first empty cell he can enter (MoveCost ≠
  0xff): [0x55a6d0] = (facing, enemies passed), scripted move there (0x459487; the path is forced straight by
  0x43a9be → 0x4d3a2d, another batch), then ChangeUnit(self, 5 机动, 6), (1 防御, 6), (3 爆发, 6).
* **横扫千军** 雄阔海 (26), T orthogonally adjacent: 5 cells = T plus, if U.x == T.x, (T.x±1, T.y) and (T.x±2, T.y),
  else (T.x, T.y±1) and (T.x, T.y±2). That is the row across the attack direction, centred on T. U faces T, plays
  attack pose (unit_status action 5) and says "滚开,滚开!", then banner. U strikes every enemy (slot ≥ 35) on those
  cells, T last (never crits). Push (0x4d8e67): each enemy still on those cells moves 1 cell in U's facing direction
  if that cell is enterable and free for it (0x4401a8). It loses 乱/麻/迷 (status &= ~0x4a) and moves via 0x459487.
* **杀手锏** 秦琼 (8), range 1–2: banner, strike, ChangeUnit(T, 0 攻击, 0) and (T, 1 防御, 0). If dyn slot 11
  (EV[3981]) == 8: the banner is "回旋杀手锏" and during the strike the class area codes at 0x4091b2..b4 (classes
  33–35, i.e. 秦琼's 双刃骑 line) and 0x4091bc (class 43) are patched to 4 (pierce 1 cell behind T, half damage),
  then restored. The second target (attack ctx byte 0x492801) also gets 攻击/防御 0. [G: stale value if there was
  no second target.]
* **尽命三锤** 裴元庆 (17): U faces T, banner, [0x4d352e] = 1 (3-hammer strike animation from table 0x42bf08 instead
  of 0x40572e), strike with T.Def = 0.
* **回马枪** 罗成 (19), T orthogonally adjacent: they face each other. If 罗成 moved this turn (path count > 0) and
  0x4d9e68 finds a lure cell, the full move runs. 0x4d9e68 places 罗成 at path[0] for the test and scans the
  recorded path from path[1]: the first path cell T can stand on, or for a sideways step a cell beside the path
  [G: exact neighbour order], else the last cell.
  * If T is 乱/麻/迷: cure animation (0x43e69f(pid,6,0x88)) and status &= ~0x4a.
  * 罗成 rides back to path[0], his turn-start cell (0x459487).
  * T says "哪里逃？" (0x42d5f1) and walks 罗成's path backwards to the lure cell (0x4da000).
  * They face each other, banner "回马枪", strike, ChangeUnit(T, 5 机动, 0).

  If 罗成 did not move: one plain strike with no banner and no debuff.
* **威震八荒** 伍天锡 (7): no picker. Targets = enemy units (slot ≥ 35) on the 4 diagonal cells (only if his
  attack range code ≠ 0) and the 4 orthogonal cells. If there are none → popup "范围内没有敌军部队。" and nothing is
  spent. Otherwise banner, MP = 0, and one strike on each target in turn (U faces it; no crit, no counter).
* **夺面鞭** (dyn slot 4 person = 尉迟恭): banner, ChangeUnit(self, 0 攻击, 6) and (self, 1 防御, 6), then the
  strike.

##### B5 F2. 围攻 (siege command) — PORTED [C] unless marked
Port: battle_commands.gd `helpers`, `siege_enabled`, `siege_command` and the siege run; 并蒂 in battle_actions.gd
`_crit_rate`.

**Helper test** helpers(A, T) (0x4d698e). Check the 8 cells around T (4 orthogonal, then 4 diagonal). A helper H
on such a cell must satisfy all of:
* H ≠ A and H is on A's side (both slots < 35 or both ≥ 35);
* H has not finished (flags & 0x02 == 0) and is not confused;
* H's attack range code is in {0, 5} (counts only on an orthogonal cell) or in {1, 6, 10, 12, 13} (any of the 8).

Ranged codes never help. The list goes to 0x4cf318 (≤ 8 entries).

**Enable** (0x4d7196, A = first slot with the commanded pid). The range code r of A decides:
* r ∈ {0, 5}: some enemy (slot ≥ 35) orthogonally adjacent to A has helpers ≥ 1;
* r ∈ {1, 6, 10, 12, 13}: the same for diagonal (checked first) or orthogonal neighbours;
* any other r: disabled.

**On click** (result 7 → 0x4d6d00): pick T with the attack picker (mode 1, A's range); cancel → nothing. If
helpers(A, T) == 0 → popup "无法围攻该部队" and pick again. Then 0x4d6d87(T, A, n), starting with SE 5:
* **Siege break** (0x4d74e4(T, A.pid)). Conditions:
  * T is not confused and is alive;
  * one of: T has effect 60 先手攻击; T is 定彦平 (101) or 东方伯 (136) and 0x4d75d2(T, A) [G: their 双雷引
    condition, not traced]; T is 姜松 (14, sets [0x55ac68] = 1 = forced double);
  * A lies in T's attack range from T's cell.

  Then T and A face each other, [0x4d002c] = 1 and T makes a normal Attack on A (0x4064f1: its strikes plus A's
  normal counter; [0x55ac24] = 0x4d7b90(…) mode for 双雷引 [G]). The helpers do nothing and there is no extra
  counter.
* **Otherwise**: popup "围攻" (0x4d73aa). A attacks T (0x4d2f1e, ctx 0x4927f0 → 0x433540: strike, possible double,
  no counter). Then each helper in list order attacks T the same way (separate ctx 0x4cf330) and is marked finished
  (flags |= 6, greyed). Finally T counterattacks A once with the original Counter rules (0x40639a: T alive and not
  confused, A in T's range, A without effect 44).
* A's action ends (6). EXP is awarded per attack sequence as usual.

**并蒂** (0x43d5f3 site): while the commanded unit is 管毅 (pid 0), any non-counter attack by the dyn-slot-2 person
(EV[3972] = 2 王君珂) has crit rate 100. In practice this is his help in 管毅's 围攻.

**AI** (other batch, site 0x43ac3f → 0x4d6b80): in the AI's physical attack, if helpers(U, T) ≥ 1, T is 8-adjacent
to U and U's range ∉ {2, 3, 4}, the AI runs 0x4d6d87 (the same 围攻) instead of a normal attack. Enemy helpers that
have not acted lose their turn.

##### B5 F3. 交给 (hand over an accessory) — PORTED [C] unless marked
Port: battle_commands.gd `give_enabled`, `give_command`, `give`, `_give_fx`.

**Enable** (0x4d9cc9):
* commanded pid low byte == 11 (樊虎, 行囊): some bag entry (GS+0x13 = 0x4b0783, 200 × {id, lvl, exp}) has id ≥ 0x35
  (≠ 0xff). Ids ≥ 53 are accessories and consumables.
* anyone else: has an accessory equipped (person +0x34 ≠ 0xff).

**On click** (result 6 → 0x4d287e):
* Not 樊虎: item = own accessory → Give(U, item).
* 樊虎: [0x55ac5c] = 1 while it runs. Loop while 樊虎 is not finished: choose an item from the item-list dialog
  0x43dd2b [G: filtered to accessories by [0x55ac5c]]; cancel → stop. Give(U, item); on success clear the first bag
  entry with that id (0x4d9d4b).

**Give(U, item)** (0x4d28f0):
1. Pick a receiver R with 0x45533d(range code 1 = the 8 surrounding cells, mode 4 = own side, incl. own cell,
   param item). The HUD preview shows the item's effect; types > 0x51 are named via 0x4412c9 → 0x4d23a8. Cancel →
   return, nothing happens.
2. Picking U itself → ignored, pick again.
3. If R is 樊虎 (pid 11): the item goes into the first free bag slot (0x4d9c85).
4. Else if R has an accessory → popup "该武将辅助装备不为空", pick again.
5. Else if R cannot use it (0x407907: accessory family byte +0x17) → popup "该武将不能装备该辅助", pick again.
6. Else equip it on R: 0x407dec(R, slot 2, code = item − 0x33, level 0xff).
7. Then clear the giver's accessory slot (0x407dc4(giver, 2)) and end U's action (6).
8. Feedback (0x4d9bfd): giver unit_status action 1, item icon from giver to receiver via 0x4d2b66 twice [G: exact
   animation], receiver unit_status 0, popup "交出%s" (item name).

##### B5 F4. Command-menu plumbing (sites 0x43d53e, 0x43e17b, 0x45bb2b, 0x45bc55, 0x45bd35) — PORTED, except the icons
Port for F1–F3:
* the seven entries in the original order (攻击, 绝招, 围攻, 策略, 交给, 道具, 待命): battle_input.gd `COMMANDS` /
  `command_menu`, with the enable tests above;
* the commanded pid in [0x4cf310]: battle_input.gd `select_unit`;
* icons: none. The port's menu is a text list without icons for any command (row 0x45bd35).

##### B5 F5. 连续攻击 (effect 90) and 连续策略 (effect 83) — PORTED [C]
Port: battle_input.gd `_do_attack` and `_do_strategy`; battle_actions.gd `second_cast` / `strategy_mp`.

**连续攻击** (attack command 0x43dada; [ebp-0x10] counts extra rounds). After the first attack (and any 引导攻击
re-attack):
* Conditions: count == 0, attacker has effect 90, and 0x4d2a47: the attacker is alive and not 乱 (8), 怯 (0x20) or
  迷 (0x40).
* Then (0x406b4f): [0x4d0d5d] = 0, UI refresh 0x4d2ab2, count = 1, and the target picker opens again for a second
  attack. Cancelling the second pick ends the action.
* So: one optional extra attack, player-commanded units only.

**连续策略** (strategy loop 0x43dc21 / 0x43dc99):
* After a successful cast, 0x4d0d71: if [0x4d0d61] == 0 and the caster has effect 83 → [0x4d0d61] = 1 and the
  action does not end. The strategy list reopens; MP cost ×2 via 0x425ad0.
* Otherwise [0x4d0d61] = 0 and the action ends (6) with a map refresh.
* Cancelling the list while [0x4d0d61] == 1 → [0x4d0d61] = 0 and the action ends.

AIAct also calls 0x43dc99. An AI caster with 83 leaves [0x4d0d61] = 1, so the next cast by anyone pays ×2 and is
treated as the second cast (quirk).

##### B5 F6. 再移动 (effect 82) — PORTED [C]
Port: battle_input.gd `_move_again` (not for a unit that fell in its own attack, which the original would let move).

After every executed player command (0x43e1b9 → 0x4d27a0):
* Condition: U has flag 4 (moved) and flag 2 (acted), and its person has effect 82.
* Clear both flags (0x406690(6)) and run the move UI again (0x43d538: range from the new cell, pick a destination,
  walk; a right click keeps U in place).
* Then end the action (6) regardless.
* (Corrected while porting: every finished command ends with 0x442718(6), which sets flag 4 as well, so a unit that
  did not move before acting gets the second move too.)

##### B5 F7. 锻造 / 波若 path skills (0x44272c → 0x4d90bf) — PORTED [C]
Trigger: U's action ends with flags 6, U.pid == commanded pid [0x4cf310], path count n = [0x4cfbfc] ≥ 2. Visit the
cells path[n−1] down to path[0] (every cell walked through except the final one); each cell holding a unit (an
ally passed through, or anyone at path[0]) counts:
* **波若** — 罗士信 (pid 15) and byte [0x55ac48] ≠ 0 (scripts set it; the info window shows 【异术·波若】 when it
  is 15). c = 10/(n−1) (integer). For each unit X:
  * s = rand(5); ChangeUnit(X.pid, s, 6, anim): temporary strong buff.
  * w = X.person stat word s (+0x11+2s); f = 100 if w ≤ 300, 400−w if w ≤ 400, else 0.
  * If chance(c·f/100): stat word s += 1 (permanent). Else c = 0 for the remaining units.
* **锻造** — 齐国远 (pid 16) and byte [0x55ac60] ≠ 0. For each unit X:
  * slot = chance(50) ? armour : weapon. Skip if empty or exp == 0xff.
  * m = 149 for a treasure (0x40c76e), else 99.
  * exp < m → exp += 1. Else at level 9 with exp < 249 → exp += 1. Else level += 1; exp = 0xff if the new level
    reaches the maximum (10 for a treasure, 3 otherwise), else 0; then the level-up notice 0x4083ef.
  * On a change: unit_status(X, 1) and SE 30.

Port: battle_actions.gd `end_action` (`_boruo`, `_duanzao`), on the path record of row 0x43da45
(battle_stage.gd `record_path`).

##### B5 F8. Kill rewards after each player command (0x43e1be → 0x4dcb09) — PORTED [C]
Port: battle_actions.gd `kill_rewards`, called by battle_input.gd `command_menu`.

Scan enemy slots 35..114 for units with state 2 and HP == 0 (killed during this command, not yet removed).
* Value per unit: generic (pid ≥ 0xd2) 1. Named pids default 3, or the value from table 0x4dcc40:
  * 10: 17 裴元庆, 32 杨林, 33 宇文成都, 34 李元霸, 100 杨素, 101 定彦平, 204 张善相, 27 伍登, 208 李孝恭;
  * 8: 19, 35, 41, 42, 43, 44, 46, 48, 54, 107, 136, 142, 178, 187, 188, 189;
  * 6: 40, 50, 57, 58, 68, 84, 86, 91, 108, 122, 205, 207.
* **辰屑**: for each value point, chance(10) → EV[3007 + rand(3)] += 1 (3007 辰屑·天, 3008 辰屑·地, 3009 辰屑·人;
  the scripts use them as materials). No popup.
* **尉迟恭 MP**: if EV[3183] ≥ 4 and a slot holds pid 3: its MP byte += 5 × (number of dead enemies), capped at
  person byte +0x20 (base MP), +15 if accessory 0x43 逍遥巾, +30 if 0x44 诸葛巾. Who made the kill does not matter.

##### B5 F9. EV[10] "HP reached 0" flag (sites 0x43e16b, 0x44ccc8) — PORTED [C] for the sites, cross-batch
EV[10] = 0 at battle-unit creation (0x44ccc8), before each player command (0x43e16b) and at AIAct start (0x43ad2b).
The engine sets EV[10] = 1 when a unit's HP reaches 0:
* 0x405bb7 after a strike;
* 0x422c87 for strategies;
* 0x4121b5 op 0x38;
* 0x4093c3 暗杀 (other batches).

27 battle scripts (S_23..S_57) have a WHEN section "合并所有HP0撤退" gated by `test_int_var EV[10] ≥ 1`. For each
person with battle HP == 0 it runs:
* unit_op_53 retreat (with retreat line) and kill counters (S_23: EV[322] / EV[324] += 1);
* boss lines and **item rewards** (S_23: 宇文化及 → get_item 91, 宇文成都 → get_item 89);
* other characters leaving.

Done: the port sets EV[10] = 1 where the original does (battle_actions.gd `unit_fell`, battle_stage.gd
`_assassination_countdown`) and resets it at the three points above (battle_stage.gd `create_battlefield`,
battle_input.gd `command_menu`, battle_ai.gd `act`). HP-0 units stay
on the map until the command or AI action is over; the poll with the actor as current unit (0x45b5fe) sees them
there, then 0x44cc03 removes them and the scene is polled again (rules.md §9.1, verified 2026-10-11).

##### B5 F10. Per-character terrain rules (0x43f7cf / 0x43f84d hooks) — PORTED [C]
MoveCost(U, terrain) in order:
1. family ≥ 27 or table cost 0xff → impassable.
2. has_effect(34 恶移麻痹/虎类豹) → 1.
3. **单雄信** (pid 4) with accessory 47 板角墨麒麟 and EV[3190] ≥ 3 → 1.
4. If c > 1 and (has_effect(86 黄骠马) or **张公瑾** (pid 25) with class 41) → c −= 1.
5. **丁天庆** (pid 6) on terrain 9/10/13 → 1.
6. Else c.

TerrainEffect: table value; **丁天庆** on 9/10/13 → 11; then effect 86 → max(·, 10); 0xff → 0.

Port: rules.gd `move_cost` (steps 1–6 in this order) and `terrain_effect`.

Attack range (0x43f8be, not in a 绝招): **张善相** (pid 204) → 12 (manhattan 1–3, 枪母子); **张公瑾** (pid 25)
with class 41 → 4 (manhattan 2–4, 飞将军). Both are evaluated before effect 42 and after 怯. Port:
battle_actions.gd `attack_range_code`.

##### B5 F11. 暗杀 delayed defeat (0x441888 site; the rest in other batches) — PORTED [C]
* On a successful 暗杀 (0x43c058): 0x569f00[T] = 2 (countdown), 0x569f73[T] = caster slot, byte 0x569fe7 ^= 1.
* At each player phase start, 0x4364c6 counts down enemy slots 35..114. At each enemy phase start, 0x4364b6 counts
  down slots 0..34 (call sites 0x44ee2c / 0x44e92e). Per unit (0x40937f): if the mark is ≠ 0, decrement it. If it
  reaches 0 and the link ≠ 0xff:
  * T.HP = 1 and EV[10] = 1;
  * popup "%s被暗杀了！！" (0x48c9e6);
  * link = 0xff.

  The HP0 script sections (F9) then retreat the unit.
* When any unit leaves the map (RemoveUnit tail, 0x4dbff3): its own mark is cleared and every mark whose link is
  that unit is cancelled. If the assassin dies or retreats first, nothing happens.
* Usability (0x4dbf8a, category 17): never blocks. It compares the category, not the strategy, with 0x15, so the
  earlier guess that pending marks forbid a cast was wrong (checked with group 1, item 2).

Port: the mark in battle_actions.gd `_apply_strategy`, the countdown and defeat in battle_stage.gd
`_assassination_countdown` (from `_phase_start_effects`), the cancellation in battle_stage.gd `remove_unit`.

##### B5 F12. 怀恨攻击 (effect 87) hit counters (0x44e914, 0x44ee15) — PORTED [C]
Counter byte 0x55a500[slot]:
* +1 (saturating at 0xff) for the defender on every real damage calculation that passes the hit roll (CalcDamage
  hook 0x43bd2c → 0x4d3389 → 0x4d0cf5, other batch).
* Cleared for slots 0..34 at the enemy phase start and for slots 35..114 at the player phase start, and for all
  slots by op 0x44.

Use (0x43bef7 → 0x4d0d2e, other batch): mode-0 damage × (10 + counter)/10 when the attacker has effect 87
天玉玲珑铠. 王君珂's 并蒂 attack bonus from 管毅's counter reads the same array (other batch).

Port: the counters are Mem 0x55a500 (`BUnit.GRUDGE`): +1 in rules.gd `_count_hit`, used in rules.gd `calc_damage`, cleared
in battle_stage.gd `_phase_start_effects` and by op 0x44 (battle_stage.gd `op_battle_init`).

##### B5 F13. 战场位置 map preview in 选择武将 (0x45e91a / 0x45e984 / 0x45e990 / 0x45ea04) — PORTED [C]
The sortie dialog 236 has an extra button 0x3e9 "战场位置" at (207,344, 60×14 du). The template has it disabled;
WM_INITDIALOG enables it. It opens the modeless dialog 333 "出战位置" (136×108 du, one static 0x43f). The static
hosts window [0x4b5ff4], sized map W×12 × H×12 px. 0x4db2a7 draws into it:
* the coming battle's terrain grid (map id = 0x418e10(GS) / 2, loaded via 0x44c1cb(1) from Yun.wa) with one 12×12
  terrain tile per cell (atlas from file 0x48bb88, entries 12..14);
* numbered markers for the up to 15 player deployment positions from the mod table 0x55e9d8 (3 bytes each: x, y,
  marker set; filled by op 0x4b in story mode). The port stores this table (script_host.gd `op_op_4b`).

决定/取消 hide and destroy it. Port: the 战场位置 button of sortie_screen.gd opens battle/sortie_map.gd `SortieMap`.

##### PARTIAL details
* **0x43da45 path record**: done (battle_stage.gd `record_path` / `move_path`).
* **0x43f8d1 attack range**: done (battle_actions.gd `attack_range_code`).
* **0x44e1c9 autosave** (still PARTIAL): original saves silently into slots 0..4 in rotation at every player-phase
  end while saving is allowed. The port's separate autosave file is a deliberate replacement and does not touch
  numbered slots ([Deliberate differences](#deliberate-differences-port-design-keep-unless-asked)).
* **0x4525d4 cursor readout**: done (battle_hud.gd `_draw_cursor_text`).

### B6 — Dialogs, info window, runtime (0x460000..0x486000)
Method: the original code disassembled around every site, mod code followed to its return into .text, containing
functions decompiled with Ghidra.
Dialog ids: 325 道具一览 (proc 0x46d00b → 0x4680e7), 327 买进 (0x46ce1c → 0x46aa02, panel object at +0x1b0),
328 装备 (0x46cf36 → 0x46c065, panel at +0x6a0), 329 卖出 (0x46cea9 → 0x46b7ce), 335 地形情报一览 (0x46ee76),
341 历史情报 (mod 0x4d184c), 166 武将情报 (0x479164). Main menu APPMENU: 101 保存 = 0x65, 102 读取, 112 结束游戏
= 0x70, 107 环境设定 = 0x6b, 105 武将一览, 40147 持有道具一览 = 0x9cd3, 40150 地形情报一览 = 0x9cd6, 40151 历史情报
= 0x9cd7, 106 胜利条件, 108 战场缩小图, 40073 版本情报.
Person names as in [Skill owners](#skill-owners); all pid tests were read from code.

Counts (55 rows), brought up to date with the port on 2026-10-12: PORTED 29 · PARTIAL 0 · MISSING 7 (技能说明, by
design) · N/A 17 · FALSE 2. At the audit: PORTED 9 · PARTIAL 2 · MISSING 25.

#### B6.1 Sites

| site | original function (what it does) | mod change | feature | status | port evidence or missing spec |
|---|---|---|---|---|---|
| 0x465d40 | 0x465a40: fills the battle 策略 command list (dialog 282, object 0x487038, opened by 0x4664cb(unit) from 0x43dc5f): strategies 0..0x43 with learn level (strategy+0x11+class, 0x409580) ≠ 0 and ≤ level; also the original 策略模仿 (effect 51) rows from the 4 adjacent units | jmp 0x4da280 inside the loop: if class == 0x2b (统军) and strategy id is 0x29 补给 or 0x2b 救护 and the unit's person id low byte == 8 (秦琼), the class used for the learn table is switched to 0x23 (凤凰骑) — the local is overwritten, so it stays 0x23 for all later ids 0x29..0x43 | 秦琼 as 统军 gets 补给 (Lv 28) and 救护 (Lv 40) in battle | PORTED | battle_actions.gd `known_strategies` (class 35's table from id 0x29 on) |
| 0x4664b9 | 0x466446: MP cost shown for a row of the battle 策略 list (and used by 0x4659f9: row enabled iff cost ≤ unit MP): cost = 0x425ad0 (strategy+0xe, ×2 during the second 连续策略 cast) minus cost·v/100 for 节约MP (effect 49) | jmp 0x4d4a2b: if 0x4d4a60(0xb3, unit) — 房玄龄's unit on the map (state 2), same side group (slot < 35 vs ≥ 35, 0x406710) and in one of the 8 cells around the caster (0x45afca(caster.pid, 0xb3, loose=1)) — cost = cost >> 1, and 0 becomes 1 | 【术】房谋 (房玄龄): adjacent allies cast for half MP (menu cost/enable; cast-time deduction is hooked separately at 0x422f7c → 0x4d4a05, other batch) | PORTED | battle_actions.gd `strategy_cost` (with 节约MP; `Skills.beside`), used by the 策略 list (`BattleInput._do_strategy`), `can_cast` and the cast |
| 0x467eb8 | 0x467e57: fill of the consumable list class (vtable 0x486738/0x486740) used by the battle item dialog 0x43dd2b (dialog 242); original filler 0x466a73 lists items 0x57..0x67 whose stack count GS+0x26b+(id−0x57) ≠ 0 | jmp 0x4d9a65: if [0x55ac5c] == 1 it calls 0x4d9ad3 instead: one row per item id in {0x2f, 0x35..0x56} that occurs in any of the 200 bag slots (GS+0x13, 0x4d9b87). [0x55ac5c] is 1 only inside 0x4d287e when the acting unit is pid 11 樊虎 (交给 command) | 樊虎's 【术】行囊: his 交给 hands out accessories from the warehouse | PORTED | battle_commands.gd `give_command` (as a choice list) |
| 0x4680ff | 0x4680e7: dialog 325 道具一览 proc; WM_INITDIALOG | call 0x4db000(hDlg): SetDlgItemText(2000, "%d/200" % used bag slots) | 仓库装备现存量 counter | PORTED | ui/item_list_window.gd (counted when the window opens) |
| 0x4693a4 | 0x46938f: value of a treasure's special effect at an item level (display, 0x461ef3): ×(lvl+1) for specials 0x18/0x19 | jmp 0x4d9303: also ×(lvl+1) for 0x1a (辅助防御), ×(lvl+4) for 0x55 (固定伤害) | item effect values in detail texts | PORTED | person.gd:189 treasure_effect_value; used by detail_panel.gd effect_text |
| 0x469433 | 0x46942a(slot): fills one slot (Wepon/Armor/Sub Item) of the equipment panel of 买进 327 / 装备 328 | jmp 0x4d0eb4 at entry: EnableWindow(control 0x575 "Sub Item:", pid != 11) | 樊虎 (pid 11) has no 辅助 slot | PORTED | ui/person_panel.gd `_draw_slot` (label greyed for pid 11); person.gd `can_equip` refuses his accessories |
| 0x4695c6 | same function: Lv / Exp bar of the slot | jmp 0x4d3d5a: bar maximum = 100, or 150 for a treasure (0x40c76e), +100 when the level is 9 | equipment Exp bar scale | PORTED | person_panel.gd `_draw_slot` |
| 0x469dd7 | 0x469c60: init of the 买进/装备 panel: fills the person combobox 1098 (owner-drawn, item data = person record) with party members (0x41a190: P+0x2a == 0), selects entry 0 | jmp 0x4dbd90: the loop runs i = 0..31 over the byte table 0x4dbdb0 instead of the person ids: 0 8 3 1 19 17 14 26 7 5 43 4 9 2 24 13 10 6 16 18 12 11 28 25 15 23 22 21 29 20 31 27 | order / set of selectable characters in 买进 and 装备 | PORTED | person_panel.gd `TABLE` / `_init` (party members of 0x4dbdb0, in its order) |
| 0x469fb8 | 0x469ecb: combobox 1098 handler (CBN_SELCHANGE) of 327/328: prev/next buttons, new person | call 0x4db000(hDlg) after enabling 上一/下一 (label exists only in 328) | 仓库装备现存量 counter | PORTED | shop_window.gd / equip_window.gd `_draw_dialog` (`ShopWindow.used_slots`, redrawn after every change) |
| 0x46a05e | same: on a new person, load his portrait for control 1076 (original: Nao face via object 0x4ac538) | jmp 0x4d4371: LoadImage sge.wa 301+face (0x4075a7) into [0x4cf2c0] (hinst [0x4cf100], 0x4d4144) | big 120×120 portrait in 买进/装备 | PORTED | person_panel.gd `draw` (`Game.person_face`, sge 301+face) |
| 0x46b1f5 | 0x46b043: 卖出 329, sell one equipment row: price 0x40c7a9, confirm in the merchant window, gold += price (cap 9 999 999), remove bag slot (0x40d51b; may give a bonus fruit) | call 0x4db000(hDlg) right after removing the bag slot | 仓库装备现存量 counter | PORTED | shop_window.gd `_draw_dialog` (`used_slots`) |
| 0x46b7ed | 0x46b7ce: 卖出 329 proc, WM_INITDIALOG | call 0x4db000(hDlg) | 仓库装备现存量 counter | PORTED | shop_window.gd `_draw_dialog` (`used_slots`) |
| 0x46bd89 | 0x46bc8d: 装备 328 warehouse list, equip the clicked item on the person if 0x407907 allows (bag slot freed, old item back into the list) | call 0x4db058 = original 0x4640cd(list) + 0x4db000(hwnd of the 装备 dialog [0x4b68e0]) | 仓库装备现存量 counter | PORTED | equip_window.gd `_draw_dialog` (`ShopWindow.used_slots`) |
| 0x46bf9a | 0x46befb(slot): 装备 328, take off a slot into the warehouse (refused when 200 slots are used) | call 0x4db058 (list refresh + counter) | 仓库装备现存量 counter | PORTED | equip_window.gd `_draw_dialog` |
| 0x46c726 | 0x46c53b: init of both 地形情报一览 lists (vtables 0x487488 地形效果, 0x4874e8 消耗机动力): columns, shared 48×48 image list [0x4b68d0] from Mapatr.dll 100..123 | call 0x4d5fa1 = ++[0x4b68d4] (image-list reference count, decremented and destroyed in 0x46cbc9) then returns the list | none (resource ref-count fix) | N/A | Win32 image-list lifetime |
| 0x46c75b | same: rows = terrains 0..23 with flag table[t] == 1 | the table operand now points at mod data 0x4d5fbc = 1 for 平原 草原 树林 荒地 山地 雪原 桥梁 浅滩 沼泽 大河 城内 民居 (t 0 1 2 3 4 7 8 9 10 13 16 23) | 地形情报一览 row set | PORTED | ui/terrain_window.gd `TERRAINS` |
| 0x46d452 | 0x46d43a: paints the merchant message window (shop confirmations, 0x46d9a4/0x46dc1c): clear text area (0x90,0x1d,0x130,0x50), up to 3 lines at column 0x13, y = 0x33 + 20k | call 0x4d4606(0) in place of the original face drawing: TransparentBlt (black key) of the 120×120 sge portrait [0x4cf2d4] at ([0x4cf2fc],[0x4cf300]) = (0,0), mark.wa id 2 (8×80) at (x+0x88, y+0x1d), id 3 at (x+0x1c0, y+0x1d) (other offsets when [0x4cf305] = 0), mark id 5 24×24 when [0x4cf306]; DC of [0x4b601c] when [0x4cf2ba] == 3 | shop merchant window look | PORTED | ui/merchant_box.gd (modal, [Deliberate differences](#deliberate-differences-port-design-keep-unless-asked)) |
| 0x46d7e9 | 0x46d749: setup of the merchant window (456×120 at client (16,56) of the main window, or (16,168) of the caller when [0x4cf306]); loads the speaker's face (0x4092a4 → sge 301+face into [0x4cf2d4], mode [0x4cf2ba] = 3) | call 0x4d4144(2, [0x4cf2f4] mark.wa, &[0x4cf2dc]) | merchant window side piece | PORTED | merchant_box.gd (mark.wa pieces 2 and 3) |
| 0x46d7fb | same | call 0x4d4144(3, mark.wa, &[0x4cf2e0]); then [0x4cf305] = 1 | merchant window side piece | PORTED | merchant_box.gd |
| 0x4701be | 0x47018c: WM_DRAWITEM of the Exp bar (0x565) in item detail dialog 167 | jmp 0x4d3d08: bar maximum 100, +50 for a treasure, +100 at level 9 | item detail Exp bar scale | PORTED | detail_panel.gd:46 exp_max, :143 |
| 0x4706e9 | 0x470686: window-message dispatcher of the scrolling-panel class (original 宝物 catalogue 0x487548; the mod's 历史情报 panel copies it as vtable 0x4d1818) | data ref: if [0x4d18e0] ≠ 0 (set to 2 while 历史情报 runs) WM_VSCROLL passes (wParam, 0) instead of (LOWORD, HIWORD) to the scroll method (0x4d1b8e → 0x4d127a) | 历史情报 scrolling | N/A | scrollbar message plumbing; port lists scroll by their own means |
| 0x474b24 | 0x474b0f: yes/no message box (dialog 0x154) | none: E8 byte of `lea ecx,[ebp-0x18]` (8D 4D E8) followed by the real `call 0x475600` at 0x474b25 | — | FALSE | linear-sweep artefact (verified bytes 8d4de8e8d60a0000) |
| 0x474b80 | 0x474b78: OK message box (dialog 0x153) | none: same pattern, real `call 0x475600` at 0x474b81 | — | FALSE | linear-sweep artefact |
| 0x474c90 | 0x474c59: main-window menu commands; cmd 0x65 = 保存 → save dialog 0x41a466 | `je` retargeted to 0x4d009f: if u32 [0x4ce004] == 0 show "目前不可存盘。" (0x555000, 0x42f699(2, …)) and do nothing, else 0x41a466. [0x4ce004] is set by script op 0x74 set_4ce004 (473 uses: 0/1) | saving forbidden while scripts say so | PORTED | main.gd `save_menu` (story and battle menus) |
| 0x474cd2 | same; cmd − 0x66 jump table (0..8) | cmd 0x70 (menu 112 结束游戏) → jmp 0x4d1bf0: PostMessage(main, WM_CLOSE) (same as the old 0x68 entry) | 结束游戏 menu item | N/A | quitting the app is platform UI; port has 回到标题 |
| 0x474db7 | same; cmd 0x9cd7 — originally the treasure catalogue (object 0x475700, "目前为止发现的宝物 %2d / %2d"; that code is now NOPs and 0x475700 has no caller) | call 0x4d184c: the mod's 历史情报 window (dialog 341) | 历史情报 (chronicle) window | PORTED | ui/history_window.gd (town and battle menus) |
| 0x474de8 | same; cmd 0x6b = 环境设定 → 0x41bf43 (dialog KANKYOU) | call 0x4e2000: runs the dialog, then writes GS+0, GS+1, GS+8, GS+0x10 and [0x4dbe25] to SAVEDATA\Niuniu.wa bytes 1..5 (0x41a1b0); 0x4e20ff reads them back at start | settings remembered between sessions | PORTED | core/settings.gd `save_file` / `load_file`, ui/settings_window.gd (title, town and battle menus) |
| 0x4769dd | 0x476987: 能力 page 机动 field | call 0x4d3197 (= unit 0x4b2c50 + (slot & 0xff)·0x24, same as the inline code it replaces); the space was used for the new "%u ( -%d )" debuff text (format at 0x4072f0 in a .text cave) | 机动 with buff/debuff | N/A (helper) | behaviour-neutral helper; the related mod text ("( -2 )" for move buff ≤ 2) is PORTED in info_window.gd:319 _move_text |
| 0x476eae | 0x476eab: 装备 page (179) fill entry | jmp 0x4d0e6a: EnableWindow(0x575 辅助 label, pid != 11) | 樊虎 has no 辅助 | PORTED | info_window.gd:343 (label dimmed for pid 11) |
| 0x47771e | 0x477697: WM_DRAWITEM of the two Exp bars on page 179 | jmp 0x4e0021: bar maximum 100 / treasure 150 (+100 at Lv 9) | equipment Exp bar scale | PORTED | info_window.gd:352 → detail_panel.gd:46 |
| 0x478732 | 0x478688: 武将情报 refresh; after 0x477adc (unit lookup) | jmp 0x4d3bd3: 技能 group caption chain ([0x55ac04] 三板斧, [0x55ac40] 天魔, [0x55ac48] 波若, [0x55ac44] 魔功, [0x55ac60] 锻造, codes ≥ 0x36 → 0xff, dynamic list 0x55ee08 = EV[3970..3999], pid 25 飞将军, pid 24 贯石, static table 0x4d3c4c/0x4d8260, else 无) | 技能 caption | PORTED | info_window.gd:131 skill_info (same order and code-table writes) |
| 0x4788c0 | same: portrait of control 1076 (original Nao face) | jmp 0x4d40f8: sge.wa 301+face (0x4d4144) | big portrait | PORTED | info_window.gd:216 p.face_tex() → large sge face |
| 0x4788cb | same: after the portrait | call 0x4dc630 → 0x4dc6a8(hDlg): button 100 enabled iff [0x4dc0ff] ≠ 0xff (page 兵种 shown) and the skill is active (0x4dc5c5); caption 技能介绍 / 武将列传 / ---- for state 0 / 1 / other | 技能说明 button | MISSING (by design) | left out on purpose (group 5 item 40; rules.md §11); spec F7 [C] |
| 0x47895b | same: 基本能力 fill 0x4783c1 | call 0x528000: 0x4783c1, then 技能 text (1445) = Fhua[450+code] if active else Fhua[598], empty for pid ≥ 210 | 技能 text | PORTED | info_window.gd:170 |
| 0x478a47 | 0x478a0f: 状态 line, 混乱 test | call 0x4d3197 (neutral unit-pointer helper; frees room for the inline 暗杀 test at 0x478bd3) | 状态 line | N/A (helper) | feature PORTED info_window.gd:186 status_text (暗杀 included) |
| 0x478a82 | same, 麻痹 test | call 0x4d3197 (neutral) | 状态 line | N/A (helper) | as above |
| 0x478ab5 | same, before 中毒 | jmp 0x4d6140: adds 迷失 (0x40) and 怯力 (0x20), then the 中毒 test, continues at 0x478af0 | 状态 words | PORTED | info_window.gd:15 STATUS_PARTS order 混乱 麻痹 迷失 怯力 中毒 穷计 |
| 0x478aba | (no function; old 中毒 block) | call 0x4d3197 in code that 0x4d6140 now jumps over | — | N/A | dead code |
| 0x478af5 | 0x478a0f: 穷计 test | call 0x4d3197 (neutral) | 状态 line | N/A (helper) | feature PORTED (status_text) |
| 0x478b2e | same, 攻击增加 (buff ≥ 4) | call 0x4d3197 (neutral) | 状态 line | N/A (helper) | feature PORTED |
| 0x478b83 | same, 攻击减少 (buff ≤ 2) | call 0x4d3197 (neutral) | 状态 line | N/A (helper) | feature PORTED |
| 0x47907f | 0x478f7b: WM_INITDIALOG of 武将情报 (created hidden at start-up, first refresh for list entry 0) | `mov byte [0x4dc100], 3`: restores pid 0's skill code after that start-up refresh | none visible | N/A | the port never runs a start-up refresh; the code table keeps its exe value 3 until the window is opened, as in the original |
| 0x479230 | 0x479164: 武将情报 proc, WM_INITDIALOG | call 0x4dc500: [0x4dc0ff] = (page == 3 兵种) ? 0 : 0xff | 技能说明 button state | MISSING (by design) | F7 |
| 0x479309 | same, WM_COMMAND id 100 | call 0x4dc720(index, page-284 hwnd): state = (state+1) mod 2 (0xff → 0); page 284's description box (1446) := biography Fhua[922+pid] (pid < 0x400); caption updated | 技能说明 button click | MISSING (by design) | F7 |
| 0x47932a | same, 上一武将 | call 0x4dc500 (reset state) | 技能说明 button state | MISSING (by design) | F7 |
| 0x479388 | same, 下一武将 | call 0x4dc500 | 技能说明 button state | MISSING (by design) | F7 |
| 0x479492 | same, TCN_SELCHANGE → 0x4790da(page) | call 0x4dc662: 0x4790da(page), reset state, 0x4dc6a8 (enable/caption button 100) | 技能说明 button state | MISSING (by design) | page switch itself PORTED (info_window.gd _set_tab); button F7 |
| 0x479754 | 0x479728: show the window for a pid | call 0x4dc500 before the gate 0x407060 | 技能说明 button state | MISSING (by design) | F7 |
| 0x479c31 | 0x479bf1: hides the floating windows (info window, overview, map) at phase changes (callers 0x44ec24, 0x44f012) | the freed bytes now also ShowWindow([0x4d1050] = 历史情报 text panel, SW_HIDE) | none (modal in practice) | N/A | port windows are modal |
| 0x47c8b6 | 0x47c883: dirty-rect bookkeeping of a drawing surface; immediate mode ([0x4bc018] == 0) blits at once via 0x47c966 | jmp 0x4d418e: first InvalidateRect(whole client of [0x4bbec0], FALSE) (0x4d41a6), then 0x47c966 | forces WM_PAINT so the mod's paint-hook overlays (duel portraits 0x4d4315) are redrawn | N/A | Win32 repaint plumbing |
| 0x47ca76 | 0x47c966: blit of a surface to its window (BitBlt 0x47f41b) | jmp 0x4d4f20: while [0x4cf61c] ≠ 0 (only during duel op 0x62 = 0x4490da, set/cleared at 0x406d52) TransparentBlt the two 80×80 sge 2301+face duel portraits [0x4cf600]/[0x4cf604] at ([0x4cf60c],[0x4cf610]) / ([0x4cf614],[0x4cf618]) over the blitted image | duel portraits stay in colour over the result screen | PORTED | duel_layer.gd:768 draws both small portraits in colour every frame, also after result() (:683) greys the loser sprite |
| 0x47fb14 | 0x47fb13 rand(n) = MSVC rand() % n | jmp 0x4d966f: if [0x55ad00] ≠ 0 a deterministic sequence (r = s % (n+1); s = (s + r) % 100) | — | N/A | dead: [0x55ad00] is written only at 0x4dbe82 from checkbox 1007 of 环境设定, which the KANKYOU template does not contain (GetDlgItem → NULL → 0); no script writes 0x55ad00. Port rules.gd:9 = plain rand, matching the shipped behaviour |
| 0x47fb37 | 0x47fb32 chance(p) = rand(100) < p | jmp 0x4d96bd: if [0x55ad00] ≠ 0 LCG s = (s·0x204fb + 0x392) % 0x2e7, true iff p·0x2e6 ≥ s·100 | — | N/A | dead (as above); port rules.gd:15 |
| 0x483bdc | 0x483bb8: CRT __heap_init (HeapCreate + small-block heap 0x483ea0) | `mov [0x4d0048], edx; add [0x4d004c], edx`: takes the 72-byte person table (1024 × 0x48) from the heap region and stores its base | mod person table allocation | N/A | port: mem.gd:10/16 places the table at 0x01000000 with the pointer at 0x4d0048 |
| 0x483be2 | same | `add [0x4d004c], 0x12000` (end of the 0x12000-byte table; 0x4d004c is not read by code) | same | N/A | as above |

#### B6.2 Missing / partial features

##### B6 F1. Shop / warehouse dialogs 买进 327, 卖出 329, 装备 328, 持有道具一览 325 — mod changes — PORTED
Port: `ShopWindow`, `EquipWindow`, `PersonPanel`, `MerchantBox`, `ItemListWindow` (group 5).
No patch in this batch changes
prices, the goods lists, the sell rule or the 200-slot limit. Those are original code, summarised here for whoever
builds the dialogs [C]: shop record = min(GS+7 >> 1, 57) (0x4790ae) in the 0x28-byte table 0x4aeb68 (+4 u32 =
person whose face the merchant window shows, +8 16 equipment ids, +0x18 16 consumable ids, 0xff = none;
0x466b2d / 0x466c87); tabs 武器店 / 道具店; sell price 0x40c7a9 = price byte (+0x12)·300 >> 2, ×(lvl+1) >> 1 for
weapons/armour, 0xff → 0xffff; gold capped at 9 999 999 (0x40dbed); bag = 200 3-byte slots at GS+0x13, consumables
are stack counts at GS+0x26b; selling a non-treasure weapon/armour of level 3 always returns a fruit (0x40d51b: kind 0
→ 0x67, 2/8 → 0x62, 4/6 → 0x66, 10/12 → 0x63, 14 → 0x64, 16 → 0x65; message 0x486e40).

* **F1a 仓库装备现存量 "N/200"** (static 2000 next to the label "仓库装备现存量" in templates 325, 328, 329; 327 has
  none). N = number of bag slots whose id byte ≠ 0xff (0x4db000; consumable stacks are not counted), text "%d/200".
  Refreshed: 325 and 329 on open (0x4680ff, 0x46b7ed); 327/328 on every person change (0x469fb8; no visible effect in
  327); 329 after selling an equipment row (0x46b1f5, after the slot is freed; a bonus fruit is a stack, so N is still
  right); 328 after equipping from the warehouse (0x46bd89) and after taking a slot off (0x46bf9a). [C]
* **F1b Person selector (combobox 1098) of 买进 and 装备** (0x469dd7): entries = party members (P+0x2a == 0) among
  the 32 pids of 0x4dbdb0, in this order: 管毅0 秦琼8 尉迟恭3 程咬金1 罗成19 裴元庆17 姜松14 雄阔海26 伍天锡7
  伍云召5 魏文通43 单雄信4 尤俊达9 王君珂2 谢映登24 王伯当13 盛彦师10 丁天庆6 齐国远16 侯君集18 鲁明星12
  樊虎11 金成28 张公瑾25 罗士信15 魏征23 徐茂功22 柴绍21 鲁明月29 贾润甫20 柳周臣31 伍登27. Anyone else (e.g. 30
  上官狄, 32..42, ≥ 44) cannot be chosen there. The first entry is selected on open; 上一/下一 (0x403/0x404) step
  through the list and are disabled at the ends. Port: `PersonPanel`. [C]
* **F1c Portrait** of the chosen person in 买进/装备 (control 1076): sge.wa 301+face (face rule 0x4075a7, as in
  武将情报), loaded on every person change (0x46a05e). [C]
* **F1d Equipment panel** (Wepon / Armor / Sub Item, 0x46942a per slot): for pid 11 樊虎 the "Sub Item:" label is
  disabled (0x469433); Exp bar maximum 100, treasure 150, a treasure at Lv 9 250 (0x4695c6; the +100 is on the
  treasure branch only).
  Related rule from another batch (0x40790d → 0x4d9a91): 樊虎 may not equip any accessory (can_equip returns 0 for
  category 2), ported in `Person.can_equip`. [C]
* **F1e Merchant message window** (0x46d9a4: used for the sell confirmations "Lv.%2d的%s可卖%d。\n要卖掉吗？" /
  "%s的价格为%d。\n要卖掉吗？", the bonus message and the bag-full message; plain message box instead when 0x40b922 or
  0x41a0a4(0x496f38)): 456×120 window at client (16,56) of the main window (or (16,168) of the caller when
  [0x4cf306]); mod drawing (0x46d452/0x46d7e9/0x46d7fb): 120×120 sge portrait 301+face of person (shop record +4; the
  "warehouse full" message uses record +0) at
  (0,0), mark.wa bitmap 2 (8×80) at (136,29) and bitmap 3 at (448,29), black transparent; text area (144,29,304,80),
  ≤ 3 lines at x = 0x13 columns, y = 51/71/91. [C code; pixel placement of the text grid G]

##### B6 F2. 地形情报一览 (menu 情报 → 地形情报一览, dialog 335) — PORTED
Two tabs 地形效果 / 消耗机动力 (labels 0x486cc8), each a list with 28 columns: 地形 + 27 class-family columns whose
headers come from the mod table 0x558100 (5-byte strings: 英雄 刀兵 枪兵 轻骑 弓兵 间谍 格斗 重骑 僧兵 谋士 道士
双刃 锤骑 燕山 山贼 弓骑 雄师 统军 国师 力士 狄骑 战车 辎重 箭车 玄骑 倭兵 百姓). Rows (mod table 0x4d5fbc, site
0x46c75b): 平原 草原 树林 荒地 山地 雪原 桥梁 浅滩 沼泽 大河 城内 民居, each with its Mapatr.dll 100+t picture, its
name and small icons of the element strategies usable there (0x420ab6 / 0x420b17 / 0x420b98 / 0x420b42). Cell of
family f, terrain t: tab 1 (0x46cc12/0x46cc75): "--" if the family's move cost byte (+0x1e+t) is 0xff or the effect
byte ≤ 0, else effect byte shown as "8" (≤ 8), "9", "10", "11", "12" (≥ 12) with a colour per value; tab 2
(0x46cd5e/0x46cd90): move cost "%d", "--" for 0xff, colour by 1/2/3/other. [C] Port: `TerrainWindow`.

##### B6 F3. 历史情报 window (menu 情报 → 历史情报, 0x474db7 → 0x4d184c) — PORTED
Original: '目前无记录' if the chronicle buffer (u32 at 0x565800) is empty; '需要设置对话框花色' if the dialog skin
[0x492e20] ≥ 4; otherwise modal dialog 341 with a 376×374 text panel (centred, vertical
scrollbar: line ±1, page ± visible lines, thumb) and the checkbox 1031 按顺序显示 = byte [0x55eff4] (kept in the
.data3 block). Buffer entries are '&' + category byte + text, lines split at '\n'; the leading entry number is
hidden unless [0x55eff0]. Unchecked: four passes for categories 1, 2, 3, 4, each followed by an empty line, entries
in buffer order; checked: one pass over all entries in buffer order. Colours: category 1 black, 2 red, 3 blue,
other magenta, font weight 600 (0x4d1385). The menu is available in battle too.
Port: `HistoryWindow`, in the town and battle menus; the colours are lighter on the dark panel
([Deliberate differences](#deliberate-differences-port-design-keep-unless-asked)). [C]

##### B6 F4. Save allowed only when the scripts allow it (0x474c90) — PORTED
保存 (and the port's 存储进度) must check u32 [0x4ce004]: 0 → message "目前不可存盘。" and no save; ≠ 0 → save
dialog. [0x4ce004] is set by op 0x74 set_4ce004 (scripts use 0 and 1 around story sequences, e.g. R_07 before a
duel). Loading is not gated. The battle auto-save 0x4d4f80 also depends on it (other batch). [C] Port: main.gd
`save_menu`; a load sets the flag to 1 (`Game.load_game`). The port's own autosave is not gated
([Deliberate differences](#deliberate-differences-port-design-keep-unless-asked)).

##### B6 F5. Battle 策略 menu rules (dialog 282 list) — PORTED
* 房谋 (0x4664b9): after the base cost (strategy+0xe, ×2 during the second 连续策略 cast) and the original 节约MP
  reduction (effect 49: cost −= cost·v/100), if 房玄龄 (pid 0xb3) has a unit on the map, in the caster's side group
  (both slots < 35 or both ≥ 35) and in one of the 8 cells around the caster, cost = max(cost >> 1, 1) (a cost of 0
  also becomes 1). The row is enabled iff cost ≤ unit MP (0x4659f9). The same halving is applied when the MP is
  deducted (0x4d4a05, other batch). 房玄龄 does not halve his own costs (not adjacent to himself) [G]. [C]
  Port: `BattleActions.strategy_cost`.
* 秦琼 / 统军 (0x465d40): when the unit's class is 0x2b and its person id & 0xff == 8, the learn table of class 0x23
  is used for strategy 0x29 and every later id (the switch is sticky), class 0x2b's for ids < 0x29. With the current
  data this adds 补给 (Lv 28) and 救护 (Lv 40); 聚气 (Lv 5) is in both tables. The 武将情报 策略 page (0x4658c0) is
  unpatched, so 秦琼's page does not list them. [C] Port: `BattleActions.known_strategies`.
* Not mod patches, but in the same function (original code), and ported with them: 策略模仿 (effect 51: also the
  strategies the 4 orthogonally adjacent units know at their levels) and 节约MP. [C]

##### B6 F6. 樊虎's 交给 hands out warehouse accessories (0x467eb8) — PORTED
When the acting unit is pid 11 (0x4d287e) the item dialog lists, instead of consumables, one row per item id in
{0x2f, 0x35..0x56} (板角墨麒麟 and the accessories 犀皮盾 … 六军镜·技巧) present in any bag slot; the chosen one is
given to an adjacent ally (0x4d28f0) and the first bag slot with that id is emptied (0x4d9d4b); repeated until the
unit has acted or the player cancels (0x4d2ad1). [C for the list; the give rules belong to the 交给 audit]
Port: `BattleCommands.give_command` (the list is a choice menu).

##### B6 F7. 武将情报 button 100 技能说明 — MISSING by design (group 5 item 40, rules.md §11)
Template rect (300,252,54,10) in the 313×256 client: only a 13×4-DLU corner is inside, so it is barely visible but
clickable (rules.md §11 is corrected). State [0x4dc0ff]: on open, page change, 上一/下一 → 0 if the 兵种 page is
shown else 0xff. Enabled iff state ≠ 0xff and the person's skill is active (0x4dc5c5). Caption 技能介绍 (state 0) /
武将列传 (1) / ---- (other). Click: state = (state + 1) mod 2 and the 兵种 page's description box shows the
biography Fhua[922+pid] (both states; the class text comes back on the next refresh). [C]

##### B6 F8. 环境设定 and its persistence (0x474de8) — PORTED
Port: `Settings`, `SettingsWindow` (group 5).
The mod runs KANKYOU and then stores GS+0, GS+1 (switch bits: BGM 0x2000, SE 0x1000, …; the checkbox table
0x48b4d0), GS+8, GS+0x10 (message speed) and [0x4dbe25] (升级显示能力成长) in SAVEDATA\Niuniu.wa bytes 1..5
(0x41a1b0); 0x4e20ff restores them at start. Bytes 3..5 also serve as found-flags of items 0..2 (unused: these items
are not unique). [C]

