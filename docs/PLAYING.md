# Player guide

How to start the game and play it: story scenes, battles, duels, menus and saving. For building the app see
[BUILDING.md](BUILDING.md).

## Starting the game

* **Download (recommended):** the [Releases page](https://github.com/seedds/wagang-godot/releases) has a ready
  build for macOS, Windows and iPhone for every update; take the newest *Build N*.
  * **macOS** (11+ on Apple Silicon, 10.13+ on Intel): unzip and open the app. It is not notarized, so macOS
    blocks it the first time. On macOS 15 and later open **System Settings → Privacy & Security**, scroll down
    and click **Open Anyway**; on older versions right-click the app → **Open**. Or run
    `xattr -dr com.apple.quarantine <app>`.
  * **Windows** (64-bit): unzip and run `WaGang.exe`; keep `WaGang.pck` in the same folder. If SmartScreen warns
    about an unknown publisher, choose **More info → Run anyway**.
  * **iPhone** (iOS 15+, iPhone XS or newer): `WaGang-iOS-build-N.ipa` is unsigned; install it with AltStore or
    Sideloadly, which sign it with your Apple ID (a free Apple ID needs re-signing every 7 days). With a developer
    account and a Mac, `tools/build_ios.sh --device` builds and installs it ([BUILDING.md](BUILDING.md)).
* **From source:** `./run_game.sh` in the repository root (needs Godot 4.7). The first run downloads the HD
  graphics pack (about 720 MB) and imports the project. See [BUILDING.md](BUILDING.md) to export an app yourself.

The window opens at the largest of 3×, 2.5×, 2×, 1.5× or 1× the original 640×480 that fits your screen. You can
resize it freely; when you let go, it snaps to the game's 4:3 shape so the picture fills it. Toggle full screen with
**⌘F**, **F11** or **Alt+Enter**.

On iPhone the game runs in landscape: the 4:3 picture fills the screen height, with touch buttons on both sides (see
[Touch controls](#touch-controls-iphone)).

The title screen offers **开始新游戏** (new game), **读取进度** (load) and **结束游戏** (quit; not on iPhone). After an ending has
been reached once, the title picture changes. Downloaded builds show their version (版本 1.0.N) in the bottom-right
corner.

The game uses the 4× AI-upscaled HD art ([HD_GRAPHICS.md](HD_GRAPHICS.md)).

## General controls

| Input | Action |
|---|---|
| Left click / Enter | confirm, select, advance dialogue |
| Right click / Esc | cancel or go back; opens the menu where there is one |
| Arrow keys / mouse wheel / Page Up, Page Down | move through menus (long lists scroll) |
| Hold **Space** or **Ctrl** | fast-forward animations and text (×4 game speed) |
| Click / Enter / Esc during a video | skip the cutscene |

### Touch controls (iPhone)

| Touch | Action |
|---|---|
| Tap | a left click: confirm, select, advance dialogue, skip a video |
| Tap a battle cell | also shows its unit or terrain panel (what hovering does with a mouse) |
| Drag on the battle map | scroll the map; a drag never counts as a click |
| Drag up/down on a long list | scroll the list (history, unit list, items …) |
| Slide on a menu, lift | the entry under the finger is highlighted and picked when you lift it, so you can correct a near-miss before lifting |
| **返回** (left of the picture) | a right click / Esc: cancel or go back; with nothing to cancel it opens the menu (in battle: end turn, unit list, save, load) |
| **快进** (right of the picture) | fast-forward on/off: ×4 speed and text skips ahead, like holding Ctrl |

Dialogue boxes show the speaker's portrait and name. Text types out; a click shows the rest, the next click
continues.

## Story scenes

Story scenes alternate with battles. Some play out on their own as cutscenes. In others you walk around a town or
camp and click characters and places to talk to them or go somewhere. These scenes keep waiting until you do the
thing that moves the story on, such as talking to a particular person.

While a scene is waiting for you:

* **菜单** (top right, or right click / Esc) opens the menu:
  * **部队状态** – party roster and each character's status (class, level, stats, equipment)
  * **装备** – equip weapons, armour and accessories from the bag
  * **道具** – use items outside battle (stat fruits, level-up and promotion items)
  * **存储进度 / 读取进度** – save or load
  * **回到标题** – back to the title screen
  * **史录** – the chronicle: story events, deeds and items, in one scrolling list; choose an entry to read it in
    full
* **出征** (top right, or first in the menu) appears once the next battle is ready. It marches out. If more members
  are available than the battle allows, a sortie screen (出场选择) lets you choose who goes; required members are
  pre-selected.

Hub towns have shops, side quests and optional characters. Some scenes contain **mini-games**:

* **单挑 duels** – a side-view fight where you click **攻击** (attack), **防御** (defend), **回避** (evade) or
  **绝招** (special, once its gauge allows). Losing usually ends the game, so save before risky fights.
* **Puzzles** – e.g. ordering lines of a poem.
* **A dice game** in a gambling house.

<p align="center"><img src="images/minigame.jpg" width="480" alt="Story mini-game duel"></p>

Choices matter: many dialogue choices and battle outcomes change story flags and hidden scores. Those decide later
branches and which of the endings you reach.

## Battles

<p align="center">
  <img src="images/battle-move.jpg" width="400" alt="Attack range">
  <img src="images/battle-info.jpg" width="400" alt="Unit information">
</p>

Each battle starts with its victory and defeat conditions (胜利条件 / 失败条件). Turns go: **your phase**, then
**allied** (green units), then **enemy** (blue units). Your units are red.

**Your phase**

1. Click one of your units. **Blue** cells show where it can move, **red** cells what it could attack from there.
2. Click a blue cell to move (click the unit's own cell to stay).
3. Pick a command:
   * **攻击** – attack; click a target inside the red range.
   * **策略** – cast a strategy (uses MP); pick it, then the target or area. The menu shows the hit chance.
   * **道具** – use an item on the unit or a neighbour.
   * **待命** – wait. Right-clicking in the command menu takes the move back.
4. Once every unit has acted the phase ends, or end it early from the system menu.

**Information**

* Hover over a unit or cell to see its panel: portrait, class and level, troops (兵), MP (策), status effects
  (毒 poison, 乱 confusion, 麻 paralysis, 封 seal, 怯 fear) and the terrain bonus.
* Click an enemy or ally to show its movement and attack ranges.
* Turn number, turn limit and weather are shown top right.

**System menu** (right click / Esc on the map; **返回** on iPhone): **回合结束** (end turn), **部队一览** (unit list), **胜利条件**
(objectives), **存储进度 / 读取进度** (save / load), **回到标题** (title).

**Moving around the map:** arrow keys move the cursor; the mouse at a screen edge or a middle-button drag scrolls.
On iPhone drag the map with a finger; tapping a cell shows its unit or terrain panel.

Units that run out of troops retreat; some characters have scripted retreat lines. Experience comes from fighting
and casting; at 100 EXP a unit levels up. From level 20 (and again from 40) a promotion item raises the unit to
the next class. Weapons and armour gain levels with use.

Many battles have scripted events: reinforcements, ambushes, weather changes, objectives that change mid-battle,
traps, and duels triggered when two particular units stand next to each other.

## Duels (单挑)

<p align="center"><img src="images/duel.jpg" width="480" alt="Duel screen"></p>

When the story calls for it, two officers duel on a separate screen: an introduction, then the fight with speech
bubbles. Duels are scripted and play by themselves. Text advances on a timer; click to finish a line early. The
winner may gain experience when the duel closes.

## Saving and loading

* **10 save slots**, from the story menu or the battle system menu, including mid-battle. Loading works from the
  title screen or in-game.
* Saves are stored as `save_00.json` … `save_09.json` (each with a small `save_NN.info.json` summary for the slot
  list) in the game's user folder:
  * macOS: `~/Library/Application Support/Godot/app_userdata/兴唐传·瓦岗山异闻录/`
  * Windows: `%APPDATA%\Godot\app_userdata\兴唐传·瓦岗山异闻录\`
  * iPhone: the app's own folder, visible in the **Files** app under **On My iPhone → 兴唐传·瓦岗山异闻录**
    (or in Finder's iPhone *Files* tab), so saves can be copied to and from a computer

  The file `niuniu.bin` there records reached endings, as the original's `Niuniu.wa` did. Saves can be copied
  between the macOS, Windows and iPhone versions. A save is written to a temporary file first, so a crash while saving
  leaves the old save intact; a damaged save, or one from a newer version of the game, is refused instead of
  loaded.
* A defeat (game over) returns to the title screen, so save often.

## Troubleshooting

| Problem | Fix |
|---|---|
| macOS: "App can't be opened" / "Apple could not verify…" | macOS 15+: **System Settings → Privacy & Security → Open Anyway**; older: right-click → **Open**; or `xattr -dr com.apple.quarantine <app>` |
| Windows: SmartScreen "Windows protected your PC" | **More info → Run anyway** (the build is not code-signed) |
| Windows: the game starts with an error about a missing pack | Keep `WaGang.pck` next to `WaGang.exe` (unzip the whole folder) |
| Window too small or large | Drag the window's edge or corner (it snaps to 4:3), or toggle full screen (⌘F) |
| Missing characters (▯) in text | The game uses system Chinese fonts: Songti SC, Hiragino Sans GB and Heiti SC on macOS (make sure they are not disabled in Font Book); SimSun, Microsoft YaHei and SimHei on Windows (install the Chinese supplemental fonts if your Windows lacks them). The iPhone version brings its own (Noto Serif SC) |
| A town scene "does nothing" | It is waiting for you: find the character or place that continues the story, or check the menu for **出征** |
