class_name SettingsWindow
extends DlgPanel
## 环境设定 (dialog KANKYOU, 163×232; proc 0x41badd, init 0x41bdb1 + mod 0x4d970c, apply 0x41b92d + mod 0x4dbe6b),
## opened from the title (0x41c001) and the menu (command 107, 0x474de8). 确定 applies the options; both buttons
## then write Niuniu.wa (mod 0x4e2000). The skin choice is previewed on this window before 确定.
## 战斗时，窗口自动最大化 sizes the Win32 window, so it is shown but cannot be changed here.

const CHECKS := [[Settings.BGM, "听背景音乐", 34], [Settings.SE, "听音效", 49],
	[Settings.MAXIMIZE, "战斗时，窗口自动最大化", 64], [Settings.MINIMAP, "战斗时，自动显示战场缩小图", 79],
	[Settings.NO_AUTO_CLOSE, "会话窗口不自动关闭", 94]]
## Radio buttons left to right: [label, value] (tables 0x48b4f8 / 0x48b508: 0 is 快 in both groups).
const MSG_RADIOS := [["慢", 2, 29], ["普通", 1, 69], ["快", 0, 109]]
const MOVE_RADIOS := [["快", 0, 29], ["普通", 1, 69], ["慢", 2, 109]]

var _bits := 0
var _level := false
var _msg := 0
var _move := 0
var _skin := 0
var _combo := false
var _saved := false


static func open(ui: CanvasLayer) -> void:
	var w := SettingsWindow.new()
	w.dlu = Vector2(163, 232)
	w.dlu_scale = Vector2(2.2, 1.85)
	Audio.se(0)
	await DlgPanel.run(ui, w)


func _ready() -> void:
	super._ready()
	_bits = Mem.r16(Mem.GS)
	_level = Mem.r8(Settings.LEVEL_DETAIL) != 0
	_msg = Settings.message_speed()
	_move = Settings.move_speed()
	_skin = Settings.skin()
	skin = _skin


func _draw_dialog() -> void:
	text(r(9, 6, 144, 10), "请点击项目以设定。")
	text(r(9, 20, 144, 10), "设定结束后请选择[确定]。")
	for c in CHECKS:
		var bit: int = c[0]
		_check(r(9, c[2], 144, 14), str(c[1]), _bits & bit != 0, ["bit", bit], bit != Settings.MAXIMIZE)
	_check(r(9, 109, 144, 15), "升级显示能力成长", _level, ["level", 0])
	group(r(9, 125, 144, 25), "讯息显示速度")
	for c in MSG_RADIOS:
		_radio(r(c[2], 138, 32, 8), str(c[0]), _msg == int(c[1]), ["msg", c[1]])
	group(r(9, 155, 144, 24), "武将移动速度")
	for c in MOVE_RADIOS:
		_radio(r(c[2], 167, 32, 8), str(c[0]), _move == int(c[1]), ["move", c[1]])
	text(r(10, 187, 48, 10), "对话框花色")
	var box := r(61, 185, 61, 12)
	draw_rect(box, Color(0, 0, 0.05, 0.6))
	draw_rect(box, UIStyle.BORDER_IN, false, 1.0)
	if hovered(["combo", -1]):
		draw_rect(box, HOVER)
	text(Rect2(box.position + Vector2(5, 0), box.size), str(Settings.SKINS[clampi(_skin, 0, 4)]))
	text(Rect2(box.position, box.size - Vector2(4, 0)), "▼", HORIZONTAL_ALIGNMENT_RIGHT, UIStyle.TEXT_COLOR, SMALL_SIZE)
	hit(box, ["combo", -1])
	button(r(22, 208, 50, 14), "确定", ["ok", 0])
	button(r(91, 208, 50, 14), "取消", ["cancel", 0])
	if _combo:
		var lr := Rect2(box.position + Vector2(0, box.size.y), Vector2(box.size.x, box.size.y * Settings.SKINS.size()))
		draw_rect(lr, Color(0.05, 0.07, 0.16, 0.98))
		draw_rect(lr, UIStyle.BORDER_IN, false, 1.0)
		for i in Settings.SKINS.size():
			var rr := Rect2(lr.position + Vector2(0, box.size.y * i), box.size)
			if i == _skin:
				draw_rect(rr, UIStyle.HILITE)
			if hovered(["skin", i]):
				draw_rect(rr, HOVER)
			text(Rect2(rr.position + Vector2(5, 0), rr.size), str(Settings.SKINS[i]))
			hit(rr, ["skin", i])


