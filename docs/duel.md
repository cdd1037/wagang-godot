# Duel screen (单挑) — reimplementation spec

Evidence: `wg2025/wagan.wa`. Decompiled with Ghidra headless (scratch: `extract/gd/duel_*.c`), and the
mod trampolines were checked with capstone (`tools/disx.py`). Several original functions are split by `jmp`
patches into `.text` padding (0x406c82..0x406d6b) and `.text2` (0x4d4xxx). The timelines below follow the
jumps.
Tags: **[C]** read directly from the code. **[I]** inferred. Unmarked statements are [C].

Conventions
* **tick** = `GetTickCount()/50` → **1 tick = 50 ms** (`0x403340(&0x4b1b18,n)` + `0x42c4e0` = wait n ticks).
  "skippable wait n" = `0x42c646(n)`: n × 100 ms. A mouse click ends it early (0x42c56b).
* **SE n** = sound effect `SeNN.wav` (wave player `0x47467a(&0x4b69b0, n, 1)`: stop the current SE, then play).
  The step sounds use mode 0, which does not restart an SE that is still playing.
* **BGM t** = CD track t (`0x4745fe(&0x4b69b8, t)`), file `SoundTrk/tt-AudioTrack tt.mp3` (script BGM id = t − 2).
* Sprite sheets (docs/gfx.md §3): **MOV** = `~zl1g.dat` 48×48 ×11, **ATK** = `~gtl.dll` 64×64 ×12, **SPC** =
  `~kvr.db` 48×48 ×5. Entry index = `0x43fc48(unit)` (gfx.md entry rule).
* **All fighter sprites are drawn at 2×.** A 48 px frame becomes 96×96 and a 64 px frame becomes 128×128.
  The upscaler `0x430a76` is described in §8.
* Palette indices are raw (draw mode 4). Colours come from the shared range of every game palette:
  0x12 #fff, 0x13 #eee, 0x14 #ddd, 0x15 #ccc, 0x16 #bbb, 0x17 #aaa, 0x18 #999, 0x19 #888, 0x1a #777, 0x1b #666,
  0x1c #555, 0x1d #444, 0x1e #222, 0x1f #000, 0x28 #f00, 0x2a #c30000, 0x3a #00f, 0x3c #0000c3, 0xac #001f7b,
  0xad #c25502. The game shows only the high nibble of each channel.
* **No randomness**: no rand/chance call is reachable from any duel routine [C]. The outcome is fully
  scripted. The duel does **not** read or change HP/MP and has **no HP bars**. Its only gameplay effect is the
  EXP award (§6).

## 1. Script ops

