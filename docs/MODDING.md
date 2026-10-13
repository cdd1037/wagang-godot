# Modding

A mod changes the game's content: the story and battle scripts, the data tables (characters, items, classes,
strategies, shops …), what strategies, consumables and character skills do ("Rules as tables" below), pictures,
music, sound or video. The rest of the game's rules is GDScript in `game/src`; changing that means changing the
source and building your own version.

## What a mod is

A mod is a **.zip file** whose files are laid out like the game's `game/assets` folder, under `assets/`:

```
mymod.zip
└── assets/
    ├── scripts/R_05.json        a story file (R_xx) or battle file (S_xx)
    ├── data/persons.json        a data table
    ├── data/exe_image.bin       the original program's memory image (its built-in tables)
    ├── gfx/portraits/012.png    a picture (the original's size; see "Pictures")
    └── audio/bgm/07.mp3         a music track
```

When the game starts it mounts every `.zip` in its **mods folder** over its own files, in name order, so a mod's
files replace the game's and a later mod (by name) wins over an earlier one. Files a mod leaves out stay the game's.
The title screen shows how many mods are loaded (`模组 N`), and the log prints `mod loaded: <file>` for each.

The mods folder is `mods` in the game's user folder (where the saves are, see [PLAYING.md](PLAYING.md)):

