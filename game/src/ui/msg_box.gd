class_name MsgBox
extends DlgPanel
## The game's Win32 message boxes: the OK box (dialog 339, 0x474b78 / 0x474b59 with a title) and the yes/no box
## (dialog 340, 是 / 否, 0x474b0f), the app icon beside the text. Also 版本情报 (dialog 348).

var lines: PackedStringArray = []
var title := ""
var buttons: Array = []         # [label, result]
var result := 0
var icon_tex: Texture2D


static func ok(ui: CanvasLayer, text: String, caption := "") -> void:
	if Game.autoplay:
		return
	await _run(ui, text, caption, [["确定", 1]])


static func yes_no(ui: CanvasLayer, text: String, caption := "瓦岗山异闻录") -> bool:
	if Game.autoplay:
		return true
	return await _run(ui, text, caption, [["是", 1], ["否", 0]]) == 1


## 版本情报 (dialog 348): the icon, the title and the copyright line, 确定.
static func version(ui: CanvasLayer) -> void:
	await _run(ui, "兴唐传·瓦岗山异闻录【归唐之章完结篇】\n轩辕学院 2005,2024", "版本情报", [["确定", 1]])


static func _run(ui: CanvasLayer, text: String, caption: String, btns: Array) -> int:
	var w := MsgBox.new()
	w.lines = text.split("\n")
	w.title = caption
	w.buttons = btns
	w.dlu_scale = Vector2.ONE
	var f := Assets.font()
	var tw := 0.0
	for l in w.lines:
		tw = maxf(tw, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x)
	tw = maxf(tw, f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x)
	var lh := f.get_height(TEXT_SIZE) + 4
	w.dlu = Vector2(maxf(tw + 76, 100.0 * btns.size() + 40), (28 if caption != "" else 8) + maxf(lh * w.lines.size(), 34) + 56)
	await DlgPanel.run(ui, w)
	return w.result


func _ready() -> void:
	super._ready()
	icon_tex = Assets.tex("gfx/ui/exe/icon137.png")


func _draw_dialog() -> void:
	var y := 8.0
	if title != "":
		text(r(10, 4, dlu.x - 20, 20), title, HORIZONTAL_ALIGNMENT_LEFT, CAPTION)
		draw_line(origin + Vector2(6, 26), origin + Vector2(dlu.x - 6, 26), FRAME)
		y = 32.0
	if icon_tex:
		draw_texture_rect(icon_tex, r(12, y, 32, 32), false)
	var lh := Assets.font().get_height(TEXT_SIZE) + 4
	for i in lines.size():
		text(r(56, y + lh * i, dlu.x - 64, lh), lines[i])
	var bw := 90.0
	var gap := 14.0
	var x := (dlu.x - bw * buttons.size() - gap * (buttons.size() - 1)) / 2
	for b in buttons:
		button(r(x, dlu.y - 40, bw, 28), str(b[0]), ["btn", b[1]])
		x += bw + gap


func _on_hit(key: Variant) -> void:
	if key is Array and key[0] == "btn":
		result = int(key[1])
		close()


func _on_key(ev: InputEvent) -> bool:
	if ev.is_action_pressed("ui_accept"):
		result = int(buttons[0][1])
		close()
		return true
	return false
