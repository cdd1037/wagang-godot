class_name BattleHUD
extends Control
## Battle overlay: hovered-unit info, terrain, turn/weather, phase & goal banners, HP popups.

var stage: BattleStage
var hover_unit: BUnit
var hover_cell := Vector2i(-1, -1)
var _banner_text := ""
var _banner_a := 0.0
var _picture: Texture2D
var popups: Array = []     # [{text, pos(world), t, color}]
var _tpop := {}            # the terrain box of an empty cell: {"rect" (screen), "cell", "t"}
var icon_over := {}        # an item icon over a cell: {"tex", "cell", "off" (px from the cell's corner)}
var _reward := {}          # the reward screen: {"wipe" 0..1, "lines": [[text, y, size, colour]], "bars": [[tex, name, y]]}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	var alive := []
	for p in popups:
		p["t"] += delta
		if p["t"] < 1.0:
			alive.append(p)
	popups = alive
	queue_redraw()


func set_hover(c: Vector2i) -> void:
	hover_cell = c
	hover_unit = stage.unit_at(c) if stage else null
	queue_redraw()


func popup_number(text: String, cell: Vector2i, color := Color(1, 1, 1)) -> void:
	popups.append({"text": text, "cell": cell, "t": 0.0, "color": color})


func phase_banner(text: String) -> void:
	_banner_text = text
	if Game.autoplay:
		return
	var tw := create_tween()
	tw.tween_property(self, "_banner_a", 1.0, 0.25)
	tw.tween_interval(0.7)
	tw.tween_property(self, "_banner_a", 0.0, 0.25)
	await tw.finished


func goal_banner(text: String) -> void:
	await phase_banner(text)


func show_picture(t: Texture2D) -> void:
	_picture = t
	queue_redraw()


func _draw() -> void:
	if stage == null:
		return
	var vs := get_viewport_rect().size
	if _picture:
		draw_texture(_picture, Vector2(0, 40))
	# floating numbers
	for p in popups:
		var c: Vector2i = p["cell"]
		var wp := stage.view.cell_pos(c) - stage.view.camera.position + Vector2(24, 10 - 22 * float(p["t"]))
		var col: Color = p["color"]
		col.a = 1.0 - maxf(float(p["t"]) - 0.6, 0) / 0.4
		UIStyle.draw_text(self, wp - Vector2(Assets.font().get_string_size(p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x / 2, 0), p["text"], col, 18)
	# turn / weather (top right) and the hover panel — only once the battle proper has started
	if stage.field_ready and stage.turn > 0:
		var t := "第 %d 回合" % stage.turn
		if stage.turn_limit > 0:
			t += " / %d" % stage.turn_limit
		t += "　" + BattleStage.WEATHER_NAMES[stage.weather()]
		var tw := Assets.font().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var tr := Rect2(vs.x - tw - 20, 4, tw + 16, 22)
		draw_rect(tr, Color(0, 0, 0, 0.55))
		UIStyle.draw_text(self, tr.position + Vector2(8, 16), t, Color(1, 1, 1), 14)
		if hover_cell.x >= 0 and stage.view.in_bounds(hover_cell):
			_draw_info(vs)
			_draw_cursor_text()
	if not _tpop.is_empty():
		_draw_terrain_box()
	if not icon_over.is_empty():
		var p := stage.view.cell_pos(icon_over["cell"]) - stage.view.camera.position + Vector2(icon_over["off"])
		draw_texture_rect(icon_over["tex"], Rect2(p, Vector2(32, 32)), false, Color(1, 1, 1, float(icon_over.get("alpha", 1.0))))
	if not _reward.is_empty():
		_draw_reward(vs)
	if not _epanel.is_empty():
		_draw_equip_panel(vs)
	# phase banner
	if _banner_a > 0.01 and stage.field_ready and stage.turn > 0:
		var f := Assets.font()
		var sz := f.get_string_size(_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28)
		var r := Rect2((vs.x - sz.x) / 2 - 30, vs.y * 0.42 - 30, sz.x + 60, 46)
		draw_rect(r, Color(0, 0, 0, 0.6 * _banner_a))
		UIStyle.draw_text(self, Vector2((vs.x - sz.x) / 2, vs.y * 0.42 + 2), _banner_text, Color(1, 0.9, 0.6, _banner_a), 28)


## The reward screen of op 0x59 (0x44b5a8 / 0x44b046): the map wiped from both sides to the middle, BGM track 9,
## "作战结束" and "酬金   N", then "战利品" with a bar per item (icon and name); with the final flag "全程作战结束" and
## "恭贺您实现统一大业" instead. Each line comes after 20 ticks (10 for the second final line); the last waits
## 3 s more, which a click ends.
func reward_screen(gold: int, items: Array, final: bool) -> void:
	if Game.autoplay:
		return
	var vs := get_viewport_rect().size
	var cy := vs.y / 2
	_reward = {"wipe": 0.0, "lines": [], "bars": []}
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_reward["wipe"] = v
		queue_redraw(), 0.0, 1.0, 0.4)
	await tw.finished
	Audio.play_bgm(9)
	if final:
		_reward["lines"].append(["全程作战结束", cy - 60, 48, Color(1, 1, 1)])
		await stage.wait(0.5)
		_reward["lines"].append(["恭贺您实现统一大业", cy + 40, 36, UIStyle.NAME_COLOR])
		await stage.wait(1.0)
		await stage.ui.wait_or_click(3.0)
	else:
		_reward["lines"].append(["作战结束", cy - 60, 48, Color(1, 1, 1)])
		await stage.wait(1.0)
		_reward["lines"].append(["酬金   %5d" % gold, cy + 40, 36, UIStyle.NAME_COLOR])
		await stage.wait(1.0)
		await stage.ui.wait_or_click(3.0)
		var any := false
		for it in items:
			if int(it) != 0xff and int(it) != 0xffff:
				any = true
		if any:
			_reward["lines"] = [["战利品", 60.0, 36, Color(1, 1, 1)]]
			var n := 0
			for it in items:
				if int(it) == 0xff or int(it) == 0xffff:
					continue
				await stage.wait(1.0)
				var y := 140.0 + 96 * n + (96 if items.size() < 3 else 0)
				var d := Game.item(int(it))
				_reward["bars"].append([Assets.tex("gfx/icons/items/large/%03d.png" % int(d.get("icon", 0))), str(d.get("name", "?")), y])
				n += 1
			await stage.wait(1.0)
			await stage.ui.wait_or_click(3.0)
	_reward = {}
	queue_redraw()