* macOS: `~/Library/Application Support/Godot/app_userdata/兴唐传·瓦岗山异闻录/mods/`
* Windows: `%APPDATA%\Godot\app_userdata\兴唐传·瓦岗山异闻录\mods\`
* iPhone: in the **Files** app, **On My iPhone → 兴唐传·瓦岗山异闻录 → mods** (create the folder)
* Android: the app's storage is private, so mods cannot be installed there yet

Saves hold the game's memory, not the scripts or tables: a save made with a mod may not fit the game without it,
and the other way round.

## Making a mod from the original game

The mod (兴唐传) itself was made with the Cao Cao Zhuan community's tools, which work on the original game's files:
the script editor (剧本编辑器) for the `R_xx.wagan` / `S_xx.wagan` scripts and the data editors (修改器) for
`data.wa`, `person.wa` and the program's tables. Edit a **copy** of the original game with them, then convert the
copy into a mod with this repository (prerequisites in [BUILDING.md](BUILDING.md), "Re-generating the game data"):

```sh
tools/venv/bin/python -I tools/make_mod.py /path/to/modified-copy mymod.zip
tools/venv/bin/python -I tools/make_mod.py /path/to/modified-copy mymod.zip extra/   # plus pictures, sounds …
```

The program image (`data/exe_image.bin`) carries the built-in tables the game reads from it: strategy power and
category, the mounted families, terrain and other names, the area codes and more, so an edit to them in the copy's
`wagan.wa` reaches the game. Rules that are code in the original (and GDScript here) do not change that way.

`make_mod.py` converts the copy's scripts (`tools/eex.py`), data tables (`tools/conv_data.py`) and program image
(`tools/dump_image.py`), compares each file with the game's own, and packs only those that differ or are new.
Run on the unmodified original it finds nothing to pack: the converters reproduce `game/assets` exactly. `extra/`
is a folder laid out like `game/assets` whose files go into the zip as they are.

Scripts can also be edited as JSON (their format and every opcode are in [eex.md](eex.md)), but a body stores its
jump targets as resolved positions, so inserting or removing an instruction by hand breaks them; going through the
`.wagan` file and the converter keeps them right. The data tables' fields are those `tools/conv_data.py` writes
(see [rules.md](rules.md) for what they mean).

## Rules as tables

Three tables in `assets/data` say what strategies, consumable items and character skills do. A mod changes them by
bringing its own copy, from `make_mod.py`'s `extra/` folder: `extra/data/skills.json` and so on. Each holds the
original's values. The code's behaviours stay fixed, so a record can only pick among them: a mod can move a skill to
another person or change its numbers, but a new kind of effect still needs code. Mistakes are not caught: a
mistyped field reads as missing. (`t_tables` checks the shipped tables against the original's values.)

**`strategy_rules.json`**: one record per strategy id, in the order of `strategies.json`.

| Field | Meaning |
|---|---|
| `handler` | which of the original's handlers runs it (dispatcher 0x425627): `damage`, `storm` (飓风: every enemy on the map), `stat`, `status`, `heal`, `bazhen` / `xuanwu` (a random outcome per target), `again` (战备: act again, once per turn), `weather`, `fortify`, `meditate` (暝思: +¼ MP, needs 兵力 ≥ 3), `qinglong`, `baihu`, `none`. 烈魔 casts `damage` and `status` strategies twice |
| `element` | 0 火, 1 水, 2 风, 3 地: the terrain it needs (0x420422); 火 fails in rain, heavy rain and snow |
| `hit` | the hit factor on the hit curve: `[numerator, denominator]`, `"always"`, or `"leader_third"` (狂澜: ⅓, 0 against the leader or the enemy commander, no sure hit on a confused target) |
| `hp_damage`, `mp_damage` | it does HP damage / takes MP (暗鬼: the caster gets it) |
| `absorb_hp`, `assassinate` | 暗算 (the caster gets the HP; family 12 ×1.5 hit, ×2 damage), 暗杀 (marks the target) |
| `status` | `confusion`, `poison`, `paralysis` or `seal`: given on a hit (after a damage strategy, only if the target survives) |
| `cure` | the status bits it clears |
| `heal`, `heal_size` | `hp` or `mp`; `small` (精神/8 + 60) or `large` (精神/2 + 100); an MP heal restores its MP cost |
| `stat_codes` | the stat changes (codes of 0x420cb2: 0x17 爆发↓ … 0x37 防御↑) |
| `weather` | 0 晴明, 1 叆叇, 2 阴雨: which level of the climate it picks (0x44a1f9) |
| `ai`, `ai_bonus`, `ai_opposing` | how the AI scores it (0x4395ae) and whether the AI aims it at the other side |

**`item_rules.json`**: one record per consumable item type (an item's `type` in `items.json`). `kind` is
`heal_hp`, `heal_mp`, `cure` (with the status bits `mask`), `all_up` (太保令), `fruit` (with `stat`, the person stat
0..4, and `fx`, its effect picture), `level_up` (仙人果) or `promote` (印绶).

**`skills.json`**: one record per character skill, with an `id` the code asks for, a `name` and `src` (the
original's address). The fields:

* `holder` says who has the skill. It is one of:
  * `{"pid": n}` or `{"pids": [...]}`: fixed persons;
  * `{"dyn": k}` or `{"dyns": [...]}`: whoever the story scripts put in dynamic slot `k` (`EV[3970 + k]`);
  * `{"mem": address}`: a person id the scripts write there;
  * `{"beside": pid}`: that person standing next to the unit.
* `if` limits a holder to a class (`{"class": 41}`).
* The other fields are the skill's numbers, for example `range`, `percent` or `ev` (an EV variable it reads).
* The 绝招 records carry `special`, the routine that runs. When a person holds several, the first in file order is
  used, as in the original.

## Pictures

Pictures are PNG at the original's size. The game normally shows the 4× HD version of each picture
(`assets_hd/gfx/….webp`, see [HD_GRAPHICS.md](HD_GRAPHICS.md)); for a picture a mod replaces, it shows the mod's
PNG instead, unless the mod also brings `assets_hd/gfx/<same path>.webp`.

## Testing a mod

* Start the game and look for `模组 N` on the title screen; from a terminal, `godot --path game` prints
  `mod loaded: …` and any `missing json` / `missing image` warnings.
* The automated tests and bots (DEVELOPMENT.md) ignore mods unless `WG_MODS=1` is set, so they always test the game
  as shipped. `WG_MODDIR=/some/folder` reads mods from another folder than `user://mods/`, for example to run the
  flow tests on a mod: `WG_MODS=1 WG_MODDIR=$PWD/mods tools/flowpar.sh 0 20 11`.
