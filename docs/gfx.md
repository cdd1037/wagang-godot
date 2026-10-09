# wagan graphics / asset formats (gfx track)

Status: complete first pass (all files identified and converted); open questions in §9.
Exe = `wagan.wa` (CCZ Ekd5.exe + mod code in .text2 0x4d0000+). Addresses are VAs.

## 1. Global facts

### 1.1 Archive containers
* Ls12 (Koei LS11 family), reader `tools/ls12.py`. Archive class: open = 0x41fb35 (`File%sOpenErr`),
  read entry `i` into buffer = 0x41fc89(i, dst).
* **Hidden-offset obfuscation** (mod code 0x4d2600, hooked into the seek wrapper at 0x419211):
  for handles of Yueyue / ~zl1g.dat / ~kvr.db / ~gtl.dll / Buha / Giji / Ghai / Nao the seek position
  gets `+0x500 / +0x7cc / +0x2130 / +0x18c / +0x1f0 / +0x510 / +0x4000 / +0x4000` **unless** the file's
  first dword equals `"Ls12"` (check 0x4d249d vs dword 0x555460). In the shipped files only
  `yueyue.wa` is shifted (real Ls12 at file offset 0x500). `ls12.read_archive` handles this.
* **face.wa** is not portraits: it is a ZIP whose byte blocks `[0:0xc8]` and `[0x400:0x4c8]` are swapped.
  The launcher `wg.exe` (0x401160) un-swaps it to `%TEMP%\de1.dat` and unzips (minizip 0.18) the three
  battle-unit sprite archives `~gtl.dll`, `~kvr.db`, `~zl1g.dat` into %TEMP%; `wagan.wa` opens them with
  a GetTempPathA prefix (0x4d25c1). See `gfxcommon.face_zip_members()`.

### 1.2 Palettes (Fei.WA / Niuqun.wa / DeDe.WA)
* 768-byte entries, **stored as (B, R, G) triplets**: palette setter 0x47e867 writes byte0→blue,
  byte1→red, byte2→green (into RGBQUAD 0x4b9548 and PALETTEENTRY 0x4b9e10).
* Loader 0x41e050(index, kind): kind 0 = Niuqun.wa, 1 = Fei.wa, 2 = Dede.wa. Loads to 0x497770,
  shifts every byte `>>4`, builds a 16x16x16 RGB444→index lookup (0x42fcc6 → 0x4b1b28, used for
  blending), then 0x41e1f3 applies entries 10..245 (`0x47e867(10, 236, pal+30)`) with `<<4`
  (shift table 0x4ba228 initialised to 4). → the game displays `v & 0xF0` per channel.
  Our converter uses the full stored 8-bit values (option `--quantize` reproduces `&0xF0`).
* Indices 0..9 and 246..255 are never written: they are the Windows static colours (0 = black ...).
  In the files those slots contain placeholder `ff f7 00`.
* Indices 10..173 are identical in every palette (shared sprite/UI colours); 174..245 are per-image
  background colours. Hence sprites (units, RPG figures, icons) can be drawn with any palette.
* Fei.WA: 58 palettes = battle map N (HM N). Niuqun.wa: 337 palettes = Giji.WA image N.
  DeDe.WA: 4 palettes (0/2 = 246-colour game palettes, 1 = 6x6x6 web cube, 3 = 230-colour grey ramp).
  Helper: `tools/gfxpal.py`.

### 1.3 Battle maps (HM00-57.wa, Yun.wa, Xixi.wa)
* `Yun.wa` (= CCZ **Hexzmap.e5**, 59 entries, loader 0x44c1cb): `byte0 = W*3, byte1 = H*3`
  (map size in 16-px units), then `W*H` terrain bytes (cells 48x48, row-major). The exe divides by 3
  and stores W,H at 0x4b422c/0x4b422d.
