# Development

Debug options, the automated test harness, and the reverse-engineering workflow. For the code structure see
[ARCHITECTURE.md](ARCHITECTURE.md).

## Running from source

```sh
./run_game.sh                               # windowed; downloads the HD pack once, re-imports when a script changed
godot --headless --path game ...            # headless, for tests (after one `--import`)
godot -e --path game                        # open in the Godot editor
```

Godot prints to the terminal. Harmless noise you can ignore:
* `WARNING: Case mismatch opening requested file … app_userdata …` comes from the user-data folder name on a
  case-insensitive file system.
* `ObjectDB instances were leaked at exit`.

## Debug environment variables

All options are environment variables read at start-up, for example
`WG_START=21 WG_PARTY=0,8,13 ./run_game.sh`. They also work with the exported app's binary.

**Starting point**

| Variable | Effect |
|---|---|
| `WG_START=n` | Skip the title and start a new game at scenario *n* (even = story `R_(n/2)`, odd = battle `S_(n/2)`). At a battle, the party becomes the sortie list. |
| `WG_PARTY=0,8,13` | With `WG_START`: add these person ids to the party |
| `WG_SETFLAGS=755,…` | With `WG_START`: preset story flags that an earlier branch would have set |
| `WG_LOADSLOT=n` | Skip the title and load save slot *n* |
| `WG_STOP=n` | Quit when scenario *n* is reached |
| `WG_NOVIDEO=1` | Skip cutscene videos |
| `WG_HD=0` | Show the original art instead of the HD graphics pack (for comparisons) |
| `WG_MODS=1`, `WG_MODDIR=path` | Load the mods ([MODDING.md](MODDING.md)) in a test or bot run too (they skip them otherwise); read them from *path* instead of `user://mods/` |

**Automatic play**

