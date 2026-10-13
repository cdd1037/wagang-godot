# Architecture

How the Godot reimplementation is put together. The reverse-engineering facts it relies on (file formats, script
opcodes, formulas, AI) are specified in the documents listed in [README.md](README.md). This page is about the code
in `game/src/`.

## Design in one paragraph

The mod's 117 scripts do not only call high-level opcodes: they also read and write raw engine memory, poking
person records, battle units, flags and variables by address. So the reimplementation keeps the game state in an
**emulated byte image of the original engine's memory**, laid out exactly like the original. A script interpreter
runs the original (converted) scripts against it. Godot nodes render that state and handle input. Formulas and AI
are ported from the decompiled executable.

```
             ┌──────────── main.gd ────────────┐
             │ title · scenario loop · saves   │
             └──────┬──────────────────┬───────┘
         even n: R_xx.json      odd n: S_xx.json
                    ▼                  ▼
            StoryStage            BattleStage ── BattleActions · BattleCommands · BattleAI · BattleInput
                    └──── extends ScriptHost ──┘         BattleView · BattleHUD · DuelLayer
                               │ op_<name>()
                            EexVM  (scenes → sections → bodies)
                               │
   Autoloads:  Mem (emulated memory) · Game (state, data tables) · Assets · Audio
                               │
                         GameUI (dialog, menus, popups, fades, video)
```

On iOS and Android the main scene is `touch/touch_shell.tscn` instead. It runs `main.tscn` inside a 640×480 `SubViewport` with
touch buttons beside it (see "Touch controls" in [DEVELOPMENT.md](DEVELOPMENT.md)). Code reaches the Main node
through `Game.main`, never `/root/Main`.

## Autoloads

| Singleton | File | Role |
|---|---|---|
| `Assets` | `core/assets.gd` | Loads converted data at run time: textures from PNG bytes, JSON, MP3/WAV, OGV video, fonts (system Chinese fonts with fallbacks; on mobile a bundled Noto Serif SC subset, `tools/subset_font.py`). Everything under `res://assets` is imported with `importer="keep"`, so files are read raw. With the HD pack active, `tex()` substitutes the 4× `.webp` from `res://assets_hd` at the original's logical size (see [HD_GRAPHICS.md](HD_GRAPHICS.md)). |
| `Audio` | `core/audio.gd` | BGM player (the original CD tracks as `audio/bgm/NN.mp3`) and a small pool of sound-effect players. |
| `Mem` | `core/mem.gd` | The emulated memory (below). |
| `Game` | `core/game.gd` | Static data tables (persons, classes, items, strategies, terrain …), the party and bag, scenario number, gold, and save/load. |

## Emulated memory (`core/mem.gd`)

`Mem.r8/r16/r32` and `w8/w16/w32` address one flat 32-bit space:

* **0x400000 …** – `assets/data/exe_image.bin`, the executable's sections mapped as the loader would, including
  all initialised data tables. Writes go into a copy.
* **0x01000000 …** – heap for the 0x48-byte person records; the pointer to them lives at 0x4d0048 like in the
  original.
* **0x02000000 …** – the battle map buffer (0x640-byte header, then one terrain byte per cell). Its address is
  stored at 0x4aeb44 like the original's, so scripts that read terrain through that pointer see the real map, and
  terrain changes made during a battle are part of a save.
* Anything else lands in sparse 4 KB pages created on first write.

Important locations:

