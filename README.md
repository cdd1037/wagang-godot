# 兴唐传·瓦岗山异闻录 — Godot reimplementation (macOS)

A reverse-engineered reimplementation of the Windows game in `wg2025/` (a Sui–Tang story mod running on
Koei's 1998 *三国志曹操传* engine) in **Godot 4.7**, playable on macOS.

## Play
* **App:** `build/WaGang.app` (double-click; first launch: right-click → Open, since it is not notarized).
* **From source:** `godot --path game` (Godot 4.7: `brew install --cask godot`).
* Saves go to `~/Library/Application Support/Godot/app_userdata/兴唐传·瓦岗山异闻录/`.

### Controls
| | |
|---|---|
| Left click / Enter / Space-tap | select, confirm, advance dialogue |
| Right click / Esc | cancel, open the system menu (battle: 回合结束, 部队一览, 胜利条件, save/load) |
| Story scenes | click characters to talk; 菜单 button (top right) or right click → 出征 (march out), 装备, 道具, 部队状态, 史录, save/load |
| Battle | click a unit → click a blue cell to move → 攻击 / 策略 / 道具 / 待命; red cells = attack range |
| Arrow keys | move the battle cursor; mouse at screen edge / middle-drag scrolls the map |
| Hold Space or Ctrl | fast-forward |
| ⌘F / F11 / Alt+Enter | toggle full screen |

## Layout
| path | content |
|---|---|
| `wg2025/` | original game (read-only input) |
| `tools/` | Python converters/RE helpers (`venv/` has capstone, pefile, pillow); `ghidra/gdec.sh` = Ghidra headless decompiler wrapper |
| `docs/` | reverse-engineering specs: `NOTES.md`, `gfx.md` (all graphics formats), `eex.md` (script language), `rules.md` (data tables, battle formulas, AI), `engine_notes.md` (misc op semantics), `duel.md` (单挑 screen) |
| `game/` | Godot project; `assets/` = converted data (PNG/JSON/MP3/WAV/OGV, loaded at runtime) |
| `build/` | exported macOS app |

## Rebuilding the assets
```
tools/venv/bin/python -I tools/conv_gfx.py          # graphics → game/assets/gfx
tools/venv/bin/python -I tools/conv_data.py         # data.wa tables → game/assets/data
tools/venv/bin/python -I tools/eex.py               # R_xx/S_xx.wagan scripts → game/assets/scripts
tools/venv/bin/python -I tools/dump_image.py        # exe image for the emulated memory
python3 -I tools/conv_audio.py && tools/conv_video.sh   # audio, videos (needs ffmpeg-full for Theora)
python3 -I tools/mark_keep.py                        # mark assets importer=keep
godot --headless --path game --export-release "macOS" ../build/WaGang.app
```

## Engine design (game/src)
* `core/eex_vm.gd` – EEX script interpreter (scene/section polling, runtime IF/ELSE/goto nesting, yields).
* `core/mem.gd` – emulated memory: the mod's scripts poke raw engine memory (pointer table, unit array,
  game-state block), so persons, units, flags, variables, bag, gold… live in a byte image of the original
  layout (`assets/data/exe_image.bin`) and the engine reads them through views (`Person`, `BUnit`).
* `core/script_host.gd` – shared opcode handlers; `story/story_stage.gd` (isometric RPG scenes),
  `battle/battle_stage.gd` (deployment, turn loop, battle ops, duel), `battle/battle_actions.gd`
  (combat/strategy/items/exp per docs/rules.md), `battle/battle_ai.gd` (original AIAct scoring).
* Debug env vars: `WG_START=n` (start at scenario n; at a battle the party becomes the sortie list), `WG_PARTY=0,35`,
  `WG_AUTO=1` (autoplay), `WG_GOD=1`, `WG_TRACE_SEC=1`, `WG_TRACE_TEXT=1`, `WG_TRACE_BATTLE=1`,
  `WG_LOADSLOT=n`, `WG_AUTOSAVE=1` + `WG_AUTOSLOT=n` (autosave/retry slot), `WG_INPUTBOT=dir`
  (+`WG_BOTMODE=load`) drives battles through real input events, `WG_ACCEPT_SPAM=1` taps Enter,
  `WG_SORTIE_P=n` = autoplay chance (%) to press 出征 when available, `WG_SETFLAGS=755,…` presets story
  flags for a jump start (branch scenes check flags their predecessor sets), `WG_TRACE_OPS=1` traces every op.
* Flow tests (autoplay with autosave, retry, and skips for scripted objectives random play can't reach):
  `tools/flowtrace.sh` (sequential, from slot 9), `tools/flowpar.sh START STOP SLOT` (jump start),
  `tools/flowres.sh SLOT STOP LOG` (resume) → logs in `extract/`.

## Known gaps
* The duel (单挑) screen follows the decompiled routines (docs/duel.md) but upscales sprites with nearest
  neighbour instead of the original edge-smoothing 2× filter.
* The original town toolbar is replaced by 菜单 / 出征 buttons in the story scenes' top bar.
* Some rarely used ops are approximations (see warnings printed for unimplemented ops).
* UI layout follows the original style but is not pixel-identical.