| Variable | Effect |
|---|---|
| `WG_AUTO=1` | Autoplay: the AI plays your phase, dialogue and waits are instant, menus pick automatically, story scenes click characters |
| `WG_DEMO=1` | Like autoplay but at normal speed (watchable) |
| `WG_RANDOM=1` | Autoplay picks random choices and clicks (otherwise deterministic) |
| `WG_CLICKS=608,600,…` | Autoplay clicks these actors first, in order, each as soon as its click would run a section (a guided run through a puzzle; R_14's poem: `608,600,609,602,616,604,617,606,614,648,615,653,618,655,619,657`) |
| `WG_CLICKCAP=n` | With `WG_AUTOSAVE`: end a story file after *n* autoplay clicks instead of 2,500 |
| `WG_GOALS=0`, `WG_DUELSIM=0`, `WG_PUZZLE=0` | With `WG_AUTOSAVE`: turn off the battle objectives, the story 单挑 player or the flag-puzzle solver of the flow-test harness |
| `WG_GOD=1` | Player side invulnerable and strong. With autoplay: from turn 13 the enemies on the map fall at each round (HP 0 and EV[10] as in combat, so the scripts' kill sections run) and hidden ones go; a battle still running at turn 60 jumps to its aftermath |
| `WG_SORTIE_P=n` | Chance (%) that autoplay presses 出征 when available (default 12) |

**Tracing**

| Variable | Effect |
|---|---|
| `WG_TRACE_SEC=1` | Print every script section that runs, with battle turn and phase |
| `WG_TRACE_TEXT=1` | Print dialogue, choices, popups and autoplay clicks |
| `WG_TRACE_OPS=1` | Print every executed instruction (very verbose) |
| `WG_TRACE_BATTLE=1` | Print battle details (deployment, joins, area tests) |
| `WG_TRACE_PID=p` / `all` | Print person p's unit, or every unit on the map, at each round start |
| `WG_TRACE_MAP=1` | Print the battle map's terrain codes once, at turn 2 |
| `WG_MEMWATCH=4b2c50-4b2c74` | Report writes to an address range (hex) in the emulated memory |

**Test harness and bots**

| Variable | Effect |
|---|---|
| `WG_AUTOSAVE=1`, `WG_AUTOSLOT=n` | Flow-test harness (below): autosave to slot *n* (default 19) after each scenario, retry from it after a game over. Slots 0–9 are the player's saves: the game refuses them and quits with exit code 2 |
| `WG_INPUTBOT=dir` | Drive the player phase with synthetic mouse and keyboard events and save screenshots to *dir*. `WG_BOTTURNS=n` limits the turns |
| `WG_UIBOT=dir` | The UI bot (`game/src/debug/ui_bot.gd`): plays from the title screen through real input events only, with the game in its normal mode, and checks the UI as it goes (see "UI playthrough test" below). With a window it saves pictures to *dir*. `WG_UIBOT_TIME` (default 3600 s), `WG_UIBOT_STALL` (90 s), `WG_UIBOT_SEED`; `WG_UIBOT_GALLERY=n` (with a window) also saves the whole screen at each window, menu, dialogue page, move range and town toolbar it meets, up to *n* of each per scenario, in the touch shell with its side buttons (the README's screenshots: e.g. `WG_UIBOT=dir WG_UIBOT_GALLERY=3 WG_SAVEDIR=shots WG_LOADSLOT=n`) |
| `WG_SAVEDIR=name` | Keep every save in `user://name/` instead of `user://`. The UI bot uses `user://uibot/` |
| `WG_BOTMODE=load`, `WG_BOTSLOT=n` | Input-bot variant: load slot *n* from the battle menu |
| `WG_BOTMODE=duel` | Input-bot variant: stage a 单挑 between the first player unit and the first enemy, with screenshots |
| `WG_BOTMODE=victory` | Input-bot variant: open the system menu, pick 胜利条件 and screenshot the window |
| `WG_BOTMODE=info` | Input-bot variant: right-click (in the touch shell: long-press) an own unit and an enemy, check that 武将情报 opens with that side's list, switch pages by taps, close with Esc; Esc and a right click on an empty cell open the system menu. Prints `INFOBOT: PASS`, also `infobot.txt` in the bot folder |
| `WG_BOTMODE=special` | Input-bot variant: 管毅 with a full MP bar walks next to an enemy and uses 绝招 from the command menu (screenshots of the menu, the banner and the result); prints `SPECIALBOT: PASS` |
| `WG_BOTMODE=touchcancel` | Input-bot variant for the touch shell: checks that taps on empty spots cancel and that 菜单 opens the system menu; prints `TOUCHCANCEL: PASS` and writes `touchcancel.txt` to the bot folder |
| `WG_FXTEST=3,5` | Input-bot variant: cast these strategy ids from the first player unit at the first enemy and screenshot their animations. With `WG_AUTO=1` instead of the bot (no screenshots) it prints each target's HP, status and buffs before and after, e.g. `WG_START=1 WG_AUTO=1 WG_GOD=1 WG_FXTEST=38,66` |
| `WG_SAVETEST=1` | Save at battle turn 2 and quit; run again with `WG_LOADSLOT=18` to check the restore |
| `WG_ACCEPT_SPAM=1` | Press Enter every 0.6 s |
| `WG_SHOTS=dir` | Save a screenshot to *dir* every `WG_SHOT_EVERY` seconds (default 3) |
| `WG_SHELLSHOT=dir` | Touch shell only: the same for the whole screen, side buttons included (`user://…` works on a phone) |
| `WG_SHELLSIZE=WxH` | Touch shell on a desktop: open the window at this size, e.g. `1734x800` (iPhone shape) or `1334x750` (16:9) |

While `WG_AUTO`, `WG_DEMO`, `WG_START`, `WG_AUTOSAVE`, `WG_INPUTBOT`, `WG_UIBOT` or the unit checks' `TEST` is set
(`Game.test_run`), tests and bots leave the player's files alone: the autosave (`user://autosave.json`, the title
screen's 继续游戏) is neither read nor written, and the endings and items record `niuniu.bin` is a copy in the run's
own folder (`WG_SAVEDIR`'s, else `user://test/`), taken from the player's when the run starts so the run sees the
player's 环境设定. Other runs, `WG_LOADSLOT` among them, keep the autosave up to date like normal play.

Example: watch the first battle play itself:
`WG_START=1 WG_DEMO=1 WG_NOVIDEO=1 ./run_game.sh`

## Automated play-through tests ("flow tests")

The scripts in `tools/` run the game headless in autoplay and log to `extract/`:

| Script | Purpose |
|---|---|
| `tools/flowtest.sh [seconds] [stop]` | Long autoplay run with autosave and retry: continues from slot 19 (`WG_AUTOSLOT`) if it exists, else (or with `FRESH=1`) starts a new game → `extract/flow.log` |
| `tools/flowtrace.sh [seconds] [stop]` | The same (slot 19 too) with section and text tracing → `extract/flow_trace.log` |
| `tools/flowpar.sh START STOP SLOT [seconds] [PARTY]` | Jump-start a scenario range (for running ranges in parallel) → `extract/flow_par_START.log` |
| `tools/flowres.sh SLOT STOP LOG [seconds]` | Resume such a run from its autosave slot |
| `tools/flowwatch.sh LOG…` | Print skips and errors as they appear, and `STALL` when a log is silent for 5 minutes (use with a log watcher) |
| `tools/test_all.sh [t_name…]` | Run every headless unit check (below) and print a summary; exit status 1 if one failed. CI runs it on every push (`.github/workflows/tests.yml`) and before every release build |
| `tools/gtest.sh t_name [seconds]` | Run one check, `game/src/debug/t_name.gd`, under the headless test runner; exit status 0 passed, 1 failed, 2 timed out (default 120 s) |
| `tools/uitest.sh [stop] [seconds]` | UI playthrough test: the UI bot from a new game to scenario *stop* (default 5, after R_02) → `extract/uibot/uitest.log`; prints `uitest: PASS` or `uitest: FAIL` |

The autosave slot numbers are save files in the game's user folder: use **11 or higher**, since slots 0–9 are the
player's own saves (the scripts and the game refuse them). Run several ranges in parallel with bash, for example
`bash -c 'for r in "0 16 11" "16 32 12"; do set -- $r; tools/flowpar.sh $1 $2 $3 1500 & done; wait'`. The endings
the runs reach go to `user://test/niuniu.bin`, not the player's record.

Headless unit checks (`tools/test_all.sh`, one with `tools/gtest.sh NAME`). Each prints `t_name: PASS` or
`t_name: FAILED` (after `t_name: FAIL …` lines); the test runner (`debug/test_runner.gd`) turns that into the exit
status, fails a check that hits a script error, and stops one still running after `TEST_TIMEOUT` seconds.
`t_parse` loads every script (catches parse errors anywhere) and checks that every opcode the story and battle
scripts use has a handler on that stage (`EexVM.handler`), `t_mods` a mod zip (its JSON and its picture replace
the game's, HD version included; in `user://test/mods/`),
`t_equip` checks the equipment codes of ops 0x3e/0x48, `t_strat` the strategy usability rules (0x420422, 0x41fec9),
`t_touch` the touch controls (map taps and drag-panning, menu taps, slides and drag-scrolling; a drag or cursor
key that stops a camera scroll lets whoever awaits it go on), `t_rpgwalk` story
walking (route order and facing per step, 0x429159), `t_dialog` the message box growing to fit long texts (the
9-line 胜利条件 window), `t_info` the 武将情报 window (status line, 技能 box, strategy list, item effect texts, pages,
上一/下一, closing, the details, a pointer right click versus Esc on the map, long presses, story-scene right
clicks; with `OUT=file.png` and a window it also saves a screenshot of each page and of the details),
`t_battle` the battle state the scripts see (EV[10] and the removal of fallen units after a command, the 暗杀
countdown, fire with op 0x21 and its undo with op 0x58, script attr 8, op 0x3b in a battle, the AI's score for
an area attack's extra targets, the default victory and defeat of ops 0x42 / 0x43, the cell → unit caches after a
restored battle save, the 史录 rules),
`t_commands` the mod's battle commands (the 绝招 enable rules and moves, multi-target strikes, 围攻, 交给,
连续策略, the move record), `t_skills` the character skills (the 【技】 techniques with an attack trace, the
phase-start auras, 明镜, the stat auras, 并蒂, 宿痕, 舍命 / 智将, 杜断, 房谋, 烈魔, 逐影随行咒, the on-hit skills,
terrain, 相马, 天运, 百宝, 统军, 锻造 / 波若, kill rewards), `t_rules` the general battle rules (反应 / 士气 equipment,
组阵, effect 37, 笼屉, 怀恨攻击 and the counterattack's combat object, 太保令, the level-up penalty and report, SetExp
past 70, 引导攻击, 策略模仿, 狂澜, per-phase equipment experience, op 0x38's signed AddStat, the unit lookup 0x43e4d6),
`t_save` saves (a save loads back; a damaged one, or one whose memory ranges do not fit, is refused before
anything changes; it uses user://test/saves/), `t_shop` the shops and the warehouse (prices with
八折, the bonus fruit, goods per record, buying = wearing, 装备 moves, selling), `t_menus` the group 5 windows
(环境设定 applied without writing Niuniu.wa, 历史情报 line order, the sortie builder and 选择武将 rules, 部队情报一览
sorting, 地形情报一览, the town gate GS+2, the status panes kept in memory and put up again by a load; `OUT=dir` with a window saves their pictures), `t_screens` the screens of
the script-op audit (开始作战, the 胜利条件 sequence, the chapter cards, the resource meter; `OUT=dir` with a window
saves them), `t_storyclick` plays R_00 by hand up to the training 单挑 (the opening's captions gone, 攻击 runs nothing
until 防御 has, the click on 防御 starts it; windowed, about two minutes, run with `WG_START=0 WG_NOVIDEO=1
WG_ACCEPT_SPAM=1`), `t_person` prints person stats.

The harness, the bots and the tracing step into the game only through `Game.hooks` (`core/test_hooks.gd`, which does
nothing; `debug/harness.gd` is loaded in its place when the build has `src/debug`). A new test feature goes into the
harness, with a hook in `TestHooks` if the game has to call it; `t_parse` fails when game code names a debug class.

Two checks need a window (they read rendered pixels or resize the window), so run them without `--headless`:

```sh
cd game
TEST=res://src/debug/t_hd.gd godot --path . res://src/debug/test_runner.tscn       # prints t_hd: PASS
TEST=res://src/debug/t_resize.gd godot --path . res://src/debug/test_runner.tscn   # prints t_resize: PASS
```

The harness (`WG_AUTOSAVE`) keeps random play moving:

* A **game over** reloads the last autosave and retries.
* A **battle** lost 3 times jumps to its aftermath on the next try.
* A **story scene** that fails 30 times (usually chained 单挑 mini-games) is skipped.
* A **story scene** with more than 2,500 autoplay clicks (an unsolved puzzle or hub) is ended; the line lists the
  story flags that are set, to see how far a quest got.
* A **story scene** with nothing to click and no section to run for a minute is ended ("idle scene"). This happens
  on a jump start that lacks an earlier file's story flags: R_10's opening needs flag 755 from R_09, so start at
  18 or pass `WG_SETFLAGS=755`. The original would sit in the same empty scene.
* Jump starts lack earlier files' flags in quests too: R_21's 出征 needs flag 19, which 并肩王府 / 管毅邸 set only
  with R_09's branch flag 755 / 754. So `tools/flowpar.sh` passes `WG_SETFLAGS=755` (the 突围 branch) to a range
  that starts after R_09 unless `WG_SETFLAGS` is set. R_21 also needs R_20's choice of a name for the garden
  (flags 799-801, 月映轩 …), so test it from R_19 (38) or earlier, not by a jump into R_21.
* A jump start's party is only 管毅 and `WG_PARTY`, so the persons a story file forces into the next sortie
  (op 0x06) join the party when the sortie is built (S_31 needs its four 主攻手 to take the corners). Not from
  scenario 0: R_08 forces 雄阔海, who joins only in S_08, and with him S_08 would field a seventh unit, which the
  six op 0x4b places leave at S_07's spot, shut in behind the city wall.
* An **ending** in the last chapters stops the run.

Autoplay clicks mostly go to actors whose click would run a section that has not run yet in this file (the
section the next poll would pick), else to actors some section tests for, else to anyone.

In battles the AI plays our units, and the AI knows nothing of the script's position objectives. Under the harness
`FlowGoals` (`game/src/debug/flow_goals.gd`) reads them from the battle scene before each of our units acts:
* **Reach:** a section whose other conditions hold, whose title names an objective (到达, 占领, 攻破, 突破, 打开,
  逃离, 撤离, 我军逃, 挖宝, 秘藏, 找到, but nothing with 伏 or 敌军) or whose cells lie in the 指定地点 the map marks
  (op 0x5b; S_04's 伏兵出现（已料及） at (19, 4); S_36's 我军逃走 needs its name, since the marker moves on), and
  that waits for our units on a cell or in an area (0x25 / 0x26 / 0x41) sends them there (the nearest one for a
  single cell). They hold the cell once there and attack whatever is in
  range. Treasure sections (no dialogue) come last, and are dropped when they lie inside the area of a trigger that
  is armed or of a defeat section. The other position sections are mostly enemy triggers (伏兵起动, 我军过于南进):
  walking into them pulled our units off the pass in S_40, and S_45's 挖宝 lies in 妖风1's area, whose 罡岚万仞
  takes 罗成's HP (his fall loses the battle; god mode only covers combat).
* **Guard:** a defeat section (its body sets story flag 1) that waits for an enemy on a cell sends the nearest unit
  there to hold it. An enemy closing in on such a cell (a shorter walk there than at an earlier turn) and within
  four of its moves is the first target of every unit that can hit it this turn, unless it is a duel foe: in S_08,
  内郭军方针变更 sends two light cavalry for 鹿砦 through the gate's guards, who block our way there.
* **Keep out:** a defeat section that waits for our units in an area keeps them from ending a move there (S_04's
  友军提前攻城: coming near the town before the ambush is drawn out loses the battle). So does a section titled as
  a trap (机关, 陷阱, 中计: S_43's 机关第五区; S_36's 挖宝04中计 is not a treasure to dig), unless the title is about
  finding it (找到, an objective: S_36's 我军找到吊桥机关 lowers the drawbridges out of the maze) or the trap sets a
  flag an objective waits for (S_36's 究极陷阱 has to go off before that mechanism works). Units walk round the
  areas they keep out of when there is a way round.
* **Sparing:** a defeat section that counts an enemy side on the whole map ("fewer than n", S_03's 绿林军死伤过重;
  not S_08's count of our own side, 我方有人撤退) makes our units leave that side alone except the target 胜利条件
  names after 击退 (else the persons a section waits for at HP 0); they all go for it, god mode's ×20 damage spares
  that side, and its clear after turn 12 is skipped.
* **Duels:** a section titled "…VS…" that waits for our unit next to someone (0x2e, S_13's 管毅VS杨素) sends the unit
  there, and nobody hits that person meanwhile (the duel lowers his HP by script and keeps him on the map). God
  mode's clear after turn 12 still takes him: the duels are optional, and S_28 / S_39 need every enemy gone.
  Duel goals come after the objectives (S_08: the race to 鹿砦 before the duels with 宇文成都).
* Sections that wait for different units on the same cells count as one goal: the nearest of those units goes
  (S_31: one section per 主攻手 at each corner, so the four go to four corners). Nearest means the cheapest walk
  by the unit's move costs; a unit that cannot get there is passed over, and the unit already sent to a single
  cell keeps it unless another is much nearer (two units would otherwise swap two goals at every move). A guarded
  cell that is also an objective (S_08's 鹿砦, which the enemy makes for too) gets every unit the objective waits
  for.
* Phase and turn tests count as true. Only the pure tests 0x05 / 0x36 / 0x79 / 0x2e are evaluated, and a section
  with any other op is left out.
* `WG_TRACE_SEC` prints each new goal (`[goal] 管毅: reach 1.36 管毅到达鹿砦 → (2, 7)`). `WG_GOALS=0` turns it
  off.

Story 单挑 (sections 攻击 / 防御 / 绝招 / 回避, the enemy's answer rolled inside them) are played by `DuelSim`
(`game/src/debug/duel_sim.gd`): those sections test only flags and random rolls and change only flags, so a dry run
of their control flow on a copy of the flags gives every outcome of a move with its probability; the bot clicks
the move with the best chance to win, looking 5 rounds ahead (expectimax; a path through "R剧本单挑失败" loses, one
into "R剧本单挑胜利" wins). `WG_TRACE_TEXT` prints each decision (`[duel] 攻击 0.78, 回避 0.70 …`),
`WG_DUELSIM_CHECK=1` checks each round played against the predicted outcomes, `WG_DUELSIM=0` turns it off. When
sections keep running without a pause for the player (R_16's 张千, who must be clicked during a 4-tick delay), the bot
clicks an actor whose click would run a section, as a player's click during the delay would.
Click puzzles whose answer is a set of story flags are solved by `FlagPuzzle` (`game/src/debug/flag_puzzle.gd`):
the target is a section of the scene that has not run, with only flag tests, that needs at least 4 flags which click
sections set (R_14's 管德昭解图赴东郡: flags 111, 122, …, 188, verse v in slot v). Dry runs with DuelSim's flag
interpreter rate each click on screen and every follow-up click; the bot takes the one whose best two clicks set the
most of those flags, never clears one already set and changes some flag. After 30 such clicks without a new flag
the scene goes back to the usual clicking (R_31's placement puzzle, whose last pieces the dry runs get wrong).
`WG_TRACE_TEXT` prints `[puzzle] 3 of 8 flags, aiming at 4`; `WG_PUZZLE=0` turns it off.
`WG_TRACE_PID=p` prints person p's unit (slot, state, HP, cell) at each round start; `WG_TRACE_PID=all` every unit on the map.
`WG_TRACE_MAP=1` prints the battle map's terrain codes (hex, a row per line) once, at turn 2.

Every skip prints a `== flow-test: …` line. A skip usually means random play can't meet a scripted objective (turn
limits, traps, puzzles, choice-dependent endings), not a bug. Look for `SCRIPT ERROR`, `ERROR` or a `STALL`
instead.

Tips:

* Jump starts lack the story flags and levels of a real play-through. Start at a story scene (even *n*) where
  possible, and use `WG_SETFLAGS` for branch scenes.
* Godot's output is block-buffered when redirected to a file. To see the last line before a hang, run under a
  pseudo-terminal: `script -q /dev/null godot … < /dev/null > log`.
* A hung run at 100 % CPU is a script loop; at ~0 % it is an `await` that never completes. `WG_TRACE_OPS=1` shows
  where.
* Decode GBK with `Mem.gbk()` / `Mem.str_at()`, not `get_string_from_multibyte_char("GBK")` directly: Godot
  4.7's iconv conversion never returns for a single two-byte character (无, 船, 火 …).
* Synthetic `InputEventAction`s from the bots and `WG_ACCEPT_SPAM` don't reach the battle map, which takes only
  real key events; the bots press a real Esc (`_esc()`) to open its system menu.

### UI playthrough test

Flow tests run with autoplay, which skips dialogue, menus, windows and the mouse path, so a UI regression gets past
them. `tools/uitest.sh` runs the UI bot instead. It starts a new game from the title screen with the game in its
normal mode and only sends input a player could:
* clicks on dialogue boxes, menu rows, window buttons, story actors, the town toolbar and map cells;
* the wheel on long lists, Esc for the battle's system menu, and Enter when something waits with nothing to click.

It decides like autoplay:
* a story click is `StoryStage.auto_pick`, with `DuelSim` for 单挑 and `FlagPuzzle` for puzzles;
* a player unit's move, strategy and target come from `BattleAI.decide`, with the bytes and the random state it
  touches put back;
* a menu gets its first enabled row;
* the sortie takes the first candidates.

It checks:
* every click reaches its handler: a waiting dialogue page closes, a menu row is chosen, a window's 确定 / 结束 /
  取消 closes it, an actor or map cell click is taken (each within 3 s);
* a new stage starts with no dialogue, menu, window, popup or caption left from the last one;
* in the first town of each story file with the toolbar, every system-menu window, the toolbar's windows and
  武将情报 open and close, and a save to slot 1 followed by its load brings back the same scenario, gold and party.
  Saves go to `user://uibot/`, never the player's slots; 环境设定 is closed with 取消, so the settings stay;
* the game never sits for 90 s with nothing changing and nothing the bot can do.

The script also fails on any `SCRIPT ERROR` / `ERROR:` in the log. It runs headless with `WG_GOD=1` and
`WG_NOVIDEO=1` by default; `WINDOW=1` shows the game and saves a picture of each stage start and of each failure
to `extract/uibot/`. The default run, R_00 to the end of R_02, takes about 20 minutes; `WG_TRACE_TEXT=1` adds the
bot's battle moves and tour steps to the log.

## Touch controls and the phone builds

On mobile, `project.godot` runs `res://src/touch/touch_shell.tscn` (`run/main_scene.mobile`) instead of
`main.tscn`. `TouchShell`:

* Lays out in window pixels. The window has no content scaling there (`window/stretch/mode.mobile="disabled"`).
* Runs `main.tscn` inside a `SubViewport` with `size_2d_override` 640×480. The game still sees an exact 640×480
  screen, and it is drawn at the display's resolution, so HD art and text stay sharp.
* Puts the 4:3 picture in the middle and the buttons in the side bars, clear of the notch. The original's right
  click does two jobs, and each gets its own button:
  * **菜单** (top left) calls the stage's `open_menu()`. It is only enabled while the stage's `menu_ready()` is
    true: a story scene waiting (`_waiting_click`), or the battle player phase at its top level (`BattleInput.idle`).
  * **返回** sends Esc; every cancel path also takes `ui_cancel`. It is dimmed while 菜单 is enabled.
  * **快进** toggles `Game.fast_toggle`, which `Game.skip_held()` treats like holding Ctrl.
  * Android's back button or gesture (`NOTIFICATION_WM_GO_BACK_REQUEST`) activates 返回, or 菜单 where 返回 is
    dimmed. `application/config/quit_on_go_back` is off, so it never quits the app.

Game-side switches:

* `Game.touch` (set by the shell) makes `BattleView` click a cell on release and pan on drag, and show the tapped
  cell's info panel.
* It also makes `ChoiceMenu` pick on release and scroll long lists by dragging. Desktop input is unchanged.
* Tapping an empty spot cancels. Outside a cancellable `ChoiceMenu` (pressed and released there) the menu closes.
  Outside the highlighted cells while picking a target, `BattleInput._cancels` treats the tap as a right click.
* `Game.main` replaces `/root/Main`, which does not exist inside the shell.
* `Game._input` ignores presses on the side bars.
* On mobile, `Assets` halves HD textures over 4096 px and keeps a smaller HD cache.

Try it on the desktop; the mouse acts as a finger, and right click still works:

```sh
cd game
WG_SHELLSIZE=1734x800 godot --path . res://src/touch/touch_shell.tscn
# the input bot through the shell (taps on release, 菜单 for the system menu):
WG_START=1 WG_ACCEPT_SPAM=1 WG_NOVIDEO=1 WG_INPUTBOT=/tmp/bot WG_BOTTURNS=2 WG_SHELLSIZE=1734x800 \
  godot --path . res://src/touch/touch_shell.tscn
# tap-an-empty-spot checks in a real battle; prints TOUCHCANCEL: PASS, also written to /tmp/bot/touchcancel.txt:
WG_START=1 WG_ACCEPT_SPAM=1 WG_NOVIDEO=1 WG_INPUTBOT=/tmp/bot WG_BOTMODE=touchcancel WG_SHELLSIZE=1734x800 \
  godot --path . res://src/touch/touch_shell.tscn
```

Building and installing on a phone: `tools/build_ios.sh --device`; in the Xcode Simulator (native arm64, after
`tools/build_ios_sim_lib.sh` once): `tools/build_ios.sh --sim` (see [BUILDING.md](BUILDING.md)). Android:
`tools/build_android.sh --install` builds the APK and installs it on the connected phone or a running emulator; the
game's output is in `adb logcat -s godot`. Debug variables reach the iOS app through `IOS_ENV`. For example,
`IOS_ENV='{"WG_SHELLSHOT":"user://shots"}' tools/build_ios.sh --device` saves screenshots in the app's Documents
folder. Fetch them from a phone with
`xcrun devicectl device copy from --device UDID --domain-type appDataContainer --domain-identifier com.seedds.wagang --source Documents/shots --destination DIR`;
in the simulator they are under `$(xcrun simctl get_app_container booted com.seedds.wagang data)/Documents`. For
example, this plays one battle turn through the touch path with screenshots:
`IOS_ENV='{"WG_START":"1","WG_NOVIDEO":"1","WG_ACCEPT_SPAM":"1","WG_INPUTBOT":"user://bot","WG_BOTTURNS":"1","WG_SHELLSHOT":"user://shots"}' tools/build_ios.sh --sim`.

## HD graphics and releases

* `tools/get_hd_pack.sh` downloads the HD graphics pack into `game/assets_hd/`. `tools/upscale_assets.py`
  rebuilds it, and `tools/upscale.py` upscales single images for trying models. See [HD_GRAPHICS.md](HD_GRAPHICS.md).
* Every push to `main` that changes the game builds and publishes *Build N* for macOS, Windows, iPhone and Android; see
  "Automatic releases" in [BUILDING.md](BUILDING.md). Check a run with `gh run list --workflow release.yml`.

## Reverse-engineering workflow

The original executable is `wg2025/wagan.wa` (PE32, image base 0x400000). The mod's code lives in an extra
`.text2` section around 0x4d0000 and hooks the original code with `jmp` patches.

* **Ghidra (preferred):** `tools/ghidra/gdec.sh OUT.c 0x41973c 0x448524 …` decompiles functions headlessly. The
  first run imports and analyses the executable into `extract/ghidra_proj` (slow, once). The script uses Ghidra
  and JDK 21 from Homebrew unless `GHIDRA_INSTALL_DIR` / `JAVA_HOME_21` point elsewhere.
* **Quick disassembly:** `tools/venv/bin/python -I tools/disx.py 0x43640e 40` (capstone). `tools/cases.py`
  disassembles jump-table targets, and `tools/findins.py REGEX` searches instructions.
* **Mod-code coverage:** `tools/ghidra/modcov.sh` traces `.text2` from the audited entry points, with Ghidra and with
  `tools/modcov.py`. It writes the bytes neither trace reaches, with every reference into them, to
  `extract/modcov.txt`. See "Coverage of the mod code" in [mod_patches.md](mod_patches.md).
* **Data:** `game/assets/data/exe_image.bin` is the mapped executable, so `offset = address − 0x400000` reads any
  table the game uses. The same image is the game's emulated memory.
* **Scripts:** `tools/eex.py` also writes human-readable listings to `extract/eex_txt/`. The JSON in
  `game/assets/scripts/` is what the game runs.

Conventions:

* Findings go into `docs/` with the addresses they come from: `rules.md` for formulas and AI, `eex.md` for
  opcodes, `engine_notes.md` for op semantics and engine behaviour, `gfx.md` for formats, `duel.md` for the duel
  screen. Code comments cite the same addresses. `mod_patches.md` lists every patch the mod makes to the engine
  and whether the port has it; update its status when a missing feature is implemented.
* **Adding an opcode:** implement `op_<name>(ins)` in `ScriptHost`, or in `StoryStage` / `BattleStage` if it only
  makes sense there. Read arguments with `arg(ins, i)` (resolves `{"var": n}`) or `sarg()`; test ops return a bool.
  An unimplemented op prints `EEX unimplemented op …` once.
* Script names in `opcodes.json` come from the original parser and can be misleading; trust the decompiled handler
  (see `engine_notes.md`).
