# Engine notes (main-thread RE, complements eex.md / rules.md / gfx.md)

Evidence = addresses in `wg2025/wagan.wa`. Decompilation with Ghidra headless: `tools/ghidra/gdec.sh OUT ADDR...`
(project in `extract/ghidra_proj`), capstone helpers `tools/rd_trace.py`, `tools/cases.py`.

## Script ops whose parser names are misleading
| op | parser name | real behaviour |
|---|---|---|
| 0x23 | play_music | **sound effect** (0x4157b4 → wave player 0x474a07): id 0..99 → `SeNN.wav`, 100..199 → `Se_m_(id-100)`, 200.. → `Se_e_(id-200)`; mode 1 once, 0 loop, 255 stop |
| 0x24 | play_sound | **BGM**: CD track = id + 2 (0x41581c → 0x4745fe), 255 = stop. Tracks = `SoundTrk/NN-AudioTrack NN.mp3` |
| 0x22 | set_weather | **play video** (0x42f754 → 0x41f862): 0 LOG.avi, 1 OPE.avi, 2 END.wmv, 3 PRE.wmv, 4.. 001.wmv… |
| 0x0f | screen_mode | ending reached: Niuniu.wa byte v = 1 (0x41a1b0), then credits/title (0x42b7c6) |
| 0x31 | actor_select | story: remove actor (0x428b22); battle: remove unit silently (mode 0 person, else side+rect) |
| 0x55 | unit_move | battle: a retreated unit (state 3) re-enters at (x,y) |
| 0x61 / 0x5f | duel_end / duel_start | **start fight** / **close** the duel screen (0x448ff5 / 0x4498e0); full duel spec in duel.md |
| 0x07 | test_pending | true once after toolbar 出征 (flag 0x4ae4c0, cleared) |
| 0x06 | battle_select_units | store sortie params (max u8 0x4b09ec, forced u32 0x4b09f0[5], flags u32 0x4b0a04[5]); arg0≠0 enables the town toolbar incl. 出征 ([0x55ac02]=1) |

## Other op semantics
* 0x09 delay: unit = 100 ms (tick = GetTickCount/50, waits 2n ticks; 0x42c522).
* 0x27 change_scene(mode, a1, a2, a3, a4): value = a1/a2/a3/a4 for mode 0/1/2/3; scene obj 0x4ac63c = {mode, value};
  `[0x55bfe4]==1` adds 0x100. Giji entry = value + {mode0: 0, mode1: 114, mode2: 40}; mode 3 = battle map value.
