class_name ChoiceMenu
extends Control
## Vertical selection menu. `var i = await menu.choose(["a","b"], pos, cancellable)`
## Returns the chosen index, or -1 when cancelled.

signal chosen(index: int)

const ROW_H := 24
const PAD := 10

var items: PackedStringArray = []
var enabled: Array = []
var sel := 0
var cancellable := true
var title := ""
var _rect := Rect2()
var _active := false
var _min_width := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func choose(options: Array, at := Vector2(-1, -1), can_cancel := true, header := "", enabled_mask: Array = [], min_width := 0.0) -> int:
	items = PackedStringArray(options)
	enabled = enabled_mask if enabled_mask.size() == options.size() else []
	cancellable = can_cancel
	title = header
	_min_width = min_width
	sel = 0
	while not _is_enabled(sel) and sel < items.size() - 1:
		sel += 1
	var f := Assets.font()
	var w := _min_width
	for s in items:
		w = maxf(w, f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.FONT_SIZE).x)
	if title != "":
		w = maxf(w, f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.FONT_SIZE).x)
	var h := items.size() * ROW_H + PAD * 2 + (ROW_H if title != "" else 0)
	var vs := get_viewport_rect().size
	var pos := at
	if pos.x < 0:
		pos = (vs - Vector2(w + PAD * 2 + 16, h)) / 2
	pos.x = clampf(pos.x, 0, vs.x - (w + PAD * 2 + 16))
	pos.y = clampf(pos.y, 0, vs.y - h)
	_rect = Rect2(pos, Vector2(w + PAD * 2 + 16, h))
	visible = true
	_active = true
	queue_redraw()
	if Game.autoplay or Game.demo:
		if Game.demo:
			await get_tree().create_timer(1.0).timeout
		await get_tree().process_frame
		visible = false
		_active = false
		var pick := 0
		var opts := []
		for k in items.size():
			if _is_enabled(k):
				opts.append(k)
		if not opts.is_empty():
			pick = opts[Rules.rand(opts.size())] if OS.get_environment("WG_RANDOM") != "" else opts[0]
		if OS.get_environment("WG_TRACE_TEXT") != "":
			print("  [menu] %s -> %s" % [items, items[pick] if pick < items.size() else "?"])
		return pick
	var r: int = await chosen
	visible = false
	_active = false
	return r


func _is_enabled(i: int) -> bool:
	return enabled.is_empty() or (i < enabled.size() and enabled[i])


func _row_rect(i: int) -> Rect2:
	var y0 := _rect.position.y + PAD + (ROW_H if title != "" else 0)
	return Rect2(_rect.position.x + 4, y0 + i * ROW_H, _rect.size.x - 8, ROW_H)


func _draw() -> void:
	UIStyle.draw_panel(self, _rect)
	if title != "":
		UIStyle.draw_text(self, Vector2(_rect.position.x + PAD + 8, _rect.position.y + PAD + 17), title, UIStyle.NAME_COLOR)
	for i in items.size():
		var rr := _row_rect(i)
		if i == sel:
			draw_rect(rr, UIStyle.HILITE)
		var col := UIStyle.TEXT_COLOR if _is_enabled(i) else Color(0.55, 0.55, 0.6)
		UIStyle.draw_text(self, Vector2(rr.position.x + PAD + 4, rr.position.y + 17), items[i], col)


func _move(d: int) -> void:
	if items.is_empty():
		return
	for k in items.size():
		sel = (sel + d + items.size()) % items.size()
		if _is_enabled(sel):
			break
	Audio.se(0)
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if not _active:
		return
	if ev is InputEventMouseMotion:
		for i in items.size():
			if _row_rect(i).has_point(ev.position) and sel != i and _is_enabled(i):
				sel = i
				queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			for i in items.size():
				if _row_rect(i).has_point(ev.position) and _is_enabled(i):
					sel = i
					_finish(i)
					return
		elif ev.button_index == MOUSE_BUTTON_RIGHT and cancellable:
			_finish(-1)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_move(-1)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_move(1)
	accept_event()


func _unhandled_input(ev: InputEvent) -> void:
	if not _active:
		return
	if ev.is_action_pressed("ui_up"):
		_move(-1)
	elif ev.is_action_pressed("ui_down"):
		_move(1)
	elif ev.is_action_pressed("ui_accept"):
		if _is_enabled(sel):
			_finish(sel)
	elif ev.is_action_pressed("ui_cancel") and cancellable:
		_finish(-1)
	else:
		return
	get_viewport().set_input_as_handled()


func _finish(i: int) -> void:
	_active = false
	Audio.se(1 if i >= 0 else 2)
	chosen.emit(i)