| op | parser name | handler | args | meaning |
|---|---|---|---|---|
| 0x68 | duel_setup | 0x417535 → 0x44999f | personA, personB, **backdrop** (3rd arg: passed on the stack through trampoline 0x4175ab to 0x4486f4 `[ebp+8]` → GHAI index) | build duel, play intro (§3.1) |
| 0x60 | duel_say | 0x4175fc → 0x406cf5 → **0x449480** | side, text, act | fighter **appears** (fade from white), optional action `act` (0 = none), then speech (mode 1) |
| 0x61 | duel_end (misnamed) | 0x4176a8 → **0x448ff5** | — | **start the fight**: redraw, "胜 负" banner |
| 0x63 | duel_say2 | 0x417701 → **0x4431af** | side, text, mode | speech bubble (empty text = erase that side's bubble) |
| 0x64 | duel_action | 0x4177b6 → **0x448524** | side, act 0..15 | single-fighter action (§4) |
| 0x65 | duel_action2 | 0x417826 → **0x448394** | side(attacker), kind 0..4, arg | one attack with an outcome (§5.1) |
| 0x66 | duel_action3 | 0x4178c6 → **0x44847b** | side, kind 0..2, arg | special attacks (§5.2) |
| 0x62 | duel_62 | 0x4176bc → 0x406d52 → **0x4490da** | **winner side** | loser greyed out, EXP computed (§6) |
| 0x5f | duel_start (misnamed) | 0x4175e8 → **0x4498e0** | — | close the duel, restore BGM, give EXP (§7) |

* "side" is 0 or 1 (any non-zero value = 1). The routines take `A = this+4+0x2c*(side!=0)` and O = the other record.
* Text args are copied with `0x4179a5`: GBK text, cut at the first `"\n&"`.
* Script usage counts: exchange kinds 0:46, **1:1255**, 2:357, 3:210, 4:194 (arg 0 / arg 1 ≈ 1303 / 759).
  Specials 0:82, 1:278, 2:29. say2 mode 1:1040, 0:208. duel_say act 0:110, 9:71, 10:30, 6:14, 8:5, 12:2.
  Actions 14 and 15 are never used. 0x62: arg 1 ×19, arg 0 ×7. **All 116 setups use backdrop 5.**

Typical script order: `68 setup` → `60 say side0` → `60 say side1` → `61 open` → actions, exchanges and say2 …
→ (`62 winner`) → `5f close`.

### Side assignment (0x44999f) [C]
`member(p)` = person byte +0x2a == 0 (party member).
* If A is a member: side0 = B, side1 = A.
* Else if B is a member: side0 = A, side1 = B.
* Else: if A's unit index < 35 (player/friend slots), side0 = B, side1 = A. Otherwise side0 = A, side1 = B.

The **player-side fighter is always side 1**. Side 1 stands on the right, has its portrait bottom-right and
faces left. Side 0 stands on the left, has its portrait top-left and faces right.

`0x4495f8` fails (duel object `+0` = 0, nothing is drawn) if either person has no unit on the map:
`0x477adc` returns 0xff, and it only works during a battle. `0x449480` checks `+0`. Ops 0x61 and 0x64–0x66 do
not check it. **Godot: skip all duel ops while the duel is inactive.**

## 2. Duel object 0x4b3c80

The fighter record is R = `this+4` (side 0) or `this+0x30` (side 1), 0x2c bytes each.

| R+ | side0 abs | side1 abs | type | meaning |
|---|---|---|---|---|
| 0x00 | +0x04 | +0x30 | ptr | person record (`[0x4d0048] + pid*0x48`) |
| 0x04 | +0x08 | +0x34 | ptr | battle unit (`0x4b2c50 + idx*0x24`) |
| 0x08 | +0x0c | +0x38 | u32 | person id |
| 0x0c | +0x10 | +0x3c | u8 | **visible / sprite-cache slot**. 0xff = not shown (set at setup). Op 0x60 sets it to `side` (0/1). 0x443aed draws the fighter only when ≠ 0xff. 1 → cache `work+0x1c000`, otherwise `work+0x20000` |
| 0x0d | +0x11 | +0x3d | u8 | unit index (MOV cache `0x4aab80 + idx*0x6300`) |
| 0x0e | +0x12 | +0x3e | u8 | **facing**: 1 = right, 3 = left. Setup: side0 = 1, side1 = 3 |
| 0x10 | +0x14 | +0x40 | i32 | portrait x |
| 0x14 | +0x18 | +0x44 | i32 | portrait y |
| 0x18 | +0x1c | +0x48 | i32 | speech bubble x |
| 0x1c | +0x20 | +0x4c | i32 | speech bubble y |
| 0x20 | +0x24 | +0x50 | i32 | **fighter x**: left edge of the 96 px sprite. Not clamped; only the drawing is clamped |
| 0x24 | +0x28 | +0x54 | i32 | size of the last drawn image: 0x60 (96) or 0x80 (128) |
| 0x28 | +0x2c | +0x58 | u32 | original MOV-cache mirror flag of the unit (unit byte +0xd bit 8), restored at close |

| abs | meaning |
|---|---|
| +0x00 | active flag (result of 0x4495f8) |
| +0x5c/+0x5d | view width/48, view height/48. +0x62 = 13, +0x63 = 8. +0x5e/+0x5f = ((w−13)/2, (h−8)/2). +0x60/+0x61 = +0x5e+13, +0x5f+8 (cell rectangle of the box; not read by any duel routine examined) |
| +0x64 | saved BGM track (GS+4) |
| +0x68 / +0x6c | box left L / right L+624 |
| +0x70 / +0x74 | box top T / bottom T+384 |
| +0x78 / +0x7c | horizontal clip for fighters (= L, L+624) |
| +0x80 | **Y = T+144**: top of a 96 px fighter. A 128 px image is drawn at Y−16 |
| +0x84 | EXP award (set by 0x62, used by close) |

### Work buffers [C]
* `0x4aab68`: 624×384 composed duel background, with portraits and names.
* Work buffer `0x4ae4c8`: 2× slots of 128×128 at +0, +0x4000, … +0x18000. +0x1c000 / +0x20000 hold the last
  image of side1 / side0. +0x24000 holds the 624×128 **fighter strip** (background rows Y−16 … Y+112).
  +0x37800 is the raw sheet entry and +0x43800 is the mirror temp.
* `0x4aeb50` = Kao.wa atlas.

## 3. Screen layout

**Box** = 624×384 at (L, T), where `L = viewW/2 − 312` and `T = viewH/2 − 136`. viewW/H = map-view size
(`0x4b4250` +0x14/+0x18). The map view is initialised by `0x451ab5(x=0, y=56, 624, 384)`, so the box sits
centred on the battle map view. **With that default view it covers the map view exactly: box = (0,56)–(624,440)
on the 640×480 surface.** [I] Other window sizes re-centre it. All coordinates below are relative to (L, T).

| element | position (rel. to L,T) | size | notes |
|---|---|---|---|
| backdrop | (0,0) | 624×384 | GHAI.WA[setup arg 3] (always 5 = grey stone relief, indices 19..31 only → palette independent) |
| fighter side0 | x = **168**, y = **144** | 96×96 (128×128 at x−16, y−16) | facing right |
| fighter side1 | x = **360**, y = **144** | same | facing left; 96 px gap between the fighters (centre 312) |
| portrait side0 | (24,24) original 64×80 Nao face; **mod: 80×80 sge `2301+face` at (16,24)** | | |
| portrait side1 | (536,280) original; **mod: (526,280)** | | |
| name side0 | centred on x = 56, y = 112 (under the portrait) | 16 px font | |
| name side1 | centred on x = 568, y = 256 (above the portrait) | | |
| bubble side0 | (120,32) | 320×64 | tail ◄ (Kao 0x198c0, 16×16) at (104,56) |
| bubble side1 | (184,288) | 320×64 | tail ► (Kao 0x199c0) at (504,312) |
| fighter strip | rows 128..255 | 624×128 | restored before every fighter redraw (it erases the banners) |

* The **mod portraits** (0x4d4e8c / paint hook 0x4d4315, 0x4d4f20) are loaded with `LoadImage(2301+GetFace(p))`
  from sge.wa. They are TransparentBlt'd (black key) **over** the 8-bit surface on every WM_PAINT while
  `[0x4cf608]==1`. The flag is set at the end of the setup frame and cleared by the map redraw at close
  (0x452737 → 0x4d4222). The original 64×80 face blit at 0x443a58 is NOPed.
* **Name** (0x443773 mode 1 → 0x4403aa): person name with digits removed (0x407757, ≤15 bytes). It is printed
  with the standard text object 0x492f38 on an 8 px column grid. The column is `((px+32)>>3) − len/2`, where
  len = GBK byte count. Text colour is 0x12 white. The outline/border colour comes from the unit's army
  (unit byte +5): 0 player → 0x2a, 1 friend → 0xad, 2/3 enemy → 0xac. That this colour is an outline is [I].

### 3.1 Setup sequence (op 0x68) — 0x4486f4 + mod chain 0x4d420c / 0x448aa4 / 0x406cxx / 0x448b4f

1. **Frame.** `0x473202(L,T,624,384,1,0)` fills the box with the Kao 48×48 tile **0x1abc0** (grey
   bird medallion), 13×8 tiles. It then draws a 3 px drop shadow **outside** the box: rows B+i from L+i to R
   and columns R+i from T+i to B+2, i = 0..2, colours 0x18, 0x1a, 0x1c (inner → outer). A 1 px 0x13 line runs
   along y = T−1 and x = L−1.
   * Inner bevel, bottom/right, i = 0..11: colour `0x19 − (i>>1)`. Line y = B−12+i from L to R−1, and line
     x = R−12+i from T to B−1.
   * Inner bevel, top/left, i = 0..7: colour 0x13 for i < 3, else `i+0x11`. Line y = T+i from L+i to R−1, and
     line x = L+i from T+i to B−1. For i ≥ 5 both lines are shortened by `3(i−4)` px.
2. `[0x4cf608]=1` (portrait overlay on). Save BGM (`+0x64 = GS+4`), then **BGM 10**. Wait 10 T.
3. Side-0 portrait plus the **big intro name**, see below. Wait 20 T.
4. **"单挑" banner** (0x443534): 宋体 bold, 32×64 cell. Rect (245,160)–(309,224); the text is 128 px wide.
   Layers are offset +3/+2/+1 in colours 0x1f/0x18/0x15, then the main layer at +0 in 0x12. Wait 20 T.
5. Side-1 portrait plus big intro name. **Wait 75 T** (3.75 s).
6. Blit GHAI[arg] at (0,0), then the bevels again:
   * bottom/right: colour `0x1f − i` (black inner → 0x14 outer), i = 0..11;
   * top/left: 0x13 for i < 3, 0x14 and 0x15 for i = 3, 4, and `0x16 + 3(i−5)` for i ≥ 5 (lines shortened as in
     step 1).

   Draw both portraits and both small names, then capture the box into `0x4aab68` and the fighter strip into
   `work+0x24000`.
7. Facing: side0.dir = 1 and mirror its MOV cache to face right. side1.dir = 3, cache faces left
   (`0x43fd34(unit, right?)`).

Fighters are **not** drawn by setup. They appear through op 0x60.

**Big intro name** (0x443773 mode 0): 宋体 bold, cell 32×64. The width is len×32 (len = GBK bytes), left-aligned.
* side0 at (120,32).
* side1 right-aligned: `x0 = 536 − len*32 − 32` (ends at 504), y = 288.

Layers (offset → colour):

| offset | side0 | side1 |
|---|---|---|
| +7 | 0x18 | 0x18 |
| +6 | 0x18 | 0x18 |
| +2 | 0xac | 0x2a |
| +1 | 0x3c | 0x2a |
| +0 (main) | **0x3a blue** | **0x28 red** |

### 3.2 Fighter appear + speech (op 0x60, 0x449480)
`R.visible = side`. MOV[8] (stand, in the current facing) is upscaled 2×. It is drawn 16 times at (x, Y), 1 T
each, **brightened by 15, 14, … 0** (§8 flash), so it fades in from a white silhouette in 800 ms. Wait 5 T.
If `act ≠ 0`, run action `act` (§4). Then say2(side, text, mode 1).

### 3.3 Fight start (op 0x61, 0x448ff5 + 0x406cdb + 0x44908e)
Wait 20 T. Blit the saved background, then draw side1 and side0 (cached images). **"胜 负" banner**
(0x443653): 宋体 bold 48×96, rect (192,144)–(432,240), layers +3/+2/+1 in 0x1f/0x18/0x15, main 0x12 white.
Wait 20 T. Restore the strip and redraw both fighters, which erases the banner. Wait 10 T.

### 3.4 Speech bubble (op 0x63 / end of 0x60) — 0x4431af(side, text, mode)
* **Empty text:** restore background rows 0..127 (side0) or rows 256..383 (side1). This erases that bubble.
  Return.
* **Otherwise:** draw the bubble at (bx, by) = R+0x18/+0x1c:
  * left cap Kao **0x19ac0** at (bx, by);
  * right cap Kao **0x19ec0** at (bx+304, by). Both are 16×64 white rounded ends; the atlas export shows them
    as 64×16;
  * white fill (0x12) over (bx+16, by)–(bx+304, by+63);
  * tail: side0 ◄ at (bx−16, by+24), side1 ► at (bx+320, by+24).
* **Text:** black (0x1f), 16 px game font, starting at column `(bx+16)>>3`. Lines go at y = by+5, by+25,
  by+45 (20 px pitch), **3 lines per page**; lines are split by `\n`. There is no wrapping (≤ 288 px = 18
  full-width characters per line).
  * Typewriter: 1 T (50 ms) per character. A click prints the rest at once. "、" (A1A2 or Big5 A142) adds
    1 T; Big5 A143/A153/A154/A17E add 6 T (leftovers).
  * After each page, a **timed hold**, not a click wait. mode 0: no hold. mode ≠ 0: speed option
    `s = GS+0x10` (0x4b0770+0x10) → skippable wait 5/12/20 (0.5/1.2/2.0 s) for s = 0/1/2, none for s ≥ 3.
  * The next page re-fills the white area first.
* The bubble **stays on screen** after the op. It disappears only on the next say2 for the same side, an empty
  say2, a full redraw (0x61, 0x62) or close.

## 4. Single-fighter actions (op 0x64, 0x448524 → per-act routine)

Notation:
* A = actor, O = other. `fwd = +1` if A.dir == 1 (right), else −1.
* "frame" = restore the fighter strip, draw O's cached image, draw A's image (A is drawn last, on top).
* Directional frames (MOV 4/5/8, ATK 8–11, SPC 2) are the left-facing sheet frames, **mirrored when the
  fighter faces right**. MOV 4/5/8 use the unit's MOV cache, which the duel keeps mirrored to match R.dir.
  MOV 0–3, 9, 10 and SPC 0, 1, 3, 4 are never mirrored (except the explicit mirror in act 14/15).
* 96 px images are drawn at (A.x, Y); ATK (128 px) at (A.x−16, Y−16).
* Drawing is clamped to `L ≤ x ≤ L+624−size−1`.

| act | routine | name | sequence (frame : delay) | SE | Δx |
|---|---|---|---|---|---|
| 0 | 0x443ce6 | stand | MOV8, static | 8 | 0 |
| 1 | 0x444ccf | turn around | dir ^= (1↔3), mirror MOV cache, MOV8 static | 6 | 0 |
| 2 | 0x444a7c | **advance** | 4 steps: MOV4, MOV4, MOV5, MOV5, 1 T each; before each step x += 24·fwd | step SE each step (see note) | **+96·fwd** |
| 3 | 0x444939 | small step forward | 4 steps MOV4, 4, 5, 5, 1 T each, x += 8·fwd | step SE once at start | +32·fwd |
| 4 | 0x444dad | step back (still facing) | 4 steps MOV4, 4, 5, 5, 1 T each, x −= 8·fwd | 6 once | −32·fwd |
| 5 | 0x443dff | cheer | SPC4, static | 8 | 0 |
| 6 | 0x443f51 | guard pose | SPC2 (dir), static | 8 | 0 |
| 7 | 0x4440f1 | hurt pose | SPC3, static | 8 | 0 |
| 8 | 0x4442ea | raise weapon / ready | ATK8 (dir), static, 128 px | 8 | 0 |
| 9 | 0x444496 | swing | ATK8, 9, 10, 11, 1 T each | 7 at start | 0 |
| 10 | 0x4446d1 | double swing | 2 × [SE 7; ATK8–11, 2 T each] | 7 ×2 | 0 |
| 11 | 0x444243 | kneel (weak) | MOV9, static | 8 | 0 |
| 12 | 0x444bbf | panting | MOV9, 10, 9, 10, 9, 10, 8 T each (ends on MOV10) | 8 at start | 0 |
| 13 | 0x443d8d | vanish | blank (fully transparent) image; stays invisible until A's next action | — | 0 |
| 14 | 0x444eea | war dance (unused) | see below | BGM 21 | net +88 (always +x/−x, not fwd) |
| 15 | 0x445943 | look around (unused) | see below | BGM 20 | 0 |

**Step SE** (0x43f4d3 → 0x43f38b with position 0xffff) is chosen by the actor's class family (0x4077d0):
* **SE 24**: 英雄, 轻骑, 重骑, 双刃, 锤骑, 燕山, 弓骑, 雄师, 统军, 狄骑, 玄骑 (families 0, 3, 7, 11, 12, 13, 15,
  16, 17, 20, 24; mounted);
* **SE 25**: 战车, 辎重, 箭车 (21–23);
* **SE 23**: all other (infantry) families.

It is played with no-restart (if the same SE is still playing, it continues).

The static acts are a single frame, after which the routine returns immediately; the hold time comes from
script delays. Contact distance after one advance from the start positions: side0 at 168..264, side1 at
360 → 264, so the fighters touch.

**act 14** (0x444eea):
1. BGM 21. Spin slots = SPC0, SPC2, SPC1, SPC2-mirrored (down, left, up, right); cheer = SPC4.
2. Spin 17 frames (slot i%4) at 4 T.
3. +4 T, then cheer, then 40 T.
4. 9 × (x−8, spin, 4 T); +4 T, cheer, 20 T.
5. 9 × (x+8, spin, 4 T); +4 T, cheer, 40 T.
6. MOV4/5/9: 8 × (x+16, MOV4/5 alternating, 2 T); MOV9, 40 T; 4 × (x−8, MOV9, 8 T); 40 T.
7. ATK entry (loaded with index `&0xff`, a bug for entries ≥ 256). Slots ATK3, ATK11, ATK7, ATK11-mirrored.
   20 × (x−4, slot i%4 at 128 px, 2 T); 40 T; 18 × (x+4, …, 2 T); 40 T.

**act 15** (0x445943):
1. BGM 20. Wait 20 T.
2. 4 rounds alternating pairs MOV0/1 (down) and MOV2/3 (up): down, up, down, up. Each round has 6 frames
   alternating its pair, with delays 4, 8, 8, 4, 4, 4 T, then +10 T.
3. 2 rounds the same way with MOV4/5 in cache facing, then MOV4/5 mirrored.

## 5. Attacks

### Common pieces
* **0x445c81(A)**: loads ATK8–11 of A (mirrored if A faces right) into slots 0–3.
* **Wind-up 0x445e14(A, O, arg)**. Each frame redraws O's cached image. The archer test is
  `0x4400a2(A.unit)` = table 0x4400df[family] == 0, i.e. 弓兵, 弓骑兵, 箭车.

| | frame 1 | frame 2 |
|---|---|---|
| melee, arg = 0 | ATK8, 2 T | ATK9, 1 T |
| melee, arg ≠ 0 | **SE 33**, ATK8 drawn 12× brightened 0..11 (charge glow), 1 T each | ATK9, 1 T |
| archer, arg = 0 | ATK8 + **SE 37**, 1 T | ATK9, 8 T |
| archer, arg ≠ 0 | ATK8 + SE 37, 1 T | **SE 33**, ATK9 glow 0..11, 12 T |

* **Flash**: image brightened by 12/15 (`0x4303c0(img, 96, 96, 12)`), i.e. a near-white hit flash.
* Defender frames assume O faces A: SPC2 (guard) is mirrored when A faces **left**. SPC3 (hurt) is not
  mirrored.
* `p = +32·fwd(A)`.

### 5.1 Exchange (op 0x65) — 0x448394(side=attacker A, kind, arg)

All kinds call 0x445c81 and then the wind-up(arg). After that come **6 frames of 1 T**. Each frame restores
the strip, draws O, then draws A (ATK10, ATK11, then ATK11 ×4). arg only switches the **charge glow** in the
wind-up.

| kind | routine | name | O during frames 0–1 | O during frames 2–5 | SE | net O Δx |
|---|---|---|---|---|---|---|
| 0 | 0x44620b(…,0) | **hit** | SPC3 hurt, **flashed**, at O.x + p | SPC3 at O.x | **36** on frames 0 and 1 | 0 |
| 1 | 0x44620b(…,1) | **parried** (most common) | SPC2 guard at O.x + p, no flash | SPC2 at O.x | **31** on frames 0 and 1 | 0 |
| 2 | 0x446613 | **parried and pushed back** | SPC2 flashed; O.x += p on frames 1 and 2, += p/2 on frames 3 and 4 | SPC2 | 31 on frames 0 and 1 | **+96·fwd** |
| 3 | 0x4469eb | **knocked flying** | O's MOV4 drawn at O.x + 16·fwd, with O.x += 40·fwd on frames 0 and 1; frame 2: O.x += 16·fwd, MOV4 | MOV5 (frames 3–5) | **7** on frames 0 and 1 | **+96·fwd** |
| 4 | 0x446db6 | **dodge behind attacker** | O not drawn on frames 0–4 (vanishes) | frame 5: O.x −= 192·fwd, O.dir = A.dir (MOV cache re-mirrored), MOV8 | 7 on frames 0 and 1 | **−192·fwd** (lands 96 px behind A if A was in contact) |

Kind 4 detail: O's MOV8 is taken after the facing flip. O ends up facing A's back. A is drawn first, then O.

There is no "who wins" logic. Each op is one blow with a scripted outcome.

### 5.2 Special (op 0x66) — 0x44847b(side=A, kind, arg)

| kind | routine | name | sequence | SE |
|---|---|---|---|---|
| 0 | 0x445c81 + 0x44711f | **lunge** | Wind-up with no glow (arg is ignored there). 6 frames of 1 T. Frame 0: A.x += p and O.x += p. Frames 0–1: O drawn **flashed** at O.x + p (arg = 0: SPC3 hurt; arg ≠ 0: SPC2 guard) while A shows ATK10, ATK11. Frames 2–5: O normal at O.x, A ATK11. Net: both move +32·fwd | arg 0 → 36, arg ≠ 0 → 31, on frames 0 and 1 |
| 1 | 0x445c81 + 0x4475be | **afterimage dash-through** | No wind-up. 8 frames of 1 T, O drawn first. f0: ATK8 at A.x and A.x+p (ghost), A.x += 2p, ATK8. f1: ATK8 at A.x−2p (+p), ATK9 at A.x (+p), A.x += 2p, ATK9. f2: **impact**, O at O.x+p (arg 0: SPC3 flashed; else SPC2 unflashed); ATK8 at A.x−4p (+p), ATK9 at A.x−2p (+p), ATK10 at A.x (+p), A.x += 2p, ATK10. f3: O as in f2 without SE; ATK10 at A.x−2p (+p), ATK11 at A.x. f4–7: O normal at O.x, ATK11. **Net A Δx = +192·fwd** (passes O) | f2 only: arg 0 → 36, else 31 |
| 2 | 0x448004 | **clash and cross** (arg ignored) | A uses its MOV4/5; O uses its MOV4/5. 8 steps of 1 T: steps 0–3 A.x += 24·fwd and O.x −= 24·fwd; steps 4–7 ±48. When A.x == O.x (step 3 from the start positions), draw both **flashed** (A's MOV5, O's MOV5); otherwise A's MOV(4+i%2), O's MOV(4+i%2). Then wait 20 T. Net ±288: **the fighters swap sides and keep facing outward**. Scripts follow with act 1 for both | 31 at the crossing |

## 6. Result (op 0x62) — 0x4490da(winner) with mod flag `[0x4cf61c]=1` during the call [C]

1. Wait 20 T.
2. Blit the full saved background. This erases both bubbles.
3. Grey the loser's portrait: `0x443a0d(loser, gray=1)` captures 80×80 at (px, py) and converts it to grey.
4. Restore the strip and draw the winner (cached image).
5. Draw the loser's **last image converted to greyscale** (`0x43087a`: average of the 4-bit RGB channels). It
   stays cached, so it remains grey.

**In the mod**, the sge portrait overlay is painted in colour over the greyed surface area, so the loser's
portrait probably still shows in colour [I].

**EXP** (only when winner = side 1 **and** the side-1 unit is player army, unit byte +5 == 0). lw / ll =
levels (person +0x2c) of the winner / loser:
```
exp = lw < ll ? min(32 + 8*(ll-lw), 200) : max(sat_sub(32, 4*(lw-ll)), 10)
if loser pid == battle boss (Reader 0x492f90 + 0x3d06): exp *= 2
this+0x84 = exp
```
This is the same as the normal kill formula (rules.md §8.1) but without the equipment multiplier. Wait 20 T.

## 7. Close (op 0x5f) — 0x4498e0 [C]

1. Restore each unit's MOV-cache mirroring to its original state (R+0x28). Set `this+0 = 0`.
2. **Skippable wait 30** (3 s).
3. Redraw the battle map (`0x453b13`). This removes the box and switches off the portrait overlay
   (`[0x4cf608]=0`).
4. Restore the BGM (`this+0x64`).
5. If the side-1 unit is player army: `0x450984(unit1, unit0, 0, 0, exp=this+0x84, 0, 0, 1)` →
   `0x450036`. This is the **standard EXP popup** on the map next to the unit; it is the same one as after an
   attack. The displayed gain is capped so that exp ≤ 100. If exp = 0, nothing is shown.
6. Then `SetExp(person, person.exp(+0x2d) + exp)` with the **whole** award (`0x408950`: while the sum is ≥ 100 it
   levels up once (0x4d0331 → 0x40898f → 0x4073b8) and subtracts 100, so up to 4 level-ups against a boss; no gain
   at level ≥ 70). Only the popup's bar stops at 100.

The 0x450984 call does **not** touch HP or retreat anyone. The loser's fate (retreat, death, …) is handled by
the following script ops.

## 8. Image helpers (for faithful rendering)

* **2× upscale 0x430a76(src, dst, w, h)**. p = source pixel; neighbours r(ight), d(own), dr. Output block:
  `a b / c e`, all = p. Averages are taken in RGB444 (`(x+y)/2`, max 15) and mapped back through the
  RGB444→index LUT.
  * If x isn't the last column and p ≠ 0 and r ≠ 0: `b = e = avg(p, r)`.
  * If y isn't the last row and p ≠ 0 and d ≠ 0: `c = avg(p, d)`.
  * If `a ≠ b` or `a ≠ c`: `e = avg(b, c)`, and if dr ≠ 0 (and not on an edge): `e = avg(dr, e)`.
  * Second pass, for transparent p: `a = avg(up, left)`, `c = avg(down, left)`, `b = avg(up, right)` and
    `e = avg(down, right)`, each only when both neighbours are opaque. This anti-aliases diagonal edges.
  * **Godot:** nearest 2× plus this edge smoothing, or nearest 2× as an acceptable approximation.
* **Brighten 0x4303c0(img, w, h, k)**: every opaque pixel's RGB444 channels become `min(c+k, 15)`. Used for the
  hit flash (k = 12), the charge glow (k = 0..11) and the appear fade (k = 15..0).
* **Grey 0x43087a**: opaque pixels → `v = (r+g+b)/3`, giving (v, v, v).
* Index 0 is transparent in every sprite and Kao piece.

## 9. Open points
* Exact surface origin of the box when the window is resized. The map-view geometry handling in
  0x47b4c2 / 0x47bff3 was not fully traced. The default (624×384 view at y = 56) is [I].
* Semantic names of SE 6/7/8/23/24/25/31/33/36/37 were not listened to. engine_notes lists 35/36 as
  hit/critical and 30/31 as no damage.
* Mod portraits: whether a missing sge `2301+face` bitmap falls back to anything was not checked. Whether the
  overlay really hides the grey portrait is [I].
* Text-object font size (16 px) and outline semantics of `0x40ed0a(1)` / `0x40ecf4(colour)` are [I].
