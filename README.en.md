# 兴唐传·瓦岗山异闻录 — Godot remake

[中文](README.md) | **English**

A remake of the Sui–Tang tactics game **兴唐传·瓦岗山异闻录** (*Xing Tang Zhuan: Wagang Mountain Chronicles*) that runs
natively on **Windows**, **macOS**, **iPhone** and **Android**. The original is a mod by 轩辕学院 built on Koei's
*三国志曹操传* (Cao Cao Zhuan) engine. The remake was rewritten from the original program: story, battle rules, enemy
AI, shops and menus work as in the original, and every picture is AI-upscaled to 4× HD.

<p align="center">
  <img src="docs/images/title.jpg" width="400" alt="Title screen">
  <img src="docs/images/story.jpg" width="400" alt="Story dialogue">
</p>
<p align="center">
  <img src="docs/images/battle-menu.jpg" width="400" alt="Battle commands: 绝招, 围攻, 交给">
  <img src="docs/images/info.jpg" width="400" alt="武将情报 (character information)">
</p>

## Download

Get the newest **Build N** from the [Releases page](https://github.com/seedds/wagang-godot/releases). Every update
publishes a new build automatically; each platform's file is about 1.1 GB, and the iPhone and Android files arrive a
few minutes after the desktop ones.

| Platform | File | Install |
|---|---|---|
| Windows (64-bit) | `WaGang-Windows-build-N.zip` | Unzip and run `WaGang.exe` (keep `WaGang.pck` next to it). If SmartScreen warns about an unknown publisher, choose **More info → Run anyway**. |
| macOS (Apple Silicon 11+, Intel 10.13+) | `WaGang-macOS-build-N.zip` | Unzip and open the app. It is not notarized, so macOS blocks it the first time: on macOS 15 and later click **Open Anyway** at the bottom of **System Settings → Privacy & Security**; on older versions right-click the app → **Open**. |
| iPhone (iOS 15+, iPhone XS or newer) | `WaGang-iOS-build-N.ipa` | Unsigned: install it with AltStore or Sideloadly (with a free Apple ID it must be re-signed every 7 days). |
| Android (7.0+, 64-bit) | `WaGang-Android-build-N.apk` | Download it on the phone, open it and allow the install. Later builds install over it and keep the saves. |

## Features

* **The whole story**: all 117 story and battle scripts, from the opening at 牧龙谷 to every ending. Dialogue choices
  and battle results change the branches and the ending you reach.
* **The original battles**: Cao Cao Zhuan's tactics rules plus the mod's 绝招 (special move), 围攻 (siege) and 交给
  (hand over) commands and the many characters' 【技】/【术】 skills; the enemy AI is the original's too.
* **Towns and mini-games**: buy and sell weapons and items, change equipment, choose who marches out, take side
  quests; the story also has 单挑 duels, puzzles and other mini-games.
* **4× HD graphics**: every picture is AI-upscaled to 4× ([original vs HD](docs/HD_GRAPHICS.md)).
* **Save anywhere**: 10 slots, in story scenes and mid-battle, plus an autosave written when the app goes to the
  background or is closed; 继续游戏 on the title screen picks it up. Save files can be copied between computer and
  iPhone.

<p align="center">
  <img src="docs/images/town.jpg" width="400" alt="Town toolbar: 出征, 装备, 买进, 卖出">
  <img src="docs/images/shop.jpg" width="400" alt="Shop">
</p>

**On phones** the game plays in landscape with the 4:3 picture in the middle and 菜单 (menu), 返回 (back) and 快进
(fast-forward) buttons beside it; tap, drag and hold to play:

<p align="center">
  <img src="docs/images/phone-story.jpg" width="400" alt="Phone: story scene">
  <img src="docs/images/phone-battle.jpg" width="400" alt="Phone: battle">
</p>

## Controls

| Computer | Phone | Action |
|---|---|---|
| Left click / Enter | Tap | select, confirm, advance dialogue |
| Right click / Esc | Tap an empty spot / 返回 | cancel, go back |
| Esc / right click on an empty spot | 菜单 | system menu: save, load, end turn, unit list … |
| Right click on a character | Hold a finger on it | 武将情报 (character information) |
| Arrow keys / mouse at the screen edge | Drag | scroll the battle map |
| Hold Space or Ctrl | 快进 | fast-forward |
| ⌘F / F11 / Alt+Enter | — | full screen; drag the window's edge to resize it |

Android's back button works like 返回 and never quits the game. Menus, battle commands, character skills, where the
saves live and troubleshooting are in the full **[player guide](docs/PLAYING.md)**.

## Differences from the original

The game plays as the original does, apart from these deliberate changes:

* The autosave is a file of its own and takes no save slot (the original overwrote slots 1–5 in turn after each of
  your battle phases).
* Every cutscene video can be skipped.
* The original's Windows menu bar and toolbar are an in-game list and buttons in the top bar; one window is open
  at a time.
* An ending or a game over returns to the title screen instead of closing the program.

## Status

* The whole game is playable from the opening to the endings. Every script has been run by automated play-through
  tests, but nobody has played it through by hand yet.
* The Windows build has not been tested on a real Windows machine yet.
* Please report problems in [Issues](https://github.com/seedds/wagang-godot/issues).

## For developers

The original program (`wagan.wa`) was decompiled with Ghidra; its file formats, script language, battle formulas,
enemy AI and every change the mod makes to the engine were documented and then reimplemented in **Godot 4.7**. The
game data (scripts, maps, pictures, music, sound, videos) is the original's, only converted.

Running from source needs [Godot 4.7](https://godotengine.org) (`brew install --cask godot` on macOS):

```sh
git clone https://github.com/seedds/wagang-godot.git
cd wagang-godot
./run_game.sh      # first run downloads the HD graphics pack (~720 MB), imports the project, starts the game
```

Without the script, import once with `godot --headless --path game --import`, then run `godot --path game`.

| Document | Contents |
|---|---|
| [docs/PLAYING.md](docs/PLAYING.md) | The full player guide |
| [docs/BUILDING.md](docs/BUILDING.md) | Re-converting the data from the original game; exporting the macOS / Windows / iPhone / Android builds; the release workflow |
| [docs/HD_GRAPHICS.md](docs/HD_GRAPHICS.md) | The 4× HD graphics pack: building, publishing, model choice |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How it works: emulated memory, script VM, stages, UI |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Debug options, automated play-through tests, the UI test, reverse-engineering workflow |
| [docs/README.md](docs/README.md) | Reverse-engineering specifications: file formats, script ops, rules and AI, the audit of the mod's patches |

`game/` is the Godot project (`src/` source, `assets/` converted game data), `tools/` holds the converters, test
and build scripts, `.github/` the release workflow. The original game, build output and the HD graphics pack are not
in the repository.

## Legal

This is an unofficial fan project for preservation and study, not affiliated with or endorsed by Koei Tecmo or the
mod's authors. *三国志曹操传* is © Koei Tecmo. The game content in `game/assets` (graphics, music, sound, video, text,
scripts) is converted from the original game and remains the property of its respective owners.

The repository has no license file yet, so the code is "all rights reserved" by default; add a `LICENSE` to make
the source in `game/src`, `tools` and `docs` reusable. Such a license would not cover `game/assets`.
