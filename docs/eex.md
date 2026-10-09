# EEX scenario scripts (`R_xx.wagan`, `S_xx.wagan`)

Reverse-engineered from `wg2025/wagan.wa` (renamed Ekd5.exe of Koei's 三国志曹操传 / CCZ, Sui–Tang mod).
Parser: `tools/eex.py` → `game/assets/scripts/<file>.json` (+ `opcodes.json` schema) and
`extract/eex_txt/<file>.txt` (indented disassembly). **All 117 files parse with zero errors**: every scene,
section and IF-block length field agrees exactly with the parsed instruction stream, every goto target is an
instruction boundary, and all strings decode as GBK. 3,078,167 instructions in total.

Address conventions below: VAs in wagan.wa (ImageBase 0x400000). "Handler" = function in the opcode table.

---------------------------------------------------------------------------------------------------------

## 1. Files and chapter progression

| item | value |
|---|---|
| scenario counter | `u8 GS+7` where `GS` = game-state object @0x4b0770 (get 0x418e10, set 0x418d60, ++ 0x418e30) |
| file name | loader @0x417eda..0x418090: `n = GS+7`; name = `R_%c%c.WAGAN` if n even, `S_%c%c.WAGAN` if n odd, digits `'0'+n/20`, `'0'+(n%20)/2` |
| meaning | n = 2k → `R_k` = **story / town (RPG-mode) part of chapter k**; n = 2k+1 → `S_k` = **battle of chapter k** |
| order | R_00 → S_00 → R_01 → S_01 → … → S_57 → R_58 (ending). (The task description had R/S the other way round; the file contents confirm R = story (actors 0x30–0x35, click tests 0x2d), S = battle (0x44–0x47 unit placement, victory tests 0x42/0x43).) |
| next file | when the script reports "finished" (internal code 4, see §4) the manager calls `GS+7++`, loads the next file, resets the reader (vtable[0] 0x41023c) and re-initialises (0x417966, 0x417980). |
| jump | op 0x11 `goto_scenario v` sets `GS+7 = v` and ends the file → next file loaded is `v+1`. |
| new game | starts at n = 0 (R_00). |

Loading: 0x417eda builds the name, reads the whole file (0x418f5c/0x419184) and calls `Reader::load` 0x410273 on
the global reader object @0x492f90.

## 2. Container format

```
0x00  char[4]  "EEX\0"
0x04  u8 major = 1, u8 minor = 2       (loader accepts major<=1, minor<=2)
0x06  TLV list {u16 type; u16 len; u8 data[len]} terminated by type 0.
      All shipped files: just "00 00 00 00".  type 1 = font/charset name passed to an import (if present the
      reader sets flag +0x34, which makes every instruction AND every section start with one extra u16 – unused).
0x0A  u32 scene_offset[N]    N = (scene_offset[0] - 0x0A) / 4    (absolute file offsets)
```

**Scene** (场景) at `scene_offset[i]`:
```
u16 nsections
section[nsections]:
    u16 section_len                    // bytes after this field up to the next section
    <condition list>                   // instructions, terminated by op 0x00 (END); no IFs allowed
    u16 body_len                       // bytes after this field
    <body block>                       // instructions, terminated by op 0x00; may contain nested IF blocks
```

**Instruction**: `u16 opcode` followed by the opcode's fixed list of *tagged* parameters (see §5).
Parameter encoding (READP = 0x4183f7):
```
u16 tag ; value      tag 0x04 -> u32 (little endian; also used as signed for goto)
                     tag 0x05 -> NUL-terminated GBK string (no padding)
                     any other tag -> u16
```
The tag must equal the type the handler asks for (mismatch → handler returns 5 = error). The only untagged
values are the flag-number lists of op 0x05 (raw u16, "type 1").

Mod extension (patch at 0x4d0b87): for tags **0x02, 0x38, 0x39** a u16 value in **0xEFFF..0xFFFE** is not a
literal but reads extended integer variable `EV[0xFFFE - v]` (EV = u32[4096] @0x55b000). 0xFFFF stays literal
(= "none/-1"). `eex.py` emits such args as `{"var": idx}`.

**IF blocks**: op 0x01 is immediately followed by exactly one *condition instruction* (any opcode – a test op,
op 0x03 ELSE, or even op 0x02 comment which is always true), then `u16 len` and a child block of `len` bytes
that ends with op 0x00. Lengths are authoritative: 4 child blocks (R_20, R_21, R_22) contain an extra `00 00`
before their end, jumped over by a `goto +2` (see op 0x76) – a parser must use the length, not the first END.

JSON layout (`game/assets/scripts/X.json`):
```
{file, kind: "story"|"battle", scenario_index, version, tlv,
 scenes: [{index, offset, sections: [{index, offset, title, conditions:[ins...], body:[ins...]}]}]}
ins = {op, name, args:[...]}      args: ints, strings, {"var":n} (EV indirection), lists (op 05/46/47)
  op 0x01: + cond: ins, end: index of first body instruction after the child block (= skip target)
  op 0x76: + target: {scene, section, index, off}   (gotos may jump into OTHER sections/scenes)
  (run with --offsets to also get the byte offset "off" of each instruction)
```
`body` is a flat list in file order; the child block of an IF at index i is `body[i+1 .. end-1]` (its last
element is the block's END). `title` = text of a leading op 0x02 comment in the condition list (editor label).

## 3. Variables and other script-visible state

| storage | address | script access |
|---|---|---|
| boolean flags (变量) | `Reader+0x38 + 4*i` (u32 each, room for 2048) in the reader @0x492f90 → @0x492fc8 | op 0x05 test, op 0x0b set, op 0x0a/0x44 clear 0..255. Numbers seen: 0..~1100. Flags 0..255 are "local" (cleared at chapter starts), higher ones persist. Saved with the game. |
| choice result | `Reader+0x2038` | written by op 0x12 (1-based), tested by op 0x13 |
| event parameters | `Reader+0x1c` → array of small buffers (slot 0: u32, 1: clicked person, 3: 12 bytes, 5: victory, 6: defeat) | set by engine before running the script; read by ops 0x2d/0x42/0x43 |
| ext. int vars EV (mod) | u32[4096] @0x55b000 | op 0x77 arithmetic, 0x79 compare, 0x78 transfer to/from game data, and as indirect u16 args (§2) |
| pointer table (mod) | u32[2048] @0x563000 (addresses into game memory) | op 0x77/0x79 kinds 0/1/2/3 |
| byte vars (mod) | u8[] @0x55a000 | op 0x75 |
| trigger flags | `u16 GS+0` @0x4b0770 | bit 0x20 = "RPG click event" while running a click; tested by op 0x2d |

## 4. Execution model (interpreter @0x4100a1 / 0x4105a8 / 0x41084e, manager 0x4180c1)

Reader object (global @0x492f90, vtable 0x486610): `+0x04` current scene index, `+0x08` byte counter,
`+0x0c` read pointer, `+0x10` opcode of a suspended (yielded) instruction or 0xFFFF, `+0x14` depth at which
execution is suspended or -1, `+0x20` file buffer, `+0x24` number of sections of the current scene,
`+0x28` active (0 when the file is finished), `+0x2c` "inside a section body", `+0x30` header size (10).

Every handler returns a status: **0** condition false, **1** ok / true, **2** yield (wait – the instruction
started something asynchronous; execution resumes with the *next* instruction once the engine says it is
done), **3** END (op 0x00), **4** IF (op 0x01), **5** error, **6** ELSE (op 0x03), **7** "next scene"
(op 0x0d), **8** abort section (op 0x0c), **9** end of file (op 0x11).

### 4.1 Section selection (`select` 0x4100a1) – event polling
Called by the manager every time the script gets control (see 4.4):
1. If an instruction is suspended (`+0x10 != 0xFFFF`): ask the owner (vtable+0x0c) whether the async action is
   finished; if not → return "busy"; else clear and **resume** (go to 4.2 with the saved position).
2. If the file is finished or a body is already running → nothing.
3. Seek to the current scene, read `nsections`. For **every** section in order: execute its condition list
   until END; the section qualifies if every instruction returned 1 (instructions returning other codes,
   e.g. comments, don't veto). **The last qualifying section wins** (its post-condition position is kept).
4. If one qualified → run its body (4.2) at depth 0.

Typical condition instructions: 0x05 flags, 0x79 int-var compare, 0x2d clicked person (R), 0x3f turn,
0x40 phase/side, 0x25/0x26/0x41 positions, 0x36 attribute, 0x42/0x43 victory/defeat, 0x07, 0x6e random.
Sections normally guard themselves with a flag in their condition (`0x05 [..] [F]`) and set F in the body,
so each event fires once.

### 4.2 Block execution (`run_block(depth)` 0x4105a8, `run_child(exec, depth)` 0x41084e)
```
run_child(exec, depth):              # entered with the pointer at a "u16 len" (body_len or IF len)
    len = u16
    if not exec: ptr += len; return 0          # skip the block
    return run_block(depth)

run_block(depth):
    last = 1; next_scene = 0; end_file = 0
    loop:
        r = execute(next instruction)
        if op == 0x76 (goto) and depth > 0: return 0     # goto leaves the current nesting level (see 0x76)
        switch r:
          0,1,3: pass
          2: remember (opcode, depth) for resumption; return 2         # yield to engine
          4: (IF) c = execute(condition instruction)               # same dispatcher
                  if op==0x76 and depth>0: return 0
                  if c == 0: last = 0;  if c == 1: last = 1;  if c == 5: return 1
                  take = (c == 1) or (c == 6 /*ELSE*/ and last == 0)
                  x = run_child(take, depth+1)
                  if x == 0: pass  else: return x (1..5)     # 3/4 propagate "scene/file finished"
          5: return 1 (error: abort block)
          6: return 1 (ELSE without IF)
          7: next_scene = 1
          8: return 5  (op 0x0c: abort the whole section body)
          9: end_file = 1
    until r == 3   # END of this block
    if next_scene or (depth == 0 and nsections_of_scene == 1):
        scene++; if scene >= nscenes: active = 0; return 4 (file finished) else return 3
    if scene >= nscenes or end_file: active = 0; return 4
    return 0
```
Consequences:
* ELSE chains: `01 <test> len{..} 01 03 len{..}` – the ELSE block runs iff the most recent IF test *at the same
  level* returned 0. There is no ELSE-IF; nesting is used instead.
* A scene with **one** section is a linear cut-scene: when its body ends, the next scene starts (selection runs
  again on the new scene). The last scene ending finishes the file → next chapter file.
* A scene with **several** sections is an event loop: after a body ends nothing advances; the next poll
  re-selects. It is left only via op 0x0d (next scene) or op 0x11 (jump to scenario).
* Op 0x0d marks "next scene" but the current block still runs to its END; the scene change then propagates up
  through all levels (return 3) and terminates the body.
* Op 0x76 goto: `ptr += signed offset` (relative to the end of the goto instruction). At depth 0 execution
  simply continues at the target; at depth > 0 the current `run_block` returns 0, i.e. the parent level
  continues at the target. The mod's editor uses this for loops (`L: IF c { ...; goto L }`) and for "break".
  Targets may lie in other sections (shared subroutine-like code) – execution then continues there with
  *dynamic* nesting (an END encountered at runtime always closes the innermost *running* level).
  An interpreter must therefore keep a runtime stack of levels, not rely on static nesting.

### 4.3 Yield / async
Instructions that start animations/dialogs return 2 (e.g. dialogs 0x14, actor moves 0x32, delays 0x09,
`wait_frame` 0x1e, scene change 0x27 in some modes). The engine keeps drawing frames; when the owner's
"busy" check (vtable+0x0c of the reader; the RPG driver also refuses to run while any actor still moves, see
0x4182a4) reports idle, execution resumes after the yielding instruction at the same depth.

### 4.4 Who runs the script
* **Story files (R, RPG mode)**: driver 0x429733(mode, person).
  `mode 0` (every tick): if no actor (0x80 actors @0x49cf68, 64 B each) is still walking/animating →
  `0x4180c1` (select + run). `mode 1` (player clicked an actor): 0x4181dd sets `GS+0 |= 0x20`, stores the person
  in event slot 1, runs select+run once, then restores `GS+0`. Sections for talking to NPCs therefore have
  conditions like `0x2d test_clicked <person>` (+ flags).
* **Battle files (S)**: the battle module calls `0x4180c1` in loops at fixed checkpoints (0x40bbc7 game loop,
  0x44c638 / 0x44ec60 / 0x44ed52 / 0x44f0c7 inside the battle turn logic: battle start, phase start, after each
  unit action/move, after deaths) – each call polls all sections of the current scene. Scene 0 of an S file is
  the deployment (0x4a/0x44/0x45/0x46/0x47/0x4b …), scene 1 the event loop with many sections (turn N events
  via 0x3f, positional triggers via 0x25/0x26/0x41/0x2e, victory 0x42, defeat 0x43, …), later scenes the
  aftermath; leaving the battle is done with 0x0d/0x11.
* Victory/defeat: op 0x42 is true when the battle's default victory condition holds (designated boss
  defeated or all enemy slots 35..114 gone); op 0x43 likewise for defeat (event slot 6).


## 5. Opcode table

Sorted by total frequency (R = story files, S = battle files, F = number of files using it). "Layout" lists the parameter tags in order (tag 04 = u32, 05 = string, others u16). Handler = address in table @0x410a3e (≥0x4d0000 = mod code in .text2). Return: T = test (0/1), Y = may yield (2).

| op | cn | en | R | S | F | layout | args → meaning / semantics | ret | handler |
|---|---|---|---|---|---|---|---|---|---|
| 00 | 结束 | end | 530345 | 58998 | 117 | — | END of the current block / condition list. | 3 | inline |
| 01 | 条件 | if | 520145 | 52926 | 117 | — | IF: next instruction is the condition; then u16 len + child block. Child runs if cond returned 1, or cond is ELSE (0x03) and the previous IF test at this level returned 0. | 4 | inline |
| 34 | 武将动作 | actor_action | 420835 | 0 | 59 | 02 0d | args: person, action → 0x428b87(person\|0x1000, action, 0xFFFF): set RPG actor animation/pose (actor +0x2c), keep facing. The most frequent opcode (used for every expression/gesture in story scenes). | 1 | 413567 |
| 79 | 整型变量比较 | test_int_var | 201017 | 25357 | 112 | 52 04 56 52 04 | Mod integer compare: A = value(arg0 kind, arg1), B = value(arg3 kind, arg4) (kinds as op 0x77 src); arg2 mode 0: A == B, 1: A >= B, 2: A < B (unsigned). Errors → false. | T | 4d5070 |
| 05 | 测试变量 | test_flags | 215424 | 5926 | 117 | tag35 n, n×raw u16, tag35 m, m×raw u16 | Flag test: all n flags listed first must be set AND all m flags listed second must be clear (flag i = Reader+0x38+4i). | T | 4117a1 |
| 77 | 整型变量运算 | int_var_op | 148009 | 68516 | 117 | 51 04 53 52 04 | Mod integer arithmetic. arg0 dst kind: 0 = *(u32*)PT[i] (pointer table @0x563000), 1 = PT[i], 2 = EV[i] (@0x55b000); arg1 = i. arg2 op: 0 +=, 1 -= (0x4d6768), 2 =, 3 *=, 4 /= (unsigned), 5 %=. arg3 src kind: 0 = immediate arg4, 1 = *(u32*)PT[arg4], 2 = PT[arg4], 3 = &PT[arg4], 4 = EV[arg4], 5 = &EV[arg4]. | 1 | 4d03de |
| 0B | 变量赋值 | set_flag | 209150 | 5892 | 116 | 04 27 | Set boolean flag: flag[arg0] = (arg1 != 0). | 1 | 4142b2 |
| 02 | 注释 | comment | 98957 | 17178 | 117 | 05 | Comment/label string (editor section titles such as "战前过渡", or labels used as always-true IF conditions, e.g. "表情变化(…)"). | 1 | 411fdc |
| 30 | 武将出场 | actor_appear | 85991 | 0 | 59 | 02 04 04 2b 0d | args: person, x, y, dir(0-3), action(0-18). RPG (0x40b922()==0): create actor id person\|0x1000 at grid cell (x,y) (0x42909d→0x428eb0; actor table 0x80×64 B @0x49cf68, 3×3 cell footprint on a 100×100 cell grid; dir&3; action>18→0). Battle: 0x4b5df0.0x4570ee(person, x, y) – make a (hidden/reserved) unit appear on map tile (x,y). | 1 | 413010 |
| 78 | 数据存取 | data_transfer | 35644 | 17726 | 117 | 04 54 02 55 | Mod. args: var, dir, index, field. dir 0: EV[var] = FIELD[field](index); dir 1: FIELD = EV[var] (writing field 33 = battle-unit HP also kills the unit if ≤0 via 0x4121b0). Field table @0x4d0a97 (base, offset, size 0=u8/1=u16/2=u32): 0:person+2 u16 (redirected to u16 @0x565000[index]), 1:person+4 u16, 2:+17 u16, 3:+19 u16, 4:+21 u16, 5:+23 u16, 6:+25 u16, 7:+28 u32, 8..26: person bytes +32,+33,+34,+35,+36,+37,+39,+41,+42..+52; 27: byte var @0x55a000[index]; 28..41: battle unit (slot of person index, 0x24-byte records @0x4b2c50) +4,+6,+7,+13,+14 u8, +16 u32, +20,+24,+25,+26,+27,+28,+29,+30 u8. Person record = 0x407bb3(index). | 1 | 4d05f9 |
| 14 | 对话 | dialog | 37946 | 7561 | 117 | 05 | Dialogue (modal, returns after the player clicks through). String = one or more segments "&<speaker>\n<text>"; a new segment starts at the next "&". Speaker: a name → person looked up by name (0x41eec0); in battle "&\n" (empty) = the special "current unit" (0x45602b), "&NN" (1–2 digits) = player slot NN (skipped silently if that slot is not on the map). Text: lines split by "\n", expanded by 0x4179a5 (name/variable substitution). RPG or no speaker: portrait dialog window 0x42d5f1(text, person, 0x20); battle with speaker: bubble at the unit (0x45965d). | 1 | 413661 |
| 09 | 延时 | delay | 31468 | 4812 | 117 | 04 | Blocking delay: arg × 100 ms (timer 0x4b1b18 set to now + 2·arg ticks, 1 tick = GetTickCount/50; pumps messages 0x47eac4 while waiting). | 1 | 415b0f |
| 31 | 武将消失 | actor_remove | 28156 | 720 | 105 | 2c 02 04 04 04 04 03 | args: mode, person, x1, y1, x2, y2, side. RPG: remove actor person (0x428b22). Battle: mode 0 → remove unit person (ids 0x400..0x402 = special "current unit" refs resolved by 0x45602b) via 0x45a7b7(person,1,0); mode≠0 → remove all units of side (0xFFFF→6 = all) inside rect (x1,y1)-(x2,y2) via 0x45a80f. | 1 | 41311c |
| 33 | 武将转向 | actor_set | 27113 | 0 | 59 | 02 0d 2b | args: person, action, dir → 0x428b87(person\|0x1000, action, dir): set actor animation/action (0xFFFF = keep) and facing (0xFFFF = keep) (actor +0x2c action, +0x2e dir, +0x1a frame reset), redraw. | 1 | 4134c9 |
| 16 | 信息 | info | 18168 | 368 | 115 | 05 | Information message box without portrait: text (expanded by 0x4179a5) → 0x42d5f1(text, 0xFFFF, 0x20). Mod: if u32 @0x55effc ≠ 0 the text is appended to a mod text buffer instead (0x4d1679/0x4d0f9b) and the flag is cleared. | 1 | 413a57 |
| 32 | 武将移动 | actor_move | 16962 | 1339 | 106 | 40 02 04 04 04 2b | args: mode(0xFFFF→0), person, slot, x, y, dir. RPG: walk actor person\|0x1000 to cell (x,y) then face dir (0x429159); if the NEXT instruction is also 0x32 it returns 1 immediately (moves run in parallel), otherwise it yields until the walk ends. Battle: mode 0 = unit person, mode 1 = player slot (<15) occupied → its person; 0x4b5df0.0x459487(person, x, y, dir) moves the unit along a path to tile (x,y). | Y | 4132d4 |
| 23 | 背景音乐 | play_music | 16399 | 1464 | 116 | 1e 04 | Music: args track, mode → music player 0x4b69b0.0x474a07(track, mode): mode 0 = stop then play once, 1 = play looping, 0xFF = stop, other = play with mode. Tracks are CD-audio numbers, mapped by mp3list.txt to SoundTrk/NN-AudioTrack NN.mp3. | 1 | 4157b4 |
| 03 | 否则 | else | 10535 | 4531 | 111 | — | ELSE marker, only valid as the condition of an IF. | 6 | 4112df |
| 1E | 等待 | wait_actors | 12638 | 0 | 57 | — | Yield: returns 2; the RPG driver only resumes the script when no actor is still moving/animating (0x4182a4), so this means "wait until all walks/animations finish". | Y | 413ef1 |
| 76 | 跳转 | goto | 8144 | 3129 | 111 | 04 | Goto: ptr += (signed)arg, relative to the end of this instruction. At depth > 0 the current nesting level is left (parent continues at the target). Used for loops/breaks; targets can be in other sections. | 1 | 4d027d |
| 69 | 提示 | popup | 10048 | 821 | 114 | 05 | Notice/popup box: 0x4335d0(3, text) → message box style 3 (0x42f699). Mod: text starting with "\|" is shown in the battle-object panel (0x4b3d08.0x4d6366). | 1 | 413a05 |
| 08 | 设定结果 | set_result | 9422 | 116 | 117 | 2e | GS+2 (u16) = arg (0x40d277); if the screen mode object 0x4ac63c reports mode 2 also calls 0x426ba3. Used in story files with 0/1 (probably "screen/scene result" or "allow menu" flag – meaning not fully resolved). | 1 | 41431e |
| 50 | 战场状态 | unit_status | 0 | 8761 | 58 | 02 46 26 26 | (not yet analysed) |  | 416129 |
| 24 | 音效 | play_sound | 5933 | 2038 | 117 | 09 | Sound effect: arg 0..254 → 0x4b69b8.play(arg+2) (wave list Se*.wav); 0xFF = stop sound (and GS byte via 0x418d20(0xFF)). | 1 | 41581c |
| 6E | 概率测试 | test_random | 4781 | 2125 | 100 | 04 | Random test (clamped to 100): 0x47fb32(arg) – true with probability arg %. | T | 410f85 |
| 17 | 地名显示 | place_name | 4914 | 0 | 59 | 05 | Mod: show place-name / caption banner (e.g. "第七回合", "潞州监狱  牢房") via 0x40bb78(text) after expansion. | 1 | 4d0fbf |
| 4D | 战场状态变化 | unit_change | 0 | 4563 | 58 | 41 02 04 04 04 04 04 03 2f 18 30 04 04 | args: mode(0 person/1 player-slot/2 rect), person, slot?, x1, y1, x2, y2, side(0xFFFF→6 all), status(0/1/2→status idx 0/3/6, 0xFFFF none), arg0x18, arg0x30, hp_delta, mp_delta. Applies 0x4b5df0.0x45aa5c(person, value, what, 1) (what 0..5 = status-ailment bytes +0x18..+0x1d, 6 = ?, 7 = HP, 8 = MP; shows effect 0x479a01) to one unit or (mode 2, via 0x45ade5) to all units of side in the rectangle. Battle only. | 1 | 4150e7 |
| 4C | 战场指令4C | unit_op_4c | 0 | 4165 | 58 | 40 02 04 | (not yet analysed) |  | 414f42 |
| 1C | 淡出 | fade_out | 4080 | 58 | 117 | — | (not yet analysed) |  | 413ebd |
| 26 | 测试武将区域 | test_unit_in_area | 0 | 3995 | 57 | 02 04 04 04 04 | (not yet analysed) |  | 411c36 |
| 27 | 场景切换 | change_scene | 3746 | 58 | 117 | 2d 0c 1a 1c 15 | (not yet analysed) |  | 413d13 |
| 1D | 淡入 | fade_in | 3744 | 58 | 117 | — | (not yet analysed) |  | 413ee2 |
| 2D | 测试点击 | test_clicked | 3738 | 0 | 57 | 02 | (not yet analysed) |  | 4119e7 |
| 0C | 中止 | exit_section | 3470 | 227 | 69 | — | Abort the running section body immediately (like return); next poll re-selects. | 8 | 4143a4 |
| 2F | 指令2F | op_2f | 3515 | 0 | 59 | — | (not yet analysed) |  | 413652 |
| 4F | 战场指令4F | unit_op_4f | 0 | 3286 | 58 | 02 02 2b 26 26 26 | (not yet analysed) |  | 415f65 |
| 4B | 指令4B | op_4b | 1880 | 1029 | 100 | 04 04 04 2b 26 | (not yet analysed) |  | 415e31 |
| 64 | 单挑动作 | duel_action | 0 | 2768 | 42 | 26 4c | (not yet analysed) |  | 4177b6 |
| 4E | 战场指令4E | unit_op_4e | 0 | 2337 | 58 | 2c 02 04 04 04 04 03 07 02 04 04 | (not yet analysed) |  | 4146d4 |
| 53 | 战场指令53 | unit_op_53 | 0 | 2296 | 58 | 2c 02 04 04 04 04 03 26 | (not yet analysed) |  | 41557b |
| 65 | 单挑动作2 | duel_action2 | 0 | 2062 | 41 | 26 4d 26 | (not yet analysed) |  | 417826 |
| 36 | 测试属性 | test_attr | 0 | 1945 | 58 | 02 23 04 24 | (not yet analysed) |  | 4112e9 |
| 38 | 属性变更 | set_attr | 941 | 839 | 95 | 02 23 34 04 | (not yet analysed) |  | 412006 |
| 55 | 战场移动 | unit_move | 0 | 1734 | 45 | 40 02 04 04 04 2b | (not yet analysed) |  | 41591c |
| 13 | 测试选择 | test_choice | 1392 | 126 | 82 | 04 | Test last choice: Reader+0x2038 == arg. | T | 411fa5 |
| 3D | 获得物品 | get_item | 856 | 605 | 93 | 17 49 26 02 | args: item (0xFFFF or > 0x67: nothing), level (0xFFFF→0), flag, person. Level 0 for a weapon/armour = automatic from the party level L (0x40c14f: mean of the 15 highest levels of persons 0..25 in the party): normal (L mod 18)/6+1 below 48 else 3, treasures L/7+1 ≤ 10; at or above the item's maximum (3, treasures 10) the item is fully grown (exp 0xFF). Outside a battle: message "得到了…" (0x42f699(2)) then into the bag (0x40d79c / 0x40da45 for consumables); in a battle 0x45991b(item, level, flag, person, 1). Unique items (+0x18) are recorded via 0x41a1b0(item+3, 1). | 1 | 4143c2 |
| 40 | 测试阵营 | test_side | 0 | 1443 | 58 | 48 | (not yet analysed) |  | 4116ee |
| 21 | 地图标记 | map_mark | 0 | 1346 | 22 | 04 04 10 26 26 | (not yet analysed) |  | 413efb |
| 2C | 字幕 | caption | 1301 | 0 | 47 | 05 26 26 26 | (not yet analysed) |  | 417315 |
| 63 | 单挑对话2 | duel_say2 | 0 | 1248 | 41 | 26 05 26 | (not yet analysed) |  | 417701 |
| 3A | 资源变更 | set_resource | 927 | 109 | 54 | 28 34 04 | (not yet analysed) |  | 4149f7 |
| 41 | 测试区域部队 | test_units_in_area | 0 | 927 | 55 | 03 04 24 3f 04 04 04 04 | (not yet analysed) |  | 41149d |
| 3B | 加入/离队 | join | 810 | 90 | 57 | 02 0e 3e | (not yet analysed) |  | 4148fe |
| 58 | 指令58 | op_58 | 0 | 875 | 48 | 42 43 44 04 04 26 26 | (not yet analysed) |  | 4166eb |
| 18 | 标题显示 | title_text | 789 | 0 | 58 | 05 | Show title banner text via 0x40bb48 (e.g. chapter sub-title "命运的疆陲", duel caption "枪兵  对  管毅"). | 1 | 413b09 |
| 12 | 选择 | choice | 621 | 59 | 82 | 05 02 | Choice menu: arg0 = up to 3 options separated by "\n" (prefixed "1." "2." "3."), arg1 = (0xFFFF→0) cancel/default option. Result index+1 stored in Reader+0x2038. | 1 | 411db9 |
| 15 | 战场对话 | unit_say | 0 | 657 | 58 | 02 02 05 | (not yet analysed) |  | 413911 |
| 25 | 测试武将位置 | test_unit_at | 0 | 630 | 52 | 02 04 04 | (not yet analysed) |  | 411b50 |
| 48 | 战场装备设定 | battle_equipment | 0 | 517 | 55 | 02 3b 49 3c 49 3d | args: person, weapon code, weapon level, armour code, armour level, accessory code (0xFFFF→0). Stored in the person's ally/enemy deployment entry (slots 15..114) at +0x14/+0x18/+0x1c/+0x20/+0x21 and applied when the battle starts (0x44cc85 → 0x4429f9 per slot): code 0 = default equipment for the class and level (0x407fe7), 1 = take off, ≥ 2 = item code−2 (weapon) / code+0x24 (armour) / code+0x33 (accessory) if it is that kind of item and the class may use it (0x407dec); level 0 = automatic. | 1 | 412dd6 |
| 74 | 设定扩展值 | set_4ce004 | 471 | 2 | 55 | 26 | Mod: u32 @0x4ce004 = arg. | 1 | 4d00c9 |
| 1F | 镜头移动 | scroll_to | 0 | 472 | 31 | 04 04 | (not yet analysed) |  | 414257 |
| 06 | 出场选择(战中) | battle_select_units | 462 | 0 | 53 | 2e 04 38 38 38 38 38 39 39 39 39 39 | (not yet analysed) |  | 415b45 |
| 6B | 指令6B | op_6b | 0 | 447 | 12 | 04 04 4b 26 | (not yet analysed) |  | 41405b |
| 28 | 指令28 | op_28 | 446 | 0 | 57 | 36 | (not yet analysed) |  | 4174a2 |
| 0D | 场景结束 | next_scene | 112 | 299 | 111 | — | Calls 0x42c858(0); marks "advance to next scene" – the current block finishes, then the scene index is incremented and the body terminates. | 7 | 4143ae |
| 66 | 单挑动作3 | duel_action3 | 0 | 389 | 38 | 26 4e 26 | (not yet analysed) |  | 4178c6 |
| 2E | 测试相邻 | test_adjacent | 0 | 364 | 57 | 02 02 26 | (not yet analysed) |  | 411a54 |
| 3F | 测试回合 | test_turn | 0 | 353 | 53 | 04 24 | (not yet analysed) |  | 411652 |
| 5B | 指令5B | op_5b | 0 | 311 | 29 | 04 04 04 04 26 | (not yet analysed) |  | 416cbb |
| 75 | 字节变量赋值 | set_byte_var | 254 | 10 | 52 | 02 50 | Mod byte var: u8 @0x55a000[arg0] = arg1. | 1 | 4d100d |
| 49 | 界面49 | ui_49 | 0 | 262 | 58 | — | (not yet analysed) |  | 415795 |
| 37 | 测试资源 | test_resource | 252 | 0 | 20 | 28 04 24 | (not yet analysed) |  | 4118d4 |
| 60 | 单挑对话 | duel_say | 0 | 232 | 42 | 26 05 4c | (not yet analysed) |  | 4175fc |
| 6A | 指令6A | op_6a | 207 | 0 | 36 | — | (not yet analysed) |  | 416dfa |
| 0E | 界面0E | ui_0e | 0 | 164 | 57 | — | (not yet analysed) |  | 415890 |
| 0A | 清除局部变量 | clear_flags | 105 | 43 | 102 | — | Clear flags 0..255, clear mod byte array @0x569f00[0..114], u16 @0x55ac06 = 0, @0x55e9d4 = 1. Used at the start of most files. | 1 | 415ad7 |
| 59 | 指令59 | op_59 | 0 | 137 | 52 | 04 17 49 17 49 17 49 26 | (not yet analysed) |  | 41688b |
| 04 | 测试是否 | test_yes_no | 133 | 0 | 54 | 26 | Ask the player "可以吗？" (Yes/No box via 0x42f699(1,"可以吗？")); true if answer == arg (1 = yes, 0 = no). | T | 411748 |
| 19 | 胜利条件 | victory_cond_text | 0 | 124 | 58 | 05 | (not yet analysed) |  | 413bd1 |
| 29 | 指令29 | op_29 | 120 | 0 | 24 | 02 04 04 | (not yet analysed) |  | 417143 |
| 1A | 战斗目标 | battle_goal_text | 0 | 116 | 58 | 05 | (not yet analysed) |  | 413c0e |
| 5F | 单挑开始 | duel_start | 0 | 116 | 42 | — | (not yet analysed) |  | 4175e8 |
| 61 | 单挑结束 | duel_end | 0 | 116 | 42 | — | (not yet analysed) |  | 4176a8 |
| 68 | 单挑设定 | duel_setup | 0 | 116 | 42 | 02 02 4f | (not yet analysed) |  | 417535 |
| 20 | 指令20 | op_20 | 103 | 12 | 26 | 4a | (not yet analysed) |  | 416fd8 |
| 46 | 友军出场设定 | battle_allies | 0 | 113 | 53 | 20 × [02 26 04 04 2b 3e 45 07 02 04 04] | (not yet analysed) |  | 4125c5 |
| 71 | 特殊功能 | special_func | 92 | 11 | 61 | 04 | (not yet analysed) |  | 436436 |
| 6D | 指令6D | op_6d | 0 | 95 | 39 | 40 02 04 02 04 04 2b 26 | (not yet analysed) |  | 410cfc |
| 11 | 剧本跳转 | goto_scenario | 63 | 8 | 20 | 37 | Jump to scenario: GS+7 = arg; ends the file → the next file loaded is scenario arg+1 (R/S by parity). | 9 | 415c67 |
| 6F | 失去物品 | lose_item | 70 | 0 | 8 | 17 | Remove one item arg (items < 0x57: search inventory 0x4b0783 (3-byte entries), then persons' equipment slots +0x2e/+0x31/+0x34; 0x57..0x67: decrement stack count @0x4b09db[arg-0x57]). Returns 1 if something was removed. | T | 411046 |
| 47 | 敌军出场设定 | battle_enemies | 0 | 68 | 58 | 80 × [02 26 26 04 04 2b 3e 45 07 02 04 04] | (not yet analysed) |  | 4129a4 |
| 2A | 指令2A | op_2a | 59 | 0 | 21 | 02 04 04 | (not yet analysed) |  | 4171ff |
| 44 | 战场初始化 | battle_init | 0 | 58 | 58 | — | (not yet analysed) |  | 412230 |
| 45 | 战场设定 | battle_settings | 0 | 58 | 58 | 26 26 04 3e 32 02 32 02 47 22 | (not yet analysed) |  | 4122f1 |
| 5A | 界面5A | ui_5a | 0 | 58 | 58 | — | (not yet analysed) |  | 416c97 |
| 07 | 测试待处理事件 | test_pending | 52 | 0 | 52 | — | (not yet analysed) |  | 415c46 |
| 43 | 测试失败 | test_defeat | 0 | 46 | 46 | — | Counterpart of 0x42 for defeat (0x4b3d08.0x44c74d; event slot 6): leader lost / all player units gone / turn limit. | T | 411d8e |
| 5C | 指令5C | op_5c | 0 | 37 | 12 | 02 | (not yet analysed) |  | 416e17 |
| 2B | 指令2B | op_2b | 36 | 0 | 20 | 02 | (not yet analysed) |  | 4172bb |
| 52 | 指令52 | op_52 | 15 | 18 | 16 | 02 03 | (not yet analysed) |  | 414d15 |
| 51 | 指令51 | op_51 | 0 | 26 | 14 | — | (not yet analysed) |  | 41626a |
| 62 | 单挑62 | duel_62 | 0 | 26 | 14 | 26 | (not yet analysed) |  | 4176bc |
| 3E | 装备设定 | set_equipment | 22 | 1 | 12 | 02 3b 49 3c 49 3d | Same arguments and codes as 0x48, applied at once; code 0 leaves the slot. Outside a battle a weapon code of 1 takes off every slot with a code (the original tests the weapon code for all three, 0x416319); in a battle the person's unit must exist and codes > 0x67 are ignored (0x4429f9). | 1 | 416319 |
| 1B | 指令1B | op_1b | 0 | 18 | 13 | 02 27 | (not yet analysed) |  | 413c56 |
| 42 | 测试胜利 | test_victory | 0 | 15 | 15 | — | True if the battle object 0x4b3d08 already flags victory, or the boss person configured for the battle (Reader+0x3d04 bit0, id at +0x3d06) is among enemy slots 35..115 in state 3/4 (defeated/retreated), or no enemy remains (0x44c8e6(5,…)==0). Sets event slot 5. | T | 411d63 |
| 22 | 天气 | set_weather | 12 | 0 | 3 | 1b | (not yet analysed) |  | 4121ed |
| 4A | 出场选择 | battle_prepare | 0 | 11 | 9 | 04 38 38 38 38 38 39 39 39 39 39 | (not yet analysed) |  | 415d92 |
| 5D | 指令5D | op_5d | 0 | 8 | 4 | 34 04 | (not yet analysed) |  | 417068 |
| 67 | 章节标题 | chapter_title | 5 | 0 | 5 | 04 05 | (not yet analysed) |  | 413b3d |
| 0F | 画面模式 | screen_mode | 4 | 0 | 3 | 12 | (not yet analysed) |  | 4158af |
| 6C | 指令6C | op_6c | 0 | 2 | 1 | 02 02 | (not yet analysed) |  | 410c3e |
| 10 | 空 | nop | 0 | 0 | 0 | — | No operation. | 1 | 41590d |
| 35 | 武将状态 | actor_state | 0 | 0 | 0 | 02 13 | (not yet analysed) |  | 4135de |
| 39 | 指令39 | op_39 | 0 | 0 | 0 | 02 04 | (not yet analysed) |  | 414b62 |
| 3C | 指令3C | op_3c | 0 | 0 | 0 | 02 0e 3a | (not yet analysed) |  | 415cbf |
| 54 | 界面54 | ui_54 | 0 | 0 | 0 | — | (not yet analysed) |  | 415771 |
| 56 | 指令56 | op_56 | 0 | 0 | 0 | 47 | (not yet analysed) |  | 414f03 |
| 57 | 指令57 | op_57 | 0 | 0 | 0 | 22 | (not yet analysed) |  | 414ec4 |
| 5E | 扩展5E | mod_5e | 0 | 0 | 0 | 04 | (not yet analysed) |  | 4d0000 |
| 70 | 复制武将数据 | copy_person_byte | 0 | 0 | 0 | 02 02 04 | Copy one byte of the person record: person[arg1].byte[arg2] = person[arg0].byte[arg2] (arg2 < 0x48). | T | 41113a |
| 72 | 跳回开头 | rewind | 0 | 0 | 0 | — | (not yet analysed) |  | 4d002e |
| 73 | 测试合计 | test_sum | 0 | 0 | 0 | 02 04 24 26 26 26 26 26 | (not yet analysed) |  | 411207 |

## 6. Memory map for script pokes (mod ops 0x77 / 0x78 / 0x79 / 0x75)

The mod scripts manipulate raw engine memory. A reimplementation needs a small "virtual memory" layer that maps
the addresses below to engine state. All findings are from the 117 scripts (counts = occurrences) plus the exe.

### 6.1 Addressing primitives
* `EV[i]` u32 @0x55b000+4i (i < 4096) – plain integer variables.
* `PT[i]` u32 @0x563000+4i (i < 2048) – "pointer variables": hold *addresses*. Only PT[0], PT[1], PT[2], PT[9]
  are used by the scripts.
* op 0x77 `int_var_op dk, di, op, sk, sv` (216,525×): destination address = `dk 0: PT[di]` (deref, write
  through the pointer) / `1: &PT[di]` / `2: &EV[di]`; source value = `sk 0: sv` / `1: *(u32*)PT[sv]` / `2: PT[sv]`
  / `3: &PT[sv]` / `4: EV[sv]` / `5: &EV[sv]`; `op 0 +=, 1 -= (saturating at 0: 0x47fa9e), 2 =, 3 *=, 4 /=, 5 %=`
  (unsigned 32-bit). **All accesses through PT are 32-bit**: the scripts read bytes with the idiom
  `x = *PT; t = x; t /= 256; t *= 256; x -= t` ("byte读取") and write 16-bit values with a read-modify-write of the
  following word ("双字节写入"). An emulator must therefore implement unaligned little-endian u32 reads/writes over
  a byte-addressable image of the relevant engine structures.
  Observed (dk,op,sk) combos: EV←imm/EV/\*PT everywhere; `PT[i] = imm` (3448×, the addresses in 6.2),
  `PT[i] += imm/EV` (pointer stepping, e.g. `+= 36` for unit records, `+= 4` for EV arrays), `PT[i] = &EV[n]`
  (1326×, EV arrays accessed through a pointer), `PT[i] = PT[j]`, `*PT[i] = imm/EV/*PT` (writes).
* op 0x79 `test_int_var` (226,374×) only ever uses kinds 0 (immediate) and 4 (EV) in the shipped scripts.
  (Its resolver kind 1 jumps to zero-filled code @0x4d5280 and would crash – never used.)
* op 0x75 `set_byte_var i, v` (264×): u8 @0x55a000+i = v. The same byte array is field 27 of op 0x78.
  (Indices used: see 6.6.)

### 6.2 Immediate addresses loaded into PT (op 0x77 `PT[i] = imm`)
| address | count | what it is | how scripts use it |
|---|---|---|---|
| 0 | 657 | null base | `PT[0] = 0; PT[0] += EV[x]` – turn a computed address held in an EV into a pointer |
| 0x4b2c50 | 467+42 | battle unit array, 115 records × 0x24 B (slots 0..14 player, 15..34 ally, 35..114 enemy) | loop `i<115`: `EV=*PT` (u32 at +0 = person id, 0xFFFF = empty), then `PT += 36`; per-unit data read with op 0x78 fields 28..41 indexed by person |
| 0x4b313c | 198 | = 0x4b2c50 + 35·0x24: first enemy record | loop over the 80 enemy records |
| 0x4b2c6e | 37 | = 0x4b2c50 + 0x1e: field +0x1e of unit 0 | stepped by 36 to scan field +0x1e (u8 status/turn counter) of every unit |
| 0x4927f0 / 0x4927f1 | 580 / 349 | combat object 0x4927f0: bytes +0 / +1 = attacker / defender unit slot, written when an attack starts (0x4064f1 → 0x4061fc) and kept until the next one | read as byte ("byte读取") and compared with unit field 28 (unit +4) to detect who is attacking whom ("攻防") |
| 0x4aeb44 | 200 | u32 pointer to the battle map buffer (header 1600 B, then width×height terrain bytes; the port keeps it at 0x02000000 so it is saved with the game) | `EV = *PT + 1600 + y*W + x` → terrain byte of tile (x,y) |
| 0x4b422c | 200 | u8 battle-map width in tiles (+0x4b422d = height) | used in the terrain-address computation above |
| 0x44c2de | 200 | 5 NOP bytes inside .text reserved by the mod as a parameter cell; read by the mod hook at 0x44c2d3 (`mov bl,[0x44c2de]`) | scripts store the terrain byte there before op 0x58 (map effect / terrain change at a tile) |
| 0x55ac04 … 0x55ac60 | 1–252 | mod globals in .data3 (see 6.5) | read/written as ints |
| 0x48b350 | 2 | u32 table "forced sortie" person list (0xFFFF-terminated; read by battle-init op 0x44 and 0x41885a) | `PT=0x48b350; PT+=4; *PT=person` … – force persons into the next battle's deployment ("强制人物出场") |
| 0x4b077c | 41+4 | GS+0x0c (u32) | read into an EV in "support" screens (value is a u32 game counter – see 6.4) |
| 0x4b09e6 … 0x4b09eb | 1 each | GS+0x276..0x27b (u8 each) | single bytes of GS read/written by one script |
| 0x48c44c | 1 | pointer table @0x48bdc0 entry 9 → GBK terrain-name string "大河" @0x48c44c | S_12 overwrites the characters (16-bit writes) to rename the terrain ("强制更改大河显字") |
| 0x43ffec | 2 | byte in an in-code table @0x43ffd8 (per-class movement animation step/speed table, last entry) | S_11 `+= 1` / `-= 1` when 裴翠云 mounts/dismounts a horse ("行动速度变化") |
| 0x43f4c6 | 2 | byte in an in-code table @0x43f4b8 (per-class movement sound table) | S_11 `-= 2` / `+= 2` ("行动声音变化") |