* 0x29/0x2a/0x2b: show / move / hide a person's portrait at screen (x, y).
* 0x2f: clear actors (0x426c32). 0x28 toggle: town interaction on/off (also disables 出征).
* 0x20: GS+0x11 = (GS+0x11 & 0xf0) | v; v==0xff clears bit 4 + low nibble (portrait-override story bits).
* 0x6a: game over (GHAI #7) → title. 0x0e (battle): game over. 0x49: battle finished (leave turn loop).
* 0x3a/0x37 resources: kind 0 gold (GS+0xc u32 ≤ 9,999,999), 1 GS+6 byte, 2 GS+0x12 (0..100); op 0 set 1 add 2 sub.
* 0x3b join(pid, mode, arg) → 0x40c28c: membership = person byte +0x2a (0 member, 0xff not).
  mode 0: level up to min(avg level of members among persons 0..25 + arg, 70); class tier by level (≥20, ≥40);
  mode 0xff/0xffff: leave, equipment back to the bag.
* 0x71 special_func (table 0x43646b): 0/4 → EV[4088] = rand(EV[4088]) (u32 @0x55efe0); 5 → Niuniu.wa[0] = EV[2699];
  1 → 0x436490, 2 → 0x4363fd, 3 → mod 0x4d4f80, 6/7 no-op (ids 1–3 unused by the scripts).
* 0x78 data_transfer(ev, dir, id, field): field table 0x4d0a97 (kind, offset, size): f0 u16 0x565000[id] (story
  sprite id), f1 face (+4), f2-6 stat words, f7 HP base, f8 MP base, f9-13 raw abilities, f14 +0x27, f15 +0x29,
  f16 +0x2a (membership), f17 class, f18 level, f19 exp, f20-26 equipment; f27 byte var 0x55a000[id];
  f28-41 battle unit of person id: +4 slot, +6 x, +7 y, +0xd flags, +0xe AI code, +0x10 HP (u32), +0x14 MP,
  +0x18..0x1d buffs, +0x1e status.
* 0x36 test_attr attr 7 = the person's battle-unit HP; **no unit → value 0xff** (unit index), not 0.
* 0x15 unit_say: floating text at the unit. 0x51: all on-map units fully healed/cleared (victory). 0x59: reward
  gold = avg_level*100 + 700 + base, 3 items (+levels), treasures recorded in Niuniu. 0x5c: blink unit ×3.
  0x5d: turn-limit set/extend. 0x6c: copy person bytes 0x11..0x33 (except 0x26/0x2a). 0x6d: move/re-enter a unit
  relative to another unit (offsets > 40 mean negative). 0x21 map_mark: undo a recorded terrain change
  (table ctx+0x19, 250 × {x, y, new, old, patch}). 0x4b: player deployment entry position (battle) or mod table
  0x55e9d8 (story, when [0x55e9d4] ≠ 0).
* Sortie builder 0x41856a: protagonist first iff all 9 dwords at 0x4b0a04 ≠ 0 (default 0xffff); forced persons
  that are party members; if max (0x4b09ec) > count → selection UI; result list u32[] @0x48b350 (0xffff end).
* Duel setup 0x44999f: the player-side fighter (party member, else a unit index < 35) is always side 1.
* 0x2e test_adjacent(a, b, loose) (0x411a54 → 0x45afca): battle only; both persons' units in state 2 with HP > 0,
  b in one of the 8 cells around a (offset table 0x48df68: N E S W NE SE SW NW); b ≥ 0x200 = unit selector;
  loose = 0 additionally requires each to be able to attack the other (0x45b2a8 both ways).
* Unit selectors (0x45b371): 0x400 any, 0x401 unit index < 35 (player+friend), 0x402 enemy; state 2 and HP > 0.

## Endgame structure (verified with autoplay)
* R_54 is the Chang'an hub: 东/西/南/北门 sections `goto_scenario` 109/111/113/115 → R_55..R_58 (gate prep: support
  hiring; 确定支援/退出宿力界面 enable 出征 via op 0x06, 取消支援/全权委任 return to the hub with goto 107);
  each gate's 出战 → its battle (R_58 → goto 114 → S_57), whose aftermath returns to R_54.
* Ending chain in R_54 scene 1, sections 28 → 23 (flags 936 → 1413 … 1418). Section 28 sets flag 699 unless all
  four gate ratings EV[3901..3904] == 5 and flags 931/932/978/979 (→ 980), or via 722/723 without 729 (R_06/R_07
  choices). Flag 699 → section 27 ends with videos 011 + END and op 0x0f(2) = the poisoned-wine ending;
  otherwise the chain continues to 真忠义千古流颂 / 大响马百世传奇 / クリアおめでとう！.

## Story (RPG) scenes
* Actor projection (0x4272c5, camX 60, camY 25, W 200): foot point (8(x−y)+312, 4(x+y)−8z−152); 48×64 frame
  drawn at (sx, sy−64); background drawn at y = 40 of the 640×480 screen.
* Actor sprite id = u16 0x565000[pid] (initialised in .data3, changed by data_transfer field 0).
* Action table 0x48b920 (9 bytes): action 0 = walk cycle frames [0,1,0,2]; 1..17 = single frame action+2; 18 = none.
* Toolbar (0x41973c): button 3 = 出征 → sortie builder 0x41856a; on success the toolbar is hidden, interaction
  is switched off (0x42c858(0) = GS mode word 0, not a scene change) and pending flag 0x4ae4c0 = 1. Every
  sortie-enabled scene has its own `test_pending` section ("出战") whose body leaves the scene or jumps
  (e.g. R_58 → goto_scenario 114, R_36 sets story flag 868). Buttons 0/1/2 open dialogs 0x461d18(1/0), 0x461cb0.

## Portraits
GetFace 0x4075a7: pid 0 → face; else face + 7; pid 1/4/8/35 switch to fixed faces by GS+0x11 bits.
Large = sge.wa bitmap 301+f (120×120), small = 2301+f.

## Sound ids used by the engine
hit 35 / critical 36 (0x40437b), no damage 30/31 (0x4043fa), level-up 11 (0x4074ff), equipment level-up 13,
retreat 16 (0x441814), vanish 17, appear 42/15 (0x4570ee), unit turn 6, terrain change 19, revert 18,
UI cursor/confirm/cancel 0/1/2, game over 40, duel 6/7/8/31/33/37.

## Misc
* Videos 001-040/END: first byte zeroed (0x30 → 0x00); mod code 0x4dd000 restores it before playing.
* Title picture (0x42bd90): GHAI 0, or 12 + Niuniu[0] (13..15) once an ending is recorded.