| Address | Contents |
|---|---|
| 0x4b0770 (`GS`) | game-state block: scenario (+7), gold (+0xc), flags for story/portraits, message speed (+0x10) |
| 0x492fc8 (`FLAGS`) | story flags, one u32 each |
| 0x55b000 (`EV`) | the mod's 4096 integer variables |
| 0x563000 (`PT`) | the mod's pointer table |
| 0x55a000 (`BYTEVARS`) | the mod's byte variables (initialised from `person.wa`) |
| 0x4b2c50 (`UNITS`) | 115 battle-unit records × 0x24 bytes |
| 0x48b350 | sortie list (u32 person ids, 0xffff-terminated) |
| 0x4b0783 | the bag (item slots) |
| 0x4b3c80 | duel object |
| 0x4927f0 / 0x4927f1 | attacker / defender slot of the latest attack, a counterattack too (the scripts' 攻防 tests); +0x10 the target list; +0x608 the strike counter |
| 0x496c96 | the battle's enemy commander (u16 R+0x3d06, `BattleStage.boss_pid`) |
| 0x4b2c28 | the AI's choice target, which the target finder 0x436586 prefers (`BattleActions.PREFERRED`) |
| 0x4cf2b8 | the level-up grade bonus count, one for everyone (`Person.bonus_counter`) |
| 0x55a500 | 怀恨攻击's hit counter per unit slot (`BUnit.GRUDGE`); [0x55a6cc] the strike loop's last target index |
| 0x48baec | the loaded battle map's number, 0xff / 0xffff in towns (battle or town person getters, `core/skills.gd`) |
| 0x55ac1c..0x55ac68 | the mod's 【技】 technique flags (rules.md §12.1) |
| 0x55ee00..0x55ee07 | 并蒂's hit counters |
| EV[3970..3999] | the dynamic skill slots: the person holding each skill |

Addresses that more than one file uses have names in `core/addr.gd` (`Addr.SORTIE`, `Addr.SCENE_MODE` …); a file's
own addresses are constants in that file.

`Person` (`core/person.gd`) and `BUnit` (`battle/bunit.gd`) are **views**: thin objects whose properties read and
write the record in `Mem`. Every change a script makes by address is therefore visible to the engine, and the
other way round.

Saves (`Game.save_game`) store the memory ranges that hold game state (`Mem.SAVE_RANGES`), the person heap and
the extra pages as base64, plus the party, chronicle, scenario and the running stage's own state. Saves are JSON
with a version number, written through a temporary file; a small `.info.json` beside each holds what the slot
list shows.

## Script interpreter (`core/eex_vm.gd`)

The converter (`tools/eex.py`) turns each `R_xx.wagan` / `S_xx.wagan` into JSON: **scenes**, each with
**sections**. A section has a **condition list** and a flat **body** of instructions. `IF` carries its jump target
(`end`) and its condition (`cond`); `goto` carries a resolved target (scene, section, index).

The execution model follows the original:

* `poll()` evaluates every section of the current scene; the **last** one whose conditions all hold runs.
* A scene with a single section is linear: when its body ends, the next scene starts. Multi-section scenes are
  event loops left through `next_scene` / `goto_scenario`.
* Nesting is tracked at run time. `IF` pushes a level, `END` pops one, `ELSE` tests the last result at its level.
  A `goto` inside a block pops one level and continues at the target, possibly in another section.
* Each instruction is dispatched to `op_<name>(ins)` of the host stage, or of the objects in `vm.handlers` (looked
  up once per op name, `EexVM.handler`). Handlers may `await` (dialogue, animations, delays).
  Test ops return a bool. Handlers that return nothing count as true when used as an `IF` condition, as in the
  original. `vm.next_op` tells a handler which instruction follows (a run of story `actor_move`s walks in
  parallel and only the last one waits).
* Scenario scripts are parsed when a file starts and not kept in the JSON cache (a whole play-through's worth would
  take gigabytes).

`docs/eex.md` lists all opcodes; `docs/engine_notes.md` notes the ops whose parser names are misleading (for
example op 0x23 "play_music" actually plays a sound effect).

## Script host and stages

`ScriptHost` (`core/script_host.gd`) holds the opcode handlers shared by story and battle scripts: flags and
variables, `int_var_op` / `data_transfer` (raw memory access), dialogue and captions, choices, audio and video,
party and items, resources, class changes, and the special functions. `arg()` resolves `{"var": n}` operands
through EV variables.

### Story scenes (`story/story_stage.gd`)

* A 640×400 view at y = 40 of the 640×480 screen: background from `gfx/backgrounds` plus isometric actors
  (`RpgActor`, 48×64 frames). The foot point of half-cell (x, y, z) is `(8(x−y)+312, 4(x+y)−8z−152)`.
* After a poll finds nothing to run, the stage waits for a click on an actor. The click sets a flag in `GS` and polls
  again, so sections testing `test_clicked(pid)` fire.
* The **菜单** / **出征** buttons and the right-click menu replace the original toolbar. A right click (or long
  press) on an actor who is a party member opens 武将情报 instead (0x429b81). **出征** builds the sortie
  list (`build_sortie`, port of 0x41856a) and sets the pending flag that the scene's own `test_pending` section
  consumes.

### Battles (`battle/battle_stage.gd`)

* **Scene 0:** deployment ops create the battlefield (map from `gfx/maps`, terrain, units), then the opening events
  run.
* **Scene 1:** the turn loop (`battle_loop`) runs player, ally and enemy phases. At each phase start
  `checkpoint()` polls the event sections once (victory and defeat checks, reinforcements, scripted dialogue),
  then the recovery, 暗杀 countdown, poison and regeneration of that side follow (0x44ed93 / 0x44e851). A unit
  whose HP reaches 0 in a command stays on the map until the command or AI action is over. Then the acting unit
  becomes the current unit and, while it is on the map, the events are polled (`actor_poll`, 0x45b5fe), so a
  section can still see the fallen unit on the map at HP 0 (S_13's 杨素 revives). `remove_dead()` (0x44cc03) then
  takes it off and the events are polled again. EV[10] = 1 tells the scripts that a unit fell (rules.md §9.1).
* **Scene 2:** the aftermath.

`BattleStage` itself keeps the turn loop, the event polls, the unit queries, the battle-time test ops, the text and
UI ops and save / restore. The rest lives in components it creates (`deployment`, `phase_fx`, `unit_ops`,
`field_ops`); the VM finds their `op_<name>` handlers through `BattleStage.op_handlers()` (`EexVM.handlers`).

| Class | Responsibility |
|---|---|
| `BattleDeploy` | the opening ops (deployment entries, sortie list, equipment, 0x4a), `create_battlefield`'s unit setup (UnitInit, SetAI, Promote), free cells |
| `BattlePhase` | the work at each phase start: 暗杀 countdown, phase-start skills and auras, status recovery, buff decay, regeneration |
| `BattleUnitOps` | the unit ops: units appearing, moving, changing (0x4c-0x4f, 0x53 …), leaving with their animations, unit lines, effect 0x6b |
| `BattleFieldOps` | terrain changes and their undo (0x21 / 0x58, the record saves carry), the goal area (0x5b) and its blink |
| `BattleView` | map rendering, highlight overlays, cursor, camera and scrolling |
| `BattleInput` | player phase: select → move range → move → command menu; a right click on a unit → 武将情报 (only a pointer right click, `BattleView.right_from_pointer`; Esc / 菜单 / a right click elsewhere → system menu) |
| `BattleActions` | movement with zones of control, attacks (with area and piercing targets, the 【技】 techniques of the attack wrapper), counters, criticals, strategies, items, EXP, level-ups, retreats, the end-of-action skills and kill rewards (formulas in `core/rules.gd`, spec in `docs/rules.md` §4, §5, §12) |
| `BattleCommands` | the mod's commands 绝招, 围攻 and 交给, and ChangeUnit (spec in `docs/mod_patches.md` B5 F1–F3) |
| `BattleAI` | enemy and ally decision making, a port of the original AIAct scoring |
| `BattleHUD` | hovered-unit panel, turn and weather, phase banners, damage numbers |
| `EffectPlayer` | strategy and effect animations (Xben / MCALL animation sets) |
| `DuelLayer` | the 单挑 screen, implemented from `docs/duel.md` |
| `SortieScreen` | 选择武将 (dialog 236), choosing who goes into battle; `SortieMap` its 出战位置 preview |
| `Minimap` | 战场缩小图, the battle minimap with the draggable view frame |

## UI (`ui/`)

`GameUI` sits above the stages and owns the dialogue box (typewriter text, portraits), choice menus, popups,
banners, captions, chapter titles, fades and the video layer. Panels use the original's blue dragon-pattern window
texture (`UIStyle`). The menu is one list of the original's menu-bar commands; the windows below follow the
original dialogs. `Settings` (`core/settings.gd`) holds 环境设定 in GS / Niuniu.wa as the original does and
re-applies it whenever Mem is reset or restored.

* `InfoWindow` is 武将情报 (dialog 166 of wagan.wa) with its pages 能力 / 装备 / 策略 / 兵种, and `DetailPanel` the
  item (dialog 167) and strategy (dialog 285) details it opens. Both extend `DlgPanel`, which lays a window out by
  the control rects of the original dialog template (dialog units, scaled ×1.98 / ×1.8 into 640×480), draws group
  boxes, buttons and the original's bar painter (Kao.wa tiles), and routes clicks to keyed hit areas. The window
  is modal (the original's is modeless and follows the hovered unit). Spec: [rules.md](rules.md) §11.
* `DlgPanel` also has a list view (columns sharing the width, header sort hits, scroll buttons) and a tab strip;
  hover, tap (touch: a first tap selects, long press = right click) and right-click hooks. On it: the shops
  `ShopWindow` (买进 / 卖出, also the warehouse-full variant), `EquipWindow` (装备), both with `PersonPanel` (the
  person box, stat preview and equipment slots of dialogs 327 / 328) and `ItemCols` (the list columns, prices and
  sort keys); `ItemListWindow` (持有道具一览), `UnitListWindow` (部队情报一览), `TerrainWindow` (地形情报一览),
  `HistoryWindow` (历史情报), `SettingsWindow` (环境设定) and `MsgBox` (the Win32 OK / yes-no boxes, 版本情报).
  `MerchantBox` is the shops' merchant window with its 确认 and 输入数值 boxes. Spec: rules.md §13.

* "Click to continue" waits compare `Game.clicks`, a counter of presses kept by `Game._input`, instead of polling
  whether a button is held: a short trackpad tap is never missed, and the click that closed one box does not also
  close the next one.
* Choice menus scroll when they have more rows than fit on the screen (arrow keys, wheel, Page Up/Down) and cut
  over-long rows short. The dialogue box grows for long texts, and captions wrap.
* Chapter titles are drawn above the fade layer, since scripts show them on a black screen.

## Main flow (`main.gd`)

1. Boot: play the intro video, then the title screen. The title picture changes once an ending has been reached
   (recorded in `user://niuniu.bin`, like the original's `Niuniu.wa`).
2. `_run_flow()`: for scenario *n* load `R_(n/2)` if *n* is even, else `S_(n/2)`; run it; then *n* + 1, unless a
   script jumped with `goto_scenario`.
3. Game over, endings, title and loading all go through `stop_flow()`, which abandons the running stage and
   stops a looping sound effect. The
   scenario loop is tagged with a generation counter, so an orphaned loop can never continue.

Also in `main.gd`: window handling (the initial size is the largest of 3×–1× that fits the screen; after the user
resizes the window it snaps back to 4:3 so the picture fills it; full screen), the Space/Ctrl fast-forward
(`Engine.time_scale = 4`), the version label on the title screen (`application/config/version`, set by the release
workflow).

## Test hooks

The flow-test harness and the bots step into the game at a few points only: `Game.hooks` (`core/test_hooks.gd`),
whose methods do nothing by default. When the build has `src/debug`, `Game` loads `debug/harness.gd` in its place,
which brings the jump starts (`WG_START`, `WG_LOADSLOT`, `WG_STOP`), the flow test's autosave slot and its retries
from it, the battle objectives (`FlowGoals`), the story 单挑 and puzzle solvers, the skips, caps and the god mode's
field clear, the input and UI bots, `WG_SAVETEST`, `WG_SHOTS` and the battle traces. No game script names a class
of `src/debug` (t_parse checks it), so a build can leave the folder out and play the same. The release builds keep
it: their smoke test plays the exported pack from a jump start (`WG_START=0 … WG_STOP=3`), and without the
variables the harness does nothing.

## Source map

| Path | Contents |
|---|---|
| `main.gd` | boot, title, scenario loop, game over/ending, save/load menus, window |
| `core/` | `assets`, `audio`, `mem`, `addr`, `game`, `person`, `eex_vm`, `script_host`, `rules`, `skills`, `settings`, `data_transfer`, `special_funcs`, `person_attrs`, `sound_map` |
| `story/` | `story_stage`, `rpg_actor` |
| `battle/` | `battle_stage` (with `battle_deploy`, `battle_phase`, `battle_unit_ops`, `battle_field_ops`), `battle_view`, `battle_input`, `battle_actions`, `battle_commands`, `battle_ai`, `battle_hud`, `battle_attrs`, `bunit`, `unit_sprite`, `grid`, `shapes`, `effect_player`, `duel_layer`, `sortie_screen`, `sortie_map`, `minimap` |
| `ui/` | `game_ui`, `dialog_box`, `choice_menu`, `dlg_panel`, `info_window`, `detail_panel`, `shop_window`, `equip_window`, `person_panel`, `item_cols`, `merchant_box`, `item_list_window`, `unit_list_window`, `terrain_window`, `history_window`, `settings_window`, `msg_box`, `ui_style`, `video_layer` |
| `debug/` | `harness` (the test hooks, below), `test_runner`, `input_bot`, the flow-test helpers `flow_goals` (battle objectives), `duel_sim` (story 单挑) and `flag_puzzle` (click puzzles), small test scripts such as `t_hd` (HD texture mechanism) and `t_resize` (window snapping); see [DEVELOPMENT.md](DEVELOPMENT.md) |