func _draw_reward(vs: Vector2) -> void:
	var w := vs.x / 2 * float(_reward["wipe"])
	draw_rect(Rect2(0, 0, w, vs.y), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(vs.x - w, 0, w, vs.y), Color(0, 0, 0, 0.85))
	var f := Assets.font()
	for l in _reward["lines"]:
		var sz: int = l[2]
		var tw := f.get_string_size(str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var p := Vector2((vs.x - tw) / 2, float(l[1]))
		draw_string(f, p + Vector2(2, 2), str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color8(153, 153, 153))
		draw_string(f, p + Vector2(1, 1), str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color8(204, 204, 204))
		draw_string(f, p, str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, sz, l[3])
	for b in _reward["bars"]:
		var r := Rect2(vs.x / 2 - 120, float(b[2]), 240, 48)
		UIStyle.draw_panel(self, r)
		if b[0]:
			draw_texture_rect(b[0], Rect2(r.position + Vector2(16, 8), Vector2(32, 32)), false)
		UIStyle.draw_text(self, r.position + Vector2(80, 30), str(b[1]), Color(1, 1, 1), 16)


## The equipment level panel of 0x4083ef: 240×96 in the middle of the view with the item's icon, "<item> Lv N",
## "<name> 装备中" and "攻击|精神|防御 +before -> +after"; 10 ticks, then 4 s that a click ends.
func equip_panel(iid: int, lvl: int, p: Person, weapon: bool) -> void:
	if Game.autoplay:
		return
	var it := Game.item(iid)
	var label := "防御"
	if weapon:
		label = "精神" if Person.stat_of_type(int(it.get("type", 0))) == 2 else "攻击"
	_epanel = {"icon": Assets.tex("gfx/icons/items/large/%03d.png" % int(it.get("icon", 0))), "name": str(it.get("name", "?")),
		"lvl": lvl, "who": InfoWindow.display_name(p), "label": label,
		"old": Person.item_value_at(it, lvl - 1), "new": Person.item_value_at(it, lvl)}
	queue_redraw()
	await stage.wait(0.5)
	await stage.ui.wait_or_click(4.0)
	_epanel = {}
	queue_redraw()


var _epanel := {}


func _draw_equip_panel(vs: Vector2) -> void:
	var r := Rect2((vs / 2 - Vector2(120, 48)).floor(), Vector2(240, 96))
	UIStyle.draw_panel(self, r)
	if _epanel["icon"]:
		draw_texture_rect(_epanel["icon"], Rect2(r.position + Vector2(16, 16), Vector2(32, 32)), false)
	var f := Assets.font()
	var x := r.position.x + 72
	UIStyle.draw_text(self, Vector2(x, r.position.y + 26), "%s  Lv %d" % [_epanel["name"], _epanel["lvl"]], Color(1, 1, 1), 14)
	UIStyle.draw_text(self, Vector2(x, r.position.y + 50), str(_epanel["who"]), Color(0.55, 0.75, 1.0), 14)
	var ww := f.get_string_size(str(_epanel["who"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	UIStyle.draw_text(self, Vector2(x + ww + 8, r.position.y + 50), "装备中", Color(1, 1, 1), 14)
	UIStyle.draw_text(self, Vector2(r.position.x + 48, r.position.y + 82), str(_epanel["label"]), Color(1, 1, 1), 14)
	UIStyle.draw_text(self, Vector2(r.position.x + 112, r.position.y + 82), "+%d ->" % int(_epanel["old"]), Color(1, 1, 1), 14)
	UIStyle.draw_text(self, Vector2(r.position.x + 168, r.position.y + 82), "+%d" % int(_epanel["new"]), Color(1.0, 0.45, 0.4), 14)


## The cursor cell readout in the status pane (mod 0x4d1c10): "(%2d:%2d) terrain", 0-based cells.
func _draw_cursor_text() -> void:
	var t := "(%2d:%2d) %s" % [hover_cell.x, hover_cell.y, Game.terrain_name(stage.view.terrain_at(hover_cell))]
	var w := Assets.font().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var r := Rect2(4, 4, w + 16, 22)
	draw_rect(r, Color(0, 0, 0, 0.55))
	UIStyle.draw_text(self, r.position + Vector2(8, 16), t, Color(1, 1, 1), 14)


## A left click on an empty cell in the player phase (0x45576d, mod 0x4559ba → 0x4e0000): a 3×2-cell box beside
## the cell (left of it from the middle of the view on, above it likewise — the view's width decides both) with
## the cell's picture, the terrain name (types over 29 count as 平原), 可以恢复 (18..22) or 无法移动, and the
## four element icons, grey where that element cannot be cast. Any click closes it.
const RECOVER := [18, 19, 20, 21, 22]
const NO_MOVE := [5, 6, 11, 12, 14, 15, 17, 25, 26, 27, 28, 29]
## [element (Rules.element_ok), Kao.wa icon] left to right: fire, water, earth, wind.
const BOX_ICONS := [[0, "1a5c0"], [1, "1a6c0"], [3, "1a7c0"], [2, "1a8c0"]]


func terrain_popup(c: Vector2i) -> void:
	var v := stage.view
	var vs := v.view_size()
	var cam := v.camera.position
	var tl := Vector2i((cam / BattleView.CELL).floor())
	var cx := c.x - tl.x
	var cy := c.y - tl.y
	var half := int(vs.x / BattleView.CELL) / 2
	var bx := cx - 3 if cx >= half else cx + 1
	var by := cy - 1 if cy >= half else cy
	var t := v.terrain_at(c)
	if t > 29:
		t = 0
	_tpop = {"rect": Rect2(v.cell_pos(tl + Vector2i(bx, by)) - cam, Vector2(144, 96)), "cell": c, "t": t}
	queue_redraw()
	if not Game.autoplay:
		await v.cell_clicked
	_tpop = {}
	queue_redraw()


func _draw_terrain_box() -> void:
	var r: Rect2 = _tpop["rect"]
	var t: int = _tpop["t"]
	var c: Vector2i = _tpop["cell"]
	draw_rect(r, Color(0, 0, 0, 0.45))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color8(153, 153, 153))
	draw_rect(Rect2(r.position, Vector2(1, r.size.y)), Color8(153, 153, 153))
	for k in 3:
		var col: Color = [Color8(68, 68, 68), Color8(34, 34, 34), Color8(0, 0, 0)][k]
		draw_rect(Rect2(r.position.x, r.end.y - 3 + k, r.size.x, 1), col)
		draw_rect(Rect2(r.end.x - 3 + k, r.position.y, 1, r.size.y), col)
	var tex := stage.view.map_sprite.texture
	if tex:
		draw_texture_rect_region(tex, Rect2(r.position + Vector2(8, 8), Vector2(48, 48)), Rect2(Vector2(c) * BattleView.CELL, Vector2(48, 48)))
	UIStyle.draw_text(self, r.position + Vector2(64, 26), Game.terrain_name(t), Color(1, 1, 1), 14)
	if t in RECOVER:
		UIStyle.draw_text(self, r.position + Vector2(64, 54), "可以恢复", Color8(0, 221, 255), 14)
	elif t in NO_MOVE:
		UIStyle.draw_text(self, r.position + Vector2(64, 54), "无法移动", Color8(204, 204, 204), 14)
	for i in 4:
		var ic := Assets.tex("gfx/effects/kao/%s_16x16.png" % BOX_ICONS[i][1])
		if ic:
			var ok := Rules.element_ok(int(BOX_ICONS[i][0]), t)
			draw_texture_rect(ic, Rect2(r.position + Vector2(16 + 32 * i, 68), Vector2(16, 16)), false,
				Color(1, 1, 1) if ok else Color(0.5, 0.5, 0.5, 0.8))


func _draw_info(vs: Vector2) -> void:
	var u := hover_unit
	var terr := stage.view.terrain_at(hover_cell)
	var tname := Game.terrain_name(terr)
	var cam := stage.view.camera.position
	var cell_screen := stage.view.cell_pos(hover_cell) - cam
	var on_left := cell_screen.x > vs.x / 2
	var w := 268.0 if u else 120.0
	var h := 96.0 if u else 30.0
	var x := 6.0 if on_left else vs.x - w - 6
	var y := vs.y - h - 6
	var r := Rect2(x, y, w, h)
	UIStyle.draw_panel(self, r)
	if u == null:
		UIStyle.draw_text(self, r.position + Vector2(10, 20), tname, Color(1, 1, 1), 14)
		return
	var p := u.person
	var face := p.face_tex(true)
	if face == null:
		face = p.face_tex()
	if face:
		draw_texture_rect(face, Rect2(r.position + Vector2(6, 8), Vector2(80, 80)), false)
	var tx := r.position.x + 92
	var col := Color(1, 0.55, 0.5) if u.side == BUnit.Side.ENEMY else (Color(0.6, 1, 0.6) if u.side == BUnit.Side.FRIEND else UIStyle.NAME_COLOR)
	UIStyle.draw_text(self, Vector2(tx, r.position.y + 20), p.name, col, 15)
	UIStyle.draw_text(self, Vector2(tx, r.position.y + 38), "%s Lv%d" % [p.class_name_str(), p.level], Color(1, 1, 1), 13)
	_bar(Vector2(tx, r.position.y + 46), 110, u.hp, u.max_hp(), Color(0.9, 0.25, 0.2), "兵")
	_bar(Vector2(tx, r.position.y + 64), 110, u.mp, u.max_mp(), Color(0.3, 0.5, 1.0), "策")
	var eff := Rules.terrain_effect(u, terr) * 10
	UIStyle.draw_text(self, Vector2(tx, r.position.y + 92), "%s %d%%" % [tname, eff], Color(0.85, 0.85, 0.7), 12)
	var st := ""
	if u.status & BUnit.ST_POISON: st += "毒"
	if u.status & BUnit.ST_CONFUSION: st += "乱"
	if u.status & BUnit.ST_PARALYSIS: st += "麻"
	if u.status & BUnit.ST_SEAL: st += "封"
	if u.status & BUnit.ST_FEAR: st += "怯"
	if st != "":
		UIStyle.draw_text(self, Vector2(r.end.x - 40, r.position.y + 20), st, Color(1, 0.4, 1), 13)


func _bar(pos: Vector2, w: float, v: int, m: int, c: Color, label: String) -> void:
	UIStyle.draw_text(self, pos + Vector2(0, 13), label, Color(0.9, 0.9, 0.9), 12)
	var r := Rect2(pos + Vector2(16, 3), Vector2(w - 16, 10))
	draw_rect(r, Color(0.1, 0.1, 0.1))
	if m > 0:
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(float(v) / m, 0, 1), r.size.y)), c)
	draw_rect(r, Color(0.8, 0.7, 0.4), false, 1)
	UIStyle.draw_text(self, pos + Vector2(w + 4, 13), "%d/%d" % [v, m], Color(1, 1, 1), 11)
