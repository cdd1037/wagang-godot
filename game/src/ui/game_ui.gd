class_name GameUI
extends CanvasLayer
## Top-level UI: dialog, menus, popups, banners, captions, fades, cutscene video.

var dialog: DialogBox
var menu: ChoiceMenu
var video: VideoLayer
var fade_rect: ColorRect
var _popup_box: PanelContainer
var _popup_label: Label
var _banner: Label
var _caption_root: Control
var _caption_lines: Array[Label] = []
var _title_root: Control
var _strips: Array[Label] = []      # the two status panes of the top bar: chapter title (op 0x18), place (op 0x17)


func _init() -> void:
	layer = 20
	var cap := Control.new()
	cap.set_anchors_preset(Control.PRESET_FULL_RECT)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cap)
	_caption_root = cap

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_rect)

	# chapter titles are usually shown on a black screen, so they go above the fade
	_title_root = Control.new()
	_title_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_root)

	_banner = UIStyle.label("", 22, Color(1, 0.95, 0.7))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.visible = false
	add_child(_banner)

	for k in 2:
		var l := UIStyle.label("", 14, UIStyle.NAME_COLOR if k == 0 else UIStyle.TEXT_COLOR)
		l.position = Vector2(8, 2 + 19 * k)
		l.size = Vector2(256, 18)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(l)
		_strips.append(l)

	dialog = DialogBox.new()
	add_child(dialog)
	menu = ChoiceMenu.new()
	add_child(menu)

	_popup_box = PanelContainer.new()
	_popup_box.add_theme_stylebox_override("panel", UIStyle.panel_box())
	_popup_label = UIStyle.label("")
	_popup_box.add_child(_popup_label)
	_popup_box.visible = false
	add_child(_popup_box)

	video = VideoLayer.new()
	add_child(video)


func vsize() -> Vector2:
	return get_viewport().get_visible_rect().size


# ------------------------------------------------------------------ fades
func fade_to_black(t := 0.35) -> void:
	if Game.autoplay:
		fade_rect.color.a = 1.0
		return
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, t)
	await tw.finished


func fade_from_black(t := 0.35) -> void:
	if Game.autoplay:
		fade_rect.color.a = 0.0
		return
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 0.0, t)
	await tw.finished


func set_black(on: bool) -> void:
	fade_rect.color.a = 1.0 if on else 0.0


# ------------------------------------------------------------------ popup (click to close)
func popup(text: String, auto_close := 0.0) -> void:
	if Game.autoplay:
		if OS.get_environment("WG_TRACE_TEXT") != "":
			print("  [popup] ", text)
		return
	_popup_label.text = text
	_popup_box.visible = true
	_popup_box.reset_size()
	await get_tree().process_frame
	_popup_box.position = (vsize() - _popup_box.size) / 2
	if auto_close > 0:
		await wait_or_click(auto_close)
	else:
		await _wait_click()
	_popup_box.visible = false


## A timed message box (0x42f699 style 2, mod cave 0x407d33): it closes after (讯息显示速度 + 1) s, or on a click.
func message(text: String) -> void:
	await popup(text, 1.2 if Game.demo else Settings.message_hold())


func _wait_click() -> void:
	if Game.demo:
		await get_tree().create_timer(1.2).timeout
		return
	if Game.autoplay:
		await get_tree().process_frame
		return
	# a new press (counted by Game._input), so the click that closed the previous box is not reused
	# and a tap shorter than a frame is not missed; holding Ctrl skips
	var n := Game.clicks
	while Game.clicks == n and not Game.skip_held():
		await get_tree().process_frame


# ------------------------------------------------------------------ banners / captions
## kind 0 = title (top-centre), 1 = place name (top-left)
func banner(text: String, kind: int) -> void:
	if Game.autoplay:
		return
	_banner.text = text
	_banner.add_theme_font_size_override("font_size", 24 if kind == 0 else 18)
	_banner.reset_size()
	if kind == 0:
		_banner.position = Vector2((vsize().x - _banner.size.x) / 2, vsize().y * 0.35)
	else:
		_banner.position = Vector2(24, 20)
	_banner.modulate.a = 0
	_banner.visible = true
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.4)
	tw.tween_interval(1.4)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.4)
	await tw.finished
	_banner.visible = false


## Text of status pane k (0 = op 0x18 标题显示 via 0x47650f, 1 = op 0x17 地名显示 via 0x476612), kept until replaced.
func set_strip(k: int, text: String) -> void:
	_strips[k].text = text


