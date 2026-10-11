class_name Minimap
extends Control
## 战场缩小图 (window class "SmallMap", proc 0x4603c1; content 0x44a88a / 0x44a436 / 0x44a6db): the battle map's
## Xixi.wa picture at 6 px a cell, a 5×5 dot per unit on the map (我军 / 友军 / 敌军 colours; a finished 我军 unit
## gets a dark 3×3 middle) and the frame of the visible part of the map. While the player phase waits, the frame
## can be dragged (by whole cells) and the map follows when it is let go. Its title bar moves the window; ×
## hides it. Opened from the menu, at battle start with 战斗时，自动显示战场缩小图, and during battle choices.

const CELL := 6
const TITLE_H := 20.0
const DOT := [Color8(192, 0, 0), Color8(192, 80, 0), Color8(0, 16, 112), Color8(0, 16, 112)]
const DONE := Color8(96, 0, 0)
const FRAME := Color8(240, 240, 240)

var st: BattleStage
var _tex: Texture2D
var _drag := false                 # dragging the view frame
var _frame := Vector2i.ZERO        # the frame's top-left cell while dragging
var _grab := Vector2.ZERO
var _move := false                 # dragging the window by its title
var _move_from := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func setup(stage: BattleStage) -> void:
	st = stage
	_tex = Assets.tex("gfx/maps/minimap/HM%02d.png" % st.view.map_id)
	size = _img_size() + Vector2(4, TITLE_H + 4)
	position = Vector2(st.view.view_size().x - size.x - 6, 32)     # under the turn / weather line


func _img_size() -> Vector2:
	return Vector2(st.view.map_w * CELL, st.view.map_h * CELL)


## 0x449d96: show it (or keep it on top).
func open() -> void:
	if st == null or st.view.map_id < 0:
		return
	if _tex == null:
		setup(st)
	visible = true
	get_parent().move_child(self, -1)


func _process(_d: float) -> void:
	if visible:
		queue_redraw()


func _img_origin() -> Vector2:
	return Vector2(2, TITLE_H + 2)


## The view's top-left cell and its size in cells (0x44a6db: 78×48 px for the 13×8-cell view).
func _view_cells() -> Rect2:
	var vs := st.view.view_size()
	return Rect2(st.view.camera.position / BattleView.CELL, vs / BattleView.CELL)


func _draw() -> void:
	if st == null:
		return
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, UIStyle.BG)
	draw_rect(r, UIStyle.BORDER_IN, false, 1.0)
	UIStyle.draw_text(self, Vector2(6, 15), "战场缩小图", UIStyle.NAME_COLOR, 12)
	UIStyle.draw_text(self, Vector2(size.x - 16, 15), "×", UIStyle.TEXT_COLOR, 13)
	var o := _img_origin()
	if _tex:
		draw_texture_rect(_tex, Rect2(o, _img_size()), false)
	for u in st.units:
		if u.state != BUnit.STATE_ON_MAP:
			continue
		var p := o + Vector2(u.pos) * CELL
		draw_rect(Rect2(p, Vector2(5, 5)), DOT[clampi(u.colour, 0, 3)])
		if u.colour == 0 and u.moved and u.acted:
			draw_rect(Rect2(p + Vector2(1, 1), Vector2(3, 3)), DONE)
	var vc := _view_cells()
	var tl: Vector2 = Vector2(_frame) if _drag else vc.position
	draw_rect(Rect2(o + tl * CELL, vc.size * CELL - Vector2.ONE), FRAME, false, 1.0)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			if ev.position.y < TITLE_H:
				if ev.position.x > size.x - 20:
					visible = false
				else:
					_move = true
					_move_from = ev.position
			elif st.input.idle:
				# 0x460cb1: a press inside the frame starts a drag; elsewhere nothing
				var vc := _view_cells()
				var fr := Rect2(_img_origin() + vc.position * CELL, vc.size * CELL)
				if fr.has_point(ev.position):
					_drag = true
					_frame = Vector2i(vc.position)
					_grab = ev.position
		else:
			if _drag:
				# 0x461157: the map's top-left cell becomes the frame's
				_drag = false
				st.view.camera.position = st.view.clamp_cam(Vector2(_frame) * BattleView.CELL)
			_move = false
		accept_event()
	elif ev is InputEventMouseMotion:
		if _move:
			position = (position + ev.position - _move_from).clamp(Vector2.ZERO, get_viewport_rect().size - size)
		elif _drag:
			var img := Rect2(_img_origin(), _img_size())
			if not img.has_point(ev.position):
				_drag = false          # off the picture: the frame snaps back
				return
			var vc := _view_cells()
			var d := Vector2i(((ev.position - _grab) / CELL).floor())
			var maxc := Vector2i(st.view.map_w, st.view.map_h) - Vector2i(vc.size)
			_frame = (Vector2i(vc.position) + d).clamp(Vector2i.ZERO, maxc.max(Vector2i.ZERO))
		accept_event()
