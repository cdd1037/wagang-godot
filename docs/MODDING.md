# Modding

A mod changes the game's content: the story and battle scripts, the data tables (characters, items, classes,
strategies, shops …), pictures, music, sound or video. The game's rules themselves are GDScript in `game/src`;
changing those means changing the source and building your own version.

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