* `HMnn.wa` (raw, not Ls12; loader 0x44c2e3 → thread 0x47c66b, reads ≤0x39a800 bytes): 8bpp,
  **stored as 48x48 cells, cell after cell in row-major cell order** (each cell 2304 bytes row-major),
  W*H cells, plus 2 trailing zero bytes (HM00 lacks the last 2 pixels). Palette = Fei.WA[nn].
* `Xixi.wa` (58 entries): 2px-per-16px = 6px-per-cell mini map ((W*6)x(H*6) bytes).

* Palette for map N = `Fei.WA[N]`: battle setup 0x44d13c/0x44d59c calls `0x41e050(byte [battle+0], 1)`;
  the same byte indexes Yun.wa (0x44c21b) and HM%02u (0x44c2e3). Yun.wa entry 58 (20x20) has no HM file.
* Terrain ids seen in Yun: 0..26, 28 (0 plain, 4 mountain, 8 bridge, 11 pond, 12 small river/moat,
  13 big river, 15 wall, 16 inside city, 23 houses ... — verified by overlaying on HM13). Names live in data.wa.
* Output: `gfx/maps/HMnn.png` (opaque RGB), `gfx/maps/minimap/HMnn.png`, `gfx/maps/index.json`.

### 1.4 Icons / terrain tiles / UI bitmaps (resource DLLs)
* `ItemIcon.dll` (105 icons) and `MgcIcon.dll` (31 strategy icons): ImageList builder 0x40b19e:
  bitmap id = `100 + 2*i + size` (size 0 = 16x16, 1 = 32x32). Masked lists use palette **index 0 as the
  colour key** (mask generator 0x40a58a compares the 8-bit pixel to the key index passed = 0).
  Lists: MgcIcon small unmasked / large masked (0x40b5d1/0x40b61d), ItemIcon small+large masked
  (0x40b669/0x40b6b5). `CmdIcon.dll`: 5 16x16 command icons (ids 100..104).
  Koei-original bitmaps have palette[0] = (247,0,255); mod-made item icons use (0,0,255) — both keyed by index.
