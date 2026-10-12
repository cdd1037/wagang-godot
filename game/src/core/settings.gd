class_name Settings
extends RefCounted
## 环境设定 (dialog KANKYOU; init 0x41bdb1, apply 0x41b92d, mod 0x4d970c / 0x4dbe6b). The options live where the
## original keeps them: bits of the GS+0 word, GS+8 (武将移动速度), GS+0x10 (讯息显示速度), byte [0x4dbe25]
## (升级显示能力成长) and dword [0x492e20] (对话框花色). SAVEDATA\Niuniu.wa holds them across sessions: bytes 1..5 =
## GS+0, GS+1, GS+8, GS+0x10, [0x4dbe25] (mod 0x4e2000 / 0x4e20ff) and byte 0x6b = the skin (0x40af77). They are
## read each time the title screen starts (0x41bf67) and written when the dialog closes. Saves do not carry them
## (the save loader 0x40cc65 skips GS+0, +8 and +0x10), so they are put back after Mem is reset or restored.

const BGM := 0x2000            # 听背景音乐
const SE := 0x1000             # 听音效
const MAXIMIZE := 0x4000       # 战斗时，窗口自动最大化 (a Win32 window size; nothing to do here)
const MINIMAP := 0x8000        # 战斗时，自动显示战场缩小图
const NO_AUTO_CLOSE := 0x800   # 会话窗口不自动关闭
const LEVEL_DETAIL := 0x4dbe25
const SKIN := 0x492e20
## 0x40af14: the combobox entries; 0..3 tile GHAI.WA 8..11 under the windows, 4 (无) the plain colour.
const SKINS := ["花色１", "花色２", "花色３", "花色４", "无"]
const SPEEDS := ["快", "普通", "慢"]    # GS+0x10 and GS+8 values 0, 1, 2

## Bytes 1..5 and 0x6b of Niuniu.wa as last read at the title (or set by the dialog).
static var _b := PackedByteArray()
static var _skin := 0


## Title start (0x4092da → 0x4e20ff, skin 0x40b088): read the file, then apply.
static func load_file() -> void:
	var nb := SpecialFuncs.read_niuniu()
	_b = nb.slice(1, 6)
	_skin = nb[0x6b]
	apply()


## Put the options into Mem (after Mem.reset() / restore()).
static func apply() -> void:
	if _b.is_empty():
		load_file()
		return
	Mem.w8(Mem.GS, _b[0])
	Mem.w8(Mem.GS + 1, _b[1])
	Mem.w8(Mem.GS + 8, _b[2])
	Mem.w8(Mem.GS + 0x10, _b[3])
	Mem.w8(LEVEL_DETAIL, _b[4])
	Mem.w32(SKIN, _skin)


## 0x4e2000 after the dialog (OK or 取消): Mem → bytes 1..5; the skin byte only when OK changed it (0x40af77).
static func save_file(skin_changed: bool) -> void:
	_b = PackedByteArray([Mem.r8(Mem.GS), Mem.r8(Mem.GS + 1), Mem.r8(Mem.GS + 8), Mem.r8(Mem.GS + 0x10),
		Mem.r8(LEVEL_DETAIL)])
	_skin = Mem.r32(SKIN)
	for i in 5:
		SpecialFuncs.write_niuniu(1 + i, _b[i])
	if skin_changed:
		SpecialFuncs.write_niuniu(0x6b, _skin & 0xff)


static func on(bit: int) -> bool:
	return Mem.r16(Mem.GS) & bit != 0


static func set_bit(bit: int, v: bool) -> void:
	var w := Mem.r16(Mem.GS)
	Mem.w16(Mem.GS, (w | bit) if v else (w & ~bit))


## 讯息显示速度: 0 快, 1 普通, 2 慢.
static func message_speed() -> int:
	return Mem.r8(Mem.GS + 0x10)


## 武将移动速度: 0 快, 1 普通, 2 慢.
static func move_speed() -> int:
	return Mem.r8(Mem.GS + 8)


static func skin() -> int:
	return Mem.r32(SKIN)


## A dialogue page's hold when it does not wait for a click (tables 0x42d5e1 / 0x42d96a): 1.5 / 1.0 / 2.0 s for
## 快 / 普通 / 慢; -1 = wait for a click (会话窗口不自动关闭, or speed 3); 0 = none (speed > 3).
static func dialogue_hold() -> float:
	var s := message_speed()
	if on(NO_AUTO_CLOSE) or s == 3:
		return -1.0
	return [1.5, 1.0, 2.0][s] if s < 3 else 0.0


## A caption's hold after a line with a pause (op 0x2c, 0x432a34): 0.5 / 1.0 / 2.0 s, or a click.
static func caption_hold() -> float:
	var s := message_speed()
	if on(NO_AUTO_CLOSE) or s == 3:
		return -1.0
	return [0.5, 1.0, 2.0][s] if s < 3 else 0.0


## A timed message box (style 2, mod cave 0x407d33): it closes after (speed + 1) s; a click closes it sooner.
static func message_hold() -> float:
	return float(message_speed() + 1)


## Battle walk, one cell (0x44201b): 48 / s frames of 50 ms, s from the speed and whether the family is a mounted
## one (Rules.mounted_family).
static func cell_time(family: int) -> float:
	var sp := clampi(move_speed(), 0, 2)
	var s: int = ([48, 24, 12] if Rules.mounted_family(family) else [48, 12, 6])[sp]
	return 0.05 * (48 / s)


## The story-scene frame period (0x429908): GS+8 × 50 ms; 快 is not throttled at all, here one display frame.
static func scene_frame() -> float:
	var sp := move_speed()
	return 1.0 / 60.0 if sp == 0 else 0.05 * sp
