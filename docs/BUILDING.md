# Building

The repository contains the converted game data (`game/assets/`); the HD graphics pack (`game/assets_hd/`) is
downloaded by `run_game.sh` or `tools/get_hd_pack.sh`. To play or develop you only need Godot. This page covers
**exporting the apps** yourself, the **automatic releases**, and **re-generating `game/assets/`** from an original
copy of the game.

## Exporting the apps

Requirements: [Godot 4.7](https://godotengine.org) (`brew install --cask godot`) with the export templates
installed (Godot → Editor → Manage Export Templates → Download; the full download has macOS and Windows).

### macOS

```sh
godot --headless --path game --import                                  # build Godot's import cache (first time)
godot --headless --path game --export-release "macOS" ../build/WaGang.app
```

* The output path is relative to `game/`, so `../build/WaGang.app` ends up in `build/` at the repository root.
* The preset (`game/export_presets.cfg`) builds a **universal** binary (Intel macOS 10.13+, Apple Silicon 11+),
  ad-hoc code-signed, bundle id `local.wg2025.wagang`. It packs `assets/*`, `assets_hd/*` (the HD graphics pack,
  if present) and the scripts. A local export keeps the original pictures too: about 1.5 GB with the HD pack,
  860 MB without. (The release builds leave the originals out; see below.)
* Smoke test without a window: `WG_START=0 WG_AUTO=1 WG_STOP=2 WG_NOVIDEO=1 build/WaGang.app/Contents/MacOS/* --headless`.
  It should print `== scenario 0: R_00` … `== scenario 2: R_01`.

For distribution outside your own machines, sign with a Developer ID and notarize. Set `codesign/*` and
`notarization/*` in the preset.

### Windows

```sh
godot --headless --path game --export-release "Windows" ../build/windows/WaGang.exe
```

The preset exports `WaGang.exe` plus `WaGang.pck` (x86-64, no code signing; icon and version resources are not
modified, so no `rcedit` is needed). The `.pck` is the same on every platform, so it can be checked on a Mac:
`godot --headless --main-pack build/windows/WaGang.pck` with the smoke-test variables above.

## Automatic releases (GitHub Actions)

`.github/workflows/release.yml` builds and publishes both platforms on every push to `main` that changes the game
(pushes touching only `docs/`, Markdown files, `tools/` or `.gitignore` are skipped). It can also be started by
hand from the repository's **Actions** tab (*Release builds → Run workflow*).

* **Build number:** the workflow's run number *N*, which increases with every run. The release is tagged
  `build-N` and titled *Build N*; the game's version is `1.0.N`. The version is written into
  `application/config/version`, shown in the title screen's corner, and into the macOS bundle version. The
  repository itself keeps no version, so local builds show none.
* **Steps:** on an Ubuntu runner it installs Godot 4.7.2 and the macOS and Windows export templates (cached
  between runs), imports the project, exports `WaGang-macOS-build-N.zip` (universal, ad-hoc signed by Godot's
  built-in signer) and `WaGang-Windows-build-N.zip`, then creates the release with both files and install notes.
  A run takes about 5 minutes; each release is about 2.2 GB (macOS 1.09 GB, Windows 1.07 GB, HD art only).
* **HD graphics only:** the workflow downloads the HD graphics pack (`assets_hd.zip` from the release tagged
  `hd-pack`) and fails without it. It sets the presets' `exclude_filter` so the original pictures under
  `assets/gfx` stay out of the builds (palettes, index files and the terrain-patch index images stay). It then
  plays the first scenarios headless from the exported `.pck` and fails if any picture is missing. After
  rebuilding the pack, re-upload it (see [HD_GRAPHICS.md](HD_GRAPHICS.md)).

## Re-generating the game data

Everything under `game/assets/` is produced from the original game by the converters in `tools/`.

### Prerequisites

* The original game directory, placed at `wg2025/` in the repository root. It is not part of the repository. It
  contains `wagan.wa` (the executable), the `*.wa` / `*.e5` data archives, the `R_xx.wagan` / `S_xx.wagan` scripts,
  `SoundTrk/`, the `Se*.wav` sound effects and the `*.wmv` / `*.avi` videos.
* Python 3 with a virtual environment in `tools/venv`:
  ```sh
  python3 -m venv tools/venv
  tools/venv/bin/pip install pillow numpy pefile capstone av
  ```
* `ffmpeg` on the PATH for audio, and Homebrew's `ffmpeg-full` (it has libtheora) for video:
  `brew install ffmpeg ffmpeg-full`.

> **Path note:** the converters currently use absolute paths of the form `/Users/f2pgod/Downloads/rea/…` (constants
> such as `SRC`, `DST`, `ROOT`, `GAME`, `OUT` at the top of each script). If your checkout lives elsewhere, edit
> those constants or create a symlink at that path.

### Steps

Run from the repository root. Each step writes into `game/assets/`.

| # | Command | Produces |
|---|---|---|
| 1 | `tools/venv/bin/python -I tools/dump_image.py` | `data/exe_image.bin`: `wagan.wa`'s mapped sections as one flat image at 0x400000, used as the emulated memory |
| 2 | `cp wg2025/person.wa game/assets/data/person_wa.bin` | the mod's per-person graphics table, loaded at 0x55a000 |
| 3 | `tools/venv/bin/python -I tools/conv_data.py` | `data/*.json`: persons, classes, class families, items, shops, strategies, terrain, shapes, names, texts |
| 4 | `tools/venv/bin/python -I tools/eex.py` | `scripts/R_xx.json`, `scripts/S_xx.json`, `scripts/opcodes.json` (plus text listings in `extract/eex_txt/`) |
| 5 | `tools/venv/bin/python -I tools/conv_gfx.py` | `gfx/`: maps, terrain, unit sprites, portraits, story backgrounds and sprites, effects, icons, UI pieces, palettes, each with an `index.json` |
| 6 | `python3 -I tools/conv_audio.py` | `audio/bgm/NN.mp3` (CD tracks) and `audio/se/*.wav` (16-bit PCM) |
| 7 | `tools/conv_video.sh` | `video/*.ogv` (Theora/Vorbis) |
| 8 | see below | the two speech-bubble caps in `gfx/effects/kao/` |
| 9 | `python3 -I tools/mark_keep.py` | a `*.import` file with `importer="keep"` next to every asset |
| 10 | `godot --headless --path game --import` | Godot's import cache |

Notes:

* **Step 5** takes several minutes. `--only units,portraits` limits it to some groups (`palettes`, `maps`,
  `terrain`, `icons`, `ui`, `units`, `portraits`, `story`, `effects`), and `--quantize` reproduces the game's
  4-bit-per-channel colours. The formats are documented in [gfx.md](gfx.md).
* **Step 7:** the numbered and `END` videos have their first byte zeroed by the game (`0x30 → 0x00`); the script
  restores it before converting. Videos are scaled to at most 1280 px wide.
* **Step 8** is not part of `conv_gfx.py` yet. The duel screen's speech-bubble caps are 16×64 images that the atlas
  export writes as 64×16; reshape them:
  ```sh
  tools/venv/bin/python -I - <<'EOF'
  from PIL import Image
  d = 'game/assets/gfx/effects/kao/'
  for n in ('19ac0', '19ec0'):
      im = Image.open(d + n + '_64x16.png').convert('RGBA')
      out = Image.new('RGBA', (16, 64)); out.putdata(list(im.getdata())); out.save(d + n + '_16x64.png')
  EOF
  ```
* **Step 9 is required.** Godot only ships the raw PNG/JSON/MP3/WAV/OGV files (which the game loads at run time
  with `Assets.*`) if they are marked `importer="keep"`.

Then rebuild the HD graphics pack (`game/assets_hd/`) from the converted graphics and re-publish it:
`tools/venv/bin/python -I tools/upscale_assets.py`. See [HD_GRAPHICS.md](HD_GRAPHICS.md).

After converting, run the game once (`./run_game.sh`) and an automated smoke test (see
[DEVELOPMENT.md](DEVELOPMENT.md)) before exporting.