func clear_strips() -> void:
	for l in _strips:
		l.text = ""


## Narration captions (op 0x2c → 0x4327ef), in a 640×80 strip at the bottom of the scene view (y 360..440).
## a1 = 0 clears the strip and starts at its top; a2 ≠ 0 starts a new line 24 px down (one past y 439 clears the
## strip and starts at the top again); otherwise the text goes on where the last one ended, and so does a "\n".
## The text types out at a character per 50 ms (a click shows the rest of the line). a3 ≠ 0 then holds: a click
## with 会话窗口不自动关闭, else 0.5 / 1.0 / 2.0 s by 讯息显示速度 (a click ends it sooner).
const CAP_TOP := 0x170
const CAP_X := 64.0       # column 8 of the text grid [G: 8 px a column]
const CAP_SIZE := 18
var _cap_pos := Vector2(CAP_X, CAP_TOP)


func caption(text: String, a1: int, a2: int, a3: int) -> void:
	if Game.autoplay:
		if OS.get_environment("WG_TRACE_TEXT") != "":
			print("  [caption] ", text)
		return
	if a2 != 0:
		_cap_pos = Vector2(CAP_X, _cap_pos.y + 24)
	if a1 == 0 or (a2 != 0 and _cap_pos.y > 0x1b7):
		clear_captions()
	var parts := text.split("\n")
	for i in parts.size():
		if i > 0:
			_cap_pos = Vector2(CAP_X, _cap_pos.y + 24)
		await _caption_part(parts[i])
	if a3 != 0:
		var h := Settings.caption_hold()
		if h < 0:
			await _wait_click()
		else:
			await wait_or_click(h)


func _caption_part(s: String) -> void:
	if s == "":
		return
	var l := UIStyle.label(s, CAP_SIZE)
	l.position = _cap_pos
	_caption_root.add_child(l)
	_caption_lines.append(l)
	var n := l.get_total_character_count()
	var clicks := Game.clicks
	if not Game.demo:
		for k in n:
			if Game.clicks != clicks or Game.skip_held():
				break
			l.visible_characters = k
			await get_tree().create_timer(0.05).timeout
	l.visible_characters = -1
	_cap_pos.x += Assets.font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, CAP_SIZE).x


## Wait `sec` seconds; a new click (or holding Ctrl) ends it sooner (0x42c646).
func wait_or_click(sec: float) -> void:
	var n := Game.clicks
	var t := 0.0
	while t < sec and Game.clicks == n and not Game.skip_held():
		await get_tree().process_frame
		t += get_process_delta_time()


func clear_captions() -> void:
	for c in _caption_lines:
		c.queue_free()
	_caption_lines.clear()
	_cap_pos = Vector2(CAP_X, CAP_TOP)


## Special technique name (绝招) banner.
func skill_banner(text: String) -> void:
	if Game.autoplay:
		return
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.7)
	band.position = Vector2(0, vsize().y * 0.4 - 36)
	band.size = Vector2(vsize().x, 72)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	var l := UIStyle.label(text, 40, Color(1, 0.85, 0.3))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(vsize().x, 56)
	l.position = Vector2(vsize().x, vsize().y * 0.4 - 28)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(bg, "color:a", 0.7, 0.08)
	tw.tween_property(bg, "color:a", 0.0, 0.2)
	tw.parallel().tween_property(l, "position:x", 0.0, 0.25)
	tw.tween_interval(0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(band, "modulate:a", 0.0, 0.25)
	await tw.finished
	for n in [bg, band, l]:
		n.queue_free()


func chapter_title(num: int, text: String) -> void:
	if Game.autoplay:
		print("  [chapter] ", num, " ", text)
		return
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_root.add_child(bg)
	var l1 := UIStyle.label("第 %d 章" % (num + 1) if num >= 0 else "", 20, Color(0.9, 0.8, 0.5))
	var l2 := UIStyle.label(text, 32, Color(1, 0.95, 0.8))
	for l in [l1, l2]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(vsize().x, 40)
		_title_root.add_child(l)
	l1.position = Vector2(0, vsize().y * 0.36)
	l2.position = Vector2(0, vsize().y * 0.36 + 40)
	_title_root.modulate.a = 0
	var tw := create_tween()
	tw.tween_property(_title_root, "modulate:a", 1.0, 0.6)
	tw.tween_interval(1.8)
	tw.tween_property(_title_root, "modulate:a", 0.0, 0.6)
	await tw.finished
	for c in _title_root.get_children():
		c.queue_free()
	_title_root.modulate.a = 1