* `Mapatr.dll`: 28 48x48 terrain-info pictures, id = 100 + terrain (0x46c675 adds 100..123 to an
  ImageList; the mod's extra 124..127 are loaded elsewhere).
* `mark.wa`: resource-only DLL loaded by mod code (LoadImageA wrapper 0x4d4144(id, hinst, &hbmp),
  handle 0x4cf2f4): ids 2/3 (8x80) message-window side pieces, 5 (24x24) speech mark.
* `XRes.dll`: used only by the launcher `wg.exe` (window skin: close/min buttons, title bar,
  400x120 dialog, 75x27 buttons; also cursors/strings). Not used by wagan.wa.
* `wagan.wa` RT_BITMAP: 106 (288x28) / 302 (288x24) = 12-button toolbar strips (24px cells, CreateToolbarEx),
  341-344 48x48 pictures, 350/351 16x16.
* Output: `gfx/icons/{items,strategies}/{small,large}/NNN.png`, `gfx/icons/commands/NNN.png`,
  `gfx/terrain/NN.png`, `gfx/ui/{exe,mark,xres}/<id>.png`, each dir with `index.json`.

## 2. Converter
`tools/venv/bin/python -I tools/conv_gfx.py [--quantize] [--only cat1,cat2] [--out DIR]`
(default out `game/assets/gfx/`). Local categories: palettes, maps, terrain, icons, ui; delegated:
units (`tools/gfx_units.py`), portraits (`tools/gfx_portraits.py`), story (`tools/gfx_story.py`:
rpg_sprites/backgrounds/screens), effects (`tools/gfx_effects.py`). Shared helpers: `tools/gfxcommon.py`,
`tools/gfxpal.py`, `tools/ls12.py`.

### 2.1 JSON index schemas (local categories)
* `maps/index.json`: `{maps:[{id, width, height (cells), cell:48, terrain:[[row...]...], image,
  pixel_size:[w,h], palette:"fei[N]", minimap, minimap_cell:6, source}]}`.
* `palettes/index.json` + `palettes/{fei,niuqun,dede}.json` (list of 256 `#rrggbb` per palette).
* `terrain/index.json`: `{tiles:[{terrain, file, size, resource_id, name_guess}]}`.
* `icons/index.json`: `{sets:{items|strategies:{icons:[{id, small, large}]}, commands:{icons:[{id,file}]}}}`.
* `ui/index.json`: `{items:[{source, resource_id, file, size, keyed_index0}]}`.

## 3. Battle unit sprites (face.wa → ~zl1g.dat / ~gtl.dll / ~kvr.db)
| temp file | CCZ original | entry | frames |
|---|---|---|---|
| `~zl1g.dat` | Unit_mov.e5 | 25344 B = 11 × 48x48 | 0-1 walk down, 2-3 walk up, 4-5 walk left, 6 stand down, 7 stand up, 8 stand left, 9-10 weak (kneel, low HP) |
| `~gtl.dll`  | Unit_atk.e5 | 49152 B = 12 × 64x64 | 0-3 attack down, 4-7 attack up, 8-11 attack left |
| `~kvr.db`   | Unit_spc.e5 | 11520 B = 5 × 48x48  | 0 defend down, 1 defend up, 2 defend left, 3 hurt, 4 cheer |
* 270 entries each (49 entries have 2 trailing zero bytes). Frames stacked vertically, 8bpp, index 0 =
  transparent, shared sprite palette range.
* **Right-facing frames are synthesised by horizontal mirroring** (row mirror 0x41edf7 / 0x41ee53):
  mov: walk-left pair (0x43fd89, 48x96) and stand-left (0x43fde6); atk: attack-left 4 frames
  (0x403ce1, 64x256); spc: defend-left (0x403f56).
* Direction code = unit byte +0x0f (0x43e320): 0 up, 1 right (mirror of left), 2 down, 3 left
  (attack loader 0x403b8f, jump table 0x403d75 picks frames 4-7 / mirrored 8-11 / 0-3 / 8-11).
* 64x64 attack frames are drawn centred on the 48px cell (offset -8,-8; CCZ convention, blitter not re-checked).
* **Entry index** (0x43fc48): `g = graphic_id(person)`; `entry = g*3 + min(unit.side,2)` if `g < 43`
  else `entry = g + 86`. unit byte +5 = side/colour variant: +0 red, +1 green, +2 blue (as rendered).
  Entries 0..128 = 43 generic graphics × 3 colours, 129..269 = single-colour graphics (g 43..183).
* `graphic_id(person)` (0x406947 → 0x406a75): person record = `[0x4d0048] + pid*0x48` (mod's 72-byte
  person table; pid = word +0 & 0xfff); class = byte **+0x2b**; override `v = person.wa[pid]`
  (**person.wa** = 1024-byte per-person sprite override table, loaded to 0x55a000 by 0x4d00fc);
  `tier = class % 3`. v=0 → `CLASS_TO_GRAPHIC[class]` (53-entry table built at 0x406950; classes ≥0x35 → 0x45);
  v=1..5 → `0x35 + 3*(v-1) + tier`; v=6 → `0x44 if class < 0x28 else 0x45`; v≥7 → `v + 0x3f`.
  Table + overrides are exported in `units/index.json` (`entry_index`).
* Output: `gfx/units/{mov,atk,spc}/NNN.png` (vertical strips) + `units/index.json`
  (`sheets.{mov,atk,spc}: {frame_w, frame_h, frames, frame_names, file_pattern}`, `mirroring`,
  `direction_codes`, `anchor`, `entry_index`).

## 4. Portraits (sge.wa, Nao.wa)
* One **face index f** selects all portrait variants:
  | set | source | size | transparency | used by |
  |---|---|---|---|---|
  | large | sge.wa RT_BITMAP `301 + f` (500 faces, f 0..499) | 120x120 24-bit | RGB(0,0,0) key | dialog windows (mod hooks at 0x45c6f4/0x46a05a → 0x4d4104/0x4d4134/0x4d4387) |
  | small | sge.wa RT_BITMAP `2301 + f` (222, sparse) | 80x80 24-bit | RGB(0,0,0) key | mod UI 0x4d4e8c (`0x4075a7() + 0x8fd`) |
  | classic | Nao.wa entry `f` (228; = CCZ Face.e5) | 64x80 8bpp | opaque | original code paths 0x41e6ee/0x42b405/0x431e7e/0x432f3f; palette DeDe.WA[0] |
* sge faces are blitted with `TransparentBlt(..., crTransparent=0)` (0x4d4242 → import 0x4cd07d), so pure
  black pixels are transparent. LoadImage wrapper 0x4d4144(id, hinst=[0x4cf100], &hbmp).
* **Face index** (0x4075a7(person)): `stored = dword person+4` of the runtime 72-byte person table
  ([0x4d0048]); this is the face field the data agent sees in data.wa (+0x0D in the 32-byte record).
  pid 0 (hero): `f = stored` (0..7 = hero expressions/costumes: 301..308 are the same hero with different
  expressions, 307 a comic face); pid 1: `0xe0` if `(flag&0xf)==4`, `0xdf` if `!(flag&0x80)`, else
  `stored+7`; pid 0x23: `0xd6` if `flag&0x10`; pid 8: `0xe2` if `flag&0x20`; pid 4: `0xe3` if `flag&0x40`;
  **everyone else `f = stored + 7`**. `flag` = game-state byte (0x409540 on 0x4b0770).
* There are no separate expression images per face; "expressions" = different face indices.
* Output: `gfx/portraits/{large,small,classic}/FFF.png`, `portraits/index.json`:
  `faces: {"f": [file]}` (large if present, else small, else classic), `faces_detail: {"f": {large, small,
  classic}}`, `sizes`, `face_index_rule`.

## 5. Story / RPG scenes
### 5.1 Scene backgrounds (Giji.WA + Niuqun.wa, Buha.wa)
* Giji.WA: 337 × 640x400 8bpp (+2 zero bytes on 292 entries); palette **Niuqun.wa[same index]**.
* Loader 0x40bc37: scene struct 0x4ac63c = `{byte kind, word image}` (written by the S-script scene op,
  EEX 0x27 change_scene — script agent: map its args to kind/image). **Giji entry = image + {kind0: 0,
  kind2: 40, kind1: 114}**; then `0x41e050(entry, 0)` = Niuqun[entry] and blit 640x400 at (0, 40)
  (screen is 640x480; scene view occupies y 40..439). Caches: 0x48bae4 (kind0), 0x48bae0 (kind2), 0x48bae8 (kind1).
  - kind 0 → entries 0..39: full-screen story CGs (paintings);
  - kind 2 → 40..113: isometric interior/exterior RPG rooms;
  - kind 1 → 114..336: more RPG scenes; 114 = world/region map picture.
* **Storage:** entries 0..39 and 114 are plain row-major; all others are stored as **8x8 tiles in
  row-major tile order (80x50 tiles)** (verified visually + tile-boundary statistics; the blitter 0x47e09b
  itself is row-major, so the de-tiling happens in the scene compositor). Converter outputs plain images.
* Buha.wa (296 entries, index = scene image id, word 0x4ac63d → 0x428857 → buffer 0x4aeb38): 14-byte header
  (LE words `[id, 100, 100, 1, 200, 100, 1]`), 2 bytes, then a 200x100 byte grid with values 0xFF/0xF0
  (scene walk/occlusion mask; exact semantics unverified). Word@8 (200) feeds the actor transform below.
  Exported as greyscale `backgrounds/buha/NNN.png`.
* Output: `gfx/backgrounds/NNN.png` + `backgrounds/index.json` (`images:[{entry, file, palette, storage,
  scene_kind, scene_image, blank}]`, `buha`).

### 5.2 RPG actor sprites (yueyue.wa)
* yueyue.wa = Ls12 archive at file offset 0x500 (hidden-offset trick), 960 entries of 48x1280 8bpp
  (20 frames of 48x64, index 0 transparent, shared sprite palette). **Character c = entries 2c (front view,
  facing down-left) and 2c+1 (back view, facing up-left)** → 480 characters.
* Cache loader 0x426c6a(c, slot) builds a 0x3c000-byte slot `[2c+1 | mirror(2c) | 2c | mirror(2c+1)]`
  (mirror = 0x41ee53 row flip); frame pointer 0x42b010 = `slot + (dir*20 + frame)*0xC00`,
  dir = actor word +0x2e, frame = actor word +0x2a. **Direction codes: 0 = up-left (NW, −X),
  1 = down-right (SE, +X, mirrored front), 2 = down-left (SW, +Y), 3 = up-right (NE, −Y, mirrored back).**
* Frames: 0 stand, 1/2 walk; 3..19 action poses (common: 3 kneel, 4/5 raise arm, 6 hand-to-head/sweat,
  8 bow, 12 lying/fallen; later frames are character specific). Action ids of the script ops presumably
  index these frames directly (script agent to confirm).
* **Coordinates** (0x4272c5, called from the actor draw loop 0x427a94): actor X = word +4, Y = word +6,
  Z = word +8 (isometric half-cells).
  `sx = 8*(X − Y) + 4*W − 8 − 8*camX`, `sy = 4*(X + Y) − 8*Z − 8*camY + 8`, W = Buha word@8 = 200,
  camX/camY = words 0x49ceb4/0x49ceb6 (scroll in 8-px units). The 48x64 frame is blitted with its top-left at
  `(sx, sy + 40 − 64)` (0x427b2b adds 40, 0x42a2c4 subtracts 64) → (sx, sy) = bottom-left foot point.
  +1 X = (+8, +4) px, +1 Y = (−8, +4) px.
* Actor creation 0x426db2(arg, sprite_id): 128 actor records of 0x40 bytes at 0x49cf68; sprite id = c is
  passed straight from the script.
* Output: `gfx/rpg_sprites/NNN.png` = 960x256 sheet (row = direction code, column = frame), `rpg_sprites/index.json`.

## 6. Full-screen pictures (GHAI.WA) and UI atlases
* GHAI.WA (22 entries): 0/13/14/15 title screens (0x42bd90 picks 0 or 13..15 via 0x41a284(0)+0xc, save
  dependent; palette DeDe[0]); 6 credits logo (DeDe[1] = 6x6x6 cube; 0x42b6f6); 7 GAME OVER (DeDe[2];
  0x42c12f); 12 轩辕学院 splash 640x480 (DeDe[3]; heavily dithered, looks noisy at 1:1 by design);
  1-3 64x64 emblems; 4 grey battle illustration; 5 stone-relief 624x384; 8-11 48x48 tiles;
  16-21 624x384 backdrops (camp, field, night, market, fog, plain; DeDe[0] fits best).
  Output `gfx/screens/NN.png` + `screens/index.json` (`role`, `palette`, `size`).

## 7. Effects and animations
### 7.1 "KoeiAnim" animation format (MCALL00-08.wa raw files, Xben.wa Ls12 entries)
* Header 20 bytes: `u8 n_rec, u8 n_img, u8 n_alpha, u8 has_pal, u32 delay_ms, u32 W, u32 H, u32 id`;
  then `n_rec` 20-byte records; `n_img` WxH 8bpp images (index 0 = transparent); `n_alpha` WxH 8-bit alpha
  maps; 768-byte palette if `has_pal` (MCALL00 only; **4-bit values 0..15**, B,R,G order → `gfxpal`
  scales ×17). Record: `[0] image, [1] layer (0xff none / <40), [2] p2, [3] p3, [4..7] u32 mode`,
  bytes 16..19 uninitialised garbage.
* Player object 0x492788 (MCALL) / 0x4917b0 (Xben): open 0x402f7f (stream thread 0x402574, header parse
  0x4028a6: obj+0x1c..0x1f = counts), play loop 0x403014: one record per `delay_ms` tick; draw 0x402cb5
  centres the WxH frame on the target point. mode 1 → alpha-map blend (alpha image p2, strength p3/16;
  0x430369→0x4300c8); mode 0 → weighted blend (background weight p2/16, image weight p3/16; 0x43030e→0x42fd5a;
  p2 = 0 → plain copy; (16,16) ≈ additive). Blending maps RGB back to palette via the RGB444 LUT 0x4b1b28.
* **MCALL00-08.wa** (= CCZ Mcall*.e5): 240x240 / 320x240 / 300x300 full-screen strategy animations
  (phoenix fire, 八阵 trigrams, ...). Loader 0x4217fe: `sprintf("MCALL%02u.WA", v % 100)`.
* **Xben.wa** (= CCZ Meff.e5, 2003 original): 58 small effect animations (64x64 .. 100x100, 216x50).
  Entries 52..56 are the animated weather panels (0x44a121 loads `0x34 + weather`).
* **Strategy → effect** (table 0x4866c0, 68 strategy ids, read at 0x4214cf): `v < 100` → Xben[v];
  `100..108` → MCALL(v−100) (then 0x4215f0 remaps the follow-up Xben effect: 1,3,5,7,0x16,0x39,0x0a or none);
  `255` → none. Exported in `effects/index.json` (`strategy_effect_table`).
* Output `gfx/effects/{mcall,xben}/NN/img_KK.png` (RGBA) + `alpha_KK.png` (L) + per-animation records in
  `effects/index.json` (`anim_format`, `mcall.anims`, `xben.anims`: size, delay_ms, records...).

### 7.2 Other battle graphics
| file | content | converter output |
|---|---|---|
| Jiqi.wa (16 × 64x64) | attack-range diagrams (blue unit, red reach; 8x8 grid of 8px cells); loaders 0x46fcb4/0x478164; index = attack-range type of the class | `effects/ranges/attack/NN.png` |
| Drink.wa (13 × 64x64) | strategy effect-area diagrams (red target, green area, arrows = lines); loader 0x46fdda | `effects/ranges/strategy/NN.png` |
| Xthree.wa (5 × 216x200) | weather panel backdrops, 4 frames of 216x50 each: 0 clear, 1 cloudy, 2 rain, 3 storm, 4 snow (loader 0x449f27 → Kao buffer +0x1c8e0) | `effects/weather/N.png` |
| Nima.wa (186 × 20736) | 3x3-cell (144x144) battle-map patches stored cell-by-cell like HM, for terrain changes (0x456140 rewrites the terrain grid at 0x4aeb38+0x640 and redraws); palette = current map | `effects/map_patches/NNN.png` (best-fit Fei preview) + `idx/NNN.png` (raw indices as grey) |
| Yoyo.wa (104 × 32x32) | item pictures drawn by the game itself (same art as ItemIcon.dll) | `effects/items32/NNN.png` |
| Qusi.wa (15 mixed) | small buttons (50x50), blue dragon-pattern window backgrounds 400x296 / 400x128, 576x72 sea panoramas, 3 pieces with 2-byte headers (dims unknown) | `effects/qusi/NN.png` |
| Kao.wa (raw 116960 B) | UI/battle sprite atlas read whole into buffer 0x4aeb50 (0x42ba29); pieces addressed by fixed offsets: 0x0 8x8 colour bars, 0x180 24x24 icons, 0xcc0.. 48x48 cursors/terrain overlays/fire/tents, 0x196c0.. 16x16 marks, 0x19ac0 64x16 bars, 0x1a2c0 16x16 status icons, 0x1b4c0 18x8 pieces | `effects/kao/<off>_<w>x<h>.png` |

## 8. File → role summary
| file | role (CCZ original) | format |
|---|---|---|
| HM00-57.wa | battle map bitmaps | raw 8bpp 48x48 cells + 2 bytes; palette Fei[N] |
| Yun.wa | terrain grids (Hexzmap.e5) | Ls12, `[W*3, H*3, W*H terrain]` |
| Xixi.wa | battle mini-maps | Ls12, (6W)x(6H) row-major |
| Fei.WA / Niuqun.wa / DeDe.WA | palettes (map / scene / misc) | Ls12, 768 B, B,R,G order |
| face.wa | ZIP (2 swapped blocks) of ~gtl.dll / ~kvr.db / ~zl1g.dat | — |
| ~zl1g.dat / ~gtl.dll / ~kvr.db | Unit_mov / Unit_atk / Unit_spc | Ls12, 270 each |
| person.wa | per-person unit-sprite override (→0x55a000) | 1024 bytes |
| sge.wa | 120x120 + 80x80 portraits | PE resource DLL, 24-bit DIB |
| Nao.wa | 64x80 portraits (Face.e5) | Ls12, 228, palette DeDe[0] |
| Kao.wa | UI/battle sprite atlas | raw |
| Giji.WA | story CGs + RPG scene backgrounds | Ls12, 337 × 640x400, rows or 8x8 tiles |
| Buha.wa | RPG scene masks | Ls12, 296 × (16 + 200x100) |
| yueyue.wa | RPG actor sprites | Ls12 @0x500, 960 × 48x1280 |
| GHAI.WA | title / logos / game over / backdrops | Ls12, 22 mixed |
| MCALL00-08.wa | full-screen strategy animations (Mcall*.e5) | KoeiAnim |
| Xben.wa | effect animations (Meff.e5) | Ls12 of KoeiAnim |
| Jiqi.wa / Drink.wa | attack-range / strategy-area diagrams | Ls12, 64x64 |
| Xthree.wa | weather panel backdrops | Ls12, 216x200 |
| Nima.wa | 3x3-cell map change patches | Ls12, 144x144 cell-tiled |
| Yoyo.wa | 32x32 item pictures | Ls12 |
| Qusi.wa | misc UI pieces | Ls12 |
| Fhua.wa | **text**: 1946 fixed 200-byte GBK records, read by 0x40bf56(dst, n) (`record n at n*200`, NUL-terminated at 200) — for the data/script agents | raw |
| ItemIcon/MgcIcon/CmdIcon.dll, Mapatr.dll, mark.wa, XRes.dll, exe RT_BITMAP | icons, terrain pictures, UI pieces | PE resources |
| data.wa, R_/S_xx.wagan | game data / scripts (other tracks) | — |

### 8.1 Videos (for the media track)
* Name table at 0x555060 (8-byte slots): 0 `LOG.avi`, 1 `OPE.avi` (absent), 2 `END.wmv`, 3 `PRE.wmv`,
  4.. `001.wmv`..`040.wmv` (only 001-008 shipped). Player entry 0x41f4bd(.., n ≤ 0x7f, ..) (CCZ MCI movie
  player) first calls mod code **0x4dd000(n), which opens the file for writing and sets byte 0 to 0x30**:
  the shipped WMVs have their first byte zeroed (ASF GUID `30 26 b2 75...` → `00 26 b2 75...`;
  Pre.wmv already restored). **Patch byte 0 to 0x30 (on a copy) before converting the videos.**

## 9. Open questions
* Unit side ↔ colour: entry `g*3 + side` gives red/green/blue for side 0/1/2; which army uses which side
  value is decided by the battle code (data agent).
* 64x64 attack-frame anchor (−8,−8) taken from CCZ convention, not re-verified in the blitter.
* Giji 8x8-tile storage: de-tiling location in the exe not found (rule used: entries 0..39 and 114 plain,
  rest tiled — verified visually on all samples).
* Buha mask semantics (0xFF/0xF0) and exact mapping to iso coordinates; header words 100,100,1,200,100,1.
* RPG action ids → frame numbers (script agent: ops 0x30/0x34); camera values set by change_scene.
* Nima patch → map/position selection (script op), so the correct palette per patch is only guessed.
* Kao.wa region table partially inferred (some items in the 48x48 run are not 48x48); Qusi 12-14 dims.
* MCALL blend formulas summarised from the dispatch code, not cycle-exact.
* MCALL `layer` byte ([1] < 40) meaning (MCALL00 uses 0).
