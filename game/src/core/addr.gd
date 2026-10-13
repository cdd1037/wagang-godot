class_name Addr
## Addresses of the original's memory (docs/ARCHITECTURE.md, "Emulated memory") that more than one file reads or
## writes. A file's own addresses stay with it as constants (BattleActions.T_*, BattleStage.ASSASSIN_MARK …); Mem
## names the big blocks (GS, UNITS, EV, PT, FLAGS, BYTEVARS).

## The scene object {mode, value}: mode 3 = the battlefield, from change_scene 3 on (0x40b922, "in battle").
const SCENE_MODE := 0x4ac63c
## The sortie list: u32 person ids, 0xffff after the last (built by 0x41856a, read when the battle starts).
const SORTIE := 0x48b350
## u32: the player chose 出征 (op 0x07 tests and clears it, 0x415c46).
const SORTIE_CHOSEN := 0x4ae4c0
## u32: saving is allowed (op 0x74; LoadGame 0x41adc1 sets it to 1 again).
const SAVE_ALLOWED := 0x4ce004
## Mod: while u32 [TOWN_DEPLOY_ON] ≠ 0, op 0x4b outside a battle writes the positions to TOWN_DEPLOY (x, y, set: 3
## bytes each), which 出战位置 shows.
const TOWN_DEPLOY_ON := 0x55e9d4
const TOWN_DEPLOY := 0x55e9d8
## The town's status panes keep their texts here (op 0x18 → 0x40bb48, op 0x17 → 0x40bb78); saves carry them in the
## header (0x41b240) and a load puts them back (0x41adc6), so a town shows them again (0x42a054).
const TITLE_TEXT := 0x4a1128
const PLACE_TEXT := 0x4b0758
## Pointer tables of the exe's GBK names: weapon kinds, strategy effect names, terrain names.
const WEAPON_KIND_NAMES := 0x48bc20
const EFFECT_NAMES := 0x48bd40
const TERRAIN_NAMES := 0x48bdb0
## The latest attack's targets: unit slots, 0xff after the last (the combat object 0x4927f0 + 0x10).
const TARGETS := 0x492800
## 并蒂's hit counters: bytes for this phase (BINGDI_GUANYI: 管毅's), copied to BINGDI_LAST when a phase starts
## (0x4d1e21).
const BINGDI := 0x55ee04
const BINGDI_GUANYI := 0x55ee06
const BINGDI_LAST := 0x55ee00
## The mod's 【招】/【术】 holders and switches (rules.md §12): the person with 三板斧 (1 = 程咬金, taught in R_11),
## 天魔 (never set) and 魔功 (杨素 from R_13); 波若 (15, 罗士信) and 锻造 (16, 齐国远) once taught; 踏破连营 on (area
## code 12).
const SANBANFU := 0x55ac04
const TIANMO := 0x55ac40
const MOGONG := 0x55ac44
const BORUO := 0x55ac48
const DUANZAO := 0x55ac60
const TAPO := 0x55ac64