func _check(rect: Rect2, label: String, on: bool, key: Array, enabled := true) -> void:
	var b := Rect2(rect.position + Vector2(0, (rect.size.y - 13) / 2), Vector2(13, 13))
	draw_rect(b, Color(0, 0, 0.05, 0.6))
	draw_rect(b, UIStyle.BORDER_IN if enabled else DIM, false, 1.0)
	if on:
		var c := UIStyle.NAME_COLOR if enabled else DIM
		draw_polyline(PackedVector2Array([b.position + Vector2(3, 7), b.position + Vector2(6, 10), b.position + Vector2(11, 3)]), c, 2.0)
	if enabled and hovered(key):
		draw_rect(rect, HOVER)
	text(Rect2(rect.position + Vector2(19, 0), rect.size - Vector2(19, 0)), label, HORIZONTAL_ALIGNMENT_LEFT,
		UIStyle.TEXT_COLOR if enabled else DIM)
	if enabled:
		hit(rect, key)


func _radio(rect: Rect2, label: String, on: bool, key: Array) -> void:
	var c := rect.position + Vector2(6, rect.size.y / 2)
	draw_circle(c, 6, Color(0, 0, 0.05, 0.6))
	draw_arc(c, 6, 0, TAU, 20, UIStyle.BORDER_IN, 1.0)
	if on:
		draw_circle(c, 3, UIStyle.NAME_COLOR)
	if hovered(key):
		draw_rect(rect, HOVER)
	text(Rect2(rect.position + Vector2(15, 0), rect.size - Vector2(15, 0)), label)
	hit(rect, key)


func _on_hit(key: Variant) -> void:
	var k: Array = key
	if _combo and k[0] != "skin":
		_combo = false
		return
	match k[0]:
		"bit":
			_bits ^= int(k[1])
		"level":
			_level = not _level
		"msg":
			_msg = int(k[1])
		"move":
			_move = int(k[1])
		"combo":
			_combo = not _combo
		"skin":
			# CBN_SELENDOK: the window shows the pattern at once
			_skin = int(k[1])
			skin = _skin
			_combo = false
		"ok":
			_apply()
			_finish(true)
		"cancel":
			_finish(false)


## 0x41b92d + mod 0x4dbe6b.
func _apply() -> void:
	var w := Mem.r16(Mem.GS)
	var mask := 0
	for c in CHECKS:
		mask |= int(c[0])
	Mem.w16(Mem.GS, (w & ~mask) | (_bits & mask))
	Mem.w8(Mem.GS + 0x10, _msg)
	Mem.w8(Mem.GS + 8, _move)
	Audio.apply_switches()
	Mem.w8(Settings.LEVEL_DETAIL, 1 if _level else 0)


func _finish(ok: bool) -> void:
	var skin_changed := ok and _skin != Settings.skin()
	if skin_changed:
		Mem.w32(Settings.SKIN, _skin)
	Settings.save_file(skin_changed)
	_saved = true
	close()


func close() -> void:
	if not _saved:
		_saved = true
		Settings.save_file(false)        # Esc / right click = 取消, which writes the file too
	super.close()


func _on_key(ev: InputEvent) -> bool:
	if ev.is_action_pressed("ui_accept"):
		_apply()
		_finish(true)
		return true
	return false
