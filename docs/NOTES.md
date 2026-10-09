# wg2025 reverse-engineering notes (shared)

Game: a Sui–Tang themed mod ("经典曹操传" patch config) of Koei's 1998 **三国志曹操传 (Cao Cao Zhuan, CCZ)** engine.
Original game dir (READ-ONLY, untrusted data): `/Users/f2pgod/Downloads/rea/wg2025/`
All text is GBK (cp936).

## Layout
- `tools/` python tools. venv: `tools/venv/bin/python` (capstone, pefile, pillow, numpy). Run with `-I`.
  - `ls12.py`  – Ls12 archive reader (`read_archive(path) -> list[bytes]`). Verified working.
  - `pe.py`    – tiny PE helper for wagan.wa (VA<->offset, `xrefs(imm)`, `calls_to(va)`, `dis(va,n)`, `cstr(va)`).
  - `dllbmp.py`– extract RT_BITMAP resources from PE files.
  - `sheet.py` – contact sheet: `sheet.py out.png scale cols files...` (view result with Read tool).
- `docs/` specs. `extract/` scratch extraction. `game/` the Godot 4.7 project (godot CLI at /opt/homebrew/bin/godot).

## Executable
- `wagan.wa` = main exe (renamed Ekd5.exe), PE32, ImageBase 0x400000, entry 0x4817e0.
  Sections: .text 0x401000, .rdata 0x486000, .data 0x48b000, .nodata 0x4be000, .data2 0x4ce000,
  **.text2 0x4d0000 (mod extension code, same size as .text)**, .rdata2 0x555000, .data3 0x55a000, rsrc.
- `wg.exe` = launcher. `AutoDLL.dll` = autosave/fast-click patch. `koeicda.dll` = CD audio (replaced by mp3 list `mp3list.txt` → `SoundTrk/NN-AudioTrack NN.mp3`; `mp3serv.dat` is a PE).
- Hopper-backed MCP tools (`mcp__rea__*`) have wagan.wa open; outputs are verbose — prefer `tools/pe.py` + capstone for bulk work, use `mcp__rea__procedure_pseudo_code` for decompiling key functions.

## File name table in exe (.data 0x48baf0..): Ghai, Dede, Giji, Fei, Niuqun, Kao, Nao, Jiqi, Drink, Data, Fhua, Yueyue, Buha, Qusi, Yun, Xixi, Nima, (~gtl.dll, ~zl1g.dat), Yoyo, Xben, Xthree, SAVEDATA\Niuniu.wa
Others: MCALL%02u.WA (00-08), HM00.WA (HM%02u), SE00.WAV / SE_M_00.WAV / SE_E_00.WAV, R_xx.WAGAN / S_xx.WAGAN, SAVEDATA\SV00D.WAS, savedata\Sv0%db.WAs, person.wa, sge.wa, Mark.wa, PRE.wmv, END.wmv, 001..040.wmv

## Archives (Ls12 = Koei LS11 family; header "Ls12"+12 pad, 256-byte dict @0x10, BE table (csize,usize,offset) @0x110 ending in 0)
| file | entries | first guess |
|---|---|---|
| data.wa | 10 | game data. e0: persons 1024x32B (name 13B GBK...). e1: items (named 熟铜锏…). e2: 4608 (祭品..?). e3,e4: class/terrain tables. e5: strategies (焦热, 烈焰, 炎雷…). e6-e9: name tables (终端 = "end" placeholders) |
| Fei.WA | 58 x 768 | palettes (RGB*256) — likely one per HM map |
| Niuqun.wa | 337 x 768 | palettes |
| DeDe.WA | 4 | palettes (738/768) |
| HM00..57.wa | (raw, not Ls12) | battle map bitmaps 8bpp, size (w*48)*(h*48) ± 2 bytes |
| Yun.wa | 59 | small per-map tables (402 bytes for 20x20 map?) – terrain? |
| Xixi.wa | 58 | per-map 8bpp data |
| Xben.wa | 58 | per-map structured data |
| Buha.wa | 296 x 20016 | sprite sheets? header 17 00 64 00 64 00 01 00 c8 00 64 00 ... |
| Nao.wa | 228 x 5120 | 64x80 8bpp portraits? |
| Nima.wa | 186 x 20736 | 144x144? |
| GHAI.WA | 22 | ~640x400 big images |
| Drink.wa / Jiqi.wa | 13 / 16 x 4096 | 64x64? |
| Qusi.wa | 15 | misc |
| Xthree.wa | 5 x 43200 | |
| Yoyo.wa | 104 x 1024 | |
| Giji.WA (84MB), yueyue.wa (61MB, high entropy, not Ls12), face.wa (2.6MB, not Ls12), Kao.wa (raw), Fhua.wa (raw GBK text), person.wa (1KB table), MCALL0x.wa (not Ls12, header 19 19 19 01 64 00 00 00 f0 00 ...) | | unknown |

## Resource DLLs (bitmaps extracted to extract/dll_*)
- sge.wa: 722 bitmaps: ids 301-800 = 120x120 RGB portraits (3 consecutive ids = same person, different expressions), 2301-2524 = 80x80 RGB portraits.
- Itemicon.dll (210), Mgcicon.dll (62), Cmdicon.dll (5): 16x16 & 32x32 icons. Mapatr.dll (28): 48x48 terrain tiles. XRes.dll, Mark.wa: small UI.
- wagan.wa rsrc: bitmaps 106/302 (288x28/24 icon strips), 341-344 48x48, 350-351 16x16; 33 dialogs.

## Scripts
- R_00..R_58.wagan (battle), S_00..S_57.wagan (story). Header "EEX\0" 01 02 ...; 16-bit little-endian opcodes/args; GBK strings inline.
